---
allowed-tools: Bash(find:*), Bash(ls:*), Bash(head:*), Bash(cat:*), Bash(mkdir:*), Bash(date:*), Bash(command:*), Bash(printf:*), Bash(perl:*), mcp__plugin_playwright_playwright__browser_navigate, Read, Write, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput, Skill, AskUserQuestion
description: Execute a QA test plan — launch FE and BE testing agents in parallel, collect results, and generate a report with QA-XXX issue IDs.
model: opus
argument-hint: [path to test plan file]
---

# QA Test Runner

You execute QA test plans by launching specialized testing agents and generating a report.

## Arguments

**Input:** `$ARGUMENTS`

| Argument | Interpretation |
|----------|---------------|
| (empty) | Find the most recent test plan in `docs/testing/plans/` |
| `<path>` | Use the specified test plan file |

**Finding the most recent plan:**
```bash
ls -t docs/testing/plans/*.md 2>/dev/null | head -1
```

If no plans found, inform the user:
> No test plans found in `docs/testing/plans/`. Run `/qa:create-plan` first.

---

## Workflow

### Step 1: Load and Parse Test Plan

Read the test plan file using the Read tool.

Extract:
- **Source info** (PR, branch, etc.)
- **Detected tools** (what was available when plan was created)
- **FE scenarios** (all FE-XX blocks)
- **BE scenarios** (all BE-XX blocks)
- **Has FE tests:** true if `## FE Test Scenarios` section exists and contains scenarios
- **Has BE tests:** true if `## BE Test Scenarios` section exists and contains scenarios
- **Setup** (if present): take only the first backticked token of `**Base URL:**` and each `- ` bullet under `**Required environment variables:**` / `**Required databases:**`. Env names must match `^[A-Z_][A-Z0-9_]*$`; database bullets may instead start with `mcp__`. Warn and ignore any other bullet. Preserve the entire `## Setup` section verbatim for dispatch; keep database names for the BE `DB connection:` field. Text following the first backticked token is descriptive, not a value.
- **Per scenario:** record any `**Blocked-by:** BLK-NN` (and the blocker's `(file:line)` under `## Blockers / Findings`), and whether the main `**Expected:**` or each edge-case expectation carries `(unverified — confirm at run time)`. These tags apply to individual assertions, not whole scenarios.

### Step 2: Create Progress Tasks

Create tasks based on what needs to run:

| # | subject | activeForm | Condition |
|---|---------|-----------|-----------|
| 1 | Validate environment | Validating environment... | Always |
| 2 | Execute FE tests | Running FE tests... | If has FE tests |
| 3 | Execute BE tests | Running BE tests... | If has BE tests |
| 4 | Collect test results | Collecting test results... | Always |
| 5 | Generate test report | Generating test report... | Always |
| 6 | Save test report | Saving test report... | Always |

### Step 3: Validate Environment

**Task Update:** Mark task 1 as `in_progress`.

Re-check tool availability (tools may have changed since the plan was created):

**If plan has FE tests — check Playwright:**
```
Try: browser_navigate(url: "about:blank")
```

**If plan has BE tests — check HTTP client, sanitiser and DB client:**
```bash
command -v curl >/dev/null 2>&1 && printf 'curl: available\n' || printf 'curl: unavailable\n'
perl -MJSON::PP -e 1 >/dev/null 2>&1 && printf 'perl: available\n' || printf 'perl: unavailable\n'
command -v psql >/dev/null 2>&1 && printf 'psql: available\n' || printf 'psql: unavailable\n'
command -v sqlite3 >/dev/null 2>&1 && printf 'sqlite3: available\n' || printf 'sqlite3: unavailable\n'
```

If a required tool is now unavailable, testers return `NEED_INFO kind=tool` for affected scenarios, listed under `## Setup gaps`. A missing DB client only skips its `**DB check:**` field; the HTTP test still runs.

### Step 3.5: Preflight declared prerequisites

Before any tester dispatch, collect the validated environment-variable names under `## Setup → Required environment variables` and `Required databases` (skip `mcp__` bullets). For **each** name, use one Bash presence-only line with the validated name substituted literally, e.g.:

```bash
[ -n "${QA_API_TOKEN:-}" ] && printf 'QA_API_TOKEN: OK\n' || printf 'QA_API_TOKEN: MISSING\n'
```

Never print values. If any line says `MISSING`, abort before dispatch and print exactly (with the actual count and names, one per line):

```text
⚠️ Cannot start QA — <N> required value(s) missing:
  • <NAME_1>
  • <NAME_2>
Set them in the shell that launches the harness (`export NAME=…`), restart it, then re-run the command. Environment variables are captured at process start; exporting them in a running session has no effect.
```

If there is no `## Setup` or no env-name bullets, proceed with no preflight. Do not probe services or databases for liveness; that is tested at run time.

Resolve `base_url` once for both dispatches: (1) `**Base URL:**` from `## Setup`; (2) first `http://` or `https://` URL in `## Source` or a scenario heading/bullet; (3) non-empty `QA_BASE_URL`. Never read project config at run time. If none resolves, abort before dispatch with:

> Error: Base URL undetectable. Cannot guarantee loopback-only safety. Explicitly set QA_BASE_URL, add a Base URL to the plan's ## Setup section.

**Task Update:** Mark task 1 as `completed`.

### Step 4: Launch Testing Agents

Launch agents based on what the plan contains. If both FE and BE tests exist, launch BOTH in parallel.

**If has FE tests:**

**Task Update:** Mark FE task as `in_progress`.

```
Task(
  subagent_type: "qa:fe-tester",
  run_in_background: true,
  description: "Execute FE test scenarios",
  prompt: "Plan: <plan_path>
Setup:
<paste the plan's ## Setup section verbatim, or use 'Setup: none declared' instead of these two lines>
Base URL: <base_url resolved in Step 3.5>

FE Test Scenarios:
<paste all FE-XX scenario blocks from the plan>

Report NEED_INFO (kind + missing names) for missing prerequisites. Never print secret values."
)
```

**If has BE tests:**

**Task Update:** Mark BE task as `in_progress`.

```
Task(
  subagent_type: "qa:be-tester",
  run_in_background: true,
  description: "Execute BE test scenarios",
  prompt: "Plan: <plan_path>
Setup:
<paste the plan's ## Setup section verbatim, or use 'Setup: none declared' instead of these two lines>
Base URL: <base_url resolved in Step 3.5>
DB connection: <Required databases bullets (env-var or mcp__ names) from Setup, or 'none declared'>

BE Test Scenarios:
<paste all BE-XX scenario blocks from the plan>

Report NEED_INFO (kind + missing names) for missing prerequisites. Never print secret values."
)
```

### Step 5: Collect Results

**Task Update:** Mark collect task as `in_progress`.

Wait for all launched agents to complete:

```
fe_results = TaskOutput(fe_tester_id, block: true)  # only if FE agent was launched
be_results = TaskOutput(be_tester_id, block: true)  # only if BE agent was launched
```

**Task Update:** Mark FE and/or BE tasks as `completed`. Mark collect task as `completed`. Mark report task as `in_progress`.

### Step 6: Generate Report

Load the report-format skill:

```
Skill(skill: "report-format")
```

Using the skill's format:

1. **Count results:** derive one verdict per scenario using main Status plus every edge line: `fail` if main or any edge is `FAIL`; else `need-info` if main or any edge is `NEED_INFO`; else `skip` if main or any edge is `SKIP`; else `pass`. Do not count `**DB check:** SKIP` as a skipped edge. Tally pass/fail/skip/need-info; a main-flow PASS with an edge gap is not a pass.
2. **Assign QA-XXX IDs** to each failed main flow and each failed edge case, separately (NEED_INFO mints no issue), in plan order.
3. **Determine severity** from report-format's Severity Levels, including its per-assertion `(unverified — confirm at run time)` LOW rule and the ≥500/crash exception.
4. **Derive issue fields** from raw agent output and the plan (see report-format Issue Format Details):
   - **Location** — a `**Blocked-by:** BLK-NN` scenario uses the blocker's `(file:line)` from `## Blockers / Findings`. Otherwise use a source line or stack trace when grounded; infer from the route/component when possible. If truly unidentifiable, use `unknown:0` and explain (the `/fix` command will prompt).
   - **Category** — always `Testing`.
   - **Problem** — Expected copies the **failing assertion's** text with its tag verbatim (main `**Expected:**` or the specific edge); Actual reports the observed outcome, starting `Blocked by BLK-NN: <defect>` when applicable; Refutation copies the main `**Refutation:**` or the failing edge line's refutation trace. Include a sanitised request/response summary for BE; never print headers, tokens, DSNs or raw response bodies.
   - **Remediation** — one to three sentences, best-effort, no code block.
   - **Impact** (optional) — user-visible consequence.
   - **Scenario / Response / Screenshot** — copy sanitised evidence and scenario-ID artifact paths from the agent.
5. **Build the report** following the report-format exact template.
6. **Build detailed results** for all scenarios by their derived verdict, with edge gaps/skips identified even if the main flow passed.
7. **Build `## Setup gaps`** from every scenario-level `NEED_INFO` block's `Kind`/`Missing` and every edge-case `NEED_INFO — <kind>: <identifiers>` line, independently of the scenario verdict. One bullet per kind with names/URLs and scenario IDs (`BE-01 (edge 2)` for an edge); no secret values. Omit the section only when there are no gaps.

### Step 7: Save Report

**Task Update:** Mark report task as `completed`. Mark save task as `in_progress`.

```bash
mkdir -p docs/testing/reports
```

Generate filename matching the test plan topic:
- If plan is `2026-04-07-user-auth-test-plan.md` → report is `2026-04-07-user-auth-report.md`
- Extract topic by removing date prefix and `-test-plan` suffix from plan filename

Save the report using the Write tool to:
`docs/testing/reports/YYYY-MM-DD-<topic>-report.md`

**Task Update:** Mark save task as `completed`.

### Step 8: Display Summary

After saving, display a summary:

> **Test Report: <title>**
>
> - Total: N | Pass: N | Fail: N | Skip: N | Need info: N
> - Issues found: N
>
> <list top 3 issues with QA-XXX IDs and severity>
>
> Full report saved to `docs/testing/reports/<filename>`
>
> Plan used: `docs/testing/plans/<plan-filename>`
When `## Setup gaps` is non-empty, display one line per kind and then the restart advice:

> **Setup gaps:** <kind>: <identifiers> (<scenario IDs>)
>
> Set/start them, restart the harness, then re-run /qa:run.

If issues were found:

> **Found {N} issues.** To fix them:
>
> `/fix-report` — auto-merge with the newest code-review report (if any) and fix interactively.
>
> `/fix-report docs/testing/reports/<filename>` — fix issues from this QA report only.
>
> `/fix QA-001` — fix a single issue by ID. Routes by prefix to `docs/testing/reports/`.

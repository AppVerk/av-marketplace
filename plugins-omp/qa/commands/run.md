---
description: "Execute a QA test plan — launch FE and BE testing agents in parallel, collect results, and generate a report with QA-XXX issue IDs."
argument-hint: "[path to test plan file]"
---
> **OMP edition — generated file, do not edit.** Source of truth: `plugins/qa/commands/run.md`; regenerate with `python3 scripts/build_omp_edition.py`.
>
> The instructions below were written for Claude Code. In this harness, read their tool references as follows:
>
> - **Task tool** with `subagent_type: "<plugin>:<agent>"` → call `task` with `agent: "<plugin>:<agent>"` (the id is unchanged) and the prompt as the item's `task`. `run_in_background` has no equivalent: `task` runs asynchronously and results are delivered when agents finish. "Dispatch in parallel" means one `task` call with several items.
> - **TaskCreate / TaskUpdate / TaskList** → the `todo` tool: `init` with the listed subjects, `start` / `done` by subject text, `view` to list. `activeForm` has no equivalent. A subagent has no `todo` tool: when running as one, skip these progress-tracking steps and do the work they announce.
> - **AskUserQuestion** → the `ask` tool. `multiSelect: true` → `multi: true`.
> - **Skill tool**, `Skill(skill: "<name>")`, or a skill cited as `<plugin>:<name>` → `read skill://<plugin>:<name>`. Every skill is addressed with its plugin prefix; a skill named without one belongs to this plugin, so read `skill://qa:<name>`.
> - In an agent's instructions, `ARGUMENTS` (prefixed with a dollar sign) stands for the task text you were given.
> - **WebSearch** → `web_search`. **WebFetch** → `read` on the URL.
> - A subagent has no `ask` tool: where the instructions say to ask the user, choose the most likely option and state the choice and its reason in your report.
> - **allowed-tools** and `Bash(<cmd>:*)` grants are Claude Code permission pre-approvals. They grant and restrict nothing here.
> - **`mcp__<server>` and `mcp__<server>__*` grants** are not carried over: a subagent here gets every MCP tool of the session whatever its `tools:` list says, and a server the session has not configured is simply absent. MCP tools are named `mcp__<server>_<tool>` here (one underscore between server and tool), not `mcp__<server>__<tool>`.
> - **Playwright MCP** (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, `browser_type`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_evaluate`, `browser_wait_for`, `browser_take_screenshot`, and any `mcp__playwright*` or `mcp__plugin_playwright_playwright*` tool) → the `browser` global inside `eval`, OMP's own Chromium (downloaded on first use; while it is enabled, OMP removes Playwright MCP servers from the session). Read `xd://eval/browser` before the first browser step. Open one tab per run, `tab = await browser.open(name="qa", url=<url>)`, then navigate with `await tab.goto(url)`; a probe such as "try `browser_navigate`" is that `browser.open` call, and an exception from it means the browser is unavailable. `browser_snapshot()` → `await tab.observe()` (numeric ids for `tab.id(n)`) or `await tab.ariaSnapshot()` (`e5`-style refs for `tab.ref("e5")`); act on those handles or on selectors (`text/Sign In`, `aria/Email`, CSS) with `click`, `fill`, `type`, `select`, `press`, `hover`. `browser_evaluate(expression)` → `await tab.evaluate(expression)`. `browser_wait_for` → `await tab.waitForSelector("text/Success", timeout=5000)` or `await tab.waitForSelector(selector, hidden=True, timeout=10000)`. `browser_take_screenshot()` → `path = await tab.screenshot()` returns a file in the OS temp directory: copy it with `bash` to the path the instructions name.
> - **Slash commands** are `/<plugin>:<name>` here: `/fix`, `/fix-report`, `/fix-all` and `/review` are `/code-review:fix`, `/code-review:fix-report`, `/code-review:fix-all` and `/code-review:review`; a command cited with its plugin prefix, such as `/qa:run`, keeps its name.
> - In the text below, a backticked command right after `!` (for example !`git status`) is Claude Code inline context: Claude Code runs it and puts its output there before the model reads the text. Here nothing ran: run each such command in the text below with `bash` first and use its output in its place.

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

**If plan has BE tests — check HTTP client and DB client:**
```bash
command -v curl >/dev/null 2>&1 && echo "curl: available" || echo "curl: unavailable"
command -v psql >/dev/null 2>&1 && echo "psql: available" || echo "psql: unavailable"
command -v sqlite3 >/dev/null 2>&1 && echo "sqlite3: available" || echo "sqlite3: unavailable"
```

If a required tool is now unavailable, affected scenarios will be marked as SKIP in the report.

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
  prompt: "Execute the following FE test scenarios using Playwright MCP.

Base URL: <detect from test plan or project config>

FE Test Scenarios:
<paste all FE-XX scenarios from the plan>

Follow the fe-testing skill for Playwright patterns. Return results for every scenario."
)
```

**If has BE tests:**

**Task Update:** Mark BE task as `in_progress`.

```
Task(
  subagent_type: "qa:be-tester",
  run_in_background: true,
  description: "Execute BE test scenarios",
  prompt: "Execute the following BE test scenarios by testing API endpoints and verifying database state.

Base URL: <detect from test plan or project config>
DB connection: <detect from project config if available>

Available tools: <list from environment validation>

BE Test Scenarios:
<paste all BE-XX scenarios from the plan>

Follow the be-testing skill for API and DB testing patterns. Return results for every scenario."
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

1. **Count results:** tally pass/fail/skip across all scenarios
2. **Assign QA-XXX IDs:** to each failed scenario/edge case (see report-format skill for algorithm)
3. **Determine severity** for each failure:
   - 500 errors, crashes, data loss → CRITICAL
   - Wrong status code, incorrect data → HIGH
   - UI glitch, missing validation message → MEDIUM
   - Cosmetic, minor text issues → LOW
4. **Derive issue fields** from raw agent output (the skill's Issue Format Details documents each field):
   - **Location** — best-effort source file:line. For BE failures: infer from request URL → routing module (e.g., `POST /api/users` → `src/api/users.py`); use stack trace lines from the response body when present. For FE failures: infer from the failing component or route. When truly unidentifiable, use `unknown:0` (the `/fix` command will prompt the user).
   - **Category** — always `Testing` (constant for QA).
   - **Problem** — render the failure as Expected/Actual bullets; include the request and response summary for BE.
   - **Remediation** — write a one- to three-sentence best-effort suggestion in natural language (no code block required).
   - **Impact** (optional) — describe what user-visible flow is broken.
   - **Scenario / Response / Screenshot** — copy from the agent's raw result.
5. **Build the report** following the exact template from the skill
6. **Build detailed results** listing all scenarios with status

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
> - Total: N | Pass: N | Fail: N | Skip: N
> - Issues found: N
>
> <list top 3 issues with QA-XXX IDs and severity>
>
> Full report saved to `docs/testing/reports/<filename>`
>
> Plan used: `docs/testing/plans/<plan-filename>`

If issues were found:

> **Found {N} issues.** To fix them:
>
> `/fix-report` — auto-merge with the newest code-review report (if any) and fix interactively.
>
> `/fix-report docs/testing/reports/<filename>` — fix issues from this QA report only.
>
> `/fix QA-001` — fix a single issue by ID. Routes by prefix to `docs/testing/reports/`.

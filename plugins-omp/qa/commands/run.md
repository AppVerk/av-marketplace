---
description: "Execute a QA test plan — launch FE and BE testing agents in parallel, collect results, and generate a report with QA-XXX issue IDs."
argument-hint: "[path to test plan file] [--allow-host HOST]"
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
> - **Playwright MCP** (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, `browser_type`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_evaluate`, `browser_wait_for`, `browser_take_screenshot`, and any `mcp__playwright*` or `mcp__plugin_playwright_playwright*` tool) → the `browser` global inside `eval`, which uses the browser OMP's settings select (managed Chromium only when no relay, CDP URL, or cmux browser is selected; while `browser.enabled` is on, OMP removes Playwright MCP servers from the session). For QA runs, set `browser.relay` and `browser.cmux` to `false` and unset `browser.cdpUrl` so FE scenarios do not act through your own or an attached browser. Read `xd://eval/browser` before the first browser step. Open one tab per run, `tab = await browser.open(name="qa", url=<url>, app={"relay": False})`, then navigate with `await tab.goto(url)`; a probe such as "try `browser_navigate`" is that `browser.open` call, and an exception from it means the browser is unavailable. `browser_snapshot()` → `await tab.observe()` (numeric ids for `tab.id(n)`) or `await tab.ariaSnapshot()` (`e5`-style refs for `tab.ref("e5")`); act on those handles or on selectors (`text/Sign In`, `aria/Email`, CSS) with `click`, `fill`, `type`, `select`, `press`, `hover`. `browser_evaluate(expression)` → `await tab.evaluate(expression)`. `browser_wait_for` → `await tab.waitForSelector("text/Success", timeout=5000)` or `await tab.waitForSelector(selector, hidden=True, timeout=10000)`. `browser_take_screenshot()` → `path = await tab.screenshot(format="png")` returns the saved file's path: copy it with `bash` to the path the instructions name.
> - **Slash commands** are `/<plugin>:<name>` here: `/fix`, `/fix-report`, `/fix-all`, `/review` and `/analyze-feedback` are `/code-review:fix`, `/code-review:fix-report`, `/code-review:fix-all`, `/code-review:review` and `/code-review:analyze-feedback`; a command cited with its plugin prefix, such as `/qa:run`, keeps its name.
> - In the text below, a backticked command right after `!` (for example !`git status`) is Claude Code inline context: Claude Code runs it and puts its output there before the model reads the text. Here nothing ran: run each such command in the text below with `bash` first and use its output in its place.

# QA Test Runner

You execute QA test plans by launching specialized testing agents and generating a report.

## Arguments

**Input:** `$ARGUMENTS`

| Argument | Interpretation |
|----------|---------------|
| (empty) | Find the most recent test plan in `docs/testing/plans/` |
| `<path>` | Use the specified test plan file |
| `--allow-host <host>` | Allow one non-loopback Base URL host (Step 3.6). Repeatable; each occurrence appends. Without it `/qa:run` is loopback-only |

Split `$ARGUMENTS` on whitespace before any I/O: `--allow-host` takes the next token as its value (no value → `Error: --allow-host requires a host` and stop); any other token starting with `--` → `Error: Unknown argument '<token>'` and stop; the first remaining token is the plan path.

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
- **Setup** (if present): take only the first backticked token of `**Base URL:**` and each `- ` bullet under `**Required environment variables:**` / `**Required databases:**`. A `**Required environment variables:**` name must match `^QA_[A-Z0-9_]+$`. A `**Required databases:**` bullet must be such a `QA_` name, one of `PGHOST`, `PGUSER`, `PGDATABASE`, `PGPASSWORD`, `SQLITE_DB`, `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_DATABASE`, `MYSQL_PWD`, or an `mcp__` server name. Warn about and ignore any other bullet (`Warning: ignoring Setup name '<token>' — not a QA_ name or a supported database name.`): the plan is repository content, and the namespace keeps it from naming an unrelated secret of the launching shell (`GH_TOKEN`, a cloud key) as a credential. For a PostgreSQL DB check require all four `PGHOST`, `PGUSER`, `PGDATABASE`, `PGPASSWORD` declarations; if incomplete, run HTTP but mark the DB check `SKIP — incomplete PostgreSQL connection under ## Setup`. Preserve the entire `## Setup` section verbatim for dispatch; keep the valid database names for the BE `DB connection:` field. Text following the first backticked token is descriptive, not a value.
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

### Step 3.6: Resolve and guard the Base URL

Resolve `base_url` once for both dispatches: (1) `**Base URL:**` from `## Setup`; (2) first `http://` or `https://` URL in `## Source` or a scenario heading/bullet; (3) non-empty `QA_BASE_URL`. Never read project config at run time. If none resolves, abort before dispatch with:

> Error: Base URL undetectable. Cannot guarantee loopback-only safety. Explicitly set QA_BASE_URL or add a Base URL to the plan's ## Setup section.

Then guard it before any dispatch. The plan is repository content (a branch under review can add or edit one) and the testers send declared credentials to this URL, so extract the host with **strict, fail-closed parsing**. When parsing is ambiguous (no `http://`/`https://` scheme, an empty host), abort with `Error: Base URL is not an http(s) URL with a host. Loopback-only safety enforced.`

1. **Reject userinfo:** if the authority (the text between `://` and the next `/`, `?` or `#`) contains `@`, abort with `Error: Base URL carries userinfo ('@'); refusing to guess its host.` Never print the URL itself: its userinfo may hold a password.
2. **Take the host component only,** lowercase it, then strip IPv6 brackets and any `:port` suffix (`[::1]:8000` → `::1`, `127.0.0.1:8000` → `127.0.0.1`).
3. **Match by exact equality, never substring.** The host is loopback iff it equals `localhost`, `127.0.0.1` or `::1`, or ends with `.localhost`. `127.0.0.1.evil.com` and `0.0.0.0` are NOT loopback.
4. Otherwise it is allowed only if it equals an `--allow-host` value. Only the command line extends this list; nothing in the plan does.

If the host is neither loopback nor allow-listed, abort before dispatch:

> Error: Base URL resolves to non-loopback host '<host>' and is not in --allow-host. Loopback-only safety enforced. Add --allow-host <host> to override.

The testers enforce the rest: they send requests and open pages only on this URL's host, so an absolute URL on another host inside a scenario is refused, not followed.

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
Base URL: <base_url resolved and guarded in Step 3.6>

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
Base URL: <base_url resolved and guarded in Step 3.6>
DB connection: <the valid Required databases names from Step 1 (env-var or mcp__ names), or 'none declared'>

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

Using the report-format skill, derive scenario verdicts (including edges), issue IDs, severity, fields and Detailed Results in plan order. Copy each failing assertion's grounding tag and tester refutation; use the blocker's cited Location when `**Blocked-by:**` is present. For BE evidence include only sanitised request/response summaries: never headers, tokens, DSNs or raw response bodies.

Build `## Setup gaps` from **all** main-flow and edge-case `NEED_INFO` entries, including gaps in otherwise failed scenarios, independently of the scenario count. Omit the section when empty. A `**DB check:** SKIP` does not change the scenario verdict.

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

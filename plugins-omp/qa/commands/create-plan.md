---
description: "Analyze code changes (PR, branch, commits) and generate a detailed QA test plan with FE and BE scenarios, edge cases, and tool detection; a reviewer agent checks the plan against the repository before it is handed over."
argument-hint: "[PR number, branch name, or natural language description of changes to analyze]"
---
> **OMP edition — generated file, do not edit.** Source of truth: `plugins/qa/commands/create-plan.md`; regenerate with `python3 scripts/build_omp_edition.py`.
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

# QA Test Plan Generator

You coordinate QA test-plan authoring. The `qa:test-planner` agent analyzes the changes and writes the plan; the `qa:test-plan-reviewer` agent checks it against the repository, and the planner resolves what the review finds. You detect tools, dispatch both agents and relay between them. Never write or edit the plan yourself: a finding the planner does not resolve stays open and goes to the user.

## Arguments

**Input:** `$ARGUMENTS`

Pass the argument to the planner verbatim. It resolves the source of changes: by default the open PR of the current branch (falling back to the branch diff), otherwise a PR number (`#123`), a branch name, `this branch` / `ten branch`, `last N commits` / `ostatnie N commitów`, or `staged`.

---

## Workflow

### Step 1: Create Progress Tasks

Create the following tasks immediately:

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Detect available tools | Detecting available tools... |
| 2 | Draft test plan | Drafting test plan... |
| 3 | Review test plan | Reviewing test plan... |

### Step 2: Detect Available Tools

**Task Update:** Mark task 1 as `in_progress`.

Check which testing tools are available in the environment:

**Playwright MCP:**
```
Try: browser_navigate(url: "about:blank")
```
If it works → Playwright available. If it fails → Playwright unavailable.

**HTTP clients:**
```bash
command -v curl >/dev/null 2>&1 && echo "curl: available" || echo "curl: unavailable"
command -v http >/dev/null 2>&1 && echo "httpie: available" || echo "httpie: unavailable"
```

**Database clients (CLI):**
```bash
command -v psql >/dev/null 2>&1 && echo "psql: available" || echo "psql: unavailable"
command -v sqlite3 >/dev/null 2>&1 && echo "sqlite3: available" || echo "sqlite3: unavailable"
command -v mysql >/dev/null 2>&1 && echo "mysql: available" || echo "mysql: unavailable"
```

**Database MCP servers:**
Check the available tools list for database MCP servers (e.g., `mcp__postgres`, `mcp__supabase`, `mcp__neon`, `mcp__mysql`, `mcp__mongodb`, `mcp__redis`).

Write the results as a `Detected tools:` block: one `<tool>: available` or `<tool>: unavailable` line per tool above, then one line per available database MCP server. The planner copies it into the plan's `## Detected Tools`.

**Task Update:** Mark task 1 as `completed`, task 2 as `in_progress`.

### Step 3: Draft the Plan

```
Task(
  subagent_type: "qa:test-planner",
  run_in_background: false,
  description: "Draft QA test plan",
  prompt: "Mode: draft
Arguments: <$ARGUMENTS verbatim, or (empty)>
Detected tools:
<the Step 2 block>"
)
```

The planner answers with one JSON object. On `{"error": ...}`, a failed dispatch, an answer that is not the expected JSON, or no file at its `plan` path, stop:

> Test plan generation failed: <reason>

Keep `plan`, `source` and `changed_files` for the review.

**Task Update:** Mark task 2 as `completed`, task 3 as `in_progress`.

### Step 4: Review the Plan

Run at most 3 review rounds. In round `n`:

1. Dispatch the reviewer:

   ```
   Task(
     subagent_type: "qa:test-plan-reviewer",
     run_in_background: false,
     description: "Review QA test plan (round <n>)",
     prompt: "Plan: <plan>
   Diff source: <source>
   Changed files:
   <changed_files, one path per line>
   Round: <n> of 3
   Previous findings:
   <none, or every earlier finding with the number it was sent under, followed by the planner's disposition and note>"
   )
   ```

2. The reviewer's answer must be one JSON object `{"findings": [...]}` whose findings each carry a `severity` of `blocker`, `concern` or `nit`. On a failed dispatch or any other answer, the review could not run: end the review and keep the plan unreviewed, with the reason.
3. No `blocker` or `concern` → the plan is approved; end the review.
4. `n` is 3 → end the review; this round's blockers and concerns stay open for the user.
5. Otherwise number this round's findings, continuing after the last number of earlier rounds, and dispatch the planner:

   ```
   Task(
     subagent_type: "qa:test-planner",
     run_in_background: false,
     description: "Revise QA test plan (round <n>)",
     prompt: "Mode: revise
   Plan: <plan>
   Diff source: <source>
   Round: <n> of 3
   Findings:
   <this round's findings, one per line: number, [severity] location: issue Fix: fix>"
   )
   ```

   The planner answers `{"plan": ..., "dispositions": [...]}`. On `{"error": ...}`, a failed dispatch or any other answer, end the review; this round's blockers and concerns stay open. Otherwise record each disposition with its finding and start round `n + 1`.

**Task Update:** Mark task 3 as `completed`.

### Step 5: Propose Next Step

Display:

> **Test plan saved to `<plan>`.**
>
> Plan review: <exactly one of the following>
> - approved in round <n> of 3.
> - <k> blocker(s) or concern(s) still open after round <n> — check them before running the plan:
>   - [<severity>] <location>: <issue> Fix: <fix>
> - could not run (<reason>); the plan is unreviewed.
>
> <only if the approving round reported nits> Optional nits (not applied):
>   - <location>: <issue>
>
> <only if the planner declined findings> Findings the planner declined:
>   - [<severity>] <location>: <issue> — <planner's note>
>
> Review the plan and when ready, run the tests with:
>
> `/qa:run`
>
> or specify the plan path:
>
> `/qa:run <plan>`

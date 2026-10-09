---
description: "Analyze code changes (PR, branch, commits) and generate a detailed QA test plan with FE and BE scenarios, edge cases, and tool detection; a reviewer agent checks the plan against the repository before it is handed over."
argument-hint: "[change-source]"
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

You coordinate QA test-plan authoring through the shared `qa:plan-authoring` skill, also used by `/qa:run`. The `qa:test-planner` agent analyzes the changes and writes the plan; the `qa:test-plan-reviewer` agent checks it against the repository, and the planner resolves what the review finds. Never write or edit the plan yourself: a finding the planner does not resolve stays open and goes to the user. This command authors and reviews only; it never bootstraps config or executes tests.

## Arguments

**Input:** `$ARGUMENTS`

Pass the argument to the planner verbatim. It resolves the source of changes: by default the open PR of the current branch (falling back to the branch diff), otherwise a PR number (`#123`), a branch name, `this branch` / `ten branch`, `last N commits` / `ostatnie N commitów`, or `staged`.

No options are accepted. If an argument token starts with `--`, stop before calling the engine or dispatching agents:

> Error: /qa:create-plan takes no options; set policy in .av/config.toml (see docs/plugins/qa.md#configuration).

---

## Workflow

### Step 1: Create Progress Tasks

Create the following tasks immediately:

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Detect available tools | Detecting available tools... |
| 2 | Draft test plan | Drafting test plan... |
| 3 | Review test plan | Reviewing test plan... |

### Step 2: Read Config Metadata

Load `qa:engine` and resolve the installed engine script using its harness-specific instructions. Run its `config` subcommand in the repository:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/engine/scripts/qa.py config
```

In OMP use the absolute path returned by `realpath skill://qa:engine/scripts/qa.py` instead of `CLAUDE_PLUGIN_ROOT`.

Keep the JSON object, including `state`, for `qa:plan-authoring`. Print any validation errors and warnings, but a recognized `missing-file`, `missing-table` or `invalid` state does not prevent authoring: the skill passes `Config: none`, and the planner writes `$QA_…` names and target names grounded in the repository. Without a valid config, `/qa:run`'s `plan check` identifies missing users, values, targets and stores for its config flow to fill; a missing cleanup recipe alone is a soft gap. Never bootstrap config here, execute sources, ask for trust or read secret values.

An engine/version/I/O error without a recognized config state is not a missing config. Stop and display its error instead of dispatching the planner.

### Step 3: Author and Review Through the Shared Skill

Load `qa:plan-authoring` with the user's argument verbatim (or `(empty)`), the `config` JSON and the three progress tasks. Follow its Steps 2-4: engine tool detection plus the browser probe, planner draft and at most three reviewer/revision rounds. It sends the same safe `Config:` projection of `targets`, `defaults`, `users`, `values` and `stores` to both agents in every round.

Consume its return contract: `plan`, `review` outcome and `open_findings`, plus optional nits and declined findings. On `{"error": ...}`, stop with `Test plan generation failed: <reason>`; do not propose running a nonexistent plan. Never duplicate the skill's detection, drafting or review logic in this command.

### Step 5: Propose Next Step

Display:

Use the returned `plan`, `review`, `open_findings`, `nits` and `declined_findings` for this display. Select the review line from `review.outcome`: `approved`, `open` or `unreviewed`; include `review.reason` when present. Do not turn exhausted rounds or a declined finding into approval.

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

---
allowed-tools: Bash(gh:*), Bash(git:*), Bash(command:*), Bash(echo:*), Bash(find:*), Bash(ls:*), Bash(cat:*), Bash(head:*), Bash(mkdir:*), Bash(jq:*), Bash(date:*), Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/engine/scripts/qa.py *), mcp__plugin_playwright_playwright__browser_navigate, Read, Write, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, Skill
description: Analyze code changes (PR, branch, commits) and generate a detailed QA test plan with FE and BE scenarios, edge cases, and tool detection; a reviewer agent checks the plan against the repository before it is handed over.
model: opus
argument-hint: [change-source]
---

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

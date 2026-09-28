---
allowed-tools: Bash(gh:*), Bash(git:*), Bash(command:*), Bash(echo:*), Bash(find:*), Bash(ls:*), Bash(cat:*), Bash(head:*), Bash(mkdir:*), Bash(jq:*), Bash(date:*), mcp__plugin_playwright_playwright__browser_navigate, Read, Write, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, Skill
description: Analyze code changes (PR, branch, commits) and generate a detailed QA test plan with FE and BE scenarios, edge cases, and tool detection; a reviewer agent checks the plan against the repository before it is handed over.
model: opus
argument-hint: [PR number, branch name, or natural language description of changes to analyze]
---

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

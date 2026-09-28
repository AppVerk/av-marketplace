# Delivery Plugin (Oh My Pi only)

Delivery runs approved OMP plans task by task, or delivers an existing plan with `/delivery:execute <PLAN_PATH>`. Each task goes to the agent selected from its file list, then receives a review and its own commit.

## Plan format

Write the plan's Approach as numbered `### Task N: <title>` blocks. For example (paths are illustrative):

```markdown
# Catalog search plan

## Approach

### Task 1: Add catalog search
**Commit:** feat: add catalog search

**Files:**
- Create: `src/catalog/search.py`
- Modify: `src/catalog/api.py`
- Test: `tests/test_search.py`
- Delete: `src/catalog/legacy_search.py`

Write a failing search test first, implement the search endpoint, then remove the legacy implementation.

## Verification
- Run the catalog search tests.
```

Number tasks 1, 2, 3… in execution order, each number exactly once; put producers before consumers. Every file change belongs to a task: text outside task blocks is context, not implementation work. List every file the task will create, modify, test, or delete under `**Files:**`, with repository-relative paths in backticks. The file list determines the implementer. Keep one stack per task (Python, React/TypeScript frontend, PHP, or other files such as docs and CI); split work spanning stacks into separate tasks. Each task must stand alone and name any functions, types, or signatures later tasks depend on. Do not put `##` or `###` headings inside a task outside fenced code blocks: the next heading ends that task.

`**Commit:**` is optional; without it, the task commit subject is `chore: <title>`. After the last task, an optional `## Verification` section lists checks Delivery runs in order. A plan with no `### Task` headings runs without Delivery. Proposing a plan in plan mode rejects it, listing every violation, when a task heading is malformed, a task lists no files or touches several stacks, a `**Commit:**` line is empty, or a task number repeats. `/delivery:execute` runs the same check before it creates a branch or commits anything and stops with the same list; the one difference is a task without a `**Files:**` block, which `/delivery:execute` accepts. Jev (the `judge` model role, e.g. `typesafe/jev-latest`) routes such a task when it names one stack with at least 0.8 confidence; otherwise, or on every such task when the `judge` role resolves to a non-Jev model, Delivery asks you.

## Branch and plan location

On `main` or `master`, Delivery creates a `delivery/<slug>` branch (adding a numeric suffix if that name exists). On any other branch, it stays on that branch. When `/delivery:execute` receives a plan file already in the repository, it keeps that plan at its existing path. An external plan file, or a plan approved in OMP plan mode, is saved to `docs/plans/<date>-<slug>.md` (with a numeric suffix if the destination exists). Delivery commits a new or changed plan before the first task; an unchanged plan already in the repository needs no new plan commit, and a plan your `.gitignore` excludes is never committed.

## Prerequisites

Run in a git repository on a checked-out branch. At detached HEAD, Delivery stops with `Check out a branch first.` The working tree must have no changes other than the plan itself; commit or stash other changes before starting. Install the plugin for each agent that will receive a task (Python Developer, Frontend Developer, PHP Developer, or Delivery's generic implementer). If an agent is unavailable, Delivery stops and prints the plugin installation command.

Delivery needs Python 3.9 or newer as `python3` on `PATH`: its plan check, task router and preflight run Python. Without it, approving a plan does not start a delivery and the plan runs as usual.

## Commit trailers and resuming

Each task commit carries `Delivery-Plan: <PLAN_PATH>`, `Delivery-Task: <N>`, and `Delivery-Task-Title: <title>`. If you choose to accept unresolved review findings, it also carries `Delivery-Review: accepted-with-open-findings`.

To resume, run `/delivery:execute <PLAN_PATH>`. Delivery skips a task only if a commit for that exact plan path contains both its task number and exactly the same task title as the current plan. If a task number matches but the title differs (or the title trailer is missing), Delivery stops and shows the commit, task number, committed title, and plan title rather than silently treating the task as done. The stop message names them: `Task N is committed as "<committed title>" in <commit>, but <plan> titles it "<plan title>"`.

Delivery runs its git commit commands with the AV_COMMIT_SKILL=1 prefix, so the Commit plugin's git commit guard lets them through. The prefix is not part of the commit message.

## Review and fix rounds

Every task is reviewed before its commit. Findings marked `critical` or `important` return to the same implementing agent for up to 3 fix rounds, with another review after each round. If blocking findings remain, choose `Accept and commit with open findings` or `Stop delivery`. Accepted open findings add the review trailer above; stopping leaves the delivery unfinished.

After the last task and the plan's Verification, Delivery runs `/code-review:review` over the delivered commits. When that review saves a report, Delivery commits it alone as `docs: add review of delivery <slug>` before offering `/code-review:fix-all`, unless your `.gitignore` excludes the report, in which case it stays uncommitted. Whatever fix-all changes, including the statuses it writes into the report, stays uncommitted for you to review and commit.

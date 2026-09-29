# Delivery Plugin

Delivery runs approved plans task by task, or delivers an existing plan with `/delivery:execute <PLAN_PATH>`. Each task goes to the agent the router selects from its file list, then receives a review and its own commit. Delivery never asks which developer should implement a task.

**Version:** 0.5.0

## How a delivery starts

In Claude Code:

- **Superpowers plans.** When you pick subagent-driven execution for a plan that `superpowers:writing-plans` saved, Delivery takes over instead of `superpowers:subagent-driven-development`: its hook denies that skill and starts the Delivery run. An explicitly named Markdown plan takes precedence over the one saved in the session only when its resolved path is inside the session's git repository, even when its path is part of a sentence, followed by punctuation, in backticks, or in a Markdown link; a named path outside the repository or one that cannot be found does not trigger the saved plan instead. With no named plan, Delivery uses the session's saved plan, including plans outside the repository that the hook recorded when they were written. Native (inline) execution is unchanged. The hand-over needs a plan with `### Task N: <title>` headings in a git repository; otherwise Superpowers runs as usual. Typing `/superpowers:subagent-driven-development` yourself hands the plan over the same way.
- **Plan mode.** Approving a plan with `### Task` headings starts the Delivery run.
- **`/delivery:execute <PLAN_PATH>`** delivers a plan file or resumes an interrupted delivery.

In OMP, approving a plan-mode plan with `### Task` headings starts the Delivery run, and `/delivery:execute <PLAN_PATH>` works as in Claude Code.

The plan check runs before a plan reaches you. In Claude Code, Delivery adds its task rules when Superpowers starts writing a plan and to every plan-mode prompt; saving a plan in a `plans` directory, or a Markdown file elsewhere with a valid `### Task N: <title>` heading, runs the check and gives Claude every violation to fix. Ordinary headings such as `### Task queue` do not replace the session plan or block a research plan. A plan with errors is sent back to be fixed instead of being handed over.

Only top-level session plan writes and edits run this check or update the session's saved plan; Markdown edits inside subagents do neither.

Delivery's Claude Code hooks start Python for each prompt you submit, each Skill call, ExitPlanMode, the typed subagent-driven command, and Markdown writes and edits; other file edits skip it. The hook acts only on plan-mode prompts, the two Superpowers skills above, ExitPlanMode and plan files, and exits without output for anything else.

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

Number tasks 1, 2, 3… in execution order, each number exactly once; put producers before consumers. Every file change belongs to a task: text outside task blocks is context, not implementation work. List every file the task will create, modify, test, or delete under `**Files:**`, with repository-relative paths in backticks. The file list determines the implementer. Keep one stack per task (Python, React/TypeScript frontend, PHP, or other files such as docs and CI); split work spanning stacks into separate tasks. Each task must stand alone and name any functions, types, or signatures later tasks depend on. Do not put `##` or `###` headings inside a task outside fenced code blocks: the next heading ends that task. Keep the English word `Task` in the heading even when the plan is written in another language: `### Zadanie 1:` is not a task heading.

`**Commit:**` is optional; without it, the task commit subject is `chore: <title>`. After the last task, an optional `## Verification` section lists checks Delivery runs in order. A plan with no `### Task` headings runs without Delivery. Proposing a plan in plan mode (OMP's `xd://propose`, Claude Code's ExitPlanMode) rejects it, listing every violation, when a task heading is malformed, a task lists no files or touches several stacks, a `**Commit:**` line is empty, or a task number repeats. `/delivery:execute` and the Superpowers hand-over run the same check before Delivery creates a branch or commits anything and stop with the same list; the one difference is a task without a `**Files:**` block, which they accept and route by its text.

## Routing

A task's file list decides its agent: `.py` files go to the Python Developer, `.php` files to the PHP Developer, TypeScript, JavaScript and CSS files to the Frontend Developer when the nearest manifest above them is a `package.json` that depends on React, and everything else (docs, CI, configuration, Node tooling) to Delivery's generic implementer. Docs and configuration files do not vote.

A task without a file list is routed by its text. Mentioned directory paths vote for their stack as listed files would, except URL-shaped paths with a dotted host before the first `/`. Bare code file names vote only in inline code or fenced blocks; a bare TypeScript, JavaScript or CSS file name, and every fenced code block in those languages, votes frontend when the repository has a React package and generic otherwise. A fenced Python or PHP block votes for that stack. The stack with the most votes gets the task. No votes, or a tie, sends it to the generic implementer. In OMP, when the repository has a Python project (`pyproject.toml`, `setup.py`, `setup.cfg` or `requirements.txt`), a PHP project (`composer.json`) or a `package.json` that depends on React, at its root or up to three directory levels below it, Delivery first asks the model on the `judge` role and uses the answer only when that model's name contains `jev` (as the default `typesafe/jev-latest` does) and the answer names one stack with at least 0.8 confidence. A repository without such a project, a `judge` role mapped to a model without `jev` in its name, or a judge that fails or does not answer leaves the task to routing by its text.

Delivery prints one `Routing: task <N> → <agent> (source: <source>)` line per task before the first one starts; the source is `files`, `text (<votes>)`, `default`, or in OMP `jev p=<confidence> via <model>`.

## Branch and plan location

On `main` or `master`, Delivery creates a `delivery/<slug>` branch (adding a numeric suffix if that name exists). On any other branch, it stays on that branch. When Delivery receives a plan file already in the repository, such as a Superpowers plan in `docs/superpowers/plans/`, it keeps that plan at its existing path. An external plan file, or a plan approved in plan mode, is saved to `docs/plans/<date>-<slug>.md` (with a numeric suffix if the destination exists). Claude Code names plan-mode files at random, so the slug of an external plan there comes from its `# ` title. Delivery commits a new or changed plan before the first task; an unchanged plan already in the repository needs no new plan commit, and a plan your `.gitignore` excludes is never committed.

## Prerequisites

Run in a git repository on a checked-out branch. At detached HEAD, Delivery stops with `Check out a branch first.` The working tree must have no changes other than the plan itself; commit or stash other changes before starting. Install the plugin for each agent that will receive a task (Python Developer, Frontend Developer, PHP Developer, or Delivery's generic implementer). If an agent is unavailable, Delivery stops and prints the plugin installation command. The final review needs Code Review. The Superpowers hand-over needs the `superpowers` plugin from the official Claude Code marketplace.

Delivery needs Python 3.9 or newer as `python3` on `PATH`: its plan check, task router, hooks and preflight run Python. Without it, approving a plan does not start a delivery and the plan runs as usual.

## Agents and models

The task loop dispatches the routed developer agent, then `delivery:task-reviewer`. In Claude Code, `delivery:implementer` and `delivery:task-reviewer` run on `opus`, like the developer agents; the task reviewer returns its verdict as a JSON block, and a reply without one is retried once before the delivery stops. In OMP they use the `executor` and `code_review` model roles (see the [Oh My Pi guide](../oh-my-pi.md#model-roles)).

## Commit trailers and resuming

Each task commit carries `Delivery-Plan: <PLAN_PATH>`, `Delivery-Task: <N>`, and `Delivery-Task-Title: <title>`. If you choose to accept unresolved review findings, it also carries `Delivery-Review: accepted-with-open-findings`.

To resume, run `/delivery:execute <PLAN_PATH>`. Delivery skips a task only if a commit for that exact plan path contains both its task number and exactly the same task title as the current plan. If a task number matches but the title differs (or the title trailer is missing), Delivery stops and shows the commit, task number, committed title, and plan title rather than silently treating the task as done. The stop message names them: `Task N is committed as "<committed title>" in <commit>, but <plan> titles it "<plan title>"`.

Delivery runs its git commit commands with the AV_COMMIT_SKILL=1 prefix, so the Commit plugin's git commit guard lets them through. The prefix is not part of the commit message.

## Review and fix rounds

Every task is reviewed before its commit. Findings marked `critical` or `important` return to the same implementing agent for up to 3 fix rounds, with another review after each round. If blocking findings remain, choose `Accept and commit with open findings` or `Stop delivery`. Accepted open findings add the review trailer above; stopping leaves the delivery unfinished.

After the last task and the plan's Verification, Delivery runs `/code-review:review` over the delivered commits. When that review saves a report, Delivery commits it alone as `docs: add review of delivery <slug>` before offering `/code-review:fix-all`, unless your `.gitignore` excludes the report, in which case it stays uncommitted. Whatever fix-all changes, including the statuses it writes into the report, stays uncommitted for you to review and commit.

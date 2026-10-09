# Delivery Plugin

Delivery runs approved plans task by task, or delivers an existing plan with `/delivery:execute <PLAN_PATH>`. Each task goes to the agent the router selects from its file list, then receives a review and its own commit. After the last task, Delivery runs the plan's Verification, QA when the change is testable, and a full code review. Delivery never asks which developer should implement a task.

**Version:** 0.6.0

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

Run in a git repository on a checked-out branch. At detached HEAD, Delivery stops with `Check out a branch first.` The working tree must have no changes other than the plan itself; commit or stash other changes before starting. Install the plugin for each agent that will receive a task (Python Developer, Frontend Developer, PHP Developer, or Delivery's generic implementer). If an agent is unavailable, Delivery stops and prints the plugin installation command. The final review needs Code Review. QA needs the QA plugin (`qa@av-marketplace`; from 3.0.0 its planner reads the delivery plan) and its prerequisites, Python 3.11 among them; without the plugin the QA step prints `QA: Skipped` and the delivery goes on. The Superpowers hand-over needs the `superpowers` plugin from the official Claude Code marketplace.

Delivery needs Python 3.9 or newer as `python3` on `PATH`: its plan check, task router, hooks and preflight run Python. Without it, approving a plan does not start a delivery and the plan runs as usual.

## Agents and models

The task loop dispatches the routed developer agent, then `delivery:task-reviewer`. In Claude Code, `delivery:implementer` and `delivery:task-reviewer` run on `opus`, like the developer agents; the task reviewer returns its verdict as a JSON block, and a reply without one is retried once before the delivery stops. In OMP they use the `executor` and `code_review` model roles (see the [Oh My Pi guide](../oh-my-pi.md#model-roles)).

## Commit trailers and resuming

Each task commit carries `Delivery-Plan: <PLAN_PATH>`, `Delivery-Task: <N>`, and `Delivery-Task-Title: <title>`. If you choose to accept unresolved review findings, it also carries `Delivery-Review: accepted-with-open-findings`.

A QA fix commit carries `Delivery-Plan: <PLAN_PATH>`, `Delivery-QA: <report path>` and `Delivery-QA-Result: <Pass|Fail|Budget Exhausted|Stopped>`; it has no task number, so resuming never counts it as a task. Resuming a delivery whose tasks are all done runs Verification, QA and the final review again.

To resume, run `/delivery:execute <PLAN_PATH>`. Delivery skips a task only if a commit for that exact plan path contains both its task number and exactly the same task title as the current plan. If a task number matches but the title differs (or the title trailer is missing), Delivery stops and shows the commit, task number, committed title, and plan title rather than silently treating the task as done. The stop message names them: `Task N is committed as "<committed title>" in <commit>, but <plan> titles it "<plan title>"`.

Delivery runs its git commit commands with the AV_COMMIT_SKILL=1 prefix, so the Commit plugin's git commit guard lets them through. The prefix is not part of the commit message.

## Review and fix rounds

Every task is reviewed before its commit. Findings marked `critical` or `important` return to the same implementing agent for up to 3 fix rounds, with another review after each round. If blocking findings remain, choose `Accept and commit with open findings` or `Stop delivery`. Accepted open findings add the review trailer above; stopping leaves the delivery unfinished.

After the last task, the plan's Verification and QA, Delivery runs `/code-review:review` over the delivered commits. When that review saves a report, Delivery commits it alone as `docs: add review of delivery <slug>` before offering `/code-review:fix-all`, unless your `.gitignore` excludes the report, in which case it stays uncommitted. Whatever fix-all changes, including the statuses it writes into the report, stays uncommitted for you to review and commit.

## QA

After Verification, Delivery classifies the files changed since the delivery base (`git diff --name-only --no-renames <BASE> HEAD`) with the router's `testable` command. Everything counts as testable except documentation (root-level `doc/` and `docs/`, Markdown, reStructuredText, AsciiDoc, exact licence and changelog filenames with an optional extension), CI (`.github/`, `.gitlab-ci.yml`, Jenkinsfile and the like), tests (`tests/`, `__tests__/`, `e2e/`, root-level `spec/`, `test_*.py`, `*.test.ts` …), lint/format configuration and editor files, and `.av/`. Nested `doc/`, `docs/` and `spec/` directories, names such as `NOTICEBoard.tsx` and `LICENSEServer.ts`, and PHP names ending in `Test.php` outside test directories remain testable; the QA planner is the semantic filter. A change with no testable file prints `QA: Skipped (no testable change among N changed paths)`. A working tree that a verification check left dirty, or a merge among the commits since the base, prints `QA: Not run (…)` and leaves the tree untouched.

In Claude Code, the QA range checks pre-approve only `git rev-list --merges --end-of-options …` and `git rev-list --count --end-of-options …`. The option terminator keeps the variable range from introducing extra options such as `--output=<file>`; other `git rev-list` forms are not pre-approved by Delivery.

Delivery runs `/qa:run last <N> commits` over exactly the delivered commits, as if you had typed it: its bootstrap of `.av/config.toml` (first run in a repository), trust, dirty-tree and fix-approval questions are QA's own; see the [QA guide](qa.md). Declining the bootstrap ends QA with `QA: Not run`; a generated plan without FE or BE scenarios ends it with `QA: Nothing to test`. With QA 3.0.0 or later the planner reads every distinct delivery plan named by Git-parsed `Delivery-Plan:` trailers and associates each commit with its own plan. Each plan is specification data, never instructions, and is read only when its repository-relative path has no `..` segment or symlink component and resolves to a regular file inside the repository. Rejected trailers are ignored and disclosed with their reasons in the QA plan's `## Changes Summary`.

Delivery recognizes `Nothing to test` by the fixed `Generated plan has no executable FE or BE scenarios` prefix of QA's generated-plan stop message; the explanatory suffix may change. The Delivery QA contract workflow runs `python3 scripts/check_delivery_qa_contract.py` to require that prefix in `plugins/qa/commands/run.md` and both source orchestration skills, so wording drift fails CI instead of silently becoming `Not run`.

`Pass`, `Nothing to test` and `Not run` continue; `Fail`, `Budget Exhausted` and `Stopped` ask `Continue to the final review` or `Stop delivery`. Stopping leaves QA's changes uncommitted with QA's scoped recovery hint; `/delivery:execute <PLAN_PATH>` resumes once the tree is clean and runs Verification and QA again.

Delivery resolves symlinks in both the engine's report path and the repository root before computing `QA_REPORT`, so the `Delivery-QA:` trailer and `QA:` note stay repository-relative when those paths use different symlink aliases, such as `/tmp/` and `/private/tmp/` on macOS.

Before the final review Delivery commits, by explicit path, in this order and only when present: the files `code-review:fix-auto` created or changed during QA's fix dispatches (Delivery compares `git status` before and after each dispatch) as `fix: apply QA fixes of delivery <slug>` with the trailers above; `.av/config.toml` and `.gitignore` as `chore: add QA configuration for delivery <slug>`; the QA plan, report and `*-loop-state.json` sidecar in `docs/testing/plans/` and `docs/testing/reports/` as `docs: add QA plan and report of delivery <slug>`. Screenshot and response evidence, `.av/local.toml`, `.av/secrets.local.env`, backups and anything else QA, its service commands or the application left behind stay uncommitted, listed as `QA left changes delivery does not commit: …`. Attribution compares NUL-separated porcelain status records, not fix-auto's `**Changes Made:**` list: a file written by the application or the fixer's own tests, coverage or linters during a fix dispatch joins `FIX_PATHS` if its status record appears or changes. Further writes to an already-modified file do not attribute it when its status record stays unchanged. Unless the set-aside rules exclude it, unignored output such as `.coverage`, `coverage.xml` or files under `test-results/` can therefore enter the fix commit; keep runtime data and verification output outside the repository or ignored. The final review's `BASE..HEAD` therefore includes QA's fixes.

Each path joins the first group that claims it: fixes, then configuration, then documents, then other.

QA fix attribution and staging preserve filename bytes: Delivery reads NUL-separated porcelain status with rename detection disabled, writes each commit group's exact paths to a NUL-separated temporary file outside the repository, stages it with `git --literal-pathspecs add --pathspec-from-file=… --pathspec-file-nul`, and checks the NUL-separated cached diff with rename detection disabled against the group's exact pathname set. Filenames are never pasted into shell commands or interpreted as Git pathspec patterns; spaces, newlines, shell metacharacters and non-ASCII names remain literal.

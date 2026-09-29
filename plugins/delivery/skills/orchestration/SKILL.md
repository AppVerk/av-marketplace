---
name: orchestration
description: "The Delivery run: delivers a plan task by task, each task to the developer agent the router picks, reviewed and committed, then runs the plan's Verification and a full code review. Delivery's hooks start it for a Superpowers plan when subagent-driven execution is picked and for a plan approved in plan mode; /delivery:execute starts it for a plan file."
argument-hint: "<plan path>"
user-invocable: false
allowed-tools: Bash(git rev-parse *), Bash(git status *), Bash(git branch --show-current), Bash(git switch -c *), Bash(git ls-files *), Bash(git add *), Bash(git diff --cached --quiet), Bash(git reset --soft *), Bash(git stash push *), Bash(git check-ignore *), Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py *)
---

# Delivery orchestration

The Delivery run of the delivery plugin. `PLAN_SOURCE` is `$ARGUMENTS`: the plan's file path. Values in `<ANGLE_BRACKETS>` come from earlier steps; write them literally into later commands. The Bash tool keeps the working directory between calls but not shell variables, so the commands below print what later steps need.

The router is `${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py`; run it exactly as `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py <command> ...`. Its commands:

- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py check '<REPO>' '<plan>'` → `{"tasks": N, "problems": [...], "no_files": [...]}`. `problems` are plan errors that stop a run; `no_files` names tasks without a **Files:** block, which the router still routes.
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py plan '<REPO>' '<plan>'` → one entry per task with `task`, `title`, `commit`, `block`, `files`, `groups`, `stack`, `agent`, `source`, `evidence`. `agent` is the implementer. `source` is `files` when the task's file list decided it; for a task without files the router decides from the task text: `text` when its code paths and fenced code languages favor one stack (`evidence` lists the votes), `default` when they favor none and `agent` is `delivery:implementer`.
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py message '<REPO>' '<plan>' <N> [--open-findings]` → the commit message of task N with its `Delivery-*` trailers.
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py done '<REPO>' '<plan>'` → `{"done": [...], "conflicts": [...], "base": "<sha>"}` from the branch's delivery commits.
- `slug <plan.md> [--in-repo]` → a filesystem-safe slug from the external plan's first `# ` heading (or its filename if absent); `--in-repo` uses only the filename.

The router's `agent` is final. Never ask the user which agent implements a task.

## Delivery run

Run the steps in order. Every `stop` prints its message and ends the run.

### 1. Preflight

1. **Repository.** `git rev-parse --show-toplevel` prints `REPO`. A failure → stop with `Delivery needs a git repository.`
2. **Plan file.** From the session's working directory, `realpath '<PLAN_SOURCE>'` prints `PLAN_FILE`; a failure → stop with `Plan not found: <PLAN_SOURCE>.` When `PLAN_FILE` is inside `<REPO>/`, `PLAN_PATH` is its path relative to `REPO`; otherwise step 6 sets `PLAN_PATH`. Then `cd '<REPO>'`: every later command runs there.
3. **Slug.** Run the router on the plan file; when `PLAN_FILE` is inside `<REPO>/`, append `--in-repo` so its filename, not its heading, decides the slug:
   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py slug '<PLAN_FILE>'
   ```
   It prints `SLUG`.
4. **Other changes.** When `PLAN_PATH` is set, run `git status --porcelain --untracked-files=all -- . ':(exclude,literal)<PLAN_PATH>'`; otherwise run `git status --porcelain --untracked-files=all`. Any output → stop with `Commit or stash your other changes before delivery, then run /delivery:execute <PLAN_SOURCE>.` Nothing below runs on this path.
5. **Current branch.** `git branch --show-current` prints `BRANCH`; empty output (detached HEAD) → stop with `Check out a branch first.`
6. **Save the plan** when `PLAN_PATH` is not set yet:
   ```bash
   P="docs/plans/$(date +%F)-"'<SLUG>'.md; n=2; while [ -e "$P" ]; do P="docs/plans/$(date +%F)-"'<SLUG>'"-$n.md"; n=$((n+1)); done; mkdir -p docs/plans && cp '<PLAN_FILE>' "$P" && printf '%s\n' "$P"
   ```
   `PLAN_PATH` is the printed path. The file stays untracked until step 9.
7. **Plan check.** Run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py check '<REPO>' '<PLAN_PATH>'`; a non-zero exit → stop with the router's error. When `tasks` is 0 → stop with `Delivery cannot run <PLAN_PATH>: it has no '### Task N: <title>' headings.` When `problems` is not empty → stop with one line per problem:
   ```
   Delivery cannot run <PLAN_PATH>:
   - <problem>
   Fix these tasks in <PLAN_PATH>, then run /delivery:execute <PLAN_PATH>.
   ```
   A plan saved in step 6 stays where it is. Entries of `no_files` are not problems: the router routes those tasks by their text.
8. **Delivery branch.** `BRANCH` is `main` or `master` → create the first free delivery branch; the untracked plan comes along:
   ```bash
   B='delivery/<SLUG>'; n=2; while git rev-parse --verify --quiet "refs/heads/$B" >/dev/null; do B='delivery/<SLUG>'"-$n"; n=$((n+1)); done; git switch -c "$B" && printf '%s\n' "$B"
   ```
   `BRANCH` becomes the printed name.
9. **Commit the plan** when `git status --porcelain -- '<PLAN_PATH>'` prints anything. A plan that git ignores and does not track prints nothing, so it stays uncommitted. The subject is `docs: update delivery plan <SLUG>` when `git ls-files --error-unmatch -- '<PLAN_PATH>'` succeeds, otherwise `docs: add delivery plan <SLUG>`. Run `git add -- '<PLAN_PATH>'`, then `AV_COMMIT_SKILL=1 git commit -m '<subject>' -- '<PLAN_PATH>'`. A failed commit → print git's output and stop. The AV_COMMIT_SKILL=1 prefix lets the Commit plugin's git commit guard pass delivery's commits; keep it on every commit delivery makes.
10. If `git status --porcelain` prints anything → stop with `Commit or stash your other changes, then run /delivery:execute <PLAN_PATH>.`
11. `TASKS` = the JSON of `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py plan '<REPO>' '<PLAN_PATH>'`; a non-zero exit → stop with the router's error.
12. **Done tasks and base.** Run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py done '<REPO>' '<PLAN_PATH>'`; a non-zero exit → stop with the router's error. When its `conflicts` list is not empty → stop, printing one line per entry: `Task <task> is committed as "<committed_title, or missing>" in <commit>, but <PLAN_PATH> titles it "<plan_title>". Restore the title or drop the commit, then run /delivery:execute <PLAN_PATH>.` Mark no task done on this path. Otherwise the tasks listed in `done` are done and `BASE` is its `base`.
13. **Routing.** For every not-done task, print one line in your reply before starting step 2; it is the audit trail of each routing decision:
    ```
    Routing: task <N> → <agent> (source: <source>)
    ```
    `<agent>` is the entry's `agent`. `<source>` is `files`, `default`, or `text (<evidence joined with "; ">)`.
14. Every routed agent must be available as a `subagent_type` of the Agent tool. A missing one → stop with `Install <plugin>: /plugin install <plugin>@av-marketplace, then restart Claude Code and run /delivery:execute <PLAN_PATH>.` (`<plugin>` is the part before `:`).
15. Create one task-list item per not-done task with TaskCreate, `Task <N>: <title>`, then `Plan verification` and `Final code review`.

If every task is already done, print `All tasks of <PLAN_PATH> are delivered.` and go to step 3.

### 2. Tasks

For each not-done task, in ascending order of `N`:

1. Mark its task-list item in progress. Run **Task loop** with `N`, `TASK_BLOCK` = the task's `block`, `AGENT` = its `agent`, `PLAN_PATH`, `BRANCH`.
2. Act on the result:
   - `stopped` → run step 4 and end the run;
   - `skipped` → mark the item completed and note `skipped` in the summary;
   - `approved` or `accepted-with-open-findings` → commit the staged changes in one Bash call; for `accepted-with-open-findings` add `--open-findings` after `<N>`:
     ```bash
     MSG=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py message '<REPO>' '<PLAN_PATH>' <N>) && printf '%s' "$MSG" | AV_COMMIT_SKILL=1 git commit -F -
     ```
     A router error commits nothing: print it and stop. Mark the item completed only after the commit succeeds.
   - A failed commit (for example a rejecting hook) → print git's output and stop.

### 3. Verification

Mark `Plan verification` in progress. When `PLAN_PATH` has a `## Verification` section, carry out each check it lists, in order, with your own tools — commands, scripts, smoke runs — without editing project files. A check that needs a person, such as a manual UI step you cannot perform, is `manual`. Print one line per check:

```
Verification: <check> — pass | fail | manual (<evidence>)
```

Without a `## Verification` section, print `Verification: none in plan`. Any `fail` → use AskUserQuestion: `Verification failed: <checks>. What now?` with options `Continue to the final review` and `Stop delivery`. `Stop delivery` → run step 4 and end the run. Mark `Plan verification` completed.

### 4. Summary

Print the table `Task | Agent | Routing | Fix rounds | Result`, one row per task handled in this run, then the `Verification:` lines. The `Routing` column holds the routing source.

### 5. Final review

Mark `Final code review` in progress.

- Invoke the Skill tool with skill `code-review:review` and these args, then carry out the review it loads completely:
  ```
  Changes on branch <BRANCH> in <BASE>..HEAD (git diff <BASE>..HEAD), delivered from <PLAN_PATH>. Review only these changes.
  ```
  When the Skill tool has no `code-review:review`, print `Install code-review@av-marketplace and run /code-review:review.` and end. Do not substitute another review skill or command, such as Claude Code's built-in `code-review`: the final review is `code-review:review` or none.
- If the review saved a report, run `git check-ignore -q -- '<report path>'`. Exit 0 means git ignores the report: leave it uncommitted. Otherwise commit it before anything else touches it: `git add -- '<report path>'`, then `AV_COMMIT_SKILL=1 git commit -m 'docs: add review of delivery <SLUG>' -- '<report path>'`. Commit only that path. If adding or committing fails, print git's output and stop.

Mark `Final code review` completed.

### 6. Fix offer

If the review saved a report, use AskUserQuestion: `Run /code-review:fix-all on <report path>?` with options `Yes` and `No`. On `Yes`, invoke the Skill tool with skill `code-review:fix-all` and args `<report path>`, and carry it out completely. Whatever it changes, including the statuses it writes into the report, stays uncommitted: end with `Review fixes are uncommitted; review them and commit.` Without a saved report, end the run.

## Task loop

Inputs: `N`, `TASK_BLOCK`, `AGENT`, `PLAN_PATH`, `BRANCH`. `PLUGIN` is the part of `AGENT` before `:` when `AGENT` is a developer agent (`python-developer`, `frontend-developer`, `php-developer`), otherwise `none`.

Every dispatch below is one Agent tool call in the foreground: `subagent_type` is the agent, `description` is `Task <N>: implement`, `Task <N>: review` or `Task <N>: fix`, and `prompt` is this line, a blank line, then the template:

```
Delivery of <PLAN_PATH> on branch <BRANCH>. One task per agent; the orchestrator reviews and commits.
```

1. `git rev-parse HEAD` prints `TASK_BASE`.
2. **Implement.** Dispatch `AGENT` with the **Implementer template**.
3. **Stage.** Run `git branch --show-current`. If it prints something other than `BRANCH`, print `Delivery stopped: expected branch <BRANCH>, current branch <printed branch, or detached HEAD>.` and return result `stopped` without resetting or staging. If `git rev-parse HEAD` differs from `TASK_BASE`, the agent committed: run `git reset --soft <TASK_BASE>`. Then run `git add -A`.
4. **Nothing to review?** If `git diff --cached --quiet` succeeds (no changes), or the report's `**Status:**` line contains `❌`, use AskUserQuestion:
   - question: `Task <N> produced <no changes | a ❌ Failed report>. What now?`
   - `Retry once` → go back to step 2. Allowed once per task; after a retry, offer only the other two options;
   - `Skip this task` → `git stash push --include-untracked -m "delivery: skipped task <N>"` and return result `skipped`;
   - `Stop delivery` → leave the tree as it is and return result `stopped`.
5. **Review, round `r = 0`.** Dispatch `delivery:task-reviewer` with the **Reviewer template**. Its verdict is the last fenced `json` block of its reply: `{"verdict": ..., "findings": [...]}`. When no such block parses, dispatch it once more with the same prompt plus the line `Your reply had no JSON verdict block. End with it.`; a second failure → print `Delivery stopped: the reviewer of task <N> returned no verdict.` and return result `stopped`. The review is blocking when any finding has severity `critical` or `important`, whatever `verdict` says.
6. **Fix rounds.** While the review is blocking and `r < 3`:
   - `r = r + 1`;
   - dispatch `AGENT` with the **Fix template**, passing the blocking findings;
   - repeat step 3;
   - dispatch `delivery:task-reviewer` again with the Reviewer template and the previous findings.
7. **Still blocking after round 3** → use AskUserQuestion:
   - question: `Task <N> still has <k> blocking findings after 3 fix rounds. What now?`
   - options: `Accept and commit with open findings` (result `accepted-with-open-findings`), `Stop delivery` (result `stopped`).
8. Not blocking → result `approved`. Return `{result, rounds: r, findings}` to the Delivery run. The Delivery run commits; this loop never does.

### Implementer template

```
You are implementing Task <N> of the plan <PLAN_PATH>.

<TASK_BLOCK>

Rules:
- Implement exactly this task. Write tests first when the task lists a Test file.
- Do not commit, stash, switch branches or rewrite history. Leave all changes in the working tree.
- End with your report, including a **Status:** line (✅ Complete | ⚠️ Partial | ❌ Failed).
```

### Reviewer template

```
Review the staged changes for Task <N> of <PLAN_PATH>.
Stack plugin: <PLUGIN>

<TASK_BLOCK>
```

From round 1 on, append:

```

Findings from the previous review — verify each is resolved:
<previous findings as JSON>
```

### Fix template

```
Fix the review findings for Task <N> of <PLAN_PATH>. Your earlier implementation is staged (git diff --cached).

<TASK_BLOCK>

Findings to fix — fix exactly these, do not redo the task:
<blocking findings as JSON>

Rules:
- Change only what the findings require; add a failing test first when a finding reports missing coverage.
- Do not commit, stash, switch branches or rewrite history. Leave all changes in the working tree.
- End with your report, including a **Status:** line (✅ Complete | ⚠️ Partial | ❌ Failed).
```

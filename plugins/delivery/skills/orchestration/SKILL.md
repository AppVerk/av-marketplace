---
name: orchestration
description: "The Delivery run: delivers a plan task by task, each task to the developer agent the router picks, reviewed and committed, then runs the plan's Verification, QA when the change is testable, and a full code review. Delivery's hooks start it for a Superpowers plan when subagent-driven execution is picked and for a plan approved in plan mode; /delivery:execute starts it for a plan file."
argument-hint: "<plan path>"
user-invocable: false
allowed-tools:
  - Bash(git rev-parse *)
  - Bash(git rev-list --merges --end-of-options *)
  - Bash(git rev-list --count --end-of-options *)
  - Bash(git status *)
  - Bash(git branch --show-current)
  - Bash(git switch -c *)
  - Bash(git ls-files *)
  - Bash(git add *)
  - Bash(git --literal-pathspecs add *)
  - Bash(git diff --cached --quiet)
  - Bash(git diff --cached --name-only *)
  - Bash(git reset --soft *)
  - Bash(git reset -q)
  - Bash(git stash push *)
  - Bash(git check-ignore *)
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py *)
  - "Bash(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' *)"
---

# Delivery orchestration

The Delivery run of the delivery plugin. `PLAN_SOURCE` is `$ARGUMENTS`: the plan's file path. Values in `<ANGLE_BRACKETS>` come from earlier steps; write them literally into later commands. The Bash tool keeps the working directory between calls but not shell variables, so the commands below print what later steps need.

The router is `${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py`; run it exactly as `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py <command> ...`. Its commands:

- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py check '<REPO>' '<plan>'` → `{"tasks": N, "problems": [...], "no_files": [...]}`. `problems` are plan errors that stop a run; `no_files` names tasks without a **Files:** block, which the router still routes.
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py plan '<REPO>' '<plan>'` → one entry per task with `task`, `title`, `commit`, `block`, `files`, `groups`, `stack`, `agent`, `source`, `evidence`. `agent` is the implementer. `source` is `files` when the task's file list decided it; for a task without files the router decides from the task text: `text` when its code paths and fenced code languages favor one stack (`evidence` lists the votes), `default` when they favor none and `agent` is `delivery:implementer`.
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py message '<REPO>' '<plan>' <N> [--open-findings]` → the commit message of task N with its `Delivery-*` trailers.
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py done '<REPO>' '<plan>'` → `{"done": [...], "conflicts": [...], "base": "<sha>"}` from the branch's delivery commits.
- `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py testable '<REPO>' '<BASE>'` → `{"testable": bool, "files": [...], "excluded": [...]}`: the paths changed between `<BASE>` and `HEAD` that QA can exercise, and the docs, CI, test, tooling and `.av/` paths it ignores.
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
15. Create one task-list item per not-done task with TaskCreate, `Task <N>: <title>`, then `Plan verification`, `QA` and `Final code review`.

If every task is already done, print `All tasks of <PLAN_PATH> are delivered.` and go to step 3.

### 2. Tasks

For each not-done task, in ascending order of `N`:

1. Mark its task-list item in progress. Run **Task loop** with `N`, `TASK_BLOCK` = the task's `block`, `AGENT` = its `agent`, `PLAN_PATH`, `BRANCH`.
2. Act on the result:
   - `stopped` → run step 5 and end the run;
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

Without a `## Verification` section, print `Verification: none in plan`. Any `fail` → use AskUserQuestion: `Verification failed: <checks>. What now?` with options `Continue to the final review` and `Stop delivery`. `Stop delivery` → run step 5 and end the run. Mark `Plan verification` completed.

### 4. QA

Mark `QA` in progress. This step ends with `QA_RESULT`, one of `Skipped`, `Nothing to test`, `Not run`, `Pass`, `Fail`, `Budget Exhausted`, `Stopped`; `QA_NOTE`, its reason; `QA_REPORT`, the run's report path relative to `REPO` when a run started; and `FIX_PATHS`, the paths QA's fixer created or changed. Sub-step 7 commits only paths attributed to QA by these rules; nothing else is ever staged.

**Path handling for sub-steps 4 and 7:** filenames are data, never shell source. Use a short Python driver with `subprocess.run(argv, check=True, capture_output=True)` (no `shell=True` or `text=True`) to capture `git status --porcelain=v1 -z --no-renames --untracked-files=all` as bytes. Split only on `b"\0"`; each non-empty record is the two-byte status, one separator byte, then the exact pathname bytes (`record[3:]`). `--no-renames` keeps rename endpoints as separate deletion/addition records. Keep `FIX_PATHS` and the groups as exact pathname bytes; do not split on whitespace/newlines, C-unquote, or decode/re-encode names. Persist the snapshots and NUL-separated `FIX_PATHS` in binary files in a private temporary directory outside `<REPO>` so they survive separate tool calls; remove that directory when QA finishes or stops. Never paste a status record or filename into a command, including `printf`, a heredoc or Python source; the driver must read paths from Git's binary output or these binary files. Only escape names for display.

**Attribution residual:** status-delta attribution does not consult fix-auto's `**Changes Made:**` list. Unignored files written during a fix dispatch by the application or the fixer's tests, coverage or linters (for example `.coverage`, `coverage.xml` or files under `test-results/`) can join `FIX_PATHS` and enter the fix commit unless sub-step 7's set-aside rules exclude them. Keep runtime data and verification output outside the repository or ignored.

1. When the Skill tool has no `qa:run` → `QA_RESULT=Skipped`, `QA_NOTE`: `qa@av-marketplace is not installed`; go to 8.
2. Run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py testable '<REPO>' '<BASE>'`; a non-zero exit → stop with the router's error. When its `testable` is false → `QA_RESULT=Skipped`, `QA_NOTE`: `no testable change among <length of excluded> changed paths`; go to 8.
3. **Clean tree and range.** `git status --porcelain --untracked-files=all` prints anything (a verification check left files behind) → `QA_RESULT=Not run`, `QA_NOTE`: `the working tree has changes after verification: <paths, space-separated>`; go to 8. QA never adopts those changes. Then `git rev-list --merges --end-of-options '<BASE>'..HEAD` prints anything → `QA_RESULT=Not run`, `QA_NOTE`: `commits since <BASE> include a merge; run /qa:run <BRANCH> yourself`; go to 8. Then `git rev-list --count --end-of-options '<BASE>'..HEAD` prints `N`; `git rev-parse 'HEAD~<N>'` differs from `BASE` → the same `Not run` with `commits since <BASE> are not linear` and go to 8. Only a linear range reaches QA, so `last <N> commits` is exactly `BASE..HEAD`.
4. `FIX_PATHS` starts empty. Invoke the Skill tool with skill `qa:run` and args `last <N> commits`, then carry out the run it loads completely. Its gates (config bootstrap and trust, dirty tree, fix approval, service start, takeover) go to the user through AskUserQuestion exactly as that command specifies; never answer one yourself. **Fix attribution:** immediately before every `code-review:fix-auto` dispatch of its Step 10, capture the NUL-separated status bytes using the path-handling rule above; immediately after that dispatch returns, capture them again. Compare the before/after maps of pathname bytes to two-byte status; every path with a new or different status joins `FIX_PATHS`. Relay QA's summary, `**Result:**` line and recovery wording as it prints them: its `Changes remain uncommitted for your control.` describes the tree before sub-step 7. Do not substitute another testing tool or skill: QA is `qa:run` or none.
5. `QA_RESULT`:
   - the run printed the engine `summary` → its `**Result:**` value (`Pass`, `Fail`, `Budget Exhausted` or `Stopped`); `QA_REPORT` is the `report` path that `run start` returned, made relative to `REPO` (`python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' '<report path>' '<REPO>'`); `QA_NOTE` is `QA_REPORT`, plus the stop reason for `Stopped`;
   - it stopped before `run start` succeeded with the `Generated plan has no executable FE or BE scenarios` message → `Nothing to test`, `QA_NOTE`: `the generated plan has no FE or BE scenarios`;
   - it stopped before `run start` succeeded for any other reason (declined bootstrap or trust, invalid config, failed plan generation, an open blocker, plan check) → `Not run`, `QA_NOTE`: the first line of its stop message.
6. `Fail`, `Budget Exhausted` or `Stopped` → use AskUserQuestion: `QA ended with <QA_RESULT>. What now?` with options `Continue to the final review` and `Stop delivery`. `Stop delivery` → leave the working tree as it is, print the `QA:` line of sub-step 8, mark `QA` completed, run **5. Summary** and end the run.
7. **QA changes.** `git reset -q` (nothing QA staged survives; the working tree is untouched), then capture and parse `git status --porcelain=v1 -z --no-renames --untracked-files=all` using the path-handling rule above. First set aside the paths delivery never commits, whatever list they are on: anything under `docs/testing/reports/screenshots/` or `docs/testing/reports/responses/` (evidence; QA's guide keeps it out of version control because it can hold user data), `.av/local.toml`, `.av/secrets.local.env`, and `*.bak` files under `docs/testing/`. Sort the remaining status paths into four groups, each a list of exact pathname bytes:
   - fixes: the paths of `FIX_PATHS` that the status lists;
   - configuration: `.av/config.toml` and `.gitignore` when the status lists them (nothing else under `.av/`);
   - documents: the status paths matching `docs/testing/plans/*.md`, `docs/testing/reports/*.md` or `docs/testing/reports/*-loop-state.json` (the plan, the report and the engine's durable sidecar, files directly in those directories);
   - other: every remaining path — service or application output, anything unexpected. Together with the set-aside paths, print `QA left changes delivery does not commit: <paths>` when there is any, and leave them all in the tree.

   Each path joins the first group that claims it: fixes, then configuration, then documents, then other.

   For each non-empty group of the first three, in this order: use the Python driver to write a group file in that private temporary directory with `group_file.write_bytes(b"".join(path + b"\0" for path in paths))`, where `group_file` is a `Path`; it prints the group file's path as `G`. Run `git --literal-pathspecs add --pathspec-from-file='<G>' --pathspec-file-nul` with that literal temporary path, never with a filename from status. Then capture `git diff --cached --name-only --no-renames -z` as bytes and split only on NUL. Compare its pathname set with the group's exact byte set; commit only when they match. `--literal-pathspecs` also prevents glob or `:(...)` pathspec interpretation. A failed capture/write/add, a different cached set or a failed commit → print the error and stop.
   - fixes:
     ```bash
     printf '%s\n' 'fix: apply QA fixes of delivery <SLUG>' '' 'Delivery-Plan: <PLAN_PATH>' 'Delivery-QA: <QA_REPORT>' 'Delivery-QA-Result: <QA_RESULT>' | AV_COMMIT_SKILL=1 git commit -F -
     ```
   - configuration: `AV_COMMIT_SKILL=1 git commit -m 'chore: add QA configuration for delivery <SLUG>'`.
   - documents: `AV_COMMIT_SKILL=1 git commit -m 'docs: add QA plan and report of delivery <SLUG>'`.
8. Print `QA: <QA_RESULT> (<QA_NOTE>)`. Mark `QA` completed.

### 5. Summary

Print the table `Task | Agent | Routing | Fix rounds | Result`, one row per task handled in this run, then the `Verification:` lines and the `QA:` line; a run that stopped before step 4 prints `QA: Not run (delivery stopped before QA)` as that line. The `Routing` column holds the routing source.

### 6. Final review

Mark `Final code review` in progress.

- Invoke the Skill tool with skill `code-review:review` and these args, then carry out the review it loads completely:
  ```
  Changes on branch <BRANCH> in <BASE>..HEAD (git diff <BASE>..HEAD), delivered from <PLAN_PATH>. Review only these changes.
  ```
  When the Skill tool has no `code-review:review`, print `Install code-review@av-marketplace and run /code-review:review.` and end. Do not substitute another review skill or command, such as Claude Code's built-in `code-review`: the final review is `code-review:review` or none.
- If the review saved a report, run `git check-ignore -q -- '<report path>'`. Exit 0 means git ignores the report: leave it uncommitted. Otherwise commit it before anything else touches it: `git add -- '<report path>'`, then `AV_COMMIT_SKILL=1 git commit -m 'docs: add review of delivery <SLUG>' -- '<report path>'`. Commit only that path. If adding or committing fails, print git's output and stop.

Mark `Final code review` completed.

### 7. Fix offer

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

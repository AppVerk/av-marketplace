---
name: "delivery:orchestration"
description: "Internal procedures of the delivery plugin: the delivery run, plugin roots, routing, the per-task loop."
hide: true
---

# Delivery orchestration

Procedures of the delivery plugin. The delivery extension starts the **Delivery run** when a plan with `### Task` headings is approved in plan mode; `/delivery:execute` starts it for a plan file. The Delivery run uses the other sections. Values in `<ANGLE_BRACKETS>` come from the caller.

## Delivery run

Inputs: `PLAN_SOURCE` — the plan as the caller gave it: a `local://` URL or a file path; `PLAN_FILE` — the plan's absolute file path, when the caller knows it.

Run the steps in order. Every `stop` prints its message and ends the run.

### 1. Preflight

1. Run **Plugin roots**. Keep the `code-review` root.
2. `REPO=$(git rev-parse --show-toplevel)`. A failure → stop with `Delivery needs a git repository.` Step 3 resolves paths from the session's working directory. Run every command after step 3 from `$REPO`.
3. **Plan file.**
   - `PLAN_FILE` given → keep it.
   - `PLAN_SOURCE` is a `local://` URL and no `PLAN_FILE` is given → leave `PLAN_FILE` unset.
   - Otherwise `PLAN_FILE=$(realpath "$PLAN_SOURCE")`; a failure → stop with `Plan not found: <PLAN_SOURCE>.`
   - `PLAN_FILE` inside `$REPO/` → `PLAN_PATH` is its path relative to `REPO`. Otherwise step 7 sets `PLAN_PATH`.
4. **Slug.**
   ```bash
   SLUG=$(python3 -c 'import re,sys; s=sys.argv[1].rsplit("/",1)[-1].lower().removesuffix(".md"); s=re.sub(r"[^a-z0-9]+","-",s).strip("-"); s=re.sub(r"^\d{4}-\d{2}-\d{2}-","",s); print(re.sub(r"-plan$","",s) or "plan")' "$PLAN_SOURCE")
   ```
5. **Other changes.** When `PLAN_PATH` is set, run `git status --porcelain --untracked-files=all -- . ":(exclude,literal)$PLAN_PATH"`; otherwise run `git status --porcelain --untracked-files=all`. Any output → stop with `Commit or stash your other changes before delivery, then retry <PLAN_SOURCE>.` Nothing below runs on this path.
6. **Current branch.** `BRANCH=$(git branch --show-current)`; empty (detached HEAD) → stop with `Check out a branch first.`
7. **Save the plan** when `PLAN_PATH` is not set yet:
   ```bash
   DATE=$(date +%F); P="docs/plans/$DATE-$SLUG.md"; n=2
   while [ -e "$P" ]; do P="docs/plans/$DATE-$SLUG-$n.md"; n=$((n+1)); done
   mkdir -p docs/plans
   ```
   `PLAN_PATH=$P`. With `PLAN_FILE`, run `cp "$PLAN_FILE" "$PLAN_PATH"`. Without it, `read <PLAN_SOURCE>:raw` and `write` that exact text to `PLAN_PATH`. The file stays untracked until step 10.
8. **Plan check.** `CHECK=$(python3 "$ROUTER" check "$REPO" "$PLAN_PATH")`; a non-zero exit → stop with the router's error. When its JSON `tasks` is 0 → stop with `Delivery cannot run <PLAN_PATH>: it has no '### Task N: <title>' headings.` When its JSON `problems` list is not empty → stop with one line per problem:
   ```
   Delivery cannot run <PLAN_PATH>:
   - <problem>
   Fix these tasks in <PLAN_PATH>, then run /delivery:execute <PLAN_PATH>.
   ```
   A plan saved in step 7 stays where it is. Entries of `no_files` are not problems: step 14 routes those tasks.
9. **Delivery branch.** `BRANCH` is `main` or `master` → create the first free delivery branch; the untracked plan comes along.
   ```bash
   B="delivery/$SLUG"; n=2
   while git rev-parse --verify --quiet "refs/heads/$B" >/dev/null; do B="delivery/$SLUG-$n"; n=$((n+1)); done
   git switch -c "$B"
   ```
   `BRANCH` becomes `$B`.
10. **Commit the plan** when `git status --porcelain -- "$PLAN_PATH"` prints anything. A plan that git ignores and does not track prints nothing, so it stays uncommitted. The subject is `docs: update delivery plan <SLUG>` when `git ls-files --error-unmatch -- "$PLAN_PATH"` succeeds, otherwise `docs: add delivery plan <SLUG>`. Run `git add -- "$PLAN_PATH"`, then `AV_COMMIT_SKILL=1 git commit -m "<subject>" -- "$PLAN_PATH"`. A failed commit → print git's output and stop. The AV_COMMIT_SKILL=1 prefix lets the Commit plugin's git commit guard pass delivery's commits; keep it on every commit delivery makes.
11. If `git status --porcelain` prints anything → stop with `Commit or stash your other changes, then run /delivery:execute <PLAN_PATH>.`
12. `TASKS` = JSON output of `python3 "$ROUTER" plan "$REPO" "$PLAN_PATH"`; a non-zero exit → stop with the router's error.
13. **Done tasks and base.** `DONE=$(python3 "$ROUTER" done "$REPO" "$PLAN_PATH")`; a non-zero exit → stop with the router's error. When its `conflicts` list is not empty → stop, printing one line per entry: `Task <task> is committed as "<committed_title, or missing>" in <commit>, but <PLAN_PATH> titles it "<plan_title>". Restore the title or drop the commit, then run /delivery:execute <PLAN_PATH>.` Mark no task done on this path. Otherwise the tasks listed in `done` are done and `BASE` is its `base`.
14. Route every not-done task with **Routing**. For a task whose `source` is not `files`, `TASK_TEXT` is its `block`. Print the `Routing: task <N> → <agent> (source: <source>)` line for every task in your reply before starting step 2; it is the audit trail of each routing decision.
15. Every routed agent must be listed among the `task` tool's available agents. A missing one → stop with `Install <plugin>: omp plugin install <plugin>@av-marketplace, then start a new session.` (`<plugin>` is the part before `:`).
16. `todo init` with one item per not-done task, `Task <N>: <title>`, then `Plan verification` and `Final code review`.

If every task is already done, print `All tasks of <PLAN_PATH> are delivered.` and go to step 3.

### 2. Tasks

For each not-done task, in ascending order of `N`:

1. Mark its todo item in progress. Run **Task loop** with `N`, `TASK_BLOCK` = the task's `block`, `AGENT` = its routed agent, `PLAN_PATH`, `BRANCH`.
2. Act on the result:
   - `stopped` → run step 4 and end the run;
   - `skipped` → mark the todo item done and note `skipped` in the summary;
   - `approved` or `accepted-with-open-findings` → build the commit message first: `MSG=$(python3 "$ROUTER" message "$REPO" "$PLAN_PATH" <N>)`; for `accepted-with-open-findings` add `--open-findings` after `<N>`. A non-zero router exit → print the router's error and stop without committing. Otherwise commit the staged changes with `printf '%s' "$MSG" | AV_COMMIT_SKILL=1 git commit -F -`. Mark the todo item done only after the commit succeeds.
   - A failed commit (for example a rejecting hook) → print git's output and stop.

### 3. Verification

Mark `Plan verification` in progress. When `PLAN_PATH` has a `## Verification` section, carry out each check it lists, in order, with your own tools — commands, scripts, smoke runs — without editing project files. A check that needs a person, such as a manual UI step you cannot perform, is `manual`. Print one line per check:

```
Verification: <check> — pass | fail | manual (<evidence>)
```

Without a `## Verification` section, print `Verification: none in plan`. Any `fail` → use the `ask` tool: `Verification failed: <checks>. What now?` with options `Continue to the final review` and `Stop delivery`. `Stop delivery` → run step 4 and end the run. Mark `Plan verification` done.

### 4. Summary

Print the table `Task | Agent | Routing | Fix rounds | Result`, one row per task handled in this run, then the `Verification:` lines. The `Routing` column holds the routing source.

### 5. Final review

Mark `Final code review` in progress.

- `code-review` root is `null` → print `Install code-review@av-marketplace and run /code-review:review.` and end.
- Otherwise `read <code-review root>/commands/review.md` and carry it out completely, as if it had been invoked with this argument in place of its `$ARGUMENTS`:
  ```
  Changes on branch <BRANCH> in <BASE>..HEAD (git diff <BASE>..HEAD), delivered from <PLAN_PATH>. Review only these changes.
  ```

- If the review saved a report, run `git check-ignore -q -- "<report path>"`. Exit 0 means git ignores the report: leave it uncommitted. Otherwise commit it before anything else touches it: `git add -- "<report path>"`, then `AV_COMMIT_SKILL=1 git commit -m "docs: add review of delivery $SLUG" -- "<report path>"`. Commit only that path. If adding or committing fails, print git's output and stop.

Mark `Final code review` done.

### 6. Fix offer

If the review saved a report, use the `ask` tool: `Run /code-review:fix-all on <report path>?` with options `Yes` and `No`. On `Yes`, `read <code-review root>/commands/fix-all.md` and carry it out completely with `$ARGUMENTS` = the report path. Whatever it changes, including the statuses it writes into the report, stays uncommitted: end with `Review fixes are uncommitted; review them and commit.` Without a saved report, end the run.

## Plugin roots

Run:

```bash
omp plugin list --json | python3 -c 'import json,sys; want=sys.argv[1:]; d=json.load(sys.stdin); r={p["id"]: p["entries"][0]["installPath"] for p in d.get("marketplace", []) if p.get("entries") and not p.get("shadowedBy")}; print(json.dumps({w: r.get(f"{w}@av-marketplace") for w in want}))' delivery code-review
```

- `delivery` is `null` → stop with `Install delivery: omp plugin install delivery@av-marketplace`.
- Otherwise `ROUTER` is `<delivery root>/scripts/route_task.py`; use it through `python3 "$ROUTER" ...`.
- Keep the `code-review` root; `null` means code-review is not installed.

The router prints JSON:

- `check "$REPO" <plan>` → `{"tasks": N, "problems": [...], "no_files": [...]}`. `problems` are plan errors that stop a run; `no_files` names tasks without a **Files:** block, which **Routing** handles.
- `plan "$REPO" <plan>` → one entry per task with `task`, `title`, `commit`, `block`, `files`, `groups`, `stack`, `agent`, `source`, `evidence`. `source` is `files` when the task's file list decided `agent`; for a task without files the router decides from the task text: `text` when its code paths and fenced code languages favor one stack (`evidence` lists the votes), `default` when they favor none and `agent` is `delivery:implementer`.
- `message "$REPO" <plan> <N> [--open-findings]` → the commit message of task N with its `Delivery-*` trailers.
- `done "$REPO" <plan>` → `{"done": [...], "conflicts": [...], "base": "<sha>"}` from the branch's delivery commits.

## Routing

Decide the implementer for each task. Never ask the user which agent to use: every task ends with an agent from the steps below.

- `source` is `files` → use the entry's `agent`. Source: `files`.
- Otherwise (the task lists no files):
  1. Run `python3 "$ROUTER" layout "$REPO"` and keep its JSON as `LAYOUT`. If `LAYOUT["stacks"]` is empty → go to step 4.
  2. Run this in the `eval` tool (python). Set `LAYOUT` to that JSON and `TASK_TEXT` to the task text:
     ```python
     CRIT = {"python": "Python code or its tests.", "frontend": "React/TypeScript web app code or its tests.", "php": "PHP code or its tests."}
     crit = {s: CRIT[s] for s in LAYOUT["stacks"]}
     crit["generic"] = "Work outside those stacks: docs, CI, repo configuration, Node tooling without React."
     crit["split"] = "The task needs changes in two or more of the stacks above."
     Q = {"route": {"type": "choice", "instructions": "Pick the implementer for this task given the repository layout. One task should touch one stack.", "criteria": crit}}
     state = "Repository layout:\n" + "\n".join(LAYOUT["lines"]) + "\n\nTask:\n" + TASK_TEXT
     b = judge_batch({"t": state}, Q, intent="Routing a delivery task")
     got = []
     for _ in range(3):
         got = await b.drain(timeout=60)
         if got:
             break
     model = b.status()["model"]
     item = got[0][1] if got else None
     answer = item.answers["route"] if item is not None and not getattr(item, "error", None) else None
     print({"model": model, "answer": answer, "error": getattr(item, "error", None) if item is not None else "no answer"})
     ```
  3. Accept `answer["choice"]` only when all of these hold:
     - `answer` is not `None`;
     - `"jev" in model.lower()`;
     - `answer["choice"] != "split"`;
     - `answer["confidence"] >= 0.8`.

     The agent is `python` → `python-developer:developer`, `frontend` → `frontend-developer:developer`, `php` → `php-developer:developer`, `generic` → `delivery:implementer`. Source: `jev p=<confidence, 2 decimals> via <model>`.
  4. Otherwise use the entry's `agent`, decided by the router from the task text. Source: `text (<evidence joined with "; ">)` when the entry's `source` is `text`, otherwise `default`.

For every routed task, print exactly one line:

```
Routing: task <N> → <agent> (source: <source>)
```

## Task loop

Inputs: `N`, `TASK_BLOCK`, `AGENT`, `PLAN_PATH`, `BRANCH`. `PLUGIN` is the part of `AGENT` before `:` when `AGENT` is a developer agent (`python-developer`, `frontend-developer`, `php-developer`), otherwise `none`.

Every dispatch below is one `task` tool call with one item. Its result arrives on its own; if you have nothing else to do until then, call the `wait` tool. Use this `context` for every item:

```
Delivery of <PLAN_PATH> on branch <BRANCH>. One task per agent; the orchestrator reviews and commits.
```

1. `TASK_BASE=$(git rev-parse HEAD)`.
2. **Implement.** Dispatch `AGENT` with the **Implementer template**.
3. **Stage.** First run `CURRENT_BRANCH=$(git branch --show-current)`. If `CURRENT_BRANCH` differs from `BRANCH`, print `Delivery stopped: expected branch <BRANCH>, current branch <CURRENT_BRANCH or detached HEAD>.` and return result `stopped` without resetting or staging. If `git rev-parse HEAD` differs from `TASK_BASE`, the agent committed: run `git reset --soft "$TASK_BASE"`. Then run `git add -A`.
4. **Nothing to review?** If `git diff --cached --quiet` succeeds (no changes), or the report's `**Status:**` line contains `❌`, use the `ask` tool:
   - question: `Task <N> produced <no changes | a ❌ Failed report>. What now?`
   - `Retry once` → go back to step 2. Allowed once per task; after a retry, offer only the other two options;
   - `Skip this task` → `git stash push --include-untracked -m "delivery: skipped task <N>"` and return result `skipped`;
   - `Stop delivery` → leave the tree as it is and return result `stopped`.
5. **Review, round `r = 0`.** Dispatch `delivery:task-reviewer` with the **Reviewer template**. Its structured output is `{verdict, findings}`. The review is blocking when any finding has severity `critical` or `important`, whatever `verdict` says.
6. **Fix rounds.** While the review is blocking and `r < 3`:
   - `r = r + 1`;
   - dispatch `AGENT` with the **Fix template**, passing the blocking findings;
   - repeat step 3;
   - dispatch `delivery:task-reviewer` again with the Reviewer template and the previous findings.
7. **Still blocking after round 3** → use the `ask` tool:
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

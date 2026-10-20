---
description: "Deliver or resume a plan file: each task goes to the developer agent the router picks, is reviewed and committed, then the plan's verification, QA when the change is testable, and the full code review run. Superpowers plans sent to subagent-driven execution and plans approved in plan mode start this automatically."
argument-hint: "<plan path>"
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
  - Bash(AV_COMMIT_SKILL=1 git commit *)
  - Bash(printf *)
  - Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/route_task.py *)
  - "Bash(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' *)"
---

# Delivery: execute

Invoke the Skill tool with skill `delivery:orchestration` and args `$ARGUMENTS`, then carry out its Delivery run.

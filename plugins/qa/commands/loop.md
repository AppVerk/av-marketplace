---
allowed-tools: Bash(find:*), Bash(ls:*), Bash(head:*), Bash(cat:*), Bash(mkdir:*), Bash(date:*), Bash(command:*), Bash(echo:*), Bash(git:*), Bash(shasum:*), Bash(jq:*), Bash(cp:*), Bash(mv:*), mcp__plugin_playwright_playwright__browser_navigate, Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput, Skill, AskUserQuestion
description: Closed test-fix-retest loop — run a QA plan, auto-fix failures via fix-auto, re-run affected sections, and repeat until green or budget exhausted.
model: opus
argument-hint: [plan path] [--mode approve|auto|step] [--max-iterations N] [--max-dispatches D] [--time-budget S] [--severity LEVEL] [--allow-mutations] [--allow-host HOST]
---

# QA Loop Command

Execute a closed test → fix → retest loop. Runs a QA plan, identifies failures, auto-fixes issues via `code-review:fix-auto`, re-runs affected scenarios, and repeats until all issues pass or the budget is exhausted.

This command orchestrates existing agents (`qa:fe-tester`, `qa:be-tester`, `code-review:fix-auto`) and applies strict safety guards (environment, mutation, budget) to prevent uncontrolled loops.

## Arguments

**Input:** `$ARGUMENTS`

| Argument | Interpretation | Default | Rules |
|----------|---|---|---|
| (empty) | Find the newest plan in `docs/testing/plans/` | — | If no plan found, print "Run `/qa:create-plan` first." and stop |
| `<path>` | Use the specified test plan file | — | File must exist and be readable |
| `--mode` | Loop mode: `approve` (batch HITL), `auto` (headless), `step` (per-fix HITL) | `approve` | Case-sensitive; unknown value → error listing valid modes; stop |
| `--max-iterations` | Maximum loop iterations | 3 | Must be positive integer; invalid → error; stop |
| `--max-dispatches` | Maximum fix-auto + tester launches combined | 50 | Must be positive integer; invalid → error; stop |
| `--time-budget` | Wall-clock seconds before timeout | 1800 | Must be positive integer; invalid → error; stop |
| `--severity` | Minimum severity to credit as fixed: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` | (none = all) | Case-insensitive; normalized to uppercase; unknown value → error; stop |
| `--allow-mutations` | Permit state-changing BE scenarios (POST/PUT/PATCH/DELETE, DB writes) | (off) | Present → on; absent → off; no value needed |
| `--allow-host` | Whitelist additional hosts beyond loopback | (loopback only) | Repeatable; each invocation appends; format: hostname or IP |

**Validation timing:** All arguments are validated **before any I/O** (mirror `/fix-all` Step 0). Exit on any error.

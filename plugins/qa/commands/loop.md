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

---

## Workflow

### Step 1: Create Progress Tasks

Use TaskCreate to set up progress tracking:

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Validate & resolve | Validating arguments... |
| 2 | Baseline run | Running baseline tests... |
| 3 | Loop iterations | Running iteration N/M... |
| 4 | Final run | Final verification run... |
| 5 | Write report | Writing final report... |

**After creating all tasks:** Mark task 1 as `in_progress` using TaskUpdate.

---

### Step 0: Resolve & Validate

#### Step 0.1: Parse Arguments

Split `$ARGUMENTS` on whitespace. Extract:
- `plan_path` — first non-flag token (or empty)
- Flags: validate each `--flag value` or `--flag-name` pairs

**Validation errors (before any I/O):**

1. **Unknown `--mode`:** if present and not in {`approve`, `auto`, `step`}:
   > Error: Unknown mode 'X'. Valid modes: approve, auto, step

2. **Invalid positive integers:** if `--max-iterations`, `--max-dispatches`, or `--time-budget` are not positive integers:
   > Error: --<flag> must be a positive integer, got 'X'

3. **Unknown `--severity`:** if present and not in {`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`} (case-insensitive):
   > Error: Unknown severity 'X'. Valid levels: CRITICAL, HIGH, MEDIUM, LOW

If any validation fails, print the error and stop immediately.

#### Step 0.2: Resolve Plan Path

If `plan_path` is empty:

```bash
plan_path=$(ls -t docs/testing/plans/*.md 2>/dev/null | head -1)
```

If `plan_path` is still empty:

> No test plans found in `docs/testing/plans/`. Run `/qa:create-plan` first.

Stop execution.

If `plan_path` is not empty, verify it is readable (Read tool will error if not).

#### Step 0.3: Base-URL Resolution (Fail-Closed)

Probe for the base URL in this order; stop at the first non-empty match:

1. **Explicit URLs in the plan:** Read `plan_path` and extract URLs from the `## Source` section or scenario headers (look for `http://` or `https://` patterns). Take the first match.
2. **`QA_BASE_URL` env var:** Check if set and non-empty.
3. **Project config:** Best-effort probe (check for `.env`, `vite.config.ts`, or other project-specific config files for a base URL).

If **none of these resolve a base URL**, abort:

> Error: Base URL undetectable. Cannot guarantee loopback-only safety. Explicitly set QA_BASE_URL, add URLs to the plan's ## Source section, or use --allow-host.

Stop execution.

#### Step 0.4: Environment Guard

Parse the base URL to extract its hostname. Check:

- Is the hostname in {`localhost`, `127.0.0.1`, `::1`} or matches `*.localhost`?
- Is the hostname in the `--allow-host` list?

If neither:

> Error: Base URL resolves to non-loopback host 'X' and is not in --allow-host. Loopback-only safety enforced. Add --allow-host X to override.

Stop execution.

#### Step 0.5: Hash the Plan & Init Counters

```bash
PLAN_HASH=$(shasum -a 256 "<plan_path>" | cut -d' ' -f1)
dispatch_count=0
start_time=$(date +%s)
```

**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

---

### Step 1: Resolve Report + Sidecar (Idempotency)

Read the test plan file to extract the **topic** (the `<topic>` portion of the plan filename, e.g., for `2026-06-17-user-auth-test-plan.md`, topic is `user-auth`).

#### Step 1.1: Locate Existing Report & Sidecar

```bash
report_file=$(ls -t docs/testing/reports/*-<topic>-report.md 2>/dev/null | head -1)
sidecar_file="docs/testing/reports/<topic>-loop-state.json"
```

#### Step 1.2: Sidecar Idempotency Logic

**Case 1: Sidecar exists and hash matches**

```bash
if [ -f "$sidecar_file" ]; then
  stored_hash=$(jq -r .plan_sha256 "$sidecar_file")
  if [ "$stored_hash" = "$PLAN_HASH" ]; then
    # REUSE — load scenario→QA-ID map and existing IDs/Status
    # Continue with the existing report in place
  fi
fi
```

Read the sidecar and extract `scenario_issues` (scenario-id → [QA-IDs]) and the report's existing `**Status:**` lines. New issues will be assigned IDs at `max(existing_ids) + 1`.

**Case 2: Sidecar absent but report exists**

If `report_file` exists but `sidecar_file` does not:

```bash
# ADOPT — import QA-XXX IDs and Status lines from the report
# Create a fresh sidecar stamped with the current PLAN_HASH
```

Read the report, extract all `### [SEVERITY] QA-NNN:` headings and any `**Status:**` lines, and build the `scenario_issues` map and `baseline` map. Create the sidecar with these values.

**Case 3: Hash mismatch**

If `sidecar_file` exists but `stored_hash != PLAN_HASH`:

```bash
cp "$report_file" "${report_file%.md}.bak"
cp "$sidecar_file" "${sidecar_file%.json}.bak"
# Start FRESH with no prior IDs or Status lines
```

**Case 4: No prior artifacts**

Initialize fresh report/sidecar filenames and start with `qa_count = 0` in the report-format logic.

#### Step 1.3: Initialize Sidecar

Create or update the sidecar JSON file with this exact schema:

```json
{
  "plan_sha256": "<64-hex-from-PLAN_HASH>",
  "plan_path": "docs/testing/plans/2026-06-17-user-auth-test-plan.md",
  "report_file": "docs/testing/reports/2026-06-17-user-auth-report.md",
  "topic": "user-auth",
  "created": "2026-06-17",
  "scenario_issues": { "BE-03": ["QA-001", "QA-002"], "FE-05": ["QA-003"] },
  "baseline": { "FE-01": "pass", "BE-03": "fail", "FE-05": "fail" },
  "dispatch_count": 0,
  "iterations": []
}
```

- `plan_sha256`: the 64-hex SHA-256 hash of the plan file
- `plan_path`: path to the test plan
- `report_file`: path to the QA report (no `docs/testing/reports/` prefix in the sidecar; store absolute or relative from root)
- `topic`: extracted from the plan filename
- `created`: date stamp (YYYY-MM-DD)
- `scenario_issues`: map of scenario-id → array of QA-XXX IDs assigned to that scenario
- `baseline`: map of scenario-id → "pass" | "fail" | "skip" (recorded after Step 2)
- `dispatch_count`: incremented each time a fix-auto or tester is launched
- `iterations`: array of iteration results (appended in Step 3e)

The sidecar is **real JSON**, read/written via Read/Write/Edit tools, and queried with `jq`.

**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

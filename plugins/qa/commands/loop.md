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

**Validation timing:** All **flag** arguments (`--mode`, `--max-iterations`, `--max-dispatches`, `--time-budget`, `--severity`, `--allow-mutations`, `--allow-host`) are validated before any I/O (mirror `/fix-all` Step 0). Plan-path resolution legitimately performs I/O. Exit on any validation error.

---

## Workflow

### Create Progress Tasks

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

---

### Step 2: Baseline Run

#### Step 2.1: Launch Testers

Load the `report-format` skill:

```
Skill(skill: "report-format")
```

Parse the plan to identify FE and BE scenarios. Launch both in parallel if both exist:

**If FE scenarios exist:**

Apply the mutation guard: if a scenario contains a POST/PUT/PATCH/DELETE request in the plan **and** `--allow-mutations` is not set, mark it to SKIP with reason `mutation-guard` in the results (do not execute it).

```
Task(
  subagent_type: "qa:fe-tester",
  run_in_background: true,
  description: "Execute FE test scenarios (baseline)",
  prompt: "Execute all FE test scenarios from this plan:

<paste all FE-XX scenarios from the plan>

Base URL: <resolved from Step 0.3>

Follow the fe-testing skill patterns. For each scenario that should run, execute it and report PASS/FAIL/SKIP.

Scenarios marked mutation-guard should return SKIP with reason 'mutation-guard'.

Return results for every scenario."
)
```

**If BE scenarios exist:**

Apply the mutation guard: if a scenario specifies a state-changing HTTP method (POST/PUT/PATCH/DELETE) or a DB-write check in the plan **and** `--allow-mutations` is not set, mark it to SKIP with reason `mutation-guard`.

```
Task(
  subagent_type: "qa:be-tester",
  run_in_background: true,
  description: "Execute BE test scenarios (baseline)",
  prompt: "Execute all BE test scenarios from this plan:

<paste all BE-XX scenarios from the plan>

Base URL: <resolved from Step 0.3>
DB connection: <detect from plan or project config>

Follow the be-testing skill patterns. For each scenario that should run, execute it and report PASS/FAIL/SKIP.

Scenarios marked mutation-guard should return SKIP with reason 'mutation-guard'.

Return results for every scenario."
)
```

Collect results with:

```
fe_results = TaskOutput(fe_tester_id, block: true)  # if FE was launched
be_results = TaskOutput(be_tester_id, block: true)  # if BE was launched
```

Baseline launches count toward the budget:

```
dispatch_count += (1 if FE launched) + (1 if BE launched)
```

Every tester launch counts toward `--max-dispatches`.

#### Step 2.2: Render Report (report-format Step 6)

Using the `report-format` skill, build the QA-XXX report:

1. **Count results:** tally pass/fail/skip across all scenarios.
2. **Assign QA-XXX IDs:**
   - If reusing a prior report (Step 1, Case 1), use the existing scenario→QA-ID map; assign new IDs at `max(existing) + 1`.
   - If adopting a report (Step 1, Case 2), use the extracted IDs; new ones at `max(existing) + 1`.
   - If fresh (Step 1, Cases 3–4), start at `qa_count = 0` and assign sequentially: QA-001, QA-002, etc.
3. **Determine severity** for each failure (per the report-format skill guidance).
4. **Derive issue fields:** Location, Category, Problem, Remediation, Impact (per report-format).
5. **Build the report** following the report-format exact template.

#### Step 2.3: Update Sidecar with Baseline

Edit the sidecar to record:

```json
{
  ...
  "baseline": {
    "FE-01": "pass",
    "FE-02": "fail",
    "BE-03": "fail",
    "BE-04": "skip"
  },
  "scenario_issues": {
    "FE-02": ["QA-001"],
    "BE-03": ["QA-002", "QA-003"]
  }
}
```

#### Step 2.4: Zero-Failure Exit

Count failures at or above `--severity` (default: all):

- If **zero failures** → print:

> All passing, nothing to fix.

  Skip the loop (Step 3) AND the final run (Step 4), and exit success.

- If **all scenarios are SKIP** (no executable verifier) → abort:

> Error: No executable verifier — cannot gate (all scenarios marked SKIP or unavailable). Check your test plan and tool availability.

  Stop execution.

#### Step 2.5: Save Report

Write the report to `docs/testing/reports/<YYYY-MM-DD>-<topic>-report.md` using the Write tool.

Write the sidecar to `docs/testing/reports/<topic>-loop-state.json` using the Write tool.

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

---

### Step 3: Loop Iterations

Bounded loop (condition checked at iteration start):

```
while (still-failing scenarios exist at/above --severity)
  AND (iteration < --max-iterations)
  AND (dispatch_count < --max-dispatches)
  AND (elapsed < --time-budget)
```

#### Step 3.0: Check Loop Conditions

Compute `elapsed = $(date +%s) - start_time`. If elapsed >= `--time-budget`:

> Time budget exhausted. Stopping loop.

Exit the loop.

#### Step 3a: Select & Pre-Filter Fix-Set

From the sidecar `baseline` and `scenario_issues`:

1. Identify all scenarios still failing (baseline == "fail" or later iteration status == "fail").
2. For each failing scenario, extract its QA-XXX issues.
3. Filter by `--severity` (keep issues at or above the floor).
4. Pre-filter: drop any issue with:
   - **Location field is `unknown:0`** or missing entirely
   - **Missing fix-auto-required fields** (Location, Problem, Remediation)
   
   For dropped issues, record: `needs manual location` or `incomplete fields`. Never dispatch them.

Call this list `fix_candidates`.

#### Step 3b: HITL Gate Per Mode

**Mode: `approve` (default)**

Show the fix-set to the user using a single `AskUserQuestion`:

```
question: "Approve fixing N issues on Y scenarios? (Iteration Z/M)"
options:
  - label: "Approve & continue"
    description: "Proceed with fixes"
  - label: "Skip to final run"
    description: "Stop fixing, run final verification"
  - label: "Abort"
    description: "Cancel the loop"
```

Also display:
- List of issues (ID, severity, scenario, title)
- Anti-hardcoding warnings (if any from prior iterations)
- Target host (the resolved base URL)

If user selects "Skip to final run" → jump to Step 4 (skip remaining iterations).
If user selects "Abort" → exit immediately with partial report.
If user selects "Approve & continue" → proceed to Step 3c.

**Mode: `auto`**

Print a text scope banner showing the fix-set (failures, dispatch budget, target host), then proceed to Step 3c without a gate. Abort is via session interrupt (Esc).

**Mode: `step`**

Per iteration, approve fixes before each re-test (after Step 3c, before Step 3d). Use `AskUserQuestion` with:

```
question: "Re-run affected sections with fixes?"
options:
  - label: "Yes"
    description: "Run fixed scenarios"
  - label: "No — skip to final run"
    description: "Stop fixing"
  - label: "Abort"
    description: "Cancel the loop"
```

**Headless check:** if `--mode approve` or `--mode step` and stdin is not a TTY (non-interactive session):

> Error: approve/step modes require an interactive session. Use --mode auto for headless execution.

Abort.

#### Step 3c: Fix

For each issue in `fix_candidates`, **sequentially**:

```
dispatch_count++

Task(
  subagent_type: "code-review:fix-auto",
  run_in_background: false,
  description: "Auto-fix: [<SEVERITY>] <Issue-ID>: <Title>",
  prompt: "<full issue block from the report, including all fields>

INJECTED CONSTRAINTS FOR THIS FIX:

1. Source-only fix: do not modify the test plan, plan-referenced test files, or test scenarios.
2. Fix only the source code under test.
3. Keep the working tree clean (uncommitted changes only, no staging).
4. If a location-less issue arrives (Location: unknown:0 or missing), return Failed — do not prompt."
)
```

Collect result: **Fixed**, **Partially Fixed**, or **Failed**.

#### Step 3d: Anti-Hardcoding Warning (Per Fix)

After each fix completes, run:

```bash
git diff --unified=0 <touched-files>
```

For each line added (starting with `+`), extract the literal string. For each scenario in `fix_candidates` (the one this issue came from), extract its request-payload value (from the plan). If the added literal **exactly matches** a request-payload value:

Record a **WARNING** for this fix: `"Possible hardcoding: added literal matches scenario request-payload value X"`.

Store the warning in the sidecar `iterations[]` entry (not a blocker — just a human-review flag).

#### Step 3e: Re-Run Section(s)

Identify which section(s) contain still-failing scenarios (FE and/or BE). Re-run the **whole section** (all scenarios in that section, in order):

```
dispatch_count++
Task(
  subagent_type: "qa:fe-tester",
  run_in_background: true,
  description: "Re-run FE section (iteration N)",
  prompt: "<all FE scenarios from the plan; mutation guard applied again>
Base URL: <re-resolve from Step 0.3>
Execute all scenarios in order (dependency-safe)."
)

dispatch_count++
Task(
  subagent_type: "qa:be-tester",
  run_in_background: true,
  description: "Re-run BE section (iteration N)",
  prompt: "<all BE scenarios from the plan; mutation guard applied again>
Base URL: <re-resolve from Step 0.3>
Execute all scenarios in order."
)

fe_results = TaskOutput(fe_tester_id, block: true)  # if FE section re-run
be_results = TaskOutput(be_tester_id, block: true)  # if BE section re-run
```

#### Step 3f: Update Sidecar

After the section re-run, update the sidecar with an entry in `iterations[]`:

```json
{
  "iteration": 1,
  "attempted_fixes": ["QA-001", "QA-003"],
  "now_passing": ["FE-02", "BE-03"],
  "still_failing": ["BE-04"],
  "warnings": ["QA-001: Possible hardcoding — added literal matches scenario payload"],
  "dispatch_count": 3,
  "elapsed_s": 120
}
```

Update the `baseline` map with the latest pass/fail/skip status for each scenario.

#### Step 3g: Append Loop History Row

Append a human-facing row to the report's `## Loop History` section (if it doesn't exist, create it after `## Detailed Results`):

```markdown
## Loop History

| Iteration | Failing in | Now passing | Still failing | Warnings | Regressions | Dispatches |
|-----------|-----------|-----------|-----------|-----------|-----------|-----------|
| 1 | FE-02, BE-03, BE-04 | FE-02, BE-03 | BE-04 | QA-001 ⚠ | — | 3 |
| 2 | BE-04 | BE-04 | — | — | — | 2 |
```

Columns:
- **Iteration** — iteration number
- **Failing in** — scenarios that were failing at iteration start
- **Now Passing** — scenarios that passed this iteration (newly fixed)
- **Still Failing** — scenarios still failing after this iteration
- **Warnings** — comma-separated QA-XXX IDs with warnings (anti-hardcoding flags, "⚠" symbol)
- **Regressions** — scenarios that passed at baseline but failed this iteration
- **Dispatches** — fix + re-run count for this iteration

**DO NOT write `**Status:**` headings yet** — they are written only from the authoritative final run (Step 4).

#### Step 3h: Progress / Oscillation Check

**Progress:** has at least one scenario newly passed this iteration? If **no**, stop (no progress):

> No progress this iteration (no newly passing scenarios). Stopping loop.

Exit loop.

**Regression:** did any previously-passing scenario regress? If **yes**, stop:

> Scenario regression detected (e.g., FE-01 passed at baseline but failed this iteration). Stopping loop to prevent oscillation.

Exit loop.

**Budgets:** check all three:
- `iteration >= --max-iterations` → stop: "Max iterations reached."
- `dispatch_count >= --max-dispatches` → stop: "Max dispatch budget exhausted."
- `elapsed >= --time-budget` → stop: "Time budget exhausted."

After checking, loop back to Step 3.0.

**Task Update:** Periodically update task 3 with the current iteration count.

---

### Step 4: Final Run (Authoritative)

**Skip this step if the zero-failure exit fired in Step 2.4.**

Re-run the **entire plan** (all FE and BE scenarios, in order):

```
dispatch_count++
Task(
  subagent_type: "qa:fe-tester",
  run_in_background: true,
  description: "Final run — FE scenarios",
  prompt: "<all FE scenarios; mutation guard applied>

Base URL: <resolved from Step 0.3>

Execute all scenarios in order. This is the authoritative final run."
)

dispatch_count++
Task(
  subagent_type: "qa:be-tester",
  run_in_background: true,
  description: "Final run — BE scenarios",
  prompt: "<all BE scenarios; mutation guard applied>

Base URL: <resolved from Step 0.3>
DB connection: <detect from plan or project config>

Execute all scenarios in order. This is the authoritative final run."
)

fe_results = TaskOutput(fe_tester_id, block: true)
be_results = TaskOutput(be_tester_id, block: true)
```

#### Step 4.1: Write Status (One-Time, Authoritative)

For each scenario that **PASSES** in the final run:

1. Locate all its QA-XXX headings in the report.
2. For each heading, use the Edit tool to insert immediately after the `### [SEVERITY] QA-XXX: Title` line:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

Use today's date in YYYY-MM-DD format.

**Still-failing scenarios:** leave their issues unmarked (no `**Status:**` line; they remain retryable by a future run).

**`⚠️ Partially Fixed` is never written** — it would freeze issues out of `/fix-report`. The report stays compatible with `/fix` / `/fix-report`.

#### Step 4.2: Handle Regressions

A scenario that passed at baseline (recorded in the sidecar `baseline` map) but fails in the final run is a regression:

1. Create a **new QA-XXX** for the regression (deduped vs. still-open IDs), at `max(existing) + 1`.
2. Record it in the sidecar's `iterations[]` as a "regression" entry.
3. Append a row to the Loop History section (in the `Regressions` column, list the new QA-XXX).
4. Do NOT write `**Status:** Fixed` (it's not fixed; it's a regression).

**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.

---

### Step 5: Final Report & Summary

#### Step 5.1: Compute Summary Stats

- **final_pass_count** — scenarios passing in the final run
- **final_fail_count** — scenarios still failing
- **fixed_count** — scenarios with `**Status:** ✅ Fixed` written
- **warnings_count** — number of issues with anti-hardcoding warnings
- **regressions_count** — number of regressions detected
- **elapsed** — `$(date +%s) - start_time` in seconds

#### Step 5.2: Print Summary

```
## Loop Summary

**Result:** <Pass | Fail | Budget Exhausted | Stopped>

**Final Status:**
- Pass: N | Fail: N | Skip: N
- Fixed (Status written): N
- Remaining unfixed: N
- Warnings: N (anti-hardcoding)
- Regressions: N

**Budget Used:**
- Dispatches: N / <--max-dispatches>
- Iterations: N / <--max-iterations>
- Time: Nm Ns / <--time-budget>s

**Next Steps:**

If issues remain unfixed, use `/fix` to manually fix by ID, or run `/qa:loop` again with different settings (increase budgets, change `--mode`, adjust `--severity`).

To recover uncommitted changes: `git restore .`

**Changes remain uncommitted for your control.**
```

If any issues have warnings, append:

```
**Warnings (manual review recommended):**
- <QA-XXX>: <warning text>
- ...
```

#### Step 5.3: Save Report & Sidecar

Write the updated report (with Loop History and Status lines) to `docs/testing/reports/<YYYY-MM-DD>-<topic>-report.md`.

Write the updated sidecar to `docs/testing/reports/<topic>-loop-state.json` (include the final `iterations[]` entries and updated dispatch_count).

**Task Update:** Mark task 5 as `completed` using TaskUpdate.

---

## Modes & Safety Guards

### Modes Table

| Mode | Behavior | HITL | Headless-Safe |
|---|---|---|---|
| **approve** *(default)* | Single batch approval before fixing; show fix-set + warnings. | Yes (one gate) | No |
| **auto** | No per-batch gate; print scope banner; abort via Esc. | No | Yes |
| **step** | Approve before each re-test. | Yes (per iteration) | No |

**Headless behavior:** if stdin is not a TTY and `--mode approve` or `--mode step` is set → abort with "approve/step require an interactive session; use --mode auto."

### Base-URL Resolution (Fail-Closed)

Resolve in order:

1. Explicit URLs in the plan's `## Source` section or scenario headers
2. `QA_BASE_URL` env var
3. Project config (best-effort)

If none resolve → abort. Cannot guarantee loopback-only safety.

### Safety Guards (Apply in All Modes)

**Environment guard:** resolved host must be loopback (`localhost`, `127.0.0.1`, `::1`, `*.localhost`) or in `--allow-host`, else abort.

**Mutation guard:** state-changing BE scenarios (HTTP POST/PUT/PATCH/DELETE or DB-write checks) SKIP with reason `mutation-guard` unless `--allow-mutations` is set. Issues on skipped scenarios are reported as "needs --allow-mutations"; never counted as fixed.

---

## Error Handling

| Situation | Behavior |
|---|---|
| Invalid args (before I/O) | Clear error message → stop. Examples: unknown `--mode`, non-integer `--max-iterations`, unknown `--severity`. |
| No plan found | Message → `/qa:create-plan` → stop. |
| Base URL undetectable | Abort (fail-closed) — cannot guarantee loopback safety. |
| Non-loopback host (no `--allow-host`) | Abort (environment guard). |
| Mutating BE scenario without `--allow-mutations` | SKIP with reason `mutation-guard`; issue marked "needs --allow-mutations". |
| Tool unavailable (Playwright, curl, DB) | Affected scenarios SKIP / "cannot confirm" (never counted as fixed). If all verifiers unavailable → abort. |
| Entire baseline is SKIP | Abort: "no executable verifier — cannot gate." |
| Zero baseline failures at/above floor | "All passing, nothing to fix" → skip loop AND final run → exit success. |
| Issue `Location: unknown:0` / missing fields | Pre-filtered out; "needs manual location"; never dispatched. fix-auto also returns Failed if a location-less issue arrives. |
| fix-auto fails on an issue | Mark failed for this iteration; keep looping on remaining issues. |
| fix-auto says "Fixed" but re-run still fails | Re-run is authoritative; scenario stays failing. |
| Anti-hardcoding warning | Surfaced for human review (approve mode) / logged (auto mode); not a credit block. |
| No progress / oscillation / budget exceeded | Stop; report remaining issues; suggest `/fix` or another `/qa:loop` run. |
| Regression in final run | New QA-XXX (deduped); reported in Loop History, not auto-fixed. |
| Plan hash mismatch | Mid-run → abort; cross-run → re-baseline (archive prior artifacts to `.bak`). |
| User abort (Esc in auto mode) | Uncommitted changes left; partial report + Loop History so far. |
| Approve/step mode without TTY | Abort: "approve/step require an interactive session; use --mode auto." |

---

## Glossary

- **Scenario-level granularity:** an issue is credited fixed **iff its whole scenario passes**. Intra-scenario partial progress is reported in Loop History but not separately credited.
- **Section-level re-run:** re-run the entire FE and/or BE section containing failures (not individual scenarios). Dependency-safe by construction.
- **Dispatch:** one fix-auto launch or one tester (fe-tester/be-tester) launch. The `--max-dispatches` budget counts both.
- **Verifier authority:** only fresh re-runs (section-level + final) decide pass/fail. fix-auto's verdict is advisory (informs which scenarios to re-run).
- **Sidecar:** a real JSON file (`<topic>-loop-state.json`) holding machine state (plan hash, scenario→QA-ID map, iteration results, dispatch count). The report keeps only human-facing Loop History.
- **Status write-back:** `**Status:** ✅ Fixed (date)` is written exactly once, only from the authoritative final run. No premature `**Status:**` lines.
- **Oscillation:** a scenario regresses (passes at baseline, fails in an iteration). The loop stops to prevent chasing.

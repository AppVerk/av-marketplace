---
allowed-tools: Bash(find:*), Bash(ls:*), Bash(head:*), Bash(cat:*), Bash(mkdir:*), Bash(date:*), Bash(command:*), Bash(echo:*), Bash(git:*), Bash(gh:*), Bash(shasum:*), Bash(jq:*), Bash(cp:*), Bash(mv:*), mcp__plugin_playwright_playwright__browser_navigate, Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput, Skill, AskUserQuestion
description: Closed test-fix-retest loop — run a QA plan, auto-fix failures via fix-auto, re-run affected sections, and repeat until green or budget exhausted.
model: opus
argument-hint: [plan path] [--mode approve|auto|step] [--max-iterations N] [--max-dispatches D] [--time-budget S] [--severity LEVEL] [--allow-mutations] [--allow-host HOST] [--auto-plan] [--no-auto-plan] [--allow-dirty]
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
| `--allow-mutations` | Permit state-changing BE scenarios (POST/PUT/PATCH/DELETE, DB writes) | (off) | Present → on; absent → off; no value needed; **note: test DB must be disposable (no rollback)** |
| `--allow-host` | Whitelist additional hosts beyond loopback | (loopback only) | Repeatable; each invocation appends; format: hostname or IP |
| `--auto-plan` | Force auto-plan generation ON when no plan exists (required to enable it in `--mode auto`) | on in approve/step, off in auto | Valueless presence flag; mutually exclusive with `--no-auto-plan` |
| `--no-auto-plan` | Force auto-plan OFF — restore the dead-stop when no plan exists | — | Valueless presence flag; mutually exclusive with `--auto-plan` |
| `--allow-dirty` | Permit running with uncommitted **tracked** changes (bypass the working-tree gate); suppresses whole-tree recovery hints | (off) | Valueless presence flag; present → on |

**Validation timing:** All **flag** arguments (`--mode`, `--max-iterations`, `--max-dispatches`, `--time-budget`, `--severity`, `--allow-mutations`, `--allow-host`, `--auto-plan`, `--no-auto-plan`, `--allow-dirty`) are validated before any I/O (mirror `/fix-all` Step 0). Plan-path resolution legitimately performs I/O. Exit on any validation error.

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

#### Step 0.1: Parse Arguments & TTY Check

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

4. **Mutually-exclusive auto-plan flags:** if both `--auto-plan` and `--no-auto-plan` are present → `Error: --auto-plan and --no-auto-plan are mutually exclusive` and stop.

5. **Headless check (fail-fast):** if `--mode approve` or `--mode step` and stdin is not a TTY (non-interactive session):
   > Error: approve/step modes require an interactive session. Use --mode auto for headless execution.

If any validation fails, print the error and stop immediately.

Resolve the effective auto-plan setting: `--mode approve`/`step` → ON, `--mode auto` → OFF; `--auto-plan` forces ON, `--no-auto-plan` forces OFF. These three flags are valueless presence flags (like `--allow-mutations`).

#### Step 0.1.5: Working-Tree Safety Gate

The loop auto-fixes source and its recovery guidance is `git restore`, so uncommitted **tracked** changes are at risk. This gate runs after argument validation, before plan resolution — it judges the pre-existing tree. Record the pre-existing tracked-modified set (used later for scoped recovery):

```bash
pre_loop_dirty=$(git -c core.quotePath=false diff --name-only HEAD)   # tracked-modified paths vs HEAD, one FULL path per line (space/quote-safe — do NOT field-split; compare as line-sets)
```

- If `pre_loop_dirty` is non-empty (dirty tree):
  - `--mode auto`: **abort** unless `--allow-dirty` → `Error: Uncommitted changes present; the loop's recovery could discard them. Commit/stash first, or pass --allow-dirty.`
  - `--mode approve`/`step`: **warn + confirm** (proceed / abort) via AskUserQuestion.
- `--allow-dirty` bypasses the abort/confirm in all modes, but `pre_loop_dirty` is **still recorded** (so scoped recovery can subtract it later).

`pre_loop_dirty` is the baseline subtracted in the fix phase to compute the loop's own touched files. **Persist it into the sidecar at Step 1.3** — it is not a durable shell variable, and Step 3g reads it back from the sidecar, so the subtraction survives the many tool calls (baseline, HITL gates, fixes) between here and the fix phase. (`Bash(git:*)` is already in allowed-tools.)

#### Step 0.2: Resolve Plan Path

If `plan_path` is empty:

```bash
plan_path=$(ls -t docs/testing/plans/*.md 2>/dev/null | head -1)
```

If `plan_path` is still empty, branch on the **effective auto-plan setting** resolved in Step 0.1 (`approve`/`step` → ON by default; `auto` → OFF unless `--auto-plan`; `--no-auto-plan` forces OFF):

**Auto-plan OFF** → keep the dead-stop:

> No test plans found in `docs/testing/plans/`. Run `/qa:create-plan` first.

Stop execution.

**Auto-plan ON** → trigger inline generation:

- **`approve`/`step`:** ask once via `AskUserQuestion`:
  ```
  question: "No QA plan found for this branch. Generate one and run the loop?"
  options:
    - label: "Generate & run"
      description: "Generate a branch-vs-default plan, then run the loop"
    - label: "Cancel"
      description: "Stop without generating a plan"
  ```
  If the user selects **Cancel** → stop execution. If **Generate & run** → proceed to Step 0.2.1. *(Headless `approve`/`step` was already aborted in Step 0.1, so this prompt only ever runs interactively.)*
- **`auto` (with `--auto-plan`):** print a **non-silent banner** (always shown, even in headless `--mode auto`) and proceed without a gate:
  > No QA plan found. `--auto-plan` is set: generating a test plan for the current branch (vs the default branch), then continuing the loop.
  Then proceed to Step 0.2.1.

#### Step 0.2.1: Generate Plan Inline (branch-vs-default)

This generates a plan in place of the dead-stop, mirroring `/qa:create-plan` Steps 2–7 but **only the current-branch-vs-default-branch path**. It **skips** create-plan Step 1 (its task scaffold — reuse this loop's tracker) and Step 8 (its "run `/qa:run`" prompt — that contradicts continuing the loop here).

1. **Resolve the default branch** (the `--short` form returns `origin/master`, so the `origin/` strip is required; do **not** use `sed`):

   ```bash
   BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); BASE=${BASE#origin/}
   [ -z "$BASE" ] && git rev-parse --verify main   >/dev/null 2>&1 && BASE=main
   [ -z "$BASE" ] && git rev-parse --verify master >/dev/null 2>&1 && BASE=master
   [ -z "$BASE" ] && BASE=main
   ```

2. **Get the diff + changed files** (source is fixed to current-branch-vs-default — do **not** inline create-plan's PR / `last-N` / staged dispatch):

   ```bash
   git diff "$BASE"...HEAD
   git diff --name-only "$BASE"...HEAD
   ```

3. **Analyze & detect tools.** Classify each changed file as FE or BE using create-plan's indicators (Step 3), and detect available testing tools (Playwright MCP, HTTP client, DB access) as in create-plan Step 5. Then render the plan body using the format skill:

   ```
   Skill(skill: "test-plan-format")
   ```

   Fill `## Source` (Type: branch `<current>`, Base: `$BASE`, Date), `## Changes Summary`, `## Detected Tools`, and the FE/BE scenario sections per the skill (including its section-omission rules).

4. **Construct the path before writing** (bind it explicitly — there is nothing to "capture afterward"), then **Write** the plan to that literal path with the Write tool:

   ```bash
   mkdir -p docs/testing/plans
   DATE=$(date +%Y-%m-%d)
   # choose <topic> slug (lowercase, hyphens) from the changes
   plan_path="docs/testing/plans/${DATE}-<topic>-test-plan.md"
   ```

   Do **not** re-glob `ls -t` to locate the file afterward — write to and keep this exact `plan_path`.

5. **Provenance.** The sidecar created for this run (Step 1.3) records **`auto_generated: true`** for an auto-plan-generated plan. (A user-provided plan leaves it `false`/absent. The schema field is added by a later task; here, just set it true for this auto-generated path.)

6. **Success / validity contract.** After the Write, verify the file exists at `plan_path` **and** is structurally valid — it has the always-present headers `## Source`, `## Changes Summary`, and `## Detected Tools`. *(The FE/BE scenario sections are OPTIONAL per the format's omission rules; their absence is **thin**, not malformed — handled in Step 0.2.3.)* If the file is **missing** or any of those structural headers is **absent** → **abort**:

   > Error: Plan generation failed / produced a malformed plan. Aborting.

   Never fall through to a stale plan on failure.

7. **Re-entry.** Generation occurs in place of the dead-stop and has now set `plan_path` (non-empty), so the Step 0.2 `ls -t` fallback is **not** re-run. Control proceeds to the surfacing banner (Step 0.2.2), then the static thin-check (Step 0.2.3), then Step 0.3 (base-URL).

#### Step 0.2.2: Pre-Baseline Surfacing Banner (all modes)

Immediately after generation, **before** base-URL resolution, echo (counting `### FE-NN` and `### BE-NN` headings in the just-written plan):

> Generated plan: `<plan_path>` — <N> FE scenarios, <M> BE scenarios

In `--mode auto` this banner **is the audit trail** for the generated plan. Note that the **mutation-guarded SKIP count is reported post-baseline** — it is computed during the Step 2.1 mutation-guard pass, not here.

#### Step 0.2.3: Static Thin-Plan Exit (graceful success)

After generation + banner, and **before** Step 0.3 base-URL resolution: if the (valid) generated plan has **zero `### FE-NN` blocks and zero `### BE-NN` blocks** → exit **gracefully with success** (not an error):

> Generated plan has no executable FE or BE scenarios — nothing to test (e.g. a backend-only change fully covered by the unit/integration suite). Relying on that suite; not launching testers.

Do not launch testers. This runs **before** Step 0.3 precisely so a URL-less empty plan does not trip Step 0.3's fail-closed base-URL abort. A valid-but-thin plan is **not** malformed (malformed plans already aborted in Step 0.2.1 step 6).

**Readability check (all paths — a user-resolved plan OR a generated one that was not thin).** Once `plan_path` is settled and not empty, verify it is readable before continuing to Step 0.3 (the Read tool will error if not).

#### Step 0.3: Base-URL Resolution (Fail-Closed)

Probe for the base URL in this order; stop at the first non-empty match:

1. **Explicit URLs in the plan:** Read `plan_path` and extract URLs from the `## Source` section or scenario headers (look for `http://` or `https://` patterns). Take the first match.
2. **`QA_BASE_URL` env var:** Check if set and non-empty.
3. **Project config:** Best-effort probe (check for `.env`, `vite.config.ts`, or other project-specific config files for a base URL).

If **none of these resolve a base URL**, abort:

> Error: Base URL undetectable. Cannot guarantee loopback-only safety. Explicitly set QA_BASE_URL, add URLs to the plan's ## Source section, or use --allow-host.

Stop execution.

#### Step 0.4: Environment Guard

This guard is the only thing between the autonomous loop and the open network, so extract the host with **strict, fail-closed parsing** (when parsing is ambiguous, abort):

1. **Reject userinfo:** if the authority contains `@` (e.g. `http://localhost@evil.com/`), abort — never treat the userinfo as the host.
2. **Take the host component only,** then strip IPv6 brackets and any `:port` suffix (`[::1]:8000` → `::1`, `127.0.0.1:8000` → `127.0.0.1`).
3. **Match by exact equality, never substring.** The host is loopback iff it equals `localhost`, `127.0.0.1`, or `::1`, **or** it equals `localhost` / ends with `.localhost` (the `*.localhost` rule). `127.0.0.1.evil.com` and `0.0.0.0` are NOT loopback.
4. Otherwise it is allowed only if it appears in the `--allow-host` list.

If the host is neither loopback nor allow-listed:

> Error: Base URL resolves to non-loopback host 'X' and is not in --allow-host. Loopback-only safety enforced. Add --allow-host X to override.

Stop execution.

**Re-resolution:** any base URL re-resolved later in the run (Steps 3e, 4) MUST pass this same guard before any tester is dispatched — a host that drifts off loopback mid-run aborts.

#### Step 0.5: Hash the Plan & Init Counters

```bash
PLAN_HASH=$(shasum -a 256 "<plan_path>" | cut -d' ' -f1)
dispatch_count=0
start_time=$(date +%s)
iteration=0
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

**If the sidecar matches but `report_file` is missing or empty** (the report was deleted out from under the sidecar), fall through to a FRESH render but carry the sidecar's existing IDs — new IDs still continue at `max + 1` so they never collide with the sidecar's `scenario_issues`.

**Case 2: Sidecar absent but report exists**

If `report_file` exists but `sidecar_file` does not:

```bash
# ADOPT — import QA-XXX IDs and Status lines from the report
# Create a fresh sidecar stamped with the current PLAN_HASH
```

Read the report, extract all `### [SEVERITY] QA-NNN:` headings and any `**Status:**` lines, and build the `scenario_issues` map. Create the sidecar with these IDs; leave `baseline`/`current` to be populated by the authoritative baseline run (Step 2.3).

**Case 3: Hash mismatch**

If `sidecar_file` exists but `stored_hash != PLAN_HASH`:

```bash
[ -f "$report_file" ] && cp "$report_file" "${report_file%.md}.bak"
[ -f "$sidecar_file" ] && cp "$sidecar_file" "${sidecar_file%.json}.bak"
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
  "scenario_kind": { "BE-03": "negative", "BE-04": "feature" },
  "scenario_reason": { "BE-04": "auth-unverified", "BE-05": "mutation-guard" },
  "provisional_scenarios": [],
  "baseline": { "FE-01": "pass", "BE-03": "fail", "FE-05": "fail" },
  "current": { "FE-01": "pass", "BE-03": "fail", "FE-05": "fail" },
  "auto_generated": false,
  "pre_loop_dirty": [],
  "fix_touched_files": [],
  "dispatch_count": 0,
  "iterations": []
}
```

**When writing the sidecar:** set `auto_generated` to `true` if this run generated the plan in Step 0.2.1, else `false` (the example above shows the default) — do not take the literal `false` as unconditional. Persist `pre_loop_dirty` (recorded in Step 0.1.5). On the REUSE/ADOPT idempotency paths (Step 1.2), **preserve** the existing `auto_generated` value rather than overwriting it.

- `plan_sha256`: the 64-hex SHA-256 hash of the plan file
- `plan_path`: path to the test plan
- `report_file`: path to the QA report (no `docs/testing/reports/` prefix in the sidecar; store absolute or relative from root)
- `topic`: extracted from the plan filename
- `created`: date stamp (YYYY-MM-DD)
- `scenario_issues`: map of scenario-id → array of QA-XXX IDs assigned to that scenario
- `scenario_kind`: map of scenario-id → "sanity" | "negative" | "feature" (set once at baseline ingest, Step 2.1; classifies what a PASS means for coverage)
- `scenario_reason`: map of scenario-id → normalized reason for every non-PASS scenario ("mutation-guard" | "tool-unavailable" | "cannot-confirm" | "transport"), refreshed each ingest; drives the Coverage block and unlock-hints
- `provisional_scenarios`: array of auto-generated scenario-ids whose assertions are guessed-exact (decided in Step 0.2.1, persisted here); read by Step 3a to treat their failures as plan-suspect
- `baseline`: map of scenario-id → "pass" | "fail" | "skip" | "auth-unverified" (immutable reference recorded after Step 2; used for regression detection)
- `current`: map of scenario-id → "pass" | "fail" | "skip" | "auth-unverified" (mutable, updated each iteration to track latest status; used for iteration logic)
- `auto_generated`: `true` iff this run's loop generated the plan via auto-plan (Step 0.2.1); `false`/absent for a user-provided or pre-existing plan. Read by the thin/all-SKIP exit (Step 0.2.3 / Step 2.4) to decide graceful-success vs. error
- `pre_loop_dirty`: array of tracked paths already modified **before** the loop started (recorded in Step 0.1.5, persisted here so it survives across the many tool calls before the fix phase); subtracted from the post-fix set to compute `fix_touched_files`. Persisting it (rather than relying on a shell variable that can be lost mid-run) is what keeps scoped recovery from over-restoring the user's pre-existing edits
- `fix_touched_files`: array of tracked paths the loop's own fixes edited (post-fix tracked-modified set **minus** `pre_loop_dirty`, accumulated cumulatively across iterations in Step 3g); what scoped recovery (`git restore <fix_touched_files>`) restores — never the user's pre-existing changes
- `dispatch_count`: incremented each time a fix-auto or tester is launched
- `iterations`: array of iteration results (appended in Step 3e)

An older /qa:loop build reading a 2.3.0 sidecar treats the unknown "auth-unverified" status as non-failing (neither "pass" nor "fail"), degrading like "skip"; a hash-mismatch re-baseline recovers cleanly.

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

Apply the mutation guard: if a scenario contains a POST/PUT/PATCH/DELETE request (case-insensitive) in the plan **and** `--allow-mutations` is not set, mark it to SKIP with reason `mutation-guard` in the results (do not execute it). *(FE scenarios are UI-driven, so an action that triggers a write without a literal HTTP verb in the plan — e.g. a Delete button — is not detected; rely on a disposable test DB.)*

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

Apply the mutation guard: if a scenario specifies a state-changing HTTP method (POST/PUT/PATCH/DELETE, case-insensitive) or a DB-write check in the plan **and** `--allow-mutations` is not set, mark it to SKIP with reason `mutation-guard`.

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

Using the `report-format` skill, build the QA-XXX report **in memory** (the actual write happens in Step 2.5, or — on the zero-failure path — in Step 2.4 just before exit):

**Mutation-guarded SKIP count (post-baseline):** Now that the Step 2.1 guard pass has classified SKIPs, surface the count the pre-baseline banner (Step 0.2.2) deferred:

> Mutation-guarded SKIPs: <count> scenarios skipped under the mutation guard (re-run with `--allow-mutations` to execute them; test DB must be disposable).

#### Step 2.1.5: Structured Result Ingest

The testers return free-text result blocks (`be-tester.md:60-79`). Before tallying, parse **each** scenario block into a structured record `{ id, verdict, observed_status, reason, kind }`:

- **`verdict`** — the `**Status:**` line (`PASS`/`FAIL`/`SKIP`).
- **`observed_status`** — the **first integer** after `**Response status:**`, ignoring any `(expected: N)` parenthetical (the tester prints `500 (expected: 201)`); this is the scenario's **main-request** status. **BE only** — FE blocks have no `**Response status:**` line, so `observed_status` is `null` for FE.
- **`reason`** (non-PASS only) — **normalize** the tester's free prose into one bucket (the testers emit prose, not these tokens):
  - `mutation-guard` — **orchestrator-assigned** at dispatch (Step 2.1), authoritative; never parsed from output.
  - `/no .*client|unavailable|not supported/i` → `tool-unavailable`.
  - `/connection refused|could not connect|timeout/i` → `transport` (feeds §4 reachability; **not** a coverage SKIP reason).
  - any other prose → `cannot-confirm`.
- **`kind`** — per Step 2.1.6 (§1a).
- **Edge-case sub-blocks** (`be-tester.md:76-79`, nested `- <name>: PASS/FAIL`) are read for their inline verdict only; they have no isolatable `**Response status:**`, so they are NOT reclassified (Step 2.1.7) and inherit the parent's `kind`.

Persist `scenario_kind` and `scenario_reason` in the sidecar. `observed_status` is used transiently here (Step 2.1.7) and need not persist. If a block lacks a parseable status/reason, record `null` and degrade gracefully (the scenario keeps its bare verdict).

#### Step 2.1.6: Scenario-Kind Classification

For each scenario, derive `kind` from its declared `**Expected:**` status + endpoint path (the plan is already parsed at Step 2.1):

- BE: `**Expected:**` status **≥ 400** ⇒ `negative`; endpoint path ∈ {`/health`, `/healthz`, `/openapi.json`, `/version`, `/`, `/docs`, `/api/docs`} ⇒ `sanity`; otherwise ⇒ `feature`.
- FE: default `feature` unless purely navigational/sanity.

`scenario_kind` MUST be fully populated by the end of Step 2.3 (before Step 2.4 reads it). Best-effort and non-gating — a feature endpoint that asserts a 4xx is misclassified `negative`; this only shapes confidence wording, never a pass/fail decision.

#### Step 2.1.7: Auth-Unverified Reclassification (at ingest, BE only)

For a BE scenario with `kind == feature`: if the parsed `observed_status` ∈ {401, 403} **and** the declared `**Expected:**` is a 2xx, set `verdict = auth-unverified` (executed, but the feature path was gated — no token). Counted and surfaced, **never** credited as PASS. A scenario that *expected* 401 and got 401 stays a normal `negative` PASS. If `observed_status` is `null`, leave the verdict unchanged (best-effort).

**Not detected (residual, see §8 of the spec):** 2xx-shaped gating (empty `200 []`, tenant `404`), auth surfaced only via an edge-case sub-test, and any FE gating (no FE HTTP status). Hence the Coverage block reports **"Exercised"**, not "Verified", for feature PASSes.

1. **Count results:** tally pass/fail/skip across all scenarios.
2. **Assign QA-XXX IDs.** `max(existing)` is the highest QA-ID number across the **union** of: the report's `### … QA-NNN` headings, the sidecar `scenario_issues` IDs, and any QA-IDs referenced in Loop History. If that union is empty or unparseable, start at 0.
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
  "current": {
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

The `baseline` map is immutable and serves as the regression reference. The `current` map is a mutable copy initialized to match baseline; it is updated each iteration to reflect the latest pass/fail status.

#### Step 2.4: Zero-Failure Exit

Count failures at or above `--severity` (default: all):

- If **zero failures** → print:

> All passing, nothing to fix.

  Save the report and sidecar first (Step 2.5 — on reuse/adopt this preserves any existing `**Status:**` lines), then skip the loop (Step 3) AND the final run (Step 4), and exit success.

- If **all scenarios are SKIP**, branch on provenance (`auto_generated`, the sidecar flag set during generation in Step 0.2.1) and the SKIP reasons:

  - **Auto-generated plan (`auto_generated == true`):**
    - If **every** SKIP reason is `mutation-guard` → exit **gracefully with success** (not an error):

      > Auto-generated plan is backend-write-only under the mutation guard — nothing executable here; rely on the unit/integration suite.

    - Else (**any** SKIP is `tool-unavailable` / `cannot-confirm` / `parse-failure`, i.e. not purely mutation-guard) → exit **gracefully** but print a **coverage-zero WARNING**:

      > Warning: All scenarios skipped for tooling/parse reasons, not mutation-guard — coverage is zero; verify the generated plan and tool availability.

  - **User-provided plan (`auto_generated` false/absent)** → abort (no executable verifier):

    > Error: No executable verifier — cannot gate (all scenarios marked SKIP or unavailable). Check your test plan and tool availability.

    Stop execution.

  On either graceful auto-generated path, save the report and sidecar (Step 2.5) first, then skip the loop (Step 3) and the final run (Step 4) and exit success.

#### Step 2.5: Save Report

**For reuse (Case 1) and adopt (Case 2) modes:**

Before writing, extract any existing `**Status:**` lines from the prior report. **Match each Status line to its issue strictly by the `QA-NNN` token, not the full `### [SEVERITY] … Title` heading** — severity and title may be re-derived differently between runs. When rendering the new report, re-insert each preserved Status line immediately after its `QA-NNN` heading, **exactly once** (never add a second Status line to an issue that already has one). Alternatively, use the Edit tool to make surgical updates to the existing report (merge new issues, keep old Status lines intact).

**For fresh mode (Case 3 mismatch / Case 4 none):**

Write a clean report using the Write tool (full overwrite).

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

Run the pre-checks **before** committing to this iteration, so a pass that does no work never inflates the reported iteration count.

Re-hash the plan to detect mid-run tampering:

```bash
CURRENT_PLAN_HASH=$(shasum -a 256 "<plan_path>" | cut -d' ' -f1)
```

If `CURRENT_PLAN_HASH != PLAN_HASH`, the plan was edited mid-run. **Before stopping, flush the partial report + the Loop History rows accumulated so far** (do NOT write any `**Status:**` line — there is no authoritative final run), then print and stop:

> Error: Plan changed mid-run (hash mismatch). Stopping. Uncommitted source changes left for review; recover the loop's own edits with `git restore <fix_touched_files>` (scoped — never touches your pre-existing changes).

Substitute the accumulated `fix_touched_files` list (Step 3g) for `<fix_touched_files>`; this restores only the loop's fixes, never the user's pre-existing dirt. **Under `--allow-dirty` the whole-tree hint is suppressed** — print the scoped `fix_touched_files` list plus the overlap note (files both pre-existing-dirty and fix-edited are left for the user to reconcile).

This mirrors the Esc-abort path: a partial report is always flushed, Status is never written.

Compute `elapsed = $(date +%s) - start_time`. If elapsed >= `--time-budget`:

> Time budget exhausted. Stopping loop.

Exit the loop.

Check dispatch budget before re-running:

```bash
if [ "$dispatch_count" -ge "$--max-dispatches" ]; then
  # Skip fixing; proceed to Step 4
fi
```

Only once the pre-checks pass and this iteration commits to doing fix work, increment the counter:

```bash
iteration++
```

#### Step 3a: Select & Pre-Filter Fix-Set

From the sidecar `current` and `scenario_issues`:

1. Identify all scenarios still failing (current == "fail").
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

*(Headless check was already performed in Step 0.1; no need to re-check here.)*

#### Step 3c: Fix

Pre-check: If `dispatch_count >= --max-dispatches`, skip the entire fix phase and proceed to Step 4 (final run). The final run always launches (counted but not gated) to provide authoritative verification.

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

**Note on dispatch budget:** The `--max-dispatches` limit is a soft guard checked at iteration boundaries. A single iteration may slightly overshoot dispatch_count before the next boundary check. The **final run (Step 4) always runs** regardless, with its launches counted but not gated, to ensure authoritative verification.

#### Step 3d: Anti-Hardcoding Warning (Per Fix)

After each fix completes, run:

```bash
git diff --unified=0 <touched-files>
```

**Scope:** This check applies only to **BE scenarios** (which carry structured request-payloads in the plan). FE scenarios do not have payload values to match.

For each line added (starting with `+`) in the diff, extract the literal string. For the BE scenario(s) in `fix_candidates` (the one(s) this issue came from), extract its request-payload value (from the plan). If the added literal **exactly matches** a request-payload value (**exact-string, case-sensitive**):

Record a **WARNING** for this fix: `"Possible hardcoding: added literal matches scenario request-payload value X"`.

**Best-effort, non-blocking:** If a scenario has no extractable payload, skip the warning (do not error). This is a heuristic check, not a guarantee.

Store the warning in the sidecar `iterations[]` entry (not a blocker — just a human-review flag).

#### Step 3e: Re-Run Section(s)

Identify which section(s) contain still-failing scenarios. Re-run the **whole section** (all scenarios in that section, in order) for each affected section:

**If any FE scenario is still failing:**

```
dispatch_count++
Task(
  subagent_type: "qa:fe-tester",
  run_in_background: true,
  description: "Re-run FE section (iteration N)",
  prompt: "<all FE scenarios from the plan; mutation guard applied again>
Base URL: <re-resolve from Step 0.3, re-validated via Step 0.4>
Execute all scenarios in order (dependency-safe)."
)

fe_results = TaskOutput(fe_tester_id, block: true)
```

**If any BE scenario is still failing:**

```
dispatch_count++
Task(
  subagent_type: "qa:be-tester",
  run_in_background: true,
  description: "Re-run BE section (iteration N)",
  prompt: "<all BE scenarios from the plan; mutation guard applied again>
Base URL: <re-resolve from Step 0.3, re-validated via Step 0.4>
Execute all scenarios in order."
)

be_results = TaskOutput(be_tester_id, block: true)
```

Only launch and count sections that contain at least one still-failing scenario.

#### Step 3f: Check Regressions & Progress

**Regression check:** Read the sidecar `baseline` map. For each scenario, check if it passed at baseline (baseline == "pass") but fails in the newly-received re-run results (current == "fail"). Record any regressions detected.

If any regression is detected, stop:

> Scenario regression detected (e.g., FE-01 passed at baseline but failed this iteration). Stopping loop to prevent oscillation.

Exit loop. (Regressions are reported in Step 4.2.)

**Progress:** has at least one scenario newly passed this iteration? Compare the `current` map **as it stood at the start of this iteration** (before Step 3g updates it) against the newly-received re-run results. If **at least one scenario went from "fail" to "pass"**, continue. If **no**, stop (no progress):

> No progress this iteration (no newly passing scenarios). Stopping loop.

Exit loop.

**`auth-unverified` across consumers:** it is never `"fail"`, so it is excluded from the fix-set (Step 3a, `current == "fail"`), is never a regression (Step 3f / 4.2, which key on `baseline == "pass" ∧ current == "fail"`), and is inert for the progress check (a scenario the loop is not fixing). A re-run scenario that becomes `auth-unverified` updates `current` normally (Step 3g merge).

#### Step 3g: Update Sidecar

After progress/regression checks, update the sidecar with an entry in `iterations[]`:

```json
{
  "iteration": <live iteration counter>,
  "attempted_fixes": ["QA-001", "QA-003"],
  "now_passing": ["FE-02", "BE-03"],
  "still_failing": ["BE-04"],
  "regressions": [],
  "warnings": ["QA-001: Possible hardcoding — added literal matches scenario payload"],
  "dispatch_count": 3,
  "elapsed_s": 120
}
```

The `"iteration"` field must be set to the live `iteration` counter (e.g., iteration 1 on the first loop pass, iteration 2 on the second, etc.). If regressions were detected in Step 3f, record them in the `"regressions"` array.

Update the `current` map with the latest pass/fail/skip status — **merge, don't replace:** only overwrite entries for scenarios actually re-run this iteration; leave all other entries (e.g. an un-re-run section's passing scenarios) unchanged:

```json
{
  "current": {
    "FE-02": "pass",
    "BE-03": "pass",
    "BE-04": "fail"
  }
}
```

Keep the `baseline` map immutable (it is the reference for regression detection).

**Accumulate `fix_touched_files` (the loop's own edits).** After the fix phase, compute the set of tracked files the loop's fixes edited, excluding the user's pre-existing dirt — **read `pre_loop_dirty` back from the sidecar** (persisted in Step 1.3, not a shell variable that may have been lost across the intervening tool calls):

```bash
post=$(git -c core.quotePath=false diff --name-only HEAD)   # same robust form as Step 0.1.5 (one FULL path per line)
# fix_touched_files = post − pre_loop_dirty  (line-set difference; read pre_loop_dirty back from the sidecar, not a shell var)
```

Persist `fix_touched_files` (the array) in the sidecar — **merge cumulatively** across iterations so it reflects every file the loop has touched, not just this iteration's:

```json
{
  "fix_touched_files": ["src/api/users.py", "src/services/auth.py"]
}
```

This set is what scoped recovery (`git restore <fix_touched_files>`) restores — never the user's pre-existing changes.

**Overlap note (pre-existing AND fix-edited):** a file that is in **both** `pre_loop_dirty` and `post` (the user already had it dirty *and* a fix further edited it) is **excluded** from `fix_touched_files` by the set difference above — restoring it would discard the user's own work. Surface these as a one-line note for the user to reconcile, rather than restoring them:

> Note: <files> were already modified before the loop and also edited by a fix — left untouched for you to reconcile (not included in scoped recovery).

#### Step 3h: Append Loop History Row

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
- **Now passing** — scenarios that passed this iteration (newly fixed)
- **Still failing** — scenarios still failing after this iteration
- **Warnings** — comma-separated QA-XXX IDs with warnings (anti-hardcoding flags, "⚠" symbol)
- **Regressions** — scenarios that passed at baseline but failed this iteration (newly detected regressions)
- **Dispatches** — fix + re-run count for this iteration

This section is `##`-level (placed after `## Detailed Results`) and MUST contain no `### [SEVERITY]` headings and no `---` separators, so `/fix-report`'s block parser skips it (see the `report-format` skill).

**DO NOT write `**Status:**` headings yet** — they are written only from the authoritative final run (Step 4).

#### Step 3i: Budget Check

Check the remaining budgets:
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

Base URL: <resolved from Step 0.3, re-validated via Step 0.4>

Execute all scenarios in order. This is the authoritative final run."
)

dispatch_count++
Task(
  subagent_type: "qa:be-tester",
  run_in_background: true,
  description: "Final run — BE scenarios",
  prompt: "<all BE scenarios; mutation guard applied>

Base URL: <resolved from Step 0.3, re-validated via Step 0.4>
DB connection: <detect from plan or project config>

Execute all scenarios in order. This is the authoritative final run."
)

fe_results = TaskOutput(fe_tester_id, block: true)
be_results = TaskOutput(be_tester_id, block: true)
```

#### Step 4.1: Write Status (One-Time, Authoritative)

For each scenario that **PASSES** in the final run:

1. Locate all its QA-XXX headings in the report **by the `QA-NNN` token** (not the full heading text).
2. For each heading, use the Edit tool to insert immediately after the `### [SEVERITY] QA-XXX: Title` line — **exactly once** (if a `**Status:**` line already exists for that issue, update it in place rather than adding a second):

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

Use today's date in YYYY-MM-DD format.

**Still-failing scenarios:** leave their issues unmarked (no `**Status:**` line; they remain retryable by a future run).

**`⚠️ Partially Fixed` is never written** — it would freeze issues out of `/fix-report`. The report stays compatible with `/fix` / `/fix-report`.

#### Step 4.2: Handle Regressions

Read the sidecar `baseline` map. For each scenario, check if it passed at baseline (baseline == "pass") but fails in the final run (final-run-results == "fail"). This is a regression.

For each regression:

1. Create a **new QA-XXX** for the regression at `max(existing) + 1` (the union of report + sidecar + Loop History IDs, per Step 2.2), deduped vs. still-open IDs.
2. Add it to the report with the issue format (Location, Problem, Remediation).
3. Append a row to the Loop History section (in the `Regressions` column, list the new QA-XXX).
4. Record it in the sidecar's `iterations[]` as a "regression" entry.
5. Do NOT write `**Status:** Fixed` (it's not fixed; it's a regression).

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

To recover the loop's own edits: `git restore <fix_touched_files>`  (scoped — restores only what the loop's fixes touched, never your pre-existing changes)

**Changes remain uncommitted for your control.**

**Note on --allow-mutations:** Mutation-allowing runs modify the database (POST/PUT/PATCH/DELETE). Ensure your test database is disposable and can be safely reset between runs.
```

For the recovery line, substitute the accumulated `fix_touched_files` list (Step 3g) for `<fix_touched_files>`. **Under `--allow-dirty` the whole-tree hint is suppressed** (the gate was bypassed, so the tree intentionally held pre-existing dirt): print the scoped `fix_touched_files` list **plus the overlap note** — files that were both pre-existing-dirty and fix-edited are excluded from scoped recovery and left for the user to reconcile. If `fix_touched_files` is empty, state that the loop touched nothing to recover.

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

*Mutation classification is syntactic and best-effort (HTTP-verb matching is case-insensitive). It detects HTTP verbs and DB-write patterns in the plan, but does **not** detect GET-with-side-effects, GraphQL mutations without an explicit verb, or **FE UI actions that trigger writes** (e.g. clicking a Delete button). Treat the test DB as disposable regardless of `--allow-mutations`.*

**Verifier-gaming residual (v1):** The loop defends against payload-literal hardcoding via the anti-hardcoding warning, but a capable fixer with visibility to deterministic scenarios can make a scenario pass without a real fix. The default `approve` mode is the runtime mitigation; randomized re-verification is planned for v2.

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
| Entire baseline is SKIP (user-provided plan) | Abort: "no executable verifier — cannot gate." |
| Entire baseline is SKIP (auto-generated plan) | Graceful success if every SKIP reason is `mutation-guard` (backend-write-only — rely on unit/integration suite); graceful exit **with a coverage-zero WARNING** if any SKIP is tooling/parse-related (`tool-unavailable` / `cannot-confirm` / `parse-failure`). |
| Zero baseline failures at/above floor | "All passing, nothing to fix" → skip loop AND final run → exit success. |
| Issue `Location: unknown:0` / missing fields | Pre-filtered out; "needs manual location"; never dispatched. fix-auto also returns Failed if a location-less issue arrives. |
| fix-auto fails on an issue | Mark failed for this iteration; keep looping on remaining issues. |
| fix-auto says "Fixed" but re-run still fails | Re-run is authoritative; scenario stays failing. |
| Anti-hardcoding warning | Surfaced for human review (approve mode) / logged (auto mode); not a credit block. |
| No progress / oscillation / budget exceeded | Stop; report remaining issues; suggest `/fix` or another `/qa:loop` run. |
| Regression in final run | New QA-XXX (deduped); reported in Loop History, not auto-fixed. |
| Plan hash mismatch (mid-run) | Abort; flush partial report + Loop History (never Status); plan changed during loop execution. Recover the loop's own edits with scoped `git restore <fix_touched_files>` (suppressed under `--allow-dirty`). |
| Plan hash mismatch (cross-run) | Re-baseline; archive prior artifacts to `.bak`. |
| Dispatch budget exhausted | Skip remaining fixes; proceed to final run (always runs, not gated). |
| User abort (Esc in auto mode) | Uncommitted changes left; partial report + Loop History so far. Recover the loop's own edits with scoped `git restore <fix_touched_files>` (suppressed under `--allow-dirty`, where the scoped list + overlap note are printed instead). |
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

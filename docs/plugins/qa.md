# QA Plugin

Automated QA testing — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports with unique issue IDs compatible with code-review's `/fix QA-001` and `/fix-report` auto-merge.

**Version:** 2.7.0

## Commands

### `/qa:create-plan`

Analyze code changes and generate a detailed test plan with FE and BE scenarios, edge cases, and tool detection.

```bash
# Analyze current branch's PR (or branch diff as fallback)
/qa:create-plan

# Analyze specific PR
/qa:create-plan #123

# Analyze branch diff
/qa:create-plan feature/xyz

# Analyze current branch
/qa:create-plan ten branch

# Analyze last N commits
/qa:create-plan last 5 commits

# Analyze staged changes
/qa:create-plan staged
```

The command:
1. Resolves the diff source (PR, branch, commits, or staged changes) and pins the intended success and error-path contract before observing runtime behavior
2. Classifies changed files as FE or BE and reads related producers (routers, models, schemas, docs, OpenAPI specs and installed framework behavior) to ground each assertion
3. Scans for contract blockers and records them in mandatory `## Blockers / Findings` (`None found.` if none); affected scenarios retain their intended expectation and carry `**Blocked-by:** BLK-NN`
4. Grounds `## Setup` (base URL, required environment-variable names, services and database connections) from the repository at plan-authoring time; credentials are `$NAME` references, not literal values
5. Detects testing tools (Playwright MCP, curl/httpie, psql/sqlite3/mysql, database MCP servers); an available MCP server is not assumed to point to the test DB
6. Limits scenario steps to browser actions, HTTP requests and DB queries against an already-running app; human bring-up belongs under Required services and unobservable checks under `## Out of harness scope`
7. When behavior depends on at least two independent booleans, loads `state-combination-planning` and records every row of the $2^N$ combination table with a scenario or justified disposition
8. Generates `FE-XX`/`BE-XX` scenarios whose expected results and edge cases carry `(path:line)` or `(unverified — confirm at run time)` tags; refutes unsupported assertions before saving to `docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md`
9. Proposes running `/qa:run` to execute the plan

### `/qa:run`

Execute a test plan by launching FE and BE testing agents in parallel and generating a report.

```bash
# Run the most recent test plan
/qa:run

# Run a specific test plan
/qa:run docs/testing/plans/2026-04-07-user-auth-test-plan.md
```

The command:
1. Loads the plan (including `## Setup` and each assertion's grounding tag), re-validates tools and checks declared environment-variable **presence only** before dispatch. If any are missing, it aborts: `⚠️ Cannot start QA — <N> required value(s) missing:` followed by their names and advice to export them in the shell that launches the harness, restart it, then re-run; values are never printed.
2. Resolves the Base URL from `## Setup`, then the first URL in `## Source` or a scenario heading/bullet, then `QA_BASE_URL`; no URL means a fail-closed abort. It does not read project config at run time.
3. Launches **fe-tester** (browser actions) and **be-tester** (HTTP requests and declared DB connections) in parallel. A missing prerequisite returns `NEED_INFO` with kind `credentials`, `service`, `fixture` or `tool`; an assertion mismatch returns FAIL.
4. Before reporting any FAIL, testers refute it with a single read-only re-verification, check prerequisites and scope, and distinguish harness failures from app defects. A mutating action (POST, submit or write-triggering click) is **never replayed**; when its outcome remains unknown after one read of resulting state, the scenario is SKIP rather than a fabricated failure.
5. Derives one scenario verdict: `fail` for a failed main flow or edge; otherwise `need-info` for any missing prerequisite; otherwise `skip` for an unrunnable main flow or edge; otherwise `pass`. A skipped DB check alone does not downgrade the HTTP result. Only failing assertions mint `QA-XXX` issues; gaps appear under conditional `## Setup gaps` with names/URLs, never secret values.
6. BE responses are inspected and persisted only after fail-closed redaction of listed sensitive headers, sensitive JSON keys, Bearer/query tokens and declared environment values of at least four characters; non-JSON and bare-string bodies are withheld. It does not claim to catch undeclared secrets in arbitrary non-sensitive free text. Failed FE screenshots use `docs/testing/reports/screenshots/<ID>-fail.png` (edge n: `<ID>-edge<n>-fail.png`); BE dumps use `docs/testing/reports/responses/<ID>-body.json` (edge n: `<ID>-edge<n>-body.json`), never QA issue IDs or timestamps.
7. Saves the report to `docs/testing/reports/YYYY-MM-DD-<topic>-report.md` with severity per assertion (unverified mismatch: LOW unless HTTP ≥ 500 or crash/stack trace).

### `/qa:loop`

Close a test → fix → retest loop: run a QA plan, auto-fix failures via `code-review:fix-auto`, re-run affected sections, and repeat until all issues pass or the budget is exhausted.

**Self-driving (2.2.0):** when no plan exists, `/qa:loop` can generate one for the current branch (diffed against the default branch) and continue straight into the loop — no separate `/qa:create-plan` step. Whether it does so depends on the mode (see [Auto-plan](#auto-plan-self-driving-loop-220) below).

```bash
# Run the most recent test plan in default mode (approve — one batch HITL gate)
/qa:loop

# No plan yet? In approve/step the loop offers to generate one for the branch and run it
/qa:loop

# Headless auto mode: opt in to plan generation explicitly
/qa:loop --mode auto --auto-plan

# Run a specific plan in automatic mode (headless, no HITL gates)
/qa:loop docs/testing/plans/2026-06-17-user-auth-test-plan.md --mode auto

# Strict: max 2 iterations, 20 dispatches, step-by-step approval
/qa:loop --mode step --max-iterations 2 --max-dispatches 20

# Allow state-changing BE scenarios (POST/PUT/PATCH/DELETE) and non-loopback hosts
/qa:loop --allow-mutations --allow-host staging.example.com

# Only fix CRITICAL and HIGH issues; set a 30-minute time budget
/qa:loop --severity HIGH --time-budget 1800

# Run with uncommitted changes already in the tree (bypass the working-tree gate)
/qa:loop --allow-dirty
```

**Invocation & flags:**

```
/qa:loop [plan-path] [--mode approve|auto|step] [--max-iterations N] 
         [--max-dispatches D] [--time-budget S] [--severity LEVEL] 
         [--allow-mutations] [--allow-host HOST]
         [--auto-plan] [--no-auto-plan] [--allow-dirty]
```

| Argument | Interpretation | Default | Rules |
|----------|---|---|---|
| (empty) | Find the newest plan in `docs/testing/plans/` | — | If no plan found, **auto-plan** decides: approve/step generate one for the branch (after a confirm); auto stops with "Run `/qa:create-plan` first." unless `--auto-plan` (see [Auto-plan](#auto-plan-self-driving-loop-220)) |
| `<path>` | Use the specified test plan file | — | File must exist and be readable |
| `--mode` | Loop mode: `approve` (batch HITL), `auto` (headless), `step` (per-fix HITL) | `approve` | Case-sensitive; unknown value → error; `approve`/`step` require interactive session (TTY); headless → error |
| `--max-iterations` | Maximum loop iterations | 3 | Must be positive integer; invalid → error |
| `--max-dispatches` | Maximum fix-auto + tester launches combined | 50 | Must be positive integer; soft limit at iteration boundaries; final run always runs (not gated) |
| `--time-budget` | Wall-clock seconds before timeout | 1800 | Must be positive integer; error on invalid |
| `--severity` | Minimum severity to credit as fixed: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` | (none = all) | Case-insensitive; unknown value → error |
| `--allow-mutations` | Permit state-changing BE scenarios (POST/PUT/PATCH/DELETE, DB writes) beyond the expected-rejection exemption | (off) | Present → on; absent → off; no value needed; **test DB must be disposable (no rollback)** |
| `--allow-host` | Whitelist additional hosts beyond loopback | (loopback only) | Repeatable; each invocation appends; format: hostname or IP |
| `--auto-plan` | Force auto-plan generation ON when no plan exists (required to enable it in `--mode auto`) | on in approve/step, off in auto | Valueless presence flag; mutually exclusive with `--no-auto-plan` |
| `--no-auto-plan` | Force auto-plan OFF — restore the 2.1.0 dead-stop when no plan exists | — | Valueless presence flag; mutually exclusive with `--auto-plan` |
| `--allow-dirty` | Permit running with uncommitted **tracked** changes (bypass the working-tree gate); suppresses whole-tree recovery hints | (off) | Valueless presence flag; present → on |

**Modes:**

| Mode | Behavior | HITL | Headless-Safe |
|---|---|---|---|
| **approve** *(default)* | Single batch approval before fixing; shows fix-set + warnings | Yes (one gate) | No — requires TTY |
| **auto** | No HITL gate; prints scope banner; abort via Esc | No | Yes — headless safe |
| **step** | Approve before each re-test (maximum control) | Yes (per iteration) | No — requires TTY |

**Headless behavior:** if `--mode approve` or `--mode step` and stdin is not a TTY (non-interactive session) → abort with "approve/step require an interactive session; use --mode auto."

#### Auto-plan (self-driving loop, 2.2.0)

When no plan exists, instead of dead-stopping, `/qa:loop` can generate one for the **current branch** (diffed against the default branch) and continue into the loop. The default is **mode-dependent**:

| Mode | Auto-plan default | No-plan behavior |
|---|---|---|
| **approve** *(default)* / **step** | **ON** | One confirm — *"No QA plan found for this branch. Generate one and run the loop?"* → generate → continue. Fixes are still gated by the per-mode HITL gate. Headless (no TTY) aborts first, so this prompt only ever runs interactively. |
| **auto** | **OFF** | The 2.1.0 dead-stop, **unless `--auto-plan`** is passed. With `--auto-plan`, a non-silent banner is printed (even headless) and a plan is generated, then the loop continues with no gate. |

**Why mode-dependent:** `approve`/`step` gate every fix, so generating a plan there is low-risk and merely prompted. `auto` has no gate, so silently turning a CI `qa:loop --mode auto` (which previously expected a no-op stop) into source-mutating execution would be a behavior change — it is opt-in via `--auto-plan`.

**Overrides:** `--auto-plan` forces ON, `--no-auto-plan` forces OFF (restores the dead-stop). Both are valueless presence flags; passing both is an error.

**Surfacing the generated plan:**

- **Before baseline:** the generated plan path plus FE/BE scenario counts are echoed — e.g. `Generated plan: <path> — 4 FE scenarios, 2 BE scenarios`. In `--mode auto` this banner is the audit trail.
- **After baseline:** the **mutation-guarded SKIP count** is rendered in the Loop Summary's "Next steps to widen coverage" table (it is only knowable once the Step 2.1 guard pass has classified SKIPs, so it is not claimed in the pre-baseline banner).

**Working-tree safety gate:** because the loop auto-fixes source and recovers via `git restore`, uncommitted **tracked** changes are at risk. After argument validation and before plan resolution, the loop inspects the tree (`git status --porcelain` over tracked files; untracked files are excluded — `git restore` cannot destroy them):

- **`auto`** — a dirty tree **aborts** unless `--allow-dirty`.
- **`approve`/`step`** — a dirty tree **warns and confirms** (this prompt comes *before* the generate confirm, so a dirty no-plan run shows two prompts).
- `--allow-dirty` bypasses the gate in all modes.

**Scoped recovery (never whole-tree):** every recovery hint the loop prints restores only the loop's own edits — `git restore <fix_touched_files>` — never `git restore .`. `fix_touched_files` is the post-fix tracked-modified set minus what was already dirty before the loop, recorded in the sidecar. This guarantees recovery never discards your pre-existing edits. A file that was *both* already dirty and further edited by a fix is left untouched (surfaced as a one-line note for you to reconcile). Under `--allow-dirty`, the whole-tree hint is suppressed entirely.

**Graceful, reason-aware thin-plan exit:** an **auto-generated** plan with nothing executable exits **successfully** (the unit/integration suite is the real coverage there), not as an error:

- **Empty plan** (zero `FE-NN` and zero `BE-NN` scenarios — e.g. a change with no testable UI/API surface) → graceful success before any tester launches.
- **All verdicts `skip` or `need-info`, all under the mutation guard** (the legitimate backend-write-only case) → graceful success; rely on the unit/integration suite.
- **All verdicts `skip` or `need-info`, with any setup/tooling/parse gap** → graceful exit **with a coverage-zero warning** — no missing prerequisite is laundered into "success."
- A **user-provided** all-`skip`/`need-info` plan still **errors** (`No executable verifier — cannot gate`), with setup gaps listed.

A *malformed* generated plan (missing the always-present `## Source` / `## Changes Summary` / `## Detected Tools` headers) is a different case — it **aborts**, never falls through to a stale plan.

**Mode matrix (no-plan / dirty-tree / thin-plan):**

| Situation | `auto` | `approve` / `step` |
|---|---|---|
| No plan | dead-stop, unless `--auto-plan` → banner → generate → run | confirm → generate → run (headless: abort) |
| Dirty tree | abort unless `--allow-dirty` | warn + confirm (before the generate confirm) |
| After generation | pre-baseline banner (path + FE/BE counts) → continue | pre-baseline banner → continue |
| Empty plan (0 FE + 0 BE) | graceful success | graceful success |
| All skip/need-info, auto-generated, mutation-guard only | graceful success | graceful success |
| All skip/need-info, auto-generated, setup/tooling/parse reasons | graceful exit + coverage-zero warning | graceful exit + warning |
| All skip/need-info, user-provided plan | existing error + setup gaps | existing error + setup gaps |

> [!IMPORTANT]
> **Behavior changes for all `/qa:loop` users (2.3.0).** The no-plan default in `auto` **stays a no-op stop** unless you add `--auto-plan`, so existing CI invocations are unaffected. The **interactive default** (`approve`/`step`), however, changes from "stop" to "**confirm, then generate**" — a prompted action, not a silent one. Pass `--no-auto-plan` to restore the 2.1.0 dead-stop in any mode.
>
> **New in 2.3.0:**
> - The **shallow-coverage WARNING** can now appear in any mode (`approve`, `step`, `auto`) and on **user-authored plans** — a visible change to a previously-silent green exit. The exit is still success; it is a disclosure, not a gate.
> - **`--mode auto --auto-plan`** may now produce an **empty fix-set** (all feature scenarios were `auth-unverified` or provisional) and exit green-with-caveat *by design* — this is correct behavior, not a regression.

**Algorithm summary:**

1. **Resolve & Validate** — Parse arguments; resolve the base URL from `## Setup`, then plan URLs, then `QA_BASE_URL` (never project config at run time); enforce the loopback-only guard unless `--allow-host`; preflight declared env-var names before dispatch; hash the plan
2. **Baseline Run** — Execute FE and BE scenarios with the mutation guard (expected-rejection BE exemption below), derive the full main-flow-plus-edge verdict, render `QA-XXX` report and `## Setup gaps` for missing prerequisites; in `approve`/`step` ask whether to re-run affected sections once, continue or abort when gaps exist (`auto` continues)
3. **Loop Iterations** — For each iteration (bounded by `--max-iterations`, `--max-dispatches`, `--time-budget`):
   - Select failing scenarios at/above `--severity`; never treat `need-info` or `auth-unverified` as fix candidates
   - Pre-filter issues rejected by the user, without usable Location or required fields; exclude auth-gated **main-flow** QA IDs in all modes even if an independent edge FAIL keeps their scenario failing
   - Flag each issue whose assertion is `(unverified — confirm at run time)` as plan-suspect; in `auto` do not fix that issue, but grounded failures of the same scenario remain eligible
   - HITL gate per `--mode` (approve: one batch; step: per re-test; auto: no gate)
   - Auto-fix eligible issues via `code-review:fix-auto`, warn on request-payload-literal hardcoding, re-run affected whole sections, update sidecar and Loop History
   - Stop if: no scenario newly passed, oscillation detected (regression), or any budget exhausted
4. **Final Run** — Unless zero-failure exit fired: re-run the entire plan once (authoritative source of truth); write `**Status:** ✅ Fixed (YYYY-MM-DD)` only when the **entire** scenario's final verdict is `pass`, including all edges. A passing main flow with an edge `NEED_INFO`, `SKIP` or `FAIL` keeps its issues open.
5. **Summary** — Loop History, final Pass/Fail/Skip/Need info counts, Coverage and names-only need-info unlock hints, fixed/remaining/warnings/regressions, dispatch & time budget used

`/qa:loop` derives a verdict per scenario in this order: `fail` when the main flow or any edge FAILs; otherwise `need-info` when either has a missing prerequisite; otherwise `auth-unverified` for a BE feature main flow reclassified from a 401/403 instead of its expected 2xx; otherwise `skip` when main flow or edge SKIPs; otherwise `pass`. A `**DB check:** SKIP` alone does not count as an edge SKIP. `## Setup gaps` lists edge gaps even when an independent failure wins the scenario verdict.

**Safety guards (all modes):**

- **Environment guard:** base URL must resolve to loopback (`localhost`, `127.0.0.1`, `::1`, `*.localhost`) or be in `--allow-host`, else **abort**; no config file is read for a runtime base URL
- **Mutation guard:** without `--allow-mutations`, state-changing BE scenarios SKIP unless the first status on `**Expected:**` and every edge's expected status are ≥ 400, an optional `**DB Check:**` is read-only and no other bullet describes a write (`create`/`delete`/`update`/`insert`/`seed`). Unclassifiable actions remain guarded. An unexpected 2xx on an exempt request lands a write **once**, so keep the test DB disposable. This static guard does not detect GET side effects or write-triggering FE UI actions.
- **Fix-set pre-filter:** three classes of issue are dropped from the fix-set and never dispatched, each recorded under its own reason:
  - a `**Status:**` line beginning `🚫 Rejected` — reason `rejected by user`. The status is terminal, so the finding never re-enters the fix-set on this or any later run. Matched **by prefix**, never by whole-line equality: a rejected line carries a ` — <reason>` tail that is not this loop's to control
  - a location-less `**Location:**` field — reason `needs manual location`. The field's **value** is what is tested, read by a two-clause rule: the first backticked token, ignoring any trailing parenthetical; or, where the line carries no backticked token, the first whitespace-delimited token after the field name. That value is location-less when it is `—`, `unknown:0`, absent, or anything that does not parse as `path:line` or `path:line-range`. **Never test the whole line** — a repaired finding reading `` **Location:** `src/a.py:12` (was: `unknown:0`) `` still contains `unknown:0` in its preserved tail, yet is perfectly dispatchable
  - missing fix-auto-required fields (Location, Problem, Remediation) — reason `incomplete fields`
- **Anti-hardcoding warning:** a heuristic check (not a credit gate) flags fixes where added source literals match scenario request-payload values; surfaced for human review in `approve` mode, logged in auto/step

**Sidecar & state:**

The command owns a machine-state JSON file: `docs/testing/reports/<topic>-loop-state.json`

Contains:
- `plan_sha256` — fingerprint to detect plan tampering (cross-run or mid-run)
- `scenario_issues` — scenario-id → [QA-IDs] map
- `baseline` / `current` — full scenario verdicts (`pass`, `fail`, `skip`, `auth-unverified`, `need-info`), after edge aggregation
- `need_info` — current names-only missing prerequisites by scenario ID and `<ID> (edge n)`; refreshed for re-run sections
- `unverified_issues` — QA IDs for individually unverified assertions; per-issue plan-suspect guard
- `auth_gated_issues` — auth-unverified **main-flow** QA IDs; excluded from every fix dispatch while independent failing edges remain eligible
- `auto_generated` — whether this run generated the plan (drives the graceful thin/coverage-zero exit vs. error)
- `fix_touched_files` — tracked paths the loop's own fixes edited (post-fix modified minus pre-loop dirt); the set scoped recovery restores
- `iterations[]` and `dispatch_count` — iteration results and running dispatch total

The human-facing **Loop History** section is appended to the report (one row per iteration); the sidecar is the authoritative machine state.

**Limitations (v1, accepted for scope):**

- **Scenario-level crediting:** an issue is fixed iff its whole scenario passes; intra-scenario partial progress (e.g., main flow fixed but edge case still failing) is shown in Loop History but not separately credited
- **Cross-section regressions:** regressions within a section are caught each iteration; cross-section regressions only at the final full run
- **Verifier-gaming:** the loop defends against payload-literal hardcoding via the anti-hardcoding warning, but a capable fixer with visibility to deterministic scenarios can make a scenario pass without a real fix; the default `approve` gate is the runtime mitigation; randomized re-verification is planned for v2
- **Mutation guard scope:** is a static pre-classification; it reduces but cannot eliminate side effects; the test DB should be disposable

### `/qa:loop — manual verification`

Before integrating, verify these five manual checks:

1. **Deterministic fix → loop reaches green:** create a plan with a failure that has a known, deterministic source-level root cause; run `/qa:loop --mode auto` with a simple fix in place; confirm the loop reaches "all passing" and the final run writes `**Status:** ✅ Fixed` on the issue.

2. **Status written only from final run:** run `/qa:loop` with multiple iterations; check that no `**Status:**` lines appear in Loop History rows or mid-loop reports; only the authoritative final run writes Status.

3. **Hardcoding warning does not block correct fix:** create a fix that legitimately contains the expected status code or response field that happens to match a scenario payload; run the loop and confirm (a) the anti-hardcoding warning fires; (b) the fix is not blocked; (c) a correct fix containing that literal still re-runs and can pass.

4. **Environment guard aborts on non-loopback:** attempt `/qa:loop` against a plan with a non-loopback URL (`staging.example.com`) without `--allow-host staging.example.com`; confirm the loop aborts with "Base URL resolves to non-loopback host 'X'…" (fail-closed).

5. **Reuse/adopt idempotency preserves manual Status:** run `/qa:loop` once, then manually add `**Status:** ✅ Fixed (YYYY-MM-DD)` to one issue in the report; run `/qa:loop` again on the same plan with hash match (no plan change); confirm the Status line is preserved (not overwritten or lost) and the sidecar re-uses the existing scenario→QA-ID map.

### Coverage honesty (2.3.0)

`/qa:loop` now reports what it actually verified, not just whether all scenarios passed.

**Coverage block.** Every Loop Summary includes a `## Coverage` block:

```
## Coverage
- Exercised: <N> feature · <M> sanity · <K> enforcement
- Not verified: auth-unverified <N> · need-info <M> · mutation-guard SKIP <K> · tool-unavailable <J> · …
- Confidence: high | low — <reason>
```

"Exercised" (not "Verified") because a feature PASS means the endpoint was reached and returned a non-4xx — an upper bound on true verification (see `auth-unverified` below).

**Shallow-coverage WARNING.** When no feature scenario passed (every feature scenario was `auth-unverified`, `need-info`, skipped, or failed) but ≥1 feature scenario existed, the loop emits:

> Warning: shallow coverage — no feature behavior was exercised (N feature scenarios were auth-unverified/skipped/unreachable). This green reflects infrastructure and enforcement checks only.

This WARNING is **provenance-independent**: it fires in `--mode approve`, `--mode step`, and `--mode auto`, and on both user-authored and auto-generated plans. It does **not** fire on the legitimate mutation-guard-only all-SKIP graceful path (that already has its own message), nor on a plan that contains zero feature scenarios.

**Low-confidence green (auto-generated plans only).** On a zero-failure exit with shallow coverage on an auto-generated plan, the "All passing" message is replaced with:

> All assertions passed, but coverage is shallow — no feature behavior was exercised (see Coverage). Low-confidence green: the plan was auto-generated and may not reflect runtime auth/setup.

The exit is still success; only the wording changes. A user-authored plan keeps the plain "All passing" message alongside the Coverage block.

**`auth-unverified` outcome.** When a BE feature scenario gets HTTP 401 or 403 (instead of the expected 2xx), the orchestrator reclassifies its **main flow** as `auth-unverified` at ingest: that feature path was gated rather than exercised. Its main-flow QA issue stays in the report but its ID enters `auth_gated_issues`, so **no mode** dispatches it to `fix-auto`. An independent edge FAIL still takes precedence over the gated main flow, mints its own issue and can reach the fixer; an edge `NEED_INFO` takes precedence over `auth-unverified` too. A scenario that expected 401 and got 401 stays a normal enforcement PASS. Full `auth-unverified` verdicts appear under Not verified in Coverage, never earn PASS or trigger regressions, and appear in the report's Skip count solely as a presentation bucket.

**Unlock hints.** When scenarios are blocked or unverified, the Loop Summary shows "Next steps to widen coverage" keyed by reason:

- `mutation-guard` (N): re-run with `--allow-mutations` (test DB must be disposable)
- `auth-unverified` (N): the app is auth-gated; exercise authenticated behavior via the project's integration/e2e suite (no `--auth-token` intake)
- `need-info` (N): names/hosts from the current gap map by kind — set/start them, restart the harness, re-run
- `tool-unavailable` (N): install/enable the missing tool
- `dispatch-exhausted`: raise `--max-dispatches`

**Reactive suggestions.** Post-baseline, when every BE scenario has `need-info kind=service` for its main flow, or every BE scenario failed with a transport reason and no response status, the loop suggests checking reachability without claiming an app crash.

**Plan-suspect guards.** Auto-generated plans bias assertions toward observable invariants. A guessed-exact scenario remains provisional: its failures are flagged for human review and excluded from automatic fixes. Independently, an issue from any plan whose *failing assertion* is `(unverified — confirm at run time)` is flagged `⚠ unverified assertion — verify before fixing` in `approve`/`step`; `auto` excludes only that QA ID, leaving grounded issues in the same scenario eligible.

**Deliberate split with `/qa:run`.** These coverage-honesty mechanisms are `/qa:loop`-only — `/qa:run` is a single-shot executor with no fix loop, so a wrong auto-generated assertion has no code to "fix" there. The split is intentional and accepted.

## Two-Phase Workflow

The plugin follows a plan-then-execute model:

1. **Plan phase** (`/qa:create-plan`) — generates a Markdown test plan for human review
2. **Execute phase** (`/qa:run`) — executes the approved plan, can run in the same or a new session

This allows reviewing and adjusting the test plan before execution.

## Test Plan Format

Plans are saved as Markdown with the following structure:

- **Setup** (optional, directly after the title) — `**Base URL:**`, required environment-variable names, services to start manually and database connections; first backticked token on a line/bullet is the value the runner reads. Declare only names actually used by scenarios, never a credential or DSN value.
- **Source** — diff origin (PR, branch, commits)
- **Changes Summary** — what changed and what needs testing
- **Blockers / Findings** — mandatory in generated plans, `None found.` if none; blocked scenarios may carry `**Blocked-by:** BLK-NN`, keeping their contract-correct expectation
- **Detected Tools** — available testing tools (Playwright, curl, psql, MCP servers, etc.)
- **FE Test Scenarios** (`FE-01`, `FE-02`, ...) — UI steps, expected results, edge cases
- **BE Test Scenarios** (`BE-01`, `BE-02`, ...) — endpoint, method, payload, expected response, DB checks, edge cases
- **Out of harness scope** (optional) — bullet-only unobservable checks with one-clause harness reasons, not FE/BE scenarios; code defects belong in Blockers

Each main `**Expected:**` and edge-case expectation carries its own `(path:line)` citation for a producer that was read or `(unverified — confirm at run time)` when it could not be read. `(exact text — brittle)` asks the tester to match quoted text as a substring. Credentials in headers and steps are `$NAME` references declared under `## Setup → **Required environment variables:**`; never use a literal credential or a `TOKEN` placeholder. `**Required databases:**` lists env var names (including `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_DATABASE`, `MYSQL_PWD` when using MySQL), or a human-declared `mcp__` server known to point to the test DB. `/qa:create-plan` does not invent an `mcp__` connection.

## Report Format

Reports use the same issue format as the code-review plugin (`### [SEVERITY] QA-NNN: Title` heading with required fields `ID`, `Location`, `Category: Testing`, `Problem`, `Remediation`). This means `/fix QA-001` and `/fix-report` from the code-review plugin work directly on QA reports. The Summary counts `Total | Pass | Fail | Skip | Need info` by full scenario verdict. Conditional `## Setup gaps` (after Summary) lists missing names/URLs by kind and scenario ID, including edge gaps, with no issues minted for missing prerequisites.

```markdown
## Summary
- Total: N | Pass: N | Fail: N | Skip: N | Need info: N

## Setup gaps
- credentials: `QA_API_TOKEN` — BE-03 (edge 1)
```

Example issue:

```markdown
### [CRITICAL] QA-001: POST /api/users returns 500 instead of 201

**ID:** QA-001
**Location:** `src/api/users.py:45`
**Category:** Testing

**Problem:**
- Expected: POST /api/users with valid body should return 201 and create the user. (src/api/users.py:45)
- Actual: Endpoint returns 500 with `KeyError: 'email'` raised in `users.py:48`.
- Refutation: re-verified: yes (state re-read, no re-fire); env: n/a; scope: in; harness: ok

**Impact:**
Blocks new account creation.

**Remediation:**
Schema requires `email` but the `create_user` handler does not validate the key's presence. Add Pydantic field validation or an early 422 return for the missing field.

**Scenario:** BE-03 — Create new user with valid payload
**Response:** `{"detail": "Internal Server Error"}`
```

QA-specific extras (`Scenario`, `Response`, `Screenshot`) are kept for testing context; the code-review parser ignores unknown fields.

**Severity levels:**

| Severity | Criteria |
|----------|----------|
| CRITICAL | HTTP 500, server crash, data loss, security bypass |
| HIGH | Wrong status code, incorrect data returned |
| MEDIUM | Degraded UX, missing validation feedback |
| LOW | Cosmetic issues, minor text problems |

An issue whose failing assertion is tagged `(unverified — confirm at run time)` is LOW unless an observed HTTP status ≥ 500 or a crash/stack trace invokes the normal severity rules. The issue's Expected bullet retains the plan's tag verbatim; when a scenario has `**Blocked-by:** BLK-NN`, Location is the blocker's `(file:line)` and Actual identifies the blocker.

## Synergy with code-review

When the `code-review` plugin is also installed, QA-detected issues become repairable through the same workflow as `/review` findings:

- **`/fix QA-001`** — the `/fix` command routes by ID prefix; `QA-NNN` reads the newest report from `docs/testing/reports/`. Other prefixes continue to read from `docs/reviews/`.
- **`/fix-report`** (no argument) — auto-merges the newest report from `docs/reviews/` and the newest from `docs/testing/reports/` into a single checklist. Status writes go back to the originating file.
- **`/fix-report docs/testing/reports/<file>.md`** — explicit single-file mode also works on QA reports.

A typical end-to-end flow:

```bash
/qa:create-plan
/qa:run                 # produces docs/testing/reports/...
/review                 # produces docs/reviews/...
/fix-report             # auto-merge — fix issues from both reports in one pass
```

For full details on `/fix` routing and `/fix-report` auto-merge, see [code-review.md](code-review.md).

## Adaptive Tool Detection

The plugin detects available tools at plan creation and re-validates before execution:

| Tool | Purpose | Detection |
|------|---------|-----------|
| Playwright MCP | FE testing (navigation, clicks, forms) | MCP tool availability |
| curl / httpie | API requests | `command -v` |
| psql / sqlite3 / mysql | Database verification (CLI) | `command -v` |
| Database MCP servers | DB verification only if declared in `## Setup → **Required databases:**` as bound to the test DB | MCP tool availability |
| perl with `JSON::PP` | Fail-closed BE response sanitiser | `perl -MJSON::PP -e 1` |
| jq | JSON response parsing | `command -v` |

**Database access:** a tester uses only a connection named under `## Setup → **Required databases:**` — a declared `mcp__` server, or declared env-var connection names with the corresponding CLI client. A preconfigured but undeclared MCP server is never selected. With no declared connection or an unavailable DB client, only the `**DB check:**` field is SKIP; a runnable HTTP request still executes.

If a required browser, HTTP client or `perl`/`JSON::PP` is unavailable at run time, affected scenarios return `NEED_INFO kind=tool` and appear under `## Setup gaps`, not SKIP. An unavailable tool is recorded under `## Detected Tools` during plan authoring; plans do not label their scenarios `(skip — <tool> unavailable)`.

## Skills

The qa plugin ships these skills. `loop-engineering`, `reader-context-hygiene`, `report-format`, and `test-plan-format` load with the plugin; `state-combination-planning` is loaded conditionally in `/qa:create-plan` for two or more independent boolean inputs. `fe-testing` and `be-testing` are scoped to the `qa:fe-tester` and `qa:be-tester` agents and load on demand inside them (declared via `skills:` in each agent's frontmatter), not ambiently across the plugin.

| Skill | Loaded | Purpose |
|-------|--------|---------|
| `loop-engineering` | With plugin | Doctrine for authoring robust closed agent loops — the minimum-bar checklist, the ground-truth oracle taxonomy, and the anti-patterns, anchored to `/qa:loop` as the reference implementation. |
| `reader-context-hygiene` | With plugin | Doctrine for authoring fan-out reader/scout agents — bulk evidence to disk, decision-relevant signals inline, fail-closed on access failure, declared truncation. |
| `report-format` | With plugin | Test report format with `QA-XXX` issue IDs, compatible with the code-review plugin. |
| `test-plan-format` | With plugin | Test plan structure produced by `/qa:create-plan` and consumed by `/qa:run` and `/qa:loop`. |
| `state-combination-planning` | `/qa:create-plan` on demand | Enumerates the $2^N$ combinations of independent boolean inputs and records a scenario or disposition for each row. |
| `fe-testing` | `qa:fe-tester` agent | Frontend test-execution guidance using Playwright MCP — navigation, interaction, assertions, and screenshots on failure. |
| `be-testing` | `qa:be-tester` agent | Backend test-execution guidance — API request construction, response verification, database state checks, error-path testing, and adaptive CLI/MCP tool detection. |

<a id="upgrade-notes"></a>
## Upgrade Notes

**`qa` 2.7.0:** Runtime base URLs no longer come from `.env` or project config: declare `**Base URL:**` under `## Setup`, provide a URL in the plan's Source/scenarios, or set `QA_BASE_URL`. Declare credentials under `## Setup` and reference them as `$NAME` in scenarios; testers no longer read `.env` or mint tokens outside explicit scenario steps. Export declared env vars in the shell that **launches** the harness; missing ones abort before tester dispatch, and changes require a restart. DB checks use only declared connections — an available MCP server is no longer picked up automatically, and MySQL needs `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_DATABASE` and `MYSQL_PWD`. A missing browser or HTTP client now returns `NEED_INFO kind=tool` rather than SKIP, and reports count Need info separately with a conditional `## Setup gaps` section. Screenshots are `<ID>-fail.png`; backend response dumps are `<ID>-body.json`. BE responses pass through a fail-closed sanitiser that withholds non-JSON and bare-string bodies; `perl` with `JSON::PP` is now required for BE testing. The loop prompts to retry/continue/abort on baseline setup gaps in interactive modes, and does not auto-fix unverified assertions or auth-gated main-flow issues.

**`qa` 2.6.0 pairs with `code-review` ≥ 2.0.0 wherever a shared report carries a decision-stage rejection.** That is the precondition, and it is worth stating plainly: `**Fix-policy:** needs-decision` is emitted by `code-review`'s own producers alone — today, reports written by `/review` — while `/qa:run` and `/qa:loop` never write the field, and an absent field is `auto` by both fix commands' fail-safe. A report this plugin produces therefore cannot presently reach the decision gate, and cannot acquire a `🚫 Rejected` status or any of the loop-written decision fields. `qa` 2.6.0's handling of them is **forward compatibility** for a schema the QA producers do not yet emit.

Where the state does arise — a `/review` report fed through the decision stage and then re-rendered by this plugin — the pairing binds: `code-review` 2.0.0 adds a `🚫 Rejected` status to reports it shares with this plugin, and `/qa:loop` on `qa` ≥ 2.6.0 knows to read it as terminal and preserve the line. An older `/qa:loop` (< 2.6.0) does not: its Step 4.1 in-place Status update overwrites a `🚫 Rejected` line and its reason whenever a sibling issue passes on the same scenario in a later iteration, silently discarding the rejection. So keep both plugins on paired minimums (`code-review` ≥ 2.0.0, `qa` ≥ 2.6.0) for any report that can carry a rejection. This is milder than `code-review`'s own intra-plugin skew — an older `code-review` reader can silently re-offer and dispatch a rejected finding, which is worse, and which is unconditional rather than waiting on a producer that does not exist yet. See [code-review.md's Upgrade Notes](code-review.md#upgrade-notes) for the fuller detail.

## Prerequisites

- **Server must be running** — the plugin does not start/stop application servers; declare bring-up under `## Setup → **Required services:**`
- **Declared env vars** — export names under `## Setup` in the shell that launches the harness; restart the harness after changing them
- **Database connection** — for DB verification, declare its env var names or test-DB-bound `mcp__` server under `## Setup → **Required databases:**`; otherwise the DB check is SKIP
- **Playwright MCP** — required for FE testing in Claude Code (without it FE scenarios return `NEED_INFO kind=tool`); Oh My Pi uses its built-in browser instead, see [Oh My Pi](#oh-my-pi)
- **HTTP client** — at least `curl` or `httpie` for BE testing (without either BE scenarios return `NEED_INFO kind=tool`)
- **perl with `JSON::PP`** — required by the fail-closed BE response sanitiser (without it BE scenarios return `NEED_INFO kind=tool`)

## Oh My Pi

Install with `omp plugin install qa@av-marketplace`. If you added the marketplace earlier, first run `omp plugin marketplace update av-marketplace`. The commands are `/qa:create-plan`, `/qa:run`, and `/qa:loop`.

Both `qa:fe-tester` and `qa:be-tester` run through the `tester` model role (`modelRoles.tester` in `~/.omp/agent/config.yml`). Without that mapping, OMP falls back to the `opus` selector, then to the session model.

In OMP, FE scenarios use `eval`'s `browser` global, which runs in the browser OMP's settings select (managed Chromium only when no relay, CDP URL, or cmux browser is selected), not Playwright MCP. For QA runs, set `browser.relay` and `browser.cmux` to `false` and unset `browser.cdpUrl` so scenarios do not use your own or an attached browser. FE testing needs `browser.enabled` in place of Playwright MCP: with it off, `eval` has no `browser` global and the FE tester returns `NEED_INFO` (kind `tool`) for every FE scenario. With `browser.enabled` (on by default), OMP removes Playwright MCP servers from the session; no Playwright MCP setup is needed, and a configured `@playwright/mcp` server is not used. Credential fields are filled from `process.env` inside a JavaScript `eval` cell, keeping the values out of the tester's output; OMP's Python eval kernel allow-lists its environment and does not carry `QA_*` names. BE scenarios use the same CLI clients as in Claude Code. OMP gives every subagent all MCP servers configured for the session, so both `qa:fe-tester` and `qa:be-tester` can call any of them (a `tools:` list cannot narrow this); the BE tester uses only DB connections declared in `## Setup`. Before running `/qa:run` or `/qa:loop` against code you do not trust, remove write-capable MCP servers from the OMP config. Screenshots of failed FE scenarios go to `docs/testing/reports/screenshots/`.

`/qa:loop` dispatches `code-review:fix-auto` and requires `code-review@av-marketplace` to be installed. In OMP, `/fix QA-001` is `/code-review:fix QA-001`, and `/fix-report` is `/code-review:fix-report`.

# QA Plugin

Automated QA testing — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports with unique issue IDs compatible with code-review's `/fix QA-001` and `/fix-report` auto-merge.

**Version:** 2.1.0

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
1. Resolves the diff source (PR, branch, commits, or staged changes)
2. Classifies changed files as FE or BE based on file extensions and paths
3. Reads related files for context (routers, models, schemas, docs, OpenAPI specs)
4. Detects available testing tools (Playwright MCP, curl/httpie, psql/sqlite3/mysql, database MCP servers)
5. Generates the test plan using scenario conventions (`FE-XX` for frontend, `BE-XX` for backend)
6. Saves the plan to `docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md`
7. Proposes running `/qa:run` to execute the plan

### `/qa:run`

Execute a test plan by launching FE and BE testing agents in parallel and generating a report.

```bash
# Run the most recent test plan
/qa:run

# Run a specific test plan
/qa:run docs/testing/plans/2026-04-07-user-auth-test-plan.md
```

The command:
1. Loads and parses the test plan
2. Re-validates tool availability (tools may have changed since plan creation)
3. Launches testing agents in parallel:
   - **fe-tester** — executes FE scenarios via Playwright MCP (navigation, clicks, form fills, snapshot verification)
   - **be-tester** — executes BE scenarios via HTTP clients and database queries
4. Collects results from all agents
5. Generates a report with `QA-XXX` issue IDs and severity levels
6. Saves the report to `docs/testing/reports/YYYY-MM-DD-<topic>-report.md`

### `/qa:loop`

Close a test → fix → retest loop: run a QA plan, auto-fix failures via `code-review:fix-auto`, re-run affected sections, and repeat until all issues pass or the budget is exhausted.

```bash
# Run the most recent test plan in default mode (approve — one batch HITL gate)
/qa:loop

# Run a specific plan in automatic mode (headless, no HITL gates)
/qa:loop docs/testing/plans/2026-06-17-user-auth-test-plan.md --mode auto

# Strict: max 2 iterations, 20 dispatches, step-by-step approval
/qa:loop --mode step --max-iterations 2 --max-dispatches 20

# Allow state-changing BE scenarios (POST/PUT/PATCH/DELETE) and non-loopback hosts
/qa:loop --allow-mutations --allow-host staging.example.com

# Only fix CRITICAL and HIGH issues; set a 30-minute time budget
/qa:loop --severity HIGH --time-budget 1800
```

**Invocation & flags:**

```
/qa:loop [plan-path] [--mode approve|auto|step] [--max-iterations N] 
         [--max-dispatches D] [--time-budget S] [--severity LEVEL] 
         [--allow-mutations] [--allow-host HOST]
```

| Argument | Interpretation | Default | Rules |
|----------|---|---|---|
| (empty) | Find the newest plan in `docs/testing/plans/` | — | If no plan found, prints "Run `/qa:create-plan` first." and stops |
| `<path>` | Use the specified test plan file | — | File must exist and be readable |
| `--mode` | Loop mode: `approve` (batch HITL), `auto` (headless), `step` (per-fix HITL) | `approve` | Case-sensitive; unknown value → error; `approve`/`step` require interactive session (TTY); headless → error |
| `--max-iterations` | Maximum loop iterations | 3 | Must be positive integer; invalid → error |
| `--max-dispatches` | Maximum fix-auto + tester launches combined | 50 | Must be positive integer; soft limit at iteration boundaries; final run always runs (not gated) |
| `--time-budget` | Wall-clock seconds before timeout | 1800 | Must be positive integer; error on invalid |
| `--severity` | Minimum severity to credit as fixed: `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` | (none = all) | Case-insensitive; unknown value → error |
| `--allow-mutations` | Permit state-changing BE scenarios (POST/PUT/PATCH/DELETE, DB writes) | (off) | Present → on; absent → off; no value needed; **note: test DB must be disposable (no rollback)** |
| `--allow-host` | Whitelist additional hosts beyond loopback | (loopback only) | Repeatable; each invocation appends; format: hostname or IP |

**Modes:**

| Mode | Behavior | HITL | Headless-Safe |
|---|---|---|---|
| **approve** *(default)* | Single batch approval before fixing; shows fix-set + warnings | Yes (one gate) | No — requires TTY |
| **auto** | No HITL gate; prints scope banner; abort via Esc | No | Yes — headless safe |
| **step** | Approve before each re-test (maximum control) | Yes (per iteration) | No — requires TTY |

**Headless behavior:** if `--mode approve` or `--mode step` and stdin is not a TTY (non-interactive session) → abort with "approve/step require an interactive session; use --mode auto."

**Algorithm summary:**

1. **Resolve & Validate** — Parse arguments, resolve base URL with fail-closed safety, enforce environment guard (loopback-only unless `--allow-host`), hash the plan
2. **Baseline Run** — Execute all FE and BE scenarios (mutation guard skips state-changing scenarios unless `--allow-mutations`); render QA-XXX report
3. **Loop Iterations** — For each iteration (bounded by `--max-iterations`, `--max-dispatches`, `--time-budget`):
   - Select failing scenarios at/above `--severity` threshold
   - Pre-filter issues with missing Location or required fields (report as "needs manual location"; never dispatch)
   - HITL gate per `--mode` (approve: one batch; step: per re-test; auto: no gate)
   - Auto-fix each selected issue via `code-review:fix-auto` (source-only constraint injected)
   - Anti-hardcoding warning: flag added literals matching scenario request-payloads (human-review only; not a credit block)
   - Re-run the affected FE and/or BE section(s) (dependency-safe; whole section per section)
   - Update sidecar with iteration results and append Loop History row
   - Stop if: no scenario newly passed, oscillation detected (regression), or any budget exhausted
4. **Final Run** — Unless zero-failure exit fired: re-run the entire plan once (authoritative source of truth)
   - Write `**Status:** ✅ Fixed (YYYY-MM-DD)` on QA-XXX issues from scenarios that pass
   - Report any regressions (scenarios that passed at baseline but failed in final run) as new QA-XXX IDs
5. **Summary** — Loop History table, final pass/fail counts, fixed/remaining/warnings/regressions, dispatch & time budget used

**Safety guards (all modes):**

- **Environment guard:** base URL must resolve to loopback (`localhost`, `127.0.0.1`, `::1`, `*.localhost`) or be in `--allow-host`, else **abort**
- **Mutation guard:** state-changing BE scenarios (HTTP POST/PUT/PATCH/DELETE or DB-write checks) SKIP with reason `mutation-guard` unless `--allow-mutations` is set; their issues reported as "needs --allow-mutations"; never counted as fixed
- **Location pre-filter:** issues with `Location: unknown:0` or missing Location/Problem/Remediation are dropped from the fix-set and reported as "needs manual location"
- **Anti-hardcoding warning:** a heuristic check (not a credit gate) flags fixes where added source literals match scenario request-payload values; surfaced for human review in `approve` mode, logged in auto/step

**Sidecar & state:**

The command owns a machine-state JSON file: `docs/testing/reports/<topic>-loop-state.json`

Contains:
- `plan_sha256` — fingerprint to detect plan tampering (cross-run or mid-run)
- `scenario_issues` — scenario-id → [QA-IDs] map
- `baseline` — baseline pass/fail for each scenario
- `iterations[]` — per-iteration results (attempted fixes, now-passing, still-failing, warnings, dispatches)
- `dispatch_count` — running total

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

## Two-Phase Workflow

The plugin follows a plan-then-execute model:

1. **Plan phase** (`/qa:create-plan`) — generates a Markdown test plan for human review
2. **Execute phase** (`/qa:run`) — executes the approved plan, can run in the same or a new session

This allows reviewing and adjusting the test plan before execution.

## Test Plan Format

Plans are saved as Markdown with the following structure:

- **Source** — diff origin (PR, branch, commits)
- **Changes Summary** — what changed and what needs testing
- **Detected Tools** — available testing tools (Playwright, curl, psql, MCP servers, etc.)
- **FE Test Scenarios** (`FE-01`, `FE-02`, ...) — UI steps, expected results, edge cases
- **BE Test Scenarios** (`BE-01`, `BE-02`, ...) — endpoint, method, payload, expected response, DB checks, edge cases

## Report Format

Reports use the same issue format as the code-review plugin (`### [SEVERITY] QA-NNN: Title` heading with required fields `ID`, `Location`, `Category: Testing`, `Problem`, `Remediation`). This means `/fix QA-001` and `/fix-report` from the code-review plugin work directly on QA reports.

Example issue:

```markdown
### [HIGH] QA-001: POST /api/users returns 500 instead of 201

**ID:** QA-001
**Location:** `src/api/users.py:45`
**Category:** Testing

**Problem:**
- Expected: POST /api/users with valid body should return 201 and create the user.
- Actual: Endpoint returns 500 with `KeyError: 'email'` raised in `users.py:48`.

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
| CRITICAL | Server crash, data loss, security bypass |
| HIGH | Wrong status code, incorrect data returned |
| MEDIUM | Degraded UX, missing validation feedback |
| LOW | Cosmetic issues, minor text problems |

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
| Database MCP servers | Database verification (pre-configured) | MCP tool availability |
| jq | JSON response parsing | `command -v` |

**Database access priority:** MCP server > CLI client > SKIP

If a required tool is unavailable, affected scenarios are marked as SKIP (not FAIL).

## Prerequisites

- **Server must be running** — the plugin does not start/stop application servers
- **Database must be accessible** — for DB verification scenarios
- **Playwright MCP** — required for FE testing (FE scenarios are skipped without it)
- **HTTP client** — at least `curl` or `httpie` for BE testing (BE scenarios are skipped without either)

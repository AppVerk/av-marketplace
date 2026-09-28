---
description: "Closed test-fix-retest loop — run a QA plan, auto-fix failures via fix-auto, re-run affected sections, and repeat until green or budget exhausted."
argument-hint: "[plan path] [--mode approve|auto|step] [--max-iterations N] [--max-dispatches D] [--time-budget S] [--severity LEVEL] [--allow-mutations] [--allow-host HOST] [--auto-plan] [--no-auto-plan] [--allow-dirty]"
---
> **OMP edition — generated file, do not edit.** Source of truth: `plugins/qa/commands/loop.md`; regenerate with `python3 scripts/build_omp_edition.py`.
>
> The instructions below were written for Claude Code. In this harness, read their tool references as follows:
>
> - **Task tool** with `subagent_type: "<plugin>:<agent>"` → call `task` with `agent: "<plugin>:<agent>"` (the id is unchanged) and the prompt as the item's `task`. `run_in_background` has no equivalent: `task` runs asynchronously and results are delivered when agents finish. "Dispatch in parallel" means one `task` call with several items.
> - **TaskCreate / TaskUpdate / TaskList** → the `todo` tool: `init` with the listed subjects, `start` / `done` by subject text, `view` to list. `activeForm` has no equivalent. A subagent has no `todo` tool: when running as one, skip these progress-tracking steps and do the work they announce.
> - **AskUserQuestion** → the `ask` tool. `multiSelect: true` → `multi: true`.
> - **Skill tool**, `Skill(skill: "<name>")`, or a skill cited as `<plugin>:<name>` → `read skill://<plugin>:<name>`. Every skill is addressed with its plugin prefix; a skill named without one belongs to this plugin, so read `skill://qa:<name>`.
> - In an agent's instructions, `ARGUMENTS` (prefixed with a dollar sign) stands for the task text you were given.
> - **WebSearch** → `web_search`. **WebFetch** → `read` on the URL.
> - A subagent has no `ask` tool: where the instructions say to ask the user, choose the most likely option and state the choice and its reason in your report.
> - **allowed-tools** and `Bash(<cmd>:*)` grants are Claude Code permission pre-approvals. They grant and restrict nothing here.
> - **`mcp__<server>` and `mcp__<server>__*` grants** are not carried over: a subagent here gets every MCP tool of the session whatever its `tools:` list says, and a server the session has not configured is simply absent. MCP tools are named `mcp__<server>_<tool>` here (one underscore between server and tool), not `mcp__<server>__<tool>`.
> - **Playwright MCP** (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, `browser_type`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_evaluate`, `browser_wait_for`, `browser_take_screenshot`, and any `mcp__playwright*` or `mcp__plugin_playwright_playwright*` tool) → the `browser` global inside `eval`, which uses the browser OMP's settings select (managed Chromium only when no relay, CDP URL, or cmux browser is selected; while `browser.enabled` is on, OMP removes Playwright MCP servers from the session). For QA runs, set `browser.relay` and `browser.cmux` to `false` and unset `browser.cdpUrl` so FE scenarios do not act through your own or an attached browser. Read `xd://eval/browser` before the first browser step. Open one tab per run, `tab = await browser.open(name="qa", url=<url>, app={"relay": False})`, then navigate with `await tab.goto(url)`; a probe such as "try `browser_navigate`" is that `browser.open` call, and an exception from it means the browser is unavailable. `browser_snapshot()` → `await tab.observe()` (numeric ids for `tab.id(n)`) or `await tab.ariaSnapshot()` (`e5`-style refs for `tab.ref("e5")`); act on those handles or on selectors (`text/Sign In`, `aria/Email`, CSS) with `click`, `fill`, `type`, `select`, `press`, `hover`. `browser_evaluate(expression)` → `await tab.evaluate(expression)`. `browser_wait_for` → `await tab.waitForSelector("text/Success", timeout=5000)` or `await tab.waitForSelector(selector, hidden=True, timeout=10000)`. `browser_take_screenshot()` → `path = await tab.screenshot(format="png")` returns the saved file's path: copy it with `bash` to the path the instructions name.
> - **Slash commands** are `/<plugin>:<name>` here: `/fix`, `/fix-report`, `/fix-all`, `/review` and `/analyze-feedback` are `/code-review:fix`, `/code-review:fix-report`, `/code-review:fix-all`, `/code-review:review` and `/code-review:analyze-feedback`; a command cited with its plugin prefix, such as `/qa:run`, keeps its name.
> - In the text below, a backticked command right after `!` (for example !`git status`) is Claude Code inline context: Claude Code runs it and puts its output there before the model reads the text. Here nothing ran: run each such command in the text below with `bash` first and use its output in its place.

# QA Loop Command

Execute a closed test → fix → retest loop. Runs a QA plan, identifies failures, auto-fixes issues via `code-review:fix-auto`, re-runs affected scenarios, and repeats until all issues pass or the budget is exhausted.

This command orchestrates existing agents (`qa:fe-tester`, `qa:be-tester`, `code-review:fix-auto`) and applies strict safety guards (environment, mutation, budget) to prevent uncontrolled loops.

> **Doctrine:** the loop-engineering discipline this command implements — oracle taxonomy, the minimum-bar checklist, and the anti-patterns — is documented in the `qa:loop-engineering` skill.

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

This generates a plan in place of the dead-stop, mirroring the `qa:test-planner` agent's Draft workflow (Steps 2–7) but **only the current-branch-vs-default-branch path**. It runs in this session: it does not dispatch the planner, does not run `/qa:create-plan`'s plan review, and skips create-plan's progress tasks (reuse this loop's tracker) and its "run `/qa:run`" prompt (that contradicts continuing the loop here).

1. **Resolve the default branch** (the `--short` form returns `origin/master`, so the `origin/` strip is required; do **not** use `sed`):

   ```bash
   BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); BASE=${BASE#origin/}
   [ -z "$BASE" ] && git rev-parse --verify main   >/dev/null 2>&1 && BASE=main
   [ -z "$BASE" ] && git rev-parse --verify master >/dev/null 2>&1 && BASE=master
   [ -z "$BASE" ] && BASE=main
   ```

2. **Get the diff + changed files** (source is fixed to current-branch-vs-default — do **not** inline the planner's PR / `last-N` / staged dispatch):

   ```bash
   git diff "$BASE"...HEAD
   git diff --name-only "$BASE"...HEAD
   ```

3. **Analyze & detect tools.** Classify each changed file as FE or BE using the planner's indicators (its Step 3), and detect available testing tools (Playwright MCP, HTTP client, DB access) as in `/qa:create-plan` Step 2. Then render the plan body using the format skill:

   ```
   Skill(skill: "test-plan-format")
   ```

   Fill `## Source` (Type: branch `<current>`, Base: `$BASE`, Date), `## Changes Summary`, `## Detected Tools`, and the FE/BE scenario sections per the skill (including its section-omission rules).

   Apply the planner's Steps 2.5, 4 item 6, 4.5, 4.6 and 6.5 before saving: pin the intended contract, ground every assertion, scan blockers, ground the environment, then refute the plan's apparent passes. Emit `## Setup` when needed, mandatory `## Blockers / Findings`, and assertion-level grounding tags; record bring-up only as a human `Required services` prerequisite.

4. **Construct the path before writing** (bind it explicitly — there is nothing to "capture afterward"), then **Write** the plan to that literal path with the Write tool:

   ```bash
   mkdir -p docs/testing/plans
   DATE=$(date +%Y-%m-%d)
   # choose <topic> slug (lowercase, hyphens) from the changes
   plan_path="docs/testing/plans/${DATE}-<topic>-test-plan.md"
   ```

   Do **not** re-glob `ls -t` to locate the file afterward — write to and keep this exact `plan_path`.

5. **Provenance.** The sidecar created for this run (Step 1.3) records **`auto_generated: true`** for an auto-plan-generated plan. (A user-provided plan leaves it `false`/absent.)

**Assertion fidelity (auto-plan only).** Bias generated assertions toward observable invariants the generator can be confident about (non-5xx, no stack-trace/secret leak in the body, auth-gate present) over guessed exact path+status. Where an exact value must be asserted that the generator could not observe, mark that scenario **provisional**, tag every guessed exact value `(unverified — confirm at run time)` as well, and generate it as its **own** scenario (never co-located with a robust invariant, so Step 3a's scenario-level exclusion can't drop a real finding). The provisional split happens **before** BE-NN/FE-NN numbers are assigned; number once over the final set; collect the provisional IDs. (Also note the provisional IDs in the surfacing output so they survive to Step 1.3 across a context loss.)

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

1. **`## Setup`:** the first backticked token on its `**Base URL:**` line.
2. **Plan URLs:** the first `http://` or `https://` URL in `## Source` or a scenario heading/bullet.
3. **`QA_BASE_URL`:** non-empty environment variable.

Never read project config files (`.env` or framework/build config) at run time. Parse `## Setup` once using the first backticked token of each bullet under `**Required environment variables:**` and `**Required databases:**`. A `**Required environment variables:**` name must match `^QA_[A-Z0-9_]+$`. A `**Required databases:**` bullet must be such a `QA_` name, one of `PGHOST`, `PGUSER`, `PGDATABASE`, `PGPASSWORD`, `SQLITE_DB`, `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_DATABASE`, `MYSQL_PWD`, or an `mcp__` server name. Warn about and ignore any other bullet (`Warning: ignoring Setup name '<token>' — not a QA_ name or a supported database name.`): the plan is repository content, and the namespace keeps it from naming an unrelated secret of the launching shell (`GH_TOKEN`, a cloud key) as a credential. For a PostgreSQL DB check require all four `PGHOST`, `PGUSER`, `PGDATABASE`, `PGPASSWORD` declarations; if incomplete, run HTTP but mark the DB check `SKIP — incomplete PostgreSQL connection under ## Setup`. Preserve `## Setup` verbatim for all dispatches, or pass `Setup: none declared`. BE receives only the valid declared database names in `DB connection:`, or `none declared`.

If none resolves, abort with exactly:

> Error: Base URL undetectable. Cannot guarantee loopback-only safety. Explicitly set QA_BASE_URL, add a Base URL to the plan's ## Setup section, or use --allow-host.

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

#### Step 0.4.5: Preflight declared prerequisites

Before **any** tester dispatch, check the presence of every validated env var name under `## Setup → Required environment variables` and `Required databases`. Skip `mcp__` bullets. Run one Bash line per name with the name substituted literally, reporting only its name and presence:

```bash
[ -n "${QA_API_TOKEN:-}" ] && printf 'QA_API_TOKEN: OK\n' || printf 'QA_API_TOKEN: MISSING\n'
```

If any name is `MISSING`, abort before dispatch and print exactly (substituting the count and missing names):

```text
⚠️ Cannot start QA — <N> required value(s) missing:
  • <NAME_1>
  • <NAME_2>
Set them in the shell that launches the harness (`export NAME=…`), restart it, then re-run the command. Environment variables are captured at process start; exporting them in a running session has no effect.
```

No Setup or no env-name bullets → proceed without preflight. Do not probe service/database liveness: the tester returns NEED_INFO if a service is absent at run time.

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

Read `scenario_issues` (scenario-id → [QA-IDs]) and `issue_assertion` (QA-ID → main scenario ID or `<ID> (edge n)`) from the sidecar, plus the report's existing `**Status:**` lines. New issues will be assigned IDs at `max(existing_ids) + 1`. For a sidecar written before `issue_assertion` existed, reconstruct missing entries **once** from the report's `**Scenario:**` and `Problem` → `Expected` against the plan's main `**Expected:**` and ordered edge assertions, only when the match is unique. Never infer main versus edge from QA-ID order; leave ambiguous IDs unmapped for the Step 3a safety filter.

**If the sidecar matches but `report_file` is missing or empty** (the report was deleted out from under the sidecar), fall through to a FRESH render but carry the sidecar's existing IDs — new IDs still continue at `max + 1` so they never collide with the sidecar's `scenario_issues`.

**Case 2: Sidecar absent but report exists**

If `report_file` exists but `sidecar_file` does not:

```bash
# ADOPT — import QA-XXX IDs and Status lines from the report
# Create a fresh sidecar stamped with the current PLAN_HASH
```

Read the report, extract all `### [SEVERITY] QA-NNN:` headings and any `**Status:**` lines, and build `scenario_issues`. Reconstruct `issue_assertion` from each issue's `**Scenario:**` and `Problem` → `Expected` against the plan as in Case 1; ambiguous IDs remain unmapped. Create the sidecar with these IDs; leave `baseline`/`current` to be populated by the authoritative baseline run (Step 2.3).

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
  "issue_assertion": { "QA-001": "BE-03 (edge 2)", "QA-002": "BE-03", "QA-003": "FE-05" },
  "scenario_kind": { "BE-03": "negative", "BE-04": "feature" },
  "scenario_reason": { "BE-04": "need-info", "FE-05": "cannot-confirm" },
  "provisional_scenarios": [],
  "unverified_issues": [],
  "auth_gated_issues": [],
  "need_info": { "BE-04": { "kind": "credentials", "missing": ["QA_STRIPE_TEST_KEY"] }, "BE-03 (edge 2)": { "kind": "fixture", "missing": ["users.seed"] } },
  "baseline": { "FE-01": "pass", "BE-03": "fail", "BE-04": "need-info", "FE-05": "fail" },
  "current": { "FE-01": "pass", "BE-03": "fail", "BE-04": "need-info", "FE-05": "fail" },
  "auto_generated": false,
  "pre_loop_dirty": [],
  "fix_touched_files": [],
  "dispatch_count": 0,
  "iterations": []
}
```

**When writing the sidecar:** set `auto_generated` to `true` if this run generated the plan in Step 0.2.1, else `false` (the example above shows the default) — do not take the literal `false` as unconditional. Persist `pre_loop_dirty` (recorded in Step 0.1.5). On the REUSE/ADOPT idempotency paths (Step 1.2), **preserve** the existing `auto_generated` value rather than overwriting it. Persist `provisional_scenarios` (the IDs decided in Step 0.2.1; empty array if not auto-generated), `issue_assertion`, `unverified_issues` and `auth_gated_issues` (QA IDs identified in Step 2.2); on REUSE/ADOPT preserve these and the unaffected `need_info` entries. Do NOT write at Step 0.2.1 — the sidecar does not exist yet.

- `plan_sha256`: the 64-hex SHA-256 hash of the plan file
- `plan_path`: path to the test plan
- `report_file`: path to the QA report (no `docs/testing/reports/` prefix in the sidecar; store absolute or relative from root)
- `topic`: extracted from the plan filename
- `created`: date stamp (YYYY-MM-DD)
- `scenario_issues`: map of scenario-id → array of QA-XXX IDs assigned to that scenario
- `issue_assertion`: one-to-one map of QA-XXX ID → the scenario's main-flow ID or `<ID> (edge n)` for its failing edge assertion (1-based plan order, same keys as `need_info`). Set it when an issue is assigned or reconciled, **not** by assuming the first `scenario_issues[ID]` entry is the main flow. Preserve mappings when an assertion later passes; a later main-flow failure may receive a higher QA ID than an earlier edge failure. Each mapped QA ID belongs to its `scenario_issues` owner; no two QA IDs may claim the same assertion key.
- `scenario_kind`: map of scenario-id → "sanity" | "negative" | "feature" (set once at baseline ingest, Step 2.1; classifies what a PASS means for coverage)
- `scenario_reason`: map of scenario-id → normalized reason for every non-pass verdict ("mutation-guard" | "need-info" | "auth-unverified" | "tool-unavailable" | "cannot-confirm" | "transport"); refreshed per scenario on ingest; drives Coverage and unlock hints
- `provisional_scenarios`: array of auto-generated scenario-ids whose assertions are guessed-exact (decided in Step 0.2.1, persisted here); read by Step 3a to treat their failures as plan-suspect
- `unverified_issues`: QA-XXX IDs of individual issues whose mapped assertion (main `**Expected:**` or failing edge case) is tagged `(unverified — confirm at run time)`; assigned in Step 2.2 and refreshed for returned scenarios on each later ingest using `issue_assertion`, never per whole scenario
- `auth_gated_issues`: QA-XXX IDs whose `issue_assertion` key is the bare scenario ID and whose main-flow result Step 2.1.7 reclassified as `auth-unverified`; refreshed on ingest, excluded from every fix dispatch (Step 3a), even when a failed edge makes the scenario verdict `fail`. Never include the independent edge issues.
- `need_info`: map of scenario IDs and `<ID> (edge n)` keys to `{ "kind": "credentials|service|fixture|tool", "missing": ["<identifier>", ...] }`. At **every ingest** (baseline, Step 2.1.8 retry, Step 3e, Step 4), delete entries for the scenario IDs returned in that dispatch **and their edge keys** before rebuilding from the new results. Keep entries for sections not re-run; render `## Setup gaps` and unlock hints from the current map.
- `baseline`: map of scenario-id → "pass" | "fail" | "skip" | "auth-unverified" | "need-info" (immutable reference recorded after Step 2; used for regression detection)
- `current`: map of scenario-id → "pass" | "fail" | "skip" | "auth-unverified" | "need-info" (mutable, updated each iteration by the aggregated verdict from Step 2.1.5 item 3)
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

Use this dispatch template for **every** tester launch in Steps 2.1, 2.1.8, 3e and 4; substitute the FE or BE section **in plan order** and mark guarded scenarios `mutation-guard` (`SKIP` without execution). Re-resolve and guard the Base URL before each launch. Include the `DB connection:` line only for BE:

```text
Plan: <plan_path>
Setup:
<paste the plan's ## Setup verbatim; when absent use "Setup: none declared" instead of these two lines>
Base URL: <resolved and guarded per Steps 0.3–0.4>
DB connection: <BE only: Required databases names from Setup, or "none declared">

<FE or BE> Test Scenarios:
<all scenario blocks of that section, with mutation-guard marks>

Report NEED_INFO (kind + missing names) for missing prerequisites. Never print secret values.
```

For FE, if a scenario explicitly contains a POST/PUT/PATCH/DELETE request (case-insensitive) and `--allow-mutations` is absent, mark it `mutation-guard`. The expected-rejection exemption below applies **only to BE**. FE writes triggered by UI actions without a literal HTTP verb are not detected; use a disposable test DB.

Apply the mutation guard without `--allow-mutations` to state-changing BE scenarios (POST/PUT/PATCH/DELETE case-insensitively, or DB-write checks).

**Expected-rejection exemption:** Dispatch one of these scenarios unguarded only when **each** main `**Expected:**` and edge-case assertion has exactly one expected HTTP status token: a standalone three-digit number from 100 to 599, ignoring numbers inside `(path:line)` grounding citations. That sole status must be ≥ 400; any 1xx–3xx status on an assertion keeps the whole scenario guarded. Never exempt a scenario if the main Expected or **any** edge assertion is tagged `(unverified — confirm at run time)`. Its optional `**DB Check:**` must be read-only (no `INSERT`, `UPDATE`, `DELETE`, `DROP`, `TRUNCATE`, `CREATE`, `UPSERT`), and no other bullet may describe a write (`create`, `delete`, `update`, `insert`, `seed` steps). Missing or ambiguous status, DB write, or write-ish step keeps the scenario guarded.

An unexpected 2xx on an exempt request lands a write **once** — the defect this scenario exposes; keep the test DB disposable. Reapply this same predicate on every baseline retry, section re-run and final run.

For each present section launch `Task(subagent_type: "qa:fe-tester" | "qa:be-tester", run_in_background: true, description: "Execute FE/BE test scenarios (baseline)", prompt: <Step 2.1 dispatch template rendered for that section>)`. Launch both in parallel when both exist; do not dispatch absent sections.

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

#### Step 2.1.5: Structured Result Ingest

Apply these three independent extractions **on every ingest** (baseline, Step 2.1.8 retry, Step 3e and Step 4). Parse each tester scenario block into `{ id, main_flow, edges, verdict, observed_status, reason, kind }`. A `**DB check:** SKIP` is best-effort evidence, **never** an edge SKIP for aggregation.

1. **Gaps:** For every scenario ID in a returned section, first delete its `need_info[ID]` and **all** `need_info["<ID> (edge n)"]` entries from the sidecar. A main `**Status:** NEED_INFO` block supplies `need_info[ID] = {kind, missing}` from its `**Kind:**` and comma-separated `**Missing:**` fields. Independently, each edge line `NEED_INFO — <kind>: <identifiers>` supplies `need_info["<ID> (edge n)"] = {kind, missing}`; `n` is the edge's 1-based order in the plan, even if the main flow is PASS or FAIL. Keep gaps of sections **not** returned in this dispatch. Never store secret values, only identifiers.
2. **Main flow:** Read the `**Status:**` line (`PASS`/`FAIL`/`SKIP`/`NEED_INFO`) and the **first integer** after `**Response status:**` (before any `(expected: N)`); FE has `null` observed status. Classify kind at Step 2.1.6, apply Step 2.1.7's auth reclassification **only to this main-flow result**, then perform the verdict aggregation below. If no status is parseable, keep the bare verdict or `null` without inventing PASS.
3. **Verdict/reason:** Aggregate the main flow and **every** edge line using the precedence below, after Step 2.1.7. Persist the resulting `scenario_kind` and `scenario_reason`; keep `observed_status` transient. A missing DB client with runnable HTTP marks only `**DB check:** SKIP`.

Use `issue_assertion` to find the main-flow QA ID: select the unique QA ID in `scenario_issues[ID]` whose `issue_assertion[QA-ID] == ID`, never the first array entry or a text match. After Step 2.2 assigns/reconciles baseline issue IDs, add that ID to `auth_gated_issues` if Step 2.1.7 reclassified the main flow, otherwise remove it; on later ingests refresh it the same way. Leave edge IDs and sections not returned untouched. If a later run first exposes a failing main flow after an existing failed edge (or another new failing assertion), assign/reconcile its QA ID using Step 2.2's assertion key and update the report and `issue_assertion` **before** refreshing these guards; do not reuse the edge's ID.

For every mapped QA ID of a returned scenario, refresh `unverified_issues` from **its own** plan assertion's `(unverified — confirm at run time)` tag using `issue_assertion[QA-ID]`; preserve IDs of sections not returned. In particular, when a newly failed main flow is mapped after an edge, neither the edge's tag nor its QA ID determines the main-flow guard.

#### Step 2.1.6: Scenario-Kind Classification

For each scenario, derive `kind` from its declared `**Expected:**` status + endpoint path (the plan is already parsed at Step 2.1):

- BE: `**Expected:**` status **≥ 400** ⇒ `negative`; endpoint path ∈ {`/health`, `/healthz`, `/openapi.json`, `/version`, `/`, `/docs`, `/api/docs`} ⇒ `sanity`; otherwise ⇒ `feature`.
- FE: default `feature` unless purely navigational/sanity.

`scenario_kind` MUST be fully populated by the end of Step 2.3 (before Step 2.4 reads it). Best-effort and non-gating — a feature endpoint that asserts a 4xx is misclassified `negative`; this only shapes confidence wording, never a pass/fail decision.

#### Step 2.1.7: Auth-Unverified Reclassification (at ingest, BE only)

For a BE scenario with `kind == feature`: if the parsed `observed_status` ∈ {401, 403} **and** the declared `**Expected:**` is a 2xx, set the **main-flow result only** to `auth-unverified` (executed, but the feature path was gated). A scenario that expected 401 and got 401 stays a normal `negative` PASS. If `observed_status` is `null`, leave the main flow unchanged (best-effort). Do **not** overwrite an independent edge-case FAIL with auth-unverified.

**Not detected (residual, see §8 of the spec):** 2xx-shaped gating (empty `200 []`, tenant `404`), auth surfaced only via an edge-case sub-test, and any FE gating (no FE HTTP status). Hence the Coverage block reports **"Exercised"**, not "Verified", for feature PASSes.

**Verdict aggregation (Step 2.1.5 item 3, after reclassification):** Use the *reclassified* main-flow result, not the original `**Status:**` line, for this precedence:

1. `fail` if the main-flow result is FAIL **or any edge is FAIL**.
2. Else `need-info` if the main-flow result is NEED_INFO **or any edge is NEED_INFO**.
3. Else `auth-unverified` if Step 2.1.7 reclassified the main flow.
4. Else `skip` if the main-flow result is SKIP or any edge is SKIP; otherwise `pass`.

Thus a main `FAIL` reclassified to `auth-unverified` does not itself win over an edge gap, but an independent edge FAIL still wins; a passing main flow with an unrun edge is not credited. For a non-pass verdict normalize the reason: `need-info` exactly when the verdict is `need-info`; otherwise an orchestrator-assigned `mutation-guard` wins; then an explicit Status/edge verdict wins over free-text guesses (`auth-unverified` stays distinct; `SKIP` with `harness error:` or `out of harness scope:` → `cannot-confirm`). For prose-only outputs `/no .*client|unavailable|not supported/i` → `tool-unavailable`, `/connection refused|could not connect|timeout/i` → `transport`, otherwise `cannot-confirm`. `transport` remains a prose-only reachability hint, not a reason to change an explicit NEED_INFO or FAIL. Refresh the scenario's reason each ingest.

#### Step 2.1.8: Setup-gap pause

After baseline ingest, if `need_info` is non-empty, print one names-only line **per kind**: `need-info <kind>: <identifiers> — <scenario IDs>` (use `<ID> (edge n)` for an edge). `N` in the question counts unique scenario IDs with gaps (not edge rows). In `--mode approve`/`step`, use `AskUserQuestion`:

```text
question: "N scenario(s) need setup (<kinds>). What now?"
options:
  - label: "Re-run baseline"
    description: "Retry the affected full sections after starting services / creating fixtures"
  - label: "Continue without them"
    description: "Keep gaps visible; continue without treating them as failures"
  - label: "Abort"
    description: "Stop without writing a report"
```

`Re-run baseline`: the user may start a service or add a fixture; env vars only count if exported **before the harness started**. Re-dispatch Step 2.1 **once**, only for sections holding current gap entries, but always their **whole sections**, with the Step 2.1 prompt shape and mutation guard reapplied; increment `dispatch_count` for each launch. Re-ingest Step 2.1.5 (delete/rebuild returned IDs' gaps), replace the affected baseline results, and **do not ask again** even if gaps remain. `Continue without them`: proceed. `Abort`: print the gap list and the Step 0.4.5 restart advice, write **no report**, stop. In `auto`, continue without a question.

#### Step 2.2: Render Report (report-format Step 6)

Using the `report-format` skill, build the QA-XXX report **in memory** (the actual write happens in Step 2.5, or — on the zero-failure path — in Step 2.4 just before exit):

**Mutation-guarded SKIP count (post-baseline):** Now that the Step 2.1 guard pass has classified SKIPs, the count is rendered in the Step 5.2 "Next steps to widen coverage" table (single source of truth).

1. **Count results:** follow report-format's verdict and Summary rules using Step 2.1.5; keep `auth-unverified` in the sidecar and Coverage but show it under Skip (auth-unverified) in the report.
2. **Assign QA-XXX IDs.** `max(existing)` is the highest QA-ID number across the **union** of: the report's `### … QA-NNN` headings, the sidecar `scenario_issues` IDs, and any QA-IDs referenced in Loop History. If that union is empty or unparseable, start at 0.
   - If reusing or adopting a report (Step 1, Cases 1–2), match each failed assertion by its **key** (`ID` for main flow; `<ID> (edge n)` for an edge) to a unique existing `issue_assertion` entry; reuse only that QA ID. An unmapped legacy issue is not a match. If the assertion is new, assign `max(existing) + 1` without reusing a sibling's ID.
   - If fresh (Step 1, Cases 3–4), start at `qa_count = 0` and assign sequentially: QA-001, QA-002, etc.
   - For every assigned or reconciled issue, set `issue_assertion[QA-ID]` to that key and add the QA ID to `scenario_issues[ID]` once. Do not rely on array position: an edge can receive QA-001 before a later-failing main flow receives QA-002. On reruns (Steps 2.1.8, 3e, 4), apply this same key-based assignment for newly failing assertions when updating the report; never replace an existing key-to-ID mapping when the assertion passes.
3. **Determine severity** per report-format for each failing assertion. Track tagged `(unverified — confirm at run time)` issue IDs in `unverified_issues`, reconciling reused IDs on re-render.
4. **Derive issue fields** per report-format. A reclassified `auth-unverified` main flow still mints an issue, but only its main-flow QA ID (`issue_assertion[QA-ID] == ID`) enters `auth_gated_issues` and is barred from fixes; a separately failing edge remains eligible, even with a main-flow gate or setup gap. A `NEED_INFO` assertion mints none. On REUSE/ADOPT, use restored assertion keys, never array order.
5. **Build the report** per report-format, rendering current `need_info` gaps independently of the scenario verdict and counting `need-info` by verdict only.

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
  },
  "issue_assertion": {
    "QA-001": "FE-02",
    "QA-002": "BE-03 (edge 2)",
    "QA-003": "BE-03"
  }
}
```

The `baseline` map is immutable and serves as the regression reference. The `current` map is a mutable copy initialized to match baseline; both hold the aggregated verdict (Step 2.1.5 item 3: `pass`, `fail`, `skip`, `auth-unverified`, `need-info`), not just the main-flow Status. It is updated on each ingest to reflect the latest full scenario result.

#### Step 2.4: Zero-Failure Exit

Count failures at or above `--severity` (default: all):

- If **zero failures and at least one scenario executed** (the all-`skip`/`need-info` branch below takes precedence), print:

> No failing assertions to fix. Check Coverage and Setup gaps for unverified scenarios.

  **Shallow-coverage check.** Let `meaningful = count(verdict == pass AND kind == feature)`. Coverage is **shallow** when `meaningful == 0` AND ≥1 `feature` scenario did not pass (it was `auth-unverified`/`need-info`/`skip`/`fail`). On shallow coverage, emit:

  > Warning: shallow coverage — no feature behavior was exercised (N feature scenarios were auth-unverified/skipped/unreachable). This green reflects infrastructure and enforcement checks only.

  **Precedence:** this WARNING does NOT fire on the existing mutation-guard-only all-SKIP graceful path (the "backend-write-only — rely on the unit/integration suite" branch below); that branch keeps its own message. The WARNING also does not fire when the plan contains **zero** feature-kind scenarios (a deliberately sanity-only plan — nothing claimed-but-unverified).

  **Low-confidence green:** when the message would print AND coverage is shallow AND `auto_generated == true`, replace the "No failing assertions to fix. Check Coverage and Setup gaps for unverified scenarios." line (still exit **success**) with:

  > All assertions passed, but coverage is shallow — no feature behavior was exercised (see Coverage). Low-confidence green: the plan was auto-generated and may not reflect runtime auth/setup.

  One authoritative coverage verdict per run: on the auto-generated zero-failure path the low-confidence-green line subsumes the shallow-coverage WARNING (print one, not both); otherwise the shallow-coverage WARNING is the verdict. The Coverage block restates counts and never re-decides.

  Save the report and sidecar first (Step 2.5 — on reuse/adopt this preserves any existing `**Status:**` lines), then skip the loop (Step 3) AND the final run (Step 4), and exit success.

- If **every verdict is `skip` or `need-info`**, branch on provenance (`auto_generated`, set during Step 0.2.1) and reasons:
  - **Auto-generated plan (`auto_generated == true`):**
    - If **every** reason is `mutation-guard`, exit gracefully with success: `Auto-generated plan is backend-write-only under the mutation guard — nothing executable here; rely on the unit/integration suite.`
    - Otherwise (`need-info`, `tool-unavailable`, `cannot-confirm`, unparseable/`null` or any other non-guard reason), exit gracefully **with a coverage-zero WARNING**: `Warning: All scenarios skipped or need setup for tooling/parse/prerequisite reasons, not mutation-guard — coverage is zero; verify the generated plan, Setup gaps and tool availability.`
  - **User-provided plan (`auto_generated` false/absent):** print the `need_info` gap list (names only) and abort: `Error: No executable verifier — cannot gate (all scenarios marked SKIP or NEED_INFO). Check your test plan, Setup gaps and tool availability.`

  On either graceful auto-generated path, save the report and sidecar (Step 2.5) first, then skip the loop (Step 3) and final run (Step 4). The user-provided all-unverified path aborts as before (no verifier); its names-only gaps are still surfaced.

#### Step 2.5: Save Report

**For reuse (Case 1) and adopt (Case 2) modes:**

Before writing, extract any existing `**Status:**` lines from the prior report. **Match each Status line to its issue strictly by the `QA-NNN` token, not the full `### [SEVERITY] … Title` heading** — severity and title may be re-derived differently between runs. When rendering the new report, re-insert each preserved Status line immediately after its `QA-NNN` heading, **exactly once** (never add a second Status line to an issue that already has one). Alternatively, use the Edit tool to make surgical updates to the existing report (merge new issues, keep old Status lines intact).

**Carry the decision record over as well.** The same extract-and-re-insert — matched by the same `QA-NNN` token, re-inserted exactly once — applies to every loop-written field of the finding block the `qa` and `code-review` plugins share:

- `**Decision:**`
- `**Decision-retired:**`
- `**Verification-plan:**`
- `**Decision-pin:**`
- `**Dispatch:**`
- `**Verification:**`

It applies equally to the rewritten `**Location:**` line, **carried over verbatim with its `(was: …)` parenthetical intact** — the preserved line wins over whatever Location this run re-derived for that issue, because it is the corrected address. Each of these fields occupies exactly one physical line with no continuation, so each is extracted and re-inserted as a single line. `**Status:**` stays the first non-blank line under the `QA-NNN` heading; the six fields are re-inserted below it, preserving the relative order they had in the prior report.

Without this carry-over a re-render drops the decision record and the corrected address the replay path depends on, and the user is re-asked decisions they have already made.

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

From the sidecar `current`, `scenario_issues` and `issue_assertion`:

1. Identify all scenarios still failing (current == "fail").
2. For each failing scenario, extract its QA-XXX issues.
3. Filter by `--severity` (keep issues at or above the floor).
4. Pre-filter: drop any issue with:
   - **A `**Status:**` line whose value begins `🚫 Rejected`** — the status is terminal, so a rejected issue never enters `fix_candidates` on this or any later run. Match the status value **by prefix, never by whole-line equality** — a rejected line carries a ` — <reason>` tail that is not this loop's to control.
   - **A location-less `**Location:**` field** — read the field by the two-clause rule below; a value of `—`, `unknown:0`, missing entirely, or anything that does not parse as `path:line` or `path:line-range` is location-less
   - **Missing fix-auto-required fields** (Location, Problem, Remediation)
   - **A missing, duplicated or mismatched `issue_assertion` key** — its QA ID must map uniquely to this scenario's main ID or one of its `<ID> (edge n)` keys; no other QA ID may claim the same key. An unmapped/ambiguous legacy issue or a corrupt mapping cannot be safely attributed to an assertion.

   **`**Location:**` read rule, two clauses.** Take the **first backticked token** on the line as the location and **ignore any trailing parenthetical** — this is the form the decision-gate loop always writes when it corrects a location, and its `(was: …)` tail preserves the *original* value, `unknown:0` included. Where the line carries no backticked token at all — a legacy `**Location:** src/foo.ts:12`, which this loop never writes but still meets — take the first whitespace-delimited token after the field name instead. **Never test the whole line:** a whole-line test reads a repaired finding as location-less because of the `unknown:0` preserved in its tail, and silently drops an issue that is fixable.

   For dropped issues, record: `rejected by user`, `needs manual location`, `incomplete fields` or `needs manual assertion mapping`. Never dispatch them.

Call this list `fix_candidates`.

**Auth-gated main-flow guard (all modes).** For each candidate, read its `issue_assertion[QA-ID]`. Only an ID mapped to the **bare scenario ID** can be an auth-gated main-flow issue: remove it when it is in `auth_gated_issues`, and log `auth-gated main flow; not fixing — verify access before changing auth.` Keep it in the report. A candidate mapped to `<ID> (edge n)` is an independent edge issue and stays eligible even when the scenario's main result is `auth-unverified` and the edge FAIL makes `current == "fail"`.

**Plan-suspect guards (per issue).** Read each candidate's `issue_assertion` key to identify the specific failing main `**Expected:**` or edge-case line. A QA issue whose ID is in `unverified_issues` (that assertion carries `(unverified — confirm at run time)`) is suspect regardless of its scenario's provenance; flag it `⚠ unverified assertion — verify before fixing` in `approve`/`step`, and in `auto` exclude **that issue only** from `fix_candidates` with log line `unverified assertion; not auto-fixing — verify the plan.` For an auto-generated scenario in `provisional_scenarios`, likewise flag its issues `⚠ auto-generated assertion — verify before fixing` (`approve`/`step`) or exclude them in `auto` with `auto-generated assertion suspected; not auto-fixing — verify the plan.` Apply both flags when both match. A **grounded sibling issue** from the same scenario remains eligible: do not exclude every QA ID solely because another failed assertion in that scenario was unverified.

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

**Dispatch-copy rule.** `/qa:loop` is itself a dispatcher of the finding block the `qa` and `code-review` plugins share, so what `fix-auto` receives is the **dispatch copy** of the block, not the raw block. It carries the reviewer-authored fields plus the rewritten `**Location:**` line, which travels in full — corrected value, `(was: …)` parenthetical and all. Every other line on the closed list is handled exactly as `code-review`'s `decision-gate` skill defines it at stage 3:

| Line | In the dispatched copy |
|---|---|
| `**Location:**` | **travels**, rewritten form and all |
| `**Verification-plan:**` | stripped |
| `**Decision-pin:**` | stripped |
| `**Dispatch:**` | stripped |
| `**Verification:**` | stripped |
| `**Decision-retired:**` | stripped |
| `**Decision:**` | reduced to its trailing `User decision: <resolution>` |
| `**Status:**` | **travels unchanged** — every Status line the block carries here pre-dates this run (this loop writes none before Step 4.1), and `fix-auto`'s own abort on `🚫 Rejected` reads exactly it |

All of the stripped lines **stay in the source report** — that is what the replay path and the decision-gate's verification read. A fixer holding unrestricted `Edit`, `Write` and `Bash`, told to iterate until its fix verifies, must not be handed the checks it will be graded by; without this rule a decided-but-unfixed finding arrives carrying them.

```
dispatch_count++

Task(
  subagent_type: "code-review:fix-auto",
  run_in_background: false,
  description: "Auto-fix: [<SEVERITY>] <Issue-ID>: <Title>",
  prompt: "<the issue block from the report, rendered as the dispatch-copy rule above defines it>

INJECTED CONSTRAINTS FOR THIS FIX:

1. Source-only fix: do not modify the test plan, plan-referenced test files, or test scenarios.
2. Fix only the source code under test.
3. Keep the working tree clean (uncommitted changes only, no staging).
4. If a location-less issue arrives, return Failed — do not prompt. Read the Location field by its two-clause rule: take the first backticked token, ignoring any trailing parenthetical; where the line carries no backticked token, take the first whitespace-delimited token after the field name. Under either clause a value of —, unknown:0, or anything that does not parse as path:line or path:line-range is location-less. Never test the whole line: a corrected Location preserves the original unknown:0 inside its (was: ...) tail, and a whole-line test would fail a fix that is perfectly dispatchable."
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

Re-run each section containing a still-failing scenario in full, in plan order. For each, increment `dispatch_count`, re-resolve/guard the Base URL, reapply the Step 2.1 mutation guard (including its exemption), and launch its tester with the **Step 2.1 dispatch template** and description `Re-run FE/BE section (iteration N)`. Wait for each dispatched tester result; ingest every returned section via all three Step 2.1.5 extractions, deleting/rebuilding only its gap keys. The residual unexpected-write risk of the exemption still applies. Do not launch or count unaffected sections.

#### Step 3f: Check Regressions & Progress

**Regression check:** Read the sidecar `baseline` map. For each scenario, compare its aggregated verdict (Step 2.1.5 item 3): a `baseline == "pass"` that now has `verdict == "fail"` (including an edge FAIL) is a regression. `need-info`, `auth-unverified` and `skip` are not regressions or successful retests.

If any regression is detected, stop:

> Scenario regression detected (e.g., FE-01 passed at baseline but failed this iteration). Stopping loop to prevent oscillation.

Exit loop. (Regressions are reported in Step 4.2.)

**Progress:** has at least one scenario newly passed this iteration? Compare the aggregated `current` verdict (Step 2.1.5 item 3) as it stood at the start of the iteration (before Step 3g) with the newly received verdicts. Only `"fail" → "pass"` (main flow **and all** edges passed) counts; main PASS with an edge `NEED_INFO` or `SKIP` does not.

> No progress this iteration (no newly passing scenarios). Stopping loop.

Exit loop.

**`auth-unverified` and `need-info` across consumers:** A scenario whose full verdict is either is not `"fail"` and does not enter Step 3a. If an independent edge FAIL makes its verdict `"fail"`, exclude only the auth-gated **main-flow** QA ID via `auth_gated_issues`; the edge issue remains eligible. Neither an `auth-unverified` nor a `need-info` verdict is a regression (Step 3f / 4.2 keys on `baseline == "pass" ∧ current == "fail"`), progress or a credited pass. Merge both into `current` normally when re-run.

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

Update `current` with the latest **aggregated verdicts (Step 2.1.5 item 3)** (`pass`/`fail`/`skip`/`auth-unverified`/`need-info`) — **merge, don't replace:** only overwrite entries for scenarios actually returned this iteration; keep all others (including an un-re-run section's gaps). Step 2.1.5 separately refreshes those returned scenarios' `need_info` keys.

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

Re-run the **entire plan** (all FE and BE scenarios, in order). Re-resolve/validate the base URL (Steps 0.3–0.4), apply the Step 2.1 mutation guard **including its expected-rejection exemption** and disposable-DB residual, then ingest every returned scenario through Step 2.1.5's **three** extractions (delete/rebuild gaps for returned IDs, main flow, verdict). Update `current` and the report's Detailed Results, `## Setup gaps` and counts from the authoritative aggregated verdicts (Step 2.1.5 item 3); gaps for sections not re-run persist.

For each present FE/BE section increment `dispatch_count`, launch its tester in parallel with `description: "Final run — FE/BE scenarios"` and the **Step 2.1 dispatch template** rendered with all of that section's scenarios and fresh mutation-guard marks. Wait for both launched results. Do not dispatch an absent section.

#### Step 4.1: Write Status (One-Time, Authoritative)

For each scenario whose **final-run aggregated verdict (Step 2.1.5 item 3) is `pass`** (main flow **and every edge case** passed):

1. Locate all its QA-XXX headings in the report **by the `QA-NNN` token** (not the full heading text).
2. For each heading, use the Edit tool to insert immediately after the `### [SEVERITY] QA-XXX: Title` line — **exactly once** (if a `**Status:**` line already exists for that issue, update it in place rather than adding a second):

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

Use today's date in YYYY-MM-DD format.
Write this status whether or not this run dispatched a fix for the issue. The final run is authoritative, and environment or setup changes count.

**A `🚫 Rejected` line is left exactly as found.** Before updating any existing Status line in place, read its value and match **by prefix, never by whole-line equality** — a rejected line carries a ` — <reason>` tail. Where the value begins `🚫 Rejected`, write nothing for that issue: do not update the line in place, and do not add a second `**Status:**` line beside it. The status is terminal, and the reason is the entire record of why the rejection happened. This guard is load-bearing because the sidecar binds scenario → [QA-IDs]: a *sibling* issue passing on the same scenario is enough to reach a rejected issue's heading here, and the in-place update would destroy both the rejection and its reason.

**Every other verdict:** leave its issues unmarked (no new `**Status:**` line; they remain retryable). A main-flow PASS with an edge `NEED_INFO`, `SKIP` or `FAIL` closes **none** of the scenario's issues. Append a **Final** Loop History row using the Step 3h columns even if no fix iteration ran; its `Still failing` column lists every scenario with open issues, including a main-flow PASS with an edge `(edge need info)` or `(edge skipped)`, whether final verdict is `need-info`/`skip`/`fail`. The Final row is not credited as a fix iteration.

**`⚠️ Partially Fixed` is never written** — it would freeze issues out of `/fix-report`. The report stays compatible with `/fix` / `/fix-report`.

#### Step 4.2: Handle Regressions

Read the sidecar `baseline` map. For each scenario, compare full aggregated verdicts (Step 2.1.5 item 3): a baseline `"pass"` becoming final-run `"fail"` (including edge FAIL) is a regression; a final `"need-info"`, `"skip"` or `"auth-unverified"` is unverified but not a regression.

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

- **final_pass_count** — scenarios with full aggregated `pass` verdict (Step 2.1.5 item 3) in final run
- **final_fail_count** — scenarios with full `fail` verdict in final run
- **final_need_info_count** — scenarios with `need-info` verdict in final run (edge gaps included)
- **final_skip_count** — `skip` plus `auth-unverified` for the four-count display only; the sidecar and Coverage still distinguish them
- **fixed_count** — scenarios with `**Status:** ✅ Fixed` written
- **warnings_count** — number of issues with anti-hardcoding warnings
- **regressions_count** — number of regressions detected
- **elapsed** — `$(date +%s) - start_time` in seconds

#### Step 5.2: Print Summary

```
## Loop Summary

**Result:** <Pass | Fail | Budget Exhausted | Stopped>

**Final Status:**
- Pass: N | Fail: N | Skip: N | Need info: N
- Fixed (Status written): N
- Remaining unfixed: N
- Warnings: N (anti-hardcoding)
- Regressions: N

**Coverage** (computed from `scenario_kind` + verdicts + `scenario_reason`):

```
## Coverage
- Exercised: <feature-PASS> feature · <sanity-PASS> sanity · <negative-PASS> enforcement
- Not verified: auth-unverified <N> · need-info <M> · mutation-guard SKIP <K> · tool-unavailable <J> · …
- Confidence: <high | low — reason>
```

"Exercised" (not "Verified") because a feature PASS means "reached and returned non-4xx" — an upper bound (see the auth-detection residual in Step 2.1.7).

**Next steps to widen coverage** (render rows whose count > 0 from `scenario_reason`; render `need-info` whenever the current `need_info` map is non-empty, even if its verdict count is 0):

- `mutation-guard` (N): re-run with `--allow-mutations` (test DB must be disposable).
- `auth-unverified` (N): the app is auth-gated; `/qa:loop` verifies enforcement only. Exercise authenticated behavior via the project's integration/e2e suite. (No `--auth-token` intake in this version.)
- `need-info` (N): <kind>: <identifiers> — set/start them, restart the harness, re-run. Group the **current `need_info` map** by kind and list its names/hosts only. N counts scenarios with a `need-info` verdict (the map separately lists every edge gap); show `need-info (0)` when only failed scenarios have gaps.
- `tool-unavailable` (N): install/enable the missing tool (Playwright / curl / DB client).
- `dispatch-exhausted`: raise `--max-dispatches`.

Counts come from aggregated verdicts (Step 2.1.5 item 3) and the normalized `scenario_reason`: `mutation-guard` is exact (orchestrator-assigned); `need-info` identifiers come from the current `need_info` map, **not** from prose. Other heuristic prose-matches may under-count — acceptable for an advisory hint.

**Reactive suggestions** (each with its caveat, shown only when triggered):

- **Reachability:** if **every BE scenario** is `need-info` with kind `service` for its main flow, **or** every BE scenario is `fail` with a prose-only `transport` reason and `null` `observed_status`, print: "no BE scenario returned an HTTP status at `<host:port>` — the dev stack may be down." Assemble `<host:port>` from the resolved base URL's authority (Step 0.4 rejected userinfo), **never** from a raw transport error or secret-bearing response. Do not claim all BE scenarios unreachable when any answered.
- **Mutation:** if every BE scenario was `mutation-guard` SKIP, print the `--allow-mutations` hint (disposable DB).

No proactive guard-widening nudges: flags that widen a guard appear only in the reactive unlock-hints after the guard actually blocked something.

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

1. First backticked token of `**Base URL:**` under `## Setup`
2. First `http://` or `https://` URL in `## Source` or a scenario heading/bullet
3. Non-empty `QA_BASE_URL`

Never read project config at run time. If none resolves, abort with Step 0.3's exact fail-closed error (including the `--allow-host` clause).

### Safety Guards (Apply in All Modes)

**Environment guard:** resolved host must be loopback (`localhost`, `127.0.0.1`, `::1`, `*.localhost`) or in `--allow-host`, else abort. Testers also send requests and open pages only on the Base URL's host (`SKIP — off-host URL refused: <host>` otherwise), so an absolute URL inside a scenario cannot bypass this guard.

**Mutation guard:** state-changing BE scenarios (HTTP POST/PUT/PATCH/DELETE or DB-write checks) SKIP with reason `mutation-guard` unless `--allow-mutations` is set **or** every state-changing action is a grounded expected rejection: the main `**Expected:**` and **each** edge assertion must each contain exactly one standalone three-digit HTTP status (100–599), after ignoring `(path:line)` citation numbers; each must be ≥ 400, with no 1xx–3xx status on any assertion and no `(unverified — confirm at run time)` tag on any of them. The optional DB check must be read-only (no `INSERT`/`UPDATE`/`DELETE`/`DROP`/`TRUNCATE`/`CREATE`/`UPSERT`) and no other bullet may describe a write (`create`/`delete`/`update`/`insert`/`seed`). Missing or ambiguous status or action remains guarded; skipped issues are never counted as fixed. An unexpected 2xx on an exempt request lands one write — keep the test DB disposable.

*Mutation classification is syntactic and best-effort (HTTP-verb matching is case-insensitive). It detects HTTP verbs and DB-write patterns in the plan, but does **not** detect GET-with-side-effects, GraphQL mutations without an explicit verb, or **FE UI actions that trigger writes** (e.g. clicking a Delete button). Treat the test DB as disposable regardless of `--allow-mutations`.*

**Verifier-gaming residual (v1):** The loop defends against payload-literal hardcoding via the anti-hardcoding warning, but a capable fixer with visibility to deterministic scenarios can make a scenario pass without a real fix. The default `approve` mode is the runtime mitigation; randomized re-verification is planned for v2.

---

## Error Handling

| Situation | Behavior |
|---|---|
| Invalid args (before I/O) | Clear error message → stop. Examples: unknown `--mode`, non-integer `--max-iterations`, unknown `--severity`. |
| No plan found | Message → `/qa:create-plan` → stop. |
| Base URL undetectable | Abort with Step 0.3's exact message; project config is never read at run time. |
| Declared env var missing (preflight) | Abort before any dispatch; names only. |
| Non-loopback host (no `--allow-host`) | Abort (environment guard). |
| Mutating BE scenario without `--allow-mutations` | SKIP with reason `mutation-guard` unless Step 2.1's grounded, single-rejection-per-assertion exemption applies; guarded issues marked "needs --allow-mutations". |
| BE scenario whose every action is a grounded expected rejection | Dispatched without `--allow-mutations`; an unexpected 2xx lands one write. Test DB must be disposable. |
| Tool unavailable (Playwright, curl, perl) | Testers return `NEED_INFO kind=tool`, listed under `## Setup gaps`; an unavailable DB client skips only the DB check while HTTP runs. |
| Scenario returns NEED_INFO (main flow or an edge) | approve/step: ask (re-run baseline once / continue / abort); auto: continue. Verdict `need-info`: not verified, never a fix candidate, never a regression, never credited. |
| Entire baseline is `skip` or `need-info` (user-provided plan) | Abort: "no executable verifier — cannot gate", with the gap list. |
| Entire baseline is `skip` or `need-info` (auto-generated plan) | Graceful success only when every reason is `mutation-guard`; otherwise graceful exit with a coverage-zero WARNING, including `need-info` gaps. |
| Feature scenario auth-gated (main flow) | Reclassify main result as `auth-unverified` before edge aggregation; keep its main-flow issue in the report but put its QA ID in `auth_gated_issues` and exclude it from all fix dispatches. A failed edge still wins, mints a separate issue and remains eligible. |
| Shallow coverage (no feature PASS) | WARNING + low-confidence green on auto-generated; still exit success. |
| Zero baseline failures at/above floor | No failing assertions to fix; report any setup gaps, then skip loop and final run. |
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

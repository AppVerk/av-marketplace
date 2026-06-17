# Design Spec: `/qa:loop` — Closed Test → Fix → Retest Loop for the QA Plugin

**Date:** 2026-06-17
**Status:** Revised (v3, "lean & honest") — ready for re-approval before implementation planning
**Target plugin:** `qa` (version 2.0.1 → 2.1.0)
**Origin:** Brainstormed from a mixture-of-agents analysis of "loop engineering"; hardened by two rounds of sequential-thinking + mixture-of-agents adversarial review.

---

## 0. Revision history

- **v1** — initial design (new `/qa:loop`; default `auto`; "purely additive / zero changes").
- **v2** — after review round 1: default → `approve`; added safety guards (env guard, `--allow-mutations`, Location pre-filter, anti-hardcoding check); issue↔sub-test map; write-once Status; budgets; corrected the "zero changes" and "parity CI is optional" errors.
- **v3** — after review round 2, which found v2 had traded v1's gaps for **"phantom mechanisms"** (controls that read concrete but rest on data/tools that don't exist). v3 dissolves them by relaxing the self-imposed "reuse single-pass artifacts as iterative state, prompt-only" constraint where it forced fragility:
  - **Scenario-level granularity.** Dropped the issue↔sub-test map (sub-test "labels" don't exist in the plan or tester contracts). An issue is credited fixed **iff its whole scenario passes**; intra-scenario partial progress is not separately credited (documented tradeoff).
  - **Command-owned sidecar state file** (`<topic>-loop-state.json`) instead of an in-report HTML-comment block — so the state is real JSON the command reads/writes/`jq`s. The report keeps only a human-facing `## Loop History` section.
  - **Section-level re-run** (re-run the whole FE and/or BE section containing failures) instead of a fragile free-text dependency parse — dependency-safe by construction.
  - **Real base-URL resolution with fail-closed** (v2 cross-referenced a `/qa:run` step that is only a placeholder).
  - **Dispatch-count budget** (`--max-dispatches`) replacing the **unmeasurable token budget**; dropped the per-iteration top-K cap (its starvation interaction is gone).
  - **Anti-hardcoding check is a human-review *warning*** scoped to request-payload literals — not a credit-blocking gate (it both false-positives on correct fixes and false-negatives on clever ones; the final run is the authority).
  - Reconciled v2's internal seams: ID-minting override on reuse, dead `approve` re-ask removed, "updated incrementally" vs write-once Status, mid-loop "unresolved" defined, env-guard stated once, `allowed-tools` completed, final run conditional on the zero-failure exit, redundant Location injection reduced to a single backstop.

---

## 1. Context & Motivation

**Loop engineering** is designing the *control system that runs an agent's loop* — trigger + verifiable goal + guardrails. Canonical loop: *gather context → take action → **verify** → repeat*.

The load-bearing research finding: **code is the best domain for loops because it has cheap, near-ground-truth feedback** (tests/types/compilers/linters) — "verification asymmetry." Corollary:

> **Loop on a signal that cannot lie — never on the model's judgment of its own work.**

A mixture-of-agents audit found the marketplace already has good loop instincts (developer plugins' TDD; code-review's `challenger`/`cross-verifier` + `fix → verify → iterate`), but **`qa` is single-pass**: `/qa:run` reports `QA-XXX` failures and stops. Closing that gap is the cleanest first application — the verifiable signal (the scenarios) already exists.

The adversarial reviews sharpened one caveat that shapes v3: **the fixer and the verifier must be treated as adversaries.** Scenarios are deterministic and visible to the fixer, so an unconstrained fixer can make a scenario pass *without a real fix*. v3 is honest about what this loop can and cannot guarantee against that.

---

## 2. Goal & Scope

Add a **closed test → fix → retest loop** to the `qa` plugin:

```
run → (failing scenarios) → fix → re-run the affected section(s) → repeat until green or budget exhausted
```

### In scope

- New command `/qa:loop`.
- A **command-owned sidecar state file** per topic.
- One documented extension to the `qa`-owned `report-format` skill: a human-facing `## Loop History` section.
- Loop-level guardrails and safety guards.

### Non-goals (explicit)

- Cross-plugin wiring of `review ↔ qa ↔ fix`.
- A reusable, marketplace-wide loop primitive.
- Changes to `code-review:fix-auto`, `qa:fe-tester`, `qa:be-tester` agent files.
- **Per-edge-case (sub-scenario) fix crediting** — v1 credits at scenario granularity (a coarser, honest signal); finer granularity is deferred.
- Auto-fixing regressions (reported only).
- Committing changes (the loop never commits).
- **Gaming-proof verification** — see §5.2; randomized/property-based re-verification is a planned v2 hardening, not in v1.

---

## 3. Architecture

New file: **`plugins/qa/commands/loop.md`**. It *orchestrates*; it reimplements nothing.

### Reused components

| Component | Role |
|---|---|
| `qa:fe-tester` / `qa:be-tester` (agents) | **Verifier** — execute scenarios, return scenario-level pass/fail |
| `code-review:fix-auto` (agent) | **Fixer** — fix one `QA-XXX` issue, source-only, uncommitted |
| `report-format` (skill, qa-owned) | Parse/emit `QA-XXX`; **extended** with a `## Loop History` section |
| `docs/testing/plans/*` | Plan input (scenario source of truth) |
| `docs/testing/reports/*` | Human-facing report (living ledger of `**Status:**`) |
| `docs/testing/reports/<topic>-loop-state.json` | **New, command-owned** machine state (plan hash, scenario↔QA-ID map, per-iteration results, dispatch count) |

### Invocation

```
/qa:loop [plan-path]
         [--mode approve|auto|step]      (default: approve)
         [--max-iterations N]            (default: 3,    N >= 1)
         [--max-dispatches D]            (default: 50,   D >= 1)  # total fix-auto + tester launches
         [--time-budget SECONDS]         (default: 1800)
         [--severity CRITICAL|HIGH|MEDIUM|LOW]   (default: none = all)
         [--allow-mutations]             (default: off)
         [--allow-host HOST]             (repeatable; default: loopback only)
```

Args are validated **before any I/O** (mirroring `/fix-all` Step 0): unknown `--mode`/invalid integers/unknown `--severity` → clear error. `--severity` is case-insensitive. `plan-path` defaults to the newest plan in `docs/testing/plans/`; no plan → `/qa:create-plan`, stop.

### `loop.md` frontmatter (`allowed-tools`)

```
allowed-tools: Bash(find:*), Bash(ls:*), Bash(head:*), Bash(cat:*), Bash(mkdir:*),
  Bash(date:*), Bash(command:*), Bash(echo:*), Bash(git:*), Bash(shasum:*),
  Bash(jq:*), Bash(cp:*), Bash(mv:*),
  mcp__plugin_playwright_playwright__browser_navigate,
  Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput,
  Skill, AskUserQuestion
model: opus
```

(`jq` now operates on the **real** sidecar JSON file; `cp`/`mv` support the `.bak` archive; `shasum` the plan fingerprint; `git` the anti-hardcoding `git diff`; `Edit` the in-place `**Status:**` write-back. `fix-auto`/testers run as subagents with their own tool sets, so the loop needs none of `pytest`/`curl`/Playwright-action perms.)

---

## 4. The Loop Algorithm

```
0. RESOLVE & VALIDATE
   - Validate args (before I/O). Resolve plan (as /qa:run). No plan → /qa:create-plan, stop.
   - RESOLVE BASE URL via an explicit ordered probe (§6). If undetectable → ABORT (fail-closed).
   - ENVIRONMENT GUARD: if the resolved host is not loopback and not in --allow-host → ABORT.
   - PLAN_HASH = `shasum -a 256 <plan-path>`. Init dispatch_count = 0, start_time = `date +%s`.

1. RESOLVE REPORT + SIDECAR (idempotency)
   - Locate newest `docs/testing/reports/*-<topic>-report.md` and its sidecar `<topic>-loop-state.json`.
   - SIDECAR PRESENT and its plan_sha256 == PLAN_HASH → REUSE report in place; load scenario↔QA-ID
       map + existing IDs/Status from the report; new IDs continue at max(existing)+1.
   - SIDECAR ABSENT but a report exists (e.g. from a plain /qa:run) → ADOPT it as baseline:
       import its QA-XXX IDs + any **Status:** lines, create a fresh sidecar stamped with PLAN_HASH.
   - PLAN_HASH MISMATCH (plan changed) → archive report+sidecar to *.bak (cp/mv), start FRESH.
   - Pin the report filename + sidecar for the whole run (no midnight fork).

2. BASELINE RUN (full): launch fe-tester/be-tester on ALL scenarios (parallel if both;
   mutation guard gates state-changing BE scenarios unless --allow-mutations).
   - Render the QA-XXX report (reuse /qa:run Step 6 report-format RENDERING, but ID ASSIGNMENT
     follows step 1: reused scenarios keep their IDs (matched by scenario-id), new failing
     scenarios get max+1; on a FRESH report use report-format's qa_count=0 algorithm).
   - Write the sidecar: plan_sha256, scenario→{QA-IDs}, baseline scenario pass/fail.
   - ZERO failures at/above --severity → "all passing, nothing to fix"; SKIP the loop AND
     the final run; exit success.

3. LOOP while (scenarios with unresolved issues remain at/above --severity)
            AND (iteration < --max-iterations)
            AND (dispatch_count < --max-dispatches)
            AND (elapsed < --time-budget):
   a. iteration += 1
   b. SELECT fix-set: issues on still-failing scenarios, filtered by --severity, then
        PRE-FILTERED: drop issues with Location `unknown:0` / missing fix-auto-required fields
        → list as "needs manual location", never dispatch.
      └─ HITL gate per --mode (§6).
   c. FIX: for each selected issue → dispatch fix-auto (sequentially), SOURCE-ONLY
        (constraints injected into the prompt; see §10). dispatch_count++ per launch.
        ANTI-HARDCODING WARNING: diff touched files; if an added source literal equals a
        scenario's request-payload value → record a WARNING on that fix (human-review flag;
        NOT a credit block — the re-run + final run remain authoritative).
   d. RE-RUN (section-level): re-run the WHOLE FE section and/or BE section that contains any
        still-failing scenario (dependency-safe; no prerequisite parsing). Launch fresh
        fe-tester/be-tester (parallel if both; re-resolve base URL/DB; dispatch_count++ each).
   e. UPDATE STATE (provisional, in the SIDECAR only): record per-scenario pass/fail and an
        iteration entry (attempted, now-passing, still-failing, warnings, dispatches). Append a
        human-facing `## Loop History` row to the report. DO NOT write **Status:** headings yet.
   f. PROGRESS / OSCILLATION: stop if no scenario newly passed this iteration; OR if any
        previously-passing scenario regressed (oscillation guard); OR any budget exceeded.

4. FINAL RUN (full, AUTHORITATIVE) — unless the zero-failure exit fired in step 2:
   re-run the ENTIRE plan once. This is the sole source of truth for Status.
   - For each scenario that PASSES here, write **Status:** ✅ Fixed (date) on ALL its QA-XXX
     headings. Still-failing scenarios' issues are left UNMARKED (retryable by a future run;
     `⚠️ Partially Fixed` is never written — it would freeze them out of /fix-report).
   - REGRESSION: a scenario that passed at baseline but fails here gets a NEW QA-XXX
     (deduped vs. still-open IDs) and is flagged in Loop History — reported, not fixed.

5. FINAL REPORT & SUMMARY: Loop History, final pass/fail, fixed/remaining/warnings/regressions,
   dispatch_count + elapsed, recovery hint (`git restore` for source). Changes stay uncommitted.
```

---

## 5. The Three Pillars

### 5.1 Verifier authority

"Green" is decided **only** by a fresh re-run executed by the independent tester agents — the per-iteration section re-run for loop control, and **authoritatively the §4-step-4 final full run** for Status. `fix-auto`'s own verdict is advisory (used only to decide which scenarios to re-run).

### 5.2 Verifier protection — *and an honest boundary*

- **Source-only / immutability** constraint injected into the `fix-auto` prompt (plan, scenarios, plan-referenced test files are immutable; fix the source under test).
- **Plan fingerprint** (`shasum -a 256`) stored in the sidecar; checked each run → detects cross-run plan tampering (re-baseline) and mid-run edits (abort).
- **Anti-hardcoding WARNING** (§4 step c): a heuristic `git diff` check for added literals equal to a scenario's request-payload value; surfaced as a human-review flag (in `approve`, shown before the next gate; in `auto`, logged in the report). It is **not** a credit gate, because it both false-positives (a correct fix may legitimately contain the expected status/field) and false-negatives (derived-value branching, request-shape special-casing, condition-widening).
- **Honest boundary (residual, accepted for v1):** because scenarios are deterministic and visible, a same-capability fixer can make the live re-run pass without a real fix, and *no in-loop check fully prevents this*. The real defense — **randomized / property-based re-verification** (perturb payloads off the plan literals before crediting green) — is deferred to a v2 hardening. In v1 the backstop is the **default `approve` human gate**. This is mitigation, not a guarantee; it is stated, not hidden.

### 5.3 Hard guardrails

- **Bounded** on three *measurable* axes: `--max-iterations`, `--max-dispatches` (every fix-auto + tester launch counts; the command increments and checks it), and `--time-budget` (wall-clock via `date`). Breaching any → partial report + stop. (No token budget — a command cannot observe its own token spend; the dispatch count is the enforceable proxy.)
- **Progress / oscillation**: progress = ≥1 still-failing scenario newly passes this iteration; if any previously-passing scenario regresses → **stop** (don't chase).
- **Never commits** — source edits stay in the working tree (`git restore` recovers). Runtime/DB blast radius is bounded by the environment + mutation guards (§6), not by git.

---

## 6. Modes, Base-URL Resolution & Safety Guards

### Modes (default **approve**)

| Mode | Behavior |
|---|---|
| **approve** *(default)* | Show the fix-set (issues + target scenarios) + any anti-hardcoding warnings; take **one batch approval**; then run to green/budget. |
| **auto** | No per-batch HITL gate (this is the only difference from `approve` — the env/mutation guards apply identically). Opt-in. Prints a text scope banner (failures, budgets, target host); abort is via session interrupt (Esc). |
| **step** | Approve fixes before each re-test (maximum control). |

**Headless / non-interactive:** `approve`/`step` use `AskUserQuestion` and block without input → the loop **aborts early** with "approve/step require an interactive session; use --mode auto." `auto` is the only headless-safe mode.

### Base-URL resolution (fail-closed)

Resolve in order: (1) explicit URLs in the plan's `## Source`/scenarios (e.g. `http://localhost:8000`); (2) a `QA_BASE_URL` env var; (3) best-effort project config. **If none resolve → ABORT** (cannot guarantee loopback safety). Then the environment guard classifies the host.

### Guards (apply in **all** modes)

- **Environment guard:** host must be loopback (`localhost` / `127.0.0.1` / `::1` / `*.localhost`) or in `--allow-host`, else **abort** (§4 step 0).
- **Mutation guard:** state-changing BE scenarios (HTTP `POST/PUT/PATCH/DELETE`, or any DB-write check) run only with `--allow-mutations`; otherwise they SKIP with reason `mutation-guard` and their issues are reported as "needs --allow-mutations" (never counted as fixed). *Note:* this is a static pre-classification; it reduces but cannot eliminate side effects (the test DB should be disposable — see §11). It provides no rollback.

---

## 7. Report, Sidecar & Status

- **Sidecar `docs/testing/reports/<topic>-loop-state.json`** (command-owned, real JSON → `jq`-readable) holds: `plan_sha256`, `report_file`, `scenario_issues` (scenario-id → [QA-IDs]), `baseline` (scenario → pass/fail), `iterations[]`, `dispatch_count`. This is the machine state; the report stays human-facing.
- **`## Loop History` section** — a new `##`-level section placed **after `## Detailed Results`**, MUST NOT contain any `### [SEVERITY] …` headings or `---` separators (so `/fix-report`'s block parser ignores it). Columns: iteration · failing-in · now-passing · still-failing · warnings · regressions · dispatches. *(Requires a documented extension to the `report-format` skill — §10/§11.)*
- **The report is updated incrementally**: each iteration appends a Loop History row; **`**Status:**` headings are written exactly once, from the authoritative final run** (§4 step 4). (No premature/laundered `✅`; the "living document" of `**Status:**` lines is finalized at the end.)
- **Status format** is identical to `/fix-report` (`**Status:** ✅ Fixed (YYYY-MM-DD)` after the issue heading), so the report stays compatible with `/fix` and `/fix-report`. Still-failing issues are left unmarked (retryable). `/fix-report` auto-merge picks the loop's report by path (newest in `docs/testing/reports/`); prefix routing is a `/fix` concern.
- **ID stability:** QA-XXX IDs are anchored to **scenario-id** in the sidecar and preserved across iterations and reuse runs (step 1 overrides report-format's from-zero counter on reuse/adopt).

---

## 8. Re-run Granularity

- **Re-run unit = the section (FE and/or BE)** that contains any still-failing scenario. Re-running the whole section is **dependency-safe by construction** (prerequisite scenarios run in order), eliminating both the fragile "created in BE-02" free-text parse and the false-failure risk of isolated re-runs. The final run is the full plan.
- **Credit is at scenario granularity:** an issue is credited (provisionally, then finally) **iff its whole scenario passes**. When a scenario carries several QA-IDs (main + edge cases), they resolve together. Intra-scenario partial progress is shown in Loop History (from the testers' free-text sub-results) but is **not** separately credited in v1 — a deliberate, documented coarsening that removes the (unimplementable) sub-test-label machinery.
- **Regression coverage:** section re-runs surface **intra-section** regressions each iteration (and stop on them); **cross-section** regressions are caught at the final full run (reported, not fixed). This limitation is documented, not hidden.

---

## 9. Error Handling

| Situation | Behavior |
|---|---|
| Invalid args | Clear error before any I/O; stop. |
| No plan found | Message → `/qa:create-plan` → stop. |
| **Base URL undetectable** | **Abort (fail-closed)** — cannot guarantee loopback safety. |
| Non-loopback host (no `--allow-host`) | **Abort** (environment guard). |
| Mutating BE scenario without `--allow-mutations` | SKIP (`mutation-guard`); issue reported as "needs --allow-mutations". |
| Tool unavailable (Playwright/curl/db) | Affected scenarios SKIP / "cannot confirm" (never counted as fixed). If *all* verifiers for the failing scenarios are unavailable → abort. |
| Entire baseline is SKIP (no pass, no fail) | Abort: "no executable verifier — cannot gate." |
| Zero baseline failures at/above floor | "All passing, nothing to fix" → skip loop AND final run → exit success. |
| Issue `Location: unknown:0` / missing fields | Pre-filtered out; "needs manual location"; never dispatched. Backstop: the fix-auto prompt also says "if a location-less issue arrives, return Failed — do not prompt." |
| `fix-auto` fails on an issue | Mark failed for this iteration; keep looping on the rest. |
| `fix-auto` says "Fixed" but the re-run still fails | Re-run wins; scenario stays failing. |
| Anti-hardcoding warning | Surfaced for human review (approve) / logged (auto); not a credit block. |
| No progress / oscillation / any budget exceeded | Stop; "stalled"/"budget reached" + remaining issues + suggest `/fix` or another `/qa:loop`. |
| Regression in the final run | New QA-XXX (deduped); reported, not auto-fixed. |
| Plan hash mismatch | Mid-run → abort; cross-run → re-baseline. |
| User abort (Esc) | Uncommitted changes left; partial report + Loop History so far. |

---

## 10. Scope of Change

- **No changes** to `code-review:fix-auto`, `qa:fe-tester`, `qa:be-tester` (agent files). Constraints (source-only, immutability, "return Failed rather than prompt on a missing location") are **injected via the loop's prompts**.
- **New:** `plugins/qa/commands/loop.md`; the command-owned sidecar `*-loop-state.json` (a runtime artifact under `docs/testing/reports/`, gitignored if desired).
- **Extended (within `qa`):** `plugins/qa/skills/report-format/SKILL.md` gains a documented optional `## Loop History` section (with the "no `###`/`---` inside it" rule added to its Quality Checklist). This is a real, versioned change to a reused skill — the v1 "zero changes" claim was inaccurate and is dropped.

---

## 11. Testing & CI

- **Existing mandatory CI:** `.github/workflows/plugin-version-parity.yml` runs `scripts/check_plugin_versions.py` on every push/PR to master, enforcing version parity across all four canonical locations. The §12 edits **must** land together or the gate fails the PR.
- **v1 verification — manual recipe** covering: (a) a deterministic source-level failure a real fix resolves → loop reaches green; (b) Status written only from the final run; (c) a *hardcoding* fix that the anti-hardcoding check flags as a WARNING (and confirm it does **not** block a legitimately-correct fix that happens to contain the expected status code); (d) the env guard aborting on a non-loopback URL; (e) reuse/adopt idempotency preserving a manual `**Status:**`. Rationale: markdown command-specs aren't unit-tested in CI (only the executable `commit` hooks are); a structural frontmatter/contract check could be added later.

---

## 12. Versioning & Documentation (per CLAUDE.local.md)

All four version locations change **in the same commit** (parity CI gates on it):

- `plugins/qa/.claude-plugin/plugin.json`: **2.0.1 → 2.1.0** (MINOR — new command).
- `.claude-plugin/marketplace.json`: `qa` entry → **2.1.0**.
- `README.md`: `qa` row → **2.1.0** + closed-loop mention; plugin-count badge **unchanged**.
- `docs/plugins/qa.md`: document `/qa:loop` (args, modes, guards, algorithm, sidecar, examples, the scenario-level + cross-section-regression limitations) + `**Version:** 2.1.0` header; document the `report-format` `## Loop History` extension.

---

## 13. Success Criteria

1. `/qa:loop` against a plan with genuinely fixable failures drives the affected scenarios to passing — or to a bounded, clearly-reported stop — under the default `approve` gate, and end-to-end in `auto` (loopback env).
2. `**Status:** ✅ Fixed` is written **only** from the authoritative final run; QA-XXX IDs are stable across iterations/reuse (anchored in the sidecar); the report stays compatible with `/fix` / `/fix-report`.
3. The anti-hardcoding warning fires on a payload-hardcoding fix **without** blocking a correct fix.
4. The guards bound the loop and its blast radius: iteration/dispatch/time budgets, oscillation stop, fail-closed base-URL resolution, loopback-only execution, mutation gate, reversible source edits.
5. No changes to `fix-auto` or the tester agents; `report-format` gains exactly one documented optional section; the sidecar is the only new state artifact; existing QA / code-review flows are unaffected.

---

## 14. Resolved Decisions

| Decision | Choice |
|---|---|
| Strategic direction | Close existing loops |
| First target | `qa` fix → re-test loop |
| Architecture | New `/qa:loop` command (reuses testers + `fix-auto`) |
| Default mode | `approve` (`auto` opt-in; env-guarded) |
| **Granularity** | **Scenario-level** (no sub-test map); intra-scenario partial progress not separately credited |
| **Loop state** | **Command-owned sidecar JSON file** (not an in-report block) |
| **Re-run unit** | **Whole affected section** (dependency-safe; no free-text dep parse) |
| **Budgets** | iterations + **dispatch-count** + wall-clock (no token budget) |
| **Verifier-gaming** | source-only + payload-scoped anti-hardcoding **warning** + plan fingerprint + `approve` gate; randomized re-verification deferred to v2 |
| Base-URL safety | explicit resolution, **fail-closed**, loopback-only + `--allow-mutations` |
| Status write-back | once, from the authoritative final run |
| Regressions in v1 | reported, not auto-fixed |
| `report-format` | extended with one documented optional section |
| Tests in v1 | manual recipe (incl. hardcoding-warning + env-guard cases) |

---

## 15. References (selected research)

- Anthropic — *Building agents with the Claude Agent SDK*; *Effective context engineering*; *Effective harnesses for long-running agents*.
- Huang et al., ICLR 2024 — *LLMs Cannot Self-Correct Reasoning Yet*.
- Kamoi et al., TACL 2024 — self-correction needs reliable external feedback.
- *ImpossibleBench* / reward-hacking literature — protect the verifier (basis for §5.2's honest boundary).
- Jason Wei — *Asymmetry of verification and Verifier's Law*.

---

## Appendix A — Review trail (v1 → v2 → v3)

- **Round 1** (4 lenses) → v2 closed 6 blockers + 7 majors (granularity, verifier-gaming, side effects, idempotency, frontmatter, Location deadlock; no-progress, regression accumulation, dependencies, Loop-History honesty, parity-CI error, `⚠️` freeze, budgets).
- **Round 2** (3 lenses) verified v2 (8/13 findings solidly closed) and exposed a **"phantom mechanism" cluster** — controls resting on non-existent data/tools: the sub-test-label join key, an unmeasurable token budget, non-existent base-URL resolution, `jq` on HTML-comment JSON, and a credit-blocking anti-hardcoding check that false-positives — plus internal seams (ID-minting collision, dead `approve` re-ask, redundant Location injection, hollow "living document", top-K starvation, missing `mv/cp`). **v3 dissolves the cluster** via scenario-level granularity, a sidecar state file, section-level re-runs, real fail-closed URL resolution, a dispatch-count budget, and a non-blocking anti-hardcoding warning, and reconciles every seam.

## Appendix B — Known residual risks (accepted for v1, by decision)

- **Verifier-gaming** beyond payload-literal hardcoding is not fully preventable in-loop; backstop is the `approve` gate; randomized re-verification is the planned v2 fix.
- **Scenario-level coarseness** — when one scenario has several QA-IDs, they are credited together; a fix that resolves the main flow but not an edge case credits neither until the whole scenario passes.
- **Cross-section regressions** are caught only at the final full run (intra-section caught each iteration).
- **Mutation guard** is a static pre-classification with no rollback — `--allow-mutations` should point at a disposable test DB.
- **Section re-runs** can be costly (a full Playwright section per iteration); bounded by the dispatch/time budgets; finer selectivity is a v2 optimization.

# qa 2.3.0 — Coverage-Honesty & Advisory Hints for `/qa:loop` — Design

> **Revision v2** (post-MoA-spec-review). v1 was reviewed by a 3-lens mixture-of-agents pass (fidelity / phantom-mechanism data-flow / adversarial-safety); every finding was verified against `plugins/qa/commands/loop.md`. v2 adds the **structured result ingest** keystone (v1's mechanisms depended on per-scenario observed-status/reason state the command never parsed — the same phantom-mechanism class as the prior auto-plan spec's v2→v3), fixes the `provisional_scenarios` write-ordering inversion, audits the `auth-unverified` enum against every consumer, resolves the shallow-WARNING vs. mutation-guard-only collision, re-scopes the reachability hint (no `curl` in allowed-tools), and adds the 2xx-shaped-auth-gating honesty caveat. Changes are flagged inline as **[v2: …]**.
>
> **Revision v3** (final verification round). A 3-lens pass (keystone-groundedness / new-seam / implementation-readiness) confirmed the v2 fixes landed and converged on one cluster: §1.0 promised to parse `reason` tokens and signals that the testers emit only as **free prose** (verified: the canonical tokens `tool-unavailable`/`cannot-confirm`/`parse-failure` appear nowhere in the tester files). v3 specifies the prose→canonical **normalization map**, the `**Response status:**` integer parse (main request; ignore `(expected: N)`), **edge-case** sub-block handling, **FE-has-no-status** scoping, a **concrete §4 transport signal**, the §2b/§2c subsumption, the provisional **numbering order**, and corrects the error-table change-site range. Changes flagged **[v3: …]**. Verdict: implementation-ready.

**Goal:** Make `/qa:loop` tell the truth about *what it actually verified* (not just "all passing"), and give the user actionable guidance when coverage is shallow — while closing a latent safety hole where an auto-generated assertion can drive `fix-auto` to edit correct source.

**Architecture:** Additive, **runtime/output-only where possible**. The detection signal that makes honest reporting possible is parsed by the orchestrator from data the testers *already* emit (observed HTTP status + SKIP reason, as prose), assembled into a structured per-scenario record, and persisted in the sidecar. Tester agents' contracts and `/qa:create-plan` are left untouched — dodging the create-plan/loop duplication trap (the deferred shared-skill extraction). Only the T3 safety work touches the generation step, and only inside `/qa:loop`'s inlined auto-plan.

**Tech Stack:** Claude Code plugin (markdown command-spec `plugins/qa/commands/loop.md` + the `report-format` skill), Bash (`jq`/`git`), the repo's `scripts/check_plugin_versions.py` parity gate.

**Versioning:** qa **2.3.0** (MINOR — all changes additive: a new result classification, new summary sections, more-honest wording on an already-successful exit, and a safety guard on the fix path; no removed commands, no changed flag semantics, **no new flags**). **[v3]** The new shallow-coverage WARNING (§2b) is provenance-independent — it can appear on an existing user's hand-authored plan in **any** mode, a visible change to a previously-silent green run (still additive and non-gating; MINOR holds). Forward-compat note: the new `auth-unverified` sidecar status is additive; an older `/qa:loop` build reading a 2.3.0 sidecar treats an unknown status as non-failing (it is neither `"pass"` nor `"fail"`), degrading like `skip` — no crash, and a hash-mismatch re-baseline (loop.md `.bak` archive path) recovers cleanly.

---

## Nature of this implementation (read first)

This is **prompt-engineering, not application code**: the deliverables are edits to a markdown command-spec, a skill, and docs, plus a version bump. There is no unit-testable runtime, so verification is by structural checks (`grep`/Read confirming authored sections + tokens), `jq` validity on the documented sidecar example, and the version-parity gate — the same regime used for qa 2.1.0 / 2.2.0.

---

## 1. Context & Motivation

`/qa:loop` (qa 2.2.0) is a loopback HTTP test→fix→retest orchestrator: it dispatches `qa:be-tester`/`qa:fe-tester` against a locally-running app, auto-fixes failures via `code-review:fix-auto`, re-runs, and (2.2.0) auto-generates a plan from the branch diff when none exists.

A real run on an unrelated project exposed the problem this design fixes. On a backend-only, **JWT-gated** branch whose feature behavior lives in an async Temporal worker:

- Auto-plan generated 6 BE scenarios; the mutation guard SKIP'd the 2 writes; the remaining 4 "PASSED".
- But those 4 PASSes were **infra sanity** (`/health` 200, OpenAPI builds) + **auth-enforcement** (401 without a token). Every `/api/v1/*` happy-path was unreachable (no token). The feature itself was never exercised.
- The zero-failure exit fired → reported **success**. The Loop Summary surfaced only the 2 mutation-guard SKIPs. The deeper truth — *the feature was never verified* — surfaced **only when the user explicitly asked "what was skipped and why?"**.

A 4-lens mixture-of-agents review (coverage-honesty, SKIP-taxonomy, auth-reachability, auto-plan-fidelity), each finding verified against the source, produced the findings below. The central insight: **the user's requested "advisory hints" sit on top of a missing detection layer.** You cannot truthfully report a coverage gap the command cannot detect — and today an auth-gated 200-path is scored as a PASS (the 401 edge-case matched `expected`), so the loop has *no datum* saying the feature went unverified.

---

## 2. Verified problem statement

All line references verified against `plugins/qa/commands/loop.md` (qa 2.2.0).

**T1 — Auth-blindness (HIGH).** `loop.md` contains zero auth handling (grep for `auth|token|401|jwt|bearer` returns only unrelated hits). The BE tester dispatch (`:381-392`) passes only Base URL + DB connection — **no token**. `be-tester.md:91` is best-effort ("try to obtain one by calling the auth endpoint") and the be-testing skill uses an undefined `$TOKEN` placeholder. The tester is told *not* to skip reachable scenarios (`be-tester.md:86`), so an auth-gated endpoint returns a real 401 → scored PASS/FAIL against `expected`, **never SKIP**. Consequence: there is no `auth-unverified` outcome, so the all-SKIP coverage nets (`:466-483`) can never fire for an auth-walled feature.

**T2 — Coverage-honesty on the success path (HIGH).** The zero-failure exit (`:458-464`) is a pure `failures == 0` test — a trivial all-PASS (health + 401-enforcement) is reported *identically* to a run that exercised the feature. The coverage-zero WARNING (`:473-475`) lives **entirely inside** the "all scenarios are SKIP" branch, so it cannot fire on a partial run (4 PASS / 2 SKIP). The Loop Summary (`:888-913`) and the `report-format` Summary have no "verified vs NOT-verified, and why" slot. The `auto_generated` provenance flag exists (`:327`) but is unused on the green path.

**T3 — Auto-plan → fix-auto "phantom fix" (HIGH, latent).** Step 3a fix-set selection (`:550-563`) reads `current == "fail"` with **no branch on `auto_generated`**. Step 3c (`:627-630`) then injects into `fix-auto`: *"Source-only fix: do not modify the test plan… Fix only the source code under test."* So a **wrong auto-generated assertion** (the run's `/docs`→404 and 401-vs-404 misses) becomes a phantom failure that `fix-auto` is told to "fix" by editing correct source. It did not fire in the observed run (zero-failure), but is fully reachable on the next auto-plan that emits one wrong-but-failing assertion. Partial existing mitigation: the `unknown:0` location pre-filter (`:557-561`) drops issues with no source location.

---

## 3. Goals / Non-goals

**Goals**
1. A detection layer that lets the loop *know* when feature behavior was not exercised (auth-gated, skipped, unreachable).
2. Honest coverage reporting on every run: a Coverage block, a shallow-coverage WARNING that fires on partial runs, and a "low-confidence green" caveat — **without converting green to red** (disclose-don't-gate).
3. The three advisory mechanisms the user asked for: (#1) reactive unlock-hints keyed by SKIP/outcome reason, (#2) the proactive "what was NOT verified and why" summary, (#3) reactive contextual setup suggestions.
4. Close T3: stop `fix-auto` from editing correct source to satisfy an unverified auto-generated assertion.

**Non-goals (explicitly out of scope, with rationale)**
- **Token intake / `--auth-token` (T1b).** Deferred. The auth dimension is **disclose-only** in 2.3.0. **[v2: honest cost statement]** On a fully auth-gated *synchronous* app — the motivating case — disclose-only means `/qa:loop`'s feature-verification value is ~zero until T1b lands; the `auth-unverified` unlock-hint is *informational*, not *actionable* (unlike `--allow-mutations`, which is). **T1b (a bounded raw-token passthrough into the tester dispatch) is the real fix and is the single highest-value follow-up.**
- **Driving login flows or Temporal workers.** Rejected — turns a loopback HTTP loop into an integration-test harness it was never scoped to be. Worker-resident behavior is disclosed, not executed.
- **Hard-failing on shallow coverage.** Rejected — would break the legitimate backend-write-only graceful-success path (`:469-471`). Honesty is a *caveat on a still-green exit*, not a new failure mode.
- **Changing the tester agents' contract.** Avoided — `auth-unverified` is derived by the orchestrator from the observed status the tester already prints (`be-tester.md:66,73`). **[v2: §1.0 makes the parse explicit rather than assuming the datum is already structured.]**
- **Mirroring to `/qa:run` (D-07) or extracting a shared create-plan skill (D-06).** Deferred — documented deliberate "loop is the smart one" split; CORE is runtime-only so the duplication concern barely bites.

---

## 4. Design

### §1 Detection layer (the signal #2 depends on)

**§1.0 — Structured result ingest (keystone — new state everything below depends on).** **[v2: NEW — closes the phantom-mechanism gap.]**
Today the orchestrator receives each tester's output as a free-text blob (`loop.md:399`, `TaskOutput`) and the **only** extraction is "tally pass/fail/skip" (`loop.md:419`); the sidecar persists only `pass|fail|skip` (`loop.md:325-326`) — no observed status, no reason. Every mechanism below needs more. So at the baseline ingest (Step 2.1→2.3) **and every re-run ingest**, the orchestrator MUST parse each tester result block into a structured per-scenario record and persist its durable parts:
- **`verdict`** from the `**Status:**` line (`PASS`/`FAIL`/`SKIP`).
- **`observed_status`** from the `**Response status:**` line — take the **first integer** after the label, ignoring any `(expected: N)` parenthetical (`be-tester.md:73` prints `500 (expected: 201)`); this is the scenario's **main-request** status. **BE only** — the FE tester emits no `**Response status:**` line (`fe-tester.md`: Status/Details/Screenshot only), so `observed_status` is `null` for FE.
- **`reason`** for non-PASS scenarios — **[v3: normalized]** mapped from the tester's free prose into a canonical bucket, because the testers emit prose, not the bucket tokens (verified: `tool-unavailable`/`cannot-confirm`/`parse-failure` appear nowhere in the tester files). Mapping: `mutation-guard` is **orchestrator-assigned** at dispatch (`loop.md:351,374` — authoritative, not parsed); `/no .*client|unavailable|not supported/i` → `tool-unavailable` (e.g. `be-tester.md:40` "No HTTP client available", `fe-tester.md` "not supported in current Playwright MCP setup"); `/connection refused|could not connect|timeout/i` → a **`transport`** signal that feeds **§4 reachability**, *not* a coverage SKIP reason (`be-testing/SKILL.md:313-314`); any other unmatched prose → `cannot-confirm`.
- **`kind`** (§1a); then apply the §1b auth reclassification **at ingest**, so the verdict written into `baseline`/`current` already reflects `auth-unverified`.
- **[v3] Edge-case sub-blocks** (`be-tester.md:76-79`, nested `- <name>: PASS/FAIL`) are parsed for their inline verdict only; they carry no isolatable `**Response status:**`, so they are **not** subject to §1b reclassification and inherit the parent's `kind`.
- Persist in the sidecar: `scenario_kind` (static, written once) and `scenario_reason` (id → normalized reason for every non-PASS scenario, refreshed each run). `observed_status` is consumed transiently at ingest and need not persist.

This record is the single source of truth for §1b, §2 (Coverage / shallow trigger), and §3 (per-reason hint counts). It also *formalizes* the reason-read the existing Step 2.4 branch already performs ad-hoc (`loop.md:466-475`). Parsing is best-effort against the documented tester format (`be-tester.md:60-79`); if a block lacks a parseable status/reason, the field is recorded `null` and the dependent mechanism degrades gracefully (the scenario keeps its bare verdict).

**§1a — Scenario-kind classification.** Derived during §1.0 ingest from each scenario's declared `**Expected:**` status + endpoint path (the plan is already parsed by Step 2.1, `loop.md:347`; `**Expected:**` is a defined BE field, `test-plan-format:58`). Heuristic:
- BE: declared `**Expected:**` status **≥ 400** ⇒ `negative`; endpoint path in the sanity allowlist {`/health`, `/healthz`, `/openapi.json`, `/version`, `/`, `/docs`, `/api/docs`} ⇒ `sanity`; otherwise ⇒ `feature`.
- FE scenarios default to `feature` unless purely navigational/sanity.
- **[v2: ordering/default contract]** `scenario_kind` MUST be fully populated by the end of Step 2.3 (before the Step 2.4 exit reads it). Best-effort and non-gating: a feature endpoint that legitimately asserts a 4xx is misclassified `negative`; this only affects confidence wording, never a pass/fail decision.

**§1b — `auth-unverified` outcome (orchestrator post-classification, at ingest).** For a BE scenario with `kind == feature`: if the parsed `observed_status` ∈ {401, 403} **and** the declared `**Expected:**` is a 2xx, set the verdict to **`auth-unverified`** (executed, but the feature path was gated off — no token). Counted and surfaced, **never credited as PASS**. A scenario that *expected* 401 and got 401 stays a normal `negative` PASS (it asserts the gate works — a real, intended check). If `observed_status` is unavailable, leave the verdict unchanged (best-effort).

**[v2: 2xx-shaped auth-gating caveat — F1-02; v3: FE + edge-case scope.]** Detection is limited to an explicit 401/403 **on a BE scenario's main request**. It does **not** catch: auth-gating that returns a 2xx-shaped result (an empty `200 []`, a tenant-scoped `404`); auth surfaced only via an **edge-case sub-test** (parsed for verdict only — §1.0); or **any FE gating** (the FE tester emits no HTTP status, so an FE `302`→`/login` is *undetectable*, not merely undetected). In those shapes `observed == expected` (or no status at all) ⇒ scored PASS ⇒ counted as feature coverage. Therefore the Coverage block (§2a) reports **"Exercised"**, not "Verified", for feature PASSes, and its feature count is an **upper bound**, not a guarantee. §5b's bias toward robust invariants (non-5xx) makes the empty-200 case *more* likely to slip, so this caveat is load-bearing for honesty and is restated in §8.

**[v2: `auth-unverified` per-consumer audit — F2-03.]** "Treat like skip" is made precise at every `baseline`/`current`/`final` consumer:
- Step 2.4 failure count (`:458`): not a failure → does not block the zero-failure exit; it *is* the shallow signal (§2b).
- Step 3a fix-set (`:554`, `current == "fail"`): excluded → an auth-gated scenario is never sent to `fix-auto`.
- Step 3f regression (`:698`, `baseline == "pass" ∧ current == "fail"`): a transition to/from `auth-unverified` is never a regression (it is not `"fail"`).
- Step 3f progress (`:706`, `"fail" → "pass"`): `auth-unverified` scenarios are inert (never in `fix_candidates`); an `auth-unverified → pass` transition does not count as progress — **correct**, because the loop was not fixing it. Documented so it is intentional.
- Step 3g merge (`:731`): a re-run scenario that becomes `auth-unverified` updates `current` normally (merge, don't replace).
- Step 4.2 final regression: same rule as Step 3f.

### §2 Coverage-honesty output (T2 + mechanism #2)

**§2a — Coverage block.** Add a `## Coverage` block to the Loop Summary (Step 5.2) and a parallel slot in the `report-format` Summary (`##`-level, no `### [SEVERITY]` headings, no `---` — parser-safe per the report-format block rules):
```
## Coverage
- Exercised: <feature-PASS> feature · <sanity-PASS> sanity · <negative-PASS> enforcement
- Not verified: auth-unverified <N> · mutation-guard SKIP <M> · tool-unavailable <K> · …
- Confidence: <high | low — reason>
```
**[v2: "Exercised" not "Verified"]** — per §1b's 2xx-shaped caveat, a feature PASS means "reached and returned a non-4xx", which is an upper bound on true verification.

**§2b — Shallow-coverage WARNING (generalized).** Define `meaningful = count(verdict == PASS AND kind == feature)`. Coverage is **shallow** when `meaningful == 0` **and** ≥1 `feature` scenario did not PASS (it was `auth-unverified` / `skip` / `fail`). On shallow coverage, emit:
> Warning: shallow coverage — no feature behavior was exercised (N feature scenarios were auth-unverified/skipped/unreachable). This green reflects infrastructure and enforcement checks only.

**[v2: precedence — F3-04.]** This WARNING does **NOT** fire on the existing mutation-guard-only all-SKIP graceful path (`loop.md:469-471`): that case already has its dedicated success message ("backend-write-only — rely on the unit/integration suite") plus the §3 mutation-guard unlock-hint, and is the legitimate backend-write-only case this design protects. Precedence: the mutation-guard-only all-SKIP branch keeps its existing message and emits no §2b WARNING. The WARNING generalizes only the *coverage-zero* sibling (`:473-475`) to partial-PASS runs.

**[v2: no false alarm for sanity-only plans — F3-05.]** Because the trigger requires ≥1 `feature` scenario that did not PASS, a plan containing **zero** feature-kind scenarios (a deliberately sanity/enforcement-only plan) never fires the WARNING — there is nothing claimed-but-unverified to warn about.

**§2c — Low-confidence green on the zero-failure exit.** In Step 2.4, when the run would print "All passing, nothing to fix" **and** coverage is shallow **and** `auto_generated == true`, replace the message (still exit **success**):
> All assertions passed, but coverage is shallow — no feature behavior was exercised (see Coverage). Low-confidence green: the plan was auto-generated and may not reflect runtime auth/setup.

The §2b WARNING is provenance-independent; only this §2c *exit-message rewording* is gated on `auto_generated` (a user who authored a plan owns its scope and keeps the plain "All passing" message alongside the Coverage block).

**§2d — Subordination (guardrail D-04).** **[v3]** There is one authoritative coverage verdict per run. On the auto-generated zero-failure path where both could apply, the §2c reworded exit line **subsumes** the §2b WARNING — print the §2c line, not both. On any other shallow path (a user-authored plan, or a run that went through the loop to Step 5.2), the §2b WARNING is the verdict. The Coverage block (§2a) restates counts and references that verdict; it never re-decides or softens it into neutral prose.

### §3 Unlock-hints surface (mechanism #1)

Add a "Next steps to widen coverage" list to the Loop Summary, rendered **only** for reasons that actually occurred this run (counts come from `scenario_reason`, §1.0), keyed reason → count → remediation:
- `mutation-guard` (N): re-run with `--allow-mutations` (test DB must be disposable).
- `auth-unverified` (N): the app is auth-gated; `/qa:loop` verifies enforcement only. Exercise authenticated behavior via the project's integration/e2e suite. *(A `--auth-token` intake is not available in this version — see §8.)*
- `tool-unavailable` (N): install/enable the missing tool (Playwright / curl / DB client).
- `dispatch-exhausted`: raise `--max-dispatches`.

The existing standalone mutation-guard surfacing (`:415-417`) folds into this single table (one source of truth). **[v3]** Counts come from the §1.0 normalized `scenario_reason`: `mutation-guard` is exact (orchestrator-assigned), the others are heuristic prose-matches and may under-count — acceptable for an advisory hint.

### §4 Contextual reactive suggestions (mechanism #3, safe subset)

Reactive only, each with its paired caveat:
- **[v2: re-scoped post-baseline; v3: concrete signal.]** **Reachability:** the orchestrator has no `curl` in its allowed-tools (`loop.md:2`) and never probes the URL itself, so a *pre*-baseline liveness check is not implementable without a tools change. Instead, derive it from the §1.0 ingest's **`transport`** signal: trigger **only when every BE scenario** is `FAIL` with a `transport` reason (Details matched `/connection refused|could not connect|timeout/i`) and a `null` `observed_status`; FE SKIPs are ignored for this signal. Because a transport-FAIL is indistinguishable from a genuine all-5xx app at the verdict level, phrase it honestly — *after* baseline: "no BE scenario returned an HTTP status at `<host:port>` — the dev stack may be down (or every endpoint is 5xx'ing)." (host:port assembled per §6, never from the raw error string.)
- **Mutation suggestion:** if every BE scenario was mutation-guard SKIP, print the §3 mutation-guard hint.

**No proactive guard-widening nudges.** Flags that widen a guard (`--allow-mutations`, `--allow-host`, `--allow-dirty`, `--auto-plan` in auto) appear only in the *reactive* unlock-hints after the guard actually blocked something — never as an up-front "tip".

### §5 T3 — auto-plan → fix-auto safety

**§5a — Plan-suspect branch in fix-set selection (Step 3a).** A failing scenario that is **provisional** (see §5b) is treated as *plan-suspect*, not code-suspect:
- `approve`/`step` mode: include it in the HITL gate, flagged `⚠ auto-generated assertion — verify before fixing`; the user approves or skips.
- `auto` mode: **exclude** it from `fix_candidates` and log `auto-generated assertion suspected; not auto-fixing — verify the plan.` (Do not dispatch `fix-auto` — and because Step 3c only iterates `fix_candidates`, `loop.md:616`, the "fix source, don't touch the plan" injection is never reached for it.)
- A failure on a **non-provisional** assertion uses the normal fix path: real bugs (5xx, stack-trace leak) are still auto-fixed.
- **[v2: default — F1-06]** absent `provisional_scenarios` (every user-provided plan) means *no* scenario is plan-suspect → §5a falls through to the normal fix path for all failures.

**§5b — Provisional generated assertions (Step 0.2.1 decision, Step 1.3 persist).** When auto-plan generates scenarios, bias assertions toward **observable invariants** the generator can be confident about (non-5xx, no stack-trace/secret leak in the body, auth-gate present) rather than guessed exact path+status. Where an exact value must be asserted that the generator could not observe, mark the scenario **provisional**.
- **[v2: granularity — F3-01]** A provisional (guessed-exact) assertion MUST be generated as its **own** scenario — never co-located in a scenario that also carries a robust invariant — so that scenario-level exclusion in §5a can never drop a real 5xx/leak finding that happened to ride alongside a guess. **[v3]** The provisional split happens **before** BE-NN/FE-NN numbers are assigned; numbers are assigned once over the final scenario set, and `provisional_scenarios` is populated from those final IDs — so the surfacing banner's scenario count (`loop.md:181-183`), the `### BE-NN` headings, and the `provisional_scenarios`/`scenario_kind` maps all derive from one settled numbering.
- **[v2: write-ordering — F2-02]** The provisional set is *decided* at Step 0.2.1 but **persisted at Step 1.3** (`provisional_scenarios` array), mirroring how `auto_generated` is decided-at-0.2.1 / written-at-1.3 (`loop.md:317`). It must NOT be written at Step 0.2.1, where the sidecar does not yet exist. **[v3]** The mirror is imperfect in one way: `auto_generated` is re-derivable from on-disk state, whereas the specific provisional-ID set lives only in the orchestrator's same-session context between 0.2.1 and 1.3 — so Step 0.2.1 SHOULD also note the provisional IDs in its surfacing output, making them reconstructable if 1.3 is reached after a context loss (otherwise provisional degrades to empty → §5a safely falls through to the normal fix path). On the REUSE/ADOPT idempotency paths, preserve the existing value (like `auto_generated`).
- Generation-time, **loop-only** — `create-plan.md` is not modified; the minor divergence is accepted because `/qa:run` has no fix loop to weaponize a wrong assertion.

### §6 Guardrails (woven through all of the above)

- **Redaction contract (D-03).** **[v2: hardened — F3-03.]** Coverage / hint / suggestion / banner text may include scenario IDs and a *category* reason only. It MUST NOT interpolate the resolved URL authority beyond `host:port`, any `*_URL`/DSN/connection-string value, userinfo, or filesystem paths surfaced by fetch errors. Where a host must be shown, assemble the string **solely** from the env-guard-sanitized host (Step 0.4, `loop.md:213-218`, which rejects userinfo and strips brackets) **plus** the separately-parsed port integer — never from any raw fetch/resolver error body, which is discarded.
- **Subordination (D-04):** §2d.
- **Reactive-not-nudge (D-05):** §4.
- **Placement (D-06):** all CORE logic is runtime/output inside `loop.md`; only §5b touches generation, loop-only; tester contracts and `create-plan.md` are untouched; shared-skill extraction stays deferred.
- **Consistency (D-07):** `run.md` unchanged; the deliberate split is documented in `docs/plugins/qa.md`.

---

## 5. Change sites

`plugins/qa/commands/loop.md`
- Sidecar schema (`~:299-331`): add `scenario_kind` (map), `scenario_reason` (map), `provisional_scenarios` (array); extend `baseline`/`current` status enum with `auth-unverified`; document the forward-compat note.
- **[v2]** Step 1.3 sidecar init (`~:295-317`): persist `provisional_scenarios` alongside `auto_generated` (decided in Step 0.2.1); preserve on REUSE/ADOPT.
- Step 0.2.1 generation (`~:130-177`): §5b robust-assertion bias + own-scenario rule for provisional + *decide* `provisional_scenarios`.
- **[v2]** Step 2.1→2.3 ingest (`~:339-446`): §1.0 structured per-scenario parse (verdict/observed_status/reason), §1a `scenario_kind`, §1b `auth-unverified` reclassification-at-ingest, persist `scenario_kind`/`scenario_reason`.
- Step 2.2 report build (`~:413-419`): fold mutation-guard surfacing into §3; build the Coverage block source from the §1.0 record.
- Step 2.4 (`~:456-483`): §2b generalized shallow WARNING **with the mutation-guard-only precedence carve-out**; §2c low-confidence green.
- Step 3a (`~:550-563`): §5a provisional-suspect branch (+ absent-array default).
- Step 3f consumers (`~:696-710`): document `auth-unverified` behavior in regression/progress checks.
- Step 5.2 Loop Summary (`~:888-915`): §2a Coverage block + §3 unlock-hints + §4 reactive suggestions.
- Error-handling table (`## Error Handling`, `~:969-995`): document `auth-unverified` and shallow-coverage rows.

`plugins/qa/skills/report-format/SKILL.md`: add the `## Coverage` block to the Summary section (`##`-level, parser-safe).

`docs/plugins/qa.md`: document coverage-honesty (Coverage block, shallow WARNING, low-confidence green), the new `auth-unverified` outcome, the unified unlock-hints, the reactive suggestions, and T3 provisional behavior; note the deliberate `/qa:run` split. **[v2: F3-02/F3-06]** Extend the existing `> [!IMPORTANT]` behavior-change note to cover (a) the new shallow-coverage WARNING and reworded zero-failure exit visible to existing users, and (b) that `--mode auto --auto-plan` may now produce an **empty fix-set** (auth-unverified + provisional exclusions) and exit green-with-caveat *by design*. **[v3]** Widen the note's heading scope beyond "`--mode auto` users" — the §2b shallow-coverage WARNING is provenance-independent and fires in approve/step and on user-authored plans too.

Version parity → **2.3.0**: `plugins/qa/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md` (Available Plugins row), `docs/plugins/qa.md` `**Version:**`. **[v2: F3-06]** The parity gate checks *version* only, not description text — if the `README.md` row + `marketplace.json` description one-liners gain a "+ honest coverage reporting" clause, update both in lockstep manually (CI won't catch drift).

---

## 6. Sidecar schema additions (illustrative)

```json
{
  "auto_generated": true,
  "scenario_kind": { "BE-01": "sanity", "BE-02": "sanity", "BE-03": "negative", "BE-04": "feature" },
  "scenario_reason": { "BE-04": "auth-unverified", "BE-05": "mutation-guard" },
  "provisional_scenarios": ["BE-04"],
  "baseline": { "BE-01": "pass", "BE-03": "pass", "BE-04": "auth-unverified", "BE-05": "skip" },
  "current":  { "BE-01": "pass", "BE-03": "pass", "BE-04": "auth-unverified", "BE-05": "skip" }
}
```

---

## 7. Rejected alternatives

- **Token intake now (T1b).** Deferred to a future MINOR; disclose-only chosen for 2.3.0 (with the honest cost stated in §3/§8). Even with a token, the observed run's worker-resident feature stays unreachable — token helps only synchronous auth-gated apps.
- **Hard-fail on shallow coverage.** Rejected — breaks the legitimate backend-write-only graceful-success path; disclose-don't-gate instead.
- **Login/Temporal driving.** Rejected — integration-harness scope creep.
- **New `auth-unverified` SKIP emitted by the tester.** Rejected in favor of orchestrator post-classification from the already-printed observed status (no tester-contract change, no create-plan spread). **[v2: §1.0 makes the parse an explicit orchestrator step rather than an assumed-structured datum.]**
- **Per-assertion provisional marking via a new `test-plan-format` field.** Rejected — kept at scenario level in the sidecar (with the own-scenario rule, §5b) to avoid touching the shared plan-format skill and `/qa:create-plan`.
- **[v2] Pre-baseline `curl` liveness probe.** Rejected — would require adding `curl` to the loop's allowed-tools (new surface); the reachability hint is derived post-baseline from tester output instead (§4).
- **[v2] Adding `curl` to the orchestrator generally.** Rejected — the testers already own HTTP; the orchestrator stays a coordinator.

---

## 8. Residual risks (carried, accepted)

- **2xx-shaped auth-gating is undetected (F1-02):** an empty `200 []`, a tenant `404`, or an FE `302`→login is scored PASS, so the Coverage "Exercised: N feature" count is an **upper bound**, not a guarantee. This is the main honesty limit of the disclose-only approach; mitigated only partially by the "Exercised" (not "Verified") wording and the explicit caveat.
- **Disclose-only leaves auth-gated apps at ~zero feature-verification value (F1-03):** the `auth-unverified` unlock-hint is informational, not actionable, until **T1b** (the highest-value follow-up) lands.
- **Generation-time auth-labeling (C-02) is not implemented:** §1b masks the symptom at *runtime*; an all-auth-gated diff is not flagged at *generation*. Acceptable because the user-facing outcome (the run is flagged) is achieved at runtime, but the generation-time detection is genuinely deferred.
- **§1.0 parse fragility:** `auth-unverified`/reason/status detection depends on parsing the tester's documented prose format (`be-tester.md:60-79`); a tester that omits or rephrases `**Response status:**` degrades the mechanism to a silent no-op (the scenario keeps its bare verdict). A future tester-side structured-output contract would harden this. **[v3]** Specifically undetected by design: (a) auth surfaced only via an **edge-case sub-test** (no isolatable status); (b) **any FE auth-gating** (the FE tester emits no HTTP status); (c) reason buckets beyond `mutation-guard` are heuristic prose-matches, so `tool-unavailable`/`cannot-confirm` counts are approximate.
- **Coarse `scenario_kind` classifier:** a feature endpoint asserting a 4xx is misread `negative`; FE kind is coarse. Best-effort; only shapes confidence wording, never gates.
- **`create-plan.md` divergence:** provisional marking lives only in the loop's auto-plan. Accepted (no fix loop in `/qa:run`).
- **`--mode auto --auto-plan` may now fix nothing (F3-02):** auth-unverified + provisional exclusions can empty the fix-set; this is intended and disclosed in the behavior-change note.
- **Low-confidence green is wording-only:** a determined reader can still over-trust green; mitigated by the explicit WARNING + Coverage block.
- **Verifier-gaming carryover** from 2.1.0 is unchanged (mitigation remains `--mode approve`).
- **Deferred shared-skill extraction (D-06)** is revisited only if generation-time advisory logic grows.

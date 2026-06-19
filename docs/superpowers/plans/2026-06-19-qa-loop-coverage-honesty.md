# qa 2.3.0 — Coverage-Honesty & Advisory Hints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/qa:loop` honestly report what it actually verified (not just "all passing"), give actionable unlock-hints when coverage is shallow, and stop `fix-auto` from editing correct source to satisfy an unverified auto-generated assertion — shipping as qa **2.3.0**.

**Architecture:** Additive edits to one markdown command-spec (`plugins/qa/commands/loop.md`) plus the `report-format` skill and docs. A new **structured result-ingest** step parses each tester's prose output into a per-scenario record (`verdict`/`observed_status`/`reason`/`kind`), persisted in the sidecar; every honesty mechanism reads that record. Tester agents and `/qa:create-plan` are **not** modified. Only the T3 safety work touches the inlined auto-plan generation.

**Tech Stack:** Claude Code plugin (markdown command-spec + `report-format` skill), Bash (`jq`/`git`/`grep`), the repo's `scripts/check_plugin_versions.py` version-parity gate.

**Spec:** `docs/superpowers/specs/2026-06-19-qa-loop-coverage-honesty-design.md` (v3). Read it before starting; each task cites the section it implements.

---

## Nature of this implementation (read first)

This feature is **prompt-engineering, not application code**: every deliverable is an edit to a markdown command/skill/doc file plus a version bump. There is **no unit-testable runtime**, so this plan does NOT use pytest-style TDD. Each task is verified by the real checks this repo supports:

- **Structural checks** — `grep`/Read confirming the authored section contains the required tokens/logic.
- **JSON validity** — `jq` over the documented sidecar example block.
- **Version parity** — `python3 scripts/check_plugin_versions.py` (must print all-OK for qa at the new version).

Commits use the repo's bypass: `env AV_COMMIT_SKILL=1 git commit -m "…"` (fish requires the `env` prefix). **No** `Co-Authored-By` trailer (repo /commit convention). Conventional-commit types; scope `qa:loop`.

**Hard ordering constraint:** Task 2 (§1.0 ingest) and Task 1 (schema) MUST land before Tasks 3–8 (they all read the ingest record / sidecar fields). Tasks 9–10 (T3) and Task 11 (docs/version) can follow.

---

## File Structure

| File | Responsibility | Tasks |
|------|----------------|-------|
| `plugins/qa/commands/loop.md` | The command-spec — all runtime logic | 1–10 |
| `plugins/qa/skills/report-format/SKILL.md` | The `## Coverage` block in the report Summary | 5 |
| `docs/plugins/qa.md` | User docs + `> [!IMPORTANT]` behavior-change note + `**Version:**` | 11 |
| `plugins/qa/.claude-plugin/plugin.json` | Plugin version | 11 |
| `.claude-plugin/marketplace.json` | Marketplace version (+ optional description) | 11 |
| `README.md` | Available-Plugins row version | 11 |

Canonical names used across tasks (keep identical):
- Sidecar fields: `scenario_kind` (id→`"sanity"`/`"negative"`/`"feature"`), `scenario_reason` (id→reason), `provisional_scenarios` (array of ids); status enum gains `"auth-unverified"`.
- Reason buckets: `mutation-guard`, `tool-unavailable`, `cannot-confirm`, and `transport` (the connection/timeout signal that feeds §4 — **not** a coverage SKIP reason).
- Output: a `## Coverage` block with `Exercised:` / `Not verified:` / `Confidence:` lines.

---

### Task 1: Sidecar schema additions (data model foundation)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 1.3 sidecar schema (`~:295-331`)

Implements spec §6 + the `auth-unverified` enum + forward-compat note.

- [ ] **Step 1: Add the three new fields to the JSON schema example.** In the ```json``` block at `loop.md:300-314`, add after `"scenario_issues": …`:

```json
  "scenario_kind": { "BE-03": "negative", "BE-04": "feature" },
  "scenario_reason": { "BE-04": "auth-unverified", "BE-05": "mutation-guard" },
  "provisional_scenarios": [],
```

- [ ] **Step 2: Extend the `baseline`/`current` enum docs.** Edit the two field-doc lines (`loop.md:325-326`) to read `→ "pass" | "fail" | "skip" | "auth-unverified"` (append the new value to both).

- [ ] **Step 3: Add field docs.** After the `scenario_issues` field-doc bullet, add:

```
- `scenario_kind`: map of scenario-id → "sanity" | "negative" | "feature" (set once at baseline ingest, Step 2.1; classifies what a PASS means for coverage)
- `scenario_reason`: map of scenario-id → normalized reason for every non-PASS scenario ("mutation-guard" | "tool-unavailable" | "cannot-confirm" | "transport"), refreshed each ingest; drives the Coverage block and unlock-hints
- `provisional_scenarios`: array of auto-generated scenario-ids whose assertions are guessed-exact (decided in Step 0.2.1, persisted here); read by Step 3a to treat their failures as plan-suspect
```

- [ ] **Step 4: Add the forward-compat note** after the schema block: `An older /qa:loop build reading a 2.3.0 sidecar treats the unknown "auth-unverified" status as non-failing (neither "pass" nor "fail"), degrading like "skip"; a hash-mismatch re-baseline recovers cleanly.`

- [ ] **Step 5: Verify.** Run:
```bash
jq -e '.scenario_kind and .scenario_reason and (.provisional_scenarios|type=="array")' <(sed -n '/^```json/,/^```/p' plugins/qa/commands/loop.md | sed '1d;$d' | head -20)
grep -c 'auth-unverified' plugins/qa/commands/loop.md   # expect >= 3
```
Expected: `jq` prints `true`; grep count ≥ 3.

- [ ] **Step 6: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): add scenario_kind/scenario_reason/provisional_scenarios + auth-unverified to sidecar schema"
```

---

### Task 2: §1.0 structured result ingest + normalization (KEYSTONE — land before Tasks 3–8)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 2.2 "Render Report", insert a new ingest subsection before the existing `1. **Count results:**` (`~:411-419`)

Implements spec §1.0. This is the load-bearing parse; everything downstream reads its record.

- [ ] **Step 1: Author the ingest subsection.** Insert immediately before `loop.md:419` (`1. **Count results:**`):

````markdown
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
````

- [ ] **Step 2: Verify.** Run:
```bash
grep -nE 'Structured Result Ingest|observed_status|transport|first integer|Edge-case sub-blocks' plugins/qa/commands/loop.md
```
Expected: all five tokens present under the new subsection.

- [ ] **Step 3: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): add structured result ingest with prose→reason normalization (Step 2.1.5)"
```

---

### Task 3: §1a scenario-kind classification

**Files:**
- Modify: `plugins/qa/commands/loop.md` — add Step 2.1.6 immediately after the Task 2 ingest subsection

Implements spec §1a.

- [ ] **Step 1: Author the classifier.** Insert after Step 2.1.5:

````markdown
#### Step 2.1.6: Scenario-Kind Classification

For each scenario, derive `kind` from its declared `**Expected:**` status + endpoint path (the plan is already parsed at Step 2.1):

- BE: `**Expected:**` status **≥ 400** ⇒ `negative`; endpoint path ∈ {`/health`, `/healthz`, `/openapi.json`, `/version`, `/`, `/docs`, `/api/docs`} ⇒ `sanity`; otherwise ⇒ `feature`.
- FE: default `feature` unless purely navigational/sanity.

`scenario_kind` MUST be fully populated by the end of Step 2.3 (before Step 2.4 reads it). Best-effort and non-gating — a feature endpoint that asserts a 4xx is misclassified `negative`; this only shapes confidence wording, never a pass/fail decision.
````

- [ ] **Step 2: Verify.**
```bash
grep -nE 'Scenario-Kind Classification|sanity allowlist|≥ 400|/openapi.json' plugins/qa/commands/loop.md
```
Expected: the classifier subsection with the ≥400 rule and the sanity allowlist.

- [ ] **Step 3: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): classify scenario kind (sanity/negative/feature) at ingest"
```

---

### Task 4: §1b auth-unverified reclassification + per-consumer audit

**Files:**
- Modify: `plugins/qa/commands/loop.md` — add Step 2.1.7 after Step 2.1.6; add a per-consumer note at Step 3f (`~:696-710`)

Implements spec §1b.

- [ ] **Step 1: Author the reclassification.** Insert after Step 2.1.6:

````markdown
#### Step 2.1.7: Auth-Unverified Reclassification (at ingest, BE only)

For a BE scenario with `kind == feature`: if the parsed `observed_status` ∈ {401, 403} **and** the declared `**Expected:**` is a 2xx, set `verdict = auth-unverified` (executed, but the feature path was gated — no token). Counted and surfaced, **never** credited as PASS. A scenario that *expected* 401 and got 401 stays a normal `negative` PASS. If `observed_status` is `null`, leave the verdict unchanged (best-effort).

**Not detected (residual, see §8 of the spec):** 2xx-shaped gating (empty `200 []`, tenant `404`), auth surfaced only via an edge-case sub-test, and any FE gating (no FE HTTP status). Hence the Coverage block reports **"Exercised"**, not "Verified", for feature PASSes.
````

- [ ] **Step 2: Add the per-consumer note at Step 3f.** After the Progress paragraph (`loop.md:710`), insert:

```markdown
**`auth-unverified` across consumers:** it is never `"fail"`, so it is excluded from the fix-set (Step 3a, `current == "fail"`), is never a regression (Step 3f / 4.2, which key on `baseline == "pass" ∧ current == "fail"`), and is inert for the progress check (a scenario the loop is not fixing). A re-run scenario that becomes `auth-unverified` updates `current` normally (Step 3g merge).
```

- [ ] **Step 3: Verify.**
```bash
grep -nE 'Auth-Unverified Reclassification|401, 403|never.*credited as PASS|across consumers' plugins/qa/commands/loop.md
```
Expected: reclassification rule + the consumer note.

- [ ] **Step 4: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): reclassify auth-gated feature scenarios as auth-unverified"
```

---

### Task 5: §2a Coverage block (Loop Summary + report-format skill)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 5.2 Loop Summary (`~:888-915`)
- Modify: `plugins/qa/skills/report-format/SKILL.md` — Summary section (`~:24-28`)

Implements spec §2a.

- [ ] **Step 1: Add the Coverage block to the Loop Summary.** In Step 5.2, after the `Final Status` block, insert:

````markdown
**Coverage** (computed from `scenario_kind` + verdicts + `scenario_reason`):

```
## Coverage
- Exercised: <feature-PASS> feature · <sanity-PASS> sanity · <negative-PASS> enforcement
- Not verified: auth-unverified <N> · mutation-guard SKIP <M> · tool-unavailable <K>
- Confidence: <high | low — reason>
```

"Exercised" (not "Verified") because a feature PASS means "reached and returned non-4xx" — an upper bound (§1b residual).
````

- [ ] **Step 2: Add a parallel slot to the report-format Summary.** In `report-format/SKILL.md`, in the `## Summary` section, document an optional sibling `## Coverage` block (`##`-level, **no** `### [SEVERITY]` headings, **no** `---`, so the `/fix-report` block parser skips it — same rule as Loop History). Show the same three-line shape.

- [ ] **Step 3: Verify.**
```bash
grep -nE '## Coverage|Exercised:|Not verified:|Confidence:' plugins/qa/commands/loop.md
grep -nE 'Coverage' plugins/qa/skills/report-format/SKILL.md
```
Expected: Coverage block present in both; parser-safe (no `### [SEVERITY]` inside it).

- [ ] **Step 4: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md plugins/qa/skills/report-format/SKILL.md && git commit -m "feat(qa:loop): add Coverage block (exercised vs not-verified) to summary and report"
```

---

### Task 6: §2b shallow WARNING + precedence + §2c low-confidence green + §2d subsumption

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 2.4 (`~:456-483`)

Implements spec §2b/§2c/§2d.

- [ ] **Step 1: Define the shallow signal + WARNING.** In Step 2.4, after the zero-failure bullet (`loop.md:464`), insert:

````markdown
**Shallow-coverage check.** Let `meaningful = count(verdict == PASS AND kind == feature)`. Coverage is **shallow** when `meaningful == 0` AND ≥1 `feature` scenario did not PASS (it was `auth-unverified`/`skip`/`fail`). On shallow coverage, emit:

> Warning: shallow coverage — no feature behavior was exercised (N feature scenarios were auth-unverified/skipped/unreachable). This green reflects infrastructure and enforcement checks only.

**Precedence:** this WARNING does NOT fire on the existing mutation-guard-only all-SKIP graceful path (the "backend-write-only — rely on the unit/integration suite" branch below); that branch keeps its own message. The WARNING also does not fire when the plan contains **zero** feature-kind scenarios (a deliberately sanity-only plan — nothing claimed-but-unverified).
````

- [ ] **Step 2: Add the §2c low-confidence green.** Edit the zero-failure "All passing, nothing to fix" bullet to add: when the message would print AND coverage is shallow AND `auto_generated == true`, replace it (still exit success) with:

```
> All assertions passed, but coverage is shallow — no feature behavior was exercised (see Coverage). Low-confidence green: the plan was auto-generated and may not reflect runtime auth/setup.
```

- [ ] **Step 3: Add the §2d subsumption note.** Append: `One authoritative coverage verdict per run: on the auto-generated zero-failure path the §2c line subsumes the §2b WARNING (print one, not both); otherwise the §2b WARNING is the verdict. The Coverage block restates counts and never re-decides.`

- [ ] **Step 4: Verify.**
```bash
grep -nE 'Shallow-coverage check|meaningful = count|does NOT fire on the existing mutation-guard-only|Low-confidence green|subsumes the' plugins/qa/commands/loop.md
```
Expected: all five anchors present.

- [ ] **Step 5: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): shallow-coverage WARNING + low-confidence green on the zero-failure exit"
```

---

### Task 7: §3 unlock-hints surface (mechanism #1)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 5.2 Loop Summary; fold the standalone mutation-guard surfacing at `~:415-417`

Implements spec §3.

- [ ] **Step 1: Author the unlock-hints list.** In Step 5.2, after the Coverage block, insert:

````markdown
**Next steps to widen coverage** (render only rows whose count > 0, from `scenario_reason`):

- `mutation-guard` (N): re-run with `--allow-mutations` (test DB must be disposable).
- `auth-unverified` (N): the app is auth-gated; `/qa:loop` verifies enforcement only. Exercise authenticated behavior via the project's integration/e2e suite. (No `--auth-token` intake in this version.)
- `tool-unavailable` (N): install/enable the missing tool (Playwright / curl / DB client).
- `dispatch-exhausted`: raise `--max-dispatches`.

Counts come from the normalized `scenario_reason`: `mutation-guard` is exact (orchestrator-assigned); the rest are heuristic prose-matches and may under-count — acceptable for an advisory hint.
````

- [ ] **Step 2: Fold the old surfacing.** Edit the standalone mutation-guard line at `loop.md:415-417` to a one-line pointer that it is now rendered in the Step 5.2 "Next steps" table (single source of truth).

- [ ] **Step 3: Verify.**
```bash
grep -nE 'Next steps to widen coverage|--allow-mutations|auth-unverified.*enforcement only|dispatch-exhausted' plugins/qa/commands/loop.md
```
Expected: the unified hint table.

- [ ] **Step 4: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): unified unlock-hints surface keyed by SKIP/outcome reason"
```

---

### Task 8: §4 transport reachability suggestion (mechanism #3)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 5.2 Loop Summary

Implements spec §4 (reactive, post-baseline).

- [ ] **Step 1: Author the reachability + mutation suggestions.** In Step 5.2, after the unlock-hints, insert:

````markdown
**Reactive suggestions** (each with its caveat, shown only when triggered):

- **Reachability:** if **every BE scenario** is `FAIL` with a `transport` reason (Details matched `/connection refused|could not connect|timeout/i`) and a `null` `observed_status` (FE SKIPs ignored), print: "no BE scenario returned an HTTP status at `<host:port>` — the dev stack may be down (or every endpoint is 5xx'ing)." Assemble `<host:port>` from the Step 0.4-sanitized host plus the parsed port — **never** from the raw error string.
- **Mutation:** if every BE scenario was `mutation-guard` SKIP, print the `--allow-mutations` hint (disposable DB).

No proactive guard-widening nudges: flags that widen a guard appear only in the reactive unlock-hints after the guard actually blocked something.
````

- [ ] **Step 2: Verify.**
```bash
grep -nE 'Reactive suggestions|every BE scenario.*transport|host:port.*sanitized|No proactive guard-widening' plugins/qa/commands/loop.md
```
Expected: the reachability trigger + redaction + no-nudge rule.

- [ ] **Step 3: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): reactive reachability + mutation suggestions (transport signal)"
```

---

### Task 9: §5b auto-plan provisional generation (Step 0.2.1 decide, Step 1.3 persist)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 0.2.1 generation (`~:130-177`); Step 1.3 sidecar init (`~:295-317`)

Implements spec §5b.

- [ ] **Step 1: Add the generation bias + provisional decision at Step 0.2.1.** Insert into the generation step:

````markdown
**Assertion fidelity (auto-plan only).** Bias generated assertions toward observable invariants the generator can be confident about (non-5xx, no stack-trace/secret leak in the body, auth-gate present) over guessed exact path+status. Where an exact value must be asserted that the generator could not observe, mark that scenario **provisional** and generate it as its **own** scenario (never co-located with a robust invariant, so Step 3a's scenario-level exclusion can't drop a real finding). The provisional split happens **before** BE-NN/FE-NN numbers are assigned; number once over the final set; collect the provisional IDs. (Also note the provisional IDs in the surfacing output so they survive to Step 1.3 across a context loss.)
````

- [ ] **Step 2: Persist at Step 1.3.** In the Step 1.3 "When writing the sidecar" paragraph (`loop.md:317`), add: `Persist provisional_scenarios (the IDs decided in Step 0.2.1; empty array if not auto-generated). On REUSE/ADOPT, preserve the existing value (like auto_generated). Do NOT write it at Step 0.2.1 — the sidecar does not exist yet.`

- [ ] **Step 3: Verify.**
```bash
grep -nE 'Assertion fidelity|observable invariants|its \*\*own\*\* scenario|before \*\*BE-NN' plugins/qa/commands/loop.md
grep -nE 'Persist provisional_scenarios|Do NOT write it at Step 0.2.1' plugins/qa/commands/loop.md
```
Expected: generation bias + own-scenario + numbering at 0.2.1; persist rule at 1.3.

- [ ] **Step 4: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): bias auto-plan assertions to invariants; mark guessed-exact scenarios provisional"
```

---

### Task 10: §5a fix-set plan-suspect branch (Step 3a)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Step 3a (`~:550-563`)

Implements spec §5a.

- [ ] **Step 1: Author the plan-suspect branch.** In Step 3a, after building `fix_candidates`, insert:

````markdown
**Provisional plan-suspect guard (T3).** For a failing scenario whose ID is in `provisional_scenarios`:
- `approve`/`step`: keep it in the HITL gate but flag it `⚠ auto-generated assertion — verify before fixing`.
- `auto`: **exclude** it from `fix_candidates` and log `auto-generated assertion suspected; not auto-fixing — verify the plan.` (Step 3c only iterates `fix_candidates`, so the "fix source, don't touch the plan" injection is never reached for it.)

A failure on a **non-provisional** assertion uses the normal fix path (real 5xx/leak bugs are still fixed). Absent `provisional_scenarios` (every user-provided plan) ⇒ no scenario is plan-suspect → normal fix path for all.
````

- [ ] **Step 2: Verify.**
```bash
grep -nE 'Provisional plan-suspect guard|verify before fixing|exclude.*fix_candidates|Absent .provisional_scenarios' plugins/qa/commands/loop.md
```
Expected: the branch with approve/step + auto handling + absent-default.

- [ ] **Step 3: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && git commit -m "feat(qa:loop): treat failing auto-generated provisional assertions as plan-suspect, not code-suspect"
```

---

### Task 11: Error-table rows, docs sync, and 2.3.0 version parity (final)

**Files:**
- Modify: `plugins/qa/commands/loop.md` — Error Handling table (`## Error Handling`, `~:969-995`)
- Modify: `docs/plugins/qa.md` — body + `> [!IMPORTANT]` note + `**Version:**`
- Modify: `plugins/qa/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md`

Implements spec §5 change-sites + versioning.

- [ ] **Step 1: Add error-handling rows.** In the `## Error Handling` table, add rows for: `Feature scenario auth-gated (no token)` → `Reclassified auth-unverified; counted, surfaced, never PASS; unlock-hint shown`; and `Shallow coverage (no feature PASS)` → `WARNING + low-confidence green on auto-generated; still exit success`.

- [ ] **Step 2: Document in `docs/plugins/qa.md`.** Add a "Coverage honesty" subsection (Coverage block, shallow WARNING, low-confidence green, `auth-unverified`, unlock-hints, reactive suggestions, T3 provisional). Note the deliberate `/qa:run` split.

- [ ] **Step 3: Extend the `> [!IMPORTANT]` behavior-change note.** Widen its heading scope **beyond `--mode auto`**, and add: (a) the new shallow-coverage WARNING can appear on approve/step and **user-authored** plans (a visible change to a previously-silent green); (b) `--mode auto --auto-plan` may now produce an **empty fix-set** (auth-unverified + provisional exclusions) and exit green-with-caveat *by design*.

- [ ] **Step 4: Bump version to 2.3.0** in all four parity sites: `plugins/qa/.claude-plugin/plugin.json` (`.version`), `.claude-plugin/marketplace.json` (qa entry `.version`), `README.md` (qa Available-Plugins row), `docs/plugins/qa.md` (`**Version:**`). If you change the README/marketplace one-liner, change both in lockstep (CI checks version only).

- [ ] **Step 5: Verify parity + structure.**
```bash
python3 scripts/check_plugin_versions.py        # expect: qa 2.3.0 OK across all sites
grep -nE 'auth-unverified|Shallow coverage' plugins/qa/commands/loop.md | grep -iE 'error|table' || grep -n 'auth-unverified' plugins/qa/commands/loop.md
grep -n '2.3.0' plugins/qa/.claude-plugin/plugin.json docs/plugins/qa.md README.md .claude-plugin/marketplace.json
```
Expected: parity script all-OK; `2.3.0` in all four sites.

- [ ] **Step 6: Commit.**
```bash
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md docs/plugins/qa.md plugins/qa/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md && git commit -m "release(qa): 2.3.0 — coverage-honesty, unlock-hints, and fix-auto provisional guard"
```

---

## Self-Review

**1. Spec coverage:**
- §1.0 ingest → Task 2 ✓ · §1a kind → Task 3 ✓ · §1b auth-unverified + consumer audit → Task 4 ✓
- §2a Coverage block → Task 5 ✓ · §2b/§2c/§2d → Task 6 ✓
- §3 unlock-hints → Task 7 ✓ · §4 reachability → Task 8 ✓
- §5b generation → Task 9 ✓ · §5a fix-set guard → Task 10 ✓
- §6 schema → Task 1 ✓ · §5 change-sites (error table, docs, parity) + versioning → Task 11 ✓
- §6 guardrails (redaction/subordination/reactive/placement) are woven into Tasks 6/8 (redaction in 8, subordination in 6, reactive in 8). ✓
- No gaps.

**2. Placeholder scan:** Each task carries the actual markdown to author + a concrete `grep`/`jq`/parity verification with expected output. No "TBD"/"handle edge cases"/"similar to Task N".

**3. Name consistency:** `scenario_kind`/`scenario_reason`/`provisional_scenarios`/`auth-unverified`/`transport` are defined in Task 1/2 and used identically in Tasks 3–11. The `## Coverage` block shape (`Exercised:`/`Not verified:`/`Confidence:`) is identical in Tasks 5 and referenced in 6/7. Reason buckets match between Task 2 (definition) and Tasks 7/8 (consumers).

**Ordering note for the executor:** Do Tasks 1→2 first (schema then ingest); 3–8 depend on them; 9–10 (T3) and 11 (docs/version) last. Within `loop.md`, Tasks 2–4 insert sequential `Step 2.1.5/2.1.6/2.1.7` subsections — keep that numbering.

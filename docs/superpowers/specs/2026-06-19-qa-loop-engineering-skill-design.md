# `qa:loop-engineering` Doctrine Skill — Design

**Date:** 2026-06-19
**Status:** MoA-reviewed (4 rounds, sequential-thinking + mixture-of-agents) — CONVERGED, ready for implementation
**Target:** qa plugin 2.3.0 → **2.4.0** (MINOR — new skill)
**Branch:** `feat/qa-loop-engineering` (off master @ 2.3.0)

---

## Goal

Ship an **invocable doctrine skill** that captures, in one place, the discipline for authoring robust closed agent loops in this marketplace — the minimum-bar checklist, the ground-truth-oracle taxonomy, and the anti-patterns — anchored to `/qa:loop` as the **reference implementation** (it conforms to the whole MUST bar; the doctrine prescribes one further cost rider for model-heavy loops that qa:loop has yet to adopt — see Residual risks).

## Motivation

A mixture-of-agents analysis (loop-engineering concept · repo map · strategy · adversary) plus sequential-thinking synthesis established two facts, both verified against files:

1. **The repo already practices loop engineering.** `/qa:loop` (`plugins/qa/commands/loop.md`) is a fully engineered closed loop: separated verifier authority, a **triple-gate budget** (iterations ∧ dispatches ∧ time) plus progress/oscillation stops, fail-closed safety guards, disclose-don't-gate coverage honesty, a provenance guard.
2. **The repo already paid the tuition for its hardest failure.** The incident that drove qa 2.3.0 — a run that reported SUCCESS while verifying ~nothing of an auth-gated feature (false convergence, "green but verified nothing") — is the canonical loop-engineering failure mode.

So the work is **not** "introduce loop engineering" — it is "turn the hard-won, currently-implicit discipline (scattered across `loop.md` prose and residual notes) into an explicit, reusable, *citable* asset." Packaging the discipline **as a skill** is on-brand with the developer plugins' coding-standards / TDD skills *as an artifact type* — an authoring-guidance skill. (Caveat: those skills are loaded **within their own plugin**; this doctrine is read at *authoring/review* time by a human or agent, not auto-loaded across plugins — see Packaging.)

## Packaging decision (and why)

**Decision:** a single invocable skill, **bundled inside the `qa` plugin** at `plugins/qa/skills/loop-engineering/SKILL.md`. Not docs-only; not a standalone plugin (yet).

**Audience vs. home (reconciled):** the doctrine's **audience is cross-cutting** — every loop author in the marketplace, including a future code-review or web-auditor loop. Its **home is `qa` for now** — a pragmatic housing choice, not a claim that qa "owns" the concept. qa is where the only loop and the reference implementation live, so it is the least-friction home until a second consumer or an active command justifies promotion.

**Rationale — driven by the user's install-dependency concern, verified in-repo:**

- Claude Code plugins here have **no dependency mechanism** (no `dependencies`/`requires`/`peer` field anywhere in `plugins/*/.claude-plugin/plugin.json`). A plugin that must be installed for another to work is unsupported and fragile.
- The marketplace already tolerates one **undeclared** cross-plugin runtime dependency: `/qa:loop` dispatches the `code-review:fix-auto` agent (`loop.md:679`). We should not multiply must-install couplings.
- **Tier-0 doctrine has no runtime consumers** — nothing calls it during execution; it is read at authoring/review time. So wherever it lives it creates **no install dependency**. A standalone "doctrine plugin" would therefore be pure overhead (own version, marketplace entry, badge, parity) for a unit nobody is required to install and few would.
- **YAGNI / promote-later, with its true cost stated:** if loop engineering spreads (a code-review loop, a shared harness) or the skill gains an *active* command, promote it to its own plugin then. **Promotion renames the invocation handle** `qa:loop-engineering` → `loop-engineering:loop-engineering` — a breaking change for any consumer of the handle. Therefore keep cross-references to the handle minimal until promotion (see Integration).

## Skill specification

**Location:** `plugins/qa/skills/loop-engineering/SKILL.md`
**Namespaced name:** `qa:loop-engineering`
**Structure:** opens with an `#` H1 title (`# Loop Engineering`) and renders its sections as `##` headings — matching every existing qa skill (`#` title + `##` sections; no numbered headings). Frontmatter is `name` + `description` only (no `allowed-tools` — the skill needs no tools), like `report-format`.

**Frontmatter:**

```yaml
---
name: loop-engineering
description: Use when designing, authoring, or reviewing a closed agent loop (test→fix→retest, audit→fix→re-audit, generate→verify→correct) in this marketplace — the minimum-bar checklist, the ground-truth oracle taxonomy, and the anti-patterns, anchored to /qa:loop as the reference implementation.
---
```

**Body — six `##` sections (approved skeleton; the `### 1.`–`### 6.` numbering below is editorial scaffolding for this spec — render each as a `##` non-numbered heading):**

### 1. What a loop is / when to invoke
A loop = *act → verify → correct → repeat*, bounded by budget. The **ground-truth oracle** (the signal that says "correct") is the load-bearing part; everything else is plumbing. Invoke this skill when authoring or reviewing any closed loop before it ships. (The bar below separates **Universal** items, which apply to every loop, from **Conditional** items, which apply only to loops that persist state, mutate the workspace, or auto-correct.)

### 2. The minimum bar (checklist) — 8 Universal + 3 Conditional
**Universal** items apply to every closed loop. **Conditional** items apply when the loop **persists state, mutates the workspace, and/or auto-corrects toward a target**. A stateless, read-only, non-correcting loop may satisfy the Conditional items as **N/A with a one-line justification that affirms it neither persists loop-critical state, mutates the workspace, nor auto-corrects** — never silently. Each item: rule, one-line *why*, qa:loop anchor. (§2 is the single source of truth for the bar's content and count; §6 is a rendering of it. Each Conditional item is gated **independently** by its own trigger — a stateful-but-read-only loop satisfies item 10 and marks 9 and 11 N/A.)

**Universal (always MUST):**
1. **Named oracle + explicit "what it canNOT verify."** State the ground-truth signal *and* its blind spots. *Why:* an unstated oracle is an unfalsifiable "it passed." → qa:loop Coverage block reports **`"Exercised"`, not `"Verified"`** for feature PASSes.
2. **Verifier authority separated from the actor/fixer; gate and log on the raw signal, not narration.** Only a *fresh, independent* re-run decides pass/fail; the fixer's self-verdict is advisory; never hand the verifier the exact target it grades; gate/log on the raw oracle output (exit code, HTTP status, row count, test output), never the actor's "I'm done." *Why:* a fixer grading its own fix — or a loop logging narration — is self-report, not verification. → qa:loop glossary *Verifier authority*; the Error-Handling rule *"fix-auto says 'Fixed' but re-run still fails → Re-run is authoritative"*; Step 2.1.5 structured ingest of `observed_status`.
3. **Disclose-don't-gate coverage honesty.** Shallow/partial coverage → WARNING (+ low-confidence-green message), never green→red; the loop can say "I converged but verified little." → qa:loop shallow-coverage WARNING + low-confidence green.
4. **Human gate by default; headless only on explicit opt-in + TTY fail-closed.** *Why:* autonomous correctness is unreachable when the verifier is stochastic. → qa:loop `--mode approve` default; approve/step abort without a TTY.
5. **Reused fail-closed safety guards, not reinvented.** Environment/host guard, mutation/write guard (moot for a read-only loop), ambiguous-input → ask/abort. → qa:loop *Safety Guards (Apply in All Modes)*; `plugins/commit/scripts/block-git-push.sh` (deny > ask > allow) as the deterministic exemplar.
6. **Hard budgets.** Bound the loop on **iterations ∧ dispatches ∧ time** (qa:loop's triple-gate). *Why:* unbounded loops blow cost; weak budgets ship the first (false) green. → qa:loop triple-gate (`--max-iterations` / `--max-dispatches` / `--time-budget`). **Rider (model-heavy loops — recommended, not a universal MUST):** also bound **cost/tokens** — see §4 anti-patterns. qa:loop has no cost ceiling despite being model-heavy (repeated `fix-auto`/tester dispatches); adopting one is a recommendation it has yet to take up (Residual risks), so this rider prescribes beyond the reference *without* making the reference non-conforming to the MUST bar.
7. **Progress & oscillation stops, reported as distinct from success.** Stop on regression and on no-progress; surface "stopped / budget-exhausted" as a non-success outcome. *Why:* a loop can oscillate or stall well under budget; "stopped" must not read as "passed." → qa:loop Step 3f regression-stop + no-progress stop; glossary *Oscillation*.
8. **Documented residual-risk list.** If the author cannot enumerate what the loop fails to catch, it is not ready. → qa:loop residual notes (auth-unverified, *Verifier-gaming residual (v1)*, 2xx-shaped gating).

**Conditional (MUST when the loop persists state, mutates the workspace, and/or auto-corrects):**
9. **Provenance / plan-suspect branch.** *(Applies to auto-correcting loops.)* Auto-generated or guessed assertions are NOT auto-fixed against correct source. *Why:* the failure may be the assertion, not the code; a read-only loop has nothing to auto-fix and satisfies this trivially. → qa:loop *Provisional plan-suspect guard (T3)* (excludes such scenarios from `fix_candidates`).
10. **Durable sidecar state with input hash-pinning, and run-level idempotency.** *(Applies to stateful loops.)* Loop-critical state lives on disk, not in the conversation; the input is hashed to detect mid-run tampering; **re-running on identical input reuses/adopts prior state by hash and never duplicates issues or re-applies fixes** (IDs continue at max+1). *Why:* the orchestrator's own memory is lossy across many tool calls, and a re-run must not double-apply. → qa:loop sidecar + plan hash; Step 1 "Resolve Report + Sidecar (Idempotency)".
11. **Scoped, recoverable writes.** *(Applies to mutating loops.)* Touch only what you changed; never destroy the user's pre-existing work; leave changes uncommitted for human control. → qa:loop `fix_touched_files = post − pre_loop_dirty`; scoped `git restore`.

### 3. Oracle taxonomy
- **Strong (tool/wire):** tests, type checker, build, exit codes, HTTP status, row counts, browser/E2E. Deterministic, fast, ungameable-from-inside.
- **Soft (LLM-judged):** another agent's opinion. Slow, non-deterministic.
- **Rules:** prefer strong; a soft oracle MUST self-label its verdict *advisory* (e.g. a prescribed "Re-reviewed (advisory)" status; qa:loop's `"Exercised"`, not `"Verified"`); the actor must never be the *author* of the oracle nor able to see-and-game it; re-verification must be independent of the corrector.

### 4. Anti-patterns (do NOT)
- **Self-graded auto-fix loop** — e.g. an autonomous code-review fix loop where "Fixed" is the fixer's own verdict with no independent re-dispatch of the originating auditor. *(Prospective: this loop is **not yet built in this repo** — see OUT-of-scope. The anti-pattern is a design constraint derived by analogy from qa:loop's verifier-authority separation, not from a shipped code-review loop; revisit when that loop is actually designed.)*
- **`--auto` / exit-code-0 read as "verified"** in CI — the disclosure layer is for a human reader, not a gate.
- **Auto-fixing a guessed/auto-generated assertion** against correct source.
- **Soft-only budget on expensive (model-heavy) loops** with no cost ceiling.
- **Loop-critical state kept in conversation context.**
- **A loop whose verifier structurally cannot reach the thing under test** (auth-gated, worker-resident, async) reported as PASS instead of disclosed.
- **Tightening the budget to force convergence** — ships the first green, which may be the false one.

### 5. Reference implementation — `/qa:loop`
qa:loop conforms to the whole MUST bar and is the worked example for every item (the cost rider is a recommendation it has yet to adopt — Residual risks). Reference its **named** anchors (stable across edits), each with what to look at it for:
- *Verifier authority* (glossary) — fresh re-run gates; fixer verdict advisory.
- *Verifier-gaming residual (v1)* — the honest "a capable fixer can still game a visible check" caveat.
- *Provisional plan-suspect guard (T3)* — auto-generated assertions excluded from auto-fix.
- *Safety Guards (Apply in All Modes)* — Environment guard + Mutation guard, fail-closed.
- *Status write-back* (glossary) — written once, only from the authoritative final run.
- The `## Coverage` block + the auth-unverified outcome — "Exercised vs Not verified" disclosure.
- `plugins/commit/scripts/block-git-push.sh` — the deterministic, fail-closed guard exemplar (deny > ask > allow).

### 6. Copy-paste checklist (optional, kept)
A terse tick-box **rendering of §2** that MUST stay 1:1 with §2's items: **one `- [ ]` line per bar item, rule-clause only** (drop the *why* and the anchor), Universal block then Conditional block — so a reviewer can paste it into a loop spec's review. **Riders (e.g. item 6's cost ceiling) render as an indented sub-bullet under their parent item and do NOT count toward the 8+3 item total**, so the checklist surfaces them without inflating the count. §2 remains the single source of truth; this is its checklist view.

## Files

- **Create:** `plugins/qa/skills/loop-engineering/SKILL.md`
- **Modify (version 2.3.0 → 2.4.0):** `plugins/qa/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (qa `version` field only), `README.md` (qa table-row version), `docs/plugins/qa.md` (`**Version:**` **and** create a new `## Skills` section)
- **Unchanged:** plugin-count badge (no new plugin); qa marketplace `description` (skill addition doesn't change the one-liner)

## Integration / cross-links

- `docs/plugins/qa.md` **has no `## Skills` section today** (verified — 0 skill mentions; existing skills are undocumented there). **Create** a `## Skills` section, modelled on `docs/plugins/code-review.md`'s `## Skills`, and list `loop-engineering` with a one-line purpose. *(Optional, may be deferred as separate cleanup: backfill the four existing qa skills — report-format, test-plan-format, fe-testing, be-testing — into the same section.)*
- **Recommended (not optional):** a prose back-reference from `loop.md` — "the doctrine this implements: `qa:loop-engineering`". This is the **single discovery hook** that creates pull toward the doctrine, so it is recommended, not nice-to-have.
- **Invariant:** the `loop.md` back-reference MUST stay a **prose mention**, never a `Skill(skill: "qa:loop-engineering")` auto-load, for as long as the doctrine lives in `qa`. Auto-loading would (a) create a runtime consumer and (b) couple the promote-later migration (reviving exactly the undeclared cross-plugin dependency this design avoids). If auto-loading is ever wanted, that *is* the trigger to promote the skill to its own plugin first.

## Versioning & conventions

MINOR bump (new skill = new feature, per `CLAUDE.local.md`). Enforce 4-way parity via `scripts/check_plugin_versions.py` (plugin.json, marketplace.json, README row, `docs/plugins/qa.md` `**Version:**`). Docs-sync per `CLAUDE.local.md`. Commits via `env AV_COMMIT_SKILL=1 git commit`, **no Co-Authored-By trailer**; the **PR body** gets the "🤖 Generated with Claude Code" footer (commits do not). Internal planning docs (this spec + the plan) removed before the 2.4.0 PR, per the established cycle (e.g. `54d40c3`).

## Verification (prompt-spec — no runtime)

- `python3 scripts/check_plugin_versions.py` → parity OK, qa 2.4.0 across all four sources. *(Note: the parity script is blind to skills — it does NOT cover the anchor/invariant checks below.)*
- Structural: `SKILL.md` has valid frontmatter (`name`, `description`), an `#` H1 + `##` sections, all six sections, and the §6 checklist with one line per §2 bar item (8 Universal + 3 Conditional; riders render as uncounted sub-bullets).
- **Anchor integrity:** grep `loop.md` for each **named** anchor cited in §5 (`Verifier authority`, `Verifier-gaming residual (v1)`, `Provisional plan-suspect guard (T3)`, `Safety Guards (Apply in All Modes)`, `Status write-back`, `## Coverage`) — confirm each still exists. This proves the strings exist, **not** that the surrounding section still *means* what the doctrine claims (see Residual risks).
- **Back-reference invariant:** `grep -nE 'Skill\(\s*skill:\s*"qa:loop-engineering"' plugins/qa/commands/loop.md` → MUST be empty (the back-reference stays prose, never an auto-load).
- Docs-sync: qa.md `## Skills` section created and lists the new skill; README/marketplace/plugin.json versions agree.
- `bash plugins/commit/tests/test-block-git-push.sh` → unaffected (51/51) — sanity that no hook regressed.

## Scope (YAGNI) — explicitly OUT

- **No shared `loop-harness` extraction** (Tier 1.5) — runtime code with a single consumer; defer until a second loop needs it.
- **No active audit command** (`/loop-engineering:audit`) — would justify a standalone plugin; out of Tier 0. (A committed anchor-grep *test* enforcing §Verification is a possible future enhancement in the same spirit — also out of Tier 0, as it edges toward the enforcement this skill deliberately leaves advisory.)
- **No code-review review→fix→re-review loop** (Tier 1) — separate, larger design.
- Doctrine only: this skill changes **no runtime behavior** of qa:loop or any plugin.

## Residual risks (honest)

- **qa:loop has not adopted the cost rider.** qa:loop **conforms to the whole MUST bar** — all 8 Universal items and all 3 Conditional items (which apply, since it is stateful, mutating, and auto-correcting). It budgets iterations/dispatches/time but **not** cost/tokens, despite being model-heavy (repeated `fix-auto`/tester dispatches) — so it has yet to adopt the cost *rider* the doctrine recommends for model-heavy loops (item 6). The rider is a recommendation, not a MUST, so this is the doctrine **identifying an improvement to its own reference**, not a conformance gap. (Documented *here*, not in loop.md, which has no cost residual.)
- **Anchor-by-name reduces, does not eliminate, doc-rot.** It removes brittle line numbers, but a renamed section silently breaks the doctrine; the §Verification grep proves a named anchor still *exists*, not that it still *means* the same thing. Mitigation is discipline + the grep check, not a guarantee. (Quoted phrases — as opposed to named sections — are the most rot-prone; rounds 1–2 already corrected drifted phrasings, e.g. the Coverage wording, and de-line-numbered citations.)
- **Advisory, not enforced.** Nothing mechanically forces a future loop to meet the bar; the skill is guidance + a checklist a reviewer can paste, not a gate. Realistic leverage = *discoverable and citable*, not enforced — realized only when an author/reviewer invokes it (hence the recommended back-reference as the one discovery hook).
- **Semantic home:** living in `qa` (a testing plugin) is a slight mismatch; accepted under promote-later, whose true cost (a breaking handle rename) is stated.
- **Forward dependency on an unbuilt loop:** the marquee anti-pattern (self-graded code-review fix loop) describes a loop not yet designed; it is anticipated, not battle-tested, and is tagged prospective.

## Rejected alternatives

- **Standalone `loop-engineering` plugin (now):** over-engineering for one markdown skill with no runtime consumers; adds a must-install unit + full parity/badge overhead for low uptake. Revisit only with an active command or a second consumer.
- **Docs-only (`docs/`):** lightest, but not invocable as a skill and weakest as a "marketplace artifact."
- **Fold into the 2.3.0 release:** mixes two unrelated features in one branch/PR whose spec/commits are entirely about coverage-honesty.

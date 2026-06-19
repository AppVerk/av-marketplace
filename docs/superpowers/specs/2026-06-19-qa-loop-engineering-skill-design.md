# `qa:loop-engineering` Doctrine Skill — Design

**Date:** 2026-06-19
**Status:** Approved skeleton → spec for review
**Target:** qa plugin 2.3.0 → **2.4.0** (MINOR — new skill)
**Branch:** `feat/qa-loop-engineering` (off master @ 2.3.0)

---

## Goal

Ship an **invocable doctrine skill** that captures, in one place, the discipline for authoring robust closed agent loops in this marketplace — the minimum-bar checklist, the ground-truth-oracle taxonomy, and the anti-patterns — anchored to `/qa:loop` as the conforming reference implementation.

## Motivation

A mixture-of-agents analysis (loop-engineering concept · repo map · strategy · adversary) plus sequential-thinking synthesis established two facts, both verified against files:

1. **The repo already practices loop engineering.** `/qa:loop` (`plugins/qa/commands/loop.md`) is a fully engineered closed loop: separated verifier authority, quad-gate budget, fail-closed safety guards, disclose-don't-gate coverage honesty, provenance guard.
2. **The repo already paid the tuition for its hardest failure.** The incident that drove qa 2.3.0 — a run that reported SUCCESS while verifying ~nothing of an auth-gated feature (false convergence, "green but verified nothing") — is the canonical loop-engineering failure mode.

So the work is **not** "introduce loop engineering" — it is "turn the hard-won, currently-implicit discipline (scattered across `loop.md` prose and residual notes) into an explicit, reusable, *shippable* asset." Packaging the discipline **as a skill** is itself the way to "leverage the concept in the marketplace," on-brand with the developer plugins' coding-standards / TDD skills.

## Packaging decision (and why)

**Decision:** a single invocable skill, **bundled inside the `qa` plugin** at `plugins/qa/skills/loop-engineering/SKILL.md`. Not docs-only; not a standalone plugin (yet).

**Rationale — driven by the user's install-dependency concern, verified in-repo:**

- Claude Code plugins here have **no dependency mechanism** (no `dependencies`/`requires`/`peer` field anywhere in `plugins/*/.claude-plugin/plugin.json`). A plugin that must be installed for another to work is unsupported and fragile.
- The marketplace already tolerates one **undeclared** cross-plugin runtime dependency: `/qa:loop` dispatches `code-review:fix-auto`. We should not multiply must-install couplings.
- **Tier-0 doctrine has no runtime consumers** — nothing calls it during execution; it is read at authoring/review time. So wherever it lives it creates **no install dependency**. A standalone "doctrine plugin" would therefore be pure overhead (own version, marketplace entry, badge, parity) for a unit nobody is required to install and few would.
- **YAGNI / promote-later:** qa is the home of the only loop and the reference implementation the skill documents — a defensible "qa owns the loop pattern in this marketplace" framing. If loop engineering later spreads (a code-review loop, a shared harness) or the skill gains an *active* command, **promote** it to its own plugin then.

## Skill specification

**Location:** `plugins/qa/skills/loop-engineering/SKILL.md`
**Namespaced name:** `qa:loop-engineering`

**Frontmatter:**

```yaml
---
name: loop-engineering
description: Use when designing, authoring, or reviewing a closed agent loop (test→fix→retest, audit→fix→re-audit, generate→verify→correct) in this marketplace — the minimum-bar checklist, the ground-truth oracle taxonomy, and the anti-patterns, anchored to /qa:loop as the reference implementation.
---
```

**Body — six sections (approved skeleton):**

### 1. What a loop is / when to invoke
A loop = *act → verify → correct → repeat*, bounded by budget. The **ground-truth oracle** (the signal that says "correct") is the load-bearing part; everything else is plumbing. Invoke this skill when authoring or reviewing any closed loop before it ships.

### 2. The minimum bar (checklist)
Every loop in this repo MUST meet all of the following before shipping. Each item: the rule, a one-line *why*, and the qa:loop anchor that exemplifies it.

1. **Named oracle + explicit "what it canNOT verify."** A loop must state its ground-truth signal *and* its blind spots ("Exercised ≠ Verified"). *Why:* an unstated oracle is an unfalsifiable "it passed." → qa:loop Coverage block ("Exercised, not Verified").
2. **Verifier authority separated from the actor/fixer.** Only a *fresh, independent* re-run gates pass/fail; the fixer's self-verdict is advisory; never hand the verifier the exact target it grades. *Why:* a fixer grading its own fix is self-report, not verification. → qa:loop glossary *Verifier authority*; *"fix-auto says Fixed but re-run still fails → Re-run is authoritative."*
3. **Disclose-don't-gate coverage honesty.** Shallow/partial coverage produces a WARNING (and a low-confidence-green message), never a green→red flip; the loop can say "I converged but verified little." *Why:* honesty without breaking working runs. → qa:loop shallow-coverage WARNING + low-confidence green.
4. **Human gate by default; headless only on explicit opt-in + TTY fail-closed.** *Why:* autonomous correctness is not achievable when the verifier is stochastic. → qa:loop `--mode approve` default; approve/step abort without a TTY.
5. **Reused fail-closed safety guards, not reinvented.** Environment/host guard, mutation/write guard, ambiguous-input → ask/abort. *Why:* every new loop re-deriving these will omit one. → qa:loop *Safety Guards (Apply in All Modes)*; `block-git-push.sh` deny>ask>allow as the gold standard.
6. **Hard budgets (iterations ∧ dispatches ∧ time ∧ cost) + oscillation/no-progress stops; "stopped/exhausted" reported as distinct from success.** *Why:* unbounded loops blow cost; weak budgets ship the first (false) green. → qa:loop quad-gate; regression / no-progress stops.
7. **Durable sidecar state with input hash-pinning.** Loop-critical state lives on disk, not in the conversation; the input (plan) is hashed to detect mid-run tampering. *Why:* the orchestrator's own memory is lossy across many tool calls. → qa:loop sidecar + plan hash.
8. **Scoped, recoverable writes.** Touch only what you changed; never destroy the user's pre-existing work; leave changes uncommitted for human control. *Why:* a loop must be safely undoable. → qa:loop `fix_touched_files = post − pre_loop_dirty`; scoped `git restore`.
9. **Provenance / plan-suspect branch.** Auto-generated or guessed assertions are NOT auto-fixed against correct source. *Why:* the failure may be the assertion, not the code. → qa:loop *Provisional plan-suspect guard (T3)*.
10. **Documented residual-risk list.** If the author cannot enumerate what the loop fails to catch, it is not ready. *Why:* the repo's own multi-revision spec history proves this discipline catches phantom mechanisms. → qa:loop residual sections (auth-unverified, verifier-gaming v1, 2xx-shaped gating).

### 3. Oracle taxonomy
- **Strong (tool/wire):** tests, type checker, build, exit codes, HTTP status, row counts, browser/E2E. Deterministic, fast, ungameable-from-inside.
- **Soft (LLM-judged):** another agent's opinion. Slow, non-deterministic.
- **Rules:** prefer strong; a soft oracle MUST self-label its verdict *advisory* ("Re-reviewed (advisory)", "Exercised ≠ Verified"); the actor must never be the *author* of the oracle nor able to see-and-game it; re-verification must be independent of the corrector.

### 4. Anti-patterns (do NOT)
- **Self-graded auto-fix loop** — esp. an autonomous code-review fix loop where "Fixed" is the fixer's own verdict with no independent re-dispatch of the originating auditor.
- **`--auto` / exit-code-0 read as "verified"** in CI — the disclosure layer is for a human reader, not a gate.
- **Auto-fixing a guessed/auto-generated assertion** against correct source.
- **Soft-only budget on expensive (Opus-heavy) loops** with no cost ceiling.
- **Loop-critical state kept in conversation context.**
- **A loop whose verifier structurally cannot reach the thing under test** (auth-gated, worker-resident, async) reported as PASS instead of disclosed.
- **Tightening the budget to force convergence** — ships the first green, which may be the false one.

### 5. Reference implementation — `/qa:loop`
qa:loop is the conforming example. Reference its **named** anchors (stable across edits), not raw line numbers:
- *Verifier authority* (glossary) · *Verifier-gaming residual (v1)* · *Provisional plan-suspect guard (T3)* · *Safety Guards (Apply in All Modes)* (Environment + Mutation guard) · *Status write-back* (glossary) · the Coverage block and the auth-unverified outcome.
- `plugins/commit/scripts/block-git-push.sh` as the deterministic, fail-closed guard exemplar (deny > ask > allow).

### 6. Copy-paste checklist (optional, kept)
A terse, tick-box rendering of §2 for dropping into a loop spec's review — so the bar is checkable, not just readable.

## Files

- **Create:** `plugins/qa/skills/loop-engineering/SKILL.md`
- **Modify (version 2.3.0 → 2.4.0):** `plugins/qa/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (qa `version`), `README.md` (qa table row version), `docs/plugins/qa.md` (`**Version:**` + add the skill to qa's skills list / a short "Loop engineering doctrine" note)
- **Unchanged:** plugin-count badge (no new plugin); qa marketplace `description` (skill addition doesn't change the one-liner)

## Integration / cross-links

- `docs/plugins/qa.md`: list `loop-engineering` among qa's skills with a one-line purpose.
- Optional light back-reference from `loop.md` ("the doctrine this implements: `qa:loop-engineering`") — nice-to-have, not required; decide at implementation.

## Versioning & conventions

MINOR bump (new skill = new feature, per `CLAUDE.local.md`). Enforce 4-way parity via `scripts/check_plugin_versions.py`. Docs-sync per `CLAUDE.local.md`. Commits via `env AV_COMMIT_SKILL=1 git commit`, no Co-Authored-By. Internal planning docs (this spec + the plan) removed before the 2.4.0 PR, per the established cycle.

## Verification (prompt-spec — no runtime)

- `python3 scripts/check_plugin_versions.py` → parity OK, qa 2.4.0 across all four sources.
- Structural: `SKILL.md` has valid frontmatter (`name`, `description`) and all six sections; the checklist has the ten items; the named qa:loop anchors it cites actually exist in `loop.md` (grep each anchor string).
- Docs-sync: qa.md lists the new skill; README/marketplace/plugin.json versions agree.
- `bash plugins/commit/tests/test-block-git-push.sh` → unaffected (51/51) — sanity that no hook regressed.

## Scope (YAGNI) — explicitly OUT

- **No shared `loop-harness` extraction** (Tier 1.5) — that's runtime code with a single consumer; defer until a second loop needs it.
- **No active audit command** (`/loop-engineering:audit`) — would justify a standalone plugin; out of Tier 0.
- **No code-review review→fix→re-review loop** (Tier 1) — separate, larger design.
- Doctrine only: this skill changes **no runtime behavior** of qa:loop or any plugin.

## Residual risks (honest)

- **Doc-rot:** a doctrine skill can drift from the reference implementation. Mitigation: anchor by *named* sections (not line numbers), and treat qa:loop as the single source of truth the skill points at.
- **Advisory, not enforced:** nothing mechanically forces a future loop to meet the bar; the skill is guidance + a checklist, not a gate. (A future audit command could enforce — deliberately out of scope.)
- **Semantic home:** living in `qa` (a testing plugin) is a slight mismatch; accepted under promote-later. The trigger to promote: a second loop consumer or an active command.

## Rejected alternatives

- **Standalone `loop-engineering` plugin (now):** over-engineering for one markdown skill with no runtime consumers; adds a must-install unit + full parity/badge overhead for low uptake. Revisit only with an active command or a second consumer.
- **Docs-only (`docs/`):** lightest, but not invocable as a skill and weakest as a "marketplace artifact."
- **Fold into the 2.3.0 release:** mixes two unrelated features in one branch/PR whose spec/commits are entirely about coverage-honesty.

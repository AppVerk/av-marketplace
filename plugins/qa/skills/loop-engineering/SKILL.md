---
name: loop-engineering
description: Use when designing, authoring, or reviewing a closed agent loop (test→fix→retest, audit→fix→re-audit, generate→verify→correct) in this marketplace — the minimum-bar checklist, the ground-truth oracle taxonomy, and the anti-patterns, anchored to /qa:loop as the reference implementation.
---

# Loop Engineering

## What a loop is, and when to invoke this skill

A closed agent loop is *act → verify → correct → repeat*, bounded by a budget. The **ground-truth oracle** — the signal that decides "correct" — is the load-bearing part; everything else is plumbing. A loop is only as trustworthy as the oracle that gates it.

Invoke this skill when authoring or reviewing any closed loop in this marketplace, before it ships. The minimum bar below separates **Universal** items (every loop) from **Conditional** items (only loops that persist state, mutate the workspace, or auto-correct). `/qa:loop` (`plugins/qa/commands/loop.md`) is the reference implementation — it conforms to the whole MUST bar; cite its named anchors when you need a worked example.

## The minimum bar

Every closed loop in this marketplace MUST meet the **Universal** items. The **Conditional** items become MUST when the loop **persists state, mutates the workspace, and/or auto-corrects toward a target**. Each Conditional item is gated independently by its own trigger; a loop that does not hit a trigger may mark that item **N/A with a one-line justification affirming it neither persists loop-critical state, mutates the workspace, nor auto-corrects** — never silently.

### Universal (always MUST)

1. **Name the oracle, and state what it cannot verify.** Declare the ground-truth signal *and* its blind spots. An unstated oracle is an unfalsifiable "it passed." → qa:loop's Coverage block reports `"Exercised"`, not `"Verified"`, for feature passes.
2. **Separate verifier authority from the actor; gate and log on the raw signal, not narration.** Only a fresh, independent re-run decides pass/fail; the fixer's self-verdict is advisory; never hand the verifier the exact target it grades; gate and log on the raw oracle output (exit code, HTTP status, row count, test output), never the actor's "I'm done." A fixer grading its own fix — or a loop logging narration — is self-report, not verification. → qa:loop glossary *Verifier authority*; the Error-Handling rule *"fix-auto says 'Fixed' but re-run still fails → Re-run is authoritative."*
3. **Disclose, don't gate, on coverage.** Shallow or partial coverage produces a WARNING (and a low-confidence-green message), never a green→red flip; the loop must be able to say "I converged but verified little." → qa:loop's shallow-coverage WARNING + low-confidence green.
4. **Default to a human gate; go headless only on explicit opt-in with a fail-closed TTY check.** Autonomous correctness is unreachable when the verifier is stochastic. → qa:loop's `--mode approve` default; approve/step abort without a TTY.
5. **Reuse fail-closed safety guards; don't reinvent them.** Environment/host guard, mutation/write guard (moot for a read-only loop), ambiguous input → ask/abort. → qa:loop's *Safety Guards (Apply in All Modes)*; `plugins/commit/scripts/block-git-push.sh` (deny > ask > allow) as the deterministic exemplar.
6. **Bound the loop with hard budgets.** Cap iterations ∧ dispatches ∧ time. Unbounded loops blow cost; weak budgets ship the first (false) green. → qa:loop's triple-gate (`--max-iterations` / `--max-dispatches` / `--time-budget`).
   - *Rider (model-heavy loops — recommended, not a universal MUST):* also cap cost/tokens. qa:loop has no cost ceiling despite being model-heavy, so this prescribes beyond the reference.
7. **Stop on no-progress and oscillation, and report "stopped" as distinct from success.** A loop can stall or oscillate well under budget; "stopped / budget-exhausted" must not read as "passed." → qa:loop's Step 3f regression-stop + no-progress stop; glossary *Oscillation*.
8. **Document the residual-risk list.** If you cannot enumerate what the loop fails to catch, it is not ready. → qa:loop's residual notes (auth-unverified, *Verifier-gaming residual (v1)*, 2xx-shaped gating).

### Conditional (MUST when the loop persists state, mutates the workspace, and/or auto-corrects)

9. **Guard provenance — don't auto-fix a suspect assertion.** *(Auto-correcting loops.)* Auto-generated or guessed assertions are not auto-fixed against correct source; the failure may be the assertion, not the code. A read-only loop has nothing to auto-fix and satisfies this trivially. → qa:loop's *Provisional plan-suspect guard (T3)* (excludes such scenarios from `fix_candidates`).
10. **Persist state in a durable sidecar with input hash-pinning, and be idempotent.** *(Stateful loops.)* Loop-critical state lives on disk, not in the conversation; the input is hashed to detect mid-run tampering; re-running on identical input reuses prior state by hash and never duplicates results or re-applies corrections. The orchestrator's own memory is lossy across many tool calls. → qa:loop's sidecar + plan hash; Step 1 "Resolve Report + Sidecar (Idempotency)".
11. **Keep writes scoped and recoverable.** *(Mutating loops.)* Touch only what you changed; never destroy the user's pre-existing work; leave changes uncommitted for human control. → qa:loop's `fix_touched_files = post − pre_loop_dirty`; scoped `git restore`.

## Oracle taxonomy

The oracle is the loop's load-bearing part. Classify it before you trust it.

- **Strong (tool / wire):** tests, type checker, build, exit codes, HTTP status, row counts, browser/E2E. Deterministic, fast, ungameable from inside the loop.
- **Soft (LLM-judged):** another agent's opinion. Slow, non-deterministic.

Rules: prefer strong oracles; a soft oracle MUST self-label its verdict *advisory* (e.g. a "Re-reviewed (advisory)" status, or qa:loop's `"Exercised"`, not `"Verified"`). The actor must never author the oracle nor be able to see-and-game it, and re-verification must be independent of the corrector.

## Anti-patterns

- **Self-graded auto-fix loop** — e.g. an autonomous code-review fix loop where "Fixed" is the fixer's own verdict, with no independent re-dispatch of the originating auditor. *(Prospective: no such loop exists in this repo yet; this is a design constraint derived by analogy from qa:loop's verifier-authority separation, to apply when that loop is built.)*
- **Reading `--auto` / exit-code-0 as "verified"** in CI — the disclosure layer is for a human reader, not a gate.
- **Auto-fixing a guessed or auto-generated assertion** against correct source.
- **A soft-only budget on an expensive (model-heavy) loop** with no cost ceiling.
- **Keeping loop-critical state in conversation context.**
- **Reporting PASS for a target the verifier structurally cannot reach** (auth-gated, worker-resident, async) instead of disclosing the gap.
- **Tightening the budget to force convergence** — that just ships the first green, which may be the false one.

## Reference implementation — `/qa:loop`

`/qa:loop` (`plugins/qa/commands/loop.md`) conforms to the whole MUST bar; reference its **named** anchors (stable across edits), each for one thing:

- *Verifier authority* (glossary) — fresh re-run gates; the fixer's verdict is advisory.
- *Verifier-gaming residual (v1)* — the honest "a capable fixer can still game a visible check" caveat.
- *Provisional plan-suspect guard (T3)* — auto-generated assertions excluded from auto-fix.
- *Safety Guards (Apply in All Modes)* — the fail-closed environment and mutation guards.
- *Status write-back* (glossary) — written once, only from the authoritative final run.
- The `## Coverage` block and the auth-unverified outcome — "Exercised vs Not verified" disclosure.
- `plugins/commit/scripts/block-git-push.sh` — the deterministic, fail-closed guard exemplar (deny > ask > allow).

## Review checklist

Paste this into a loop spec's review. One box per bar item (Universal, then Conditional); riders hang off their item and are not counted.

**Universal**
- [ ] 1. Oracle named, with its blind spots stated
- [ ] 2. Verifier authority separated from the actor; gates/logs on the raw signal, not narration
- [ ] 3. Coverage disclosed, never gated green→red
- [ ] 4. Human gate by default; headless opt-in with fail-closed TTY check
- [ ] 5. Fail-closed safety guards reused, not reinvented
- [ ] 6. Hard budgets on iterations ∧ dispatches ∧ time
  - [ ] 6-rider (model-heavy): cost/token ceiling
- [ ] 7. No-progress and oscillation stops; "stopped" reported as non-success
- [ ] 8. Residual-risk list documented

**Conditional** (N/A allowed with a one-line justification)
- [ ] 9. Provenance guard — suspect assertions not auto-fixed *(auto-correcting loops)*
- [ ] 10. Durable sidecar + input hash-pin + idempotent re-runs *(stateful loops)*
- [ ] 11. Scoped, recoverable writes *(mutating loops)*

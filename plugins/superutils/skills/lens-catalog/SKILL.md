---
name: lens-catalog
description: Lens roster, panel-selection rules, and severity/needs-decision anchors for the /superutils:spec-review loop. Load when composing a review panel or grading findings.
---

# Lens Catalog

A lens is one reviewer's single perspective. The orchestrator selects 3–6
lenses per round; the two core lenses are always on. Panel composition and
selection rationale are logged in the sidecar every round.

## Roster (v1)

### Lens: internal-consistency (core)
Mandate: contradictions between the spec's own sections — nothing else.

### Lens: ambiguity-testability (core)
Mandate: requirements readable two ways by competent implementers, and
acceptance criteria that cannot be checked — nothing else.

### Lens: completeness
Mandate: could a developer write the implementation plan without coming back
with design questions? Missing load-bearing design decisions only. Never
demand implementation-plan detail; never report gaps the spec explicitly
delegates or defers.

### Lens: feasibility
Mandate: can the platform actually deliver each claimed behavior? Verify
against the repository (this lens may read the repo); a mechanism the
reference implementations already demonstrate refutes the finding.

### Lens: doctrine-compliance
Mandate: audit the spec against the loop-engineering bar **restated below** —
it is reproduced here in full because the reviewer agent has no `Skill` tool
and cannot load a cross-plugin skill; a lens that silently reconstructs the bar
from memory would grade against invented criteria and still return valid JSON,
which Coverage would score as a clean pass. Report one finding per unmet item,
citing the item number. Select only for specs that design closed loops, agents,
or marketplace plugins.

**The bar** (8 universal + 3 conditional; source of truth is the
`qa:loop-engineering` skill — keep this copy in sync with it):

1. **Name the oracle, and state what it cannot verify.** An unstated oracle is
   an unfalsifiable "it passed."
2. **Separate verifier authority from the actor; gate and log on the raw
   signal, not narration.** Only a fresh, independent re-run decides pass/fail;
   the fixer's self-verdict is advisory; **never hand the verifier the exact
   target it grades**; gate on the raw oracle output, never on the actor's
   "I'm done."
3. **Disclose, don't gate, on coverage.** Shallow coverage produces a WARNING
   and a low-confidence pass — **never a green→red flip**. The loop must be able
   to say "I converged but verified little."
4. **Default to a human gate; go headless only on explicit opt-in with a
   fail-closed TTY check.** Autonomous correctness is unreachable when the
   verifier is stochastic. Judge this item as written: a loop that cannot probe
   a TTY and judges interactivity heuristically **does not meet it** — grade it
   unmet and let the spec disclose the gap. Do not grade the loop against a
   softened restatement of the bar; that is how a loop passes the one item it
   fails.
5. **Reuse fail-closed safety guards; don't reinvent them** (environment/host,
   mutation/write, ambiguous input → ask or abort).
6. **Bound the loop with hard budgets:** iterations ∧ dispatches ∧ time.
   *(Rider, not a universal MUST: a model-heavy loop should also cap
   cost/tokens.)*
7. **Stop on no-progress and oscillation, and report "stopped" as distinct from
   success.** "Budget-exhausted" must never read as "passed."
8. **Document the residual-risk list.** If you cannot enumerate what the loop
   fails to catch, it is not ready.
9. *(Auto-correcting loops)* **Guard provenance:** a suspect or auto-generated
   assertion is never auto-fixed against correct source — the failure may be the
   assertion, not the target.
10. *(Stateful loops)* **Durable sidecar with input hash-pinning, idempotent
    re-runs.** Loop-critical state lives on disk, never in conversation context;
    the input is hashed to detect mid-run tampering; a re-run on identical input
    reuses prior state and **never duplicates results or re-applies
    corrections**.
11. *(Mutating loops)* **Writes are scoped and recoverable:** touch only what
    you changed, never destroy pre-existing work, leave changes uncommitted.

**Oracle taxonomy (also auditable):** prefer a *strong* oracle (tests, types,
build, exit code, HTTP status, row count) over a *soft* one (LLM-judged). A soft
oracle **MUST** self-label its verdict advisory. The actor must never author the
oracle nor be able to see-and-game it, and re-verification must be independent
of the corrector.

Each conditional item (9–11) is gated **independently by its own trigger**. A
loop that does not hit a trigger may mark that item **N/A with a one-line
justification affirming it neither persists loop-critical state, mutates the
workspace, nor auto-corrects** — never silently. (Quoted from the source bar,
whose gating sentence and justification form sit in tension; when auditing,
require the justification to at least address the item's own trigger —
auto-correction for 9, persisted state for 10, workspace mutation for 11.)

**Anti-patterns** (each is a finding): a self-graded fix loop; reading `--auto`
or exit-code-0 as "verified"; auto-fixing a guessed assertion; a soft-only
budget on a model-heavy loop; loop-critical state kept in conversation context;
reporting PASS for a target the verifier structurally cannot reach; tightening
the budget to force convergence.

### Lens: ux
Mandate: user-facing flows, interaction cost, and copy. Select only for specs
with UI/UX surface.

### Lens: contracts
Mandate: API shapes, schemas, data contracts, versioning/compatibility.
Select only for specs defining external interfaces or data formats.

## Panel selection

1. Always include both core lenses.
2. Include `completeness` unless the spec is under 3 `##` sections.
3. Content triggers from the unit list: loop/agent/plugin design →
   `doctrine-compliance` + `feasibility`; UI/screens/flows → `ux`;
   API/schema/format → `contracts`.
4. **Floor at 3:** if rules 1–3 yield fewer than 3 lenses (a short spec with no
   content trigger), add `completeness`, then `feasibility`, until the panel
   reaches 3. The panel is never smaller than 3.
5. Cap at 6. Log the selected ids and one-line rationale in the sidecar.

## Severity anchors (shared by reviewers and challengers)

- **critical** — the spec self-contradicts or a compliant implementation
  would violate a stated invariant.
- **major** — two competent implementers would build observably different
  load-bearing behavior.
- **minor** — divergence with low blast radius.
- **nit** — wording/format only.

## Needs-decision anchor

Flag `needs_decision` iff the fix requires choosing among materially
different alternatives that the spec's own content cannot arbitrate (a
decision, not a derivation), or the fix would reverse a recorded user
decision or an explicitly stated requirement.

## Self-falsification (binding on every reviewer)

Before reporting, try to refute each finding from the reviewed text. Report
only survivors; list rejected candidates one line each. Never silently drop.

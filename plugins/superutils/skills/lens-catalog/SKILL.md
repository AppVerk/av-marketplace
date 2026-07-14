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

1. The oracle is named, and what it *cannot* verify is stated.
2. Verifier authority is separated from the actor; the loop gates and logs on
   the raw signal, never on the actor's narration. A fixer's self-verdict is
   advisory only.
3. Coverage is disclosed, never gated: shallow coverage produces a WARNING and
   a low-confidence pass, never a silent green.
4. A human gate is the default; headless is opt-in with a fail-closed check.
5. Safety guards are reused, not reinvented (environment/host, mutation/write,
   ambiguous input → ask or abort).
6. Hard budgets bound iterations ∧ dispatches ∧ time. *(Rider, not a MUST: a
   model-heavy loop should also cap cost/tokens.)*
7. No-progress and oscillation stops exist, and "stopped" is reported as
   distinct from success.
8. The residual-risk list is documented.
9. *(Auto-correcting loops)* Provenance guard: a suspect or auto-generated
   assertion is never auto-fixed against correct source.
10. *(Stateful loops)* State lives in a durable sidecar with an input hash-pin;
    re-runs are idempotent.
11. *(Mutating loops)* Writes are scoped and recoverable; the user's
    pre-existing work is never destroyed; nothing is committed.

Conditional items may be marked N/A only with a one-line justification that the
loop neither persists state, mutates the workspace, nor auto-corrects.

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

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
Mandate: audit against `qa:loop-engineering` (bar items 1–11 + anti-patterns).
Select only for specs that design closed loops, agents, or marketplace
plugins.

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
4. Cap at 6. Log the selected ids and one-line rationale in the sidecar.

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

# Acceptance protocol — /superutils:spec-review

**Harness (v1, resolves the spec's open question):** manual interactive
protocol — a human runs the command and answers prompts from the script
below. (Future automation: Agent SDK `canUseTool` auto-responder.)

## Procedure (3 independent runs)

Each run starts fresh: copy `fixtures/seeded-spec.md` to
`docs/superpowers/specs/seeded-spec.md` in a scratch branch, with no sidecar,
report, or snapshot present.

Run `/superutils:spec-review docs/superpowers/specs/seeded-spec.md` in the
default mode with this answer script:
- the working-tree gate (fires on every run — the fixture copy is untracked)
  → **proceed**
- every needs-decision prompt → **accept the proposed fix**
- every batch-approve gate → **approve (full batch)**

## Pass condition (per run)

Terminal status `CONVERGED` within default budgets AND all three post-run
content predicates hold on the final fixture file:

1. **Contradiction seed:** the Delivery-rules / Batching / 60-second claims
   no longer conflict (one consistent policy remains).
2. **Phantom-section seed:** the "Error Handling" reference is removed or an
   `## Error Handling` section exists.
3. **Ambiguity seed:** exactly one duplicate-detection behavior is derivable
   (the duplicate key and window are stated).

A keep-as-is outcome on a seeded defect does NOT count as resolved — the
fixture demonstrates fixing, not just termination.

**Overall pass: at least 2 of 3 runs pass.** Record each run's report path
and result here.

## Dogfood check (once per release)

Run the command on a **real** design spec — one produced by the superpowers
brainstorming→design flow, not the seeded fixture; this repo keeps no such
document, so use one from the project you are working in. Pass = a valid
terminal status within default budgets and a report + sidecar conforming to
`superutils:spec-report-format`.

**Isolate it — the loop edits its target in place.** A clean tracked file
passes the working-tree gate silently, so an unisolated run rewrites a
committed document with no warning. Run it on a scratch branch and discard that
branch afterwards (or `git restore` the spec once the report is captured).

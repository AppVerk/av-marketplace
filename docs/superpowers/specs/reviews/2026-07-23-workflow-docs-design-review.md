# Spec-review loop report — 2026-07-23-workflow-docs-design.md

**Run:** 1 · **Mode:** default (interactive, approve-gated) · **Budgets used:** 1/3 iterations, 4/60 dispatches, ~276/1800 s · **Terminal status:** `CONVERGED` · **Verdict:** Re-reviewed (advisory)

The panel found zero significant (major+) findings in round 1; with no unlanded
fixes and no unconfirmed entries, the loop converged before the fix phase. The
five minor findings below were reported, not applied — the spec is byte-identical
to what the panel reviewed.

## Round 1 — panel: internal-consistency, ambiguity-testability, completeness, feasibility

Panel rationale: two core lenses always on; completeness (spec has >3 `##`
sections); feasibility added because the spec's load-bearing content is factual
claims about repo commands and artifact paths. No doctrine-compliance (not a
loop/agent/plugin design), no ux, no contracts.

Units: Goal · Motivation · Non-Goals · Design · Error handling / edge cases · Success criteria

| SR | severity | lenses | outcome | finding |
|----|----------|--------|---------|---------|
| SR-001 | minor | internal-consistency | reported-only | Design's per-stage behavioral content (Stage 2 terminal statuses, Stage 4 `/qa:loop` internals, Stage 5 `/fix-report` merge behavior) exceeds what Non-Goals and Success criterion 2 permit ("no content duplicated beyond command names and artifact paths"). Fix: reconcile — either loosen the criterion to allow per-stage purpose/hand-off prose, or trim the behavioral sentences from the stage bullets. |
| SR-002 | minor | ambiguity-testability | reported-only | Success criterion 1 is a hypothetical reader-outcome no reviewer can check ("a reader … can run a full feature cycle"), and "full" is ambiguous given the superpowers-absent path. Fix: recast as an artifact-checkable property (every stage documents purpose, command, artifact path, hand-off; superpowers-absent path covered). |
| SR-003 | minor | ambiguity-testability | reported-only | "No content duplicated … beyond command names and artifact paths" leaves "duplicated" undefined (verbatim vs paraphrase), so two implementers could both claim compliance with observably different documents. Fix: define the test (no verbatim/near-verbatim flag tables, option lists, or edge-case text; per-stage text limited to purpose, command, artifact, hand-off). |
| SR-004 | minor | completeness | reported-only | Stage 3 offers two implementation paths (superpowers writing-plans/TDD or stack `/develop`) with no default or selection criterion, unlike Stage 4 which designates `/qa:loop` as first choice. Fix: recommend `/develop` when a matching developer plugin is installed, superpowers plan flow otherwise. |
| SR-005 | minor | feasibility | reported-only | Stage 6 *(commit)* folds in `/analyze-feedback`, which is a code-review plugin command (docs/plugins/code-review.md); a writer following the grouping would link it to commit.md, which does not document it. Fix: attribute `/analyze-feedback` to code-review in Stage 6. |

## Coverage

- Catalog lenses not selected this run: doctrine-compliance (spec designs no loop/agent/plugin), ux (no UI surface), contracts (no external interfaces or data formats).
- Not returned (failures, with reasons): none — all four reviewers returned parseable output on first dispatch.
- Standing oracle blind spots: intent, external facts, unstated requirements.

## Rejected by the panel (self-falsification)

- [internal-consistency] 'cycle'/'full development cycle' vs. the linear Mermaid chain with no return edge — idiomatic for a linear feature lifecycle; no contradiction.
- [internal-consistency] '## Workflow' heading vs. 'Recommended Workflow' link vs. 'lifecycle of a feature' subtitle — wording variance across a section, a link, and a subtitle, not a contradiction.
- [internal-consistency] 'ten plugins' vs. plugins enumerated across Design — exactly ten marketplace plugins enumerated; superpowers flagged as external; consistent.
- [internal-consistency] Prerequisites 'cycle starts at the implementation stage' vs. Stage 3's superpowers path — the non-superpowers `/develop` path remains available; no contradiction.
- [internal-consistency] Error handling 'start at Stage 3' vs. Prerequisites 'starts at the implementation stage' — Stage 3 is the implementation stage; the descriptions agree.
- [internal-consistency] Stage 3 lacks a '(plugin)' tag while the cheat sheet maps stage→plugin — Stage 3 legitimately spans plugins; the cheat sheet is not one-row-per-stage.
- [ambiguity-testability] 'sees ten plugins' count — verifiable, not readable two ways; feasibility/consistency domain.
- [ambiguity-testability] README diagram (7 nodes) vs workflow.md (6 stages) — each explicitly enumerated; no implementer divergence.
- [ambiguity-testability] 'reads acceptably as plain text' — rationale for choosing Mermaid, not an acceptance criterion.
- [ambiguity-testability] 'replace the generic one-liner' — the one-liner is discoverable in README; not readable two ways.
- [ambiguity-testability] Goal's artifact chain vs stage labels — motivational prose, not a build target.
- [ambiguity-testability] 'two–three sentences on the artifact flow' — bounded and checkable.
- [ambiguity-testability] Stage 3 missing plugin tag — plugins named inline; no build ambiguity.
- [completeness] Stage 3 artifact not explicitly named — derivable as the tested code on the feature branch.
- [completeness] Superpowers install command omitted — fillable content detail, not a design decision.
- [completeness] Diagram linear vs cyclic — representation explicitly decided in the spec.
- [completeness] Cheat-sheet plugin column for multi-plugin Stage 3 — table-cell detail, not load-bearing.
- [completeness] Whether workflow.md repeats the README diagram — placement detail governed by the no-duplication Non-Goal.
- [completeness] 'Documentation section' presupposed in README — known existing structure; repo fact outside this lens.
- [completeness] Ten-plugin coverage — all ten placed (7 in-cycle, 3 outside).
- [completeness] Feedback loops absent from the diagram — an explicit decision, not a gap.
- [completeness] Per-stage 'consumes' not spelled per stage — schema plus concrete paths make each derivable.
- [feasibility] 'sees ten plugins' — README badge=10; marketplace.json lists exactly 10.
- [feasibility] /superutils:spec-review command, reviews/ path, CONVERGED/STOPPED statuses — confirmed in superutils.md.
- [feasibility] Terminal-status shorthand omits 'CONVERGED (low-confidence)' — the spec's list is illustrative; both statuses are real.
- [feasibility] /develop in all three developer plugins with coding standards + TDD — confirmed in README.
- [feasibility] /qa:loop plan generation conditionality — default interactive mode auto-generates after a confirm; matches README and qa.md.
- [feasibility] /qa:create-plan, /qa:run, plans and reports paths — confirmed in qa.md.
- [feasibility] /review report path and SEC/PERF/ARCH/MAINT/DOC prefixes — confirmed in code-review.md.
- [feasibility] /fix, /fix-report auto-merge, /fix-all skip behavior — confirmed verbatim in code-review.md.
- [feasibility] /commit Conventional Commits + push guards — confirmed in commit.md.
- [feasibility] /audit and /setup outside the cycle — confirmed in web-auditor.md and README.
- [feasibility] sequentialthinking 'used by other plugins, e.g. superutils' — the one committed example is confirmed.
- [feasibility] Stage 1 spec path pattern — matches superutils.md's example.
- [feasibility] Workflow section placement after Installation — README structure supports it.
- [feasibility] Mermaid renders natively on GitHub — true external fact.

## Accepted risks (user-decided)

None.

## Declined (user-decided)

None.

## Residual risks

- Verifier gaming: reviewers and the orchestrator share a model family; a plausible-but-wrong framing can survive.
- Stochasticity: a re-run may surface findings this run did not (fresh panels re-derive candidates by design).
- Lens drift: a lens can wander from its mandate despite the single-mandate prompt.
- No token ceiling: budgets bound iterations, dispatches, and time — not tokens.
- Soft registry matching: semantic equivalence judgments are model-made and logged, not provable.
- Best-effort headless detection: session interactivity is model-judged; no TTY probe exists.
- The five minors were reported, not fixed — convergence asserts the absence of significant findings, not of all findings.

## Recovery

- Loop-touched files: `docs/superpowers/specs/reviews/2026-07-23-workflow-docs-design-review.state.json`, `docs/superpowers/specs/reviews/2026-07-23-workflow-docs-design-review.md` (this report).
- The spec itself was never written to; no pre-loop snapshot was taken (the snapshot is only taken before a first fix application, which never occurred). Never `git restore` on the spec.
- Nothing was committed by the loop.

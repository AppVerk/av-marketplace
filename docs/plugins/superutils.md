# Superutils Plugin

Companion utilities for the superpowers workflow — loop-engineered
verification of design specs.

**Version:** 1.0.1

## Commands

### `/superutils:spec-review`

Closed review loop for a design spec from `docs/superpowers/specs/`
(brainstorming→design shape). Each round: decomposition into `##` units (uses
the sequential-thinking MCP server when available) →
3–6 lens reviewers in parallel (2 core lenses always on) → orchestrator
finding registry (SR ids) → adversarial challenger per major+ finding
(2 for criticals) → needs-decision questions → fix batch behind an
approve-before-apply diff preview → fresh-panel re-review decides
convergence.

```bash
# Newest spec in docs/superpowers/specs/
/superutils:spec-review

# Explicit spec, default interactive (approve-gated) mode
/superutils:spec-review docs/superpowers/specs/2026-07-13-foo-design.md

# Auto-apply with printed diffs; questions still asked
/superutils:spec-review --no-approve

# Headless; needs-decision findings skipped, never auto-decided
/superutils:spec-review --auto --max-iterations 2
```

| Flag | Default | Meaning |
|---|---|---|
| `--no-approve` | off | Skip the batch gate; print full diff after each batch |
| `--auto` | off | Headless; implies `--no-approve` |
| `--allow-dirty` | off | Bypass the working-tree gate |
| `--max-iterations` | 3 | Round cap |
| `--max-dispatches` | 30 | Subagent-launch cap (retries count) |
| `--time-budget` | 1800 | Active seconds (user waits excluded) |

**Terminal statuses:** `CONVERGED`, `CONVERGED (low-confidence)`,
`STOPPED(budget | no-progress | oscillation | pending-decisions |
user-declined | interaction-unavailable | external-edit)` — a stop is never
success. Reports and a state sidecar land in
`docs/superpowers/specs/reviews/`; the loop never commits, and recovery
points at the pre-loop snapshot.

**Re-running (the sidecar is control flow, not just an artifact):**

| State | What a re-run does |
|---|---|
| Spec unchanged since a finished run | Prints the prior report summary and exits — no dispatches, no new review |
| Run interrupted mid-way | Resumes: counters continue, recorded decisions replay without re-asking |
| Spec edited since the last run | Starts a new run; prior report and rounds are archived, decisions carry forward |

To force a clean review of an unchanged spec (e.g. after a
`CONVERGED (low-confidence)` run whose lens failures you want re-tried), delete
`docs/superpowers/specs/reviews/<spec>-review.state.json` first.

**Honest limits:** the oracle is soft (LLM panel + challenger) — verdicts are
advisory; it cannot verify your intent, external facts, or unstated
requirements. The command implements the `qa:loop-engineering` bar; see the acceptance protocol in `plugins/superutils/tests/ACCEPTANCE.md`.

## Agents

- `spec-reviewer` — one lens per dispatch, self-falsifying, raw JSON findings
- `spec-challenger` — refute-or-uphold at the finder's severity, one finding per dispatch
- `spec-fixer` — proposes exact `{old, new}` edit pairs; has no write tools

## Skills

- `lens-catalog` — lens roster, panel-selection rules, severity and
  needs-decision anchors, and the loop-engineering bar the
  `doctrine-compliance` lens audits against
- `spec-report-format` — report structure, sidecar schema, outcome enum,
  statuses (named apart from `qa:report-format`, which is the QA test-report
  format)

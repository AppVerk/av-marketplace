# Superutils Plugin

Companion utilities for the superpowers workflow — bounded, loop-engineered
triage of design specs.

**Version:** 2.0.0

## Commands

### `/superutils:spec-review`

Fixed triage pipeline for a design spec from `docs/superpowers/specs/`
(brainstorming→design shape). One pass, nothing repeats: decomposition into `##`
units (uses the sequential-thinking MCP server when available) → every
applicable lens reviewer in parallel (2 core lenses always on, no cap) →
orchestrator finding registry (SR ids) → one adversarial challenger per
**critical** finding → needs-decision questions (grouped four per call) → batch
A behind an approve-before-apply diff preview → a `fix-coherence` verifier that
reads the applied diff and says, per finding, whether the defect is gone →
batch B (unresolved and fix-induced findings, same gate) → report.

```bash
# Newest spec in docs/superpowers/specs/
/superutils:spec-review

# Explicit spec, default interactive (approve-gated) mode
/superutils:spec-review docs/superpowers/specs/2026-07-13-foo-design.md

# Auto-apply with printed diffs; questions still asked
/superutils:spec-review --no-approve

# Headless; needs-decision findings skipped, never auto-decided
/superutils:spec-review --auto --max-dispatches 12
```

| Flag | Default | Meaning |
|---|---|---|
| `--no-approve` | off | Skip the approve gate; print the full diff after each batch |
| `--auto` | off | Headless; implies `--no-approve` |
| `--allow-dirty` | off | Bypass the working-tree gate |
| `--max-dispatches` | 20 | Subagent-launch cap (retries count) |
| `--time-budget` | 900 | Active seconds (user waits excluded) |

A typical run costs 8–12 dispatches: five to seven reviewers, a challenger per
critical, two fixers, one verifier. There is no iteration flag — the pipeline's
shape bounds it.

**Terminal statuses:** `TRIAGED` · `TRIAGED (incomplete)` ·
`STOPPED(user-declined | budget | interaction-unavailable | external-edit)` — a
stop is never success. The report lands in `docs/superpowers/specs/reviews/`
beside a pre-loop snapshot of the spec; the pipeline never commits.

**`TRIAGED` means the pipeline ran to the end and every fix it batched landed.**
It does not mean a fresh panel would find nothing: minors and nits are reported,
not fixed, and batch B's edits are applied without further verification (their
outcome says so: `applied (not re-reviewed)`). `TRIAGED (incomplete)` means
something the pipeline owed did not land or return — a lens or the verifier did
not come back, a fix failed twice, or a needs-decision entry was skipped under
`--auto` — and the report names it. Residuals are ordered most- to
least-serious, with `confirmed (not fixed — stopped)` and `fix-failed` first.

**Re-running (the report is the durable state):**

| State | What a re-run does |
|---|---|
| Spec unchanged since the last run (its hash equals the report's `post-loop` hash) | Interactive: asks re-run / exit. `--auto`: prints the prior status and exits — no dispatches |
| Spec edited since the last run, or a report with no hash line (pre-2.0.0) | Archives the report to `<spec>-review.run<N>.bak` and starts fresh from SR-001 |
| Run interrupted mid-way | Nothing resumes: re-run, and the pipeline triages whatever the spec now contains. A pre-2.0.0 sidecar beside the report is archived, never read |

**Honest limits:**

- The oracle is soft (an LLM panel, a challenger per critical, an LLM verifier),
  so every verdict is advisory — "Re-reviewed (advisory)", never "Verified". It
  cannot check your intent, external facts, or requirements you never wrote down.
- Against the `qa:loop-engineering` bar: **item 4 is not met** — no fail-closed
  TTY check exists in this harness (a tool's stdin is never a TTY), so
  interactivity is judged heuristically and the run fails closed by default, with
  an AskUserQuestion failure stopping it before any write of the pending batch.
  **Item 9 applies** — the pipeline auto-corrects, and every assertion it corrects
  toward is a stochastic panel finding; majors carry no challenger, so under
  `--auto` or `--no-approve` a wrong finding is fixed rather than questioned.
  **Item 10's first clause is not met, deliberately** — the registry, your
  decisions and the pinned hash live in the orchestrator's context until the
  report is written; an interruption across the approve gate loses them and the
  questions are asked again next run.
- Human interaction cost is disclosed, not budgeted: at most one question per
  needs-decision finding (four per call), one approve gate per batch, and one
  page per four edit groups only if you choose to approve a subset.
- The dispatch cap doubles as the cost ceiling; there is no token budget.
- Spec growth is measured and shown at the gate (`+N lines (+P%)`), not limited.
- **The acceptance protocol (`plugins/superutils/tests/ACCEPTANCE.md`) has not
  been run against 2.0.0.** Treat the first real run as the actual test.

## Agents

- `spec-reviewer` — one lens per dispatch, self-falsifying, raw JSON; barred from
  reading the pipeline's own reports and snapshots. With the `fix-coherence`
  lens it verifies an applied batch: it sees the diff, the spec and each
  finding's description, never the proposed fix or the fixer's pairs, and it
  echoes SR ids without ever deriving one
- `spec-challenger` — one critical finding per dispatch, uphold or refute at the
  finder's severity. `refute` means *not a real defect*: uncertainty upholds
- `spec-fixer` — proposes exact `{old, new}` edit pairs; a pair lists every SR it
  resolves (`sr_ids`), rewrites before it appends, reports the batch's growth,
  and re-derives (`re-derive`) or re-fixes (`re-fix`) what an earlier pass left
  unresolved; it has no write tools — the orchestrator applies what you approve

## Skills

- `lens-catalog` — lens roster (seven panel lenses plus the verification-only
  `fix-coherence`), panel-selection rules, severity and needs-decision anchors,
  and the loop-engineering bar the `doctrine-compliance` lens audits against
- `spec-report-format` — output shapes (reviewer, challenger, verifier, fixer),
  SR-id rules, markers, outcome enum, statuses, and the report skeleton (named
  apart from `qa:report-format`, which is the QA test-report format)

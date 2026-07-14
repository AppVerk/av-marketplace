# Superutils Plugin

Companion utilities for the superpowers workflow — loop-engineered
verification of design specs.

**Version:** 1.0.2

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
| `--max-dispatches` | 60 | Subagent-launch cap (retries count) |
| `--time-budget` | 1800 | Active seconds (user waits excluded) |

**Terminal statuses:** `CONVERGED`, `CONVERGED (low-confidence)`,
`STOPPED(budget | no-progress | oscillation | pending-decisions |
user-declined | interaction-unavailable | external-edit)` — a stop is never
success. Reports and a state sidecar land in
`docs/superpowers/specs/reviews/`; the loop never commits, and recovery
points at the pre-loop snapshot.

**`CONVERGED` means the work actually landed.** The loop will not report success
while it still owes you something, so convergence requires all three: no
significant findings left, **no unlanded fix** (a fix that entered the batch but
whose edit did not apply — at any severity, including a minor), and **no
unconfirmed finding** (a major+ whose challenger never returned). Consequences
worth knowing before you see them:

- A fix you accepted whose edit fails to apply is re-proposed next round with a
  freshly derived edit — never a replay of the one that already failed. If that
  attempt fails too, the run ends `STOPPED(no-progress)`, not `CONVERGED`. You
  are told the fix never landed rather than being handed a green report.
- A challenger that dies is re-dispatched every round until it returns a
  verdict; its finding is never silently treated as refuted.
- Accepting a fix settles *which* edit to make, not *whether* the defect exists:
  if a later fresh panel still finds it, it comes back as a normal finding.

**Re-running (the sidecar is control flow, not just an artifact):**

| State | What a re-run does |
|---|---|
| Spec unchanged since a finished run | Prints the prior report summary and exits — no dispatches, no new review |
| Run interrupted mid-way | Resumes: counters continue, recorded decisions replay without re-asking |
| Spec edited since the last run | Starts a new run; prior report and rounds are archived. The finding registry carries forward whole — decisions **and** unfinished work (unlanded fixes, unconfirmed findings): a new run does not forgive them |

To force a clean review of an unchanged spec (e.g. after a
`CONVERGED (low-confidence)` run whose lens failures you want re-tried), delete
`docs/superpowers/specs/reviews/<spec>-review.state.json` first.

**Honest limits:**

- The oracle is soft (an LLM panel plus challengers), so every verdict is
  advisory — reported as "Re-reviewed", never "Verified". It cannot check your
  intent, external facts, or requirements you never wrote down.
- It meets the `qa:loop-engineering` bar on 10 of its 11 items. **Item 4 is only
  partially met:** no fail-closed TTY check exists in this harness (a tool's
  stdin is never a TTY), so interactivity is judged heuristically and fails
  closed by default, with an AskUserQuestion failure aborting the run as a
  backstop. Disclosed rather than designed away.
- The dispatch cap doubles as the cost ceiling; there is no hard token budget.
- **The acceptance protocol (`plugins/superutils/tests/ACCEPTANCE.md`) has not
  been run.** The loop is verified statically — by review, not by execution — so
  treat the first real run as the actual test.

## Agents

- `spec-reviewer` — one lens per dispatch, self-falsifying, raw JSON findings;
  barred from reading the loop's own reports and sidecar, so a fresh panel
  cannot read its own answer key
- `spec-challenger` — one finding per dispatch, uphold or refute at the finder's
  severity. `refute` means *not a real defect*: uncertainty upholds, and a real
  defect graded too high is still upheld rather than deleted over its grade
- `spec-fixer` — proposes exact `{old, new}` edit pairs (plus an `obsolete` list
  for defects already gone from the text); has no write tools — the orchestrator
  applies what you approve

## Skills

- `lens-catalog` — lens roster, panel-selection rules, severity and
  needs-decision anchors, and the loop-engineering bar the
  `doctrine-compliance` lens audits against
- `spec-report-format` — report structure, sidecar schema, outcome enum,
  statuses (named apart from `qa:report-format`, which is the QA test-report
  format)

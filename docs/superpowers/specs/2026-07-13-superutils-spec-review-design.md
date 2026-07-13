# superutils — `/superutils:spec-review` Design

**Date:** 2026-07-13
**Status:** Approved design, pre-implementation
**Doctrine:** conforms to `qa:loop-engineering` (see compliance checklist at the end)

## Purpose

A new marketplace plugin, `superutils`, that provides companion commands for the
superpowers workflow. Its first command, `/superutils:spec-review`, runs a closed
agent loop that reviews and improves a design spec produced by
`superpowers:brainstorming`: decompose → Mixture-of-Agents review → adversarial
confirmation → apply fixes → fresh re-review, until convergence or a stop condition.

It replaces this manual prompt with an engineered, bounded, auditable loop:

> Use sequential thinking to decompose complex topics, run a Mixture of Agents
> review, apply the suggested changes, and repeat until there are no significant
> suggestions.

## Scope (v1)

- **Input:** superpowers-produced specs only — `docs/superpowers/specs/*.md`,
  assuming the brainstorming→design document shape. Path given as argument;
  with no argument, the newest file (by modification time) in
  `docs/superpowers/specs/` is used. No candidate file → ask/abort, never guess.
- **One command:** `/superutils:spec-review`. Growth path (explicitly out of v1
  scope): `plan-review` for writing-plans output, a single-pass review mode.

## Plugin identity and structure

- **Name:** `superutils` — category `planning`, initial version `1.0.0`.
- **Marketplace description:** "Companion utilities for the superpowers workflow —
  loop-engineered verification of specs and plans."

```
plugins/superutils/
  .claude-plugin/plugin.json
  commands/spec-review.md        # loop orchestrator (pattern: /qa:loop)
  agents/spec-reviewer.md        # lens-parameterized reviewer
  agents/spec-challenger.md      # adversarial verifier of findings
  agents/spec-fixer.md           # applies confirmed fixes to the spec
  skills/lens-catalog/SKILL.md   # lens catalog + panel-selection rules
  skills/report-format/SKILL.md  # report + sidecar format
```

Registration obligations (per repo rules): entry in
`.claude-plugin/marketplace.json`, row in the README Available Plugins table,
plugin-count badge bump, and `docs/plugins/superutils.md`.

## Architecture

Command-orchestrated loop (approach A): the main conversation drives rounds and
dispatches subagents. This is the only architecture compatible with the
needs-decision gate — only the main loop can ask the user questions mid-run.
Reviewer, challenger, and fixer are separate agents (actor/verifier separation).

## Loop algorithm

Round `r` on spec `S`:

1. **Decompose (sequential thinking).** The orchestrator breaks `S` into review
   units and selects the panel: 3–6 lenses from the lens catalog. Two **core
   lenses are always on** — internal consistency and ambiguity/testability — the
   rest are chosen to fit the spec's content (e.g. a UI spec gets a UX lens, an
   API spec gets a contracts lens). The panel composition is logged in the
   sidecar each round, keeping the dynamic panel auditable and rounds comparable.
2. **MoA fan-out.** One reviewer agent per lens, dispatched in parallel. A
   finding is `{severity: critical|major|minor|nit, location, description,
   proposed fix, needs-decision?, fingerprint}`. The fingerprint is a stable
   hash of (location + normalized issue summary), excluding severity and lens,
   so the same issue matches across rounds regardless of who found it.
3. **Quorum via challenger.** With disjoint lenses, "≥2 reviewers saw the same
   thing" is structurally unavailable (only the completeness lens can see a
   completeness gap). Quorum is therefore **finder + independent challenger**:
   every major+ finding goes to an adversarial challenger whose job is to refute
   it. **Significant = major+ AND survived refutation** (two independent
   opinions). Critical findings get 2 challengers and a 2-of-3 majority decides,
   with the finder counting as one uphold vote (i.e. a critical finding survives
   if at least one challenger upholds it). This reuses
   the existing marketplace challenger pattern (code-review:challenger,
   web-auditor:challenger).
4. **Needs-decision gate.** Findings flagged needs-decision are put to the user
   (AskUserQuestion in the main loop); decisions are recorded in the sidecar.
   Without a TTY they are skipped and reported — never auto-decided.
5. **Fix.** The fixer applies confirmed fixes **to the spec file only**, never
   committing. Its "done" is advisory.
6. **Verifier authority.** Convergence is decided solely by the **next round's
   fresh panel** on the updated spec: the loop converges when a fresh round
   yields zero significant findings (post-refutation). The verdict is reported
   as **"Re-reviewed (advisory)"** — never "Verified" — because the oracle is
   soft.

### Interaction modes

- **Default (interactive):** mechanical fixes auto-applied; the loop stops only
  for needs-decision findings; a per-round diff summary is printed so the spec
  never changes invisibly.
- **`--approve`:** stricter mode — the round's fix batch requires a yes/no
  before application.
- **`--auto` (headless, explicit opt-in):** no interaction; needs-decision
  findings are skipped and reported. Fail-closed TTY check: interactive modes
  abort without a TTY; `--auto` is the only mode that proceeds.

### Budgets and stop conditions

- **Triple gate:** `--max-iterations` (default 3), `--max-dispatches`
  (default 30 — doubles as the soft cost ceiling for this model-heavy loop, per
  the loop-engineering rider), `--time-budget` (default 30 min).
- **No-progress stop:** an identical significant-finding set (by fingerprint)
  in two consecutive rounds.
- **Oscillation stop:** a fingerprint fixed in round `r−2` reappears in round `r`.
- **Terminal statuses:** `CONVERGED` vs `STOPPED(budget|no-progress|oscillation)`
  — a stop is never reported as success.

### State and writes

- **Sidecar:** a durable state file next to the report, pinned to the spec's
  hash. Re-running on an unchanged spec with an existing sidecar resumes or
  reports instead of duplicating rounds or re-applying fixes (idempotency). A
  hash mismatch (spec edited outside the loop) → stop and ask.
- **Scoped, recoverable writes:** the loop touches only the spec file, the
  report, and the sidecar; nothing is committed; the user's pre-existing work is
  never destroyed.

## Report

Written to `docs/superpowers/specs/reviews/<spec>-review.md`:

- round-by-round trace: panel composition, findings with `SR-XXX` ids and
  outcomes (applied / skipped / needs-decision: user's decision),
- a **Coverage** block: "Exercised lenses: … / Not verified: …",
- terminal status and the residual-risk list.

## Oracle statement

**Oracle:** the MoA panel verdict plus challenger-refutation survival — a
**soft** (LLM-judged) oracle; every verdict is labeled advisory.

**Blind spots (stated in the command and every report):** it cannot verify that
the spec matches the user's actual intent; it cannot verify external facts (the
feasibility lens may read the repo, but its output is still an opinion); it
cannot verify completeness against unstated requirements.

## Residual risks

1. **Verifier gaming:** the fixer could in principle write to please the lenses;
   a fresh panel each round limits but does not eliminate this.
2. **Stochasticity:** the same loop may converge on one run and not another.
3. **Lens drift:** dynamic panels may differ between rounds despite the core
   lenses — mitigated by logging composition, not eliminated.
4. **No hard token ceiling:** the dispatch cap is a proxy, not a cost meter.

## Verifying the plugin itself

- A fixture spec with seeded defects (a contradiction, a phantom section, an
  ambiguous requirement) — the loop must find and fix all three.
- The `qa:loop-engineering` review checklist applied to the shipped command
  (see below).
- Dogfooding: this design document is the loop's first real target.

## Loop-engineering compliance checklist

**Universal**
- [x] 1. Oracle named, blind spots stated (Oracle statement section)
- [x] 2. Verifier authority separated; fresh-panel gating, fixer verdict advisory
- [x] 3. Coverage disclosed ("Exercised lenses / Not verified"), never gated
- [x] 4. Human gate by default (needs-decision + diff visibility; `--approve`);
      headless only via `--auto` with fail-closed TTY check
- [x] 5. Fail-closed guards reused (ambiguous input → ask/abort; hash-mismatch → stop)
- [x] 6. Hard budgets: iterations ∧ dispatches ∧ time
  - [x] 6-rider: dispatch cap doubles as the model-heavy cost proxy
- [x] 7. No-progress and oscillation stops; `STOPPED ≠ CONVERGED`
- [x] 8. Residual-risk list documented

**Conditional** (all triggered: the loop persists state, mutates the spec, auto-corrects)
- [x] 9. Provenance guard: findings enter fixing only after challenger
      confirmation; needs-decision findings are never auto-fixed
- [x] 10. Durable sidecar + spec-hash pinning + idempotent re-runs
- [x] 11. Writes scoped to spec/report/sidecar, uncommitted, recoverable

## Out of scope (v1)

- `plan-review` for writing-plans output
- single-pass (non-loop) review mode
- reviewing arbitrary markdown documents outside `docs/superpowers/specs/`
- a hard token/cost ceiling (tracked as residual risk 4)

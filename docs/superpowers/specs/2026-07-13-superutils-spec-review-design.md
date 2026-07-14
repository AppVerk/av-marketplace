# superutils — `/superutils:spec-review` Design

**Date:** 2026-07-13
**Status:** Approved design, pre-implementation; revised by rounds 1–3 of a manual
spec-review loop run (see Revision history)
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

- **Input:** superpowers-produced specs only — `docs/superpowers/specs/*.md`
  (non-recursive; the `reviews/` subdirectory is never a candidate), assuming
  the brainstorming→design document shape. Path given as argument; an argument
  path that is not a `.md` file directly in `docs/superpowers/specs/` aborts
  with an out-of-scope error in all modes. With no argument, the newest file by
  modification time in `docs/superpowers/specs/` is used. No candidate file, or
  a tie for the newest mtime among candidates (byte-equal mtimes as reported
  by stat) → list and ask (interactive) or abort (`--auto`) — never guess.
- **One command:** `/superutils:spec-review`. Growth path (explicitly out of v1
  scope): `plan-review` for writing-plans output, a single-pass review mode.

## Plugin identity and structure

- **Name:** `superutils` — category `planning`, initial version `1.0.0`.
- **Marketplace description:** "Companion utilities for the superpowers workflow —
  loop-engineered verification of design specs."

```
plugins/superutils/
  .claude-plugin/plugin.json
  commands/spec-review.md        # loop orchestrator (pattern: /qa:loop)
  agents/spec-reviewer.md        # lens-parameterized reviewer
  agents/spec-challenger.md      # adversarial verifier of findings
  agents/spec-fixer.md           # proposes edit pairs for confirmed findings
  skills/lens-catalog/SKILL.md        # lens catalog + panel-selection rules
  skills/spec-report-format/SKILL.md  # report + sidecar format (named apart
                                      # from the shipped qa:report-format)
```

The lens catalog's roster and panel-selection rules are a deliverable of the
implementation plan (like agent prompts); this design fixes the lens system's
parameters (panel size 3–6, two core lenses, content-fit selection, per-round
composition logging) and the severity and needs-decision anchors below, not the
full roster.

Registration obligations (per repo rules): entry in
`.claude-plugin/marketplace.json`, row in the README Available Plugins table,
plugin-count badge bump, and `docs/plugins/superutils.md`.

## Architecture

Command-orchestrated loop (approach A): the main conversation drives rounds and
dispatches subagents. This is the only architecture compatible with the
needs-decision gate — only the main loop can ask the user questions mid-run.
Reviewer, challenger, and fixer are separate agents (actor/verifier separation);
the fixer proposes edits, the orchestrator applies them (see step 7).

## Loop algorithm

Round `r` on spec `S`:

1. **Decompose.** The orchestrator breaks `S` into review units — a review unit
   is a top-level (`##`) section of the spec. Decomposition is
   orchestrator-internal: it informs panel selection and is passed to reviewers
   as a reading guide; reviewers always receive the full spec. Decomposition
   uses the sequential-thinking MCP tool when available, otherwise the same
   structured decomposition inline. The orchestrator then selects the panel:
   3–6 lenses from the lens catalog. Two **core lenses are always on** —
   internal consistency and ambiguity/testability — the rest are chosen to fit
   the spec's content (e.g. a UI spec gets a UX lens, an API spec gets a
   contracts lens). Panel composition and the unit list are logged in the
   sidecar each round.
2. **MoA fan-out.** Exactly one reviewer agent per lens per round, dispatched in
   parallel. A reviewer returns findings as `{severity: critical|major|minor|nit,
   location, description, proposed fix, needs-decision?}` — reviewers do NOT
   compute fingerprints or SR ids.
   **Severity anchors** (shared by reviewers and challengers): **critical** =
   the spec self-contradicts or a compliant implementation would violate a
   stated invariant; **major** = two competent implementers would build
   observably different load-bearing behavior; **minor** = divergence with low
   blast radius; **nit** = wording/format only.
   **Needs-decision anchor:** flag needs-decision iff the fix requires choosing
   among materially different alternatives that the spec's own content cannot
   arbitrate (a decision, not a derivation), or the fix would reverse a
   recorded user decision or an explicitly stated requirement.
3. **Finding registry (orchestrator-owned identity).** The orchestrator
   maintains a finding registry in the sidecar: for each incoming finding it
   assigns an SR id (once per issue, in discovery order — within a round:
   panel order as logged in the sidecar, then each reviewer's own output
   order; reused whenever the issue reappears; a later run continues at
   max+1), anchors the location to the nearest enclosing `##` heading slug
   (GitHub-style: lowercase, spaces to hyphens, punctuation stripped;
   duplicate headings get `-2`, `-3` in document order), and **derives (without replacing
   the description)** a ≤10-word canonical issue phrase used only for identity —
   challengers and the fixer always receive the reviewer's original description
   and proposed fix. Anchor edge cases: content before the first `##` heading
   anchors to the reserved slug `__preamble__`; document-level or locationless
   findings anchor to the reserved slug `__document__`; a cross-section finding
   anchors to the first-cited section's slug with the other section named in
   the canonical phrase. The stored key is
   `sha256(heading-slug + "|" + canonical phrase)`. Matching is semantic, not
   byte-exact — **both within a round and across rounds**: two entries match
   when their heading slugs are equal and an orchestrator yes/no equivalence
   judgment on the two canonical phrases says so; every equivalence verdict is
   logged in the sidecar. Within-round duplicates collapse to one registry
   entry at the **maximum severity** among the merging findings; the entry's
   lens field records all contributing lenses. The no-progress and oscillation
   stops operate on registry identity and are therefore best-effort (the
   matching is itself soft — residual risk 5); the triple budget is the hard
   backstop.
4. **Quorum via challenger.** With disjoint lenses, "≥2 reviewers saw the same
   thing" is structurally unavailable within a round (only the completeness
   lens can see a completeness gap). Quorum is therefore **finder + independent
   challenger**: every major+ registry entry goes to an adversarial challenger
   whose job is to refute it — **one challenger dispatch per major registry
   entry** (not per raw finding); a merged entry's challenger receives all
   finder descriptions; each challenger sees only its assigned entry plus the
   spec. Registry entries carrying a recorded user decision are excluded from
   challenger dispatch — their significance is already settled. **Exception: an
   entry whose last fix attempt ended `fix-failed` is not settled.** It still
   skips the challenger (its significance was established when it was gated),
   but it re-enters the significant set and blocks convergence until the fix
   lands, is declined, or the run stops — otherwise a fix the loop committed to
   could be dropped silently while the run still reports success. The
   challenger returns exactly **uphold or refute at the finder's
   severity**; re-grading is out of scope for v1. A refutation must rest on
   textual evidence: an uncertain challenger upholds. **Significant = major+ AND
   survived refutation.** Critical entries get 2 independent challengers: both
   uphold → confirmed; both refute → dropped; split → escalated to the
   needs-decision gate. A split-verdict critical remains in the
   post-refutation significant set until its gate decision is recorded; if
   either of a critical entry's challengers fails to return after its retry,
   the entry is `unconfirmed` regardless of the other verdict. The finder does
   not vote on its own finding. This
   reuses the existing marketplace challenger pattern (code-review:challenger,
   web-auditor:challenger).
5. **Stop evaluation.** The pending-decisions, no-progress, and oscillation
   stops are evaluated here — after quorum, before the gate, in the stop
   precedence order — because re-applying fixes that demonstrably did not
   stick is the failure being detected. A stop-triggering round skips its gate
   and fix phases. On an oscillation, no-progress, or budget stop its
   significant findings receive outcome `confirmed (not fixed — stopped)`;
   skipped needs-decision entries always take `pending-decision`, including in
   the round that triggers `STOPPED(pending-decisions)`; the round's remaining
   minor/nit findings receive `reported-only`.
6. **Needs-decision gate.** Only challenger-surviving major+ entries flagged
   needs-decision (plus split-verdict criticals) are put to the user
   (AskUserQuestion in the main loop), with options: accept the proposed fix /
   supply an alternative / keep as is. Sub-major needs-decision findings are
   never asked; they get outcome `reported-only`. Accepted decisions join the
   current round's fix batch; keep-as-is decisions are recorded against the
   registry entry, excluded from the significant set from then on, and reported
   under **Accepted risks (user-decided)**. A registry entry with a recorded
   decision (keep-as-is, decline, or an accepted fix) is never re-asked, in-run
   or on resume. In `--auto`, needs-decision findings are skipped and reported
   — never auto-decided; skipped entries are excluded from the no-progress
   comparison set but block CONVERGED (see terminal statuses).
7. **Fix (two-phase: propose, then apply).** The fixer receives the round's fix
   batch — challenger-confirmed major+ entries, user-accepted needs-decision
   fixes, and minor/nit findings not flagged needs-decision (minor/nit are
   proposed without challenger confirmation) — and returns per-finding
   `{old, new}` edit pairs; **it performs no writes**. The orchestrator
   materializes the post-batch candidate in the session scratchpad (outside the
   repo, so the scoped-writes rule holds), computes the unified diff and the
   SR-id → hunk mapping, runs the interaction gate (below), and applies the
   approved pairs to the spec itself via Edit, re-stamping `last_written_hash`
   immediately after. Application is orchestrator tool work, not a dispatch.
   Findings whose edits overlap form an all-or-nothing group in approve-subset:
   two edit pairs overlap when their old-string target ranges intersect or
   when applying one changes the region the other's old string must match.
   Group application is atomic — if any edit in a group fails, the group's
   prior edits are reverted from the candidate and every finding in the group
   gets `fix-failed`. Per-finding outcomes: `applied` / `fix-failed`; the
   fixer's "done" is advisory.
8. **Verifier authority.** Convergence is decided solely by the **next round's
   fresh panel** on the updated spec: the loop converges when a fresh round
   yields zero significant findings (post-refutation; the convergence
   condition is evaluated before the gate, excluding entries user-decided in
   earlier rounds — **except entries carrying an unresolved `fix-failed`, which,
   like `unconfirmed`, block convergence**). A round whose effective fix batch is empty after its own
   gate (nothing will be applied) also completes convergence immediately — the
   spec is byte-identical to what the fresh panel just reviewed; if anything
   is applied, a subsequent fresh round is required. A converging round
   terminates **before its fix
   phase**: its minor/nit findings receive outcome `reported-only` and are not
   applied — a CONVERGED spec contains no edits that a fresh panel has not
   re-reviewed. The verdict is reported as **"Re-reviewed (advisory)"** — never
   "Verified" — because the oracle is soft.

### Interaction modes

- **Default (interactive, approve-before-apply):** after each round's gate, the
  round's full fix batch is presented as a **unified diff preview** (current
  spec vs the scratchpad candidate) with an SR-id → hunk mapping, behind a
  three-way gate: **approve** (apply the batch, continue) / **approve subset**
  (select findings to apply; the rest get outcome `declined`) / **decline &
  stop** (nothing is applied, the declined findings are recorded, terminate as
  `STOPPED(user-declined)`). A `declined` entry is a recorded user decision: it
  is excluded from the significant set and the no-progress comparison from then
  on, never re-proposed, and reported under **Declined (user-decided)**. A
  batch-gate decline of a fix accepted at the needs-decision gate supersedes
  that acceptance; the entry's recorded decision becomes declined.
- **`--no-approve`:** auto-apply without the gate; after each applied batch the
  same full unified diff (pre vs post, with the SR-id → hunk mapping) is
  printed, so the spec never changes invisibly. Needs-decision questions are
  still asked.
- **`--auto` (headless, explicit opt-in):** no interaction at all; implies
  `--no-approve`; needs-decision findings are skipped and reported.
- **Headless check (fail-fast):** at argument parse, before any I/O, if the
  session is non-interactive and the mode is default or `--no-approve`, abort
  with "interactive modes require an interactive session; use --auto". Session
  interactivity is model-judged and best-effort (there is no shell TTY probe —
  the Bash tool's stdin is never a TTY, so a literal `[ -t 0 ]` check would
  abort interactive sessions too; this mirrors /qa:loop's Step 0.1 guard). If
  interactivity cannot be positively established, treat the session as
  non-interactive and abort — the check fails closed. **Runtime backstop (the
  fail-closed element):** in default and `--no-approve` modes, any
  AskUserQuestion failure aborts immediately as `STOPPED(interaction-unavailable)`
  with the same message, before any fixer application in that round.

### Budgets and stop conditions

- **Dispatch definition:** a dispatch = one subagent launch (reviewer,
  challenger, or fixer); retries count as dispatches; orchestrator tool calls
  (including fix application) are excluded.
- **Triple gate:** `--max-iterations` (default 3), `--max-dispatches`
  (default 30 — doubles as the soft cost ceiling for this model-heavy loop, per
  the loop-engineering rider), `--time-budget` (default 30 min). Budgets are
  enforced at **stage boundaries** within each round — before the review
  fan-out, before the challenger fan-out, and before the fixer dispatch: if the
  remaining dispatch budget cannot cover the next stage's worst case including
  retries (2 × the stage's planned dispatches), or elapsed active time
  exceeds the time budget, the loop stops as `STOPPED(budget)` at that
  boundary. Rounds are never cut **within** a dispatch phase. Major+ entries
  whose challengers were never dispatched at a budget stop receive outcome
  `unconfirmed` — they block convergence and are never treated as refuted.
- **Time accounting:** elapsed time excludes intervals spent awaiting a user
  response at a gate or question; the sidecar accumulates active elapsed time
  and resume continues from the stored value.
- **Iteration definition:** an iteration = one full round (review → registry →
  quorum → stop evaluation → gate → fix). A zero-significant-findings round
  terminates as CONVERGED (before its fix phase) and still counts. Fixes
  applied in the final permitted round are reported as
  `applied (not re-reviewed)` under `STOPPED(budget)`.
- **No-progress stop:** an identical significant-finding set in two
  consecutive rounds. The comparison set for each of the two rounds is
  computed at evaluation time: that round's post-refutation significant
  entries (by registry identity) minus every entry carrying a recorded user
  decision or `--auto` skip as of the current evaluation — decisions filter
  retroactively into the previous round's set. An empty comparison set never
  triggers no-progress.
- **Oscillation stop:** a registry entry fixed in round `r−2` reappears in
  round `r`'s post-refutation significant set. Reappearance at sub-major
  severity is logged in the report but does not trigger the stop.
- **Stop precedence**, evaluated in order: pending-decisions → oscillation →
  no-progress → budget. `STOPPED(pending-decisions)` fires in the first round
  whose post-refutation significant set is non-empty but consists entirely of
  skipped needs-decision entries.
- **Terminal statuses:** `CONVERGED`, `CONVERGED (low-confidence)` (see
  Report/coverage), and `STOPPED(budget | no-progress | oscillation |
  pending-decisions | user-declined | interaction-unavailable | external-edit)`.
  A stop is never reported as success.

### State and writes

- **Sidecar:** `docs/superpowers/specs/reviews/<spec>-review.state.json`,
  written after every round and after every fix application. Fields:
  `spec_path`, `last_written_hash` (sha256 of the spec as last written by the
  loop, **re-stamped immediately after every loop write to the spec**, and at
  initial pin), `status`, run counter, iteration/dispatch/active-time counters,
  `decisions` (SR id → {decision: accepted | keep-as-is | declined; edit: the
  {old, new} pair for accepted decisions, preserving user-supplied
  alternatives}), and
  `rounds[]` (panel composition, unit list, findings with SR id / severity /
  lenses / outcome, each reviewer's self-falsified `rejected` list verbatim,
  equivalence verdicts). Severity and lenses are recorded **per round**, not
  back-filled from the registry, which holds only the current values. The
  `rejected` lists are rendered in the report: a fresh panel re-derives the same
  ghosts every round, so discarding them is the silent drop reviewers are
  themselves forbidden to perform. The fixer write → re-stamp window is
  non-atomic; a crash inside it surfaces as a hash mismatch on resume and is
  handled by the tamper flow below.
- **Tamper detection:** the orchestrator re-hashes the spec at round start and
  immediately before each fix application; a mismatch against
  `last_written_hash` means the spec changed outside the loop. Interactive: ask
  with two options — **adopt** (re-pin `last_written_hash` to the current
  content and continue; registry entries whose heading slug no longer exists
  are marked stale and excluded from matching) or **stop** (terminate as
  `STOPPED(external-edit)`). `--auto`: abort as `STOPPED(external-edit)`.
- **Idempotent re-runs / resume:** (a) terminal status + hash match → report
  the existing outcome and exit without dispatching. (b) in-progress sidecar →
  resume at the next round with counters **continued, not reset**, and recorded
  decisions replayed without re-asking. (c) terminal status + hash mismatch →
  **a new run**: the sidecar's `rounds[]` and the report are archived to
  `.bak` under the incremented run counter, the pre-loop snapshot is retaken,
  and the report is rewritten; SR-id assignment continues at max+1; the
  `decisions` map is **carried forward keyed by registry identity**, each
  carried decision revalidated (its heading slug must still exist — stale ones
  are dropped with a note in the report) and replayed without re-asking.
- **Pre-run guard (reused from /qa:loop Step 0.1.5, Working-Tree Safety Gate):**
  if the spec file has uncommitted changes or is untracked at run start,
  `--auto` aborts unless `--allow-dirty`; interactive modes warn and confirm.
  Before the first fix application of a run, the spec is snapshotted to the
  sidecar directory (`<spec>.pre-loop.bak`) — **at most once per run**: a
  resume never overwrites the snapshot; a new run (case c) retakes it.
- **Scoped, recoverable writes:** inside the repo, the loop touches only the
  spec file, the report, and the sidecar directory (sidecar + snapshot +
  archives); the diff candidate lives in the session scratchpad outside the
  repo; nothing is committed. Recovery guidance always points at the snapshot —
  never `git restore` on the spec, which would also destroy the user's own
  pre-loop edits. On any stop or abort, the report lists the loop-touched files
  and the recovery instruction.

## Report

Written to `docs/superpowers/specs/reviews/<spec>-review.md`:

- round-by-round trace: panel composition, findings with `SR-XXX` ids and
  outcomes. **Outcome enum:** `applied`, `applied (not re-reviewed)`,
  `fix-failed` (pair did not match; blocks convergence, is re-batched next
  round with a **re-derived** pair — never a replay of the pair that already
  failed — and is not settled by any user decision it carries),
  `refuted`, `unconfirmed` (challenger unavailable — failed twice
  or never dispatched at a budget stop; blocks convergence, never treated as
  refuted, excluded from the no-progress comparison), `confirmed (not fixed —
  stopped)` (significant findings of any round that ends before or during its
  fix phase — oscillation, no-progress, budget, interaction-unavailable, or
  external-edit), `reported-only` (sub-major needs-decision findings,
  and any minor/nit finding of a round that terminates before its fix phase —
  converging, stop-triggering, or aborted), `accepted-risk` (user keep-as-is),
  `pending-decision`
  (`--auto` skip), `declined` (user-declined at the batch gate). Every finding
  emitted by any reviewer appears in the trace with exactly one outcome —
  refuted findings are listed, never silently dropped.
- a **Coverage** block with three labelled sublists: (a) catalog lenses not
  selected this run, (b) lenses that failed to return, with reasons, (c) the
  standing oracle blind spots. A reviewer that fails to return is retried once;
  if it still fails, its lens is listed under (b), the round proceeds, the
  report carries a **shallow-coverage WARNING**, and a converged run is
  labelled `CONVERGED (low-confidence)`. A challenger that fails to return is
  retried once; a finding whose challenger never returns is `unconfirmed`.
- terminal status, the **Accepted risks (user-decided)** and **Declined
  (user-decided)** sections, and the residual-risk list.

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
5. **Registry matching is soft:** cross-round issue identity rests on an
   orchestrator equivalence judgment (logged but LLM-made), so the no-progress
   and oscillation stops are best-effort; the budgets are the hard backstop.
6. **Headless detection is best-effort:** session interactivity is
   model-judged; the fail-closed element is the runtime AskUserQuestion
   backstop, not the parse-time judgment.

## Verifying the plugin itself

- A fixture spec with seeded defects (a contradiction, a phantom section, an
  ambiguous requirement). **Acceptance:** run the fixture in the default
  interactive mode with a scripted **accept** for every needs-decision prompt
  and a scripted approve (full batch) for each batch-approve gate; pass = each
  seed's post-run content predicate holds on the final fixture file
  (contradiction seed: the two sentences no longer conflict; phantom-section
  seed: the dangling reference is removed or its target exists; ambiguity
  seed: exactly one behavior is derivable) and terminal status `CONVERGED`
  within default budgets, in at least 2 of 3 runs. A keep-as-is outcome on a
  seeded defect does not count as resolved — the fixture demonstrates fixing,
  not just termination. Each run starts
  from a fresh copy of the seeded fixture with no sidecar, report, or snapshot
  present. (Open verification-harness question, reported by the round-2
  feasibility lens: the platform has no native way to script AskUserQuestion
  answers — the implementation plan must pick a harness, e.g. Agent SDK
  `canUseTool` auto-responder, or redesign the fixture to run under `--auto`.)
- The `qa:loop-engineering` review checklist applied to the shipped command.
- Dogfooding: this design document is the loop's first real target. **Pass
  condition:** the dogfood run terminates with a valid terminal status within
  default budgets and produces a report and sidecar conforming to the
  spec-report-format skill. The dogfood run is isolated to a scratch branch —
  the loop edits its target in place, and this document is a committed contract.

## Loop-engineering compliance checklist

**Universal**
- [x] 1. Oracle named, blind spots stated (Oracle statement section)
- [x] 2. Verifier authority separated; fresh-panel gating, fixer verdict
      advisory, finder excluded from the challenger vote
- [x] 3. Coverage disclosed (three-sublist Coverage block; shallow-coverage
      WARNING + low-confidence CONVERGED label), never gated
- [x] 4. Human gate by default (approve-before-apply with full diff preview);
      headless only via `--auto`; parse-time headless check is best-effort,
      the AskUserQuestion runtime backstop is the fail-closed element
- [x] 5. Fail-closed guards reused, not reinvented (ambiguous input → ask/abort;
      tamper re-hash → adopt-or-stop; /qa:loop Step 0.1.5 Working-Tree Safety
      Gate + `--allow-dirty`)
- [x] 6. Hard budgets: iterations ∧ dispatches ∧ time, enforced at stage
      boundaries within each round; never cut within a dispatch phase;
      overflow findings disclosed as `unconfirmed`
  - [~] 6-rider: **partial** — the dispatch cap is a cost proxy only; no
        hard token ceiling (residual risk 4)
- [x] 7. No-progress and oscillation stops on registry identity, evaluated
      post-quorum with a defined orphan outcome (best-effort, budgets as
      backstop — residual risk 5); `STOPPED ≠ CONVERGED`
- [x] 8. Residual-risk list documented (6 items)

**Conditional** (all triggered: the loop persists state, mutates the spec, auto-corrects)
- [x] 9. Provenance guard: major+ findings enter fixing only after challenger
      confirmation, needs-decision findings are never auto-decided (anchored
      criterion); minor/nit fixes are proposed unconfirmed but are diff-visible
      and covered by the default batch-approve gate
- [x] 10. Durable sidecar + spec-hash tracking re-stamped after each loop
      write + idempotent re-runs (report / resume / new-run re-baseline) with
      recorded-decision replay and revalidated carry-forward
- [x] 11. Writes scoped to spec/report/sidecar-dir, uncommitted; diff candidate
      outside the repo; recovery via pre-loop snapshot, never `git restore`
      on the spec

## Out of scope (v1)

- `plan-review` for writing-plans output
- single-pass (non-loop) review mode
- reviewing arbitrary markdown documents outside `docs/superpowers/specs/`
- a hard token/cost ceiling (tracked as residual risk 4)
- challenger re-grading of finding severity (uphold/refute only in v1)

## Revision history

- **2026-07-13, round 1 of the manual dogfood loop** (5-lens panel: internal
  consistency, ambiguity/testability, doctrine compliance, implementer
  completeness, platform feasibility; 7 challenger dispatches): applied 3
  critical clusters (orchestrator-owned finding registry replacing byte-hash
  fingerprints; sidecar hash re-stamping + resume semantics; needs-decision
  convergence exclusions with `STOPPED(pending-decisions)`), 7 major clusters
  (default flipped to approve-before-apply per user decision; dirty/untracked
  pre-run guard + snapshot recovery; challenger verdict vocabulary; review-unit
  definition; pinned diff-preview content; three-way approve gate +
  `STOPPED(user-declined)`; minor/nit fate per user decision), and the minor
  batch. Challenger-refuted, not applied: mode/TTY contradiction,
  provenance-guard non-conformance, lens catalog as design gap, fixture
  acceptance untestable (its one-sentence kernel was applied as a minor).
- **2026-07-13, round 2** (same 5-lens fresh panel; 3 challenger dispatches,
  all upheld): applied 1 critical cluster with 5/5 cross-lens quorum
  (stage-boundary budget enforcement replacing the uncomputable round-start
  worst-case, per user decision) and majors: two-phase fixer
  (propose-then-apply with a scratchpad candidate and overlapping-edit
  grouping); within-round registry dedup with per-entry challengers; anchor
  edge cases (`__preamble__`, `__document__`, cross-section rule); anchored
  needs-decision criterion; stop evaluation point + `confirmed (not fixed —
  stopped)`; strict convergence (terminal-round minors `reported-only`, per
  user decision); new-run re-baseline with revalidated decision carry-forward
  (per user decision); sticky `declined` (per user decision); snapshot
  taken at most once per run; plus the minor batch (`unconfirmed` in the
  outcome enum, time accounting, stop precedence, headless fail-closed
  tie-break + runtime backstop, coverage third sublist, citation fix).
  Challenger-refuted, not applied: unconfirmed minor/nit application in
  `--auto` vs bar item 9 (the needs-decision anchor already excludes suspect
  findings at every severity, stricter than the reference's T3 guard;
  derivable minors follow the reference's own headless fix path).
- **2026-07-13, round 3 (final; loop terminated `STOPPED(budget)`).** Shallow
  coverage: only the two core lenses returned (doctrine and completeness
  reviewers died on a session limit; the feasibility launch failed on model
  availability) — shallow-coverage WARNING per the loop's own rules; the
  challenger stage could not be dispatched (session limit + remaining dispatch
  budget), so single-lens findings ended `unconfirmed` and the iteration cap
  closed the run. Post-loop, under the user's explicit batch approval (the
  user gate outranks a challenger): applied the cross-lens-quorum critical
  (outcome-enum totality — `reported-only` widened to any round ending before
  its fix phase) and the unconfirmed majors R3-2 (pending-decision precedence
  in stop evaluation), R3-3 (split-critical stays significant until decided),
  R3-4 (retroactive decision filtering of the no-progress comparison), plus
  the minor batch (decline supersedes accept; decision edits stored for
  replay; marketplace description narrowed to specs; retry headroom in stage
  checks; critical-challenger-failure rule; decided entries skip challenger;
  overlap definition + atomic groups; SR ordering; slug rule; mtime
  granularity). User-decided: empty-batch immediate convergence (R3-5);
  fixture content predicates with scripted accept, keep-as-is ≠ resolved
  (R3-6).

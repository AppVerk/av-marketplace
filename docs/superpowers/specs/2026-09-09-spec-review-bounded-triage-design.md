# Spec review as bounded triage — design

**Status:** approved in brainstorming, 2026-09-09
**Plugin:** superutils (1.0.2 → 2.0.0)
**Companion:** sub-project B (lightweight in-flight code review) is designed separately; the
pipeline designed here is dogfooded on sub-project B's spec (§11).

## 1. Goal

Replace the convergence-seeking `/superutils:spec-review` loop with a fixed five-stage
pipeline that catches and fixes the load-bearing defects of a design spec in one pass,
at a predictable cost of roughly 8–12 subagent dispatches, and at most one question per
needs-decision finding plus one approve gate per batch, and reports everything it did
not fix as residuals. "Done" no longer means "a fresh panel finds no major"; it means
"the pipeline ran to the end and every fix it batched landed".

## 2. Why (measured, not felt)

Three historical runs, read from the sidecars committed in git history:

| Run | Rounds | Dispatches | Challengers → refutations | Spec lines | Terminal |
|---|---|---|---|---|---|
| workflow-docs (`893e183`) | 1 | 4 | 0 → 0 | unchanged | CONVERGED |
| agent-tools (`c22cbbd`) | 10 | 72 | 13 → 0 in round 1 | 286 → 769 | CONVERGED |
| needs-decision (`2f60dd3`) | 6 | 141 | 110 → 7 | 310 → 1430 | STOPPED(budget) |

What the numbers say:

1. **In the needs-decision run, challengers were 78% of dispatches; across the runs the
   table can measure, 7 refutations came from 123 challenger dispatches, a 6% rate.**
   Round 1 of both large runs upheld 28 of 28. Reviewers already self-falsify; the
   challenger duplicated a filter that rarely filtered.
2. **No registry entry was ever re-found in a later round** (0 of 162). Each round found
   only new defects, and the round notes trace most of them to the seams of the previous
   fix batch: 20–35 local edits applied by a fixer forbidden to touch anything else.
3. **60% of findings were graded major** (98 of 162), so nearly every finding drew a
   challenger and entered the batch. The anchor "two implementers would build differently"
   fits almost any prose.

The loop did not converge because its convergence criterion is close to unreachable for a
prose document that grows every round, not because the budget was too small. Raising the
budget (done twice in the needs-decision run) bought more of the same.

## 3. Decisions taken

| Question | Decision |
|---|---|
| What does "done" mean? | Bounded triage: one panel, one fix batch, one verification of the edits, a second approve-gated batch. No fresh-panel convergence. |
| Challengers | Criticals only, one per finding. Majors go to the batch on panel argument plus self-falsification. |
| Reviewer model | Opus, unchanged. Savings come from the pipeline shape, not the model. |
| Relationship to the current command | Replace in place. No flag, no second command. Breaking change → superutils 2.0.0. |

## 4. Pipeline

```
0 resolve & gates → 1 panel → 2 critical challengers → 3 batch A → 4 verify edits → 3' batch B → 5 report
```

Nothing repeats. Stages 3 and 3' run the same **batch procedure** (§5) on different inputs.

### Stage 0 — resolve and gate

Unchanged rules from the current command, minus the iteration flag:

| Argument | Meaning | Default | Rules |
|---|---|---|---|
| (empty) | Newest `.md` by mtime in `docs/superpowers/specs/` (non-recursive, `reviews/` excluded) | — | No candidate or an mtime tie → list and ask (interactive) / abort (`--auto`); never guess |
| `<path>` | Target spec | — | Must be a `.md` directly in `docs/superpowers/specs/`; otherwise out-of-scope error in all modes |
| `--no-approve` | Skip the approve gate; apply and print the full diff | off | Needs-decision questions still asked |
| `--auto` | Headless; implies `--no-approve` | off | Needs-decision entries skipped → `pending-decision`; unchanged-spec re-run exits |
| `--allow-dirty` | Bypass the working-tree gate | off | |
| `--max-dispatches` | Subagent-launch cap, retries included | 20 | Positive integer, else error and stop |
| `--time-budget` | Active seconds, user waits excluded | 900 | Positive integer, else error and stop |

`--max-iterations` is removed; passing it is a validation error like any unknown flag.
All flags are validated before any I/O. The headless check, the working-tree gate
(`git status --porcelain -- "$spec_path"`), and the `AskUserQuestion` backstop
(`STOPPED(interaction-unavailable)` before any write of the pending batch) are carried
over verbatim.

Paths: `report_path = docs/superpowers/specs/reviews/<spec>-review.md`,
`snapshot_path = docs/superpowers/specs/reviews/<spec>.pre-loop.bak`. No sidecar.

**Re-run detection.** If `report_path` exists, read its `post-loop` hash line. A report
with no readable `post-loop` hash line (a pre-2.0.0 report, or one truncated by an
interrupted run) is treated exactly as a report whose hash differs: archive it and start
fresh. A `<spec>-review.state.json` beside it is a pre-2.0.0 sidecar: archive it
alongside the report and never read it. Equal to the current spec hash → the spec has
not changed since the last triage: interactive
asks *re-run / exit*; `--auto` prints the prior status and exits. A re-run, or a report
whose hash differs, archives the existing report to
`<spec>-review.run<N>.bak` (`N` = 1 + the number of such archives present) and starts
fresh: SR ids restart at 1 — there is no registry to continue.

**Snapshot rule.** Copy the spec to `snapshot_path` before the first `Edit` of the run,
at most once per run, overwriting a snapshot from an earlier run (git holds the
committed history; the snapshot is this run's recovery point).

### Stage 1 — panel

Decompose the spec into its `##` headings (sequential-thinking tool when available,
inline otherwise). Select lenses per the catalog: both core lenses; `completeness`
unless the spec has fewer than three sections; content triggers; floor at 3; **no cap**
— every lens the rules name is dispatched, and the roster (seven lenses) is the ceiling.
The needs-decision run dropped `ux` for five rounds under the old cap of six and paid
four defects only that lens could see.

Dispatch one `superutils:spec-reviewer` per lens in parallel (prompt: lens id and
mandate, spec path, unit list). A reviewer that fails or returns unparseable JSON is
retried once; still failing → its lens is listed under Coverage as "not returned", a
WARNING is printed, and the run ends `TRIAGED (incomplete)` unless it stops earlier.

Registry (in orchestrator context, written to the report): anchor slug per the report
format skill, canonical phrase, within-panel duplicate matching (slug equality plus a
logged equivalence judgment), merge at maximum severity recording all lenses, SR ids in
discovery order (panel order as logged, then each reviewer's output order). Every
reviewer's `rejected` list is recorded verbatim.

### Stage 2 — critical challengers

One `superutils:spec-challenger` per critical finding, in parallel (prompt: the entry
with every finder's description and proposed fix, plus the spec path). `refute` →
outcome `refuted`, the entry leaves the batch. `uphold` → stays critical. A challenger
that fails twice leaves the entry **upheld** with the note "challenger not returned" in
the report — uncertainty never refutes. Majors receive no challenger.

### Stage 3 — batch A

Input: every surviving critical and every major. Minors and nits go straight to the
report as `reported-only`. Empty input (no surviving critical and no major) → Stage 4 is
skipped and batch B is empty, so the run goes to the report. Run the batch procedure
(§5); a landed edit takes outcome `applied`.

### Stage 4 — verify the edits

Skipped when batch A applied nothing; batch B's input is then batch A's `fix-failed`
entries with `re-derive`, and nothing else.

Write two files to the session scratchpad: the unified diff of batch A (spec before →
after) and the SR list of batch A — the SRs whose edits landed, never a declined,
fix-failed or accepted-risk entry — (id, severity and description only — the reviewer's
`proposed_fix` and the fixer's pairs are withheld, so the verifier judges whether the
defect is resolved rather than whether the edit matches a suggestion the fixer also
held; the applied text is visible in the diff). Dispatch one `superutils:spec-reviewer`
with lens `fix-coherence` and
both paths in addition to the spec path. Its mandate (§6, lens catalog):

- per SR of batch A: judged against the SR description alone, does the spec as edited
  still exhibit the defect → `resolved: true|false` with a reason. The verifier never
  holds the proposed fix, so how the edit was made is never a ground for `false` — an
  edit that removes the defect by any means is `resolved: true`.
- do the edits, read against the whole spec, introduce a contradiction, an ambiguity,
  or a dangling reference that was not there before → findings tagged
  `fix_induced: true`, each naming the SR ids whose edits introduced it.

`resolved` must carry exactly one entry per landed SR of batch A. The orchestrator
checks the id set; a batch A SR missing from it is treated as unresolved (fail closed —
uncertainty never resolves), enters batch B marked `re-fix`, and the omission is noted
under Coverage.

Fix-induced findings receive the next SR ids. The verifier's `rejected` list is recorded
verbatim alongside the panel's, labelled with the `fix-coherence` lens id. The verifier
failing twice → batch B is batch A's `fix-failed` entries only, every applied edit of
batch A takes `applied (not re-reviewed)`, and the run ends `TRIAGED (incomplete)`.

### Stage 3' — batch B

Input: SRs the verifier marked unresolved (marked `re-fix`: the batch A edit landed,
`old` targets the applied text, and the fix must change it), fix-induced findings of
severity major or critical (no challenger — one pass), and batch A's `fix-failed`
entries (marked `re-derive`). Fix-induced minors and nits → `reported-only`. Empty input
→ skip to the report. A user-decided entry marked `re-fix` is a new decision: the fixer
may depart from the decided `new` text; in default mode the approve gate shows the
departure, in `--no-approve` the entry is re-asked as a needs-decision question before
the fixer runs. A landed edit takes `applied (not re-reviewed)` — no further
verification follows. A `fix-failed` here stays `fix-failed` and makes the run
`TRIAGED (incomplete)`.

### Stage 5 — report

Terminal status, then the report per §9. Print: the status with its reason in
parentheses when incomplete (e.g. `TRIAGED (incomplete: fix-coherence verifier not
returned)`); a one-line outcome summary `N residuals (X confirmed-not-fixed, Y
fix-failed, Z pending-decision)`; the one-line cost summary (dispatches, active seconds,
spec line delta); the report path; and the verdict label: `Re-reviewed (advisory)` when
the batch A verifier returned, `Not re-reviewed (verifier not returned)` when it did
not, in either case followed by `K edits applied without re-review` when any
`applied (not re-reviewed)` entry exists.

## 5. The batch procedure

Used by stages 3 and 3'. Input: a list of SR entries, some marked `re-derive` or
`re-fix`.

**Empty batch.** If the input is empty, or step 1 leaves it empty, record no outcomes
and return — the fixer is never dispatched with an empty batch.

1. **Needs-decision gate.** For every major+ entry flagged `needs_decision` that has no
   recorded decision yet: `AskUserQuestion`, up to four entries per call, each with
   *accept the proposed fix / supply an alternative / keep as is*. `accept` and
   `alternative` store the exact edit content
   with the entry; `keep as is` → outcome `accepted-risk`, entry leaves the batch.
   `--auto` → `pending-decision`, entry leaves the batch. A decision recorded in batch A
   is not re-asked in batch B for a `re-derive` entry (the decided `new` text is
   preserved); a `re-fix` entry is a new decision (Stage 3').
2. **Stage budget check** (§7), then dispatch `superutils:spec-fixer` with the batch and
   the spec path. Every `re-derive` or `re-fix` entry carries why the previous attempt
   failed: a `re-fix` entry carries the verifier's `reason` and the batch A `new` text
   now standing in the spec; a pair-mismatch `re-derive` entry carries the `old` text
   that failed to match; an entry from a double fixer failure carries no prior pair.
   Decided edit content is passed verbatim, except as SR `re-fix` rules allow (§4
   Stage 3'). Fixer failure → one retry; a second failure → every entry in the batch
   `fix-failed`, skip to step 8.
3. **Re-hash** the spec; mismatch against the last hash the loop wrote or read → tamper
   flow (§7).
4. **Materialize the candidate** in the session scratchpad: copy the spec, apply every
   pair. A pair whose `old` does not match uniquely, or an entry no returned pair lists
   in its `sr_ids`, → `fix-failed`. Overlapping pairs (intersecting ranges, or one edit
   changing text another must match) form an atomic group: all land or all fail, with
   earlier members reverted from the candidate on failure.
5. **Zero hunks** → nothing to approve; skip the gate (never ask an empty question), go
   to step 8.
6. **Diff and gate.** Compute the unified diff, the SR → hunk mapping, and the growth
   line `+N lines (+P%)`, where N is the candidate's measured net line delta against the
   spec as it stood before this batch and P is N over that pre-batch line count, rounded
   to a whole percent; the fixer's `growth.net_lines` is advisory — when it differs from
   N, show N followed by `(fixer reported +M)`; a discrepancy is disclosed, never a
   failure. Under the diff, list `growth.drivers` as `largest: SR-… (+K lines)`.
   Default mode: show the diff and the growth line, then *approve all / approve a subset
   / decline and stop*. Subset selection is by atomic group (a group renders as one
   hunk; half of it is never offered), `AskUserQuestion` with `multiSelect`, four
   groups per page until every group has been shown, each option labelled with its SR
   ids, the highest severity in the group, each finding's canonical phrase, and the
   group's net line delta. Deselected groups → `declined`; deselecting every group is a decline of
   the whole batch → `STOPPED(user-declined)`, exactly as the explicit third option.
   `--no-approve` / `--auto`: no gate — every group counts as approved; step 7 applies,
   then print the same diff. In batch B the gate prompt states "these edits are applied
   without further verification" above the diff.
7. **Re-hash** (the gate is an unbounded human wait; this check guards the write), then
   take the snapshot if not yet taken, then apply approved pairs to the spec with
   `Edit`. Outcome per landed SR: `applied` in batch A, `applied (not re-reviewed)` in
   batch B. Record the new hash.
8. **Record outcomes** for every entry of the batch; return to the pipeline.

## 6. Components

### `commands/spec-review.md` — rewritten (≈320 lines: the whole contract, tables included)

Frontmatter: `argument-hint` loses `--max-iterations`, and `description` is rewritten to
the triage shape (lens panel → critical challengers → fix batch → verification of the
edits → final batch). Body: flag table,
Stage 0, stages 1–5 once each, the batch procedure once, the budget rule, the error
table, terminalization. Everything about rounds, registry carry-over, `unlanded`,
`unconfirmed`, `fix_failures`, no-progress, oscillation, resume, and `obsolete` is
deleted.

### `agents/spec-reviewer.md` — small change

Input gains an optional fourth item, present only for the `fix-coherence` lens: the
batch diff file and the SR list file (both scratchpad paths, outside the repo, so the
"never read `reviews/**`" rule is untouched and stays). The output shape for that lens
is the verifier shape (§9). One rule gains a `fix-coherence` exception: the verifier
echoes the SR ids it is given (it still never derives them). The report-format skill's
line "Reviewers never emit SR ids or fingerprints" becomes "Panel reviewers never emit
SR ids or fingerprints; the fix-coherence verifier echoes only the ids it was given."

### `agents/spec-challenger.md` — description only

The description states that dispatch is per critical finding. Rules and output are
unchanged.

### `agents/spec-fixer.md` — new mandate

Three additions and one removal:

- **Batch coherence.** The batch is one edit set, not a sum of independent patches.
  Two findings touching one passage yield one pair. Read the whole spec before
  proposing, and check that new text does not contradict neighbouring sections. A merged
  pair lists every SR it resolves in `sr_ids`.
- **Rewrite before append.** The default form of a fix is a change to an existing
  sentence or paragraph. Adding a new paragraph is reserved for findings about missing
  content (a `completeness` finding, or a decided edit that supplies new text).
- **Growth accounting.** Report `growth: {"net_lines": N, "drivers": ["SR-…"]}` — the
  net line delta of the batch and the SR ids whose pairs account for most of it. A
  metric shown at the gate, not a limit.
- `obsolete` is removed from the output; `re-derive` handling stays as it is (the pair
  never landed; re-derive against the current text, preserving decided `new` text). New
  marker `re-fix`: the pair landed and the verifier judged the defect unresolved; `old`
  targets the applied text and the fix must change it — for a user-decided entry the
  decided text may be departed from (Stage 3').

### `skills/lens-catalog/SKILL.md`

- Panel selection: rule 5 ("cap at 6") replaced by "no cap; the roster is the
  ceiling; log the selected ids and rationale".
- New lens **`fix-coherence`** — verification only, never selected for a panel.
  Mandate as in Stage 4. It judges resolution against the SR description, never against
  a proposed fix. Out of mandate: any defect the batch did not touch.
- Severity anchor **major** tightened: "two competent implementers would build
  observably different load-bearing behaviour, **and the spec's own text does not
  arbitrate between the readings**. When another passage settles it, the defect is a
  cross-reference gap: minor."
- The doctrine bar copy is untouched (it mirrors `qa:loop-engineering`).

### `skills/spec-report-format/SKILL.md`

Removed: sidecar schema, resume rules, the unfinished-work section, `obsolete`,
`unconfirmed`, `fix_failures`. Kept: reviewer, challenger, and fixer output shapes
(fixer: `growth` added, `obsolete` dropped), the anchor-slug rules and the canonical
phrase; the SR-id rule is rewritten to single-run form — ids are assigned in discovery
order within the one panel and never reused across runs (each run restarts at SR-001),
duplicate matching is within-panel only (slug equality plus a logged equivalence
judgment), and the `sha256(slug|phrase)` stored key and all cross-round and cross-run
reuse language are removed with the sidecar. Added: the
verifier shape, the report header with hashes, the new outcome enum, statuses, and
skeleton (§9). The frontmatter `description` drops "sidecar schema" and names the
verifier shape.

### `tests/ACCEPTANCE.md`

Pass condition becomes `TRIAGED` within default budgets plus the same three seed
predicates; "at least 2 of 3 runs" and the dogfood section stay. The fixture is
unchanged. The dogfood pass condition becomes "a valid terminal status within default
budgets and a report conforming to `superutils:spec-report-format`"; both the
procedure's precondition and the dogfood section drop every mention of the sidecar.

No new agent, no new skill.

## 7. Budgets and error handling

**Budgets.** Two hard limits: `--max-dispatches` (20) and `--time-budget` (900 s).
At every stage boundary: `dispatches_used + 2 × planned ≤ max_dispatches` and active
time under budget, or stop as `STOPPED(budget)` — never inside a dispatch phase.
Iterations are bounded by the pipeline's shape; there is no iteration flag.

**Tamper flow.** Hash before each apply (procedure steps 3 and 7). Mismatch →
interactive: *adopt* (re-pin) or *stop* (`STOPPED(external-edit)`); `--auto` → abort
as `STOPPED(external-edit)`.

**Outcomes at a stop.** At any stop — budget, user-declined, interaction-unavailable,
external-edit — every entry whose outcome is not yet final takes the one its state
implies: a major+ entry never batched, or in a batch whose fixer or gate did not
complete → `confirmed (not fixed — stopped)`; a batch A edit already applied when the
stop lands before Stage 4 → `applied (not re-reviewed)`; a batch A entry the verifier
marked unresolved whose batch B pass never ran → `confirmed (not fixed — stopped)`,
superseding its batch A `applied`, and its Residuals line states that an edit for it did
land — the spec was changed, the defect was not resolved. Outcomes the pipeline already
assigned stand: minors and nits are `reported-only` (Stage 3), deselected groups
`declined` (§5 step 6), `--auto`-skipped needs-decision entries `pending-decision`
(§5 step 1).

| Event | Handling |
|---|---|
| Reviewer fails twice | Lens → Coverage "not returned"; WARNING; run ends `TRIAGED (incomplete)` |
| Challenger fails twice | Critical stays upheld with a report note; never refuted |
| Fixer fails twice | Whole batch `fix-failed`; batch A → re-derived in batch B; batch B → residuals, `TRIAGED (incomplete)` |
| Pair mismatch / no pair | That SR `fix-failed`; batch A → batch B with `re-derive`; batch B → residual |
| Verifier fails twice | Batch B = batch A's `fix-failed` only; batch A edits → `applied (not re-reviewed)`; `TRIAGED (incomplete)` |
| Hash mismatch before a write | Tamper flow |
| `AskUserQuestion` fails (interactive modes) | `STOPPED(interaction-unavailable)` before any write of the current batch; an earlier batch's edits stay, the snapshot recovers them |
| Whole batch declined | `STOPPED(user-declined)`; nothing from that batch applied; an earlier batch's edits stay, the snapshot recovers them |
| Budget stop, or any other stop (user-declined, interaction-unavailable, external-edit) | Outcomes per **Outcomes at a stop** above |
| User abort (Esc) | Partial report; changes uncommitted; recovery = snapshot |

## 8. Doctrine compliance (`qa:loop-engineering`)

The pipeline meets the bar differently from the old loop, and both the report's
residual-risk section and `docs/plugins/superutils.md` state it:

| Item | Status |
|---|---|
| 1 oracle named, limits stated | Met — soft oracle (panel + critical challengers + verifier), "Re-reviewed (advisory)" |
| 2 verifier separate from actor | Met — the verifier is a fresh dispatch that sees the diff, the spec, and each SR's severity and description; it never receives the proposed fix, the fixer's pairs, or any fixer narration, so the actor cannot see or game the check |
| 3 disclose, don't gate, on coverage | Met — `TRIAGED (incomplete)` plus WARNING, never a red flip |
| 4 human gate, fail-closed TTY | **Not met** (disclosed, unchanged from today) — no shell TTY probe exists, so interactivity is judged heuristically; the design fails closed instead: interactive modes that cannot positively establish interactivity abort, and an `AskUserQuestion` failure stops the run as `STOPPED(interaction-unavailable)` before any write of the pending batch. The bar admits no partial grade; the gap is carried in §10 and in `docs/plugins/superutils.md` "Honest limits" |
| 5 reuse fail-closed guards | Met — working-tree gate, tamper flow, out-of-scope path error |
| 6 hard budgets | Met — dispatches and time by flag; iterations by construction |
| 7 no-progress / oscillation; stopped ≠ success | Stop-vs-success met by the status set. No-progress and oscillation **N/A**: the pipeline has no repeated round to compare |
| 8 residual-risk list | Met — report section (§10) |
| 9 provenance guard | **Applies** — the pipeline auto-corrects: the fixer rewrites the spec, and under `--auto`/`--no-approve` edits land with no human decision. **Met** — every assertion is a stochastic panel finding, so provenance is guarded by mandatory reviewer self-falsification, a challenger on every critical, the default approve gate, and the fix-coherence verification of batch A. **Residual:** under `--auto`/`--no-approve` a major is applied on one reviewer's unchallenged judgment |
| 10 durable sidecar, hash-pinning, idempotency | **First clause not met, deliberately** — the registry, the recorded decisions and the pinned hash live in orchestrator context for the whole run and reach disk only when Stage 5 writes the report; hash-pinning and the tamper checks stay; a re-run on an unchanged spec is detected by hash; there is no mid-run resume. Accepted for a run of 8–12 dispatches |
| 11 scoped, recoverable writes | Met — snapshot, spec-only edits, nothing committed |

## 9. Report format

**Statuses:** `TRIAGED` · `TRIAGED (incomplete)` ·
`STOPPED(user-declined | budget | interaction-unavailable | external-edit)`.
`TRIAGED (incomplete)` is set by any of: a lens not returned, a verifier that was
dispatched and did not return after its retry (Stage 4 being skipped because batch A
applied nothing is not such a case), a `fix-failed` entry after batch B, a
`pending-decision` entry. A stop is never
success.

**Outcome enum (exhaustive):** `applied` · `applied (not re-reviewed)` · `fix-failed`
· `refuted` · `reported-only` · `accepted-risk` · `pending-decision` · `declined` ·
`confirmed (not fixed — stopped)`.

**Verifier output shape:**

```json
{"resolved": [{"sr_id": "SR-003", "resolved": true, "reason": "<one sentence>"}],
 "findings": [{"severity": "major", "location": "<## heading>", "description": "…",
               "proposed_fix": "…", "needs_decision": false,
               "fix_induced": true, "introduced_by": ["SR-003"]}],
 "rejected": ["<one line per self-falsified candidate>"]}
```

**Fixer output shape:**

```json
{"edits": [{"sr_ids": ["SR-007", "SR-011"], "old": "<exact current text>",
            "new": "<replacement>"}],
 "growth": {"net_lines": 12, "drivers": ["SR-007"]},
 "notes": "<per-SR reasons when no unique pair could be produced>"}
```

**Report skeleton** (`docs/superpowers/specs/reviews/<spec>-review.md`):

```markdown
# Spec-review report — <spec>.md
**Mode / Budgets used / Terminal status / Verdict label**
**Spec hash (pre-loop):** <sha256>
**Spec hash (post-loop):** <sha256>
**Spec lines:** <before> → <after>
## Panel — lenses, units
| SR | severity | lenses | needs-decision | outcome |
## Critical challengers
| SR | verdict | note |
## Verification of batch A
| SR | resolved | reason |
Fix-induced findings: | SR | severity | introduced by | outcome |
## Decisions
| SR | decision | edit text (verbatim) |
## Residuals
- confirmed (not fixed — stopped) · fix-failed · pending-decision · declined · accepted-risk · applied (not re-reviewed) · reported-only
- Ordered most- to least-serious; `confirmed (not fixed — stopped)` and `fix-failed` entries carry their full description, not just an SR id, and a `fix-failed` entry quotes the fixer's `notes` reason.
## Coverage
- Lenses not selected · not returned (with reasons) · standing blind spots (intent, external facts, unstated requirements)
## Rejected by the panel and the verifier (self-falsification)
## Residual risks
## Recovery
- Loop-touched files, snapshot path; never `git restore` on the spec
```

## 10. Residual risks (to be carried into every report)

- One panel pass: a defect a second fresh panel would have found on the fixed text is
  not found; the verifier reads the diff against the spec, not the spec afresh.
- The tightened major anchor may demote a real major to minor, where it is reported but
  not fixed.
- Stochastic panel and verifier; soft oracle; no token ceiling beyond the dispatch cap.
- Findings are LLM-generated assertions applied to the spec; majors carry no challenger,
  so under `--auto`/`--no-approve` a wrong finding is fixed rather than questioned.
- No mid-run resume: an interrupted run is re-run on whatever the spec then contains.
- Loop-critical state (registry, recorded decisions, pinned hash) is held in orchestrator
  context until the report is written; an interruption or a context compaction across the
  approve gate — an unbounded wait that `--time-budget` does not count — loses it, and
  the decisions must be asked again on the next run.
- Growth is disclosed, not limited.
- Human interaction cost is disclosed, not budgeted: a default-mode run asks at most one
  question per needs-decision entry across the run (grouped four per call), one approve
  gate per batch, and — only when the user chooses to approve a subset — one page per
  four edit groups; `--time-budget` does not count that time.
- Item 4 is not met: headless detection is best-effort (no TTY probe); the loop fails
  closed rather than probing.
- Budget ceiling: with the full seven-lens roster and the ×2 retry headroom, seven or
  more criticals stop the run as `STOPPED(budget)` before batch A; the docs tell the
  user to raise `--max-dispatches` for a defect-rich spec.

## 11. Testing

1. **Repo validators** clean: `scripts/check_agent_frontmatter.py`,
   `scripts/check_plugin_versions.py`, `scripts/check_execution_boundary.py`.
2. **Acceptance protocol** on `tests/fixtures/seeded-spec.md`: `TRIAGED` within default
   budgets and all three seed predicates, at least 2 of 3 runs.
3. **Dogfood:** run the new command on the sub-project B design spec. Record dispatches,
   active seconds, and the line delta in that spec's report.

## 12. Delivery

- Version 2.0.0 in `plugins/superutils/.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, the README "Available Plugins" row, and the
  `**Version:**` header of `docs/plugins/superutils.md`.
- `docs/plugins/superutils.md`: command section, flag table, statuses, the re-run table
  (unchanged / changed / interrupted), "Honest limits" with items 4, 9 and 10.
- `docs/workflow.md` Stage 2: "runs a fixed triage pipeline"; statuses `TRIAGED` /
  `TRIAGED (incomplete)` / `STOPPED(...)`.
- README row: description rewritten for the new shape.

## 13. Out of scope

- Sub-project B (lightweight in-flight code review).
- A multi-round or convergence mode behind a flag.
- Challengers for majors.
- Model tiering for reviewers.

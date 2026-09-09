---
allowed-tools: Bash(ls:*), Bash(stat:*), Bash(sort:*), Bash(head:*), Bash(cat:*), Bash(mkdir:*), Bash(date:*), Bash(echo:*), Bash(git status:*), Bash(git diff:*), Bash(shasum:*), Bash(jq:*), Bash(cp:*), Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput, Skill, AskUserQuestion, mcp__plugin_sequentialthinking_sequential-thinking__sequentialthinking
description: Bounded spec triage — lens panel, challengers for criticals, one approve-gated fix batch, verification of the applied edits, one final batch. For superpowers-produced design specs.
model: opus
argument-hint: [spec path] [--no-approve] [--auto] [--allow-dirty] [--max-dispatches D] [--time-budget S]
---

# Spec Triage Command

Run a fixed triage pipeline on a design spec from `docs/superpowers/specs/`:
panel → critical challengers → batch A → verify the edits → batch B → report.
Nothing repeats. **This file, with the two skills it loads, is the contract** —
self-contained by design, so the pipeline behaves identically in a marketplace
install.

> **Doctrine:** this command implements the `qa:loop-engineering` bar as
> disclosed in `docs/plugins/superutils.md` "Honest limits" (items 4 and 10 are
> not met; item 9 applies and carries a residual). Load the
> `superutils:lens-catalog` and `superutils:spec-report-format` skills before
> Stage 1 — they define the vocabulary this command uses.

**Oracle (soft, advisory):** panel verdict, critical-challenger survival, and
the `fix-coherence` verifier on the applied batch. It cannot verify user intent,
external facts, or unstated requirements. Every verdict is advisory — never
"Verified".

## Arguments

**Input:** `$ARGUMENTS`

| Argument | Interpretation | Default | Rules |
|---|---|---|---|
| (empty) | Newest `.md` by mtime in `docs/superpowers/specs/` (non-recursive; `reviews/` excluded) | — | No candidate, or a byte-equal-mtime tie for newest (per `stat`) → list and ask (interactive) / abort (`--auto`) — never guess |
| `<path>` | The target spec | — | Must be a `.md` file directly in `docs/superpowers/specs/`; anything else → out-of-scope error, all modes |
| `--no-approve` | Skip the approve gate; apply + print the full diff | (off) | Valueless; needs-decision questions still asked |
| `--auto` | Headless: no interaction at all; implies `--no-approve` | (off) | Needs-decision entries skipped → `pending-decision`; an unchanged-spec re-run exits |
| `--allow-dirty` | Bypass the working-tree gate | (off) | Valueless |
| `--max-dispatches` | Subagent-launch cap (reviewers + challengers + fixers + verifier; retries count) | 20 | Positive integer, else error + stop |
| `--time-budget` | Active seconds (user waits excluded) | 900 | Positive integer, else error + stop |

There is no iteration flag: the pipeline's shape bounds iterations, and an
unknown flag is a validation error. All flags are validated before any I/O.

## Stage 0: Resolve & gate

### 0.1 Parse + headless check (fail-fast)

Parse flags per the table. If the session is non-interactive and the mode is
default or `--no-approve`, abort:
> Error: interactive modes require an interactive session. Use --auto.

Session interactivity is model-judged and best-effort (no shell TTY probe
exists — Bash stdin is never a TTY). If interactivity cannot be positively
established, treat the session as non-interactive and abort — fail closed.
**Runtime backstop:** in default/`--no-approve` modes, any AskUserQuestion
failure mid-run aborts immediately as `STOPPED(interaction-unavailable)`, before
any write of the pending batch; an earlier batch's edits stay, the snapshot
recovers them.

### 0.2 Resolve the target spec

Explicit path → validate scope (table above). No argument:

```bash
ls -t docs/superpowers/specs/*.md 2>/dev/null | head -5
# BSD stat; on GNU/Linux use: stat -c '%Y %n' …
stat -f '%m %N' docs/superpowers/specs/*.md 2>/dev/null | sort -rn | head -5
```

Newest by mtime wins; byte-equal top mtimes → AskUserQuestion with the tied
files (interactive) or abort (`--auto`). Zero candidates → same ask/abort.
Set `spec_path` = the resolved file, `spec` = its basename without `.md`,
`report_path = docs/superpowers/specs/reviews/<spec>-review.md`,
`snapshot_path = docs/superpowers/specs/reviews/<spec>.pre-loop.bak`.
No sidecar is written: the report is the durable state.

### 0.3 Working-tree gate

```bash
git status --porcelain -- "$spec_path"
```

Dirty or untracked: `--auto` → abort unless `--allow-dirty`; interactive →
warn and confirm via AskUserQuestion (proceed / abort).

### 0.4 Hash pin and re-run detection

`pinned_hash` = `shasum -a 256 "$spec_path"`. If `report_path` exists, read its
`**Spec hash (post-loop):**` line:

| Report state | Action |
|---|---|
| No readable `post-loop` line (a pre-2.0.0 report, or one truncated by an interrupted run) | Treat as differing: archive and start fresh |
| `post-loop` hash == `pinned_hash` | The spec is unchanged since the last triage. Interactive → AskUserQuestion *re-run / exit*; `--auto` → print the prior status line and exit, no dispatches |
| Differing, or re-run chosen | Archive the report to `<spec>-review.run<N>.bak` (`N` = 1 + the number of such archives present) and start fresh |

A `<spec>-review.state.json` beside the report is a pre-2.0.0 sidecar: archive
it the same way (`<spec>-review.state.run<N>.bak`) and never read it. Every run
starts fresh — SR ids restart at SR-001. `mkdir -p docs/superpowers/specs/reviews`.

**Snapshot rule.** Copy the spec to `snapshot_path` before the first `Edit` of
the run, at most once per run, overwriting an earlier run's snapshot (git holds
the committed history; the snapshot is this run's recovery point).

### 0.5 Tamper flow

Re-hash immediately before each write (batch steps 3 and 7). A mismatch against
`pinned_hash` is an external edit. Interactive → AskUserQuestion: **adopt**
(re-pin to the current content) or **stop** (`STOPPED(external-edit)`).
`--auto` → abort as `STOPPED(external-edit)`.

## Budgets

**Stage budget rule (enforced at every stage boundary):** before dispatching a
stage, check `dispatches_used + 2 × planned_stage_dispatches ≤ max_dispatches`
(the ×2 is retry headroom) and active time < `--time-budget`. On failure →
Terminalization as `STOPPED(budget)`; never cut within a dispatch phase.

## Pipeline

Create progress tasks (TaskCreate): 1 Resolve · 2 Panel · 3 Challengers ·
4 Batch A · 5 Verify · 6 Batch B · 7 Report. Update as the stages complete.

### Stage 1: Panel

Units = the spec's `##` headings (sequential-thinking tool when available, else
inline; a `##` line inside a fenced code block is not a unit). Select lenses per
`superutils:lens-catalog`: both core lenses; `completeness` unless the spec has
fewer than three sections; content triggers; floor at 3; **no cap** — every lens
the rules name is dispatched, the roster is the ceiling. Log the panel and
rationale for the report.

⟨stage budget check⟩ Dispatch one `superutils:spec-reviewer` Task per lens **in
parallel**, prompt = lens id + mandate + spec path + unit list. A reviewer that
fails or returns unparseable JSON is retried once; still failing → its lens goes
to Coverage "not returned", print a WARNING, and the run ends
`TRIAGED (incomplete)` unless it stops earlier.

**Registry** (orchestrator context, written to the report): for each finding,
anchor slug and canonical phrase per `superutils:spec-report-format`; match
within the panel (slug equality + a logged equivalence judgment); merge
duplicates at maximum severity recording all lenses; assign SR ids in discovery
order. Record every reviewer's `rejected` list verbatim.

### Stage 2: Critical challengers

⟨stage budget check⟩ One `superutils:spec-challenger` per **critical** entry,
in parallel; prompt = the entry (every finder's description + proposed fix) +
spec path. `refute` → outcome `refuted`, the entry leaves the batch. `uphold` →
stays critical. Failure → one retry; still failing → the entry stays **upheld**
with the report note "challenger not returned" — uncertainty never refutes.
Majors receive no challenger.

### Stage 3: Batch A

Input: every surviving critical and every major. Minors and nits go straight to
the report as `reported-only`. Empty input → Stage 4 is skipped and batch B is
empty; go to Stage 5. Otherwise run the batch procedure; a landed edit takes
`applied`.

### Stage 4: Verify the edits

Skipped when batch A applied nothing (batch B's input is then batch A's
`fix-failed` entries, marked `re-derive`, and nothing else). Otherwise write two
files to the session scratchpad: the unified diff of batch A
(`git diff --no-index <pre-batch copy> "$spec_path"`) and the SR list of batch A
— **id, severity and description only**: the reviewer's `proposed_fix` and the
fixer's pairs are withheld, so the verifier judges whether the defect is resolved
rather than whether the edit matches a suggestion the fixer also held; the
applied text is visible in the diff.

⟨stage budget check⟩ Dispatch one `superutils:spec-reviewer` with lens
`fix-coherence`, both paths, and the spec path. Its mandate (lens catalog): per
SR, judged against the description alone, does the spec as edited still exhibit
the defect → `resolved: true|false` with a reason; and do the edits introduce a
contradiction, an ambiguity, or a dangling reference that was not there before →
findings tagged `fix_induced: true` naming the SR ids whose edits introduced it.

`resolved` must carry exactly one entry per SR of batch A: check the id set; a
missing SR is treated as unresolved (fail closed), enters batch B marked
`re-fix`, and the omission is noted under Coverage. Fix-induced findings take the
next SR ids. Record the verifier's `rejected` list verbatim, labelled
`fix-coherence`. Verifier failure → one retry; still failing → batch B is batch
A's `fix-failed` entries only, every applied edit of batch A takes
`applied (not re-reviewed)`, and the run ends `TRIAGED (incomplete)`.

### Stage 3': Batch B

Input: SRs the verifier marked unresolved or omitted (marked `re-fix`: the batch
A edit landed, `old` targets the applied text, the fix must change it),
fix-induced findings of severity major or critical (no challenger — one pass),
and batch A's `fix-failed` entries (marked `re-derive`). Fix-induced minors and
nits → `reported-only`. Empty input → Stage 5. A user-decided entry marked
`re-fix` is a new decision: the fixer may depart from the decided `new` text; in
default mode the approve gate shows the departure, in `--no-approve` the entry
is re-asked as a needs-decision question in step 1. Run the batch procedure; a
landed edit takes `applied (not re-reviewed)` — no further verification follows.
A `fix-failed` here stays `fix-failed` and makes the run `TRIAGED (incomplete)`.

### Stage 5: Report

Terminal statuses: `TRIAGED` · `TRIAGED (incomplete)` ·
`STOPPED(user-declined | budget | interaction-unavailable | external-edit)`. Set
`TRIAGED (incomplete)` when a lens or the verifier did not return, a `fix-failed`
entry remains after batch B, or a `pending-decision` entry exists; a stop status
when a stop fired; `TRIAGED` otherwise. Then go to Terminalization.

## The batch procedure

Used by stages 3 and 3'. Input: a list of SR entries, some marked `re-derive`
or `re-fix`.

**Empty batch.** If the input is empty, or step 1 leaves it empty, record no
outcomes and return — the fixer is never dispatched with an empty batch.

1. **Needs-decision gate.** For every major+ entry flagged `needs_decision`
   with no recorded decision (a `re-fix` entry in `--no-approve` mode counts as
   undecided): AskUserQuestion, up to four entries per call, each with *accept
   the proposed fix / supply an alternative / keep as is*. `accept` and
   `alternative` store the exact edit content with the entry; `keep as is` →
   `accepted-risk`, entry leaves the batch. `--auto` → `pending-decision`, entry
   leaves the batch. A decision recorded in batch A is not re-asked for a
   `re-derive` entry (its decided `new` text is preserved).
2. ⟨stage budget check⟩ Dispatch `superutils:spec-fixer` with the batch and
   the spec path. Every `re-derive` or `re-fix` entry carries why the previous
   attempt failed: a `re-fix` entry the verifier's reason and the batch A `new`
   text now standing in the spec; a pair-mismatch `re-derive` entry the `old`
   text that failed to match; an entry from a double fixer failure no prior pair.
   Decided edit content is passed verbatim, except as the `re-fix` rule allows.
   Fixer failure → one retry; a second failure → every entry `fix-failed`, go to
   step 8.
3. **Re-hash** the spec; mismatch against `pinned_hash` → tamper flow (0.5).
4. **Materialize the candidate** in the session scratchpad: copy the spec
   (keep this copy — it is the pre-batch text Stage 4 diffs against), apply
   every pair to the copy. A pair whose `old` does not match uniquely, or an
   entry no returned pair lists in its `sr_ids`, → `fix-failed`. Overlapping
   pairs (intersecting ranges, or one edit changing text another must match)
   form an atomic group: all land or all fail, earlier members reverted from the
   candidate on failure, every member `fix-failed`.
5. **Zero hunks** → nothing to approve; skip the gate (never ask an empty
   question), go to step 8.
6. **Diff and gate.** Compute the unified diff (`git diff --no-index` between
   the pre-batch copy and the candidate), the SR → hunk mapping, and the growth
   line `+N lines (+P%)`: N is the candidate's measured net line delta against
   the pre-batch copy (added minus deleted from `git diff --no-index --numstat`),
   P is N over the pre-batch line count, rounded to a whole percent. The fixer's
   `growth.net_lines` is advisory — when it differs from N, show N followed by
   `(fixer reported +M)`; a discrepancy is disclosed, never a failure. Under the
   diff list `growth.drivers` as `largest: SR-… (+K lines)`. In batch B the gate
   prompt states "these edits are applied without further verification" above
   the diff. **Default mode:** show the diff and the growth line, then *approve
   all / approve a subset / decline and stop*. Subset selection is by atomic
   group (a group renders as one hunk; half of it is never offered):
   AskUserQuestion with `multiSelect`, four groups per page until every group has
   been shown, each option labelled with its SR ids, the highest severity in the
   group, each finding's canonical phrase, and the group's net line delta.
   Deselected groups → `declined`; deselecting every group is a decline of the
   whole batch → `STOPPED(user-declined)`, exactly as the explicit third option.
   **`--no-approve` / `--auto`:** apply immediately, then print the same diff.
7. **Re-hash** (the gate is an unbounded human wait; this check guards the
   write; tamper flow on mismatch), take the snapshot if not yet taken, then
   apply approved pairs to the spec with `Edit`. Outcome per landed SR:
   `applied` in batch A, `applied (not re-reviewed)` in batch B. Re-pin
   `pinned_hash` to the written file.
8. **Record outcomes** for every entry of the batch; return to the pipeline.

## Outcomes at a stop

At any stop — budget, user-declined, interaction-unavailable, external-edit —
every entry whose outcome is not yet final takes the one its state implies: a
major+ entry never batched, or in a batch whose fixer or gate did not complete
→ `confirmed (not fixed — stopped)`; a batch A edit already applied when the
stop lands before Stage 4 → `applied (not re-reviewed)`; a batch A entry the
verifier marked unresolved whose batch B pass never ran →
`confirmed (not fixed — stopped)`, superseding its batch A `applied`, and its
Residuals line states that an edit for it did land — the spec was changed, the
defect was not resolved. Outcomes already assigned stand: minors and nits
`reported-only`, deselected groups `declined`, `--auto`-skipped needs-decision
entries `pending-decision`, refuted criticals `refuted`.

## Error handling

| Event | Handling |
|---|---|
| Reviewer fails twice | Lens → Coverage "not returned"; WARNING; run ends `TRIAGED (incomplete)` |
| Challenger fails twice | Critical stays upheld with a report note; never refuted |
| Fixer fails twice | Whole batch `fix-failed`; batch A → re-derived in batch B; batch B → residuals, `TRIAGED (incomplete)` |
| Pair mismatch / no pair | That SR `fix-failed`; batch A → batch B with `re-derive`; batch B → residual |
| Verifier fails twice | Batch B = batch A's `fix-failed` only; batch A edits → `applied (not re-reviewed)`; `TRIAGED (incomplete)` |
| Verifier omits an SR | That SR → unresolved, batch B with `re-fix`; noted under Coverage |
| Hash mismatch before a write | Tamper flow (0.5) |
| AskUserQuestion fails (interactive modes) | `STOPPED(interaction-unavailable)` before any write of the current batch; an earlier batch's edits stay, the snapshot recovers them |
| Whole batch declined | `STOPPED(user-declined)`; nothing from that batch applied; an earlier batch's edits stay, the snapshot recovers them |
| Any stop | Outcomes per **Outcomes at a stop** |
| User abort (Esc) | Partial report; changes uncommitted; recovery = snapshot |

## Terminalization

Write the report to `report_path` per `superutils:spec-report-format`: the
header with both hash lines (`pre-loop` = the hash pinned at 0.4, `post-loop` =
the hash of the file as last written — equal to `pre-loop` when nothing was
written), the line delta, the panel table, critical challengers, the
verification table with fix-induced findings, Residuals ordered most- to
least-serious, Coverage (lenses not selected, not returned with reasons,
standing blind spots), Rejected by the panel and the verifier, Residual risks
(one panel pass; the tightened major anchor; stochastic panel and verifier; no
token ceiling; majors carry no challenger; no mid-run resume and in-context
state across the gate; growth disclosed not limited; interaction cost disclosed
not budgeted; item 4 not met), and Recovery (loop-touched files, `snapshot_path`;
never `git restore` on the spec). Nothing is ever committed.

Print: the status with its reason in parentheses when incomplete (e.g.
`TRIAGED (incomplete: fix-coherence verifier not returned)`); a one-line outcome
summary `N residuals (X confirmed-not-fixed, Y fix-failed, Z pending-decision)`;
the one-line cost summary (dispatches, active seconds, spec line delta); the
report path; and the verdict label — `Re-reviewed (advisory)` when the batch A
verifier returned, `Not re-reviewed (verifier not returned)` when it did not, in
either case followed by `K edits applied without re-review` when any
`applied (not re-reviewed)` entry exists.

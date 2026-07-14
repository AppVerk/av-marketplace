---
allowed-tools: Bash(ls:*), Bash(stat:*), Bash(sort:*), Bash(head:*), Bash(cat:*), Bash(mkdir:*), Bash(date:*), Bash(echo:*), Bash(git status:*), Bash(git diff:*), Bash(shasum:*), Bash(jq:*), Bash(cp:*), Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput, Skill, AskUserQuestion, mcp__plugin_sequentialthinking_sequential-thinking__sequentialthinking
description: Closed spec-review loop — MoA lens panel, challenger quorum, needs-decision gate, fix batch behind an approve gate, fresh-panel convergence. For superpowers-produced design specs.
model: opus
argument-hint: [spec path] [--no-approve] [--auto] [--allow-dirty] [--max-iterations N] [--max-dispatches D] [--time-budget S]
---

# Spec Review Loop Command

Run a closed review loop on a design spec from `docs/superpowers/specs/`:
decompose → lens-panel review → challenger quorum → needs-decision gate →
fix batch (approve-gated) → fresh-panel re-review, until convergence or a
stop. The full design contract is
`docs/superpowers/specs/2026-07-13-superutils-spec-review-design.md`.

> **Doctrine:** this command implements the `qa:loop-engineering` bar. Load
> the `superutils:lens-catalog` and `superutils:spec-report-format` skills
> before Step 1 — they define the vocabulary this command uses.

**Oracle (soft, advisory):** panel verdict + challenger survival. It cannot
verify user intent, external facts, or unstated requirements. Every verdict
is "Re-reviewed (advisory)" — never "Verified".

## Arguments

**Input:** `$ARGUMENTS`

| Argument | Interpretation | Default | Rules |
|----------|---|---|---|
| (empty) | Newest `.md` by mtime in `docs/superpowers/specs/` (non-recursive; `reviews/` excluded) | — | No candidate, or a byte-equal-mtime tie for newest (per `stat`) → list and ask (interactive) / abort (`--auto`) — never guess |
| `<path>` | The target spec | — | Must be a `.md` file directly in `docs/superpowers/specs/`; anything else → out-of-scope error, all modes |
| `--no-approve` | Skip the batch-approve gate; auto-apply + print the full diff | (off) | Valueless flag; needs-decision questions still asked |
| `--auto` | Headless: no interaction at all; implies `--no-approve` | (off) | Needs-decision findings skipped → `pending-decision` |
| `--allow-dirty` | Bypass the working-tree gate | (off) | Valueless flag |
| `--max-iterations` | Round cap | 3 | Positive integer, else error + stop |
| `--max-dispatches` | Subagent-launch cap (reviewers + challengers + fixer; retries count) | 60 | Positive integer, else error + stop |
| `--time-budget` | Active seconds (user-wait excluded) | 1800 | Positive integer, else error + stop |

All flags are validated before any I/O; exit on any validation error.

## Step 0: Resolve & Validate

### 0.1 Parse + headless check (fail-fast)

Parse flags per the table. Then: if the session is non-interactive and the
mode is default or `--no-approve`, abort:
> Error: interactive modes require an interactive session. Use --auto.

Session interactivity is model-judged and best-effort (no shell TTY probe
exists — Bash stdin is never a TTY). If interactivity cannot be positively
established, treat the session as non-interactive and abort — fail closed.
**Runtime backstop (the fail-closed element):** in default/`--no-approve`
modes, any AskUserQuestion failure mid-run aborts immediately as
`STOPPED(interaction-unavailable)`, before any fix application in that round.

### 0.2 Resolve the target spec

Explicit path → validate scope (table above). No argument:

```bash
ls -t docs/superpowers/specs/*.md 2>/dev/null | head -5
# BSD stat; on GNU/Linux use: stat -c '%Y %n' … (the 2>/dev/null would otherwise hide the failure)
stat -f '%m %N' docs/superpowers/specs/*.md 2>/dev/null | sort -rn | head -5
```

Newest by mtime wins; byte-equal top mtimes → AskUserQuestion with the tied
files (interactive) or abort (`--auto`). Zero candidates → same ask/abort.
Set `spec_path` = the resolved target file, `spec` = its basename without
`.md`, and:
`sidecar_path = docs/superpowers/specs/reviews/<spec>-review.state.json`,
`report_path = docs/superpowers/specs/reviews/<spec>-review.md`,
`snapshot_path = docs/superpowers/specs/reviews/<spec>.pre-loop.bak`.

### 0.3 Working-tree gate (reused: /qa:loop Step 0.1.5 pattern)

```bash
git status --porcelain -- "$spec_path"
```

Dirty or untracked: `--auto` → abort unless `--allow-dirty`; interactive →
warn and confirm via AskUserQuestion (proceed / abort). The snapshot (0.4)
is the recovery guard either way.

### 0.4 Sidecar lifecycle (idempotency)

Hash the spec: `shasum -a 256 "$spec_path"`. Then, if the sidecar exists:

| Sidecar state | Action |
|---|---|
| terminal status ∧ hash == `last_written_hash` | Print the prior report summary and exit — no dispatches |
| `in-progress` | **Resume:** counters continue (never reset), recorded decisions replay without re-asking, snapshot is NOT retaken. Hash ≠ `last_written_hash` → tamper flow (0.5) first |
| terminal status ∧ hash ≠ `last_written_hash` | **New run:** archive sidecar `rounds[]` + report to `.bak` under an incremented `run`; retake the snapshot; SR ids continue at max+1; carry the **whole registry** forward — entries with their `unlanded` / `unconfirmed` / `fix_failures` state (a new run does not forgive unfinished work) — plus `decisions` keyed by registry identity, revalidating each (its heading slug must still exist — stale ones dropped **with a report note naming any unfinished work discarded**) and replaying without re-asking |

No sidecar → fresh run: `mkdir -p docs/superpowers/specs/reviews`, write the
initial sidecar (schema: `superutils:spec-report-format` skill), pin
`last_written_hash`. **Snapshot rule:** copy the spec to `snapshot_path`
before the first fix application of a run, at most once per run.

### 0.5 Tamper flow (also mid-run)

Re-hash at round start and immediately before each fix application. Mismatch
vs `last_written_hash` = external edit. Interactive → AskUserQuestion:
**adopt** (re-pin to current content; registry entries whose slug no longer
exists are marked stale and excluded from matching) or **stop**
(`STOPPED(external-edit)`). `--auto` → abort as `STOPPED(external-edit)`.
The fixer-write→re-stamp window is non-atomic; a crash inside it surfaces
here on resume — same choice applies.

## Workflow

Create progress tasks (TaskCreate): 1 Validate & resolve · 2 Round N/M ·
3 Write report. Update as the loop proceeds.

### Round r (repeat up to --max-iterations)

**Stage budget rule (enforced at every stage boundary below):** before
dispatching a stage, check `dispatches_used + 2 × planned_stage_dispatches ≤
max_dispatches` (the ×2 is retry headroom) and active time < budget. On
failure → skip to Terminalization with `STOPPED(budget)`; never cut within a
dispatch phase. Major+ entries whose challengers were never dispatched →
`unconfirmed`.

**1. Decompose & select panel.** Units = the spec's `##` headings (use the
sequential-thinking tool when available, else inline). Select 3–6 lenses per
`superutils:lens-catalog`; log panel + rationale + units to the sidecar.

**2. Review fan-out.** ⟨stage budget check⟩ Dispatch one
`superutils:spec-reviewer` Task per lens **in parallel**, prompt = lens id +
mandate + spec path + unit list. A reviewer that fails or returns unparseable
JSON is retried once; still failing → its lens goes to Coverage "not
returned" and the round proceeds (shallow-coverage WARNING; a converged run
becomes `CONVERGED (low-confidence)`).

**3. Registry.** For each finding: anchor slug (rules in
`superutils:spec-report-format`), derive the canonical phrase, match
semantically against the registry (within-round and cross-round; log every
equivalence verdict), merge duplicates at max severity recording all lenses,
assign SR ids in discovery order. Each reviewer's `rejected` list is recorded
verbatim in the round record — never dropped.

**Unfinished work (definition — the loop may never report success while any
exists).** Two registry flags, both orthogonal to severity and to any user
decision:

- **Unlanded fix** — `unlanded: true`, set when a batched fix does not land
  (pair mismatch, no pair returned, *or* fixer failure), **at any severity,
  minor and nit included** (minor/nit are batched without a challenger, so their
  failures never pass through the significant set and would otherwise leak past
  every convergence check). It is never re-challenged, never refuted, and the
  decision filter never removes it: it was adjudicated once and promised.
  **Cleared by exactly four events, all of them explicit:** a successful apply
  (8.5); an `obsolete` verdict (below); a user `declined` at the batch gate (the
  user consciously withdraws the fix — reported under Declined); or a stale-drop
  in the tamper flow, whose anchor no longer exists (0.5) — **and a stale-drop
  of unfinished work is reported as such, never silently vacated.** Nothing else
  clears it.
- **Unconfirmed** — `unconfirmed: true`, a major+ entry whose challenger never
  returned. Never treated as refuted. **Every `unconfirmed` entry is
  re-dispatched to a challenger in the next round — whether or not the fresh
  panel re-found it** (budget permitting; if the budget stops the run first, the
  status is a truthful `STOPPED(budget)`). The flag clears only when a
  challenger returns a verdict. Without this re-dispatch rule the flag is a
  one-way latch that makes convergence unreachable.
- `fix_failures` counts failed attempts for an entry (0 initially; incremented
  on **every** failed attempt *after* the fixer's one retry; reset to 0 whenever
  the flag is cleared). It gates the retry, never the safety property.
- **`obsolete`** (a vacate path, tightly gated): the fresh panel does not
  re-find the entry **and** the fixer reports — in the structured `obsolete`
  field of its output, not in prose — that the target text no longer exists (the
  defect is already gone). Outcome `obsolete`, `unlanded` cleared. It may never
  retire a fix that merely failed to apply; that is `fix-failed`.

**A decision settles *which* fix, not *whether* the defect exists.** An
`accepted` decision suppresses re-*asking* (Step 7), never re-*finding*: once its
fix is applied, the entry returns to normal adjudication — a fresh panel that
re-finds it gets a challenger and, if upheld, a significant finding, exactly as
if it were new (an accepted fix that landed but did not work must not be
invisible to the loop that applied it). Only `keep-as-is` (`accepted-risk`) and
`declined` are significance waivers.

**4. Challenger quorum.** ⟨stage budget check⟩ Skip challenger dispatch for
entries already adjudicated: those whose decision is a significance waiver
(`keep-as-is`, `declined`), and **every unlanded fix** — of any severity and
regardless of its decision status. An unlanded fix is **never re-challenged and
never refuted**; it re-enters this round's batch directly (and, if major+, the
significant set). An entry whose `accepted` fix has already been applied is
**not** skipped — a re-finding means the fix did not work. Dispatch per
remaining major+ entry **in parallel** — including **every `unconfirmed` entry,
re-dispatched whether or not this round's panel re-found it**:
majors 1 × `superutils:spec-challenger`, criticals 2. Prompt = the entry (all
finder descriptions + proposed fix) + spec path. Failure → one retry; still
failing → `unconfirmed` (for a critical: `unconfirmed` if either challenger
is missing, regardless of the other verdict). Verdicts: major upheld →
significant; refuted → `refuted`. Critical: both uphold → significant; both
refute → `refuted`; split → escalate to the gate as needs-decision (stays in
the significant set until decided). **Significant = major+ ∧ survived
refutation.**

**5. Stop evaluation (after quorum, before the gate)** — precedence:
pending-decisions → oscillation → no-progress → budget.
- *pending-decisions* (→ `STOPPED(pending-decisions)`): significant set non-empty and consists entirely of
  `--auto`-skipped needs-decision entries.
- *oscillation* (→ `STOPPED(oscillation)`): an entry fixed in round r−2 reappears in this round's
  post-refutation significant set (sub-major reappearance: log only).
- *no-progress* (→ `STOPPED(no-progress)`): comparison sets for this and the
  previous round are identical. **Both sets are computed now, at evaluation
  time**, with current flags and decisions applied retroactively to the previous
  round's set (otherwise an entry excluded last round at `fix_failures ≤ 1` and
  retained this round at `≥ 2` would make the sets differ, and the stop this
  rule exists for could never fire). Each set = that round's post-refutation
  significant entries **plus every unlanded fix, at any severity**, minus:
  - entries user-decided or `--auto`-skipped **as of now** (decisions filter
    retroactively) — **this filter never removes an unlanded fix**;
  - `unconfirmed` entries (their challenger has yet to be re-dispatched);
  - unlanded fixes with `fix_failures ≤ 1` (their re-derived retry has yet to
    run — excluding them is precisely what lets Step 8 attempt it).

  An unlanded fix at `fix_failures ≥ 2` — the re-derived pair failed too —
  **stays** in the set, so a fix that cannot land stops the loop here,
  truthfully, instead of consuming the iteration cap. An empty comparison set
  never triggers.
- *budget* (→ `STOPPED(budget)`): the stage budget rule above already stopped
  the round at a stage boundary; listed here for precedence only.
A stop here skips gate+fix: significant findings **and unlanded fixes of any
severity** → `confirmed (not fixed — stopped)` (except skipped needs-decision →
`pending-decision`) — an unlanded fix was promised, not merely reported; the
round's remaining minor/nit → `reported-only`.

**6. Convergence check (before the gate).** CONVERGED requires **all three**:
(a) zero significant findings after excluding entries user-decided in earlier
rounds; **(b) zero unlanded fixes, at any severity**; **(c) zero `unconfirmed`
entries**. (b) and (c) are separate conditions, not filters on (a), because
neither is reliably inside the significant set: a minor/nit never is, and an
`unconfirmed` entry survived no refutation so it is not significant either.
Collapsing them into (a) is how a loop converges green over an unadjudicated
major or an unlanded minor. On CONVERGED: terminate before the fix phase; this
round's minor/nit → `reported-only`.

**7. Needs-decision gate.** Only challenger-surviving major+ needs-decision
entries (+ split criticals) → AskUserQuestion, options: accept the proposed
fix / supply an alternative / keep as is. Sub-major needs-decision →
`reported-only`, never asked. Accepted (with the exact edit content stored in
`decisions`) → joins the fix batch. Keep-as-is → outcome `accepted-risk`:
recorded, excluded from significance from now on, reported under Accepted
risks. Decided entries are
never re-asked (in-run or on resume). `--auto`: skip → `pending-decision`.

**8. Fix (two-phase).** ⟨stage budget check⟩ Batch = confirmed major+ +
accepted decisions **whose fix has not yet been applied** (an applied one is
done — re-batching it would replay a landed edit and, per doctrine item 10,
re-apply a correction) + minor/nit not flagged needs-decision + **every unlanded
fix, at any severity**. Each unlanded fix is marked **re-derive**: the fixer
must produce a fresh pair against the current text — preserving the decided
`new` content for user-decided entries — and never replay the stored `old`
(a pair that already failed to match cannot succeed on replay). Dispatch
`superutils:spec-fixer` (batch + spec path) → edit pairs, no writes. **A fixer
failure is retried once, like a reviewer or challenger** (the stage budget's ×2
headroom is reserved for exactly this); only after the retry fails do its
entries take `fix-failed` — a transient dispatch fault must not charge
`fix_failures` to a whole batch. Then:
1. Re-hash the spec (tamper flow 0.5 on mismatch).
2. Materialize the candidate: copy the spec to the session scratchpad (outside the repo, so the
   scoped-writes rule holds), apply all pairs there. **Any batched entry that
   produces no edit in the candidate → `fix-failed`: set `unlanded: true` and
   increment `fix_failures`.** That covers all three producers — a pair whose
   `old` does not match, an entry the fixer returned no pair for (named in its
   `notes`), and a fixer dispatch that failed twice (every entry in the batch).
   A counter that Step 5 reads but that some failure path fails to increment
   would silently disarm the retry-stop. (This is about the candidate, not the
   gate: an entry the user later declines is `declined`, not `fix-failed`.)
   *Exception:* an entry the fixer lists in its structured `obsolete` field, and
   which this round's fresh panel did not re-find, → `obsolete` (`unlanded`
   cleared) — the defect is gone, not unfixed. Atomic
   groups: overlapping pairs — target ranges intersect or one edit changes
   the region another must match — succeed or fail together; revert the
   group's earlier pairs from the candidate on failure, and every member of a
   failed group gets `fix-failed` with its counter incremented.
3. Compute the unified diff (spec vs candidate) + SR-id → hunk mapping.
   **Zero applicable pairs → zero hunks:** there is nothing to approve, so skip
   the gate entirely (never ask an empty question) and go to 8.5's no-op and
   Step 9. Every entry stays `fix-failed`/unlanded, which blocks 8.6 — a batch
   that produced no pair is a failed fix, not a converged spec.
4. **Gate by mode.** Default: show the diff → approve (apply all) / approve
   subset (unselected → `declined`, sticky: recorded as a decision, excluded
   from significance and no-progress, never re-proposed; a decline of a
   gate-accepted fix supersedes that acceptance) / decline & stop (nothing
   applied → `STOPPED(user-declined)`). **The selection unit of approve-subset
   is the overlapping-edit group of 8.2, not the individual finding**:
   selecting or deselecting any member selects or deselects the whole group,
   partial in-group selection is never offered (an intersecting group renders
   as one diff hunk — offering half of it would apply text the user never
   approved). Elicit the subset with AskUserQuestion (`multiSelect`), **4
   groups per page**, paginating until every group has been shown; each option
   names every SR id in its group (declining a group sticky-declines all of
   them, so the user must see what rides along); a group the user never saw is
   never `declined`. **Deselecting every group is a decline of the whole batch —
   terminate as `STOPPED(user-declined)`**, exactly as the explicit third option
   does; the same user intent must never yield a green status through the subset
   path. `--no-approve`/`--auto`: apply
   immediately, then print the same full diff.
5. **Re-hash the spec (tamper flow 0.5 on mismatch) — the gate is an unbounded
   human wait, so this check, not 8.1's, is the one that guards the write.**
   Then apply approved pairs to the spec via Edit (orchestrator tool work, not
   a dispatch) — each successfully applied finding gets outcome `applied`, with
   **`unlanded` cleared and `fix_failures` reset to 0**; a group the user
   declined gets `declined`, which also clears `unlanded` and resets the counter
   (a conscious withdrawal, reported under Declined — not a silent drop);
   re-stamp `last_written_hash`; write the sidecar.
6. **Empty-batch convergence:** if after the gate nothing will be applied, the
   significant set is empty after this round's decisions, **there are no
   unlanded fixes, and there are no `unconfirmed` entries** → CONVERGED now (the
   spec is byte-identical to what this panel reviewed). Otherwise a fresh round
   is required. These are Step 6's conditions (a)+(b)+(c): **both convergence
   exits carry all three, or the loop reports success through whichever one was
   left open.**

**9. Round end.** Write the sidecar (round record: panel, units, findings with
severity + lenses + outcome, each reviewer's `rejected` list, equivalence log;
counters). Fixes applied in the final permitted round → `applied (not
re-reviewed)` under `STOPPED(budget)`.

### Terminalization

Write the terminal status to the sidecar (once, from the authoritative final
state) and generate the report per `superutils:spec-report-format`: round
traces, Coverage (3 sublists + WARNING when shallow), Rejected by the panel
(self-falsification), Accepted risks, Declined,
residual risks (verifier gaming; stochasticity; lens drift; no token
ceiling; soft registry matching; best-effort headless detection), recovery
(loop-touched files; point at `snapshot_path`; never `git restore` on the
spec). Nothing is ever committed. Print: terminal status + one-line
per-round summary + report path + "Re-reviewed (advisory)".

### Error handling

| Event | Handling |
|---|---|
| Reviewer fails twice | Lens → Coverage "not returned"; WARNING; proceed |
| Challenger fails twice / never dispatched **at a budget stop** | Entry `unconfirmed`; blocks convergence as its own condition; never refuted; **re-dispatched every following round until a verdict returns** (a deliberate Step-4 skip is not `unconfirmed`) |
| Fixer fails / pair mismatch | `fix-failed` → the entry is an **unlanded fix** (any severity): no convergence exit may fire (Steps 6 and 8.6), it is never settled by its user decision (Step 4), and it is re-batched next round with a **re-derived** pair — never a replay of the pair that failed. If the re-derived pair fails too (`fix_failures ≥ 2`), Step 5 stops the run as `STOPPED(no-progress)` |
| AskUserQuestion fails (interactive modes) | `STOPPED(interaction-unavailable)` before any fix application |
| Hash mismatch | Tamper flow 0.5 (adopt / stop / `--auto` abort) |
| User abort (Esc) | Report partial state; changes stay uncommitted; recovery = snapshot |

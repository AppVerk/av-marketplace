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
| `--max-dispatches` | Subagent-launch cap (reviewers + challengers + fixer; retries count) | 30 | Positive integer, else error + stop |
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
| terminal status ∧ hash ≠ `last_written_hash` | **New run:** archive sidecar `rounds[]` + report to `.bak` under an incremented `run`; retake the snapshot; SR ids continue at max+1; carry `decisions` forward keyed by registry identity, revalidating each (its heading slug must still exist — stale ones dropped with a report note) and replaying without re-asking |

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

**4. Challenger quorum.** ⟨stage budget check⟩ Entries with a recorded user
decision are skipped (settled) — **except an entry whose last fix attempt
ended `fix-failed`, which is not settled**: its significance was already
established, so it re-enters this round's significant set without a challenger
and blocks convergence until it is applied, declined, or the run stops.
Dispatch per major+ entry **in parallel**:
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
- *no-progress* (→ `STOPPED(no-progress)`): comparison sets for this and the previous round are
  identical, where each set = that round's post-refutation significant
  entries minus every entry user-decided or `--auto`-skipped **as of now**
  (decisions filter retroactively); an empty comparison set never triggers.
  **An entry carrying an unresolved `fix-failed` is not removed by the decision
  filter** — it is unfinished work, not a settled decision, so a fix that keeps
  failing stops the loop here rather than silently burning the iteration cap.
A stop here skips gate+fix: significant findings → `confirmed (not fixed —
stopped)` (except skipped needs-decision → `pending-decision`); the round's
minor/nit → `reported-only`.

**6. Convergence check (before the gate).** Zero significant findings after
excluding entries user-decided in earlier rounds → CONVERGED: terminate
before the fix phase; this round's minor/nit → `reported-only`. **An entry
carrying an unresolved `fix-failed` is never excluded by this filter** (like
`unconfirmed`, it blocks convergence) — the loop may not report success while
a fix it committed to has not landed.

**7. Needs-decision gate.** Only challenger-surviving major+ needs-decision
entries (+ split criticals) → AskUserQuestion, options: accept the proposed
fix / supply an alternative / keep as is. Sub-major needs-decision →
`reported-only`, never asked. Accepted (with the exact edit content stored in
`decisions`) → joins the fix batch. Keep-as-is → outcome `accepted-risk`:
recorded, excluded from significance from now on, reported under Accepted
risks. Decided entries are
never re-asked (in-run or on resume). `--auto`: skip → `pending-decision`.

**8. Fix (two-phase).** ⟨stage budget check⟩ Batch = confirmed major+ +
accepted decisions + minor/nit not flagged needs-decision. An accepted
decision whose previous attempt ended `fix-failed` is re-included and marked
**re-derive**: the fixer must produce a fresh pair that preserves the decided
intent against the current text, never replay the stored `old` (replaying a
pair that already failed to match cannot succeed). Dispatch
`superutils:spec-fixer` (batch + spec path) → edit pairs, no writes. Then:
1. Re-hash the spec (tamper flow 0.5 on mismatch).
2. Materialize the candidate: copy the spec to the session scratchpad (outside the repo, so the
   scoped-writes rule holds), apply all pairs there. Pairs whose `old`
   fails to match → `fix-failed` (atomic
   groups: overlapping pairs — target ranges intersect or one edit changes
   the region another must match — succeed or fail together; revert the
   group's earlier pairs from the candidate on failure).
3. Compute the unified diff (spec vs candidate) + SR-id → hunk mapping.
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
   groups per page**, paginating until every group has been shown; a group the
   user never saw is never `declined`. `--no-approve`/`--auto`: apply
   immediately, then print the same full diff.
5. **Re-hash the spec (tamper flow 0.5 on mismatch) — the gate is an unbounded
   human wait, so this check, not 8.1's, is the one that guards the write.**
   Then apply approved pairs to the spec via Edit (orchestrator tool work, not
   a dispatch) — each successfully applied finding gets outcome `applied`;
   re-stamp `last_written_hash`; write the sidecar.
6. **Empty-batch convergence:** if after the gate nothing will be applied and
   the significant set is empty after this round's decisions → CONVERGED now
   (the spec is byte-identical to what this panel reviewed). Otherwise a
   fresh round is required.

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
| Challenger fails twice / never dispatched | Entry `unconfirmed`; blocks convergence; never refuted |
| Fixer fails / pair mismatch | `fix-failed`; blocks convergence (Steps 4 + 6); re-batched next round with a **re-derived** pair — never a replay of the pair that failed |
| AskUserQuestion fails (interactive modes) | `STOPPED(interaction-unavailable)` before any fix application |
| Hash mismatch | Tamper flow 0.5 (adopt / stop / `--auto` abort) |
| User abort (Esc) | Report partial state; changes stay uncommitted; recovery = snapshot |

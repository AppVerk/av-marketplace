---
allowed-tools: Bash(ls:*), Bash(stat:*), Bash(head:*), Bash(cat:*), Bash(mkdir:*), Bash(date:*), Bash(echo:*), Bash(git:*), Bash(shasum:*), Bash(jq:*), Bash(cp:*), Bash(mv:*), Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput, Skill, AskUserQuestion, mcp__plugin_sequentialthinking_sequential-thinking__sequentialthinking
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
> the `superutils:lens-catalog` and `superutils:report-format` skills before
> Step 1 — they define the vocabulary this command uses.

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
stat -f '%m %N' docs/superpowers/specs/*.md 2>/dev/null | sort -rn | head -5
```

Newest by mtime wins; byte-equal top mtimes → AskUserQuestion with the tied
files (interactive) or abort (`--auto`). Zero candidates → same ask/abort.
Set `spec` = basename without `.md`, and:
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
initial sidecar (schema: `superutils:report-format` skill), pin
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

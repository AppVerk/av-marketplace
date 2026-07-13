# superutils Plugin (`/superutils:spec-review`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `superutils` marketplace plugin whose `/superutils:spec-review` command runs the closed spec-review loop defined in `docs/superpowers/specs/2026-07-13-superutils-spec-review-design.md`.

**Architecture:** A command-orchestrated loop (pattern: `/qa:loop`): the command markdown drives rounds from the main conversation and dispatches three agents (`spec-reviewer` per lens, `spec-challenger` per finding, `spec-fixer` proposing edit pairs); two skills carry the shared vocabulary (lens catalog + anchors, report/sidecar format). All state lives in a JSON sidecar; the spec file is the only repo file the loop mutates.

**Tech Stack:** Claude Code plugin markdown (commands/agents/skills), JSON sidecar, `jq`/`shasum`/`git` via Bash, AskUserQuestion gates, optional sequential-thinking MCP.

## Global Constraints

- Plugin name `superutils`, version `1.0.0`, category `planning` (spec: Plugin identity).
- Marketplace description, verbatim: "Companion utilities for the superpowers workflow — loop-engineered verification of design specs."
- All shipped artifacts in English. Conventional Commits; this repo's hook blocks bare `git commit` — commit with `AV_COMMIT_SKILL=1 git commit -m "..."`. Never add AI co-author trailers.
- Budgets defaults: `--max-iterations 3`, `--max-dispatches 30`, `--time-budget 1800` (seconds).
- Terminal statuses, verbatim set: `CONVERGED`, `CONVERGED (low-confidence)`, `STOPPED(budget | no-progress | oscillation | pending-decisions | user-declined | interaction-unavailable | external-edit)`.
- Outcome enum, verbatim set: `applied`, `applied (not re-reviewed)`, `fix-failed`, `refuted`, `unconfirmed`, `confirmed (not fixed — stopped)`, `reported-only`, `accepted-risk`, `pending-decision`, `declined`.
- Loop-mutable repo paths only: the target spec, `docs/superpowers/specs/reviews/<spec>-review.md`, `docs/superpowers/specs/reviews/<spec>-review.state.json`, `docs/superpowers/specs/reviews/<spec>.pre-loop.bak` (+ `.bak` archives). Diff candidate goes to the session scratchpad, never the repo.
- Do not modify any other plugin. The spec is the single source of truth; where this plan and the spec disagree, the spec wins.

## File Structure

```
plugins/superutils/
  .claude-plugin/plugin.json          # Task 1 — identity
  skills/lens-catalog/SKILL.md        # Task 2 — lens roster, panel selection, anchors
  skills/report-format/SKILL.md       # Task 3 — report + sidecar + outcome/status vocab
  agents/spec-reviewer.md             # Task 4 — lens-parameterized reviewer
  agents/spec-challenger.md           # Task 5 — adversarial verifier
  agents/spec-fixer.md                # Task 6 — edit-pair proposer (no writes)
  commands/spec-review.md             # Tasks 7–8 — the loop orchestrator
  tests/fixtures/seeded-spec.md       # Task 9 — acceptance fixture
  tests/ACCEPTANCE.md                 # Task 9 — acceptance protocol + predicates
.claude-plugin/marketplace.json       # Task 11 — register plugin
README.md                             # Task 11 — table row + badge 9→10
docs/plugins/superutils.md            # Task 11 — plugin docs
```

---

### Task 1: Plugin scaffold

**Files:**
- Create: `plugins/superutils/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: nothing.
- Produces: the plugin identity consumed verbatim by Task 11 (marketplace entry, README row).

- [ ] **Step 1: Write the failing check**

Run: `jq -e '.name=="superutils" and .version=="1.0.0"' plugins/superutils/.claude-plugin/plugin.json`
Expected: FAIL — `No such file or directory`.

- [ ] **Step 2: Create the file**

```json
{
  "name": "superutils",
  "description": "Companion utilities for the superpowers workflow — loop-engineered verification of design specs.",
  "version": "1.0.0"
}
```

- [ ] **Step 3: Re-run the check**

Run: `jq -e '.name=="superutils" and .version=="1.0.0"' plugins/superutils/.claude-plugin/plugin.json`
Expected: `true`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add plugins/superutils/.claude-plugin/plugin.json
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): scaffold plugin manifest"
```

---

### Task 2: lens-catalog skill

**Files:**
- Create: `plugins/superutils/skills/lens-catalog/SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: lens ids (`internal-consistency`, `ambiguity-testability`, `completeness`, `feasibility`, `doctrine-compliance`, `ux`, `contracts`), the panel-selection rules, and the severity + needs-decision anchors. Tasks 4, 7, 8 reference these ids and anchors verbatim.

- [ ] **Step 1: Write the failing check**

Run: `grep -c '^### Lens: ' plugins/superutils/skills/lens-catalog/SKILL.md`
Expected: FAIL — no such file.

- [ ] **Step 2: Create the file**

````markdown
---
name: lens-catalog
description: Lens roster, panel-selection rules, and severity/needs-decision anchors for the /superutils:spec-review loop. Load when composing a review panel or grading findings.
---

# Lens Catalog

A lens is one reviewer's single perspective. The orchestrator selects 3–6
lenses per round; the two core lenses are always on. Panel composition and
selection rationale are logged in the sidecar every round.

## Roster (v1)

### Lens: internal-consistency (core)
Mandate: contradictions between the spec's own sections — nothing else.

### Lens: ambiguity-testability (core)
Mandate: requirements readable two ways by competent implementers, and
acceptance criteria that cannot be checked — nothing else.

### Lens: completeness
Mandate: could a developer write the implementation plan without coming back
with design questions? Missing load-bearing design decisions only. Never
demand implementation-plan detail; never report gaps the spec explicitly
delegates or defers.

### Lens: feasibility
Mandate: can the platform actually deliver each claimed behavior? Verify
against the repository (this lens may read the repo); a mechanism the
reference implementations already demonstrate refutes the finding.

### Lens: doctrine-compliance
Mandate: audit against `qa:loop-engineering` (bar items 1–11 + anti-patterns).
Select only for specs that design closed loops, agents, or marketplace
plugins.

### Lens: ux
Mandate: user-facing flows, interaction cost, and copy. Select only for specs
with UI/UX surface.

### Lens: contracts
Mandate: API shapes, schemas, data contracts, versioning/compatibility.
Select only for specs defining external interfaces or data formats.

## Panel selection

1. Always include both core lenses.
2. Include `completeness` unless the spec is under 3 `##` sections.
3. Content triggers from the unit list: loop/agent/plugin design →
   `doctrine-compliance` + `feasibility`; UI/screens/flows → `ux`;
   API/schema/format → `contracts`.
4. Cap at 6. Log the selected ids and one-line rationale in the sidecar.

## Severity anchors (shared by reviewers and challengers)

- **critical** — the spec self-contradicts or a compliant implementation
  would violate a stated invariant.
- **major** — two competent implementers would build observably different
  load-bearing behavior.
- **minor** — divergence with low blast radius.
- **nit** — wording/format only.

## Needs-decision anchor

Flag `needs_decision` iff the fix requires choosing among materially
different alternatives that the spec's own content cannot arbitrate (a
decision, not a derivation), or the fix would reverse a recorded user
decision or an explicitly stated requirement.

## Self-falsification (binding on every reviewer)

Before reporting, try to refute each finding from the reviewed text. Report
only survivors; list rejected candidates one line each. Never silently drop.
````

- [ ] **Step 3: Re-run the check**

Run: `grep -c '^### Lens: ' plugins/superutils/skills/lens-catalog/SKILL.md`
Expected: `7`.

- [ ] **Step 4: Verify anchors present**

Run: `grep -c 'needs_decision\|Needs-decision anchor\|Severity anchors' plugins/superutils/skills/lens-catalog/SKILL.md`
Expected: `3` or more.

- [ ] **Step 5: Commit**

```bash
git add plugins/superutils/skills/lens-catalog/SKILL.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): add lens-catalog skill (roster, selection rules, anchors)"
```

---

### Task 3: report-format skill

**Files:**
- Create: `plugins/superutils/skills/report-format/SKILL.md`

**Interfaces:**
- Consumes: lens ids from Task 2.
- Produces: the finding JSON shape, the sidecar schema, SR-id rules, the outcome enum, terminal statuses, and the report skeleton. Tasks 4–8 use these shapes verbatim.

- [ ] **Step 1: Write the failing check**

Run: `grep -c 'last_written_hash' plugins/superutils/skills/report-format/SKILL.md`
Expected: FAIL — no such file.

- [ ] **Step 2: Create the file**

````markdown
---
name: report-format
description: Report structure, sidecar schema, SR-id rules, outcome enum, and terminal statuses for the /superutils:spec-review loop. Load when reading or writing loop state or reports.
---

# Spec-Review Report & Sidecar Format

## Reviewer finding shape (agent output, one JSON object)

```json
{
  "findings": [
    {
      "severity": "critical|major|minor|nit",
      "location": "<verbatim ## heading text, or empty when locationless>",
      "description": "<the defect, citing the text>",
      "proposed_fix": "<concrete edit instruction or replacement text>",
      "needs_decision": false
    }
  ],
  "rejected": ["<one line per self-falsified candidate>"]
}
```

Reviewers never emit SR ids or fingerprints — identity is orchestrator-owned.

## Challenger verdict shape

```json
{"sr_id": "SR-007", "verdict": "uphold|refute", "justification": "<one paragraph>"}
```

## Fixer output shape (no writes — edit pairs only)

```json
{"edits": [{"sr_id": "SR-007", "old": "<exact current text>", "new": "<replacement>"}],
 "notes": "<per-SR reasons when no unique pair could be produced — orchestrator marks those fix-failed>"}
```

## SR ids and registry identity

- SR ids are assigned once per issue, in discovery order (panel order as
  logged, then each reviewer's own output order), reused on reappearance;
  a later run continues at max+1.
- Location anchor: nearest enclosing `##` heading slug (GitHub-style:
  lowercase, spaces→hyphens, punctuation stripped; duplicates get `-2`, `-3`).
  Pre-first-heading content → `__preamble__`; locationless/document-level →
  `__document__`; cross-section → first-cited section's slug.
- Stored key: `sha256(slug + "|" + canonical-phrase)` where the canonical
  phrase is an orchestrator-derived ≤10-word identity phrase (the original
  description is never replaced). Matching (within and across rounds) is slug
  equality + an orchestrator yes/no equivalence judgment, logged.
- Within-round duplicates merge to one entry at maximum severity; the entry
  records all contributing lenses.

## Sidecar

Path: `docs/superpowers/specs/reviews/<spec>-review.state.json`
(`<spec>` = target basename without `.md`). Written after every round and
after every fix application.

```json
{
  "spec_path": "docs/superpowers/specs/<spec>.md",
  "last_written_hash": "<sha256 of the spec as last written by the loop>",
  "status": "in-progress",
  "run": 1,
  "iterations_used": 0,
  "dispatches_used": 0,
  "active_seconds": 0,
  "decisions": {"SR-003": {"decision": "accepted|keep-as-is|declined", "edit": {"old": "", "new": ""}}},
  "registry": [
    {"sr_id": "SR-001", "slug": "loop-algorithm", "phrase": "…", "key": "…",
     "severity": "major", "lenses": ["completeness"], "needs_decision": false}
  ],
  "rounds": [
    {"round": 1, "panel": ["internal-consistency", "…"], "panel_rationale": "…",
     "units": ["…"],
     "findings": [{"sr_id": "SR-001", "outcome": "applied"}],
     "equivalence_log": [{"a": "SR-001", "b": "SR-004", "match": true}]}
  ]
}
```

`decisions.edit` preserves the exact pair for accepted decisions (including
user-supplied alternatives) so replay never re-derives a fix.

## Outcome enum (exhaustive — every emitted finding gets exactly one)

`applied` · `applied (not re-reviewed)` (final permitted round, under
STOPPED(budget)) · `fix-failed` · `refuted` · `unconfirmed` (challenger failed
twice or never dispatched at a budget stop; blocks convergence; never treated
as refuted; excluded from the no-progress comparison) · `confirmed (not fixed
— stopped)` (significant findings of a round stopped by oscillation,
no-progress, or budget) · `reported-only` (sub-major needs-decision, and any
minor/nit of a round that ends before its fix phase) · `accepted-risk` (user
keep-as-is) · `pending-decision` (`--auto` skip — always, including in the
round that triggers STOPPED(pending-decisions)) · `declined` (user-declined
at the batch gate; sticky).

## Terminal statuses

`CONVERGED` · `CONVERGED (low-confidence)` · `STOPPED(budget | no-progress |
oscillation | pending-decisions | user-declined | interaction-unavailable |
external-edit)`. A stop is never reported as success. Every verdict is
advisory: report "Re-reviewed (advisory)", never "Verified".

## Report skeleton

Path: `docs/superpowers/specs/reviews/<spec>-review.md`.

```markdown
# Spec-review loop report — <spec>.md
**Run / Mode / Budgets used / Terminal status / Verdict label**
## Round N — panel, units
| SR | severity | lenses | outcome |
## Coverage
- Exercised lenses: …
- Not returned (failures, with reasons): …
- Standing oracle blind spots: intent, external facts, unstated requirements.
## Accepted risks (user-decided)
## Declined (user-decided)
## Residual risks
## Recovery
- Loop-touched files + snapshot path (never `git restore` on the spec).
```

Shallow coverage (any selected lens failed to return) → WARNING in the report
and `CONVERGED (low-confidence)` when the run converged.
````

- [ ] **Step 3: Re-run the check**

Run: `grep -c 'last_written_hash' plugins/superutils/skills/report-format/SKILL.md`
Expected: `2` or more.

- [ ] **Step 4: Verify the outcome enum is complete**

Run: `for o in "applied (not re-reviewed)" "fix-failed" "refuted" "unconfirmed" "confirmed (not fixed" "reported-only" "accepted-risk" "pending-decision" "declined"; do grep -q "$o" plugins/superutils/skills/report-format/SKILL.md || echo "MISSING: $o"; done`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/superutils/skills/report-format/SKILL.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): add report-format skill (sidecar schema, outcomes, statuses)"
```

---

### Task 4: spec-reviewer agent

**Files:**
- Create: `plugins/superutils/agents/spec-reviewer.md`

**Interfaces:**
- Consumes: lens ids + anchors (Task 2), finding JSON shape (Task 3).
- Produces: the agent type `superutils:spec-reviewer`, dispatched by Task 8 with a prompt containing: lens id + mandate, spec path, unit list. Returns the Task-3 finding JSON as its final message.

- [ ] **Step 1: Write the failing check**

Run: `grep -c 'name: spec-reviewer' plugins/superutils/agents/spec-reviewer.md`
Expected: FAIL — no such file.

- [ ] **Step 2: Create the file**

````markdown
---
name: spec-reviewer
description: Single-lens spec reviewer for the /superutils:spec-review loop. Reviews a design spec through exactly one assigned lens and returns raw JSON findings after a self-falsification pass.
tools: Read, Grep, Glob, Bash
allowed-tools: Bash(ls:*), Bash(head:*), Bash(cat:*), Bash(grep:*)
model: opus
skills: lens-catalog, report-format
---

# Spec Reviewer Agent

You review ONE design spec through ONE lens. Nothing outside your lens's
mandate is your business — do not report style, preferences, or another
lens's domain.

## Input (in your dispatch prompt)

1. **Lens** — id and mandate (from the lens catalog; follow it exactly).
2. **Spec path** — read the full file.
3. **Unit list** — the spec's `##` sections, as a reading guide only.

You receive no prior-round context by design (fresh panel). Only the
`feasibility` and `doctrine-compliance` lenses may read other repo files.

## Rules

- Grade severity and needs_decision strictly by the anchors in the
  lens-catalog skill.
- Do NOT compute SR ids or fingerprints; `location` is the verbatim `##`
  heading text (empty when locationless).
- Do NOT report gaps the spec explicitly delegates to a named deliverable,
  explicitly defers (Out of scope), or explicitly flags as an open question.
- Self-falsification is mandatory: attempt to refute every candidate from the
  reviewed text before reporting; rejected candidates go in `rejected`, one
  line each — never silently dropped.

## Output

Your final message is parsed, not read by a human. Return EXACTLY one JSON
object in the reviewer finding shape defined in the report-format skill —
no prose before or after it.
````

- [ ] **Step 3: Re-run the check**

Run: `grep -c 'name: spec-reviewer' plugins/superutils/agents/spec-reviewer.md`
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add plugins/superutils/agents/spec-reviewer.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): add spec-reviewer agent"
```

---

### Task 5: spec-challenger agent

**Files:**
- Create: `plugins/superutils/agents/spec-challenger.md`

**Interfaces:**
- Consumes: anchors (Task 2), challenger verdict shape (Task 3).
- Produces: agent type `superutils:spec-challenger`, dispatched by Task 8 with: one registry entry (SR id, severity, all finder descriptions, proposed fix), the spec path. Returns the Task-3 verdict JSON.

- [ ] **Step 1: Write the failing check**

Run: `grep -c 'name: spec-challenger' plugins/superutils/agents/spec-challenger.md`
Expected: FAIL — no such file.

- [ ] **Step 2: Create the file**

````markdown
---
name: spec-challenger
description: Adversarial verifier for the /superutils:spec-review loop. Receives exactly one finding and tries to refute it against the spec text; returns uphold or refute at the finder's severity.
tools: Read, Grep, Glob
model: opus
skills: lens-catalog, report-format
---

# Spec Challenger Agent

Your ONLY job: try to REFUTE the single finding you are given, with concrete
textual evidence from the spec (and, when the finding cites doctrine or repo
facts, from those files). If you cannot refute it, uphold it. When genuinely
uncertain, lean refute — false positives are costlier than false negatives.

## Input (in your dispatch prompt)

1. **The finding** — SR id, severity, every finder's description (a merged
   entry carries all of them), and the proposed fix.
2. **Spec path** — read the full file. You see only this one finding; other
   findings are none of your business.

## Rules

- Verdict is binary: `uphold` or `refute`, **at the finder's severity** —
  re-grading is out of scope (v1).
- Judge against the severity anchors in the lens-catalog skill: a real defect
  that does not meet its claimed severity anchor is a refute, and your
  justification must say so.
- A gap the spec explicitly delegates, defers, or discloses as an open
  question or residual risk is refuted.

## Output

Your final message is parsed, not read by a human. Return EXACTLY one JSON
object in the challenger verdict shape from the report-format skill.
````

- [ ] **Step 3: Re-run the check**

Run: `grep -c 'name: spec-challenger' plugins/superutils/agents/spec-challenger.md`
Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add plugins/superutils/agents/spec-challenger.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): add spec-challenger agent"
```

---

### Task 6: spec-fixer agent

**Files:**
- Create: `plugins/superutils/agents/spec-fixer.md`

**Interfaces:**
- Consumes: fixer output shape (Task 3).
- Produces: agent type `superutils:spec-fixer`, dispatched by Task 8 with the round's fix batch (SR id + description + proposed fix each) and the spec path. Returns Task-3 `edits` JSON. **Has no Write/Edit tools — phase separation is enforced by the toolset.**

- [ ] **Step 1: Write the failing check**

Run: `grep -q 'name: spec-fixer' plugins/superutils/agents/spec-fixer.md && grep -Eq '^tools: Read, Grep, Glob$' plugins/superutils/agents/spec-fixer.md && echo OK`
Expected: FAIL — no such file.

- [ ] **Step 2: Create the file**

````markdown
---
name: spec-fixer
description: Edit-pair proposer for the /superutils:spec-review loop. Turns a confirmed fix batch into exact {old, new} replacement pairs. Performs no writes — the orchestrator applies approved pairs.
tools: Read, Grep, Glob
model: opus
skills: report-format
---

# Spec Fixer Agent

You turn a batch of confirmed findings into exact text replacements for ONE
spec file. You have no write tools by design: you propose, the orchestrator
applies.

## Input (in your dispatch prompt)

1. **Fix batch** — findings as {SR id, description, proposed fix} (for
   user-decided findings the decided edit content is included verbatim —
   reproduce it exactly, never re-derive it).
2. **Spec path** — read the full current file before proposing.

## Rules

- Each edit pair: `old` must match the current spec text byte-exactly and
  uniquely; `new` is the complete replacement. One pair per finding where
  possible; multiple pairs for one SR id are allowed.
- Fix ONLY what the batch lists. No opportunistic improvements, reformatting,
  or fixes to problems you notice along the way.
- If a finding cannot be implemented as a unique replacement (text moved,
  ambiguous match), return no pair for it and name it in `notes` — the
  orchestrator marks it `fix-failed`. Never guess.

## Output

Your final message is parsed, not read by a human. Return EXACTLY one JSON
object: `{"edits": [{"sr_id": "...", "old": "...", "new": "..."}], "notes": "..."}`.
````

- [ ] **Step 3: Re-run the check**

Run: `grep -q 'name: spec-fixer' plugins/superutils/agents/spec-fixer.md && grep -Eq '^tools: Read, Grep, Glob$' plugins/superutils/agents/spec-fixer.md && echo OK`
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add plugins/superutils/agents/spec-fixer.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): add spec-fixer agent (propose-only, no write tools)"
```

---

### Task 7: Command — frontmatter, arguments, Step 0 (guards & state lifecycle)

**Files:**
- Create: `plugins/superutils/commands/spec-review.md` (first half)

**Interfaces:**
- Consumes: sidecar schema + statuses (Task 3).
- Produces: the command skeleton through Step 0; Task 8 appends the Workflow (rounds) section to this same file and relies on the variables named here: `spec_path`, `sidecar_path`, `report_path`, `snapshot_path`, `mode` (`approve` default / `no-approve` / `auto`), budget counters.

- [ ] **Step 1: Write the failing check**

Run: `grep -c 'argument-hint' plugins/superutils/commands/spec-review.md`
Expected: FAIL — no such file.

- [ ] **Step 2: Create the file with the following content**

````markdown
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
````

- [ ] **Step 3: Re-run the check**

Run: `grep -c 'argument-hint' plugins/superutils/commands/spec-review.md`
Expected: `1`.

- [ ] **Step 4: Verify guards present**

Run: `for s in "0.1 Parse" "0.2 Resolve" "0.3 Working-tree" "0.4 Sidecar" "0.5 Tamper" "interaction-unavailable" "external-edit"; do grep -q "$s" plugins/superutils/commands/spec-review.md || echo "MISSING: $s"; done`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/superutils/commands/spec-review.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): spec-review command — arguments, guards, state lifecycle"
```

---

### Task 8: Command — the loop body (rounds, quorum, gates, stops, report)

**Files:**
- Modify: `plugins/superutils/commands/spec-review.md` (append after Step 0.5)

**Interfaces:**
- Consumes: everything Tasks 2–7 produced — agent types `superutils:spec-reviewer` / `spec-challenger` / `spec-fixer`, JSON shapes, `spec_path`/`sidecar_path`/`report_path`/`snapshot_path`, mode and budget variables.
- Produces: the complete shipped command.

- [ ] **Step 1: Write the failing check**

Run: `grep -c '## Workflow' plugins/superutils/commands/spec-review.md`
Expected: `0`.

- [ ] **Step 2: Append the following content to the file**

````markdown
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
`superutils:report-format`), derive the canonical phrase, match semantically
against the registry (within-round and cross-round; log every equivalence
verdict), merge duplicates at max severity recording all lenses, assign SR
ids in discovery order.

**4. Challenger quorum.** ⟨stage budget check⟩ Entries with a recorded user
decision are skipped (settled). Dispatch per major+ entry **in parallel**:
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
- *pending-decisions:* significant set non-empty and consists entirely of
  `--auto`-skipped needs-decision entries.
- *oscillation:* an entry fixed in round r−2 reappears in this round's
  post-refutation significant set (sub-major reappearance: log only).
- *no-progress:* comparison sets for this and the previous round are
  identical, where each set = that round's post-refutation significant
  entries minus every entry user-decided or `--auto`-skipped **as of now**
  (decisions filter retroactively); an empty comparison set never triggers.
A stop here skips gate+fix: significant findings → `confirmed (not fixed —
stopped)` (except skipped needs-decision → `pending-decision`); the round's
minor/nit → `reported-only`.

**6. Convergence check (before the gate).** Zero significant findings after
excluding entries user-decided in earlier rounds → CONVERGED: terminate
before the fix phase; this round's minor/nit → `reported-only`.

**7. Needs-decision gate.** Only challenger-surviving major+ needs-decision
entries (+ split criticals) → AskUserQuestion, options: accept the proposed
fix / supply an alternative / keep as is. Sub-major needs-decision →
`reported-only`, never asked. Accepted (with the exact edit content stored in
`decisions`) → joins the fix batch. Keep-as-is → recorded, excluded from
significance from now on, reported under Accepted risks. Decided entries are
never re-asked (in-run or on resume). `--auto`: skip → `pending-decision`.

**8. Fix (two-phase).** ⟨stage budget check⟩ Batch = confirmed major+ +
accepted decisions + minor/nit not flagged needs-decision. Dispatch
`superutils:spec-fixer` (batch + spec path) → edit pairs, no writes. Then:
1. Re-hash the spec (tamper flow 0.5 on mismatch).
2. Materialize the candidate: copy the spec to the session scratchpad, apply
   all pairs there. Pairs whose `old` fails to match → `fix-failed` (atomic
   groups: overlapping pairs — target ranges intersect or one edit changes
   the region another must match — succeed or fail together; revert the
   group's earlier pairs from the candidate on failure).
3. Compute the unified diff (spec vs candidate) + SR-id → hunk mapping.
4. **Gate by mode.** Default: show the diff → approve (apply all) / approve
   subset (unselected → `declined`, sticky: recorded as a decision, excluded
   from significance and no-progress, never re-proposed; a decline of a
   gate-accepted fix supersedes that acceptance) / decline & stop (nothing
   applied → `STOPPED(user-declined)`). `--no-approve`/`--auto`: apply
   immediately, then print the same full diff.
5. Apply approved pairs to the spec via Edit (orchestrator tool work, not a
   dispatch); re-stamp `last_written_hash`; write the sidecar.
6. **Empty-batch convergence:** if after the gate nothing will be applied and
   the significant set is empty after this round's decisions → CONVERGED now
   (the spec is byte-identical to what this panel reviewed). Otherwise a
   fresh round is required.

**9. Round end.** Write the sidecar (round record: panel, units, findings +
outcomes, equivalence log; counters). Fixes applied in the final permitted
round → `applied (not re-reviewed)` under `STOPPED(budget)`.

### Terminalization

Write the terminal status to the sidecar (once, from the authoritative final
state) and generate the report per `superutils:report-format`: round traces,
Coverage (3 sublists + WARNING when shallow), Accepted risks, Declined,
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
| Fixer fails / pair mismatch | `fix-failed`; fresh panel re-finds next round |
| AskUserQuestion fails (interactive modes) | `STOPPED(interaction-unavailable)` before any fix application |
| Hash mismatch | Tamper flow 0.5 (adopt / stop / `--auto` abort) |
| User abort (Esc) | Report partial state; changes stay uncommitted; recovery = snapshot |
````

- [ ] **Step 3: Re-run the check**

Run: `grep -c '## Workflow' plugins/superutils/commands/spec-review.md`
Expected: `1`.

- [ ] **Step 4: Cross-file consistency checks**

Run: `for a in spec-reviewer spec-challenger spec-fixer; do grep -q "superutils:$a" plugins/superutils/commands/spec-review.md || echo "MISSING dispatch: $a"; done; for s in lens-catalog report-format; do grep -q "superutils:$s" plugins/superutils/commands/spec-review.md || echo "MISSING skill ref: $s"; done`
Expected: no output.

Run: `for st in "pending-decisions" "user-declined" "interaction-unavailable" "external-edit" "low-confidence" "no-progress" "oscillation" "budget"; do grep -q "$st" plugins/superutils/commands/spec-review.md || echo "MISSING status: $st"; done`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/superutils/commands/spec-review.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): spec-review command — loop body, quorum, gates, stops, report"
```

---

### Task 9: Acceptance fixture + protocol

**Files:**
- Create: `plugins/superutils/tests/fixtures/seeded-spec.md`
- Create: `plugins/superutils/tests/ACCEPTANCE.md`

**Interfaces:**
- Consumes: the shipped command (Tasks 7–8).
- Produces: the acceptance artifacts referenced by Task 11's docs.

- [ ] **Step 1: Write the failing check**

Run: `test -f plugins/superutils/tests/fixtures/seeded-spec.md && test -f plugins/superutils/tests/ACCEPTANCE.md && echo OK`
Expected: FAIL — nothing printed.

- [ ] **Step 2: Create the fixture (three seeded defects, marked here for the maintainer — the seeds are ordinary spec text, not annotated in-file)**

````markdown
# Notification Service Design

**Date:** 2026-07-13
**Status:** Draft

## Purpose

A small service that sends account notifications (email in v1) when domain
events occur.

## Requirements

- Events are consumed from the `events` queue.
- Duplicate events are removed before sending.
- A notification is sent within 60 seconds of event arrival.
- Retry behavior follows the policy in the Error Handling section.

## Delivery rules

Notifications for a given user are sent at most once per 10 minutes; excess
notifications are dropped.

## Batching

To reduce noise, notifications for a given user are batched: every
notification is held for 15 minutes and merged with later ones before a
single send.

## Storage

Sent notifications are recorded with `{user_id, event_id, sent_at}` and kept
for 90 days.
````

Seeds (documented in ACCEPTANCE.md, not in the fixture): **contradiction** —
"Delivery rules" (at most once per 10 min, excess dropped) vs "Batching"
(every notification held 15 min and merged; nothing dropped) also collides
with "sent within 60 seconds"; **phantom section** — Requirements cites "the
Error Handling section", which does not exist; **ambiguous requirement** —
"Duplicate events are removed" never defines the duplicate key
(`event_id`? `{user_id, type}`? time window?).

- [ ] **Step 3: Create the protocol**

````markdown
# Acceptance protocol — /superutils:spec-review

**Harness (v1, resolves the spec's open question):** manual interactive
protocol — a human runs the command and answers prompts from the script
below. (Future automation: Agent SDK `canUseTool` auto-responder.)

## Procedure (3 independent runs)

Each run starts fresh: copy `fixtures/seeded-spec.md` to
`docs/superpowers/specs/seeded-spec.md` in a scratch branch, with no sidecar,
report, or snapshot present.

Run `/superutils:spec-review docs/superpowers/specs/seeded-spec.md` in the
default mode with this answer script:
- every needs-decision prompt → **accept the proposed fix**
- every batch-approve gate → **approve (full batch)**

## Pass condition (per run)

Terminal status `CONVERGED` within default budgets AND all three post-run
content predicates hold on the final fixture file:

1. **Contradiction seed:** the Delivery-rules / Batching / 60-second claims
   no longer conflict (one consistent policy remains).
2. **Phantom-section seed:** the "Error Handling" reference is removed or an
   `## Error Handling` section exists.
3. **Ambiguity seed:** exactly one duplicate-detection behavior is derivable
   (the duplicate key and window are stated).

A keep-as-is outcome on a seeded defect does NOT count as resolved — the
fixture demonstrates fixing, not just termination.

**Overall pass: at least 2 of 3 runs pass.** Record each run's report path
and result here.

## Dogfood check (once per release)

Run the command on its own design spec
(`docs/superpowers/specs/2026-07-13-superutils-spec-review-design.md`); pass =
a valid terminal status within default budgets and a report + sidecar
conforming to `superutils:report-format`.
````

- [ ] **Step 4: Re-run the check**

Run: `test -f plugins/superutils/tests/fixtures/seeded-spec.md && test -f plugins/superutils/tests/ACCEPTANCE.md && grep -q 'at least 2 of 3' plugins/superutils/tests/ACCEPTANCE.md && echo OK`
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add plugins/superutils/tests/
AV_COMMIT_SKILL=1 git commit -m "test(superutils): seeded fixture and acceptance protocol"
```

---

### Task 10: Doctrine checklist review of the shipped command

**Files:**
- Modify: `plugins/superutils/commands/spec-review.md` (only if gaps are found)

**Interfaces:**
- Consumes: the complete command (Tasks 7–8), `plugins/qa/skills/loop-engineering/SKILL.md`.
- Produces: a verified doctrine-conformance mapping used verbatim in Task 11's docs.

- [ ] **Step 1: Run the checklist**

Open `plugins/qa/skills/loop-engineering/SKILL.md`, take its Review checklist
(Universal 1–8 + 6-rider, Conditional 9–11), and for every item find the
command section that implements it. Record the mapping as a table
(`item → command heading`). Expected mapping — verify, don't assume:
1 → Oracle statement block; 2 → Workflow 4+8 (challenger authority, fixer
propose-only) ; 3 → Terminalization Coverage; 4 → Arguments (default approve
gate) + 0.1 backstop; 5 → 0.3 working-tree gate + 0.5 tamper flow; 6 → stage
budget rule; 6-rider → partial (dispatch cap as proxy — must be stated in
the residual list); 7 → Workflow 5; 8 → Terminalization residual list;
9 → Workflow 7+8 (challenger confirmation + needs-decision never
auto-decided); 10 → 0.4 sidecar lifecycle; 11 → snapshot + scoped writes.

- [ ] **Step 2: Fix any gap inline**

An item whose mechanism is missing or weaker than the bar → edit the command
to close it (spec wins on any conflict). No gaps → no edit.

- [ ] **Step 3: Verify the residual-risk list is complete**

Run: `for r in "gaming" "Stochasticity\|stochasticity" "drift" "token" "soft" "headless\|best-effort"; do grep -qE "$r" plugins/superutils/commands/spec-review.md || echo "MISSING residual: $r"; done`
Expected: no output.

- [ ] **Step 4: Commit (only when Step 2 changed the file)**

```bash
git add plugins/superutils/commands/spec-review.md
AV_COMMIT_SKILL=1 git commit -m "fix(superutils): close loop-engineering checklist gaps in spec-review command"
```

---

### Task 11: Registration and documentation

**Files:**
- Modify: `.claude-plugin/marketplace.json` (append to `plugins` array)
- Modify: `README.md` (badge line 4, table after the QA row)
- Create: `docs/plugins/superutils.md`

**Interfaces:**
- Consumes: plugin identity (Task 1), command/flags (Tasks 7–8), acceptance protocol (Task 9), doctrine mapping (Task 10).
- Produces: the published marketplace entry.

- [ ] **Step 1: Write the failing check**

Run: `jq -e '.plugins[] | select(.name=="superutils")' .claude-plugin/marketplace.json`
Expected: FAIL — no output, exit 4.

- [ ] **Step 2: Register in marketplace.json** — append to the `plugins` array (before the `sequentialthinking` entry):

```json
{
  "name": "superutils",
  "source": "./plugins/superutils",
  "description": "Companion utilities for the superpowers workflow — loop-engineered verification of design specs.",
  "version": "1.0.0",
  "category": "planning"
}
```

- [ ] **Step 3: Update README.md**

Badge (line 4): `plugins-9-green` → `plugins-10-green`.
Table row (after the QA row):

```markdown
| [Superutils](docs/plugins/superutils.md) | 1.0.0 | Companion utilities for the superpowers workflow. `/superutils:spec-review` runs a closed review loop on design specs: MoA lens panel, adversarial challenger quorum, needs-decision gates, approve-gated fix batches, fresh-panel convergence — bounded by hard budgets, with a durable sidecar and an advisory (never "Verified") report |
```

- [ ] **Step 4: Create docs/plugins/superutils.md**

````markdown
# Superutils Plugin

Companion utilities for the superpowers workflow — loop-engineered
verification of design specs.

**Version:** 1.0.0

## Commands

### `/superutils:spec-review`

Closed review loop for a design spec from `docs/superpowers/specs/`
(brainstorming→design shape). Each round: sequential-thinking decomposition →
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

**Honest limits:** the oracle is soft (LLM panel + challenger) — verdicts are
advisory; it cannot verify your intent, external facts, or unstated
requirements. See the loop-engineering conformance mapping in the command
and the acceptance protocol in `plugins/superutils/tests/ACCEPTANCE.md`.

## Agents

- `spec-reviewer` — one lens per dispatch, self-falsifying, raw JSON findings
- `spec-challenger` — refute-or-uphold at the finder's severity, one finding per dispatch
- `spec-fixer` — proposes exact `{old, new}` edit pairs; has no write tools

## Skills

- `lens-catalog` — lens roster, panel-selection rules, severity and
  needs-decision anchors
- `report-format` — report structure, sidecar schema, outcome enum, statuses
````

- [ ] **Step 5: Verify**

Run: `jq -e '.plugins[] | select(.name=="superutils") | .category=="planning"' .claude-plugin/marketplace.json && grep -q 'plugins-10-green' README.md && grep -q 'superutils.md' README.md && test -f docs/plugins/superutils.md && echo OK`
Expected: `true` then `OK`.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/marketplace.json README.md docs/plugins/superutils.md
AV_COMMIT_SKILL=1 git commit -m "feat(superutils): register plugin, README row + badge, plugin docs"
```

# Spec Review as Bounded Triage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the convergence-seeking `/superutils:spec-review` loop with a fixed five-stage triage pipeline (panel → critical challengers → batch A → verify the edits → batch B → report) and release superutils 2.0.0.

**Architecture:** The plugin is prose contracts — one command file, two skills, three agent files — read by an orchestrating model, plus an acceptance protocol and user docs. There is no runtime code to compile; the only strong oracle is a vocabulary checker that asserts the same flags, statuses, outcomes and markers appear (and the deleted vocabulary does not) across every file, plus the three repo validators. Work bottom-up: vocabulary source of truth (report-format skill) → lens catalog → agents → command → acceptance → docs and versions → whole-tree verification.

**Tech Stack:** Markdown contract files with YAML frontmatter; Python 3.12 stdlib for the checker (matches `scripts/check_*.py`); bash for git and the validators. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-09-spec-review-bounded-triage-design.md` (reviewed by one round of the old loop, committed at `e2e035a`). The plan argues from the spec; read both.

**Branch:** `feat/spec-review-bounded-triage` (HEAD `e2e035a` at planning time). Work on this branch, or a worktree of it.

**Commits:** this repository's hook blocks bare `git commit`; every commit step uses `AV_COMMIT_SKILL=1`. The user's git config signs commits with GPG and the passphrase prompt cannot be answered by a subagent, so commit steps add `--no-gpg-sign`. The user may re-sign with `git rebase --exec 'git commit --amend --no-edit -S' e2e035a` before opening the PR. No `Co-Authored-By` lines: the repository's commit policy forbids AI attribution in messages.

## Global Constraints

- Version **2.0.0** in all four places `scripts/check_plugin_versions.py` reads: `plugins/superutils/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the superutils row of the README "Available Plugins" table, and the `**Version:** 2.0.0` header of `docs/plugins/superutils.md`.
- Flags, exactly: `--no-approve`, `--auto`, `--allow-dirty`, `--max-dispatches` (default **20**), `--time-budget` (default **900**). `--max-iterations` is removed and is a validation error.
- Terminal statuses, exactly: `TRIAGED` · `TRIAGED (incomplete)` · `STOPPED(user-declined | budget | interaction-unavailable | external-edit)`.
- Outcome enum (exhaustive, nine): `applied` · `applied (not re-reviewed)` · `fix-failed` · `refuted` · `reported-only` · `accepted-risk` · `pending-decision` · `declined` · `confirmed (not fixed — stopped)`.
- Markers: `re-derive` (the pair never landed) and `re-fix` (the batch A edit landed; the verifier judged the defect unresolved).
- Verdict labels: `Re-reviewed (advisory)` when the batch A verifier returned; `Not re-reviewed (verifier not returned)` when it did not; either followed by `K edits applied without re-review` when any `applied (not re-reviewed)` entry exists.
- Deleted vocabulary — must not appear in any superutils file, `docs/plugins/superutils.md`, `docs/workflow.md`, or the README row: `CONVERGED`, `--max-iterations`, `unlanded`, `unconfirmed`, `fix_failures`, `obsolete`, `no-progress`, `oscillation`, `last_written_hash`. The word `sidecar` may appear only in the command (the pre-2.0.0 archival rule) and in `docs/plugins/superutils.md`.
- Report paths: `docs/superpowers/specs/reviews/<spec>-review.md`, snapshot `docs/superpowers/specs/reviews/<spec>.pre-loop.bak`, archives `<spec>-review.run<N>.bak`. No sidecar is written.
- Agent frontmatter: capability is declared in `tools:` only; permitted keys are `name, description, tools, disallowedTools, model, skills` (see `scripts/check_agent_frontmatter.py`). Never add `allowed-tools:` to an agent.
- The command's `allowed-tools:` line is unchanged from today (the spec says the frontmatter changes only `argument-hint` and `description`).
- Committed artifacts are written in English.
- The doctrine bar copy inside `lens-catalog` (the eleven items) is untouched.

---

### Task 1: Contract vocabulary checker

The only strong oracle over a prose contract. It fails on the current tree (old vocabulary everywhere) and each later task makes one file pass.

**Files:**
- Create: `plugins/superutils/tests/check_contract.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `python3 plugins/superutils/tests/check_contract.py [--file KEY]` — exit 0 and `Contract OK: N file(s)` when every checked file carries its required tokens and none of the forbidden ones; exit 1 with one line per violation `<key>: missing '<token>'` / `<key>: forbidden '<token>' found` otherwise. Keys: `cmd cat fmt rev chl fix acc doc wf readme`.

- [ ] **Step 1: Write the checker**

```python
#!/usr/bin/env python3
"""Check that the /superutils:spec-review contract vocabulary agrees across
the command, its two skills, its three agents, the acceptance protocol and the
user docs.

Required tokens must appear verbatim; forbidden tokens (the vocabulary the
2.0.0 triage pipeline deleted) must not. The README check is scoped to the
superutils row of the "Available Plugins" table.

Usage: python3 plugins/superutils/tests/check_contract.py [--file KEY]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PLUGIN = ROOT / "plugins" / "superutils"

FILES: dict[str, Path] = {
    "cmd": PLUGIN / "commands" / "spec-review.md",
    "cat": PLUGIN / "skills" / "lens-catalog" / "SKILL.md",
    "fmt": PLUGIN / "skills" / "spec-report-format" / "SKILL.md",
    "rev": PLUGIN / "agents" / "spec-reviewer.md",
    "chl": PLUGIN / "agents" / "spec-challenger.md",
    "fix": PLUGIN / "agents" / "spec-fixer.md",
    "acc": PLUGIN / "tests" / "ACCEPTANCE.md",
    "doc": ROOT / "docs" / "plugins" / "superutils.md",
    "wf": ROOT / "docs" / "workflow.md",
    "readme": ROOT / "README.md",
}

FLAGS = ["--no-approve", "--auto", "--allow-dirty", "--max-dispatches", "--time-budget"]
OUTCOMES = [
    "`applied`",
    "`applied (not re-reviewed)`",
    "`fix-failed`",
    "`refuted`",
    "`reported-only`",
    "`accepted-risk`",
    "`pending-decision`",
    "`declined`",
    "`confirmed (not fixed — stopped)`",
]
STATUSES = [
    "`TRIAGED`",
    "`TRIAGED (incomplete)`",
    "STOPPED(user-declined | budget | interaction-unavailable | external-edit)",
]
DELETED = [
    "CONVERGED",
    "--max-iterations",
    "unlanded",
    "unconfirmed",
    "fix_failures",
    "obsolete",
    "no-progress",
    "oscillation",
    "last_written_hash",
]

REQUIRED: dict[str, list[str]] = {
    "cmd": FLAGS + OUTCOMES + STATUSES + [
        "re-derive", "re-fix", "fix-coherence", "Outcomes at a stop",
        "Re-reviewed (advisory)", "Not re-reviewed (verifier not returned)",
        "post-loop", "sr_ids", "Empty batch", "run<N>.bak", "| 20 |", "| 900 |",
    ],
    "cat": ["fix-coherence", "does not arbitrate", "No cap"],
    "fmt": OUTCOMES + STATUSES + [
        "sr_ids", '"growth"', "fix_induced", "introduced_by", '"resolved"',
        "post-loop", "Panel reviewers never emit SR ids", "SR-001",
        "re-derive", "re-fix",
    ],
    "rev": ["fix-coherence", "echo"],
    "chl": ["critical"],
    "fix": ["sr_ids", "growth", "re-derive", "re-fix", "Rewrite before append"],
    "acc": ["`TRIAGED`"],
    "doc": FLAGS + STATUSES + ["**Version:** 2.0.0", "Honest limits", "| 20 |", "| 900 |"],
    "wf": ["`TRIAGED`"],
    "readme": ["2.0.0", "triage"],
}

FORBIDDEN: dict[str, list[str]] = {key: list(DELETED) for key in FILES}
for key in ("fmt", "rev", "chl", "fix", "acc", "wf"):
    FORBIDDEN[key].append("sidecar")
# The lens catalog quotes the qa:loop-engineering bar verbatim (items 7 and 10 name
# no-progress, oscillation and the durable sidecar); that copy is untouched by design,
# so only the catalog's own panel-selection prose is checked for the sidecar.
FORBIDDEN["cat"] = [tok for tok in DELETED if tok not in ("no-progress", "oscillation")]
FORBIDDEN["cat"] += ["Cap at 6", "logged in the sidecar"]
FORBIDDEN["readme"] += ["sidecar", "convergence", "quorum"]


def haystack(key: str) -> str:
    text = FILES[key].read_text(encoding="utf-8")
    if key != "readme":
        return text
    rows = [line for line in text.splitlines() if "[Superutils](docs/plugins/superutils.md)" in line]
    return "\n".join(rows)


def check(key: str) -> list[str]:
    text = haystack(key)
    problems = [f"{key}: missing '{tok}'" for tok in REQUIRED.get(key, []) if tok not in text]
    problems += [f"{key}: forbidden '{tok}' found" for tok in FORBIDDEN.get(key, []) if tok in text]
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--file", choices=sorted(FILES), help="check one file only")
    args = parser.parse_args(argv)
    keys = [args.file] if args.file else list(FILES)
    problems: list[str] = []
    for key in keys:
        if not FILES[key].exists():
            problems.append(f"{key}: file not found: {FILES[key]}")
            continue
        problems += check(key)
    for line in problems:
        print(line)
    if problems:
        print(f"Contract violations: {len(problems)}")
        return 1
    print(f"Contract OK: {len(keys)} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Run it against the current tree and confirm it fails on the old vocabulary**

Run: `python3 plugins/superutils/tests/check_contract.py`
Expected: exit 1. The output contains many lines; at least these must be among them: `cmd: forbidden 'CONVERGED' found`, `cmd: forbidden '--max-iterations' found`, `cmd: forbidden 'unlanded' found`, `fmt: forbidden 'sidecar' found`, `cat: forbidden 'Cap at 6' found`, `cat: forbidden 'logged in the sidecar' found`, `rev: forbidden 'sidecar' found`, `fix: forbidden 'obsolete' found`, `acc: forbidden 'CONVERGED' found`, `doc: missing '**Version:** 2.0.0'`, `wf: forbidden 'CONVERGED' found`, `readme: forbidden 'quorum' found`, and a final `Contract violations: N`. It must NOT contain `cat: forbidden 'oscillation' found` or `cat: forbidden 'no-progress' found` — those words sit in the doctrine-bar quotation the catalog keeps.

- [ ] **Step 3: Confirm the per-file filter scopes to one file**

Run: `python3 plugins/superutils/tests/check_contract.py --file chl; echo "exit=$?"`
Expected: exactly two lines — `chl: missing 'critical'` and `Contract violations: 1` — then `exit=1`. (Today's challenger never says "critical"; Task 4 fixes that. No other file's violations may appear.)

- [ ] **Step 4: Commit**

```bash
git add plugins/superutils/tests/check_contract.py
AV_COMMIT_SKILL=1 git commit --no-gpg-sign -m "test(superutils): add the contract vocabulary checker for the triage pipeline"
```

---

### Task 2: Rewrite the `spec-report-format` skill

The vocabulary source of truth: output shapes, SR-id rules, markers, outcome enum, statuses, report skeleton. Every other file quotes it.

**Files:**
- Modify: `plugins/superutils/skills/spec-report-format/SKILL.md` (replace the whole file)

**Interfaces:**
- Consumes: nothing.
- Produces: the shapes and tokens the command (Task 5), the agents (Task 4) and the docs (Task 7) quote verbatim — in particular the fixer shape with `sr_ids` and `growth`, the verifier shape with `resolved`/`fix_induced`/`introduced_by`, the nine outcomes, the three statuses, the report header lines `**Spec hash (pre-loop):**` / `**Spec hash (post-loop):**`.

- [ ] **Step 1: Replace the file with this content**

````markdown
---
name: spec-report-format
description: Report structure, SR-id rules, reviewer/challenger/verifier/fixer output shapes, outcome enum, and terminal statuses for the /superutils:spec-review triage pipeline. Load when reading or writing a spec-review report. (Distinct from qa:report-format, which is the QA test-report format.)
---

# Spec-Review Report Format

## Reviewer finding shape (panel lenses; one JSON object)

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

Panel reviewers never emit SR ids or fingerprints — identity is
orchestrator-owned; the fix-coherence verifier echoes only the ids it was given.

## Challenger verdict shape

```json
{"sr_id": "SR-007", "verdict": "uphold|refute", "justification": "<one paragraph>"}
```

## Verifier output shape (`fix-coherence` lens; one JSON object)

```json
{"resolved": [{"sr_id": "SR-003", "resolved": true, "reason": "<one sentence>"}],
 "findings": [{"severity": "major", "location": "<## heading>", "description": "…",
               "proposed_fix": "…", "needs_decision": false,
               "fix_induced": true, "introduced_by": ["SR-003"]}],
 "rejected": ["<one line per self-falsified candidate>"]}
```

`resolved` carries exactly one entry per SR of batch A, judged against the SR
description alone (the verifier never holds a proposed fix). The orchestrator
checks the id set: a batch A SR missing from it is treated as unresolved and
enters batch B marked `re-fix`, and the omission is noted under Coverage.
`findings` are the defects the edits introduced; each names the SR ids whose
edits introduced it. The verifier's `rejected` list is recorded like a panel
reviewer's, labelled with the `fix-coherence` lens id.

## Fixer output shape (no writes — edit pairs only)

```json
{"edits": [{"sr_ids": ["SR-007", "SR-011"], "old": "<exact current text>",
            "new": "<replacement>"}],
 "growth": {"net_lines": 12, "drivers": ["SR-007"]},
 "notes": "<per-SR reasons when no unique pair could be produced>"}
```

A pair lists every SR it resolves in `sr_ids`; several pairs may share an SR.
`growth.net_lines` is the fixer's own estimate of the batch's net line delta
and `growth.drivers` the SR ids whose pairs account for most of it — advisory,
shown at the gate beside the measured figure. An SR that no returned pair lists
is `fix-failed`; the reason belongs in `notes`.

## SR ids and anchors (one run)

- SR ids are assigned once per registry entry, in discovery order: panel order
  as logged, then each reviewer's own output order; fix-induced findings from the
  verifier take the next ids. Every run starts at SR-001. Ids are never reused
  across runs — there is no registry to continue.
- Location anchor: nearest enclosing `##` heading slug (GitHub-style: lowercase,
  spaces→hyphens, punctuation stripped; duplicates get `-2`, `-3`).
  Pre-first-heading content → `__preamble__`; locationless/document-level →
  `__document__`; cross-section → first-cited section's slug, **with the other
  section named in the canonical phrase** (without it, two cross-section findings
  sharing a first-cited heading can false-merge).
- Canonical phrase: an orchestrator-derived ≤10-word identity phrase; the
  original description is never replaced.
- Duplicate matching is within the panel only: slug equality plus an
  orchestrator yes/no equivalence judgment, logged in the report. Duplicates merge
  to one entry at maximum severity, recording every contributing lens.

## Markers

- `re-derive` — the pair never landed (mismatch, no pair, or fixer failure). The
  fixer derives a fresh pair against the current text; a decided `new` text is
  preserved.
- `re-fix` — the batch A edit landed and the verifier judged the defect
  unresolved (or omitted the SR). `old` targets the applied text and the fix
  must change it. For a user-decided entry this is a new decision: the fixer may
  depart from the decided text; in default mode the approve gate shows the
  departure, in `--no-approve` the entry is re-asked before the fixer runs.

## Outcome enum (exhaustive — every emitted finding gets exactly one)

`applied` (a batch A edit landed) · `applied (not re-reviewed)` (a batch B edit
landed, or a batch A edit landed and no verifier read it) · `fix-failed` (a
batched fix did not land — pair mismatch, no pair, or fixer failure; after batch
B it stays and makes the run incomplete) · `refuted` (a critical a challenger
refuted) · `reported-only` (minors and nits, and sub-major needs-decision
entries — never batched) · `accepted-risk` (user chose keep-as-is) ·
`pending-decision` (`--auto` skipped a needs-decision entry) · `declined` (user
deselected the group at the gate) · `confirmed (not fixed — stopped)` (a major+
entry a stop left unfixed, including a verifier-unresolved batch A entry whose
batch B never ran — its Residuals line says the edit did land).

## Terminal statuses

`TRIAGED` · `TRIAGED (incomplete)` ·
`STOPPED(user-declined | budget | interaction-unavailable | external-edit)`.
`TRIAGED (incomplete)` is set by any of: a lens not returned, a verifier that was
dispatched and did not return after its retry (a skipped Stage 4 is not such a
case), a `fix-failed` entry after batch B, a `pending-decision` entry. A stop is
never success. Every verdict is advisory.

## Report header and skeleton

Path: `docs/superpowers/specs/reviews/<spec>-review.md`. Re-run detection reads
the `post-loop` hash line, so both hash lines are mandatory and verbatim.

```markdown
# Spec-review report — <spec>.md
**Mode:** default | --no-approve | --auto · **Budgets used:** <D> of <max> dispatches, <S> of <budget> active seconds · **Terminal status:** `<status>` · **Verdict label:** <label>
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
## Residuals
- confirmed (not fixed — stopped) · fix-failed · pending-decision · declined · accepted-risk · applied (not re-reviewed) · reported-only
- Ordered most- to least-serious; `confirmed (not fixed — stopped)` and `fix-failed` entries carry their full description, not just an SR id.
## Coverage
- Lenses not selected · not returned (with reasons) · standing blind spots (intent, external facts, unstated requirements)
## Rejected by the panel and the verifier (self-falsification)
- `- [lens] candidate — why it was refuted`; `None` when empty. Never rendered as findings.
## Residual risks
## Recovery
- Loop-touched files, snapshot path; never `git restore` on the spec
```
````

- [ ] **Step 2: Run the checker for this file**

Run: `python3 plugins/superutils/tests/check_contract.py --file fmt`
Expected: `Contract OK: 1 file(s)`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add plugins/superutils/skills/spec-report-format/SKILL.md
AV_COMMIT_SKILL=1 git commit --no-gpg-sign -m "feat(superutils)!: rewrite the report format for the single-run triage pipeline"
```

---

### Task 3: Update the `lens-catalog` skill

**Files:**
- Modify: `plugins/superutils/skills/lens-catalog/SKILL.md:8-10` (preamble), `:105-107` (lens `contracts` — insert the new lens after it, before `## Panel selection` at line 109), `:119` (panel selection rule 5), `:125-126` (the `major` anchor)

**Interfaces:**
- Consumes: nothing.
- Produces: lens id `fix-coherence` (verification only) that the command's Stage 4 and the reviewer agent name; panel rule "No cap"; the tightened `major` anchor.

- [ ] **Step 1: Replace the preamble (lines 8–10)**

Old:

```markdown
A lens is one reviewer's single perspective. The orchestrator selects 3–6
lenses per round; the two core lenses are always on. Panel composition and
selection rationale are logged in the sidecar every round.
```

New:

```markdown
A lens is one reviewer's single perspective. The orchestrator dispatches every
panel lens the selection rules name — there is no cap — and the two core lenses
are always on. Panel composition and rationale are logged in the report. One
lens, `fix-coherence`, is never on a panel: it verifies a fix batch.
```

- [ ] **Step 2: Insert the verification lens after the `contracts` lens (after line 107, before `## Panel selection` at line 109, separated by blank lines)**

```markdown
### Lens: fix-coherence (verification only — never selected for a panel)
Mandate: given the spec, the unified diff of the applied batch, and the batch's
SR list (id, severity, description — no proposed fix), answer two questions.
(1) Per SR: judged against the SR description alone, does the spec as edited
still exhibit the defect → `resolved: true|false` with a reason. How the edit
was made is never a ground for `false`; an edit that removes the defect by any
means is `resolved: true`. (2) Do the edits, read against the whole spec,
introduce a contradiction, an ambiguity, or a dangling reference that was not
there before → findings tagged `fix_induced: true`, each naming the SR ids whose
edits introduced it. Out of mandate: any defect the batch did not touch. Output
is the verifier shape in the spec-report-format skill.
```

- [ ] **Step 3: Replace panel-selection rule 5 (line 119)**

Old: `5. Cap at 6. Log the selected ids and one-line rationale in the sidecar.`

New: `5. No cap: the roster is the ceiling. Log the selected ids and one-line rationale in the report.`

- [ ] **Step 4: Tighten the `major` anchor (lines 125–126)**

Old:

```markdown
- **major** — two competent implementers would build observably different
  load-bearing behavior.
```

New:

```markdown
- **major** — two competent implementers would build observably different
  load-bearing behavior, **and the spec's own text does not arbitrate between
  the readings**. When another passage settles it, the defect is a
  cross-reference gap: minor.
```

- [ ] **Step 5: Run the checker for this file**

Run: `python3 plugins/superutils/tests/check_contract.py --file cat`
Expected: `Contract OK: 1 file(s)`. If it prints `cat: forbidden 'logged in the sidecar' found`, one of the two mentions (preamble, rule 5) survived — Steps 1 and 3 are the only two in the current text. The doctrine bar's own `sidecar`, `no-progress` and `oscillation` (items 7 and 10) are exempt and must stay.

- [ ] **Step 6: Confirm the doctrine bar copy is untouched**

Run: `git diff plugins/superutils/skills/lens-catalog/SKILL.md | grep -E '^-' | grep -vE '^---' | wc -l`
Expected: `6` — the three preamble lines, rule 5, and the two `major` anchor lines are the only removed lines. Any other number means an edit strayed into the doctrine bar or another lens; inspect `git diff` and revert the stray hunk.

- [ ] **Step 7: Commit**

```bash
git add plugins/superutils/skills/lens-catalog/SKILL.md
AV_COMMIT_SKILL=1 git commit --no-gpg-sign -m "feat(superutils): add the fix-coherence lens, drop the panel cap, tighten the major anchor"
```

---

### Task 4: Update the three agents

**Files:**
- Modify: `plugins/superutils/agents/spec-reviewer.md` (whole file, small changes)
- Modify: `plugins/superutils/agents/spec-challenger.md:1-6` (frontmatter description) and `:10-11`
- Modify: `plugins/superutils/agents/spec-fixer.md` (whole file)

**Interfaces:**
- Consumes: the verifier and fixer shapes from Task 2; lens id `fix-coherence` from Task 3.
- Produces: agents the command (Task 5) dispatches by name: `superutils:spec-reviewer` (panel lens or `fix-coherence`), `superutils:spec-challenger` (one critical), `superutils:spec-fixer` (a batch with `re-derive`/`re-fix` markers).

- [ ] **Step 1: Replace `spec-reviewer.md` with this content**

```markdown
---
name: spec-reviewer
description: Single-lens spec reviewer for the /superutils:spec-review triage pipeline. Reviews a design spec through exactly one assigned lens — a panel lens, or fix-coherence to verify an applied batch — and returns raw JSON after a self-falsification pass.
tools: Read, Grep, Glob
model: opus
skills: lens-catalog, spec-report-format
---

# Spec Reviewer Agent

You review ONE design spec through ONE lens. Nothing outside your lens's
mandate is your business — do not report style, preferences, or another
lens's domain.

## Input (in your dispatch prompt)

1. **Lens** — id and mandate (from the lens catalog; follow it exactly).
2. **Spec path** — read the full file.
3. **Unit list** — the spec's `##` sections, as a reading guide only.
4. **`fix-coherence` only:** the path of the batch diff file and the path of
   the SR list file (id, severity, description per SR). Both live in the session
   scratchpad, outside the repository.

A panel lens receives nothing beyond items 1–3 by design (fresh panel). Only the
`feasibility` and `doctrine-compliance` lenses may read other repo files; the
`fix-coherence` lens reads the two files it is given and nothing else outside
the spec.

## Rules

- **Never read the pipeline's own state.** `docs/superpowers/specs/reviews/**`
  (reports, snapshots, archives) is off limits — it is the answer key, and a
  fresh panel that reads it is no longer fresh. If you open such a file by
  accident, discard what you saw and report nothing from it.
- Grade severity and needs_decision strictly by the anchors in the
  lens-catalog skill.
- Do NOT compute SR ids or fingerprints; `location` is the verbatim `##`
  heading text (empty when locationless). The `fix-coherence` lens echoes the
  SR ids it was given in the SR list — it never derives one.
- Do NOT report gaps the spec explicitly delegates to a named deliverable,
  explicitly defers (Out of scope), or explicitly flags as an open question.
- Self-falsification is mandatory: attempt to refute every candidate from the
  reviewed text before reporting; rejected candidates go in `rejected`, one
  line each — never silently dropped.

## Output

Your final message is parsed, not read by a human. Return EXACTLY one JSON
object — the reviewer finding shape for a panel lens, the verifier shape for
`fix-coherence` — as defined in the spec-report-format skill, with no prose
before or after it. The orchestrator records your `rejected` list in the
report; it is output, not scratch.
```

- [ ] **Step 2: Edit `spec-challenger.md`**

Change the frontmatter `description:` line to:

```yaml
description: Adversarial verifier for the /superutils:spec-review triage pipeline. Receives exactly one critical finding and tries to refute it against the spec text; returns uphold or refute at the finder's severity.
```

Change the Input item 1 sentence `1. **The finding** — SR id, severity, every finder's description (a merged` so the item reads:

```markdown
1. **The finding** — a critical: SR id, severity, every finder's description (a
   merged entry carries all of them), and the proposed fix. Majors are never
   sent to you.
```

Leave every rule and the output section as they are.

- [ ] **Step 3: Replace `spec-fixer.md` with this content**

```markdown
---
name: spec-fixer
description: Edit-pair proposer for the /superutils:spec-review triage pipeline. Turns a fix batch into exact {old, new} replacement pairs that are coherent as one edit set. Performs no writes — the orchestrator applies approved pairs.
tools: Read, Grep, Glob
model: opus
skills: spec-report-format
---

# Spec Fixer Agent

You turn a batch of findings into exact text replacements for ONE spec file.
You have no write tools by design: you propose, the orchestrator applies.

## Input (in your dispatch prompt)

1. **Fix batch** — findings as {SR id, severity, description, proposed fix}.
   For user-decided findings the decided edit content is included verbatim —
   reproduce it exactly unless the entry is marked `re-fix` (below). Entries may
   carry one marker:
   - **`re-derive`** — a previous pair never landed. It carries the `old` text
     that failed to match (or nothing, after a fixer failure). Derive a fresh
     pair against the *current* text, preserving a decided `new` text.
   - **`re-fix`** — the previous edit landed and the verifier judged the defect
     unresolved. It carries the verifier's reason and the applied `new` text now
     standing in the spec. Your `old` must target that applied text and your
     `new` must change it; a decided text may be departed from — the
     orchestrator treats the entry as a new decision.
2. **Spec path** — read the full current file before proposing.

## Rules

- **The batch is one edit set, not a sum of independent patches.** Two findings
  touching one passage yield one pair; a merged pair lists every SR it resolves
  in `sr_ids`. Read the whole spec before proposing, and check that new text does
  not contradict neighbouring sections.
- **Rewrite before append.** The default form of a fix is a change to an
  existing sentence or paragraph. Adding a new paragraph is reserved for findings
  about missing content (a `completeness` finding, or a decided edit that
  supplies new text).
- Each pair: `old` must match the current spec text byte-exactly and uniquely;
  `new` is the complete replacement. Several pairs may share an SR id.
- Fix ONLY what the batch lists. No opportunistic improvements, reformatting, or
  fixes to problems you notice along the way.
- If a finding cannot be implemented as a unique replacement (text moved,
  ambiguous match), return no pair for it and name it in `notes` — the
  orchestrator marks it `fix-failed`. Never guess.
- **Growth accounting.** Report `growth.net_lines` — your estimate of the
  batch's net line delta — and `growth.drivers`, the SR ids whose pairs account
  for most of it. It is shown at the gate beside the measured figure; it is a
  metric, not a limit.

## Output

Your final message is parsed, not read by a human. Return EXACTLY one JSON
object in the fixer shape from the spec-report-format skill:
`{"edits": [{"sr_ids": ["…"], "old": "…", "new": "…"}], "growth": {"net_lines": N, "drivers": ["…"]}, "notes": "…"}`.
```

- [ ] **Step 4: Run the checker for the three agents**

Run: `for k in rev chl fix; do python3 plugins/superutils/tests/check_contract.py --file $k; done`
Expected: three lines `Contract OK: 1 file(s)`.

- [ ] **Step 5: Run the frontmatter validator**

Run: `python3 scripts/check_agent_frontmatter.py`
Expected: exit 0 and `Agent frontmatter OK: 26 file(s) scanned, 12 warning(s).` — the same counts as before this plan (26 files, 12 warnings; the warnings are pre-existing per-tool MCP names in other plugins). A different file count means an agent file was added or removed by mistake.

- [ ] **Step 6: Commit**

```bash
git add plugins/superutils/agents/spec-reviewer.md plugins/superutils/agents/spec-challenger.md plugins/superutils/agents/spec-fixer.md
AV_COMMIT_SKILL=1 git commit --no-gpg-sign -m "feat(superutils): teach the agents the fix-coherence lens, sr_ids pairs and the re-fix marker"
```

---

### Task 5: Rewrite the command

The contract itself. Replace the 344-line convergence loop with the five-stage pipeline.

**Files:**
- Modify: `plugins/superutils/commands/spec-review.md` (replace the whole file; keep the `allowed-tools:` line byte-identical)

**Interfaces:**
- Consumes: agent names from Task 4; lens rules from Task 3; shapes, enum, statuses and report skeleton from Task 2.
- Produces: the runnable `/superutils:spec-review` contract; the report file at `docs/superpowers/specs/reviews/<spec>-review.md` whose `post-loop` hash line the next run reads.

- [ ] **Step 1: Copy the current `allowed-tools:` line aside**

Run: `sed -n '2p' plugins/superutils/commands/spec-review.md > /tmp/allowed-tools.line && head -c 60 /tmp/allowed-tools.line`
Expected: the line starting `allowed-tools: Bash(ls:*), Bash(stat:*), …`. Step 2's file must begin with exactly this line as line 2.

- [ ] **Step 2: Replace the file with this content (line 2 is the current `allowed-tools:` line, reproduced verbatim)**

````markdown
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
````

- [ ] **Step 3: Restore the `allowed-tools:` line and verify it is byte-identical to the original**

Run: `python3 - <<'PY'
from pathlib import Path
p = Path("plugins/superutils/commands/spec-review.md"); lines = p.read_text().splitlines(keepends=True)
saved = Path("/tmp/allowed-tools.line").read_text()
assert lines[1].startswith("allowed-tools:"), lines[1]
lines[1] = saved
p.write_text("".join(lines))
print("restored; identical:", lines[1] == saved)
PY
git show HEAD:plugins/superutils/commands/spec-review.md | sed -n '2p' | diff - <(sed -n '2p' plugins/superutils/commands/spec-review.md) && echo "allowed-tools unchanged"`
Expected: `restored; identical: True` and `allowed-tools unchanged`.

- [ ] **Step 4: Run the checker for the command**

Run: `python3 plugins/superutils/tests/check_contract.py --file cmd`
Expected: `Contract OK: 1 file(s)`.

- [ ] **Step 5: Measure the contract**

Run: `wc -l plugins/superutils/commands/spec-review.md`
Expected: between 300 and 340 lines — the content in Step 2 is 319 lines as written (the spec's "≈130" counted body prose without the flag table, the error table and the batch procedure). Above 360 means text from the old loop survived — grep for `round` and `registry carry` and remove it; below 300 means a section of Step 2 was dropped — compare the headings against Step 2.

- [ ] **Step 6: Run the execution-boundary validator (it scans every `*/commands/*.md`)**

Run: `python3 scripts/check_execution_boundary.py`
Expected: exit 0, `Execution boundary OK: 68 file(s) scanned, 0 warning(s).`

- [ ] **Step 7: Commit**

```bash
git add plugins/superutils/commands/spec-review.md
AV_COMMIT_SKILL=1 git commit --no-gpg-sign -m "feat(superutils)!: replace the convergence loop with the bounded triage pipeline"
```

---

### Task 6: Update the acceptance protocol

**Files:**
- Modify: `plugins/superutils/tests/ACCEPTANCE.md:9-11`, `:22`, `:43-44`

**Interfaces:**
- Consumes: status `TRIAGED` (Task 2), report path (Task 5).
- Produces: the release gate a human runs before tagging 2.0.0.

- [ ] **Step 1: Edit the three passages**

Line 9–11, old:

```markdown
Each run starts fresh: copy `fixtures/seeded-spec.md` to
`docs/superpowers/specs/seeded-spec.md` in a scratch branch, with no sidecar,
report, or snapshot present.
```

New:

```markdown
Each run starts fresh: copy `fixtures/seeded-spec.md` to
`docs/superpowers/specs/seeded-spec.md` in a scratch branch, with no report or
snapshot present under `docs/superpowers/specs/reviews/`.
```

Line 22, old: `Terminal status `CONVERGED` within default budgets AND all three post-run`
New: `Terminal status `TRIAGED` (not `TRIAGED (incomplete)`) within default budgets AND all three post-run`

Lines 43–44, old:

```markdown
terminal status within default budgets and a report + sidecar conforming to
`superutils:spec-report-format`.
```

New:

```markdown
terminal status within default budgets and a report conforming to
`superutils:spec-report-format`, with both hash lines present.
```

- [ ] **Step 2: Run the checker for this file**

Run: `python3 plugins/superutils/tests/check_contract.py --file acc`
Expected: `Contract OK: 1 file(s)`.

- [ ] **Step 3: Commit**

```bash
git add plugins/superutils/tests/ACCEPTANCE.md
AV_COMMIT_SKILL=1 git commit --no-gpg-sign -m "test(superutils): make TRIAGED the acceptance pass condition and drop the sidecar"
```

---

### Task 7: Documentation and the 2.0.0 version bump

**Files:**
- Modify: `plugins/superutils/.claude-plugin/plugin.json` (`version`, `description`)
- Modify: `.claude-plugin/marketplace.json` (the `superutils` entry's `version` and `description`)
- Modify: `README.md:44` (the Superutils row)
- Modify: `docs/plugins/superutils.md` (replace the whole file)
- Modify: `docs/workflow.md:44-59` (Stage 2)

**Interfaces:**
- Consumes: everything above.
- Produces: the four version sites `scripts/check_plugin_versions.py` compares; user-facing docs the checker reads (`doc`, `wf`, `readme`).

- [ ] **Step 1: Bump `plugins/superutils/.claude-plugin/plugin.json`**

```json
{
  "name": "superutils",
  "description": "Companion utilities for the superpowers workflow — bounded, loop-engineered triage of design specs.",
  "version": "2.0.0"
}
```

- [ ] **Step 2: Bump the marketplace entry**

Run: `python3 - <<'PY'
import json; from pathlib import Path
p = Path(".claude-plugin/marketplace.json"); m = json.loads(p.read_text())
e = next(x for x in m["plugins"] if x["name"] == "superutils")
e["version"] = "2.0.0"; e["description"] = "Companion utilities for the superpowers workflow — bounded, loop-engineered triage of design specs."
p.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n"); print(e)
PY`
Expected: the printed entry shows `'version': '2.0.0'`. Then run `git diff --stat .claude-plugin/marketplace.json` — expected `1 file changed, 2 insertions(+), 2 deletions(-)`; if the diff is larger, the file's indentation or key order was rewritten — restore it with `git checkout .claude-plugin/marketplace.json` and edit the two values by hand instead.

- [ ] **Step 3: Replace README line 44 (the Superutils row)**

```markdown
| [Superutils](docs/plugins/superutils.md) | 2.0.0 | Companion utilities for the superpowers workflow. `/superutils:spec-review` runs a bounded triage pipeline on design specs: MoA lens panel, challengers for criticals, one approve-gated fix batch, verification of the applied edits, one final batch — hard dispatch and time budgets, every residual reported, every verdict advisory (never "Verified") |
```

- [ ] **Step 4: Replace `docs/plugins/superutils.md` with this content**

````markdown
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
````

- [ ] **Step 5: Replace Stage 2 of `docs/workflow.md` (lines 44–59)**

```markdown
### Stage 2 — Spec review *(superutils)*

**Purpose:** catch contradictions, ambiguity, and gaps while they are
still cheap to fix.

```
/superutils:spec-review
```

Runs a fixed triage pipeline on the newest spec (lens panel → challengers
for criticals → one approve-gated fix batch → verification of the applied
edits → one final batch). One pass; nothing repeats.

**Artifact:** report and pre-loop snapshot in
`docs/superpowers/specs/reviews/`; terminal status `TRIAGED`
(`TRIAGED (incomplete)` when something the pipeline owed did not land or
return) or `STOPPED(...)` — a stop is never success.
**Next stage consumes:** the reviewed spec, now the contract for the plan —
passed by you: unlike the other hand-offs, Stage 3 does not discover it on
its own; reference the spec in the task or plan you hand to it.
```

- [ ] **Step 6: Run the version-parity validator and the checker**

Run: `python3 scripts/check_plugin_versions.py && python3 plugins/superutils/tests/check_contract.py`
Expected: `Version parity OK for 9 plugin(s).` then `Contract OK: 10 file(s)`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/superutils/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md docs/plugins/superutils.md docs/workflow.md
AV_COMMIT_SKILL=1 git commit --no-gpg-sign -m "docs(superutils): document the triage pipeline and release 2.0.0"
```

---

### Task 8: Whole-tree verification and a mutation test of the checker

**Files:**
- No new files. Reads everything above.

**Interfaces:**
- Consumes: the finished tree.
- Produces: evidence, pasted into the task report, that every oracle is green and that the checker actually discriminates.

- [ ] **Step 1: Run every oracle**

Run:

```bash
python3 scripts/check_agent_frontmatter.py && python3 scripts/check_plugin_versions.py && python3 scripts/check_execution_boundary.py && python3 scripts/test_check_agent_frontmatter.py && python3 scripts/test_check_execution_boundary.py && python3 plugins/superutils/tests/check_contract.py
```

Expected: every command exits 0; the last line is `Contract OK: 10 file(s)`.

- [ ] **Step 2: Mutation-test the checker (it must fail when the contract regresses)**

Run:

```bash
cp plugins/superutils/commands/spec-review.md /tmp/cmd.bak
printf '\nThe old loop converged when CONVERGED.\n' >> plugins/superutils/commands/spec-review.md
python3 plugins/superutils/tests/check_contract.py --file cmd; echo "exit=$?"
cp /tmp/cmd.bak plugins/superutils/commands/spec-review.md
python3 plugins/superutils/tests/check_contract.py --file cmd; echo "exit=$?"
```

Expected: first run prints `cmd: forbidden 'CONVERGED' found` and `exit=1`; second run prints `Contract OK: 1 file(s)` and `exit=0`. Then `git status --short` must show nothing under `plugins/superutils/commands/`.

- [ ] **Step 3: Grep the whole plugin for leftovers the checker does not cover**

Run: `grep -rnE 'round [0-9r]|per round|fresh-panel|fresh panel re-review|max\+1|registry carry' plugins/superutils docs/plugins/superutils.md docs/workflow.md || echo "no leftovers"`
Expected: `no leftovers`. (`fresh panel` in the reviewer agent's "fresh panel" parenthetical is acceptable only in the exact phrase `by design (fresh panel)`; anything else is old-loop text — remove it.)

- [ ] **Step 4: Paste the evidence and record the deviation list**

In the task report, paste the verbatim output of Steps 1–3 and `git log --oneline e2e035a..HEAD`. Expected: seven commits above `e2e035a` (Tasks 1–7), each with the message given in its task.

- [ ] **Step 5: No commit** — this task changes nothing. If Step 3 found leftovers, fix them in the file they live in and commit as `fix(superutils): remove old-loop leftovers from <file>`.

---

## Follow-ups outside this plan

- **Acceptance protocol run** (`plugins/superutils/tests/ACCEPTANCE.md`): a human runs three seeded-fixture passes and one dogfood pass. The spec names sub-project B's design spec as the dogfood target; that spec does not exist yet.
- **Re-signing commits:** the commits above are unsigned by necessity; re-sign before the PR if the repository requires signed history.
- **Sub-project B** (lightweight in-flight code review) is brainstormed separately.

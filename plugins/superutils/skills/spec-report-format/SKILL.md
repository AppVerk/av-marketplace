---
name: spec-report-format
description: Report structure, sidecar schema, SR-id rules, outcome enum, and terminal statuses for the /superutils:spec-review loop. Load when reading or writing spec-review loop state or reports. (Distinct from qa:report-format, which is the QA test-report format.)
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
 "obsolete": [{"sr_id": "SR-009", "evidence": "<current text proving the defect is already gone>"}],
 "notes": "<per-SR reasons when no unique pair could be produced — orchestrator marks those fix-failed>"}
```

`obsolete` is the **only** channel for "this defect no longer exists"; it is not
`notes`. "I could not produce a unique pair" belongs in `notes` and yields
`fix-failed`. Conflating them retires real, unfixed defects.

## SR ids and registry identity

- SR ids are assigned once per issue, in discovery order (panel order as
  logged, then each reviewer's own output order), reused on reappearance;
  a later run continues at max+1.
- Location anchor: nearest enclosing `##` heading slug (GitHub-style:
  lowercase, spaces→hyphens, punctuation stripped; duplicates get `-2`, `-3`).
  Pre-first-heading content → `__preamble__`; locationless/document-level →
  `__document__`; cross-section → first-cited section's slug, **with the other
  section named in the canonical phrase** (without it, two cross-section
  findings sharing a first-cited heading can false-merge).
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
     "severity": "major", "lenses": ["completeness"], "needs_decision": false,
     "unlanded": true, "unconfirmed": false, "fix_failures": 1}
  ],
  "rounds": [
    {"round": 1, "panel": ["internal-consistency", "…"], "panel_rationale": "…",
     "units": ["…"],
     "findings": [{"sr_id": "SR-001", "severity": "major",
                   "lenses": ["completeness"], "outcome": "applied"}],
     "rejected": [{"lens": "internal-consistency", "candidate": "…"}],
     "equivalence_log": [{"a": "SR-001", "b": "SR-004", "match": true}]}
  ]
}
```

Round findings carry their **round-local** severity and lens set: both are
mutable across rounds, so back-filling them from the registry would render an
early round with a later round's escalated severity and erase the trajectory
the report exists to show.

`rejected` holds every reviewer's self-falsified candidates verbatim, one entry
per candidate. It is written every round and rendered in the report: a
fresh-panel loop re-derives the same ghosts by design, and dropping the list is
the very "silent drop" every reviewer is forbidden to perform.

`decisions.edit` preserves the exact pair for accepted decisions (including
user-supplied alternatives) so replay never re-derives a fix — **unless the
entry is an unlanded fix**, in which case the stored pair is known not to match
and the fixer re-derives an equivalent edit preserving the decided `new` text.

Registry flags `unlanded` / `unconfirmed` / `fix_failures` are **per-entry loop
state, not per-round outcomes** — they persist across rounds, across a resume,
and across a new run on an edited spec, together with the registry entry itself.
`unlanded` is cleared by exactly four events: a successful apply, an `obsolete`
verdict, a user `declined` at the batch gate, or a stale-drop in the tamper flow
(the entry's heading slug no longer exists). `unconfirmed` is cleared only by a
returned challenger verdict. **A stale-drop that discards unfinished work is
reported** — under Coverage, naming the SR ids and what was outstanding — since
the loop is vacating a promise it cannot keep, not fulfilling it.

## Outcome enum (exhaustive — every emitted finding gets exactly one)

`applied` · `applied (not re-reviewed)` (final permitted round, under
STOPPED(budget)) · `fix-failed` (a batched fix did not land — pair mismatch, no
pair returned, or fixer failure → registry flag `unlanded: true`, `fix_failures`
incremented. **At any severity, minor and nit included**, an unlanded fix closes
every convergence exit, is never re-challenged or refuted, and is never settled
by a user decision it carries; it is re-batched with a **re-derived** pair, and
is cleared only by a successful apply. `fix_failures` gates the retry only: at
≤ 1 Step 5 excludes it from the no-progress comparison so the retry can run; at
≥ 2 — the re-derived pair failed too — it stays in the comparison, so an
unlandable fix stops the run as `STOPPED(no-progress)` instead of consuming the
iteration cap) · `obsolete` (the fresh panel no longer finds the entry **and**
the fixer reports its target text is gone — the defect is fixed, not unfixed;
the only vacate path for `unlanded`, never a way to retire a failed fix)
· `refuted` · `unconfirmed` (challenger failed
twice, or was never dispatched at a budget stop; registry flag
`unconfirmed: true`; blocks convergence as its own condition; never treated as
refuted; excluded from the no-progress comparison; **re-dispatched every
following round until a verdict returns**) · `confirmed (not fixed
— stopped)` (significant findings **and unlanded fixes of any severity** of a
round that ends at **any** stop — oscillation, no-progress, budget,
pending-decisions, user-declined, interaction-unavailable, or external-edit —
whether it ends before or during its fix phase) · `reported-only` (sub-major
needs-decision, and any minor/nit of a round that ends before **or during** its
fix phase without being batched — **never an unlanded fix**, which was promised,
not merely reported) ·
`accepted-risk` (user keep-as-is) · `pending-decision` (`--auto` skip — always,
including in the round that triggers STOPPED(pending-decisions)) · `declined`
(user-declined at the batch gate; sticky; clears `unlanded` — a conscious
withdrawal, reported under Declined).

**Exhaustiveness rule.** Every emitted finding takes exactly one outcome on
every reachable path. When a round ends at a stop, each entry takes the outcome
its state implies — significant or unlanded → `confirmed (not fixed — stopped)`;
`--auto`-skipped → `pending-decision`; everything else minor/nit →
`reported-only`. An entry with an `accepted` decision **whose fix has landed**
is not exempt from a later round's adjudication: if a fresh panel re-finds it,
it is a normal finding again (challenger, significance, outcome) — the decision
settled *which* fix, not *whether* the defect exists.

**Unfinished work blocks success.** Convergence (Step 6 and Step 8.6) requires
all three: zero significant findings, **zero unlanded fixes**, **zero
`unconfirmed` entries**. The latter two are checked as their own conditions, not
as filters on the significant set — a minor/nit is never in that set, and an
`unconfirmed` entry survived no refutation, so folding either into the
significance test lets the loop converge green over an unlanded fix or an
unadjudicated major. No decision rule removes either. A loop that reports
`CONVERGED` while one is outstanding is reporting a fix that does not exist.

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
- Catalog lenses not selected this run: …
- Not returned (failures, with reasons): …
- Standing oracle blind spots: intent, external facts, unstated requirements.
## Rejected by the panel (self-falsification)
- Plain bullets, `- [lens] candidate — why it was refuted`; `None` when empty.
  Never rendered as findings.
## Accepted risks (user-decided)
## Declined (user-decided)
## Residual risks
## Recovery
- Loop-touched files + snapshot path (never `git restore` on the spec).
```

Shallow coverage (any selected lens failed to return) → WARNING in the report
and `CONVERGED (low-confidence)` when the run converged.

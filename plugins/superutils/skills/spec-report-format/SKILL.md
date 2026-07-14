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
 "notes": "<per-SR reasons when no unique pair could be produced — orchestrator marks those fix-failed>"}
```

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
     "severity": "major", "lenses": ["completeness"], "needs_decision": false}
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
entry's last outcome is `fix-failed`**, in which case the stored pair is known
not to match and the fixer re-derives an equivalent edit preserving the decided
`new` text.

## Outcome enum (exhaustive — every emitted finding gets exactly one)

`applied` · `applied (not re-reviewed)` (final permitted round, under
STOPPED(budget)) · `fix-failed` (pair did not match; **blocks convergence** —
the entry re-enters the next round's significant set without a challenger and
is re-batched with a re-derived pair; never treated as refuted or as settled by
its user decision) · `refuted` · `unconfirmed` (challenger failed
twice or never dispatched at a budget stop; blocks convergence; never treated
as refuted; excluded from the no-progress comparison) · `confirmed (not fixed
— stopped)` (significant findings of any round that ends before or during its
fix phase — oscillation, no-progress, budget, interaction-unavailable, or
external-edit) · `reported-only` (sub-major needs-decision, and any
minor/nit of a round that ends before its fix phase) · `accepted-risk` (user
keep-as-is) · `pending-decision` (`--auto` skip — always, including in the
round that triggers STOPPED(pending-decisions)) · `declined` (user-declined
at the batch gate; sticky).

The two convergence-blocking outcomes are `unconfirmed` (never verified) and
`fix-failed` (verified, promised, not landed). Neither may be filtered out of
the significant set by any decision rule: a loop that reports `CONVERGED` while
one is outstanding is reporting a fix that does not exist.

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

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

`resolved` carries exactly one entry per landed SR of batch A (`applied`);
declined, fix-failed and accepted-risk entries are never in the list, judged
against the SR description alone (the verifier never holds a proposed fix). The
orchestrator checks the id set: a batch A SR missing from it is treated as
unresolved and enters batch B marked `re-fix`, and the omission is noted under
Coverage.
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
## Decisions
| SR | decision | edit text (verbatim) |
## Residuals
- confirmed (not fixed — stopped) · fix-failed · pending-decision · declined · accepted-risk · applied (not re-reviewed) · reported-only
- Ordered most- to least-serious; `confirmed (not fixed — stopped)` and `fix-failed` entries carry their full description, not just an SR id, and a `fix-failed` entry quotes the fixer's `notes` reason.
## Coverage
- Lenses not selected · not returned (with reasons) · standing blind spots (intent, external facts, unstated requirements)
## Rejected by the panel and the verifier (self-falsification)
- `- [lens] candidate — why it was refuted`; `None` when empty. Never rendered as findings.
## Residual risks
## Recovery
- Loop-touched files, snapshot path; never `git restore` on the spec
```

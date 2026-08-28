# Scripted Answers — needs-decision end-to-end fixture

These are the operator's scripted answers for both entry runs
(`/fix-all` and `/fix-report`) against `report.md` in this directory.
They exist so the run is reproducible and so the post-conditions in
`RUNBOOK.md` are bound to a specific handling of each finding, rather
than to whatever an improvised sweep happens to produce (spec
`Verification` step 4, lines 1238–1285: "neither is a sweep the
operator improvises").

Answer **only** the decision-stage asks these findings trigger. Anything
else the run asks (the pre-flight yes/no, the Step 5 offer to enter the
decision stage, `AskUserQuestion` confirmations of restated text, etc.)
is answered in the obvious way needed to reach the finding below — this
file scripts the findings' own decisions, not the whole transcript.

---

## DOC-001, DOC-002 — `auto`

No decision-stage answer applies; these are fixed directly by
`fix-auto` in the ordinary batch. Nothing to script.

---

## DOC-003 — stage 0 (`**Location:** —`)

When stage 0 asks for a `path:line` to anchor this finding (it has none
— `**Location:** —`), **decline to supply one**. In `AskUserQuestion`
terms: answer with the tool's built-in way of declining / providing no
path (e.g. `other…` left empty, or the option that means "I don't have
one" if the ask renders one — whichever the live render offers; the
requirement is that no `path:line` is supplied).

Expected effect per the decision-gate skill (`Stage 0 → Declined
targets`): DOC-003 is reported **Failed** in the run summary, no
`**Status:**` line is written to `report.md`, and it is never dispatched
to an analyst.

---

## DOC-004 — reject, with a stated reason

DOC-004 is the live-referent case: `target-a.md:13` cites a "Rollback
Procedures" section in `target-b.md` that does not exist under that
exact title — but `target-b.md:6` genuinely has the same content under
the heading "Emergency Rollback". A real analyst reading `target-b.md`
should find this and return a `Rejection candidate`, backed by a
re-runnable citation such as:

```
grep -n "Rollback" docs/testing/fixtures/needs-decision-e2e/target-b.md
```

whose recorded output includes the line `6:## Emergency Rollback`. At
the reject gate the orchestrator re-runs that exact citation and shows
the raw output before offering `reject`.

**Answer: choose `reject`.**

When prompted for/confirming the reason, use (or confirm the analyst's
prefilled reason if it says materially the same thing):

> The referent exists in target-b.md under the heading "Emergency
> Rollback" — the cross-reference in target-a.md names it "Rollback
> Procedures", a rename, not a dead reference.

Do **not** accept a run where the analyst's block carries no
`Rejection candidate` for DOC-004 — per spec lines 1238–1285, a rejection
without a candidate is graded `unverified`, and "a run in which the
analyst returned no candidate for finding 2 does not satisfy the step,
however the status line reads." If the live analyst fails to surface a
candidate, that is a finding about the run, not something to paper over
by rejecting anyway — see `RUNBOOK.md`'s post-condition list.

Expected effect: `**Status:** 🚫 Rejected (YYYY-MM-DD) — <reason>` is
written to `report.md` for DOC-004, with **no** `**Decision:**` line,
and the run summary does **not** mark this rejection `unverified`.

---

## DOC-005 — choose A

DOC-005 is the ordinary dead-reference case: `target-b.md:13` cites
`scripts/generate-legacy-report.sh`, which does not exist anywhere in
the repository (confirmed — no renamed or relocated referent, unlike
DOC-004). Its `Drift-class` is `dead-reference`, so the analyst derives
alternatives structurally — per `decision-gate/SKILL.md`'s
`**Alternatives:**` render-format table, `dead-reference` gives "remove
the mention **vs** restore/update the referent", in that order, which
this fixture expects to render as **A = remove the mention**, **B =
restore/update the referent**.

**Answer: choose whichever option the live sweep renders as `[A]`** —
the scripted answer is the **label**, not a specific action. If the
live render's `[A]` turns out to read as "restore" rather than
"remove" (i.e. the order above did not hold), still answer `A`; do not
override the script based on the wording. Either way, confirm afterward
which action DOC-005's `**Decision:**` line actually recorded, since
the post-conditions in `RUNBOOK.md` are written against "whichever
resolution `A` names," not against "remove" specifically — except
where a post-condition names the concrete edit (see below), which
assumes the expected order held.

The natural hard, executable verification for this alternative is a
post-edit grep asserting the string is gone, e.g.:

```
grep -c "generate-legacy-report.sh" docs/testing/fixtures/needs-decision-e2e/target-b.md
```

expected result `0`. (The analyst derives and persists its own
`**Verification-plan:**` line at runtime; this is the shape it should
take, not text to paste in verbatim — check what the live run actually
records against `RUNBOOK.md`'s post-condition for DOC-005, in
particular that it is `hard`, not `advisory` or missing.)

If stage 2 or stage 3.5 asks for approval to run a check outside the
read-only + declared-command boundary, approve it only if it matches
the shape above (a plain `grep` over the fixture's own files) — nothing
about this fixture should need a test/build command or a write.

Expected effect: a `**Decision:**` line in the delimited grammar;
`**Location:**` rewritten to the analyst's verified `Target` normalised
to `path:line`, with `(was: `docs/testing/fixtures/needs-decision-e2e/target-b.md:13`)`
(or whatever the reviewer's original was) still recoverable; and
`**Status:** ✅ Fixed (YYYY-MM-DD)` with `**Verification:** hard — <the
checks actually run>`.

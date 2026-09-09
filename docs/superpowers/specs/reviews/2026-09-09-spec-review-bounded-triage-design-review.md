# Spec-review loop report — 2026-09-09-spec-review-bounded-triage-design.md

**Run:** 1 · **Mode:** default (approve-gated) · **Budgets used:** 1 of 3 rounds, 35 of 60 dispatches, ~1792 of 1800 active seconds (estimate, see Residual risks) · **Terminal status:** `STOPPED(budget)` · **Verdict label:** Re-reviewed (advisory)

**Spec hash (pre-loop):** `72694f75c2a3ac02b65b9abb9ff2040d30de7cea59a0eaabfa27ae478d43307e`  
**Spec hash (post-loop):** `9307e7f5217d24f89cb618cb59c50fea28eccfa6df8104a1b37c785f57694c30`  
**Spec lines:** 398 → 489 (+91, +23%)

This run is the dogfood the spec itself calls for: the shipped convergence loop reviewing the design of its bounded-triage replacement. One full round ran — six-lens panel, sixteen challengers, one fix batch of 41 pairs approved whole — and the loop stopped at the round-2 boundary on the time budget. **A stop is not success:** the 29 applied fixes were never read by a fresh panel.

## Why it stopped

Stopped at the round-2 panel boundary. The stage budget check reads active_seconds=1792 < 1800, but that figure is an estimate (wall clock minus estimated user waits; the harness exposes no active-time clock) whose error exceeds the 8-second margin, so the orchestrator treated the check as not positively established and failed closed rather than spend a six-dispatch panel whose challenger boundary would then sit at ~2300 s and stop the round before any fix. Round 1's 29 fixes were applied in the final executed round and take `applied (not re-reviewed)`. To continue: raise --time-budget and re-run; the spec's hash has changed, so a new run archives this report, carries the registry forward and starts a fresh panel at SR-031.

## Round 1 — panel, units

**Panel:** internal-consistency, ambiguity-testability, completeness, doctrine-compliance, ux, contracts  
**Rationale:** All seven roster lenses trigger (loop/plugin design -> doctrine-compliance + feasibility; interaction flows -> ux; JSON shapes/enums/statuses -> contracts). Cap 6 drops feasibility: every mechanism the spec relies on is already demonstrated by the shipped command it replaces, which the lens mandate treats as a refutation; repo-fact claims verified by the orchestrator directly. ux kept deliberately after the 2026-08-27 run dropped it five rounds running.  
**Units (13):** 1. Goal; 2. Why (measured, not felt); 3. Decisions taken; 4. Pipeline; 5. The batch procedure; 6. Components; 7. Budgets and error handling; 8. Doctrine compliance (qa:loop-engineering); 9. Report format; 10. Residual risks (to be carried into every report); 11. Testing; 12. Delivery; 13. Out of scope  
**Raw findings:** 35 → **30 registry entries** after within-round merging (16 major, 14 minor, 0 critical, 0 nit). Reviewer wall times: ux 284 s, completeness 303 s, ambiguity-testability 342 s, doctrine-compliance 330 s, contracts 449 s, internal-consistency 557 s.

| SR | severity | lenses | needs-decision | canonical phrase | outcome |
|---|---|---|---|---|---|
| SR-001 | major | internal-consistency, doctrine-compliance | — | doctrine row 2 misstates verifier inputs; verifier holds proposed fix | applied (not re-reviewed) |
| SR-002 | major | internal-consistency | — | merged pair carries one sr_id so co-finding fix-failed | applied (not re-reviewed) |
| SR-003 | major | internal-consistency | — | verifier skipped yet batch B edits unverified under plain TRIAGED | refuted |
| SR-004 | minor | internal-consistency | — | 78% challenger share is one run presented as three | applied (not re-reviewed) |
| SR-005 | minor | internal-consistency | — | interaction-unavailable before-any-write false after batch A | applied (not re-reviewed) |
| SR-006 | major | ambiguity-testability | — | verifier resolved means efficacy not compliance with proposed fix | applied (not re-reviewed) |
| SR-007 | major | ambiguity-testability, completeness, contracts | — | growth line base and fixer-vs-measured mismatch undefined | applied (not re-reviewed) |
| SR-008 | major | ambiguity-testability | — | verifier-unresolved entry outcome at stop before batch B | applied (not re-reviewed) |
| SR-009 | minor | ambiguity-testability | — | empty batch A input still dispatches fixer | applied (not re-reviewed) |
| SR-010 | minor | ambiguity-testability | — | verifier skipped readable as verifier not returned | applied (not re-reviewed) |
| SR-011 | major | completeness | — | re-derive entries carry no failure context to batch B fixer | applied (not re-reviewed) |
| SR-012 | minor | completeness | — | gate-emptied batch still dispatches fixer | applied (not re-reviewed) |
| SR-013 | minor | completeness, contracts | — | pre-2.0.0 report without hash line and stale sidecar unhandled | applied (not re-reviewed) |
| SR-014 | major | doctrine-compliance | — | item 9 N/A misgraded; auto-correction trigger hit | applied (not re-reviewed) |
| SR-015 | minor | doctrine-compliance | — | item 10 understates in-context loop state | applied (not re-reviewed) |
| SR-016 | minor | doctrine-compliance | — | item 4 partial grade not permitted by bar | applied (not re-reviewed) |
| SR-017 | major | ux | yes | human interaction cost unbounded and undisclosed | applied (not re-reviewed) |
| SR-018 | major | ux, contracts | — | residuals list omits confirmed-not-fixed-stopped | applied (not re-reviewed) |
| SR-019 | minor | ux | — | gate options lack severity and phrase; drivers unrendered | applied (not re-reviewed) |
| SR-020 | minor | ux | — | terminal print lacks residual summary and incomplete reason | applied (not re-reviewed) |
| SR-021 | minor | ux | — | verdict label unconditional; batch B gate unlabelled as final | applied (not re-reviewed) |
| SR-022 | major | contracts | — | kept SR-id rules contradict single-run ids | applied (not re-reviewed) |
| SR-023 | major | contracts | — | reviewer rules forbid verifier echoing SR ids and prior context | applied (not re-reviewed) |
| SR-024 | major | contracts | yes | re-derive conflates unlanded and verifier-unresolved; decided text rule | applied (not re-reviewed) |
| SR-025 | major | contracts | — | outcome assignment defined only for budget stop | applied (not re-reviewed) |
| SR-026 | major | contracts | — | enum lacks member for verifier-unresolved when batch B never runs | applied (not re-reviewed) |
| SR-027 | major | contracts | — | verifier resolved array incompleteness unhandled | applied (not re-reviewed) |
| SR-028 | minor | contracts | — | verifier rejected list unconsumed | applied (not re-reviewed) |
| SR-029 | minor | contracts | — | frontmatter descriptions advertise deleted design | applied (not re-reviewed) |
| SR-030 | minor | contracts | — | acceptance dogfood references sidecar | applied (not re-reviewed) |

**Challenger quorum:** 16 dispatched (one per major; no criticals), **15 upheld, 1 refuted**, 0 unconfirmed. One challenger per major (no criticals). Six challengers flagged the finder's severity as inflated but upheld per the rule that re-grading is out of scope. Two verdicts narrowed the finding (SR-023 to one limb, SR-025 to two stops) and the fix batch is scoped to the surviving residue.

| SR | verdict | challenger note |
|---|---|---|
| SR-001 | uphold | Row 2 false on plain text; proposed_fix shared by fixer and verifier is the see-and-game path. Grade arguable, defect real. |
| SR-002 | uphold | No text admits one pair for several SRs; duplicate-pair workaround fails on atomic groups; obsolete removed so batch B cannot say 'already fixed'. |
| SR-003 | refute | TRIAGED is defined by 'every batched fix landed', not 'every edit verified'; batch B is unverified on every path and applied (not re-reviewed) discloses it; skipping a vacuous stage matches the spec's own pattern. |
| SR-006 | uphold | 'as described' suggests efficacy but proposed fix is handed over with no stated role; §6 mandates departures from proposed fixes, so compliance reading is destructive. Grade arguable under the future anchor. |
| SR-007 | uphold | No base for P anywhere; no row for growth discrepancy; fixer figure systematically wrong after fix-failed/subset. Secondary finders graded minor; major looks inflated but defect real. |
| SR-008 | uphold | Stage 4 -> 3' boundary is a legal stop; spec supersedes step 7's 'applied' at other abnormal exits, so silence here is a gap. Rendered resolved:false narrows but does not equalise. |
| SR-011 | uphold | §5 step 2 is the only fixer-input statement; kept re-derive rule mis-describes the verifier-unresolved case; verifier reason routed only to the report. |
| SR-014 | uphold | Bar permits N/A only for an unhit trigger; auto-correction trigger is hit; row cites a guard (grade shape Met, not N/A) and concedes the gate can be absent. |
| SR-017 | uphold | No budget or disclosure of question count. Two magnitude corrections: needs-decision asked at most once per entry per run; pagination only on the approve-subset path. Severity generous. |
| SR-018 | uphold | Residuals is load-bearing routing (§1 defines done by it; §7 routes to it); completeness's counter bounds blast radius but does not refute. |
| SR-022 | uphold | §6 Removed list never names the SR-id/registry-identity block; max+1 is cross-run allocation, not a resume rule; Stage 1's restatement is the other half of the contradiction. |
| SR-023 | uphold | Two of three limbs refuted (§6 does override the output shape; 'compute' != 'echo'; no rounds so no prior-round rule). Survives: the kept skill line 'Reviewers never emit SR ids' vs the verifier shape. Nearer minor. |
| SR-024 | uphold | re-derive defined only in the fixer agent with a premise false for verifier-unresolved entries; §5 step 1 + step 2 normatively require re-emitting the failed decided text. needs_decision correct. |
| SR-025 | uphold | Minors/nits and declined groups already covered (finding overstates); the hole is entries mid-batch at interaction-unavailable or external-edit, which are reachable mid-run. Fix should not re-assert covered mappings. |
| SR-026 | uphold | 'No outcome' phrasing inaccurate (applied is assigned) but §7 demotes applied only when verification never ran, not when it failed; applied is excluded from Residuals. Write the fix as a revision rule. |
| SR-027 | uphold | No cardinality constraint on resolved[]; every other agent shortfall is fail-closed, this one is silent; §10's stochasticity bullet does not defer it. |

**Needs-decision gate (2 asked, both accepted with an alternative):**

- **SR-017** — `accepted` (batch-and-disclose): Needs-decision questions are asked in AskUserQuestion calls of up to four questions each (no new flag). §1 states the question cost; §10 gains a bullet with the corrected magnitude: at most one question per needs-decision entry across the run, one approve gate per batch, pagination (four groups per page) only on the approve-subset path.
- **SR-024** — `accepted` (split-markers-refix-is-new-decision): Keep `re-derive` for entries whose pair never landed. Add `re-fix` for verifier-unresolved entries: the batch A edit landed, `old` targets the applied text, the fix must change it. For a user-decided `re-fix` entry the fixer may depart from the decided `new` text and the entry counts as a new decision: shown at the approve gate in default mode, re-asked as a needs-decision question in `--no-approve`.

**Fix phase:** batched 29 (15 major + 14 minor; SR-003 excluded as refuted) · 41 pairs proposed, 41 landed, 0 fix-failed · gate: approve-all · 22 hunks · spec 398 -> 489 (+91 (+23%)).  
Ride-alongs: SR-019 rides in SR-007's §5 step 6 pair; SR-025 rides in SR-008's Outcomes-at-a-stop pair; SR-026 rides in SR-008's Outcomes-at-a-stop pair.  
Fixer output arrived with < and > HTML-escaped by the notification channel; unescaped before matching (transcription correction, no content change). All 41 olds matched uniquely in the original; no overlapping pairs, so every pair was its own atomic group.

**Equivalence log (within-round):**

- IC1 ~ DC1: match=True → SR-001 — same slug (doctrine-compliance); both are 'row 2 claims inputs Stage 4 does not give'. DC1 adds the doctrine violation and the withhold fix; the spec's own row-2 'Met' claim arbitrates toward withholding, so not needs-decision.
- AT2 ~ CO2: match=True → SR-007 — same slug, same clause (growth line P base, mismatch consequence).
- AT2 ~ CT8: match=True → SR-007 — same slug, same clause; CT8 adds 'measured is authoritative' and unrendered drivers.
- CO4 ~ CT10: match=True → SR-013 — same slug (pipeline), same branch (report lacking post-loop hash); CT10 adds stale sidecar.
- UX2 ~ CT9: match=True → SR-018 — same slug (report-format), same omission. Merged at max severity (major). Note: completeness self-rejected this candidate ('panel table renders every outcome'); challenger will test.
- AT4 ~ CO3: match=False (kept separate) — same guard (never dispatch the fixer with an empty batch) but slugs differ (pipeline vs the-batch-procedure): kept as SR-009 and SR-012; one pair at fix time.
- AT3 ~ CT5: match=False (kept separate) — same defect (verifier-unresolved entry at a stop before batch B) but slugs differ (budgets vs report-format): kept as SR-008 and SR-026; one pair at fix time.
- AT3 ~ CT4: match=False (kept separate) — same slug but CT4 is the general stop-independent rule, AT3 one case of it: SR-025 subsumes SR-008 at fix time.
- IC3 ~ AT5: match=False (kept separate) — opposite faces of the skipped-verifier status (IC3: must be incomplete when batch B lands edits; AT5: skipped alone must not read as not-returned); slugs differ; compatible single fix in §9.
- CT3 ~ CO1: match=False (kept separate) — related (batch B input) but distinct: CO1 = pass failure context; CT3 = marker semantics + decided-text rule. Slugs differ.

**Orchestrator notes:**

- First panel dispatch (6) failed on an infrastructure error (API unreachable, ENOTFOUND) before any reviewer read the spec; retried once per contract on user request.
- Retry (6) failed identically (ENOTFOUND) before any reviewer read the spec. Contract would send all six lenses to Coverage not-returned and converge vacuously; user instructed a further retry, which overrides the one-retry rule for infrastructure faults. Recorded here so the dispatch count stays truthful.
- Orchestrator correction on SR-004's proposed fix: the 57% aggregate the finder computed uses the table's '13 in round 1' cell as the agent-tools run total, but that run's round-3 re-dispatched three more challengers (its run-1 sidecar is archived), so no three-run aggregate is derivable from the spec's table. The fix will scope the 78% to the needs-decision run without asserting an aggregate.
- Repo-fact checks by the orchestrator (in place of the dropped feasibility lens): 162 distinct SR ids across rounds vs 162 registry entries in 2f60dd3 and zero repeats in c22cbbd (verified by SR-id-per-round set test, not by a registry field); major 98/162; lens-catalog cap is panel rule 5 at line 119 (not doctrine item 5 at line 61); fixer output carries obsolete; reviewer forbids reviews/**; all three validators green at baseline.

## Coverage

- **Catalog lenses not selected this run:** `feasibility` — every mechanism the spec relies on is already demonstrated by the shipped command it replaces (which the lens mandate treats as a refutation); the orchestrator verified the spec's repo-fact claims directly (see Orchestrator notes). Selected in place of it: `ux`, after the 2026-08-27 run dropped `ux` for five rounds and paid four defects only it could see.
- **Not returned (failures, with reasons):** none of the six selected lenses. The first two panel dispatches (12 launches) failed on an infrastructure error (API unreachable, ENOTFOUND) before any reviewer read the spec; the third dispatch, made after a DNS/HTTPS probe succeeded, returned all six. The contract's one-retry rule was exceeded on the user's instruction; the dispatch counter includes all 18 launches.
- **Standing oracle blind spots:** intent, external facts, unstated requirements. The challenger's refutation rate this run (1 of 16, 6%) matches the historical rate the spec cites.

## Rejected by the panel (self-falsification)

Seventy-four candidates, one line each, verbatim; never rendered as findings.

- [internal-consistency] §3's "Challengers | Criticals only, one per finding" vs Stage 3' giving fix-induced criticals "no challenger — one pass" — refuted: Stage 3' states the exception verbatim at the point of use, so nothing is left for an implementer to arbitrate.
- [internal-consistency] §1's "done ... means every fix it batched landed" vs §9 allowing plain `TRIAGED` with `declined` entries — refuted: §9's trigger list is the normative status rule and `declined` is a conscious user withdrawal, treated like `accepted-risk`, which also does not degrade the status.
- [internal-consistency] §9's Residuals bullet listing `applied (not re-reviewed)` vs §1's "reports everything it did not fix as residuals" — refuted: §1 does not say residuals contain only unfixed items, so a superset is consistent.
- [internal-consistency] Stage 1's "the roster (seven lenses) is the ceiling" vs §6 adding an eighth lens to the catalog — refuted: §6 says `fix-coherence` is "verification only, never selected for a panel", so seven remains the panel-selectable ceiling.
- [internal-consistency] §9's Recovery line naming a snapshot path unconditionally vs Stage 0 taking the snapshot only "before the first `Edit` of the run" — refuted: the skeleton is a template, and a run that wrote nothing also has no loop-touched files to list under it.
- [internal-consistency] §5 step 6's "a group renders as one hunk" vs step 4's atomic groups, which may span non-contiguous text ("one edit changing text another must match") — refuted: the operative rule in the parenthetical is atomic offering ("half of it is never offered"), not diff geometry.
- [internal-consistency] §1's "roughly 8–12 subagent dispatches" vs a seven-lens uncapped panel plus challengers plus three fixer/verifier dispatches — refuted: "roughly" plus the 20-dispatch default cap accommodate the range; no rule is contradicted.
- [internal-consistency] §11's acceptance pass condition `TRIAGED` vs §9 degrading to `TRIAGED (incomplete)` on any `pending-decision` entry — refuted: the spec never says the acceptance runs use `--auto`, and only `--auto` produces `pending-decision`.
- [internal-consistency] §8 item 9's "N/A — fixes are applied only behind the approve gate or an explicit `--no-approve`" vs §5 step 6 applying immediately under `--auto` — refuted: the row names the ungated path itself, and grading the N/A justification is the doctrine-compliance lens's domain.
- [internal-consistency] §12's promised re-run table "(unchanged / changed / interrupted)" vs Stage 0's two-branch re-run detection — refuted: §7 writes a partial report on abort, so an interrupted run falls into the unchanged or changed branch by hash; §12 names doc rows, not a third mechanism.
- [internal-consistency] A budget stop between Stage 4 and batch B leaving verifier-unresolved batch A entries at outcome `applied` — refuted: `applied` states only that the edit landed, and §9's "## Verification of batch A | SR | resolved | reason" table renders the unresolved verdict beside it.
- [internal-consistency] The lens-catalog's surviving "3–6 lenses per round" and "logged in the sidecar" preamble against Stage 0's "No sidecar" and Stage 1's "no cap" — refuted as out of lens: establishing it requires reading the catalog file rather than the spec's own sections, and §6 constrains only rule 5.
- [internal-consistency] A challenger that fails twice not setting `TRIAGED (incomplete)` while a lens that fails twice does — refuted: the entry "stays critical" and enters the batch, so no finding is lost, and §4 Stage 2 and §7 both disclose it as a report note.
- [ambiguity-testability] Scope of 'per SR of batch A' in the Stage 4 SR list — could be read to include `declined`/`accepted-risk`/`pending-decision` entries, letting the verifier push a user-declined defect into batch B; refuted because the listed field 'the applied `new` text' presupposes a landed edit and §6's fix-coherence mandate puts 'any defect the batch did not touch' out of mandate.
- [ambiguity-testability] 'the decided `new` text is preserved through `re-derive`' is ambiguous about whether the fixer may alter user-decided text when the verifier marked it unresolved; refuted by step 2's 'Decided edit content is passed verbatim' plus 'preserved', which settle the reading (the remaining problem is a design bind, not a two-way reading).
- [ambiguity-testability] Atomic overlap groups (step 4) do not say whether grouping is transitively closed when A overlaps B and B overlaps C; refuted because 'a group renders as one hunk' and 'all land or all fail' are only coherent for disjoint groups, so the equivalence-class reading is forced.
- [ambiguity-testability] '`dispatches_used + 2 × planned ≤ max_dispatches`' does not define `planned`; refuted because 'At every stage boundary' fixes it as the dispatches the stage about to start will make, and the ×2 is written out explicitly as the retry reserve.
- [ambiguity-testability] §11's acceptance pass condition '`TRIAGED` within default budgets' could be read to admit `TRIAGED (incomplete)`; refuted because §9 enumerates the two as distinct status tokens, so exact-match is the only reading of the token.
- [ambiguity-testability] Re-run detection ('read its `post-loop` hash line') is undefined for an existing report written by the old loop, which has no hash line; refuted because only equality triggers the re-run branch, so a missing line falls into 'a report whose hash differs' and archives.
- [ambiguity-testability] Step 6's '`--no-approve` / `--auto`: apply immediately' could be read as bypassing step 7's snapshot and re-hash; refuted by Stage 0's independent snapshot rule ('before the first `Edit` of the run, at most once per run'), and the skipped re-hash guards only an unbounded human wait that does not exist on that path.
- [ambiguity-testability] The verifier's second mandate ('introduce a contradiction … that was not there before') may be uncheckable without the pre-edit spec; refuted because it is given the unified diff, which carries the before-text of every passage the batch could have broken.
- [ambiguity-testability] 'the SR ids whose pairs account for most of it' (§6 growth drivers) is unquantified; refuted because the field is an advisory display item with no downstream branch, so no behaviour diverges.
- [ambiguity-testability] 'Active seconds, user waits excluded' gives no measurement rule; refuted because Stage 0 declares the flag table 'Unchanged rules from the current command, minus the iteration flag', delegating the accounting to the existing implementation.
- [ambiguity-testability] §1's '"done" … means every fix it batched landed' conflicts with §9, where `declined` and `accepted-risk` entries leave the status at plain `TRIAGED`; rejected as a contradiction between sections, which is internal-consistency's mandate, not this lens's.
- [ambiguity-testability] Whether a report file is written on the `STOPPED(interaction-unavailable)` path ('before any write'); refuted because the phrase scopes spec writes and §9's status set plus the skeleton's terminal-status line make the report unconditional.
- [ambiguity-testability] 'target ≈130 lines' for the rewritten command is not a checkable criterion; refuted because it is explicitly approximate and is a sizing note, not an acceptance criterion.
- [ambiguity-testability] 'Fixer failure → one retry' does not define failure, e.g. a fixer that returns zero pairs; refuted because step 4 already routes 'an entry the fixer returned no pair for' to `fix-failed`, leaving failure to mean dispatch/parse failure.
- [completeness] Batch B never says whether the landed-but-unresolved batch A edit is reverted before re-deriving — refuted: §5 step 4 always matches `old` against the current spec, so a re-derived pair is by construction written against the already-edited text; no revert step is implied.
- [completeness] The tamper flow's *adopt* branch does not say whether the pipeline re-dispatches the fixer or continues with pairs derived from pre-tamper text — refuted: §5 is a linear numbered procedure and step 3 sits between the dispatch and the materialization, so adopt → step 4 is settled by step order; stale pairs then fall into the defined `fix-failed` path.
- [completeness] The `--auto` unchanged-spec exit and the archive rule leave the pre-existing v1 sidecar `<spec>-review.state.json` unaddressed — refuted: §4 states "No sidecar" and no stage reads one, so an orphaned file is inert, not a behaviour the implementer must decide.
- [completeness] §9's Residuals bullet list omits `confirmed (not fixed — stopped)` although that outcome is unfixed work — refuted: the `## Panel` table carries an `outcome` column for every entry, so no entry goes unrendered; where a stop outcome is additionally summarised is presentation, not a design decision.
- [completeness] A challenger that fails twice leaves a critical unadjudicated but is not listed among §9's `TRIAGED (incomplete)` triggers — refuted: §7 explicitly settles the handling ("Critical stays upheld with a report note; never refuted") and §9 enumerates the triggers exhaustively, so the design is stated, not missing; whether it *should* trigger incomplete is a doctrine question, not a gap.
- [completeness] A refutation removes an entry that a second lens independently found at major severity, with no rule for demoting rather than dropping it — refuted: §4 Stage 2 states "`refute` → outcome `refuted`, the entry leaves the batch" for the merged entry as a whole; explicit decision, not an omission.
- [completeness] Nothing says whether a report is written on `STOPPED(...)` paths, which matters because re-run detection keys on the report — refuted: §9 lists the STOPPED statuses among report statuses, §7 assigns per-entry outcomes at a budget stop and a partial report on Esc, and the skeleton header carries "Terminal status"; a report on every terminal path is settled.
- [completeness] The Stage 2 boundary check `dispatches_used + 2 × planned ≤ max_dispatches` can stop a run with many criticals before any fix is attempted, with no rule for triaging challengers down to fit — refuted: §7 states the consequence outright ("stop as `STOPPED(budget)` — never inside a dispatch phase"); a cliff, but a specified one.
- [completeness] §6 keeps the v1 "SR-id and anchor rules", whose "a later run continues at max+1" clashes with Stage 0's "SR ids restart at 1" — refuted for this lens: the implementer is not missing a decision (Stage 0 states it plainly); the residue is a contradiction, which is internal-consistency's mandate.
- [completeness] The fixer output shape permits several `edits` entries per `sr_id` with no rule for multi-pair SRs — refuted: §5 step 4 applies every returned pair and defines failure only for a non-unique `old` or a *missing* pair, so multiple pairs for one SR are already handled.
- [completeness] `tests/ACCEPTANCE.md`'s new pass condition does not say whether `TRIAGED (incomplete)` passes — refuted: §6 says "Pass condition becomes `TRIAGED`", and §9 makes `TRIAGED (incomplete)` a distinct status string, so the exclusion is stated.
- [completeness] Stage 4's scratchpad file paths and naming are undefined — refuted: a file-naming convention is implementation-plan detail, outside this lens's mandate.
- [doctrine-compliance] Item 3 — a challenger failing twice sets neither a WARNING nor `TRIAGED (incomplete)` (§9's list covers only a lens and the verifier): refuted, §4 Stage 2 leaves the entry upheld (fail-closed, "uncertainty never refutes") and the failure is printed in the report's Critical-challengers `note` column, so coverage of the spec is unchanged and the gap is disclosed.
- [doctrine-compliance] Item 6 rider — model-heavy loop with no cost/token ceiling: refuted, the rider is explicitly not a universal MUST, the anti-pattern names a *soft-only* budget while §7 sets hard dispatch and time caps, and §10 discloses "no token ceiling beyond the dispatch cap".
- [doctrine-compliance] Item 7 — 'N/A' claimed on a universal item, where the bar allows N/A only for items 9–11: refuted, the row grades the stop-vs-success clause Met and gives an accurate one-line reason for the other two clauses; a straight-line pipeline whose only retry (`re-derive` in batch B) runs at most once cannot stall or oscillate, so the row under-claims rather than over-claims and misleads no reader about behaviour.
- [doctrine-compliance] Item 11 — §4 Stage 0's snapshot rule overwrites an earlier run's snapshot, destroying a pre-existing recovery point: refuted, the rule justifies it in place ("git holds the committed history; the snapshot is this run's recovery point") and the earlier run's report is preserved by archiving to `<spec>-review.run<N>.bak`.
- [doctrine-compliance] Item 2 — batch B's edits are never verified by anything (§4 Stage 3': "no further verification follows"): refuted, the bar requires disclosure rather than universal re-verification, and the outcome name `applied (not re-reviewed)` plus §10's first residual disclose it explicitly.
- [doctrine-compliance] Item 6 — the §7 stage-boundary check (`dispatches_used + 2 × planned ≤ max_dispatches`) can stop a run with criticals unfixed at the default 20: refuted, that path terminates as `STOPPED(budget)` with `confirmed (not fixed — stopped)` per §7's error table, which is precisely item 7's required stop≠success behaviour, not a budget defect.
- [doctrine-compliance] Item 1 — oracle blind spots understated: refuted, row 1 names the oracle and its advisory label, §9's Coverage line names the standing blind spots (intent, external facts, unstated requirements) and §10 enumerates six residuals.
- [doctrine-compliance] Item 5 — guards reinvented rather than reused: refuted, §4 Stage 0 carries the working-tree gate, the out-of-scope path error, the ambiguous-target ask/abort and the `AskUserQuestion` backstop over verbatim from the existing command.
- [doctrine-compliance] §8 preamble — "both the report's residual-risk section and `docs/plugins/superutils.md` state it" is unsupported: refuted, §9's skeleton contains `## Residual risks`, §10 supplies its content and §12 requires the 'Honest limits' section; the real shortfall is the item-9 and item-10 content itself, already reported.
- [ux] Working-tree confirmation adds an unmeasured interruption — §4 Stage 0 carries the gate over "verbatim" from the current command, so it is unchanged behaviour and adds no new interaction cost.
- [ux] `--no-approve` surprises the user by still prompting — the flag table cell states "Needs-decision questions still asked" in the same row, which is the disclosure.
- [ux] "supply an alternative" has no described input mechanism — `AskUserQuestion`'s free-text option is the platform default, storage of the resulting edit is specified, and the capture mechanism is feasibility's lane, not mine.
- [ux] The re-run question should offer "show me the prior report" — it is a single two-option question and the report path is printed either way; cost is one keystroke.
- [ux] `--auto` printing the full batch diff into a headless session is noise — in a non-interactive run the printed diff is the audit trail, not an interruption of a user.
- [ux] Plain `TRIAGED` after the user declined half the batch overstates success — `declined` and `accepted-risk` are conscious user decisions recorded per SR in the report, so the status is not hiding anything from the person who made them.
- [ux] Paginated multiSelect makes "deselecting every group is a decline of the whole batch" a trap for a user who defers choices to a later page — the explicit "decline and stop" option precedes pagination, and the cross-page semantics question belongs to the ambiguity lens.
- [ux] The subset flow offers no escape once pagination starts — §7 documents Esc as user abort with a partial report and snapshot recovery.
- [ux] The new `TRIAGED` vocabulary is unfamiliar after `CONVERGED` — §12 updates `docs/plugins/superutils.md` and `docs/workflow.md` Stage 2 with the full status set.
- [ux] Needs-decision questions are asked before any diff exists, so the user decides blind — the entry's `proposed_fix` is shown, and the approve gate later renders the real hunk before any write, so the decision is revisable.
- [ux] The gate is a human interruption inside a pipeline sold as cheap — §3 records the human gate as retained by decision and §8 item 4 claims it, so the interruption is the design, not a defect.
- [contracts] Doctrine row 2 claims the verifier sees "only the diff and the spec" while Stage 4 also hands it the SR list — refuted: the SR list is the orchestrator's record, not the fixer's rationale, and the claim/mechanism mismatch is the doctrine lens's domain, not a shape or schema defect.
- [contracts] Stage 1's "the roster (seven lenses) is the ceiling" against §6 adding an eighth lens — refuted: `fix-coherence` is "never selected for a panel", so the panel ceiling of seven still holds; a counting label, not a contract break.
- [contracts] The fixer agent's Rules bullet and Output line still document `obsolete` — refuted: §6's "`obsolete` is removed from the output" is one edit to that agent, and stripping its rule text is an implementation detail of the named deliverable.
- [contracts] The challenger verdict shape is `uphold|refute`, leaving no value for the "challenger not returned" row in the report's `| SR | verdict | note |` table — refuted: Stage 2 says the entry "stays critical"/upheld, so `uphold` plus the note is derivable.
- [contracts] §9's skeleton drops the old rendering rule for the Rejected section (`- [lens] candidate — why it was refuted`; `None` when empty) — refuted: a presentation detail of a section that survives; no consumer parses it.
- [contracts] The fixer `notes` field loses the clause "— orchestrator marks those fix-failed" — refuted: §5 step 4 states that consequence orchestrator-side, where it belongs.
- [contracts] §9 lists the outcome enum with no per-member definitions, unlike the current skill — refuted: every member's trigger is defined in §4, §5 and §7, which the skill will carry.
- [contracts] The closed status set has no member for §7's "User abort (Esc) | Partial report" — refuted: §10 discloses the interruption path ("No mid-run resume: an interrupted run is re-run on whatever the spec then contains"), so the missing label is a disclosed-adjacent labelling gap.
- [contracts] `--max-dispatches` 60→20 and `--time-budget` 1800→900 are silent behavioral breaks for existing callers — refuted: both defaults are declared in the Stage 0 flag table and carried by the 2.0.0 bump §12 propagates to all four version places.
- [contracts] Removing `--max-iterations` as a hard validation error breaks existing invocations — refuted: §3 records the decision ("Replace in place. No flag, no second command. Breaking change → superutils 2.0.0") and Stage 0 states the error explicitly.
- [contracts] The kept `sha256(slug + "|" + canonical-phrase)` stored key has no store now that the sidecar registry is deleted — folded into the SR-id/anchor finding rather than reported twice.
- [contracts] Four-place version parity (plugin.json, marketplace.json, README row, docs/plugins/superutils.md `**Version:**`) — no finding: §12 names all four, §11 runs `check_plugin_versions.py`, and plugin.json's current 1.0.2 matches the spec header's "1.0.2 → 2.0.0".
- [contracts] `fix_induced` / `introduced_by` might have no consumer — refuted: the skeleton's "Fix-induced findings: | SR | severity | introduced by | outcome |" table consumes both.
- [contracts] The command frontmatter keeps `Bash(jq:*)` though no JSON sidecar remains — refuted as out of mandate: a permission-pre-approval breadth question, not a data contract.
- [contracts] `TRIAGED (incomplete)` is not triggered by a challenger that failed twice — refuted: Stage 2 leaves the critical upheld and it still enters the batch, so no work is left undone; the omission is recorded in the report's `note` column.

## Accepted risks (user-decided)

None.

## Declined (user-decided)

None — the whole batch was approved.

## Residual risks

- **Round 1's 29 fixes are `applied (not re-reviewed)`.** +91 lines landed and no fresh panel has read them. In the two prior multi-round runs the next round's worst findings came from the previous batch's seams; expect the same here. A re-run on the changed spec (new run, registry carried forward) is how to close that.
- **Active-time accounting is an estimate.** The harness exposes no active-time clock; the figure is wall clock minus estimated user waits, with measured subagent durations where available. The stop decision rests on it and is disclosed as such.
- **Six challengers flagged the finder's severity as inflated** (SR-001, 006, 007, 014, 017, 023) but upheld per the no-re-grading rule; two narrowed the finding (SR-023 to one limb, SR-025 to two stops) and the fixes were scoped accordingly. Whether the new spec's tightened `major` anchor would have demoted them is untested.
- Verifier gaming (soft oracle; every verdict advisory); stochasticity of panel and challengers; lens drift; no token ceiling beyond the dispatch cap; soft registry matching (slug + orchestrator equivalence judgment); best-effort headless detection.
- The `feasibility` lens was not run; its repo-fact checks were done by the orchestrator, which is the actor of this loop, not an independent reviewer.

## Recovery

- Loop-touched files: `docs/superpowers/specs/2026-09-09-spec-review-bounded-triage-design.md` (modified, uncommitted — 41 edits), this report, `docs/superpowers/specs/reviews/2026-09-09-spec-review-bounded-triage-design-review.state.json` (sidecar), `docs/superpowers/specs/reviews/2026-09-09-spec-review-bounded-triage-design.pre-loop.bak` (snapshot).
- To discard the batch: copy the snapshot over the spec. Never `git restore` the spec — the committed version (`d41c7ea`) is byte-identical to the snapshot, but the rule stands so that a run on an uncommitted spec is never destroyed.
- Nothing was committed by the loop.

_Re-reviewed (advisory)._
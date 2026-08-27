# Spec-review loop report — 2026-08-27-needs-decision-batch-resolution-design.md

**Run:** 1 &nbsp;·&nbsp; **Mode:** default (interactive, batch-approve gate)
**Budgets used:** 6/6 iterations · 141/280 dispatches · time budget 10800s (not instrumented)
**Budget raised** at round 2, after the panel, before the quorum: 3/60/1800s → 5/200/7200s — user raised the budget after STOPPED(budget) and asked to continue; the run reopens at the stage the budget check refused, not at a fresh panel.  
**Budget raised** at after round 5's terminalization, before round 6's panel: 5/200/7200s → 6/280/10800s — user raised the budget and asked for another round, explicitly to get round 5's fixes reviewed; the run reopens at a fresh panel, which is what reviewing them means.
**Terminal status:** `STOPPED(budget)` — the iteration cap, not convergence.
**Verdict label:** Re-reviewed (advisory).

> The oracle is soft: a panel verdict plus challenger survival. It cannot verify user intent, external facts, or unstated requirements. Nothing here is *verified*.

## Summary

| | round 1 | round 2 | round 3 | round 4 | round 5 | round 6 |
|---|---|---|---|---|---|---|
| raw findings | 39 | 39 | 41 | 45 | 29 | 29 |
| registry entries | 32 | 24 | 29 | 28 | 24 | 25 |
| major+ entries | 15 | 18 | 19 | 20 | 16 | 16 |
| challengers | 15 | 19 | 20 | 22 | 18 | 16 |
| refuted | 0 | 2 | 2 | 1 | 1 | 1 |
| fixes batched | 31 | 22 | 27 | 27 | 23 | 22 |
| pairs landed | 33/33 | 31/31 | 38/38 | 42/42 | 35/35 | 36/36 |
| spec lines | 310 → 490 | 490 → 631 | 631 → 803 | 803 → 1093 | 1093 → 1231 | 1231 → 1430 |

**Totals:** 162 registry entries · 110 challenger dispatches, 7 refutations (4% of entries) · 19 user decisions · 215 edit pairs applied · spec 310 → 1430 lines.

**The run did not converge, and the trend is the finding.** Major+ entries per round ran 15 → 18 → 19 → 20 → 16 → 16; raw findings 39 → 39 → 41 → 45 → 29 → 29. Round 5 looked like the first genuine decline. Round 6 shows it was a plateau: identical counts on a spec that grew another 199 lines between them. The no-progress stop never fired, because the entries differ every round — the loop keeps finding *different* defects at a constant rate rather than exhausting them.

**Each round's worst findings come from the previous round's fixes.** Round 2's critical traces to round 1's SR-026 fix, round 3's to round 2's SR-043/SR-045, round 4's two to round 3's SR-062/SR-073, round 5's two to round 4's SR-103/SR-092. Round 6 reproduced it exactly: SR-139 is round 5's SR-114 and SR-129 fixes contradicting each other, SR-146 is the delimiter rule SR-133's fix closed on one separator out of three, and SR-142/SR-143 are the pin membership rule and the unpinned path that earlier rounds introduced. The spec is now 4.6× its original length and no panel has read the text round 6's fixes produced.

## Round 1 — panel, units

**Panel:** `internal-consistency`, `ambiguity-testability`, `completeness`, `feasibility`, `doctrine-compliance`, `contracts`

**Rationale:** Both core lenses mandatory. completeness by rule 2 (12 sections). Content triggers: agent + plugin design -> doctrine-compliance + feasibility; the spec defines an analyst return contract, a cross-plugin status vocabulary and SemVer bumps for two independently installable plugins -> contracts. ux was the seventh candidate and was dropped at the cap of 6: the interaction flow was co-designed with the user across five rounds of questions and is the most validated part, while cross-plugin version compatibility was the least examined.

**Units (12 `##` sections):** `Purpose`, `Evidence`, `Scope`, `The flow`, `Components`, `Decision outcomes`, `Status vocabulary extension`, `Decision record`, `Edge cases`, `Delivery`, `Verification`, `Residual risks`

| SR | severity | lenses | outcome |
|---|---|---|---|
| SR-001 | major | internal-consistency, feasibility, doctrine-compliance | applied |
| SR-002 | minor | internal-consistency, ambiguity-testability | applied |
| SR-003 | minor | internal-consistency | applied |
| SR-004 | minor | internal-consistency | applied |
| SR-005 | minor | internal-consistency | applied |
| SR-006 | minor | internal-consistency | applied |
| SR-007 | minor | internal-consistency | applied |
| SR-008 | major | ambiguity-testability, feasibility | applied |
| SR-009 | major | ambiguity-testability, completeness | applied |
| SR-010 | major | ambiguity-testability | applied |
| SR-011 | minor | ambiguity-testability | applied |
| SR-012 | minor | ambiguity-testability | applied |
| SR-013 | minor | ambiguity-testability | applied |
| SR-014 | minor | ambiguity-testability | applied |
| SR-015 | minor | ambiguity-testability | applied |
| SR-016 | major | completeness, feasibility | applied |
| SR-017 | minor | completeness | applied |
| SR-018 | major | feasibility | applied |
| SR-019 | major | feasibility, contracts | applied |
| SR-020 | minor | feasibility | applied |
| SR-021 | major | doctrine-compliance | applied |
| SR-022 | major | doctrine-compliance | applied |
| SR-023 | major | doctrine-compliance | applied |
| SR-024 | major | doctrine-compliance | applied |
| SR-025 | major | doctrine-compliance | applied |
| SR-026 | major | doctrine-compliance | applied |
| SR-027 | major | contracts | applied |
| SR-028 | major | contracts | applied |
| SR-029 | minor | contracts | applied |
| SR-030 | minor | contracts | reported-only |
| SR-031 | minor | contracts | applied |
| SR-032 | minor | contracts | applied |

**Challenger quorum:** 15 dispatched over 15 entries — 15 upheld, 0 refuted, 0 unconfirmed.

**Fix phase:** 31 batched, 33 pairs dispatched, 33 landed, 0 fix-failed; gate `approve-all`; spec 310 → 490 lines.

**Equivalence judgments logged:** 10.

## Round 2 — panel, units

**Panel:** `internal-consistency`, `ambiguity-testability`, `completeness`, `feasibility`, `doctrine-compliance`, `contracts`

**Rationale:** Fresh panel, same composition as round 1 — the selection rules yield the same six lenses for the same spec, and a fresh panel means fresh agent instances with no prior-round context, not a different roster.

**Units (13 `##` sections):** `Purpose`, `Evidence`, `Scope`, `The flow`, `Components`, `Decision outcomes`, `Status vocabulary extension`, `Decision record`, `Edge cases`, `Delivery`, `Oracle`, `Verification`, `Residual risks`

**Stop evaluation:** `STOPPED(budget)` → cleared — budget raised by the user; the quorum ran and the round proceeded to the gate and the fix phase

| SR | severity | lenses | outcome |
|---|---|---|---|
| SR-033 | critical | contracts, internal-consistency, feasibility | applied |
| SR-034 | major | completeness, ambiguity-testability, internal-consistency, contracts | applied |
| SR-035 | major | completeness, doctrine-compliance, feasibility, ambiguity-testability | applied |
| SR-036 | major | contracts, ambiguity-testability, internal-consistency | applied |
| SR-037 | major | doctrine-compliance | refuted |
| SR-038 | major | contracts, ambiguity-testability, internal-consistency | applied |
| SR-039 | major | contracts | refuted |
| SR-040 | major | ambiguity-testability, internal-consistency | applied |
| SR-041 | major | completeness, ambiguity-testability, internal-consistency | applied |
| SR-042 | major | completeness, ambiguity-testability | applied |
| SR-043 | major | doctrine-compliance | applied |
| SR-044 | major | doctrine-compliance | applied |
| SR-045 | major | doctrine-compliance | applied |
| SR-046 | major | contracts | applied |
| SR-047 | major | contracts | applied |
| SR-048 | major | internal-consistency | applied |
| SR-049 | major | feasibility | applied |
| SR-050 | major | ambiguity-testability | applied |
| SR-051 | minor | contracts | applied |
| SR-052 | minor | feasibility | applied |
| SR-053 | minor | doctrine-compliance | applied |
| SR-054 | minor | internal-consistency | applied |
| SR-055 | minor | internal-consistency | applied |
| SR-056 | nit | internal-consistency | applied |

**Challenger quorum:** 19 dispatched over 18 entries — 16 upheld, 2 refuted, 0 unconfirmed. SR-033 is critical and drew two challengers; both upheld, which the quorum rule requires. The two refutations are the loop's first — round 1's quorum upheld 15 of 15, which was weak evidence that it discriminated at all.

**Refuted:**

- **SR-037** — stage 3 destroys the reviewer's Location from an advisory field. the finder asserted one branch of SR-036's ambiguity as established fact; the spec names every intended report write explicitly and stage 3 does not, and Verification step 4's post-conditions enumerate every expected report mutation without a rewritten Location line. The challenger judged the two collapse into one defect, correctly captured by SR-036, and noted the proposed fix was self-inconsistent (substitute in the dispatched copy only, yet add a line to the report).
- **SR-039** — retirement has no field the replay check can read. the finder truncated the replay predicate. It reads '...enters stage 3 with the recorded resolution, subject to the pin check and the retry limit under Decision record' — the retry limit is an explicit conjunct incorporated by reference, and the decision line already 'carries the outcome of each attempt'. What remains is a wording gap about where the attempt tail sits on the line, which is low blast radius and is covered by SR-038.

**Fix phase:** 22 batched, 31 pairs dispatched, 31 landed, 0 fix-failed; gate `approve-all`; spec 490 → 631 lines.

- *deferred by fixer:* stage 2's permitted-writes list still omits the **Decision-pin:** line — a pre-existing gap outside this batch, left alone rather than fixed opportunistically

**Equivalence judgments logged:** 7.

## Round 3 — panel, units

**Panel:** `internal-consistency`, `ambiguity-testability`, `completeness`, `feasibility`, `doctrine-compliance`, `contracts`

**Rationale:** Fresh panel, same six lenses — the selection rules yield the same roster for the same spec; freshness is fresh agent instances with no prior-round context, not a different roster.

**Units (13 `##` sections):** `Purpose`, `Evidence`, `Scope`, `The flow`, `Components`, `Decision outcomes`, `Status vocabulary extension`, `Decision record`, `Edge cases`, `Delivery`, `Oracle`, `Verification`, `Residual risks`

| SR | severity | lenses | outcome |
|---|---|---|---|
| SR-057 | critical | internal-consistency, completeness, doctrine-compliance, ambiguity-testability | applied |
| SR-058 | major | ambiguity-testability, internal-consistency, doctrine-compliance | applied |
| SR-059 | major | contracts, ambiguity-testability, completeness | applied |
| SR-060 | major | ambiguity-testability, completeness | applied |
| SR-061 | major | ambiguity-testability, contracts | applied |
| SR-062 | major | contracts, ambiguity-testability | applied |
| SR-063 | major | internal-consistency, ambiguity-testability | applied |
| SR-065 | major | internal-consistency | applied |
| SR-066 | major | internal-consistency | applied |
| SR-067 | major | internal-consistency | applied |
| SR-070 | major | doctrine-compliance | applied |
| SR-071 | major | doctrine-compliance | applied |
| SR-073 | major | completeness | applied |
| SR-074 | major | completeness | applied |
| SR-075 | major | ambiguity-testability | refuted |
| SR-077 | major | contracts | refuted |
| SR-078 | major | contracts | applied |
| SR-079 | major | contracts | applied |
| SR-082 | major | feasibility | applied |
| SR-064 | minor | contracts, ambiguity-testability | applied |
| SR-068 | minor | internal-consistency, feasibility | applied |
| SR-069 | minor | internal-consistency | applied |
| SR-072 | minor | doctrine-compliance | applied |
| SR-076 | minor | ambiguity-testability | applied |
| SR-080 | minor | contracts | applied |
| SR-081 | minor | contracts | applied |
| SR-083 | minor | feasibility | applied |
| SR-084 | minor | feasibility | applied |
| SR-085 | minor | feasibility | applied |

**Challenger quorum:** 20 dispatched over 19 entries — 17 upheld, 2 refuted, 0 unconfirmed. SR-057 is critical and drew two challengers; both upheld. Two refutations, both well-argued: SR-075 on a misread post-condition whose proposed fix would have reduced falsifiability, SR-077 on the direction SemVer actually governs.

**Refuted:**

- **SR-075** — finding 3's status post-condition cannot fail. the finding read the post-condition as 'some status, or none', dropping the qualifier. 'A status decided by stage 3.5's logged raw output' is checkable as a pair — the decided alternative's raw output appears in the log, and the written status matches the mapping — and the proposed fix would have made it worse in both directions: a pinned Fixed would fail a conformant run whose dispatch errored, and would pass a run that copied fix-auto's advisory verdict.
- **SR-077** — MINOR bump for a release whose artifact is backward-incompatible. SemVer governs what breaks for whoever takes the new version; the cited breakage runs the other way (an old install reading a new artifact), which 2.0.0 would not repair by a byte. The spec also does apply CLAUDE.local.md on both sides — '1.18.0 (MINOR: new agent, new skill, new phase)' is a direct application of its MINOR clause — and the skew is already carried as a requirement in both upgrade notes and under Residual risks.

**Fix phase:** 27 batched, 38 pairs dispatched, 38 landed, 0 fix-failed; gate `approve-all`; spec 631 → 803 lines.

**Equivalence judgments logged:** 6.

## Round 4 — panel, units

**Panel:** `internal-consistency`, `ambiguity-testability`, `completeness`, `feasibility`, `doctrine-compliance`, `contracts`

**Rationale:** Fresh panel, same six lenses.

**Units (13 `##` sections):** `Purpose`, `Evidence`, `Scope`, `The flow`, `Components`, `Decision outcomes`, `Status vocabulary extension`, `Decision record`, `Edge cases`, `Delivery`, `Oracle`, `Verification`, `Residual risks`

| SR | severity | lenses | outcome |
|---|---|---|---|
| SR-086 | critical | contracts, internal-consistency, ambiguity-testability, completeness | applied |
| SR-088 | critical | feasibility, completeness | applied |
| SR-087 | major | feasibility, completeness, ambiguity-testability, contracts, doctrine-compliance | applied |
| SR-089 | major | internal-consistency, completeness | applied |
| SR-090 | major | completeness, contracts | applied |
| SR-091 | major | feasibility | applied |
| SR-092 | major | doctrine-compliance | applied |
| SR-093 | major | completeness | applied |
| SR-094 | major | completeness, contracts | applied |
| SR-095 | major | contracts | applied |
| SR-096 | major | ambiguity-testability | applied |
| SR-097 | major | ambiguity-testability, internal-consistency | applied |
| SR-098 | major | ambiguity-testability | applied |
| SR-099 | major | ambiguity-testability | applied |
| SR-100 | major | ambiguity-testability, internal-consistency | applied |
| SR-101 | major | ambiguity-testability | applied |
| SR-102 | major | contracts | refuted |
| SR-103 | major | doctrine-compliance | applied |
| SR-104 | major | doctrine-compliance | applied |
| SR-105 | major | doctrine-compliance | applied |
| SR-106 | minor | feasibility | applied |
| SR-107 | minor | completeness, ambiguity-testability | applied |
| SR-108 | minor | internal-consistency | applied |
| SR-109 | minor | internal-consistency, contracts | applied |
| SR-110 | minor | internal-consistency | applied |
| SR-111 | minor | contracts | applied |
| SR-112 | minor | doctrine-compliance | applied |
| SR-113 | minor | doctrine-compliance | applied |

**Challenger quorum:** 22 dispatched over 20 entries — 19 upheld, 1 refuted, 0 unconfirmed. Both criticals drew two challengers and both were upheld unanimously. SR-102's refutation reproduces round 3's refutation of SR-077 independently — the same reasoning reached twice by challengers who did not see each other's verdicts, which is the strongest evidence in this run that a refutation is sound rather than a single reviewer's slip.

**Refuted:**

- **SR-102** — the MAJOR SemVer boundary is never considered. refuted a second time, independently. Every harm the finding cites runs forward — an old install reading a new artifact — and SemVer grades what breaks for whoever takes the new version, for whom nothing breaks: the reason tail is permitted only for the new status, so 1.18.0's writes for pre-existing statuses are byte-identical and every earlier report still parses. Decisively, a MAJOR label would repair none of it: the reader on 1.17.3 installs nothing and the manifest has no dependency field, so the number on the writing side is invisible to every harmed party. The spec already handles it the only way that can work — a requirement in both upgrade notes plus two dedicated residual risks.

**Fix phase:** 27 batched, 42 pairs dispatched, 42 landed, 0 fix-failed; gate `approve-all`; spec 803 → 1093 lines.

- *orchestrator note:* One pair failed on the first application attempt through an orchestrator transcription slip (an `old` string copied with the post-fix wording); corrected and re-applied, so no finding was charged a fix_failure for it.

**Equivalence judgments logged:** 6.

## Round 5 — panel, units

**Panel:** `internal-consistency`, `ambiguity-testability`, `completeness`, `feasibility`, `doctrine-compliance`, `contracts`

**Rationale:** Fresh panel, same six lenses. Final permitted iteration.

**Units (13 `##` sections):** `Purpose`, `Evidence`, `Scope`, `The flow`, `Components`, `Decision outcomes`, `Status vocabulary extension`, `Decision record`, `Edge cases`, `Delivery`, `Oracle`, `Verification`, `Residual risks`

| SR | severity | lenses | outcome |
|---|---|---|---|
| SR-114 | critical | internal-consistency, contracts | applied |
| SR-115 | critical | internal-consistency, contracts | applied |
| SR-116 | major | completeness | applied |
| SR-117 | major | ambiguity-testability, contracts | applied |
| SR-118 | major | completeness | refuted |
| SR-119 | major | completeness, ambiguity-testability | applied |
| SR-120 | major | internal-consistency | applied |
| SR-121 | major | ambiguity-testability | applied |
| SR-122 | major | ambiguity-testability | applied |
| SR-123 | major | feasibility | applied |
| SR-124 | major | feasibility | applied |
| SR-125 | major | contracts | applied |
| SR-126 | major | contracts | applied |
| SR-127 | major | contracts | applied |
| SR-128 | major | contracts | applied |
| SR-129 | major | doctrine-compliance | applied |
| SR-130 | minor | internal-consistency | applied |
| SR-131 | minor | internal-consistency, feasibility | applied |
| SR-132 | minor | internal-consistency | applied |
| SR-133 | minor | ambiguity-testability | applied |
| SR-134 | minor | feasibility | applied |
| SR-135 | minor | contracts | applied |
| SR-136 | minor | contracts | applied |
| SR-137 | minor | doctrine-compliance | applied |

**Challenger quorum:** 18 dispatched over 16 entries — 15 upheld, 1 refuted, 0 unconfirmed. Both criticals drew two challengers and both were upheld unanimously. SR-122 was upheld even though round 3 refuted a similar-looking claim about the same bullet: the challenger distinguished the two — the earlier refutation showed the post-condition is not vacuous, while this finding is that it binds no value, a gap round 4's added clause widened.

**Refuted:**

- **SR-118** — no component is assigned stage 3's duties in /fix-report. the spec does assign stage 3's duties on the /fix-report path, in four mutually reinforcing places the finding did not engage: the skill section scopes the per-command difference to what the skill *runs* and names Step 3 as the executor; stage 4 confirms the attribution in the same words; the User decision duty and the dispatch marker are both restated command-agnostically; and the fix-auto consumer bullet asserts the stripped lines never reach the fixer as a property of the fixer's input, not of which command dispatched. Building Step 3 the way the finding fears would contradict three explicit statements rather than fill a gap.

**Fix phase:** 23 batched, 35 pairs dispatched, 35 landed, 0 fix-failed; gate `approve-all`; spec 1093 → 1231 lines.

- *outcome note:* Recorded `applied (not re-reviewed)` at the round-5 terminalization; reverted to `applied` when the user reopened the run, since round 6's fresh panel reads exactly the text these edits produced.
- *merges (an entry whose fix rides inside another's pair):*
  - **SR-121** — no pair of its own — the mixed-plan precedence sentence rides inside SR-114's `**Verification:**` enum pair in Decision record
  - **SR-131** — no pair of its own — the `Bash(git status:*)` drop and the folded `git status --porcelain` sentence ride inside SR-123's Delivery frontmatter pair
  - **SR-133** — no pair of its own — the `; ` delimiter discipline rides inside SR-116's `**Verification-plan:**` grammar pair in Decision record

**Trend:** First decline in the run: raw findings 39, 39, 41, 45, 29; doctrine-compliance fell from 5 major to 1 and refuted bar items 2, 4, 5, 7, 9, 10 and 11 with reasons crediting the round 3-4 fixes; completeness fell from 8 findings to 3.

**Equivalence judgments logged:** 6.

## Round 6 — panel, units

**Panel:** `internal-consistency`, `ambiguity-testability`, `completeness`, `feasibility`, `contracts`, `ux`

**Rationale:** Composition changed for the first time in the run. Both core lenses mandatory; completeness by rule 2 (13 sections); content triggers still yield doctrine-compliance, feasibility and contracts, which with ux makes seven candidates against the cap of 6. Rounds 1-5 all dropped ux; this round drops doctrine-compliance instead. Reasons: ux has never read this spec while the other five have read it five times each, and the report names that as a real coverage gap since the interaction flow is what the spec exists to improve; doctrine-compliance returned its lowest yield of the run in round 5 (1 major, with 7 of the 11 bar items refuted by its own self-falsification pass), and its one standing concession (bar item 6, the unbounded fan-out) is a recorded user decision it would not re-report anyway.

**Units (13 `##` sections):** `Purpose`, `Evidence`, `Scope`, `The flow`, `Components`, `Decision outcomes`, `Status vocabulary extension`, `Decision record`, `Edge cases`, `Delivery`, `Oracle`, `Verification`, `Residual risks`

| SR | severity | lenses | outcome |
|---|---|---|---|
| SR-138 | major | internal-consistency | applied (not re-reviewed) |
| SR-139 | major | internal-consistency, contracts | applied (not re-reviewed) |
| SR-140 | minor | internal-consistency | applied (not re-reviewed) |
| SR-141 | nit | internal-consistency | applied (not re-reviewed) |
| SR-142 | major | ambiguity-testability | applied (not re-reviewed) |
| SR-143 | major | ambiguity-testability, completeness | applied (not re-reviewed) |
| SR-144 | major | ambiguity-testability | applied (not re-reviewed) |
| SR-145 | major | ambiguity-testability, contracts | applied (not re-reviewed) |
| SR-146 | major | ambiguity-testability, contracts | applied (not re-reviewed) |
| SR-147 | minor | ambiguity-testability | reported-only |
| SR-148 | major | completeness | applied (not re-reviewed) |
| SR-149 | major | completeness | applied (not re-reviewed) |
| SR-150 | minor | completeness | reported-only |
| SR-151 | minor | completeness | applied (not re-reviewed) |
| SR-152 | major | ux | applied (not re-reviewed) |
| SR-153 | major | ux | applied (not re-reviewed) |
| SR-154 | major | ux | applied (not re-reviewed) |
| SR-155 | major | ux | applied (not re-reviewed) |
| SR-156 | major | ux | refuted |
| SR-157 | minor | ux | applied (not re-reviewed) |
| SR-158 | major | contracts | applied (not re-reviewed) |
| SR-159 | minor | contracts | applied (not re-reviewed) |
| SR-160 | minor | contracts | applied (not re-reviewed) |
| SR-161 | major | feasibility | applied (not re-reviewed) |
| SR-162 | minor | feasibility | applied (not re-reviewed) |

**Challenger quorum:** 16 dispatched over 16 entries — 15 upheld, 1 refuted, 0 unconfirmed. No criticals this round, so every major drew a single challenger. Five verdicts upheld the finding while explicitly narrowing it (SR-142 blast radius, SR-143 plan-passes path rescued by case 1, SR-152 escalation frequency, SR-153 fix scope, SR-155 grade) and three added evidence the finder had not supplied (SR-149 that Verification step 4 passes vacuously, SR-158 that the canonical Grep citation fails its own support test, SR-161 that Status vocabulary extension anchors the verify to fix-all.md:361 alone). The SR-154 challenger corrected an orchestrator error in its own prompt: fix.md:267-269 does render a Verification Plan.

**Refuted:**

- **SR-156** — the terminal rejection persists no trace of its provenance. The recorded round-2 decision (SR-041) names the exact consequence the finding claims it did not weigh: the sentence making the run summary the sole carrier of an unverified rejection sits one sentence after the argument that the run summary does not survive the session, so the asymmetry was in full view. The provenance half fails independently: the status grammar already mandates (YYYY-MM-DD), and every reject reason is collected through AskUserQuestion with any prefill confirmed before the write, so the user is answerable for the sentence whoever drafted it.

**Fix phase:** 22 batched, 36 pairs dispatched, 36 landed, 0 fix-failed; gate `approve-all`; spec 1231 → 1430 lines.

- *outcome note:* Round 6 is the final permitted iteration, so every landed fix takes `applied (not re-reviewed)`: no fresh panel will read the text these edits produced.
- *merges (an entry whose fix rides inside another's pair):*
  - **SR-146** — partly rides in other pairs: its one-physical-line rule for a check is inside SR-144 Verification Plan row pair, and the (soft) marker on the persisted line is inside its own Verification-plan grammar pair.
  - **SR-151** — no pair of its own — the hard/soft classification test rides inside SR-139 **Verification:** grammar pair, where the decision asked for it to sit, and the (soft) marker rides inside SR-146 Verification-plan grammar pair and SR-144 return-contract pair.
  - **SR-162** — the two-observation rewrite rides inside SR-143 stage-4 tree-observation pair as well as carrying its own Oracle row pair.
  - **SR-142** — the :edit/:ref expected-set rule rides inside SR-143 stage-4 pair and SR-162 Oracle pair, alongside its own four pairs for the pin written form, the membership and role rules, and the two stage-4 case lines.
  - **SR-161** — the fix-report half rides inside SR-149 command-row pair, alongside its own two pairs in Delivery and Verification step 5.
  - **SR-160** — the status prefix registration rides inside SR-159 report-format bullet pair, alongside its own Verification step 5 pair.

**Trend:** No decline. Raw findings 29 and major+ 16 in both round 5 and round 6, on a spec that grew 1093 -> 1231 -> 1430 lines across those two rounds. The no-progress stop did not fire because the entries are different every round: the loop keeps finding different defects at a constant rate rather than converging. Round 6 reproduced the churn pattern exactly — SR-139 comes from round 5 SR-114 and SR-129 fixes colliding, SR-146 from the delimiter SR-133 fix closing only one of three, SR-143 and SR-142 from the unpinned path and the pin membership rule that earlier rounds introduced.

**Equivalence judgments logged:** 9.

## Decisions (user-decided, all accepted)

Every needs-decision entry that reached the gate was decided *accept*, several with the user choosing an alternative over the proposed fix. No entry was kept as is and none was declined.

| SR | round | the decision |
|---|---|---|
| SR-024 | 1 | Residual-risks disclosure branch: record stage 1's fan-out as deliberately unbounded in dispatches, wall-clock and token cost. No hard ceilings, no Budgets section, and the 'No hard cap on finding count' sentence in Edge cases is left untouched. |
| SR-033 | 2 | Fix the pin's scope, keep the mechanism: the pin hashes the finding's own block with the loop-written lines excluded (Decision, Decision-pin, Status) plus file blobs; the report file's own hash is never pinned. The three ordering invariants stand unchanged. |
| SR-034 | 2 | Stage 4 becomes four-way: pass -> Fixed; edited but not passing -> Partially Fixed; dispatch error or no edit -> no Status line, attempt counted; no runnable plan -> no Status line plus 'verification: unavailable' in the summary. |
| SR-035 | 2 | Same four-way map as SR-034. Absent coverage is never written Partially Fixed, which is terminal at both Step 1.3 filters; the precedent is stage 0's own Failed handling. |
| SR-041 | 2 | Re-run the analyst's cited commands in stage 2 before offering a rejection and show the raw output at the gate; on mismatch reject is not offered and the finding returns to the sweep. Nothing beyond the existing reason tail is written — no Rejection-evidence block, and 'for a rejection the status is the record' stands. |
| SR-044 | 2 | Keep the unbounded fan-out; restate the Residual risks entry to say outright that bar item 6 is not met and that this is a deliberate choice. No ceilings, no Budgets section, and the 'No hard cap on finding count' sentence stays. |
| SR-057 | 3 | Persist the plan with the decision: a **Verification-plan:** companion line written in stage 2 for the decided alternative, added to stage 2's permitted writes and the pin's excluded lines; the replay path runs it, and 'the replay path' is struck from stage 4's fourth case. |
| SR-058 | 3 | Runnable = anything the orchestrator can execute and log, a soft LLM re-read included. A soft check lands in stage 4's first case (Fixed) with 'advisory verification' in the run summary; the fourth case narrows to 'no plan of any kind exists'. |
| SR-066 | 3 | Fix the example, keep the contract: the canonical decision example names both files and lines with no deixis, and the pin's deictic clause becomes a fallback for a contract violation rather than an expected form. |
| SR-073 | 3 | Name the execution boundary: read-only inspection plus the project's declared test and build commands; anything outside is shown and approved before execution; a refused or unrunnable check takes stage 4's fourth case. State why — the commands carry Bash(git:*) as a pre-approval, so an unbounded plan could destroy the uncommitted diff Oracle names as the recovery path. |
| SR-090 | 4 | Keep the analyst's grant narrow. The return contract gains a second citation form for tool-gathered evidence (`tool: Grep pattern=… path=…` plus verbatim result) alongside the shell form; the orchestrator re-runs both, since it holds the same tools. The ls/rg example is replaced with citations the declared grant can produce. |
| SR-093 | 4 | decision-gate runs stages 0–2 in the Step 2.4 slot and returns the decided findings to Step 3, which dispatches decided and auto findings in one sequential batch, decided first. Stage 3.5 applies to decided findings only; auto findings keep today's path. Step 4.1/4.1.5 runs once over the whole batch and the gate performs no write-back in /fix-report. |
| SR-104 | 4 | Keep the loop unbounded; repair the rationale. The sentence about a cap is rewritten to argue against a *silent* cap rather than caps as such, noting the design already has the visible-unprocessed form in `skip`, and to state plainly that this is a deliberate departure from bar item 6 rather than a reading that satisfies it. No ceilings, no Budgets section. |
| SR-114 | 5 | Drop `unverified` from the Verification enum, leaving hard|advisory|unavailable. The three statements that a rejection persists nothing beyond the reason tail stand untouched, and the run summary remains the sole carrier of an unverified rejection — consistent with the SR-041 decision in round 2. |
| SR-116 | 5 | Add an expected result to every check: `<check> → <expected>` in the contract and in the persisted grammar, and a stage 3.5 rule that a check passes when its logged output matches the recorded expectation, never on exit status alone. |
| SR-129 | 5 | Separate check level from plan level. The fourth case narrows to 'no check of any kind ran'; where some checks ran and passed, the finding is graded on those and the shortfall is disclosed in the Verification line and a run-summary warning — the shape the spec already uses for soft verdicts. |
| SR-146 | 6 | First arrow splits: no check carries a `; `, a ` → ` beyond its own separator, or an embedded newline — one that would is rewritten or split by the analyst before it is returned, mirroring the rules the spec already states for `; ` and for the ` — ` on the Decision line. Add the general invariant: every loop-written field occupies exactly one physical line, so the prefix-keyed strip in stage 3 and the grep -v of the pin pipeline both remove it whole. resolution text on Decision and Decision-retired lines is likewise single-line. |
| SR-148 | 6 | Attributable change re-pins silently. A mismatch whose changed hashes are all attributable to a dispatch this run made after the pin was written re-pins and dispatches without a re-ask; only an unattributable change sends the finding back through the analyst and the sweep. Kills the cascade at its root, since every mismatch in the second pass is self-inflicted by the loop. |
| SR-154 | 6 | State the render in stage 2 and repeat it once in the decision-gate skill. Always rendered: Target, Recommendation with its reason, Risk, both Alternatives in full, Code Preview, and any Decision-retired lines. Held back unless the user asks: the verbatim command and tool output backing Findings (the claims themselves are rendered), and both Verification Plans. Always rendered and never held back: the re-run raw output of a Rejection candidate citations and the recorded/fresh side-by-side where that re-run diverges. |

## Coverage

- **Catalog lenses not selected in every round:** the roster yields seven candidates against a cap of 6, so one is dropped each round. Rounds 1–5 dropped `ux`; round 6 dropped `doctrine-compliance` instead and ran `ux` for the first time, on the grounds that `doctrine-compliance` had returned its lowest yield of the run in round 5 (1 major, 7 of the 11 bar items refuted by its own self-falsification pass) while `ux` had never read the spec at all. That swap paid immediately: `ux` returned 6 findings, 5 of them major, and four of the five are defects no other mandate could reach — the stage 3.5 escalation interrupting the phase the design sells as unattended, the "Skip remaining" item that does the opposite of its label, the unbounded per-decision reading cost, and stage 0's hand-researched address being discarded on `skip`. The cost of the five rounds without it is exactly those four defects surviving five panels. `doctrine-compliance` in turn did not read round 6's text, so the loop-engineering bar was not graded against the final spec.
- **Not returned (failures, with reasons):** none. All 36 reviewer dispatches (6 lenses × 6 rounds) returned parseable JSON on the first attempt; no lens needed a retry and no round is shallow. All 110 challenger dispatches returned a verdict; zero entries are `unconfirmed`.
- **Standing oracle blind spots:** intent, external facts, unstated requirements. Three concrete instances in this run: no reviewer could check that the design still answers the user's original complaint (fixing needs-decision findings one `/fix` at a time); no reviewer executed a single line of the behaviour the spec describes, since no code exists yet; and `feasibility` reads the repository but cannot confirm that Claude Code's own runtime honours a `Bash(sed:*)` specifier — the spec now carries that as a verification step precisely because the loop could not settle it.
- **Not re-reviewed:** round 6's 22 fixes, 36 pairs, +269/−70 lines. The run stopped on the iteration cap immediately after applying them, so the text they produced has been read by no panel and no challenger. Round 5's fixes were in this position at the previous terminalization and are no longer: round 6 read them, and found 16 major+ entries in the result.

## Rejected by the panel (self-falsification)

Every reviewer runs a refutation pass over its own candidates before returning and reports what it killed. These are **not findings** — they are the loop's record of what a fresh panel re-derives and re-kills each round, which is why the format forbids dropping them. Rounds 3–5 were harvested from the reviewer transcripts at terminalization.

**421 candidates self-falsified across the run** (62 · 70 · 70 · 74 · 70 · 75 by round).

### Round 1 — 62 rejected

- [internal-consistency] Stage 3 'fix-auto x M' vs 'Ordering inside /fix-report' saying later-page auto findings are fixed in the same batch - refuted: M is never bound to the decision-stage input.
- [internal-consistency] fix.md row says 'Behaviour identical' while Status vocabulary extension lists fix.md as a consumer - refuted: 'behaviour unchanged' is scoped to the Phase 3 Alternatives delegation.
- [internal-consistency] 'Failed' is used in The flow and Edge cases but absent from the status vocabulary - refuted: that sentence never claims exhaustiveness and Failed is cited as pre-existing behaviour.
- [internal-consistency] Delivery calls qa 2.5.2 -> 2.5.3 a PATCH while loop.md must read Rejected as terminal - refuted: grading needs the repo's external SemVer rule, not the spec's own text.
- [internal-consistency] decision-gate contents list omits stage 0's location pre-check - refuted: The flow governs both entry points and the list reads as descriptive, not exhaustive.
- [internal-consistency] Purpose says fixers run as a single batch while /fix-all Step 5 runs after its auto batch - refuted: Components states /fix-all differs by construction.
- [internal-consistency] Evidence says installed copy is 1.17.0 yet concludes this is not version drift against 1.17.3 - refuted: the claim is that Step 2.4 is present in both copies.
- [internal-consistency] Out of scope forbids new command arguments while Decision outcomes adds an 'other...' outcome - refuted: it is an in-sweep prompt option, not command syntax.
- [internal-consistency] Stage 1 'batches of at most 8' vs Edge cases 'No hard cap on finding count' - refuted: 8 is a batch width, not a cap; batches are announced.
- [internal-consistency] Decision outcomes skip 'reappears on the next run' vs Edge cases 'the next run reports how many remain' - refuted: both describe re-surfacing undecided findings.
- [ambiguity-testability] 'Analyst fails or returns an unusable block' leaves 'unusable' undefined - refuted: the return contract's 'Every field is required unless marked optional' gives a presence test.
- [ambiguity-testability] Target must be 'verified against the file' but the orchestrator never re-reads the code, so the claim cannot be checked - refuted: it is an instruction to the analyst, and Residual risks discloses 'Analyst quality is unmeasured'.
- [ambiguity-testability] The Findings field's bar 'Concrete and citable' is unmeasurable - refuted: explicitly flagged under Residual risks.
- [ambiguity-testability] reject's <reason> provenance is unspecified - refuted: 'the user chooses' plus 'Carries the reason' makes either source acceptable with no observable difference.
- [ambiguity-testability] Stage 1's 'batches of at most 8' does not say whether batch 2 waits for batch 1 - refuted: 'successive announced batches' fixes the sequential reading.
- [ambiguity-testability] Stage 4's 'Existing Steps 4.1 / 4.1.5, unchanged' is ambiguous for /fix-all - refuted: reuse of the same write-back procedure is the only load-bearing reading.
- [ambiguity-testability] Whether /fix-all's needs_decision list is severity-floored before the decision stage is unstated - refuted: Evidence states it is exempt from the floor.
- [ambiguity-testability] 'No hard cap on finding count' versus 'batches of at most 8' reads as a cap - refuted: batching is announced and non-truncating.
- [ambiguity-testability] qa 2.5.2 -> 2.5.3 as PATCH for a behavioural read-change - refuted: versioning doctrine is outside this lens's mandate.
- [completeness] Stage 3 dispatch drops the analyst's verified Target/Code Preview - refuted: stage 3 states the payload explicitly and Evidence justifies it.
- [completeness] The partitioned needs-decision page has no stated size rule - refuted: 'their own labelled first page' (singular) plus 'No hard cap on finding count' arbitrate one unpaginated page.
- [completeness] The Alternatives derivation covers only dead-reference and decision Drift-classes - refuted: the 'names none' clause reads as the general fallback and classification is out of scope.
- [completeness] 'Failed' is used in stage 0 and Edge cases but absent from the status vocabulary - refuted: Edge cases delegates it to existing behaviour.
- [completeness] Unclear whether skip writes a Decision line - refuted: the outcomes table settles it with 'No dispatch, no status.'
- [completeness] With >8 findings, unclear whether the sweep interleaves with analyst batches - refuted: Purpose states decisions are collected in one uninterrupted sweep.
- [completeness] docs/plugins/qa.md is missing from the consumers-to-update list - refuted: Verification step 5 greps across plugins/ and docs/.
- [completeness] decision-analyst frontmatter omits model:, description: and the dispatch prompt's contents - refuted: implementation-plan detail.
- [completeness] The analyst is not required to load finding-falsification - refuted: explicitly flagged under Residual risks.
- [completeness] No CI guard for the three-value status vocabulary - refuted: listed under Out of scope and again under Residual risks.
- [completeness] No behaviour defined for the decision sweep in a headless session - refuted: no entry point in this spec claims non-interactive operation.
- [completeness] /fix loads decision-gate yet is not said to offer the new reject outcome - refuted: the table states 'Behaviour identical' and scopes the shared piece to the Alternatives format.
- [completeness] /fix-all Step 5 offer granularity is unstated - refuted: the Edge cases row for 'User answers no' establishes a single yes/no offer.
- [feasibility] The decision sweep renders five options against AskUserQuestion's 4-option pages - refuted: 'other...' is the built-in free-text answer, leaving exactly four explicit options.
- [feasibility] decision-gate cannot be loaded because the commands omit Skill from allowed-tools - refuted: CLAUDE.md states command allowed-tools pre-approves prompts without affecting availability.
- [feasibility] Task is in KNOWN_BAD_TOOLS so the fan-out tool does not exist - refuted: that check scans only plugins/*/agents/*.md and the analyst's grant contains no Task.
- [feasibility] Parallel dispatch of up to 8 subagents in a single turn is unsupported - refuted: plugins/qa/commands/run.md already launches agents in parallel.
- [feasibility] Bash(git:*) in tools: fails check_agent_frontmatter.py - refuted: _uses_colon_specifier produces a warning, not an error.
- [feasibility] Rejected collides with the plugin's existing 'Rejected after verification' vocabulary - refuted: those entries are plain bullets, never ### headings.
- [feasibility] /qa:loop Step 4.1 would overwrite Rejected - refuted: the spec delegates this to the named consumer update. [NOTE: the contracts lens raised the same candidate and the challenger upheld it as SR-028; this refutation did not survive.]
- [feasibility] The next run's replay of recorded Decision lines is unspecified - refuted as a feasibility matter: reading one more field is mechanically trivial; the gap belongs to completeness.
- [feasibility] Stage 0's request for a path:line needs free-text input AskUserQuestion cannot collect - refuted: fix-report.md:187 already asks for the target file in the same question flow.
- [feasibility] The decision sweep would break because AskUserQuestion is stripped from every subagent - refuted: the sweep runs in the command's main context.
- [feasibility] Evidence line-number citations are stale - refuted by direct check: all cited lines land on the cited text.
- [feasibility] 'Partially Fixed appears in seven files across two plugins' is miscounted - refuted: grep returns exactly seven non-spec files.
- [feasibility] 'No live fixtures exist' is wrong - refuted: docs/reviews/ and docs/testing/reports/ are both absent from the tree.
- [feasibility] Version baselines 1.17.3 / 2.5.2 and the '/fix-all skips needs-decision' descriptions are stale - refuted: both match plugin.json and marketplace.json verbatim.
- [feasibility] The analyst would need write access to record decisions inline - refuted: the decision record is written by the orchestrator in stage 2.
- [doctrine-compliance] Item 3 (disclose, don't gate, on coverage) - refuted: analyst failure degrades with a visible note, 'Never a silent skip', and no shallow-coverage path flips the run to failure.
- [doctrine-compliance] Item 7's 'report stopped as distinct from success' half - refuted: the inherited Step 4.2 summary renders Fixed/Partially Fixed/Failed counts; only the no-progress half is reported.
- [doctrine-compliance] Item 8 (residual-risk list) - refuted: Residual risks enumerates four named blind spots rather than gesturing generically.
- [doctrine-compliance] Item 9 (provenance guard) - refuted: Rejection candidate plus a reject outcome is an explicit 'the failure may be the assertion' path.
- [doctrine-compliance] Item 11 (writes scoped, recoverable, uncommitted) - refuted: writes are confined to the target file and its source report and remain uncommitted; the mutating-git exposure is reported under item 5 instead.
- [doctrine-compliance] Missing N/A declarations for conditional items 9-11 - refuted: all three triggers fire, so no N/A justification is owed.
- [doctrine-compliance] Stage 0's location pre-check as an item 5 miss - refuted: it asks before fan-out and marks the finding Failed rather than dispatching at an unresolvable target.
- [contracts] The analyst return contract gives no serialization or field order - refuted: Components names decision-gate as the single source of truth for that contract.
- [contracts] Rejected would not be caught by the already-fixed filters - refuted: Status vocabulary extension lists both Step 1.3 filters as consumers to update.
- [contracts] The Decision line collides with the Status write-back slot - refuted: the documented Edit recipe inserts Status above an existing Decision line.
- [contracts] /fix Phase 3's field set differs from the analyst return contract - refuted: the delegation is scoped to the Alternatives format.
- [contracts] The value domain of Decision is unspecified for skip - refuted for this lens: the outcomes table settles the artifact side; sweep wording is not a contract question.
- [contracts] The new Decision field breaks older parsers - refuted: both plugins extract whole blocks and match named fields, so an unrecognised line is ignored.
- [contracts] The optional Rejection candidate field has no defined consumer - refuted: Decision outcomes states the user chooses from it and Verification step 4 exercises the path.
- [contracts] fix-auto could see a conflicting Decision line and User decision line with no precedence rule - refuted: fix-auto.md:52 already declares User decision authoritative.

### Round 2 — 70 rejected

- [internal-consistency] Stage 3 credits 'Stage 0's substitution' though stage 0 only asks for missing values — refuted as standalone: the same sentence defines the scope; the load-bearing half is reported separately.
- [internal-consistency] Decisions collected 'with AskUserQuestion and with nothing else' vs 'other…' free text and the reason prompt — refuted: AskUserQuestion supports free-form input.
- [internal-consistency] Prefix matching justified by fix-all.md:361, which verifies a line that can never carry a reason tail — refuted: the Step 1.3 filters do meet reason-carrying lines, so the rule stands and only the example is loose.
- [internal-consistency] 'Dispatched in a single turn' vs 'successive announced batches' — refuted: the single turn is per batch.
- [internal-consistency] Verification post-condition on dispatch order vs /fix-all fixing the auto batch first — refuted: it constrains what follows the fan-out.
- [internal-consistency] '/fix never writes Rejected' vs fix.md listed as a consumer — refuted: the listed change is status handling, which does not entail writing.
- [internal-consistency] Stage 2 permits two writes while stage 3 overwrites Location — refuted: the restriction is scoped by its own wording to 'this stage'.
- [internal-consistency] Delivery lists prose corrections Scope does not enumerate — refuted: Scope's four-places clause covers them.
- [internal-consistency] Degraded path takes A and B from the Remediation while the contract derives them from Drift-class — refuted: the contract's own branch anchors alternatives in the Remediation.
- [internal-consistency] The abort clause vs stage 2 writing each decision as it is made — refuted: the abort governs findings not yet decided.
- [internal-consistency] Stage 4 cites fix-all.md step numbers for both entry points — refuted: the parenthetical implies the same numbering exists in /fix-report.
- [ambiguity-testability] 'Unusable block' undefined — refuted: the contract's 'every field is required unless marked optional' is the criterion.
- [ambiguity-testability] Stage 0's single prompt has no per-finding decline — refuted: 'findings whose target the user declines' already resolves it finding by finding.
- [ambiguity-testability] Residual risks relies on a pre-flight count The flow never shows — refuted here: the checklist selection and the Step 5 offer are stated consent points. [Reported separately as SR-055 by internal-consistency.]
- [ambiguity-testability] 'Match by prefix' never says which prefix — refuted: paired with the exact current line, making the status value the prefix.
- [ambiguity-testability] 'Single turn' vs 'batches of at most 8' — refuted: scoped per batch.
- [ambiguity-testability] Degraded path undefined when the Remediation names no alternatives — refuted: the Alternatives row supplies the fallback.
- [ambiguity-testability] Stage 0's 'the path exists' does not name its root — nit at most, no competing reading for a repo-scoped command.
- [ambiguity-testability] 'Normalised to the path:line form' could read as silently discarding a range — refuted: the parenthetical fixes it.
- [ambiguity-testability] Verification step 5's per-file duty looked uncheckable — refuted: it names the concrete duty and requires a recorded line number.
- [ambiguity-testability] Five options may exceed AskUserQuestion's capacity — outside this lens's mandate. [Reported as SR-049 by feasibility.]
- [completeness] Fan-out has no pre-flight consent gate — refuted: the checklist selection and the Step 5 offer are the consent point with the count in view.
- [completeness] Stage 0's collection mechanism unspecified — refuted: 'and nothing else' binds the sweep, not a data prompt, and the choice changes no downstream behaviour.
- [completeness] No rule for a user-supplied location that is itself unusable — refuted: stage 0's test applies to any location value.
- [completeness] Location overwrite destination unclear — refuted for this lens: the analyst re-verifies each run; the two-readings framing belongs to ambiguity. [Reported as SR-036.]
- [completeness] Pin mismatch forces a mid-stage-3 re-ask, contradicting the uninterrupted sweep — refuted: this is a consistency claim, not a completeness gap. [Reported as SR-033 by internal-consistency.]
- [completeness] Sweep and dispatch ordering unspecified — refuted: no stated behaviour depends on it and the pin covers the order-sensitive risk.
- [completeness] AskUserQuestion may not present five outcomes — refuted for this lens: a platform-capability question owned by feasibility.
- [completeness] The dispatch marker's written form is undefined — refuted: its purpose and the two states it must distinguish are stated; the token is plan detail.
- [completeness] The analyst is not required to load finding-falsification — refuted: disclosed and deferred under Residual risks.
- [completeness] Stage 1 carries no dispatch, time or token budget — refuted: disclosed as a knowing choice. [Graded unmet as SR-044 by doctrine-compliance, which holds disclosure is not a budget.]
- [completeness] No CI guard for the status vocabulary — refuted: Out of scope and Residual risks.
- [completeness] The fixture's path and block shape are unspecified — refuted: step 4 fixes its contents and post-conditions.
- [completeness] qa doc prose updates not enumerated — refuted: Delivery names the upgrade-notes duty and the four-place rule.
- [feasibility] Parallel fan-out in a single turn is unbuildable — refuted: spec-review.md:129 and qa/commands/run.md:82 both demonstrate it.
- [feasibility] Bash(git log:*) narrowing is unsupported in an agent's tools — refuted: feedback-analyzer.md:4 already ships the family.
- [feasibility] disallowedTools would fail the frontmatter check — refuted: it is in PERMITTED_KEYS and the strip branches are gated on key == 'tools'.
- [feasibility] The thirteen-keys citation is stale — refuted: the set holds exactly thirteen keys at those lines.
- [feasibility] fix-all.md:361's whole-line match breaks on a reason-carrying line — refuted: the spec already mandates prefix matching for it.
- [feasibility] The analyst cannot ask for a missing location — refuted: stage 0 puts the ask in the orchestrator.
- [feasibility] Stage 0's single prompt exceeds AskUserQuestion's question limit — refuted: stage 0 is not bound to that tool.
- [feasibility] The new stages need Bash grants the commands lack — refuted: allowed-tools is pre-approval, and the verifiers are already listed.
- [feasibility] reject's pasted evidence has no slot — rejected as out of lens: a spec-internal definition gap, not a delivery limit. [Reported as SR-041.]
- [feasibility] Version targets are stale — refuted: the manifest holds 1.17.3 and 2.5.2 and the checker checks the four named places.
- [feasibility] The seven-file / no-CI-guard evidence is wrong — refuted: the phrase occurs in exactly those seven files.
- [feasibility] The 'no live fixtures' premise is wrong — refuted: neither directory exists in this tree.
- [feasibility] The line-number citations have drifted — refuted: every one lands on the attributed text.
- [feasibility] Adding an agent trips EXPECTED_AGENT_FILES = 25 — refuted: that constant only warns when the count falls below 25.
- [doctrine-compliance] Item 1 unmet — refuted: the Oracle names a deciding signal per outcome and closes with what none can check.
- [doctrine-compliance] Item 4 unmet (no TTY probe) — refuted: there is no headless mode to opt into, the gate is mandatory, and it fails closed by attempt rather than heuristic.
- [doctrine-compliance] Item 4 unmet via the two non-sweep prompts — refuted: the location case fails closed and the reason prompt sits inside the sweep.
- [doctrine-compliance] Item 5 unmet (read-only not machine-enforced) — refuted: the spec reuses the platform's guards rather than reinventing, and discloses the non-enforcement in the same paragraph.
- [doctrine-compliance] Item 7 unmet (retire-then-cycle) — refuted: two failures is a no-progress stop, every re-open passes back through the human gate, and failed attempts are reported separately.
- [doctrine-compliance] Item 8 unmet — refuted: five named blind spots.
- [doctrine-compliance] Item 9 unmet — refuted: Rejection candidate, the reject outcome and the re-run rule guard exactly that case.
- [doctrine-compliance] Item 9 unmet via the Location overwrite — refuted as an item 9 finding; reported under item 11 instead. [SR-037.]
- [doctrine-compliance] Item 10 unmet because state is inline rather than a sidecar — refuted: the bar's substance is on-disk state, which inline lines satisfy.
- [doctrine-compliance] Item 6 partially met via retry limits — refuted as a defence: those bound retries, not dispatches, time or tokens.
- [doctrine-compliance] Anti-pattern 'self-graded fix loop' — refuted: stage 3.5 moves the verdict to the orchestrator; the residual defect is plan authorship, reported as SR-043.
- [doctrine-compliance] Oracle vs Decision record on where rejection evidence is logged — a real contradiction but internal-consistency's mandate, not a doctrine item. [Reported as SR-041.]
- [contracts] The return contract has no wire syntax — refuted: decision-gate SKILL.md is the named deliverable carrying it.
- [contracts] New Decision / Decision-pin lines break the block parser — refuted: both plugins split on ### / --- / EOF and match named fields.
- [contracts] fix-auto's Remediation extraction would swallow the Decision line — refuted: the line sits immediately after the heading and Remediation is bounded by the User decision line.
- [contracts] The reason tail breaks fix-all.md:361 — refuted: :361 verifies only lines the loop just wrote, which cannot carry a reason.
- [contracts] The status grammar is ambiguous when the reason contains an em dash — refuted: consumers match by prefix, so the tail is never re-parsed.
- [contracts] qa 2.6.0 understates the change — refuted: additive to qa's own behaviour, and MAJOR is reserved for removals or incompatible formats.
- [contracts] Normalising a range to its start line loses information — refuted: fix-auto parses path:line and reads surrounding context anyway.
- [contracts] Optional Rejection candidate leaves the reason undefined — refuted: the prompt-for-a-reason fallback covers it.
- [contracts] Fix-policy / Drift-class need schema changes — refuted: classification is out of scope and reject is recorded via Status.
- [contracts] Decision-pin hashes pollute fix-auto's input — refuted: Phase 1 extracts a fixed field list and ignores unrecognised fields.

### Round 3 — 70 rejected

- [completeness] No grammar given for the `**Decision-pin:**` line — refuted: its semantics are fully specified (block sha256 plus one hash per pinned file) and the serialization is plan-level detail my mandate forbids demanding.
- [completeness] Attempt counter after retirement (does a fresh decision start at 1 or at 3?) — refuted by "two failed attempts on the same recorded decision": the count is per recorded decision, so a fresh sweep starts a fresh count.
- [completeness] Timing of the pin-mismatch re-analysis inside the sequential batch is unstated — refuted: "The pin is compared immediately before dispatch; on mismatch ... the analyst is re-run" fixes the moment.
- [completeness] A finding repeatedly landing in stage 4's fourth case loops forever — refuted: an already-applied resolution makes the re-dispatched fixer report no edit, which is stage 4's third case, appends `attempt N: failed`, and retires the decision after two.
- [completeness] Reject gate has nothing to re-run when the analyst cites no commands — refuted: the return contract requires `Findings` to "carry the verbatim command output backing each claim", so such a block is "unusable" and takes the degraded path, where `Edge cases` keeps reject reachable.
- [completeness] Stage 0 says nothing about a supplied path:line that still does not parse or does not exist — refuted: stage 0's own usability test applies to the supplied value, and a value failing it leaves the finding location-less and Failed.
- [completeness] Dispatch order of decided vs `auto` findings inside `/fix-report`'s single batch is unstated — refuted as low-consequence: the pin check absorbs any pinned file an earlier dispatch edited, whichever order is chosen.
- [completeness] `/fix <ID>` aimed at an already-rejected finding is unspecified — refuted: `Status vocabulary extension` gives fix-auto Phase 1 an explicit abort on a dispatched block carrying `**Status:** 🚫 Rejected`, and `/fix` dispatches fix-auto.
- [completeness] `Oracle`'s `✅ Fixed (advisory verification)` for a prose-only check versus stage 4's "no Status: line" for "a finding whose checks are not executable" — a contradiction between two sections, internal-consistency's domain, not a completeness gap.
- [completeness] Whether the corrected Location is written when the user picks skip or reject — refuted: stage 2 permits that write only "at the moment the decision is written", and `Decision outcomes` says skip "writes nothing at all".
- [completeness] Whether `/fix` can load `decision-gate` "for the `Alternatives:` render format only" — a platform-capability question, feasibility's domain, not completeness.
- [completeness] Stage 0's construct for asking "in one prompt covering every location-less finding" is unstated — refuted: the AskUserQuestion-only mandate in `Decision outcomes` is scoped to the five-outcome sweep, and the prompt's shape is plan-level detail.
- [ambiguity-testability] Decision-line grammar's `[...]` notation collides with `Status`'s `[ — <reason>]` (literal brackets vs optional) — refuted: the worked example shows literal brackets and the prose makes the provenance marker unconditional, so the `final ` [`' extraction rule always has a delimiter.
- [ambiguity-testability] Stage 1's "Dispatched in a single turn" contradicts "More than 8 findings run in successive announced batches" — refuted: "batches of at most 8" plus "successive announced batches" reads naturally as one turn per batch, and the 3-finding fixture makes Verification's "single turn" post-condition determinate.
- [ambiguity-testability] Stage 4's `⚠️ Partially Fixed` case turns on "the fixer edited", an unobservable-to-the-orchestrator fact — refuted: the adjacent third case names the signal ("or the fixer reports no edit"), so the fixer's report governs both cases.
- [ambiguity-testability] Whether a pin mismatch re-asks the user mid-batch, breaking the "one uninterrupted sweep" promise in Purpose — refuted: "The pin is compared immediately before dispatch; on mismatch … the analyst is re-run … and the user is re-asked" places both inline at that dispatch.
- [ambiguity-testability] Whether `✅ Fixed (advisory verification)` is written into the report's Status line, which the status grammar forbids for anything but `🚫 Rejected` — refuted: "the run summary marks the finding" scopes the marker to the summary explicitly.
- [ambiguity-testability] Stage 0's "one prompt covering every location-less finding" does not name a construct and may exceed `AskUserQuestion`'s four-option ceiling — refuted: the AskUserQuestion mandate is scoped to the decision sweep ("collected with `AskUserQuestion` and with nothing else"), leaving stage 0's prompt construct deliberately unconstrained; the mechanism question is a feasibility matter.
- [ambiguity-testability] "Skip remaining" on a needs-decision page could be read as exiting the whole checklist, defeating "never leave a needs-decision finding undisplayed" — refuted: the command-changes row redefines it per-page ("On a non-final needs-decision page 'Skip remaining' advances to the next needs-decision page").
- [ambiguity-testability] The replay check trigger ("a Decision: line and no Status: line") would replay a decision already retired after two failures — refuted: the entry names "the retry limit under Decision record" as one of the conditions the replay is subject to.
- [ambiguity-testability] No acceptance criterion exercises the `Decision-pin:` line, the two-attempt retirement, or the replay path — out of mandate: absent test coverage is a completeness question, not an uncheckable criterion.
- [ambiguity-testability] The pinned file set ("every `path[:line]` token appearing in the resolution text") has no extraction rule, so `other…` wording pins different files for different implementers — refuted as low-consequence: a missed or extra pin degrades only to a re-ask, which the spec already treats as the safe direction.
- [doctrine-compliance] Item 1 (oracle unnamed) — refuted: a dedicated `Oracle` section names a deciding signal per outcome and closes with three things none of the oracles can check.
- [doctrine-compliance] Item 2 (the analyst authors both the resolution text and the Verification Plan that grades it) — refuted: the corrector never authors or sees the plan (stage 3 dispatches issue block + `User decision:` only, and the plan is never written to the report), the plan is rendered to the human at the gate, and the return contract rejects plans that "merely restate the intended edit".
- [doctrine-compliance] Item 2 (for `other…` the orchestrator derives, runs and grades its own checks) — refuted: the orchestrator is not the actor, the checks are explicitly "recorded as post-decision", and the fixer still cannot see them.
- [doctrine-compliance] Item 3 (the `reject` gate withdraws an outcome when the re-run evidence no longer supports it — a green→red flip) — refuted: that is a fail-closed guard on raw re-run output before a terminal write, not a coverage judgment.
- [doctrine-compliance] Item 4 (no TTY probe, so headless behaviour is heuristic) — refuted: the design has no headless path at all; every decision is a mandatory `AskUserQuestion`, "The orchestrator never supplies a decision on the user's behalf and never infers one from the analyst's recommendation", and gate unavailability aborts fail-closed with no dispatch and no `**Decision:**` line.
- [doctrine-compliance] Item 5 (guards reinvented — an inline decision record instead of the existing `superutils` sidecar) — refuted: item 5 governs safety guards, and the spec reuses them (Step 4.1/4.1.5 write-and-verify, `fix-auto`'s existing dispatch contract, `fix-report` Step 2.4's Failed handling, ambiguous/missing input → ask at stage 0 or abort).
- [doctrine-compliance] Item 7 (no no-progress stop) — refuted: a decision is retired after two failed attempts, failed attempts are "reported under their own heading, never folded into the fixed set", `verification: unavailable` names the finding in the run summary, and an aborted sweep reports how many findings were left undecided.
- [doctrine-compliance] Item 7 (uncapped retire → re-decide → fail → retire cycles across runs) — refuted: every cycle re-enters a human sweep where `reject` and `skip` are available, so the loop cannot spin without a human electing to continue.
- [doctrine-compliance] Item 8 (residual risks undocumented) — refuted: six risks are enumerated, including a self-reported bar violation.
- [doctrine-compliance] Item 9 (provenance unguarded — the finding may be the failure, not the code) — refuted: the `Rejection candidate` field, the user-owned `reject` outcome, `Findings` carrying verbatim command output, and the orchestrator re-running the cited commands at the gate are precisely that guard, and it stays reachable on the degraded path.
- [doctrine-compliance] Item 10 (the block hash may be computed before stage 2's `Location:` rewrite, so every location-corrected decision would mismatch its own pin at stage 3) — refuted: stage 2 writes the corrected `Location:` and the decision together "at the moment the decision is written", so the natural reading has the hash cover the corrected line.
- [doctrine-compliance] Item 11 (changes not left uncommitted) — refuted: `Oracle` states "A wrong call lands as an uncommitted diff the user can read and revert", and the pin design depends on it ("a commit pin cannot observe the very event the pin exists to detect").
- [doctrine-compliance] Conditional items 9/10/11 lack the one-line N/A justification — refuted: all three triggers fire and the spec addresses each substantively; the N/A form applies only to untriggered items.
- [internal-consistency] Evidence cites the installed copy as code-review 1.17.0 while the header says 1.17.3 — refuted: the claim is only that Step 2.4 is present in the installed build, so its non-firing is not explained by drift; the two version numbers are consistent with that argument.
- [internal-consistency] Stage 1's "Dispatched in a single turn" contradicts "More than 8 findings run in successive announced batches" — refuted: single-turn is stated per batch, and Verification's transcript post-condition is scripted against a fixture with at most two analysts.
- [internal-consistency] Stage 4's fourth case leaves a replayed decision re-dispatching forever with no `attempt N` recorded, contradicting Decision record's "fail identically, forever" argument — refuted: once the fixer edits a pinned file the Decision-pin comparison mismatches before the next dispatch, which re-runs the analyst and re-asks, so the cycle terminates.
- [internal-consistency] `✅ Fixed (advisory verification)` is a fourth status value absent from "🚫 Rejected joins ✅ Fixed and ⚠️ Partially Fixed" — refuted: Oracle scopes the parenthetical to the run summary ("the run summary marks the finding"), not to the `**Status:**` line whose grammar is fixed in Status vocabulary extension.
- [internal-consistency] "Skip remaining" on a non-final needs-decision page does not skip remaining, contradicting its label — refuted: Command changes states the advance rule explicitly and the derived claim ("never leave a needs-decision finding undisplayed") follows from it; label semantics are not a cross-section contradiction.
- [internal-consistency] Scope's "/fix ... behaviour unchanged" contradicts fix.md being listed as a status consumer to update — refuted: "behaviour unchanged" is scoped to the Phase 3 format delegation, and the status handling arrives via the separate scope bullet "New finding outcome 🚫 Rejected, propagated to both plugins".
- [internal-consistency] Needs-decision page capacity 3 versus "the checklist's usual 4" when the same parenthetical subtracts an appended item — refuted: the parenthetical derives 3 as 4-per-page minus the appended item and reserves "usual 4" for auto pages; deciding whether the existing checklist already appends that item is a repo fact, outside this lens.
- [internal-consistency] The pin's block hash excludes the loop-written `Decision:`/`Decision-pin:`/`Status:` lines but not the stage-2-corrected `Location:` line, so a corrected location would mismatch — refuted: the Location correction is written at decision time, together with the pin, so it cannot change underneath a matching pin.
- [internal-consistency] Purpose says `/fix-report` "asks for the decision from the report text alone" while Evidence reports the step never fired — refuted: Evidence explains the report as a step never reached (pagination, buried prose), and both statements hold simultaneously.
- [internal-consistency] Verification step 4's post-condition that finding 3's `**Location:**` is "rewritten to the analyst's verified `Target`" contradicts stage 3's "wherever it differs from the report" — refuted: the fixture is scripted, so it can be constructed with a differing Target.
- [internal-consistency] Stage 4's "The Step 4.1 / 4.1.5 write-and-verify procedure" names fix-all steps inside a flow shared with `/fix-report` — refuted: Ordering inside `/fix-report` states its decided findings are fixed in the same batch as the auto ones, so its existing write-back covers them and the parenthetical addresses only `/fix-all`.
- [contracts] The `**Status:** <icon> <text> (YYYY-MM-DD)[ — <reason>]` tail breaks `fix-all.md:361`'s whole-line verification — refuted: the tail is permitted only for `🚫 Rejected`, which stage 2 writes directly and which never passes through Step 4.1/4.1.5, and the spec already mandates prefix matching for consumers.
- [contracts] `qa` 2.5.2 → 2.6.0 should also be MAJOR — refuted: `qa` only gains read-and-preserve duties on a value it never emits; nothing it produces changes shape, so no reader of `qa` output is broken.
- [contracts] The analyst return block has no serialization (field markers, ordering), yet the orchestrator extracts five machine-consumed values from it — refuted: the table names each field, the consuming orchestrator is `decision-gate`, authored in this same change, and the block is rendered to a human rather than parsed by a third party; the one extraction that genuinely under-specifies its input is reported separately as the `Findings` command-citation finding.
- [contracts] Extraction "between the first ` — ` and the final ` [`" breaks on a resolution text containing ` [` — refuted: the bracketed bookkeeping field is written on every `**Decision:**` line (the provenance marker is not optional) and is always last, so the final ` [` is unambiguous.
- [contracts] The pin mixes hash algorithms — `sha256` for the block, git blob hashes for files — refuted: the spec names each explicitly and nothing in the design compares one against the other.
- [contracts] The `**Decision:**` line's position inside the block is unspecified, so it could be swallowed by `fix-auto`'s `Remediation` extraction — refuted: the example places it immediately after the `### [SEVERITY] ID: Title` heading, matching the established `**Status:**` recipe at `fix-all.md:351`, and `fix-auto.md:49` bounds Remediation at the appended `User decision:` line.
- [contracts] The status vocabulary needs a fourth value for the "nothing was verified" cases instead of writing no `**Status:**` line — refuted: the spec chooses that deliberately and gives the reason (`⚠️ Partially Fixed` is terminal at both Step 1.3 filters, so it would freeze the finding out of every future run).
- [contracts] `🚫 Rejected` must be added to `fix-auto`'s Phase 6 Status Definitions table for vocabulary parity — refuted: the spec states it is a report status and never a fixer verdict, one "no collector maps", and `reject` never dispatches.
- [contracts] Stage 0's "usable iff it parses as path:line or path:line-range" conflicts with `report-format/SKILL.md:99`'s `unknown:0` placeholder — refuted: the spec names `unknown:0` explicitly as location-less and routes it to the stage 0 prompt.
- [contracts] `/fix-all`'s Step 2.2.5 partition contract changes shape when the zero-auto path stops aborting — refuted: the partition itself (`fix-all.md:215-219`) is untouched; only the downstream edge-case branch moves, which the Command changes row states in full.
- [feasibility] decision-analyst's `Bash(git log:*)` grant form may be unsupported in an agent's `tools:` — refuted: `plugins/code-review/agents/feedback-analyzer.md:4` already ships `Bash(git:*)` in `tools:`, and the specifier spelling is the ordinary permission-rule form.
- [feasibility] The claim that `_uses_colon_specifier` reads `Bash(git log:*)` as `git` and warns on nothing — verified true by tracing `scripts/check_agent_frontmatter.py:433-443` (`tokens[0]` is `git`, no colon), so the spec's statement stands.
- [feasibility] `disallowedTools:` may not be a permitted agent frontmatter key and would fail CI — refuted: it is in `PERMITTED_KEYS`, `scripts/check_agent_frontmatter.py:46-50`, exactly as the spec cites.
- [feasibility] Adding a 26th agent might trip `EXPECTED_AGENT_FILES = 25` — refuted: `check_agent_frontmatter.py:550` warns only when the scanned count is *lower* than the constant.
- [feasibility] Fanning out 8 read-only analysts in a single turn may exceed a platform concurrency limit — refuted: `plugins/qa/commands/loop.md:885-899` already dispatches concurrent `Task` calls and blocks on `TaskOutput`, so the mechanism is demonstrated.
- [feasibility] `/qa:loop` may have no issue-level fix set, making "a rejected issue must not re-enter the fix set" unimplementable — refuted: `loop.md:603-616` Step 3a builds `fix_candidates` per QA-ID and already carries a per-issue pre-filter that a `🚫 Rejected` drop slots into.
- [feasibility] The orchestrator may lack a grant to re-run the analyst's cited evidence at the reject gate — refuted: the analyst's only shell evidence is git, and both `fix-report.md:2` and `fix-all.md:2` pre-approve `Bash(git:*)`; `Glob`/`Grep` citations are tool calls, not shell.
- [feasibility] The `decision-gate` skill may not be loadable from commands whose `allowed-tools` omits `Skill` — refuted: `CLAUDE.md` states a command's `allowed-tools` pre-approves prompts "without affecting availability", and `fix-auto.md:108` already invokes a skill by name.
- [feasibility] Stage 4's reuse of Step 4.1.5 could fail because `fix-all.md:361` verifies the whole line — refuted: the spec already mandates prefix matching for this exact reason under `Status vocabulary extension`.
- [feasibility] Evidence's "`Partially Fixed` appears in seven files across two plugins" may be miscounted — verified: the phrase occurs in `fix.md`, `fix-report.md`, `fix-all.md`, `fix-auto.md`, `qa/commands/loop.md`, `qa/skills/report-format/SKILL.md` and `docs/plugins/code-review.md`, matching the seven-consumer list.
- [feasibility] Evidence's "No live fixtures exist" may be stale — verified: neither `docs/reviews/` nor `docs/testing/reports/` exists in the tree, so the synthetic-fixture requirement is grounded.
- [feasibility] `**Decision-pin:**` is absent from stage 2's enumerated permitted writes — out of this lens (internal consistency), not a platform-delivery defect.
- [feasibility] `/fix-all` Step 5 re-running the Step 4.1/4.1.5 procedure after Step 4 closed its progress task may be impossible — refuted: TaskCreate/TaskUpdate impose no such ordering and the spec adds its own fifth progress row.
- [feasibility] The unconditional "Skip remaining" on the final needs-decision page has nowhere to advance when no `auto` page exists — a flow-definition gap for the ambiguity/consistency lenses, not a platform capability limit.

### Round 4 — 74 rejected

- [internal-consistency] Stage 4 case 2 writes ⚠️ Partially Fixed, a status the spec itself calls terminal at both Step 1.3 filters — refuted: the anti-freeze rule is explicitly scoped to "the last two" cases, and case 2 records a real partial edit.
- [internal-consistency] Stage 4 case 3 ("no pinned file changed observably") swallows case 4 ("no plan ran") — refuted: the spec states the try-order and its exact consequence ("a dispatch that errored where no plan existed records attempt N: failed").
- [internal-consistency] Scope's "/fix ... behaviour unchanged" versus /fix loading the new decision-gate skill — refuted: Components scopes /fix's load to "the `Alternatives:` render format only" and keeps its gate at (A / B / no).
- [internal-consistency] "The sweep offers five outcomes" versus stage 2's "ask with four options" — refuted: the spec distinguishes outcomes from AskUserQuestion options and names other… as the tool's built-in free-form answer, not a fifth option.
- [internal-consistency] Stage 0's "four-question ceiling" versus Decision outcomes' "four-option ceiling" — refuted: these are two distinct AskUserQuestion limits (questions per call, options per question), each used consistently where cited.
- [internal-consistency] Evidence's installed copy at 1.17.0 versus the header's "code-review 1.17.3" — refuted: the spec explicitly distinguishes the installed cache copy from the repo version and draws no conflicting claim from it.
- [internal-consistency] Stage 2 lists the corrected Location: among its permitted writes while Decision outcomes says reject writes only its Status: line — refuted: stage 2's list is permissive ("the only writes this stage permits"), and the per-outcome table supplies which of them each outcome actually makes.
- [internal-consistency] Residual risks' "the whole loop is deliberately unbounded" versus stage 1's batches of 8 and the two-attempt retirement — refuted: the section explicitly classes both as local bounds that do not bound the run.
- [internal-consistency] Purpose's "the fixers run as a single batch afterwards" versus /fix-all running its auto batch before the decision stage — refuted: Components' Ordering paragraph states "/fix-all differs by construction".
- [internal-consistency] Decision-pin's block hash is self-referential because the pin line lives in the block it hashes — refuted: the `**Decision-pin:**` line is itself on the exclusion list, and the report file's own hash is explicitly never pinned.
- [completeness] [completeness] Run-summary contents unspecified — refuted: each required element is fixed at the point it arises (Failed findings, `unverified` rejections, `verification: unavailable` naming the finding, `✅ Fixed (advisory verification)`), and `/fix-all`'s summary-block placement is stated in `Command changes`.
- [completeness] [completeness] No dispatch/time/token budget bounds the loop — refuted: `Residual risks` discloses it explicitly as a deliberate choice against loop-engineering bar item 6, so it is not a gap.
- [completeness] [completeness] No CI guard for the three-value status vocabulary — refuted: named in `Scope` → Out of scope and carried again under `Residual risks`.
- [completeness] [completeness] Analyst is not required to load `finding-falsification` — refuted: `Residual risks` states the non-requirement explicitly.
- [completeness] [completeness] Fixture report has no repository path — refuted: implementation-plan detail; `Verification` fixes the fixture's contents, the scripted answers and every post-condition.
- [completeness] [completeness] Batch size of 8 is unjustified — refuted: a stated constant with an announced pre-flight count; no design question follows from the number.
- [completeness] [completeness] Placement of `**Decision:**` inside the finding block is unspecified — refuted: the canonical DOC-004 example shows it directly under the heading, and the block hash excludes the loop-written lines, so placement is not load-bearing.
- [completeness] [completeness] `/fix-report` gains no progress-task row — refuted: only `/fix-all` is described as carrying a progress-task table, and rows are command-file detail rather than a design decision.
- [completeness] [completeness] `/fix` may need `Bash(shasum:*)` too — refuted: `Scope` limits `/fix` to the `Alternatives:` render format, so it never writes a `Decision-pin:` line and needs no new grant.
- [completeness] [completeness] Behaviour when `AskUserQuestion` is unavailable is undefined — refuted: `Decision outcomes` specifies immediate abort, no dispatch, no further `**Decision:**` line, prior decisions retained and replayed, undecided count reported.
- [completeness] [completeness] A reason string containing ` — ` would break `**Status:** … — <reason>` parsing — refuted: `Status vocabulary extension` requires consumers to match a status value by prefix rather than whole-line equality, and the tail is the line's last field.
- [completeness] [completeness] An em dash or ` [` inside a resolution would break replay extraction — refuted: `Decision record` pins the extraction to the first ` — ` and the final ` [`, and mandates a `<label>` on every written line.
- [completeness] [completeness] Nothing says whether `/fix` gets the five-outcome sweep — refuted: `Scope` states the sweep belongs to `/fix-report` and `/fix-all` alone and that `/fix` keeps its `(A / B / no)` gate.
- [completeness] [completeness] Skill-versus-command choice for `decision-gate` is unargued — refuted: `Components` gives the reason (adds no entry point) and names three in-plugin precedents.
- [feasibility] Parallel fan-out of up to 8 `decision-analyst` subagents "dispatched in a single turn" may exceed the platform's concurrency — refuted by prior art in the repo: `plugins/web-auditor/agents/web-auditor.md:185` launches up to 7 scanning agents "in parallel, in a single turn", and `plugins/superutils/commands/spec-review.md:129` dispatches one Task per lens in parallel.
- [feasibility] `disallowedTools:` is not a supported subagent frontmatter key — refuted by `scripts/check_agent_frontmatter.py:46-50`, whose `PERMITTED_KEYS` includes `disallowedTools` and is sourced from the sub-agents frontmatter docs verified against v2.1.220.
- [feasibility] `Bash(shasum:*)` cannot feed a block excerpt to `shasum`'s stdin without an unpre-approved `echo`/`printf` — refuted: `shasum -a 256 <<'EOF' … EOF` begins with `shasum`, so the prefix rule `Bash(shasum:*)` covers the whole command.
- [feasibility] `git hash-object` needs a new grant in both commands — refuted: `fix-report.md:2` and `fix-all.md:2` already carry `Bash(git:*)`, exactly as the spec claims.
- [feasibility] The orchestrator cannot use `AskUserQuestion` for the sweep because subagents are stripped of it — refuted: the sweep runs in the command, not a subagent, and both commands already declare and use `AskUserQuestion` (`fix-all.md:279`, `fix-report.md:129`).
- [feasibility] `fix-auto` does not actually honour a trailing `User decision:` line, so stage 3's dispatch contract is unimplemented — refuted at `plugins/code-review/agents/fix-auto.md:50-52`, which extracts the field and makes it authoritative over the Remediation.
- [feasibility] Adding `decision-analyst.md` breaks `check_agent_frontmatter.py`'s `EXPECTED_AGENT_FILES = 25` guard — refuted at `:550`, which warns only when the scanned count is *lower* than 25 and never errors.
- [feasibility] The four-option `AskUserQuestion` ceiling and the `other…` free-form answer are asserted platform properties with no repo evidence — refuted as in-lens: `fix-report.md:129` and `:182` already build the checklist and the decision batch around a 4-option / 4-question ceiling, so the ceiling is established behaviour in this codebase.
- [feasibility] "This change guarantees a page always follows one" is false when every unfixed finding is `needs-decision`, since the final needs-decision page is then the last page and `fix-report.md:158` appends "Skip remaining" only when more pages follow — a real defect but pagination arithmetic, not platform capability; internal-consistency's mandate, not feasibility's.
- [feasibility] Within one run, an earlier `fix-auto` editing a shared file (`README.md`, which `Evidence` calls the common case) makes every later decision's pre-dispatch pin check mismatch, collapsing the promised "one uninterrupted sweep" into mid-dispatch re-asks — the platform can execute this exactly as written; the defect is design logic, so it belongs to internal-consistency.
- [feasibility] `fix-auto`'s new Phase 1 abort on a `🚫 Rejected` block carries none of the three verdicts the callers branch on, and neither `fix-report.md:210` nor `fix-all.md:321` is listed for a matching change in `Command changes` — a gap in the change list, not a platform limit; completeness's mandate.
- [ambiguity-testability] Stage 4 case 1 vs case 3 for a passing plan with no observable pinned-file change — refuted by "Four cases, tried in this order", which makes the pass win deterministically.
- [ambiguity-testability] Stage 1 "Dispatched in a single turn" vs "successive announced batches" for N>8 — refuted: successive batches with a per-batch announcement leave only the per-batch reading coherent.
- [ambiguity-testability] Two-attempt retirement vs "records `attempt N: interrupted, unverified` … before any new dispatch" when that entry is the second — refuted: the replay check places "the retry limit" at run entry, so an entry recorded mid-run does not gate that run's dispatch.
- [ambiguity-testability] Whether stage 0's corrected `Location:` is written when the user picks `skip` or `reject` — refuted: `Decision outcomes` states `skip` "writes nothing at all" and `reject` "writes only its `**Status:**` line".
- [ambiguity-testability] Unbounded re-asking when an `other…` answer "cannot be restated self-containedly" or a withheld `reject` "returns to the sweep" — refuted: `Residual risks` explicitly declares the loop unbounded and the sweep a human gate, so this is disclosed, not ambiguous.
- [ambiguity-testability] `<who>` in the `**Decision:**` bracketed field is never enumerated — refuted: the orchestrator "never supplies a decision on the user's behalf", and the bracketed field "is never dispatched", so no behavior turns on its value.
- [ambiguity-testability] The prefix-matching rule in `Status vocabulary extension` names no consumer set and no verification step checks it landed at `fix-all.md:361` — refuted: the ` — <reason>` tail is "permitted only for `🚫 Rejected`", which never dispatches, so stage 4's write-and-verify can never encounter a line carrying one; the places where prefix matching is observable (the Step 1.3 filters) are listed and walked by Verification step 5.
- [ambiguity-testability] Extraction of the dispatchable text "between the first ` — ` and the final ` [`" could be broken by a resolution containing " [" — refuted: the bracketed field is terminal and its stated grammar contains no " [", so the final occurrence is always the field opener.
- [ambiguity-testability] "The run summary" is never formally defined although Failed targets, unverified rejections and "verification: unavailable" are all carried in it — refuted: `Components` binds it to `/fix-all` Step 5's "decision-stage summary block" and to `/fix-report`'s existing run summary.
- [ambiguity-testability] The block hash's serialization is unspecified (trailing newline, blank lines left by removed loop-written lines) — refuted: the same procedure computes and compares the hash, and `shasum -a 256` over the block excerpt is named, so the value is deterministic within any one implementation.
- [ambiguity-testability] The `Findings` command-plus-output requirement has no stated enforcement — refuted: `Findings` is advisory display material, and the only place a missing invocation changes behavior (the `Rejection candidate`) states its own consequence: "its finding falls to the no-candidate path".
- [ambiguity-testability] Stage 4's "no observable change is no edit" mislabels a correct no-op fix as `attempt N: failed` — refuted: the spec states the tree-read rule as a deliberate choice with the fixer's verdict explicitly demoted to advisory.
- [doctrine-compliance] Item 1 unmet — refuted: `Oracle` names a deciding signal per outcome and closes with "What none of these oracles can check", enumerating three concrete blind spots.
- [doctrine-compliance] Item 8 unmet — refuted: `Residual risks` enumerates six named risks, including both version-skew cases and the unbounded loop.
- [doctrine-compliance] Item 9 unmet (a suspect finding auto-fixed against correct source) — refuted: the `reject` outcome, the analyst's `Rejection candidate` with its evidence re-run at the gate, and a human deciding every dispatch mean the assertion is never auto-trusted.
- [doctrine-compliance] Item 2 anti-pattern "self-graded fix loop" via `fix-auto` Phase 5's own three-iteration verify loop — refuted: the spec demotes that verdict to "advisory input, not the deciding signal" and grades from orchestrator-run raw output.
- [doctrine-compliance] Item 10 unmet because state is inline rather than in a sidecar — refuted: the bar requires durable on-disk state, inline report lines are on disk, and `Decision record` justifies the choice against `code-review` having no sidecar concept.
- [doctrine-compliance] Item 10 "a re-dispatch re-applies a landed correction" — refuted: "The pin is compared immediately before dispatch; on mismatch the decision is not replayed", so a landed edit mismatches its own pin and the blind re-apply is blocked.
- [doctrine-compliance] Item 4 unmet for lack of a TTY probe — refuted: the design offers no headless path at all, so the opt-in clause's trigger never fires, and it fails closed on the gate mechanism itself ("If `AskUserQuestion` is unavailable or errors, the decision stage aborts immediately").
- [doctrine-compliance] Item 3 green→red flip when stage 4's fourth case withholds `✅ Fixed` — refuted: withholding a status for a target the verifier structurally cannot reach is the bar's own anti-pattern avoided, it is disclosed as "verification: unavailable", and `dispatched, unverified` is kept distinct from `failed`.
- [doctrine-compliance] Item 2 unmet because stage 3.5's raw output is logged but never persisted — refuted: no bar item requires persisting the log itself; the durable defect is the missing confidence qualifier on the status, reported separately.
- [doctrine-compliance] Conditional items 9/10/11 are never marked N/A with a justification — refuted: all three triggers fire (auto-correction, persisted state, workspace mutation), so no N/A justification is owed for any of them.
- [doctrine-compliance] Item 11 "changes not left uncommitted" — refuted: nothing in the design commits, `Oracle` records the fix landing as an uncommitted diff, and `plugins/code-review/agents/fix-auto.md:346` ends "Changes remain uncommitted for your control".
- [doctrine-compliance] Item 5 unmet for ambiguous input (a missing `Location:`) — refuted: stage 0 asks before fan-out, re-asks once, and handles a second failure "exactly as a declined target", reusing `fix-report` Step 2.4's existing behaviour.
- [doctrine-compliance] Item 7 anti-pattern "budget-exhausted reads as passed" — refuted: there is no budget to exhaust, and every no-status path is reported separately ("Failed attempts are reported under their own heading, never folded into the fixed set").
- [doctrine-compliance] Item 2 "the verifier is handed the exact target it grades" via the orchestrator deriving `other…` checks after the decision — refuted: the bar bars the *actor* from authoring the oracle, and the actor here is `fix-auto`, which authors nothing.
- [doctrine-compliance] Item 11 unmet because stages 2 and 4 rewrite the report in place with no snapshot — refuted: the report edits are themselves uncommitted diffs, and `Decision record` explains why a whole-file pin would be both self-referential and always-mismatched.
- [contracts] `**Decision:**` payload extraction ambiguous when the resolution text contains ' [' — refuted: the bracketed bookkeeping field is written at decision time and is always last, so 'the final ` [`' is unambiguous.
- [contracts] An em dash inside the resolution text breaks the first-` — ` delimiter — refuted: `<label>` is pinned to exactly A, B or other and 'every written line carries one', so the first ` — ` is always the grammar's delimiter.
- [contracts] `**Verification-plan:** <check>; <check>` collides with `;` as a shell statement separator — refuted: checks are single commands by construction ('read-only inspection plus the project's declared test and build commands'), and the same `; ` convention is used consistently for the attempt entries; no cited check embeds a `;`.
- [contracts] A `<reason>` prefilled from the analyst's `Rejection candidate` could be multi-line and break the one-line Status grammar — refuted: the written form is stated as a line, and the no-candidate path stipulates a one-line reason.
- [contracts] The status vocabulary may have consumers beyond the seven listed — refuted: `Partially Fixed` occurs in exactly four `plugins/code-review` files plus `report-format/SKILL.md` and `loop.md`, matching six of the seven entries, and Verification step 5 keeps a `plugins/` + `docs/` grep as a supplementary sweep.
- [contracts] `**Decision-pin:**` is ambiguous about whether `<path>` keeps the `:line` of a `path:line` token — refuted: hashes are produced by `git hash-object` over a file, which makes the path-only reading the only implementable one.
- [contracts] A `/qa:loop` reuse/adopt re-render invalidates carried-over pins — refuted: a block that re-renders differently mismatching its pin is the pin behaving as designed (fail-closed re-analysis and re-ask).
- [contracts] `git hash-object` needs a new Bash grant on both commands — refuted: `fix-report.md:2` and `fix-all.md:2` already carry `Bash(git:*)`, exactly as `Delivery` claims.
- [contracts] The `User decision:` dispatch contract needs extending for the new outcomes — refuted: `fix-auto.md:49-52` already parses a trailing `User decision:` line and treats it as authoritative over the Remediation, so no dispatch-side change is required.
- [contracts] `fix-auto`'s Phase 6 verdict vocabulary needs a `🚫 Rejected` value — refuted: the Phase 1 abort returns before Phase 6 and maps onto the callers' existing 'subagent errored → Failed' branch (`fix-report.md:210`, `fix-all.md:321`).
- [contracts] The new lines written under the heading break Step 4.1's insert recipe or Step 4.1.5's 'next non-blank line' verify — refuted: the recipe anchors on the heading line alone (`old_string = "<heading>\n"`), so the Status line still lands directly beneath the heading.
- [contracts] `Drift-class` is not part of the shared QA finding schema, so the `Alternatives` derivation is undefined for QA findings — refuted: the contract routes an absent or unrecognised value to the same fallback and cites `fix-report.md:139`'s `[needs-decision: —]` render as the headline case.

### Round 5 — 70 rejected

- [completeness] `reject` writing a `**Verification:** unverified` line versus "nothing beyond the `— <reason>` tail is persisted when the `🚫 Rejected` status is written" — a contradiction between two sections, internal-consistency's mandate, not a missing decision.
- [completeness] Dispatch-copy rule's strip list omits `**Decision-retired:**` and `**Verification:**`, which a retried block carries — refuted by the governing clause "the copy handed to fix-auto carries the reviewer-authored fields only", which strips every loop-written line regardless of the enumeration.
- [completeness] Stage 4's expected set is undefined for a finding recorded "without a `**Decision-pin:**` line" where neither hasher exists — refuted: the set is defined independently of the pin line as "that `Target` plus every `path[:line]` token appearing in the resolution text", and stage 4 takes its own before/after hashes.
- [completeness] A `**Decision-pin:**` mismatch arising during the second pass has no stated handling — refuted: the set-aside rule generalises recursively and "each fresh pin is taken against the tree the dispatch it belongs to will actually see" already covers a set-aside within the second pass.
- [completeness] Timing of the two-attempt retirement's re-open (same run or next) is unstated — refuted by `Purpose`: "The sweep is uninterrupted with exactly one documented exception", which arbitrates the re-analysis and re-sweep to the next run.
- [completeness] `**Verification-plan:** <check>; <check>` gives no escape for a check whose text contains `;` — refuted: the execution boundary confines checks to single inspection commands, declared test/build commands and tool calls, so a compound check is authored as two checks.
- [completeness] The run summary (Failed findings, `unverified` rejections, out-of-scope writes, `verification: unavailable`, `stalled — no progress`, unpinned findings) has no specified structure — refuted: its required contents are enumerated across the spec and its rendering is implementation-plan detail.
- [completeness] "Analyst fails or returns an unusable block" never defines unusable — refuted: the return contract states "Every field is required unless marked optional" and lists them, which is the usability test.
- [completeness] A re-opened finding's fresh analyst run is not shown the `**Decision-retired:**` history, so it may re-propose a resolution already tried — refuted: the spec assigns that duty to the sweep ("The sweep renders the retired lines with the fresh proposal"), and analyst-side history is an enhancement, not a missing decision.
- [completeness] `decision-gate` SKILL.md frontmatter is unspecified — refuted: the skill is loaded by commands whose grants the spec updates explicitly under `Delivery`, and skill `allowed-tools:` is pre-approval, not capability.
- [completeness] A `path:line` the user supplies at stage 0 is lost when that finding is then skipped, forcing a re-ask next run — refuted: "`skip` writes nothing at all — that is what makes the finding reappear next run" is a stated design property, not an omission.
- [completeness] Whether an unpinned finding (no hasher) is still dispatched in the run that decided it — refuted: the pin "is compared immediately before dispatch", so with no pin there is nothing to compare and the decision proceeds; only replay on a later run is excluded, which the spec states.
- [internal-consistency] "The sweep offers five outcomes per finding" vs the three-option calls — refuted: `Decision outcomes` states the A-alone and withheld-reject reductions two sentences later, in the same section.
- [internal-consistency] Purpose's "uninterrupted sweep" vs `Decision record`'s pin-mismatch second pass — refuted: Purpose names that exception explicitly and describes the same set-aside/second-pass sequencing.
- [internal-consistency] Stage 4's "the gate writes back nothing of its own" in /fix-report vs stages 2 and 3 writing to the report — refuted: stage 4 is scoped to the Status write-back procedure, a different write than the decision record lines.
- [internal-consistency] Skill section's "in /fix-report it runs stages 0-2" vs stage 3.5 applying to decided findings there — refuted: the `commands/fix-report.md` row assigns Step 3 the dispatch and stage 3.5 the decided findings, with the skill supplying the doctrine.
- [internal-consistency] Return contract marks `Verification Plan` required, yet stage 4's fourth case contemplates "a finding for which the analyst supplied none" — refuted: the same contract's mechanical rejection test converts an unacceptable plan into "no plan for that alternative".
- [internal-consistency] Degraded path takes A and B "from the finding's Remediation" vs stage 3's full, self-contained resolution requirement — refuted: `Decision record`'s deictic fallback explicitly covers a resolution that slipped through non-self-contained.
- [internal-consistency] Analyst grant covers four read-only git subcommands while the execution boundary names five (adds `git status`) — refuted: the boundary is the orchestrator's, deliberately broader, and the return contract separately requires citations to stay inside the analyst's grant.
- [internal-consistency] `**Verification:**` value left undefined for stage 4's third case (errored dispatch) — refuted: the enum's own definitions (`hard` where checks produced observable output, `unavailable` where no plan ran) cover it without conflict.
- [internal-consistency] `Decision-pin:`'s "the pinned files follow in resolution-text order, the `Target` first" vs the degraded path where no analyst `Target` exists — refuted: stage 2 equates the corrected Location with the verified Target, so no stated rule conflicts.
- [internal-consistency] `Verification` step 4's finding-3 post-condition demands "a status decided by stage 3.5's logged raw output" though two stage 4 cases write no status — refuted as a consistency defect: the fixture answers are scripted, and this is an acceptance-criterion strictness question rather than a contradiction between sections.
- [internal-consistency] `**Verification:** unavailable — <checks run>` naming checks in the case where no checks ran — refuted: wording only, outside this lens's mandate.
- [internal-consistency] Unbalanced closing parenthesis in stage 4's `/fix-all` parenthetical ("...owns both the write-back and their progress rows)") — refuted: formatting, outside this lens's mandate.
- [ambiguity-testability] Stage 4 case order when a dispatch errored and no plan existed — refuted by the stated try-order plus "This case is tried before the fourth, so a dispatch that errored where no plan existed records attempt N: failed and not attempt N: dispatched, unverified".
- [ambiguity-testability] Diagram's "a soft LLM re-read of prose … which is runnable, lands in stage 4's first case" read as an automatic pass — refuted by stage 4's first case ("A soft check … passes like any other") and by Oracle ("its pass is stage 4's first case").
- [ambiguity-testability] Stage 4's expected set when no `**Decision-pin:**` line was written because neither hasher exists — the literal reading is determinate (an empty pinned set), so this is a missing decision rather than a dual reading, and out of this lens.
- [ambiguity-testability] Which value the corrected `**Location:**` carries when stage 0 supplied a path and the analyst returns a different verified `Target` — refuted by stage 0's explicit "A validated path:line is carried into the analyst dispatch and, when that finding's decision is written in stage 2, into the finding's Location: field in the source report itself".
- [ambiguity-testability] "Analyst fails or returns an unusable block" leaves "unusable" undefined — refuted by the return contract's "Every field is required unless marked optional" plus the per-field degradation rules (a tool name alone is no citation; a rejected plan is treated as no plan).
- [ambiguity-testability] Whether >8 findings dispatch in one turn or successive turns, against Verification step 4's "all analyst dispatches issued in a single turn" — "Dispatched in a single turn, batches of at most 8" reads per batch, and the fixture has three findings, so one batch.
- [ambiguity-testability] Whether the plan-acceptance test is executed against the current (unedited) tree or judged by reading — the execution boundary sanctions execution only at stage 2's evidence re-run and at stage 3.5, so a competent implementer judges rather than runs candidate checks.
- [ambiguity-testability] Tokenisation of "every `path[:line]` token appearing in the resolution text" for the pinned file set — the `Alternatives` contract requires each alternative to name every file and line it touches and nothing else, and the deictic fallback is stated explicitly.
- [ambiguity-testability] Stage 4's "a content hash of every path it lists" names no hasher while the pin's mechanisms are named — any hash function serves, since the before and after values are only ever compared with each other.
- [ambiguity-testability] Extraction of the dispatchable text when the resolution contains an em dash or a ` [` — refuted by "the first ` — ` is always the grammar's delimiter" and "the text between the first ` — ` and the final ` [`".
- [feasibility] Neither `/fix-report`, `/fix-all` nor `/fix` lists `Skill` in `allowed-tools`, yet all three must load `decision-gate` — refuted: `fix.md:221` and `review.md:27` already invoke skills with the same frontmatter, and `CLAUDE.md` declares command `allowed-tools` a permission pre-approval that does not affect availability.
- [feasibility] `disallowedTools:` may not be a supported agent key — refuted: it is in `PERMITTED_KEYS` at `scripts/check_agent_frontmatter.py:46-50`, sourced from the sub-agents frontmatter docs, and is one of the two `TOOL_KEYS` the checker validates.
- [feasibility] Stage 1's "dispatched in a single turn" may not actually run in parallel, since the repo's only fan-out precedents (`review.md:67,79,93`, `loop.md`) use `run_in_background: true` plus `TaskOutput`, which neither command grants — refuted: parallel foreground tool calls in one assistant message are a platform capability, and the spec never mandates the background form.
- [feasibility] The sweep and stage 0/3.5 asks might be unreachable because `AskUserQuestion` is stripped from subagents (`ALWAYS_STRIPPED`, `check_agent_frontmatter.py:54-57`) — refuted: every ask in the design is orchestrator-side, and `fix-report.md:2` / `fix-all.md:2` both carry `AskUserQuestion`.
- [feasibility] The four-option `[A] [B] [skip] [reject]` render and the batches-of-4 stage 0 ask may exceed the tool's ceiling — refuted: `fix-report.md:182` already batches "up to 4 such issues per call, one question each", and the free-form answer is the tool's own, not a fifth option.
- [feasibility] `shasum -a 256` over an in-context excerpt is not reachable under a prefix-anchored `Bash(shasum:*)` grant — refuted: a here-doc invocation (`shasum -a 256 <<'EOF' … EOF`) begins with `shasum`, so a route inside the declared grant exists; only the byte-exact re-derivation problem survives, and it is reported separately.
- [feasibility] Stage 4 hashes "every path" `git status --porcelain` lists, but `git hash-object` errors on a deleted path — refuted: the spec already treats disappearance as an observable change and records a missing path as `absent` in the pin, so the convention is stated in the document.
- [feasibility] `Bash(git log:*)` may be inert and leave the analyst holding base `Bash` — not reportable: the spec flags it explicitly as an open question (`Components`), probes it in Verification step 6 and carries it in `Residual risks`.
- [feasibility] Stage 3's claim that a dispatched `Location: —` makes the fixer "stop to ask from inside a subagent" overstates what `fix-auto` can do, since `AskUserQuestion` is stripped from every subagent — refuted: `fix-auto.md:42,54-60` does treat Location as required, and the motivating outcome (a stalled dispatch) holds either way.
- [feasibility] `/fix`'s prose gate `(A / B / no)` violates "collected with `AskUserQuestion` and with nothing else" — refuted: that rule is scoped to the decision stage, and the spec limits `/fix` to the rendering contract, keeping the five-outcome sweep in `/fix-report` and `/fix-all` alone.
- [feasibility] The `**Dispatch:**` marker could be swallowed by `fix-auto`'s Remediation capture (`fix-auto.md:49`) — refuted: the dispatch-copy rule strips it from the dispatched copy, and the loop-written lines sit under the heading, ahead of Remediation.
- [feasibility] Evidence and citation audit found no defect: `fix-auto.md:52`, `fix.md:238/:271/:285`, `fix-all.md:213/:347/:361`, `fix-report.md:129/:139/:158-161/:180/:182`, `loop.md:902-907/:917`, `report-format/SKILL.md:233`, `check_agent_frontmatter.py:46-50/:78-80/:433-443`, `feedback-analyzer.md:4` as the tree's only agent-level `Bash` specifier, `check-prefix-sync.sh` covering Category→Prefix only, `Partially Fixed` in exactly seven plugin/doc files, absent `docs/reviews/` and `docs/testing/reports/`, versions 1.17.3 / 2.5.2, the three precedent doctrine skills, and the installed 1.17.0 cache copy all check out as written.
- [contracts] Step 1.3 filters need prefix matching for the new reason tail — refuted: `fix-report.md:86-89` and `fix-all.md:153-156` already test whether the block *contains* `**Status:** ✅ Fixed`, a containment test that tolerates a tail, so the spec's prefix rule matches what is there.
- [contracts] `**Verification:** unavailable — <checks run>` leaves the tail undefined when no plan ran — refuted: both branches of the fourth case are nameable (a refused or unrunnable check has command text; an absent plan renders as none), so the divergence is cosmetic.
- [contracts] `**Decision-pin:** block=<sha> | <path>=<hash>` collides with a path containing ` | ` or `=` — refuted: pinned paths derive from `path[:line]` tokens in a resolution text and from the analyst's `Target`, and the field is written and read only by this loop; no producible path in this format carries the delimiters.
- [contracts] The `**Decision:**` payload rule breaks on a resolution text containing ` [` — refuted: the rule dispatches "the text between the first ` — ` and the final ` [`", and the bracketed bookkeeping field is always present and always last, so the final occurrence is unambiguous.
- [contracts] The stated version baselines are stale — refuted: `.claude-plugin/marketplace.json` records `code-review` 1.17.3 and `qa` 2.5.2, exactly the baselines `Delivery` bumps from.
- [contracts] `qa` 2.5.2 → 2.6.0 understates the change, since the shared report schema gains six fields and a second `**Location:**` form — refuted: the additions are optional fields and a superset written form, existing readers keep parsing, and MINOR is what `CLAUDE.local.md` reserves for new behaviour on a new input value.
- [contracts] The extended `**Location:**` form breaks `fix-auto.md:49`'s required `**Location:** \`path:line\`` pattern — refuted: the spec states the one-line read rule (first backticked token, ignore any trailing parenthetical) and names `fix-auto.md`'s Phase 1 among the consumers that must adopt it.
- [contracts] The `tool: Grep pattern=… path=…` citation form omits parameters (`output_mode`, `head_limit`, `-n`) needed to reproduce a call exactly — refuted: the gate tests substring containment of the quoted evidence rather than output equality, so an under-specified re-run that returns a superset still supports the candidate; only the empty-result case genuinely breaks, and that is reported separately.
- [contracts] The `Alternatives` contract has no machine-checkable form for 'full, self-contained' — refuted: the spec fixes the requirement concretely (names every file and line, refers back to neither the Remediation nor the other alternative) and the pin's deictic fallback is stated to cover a violation rather than an expected form.
- [contracts] `report-format/SKILL.md` must also register `**Fix-policy:**` and `**Drift-class:**`, which the analyst contract keys off — refuted: `Scope` explicitly defers classification ("Changes to how findings are *classified* as `needs-decision`… are unchanged"), so those fields are out of scope.
- [contracts] The analyst's two-word `Bash(git log:*)` grant may resolve to base `Bash`, widening the read-only contract — refuted as a contracts finding: the spec states the uncertainty plainly, probes it in Verification step 6 and carries the inert-grant case in `Residual risks`.
- [doctrine-compliance] Item 1 unmet — refuted: `Oracle` names the deciding signal per outcome (raw stage-3.5 output, tree observation, re-run cited evidence) and closes with the explicit blind-spot list ("that the applied edit matches what the user meant… that a rejected finding was actually wrong").
- [doctrine-compliance] Item 2 unmet — refuted: the orchestrator, not the fixer, executes the plan and logs raw output, fix-auto's Phase 6 verdict is explicitly advisory, stage 4 reads the tree (`git status --porcelain` plus per-path content hash, before and after) rather than narration, and the dispatch-copy rule strips `**Verification-plan:**` so the actor can neither author nor see the oracle.
- [doctrine-compliance] Item 2 soft-oracle sub-clause ("never hand the verifier the exact target it grades") — refuted: the soft LLM re-read is judged by the orchestrator that holds the decision text, but the taxonomy's actual requirements are met — the soft verdict self-labels advisory in a persisted `**Verification:** advisory` line and "✅ Fixed (advisory verification)", the plan is authored per-alternative before the edit exists, the anti-tautology test rejects a plan that "would fail only because the edit's own text is absent", and re-verification is independent of the corrector.
- [doctrine-compliance] Item 3 unmet for the zero-coverage case (no plan at all → no `**Status:**` line, strike, finding returns) — refuted: with no oracle there is no green to flip, and reporting a pass there would be the bar's own anti-pattern ("reporting PASS for a target the verifier structurally cannot reach"); the conforming reference does the same (`loop.md:1066` "Tool unavailable → SKIP / cannot confirm (never counted as fixed)").
- [doctrine-compliance] Item 4 unmet (no TTY probe) — refuted: there is no headless opt-in at all, the sweep is an unconditional human gate collected "with `AskUserQuestion` and with nothing else: it is the only construct whose answer provably originates with the user", and unavailability aborts the decision stage before any dispatch; attempting the gate and observing its failure is a direct probe, not a heuristic reading of interactivity, and the stage-3.5 variant refuses to run the command rather than running it unapproved.
- [doctrine-compliance] Item 5 unmet (bespoke prose execution boundary instead of a deterministic guard) — refuted: the boundary is deny > ask > allow, the same ordering as the cited exemplar `block-git-push.sh`, ambiguous input asks or aborts throughout (stage 0's re-ask-once, pin mismatch → re-analyse and re-ask, no hasher → no pin and no replay), and the bar's own reference implementation states its environment and mutation guards as prose in a command file, so a prose guard is the conforming standard, not a reinvention.
- [doctrine-compliance] Item 7 unmet (no oscillation stop) — refuted: two recorded attempts retire a decision, a second retirement is not re-analysed at all but reported under a `stalled — no progress` heading naming both retired resolutions with `reject` offered, and "Failed attempts are reported under their own heading, never folded into the fixed set".
- [doctrine-compliance] Item 9 unmet (analyst not required to load `finding-falsification`) — refuted: no `needs-decision` finding is ever auto-fixed (a human decides each), and the `Rejection candidate` path plus the orchestrator's verbatim re-run of the cited evidence is exactly the provenance guard for "the failure may be the assertion, not the target"; the residual list already flags analyst quality.
- [doctrine-compliance] Item 10 unmet — refuted: decision, verification plan, pin, dispatch marker and verification strength all persist as lines in the report (explicitly because "the run summary does not survive the session"), the pin hashes the finding block and each pinned file to detect mid-run tampering, and a landed-but-unverified fix mismatches its own pin on resume, so the replay path re-analyses instead of re-applying the correction.
- [doctrine-compliance] Item 10, user-supplied `path:line` from stage 0 held only in conversation until stage 2 writes a decision — refuted: such a finding has no decision yet, so the spec's stated resume model re-analyses and re-sweeps it anyway; the loss costs one repeated question and no loop-critical result.
- [doctrine-compliance] Item 11 unmet (fix-auto's writes are unscoped) — refuted: the before/after `git status --porcelain` plus per-path content hash is the same mechanism the bar cites as conforming (`fix_touched_files = post − pre_loop_dirty`), fixes land as uncommitted diffs the user can revert, and the loop's own report writes preserve prior content (`(was: …)` on `Location:`, retire-by-rewrite for superseded decisions, the `/qa:loop` and `/fix` Phase 8 duties protecting an existing `**Status:**` line); the residual weakness is the disclosure gap, reported under item 8 instead.
- [doctrine-compliance] Item 2 for the `auto` half of `/fix-report`'s batch, whose status still comes from "fix-auto's own verdict is collected" — refuted: that is unchanged pre-existing 1.17.3 behaviour the spec explicitly preserves, not a property of the decision loop this spec designs, whose statuses are all decided by orchestrator-run raw output.
- [doctrine-compliance] Item 6 — conceded in `Residual risks` in unchanged terms ("loop-engineering bar item 6 is not met… no ceiling of any kind is added"), so not re-reported per the standing decision.

### Round 6 — 75 rejected

- [completeness] No rule for what the `decision-analyst` dispatch copy contains (e.g. whether `**Decision-retired:**` lines travel) — refuted: "Receives exactly one `needs-decision` finding block" reads as the block as it stands on disk, the strip list is scoped by its own rationale to fixers being graded, and the sweep separately "renders the retired lines with the fresh proposal".
- [completeness] The sweep's ordering across findings is unspecified — refuted: report order is the only order the spec ever uses (checklist pages, `needs_decision` list), and ordering has no load-bearing consequence since every decision precedes every dispatch.
- [completeness] Whether stage 2 rewrites `**Location:**` for a rejected finding is unclear — refuted: the permitted-writes list includes the corrected `Location:` line, and a rejected finding is never dispatched, so the address is not load-bearing for it.
- [completeness] No summary surface for the decision stage in `/fix-all` — refuted: the `Command changes` row states Step 5 "append[s] a decision-stage summary block after the one Step 4.2 printed", and the zero-auto path is covered too.
- [completeness] "Analyst fails or returns an unusable block" gives no test for unusable — refuted: both triggers route to one fully specified degrade path (raw block, five outcomes, A/B from the Remediation, "code analysis unavailable" note, reject gated on a stated reason), so the classification changes no downstream behaviour.
- [completeness] No CI guard for the status vocabulary and no bound on the analyst fan-out — refuted: both are explicitly out of scope / recorded under `Residual risks`, and the unbounded fan-out is a recorded user decision.
- [completeness] The `other…` restatement confirmation call's option set is unstated — refuted: `Decision outcomes` states the restatement "shows the restatement for confirmation" and that an unrestatable answer "returns to the sweep", which fixes both branches; the confirm/reject option pair is derivable.
- [completeness] No termination rule for a third or later pin-mismatch pass — folded into the reported `Decision-pin` finding rather than reported separately.
- [completeness] `decision-analyst`'s `description`, model and prompt body are unspecified — refuted: implementation-plan detail; the spec fixes the frontmatter keys, the grant set and the full return contract.
- [completeness] The synthetic fixture's location and file contents are unspecified — refuted: `Verification` step 4 fixes its composition and every post-condition; the rest is plan detail.
- [completeness] The `decision-gate` skill declares no `allowed-tools:` for the hashing and re-run commands — refuted: `Delivery` puts `Bash(shasum:*)`, `Bash(sha256sum:*)`, `Bash(sed:*)` and `Bash(grep:*)` on the two commands' frontmatter, and the skill runs in the invoking command's context.
- [completeness] How an unpinned decision is kept out of the replay check is unstated — refuted: the entry replay check is explicitly "subject to the pin check", and `Decision record` states an unpinned decision "is never replayed on a later run".
- [ambiguity-testability] Stage 1's "Dispatched in a single turn" against "successive announced batches" of 8 — refuted: 'successive' makes one batch per turn the only reading, and Verification step 4's fixture has three analyst dispatches, so its 'single turn' post-condition is consistent.
- [ambiguity-testability] Stage 4's cases readable as unordered where a plan passes but no pinned file changed — refuted: "Four cases, tried in this order" settles it, and `Oracle` lists them in the same order.
- [ambiguity-testability] Whether a decision retired after its second attempt is re-analysed in the same run or the next — refuted: the pin mismatch is called "the single documented exception" to collecting every decision before any fixer runs, which excludes a second in-run re-sweep.
- [ambiguity-testability] Fresh side of the empty-result support test could be read as literally matching a tool's "(no matches)" rendering, so an empty citation could never re-verify — refuted: the return contract already classifies such a rendering as "a marker of emptiness rather than output text", which settles the fresh side by the same sentence.
- [ambiguity-testability] "every re-run exits without error" has no exit code for a `tool: Grep` citation — refuted: the same paragraph's empty-result rule shows a no-match call is a successful empty result, not an error.
- [ambiguity-testability] "Analyst fails or returns an unusable block" leaves the degrade trigger undefined — refuted: "Every field is required unless marked optional" plus the per-field fallbacks stated for `Rejection candidate` and `Verification Plan` supply a workable trigger.
- [ambiguity-testability] `**Verification:** advisory` prescribed for the partial-coverage case against "the softest check the pass depends on sets the value" (which yields `hard` when only hard checks ran) — set aside: that is a section-to-section contradiction, internal-consistency's mandate rather than this lens's.
- [ambiguity-testability] `<who>` in the `**Decision:**` grammar undefined (literal `user` vs an identity) — refuted: the worked example writes `[user, 2026-08-27; …]` and no consumer parses the field.
- [ambiguity-testability] Stage 0's usability rule ignores a `**Location:**` written without backticks — refuted: "its first backticked token" is a precise test whose failure mode is defined (location-less → ask the user), not a second reading.
- [ambiguity-testability] Whether a `Failed` `fix-auto` verdict counts as "the dispatch errored" in stage 4's third case — refuted: both readings land in the same case, since a Failed dispatch that changed no pinned file is already covered by the case's second limb.
- [ambiguity-testability] "run summary" never defined as an artifact despite carrying six duties — refuted: `/fix-all` Step 4.2's summary and Step 5's appended decision-stage summary block name it.
- [ambiguity-testability] Which `**Verification:**` value stage 4's third case writes when no plan existed — refuted: the value definitions (`unavailable` where no check of any kind ran) apply independently of which case wrote the attempt entry.
- [ambiguity-testability] Pinned-list dedupe when the `Target` also appears in the resolution text — refuted: format only, nothing branches on a duplicate entry.
- [internal-consistency] "no observable change followed the dispatch" in The flow's closing prose vs stage 4 case 3's "no pinned file changed observably" — refuted: the prose explicitly defers to "the two cases stage 4 lists", so stage 4's wording governs.
- [internal-consistency] Edge cases' degraded path "the same five-outcome prompt, A and B taken from the finding's Remediation" vs stage 2's "never a B the user cannot act on" — refuted: "five-outcome prompt" names the sweep prompt (as Scope also does), not a guaranteed option count.
- [internal-consistency] Decision outcomes' "The sweep offers five outcomes per finding" vs the A-alone three-option case — refuted: the qualification appears two sentences later in the same paragraph.
- [internal-consistency] Delivery's MINOR bump (1.17.3 → 1.18.0, 2.5.2 → 2.6.0) vs its own "any report containing `🚫 Rejected` … requires `code-review` ≥ 1.18.0 wherever it is read" — refuted: the spec consciously discloses the skew, states the pairing in both upgrade notes, and carries both sides under Residual risks.
- [internal-consistency] An unpinned decision (no hasher) would always take stage 4's "no pinned file changed observably" case — refuted: case 1 is tried first and does not consult the pinned set, and Decision record says an unpinned decision is never replayed.
- [internal-consistency] Stage 2's permitted "corrected Location: line" write vs "`skip` writes nothing at all" — refuted: stage 0 binds that write to "when that finding's decision is written in stage 2", and skip writes no decision.
- [internal-consistency] Unbalanced closing parenthesis in stage 4's `/fix-all` zero-auto aside — refuted: a formatting typo, not a contradiction between sections.
- [internal-consistency] The analyst's grant omits `git status` while stage 2's re-run boundary admits five git subcommands — refuted: different actors; the orchestrator's boundary is deliberately wider than the analyst's grant.
- [internal-consistency] Evidence's "seven files across two plugins" vs Verification step 5's "seven consumers" — refuted: two different sets that both happen to number seven; no sentence equates them.
- [internal-consistency] fix-auto's Phase 1 rejected-status abort is collected as Failed, yet stage 4 case 3 appends "attempt N: failed" to a decision line a rejected block never carries — refuted: such a block is excluded at the Step 1.3 filter and never enters stage 3 of this loop.
- [internal-consistency] Stage 4 case 3 (failed) must write a `**Verification:**` line whose value none of `hard|advisory|unavailable` obviously fits — refuted: `hard` covers a plan whose checks produced observable output, pass or fail.
- [internal-consistency] Decision record's "a block that already carries one" applied to the "after a retirement" sub-case, where the retirement already rewrote the line to `**Decision-retired:**` — refuted: "one" reads as a decision line of either kind, and the at-most-one-live rule is stated separately.
- [internal-consistency] Purpose's "exactly one documented exception" vs stage 2's other return paths (unsupported rejection candidate, unrestatable `other…`) — refuted: those return to the sweep in place and never interrupt a batch in flight, which is what the exception is about.
- [ux] Stage 0 makes the user hand-derive a path:line cold, before the analyst — the only component that reads code — has run: refuted, the spec states the rationale ("An analyst has nothing to read without it"), matches today's behaviour at fix-report.md:182, bounds the re-ask, and defines the decline path as Failed-and-re-offered.
- [ux] No pre-flight statement of scale before the first ask: refuted, /fix-all's Step 5 offer names the count before anything runs, /fix-report's user just selected the findings themselves, and stage 1 states "13 findings to analyse, in 2 batches of at most 8" before dispatch.
- [ux] The sweep offers no [stop] option, so a user who wants out must kill the run: refuted, cancelling is a supported exit, every decision is "written to the source report as it is made", and Edge cases defines the resume; the four-option ceiling also leaves no slot for a fifth outcome.
- [ux] AskUserQuestion is an option picker but stage 0 collects a free-form path:line through it: refuted, the spec already treats the tool's built-in free-form answer as a first-class input at stage 2's other…, so the construct admits typed values by its own account.
- [ux] A valid-but-unwanted finding can only be skipped and returns forever, with no won't-fix outcome: refuted, reject is a user decision with a free-form reason, so "won't fix" is expressible in the outcome that already exists.
- [ux] Six loop-written bookkeeping lines per finding (Decision-pin hashes included) clutter a committed report a human reads: refuted, **Status:** stays "the first non-blank line under the finding's heading", both plugins' docs register the fields, and the inline-versus-sidecar choice is argued from readable diffs.
- [ux] **Decision-retired:** lines accumulate without bound in a committed report: refuted, a finding "reaching its second retirement is not re-analysed at all", so the count is capped at two in practice.
- [ux] The `(was: `—`)` parenthetical is empty noise on the headline case: refuted, it records that the reviewer supplied no address at all, which is provenance a later reader can act on.
- [ux] **Verification:** hard|advisory|unavailable is loop jargon in a human-facing artifact: refuted, Delivery and Verification step 5 require both plugins' docs to register the field and its values.
- [ux] /fix-all's Step 5 is an all-or-nothing yes/no over the whole needs_decision list with no per-finding selection: refuted, the offer names the count and the sweep's own skip is the per-finding opt-out.
- [ux] Purpose claims reduced friction but the new flow adds asks the old /fix path never had: refuted, typed command invocations drop from N to one and the added asks buy verification the old path did not perform.
- [contracts] `**Decision:**` payload extraction ("the text between the first ` — ` and the final ` [`") collides with a resolution text containing ` [` — refuted: the bookkeeping field is always last and carries no ` [` of its own, so the final ` [` is unambiguous.
- [contracts] `**Decision-pin:**` `<path>=<blob-hash>` and its ` | ` separator have no escaping for paths containing `=` or `|` — refuted: no stated invariant breaks, and a last-`=` split resolves it; no such path is in evidence.
- [contracts] The pin pipeline's "one pipeline with nothing in between" contradicts the canonicalisation ("trailing whitespace is stripped from every line and the excerpt ends with exactly one trailing newline") — refuted: the stripping folds into the named `sed`/`grep -v` expressions, and pin time and comparison time run the same pipeline either way, so no hash mismatch follows.
- [contracts] `**Verification:**` has no stated value for stage 4's third case (dispatch errored / no pinned file changed), though `Decision record` says the line is written "for the two cases that write no status" — refuted: derivable from the value definitions, `hard` where checks produced observable output and `unavailable` where none ran.
- [contracts] `Verification Plan` is a required return field, yet stage 4's fourth case speaks of "a finding for which the analyst supplied none" — refuted: the mechanical plan-rejection test explicitly makes a failing plan "no plan for that alternative", and the degraded path has no analyst return at all.
- [contracts] The compatibility trigger list ("any report containing `🚫 Rejected`, or a `**Location:**` line in the extended `(was: …)` form, requires `code-review` ≥ 1.18.0") omits the six loop-written decision fields, which a 1.17.3 dispatcher would forward whole to `fix-auto` — refuted: stage 2 rewrites `**Location:**` for every decided finding, so any block carrying the decision cluster also carries the extended form and is already covered by the stated trigger.
- [contracts] The pinned file set ("that `Target` plus every `path[:line]` token appearing in the resolution text") never defines what counts as a path token, so implementers pin different sets — refuted: the always-pinned `Target`, the `absent` rule for non-existent paths, and the `Alternatives` requirement that each resolution name every file and line bound the divergence.
- [contracts] Retiring a decision to `**Decision-retired:**` leaves its companion `**Verification-plan:**` and `**Decision-pin:**` orphaned with no stated disposal — refuted: the at-most-one rule overwrites them in place when the fresh decision is written, and the replay check reads only a live `**Decision:**` line.
- [contracts] Prefix-matching a status value could collide `✅ Fixed` with `⚠️ Partially Fixed` — refuted: every status value begins with its own icon, so none is a prefix of another.
- [contracts] `code-review` 1.18.0 is graded MINOR though it changes a committed artifact format that 1.17.3 misreads, which `CLAUDE.local.md` maps to MAJOR under "incompatible formats" — refuted: both releases remain backward compatible for every input their predecessors accepted, and the forward-compat skew is explicitly disclosed in `Delivery` and carried in `Residual risks`.
- [contracts] The `(empty)` citation marker is ambiguous against a tool whose literal output is the string `(empty)` — refuted: the spec labels it "a marker of emptiness rather than output text", and the colliding case is contrived.
- [contracts] The absence of a dependency field in the marketplace manifest leaves the `code-review` 1.18.0 ↔ `qa` 2.6.0 pairing unenforceable — refuted: explicitly disclosed in `Delivery` and under `Residual risks` ("stated in both upgrade notes and enforced by nothing").
- [feasibility] Stage 1's parallel fan-out (8 read-only subagents dispatched in a single turn) exceeds what the platform allows — refuted by plugins/web-auditor/agents/web-auditor.md:185 ('launch the in-scope agents in parallel, in a single turn', up to 7 agents) and plugins/superutils/commands/spec-review.md:129 ('Task per lens in parallel').
- [feasibility] The four-option / four-question AskUserQuestion ceilings the checklist pagination and stage 0 batching rest on are invented — refuted by fix-report.md:129 ('AskUserQuestion with multiSelect, 4 issues per page'), fix-report.md:182 ('batch up to 4 such issues per call, one question each') and spec-review.md:293.
- [feasibility] `other…` as 'the tool's own free-form answer, not a fifth option' may not exist, making five outcomes uncollectable within the four-option ceiling — no repo artifact contradicts it, and spec-review.md:241-242 already collects a user-authored alternative at an AskUserQuestion gate.
- [feasibility] The analyst's `Bash(git log:*)` grant may be inert, so the read-only property is unenforced — explicitly disclosed under `Residual risks` and probed by `Verification` step 6; `_uses_colon_specifier` (scripts/check_agent_frontmatter.py:433-443) does return False for that spelling exactly as the spec states, so its 'no error and no warning' claim is accurate.
- [feasibility] `disallowedTools:` would fail the frontmatter check, or the 26th agent file would trip the file-count guard — refuted: PERMITTED_KEYS (scripts/check_agent_frontmatter.py:46-50) contains `disallowedTools`, `Bash`/`Edit`/`Write`/`NotebookEdit`/`Skill` are all canonical, and EXPECTED_AGENT_FILES=25 only warns on a *lower* count (25 agent files exist today).
- [feasibility] The `sed | grep -v | shasum` pin pipeline needs grants the commands do not hold — refuted: `Delivery` adds `Bash(shasum:*)`, `Bash(sha256sum:*)`, `Bash(sed:*)`, `Bash(grep:*)`, and per CLAUDE.md `allowed-tools` is a permission pre-approval, so the worst case without them is a prompt, not an inability.
- [feasibility] `Delivery`'s 'without one of the two hashers neither command can compute the block hash' misstates `allowed-tools` as a capability grant — refuted on re-reading: 'one of the two hashers' means the binary is absent from the machine (`sha256sum` being the stated fallback where `shasum` is absent), not the grant.
- [feasibility] `sed -n '<first>,<last>p'` would cut a stale window, because the loop's own Status/Decision writes shift every later block's line numbers between pin time and the pre-dispatch comparison — refuted: 'the line range Step 1.2 delimits' reads as Step 1.2's delimiting rule (heading → next `###`/`---`/EOF) re-applied at each hashing, which yields a fresh range; the residual doubt is a readability question for another lens.
- [feasibility] The Edit tool's uniqueness requirement makes `**Dispatch:** attempt 1 dispatched <date>` unwritable/unreplaceable when two blocks carry the identical line — refuted: the line is always anchored to the unique `**Decision-pin:**` (sha256-bearing) or `**Decision:**` line directly above it, so a unique multi-line old_string always exists.
- [feasibility] The support test cannot be applied to `tool: Grep`/`Read` citations because tool output is not a stable verbatim string — refuted: the contract records the call's parameters (the example carries `output_mode=content`), the orchestrator holds the same Read/Grep/Glob tools, and any formatting divergence fails safe by withholding `reject`.
- [feasibility] `git hash-object` errors on a pinned path that does not exist, leaving the pin unwritable — refuted: `Decision record` records such a path as `<path>=absent` and treats absent↔present as an observable change.
- [feasibility] The redefinition of 'Skip remaining' ('advances to the next needs-decision page') contradicts fix-report.md:167, where selecting it proceeds to Step 3 — out of this lens: the platform can deliver either semantics by prose edit; the clash is an internal/reference contradiction for another lens.
- [feasibility] fix-auto cannot ask for a missing Location from inside a subagent (AskUserQuestion is stripped from every subagent per check_agent_frontmatter.py:54-57), breaking the stage 3 rationale — refuted: the spec cites that very failure ('stops to ask from inside a subagent') as the thing persisting the corrected Location prevents, so it relies on the limitation rather than on the ask succeeding.
- [feasibility] `Evidence`'s '264-line command' is off by one against the current fix-report.md — not a capability claim, and the rhetorical point (Step 2.4 buried mid-command at line 180) is verified exactly.

## Accepted risks (user-decided)

None as an outcome — no entry was decided *keep as is*. Two decisions are worth naming here anyway, because the user knowingly chose disclosure over a fix: **SR-024** and **SR-044** both concern stage 1's parallel fan-out being unbounded in dispatches, wall-clock and token cost — a straight miss against loop-engineering bar item 6. The user chose to record it in the spec's own `Residual risks` as a deliberate choice rather than add ceilings, and **SR-104** later repaired the rationale so it argues against a *silent* cap rather than against caps as such.

## Declined (user-decided)

None. Every batch was approved whole, at all five gates.

## Residual risks

What this loop did not catch, and could not:

- **The run stopped on the cap, not on quiet, and the rate is flat.** Round 6's panel returned 16 major+ entries and 15 survived refutation — the same counts as round 5, on different entries. A seventh round would find roughly sixteen more. Nothing here supports a claim that the spec is now correct, and the two flat rounds are positive evidence that more rounds of this loop will not make it so.
- **Round 6's fixes are unreviewed.** 22 entries, +269 lines, `applied (not re-reviewed)`. Four rounds of evidence say new machinery breeds new criticals: each round's criticals came from the previous round's fixes. There is no reason to think round 6's differ — and round 6 is the round that proved it, by finding 16 major+ entries in round 5's supposedly-final text.
- **The loop rewards elaboration.** The spec went 310 → 1430 lines while the underlying design — an analyst agent, a decision skill, five outcomes — never changed. Most of the growth is machinery invented to satisfy findings, not to serve the user's request: the `Decision-pin`, the dispatch marker, attempt retirement, stage 3.5, the `Oracle` section. None of it was user-approved; all of it is now load-bearing, and each piece generated the next round's findings.
- **`ux` never ran.** The one lens whose mandate covers the interaction this spec exists to improve was dropped at the cap five rounds running, and what it found on its first reading suggests the other five lenses were structurally unable to see that surface at all. `doctrine-compliance` is now in the same position in reverse: it has not read the final spec.
- **No executable oracle exists.** The spec describes behaviour of code not yet written. Every verdict rests on reading prose; the whole `Verification` section is a plan for checks that have never been run.
- **The reviewer panel was the same six agents five rounds running.** Fresh instances, identical roster and identical mandates. Systematic blindnesses in a lens's mandate reproduce every round rather than being caught by a different reader — which is precisely what round 6's single substitution demonstrated, and what the five rounds before it concealed.
- **19 user decisions are load-bearing and unvalidated.** Every needs-decision entry that reached a gate was decided *accept*, and several decisions added machinery that later rounds then found defects in. No mechanism in this loop checks whether a decision was a good one; the challenger explicitly declines to, treating a recorded decision as settling the question (which is how SR-156 was refuted).
- **Time was never instrumented.** `active_seconds` stayed 0 for the whole run, so the time budget — 1800s, then 7200s, then 10800s — was never a real constraint. One of the three hard budgets doctrine requires was nominal here.

## Recovery

**Loop-touched files.** The loop itself committed nothing — it left every change in the working tree, as doctrine item 11 requires. Anything committed after terminalization was a separate act:

- `docs/superpowers/specs/2026-08-27-needs-decision-batch-resolution-design.md` — the spec, rewritten six times
- `docs/superpowers/specs/reviews/2026-08-27-needs-decision-batch-resolution-design-review.state.json` — the sidecar
- `docs/superpowers/specs/reviews/2026-08-27-needs-decision-batch-resolution-design-review.md` — this report

**Snapshot:** `docs/superpowers/specs/reviews/2026-08-27-needs-decision-batch-resolution-design.pre-loop.bak` — the spec exactly as it stood before the first fix application. It is byte-identical to the spec as committed at `a67262b`, so it is a local convenience and not the durable copy; it is deliberately left untracked for that reason.

To discard the whole run: `git show a67262b:docs/superpowers/specs/2026-08-27-needs-decision-batch-resolution-design.md > docs/superpowers/specs/2026-08-27-needs-decision-batch-resolution-design.md`, which works in a fresh clone where the `.bak` does not exist. Copying the snapshot back does the same thing locally. **Do not reach for `git restore` without meaning it:** the loop's six rounds were uncommitted while it ran, and a restore then would have dropped all of them silently — that is why the snapshot was taken at all.


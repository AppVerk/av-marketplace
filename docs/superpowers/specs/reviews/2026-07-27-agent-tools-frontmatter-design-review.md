# Spec-review loop report — 2026-07-27-agent-tools-frontmatter-design.md

**Runs:** 2 (run 1 ended `STOPPED(budget)`; run 2 resumed with a raised budget)
**Mode:** interactive (batch-approve gate on)
**Budgets used:** 10 rounds · ~72 dispatches
**Terminal status:** `CONVERGED`
**Verdict label:** Re-reviewed (advisory) — never "Verified"

The spec grew from 286 to 769 lines across ten rounds. Roughly 125 findings were
raised; the great majority were fixed, a handful refuted, and the eleven minors and
nits of the final round are recorded here as `reported-only` — convergence
terminates before the fix phase by design.

## Convergence

Round 10's fresh panel returned **zero critical and zero major findings**. Two of
the five lenses — `completeness` and `doctrine-compliance` — returned an empty
findings list outright. All three contract conditions hold:

- **(a) zero significant findings.** Significant means major-or-above surviving
  refutation. No lens surfaced a major, so the set is empty with nothing left to
  challenge.
- **(b) zero unlanded fixes.** Every applied edit landed; no `fix-failed` outcome
  was ever recorded.
- **(c) zero `unconfirmed` entries.** The three run-1 majors left unadjudicated at
  the budget stop (SR-023, SR-024, SR-025) were re-dispatched to challengers at the
  start of run 2 — the contract requires this whether or not a fresh panel re-finds
  them — and all three were upheld and then fixed.

**Trajectory of major-and-above findings per round** — counting every critical and
major row the round raised, whatever its outcome: 12 → 10 → 7 → 6 → 5 → 1 → 4 →
3 → 1 → **0**.

The first two values were previously recorded as 11 and 6; both are corrected here
by counting the round tables in this report. Round 1 is 2 critical + 10 major, round
2 is 0 critical + 10 major (6 applied, 1 refuted, 3 `unconfirmed`). No single rule
produced the old pair. Rounds 3 through 9 have no table here — their counts came
from the state sidecar, which `f804c02` deleted, so they are no longer re-derivable
from this repository and are carried forward as recorded. Round 10's zero is the
Convergence condition above and is re-derivable.

### What this verdict does not mean

Round 1's fourteen findings passed a full challenger quorum, 13 for 13 upheld.
Rounds 2 through 9 did not: at the run-1 budget gate the maintainer chose to spend
the remaining time on fixes rather than on adversarial confirmation, and that
choice carried forward. Findings in those rounds were fixed on panel argument plus
orchestrator evidence, not on challenger survival — the sole exception being
SR-023, SR-024 and SR-025, re-dispatched to challengers at the start of run 2 and
upheld there, as Coverage records.

The final state is nonetheless validated independently of that path: a fresh
five-lens panel, told nothing about what had changed, found no major defect. That
panel is the strongest evidence available here precisely because it does not depend
on how the spec arrived in its current state.

## Round 1 — panel, units

**Panel:** internal-consistency, ambiguity-testability, completeness, feasibility,
doctrine-compliance.
**Rationale:** both core lenses always on; `completeness` because the spec has nine
`##` sections; `feasibility` and `doctrine-compliance` triggered by agent and
marketplace-plugin design content. `feasibility` was the highest-value lens here —
the spec restates an external platform contract and then builds a validator that
enforces the restatement, so a misread contract would have been self-confirming.

**Units:** Purpose · Evidence · Scope · The contract · Repairs · Validator ·
Verification · Delivery · Residual risks

Challenger quorum: 13 dispatches, **13 upheld, 0 refuted**. Both criticals were
double-challenged and upheld twice.

| SR | severity | lenses | outcome |
| --- | --- | --- | --- |
| SR-007 | critical | feasibility | applied |
| SR-010 | critical | doctrine-compliance | applied |
| SR-001 | major | internal-consistency | applied |
| SR-002 | major | internal-consistency, ambiguity-testability | applied |
| SR-003 | major | internal-consistency, ambiguity-testability | applied |
| SR-004 | major | ambiguity-testability, completeness | applied (user-decided) |
| SR-005 | major | ambiguity-testability, feasibility | applied |
| SR-008 | major | feasibility | applied |
| SR-009 | major | feasibility | applied |
| SR-011 | major | doctrine-compliance | applied |
| SR-012 | major | doctrine-compliance | applied |
| SR-014 | major | orchestrator | applied |
| SR-006 | minor | ambiguity-testability, completeness | applied |
| SR-013 | minor | doctrine-compliance | applied |

Two findings were confirmed against the repository rather than by argument alone.
`python3 scripts/check_plugin_versions.py` exited 1 on **this branch** because
`docs/plugins/qa.md` still read 2.5.0 against the 2.5.1 that `cecaa92`, the
branch's own first commit, had written into `plugin.json`, `marketplace.json` and
the README row (SR-009). And `plugins/code-review/agents/fix-auto.md:105` invokes
the `Skill` tool while declaring no `skills:` key, so the spec's target list would
have removed a capability the agent uses (SR-007).

SR-009 was recorded here as failing on `master`. It never did, and this line is a
correction of the report's own text: measured on `origin/master` (`0f01cd6`) by
extracting the tree with `git archive` and running the script in it, all four qa
surfaces read 2.5.0 and the check exits 0. The drift was introduced by this branch
and lived only on it — `cecaa92` reproduces it (`EXIT=1`), and `c3943a6`, which
carried all four surfaces to 2.5.2, repaired it. Naming the wrong tree is the same
error the spec made and `11c2a44` corrected there.

SR-014 was surfaced by a challenger during SR-010's adjudication rather than by a
panel lens, then confirmed by direct grep: `web-auditor.md` calls `TaskOutput` at
four sites while `TaskOutput` is stripped from every subagent. It is recorded as a
finding rather than discarded on the formal ground that challengers return verdicts
and not findings — silently dropping a verified defect is the behaviour the
self-falsification rule exists to prevent. Its lens is recorded as `orchestrator`
to keep panel attribution honest.

## Round 2 — panel, units

Same panel and units, fresh agent instances, reviewing the revised text with no
knowledge of what round 1 changed.

**None of the fourteen round-1 findings reappeared.** Every applied fix held.

The panel returned 17 new findings, most of them second-order: defects in the
verification apparatus that round 1 had itself introduced. (This sentence read
"16" until the post-implementation review counted the table below: SR-015 through
SR-031 is seventeen ids, with none skipped. The sidecar that would have settled it
independently was deleted in `f804c02`, so the table is the surviving record.)

| SR | severity | lenses | outcome |
| --- | --- | --- | --- |
| SR-015 | major | internal-consistency, feasibility, doctrine-compliance | applied |
| SR-016 | major | internal-consistency | applied |
| SR-018 | major | feasibility | applied |
| SR-020 | major | feasibility | applied |
| SR-021 | major | feasibility | applied |
| SR-022 | major | feasibility | applied |
| SR-017 | minor | internal-consistency, ambiguity-testability | applied |
| SR-030 | minor | ambiguity-testability | applied |
| SR-031 | minor | ambiguity-testability | applied |
| SR-019 | major | feasibility | refuted |
| SR-023 | major | doctrine-compliance | unconfirmed |
| SR-024 | major | doctrine-compliance | unconfirmed |
| SR-025 | major | doctrine-compliance | unconfirmed |
| SR-026 | minor | internal-consistency | reported-only |
| SR-027 | minor | internal-consistency | reported-only |
| SR-028 | minor | ambiguity-testability | reported-only |
| SR-029 | minor | completeness | reported-only |

Four round-2 findings were confirmed by direct repository evidence before any fix
was written:

- **SR-020** — `.gitignore:3` excludes `CLAUDE.local.md` and no tracked `CLAUDE.md`
  exists, so the authoring rule the spec listed as a deliverable would never have
  reached the pull request.
- **SR-022** — ten `run_in_background: true` instructions in `web-auditor.md` (nine
  dispatch sites plus the Phase 2 lead-in) would have survived a bare
  `Task(` → `Agent(` substitution, leaving the repaired coordinator with no way to
  collect results.
- **SR-018** — agent bodies contain exactly one `mcp__` occurrence each: the
  `allowed-tools:` line being deleted. The real references live in eight `SKILL.md`
  files, so body reconciliation as written in round 1 would have passed vacuously.
- **SR-021** — `fe-tester` ships the wildcard MCP form only, so if the bare form is
  the honoured one it alone would have stayed broken.

**SR-019 refuted.** The claim was that nine agents invoking skills need `Skill` in
`tools:`. The subagent documentation states that `skills:` injects each listed
skill's content at startup and that the `Skill` tool is needed only to invoke
skills *not* preloaded. This session demonstrates it directly: the `spec-reviewer`
agents declare `tools: Read, Grep, Glob` with no `Skill`, and correctly applied
`lens-catalog`'s severity anchors and self-falsification rule. `fix-auto` remains a
genuine exception because it invokes a skill it does not declare.

## Rounds 3–10 (run 2)

Same five-lens panel each round, fresh agent instances, each told nothing about
what the previous round changed. Selected findings, by the round that raised them:

- **R3** — the three run-1 `unconfirmed` majors upheld; `CLAUDE.local.md` is
  gitignored so the authoring rule would never have shipped; ten
  `run_in_background: true` instructions survive a bare `Task(`→`Agent(` swap;
  body reconciliation greps a surface containing one `mcp__` occurrence per file.
- **R4** — the registry cannot confirm filter behaviour; fifteen command and skill
  files pre-approve `Task`/`TaskOutput`/`browser_run_code`; `audit.md` has two
  `Task` references, not one.
- **R5** — the status record had no durable home (found by three lenses); the
  registry cannot retire the redundant MCP form; `fe-tester` was wildcard-only.
- **R6** — two `(background)` step labels outside every counted edit set.
- **R7** — the derivation invariant is false for `Bash` and `TaskList` too, not
  only MCP; `be-testing/SKILL.md` does name its six servers, contradicting a claim
  introduced one round earlier.
- **R8** — the pinned red-before command `git checkout master -- plugins/` would
  destroy uncommitted repairs irrecoverably; the post-write gate was
  absence-only, satisfiable by deletion.
- **R9** — no rule mapped `browser_*` references onto server-level grants, so the
  pass condition would have failed every agent the repair exists for (three
  lenses); `git worktree add master` fails when master is checked out.
- **R10** — zero major or critical. Eleven minors and nits recorded below.

Two findings were self-inflicted: the destructive `git checkout` and the false
"bodies and skills contain zero `mcp__` occurrences" were both introduced by
earlier rounds of this loop and caught by later ones.

## Reported-only (round 10, not fixed)

Convergence terminates before the fix phase, so none of these was fixed inside the
loop:

- `fix-auto`'s target list carries `Write` and `Grep` with no body evidence, and
  `web-auditor`'s `WebFetch`/`WebSearch` are evidenced only in a preloaded skill
  and a report template — neither is covered by the three stated qualifications.
- The Phase 3 collect step should refer to *in-scope* scanner results, not to seven
  always.
- The four `TaskOutput` sites are attributed differently in Repairs and
  Verification (which of them governs the Phase 2.5 pair versus the Phase 2
  scanners).
- Body reconciliation's "two classes it cannot reach" overstates the MCP half,
  which the `Covered` rule does partly reach.
- Validator well-formedness leaves a `- item` after a non-empty key, and an inline
  `#` after a value, undetermined.
- Verification miscites Delivery on which two narrowings are named.
- Minor factual slips: `be-tester`'s existing list uses bare prefixes, not the
  plugin form; `TaskOutput` is pre-approved in three command files, not seven.

Three of the findings condensed into these bullets — one bullet in whole, and part
of each of two others — were closed after the loop terminated, by the
implementation branch's post-implementation review rather than by an eleventh
panel. They are recorded here for the same reason SR-026 through SR-029 are: the
fix exists, under no finding id. `931f042` rewrote the Phase 3 collect step to refer to the
***in-scope*** scanner results, "not to seven always, since dispatch is scope-gated"
(spec lines 508–510), and corrected the `TaskOutput` file list to "three of those
same seven" (spec line 112). `c804315` took the `Write` half of the first bullet
into the plugins, dropping `Write` and `TaskList` from `fix-auto`'s shipped list as
referenced nowhere on its surface; `Write` was then restored together with the body
instruction in `plugins/code-review/agents/fix-auto.md` that now evidences it, which
closes that half by supplying the missing evidence rather than by removing the
entry.

The other four bullets stand, as do the untouched parts of the two above:
`fix-auto` still declares `Grep` with no body reference, nothing since has touched
`web-auditor`'s `WebFetch`/`WebSearch`, and the `be-tester` half of the last bullet
is unaddressed.

## Coverage

- **Catalog lenses not selected in any round:** `ux` (no UI surface), `contracts` (the
  frontmatter contract is covered by internal-consistency and feasibility, which
  read it against the platform docs and the repository).
- **Not returned:** none. The same five-lens panel returned in every one of the ten
  rounds; no reviewer or challenger failed or needed a retry.
- **Challenger quorum ran in round 1 only.** At the run-1 budget gate the maintainer
  chose to spend the remaining time on fixes rather than on adversarial
  confirmation, and that choice carried forward through round 9. Round 1's fourteen
  findings were fully challenged, 13 for 13 upheld. Round 2's nine applied fixes and
  every fix in rounds 3 through 9 rest on panel argument, orchestrator evidence and
  the user's approval, **not** on adversarial confirmation. The sole exception is
  SR-023, SR-024 and SR-025, re-dispatched to challengers at the start of run 2 and
  upheld there. This is the single largest confidence gap in the run.
- **Ten rounds, each re-reviewed by the next.** Rounds 1 through 9 were each
  followed by a fresh panel reading the revised text with no knowledge of what had
  changed — which is how round 2 caught round 1's second-order defects, and how R7
  and R8 caught two defects this loop had introduced itself. **Round 10 is the
  exception:** convergence terminates before its fix phase, so its minors are
  unfixed and no eleventh panel ever read them.
- **Standing oracle blind spots:** user intent, external facts, unstated
  requirements.

## Rejected by the panel (self-falsification)

Round 1 — 24 candidates, round 2 — 41. A representative selection; the full lists
are in the sidecar.

- [internal-consistency] "Fifteen agent definitions" vs a 15-row table excluding the
  already-repaired fe-tester — present tense makes fifteen the post-fe-tester count.
- [internal-consistency] `Agent` absent from the background built-in allowlist while
  the repairs grant it — the next sentence reconciles it explicitly.
- [ambiguity-testability] Rows marked "unchanged" could read as "do not touch the
  file" — the preceding sentence scopes "unchanged" to the tools column.
- [ambiguity-testability] `exits zero on the repaired tree` conflicts with warnings
  the repaired tree still emits — warnings are defined as non-failing.
- [completeness] The canonical tool-name list is not enumerated — explicitly
  delegated to `tools-reference` as a dated constant.
- [completeness] Concurrency of the seven scans is undecided — no baseline
  concurrency exists to preserve, since dispatch never worked.
- [feasibility] `be-tester` and the web-auditor agents declare `skills:` but no
  `Skill` tool — this repo's superutils agents demonstrate preloading works without
  it.
- [feasibility] The nesting-depth limit could block the coordinator — command →
  coordinator → scanner is two layers, under the three-layer default.
- [feasibility] `feedback-analyzer` carries a live colon-form `Bash(git:*)` the spec
  never repairs — it has no `allowed-tools:`, so it is outside the stated scope, and
  the validator's colon-form warning surfaces it anyway.
- [doctrine-compliance] Items 4, 6, 9 — triggers absent: no headless autonomous
  mode, no iterating loop, nothing auto-corrects.
- [doctrine-compliance] Item 11 — trigger fires and is met: one branch, one pull
  request, explicit file list, nothing committed to `master`.

## Accepted risks (user-decided)

None. No finding was resolved as `keep-as-is`.

## Declined (user-decided)

None. The one batch gate reached was approved in full.

## User decisions

**SR-004 — conditional narrowing removed entirely.** The panel showed the
narrowing branch had no concrete target values (SR-004), that its gating check
measured permission-prompt suppression rather than tool availability (SR-005), and
that the `fix-auto` row contradicted it (SR-003). Rather than specify the missing
allowlists, the whole branch was deleted: every agent keeps the `Bash` grant it has
today, and least-privilege narrowing is deferred to a follow-up that must first
design an availability test. Three findings were resolved by removing the optional
feature that produced them.

## Residual risks

**The open set is round 10's eleven minors and nits**, condensed into the seven
bullets under "Reported-only (round 10, not fixed)". None is major-or-above.
Convergence terminates before the fix phase by design, so the loop left all seven
unfixed and, being the last round, un-re-reviewed. They are the only findings *this
loop* leaves open — but three of them have since been closed outside it, by
`931f042` and `c804315` on the implementation branch: one bullet in whole, and part
of each of two others. The closing note under "Reported-only" records which, and
against which spec lines. Four bullets stand untouched, and so do the unclosed
parts of the other two.

Everything raised in rounds 1 through 9 was resolved: applied, or refuted (SR-019),
or — for the three run-1 majors SR-023, SR-024 and SR-025 that the budget stop left
`unconfirmed` — re-dispatched to challengers at the start of run 2, upheld in R3,
and fixed there. The four run-1 `reported-only` minors were never re-batched under
their own ids, but later rounds' edits overtook all four, and the spec now carries
each: the coordinator's Playwright grant is in the repairs table (SR-026); the Error
criterion reads "wrong regardless of which platform version reads the file, **or a
deliberate fail-closed choice named as such**" (SR-027); the expected-registry
bullet says twelve `mcp__*` entries for `be-tester` (SR-028); and server-level
`mcp__` entries are stated exempt from the unrecognised-name warning (SR-029).

This section previously listed those seven as still open, three of them as
`unconfirmed`. That was run-1 text left behind when run 2 closed them, and it
contradicted both the Convergence section above and the R3 line under Rounds 3–10.

**Loop-level residuals:** verifier gaming; stochasticity across rounds; lens drift;
no token ceiling, only dispatch and time budgets; registry matching is a soft
orchestrator judgment; headless detection is best-effort. Every fix from round 2
through round 9 carries the additional gap named under Coverage — applied without
adversarial confirmation.

## Recovery

Loop-touched files:

- `docs/superpowers/specs/2026-07-27-agent-tools-frontmatter-design.md` — revised
- `docs/superpowers/specs/reviews/2026-07-27-agent-tools-frontmatter-design-review.md`

**This section's original advice is now inverted and must not be followed.** It said
nothing was committed, told the reader to copy a `.pre-loop.bak` snapshot over the
spec, and warned against `git restore`. All three are wrong today. The loop's work
*was* committed, in `c22cbbd`, together with the report, the `.state.json` sidecar
and the `...design.pre-loop.bak` snapshot; `f804c02` then deleted both scratch
artifacts. `ls docs/superpowers/specs/reviews/` now shows the report `.md` and
nothing else, so there is no snapshot on disk to copy.

Git is the recovery path instead. `026284a` is the 286-line pre-loop spec the loop
read; `c22cbbd` is the 769-line state it produced. To recover the pre-loop text:

```
git show 026284a:docs/superpowers/specs/2026-07-27-agent-tools-frontmatter-design.md
```

The deleted sidecar and snapshot are readable the same way from `f804c02^`. Note
that commits after `c22cbbd` have edited the spec further — `11c2a44` among them —
so restoring `026284a` wholesale discards those as well as the loop's own work,
which is the reason the original warning existed even though its mechanism was
wrong.

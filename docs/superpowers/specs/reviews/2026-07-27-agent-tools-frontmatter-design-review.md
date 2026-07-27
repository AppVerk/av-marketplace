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

**Trajectory of major-and-above findings per round:** 11 → 6 → 7 → 6 → 5 → 1 → 4 →
3 → 1 → **0**.

### What this verdict does not mean

Round 1's fourteen findings passed a full challenger quorum, 13 for 13 upheld.
Rounds 3 through 9 did not: at the run-1 budget gate the maintainer chose to spend
the remaining time on fixes rather than on adversarial confirmation, and that
choice carried forward. Findings in those rounds were fixed on panel argument plus
orchestrator evidence, not on challenger survival.

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
`python3 scripts/check_plugin_versions.py` exits 1 on `master` today because
`docs/plugins/qa.md` still reads 2.5.0 against a 2.5.1 plugin (SR-009), and
`plugins/code-review/agents/fix-auto.md:105` invokes the `Skill` tool while
declaring no `skills:` key, so the spec's target list would have removed a
capability the agent uses (SR-007).

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

The panel returned 16 new findings, most of them second-order: defects in the
verification apparatus that round 1 had itself introduced.

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

Convergence terminates before the fix phase, so these stand:

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

## Coverage

- **Catalog lenses not selected in any round:** `ux` (no UI surface), `contracts` (the
  frontmatter contract is covered by internal-consistency and feasibility, which
  read it against the platform docs and the repository).
- **Not returned:** none. All five lenses returned in both rounds; no reviewer or
  challenger failed or needed a retry.
- **Round 2 challenger quorum was skipped by user decision** at the budget gate, in
  favour of spending the remaining time on fixes. The nine round-2 fixes therefore
  rest on orchestrator evidence and the user's approval, **not** on adversarial
  confirmation. Round 1's fourteen were fully challenged; round 2's were not. This
  is the single largest confidence gap in the run.
- **No round 3.** Fixes applied in round 2 were never re-reviewed by a fresh panel,
  so the loop cannot say whether they introduced third-order defects — which is
  exactly what round 2 found round 1 had done.
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

**Seven findings remain open.** Three majors are `unconfirmed` — never challenged,
never refuted, and not fixed:

- **SR-023** — the permitted-field list is the same v2.1.220 snapshot as the
  tool-name constant, but gates as an Error while the tool list only warns. A
  frontmatter field added after v2.1.220 would turn a correct agent definition red
  and block every plugin pull request.
- **SR-024** — body reconciliation is authored and graded by the same actor, runs
  before any file is written (so it grades the plan, not the artifact), and leaves
  no raw artifact a reviewer could re-run.
- **SR-025** — the live comparison's per-agent verdicts have no durable location,
  so they cannot survive the session boundary the check itself requires. The spec's
  own history demonstrates the failure: `fe-tester`'s confirmation has been carried
  in prose since 2.5.1.

Four minors are `reported-only`: SR-026 (three-way disagreement on whether the
`web-auditor` coordinator receives Playwright), SR-027 (the unparseable-frontmatter
Error contradicts the stated "wrong regardless of platform version" criterion),
SR-028 (expected-registry bullets understate the target column — `be-tester` is
described as six MCP servers where the column carries twelve entries), SR-029
(whether `mcp__*` entries trip the unrecognised-name warning is unstated, which
would make the repaired tree the noisiest the checker has ever produced).

**Loop-level residuals:** verifier gaming; stochasticity across rounds; lens drift;
no token ceiling, only dispatch and time budgets; registry matching is a soft
orchestrator judgment; headless detection is best-effort. Round 2's fixes carry the
additional gap named under Coverage — applied without adversarial confirmation.

## Recovery

Loop-touched files:

- `docs/superpowers/specs/2026-07-27-agent-tools-frontmatter-design.md` — revised
- `docs/superpowers/specs/reviews/2026-07-27-agent-tools-frontmatter-design-review.state.json`
- `docs/superpowers/specs/reviews/2026-07-27-agent-tools-frontmatter-design-review.md`

Pre-loop snapshot:
`docs/superpowers/specs/reviews/2026-07-27-agent-tools-frontmatter-design.pre-loop.bak`

To restore, copy the snapshot over the spec. Do **not** use `git restore` on the
spec — the snapshot is the loop's own record and the spec was committed before the
loop ran, so a git restore would silently discard both rounds of work rather than
the intended subset. Nothing was committed by the loop; all changes are
uncommitted.

# Spec-review loop report — 2026-07-13-superutils-spec-review-design.md

**Run:** manual dogfood of the `/superutils:spec-review` protocol (the plugin
does not exist yet; the orchestrator, registry, and fixer roles were performed
by the main conversation, reviewers and challengers as real subagent dispatches).
**Mode:** interactive; needs-decision and batch decisions taken by the user.
**Budgets:** max-iterations 3, max-dispatches 30 (used: 26 launched, of which
3 died on external limits), time-budget n/a (interactive session).
**Terminal status:** `STOPPED(budget)` — iteration cap reached with round 3
unconverged and its challenger stage undispatchable. **Not** a success status.
**Verdict label:** Re-reviewed (advisory) — soft oracle, per the design's own
Oracle statement.

## Round 1 — panel of 5, 7 challengers

Panel: internal-consistency, ambiguity/testability, doctrine-compliance,
implementer-completeness, platform-feasibility (composition logged per round;
same 5 lenses each round). 53 raw findings → clustered by registry identity.

| SR | Cluster | Severity | Quorum | Outcome |
|----|---------|----------|--------|---------|
| SR-001 | Fingerprint identity dead under self-mutation → orchestrator registry | critical | 4 lenses | applied |
| SR-002 | Sidecar hash-pinning vs loop's own writes; resume semantics | critical | 4 lenses | applied |
| SR-003 | Declined/skipped needs-decision vs convergence; `STOPPED(pending-decisions)` | critical | 2 lenses | applied (user: exclude + separate status) |
| SR-004 | Fate of minor/nit findings | major | 4 lenses | applied (user: auto-apply unchallenged, gate-covered) |
| SR-005 | Default mode not a doctrine human gate | major | challenger upheld | applied (user: default flipped to approve-before-apply) |
| SR-006 | Dirty/untracked spec guard + snapshot recovery | major | 3 lenses | applied |
| SR-007 | Challenger verdict vocabulary (uphold/refute, no re-grade) | major | 2 lenses | applied |
| SR-008 | Review units defined; whole-spec reviewer input | major | 2 lenses | applied |
| SR-009 | Diff-preview content pinned (unified diff + SR→hunk) | major | challenger upheld | applied |
| SR-010 | Three-way approve gate + `STOPPED(user-declined)` | major | challenger upheld | applied |
| SR-011 | Mode/TTY contradiction (step 4 vs modes) | major | — | refuted |
| SR-012 | Provenance guard (item 9) non-conformance | major | — | refuted |
| SR-013 | Lens catalog roster as design gap | major | — | refuted |
| SR-014 | Fixture acceptance untestable | major | — | refuted (nit kernel applied) |

Minor batch applied (severity anchors, budget/iteration definitions,
oscillation scoping, outcome enum, SR id scope, coverage/failure handling,
headless-check wording, sequential-thinking fallback, mtime tie-break).
Diff: +216/−74 lines.

## Round 2 — fresh panel of 5, 4 challengers

| SR | Cluster | Severity | Quorum | Outcome |
|----|---------|----------|--------|---------|
| SR-015 | Budget worst-case incomputable at round start | critical | 5/5 lenses | applied (user: stage-boundary checkpoints) |
| SR-016 | Two-phase fixer (propose → candidate → gate → orchestrator applies) | major | 2 lenses | applied |
| SR-017 | Converged-round minors | major | 3 lenses | applied (user: reported-only, strict convergence) |
| SR-018 | Terminal+hash-mismatch re-run; decision carry | major | 3 lenses | applied (user: carry forward with revalidation) |
| SR-019 | Within-round dedup; challenger per registry entry | major | 2 lenses | applied |
| SR-020 | Snapshot at most once per run | major | 2 lenses | applied |
| SR-021 | Declined stickiness | major | challenger upheld | applied (user: sticky) |
| SR-022 | Needs-decision anchor | major | challenger upheld | applied |
| SR-023 | Stop evaluation point + orphan outcome | major | challenger upheld | applied |
| SR-024 | `--auto` minor/nit vs item 9 | major | — | refuted |
| SR-025 | Registry anchor edge cases (`__preamble__`, `__document__`, cross-section) | major | 2 lenses | applied |

Minor batch applied (`unconfirmed` outcome, time accounting excludes user
waits, stop precedence, headless fail-closed tie-break + AskUserQuestion
runtime backstop, coverage third sublist, doctrine-anchor citation fix,
fixture fresh-copy + scripted approve). Sub-major needs-decision, reported
only: fixture answer-scripting harness choice (now an explicit open question
in the spec). Cumulative diff at this point: +316/−77.

## Round 3 — final round: shallow coverage, budget stop

**Coverage WARNING (per the loop's own disclosure rules):**
- Exercised: internal-consistency, ambiguity/testability (2 of 5).
- Not verified (agent failures): doctrine-compliance and
  implementer-completeness (subagents terminated by a session limit),
  platform-feasibility (launch rejected — safety-classifier model temporarily
  unavailable). No retry was possible within the session limit.
- Standing oracle blind spots: user intent, external facts, unstated
  requirements.

The challenger stage could not be dispatched (session limit; remaining
dispatch budget 5 < stage worst case), so per the stage-boundary rule the run
ended `STOPPED(budget)`; single-lens majors ended `unconfirmed`.

| SR | Cluster | Severity | Quorum | Loop outcome → post-loop |
|----|---------|----------|--------|--------------------------|
| SR-026 | Outcome-enum totality (reported-only widening) | critical | 2 lenses | confirmed (not fixed — stopped) → applied post-loop (user batch) |
| SR-027 | pending-decision vs confirmed-not-fixed collision | major | 1 lens | unconfirmed → applied post-loop (user batch) |
| SR-028 | Split-critical significance membership | major | 1 lens | unconfirmed → applied post-loop (user batch) |
| SR-029 | Retroactive decision filter for no-progress set | major | 1 lens | unconfirmed → applied post-loop (user batch) |
| SR-030 | Same-round gate decisions vs convergence | major | 1 lens, needs-decision | unconfirmed → user decided: empty-batch immediate convergence |
| SR-031 | Fixture acceptance predicates | major | 1 lens, needs-decision | unconfirmed → user decided: content predicates, scripted accept, keep-as-is ≠ resolved |

Minor batch (10 items: decline-supersedes-accept, decision edit storage,
marketplace description narrowed, retry headroom, critical-challenger-failure
rule, decided-entry challenger skip, overlap definition + atomic groups, SR
ordering, slug rule, mtime granularity) — applied post-loop in the same
user-approved batch.

**Post-loop edits are outside the loop's verifier authority**: they were
approved item-by-item by the user (a stronger gate than a challenger), but no
fresh panel has re-reviewed them. They are the direct analog of
`applied (not re-reviewed)`.

## Accepted risks (user-decided)

None — no keep-as-is decisions were recorded; every gated finding was either
accepted (fix applied) or resolved by an explicit design decision.

## Declined (user-decided)

None.

## Residual risks of this run

1. Round-3 additions were reviewed by only 2 of 5 lenses, and the post-loop
   batch by none — a follow-up single round (fresh panel, after the session
   limit resets) would restore full-coverage confidence.
2. All run risks disclosed in the spec's own residual list apply to this run
   too (soft oracle, stochasticity, soft registry matching).
3. Convergence was never observed: the run demonstrates the loop's stop and
   disclosure machinery, not its convergence path.

## Recovery

The loop applied edits only to the spec file; the pre-loop state is commit
`71f7b7a` (the spec's initial commit) — recovery is `git show 71f7b7a` /
branch-level revert, never needed to be exercised.

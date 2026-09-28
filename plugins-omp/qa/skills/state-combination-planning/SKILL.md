---
name: "qa:state-combination-planning"
description: Use when authoring QA scenarios for behavior driven by two or more independent boolean inputs (feature flags, permissions, connection states) — enumerate the full 2^N product as a scenario matrix, prove any "impossible" combination, never sample just the main paths.
---

# State Combination Planning

Load when authoring or self-checking a QA test plan whose change under test is driven by two or more independent boolean inputs (feature flags, permissions, connection/loading states). This is plan-authoring guidance for this plugin; scenario executors never load it.

## The problem, and when to load this skill

When N independent boolean inputs drive the behavior under test, the state
space is 2^N — but plans written path-by-path silently cover only the
combinations their author pictured. The classic escape: a feature that works
with the flag ON for an admin and OFF for a viewer, and breaks with the flag
ON for a viewer — the combination nobody planned. Load this skill whenever
the change under test is driven by ≥2 independent boolean inputs.

Scope: boolean inputs, mirroring the source pattern. A small non-boolean
enum axis (e.g. role = admin|editor|viewer) follows the same discipline
with the full cartesian product (|A|×|B| rows) in place of 2^N.

## The minimum bar (MUST)

1. **Enumerate the full 2^N product** of the independent boolean inputs as a
   literal table in the plan (a note above the affected scenarios). The table
   is cheap; the unplanned combination is not.
2. **Classify each combination real / impossible — and prove "impossible".**
   An `impossible` classification must cite a domain invariant (from code or
   docs, with a pointer) or an explicit user/plan confirmation.
   **Unconfirmed → treat as real.**
3. **One scenario per harness-reachable real combination.** A real combination
   without a scenario or an explicit harness-scope disposition is an unmodeled
   state; sampling "the two main ones" from a 2^3 space is the anti-pattern
   this skill exists to kill. A real combination the browser/HTTP/DB harness
   cannot reach (for example, a compile-time constant or a flag with no
   toggle) keeps its row with the disposition `out of harness scope — <reason>`
   instead of a scenario; a code defect is a Blocker, not a harness-scope reason.
4. **Never collapse independent axes in Expected.** A scenario's Expected
   describes what each input governs separately (content vs actions) — an
   Expected written against a synthetic single "status" deletes combinations
   the product can genuinely produce.

## Anti-patterns

- **Sampled coverage** — planning 3 scenarios for a 2^3 space and calling it
  covered.
- **Unilateral "can't happen"** — no invariant cited, no confirmation asked.
- **The synthetic status** — Expected written over `viewing | editing |
  offline` when the real inputs are `isConnected × canEdit`.

## Worked example *(Prospective)*

Inputs: `isConnected`, `canEdit` → 2^2 = 4:

| isConnected | canEdit | Classification | Scenario |
|---|---|---|---|
| yes | yes | real | FE-xx: live view, edit enabled |
| yes | no | real | FE-xx: live view, read-only |
| no | yes | real (confirmed in plan) | FE-xx: offline banner, edit queued/disabled |
| no | no | real | FE-xx: offline banner, read-only |

Four scenarios, one per row. The tempting three-branch plan (online-edit,
online-view, offline) deletes row 3 — the combination a field user hits first.

## Review checklist

- [ ] 1. All independent boolean inputs identified
- [ ] 2. Full 2^N table present in the plan (literal, not sampled)
- [ ] 3. Every `impossible` cites an invariant or explicit confirmation
- [ ] 4. Unconfirmed combinations treated as real
- [ ] 5. One scenario per harness-reachable real combination; an unreachable real row carries `out of harness scope — <reason>`
- [ ] 6. No Expected collapses independent axes into one synthetic status

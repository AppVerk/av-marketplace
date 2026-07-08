---
name: state-combination-modeling
description: Use when a component or view is driven by two or more independent boolean inputs (flags, permissions, connection states) — enumerate the full 2^N product, confirm which combinations are real, never collapse independent axes into one exclusive switch.
---

# State Combination Modeling

## The problem, and when to invoke this skill

When N independent boolean inputs drive one component, the state space is 2^N — but code written axis-by-axis silently models only the combinations its author pictured. The classic bug: an exclusive switch over "the status" deletes a state that two independent inputs can genuinely produce, and nobody notices until a user lands in it. Invoke this skill whenever a component or view is driven by two or more independent boolean inputs (feature flags, permissions, connection states, loading states).

## The minimum bar (MUST)

1. **Enumerate the full 2^N product** of the N independent boolean inputs — a literal table, not a mental sample. The table is cheap; the deleted state is not.
2. **Classify each combination real / impossible — and prove "impossible".** An `impossible` classification must cite a domain invariant or an explicit user/plan confirmation. **Unconfirmed → treat as real**: a unilateral "impossible" recreates the deleted-state bug one level up.
3. **Never collapse independent axes into one exclusive switch.** Orthogonal inputs drive *content* and *actions* separately — a permission flag may swap only the button, not the whole view. An exclusive switch over a synthetic "status" is the collapse in disguise.
4. **Tests cover every real combination.** The enumeration table doubles as the test matrix; a real combination without a test is an unmodeled state with extra steps.

## Anti-patterns

- **The synthetic status enum** — folding `isConnected × canEdit` into `status: 'editing' | 'viewing' | 'offline'` deletes `offline ∧ canEdit`.
- **Unilateral "can't happen"** — classifying a combination impossible because the author can't picture it, with no invariant cited.
- **Axis leakage** — a permission flag that swaps the whole view instead of just the actions it governs.
- **Sampled testing** — testing the two "main" combinations of a 2^3 space and calling it covered.

## Worked example *(Prospective)*

*(Prospective: genericized from the source pattern.)* Two independent inputs: `isConnected`, `canEdit` → 2^2 = 4:

| isConnected | canEdit | Classification | Render |
|---|---|---|---|
| ✓ | ✓ | real | live view, edit enabled |
| ✓ | ✗ | real | live view, read-only |
| ✗ | ✓ | real — confirmed with plan | offline banner, edit queued/disabled |
| ✗ | ✗ | real | offline banner, read-only |

The tempting `switch(status)` with three branches deletes row 3 — precisely the combination a field user hits first. Four tests, one per row.

## Review checklist

Paste into any multi-flag component review:

- [ ] 1. All N independent boolean inputs identified
- [ ] 2. Full 2^N table enumerated (literally, not sampled)
- [ ] 3. Every `impossible` cites an invariant or an explicit confirmation
- [ ] 4. Unconfirmed combinations treated as real
- [ ] 5. No exclusive switch over a synthetic status collapsing independent axes
- [ ] 6. Content vs actions driven separately by their governing inputs
- [ ] 7. A test per real combination

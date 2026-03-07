# Design: Make Verification Default in Code Review

**Date:** 2026-03-07
**Plugin:** code-review
**Scope:** code-review only (web-auditor unchanged)

## Problem

The `--verify` flag enables Cross-Verifier and Challenger subagents that catch false positives, calibrate severity, and find cross-domain correlations. This should be the default behavior, not opt-in.

## Decision

Remove `--verify` entirely. Verification always runs. No opt-out.

## Approach: Full Cleanup

Remove the flag and all conditional logic. Verification becomes an unconditional part of every review.

### Files to change

| File | Change |
|------|--------|
| `plugins/code-review/commands/review.md` | Remove `--verify` parsing, make verification unconditional |
| `plugins/code-review/.claude-plugin/plugin.json` | Version bump 1.8.0 -> 1.9.0 |
| `.claude-plugin/marketplace.json` | Version bump |
| `docs/plugins/code-review.md` | Remove `--verify` references, describe verification as built-in |
| `README.md` | Update plugin description |

### Changes in `review.md`

1. **argument-hint** (line 5): `[description] [--verify]` -> `[description]`
2. **Argument parsing** (lines 17-18): Remove `--verify` parsing. All text is the review description.
3. **Task creation** (line 100): Remove conditional -- task 6 ("Run verification") is always created. Always 8 tasks.
4. **Step 5.5** (lines 171-241): Remove "if --verify" guards. Rename to "Step 5.5: Verification".
5. **Step 5 task update** (line 342): Remove conditional -- verification always runs.
6. **Verification Summary** (lines 346-367): Remove "(if --verify)" header. Always included.
7. **Final checklist** (lines 557-563): Remove "if --verify" qualifiers. Verification checks always mandatory.

### Changes in docs

- `docs/plugins/code-review.md`: Remove "Verified Review" as separate section. Describe Cross-Verifier + Challenger as part of standard flow. Remove `--verify` from examples.
- `README.md`: Change "Optional `--verify` for cross-analysis..." to "Built-in cross-analysis and adversarial review".

## What does NOT change

- Cross-Verifier agent (`agents/cross-verifier.md`) -- unchanged
- Challenger agent (`agents/challenger.md`) -- unchanged
- Web Auditor plugin -- keeps `--verify` as opt-in
- Fix commands (`fix.md`, `fix-report.md`) -- unaffected
- Issue ID assignment -- unaffected

# Make Verification Default in Code Review — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the `--verify` flag from code-review plugin and make Cross-Verifier + Challenger verification an unconditional part of every review.

**Architecture:**
The code-review `/review` command currently has two paths: standard review (without `--verify`) and verified review (with `--verify`). We're collapsing this to a single path where verification always runs. This eliminates argument parsing, conditional task creation, and conditional step execution. The workflow becomes simpler: review always goes through both Security Auditor → Code Quality Auditor → Cross-Verifier + Challenger → report generation.

**Tech Stack:**
- Markdown command/agent definitions (no code changes)
- Task workflow (task creation, marking progress)
- Subagent spawning (already functional)

---

## Task 1: Update review.md — Argument Parsing

**Files:**
- Modify: `plugins/code-review/commands/review.md:1-25`

**Step 1: Read the current argument parsing section**

The section spans lines 1-25. Current state:
- Line 5: `argument-hint: [description] [--verify]`
- Lines 17-18: Parse `--verify` flag separately from description

**Step 2: Update argument-hint**

Replace line 5:
```
argument-hint: [description]
```

**Step 3: Update argument parsing documentation**

Replace lines 17-18 from:
```
Parse arguments:
- All text before `--verify` is the review description
- `--verify`: enable verification phase with Cross-Verifier and Challenger subagents (default: off)
```

To:
```
Parse arguments:
- All text is the review description
```

**Step 4: Verify changes look correct**

Read lines 1-25 to confirm `--verify` is removed from both hint and docs.

**Step 5: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "feat(code-review): remove --verify flag from argument parsing"
```

---

## Task 2: Update review.md — Task Creation (always create 8 tasks)

**Files:**
- Modify: `plugins/code-review/commands/review.md:83-102`

**Step 1: Review current task creation section**

Lines 83-102 show the task creation table. Currently line 100 says:
```
Note: task 6 is only created if `--verify` is active. Tasks 7-8 are always created.
```

**Step 2: Update the note**

Replace line 100 with:
```
Note: All 8 tasks are always created.
```

**Step 3: Confirm the table is correct**

The task table should show all 8 tasks unconditionally:
1. Launch security & quality auditors
2. Perform performance analysis
3. Perform architecture & maintainability review
4. Collect subagent results
5. Generate final report
6. Run verification (Cross-Verifier + Challenger)
7. Save review to file
8. Display post-review guidance

(Table is already correct as-is, just the note needed updating.)

**Step 4: Verify and commit**

Read lines 83-102 to confirm the note now says all 8 tasks are always created.

```bash
git add plugins/code-review/commands/review.md
git commit -m "docs(code-review): clarify all 8 tasks are always created"
```

---

## Task 3: Update review.md — Step 5.5 Header (remove conditional)

**Files:**
- Modify: `plugins/code-review/commands/review.md:171-175`

**Step 1: Locate the step header**

Line 171: `### Step 5.5: Verification (if --verify)`
Line 173: `**Skip this step if --verify was not provided.** Proceed to report generation.`

**Step 2: Update the header**

Replace line 171 with:
```
### Step 5.5: Verification
```

**Step 3: Remove the skip instruction**

Delete line 173 entirely. Replace lines 173-175 from:
```
**Skip this step if --verify was not provided.** Proceed to report generation.

If --verify is active:
```

To:
```
The verification phase always runs:
```

**Step 4: Verify**

Read lines 171-180 to confirm the skip language is gone and verification is unconditional.

**Step 5: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "docs(code-review): make verification step unconditional"
```

---

## Task 4: Update review.md — Step 5 (task 5 completion logic)

**Files:**
- Modify: `plugins/code-review/commands/review.md:342`

**Step 1: Find the conditional task update**

Line 342 currently reads:
```
**Task Update:** If `--verify` was NOT used, mark task 5 as `completed` using TaskUpdate. (If `--verify` was used, task 5 was already completed in Step 5.5.)
```

**Step 2: Replace with unconditional**

Replace line 342 with:
```
**Task Update:** Task 5 is marked as `completed` at the end of Step 5.5. No action needed here.
```

(Or simpler: remove this line entirely since task 5 completion happens in Step 5.5 automatically now.)

**Step 3: Verify**

Read lines 340-345 to confirm the conditional is gone.

**Step 4: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "docs(code-review): remove conditional task completion logic"
```

---

## Task 5: Update review.md — Verification Summary Header

**Files:**
- Modify: `plugins/code-review/commands/review.md:346`

**Step 1: Locate the header**

Line 346: `## Verification Summary (if --verify)`

**Step 2: Remove conditional**

Replace with:
```
## Verification Summary
```

**Step 3: Verify**

Read lines 346-350 to confirm header is now unconditional.

**Step 4: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "docs(code-review): make verification summary unconditional"
```

---

## Task 6: Update review.md — Final Verification Checklist

**Files:**
- Modify: `plugins/code-review/commands/review.md:557-563`

**Step 1: Locate the verification checklist**

Lines 557-563 contain the "Verification (if --verify)" section with conditional checkboxes.

**Step 2: Remove the conditional header**

Replace line 557 from:
```
### Verification (if --verify)
```

To:
```
### Verification
```

**Step 3: Make all checks mandatory**

Lines 559-562 currently read:
```
- [ ] Cross-Verifier and Challenger subagents spawned and results collected
- [ ] Cross-Verifier correlations integrated
- [ ] Challenger results applied (false positives removed, severity adjusted)
- [ ] Verification Summary included in output
```

These are already unconditional (no "(if --verify)" qualifiers), so no changes needed. They're already mandatory.

**Step 4: Update final note**

After line 563, the checklist ends. Make sure the preceding text (line 550) says verification checks are mandatory:

Current line 550: `**If ANY security or quality checkbox is unchecked: STOP. Complete those steps first.**`

This is correct. Keep it as-is.

**Step 5: Verify and commit**

Read lines 550-563 to confirm verification section header is now unconditional and all checks are mandatory.

```bash
git add plugins/code-review/commands/review.md
git commit -m "docs(code-review): make verification checklist unconditional"
```

---

## Task 7: Update marketplace.json — Version Bump

**Files:**
- Modify: `.claude-plugin/marketplace.json:11`

**Step 1: Read current version**

Line 11 shows: `"version": "1.7.0",`

**Step 2: Bump to 1.9.0**

Replace with: `"version": "1.9.0",`

(Bumping to 1.9.0 because: 1.8.0 was issue IDs feature, 1.9.0 is making verification default — a workflow change.)

**Step 3: Verify**

Read line 11 to confirm version is now 1.9.0.

**Step 4: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "chore(release): bump code-review to v1.9.0"
```

---

## Task 8: Update plugin.json — Version Bump

**Files:**
- Modify: `plugins/code-review/.claude-plugin/plugin.json:11`

**Step 1: Read current version**

Line 11 shows: `"version": "1.7.0",`

**Step 2: Bump to 1.9.0**

Replace with: `"version": "1.9.0",`

**Step 3: Verify**

Read line 11 to confirm version is now 1.9.0.

**Step 4: Commit**

```bash
git add plugins/code-review/.claude-plugin/plugin.json
git commit -m "chore(release): update code-review plugin version to 1.9.0"
```

---

## Task 9: Update docs/plugins/code-review.md — Remove --verify examples

**Files:**
- Modify: `docs/plugins/code-review.md:103-121`

**Step 1: Read the Verified Review section**

Lines 103-121 are the "Verified Review" or verification examples section. Currently shows `--verify` usage.

**Step 2: Locate example lines**

Line 108: `/review "Check authentication security" --verify`
Line 109: `/review --verify`

**Step 3: Remove --verify from examples**

Replace line 108 with:
```
/review "Check authentication security"
```

Replace line 109 with:
```
/review
```

**Step 4: Update descriptive text**

Find text near line 103 that says something like "Add `--verify` to enable..." and replace with language like "Verification is automatically enabled..." or "Every review includes verification..."

**Step 5: Verify**

Read lines 103-121 to confirm --verify is removed from examples and docs describe verification as built-in.

**Step 6: Commit**

```bash
git add docs/plugins/code-review.md
git commit -m "docs(code-review): describe verification as built-in, remove --verify examples"
```

---

## Task 10: Update README.md — Plugin Description

**Files:**
- Modify: `README.md:17`

**Step 1: Read current description**

Line 17 currently reads (approximately):
```
| [Code Review](docs/plugins/code-review.md) | 1.8.0 | Security, architecture, and code quality analysis with OWASP compliance. Unique issue IDs (SEC-001, PERF-001, ...), fix by ID via `/fix SEC-001` or batch via `/fix-report`. Optional `--verify` for cross-analysis and adversarial review |
```

**Step 2: Update version and remove "Optional"**

Replace with:
```
| [Code Review](docs/plugins/code-review.md) | 1.9.0 | Security, architecture, and code quality analysis with OWASP compliance. Built-in cross-analysis and adversarial review via Cross-Verifier + Challenger. Unique issue IDs (SEC-001, PERF-001, ...), fix by ID via `/fix SEC-001` or batch via `/fix-report` |
```

**Step 3: Verify**

Read line 17 to confirm:
- Version is 1.9.0
- "Optional `--verify`" is replaced with "Built-in cross-analysis..."
- Description is clear and concise

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update code-review plugin description (verification now built-in)"
```

---

## Summary of Changes

| File | Changes |
|------|---------|
| `plugins/code-review/commands/review.md` | Remove `--verify` from argument-hint; remove flag parsing; remove "skip if no --verify" logic; make verification unconditional throughout (6 separate commits: Tasks 1-6) |
| `.claude-plugin/marketplace.json` | Bump version 1.7.0 → 1.9.0 |
| `plugins/code-review/.claude-plugin/plugin.json` | Bump version 1.7.0 → 1.9.0 |
| `docs/plugins/code-review.md` | Remove --verify examples; describe verification as built-in |
| `README.md` | Update plugin description and version |

**Total commits:** 10 (one per task)

---

## Execution

This plan uses a straightforward TDD-like workflow:
1. Identify the exact lines to change
2. Make the change
3. Verify the change looks correct (by reading the file)
4. Commit with a clear message

No code to test — these are all documentation/config changes. Verification is by inspection.

All changes are localized to the code-review plugin and marketplace configs. No cross-plugin impacts.

# Design: Unique Issue IDs for Code Review

**Date:** 2026-03-06
**Plugin:** code-review
**Version:** 1.6.0 -> 1.7.0

## Summary

Add unique category-based identifiers to review issues and extend `/fix` to accept an ID for automatic issue lookup from saved reports.

## ID Format

`{CATEGORY}-{NNN}` where:

- `CATEGORY` = `SEC` | `PERF` | `ARCH` | `MAINT`
- `NNN` = zero-padded 3-digit counter, per category, starting at 001

Category mapping:

| Category        | Prefix  |
|-----------------|---------|
| Security        | SEC     |
| Performance     | PERF    |
| Architecture    | ARCH    |
| Maintainability | MAINT   |

## Heading Format

```
Before: ### [HIGH] SQL Injection in User Query
After:  ### [HIGH] SEC-001: SQL Injection in User Query
```

Each issue block also gets an `**ID:**` metadata field for easier parsing:

```markdown
### [HIGH] SEC-001: SQL Injection in User Query

**ID:** SEC-001
**Location:** `src/db/queries.py:42`
**Category:** Security
...
```

## Changes

### 1. `/review` command (review.md)

**New step: "Assign Issue IDs"** — inserted after collecting all findings, before rendering the final report.

1. Collect all issues from: security auditor, quality auditor, own performance/architecture analysis
2. Read each issue's `Category` field
3. Maintain per-category counters: `sec_count=0`, `perf_count=0`, `arch_count=0`, `maint_count=0`
4. Assign ID: increment counter, format as `{PREFIX}-{NNN}`
5. Modify heading to include ID: `### [SEVERITY] {ID}: Title`
6. Add `**ID:** {ID}` line after the heading

**Review Comment Format section** updated to show new format.

**Post-review guidance** updated:

> Found N issues. To fix them:
>
> `/fix-report <path>` — fix multiple issues interactively
>
> `/fix SEC-001` — fix a single issue by ID (uses latest saved report)
>
> `/fix <paste issue block>` — fix by pasting full block

### 2. `/fix` command (fix.md)

**Argument detection** (top of command, before any phases):

- If `$ARGUMENTS` matches `^(SEC|PERF|ARCH|MAINT)-\d{3}$` -> ID mode
- Otherwise -> legacy paste mode (unchanged)

**New Phase 0: Resolve Issue by ID** (ID mode only):

1. Scan `docs/reviews/` for `.md` files
2. Sort by modification time (newest first)
3. Read the most recent file
4. Search for heading containing the ID (e.g., `### [HIGH] SEC-001:`)
5. Extract full issue block (from `###` heading to next `###` or `---` or EOF)
6. If found -> proceed to Phase 1 with extracted block
7. If not found -> error: `Issue {ID} not found in latest report: {path}`

**New Phase 8: Update Report** (ID mode only, after Phase 7: Generate Report):

1. Determine fix status from Phase 7 (Fixed / Partially Fixed / Failed)
2. If Fixed -> insert `**Status:** Fixed (YYYY-MM-DD)` after the issue heading in the report file
3. If Partially Fixed -> insert `**Status:** Partially Fixed (YYYY-MM-DD)` after the heading
4. If Failed -> do not modify the report (issue remains unfixed for next `/fix-report` run)

Same mechanism as `/fix-report` Step 4.1.

**argument-hint** updated: `<issue-id | full issue block>`

Phases 1-7 remain unchanged — they work the same regardless of input source.

### 3. `/fix-report` command (fix-report.md)

Minor update: checklist labels now naturally include IDs since they come from the heading.

```
Before: label: "[HIGH] SQL Injection in User Query"
After:  label: "[HIGH] SEC-001: SQL Injection in User Query"
```

No logic changes required.

### 4. `fix-auto` agent

No changes. Receives full issue block as prompt — ID is informational only.

### 5. Verification mode (`--verify`)

No changes. Cross-Verifier and Challenger work on issue content, not IDs.

### 6. Documentation (docs/plugins/code-review.md)

- Show new ID format in examples
- Document `/fix <ID>` usage
- Update recommended workflow section

### 7. Plugin version bump

`plugin.json`: 1.6.0 -> 1.7.0 (new feature, backward compatible)

## Files to Modify

| File | Change |
|------|--------|
| `plugins/code-review/commands/review.md` | Add ID assignment step, update comment format, update post-review guidance |
| `plugins/code-review/commands/fix.md` | Add argument detection, Phase 0 (ID lookup), Phase 8 (report update) |
| `plugins/code-review/commands/fix-report.md` | No code changes (IDs flow through naturally) |
| `docs/plugins/code-review.md` | Update docs with ID format and `/fix <ID>` usage |
| `plugins/code-review/.claude-plugin/plugin.json` | Version bump to 1.7.0 |

## Backward Compatibility

- `/fix <full issue block>` continues to work (legacy paste mode)
- `/fix-report` continues to work (IDs appear naturally in headings)
- Reports without IDs (from older reviews) still work with `/fix-report` and paste mode
- ID mode in `/fix` only works with saved reports that contain IDs

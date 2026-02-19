# Code Review: Save to File & Auto-Fix Checklist

## Overview

Two enhancements to the `code-review` plugin:

1. **Save review to file** — after generating the report, ask user whether to save it to `docs/reviews/YYYY-MM-DD-<branch-slug>.md`
2. **Auto-fix checklist** — after review, ask user whether to fix detected issues, present a selectable checklist, and run fixes sequentially via a new `fix-auto` agent

## Approach

Extend existing `review.md` with two new steps at the end. Create a new `fix-auto.md` agent (copy of `/fix` without the confirmation phase).

## Design

### Feature 1: Save Review to File

**Trigger:** New Step 6 added after the final report is generated (after current Step 5.5 / Verification Summary), before Final Verification Checklist.

**Flow:**

1. Report is ready (displayed to user)
2. `AskUserQuestion`: "Save review to file?" (yes/no)
3. If **yes**:
   - Detect branch name: `git branch --show-current`
   - Slugify branch name (replace `/` and spaces with `-`, lowercase)
   - Write to `docs/reviews/YYYY-MM-DD-<branch-slug>.md`
   - Confirm: "Review saved to docs/reviews/2026-02-19-feature-login.md"
4. If **no** — proceed

**File format:** Full review report in the same markdown format displayed to the user. No extra metadata.

**Name collisions:** If file already exists, append suffix: `YYYY-MM-DD-<branch-slug>-2.md`.

**Changes:**

- `review.md` — add Step 6: Save Review
- Add `Write` to `allowed-tools` in `review.md`

### Feature 2: Auto-Fix Checklist

**Trigger:** New Step 7 after save review, only if review found any issues.

**Flow:**

1. `AskUserQuestion`: "Fix detected issues?" (yes/no)
2. If **no** — end review
3. If **yes**:
   - `AskUserQuestion` with `multiSelect: true`
   - Options: list of all found issues as `[SEVERITY] Title — path/to/file.py:42`
   - User selects which to fix
4. For each selected issue **sequentially**:
   - Run `fix-auto` subagent (Task tool, `run_in_background: false`)
   - Prompt contains full issue block (same format `/fix` accepts)
   - Wait for completion, proceed to next
5. After all — display summary table

**AskUserQuestion limit:** Max 4 options. If more than 4 issues, group by severity — present CRITICAL/HIGH first, then MEDIUM/LOW in follow-up questions (or list textually and ask for numbers).

**Summary format:**

```markdown
## Fix Summary
| # | Issue | Status |
|---|-------|--------|
| 1 | [HIGH] SQL Injection — src/db.py:28 | Fixed |
| 2 | [MEDIUM] Missing validation — src/api.py:55 | Partially Fixed |
```

### New Agent: `fix-auto.md`

Copy of `fix.md` with **Phase 3 (Propose Fix) removed**. Flow:

1. Phase 1: Parse Issue (unchanged)
2. Phase 2: Analyze Context (unchanged)
3. Phase 3 (was 4): Implement Fix — executed immediately after analysis
4. Phase 4 (was 5): Verify Fix (unchanged)
5. Phase 5 (was 6): Auto-Iterate on Failures (unchanged)
6. Phase 6 (was 7): Generate Report (unchanged)

Not user-facing — exists only in `agents/` and is invoked by `review.md` as a subagent.

## Files Changed

| File | Change |
|------|--------|
| `plugins/code-review/commands/review.md` | Add Step 6 (save) and Step 7 (fix checklist), add `Write` and `AskUserQuestion` to allowed-tools |
| `plugins/code-review/agents/fix-auto.md` | New agent — `/fix` without confirmation phase |
| `plugins/code-review/.claude-plugin/plugin.json` | Bump version to 1.5.0 |

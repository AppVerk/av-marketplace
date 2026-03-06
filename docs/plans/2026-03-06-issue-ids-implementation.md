# Issue IDs for Code Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add unique category-based identifiers (SEC-001, PERF-001, ARCH-001, MAINT-001) to code review issues and extend `/fix` to accept IDs for automatic lookup.

**Architecture:** IDs are assigned during report generation in the `/review` command by grouping issues by category and maintaining per-category counters. The `/fix` command detects whether input is an ID (pattern matching) or a legacy issue block, performs ID lookup if needed, and updates the report with fix status. All changes are backward compatible.

**Tech Stack:** Claude Code commands (markdown), bash for testing, git for commits

**Design Doc:** `docs/plans/2026-03-06-issue-ids-design.md`

---

## Task 1: Update `/review` Command - Add ID Assignment Logic

**Files:**
- Modify: `plugins/code-review/commands/review.md:273-342` (Review Comment Format section and post-review guidance)

**Description:** Add the ID assignment step before final report rendering, update the comment format specification, and update post-review guidance.

**Step 1: Read the current review.md file**

Read the section covering Step 6 (Save Review) to understand where to insert the ID assignment step.

Run: `wc -l plugins/code-review/commands/review.md`
Expected: ~501 lines

**Step 2: Identify insertion point**

The ID assignment step should occur after "Step 5.5: Verification (if --verify)" and before "Step 6: Save Review" (~line 368 based on the current structure).

Read the file to find the exact location where to insert the new step.

**Step 3: Add "Step 5.6: Assign Issue IDs" section**

Insert a new section (before Step 6) that documents the ID assignment logic:

```markdown
## Step 5.6: Assign Issue IDs

Before rendering the final report, assign unique identifiers to each issue based on category.

**Algorithm:**
1. Collect all findings:
   - From security auditor results
   - From code quality auditor results
   - From your own performance analysis (Step 2)
   - From your own architecture analysis (Steps 3-4)

2. Initialize counters for each category:
   - `sec_count = 0` (Security)
   - `perf_count = 0` (Performance)
   - `arch_count = 0` (Architecture)
   - `maint_count = 0` (Maintainability)

3. For each issue (in the order they appear in the report):
   - Read the issue's `Category` field
   - Map category to prefix and counter:
     - "Security" → "SEC", increment sec_count
     - "Performance" → "PERF", increment perf_count
     - "Architecture" → "ARCH", increment arch_count
     - "Maintainability" → "MAINT", increment maint_count
   - Assign ID: `{PREFIX}-{NNN}` (e.g., SEC-001, PERF-001)
   - Modify the issue heading to include the ID
   - Add `**ID:** {ID}` field right after the heading

**Example transformation:**

Before:
```
### [HIGH] SQL Injection in User Query

**Location:** `src/db/queries.py:42`
**Category:** Security
...
```

After:
```
### [HIGH] SEC-001: SQL Injection in User Query

**ID:** SEC-001
**Location:** `src/db/queries.py:42`
**Category:** Security
...
```
```

**Step 4: Update Review Comment Format section**

Find the "## Review Comment Format" section (around line 274 in the original file).

Update the example to show the new format with ID:

```markdown
### [SEVERITY] {ID}: Title of Issue

**ID:** {ID}
**Location:** `path/to/file.py:42`
**Category:** Security | Performance | Architecture | Maintainability
**OWASP:** A05:2025 (if applicable)
**CWE:** CWE-89 (if applicable)
**Effort:** trivial | easy | medium | hard

**Problem:**
Brief description of what's wrong and why it matters.

**Impact:**
What could happen if this isn't fixed.

**Remediation:**

```python
# Before (vulnerable)
cursor.execute(f"SELECT * FROM users WHERE id={user_id}")

# After (secure)
cursor.execute("SELECT * FROM users WHERE id=?", (user_id,))
```
```

**Step 5: Update post-review guidance (Step 7)**

Find the "## Step 7: Post-Review Guidance" section (around line 421).

Update the guidance text for when issues are found AND report was saved:

```markdown
**If issues were found AND report was saved to a file:**

> **Found {N} issues.** To fix them:
>
> `/fix-report <saved-report-path>` — fix multiple issues interactively
>
> `/fix SEC-001` — fix a single issue by ID (uses latest saved report)
>
> `/fix <paste issue block>` — fix a single issue by pasting

**If issues were found but report was NOT saved:**

> **Found {N} issues.** To fix individual issues, use:
>
> `/fix <paste issue block from above>`
>
> To use ID-based fixes or `/fix-report`, save the review first (re-run `/review` and choose to save).
```

**Step 6: Verify edits are correct**

Read the modified sections to ensure:
- New step 5.6 is correctly placed before Step 6
- Comment format shows ID in heading and **ID:** field
- Post-review guidance mentions all three fix methods

**Step 7: Commit changes**

```bash
git add plugins/code-review/commands/review.md
git commit -m "feat(code-review): add ID assignment to /review command

- Assign unique category-based IDs (SEC-001, PERF-001, ARCH-001, MAINT-001)
- Update comment format to include ID in heading and metadata
- Update post-review guidance to document /fix ID usage
- Update argument hints and examples"
```

---

## Task 2: Update `/fix` Command - Add ID Detection and Lookup

**Files:**
- Modify: `plugins/code-review/commands/fix.md:1-6` (header and argument-hint)
- Modify: `plugins/code-review/commands/fix.md:8-20` (top of command, before Phase 1)

**Description:** Add argument detection logic and Phase 0 for ID-based issue lookup from saved reports.

**Step 1: Update command header**

Find the header section of fix.md (lines 1-6):

```yaml
---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(pytest:*), Bash(ruff:*), Bash(mypy:*), Bash(semgrep:*), Bash(npm test:*), Bash(eslint:*), Bash(tsc:*), Bash(bandit:*), Bash(trufflehout:*), Bash(command:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskList
description: Apply fix for a single code review issue with verification and reporting.
model: claude-opus-4-6
argument-hint: <paste full issue block from /review report>
---
```

Update `argument-hint`:

```yaml
argument-hint: <issue-id | full issue block from /review report>
```

**Step 2: Add argument detection logic**

Right after the header (after line 6) and before "# Fix Code Review Issue", add a new section:

```markdown
## Input Handling

Parse the input argument to determine mode:

- **ID Mode:** If input matches pattern `^(SEC|PERF|ARCH|MAINT)-\d{3}$`
  - Examples: `SEC-001`, `PERF-042`, `ARCH-001`, `MAINT-999`
  - Action: Proceed to Phase 0 (Resolve Issue by ID)

- **Legacy Paste Mode:** If input contains `### [` (start of issue heading)
  - Action: Skip Phase 0, proceed to Phase 1 (Parse Issue) with input as-is

This allows backward compatibility: both ID lookup and issue block pasting work.
```

**Step 3: Add Phase 0: Resolve Issue by ID**

Find the section "# Fix Code Review Issue" and the Phase 1 heading (around line 8-20).

Insert a new Phase 0 BEFORE Phase 1:

```markdown
---

## Phase 0: Resolve Issue by ID (ID mode only)

**ONLY execute this phase if argument matches the ID pattern from Input Handling above.**

**Skip this phase if in Legacy Paste Mode.**

### Step 0.1: Locate most recent report

List all `.md` files in `docs/reviews/` directory:

```bash
ls -t docs/reviews/*.md 2>/dev/null | head -1
```

Expected: The most recently modified file, e.g., `docs/reviews/2026-03-06-feature-auth.md`

If no files found, display error:

> Error: No saved review reports found in `docs/reviews/`. Run `/review` and save a report first.

### Step 0.2: Read the report file

Use Read tool to read the most recent report file identified in Step 0.1.

### Step 0.3: Search for the issue by ID

Scan the report for a heading containing the provided ID using a pattern search:

Pattern: `### \[[A-Z]+\] (SEC|PERF|ARCH|MAINT)-\d{3}:`

Search for the specific ID provided in $ARGUMENTS.

Example: If user provided `SEC-001`, search for headings like:
- `### [HIGH] SEC-001: SQL Injection...`
- `### [CRITICAL] SEC-001: ...`
- `### [MEDIUM] SEC-001: ...`

### Step 0.4: Extract the full issue block

Once found, extract the complete issue block:
- Start: the `### [SEVERITY] ID: Title` line
- End: the next `###` heading, or `---` separator, or end of file

Store this block mentally for handoff to Phase 1.

### Step 0.5: Handle not found

If the ID is not found in the report, display error:

> Error: Issue {ID} not found in report: `{report-path}`
>
> Available issues in this report:
> (list up to 5 IDs found in the report)
>
> Use `/fix <paste issue block>` to fix using the full block, or check the report path.

Stop execution here.

### Step 0.6: Proceed to Phase 1

If found, proceed to Phase 1 (Parse Issue) with the extracted issue block as $ARGUMENTS.

The remainder of the fix workflow (Phases 1-7) operates normally, unaware of ID mode.

---
```

**Step 4: Update Phase 1 description**

Update the Phase 1 header to clarify it receives input from either Phase 0 or directly:

```markdown
## Phase 1: Parse Issue

**Input:** Issue block (from Phase 0 ID lookup or directly from user in Legacy Paste Mode)
```

**Step 5: Add Phase 8: Update Report (ID mode only)**

Find the end of Phase 7 (around line 393). Add a new Phase 8 AFTER Phase 7:

```markdown
---

## Phase 8: Update Report (ID mode only)

**ONLY execute this phase if in ID mode (i.e., if Phase 0 was executed).**

**Skip this phase in Legacy Paste Mode (no report file to update).**

This step marks the fixed issue in the saved report so it doesn't appear again in `/fix-report`.

### Step 8.1: Determine fix status

From Phase 7 (Generate Report), the status is one of:
- `Fixed` — all verification passed, issue is resolved
- `Partially Fixed` — main issue is fixed, minor issues remain
- `Failed` — could not fix within 3 iterations

### Step 8.2: Update the report for Fixed status

If status is `Fixed`:

1. Open the report file (same file from Phase 0)
2. Find the issue heading: `### [SEVERITY] ID: Title`
3. Insert immediately after the heading line:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

Use today's date (e.g., 2026-03-06).

Use the Edit tool with:
- `old_string`: the heading line followed by a newline and the first metadata line (e.g., `**ID:**`)
- `new_string`: the same heading line, newline, status line, newline, and the first metadata line

Example:

old_string:
```
### [HIGH] SEC-001: SQL Injection in User Query

**ID:** SEC-001
```

new_string:
```
### [HIGH] SEC-001: SQL Injection in User Query

**Status:** ✅ Fixed (2026-03-06)
**ID:** SEC-001
```

### Step 8.3: Update the report for Partially Fixed status

If status is `Partially Fixed`:

Follow the same process as Step 8.2, but insert:

```
**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)
```

### Step 8.4: Do not update for Failed status

If status is `Failed`:

Do NOT modify the report. Leave the issue unmarked so it appears again in the next `/fix-report` run.

### Step 8.5: Confirm update

After editing the report, display:

> Issue {ID} marked as {Status} in report: `{report-path}`

---

**Task Update:** Mark task 6 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**
```

**Step 6: Verify edits**

Read the modified sections to ensure:
- Argument-hint updated to show both modes
- Input Handling section clearly explains ID vs paste mode detection
- Phase 0 is complete with all steps
- Phase 8 is added with Fixed/Partially Fixed/Failed handling
- Original Phases 1-7 are unchanged

**Step 7: Commit changes**

```bash
git add plugins/code-review/commands/fix.md
git commit -m "feat(code-review): add ID-based lookup to /fix command

- Add argument detection: ID pattern (SEC-001) vs legacy paste mode
- Add Phase 0: ID resolution - find issue in latest saved report
- Add Phase 8: Report update - mark fixed issues in saved report
- Maintain backward compatibility with full block pasting
- Support both Fixed and Partially Fixed status tracking"
```

---

## Task 3: Minor Update to `/fix-report` Command (No Logic Changes)

**Files:**
- Modify: `plugins/code-review/commands/fix-report.md` (documentation only, no code changes needed)

**Description:** Update documentation to explain that IDs now appear in the checklist naturally.

**Step 1: Read fix-report.md**

Check the current documentation around Step 2 (Present Issue Checklist).

**Step 2: Add note about IDs**

In the "## Step 2: Present Issue Checklist" section, add a clarification after Step 2.2:

```markdown
**IDs in checklist:**

Issues now include their unique ID in the checklist labels. For example:

```
- label: "[HIGH] SEC-001: SQL Injection in User Query"
- description: "src/db/queries.py:42 — Code directly concatenates user input into SQL"
```

This makes it easy to reference issues when using `/fix SEC-001` directly.
```

**Step 3: Verify no code logic changes needed**

Confirm that the checklist presentation logic in Step 2 automatically includes IDs because they're part of the issue heading. No changes to the actual checklist generation logic are required.

**Step 4: Commit changes**

```bash
git add plugins/code-review/commands/fix-report.md
git commit -m "docs(code-review): clarify ID display in /fix-report checklist"
```

---

## Task 4: Update Plugin Documentation

**Files:**
- Modify: `docs/plugins/code-review.md` (Commands section and examples)

**Description:** Update user-facing documentation to show the new ID format and `/fix <ID>` usage.

**Step 1: Read the current documentation**

Review the Commands section, particularly:
- `/review` examples
- `/fix` examples
- Recommended workflow

**Step 2: Update `/fix` command documentation**

Find the `/fix` section in `docs/plugins/code-review.md`. Update it to:

```markdown
### `/fix`

Apply a fix for a single issue from a review report. Supports two modes:

**ID mode** — specify the issue ID directly:

```bash
/fix SEC-001
/fix PERF-042
```

The plugin automatically finds the most recent saved report, locates the issue by ID, and proceeds with the fix. After fixing, the issue is marked as fixed in the report.

**Legacy mode** — paste the full issue block:

```bash
/fix <paste full issue block from /review report>
```

The fix proceeds with the pasted content. No report file is updated (useful when working without saved reports).

**How it works:**

1. Parse issue or ID
2. If ID: locate in latest saved report (from `docs/reviews/`)
3. Analyze code context
4. Propose fix (waits for your approval)
5. Implement fix with verification (linters, type checks, tests)
6. Report results
7. If ID mode: update report to mark issue as fixed
```

**Step 3: Update recommended workflow**

Find the "Recommended workflow" section and update it:

```markdown
**Recommended workflow:**

1. Run `/review` and save the report
2. Review the issues found
3. Fix using one of these methods:
   - `/fix-report docs/reviews/2026-02-20-feature-login.md` — fix multiple issues interactively
   - `/fix SEC-001` — fix a single issue by ID (uses latest report)
   - `/fix <paste issue block>` — fix by pasting the full issue block
4. Re-run `/fix-report` on the same file to fix remaining issues
```

**Step 4: Update example output**

In the `/review` section, add an example showing the new ID format in the output:

```markdown
### Example Output

```
### [HIGH] SEC-001: SQL Injection in User Query

**ID:** SEC-001
**Location:** `src/db/queries.py:42`
**Category:** Security
**OWASP:** A05:2025
**CWE:** CWE-89
**Effort:** medium

**Problem:**
User input is directly concatenated into SQL queries, allowing SQL injection attacks.

**Impact:**
Attackers can read, modify, or delete database records without authentication.

**Remediation:**

Before (vulnerable):
```python
cursor.execute(f"SELECT * FROM users WHERE id={user_id}")
```

After (secure):
```python
cursor.execute("SELECT * FROM users WHERE id=?", (user_id,))
```
```

**Step 5: Verify changes**

Read the updated documentation to ensure:
- ID format is clearly explained
- Both ID mode and legacy mode are documented
- Examples show the new ID format
- Workflow section mentions `/fix <ID>` as an option

**Step 6: Commit changes**

```bash
git add docs/plugins/code-review.md
git commit -m "docs(code-review): document issue IDs and /fix ID mode

- Explain ID format (SEC-001, PERF-001, ARCH-001, MAINT-001)
- Document /fix ID mode for direct issue lookup
- Update recommended workflow
- Add example showing ID in output"
```

---

## Task 5: Update Plugin Metadata

**Files:**
- Modify: `plugins/code-review/.claude-plugin/plugin.json`

**Description:** Bump version to 1.7.0 and update changelog (if present).

**Step 1: Read plugin.json**

Check the current version and structure:

```json
{
  "version": "1.6.0",
  ...
}
```

**Step 2: Update version**

Change `"version": "1.6.0"` to `"version": "1.7.0"`

**Step 3: Update README in marketplace**

Find `plugins/code-review/README.md` or check if version is listed in main `README.md`.

Update the version number in the plugin table (if present):

```markdown
| [Code Review](docs/plugins/code-review.md) | 1.7.0 | ... |
```

**Step 4: Commit changes**

```bash
git add plugins/code-review/.claude-plugin/plugin.json README.md
git commit -m "chore(release): bump code-review plugin to v1.7.0

Features:
- Add unique category-based issue IDs (SEC-001, PERF-001, ARCH-001, MAINT-001)
- Extend /fix to accept ID for automatic lookup from saved reports
- Auto-update report status when fixing by ID"
```

---

## Summary

**Total commits:** 5

1. Add ID assignment to `/review` command
2. Add ID detection and Phase 0/8 to `/fix` command
3. Clarify IDs in `/fix-report` documentation
4. Update user-facing documentation
5. Bump version to 1.7.0

**Testing approach:** Manual testing with real review workflows (see execution notes).

**Backward compatibility:** Full ✅
- `/fix <full block>` continues to work
- `/fix-report` continues to work
- Reports without IDs still work with `/fix-report` and paste mode
- Only ID mode requires recent reports with IDs

---

## Execution Notes

After each task, test by:

1. Running `/review` on a sample repository
2. Saving the report to `docs/reviews/`
3. Verifying IDs appear in the format `{CATEGORY}-{NNN}`
4. Testing `/fix SEC-001` (ID mode)
5. Testing `/fix <paste block>` (legacy mode)
6. Verifying issue is marked fixed in the report
7. Running `/fix-report` to confirm marked issues don't reappear

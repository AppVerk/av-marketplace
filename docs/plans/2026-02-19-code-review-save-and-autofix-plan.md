# Code Review: Save to File & Auto-Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add two features to the code-review plugin: save review reports to `docs/reviews/` and offer a selectable checklist to auto-fix detected issues.

**Architecture:** Extend `review.md` with two new steps at the end of the workflow. Create a new `fix-auto.md` agent (derived from `fix.md` but without the user confirmation phase) that runs as a subagent invoked sequentially per selected issue.

**Tech Stack:** Claude Code plugins (markdown commands/agents), AskUserQuestion tool, Task tool for subagent orchestration.

---

### Task 1: Create `fix-auto.md` agent

**Files:**
- Source: `plugins/code-review/commands/fix.md` (read-only reference)
- Create: `plugins/code-review/agents/fix-auto.md`

**Step 1: Create the agent file**

Copy `fix.md` to `agents/fix-auto.md` with these modifications:

1. **Frontmatter** — change to agent frontmatter (no `argument-hint`, no `description` as command):

```yaml
---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(pytest:*), Bash(ruff:*), Bash(mypy:*), Bash(semgrep:*), Bash(npm test:*), Bash(eslint:*), Bash(tsc:*), Bash(bandit:*), Bash(trufflehog:*), Bash(command:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskList
---
```

2. **Title** — change from `# Fix Code Review Issue` to `# Auto-Fix Code Review Issue`

3. **Description** — add a line: `You are invoked as a subagent by the review command. You do NOT ask for user confirmation — you proceed directly from analysis to implementation.`

4. **Remove Phase 3: Propose Fix entirely** (lines containing Phase 3 header through the "CRITICAL: Wait for explicit user approval" section)

5. **Renumber remaining phases:**
   - Phase 4 → Phase 3 (Implement Fix)
   - Phase 5 → Phase 4 (Verify Fix)
   - Phase 6 → Phase 5 (Auto-Iterate on Failures)
   - Phase 7 → Phase 6 (Generate Report)

6. **Phase 3 (was 4): Implement Fix** — remove the line `**Only proceed after user approval.**`

7. **Progress tasks table** — update to reflect 5 phases instead of 6:

```markdown
| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse issue | Parsing issue... |
| 2 | Analyze context | Analyzing code context... |
| 3 | Implement fix | Implementing fix... |
| 4 | Verify fix | Verifying fix... |
| 5 | Generate report | Generating report... |
```

8. **All TaskUpdate references** — renumber to match new phase numbers (task 3 `in_progress` after Phase 2 completes, etc.)

**Step 2: Verify the file**

Read `plugins/code-review/agents/fix-auto.md` and confirm:
- No mention of "user approval" or "Wait for explicit user approval"
- No Phase 3 "Propose Fix"
- Phases are numbered 1-6 sequentially
- Progress tasks table has 5 rows
- All TaskUpdate references use correct task numbers

**Step 3: Commit**

```bash
git add plugins/code-review/agents/fix-auto.md
git commit -m "feat(code-review): add fix-auto agent for non-interactive auto-fix"
```

---

### Task 2: Update `review.md` allowed-tools

**Files:**
- Modify: `plugins/code-review/commands/review.md:2` (allowed-tools line)

**Step 1: Add new tools to frontmatter**

Add `Write, AskUserQuestion, Task` to the existing `allowed-tools` line in `review.md`. The `Task` tool is already implicitly available (used for subagents), but `Write` and `AskUserQuestion` need to be added explicitly.

Current allowed-tools line (line 2):
```
allowed-tools: Bash(gh issue view:*), ..., Bash(python:*), Bash(node:*), TaskCreate, TaskUpdate, TaskList
```

Add at the end, before the line break:
```
, Write, AskUserQuestion, Task
```

**Step 2: Verify**

Read line 2 of `review.md` and confirm `Write`, `AskUserQuestion`, and `Task` are present.

**Step 3: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "feat(code-review): add Write, AskUserQuestion, Task to review allowed-tools"
```

---

### Task 3: Update `review.md` progress tasks table

**Files:**
- Modify: `plugins/code-review/commands/review.md:62-73` (progress tasks table)

**Step 1: Add two new tasks to the table**

Add rows 7 and 8 to the progress tasks table (after row 6):

```markdown
| 7 | Save review to file | Saving review to file... |
| 8 | Fix selected issues | Fixing selected issues... |
```

The full table becomes:

```markdown
| # | subject | activeForm |
|---|---------|-----------|
| 1 | Launch security & quality auditors | Launching security & quality auditors... |
| 2 | Perform performance analysis | Analyzing performance... |
| 3 | Perform architecture & maintainability review | Reviewing architecture & maintainability... |
| 4 | Collect subagent results | Collecting subagent results... |
| 5 | Generate final report | Generating final report... |
| 6 | Run verification (Cross-Verifier + Challenger) | Running verification... |
| 7 | Save review to file | Saving review to file... |
| 8 | Fix selected issues | Fixing selected issues... |
```

Update the note below the table:

```markdown
Note: task 6 is only created if `--verify` is active. Tasks 7-8 are always created.
```

**Step 2: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "feat(code-review): add save and fix tasks to progress table"
```

---

### Task 4: Add Step 6 — Save Review to `review.md`

**Files:**
- Modify: `plugins/code-review/commands/review.md` (insert after Verification Summary section, before Final Verification Checklist)

**Step 1: Insert Step 6 content**

Insert the following block after line 341 (`---` after Verification Summary) and before line 343 (`## Final Verification Checklist`):

```markdown
## Step 6: Save Review

**Task Update:** Mark task 7 as `in_progress` using TaskUpdate.

After the review report has been displayed, ask whether to save it:

Use AskUserQuestion with these parameters:
- question: "Save this review to a file?"
- options:
  - label: "Yes", description: "Save review report to docs/reviews/"
  - label: "No", description: "Skip saving"
- multiSelect: false

**If user selects "Yes":**

1. Get current branch name:

```bash
git branch --show-current
```

2. Slugify the branch name:
   - Replace `/` with `-`
   - Replace spaces with `-`
   - Convert to lowercase
   - Example: `feature/user-login` → `feature-user-login`

3. Build the file path: `docs/reviews/YYYY-MM-DD-<branch-slug>.md`
   - Use today's date
   - Example: `docs/reviews/2026-02-19-feature-user-login.md`

4. Check if the file already exists. If it does, append a numeric suffix:
   - `docs/reviews/2026-02-19-feature-user-login-2.md`
   - Increment until a non-existing filename is found

5. Create the `docs/reviews/` directory if it doesn't exist:

```bash
mkdir -p docs/reviews
```

6. Write the full review report (the same markdown content displayed to the user) to the file using the Write tool.

7. Confirm to the user: "Review saved to `docs/reviews/2026-02-19-feature-user-login.md`"

**If user selects "No":** Proceed to Step 7.

**Task Update:** Mark task 7 as `completed` using TaskUpdate.

---
```

**Step 2: Verify**

Read the modified `review.md` and confirm Step 6 appears between the Verification Summary and the Final Verification Checklist.

**Step 3: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "feat(code-review): add Step 6 — save review to file"
```

---

### Task 5: Add Step 7 — Fix Issues Checklist to `review.md`

**Files:**
- Modify: `plugins/code-review/commands/review.md` (insert after Step 6, before Final Verification Checklist)

**Step 1: Insert Step 7 content**

Insert the following block after Step 6 and before `## Final Verification Checklist`:

```markdown
## Step 7: Fix Selected Issues

**Skip this step if no issues were found during the review.**

**Task Update:** Mark task 8 as `in_progress` using TaskUpdate.

### Step 7.1: Ask whether to fix issues

Use AskUserQuestion with these parameters:
- question: "Do you want to fix any of the detected issues?"
- options:
  - label: "Yes", description: "Select issues to auto-fix"
  - label: "No", description: "Skip fixing"
- multiSelect: false

**If user selects "No":** Mark task 8 as `completed` and proceed to Final Verification Checklist.

### Step 7.2: Present issues checklist

**If 4 or fewer issues:**

Use AskUserQuestion with these parameters:
- question: "Which issues should be fixed?"
- multiSelect: true
- options: one per issue, formatted as:
  - label: "[SEVERITY] Short title"
  - description: "path/to/file.py:line — brief problem description"

**If more than 4 issues:**

Present issues as a numbered text list grouped by severity (CRITICAL first, then HIGH, MEDIUM, LOW):

```
Issues found:

1. [CRITICAL] SQL Injection — src/db.py:28
2. [HIGH] Missing auth check — src/api.py:55
3. [HIGH] XSS vulnerability — src/templates.py:12
4. [MEDIUM] Unused import — src/utils.py:3
5. [LOW] Naming convention — src/models.py:88

Enter the numbers of issues to fix (e.g. 1,2,3 or 1-3 or "all"):
```

Wait for user response and parse selection.

### Step 7.3: Run auto-fix for each selected issue

For each selected issue, **sequentially** (one at a time, wait for completion):

1. Use the Task tool with these parameters:
   - subagent_type: "code-review:fix-auto"
   - run_in_background: false
   - description: "Auto-fix: [SEVERITY] Issue title"
   - prompt: The full issue block in the review comment format (including all fields: severity, title, location, category, OWASP, CWE, effort, problem, impact, remediation with code examples)

2. Collect the result (status: Fixed / Partially Fixed / Failed)

3. Proceed to the next issue

### Step 7.4: Display fix summary

After all selected issues have been processed, display:

```markdown
## Fix Summary

| # | Issue | Status |
|---|-------|--------|
| 1 | [SEVERITY] Title — path:line | STATUS_ICON STATUS_TEXT |
| 2 | [SEVERITY] Title — path:line | STATUS_ICON STATUS_TEXT |

**Fixed:** N | **Partially Fixed:** N | **Failed:** N
```

Status icons: Fixed = ✅, Partially Fixed = ⚠️, Failed = ❌

**Task Update:** Mark task 8 as `completed` using TaskUpdate.

---
```

**Step 2: Verify**

Read the modified `review.md` and confirm:
- Step 7 appears after Step 6 and before Final Verification Checklist
- AskUserQuestion parameters are correct
- fix-auto subagent is referenced with correct subagent_type

**Step 3: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "feat(code-review): add Step 7 — fix issues checklist with auto-fix"
```

---

### Task 6: Add save/fix items to Final Verification Checklist

**Files:**
- Modify: `plugins/code-review/commands/review.md` (Final Verification Checklist section)

**Step 1: Add new checklist section**

After the `### Completeness` section (and its checkboxes), before `**If ANY security or quality checkbox is unchecked...**`, add:

```markdown
### Post-Review Actions

- [ ] User asked whether to save review
- [ ] Review saved to `docs/reviews/` (if requested)
- [ ] User asked whether to fix issues (if issues found)
- [ ] Selected issues processed via fix-auto subagent (if requested)
- [ ] Fix summary displayed (if fixes were run)
```

**Step 2: Commit**

```bash
git add plugins/code-review/commands/review.md
git commit -m "feat(code-review): add post-review actions to verification checklist"
```

---

### Task 7: Bump plugin version

**Files:**
- Modify: `plugins/code-review/.claude-plugin/plugin.json`

**Step 1: Update version**

Change `"version": "1.4.0"` to `"version": "1.5.0"`.

**Step 2: Commit**

```bash
git add plugins/code-review/.claude-plugin/plugin.json
git commit -m "chore(code-review): bump version to 1.5.0"
```

---

### Task 8: Update documentation

**Files:**
- Modify: `docs/plugins/code-review.md`
- Modify: `README.md`

**Step 1: Read current docs**

Read `docs/plugins/code-review.md` to understand current structure.

**Step 2: Add documentation for new features**

Add a section describing:
- Save review to file (Step 6)
- Auto-fix checklist (Step 7)
- The `fix-auto` agent (internal, not user-facing)

**Step 3: Update README.md version**

Update the Code Review row in the plugins table to reflect version 1.5.0 and mention new capabilities.

**Step 4: Commit**

```bash
git add docs/plugins/code-review.md README.md
git commit -m "docs(code-review): document save-to-file and auto-fix features"
```

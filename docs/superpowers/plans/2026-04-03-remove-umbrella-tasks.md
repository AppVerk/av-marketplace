# Remove Umbrella Tasks from Developer Agents - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove process-phase tasks ("TDD cycle", "Quality gates", "Generate report") from developer agent TaskCreate lists across three agent definitions.

**Architecture:** Each of the three agent files (python-developer, frontend-developer, php-developer) follows identical structure. Changes are mechanical: reduce the task table from 6 to 3 rows, update one TaskUpdate instruction in Phase 3, remove three TaskUpdate blocks from Phases 4-6.

**Tech Stack:** Markdown editing only — no code changes, no testing required.

---

## File Structure

Three agent definition files will be modified identically:

1. `plugins/python-developer/agents/developer.md` — Phase 1, Phase 3, Phase 4, Phase 5, Phase 6
2. `plugins/frontend-developer/agents/developer.md` — Phase 1, Phase 3, Phase 4, Phase 5, Phase 6
3. `plugins/php-developer/agents/developer.md` — Phase 1, Phase 3, Phase 4, Phase 5, Phase 6

Each file is ~320 lines. Changes are isolated to specific sections with clear delimiters.

---

### Task 1: Modify Python Developer Agent

**Files:**
- Modify: `plugins/python-developer/agents/developer.md:30-36, :58, :214, :248, :277`

- [ ] **Step 1: Read the file**

Run: `cat plugins/python-developer/agents/developer.md | head -250 | tail -230`

Note the 6-row task table at line 30-36, the TaskUpdate at line 58 (Phase 1 end), line 214 (Phase 3 end), line 248 (Phase 4 end), and line 277 (Phase 5 end).

- [ ] **Step 2: Update task table in Phase 1**

Replace the 6-row table (lines 30-36):

```markdown
| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse input & detect mode | Parsing input... |
| 2 | Load coding standards & detect stack | Loading standards... |
| 3 | Load stack-specific skills | Loading skills... |
| 4 | TDD cycle | Running TDD cycle... |
| 5 | Quality gates | Running quality gates... |
| 6 | Generate report | Generating report... |
```

With:

```markdown
| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse input & detect mode | Parsing input... |
| 2 | Load coding standards & detect stack | Loading standards... |
| 3 | Load stack-specific skills | Loading skills... |
```

- [ ] **Step 3: Update Phase 3 TaskUpdate instruction**

Find at line ~214: `**Task Update:** Mark task 3 as \`completed\` and task 4 as \`in_progress\` using TaskUpdate.`

Replace with: `**Task Update:** Mark task 3 as \`completed\` using TaskUpdate.`

- [ ] **Step 4: Remove Phase 4 TaskUpdate block**

Find at line ~248: `**Task Update:** Mark task 4 as \`completed\` and task 5 as \`in_progress\` using TaskUpdate.`

Delete the entire paragraph.

- [ ] **Step 5: Remove Phase 5 TaskUpdate block**

Find at line ~277: `**Task Update:** Mark task 5 as \`completed\` and task 6 as \`in_progress\` using TaskUpdate.`

Delete the entire paragraph.

- [ ] **Step 6: Remove Phase 6 TaskUpdate block**

Find at line ~320: `**Task Update:** Mark task 6 as \`completed\` using TaskUpdate.`

Delete the entire paragraph.

- [ ] **Step 7: Verify changes**

Run: `diff -u <(git show HEAD:plugins/python-developer/agents/developer.md) plugins/python-developer/agents/developer.md`

Expected: Shows 4 changes (task table reduced, one TaskUpdate modified, three TaskUpdate blocks removed).

- [ ] **Step 8: Commit**

```bash
git add plugins/python-developer/agents/developer.md
git commit -m "refactor(python-developer): remove umbrella tasks from developer agent"
```

---

### Task 2: Modify Frontend Developer Agent

**Files:**
- Modify: `plugins/frontend-developer/agents/developer.md:27-33, :58, :179, :213, :243`

- [ ] **Step 1: Read the file**

Run: `cat plugins/frontend-developer/agents/developer.md | head -250 | tail -230`

Note locations of task table, Phase 3 end, Phase 4 end, and Phase 5 end.

- [ ] **Step 2: Update task table in Phase 1**

Replace the 6-row table (lines 27-33) with the 3-row version (same as Task 1):

```markdown
| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse input & detect mode | Parsing input... |
| 2 | Load coding standards & detect stack | Loading standards... |
| 3 | Load stack-specific skills | Loading skills... |
```

- [ ] **Step 3: Update Phase 3 TaskUpdate instruction**

Find: `**Task Update:** Mark task 3 as \`completed\` and task 4 as \`in_progress\` using TaskUpdate.`

Replace with: `**Task Update:** Mark task 3 as \`completed\` using TaskUpdate.`

- [ ] **Step 4: Remove Phase 4 TaskUpdate block**

Find: `**Task Update:** Mark task 4 as \`completed\` and task 5 as \`in_progress\` using TaskUpdate.`

Delete entire paragraph.

- [ ] **Step 5: Remove Phase 5 TaskUpdate block**

Find: `**Task Update:** Mark task 5 as \`completed\` and task 6 as \`in_progress\` using TaskUpdate.`

Delete entire paragraph.

- [ ] **Step 6: Remove Phase 6 TaskUpdate block**

Find: `**Task Update:** Mark task 6 as \`completed\` using TaskUpdate.`

Delete entire paragraph.

- [ ] **Step 7: Verify changes**

Run: `diff -u <(git show HEAD:plugins/frontend-developer/agents/developer.md) plugins/frontend-developer/agents/developer.md`

Expected: Shows 4 changes (task table reduced, one TaskUpdate modified, three TaskUpdate blocks removed).

- [ ] **Step 8: Commit**

```bash
git add plugins/frontend-developer/agents/developer.md
git commit -m "refactor(frontend-developer): remove umbrella tasks from developer agent"
```

---

### Task 3: Modify PHP Developer Agent

**Files:**
- Modify: `plugins/php-developer/agents/developer.md:26-32, :58, :170, :204, :242`

- [ ] **Step 1: Read the file**

Run: `cat plugins/php-developer/agents/developer.md | head -250 | tail -230`

Note locations of task table, Phase 3 end, Phase 4 end, and Phase 5 end.

- [ ] **Step 2: Update task table in Phase 1**

Replace the 6-row table (lines 26-32) with the 3-row version (same as Task 1):

```markdown
| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse input & detect mode | Parsing input... |
| 2 | Load coding standards & detect stack | Loading standards... |
| 3 | Load stack-specific skills | Loading skills... |
```

- [ ] **Step 3: Update Phase 3 TaskUpdate instruction**

Find: `**Task Update:** Mark task 3 as \`completed\` and task 4 as \`in_progress\` using TaskUpdate.`

Replace with: `**Task Update:** Mark task 3 as \`completed\` using TaskUpdate.`

- [ ] **Step 4: Remove Phase 4 TaskUpdate block**

Find: `**Task Update:** Mark task 4 as \`completed\` and task 5 as \`in_progress\` using TaskUpdate.`

Delete entire paragraph.

- [ ] **Step 5: Remove Phase 5 TaskUpdate block**

Find: `**Task Update:** Mark task 5 as \`completed\` and task 6 as \`in_progress\` using TaskUpdate.`

Delete entire paragraph.

- [ ] **Step 6: Remove Phase 6 TaskUpdate block**

Find: `**Task Update:** Mark task 6 as \`completed\` using TaskUpdate.`

Delete entire paragraph.

- [ ] **Step 7: Verify changes**

Run: `diff -u <(git show HEAD:plugins/php-developer/agents/developer.md) plugins/php-developer/agents/developer.md`

Expected: Shows 4 changes (task table reduced, one TaskUpdate modified, three TaskUpdate blocks removed).

- [ ] **Step 8: Commit**

```bash
git add plugins/php-developer/agents/developer.md
git commit -m "refactor(php-developer): remove umbrella tasks from developer agent"
```

---

### Task 4: Verify and Consolidate

**Files:**
- No files created or modified (verification only)

- [ ] **Step 1: Verify task tables are consistent**

Run: `for f in plugins/*/agents/developer.md; do echo "=== $f ==="; grep -A 5 "subject | activeForm" "$f" | head -7; done`

Expected: All three files show identical 3-row task tables.

- [ ] **Step 2: Verify TaskUpdate removals**

Run: `for f in plugins/*/agents/developer.md; do echo "=== $f ==="; grep -c "Task Update" "$f"; done`

Expected: Each file shows fewer TaskUpdate blocks than before (should be ~3 per file: Phase 1 end, Phase 2 end, Phase 3 end).

---

## Execution Notes

- No testing required — these are configuration changes
- All three tasks follow identical patterns — can be done in any order or in parallel
- Verify step in Task 4 ensures consistency across all three files

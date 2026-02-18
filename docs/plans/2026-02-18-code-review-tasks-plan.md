# Code Review Tasks Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add TaskCreate/TaskUpdate progress tracking to `/review` and `/fix` commands in the code-review plugin.

**Architecture:** Commands create all tasks upfront at the start of their workflow, then update status (in_progress/completed) at each phase transition. Subagents and skills remain unchanged — only the two command files are modified.

**Tech Stack:** Claude Code plugin system (markdown prompt files with YAML frontmatter)

---

### Task 1: Add Task tools to `/review` frontmatter

**Files:**
- Modify: `plugins/code-review/commands/review.md:2`

**Step 1: Add TaskCreate, TaskUpdate, TaskList to allowed-tools**

In `plugins/code-review/commands/review.md` line 2, append to the end of the `allowed-tools` value:

```
, TaskCreate, TaskUpdate, TaskList
```

The line currently ends with `Bash(node:*)`. After the change it should end with `Bash(node:*), TaskCreate, TaskUpdate, TaskList`.

**Step 2: Commit**

Use `/commit:commit --no-coauthor`

---

### Task 2: Add task creation to `/review` workflow

**Files:**
- Modify: `plugins/code-review/commands/review.md`

**Step 1: Add task creation instructions after the subagent launch section**

After the existing section `## MANDATORY FIRST STEP: Launch TWO Subagents` (which ends at the line `**If you only launch one agent, the review is INCOMPLETE.**`), insert a new section:

```markdown

---

## MANDATORY SECOND STEP: Create Progress Tasks

**Immediately after launching both subagents, create ALL progress tasks:**

Use TaskCreate for each of the following (in a single response, all 5 tasks):

| # | subject | activeForm |
|---|---------|------------|
| 1 | Launch security & quality auditors | Launching security & quality auditors... |
| 2 | Perform performance analysis | Analyzing performance... |
| 3 | Perform architecture & maintainability review | Reviewing architecture & maintainability... |
| 4 | Collect subagent results | Collecting subagent results... |
| 5 | Generate final report | Generating final report... |

**After creating all tasks:** Immediately mark task 1 as `completed` (auditors are already launched) and task 2 as `in_progress`.
```

**Step 2: Add TaskUpdate calls to each workflow step**

Find `### Step 2: Performance Analysis` (around line 63). Insert before it:

```markdown
**Task Update:** Mark task 2 as `in_progress` using TaskUpdate.

```

Find `### Step 3: Architecture Analysis` (around line 73). Insert before it:

```markdown
**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

```

Find `### Step 4: Maintainability & Testing` (around line 82). This step is part of task 3 (merged with architecture). No new task update needed here.

Find `### Step 5: Retrieve Subagent Results (MANDATORY)` (around line 91). Insert before it:

```markdown
**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

```

After the line `**Integrate ALL findings from both subagents into final review. DO NOT skip this step.**` (around line 109), insert:

```markdown

**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.
```

**Step 3: Add final task completion at the end of the report section**

Find the `## Final Verification Checklist` section (around line 211). Insert before it:

```markdown
**Task Update:** After generating the report, mark task 5 as `completed` using TaskUpdate.

---

```

**Step 4: Commit**

Use `/commit:commit --no-coauthor`

---

### Task 3: Add Task tools to `/fix` frontmatter

**Files:**
- Modify: `plugins/code-review/commands/fix.md:2`

**Step 1: Add TaskCreate, TaskUpdate, TaskList to allowed-tools**

In `plugins/code-review/commands/fix.md` line 2, append to the end of the `allowed-tools` value:

```
, TaskCreate, TaskUpdate, TaskList
```

The line currently ends with `Bash(jq:*)`. After the change it should end with `Bash(jq:*), TaskCreate, TaskUpdate, TaskList`.

**Step 2: Commit**

Use `/commit:commit --no-coauthor`

---

### Task 4: Add task creation to `/fix` workflow

**Files:**
- Modify: `plugins/code-review/commands/fix.md`

**Step 1: Add task creation instructions at the start of Phase 1**

Find `## Phase 1: Parse Issue` (around line 22). Insert after the heading line and before `Extract the following fields`:

```markdown

**FIRST: Create ALL progress tasks using TaskCreate:**

| # | subject | activeForm |
|---|---------|------------|
| 1 | Parse issue | Parsing issue... |
| 2 | Analyze context | Analyzing code context... |
| 3 | Propose fix | Proposing fix... |
| 4 | Implement fix | Implementing fix... |
| 5 | Verify fix | Verifying fix... |
| 6 | Generate report | Generating report... |

**After creating all tasks:** Mark task 1 as `in_progress` using TaskUpdate.

```

**Step 2: Add TaskUpdate calls to each phase transition**

Find `## Phase 2: Analyze Context` (around line 49). Insert before it:

```markdown
**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

```

Find `## Phase 3: Propose Fix` (around line 89). Insert before it:

```markdown
**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

```

Find `## Phase 4: Implement Fix` (around line 131). Insert before it:

```markdown
**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

```

Find `## Phase 5: Verify Fix` (around line 161). Insert before it:

```markdown
**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.

```

Find `## Phase 6: Auto-Iterate on Failures` (around line 224). No separate task update — phase 6 is part of task 5 (verify fix).

Find `## Phase 7: Generate Report` (around line 269). Insert before it:

```markdown
**Task Update:** Mark task 5 as `completed` and task 6 as `in_progress` using TaskUpdate.

```

**Step 3: Add final task completion at the end**

Find `**Changes remain uncommitted for your control.**` (last line). Insert before it:

```markdown
**Task Update:** Mark task 6 as `completed` using TaskUpdate.

```

**Step 4: Commit**

Use `/commit:commit --no-coauthor`

---

### Task 5: Update plugin version

**Files:**
- Modify: `plugins/code-review/.claude-plugin/plugin.json`
- Modify: `README.md` (version in table)

**Step 1: Read current plugin.json**

Read `plugins/code-review/.claude-plugin/plugin.json` and bump the patch version (e.g. `1.2.4` → `1.3.0` since this is a minor feature addition).

**Step 2: Update plugin.json version**

Change the `"version"` field to the new version.

**Step 3: Update README.md version**

In `README.md`, find the Code Review row in the plugins table and update the version number to match.

**Step 4: Commit**

Use `/commit:commit --no-coauthor`

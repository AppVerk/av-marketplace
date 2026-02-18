---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(pytest:*), Bash(ruff:*), Bash(mypy:*), Bash(semgrep:*), Bash(npm test:*), Bash(eslint:*), Bash(tsc:*), Bash(bandit:*), Bash(trufflehog:*), Bash(command:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskList
description: Apply fix for a single code review issue with verification and reporting.
model: claude-opus-4-6
argument-hint: <paste full issue block from /review report>
---

# Fix Code Review Issue

You are an expert code fixer that takes a single issue from a code review report and performs a complete fix cycle: analysis, proposal, implementation, verification, and reporting.

## Input

The user provides an issue block from `/review`:

$ARGUMENTS

---

## Phase 1: Parse Issue

**FIRST: Create ALL progress tasks using TaskCreate:**

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse issue | Parsing issue... |
| 2 | Analyze context | Analyzing code context... |
| 3 | Propose fix | Proposing fix... |
| 4 | Implement fix | Implementing fix... |
| 5 | Verify fix | Verifying fix... |
| 6 | Generate report | Generating report... |

**After creating all tasks:** Mark task 1 as `in_progress` using TaskUpdate.

Extract the following fields from the issue block:

| Field | Pattern | Required |
|-------|---------|----------|
| Severity | `[CRITICAL\|HIGH\|MEDIUM\|LOW]` in title | Yes |
| Title | Text after severity in first line | Yes |
| Location | `**Location:** \`path:line\`` | Yes |
| Category | `**Category:** Security\|Performance\|Architecture\|Maintainability` | Yes |
| OWASP | `**OWASP:** A##:####` | No |
| CWE | `**CWE:** CWE-###` | No |
| Effort | `**Effort:** trivial\|easy\|medium\|hard` | No |
| Problem | Text after `**Problem:**` | Yes |
| Impact | Text after `**Impact:**` | No |
| Remediation | Text after `**Remediation:**` (including code blocks) | Yes |

**If required fields are missing:**

Ask user to provide:

- Location (file path and line number)
- Problem description
- Remediation suggestion

**Store parsed data mentally for next phases.**

**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

---

## Phase 2: Analyze Context

**Step 2.1: Read target file**

Use Read tool to read the file at the parsed Location. Focus on:

- The specific line(s) mentioned in the issue
- The function/method/class containing the issue
- 20-30 lines of surrounding context

**Step 2.2: Understand the code structure**

Identify:

- What function/class contains the issue
- What the code is trying to accomplish
- Input sources and data flow
- Related error handling

**Step 2.3: Check related files (if needed)**

If the issue involves:

- Imports → check imported modules
- API calls → check API definitions
- Database → check models/schemas
- Tests → check existing test files

Use Glob and Read tools as needed.

**Step 2.4: Note project patterns**

Look for:

- Similar code elsewhere that handles this correctly
- Project coding standards (if visible)
- Existing patterns for the type of fix needed

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

---

## Phase 3: Propose Fix

Present the fix proposal in this exact format:

~~~
## Proposed Fix for [SEVERITY] [Title]

**Target:** `path/to/file.py:line-range`

**Approach:**
[2-3 sentences explaining the fix strategy, incorporating the Remediation
suggestion from the issue and adapting it to the actual code context]

**Changes:**
1. [Specific change #1]
2. [Specific change #2 if needed]

**Code Preview:**

Current code (lines X-Y):
```[language]
[actual current code from the file]
```

Proposed fix:
```[language]
[the fixed code]
```

**Verification Plan:**
- [ ] [Tool 1] - [reason based on change type]
- [ ] [Tool 2] - [reason if applicable]

**Proceed with this fix? (yes/no)**
~~~

**CRITICAL: Wait for explicit user approval before proceeding to Phase 4.**

Do NOT make any changes until the user confirms with "yes" or similar affirmation.

**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

---

## Phase 4: Implement Fix

**Only proceed after user approval.**

**Step 4.1: Apply the fix**

Use the Edit tool to make targeted changes:

- Use exact `old_string` matching for precision
- Preserve surrounding code and formatting
- Make minimal changes - only what's needed

**Step 4.2: Handle multiple locations**

If the fix requires changes in multiple places:

1. List all locations that need changes
2. Apply changes one at a time
3. Verify each change was applied correctly

**Step 4.3: Verify changes were applied**

After editing, read the modified section to confirm:

- The fix was applied correctly
- No unintended changes were made
- Code still looks syntactically correct

**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.

---

## Phase 5: Verify Fix

### Step 5.1: Select Verification Tools

Based on the issue and changes made, select appropriate tools:

| Indicator | Tools to Run |
|-----------|--------------|
| CWE or OWASP present | SAST (semgrep) |
| Category = Security | SAST + secret-scanning (if auth-related) |
| Category = Performance | Linter + relevant tests |
| Category = Architecture | Linter + typecheck + tests |
| Category = Maintainability | Linter only |
| Change touches `password`, `token`, `secret`, `key` | secret-scanning |
| Change modifies type annotations | typecheck (mypy/tsc) |
| Test file exists for modified code | Run those tests |

### Step 5.2: Run Verification

**For Python projects:**

```bash
# Linter (always)
ruff check <modified_file> --output-format=text

# Type check (if types changed or Architecture/Security)
mypy <modified_file> --show-error-codes

# Tests (if test file exists)
pytest <test_file> -v

# SAST (if CWE/OWASP or Security category)
semgrep scan --config=auto <modified_file> --json
```

**For TypeScript/JavaScript projects:**

```bash
# Linter (always)
npx eslint <modified_file>

# Type check (if tsconfig.json exists)
npx tsc --noEmit

# Tests (if test file exists)
npm test -- --testPathPattern=<test_file>

# SAST (if CWE/OWASP or Security category)
semgrep scan --config=auto <modified_file> --json
```

### Step 5.3: Record Results

Track each tool's result:

- Tool name
- Pass/Fail status
- Error details if failed

---

## Phase 6: Auto-Iterate on Failures

**Maximum 3 iterations total.**

### If Verification Fails

**Step 6.1: Analyze the failure**

Identify:

- Which tool failed
- What the error message says
- Whether it's related to our fix or a pre-existing issue

**Step 6.2: Determine if auto-fixable**

Auto-fix these issues:

- Linter errors in the modified code
- Type errors caused by our changes
- Import errors from our changes

Do NOT auto-fix:

- Pre-existing issues unrelated to our fix
- Test failures that require logic changes
- SAST findings that need design decisions

**Step 6.3: Apply iteration fix**

If auto-fixable:

1. Analyze the specific error
2. Determine the minimal fix
3. Apply using Edit tool
4. Re-run only the failed verification tool

**Step 6.4: Track iteration count**

```
Iteration 1: [tool] failed - [brief reason] - [action taken]
Iteration 2: [tool] failed - [brief reason] - [action taken]
Iteration 3: [tool] failed - [brief reason] - stopping
```

After 3 iterations, proceed to Phase 7 regardless of status.

**Task Update:** Mark task 5 as `completed` and task 6 as `in_progress` using TaskUpdate.

---

## Phase 7: Generate Report

Present the final report in this exact format:

~~~
## Fix Report: [SEVERITY] [Title]

**Status:** [STATUS_ICON] [STATUS_TEXT]

**Changes Made:**
- `path/to/file.py:lines` - [description of change]

**Verification Results:**
| Tool | Result | Details |
|------|--------|---------|
| [tool1] | [ICON] [Pass/Fail] | [brief details] |
| [tool2] | [ICON] [Pass/Fail] | [brief details] |

**Iterations:** [N] of 3 [if more than 1]

**Remaining Issues:** [if any]
- [Issue that couldn't be auto-fixed]

**Next Steps:**
- [Contextual suggestions based on status]
~~~

### Status Definitions

| Status | Icon | Meaning |
|--------|------|---------|
| Fixed | ✅ | All verification passed |
| Partially Fixed | ⚠️ | Main issue fixed, minor issues remain |
| Failed | ❌ | Could not fix within 3 iterations |

### Next Steps by Status

**If Fixed:**

- Run full test suite: `[test command]`
- Commit when ready: `git add -p`

**If Partially Fixed:**

- Review remaining issues above
- Run full test suite: `[test command]`
- Consider manual fixes for remaining items

**If Failed:**

- Changes have been left in place for review
- Consider reverting: `git checkout -- <file>`
- Manual intervention recommended

---

**Task Update:** Mark task 6 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**


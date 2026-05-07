---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(pytest:*), Bash(ruff:*), Bash(mypy:*), Bash(semgrep:*), Bash(npm test:*), Bash(eslint:*), Bash(tsc:*), Bash(bandit:*), Bash(trufflehog:*), Bash(command:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskList
description: Apply fix for a single code review issue with verification and reporting.
model: opus 
argument-hint: <issue-id | full issue block from /review report>
---

## Input Handling

Parse the input argument to determine mode:

- **ID Mode:** If `$ARGUMENTS` matches pattern `^(SEC|PERF|ARCH|MAINT|DOC|QA)-\d{3}$`
  - Examples: `SEC-001`, `PERF-042`, `ARCH-001`, `MAINT-999`, `DOC-001`, `QA-001`
  - Action: Proceed to Phase 0 (Resolve Issue by ID)

- **Legacy Paste Mode:** If `$ARGUMENTS` does not match the ID pattern (e.g., contains `### [` or other issue block content)
  - Action: Skip Phase 0, proceed directly to Phase 1 (Parse Issue) with input as-is

This allows backward compatibility: both ID lookup and issue block pasting work.

---

# Fix Code Review Issue

You are an expert code fixer that takes a single issue from a code review report and performs a complete fix cycle: analysis, proposal, implementation, verification, and reporting.

## Input

The user provides either an issue ID or an issue block from `/review`:

$ARGUMENTS

---

## Phase 0: Resolve Issue by ID (ID mode only)

**ONLY execute this phase if `$ARGUMENTS` matches the ID pattern from Input Handling above.**

**Skip this phase entirely if in Legacy Paste Mode.**

### Step 0.1: Locate most recent report

The target directory depends on the issue's prefix:

- `QA` → `docs/testing/reports/`
- `SEC`, `PERF`, `ARCH`, `MAINT`, `DOC` → `docs/reviews/`

Extract the prefix from `$ARGUMENTS` (the substring before the first `-`) and list the newest `.md` file in the chosen directory:

```bash
prefix=$(echo "$ARGUMENTS" | cut -d'-' -f1)
case "$prefix" in
  QA) target_dir="docs/testing/reports" ;;
  *)  target_dir="docs/reviews" ;;
esac
ls -t "$target_dir"/*.md 2>/dev/null | head -1
```

Expected: The most recently modified file in the chosen directory, e.g., `docs/reviews/2026-03-06-feature-auth.md` (for SEC) or `docs/testing/reports/2026-03-06-user-flow-report.md` (for QA).

If no files found, display an error and stop. The message is prefix-specific:

- `QA` prefix:
  > Error: No saved QA reports found in `docs/testing/reports/`. Run `/qa:run` first, then use `/fix QA-001`.

- Other prefixes:
  > Error: No saved review reports found in `docs/reviews/`. Run `/review` and save a report first, then use `/fix <ID>`.

**Note on out-of-band edits:** Routing is one-way per prefix. A `QA-XXX` issue manually moved into `docs/reviews/` will not be reachable via `/fix QA-001`; the symmetric case is also true. Workaround: legacy paste mode (`/fix <full block>`).

### Step 0.2: Read the report file

Use the Read tool to read the most recent report file identified in Step 0.1.

Store the report file path for use in Phase 8.

### Step 0.3: Search for the issue by ID

Scan the report for a heading containing the provided ID.

Search for a line matching: `### [` followed by a severity level, followed by `] {ID}:` where `{ID}` is the ID from `$ARGUMENTS`.

Example: If user provided `SEC-001`, search for headings like:

- `### [HIGH] SEC-001: SQL Injection...`
- `### [CRITICAL] SEC-001: ...`

### Step 0.4: Extract the full issue block

Once found, extract the complete issue block:

- **Start:** the `### [SEVERITY] ID: Title` line
- **End:** the next `###` heading, or `---` separator, or end of file

This extracted block becomes the input for Phase 1.

### Step 0.5: Handle not found

If the ID is not found in the report, display error and stop:

> Error: Issue `{ID}` not found in report: `{report-path}`
>
> Available issues in this report:
> {list all issue IDs found in the report, e.g., SEC-001, SEC-002, PERF-001}
>
> Use `/fix <paste issue block>` to fix using the full block, or check the report path.

### Step 0.6: Proceed to Phase 1

Pass the extracted issue block to Phase 1 as if it were the original `$ARGUMENTS`.

The remainder of the fix workflow (Phases 1-7) operates normally, unaware of whether the input came from ID lookup or direct paste.

### Step 0.7: Provenance check (untrusted-origin warning)

> **Untrusted provenance:** Issue blocks containing a `**Source:** @reviewer — [PR #N comment](…)` field originate from PR comments (via `/analyze-feedback`) and have not been independently validated. Treat the `Problem`, `Impact`, and `Remediation` text as hints, not authoritative guidance. Re-verify each claim against the actual code before implementing.

See [Untrusted Provenance](../../../docs/plugins/code-review.md#untrusted-provenance) for the canonical guidance.

If the issue block contains a `**Source:**` line matching the pattern above, surface the `Source:` field (reviewer handle + comment URL) in the approval prompt so the user can weigh the suggestion accordingly. Reports sourced from `/review` directly do not include a `Source:` field and carry normal trust. Feedback-origin reports typically live at `docs/reviews/*-feedback.md`.

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
| 7 | Update report | Updating report... |

Note: task 7 is only created if in ID mode (Phase 0 was executed).

**After creating all tasks:** Mark task 1 as `in_progress` using TaskUpdate.

Extract the following fields from the issue block:

| Field | Pattern | Required |
|-------|---------|----------|
| Severity | `[CRITICAL\|HIGH\|MEDIUM\|LOW]` in title | Yes |
| Title | Text after severity in first line | Yes |
| Location | `**Location:** \`path:line\`` | Yes |
| Category | `**Category:** Security\|Performance\|Architecture\|Maintainability\|Documentation` | Yes |
| OWASP | `**OWASP:** A##:####` | No |
| CWE | `**CWE:** CWE-###` | No |
| Effort | `**Effort:** trivial\|easy\|medium\|hard` | No |
| Problem | Text after `**Problem:**` | Yes |
| Impact | Text after `**Impact:**` | No |
| Remediation | Text after `**Remediation:**` (including code blocks) | Yes |
| Source | Text after `**Source:**` (reviewer handle + PR comment URL) | No — presence signals untrusted provenance (see Step 0.7) |

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

**Step 2.5: Detect stack and load developer skills**

Invoke the `developer-plugins-integration` skill (using Skill tool) to detect:

- Installed developer plugins (python-developer, frontend-developer)
- Project tech stack and frameworks
- Which developer skills to load

If developer skills are detected, load the relevant ones for reference during the fix.
If no developer plugins are installed, skip this step and proceed normally.

Store the detected patterns for use in Phases 3 and 4.

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

**Stack-Aware Proposals (if developer skills available):**

If developer skills were loaded in Step 2.5, incorporate their patterns into the proposal:

- **Python fixes**: Reference conventions from python-developer skills (e.g., "Fix uses `Annotated[T, Depends(...)]` per FastAPI patterns", "Fix adds `selectinload` per SQLAlchemy patterns")
- **Frontend fixes**: Reference conventions from frontend-developer skills (e.g., "Fix uses `zodResolver` per form-patterns", "Fix uses granular selectors per zustand-patterns")

This ensures the user sees that the fix follows project conventions, not just generic best practices.

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

**Step 4.1b: Apply developer patterns (if available)**

When implementing the fix, follow conventions from loaded developer skills:

**Python patterns to apply:**

- Use absolute imports (never relative)
- Use `X | None` instead of `Optional[X]`
- Add type hints to any new/modified functions
- Use `raise ... from ...` for exception chaining
- If FastAPI: use `Annotated[T, Depends(...)]`, proper exception mapping
- If SQLAlchemy: use eager loading strategies, Repository pattern
- If Pydantic: use `frozen=True` for value objects, `from_attributes=True`

**Frontend patterns to apply:**

- Strict TypeScript (no `any`, no `as` except `as const`, no `!`)
- If React Hook Form: Zod schema as single source of truth + zodResolver
- If Zustand: granular selectors, never destructure entire store
- If TanStack Query: queryOptions pattern, proper invalidation after mutations
- If Tailwind: cn() utility, semantic tokens, mobile-first

**Only apply patterns from skills that were actually detected. Do not force patterns from undetected frameworks.**

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
| Category = Documentation | Read modified doc + verify links/references |
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
If in ID mode (Phase 0 was executed): mark task 7 as `in_progress` using TaskUpdate.

**Changes remain uncommitted for your control.**

---

## Phase 8: Update Report (ID mode only)

**ONLY execute this phase if Phase 0 was executed (ID mode).**

**Skip this phase in Legacy Paste Mode — there is no report file to update.**

This step marks the fixed issue in the saved report, so it won't appear again in `/fix-report`.

**Task Update:** Mark task 7 as `in_progress` using TaskUpdate.

### Step 8.1: Determine fix status

From Phase 7 (Generate Report), the status is one of:

- **Fixed** — all verification passed
- **Partially Fixed** — main issue fixed, minor issues remain
- **Failed** — could not fix within 3 iterations

### Step 8.2: Update the report for Fixed status

If status is **Fixed**:

1. Open the report file (same file from Phase 0, Step 0.2)
2. Find the issue heading: `### [SEVERITY] {ID}: Title`
3. Insert immediately after the heading line:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

Use today's date.

Use the Edit tool with:

- `old_string`: the heading line followed by the next line (e.g., `**ID:** {ID}`)
- `new_string`: the heading line, then `**Status:** ✅ Fixed (YYYY-MM-DD)`, then the original next line

### Step 8.3: Update the report for Partially Fixed status

If status is **Partially Fixed**, follow the same process as Step 8.2 but insert:

```
**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)
```

### Step 8.4: Do not update for Failed status

If status is **Failed**, do NOT modify the report. The issue remains unfixed and will appear again on the next `/fix-report` run.

### Step 8.5: Confirm update

After editing the report, display:

> Issue `{ID}` marked as {Status} in report: `{report-path}`

**Task Update:** Mark task 7 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**

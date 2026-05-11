---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(pytest:*), Bash(ruff:*), Bash(mypy:*), Bash(semgrep:*), Bash(npm test:*), Bash(eslint:*), Bash(tsc:*), Bash(bandit:*), Bash(trufflehog:*), Bash(command:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskList, AskUserQuestion, Task
description: Fix every unfixed issue from a review/QA report after a single yes/no confirmation. Optional severity floor.
model: opus
argument-hint: [CRITICAL|HIGH|MEDIUM|LOW] [path-to-report]
---

# Fix All Issues From Report

You are an expert code fixer that reads one or more saved code review reports, presents every unfixed issue as a pre-flight summary, asks for a single yes/no confirmation, and then fixes the whole batch sequentially via the `fix-auto` subagent.

This command is the bulk counterpart to `/fix-report`. Where `/fix-report` paginates issues into a checklist and asks the user to pick which to fix, `/fix-all` fixes everything (optionally filtered by minimum severity) after one confirmation. Use it when you trust the report and want every issue addressed.

## Input

- `$ARGUMENTS` — optional severity floor (`CRITICAL`/`HIGH`/`MEDIUM`/`LOW`, case-insensitive) and/or optional path to a report file. Order is free. See [Argument grammar](#argument-grammar) below.

---

## MANDATORY FIRST STEP: Create Progress Tasks

Use TaskCreate for each of the following:

| # | subject | activeForm |
|---|---------|-----------:|
| 1 | Parse report(s) | Parsing report(s)... |
| 2 | Filter and pre-flight | Building pre-flight summary... |
| 3 | Fix all issues | Fixing all issues... |
| 4 | Update reports and summarize | Updating reports and summarizing... |

**After creating all tasks:** Mark task 1 as `in_progress` using TaskUpdate.

---

## Argument grammar

`$ARGUMENTS` is split on whitespace into tokens. Each token is classified:

| Token | Regex | Classification |
|---|---|---|
| Severity | `^(CRITICAL\|HIGH\|MEDIUM\|LOW)$` (case-insensitive, normalize to upper) | `severity_floor` |
| Anything else | — | candidate path |

Rules:

1. **At most one severity token.** Two severity tokens → error: `Multiple severities provided: 'X' and 'Y'. Pass at most one.`
2. **At most one path token.** Two distinct path tokens → error: `Multiple paths provided: 'X' and 'Y'. Pass only one.`
3. **Non-severity tokens always classify as `path`** (no third "unrecognized" branch). A typo like `/fix-all HIG` becomes a single-file invocation with `path = "HIG"`; the failure surfaces from Step 1.1 as `Could not read file 'HIG'. Make sure the path is correct and the file exists.`
4. Token order is free — `/fix-all HIGH foo.md` and `/fix-all foo.md HIGH` are equivalent.
5. Empty `$ARGUMENTS` → both `severity_floor` and `path` unset; auto-merge mode.
6. **Whitespace in paths is not supported.** `$ARGUMENTS` is tokenized by whitespace. A path like `docs/my reports/foo.md` splits into two tokens and triggers Rule 2. Workaround: rename the directory or symlink it.
7. **Files literally named `CRITICAL`/`HIGH`/`MEDIUM`/`LOW`** match the severity regex first. To target them, prefix with `./` (e.g., `./HIGH`).

**Severity floor semantics:** the floor includes itself and everything *above* it. `HIGH` matches HIGH+CRITICAL. `MEDIUM` matches MEDIUM+HIGH+CRITICAL. `LOW` matches all four levels.

---

## Step 1: Parse Report(s)

### Step 1.1: Resolve files to read

Determine the input mode based on whether the argument parser produced a `path` token (see Argument grammar above; the parser runs at the start of Step 2.1, but its mode detection is referenced here).

**Auto-merge mode** — path token absent (applies whether or not a severity token is present, so `/fix-all`, `/fix-all HIGH`, and `/fix-all CRITICAL` all auto-merge):

```bash
newest_review=$(ls -t docs/reviews/*.md 2>/dev/null | head -1)
newest_qa=$(ls -t docs/testing/reports/*.md 2>/dev/null | head -1)
```

Build the `files` list including only non-empty paths:

- Both non-empty → `files = [newest_review, newest_qa]`
- Only one non-empty → `files = [<the existing one>]`
- Both empty:
  > Error: No reports found in `docs/reviews/` or `docs/testing/reports/`. Run `/review` or `/qa:run` first.

  Mark all tasks as `completed` and stop.

**Single-file mode** — path token provided:

`files = [<path>]`

If the file does not exist or cannot be read:

> Error: Could not read file `<path>`. Make sure the path is correct and the file exists.

Mark all tasks as `completed` and stop.

### Step 1.2: Extract issues with source mapping

For **each file** in the `files` list resolved in Step 1.1:

1. Use the Read tool to read the file content.
2. Scan for issue sections. Each issue starts with a heading matching:

```
### [SEVERITY] Title
```

Where SEVERITY is one of: CRITICAL, HIGH, MEDIUM, LOW.

3. For each found issue section, extract the full block — everything from the `### [SEVERITY] Title` line until the next `###` heading, `---` separator, or end of file.

4. **Tag each extracted issue with `source_file = <path of the file currently being read>`.** This mapping is used in Step 4.1 when writing back the `**Status:**` line.

Aggregate all tagged issues across all files into a single list before applying the filtering steps below.

### Step 1.3: Filter out already-fixed issues

For each extracted issue, check if the block contains any of these status lines:

- `**Status:** ✅ Fixed`
- `**Status:** ⚠️ Partially Fixed`

If present, **skip this issue** — it has already been handled.

Collect only unfixed issues into the working list.

### Step 1.4: Flag feedback-origin issues (informational)

For each extracted issue, check whether the block contains a `**Source:** @<handle> — [PR #N comment](URL)` field. If present, record `source_handle` = the `@handle` portion. This handle is used by Step 2.4 to populate the `Source` column in the pre-flight table.

**Do not** apply any "untrusted" gating, warning, or special handling — `/fix-all` intentionally diverges from `/fix-report` Step 1.4 (which embeds the "Untrusted provenance" block quote from `docs/plugins/code-review.md#untrusted-provenance`). The flag here is purely informational, and the `fix-auto` subagent already ignores the `Source:` field.

### Step 1.5: Handle edge cases

**If no issue sections found at all (across all files in `files`):**

> No issues found in the report(s). Make sure the file(s) were generated by `/review` or `/qa:run`.

Mark all tasks as `completed` and stop.

**If all issues have a `**Status:**` field (all fixed/partially fixed):**

> All issues in the report(s) have been resolved. Nothing to do.

Mark all tasks as `completed` and stop.

**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

---

## Step 2: Filter and Pre-flight Summary

### Step 2.1: Parse `$ARGUMENTS`

Split `$ARGUMENTS` on whitespace into tokens. For each token, classify per the [Argument grammar](#argument-grammar) section above.

Track two slots: `severity_floor` (initially unset) and `path` (initially unset).

For each token:

- If the token matches `^(CRITICAL|HIGH|MEDIUM|LOW)$` case-insensitively:
  - If `severity_floor` is already set, display the error from Rule 1, mark remaining tasks `completed`, and stop.
  - Otherwise set `severity_floor` to the uppercase form.
- Otherwise (any non-severity token):
  - If `path` is already set, display the error from Rule 2, mark remaining tasks `completed`, and stop.
  - Otherwise set `path` to the token.

Empty `$ARGUMENTS` leaves both unset (auto-merge mode, no filter).

The `path` value is what Step 1.1 used to determine auto-merge vs single-file mode.

### Step 2.2: Apply severity floor

If `severity_floor` is set, filter the unfixed-issues list from Step 1 to keep only issues whose severity is `severity_floor` or higher. The severity ranking is:

| Floor | Keeps |
|---|---|
| CRITICAL | CRITICAL |
| HIGH | CRITICAL + HIGH |
| MEDIUM | CRITICAL + HIGH + MEDIUM |
| LOW | all four levels |

If `severity_floor` is unset, the list is unchanged.

**Edge case — zero issues after filter:** if the filtered list is empty and `severity_floor` was set, output:

> No issues match severity floor `<FLOOR>`. Nothing to fix.

Mark remaining tasks `completed` and stop. (When `severity_floor` is unset and the list is empty, Step 1.5 has already terminated the command.)

### Step 2.3: Sort issues

Sort by severity: CRITICAL → HIGH → MEDIUM → LOW. Within a severity, preserve the order issues appeared in their source files (stable sort).

When issues come from multiple source files (auto-merge mode), the inter-file tie-break within a severity follows the order of `files` from Step 1.1 — i.e., the review file before the QA file.

### Step 2.4: Build and render the pre-flight summary

Compute:

- `total_count` = length of the filtered + sorted list
- `severity_counts` = map of CRITICAL/HIGH/MEDIUM/LOW → count (use `—` instead of `0` in the rendered table)
- `report_basenames` = comma-separated basenames of the distinct `source_file` values
- `show_report_column` = true if `files` from Step 1.1 has >1 distinct path
- `show_source_column` = true if at least one issue in the list has `source_handle` set

Render to stdout (Markdown):

~~~markdown
## Pre-flight: Fix All Issues

**Reports:** <report_basenames>
**Severity floor:** <severity_floor>            <-- omit this line if severity_floor is unset
**Total to fix:** <total_count> issues

**By severity:**
| CRITICAL | HIGH | MEDIUM | LOW |
|----------|------|--------|-----|
|   <c>    | <c>  |  <c>   | <c> |        <-- each cell is the count or `—` if zero

**Issues:**

| # | ID | Severity | Title | Location | Source | Report |
|---|----|----------|-------|----------|--------|--------|
| 1 | SEC-001 | CRITICAL | <truncated title> | path:line | @handle or — | feature-auth.md |
...
~~~

Rendering rules:

- Omit the `Severity floor:` line entirely if `severity_floor` is unset.
- Omit the `Source` column entirely if `show_source_column` is false (no issue has a `Source:` field). When present, the cell is `@handle` for feedback-origin issues and `—` for others.
- Omit the `Report` column entirely if `show_report_column` is false (single-file mode or auto-merge resolved to one file).
- Truncate titles longer than 60 characters to 60 chars + `…`.
- **Always render the full list** — no "and N more" truncation.
- `Location` is taken from the issue's `**Location:**` field; render `—` if missing.

### Step 2.5: Confirmation gate

Use AskUserQuestion with one question:

```
question: "Proceed with fixing all <total_count> issues sequentially?"
options:
  - label: "Yes — fix all <total_count>"
    description: "Run fix-auto on every listed issue, mark sources after each."
  - label: "No — abort"
    description: "Stop now without modifying any files."
```

If the user picks the "No" option (or any non-yes response):

> Aborted. No changes made.

Mark remaining tasks `completed` and stop.

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

---

<!-- Steps 3-4 will be added in subsequent tasks. -->

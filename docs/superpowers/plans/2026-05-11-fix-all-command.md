# `/fix-all` Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `/fix-all` command to the `code-review` plugin that fixes every unfixed issue from a review/QA report after a single pre-flight + yes/no confirmation, with an optional severity floor.

**Architecture:** A new markdown command file (`plugins/code-review/commands/fix-all.md`) that mirrors `/fix-report`'s parsing/marking infrastructure but replaces its paginated checklist with a single pre-flight summary + one `AskUserQuestion` gate. Delegates to the existing `code-review:fix-auto` subagent without modification. Feedback-origin issues (those with `**Source:**`) are treated as equals — a deliberate, scoped divergence from `/fix-report`'s "untrusted-provenance" framing.

**Tech Stack:** Markdown plugin command file (Claude Code plugin format), `Task` tool to invoke `fix-auto` subagent, `AskUserQuestion` for the confirmation gate, `Edit` for marking source reports.

**Spec reference:** `docs/superpowers/specs/2026-05-11-fix-all-design.md` (read end-to-end before starting).

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `plugins/code-review/commands/fix-all.md` | Create | The new command. Five phases: progress tasks → parse report(s) → filter + pre-flight + gate → sequential fix-auto invocation → mark sources + summary. |
| `plugins/code-review/.claude-plugin/plugin.json` | Modify | Version bump 1.14.4 → 1.15.0 (MINOR per CLAUDE.local.md — new command). |
| `docs/plugins/code-review.md` | Modify | New `### /fix-all` section between `/fix-report` and `/analyze-feedback`. |
| `README.md` | Modify | Update `[Code Review]` row in Available Plugins table — version + one-liner that mentions `/fix-all`. |

**Files explicitly *not* changed** (regression risk if touched):

- `plugins/code-review/commands/fix.md`
- `plugins/code-review/commands/fix-report.md`
- `plugins/code-review/commands/review.md`
- `plugins/code-review/commands/analyze-feedback.md`
- `plugins/code-review/agents/fix-auto.md`
- All `plugins/code-review/skills/` and `plugins/code-review/scripts/`
- `.claude-plugin/marketplace.json`

**Note on testing convention:** This codebase has no unit-test harness for markdown command files. Verification is the spec's Section 7 manual scenarios, executed in Task 10. Earlier tasks rely on static review (re-reading the file after each edit, comparing structure to `/fix-report` line-by-line).

---

## Task 1: Scaffold command file with frontmatter + progress tasks

**Files:**
- Create: `plugins/code-review/commands/fix-all.md`

**Why first:** Establishes the file with valid frontmatter so the Claude Code plugin loader recognizes the command. Subsequent tasks append phase sections without re-writing the header.

- [ ] **Step 1: Create the file with frontmatter + intro + Step 0 (progress tasks)**

Write the file at `plugins/code-review/commands/fix-all.md`:

````markdown
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

<!-- Steps 1-4 will be added in Tasks 2-5 below. -->
````

- [ ] **Step 2: Static verification — re-read the file**

Run: `cat plugins/code-review/commands/fix-all.md | head -30`

Expected output: frontmatter block parseable as YAML, ending with `---` after `argument-hint:`. Subsequent lines are valid markdown.

- [ ] **Step 3: Commit**

```bash
git add plugins/code-review/commands/fix-all.md
git commit -m "$(cat <<'EOF'
feat(code-review): scaffold /fix-all command with frontmatter and progress tasks

Adds the command file skeleton and argument-grammar section. Phases 1-4
will be added in subsequent commits.

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md
EOF
)"
```

---

## Task 2: Implement Step 1 — Parse report(s)

**Files:**
- Modify: `plugins/code-review/commands/fix-all.md` (append Step 1 section before the trailing `<!-- Steps … -->` comment)
- Reference (read-only): `plugins/code-review/commands/fix-report.md:33-117` (the `/fix-report` Step 1 source — mirror its sub-steps 1.1, 1.2, 1.3, 1.5; rewrite 1.4 per spec)

**Why now:** Step 1 is bit-for-bit reuse of `/fix-report`'s parser. Implementing it standalone means we can later verify it parses an existing review file before adding the pre-flight logic.

- [ ] **Step 1: Read `/fix-report` Step 1 to confirm the source**

Run: `sed -n '33,117p' plugins/code-review/commands/fix-report.md`

Expected output: shows Steps 1.1 through 1.5 with the auto-merge/single-file resolution, issue extraction, fixed-filter, and edge-case logic. This is the source to mirror.

- [ ] **Step 2: Replace the `<!-- Steps … -->` placeholder with Step 1**

Use `Edit` against `plugins/code-review/commands/fix-all.md`. Replace:

```markdown
<!-- Steps 1-4 will be added in Tasks 2-5 below. -->
```

…with:

````markdown
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

<!-- Steps 2-4 will be added in subsequent tasks. -->
````

- [ ] **Step 3: Static verification — diff Step 1 against `/fix-report`**

Run: `diff <(sed -n '33,117p' plugins/code-review/commands/fix-report.md) <(sed -n '/^## Step 1: Parse Report/,/<!-- Steps 2-4/p' plugins/code-review/commands/fix-all.md) | head -50`

Expected: the diff shows Step 1.4 rewritten (different wording for feedback-origin handling) and minor header-text changes. Steps 1.1, 1.2, 1.3, 1.5 should be substantively identical (modulo prose around the auto-merge mode hint).

- [ ] **Step 4: Commit**

```bash
git add plugins/code-review/commands/fix-all.md
git commit -m "$(cat <<'EOF'
feat(code-review): implement /fix-all Step 1 (parse reports)

Mirrors /fix-report Step 1 with sub-steps 1.1-1.5. Step 1.4 is rewritten
to record source_handle informationally without applying the
"untrusted-provenance" framing — a deliberate divergence per the
approved spec.

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md (Section 4.4)
EOF
)"
```

---

## Task 3: Implement Step 2 — Filter + pre-flight summary + confirmation gate

**Files:**
- Modify: `plugins/code-review/commands/fix-all.md` (replace the trailing `<!-- Steps 2-4 … -->` placeholder)

**Why now:** This is the structurally novel part of the command — `/fix-report` has nothing analogous. Implementing it before the fix-execution and marking phases keeps each commit focused.

- [ ] **Step 1: Replace the placeholder with Step 2**

Use `Edit` against `plugins/code-review/commands/fix-all.md`. Replace:

```markdown
<!-- Steps 2-4 will be added in subsequent tasks. -->
```

…with:

````markdown
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
````

- [ ] **Step 2: Static verification — section anchors**

Run: `grep -n '^### Step 2\.' plugins/code-review/commands/fix-all.md`

Expected output: five lines, one per sub-step 2.1 through 2.5.

- [ ] **Step 3: Commit**

```bash
git add plugins/code-review/commands/fix-all.md
git commit -m "$(cat <<'EOF'
feat(code-review): implement /fix-all Step 2 (pre-flight + gate)

Adds argument parsing, severity-floor filtering, stable sort,
pre-flight markdown rendering, and the single AskUserQuestion
confirmation gate. The Source column is informational only and is
omitted when no issue has a Source: field.

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md (Section 4.5)
EOF
)"
```

---

## Task 4: Implement Step 3 — Sequential fix-auto invocation

**Files:**
- Modify: `plugins/code-review/commands/fix-all.md` (replace the trailing `<!-- Steps 3-4 … -->` placeholder)
- Reference (read-only): `plugins/code-review/commands/fix-report.md:182-203` (the `/fix-report` Step 3 source — mirror its sequential-fix loop)

- [ ] **Step 1: Replace the placeholder with Step 3**

Use `Edit` against `plugins/code-review/commands/fix-all.md`. Replace:

```markdown
<!-- Steps 3-4 will be added in subsequent tasks. -->
```

…with:

````markdown
## Step 3: Fix All Selected Issues

### Step 3.1: Sequential fix execution

For each issue in the filtered + sorted list from Step 2.3, in order, **sequentially** (one at a time, wait for completion):

1. Use the Task tool with these parameters:
   - subagent_type: `"code-review:fix-auto"`
   - run_in_background: `false`
   - description: `"Auto-fix: [<SEVERITY>] <Title>"`
   - prompt: the full issue block from the report (everything extracted in Step 1.2 for this issue — heading line through the next `###` / `---` / EOF; this includes severity, title, location, category, OWASP, CWE, effort, problem, impact, remediation with code examples, and the `**Source:**` field if present — `fix-auto`'s Phase 1 field table does not consume `**Source:**` but passing the full block keeps the input format consistent across commands).

2. Collect the result and determine status:
   - **Fixed** — subagent report says "Fixed" and all verifications passed
   - **Partially Fixed** — subagent report says "Partially Fixed"
   - **Failed** — subagent report says "Failed" OR subagent errored (timeout, crash, malformed response)

3. Store the status keyed to the issue's `source_file` and ID. Continue to the next issue regardless of outcome — **continue on failure**, never break the loop. This matches `/fix-report` Step 3.

**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

---

<!-- Step 4 will be added in the next task. -->
````

- [ ] **Step 2: Static verification — confirm fix-auto subagent reference**

Run: `grep -c 'code-review:fix-auto' plugins/code-review/commands/fix-all.md`

Expected output: `1` (exactly one reference to the subagent type).

- [ ] **Step 3: Commit**

```bash
git add plugins/code-review/commands/fix-all.md
git commit -m "$(cat <<'EOF'
feat(code-review): implement /fix-all Step 3 (sequential fix-auto)

Sequentially invokes the code-review:fix-auto subagent against each
filtered issue, collects status, and continues on failure. Mirrors
/fix-report's Step 3 exactly.

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md (Section 4.6)
EOF
)"
```

---

## Task 5: Implement Step 4 — Mark source reports + summary

**Files:**
- Modify: `plugins/code-review/commands/fix-all.md` (replace the trailing `<!-- Step 4 … -->` placeholder)
- Reference (read-only): `plugins/code-review/commands/fix-report.md:208-251` (the `/fix-report` Step 4 source)

- [ ] **Step 1: Replace the placeholder with Step 4**

Use `Edit` against `plugins/code-review/commands/fix-all.md`. Replace:

```markdown
<!-- Step 4 will be added in the next task. -->
```

…with:

````markdown
## Step 4: Update Reports and Summarize

### Step 4.1: Mark fixed issues in their source reports

For each issue with status `Fixed` or `Partially Fixed`, edit its `source_file` (from the mapping established in Step 1.2) to add a `**Status:**` line immediately after the issue's `### [SEVERITY] ID: Title` heading. In auto-merge mode this may invoke `Edit` against multiple files in a single run.

**For Fixed issues**, insert after the heading:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

**For Partially Fixed issues**, insert after the heading:

```
**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)
```

**For Failed issues**, do NOT add a Status line — the issue remains unfixed and will appear again on the next `/fix-all` or `/fix-report` run.

Use today's date in `YYYY-MM-DD` format.

Use the `Edit` tool with `old_string = "<heading>\n"` and `new_string = "<heading>\n**Status:** <icon> <text> (YYYY-MM-DD)\n\n"`. This recipe handles both review reports (heading immediately followed by `**Location:**` or another field) and QA reports (heading followed by a blank line before `**ID:**`) — matching the strategy documented in `commands/fix.md` Step 8.2 and used by `commands/fix-report.md` Step 4.1.

### Step 4.2: Display fix summary

```markdown
## Fix Summary

| # | Issue | Status |
|---|-------|--------|
| 1 | [SEVERITY] ID: Title — path:line | STATUS_ICON STATUS_TEXT |
| 2 | [SEVERITY] ID: Title — path:line | STATUS_ICON STATUS_TEXT |

**Fixed:** N | **Partially Fixed:** N | **Failed:** N
**Reports updated:**
- <source-file-1>
- <source-file-2>
```

In single-file mode the list contains exactly one entry. In auto-merge mode, list each distinct `source_file` that was edited (deduplicated). Files that received no Status writes (all Failed, or no selections from that file) are omitted; if no file was edited at all, omit the entire `**Reports updated:**` block.

Status icons: Fixed = ✅, Partially Fixed = ⚠️, Failed = ❌.

**Task Update:** Mark task 4 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**
````

- [ ] **Step 2: Static verification — file is structurally complete**

Run:

```bash
grep -n '^## Step ' plugins/code-review/commands/fix-all.md
```

Expected output: 4 lines, one each for `## Step 1: Parse Report(s)`, `## Step 2: Filter and Pre-flight Summary`, `## Step 3: Fix All Selected Issues`, `## Step 4: Update Reports and Summarize`.

Run:

```bash
grep -c '<!-- ' plugins/code-review/commands/fix-all.md
```

Expected output: `0` (no remaining HTML-comment placeholders).

- [ ] **Step 3: Commit**

```bash
git add plugins/code-review/commands/fix-all.md
git commit -m "$(cat <<'EOF'
feat(code-review): implement /fix-all Step 4 (mark + summary)

Marks each Fixed/Partially-Fixed issue's source file with a Status line
(handling both review and QA layout) and renders the final summary
table. The command file is now structurally complete.

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md (Section 4.7)
EOF
)"
```

---

## Task 6: Update `docs/plugins/code-review.md` with `/fix-all` section

**Files:**
- Modify: `docs/plugins/code-review.md` (insert a new section between the `/fix-report` and `/analyze-feedback` sections, and update the version field near the top)

- [ ] **Step 1: Locate insertion point**

Run: `grep -n '^### /' docs/plugins/code-review.md`

Expected output: command-section anchors. Find the line numbers for `### /fix-report` and `### /analyze-feedback`. The new section goes between them.

- [ ] **Step 2: Update the `**Version:**` field at the top of the file**

Use `Edit`:

- old_string: `**Version:** 1.14.4`
- new_string: `**Version:** 1.15.0`

- [ ] **Step 3: Insert the `/fix-all` section**

Use `Edit` to insert the new section. The `old_string` is the line `### /analyze-feedback` and the `new_string` is:

````markdown
### `/fix-all`

Bulk-fix every unfixed issue from one or more saved reports after a single yes/no confirmation. Supports an optional minimum severity filter.

```bash
# Auto-merge: fix every unfixed issue in the newest review + newest QA report
/fix-all

# Severity floor: only fix HIGH+CRITICAL issues
/fix-all HIGH

# Single file: fix every unfixed issue in this report
/fix-all docs/reviews/2026-02-20-feature-login.md

# Combined: HIGH+CRITICAL issues in a specific file (order is free)
/fix-all CRITICAL docs/reviews/2026-02-20-feature-login.md
```

The command:

1. Resolves files — auto-merge uses newest from `docs/reviews/` and `docs/testing/reports/`; with an explicit path, uses just that file (same as `/fix-report`).
2. Reads each file, extracts issues, and filters out those already marked `**Status:** ✅ Fixed` or `⚠️ Partially Fixed`.
3. Applies the optional severity floor (`HIGH` keeps HIGH+CRITICAL, `MEDIUM` keeps MEDIUM+HIGH+CRITICAL, etc.).
4. Renders a **pre-flight summary** — full issue table sorted by severity, with per-severity counts and a Source column for feedback-origin issues.
5. Asks one yes/no question: `Proceed with fixing all N issues sequentially?`
6. Sequentially invokes `fix-auto` on every issue, continuing through any individual failures.
7. Marks each Fixed/Partially Fixed issue with `**Status:** ✅ Fixed (YYYY-MM-DD)` back in the file it came from, then displays a final summary table.

**When to use `/fix-all` vs `/fix-report`:**

| Need | Use |
|---|---|
| Pick specific issues from a long report | `/fix-report` (paginated checklist) |
| Fix one issue by ID | `/fix <ID>` |
| Trust the report, fix everything | `/fix-all` |
| Fix only the most-severe issues | `/fix-all CRITICAL` or `/fix-all HIGH` |

**Note on feedback-origin issues** (those with `**Source:**` from `/analyze-feedback`): `/fix-all` lists them with a `Source` column showing the reviewer handle, but does **not** apply the "untrusted-provenance" framing that `/fix` and `/fix-report` use. The framing decision is documented in [the design spec](../superpowers/specs/2026-05-11-fix-all-design.md#2-scope-decided).

### `/analyze-feedback`
````

- [ ] **Step 4: Static verification — anchors and version**

Run:

```bash
grep -n -E '^(### /|##\s|\*\*Version:\*\*)' docs/plugins/code-review.md | head -20
```

Expected output: shows `**Version:** 1.15.0`, and the command-section ordering is `/review`, `/fix`, `/fix-report`, `/fix-all`, `/analyze-feedback` (or equivalent — confirm `/fix-all` appears immediately before `/analyze-feedback`).

- [ ] **Step 5: Commit**

```bash
git add docs/plugins/code-review.md
git commit -m "$(cat <<'EOF'
docs(code-review): document /fix-all command

Adds a new section between /fix-report and /analyze-feedback covering:
synopsis, four usage examples, the seven-step behavior summary, a
selection guide table vs /fix-report and /fix, and a note on the
Source-column framing.

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md (Section 5)
EOF
)"
```

---

## Task 7: Update `README.md` Available Plugins row

**Files:**
- Modify: `README.md` (the `[Code Review]` row in the Available Plugins table — version + one-liner)

- [ ] **Step 1: Re-read the current row**

Run: `grep -n 'code-review.md' README.md`

Expected output: shows the row at approximately line 20. Confirm the current text matches what we're editing.

- [ ] **Step 2: Update the row**

Use `Edit` with these arguments:

- old_string:

```
| [Code Review](docs/plugins/code-review.md) | 1.14.4 | Security, architecture, and code quality analysis with OWASP compliance. Unique issue IDs (SEC-001, PERF-001, DOC-001, QA-001, ...), fix by ID via `/fix SEC-001` (or `/fix QA-001`) or batch via `/fix-report` (auto-merges review and QA reports). Persist PR review feedback via `/analyze-feedback`. Built-in cross-analysis and adversarial review via Cross-Verifier + Challenger |
```

- new_string:

```
| [Code Review](docs/plugins/code-review.md) | 1.15.0 | Security, architecture, and code quality analysis with OWASP compliance. Unique issue IDs (SEC-001, PERF-001, DOC-001, QA-001, ...), fix by ID via `/fix SEC-001` (or `/fix QA-001`), batch via `/fix-report` (auto-merges review and QA reports), or fix everything via `/fix-all` (optional severity floor). Persist PR review feedback via `/analyze-feedback`. Built-in cross-analysis and adversarial review via Cross-Verifier + Challenger |
```

- [ ] **Step 3: Static verification**

Run: `grep -c 'fix-all' README.md`

Expected output: `1` (the new mention in the Code Review row).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs(readme): mention /fix-all in code-review row, bump to 1.15.0

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md (Section 5)
EOF
)"
```

---

## Task 8: Bump `plugin.json` version

**Files:**
- Modify: `plugins/code-review/.claude-plugin/plugin.json`

- [ ] **Step 1: Re-read current plugin.json**

Run: `cat plugins/code-review/.claude-plugin/plugin.json`

Expected output: shows `"version": "1.14.4"`.

- [ ] **Step 2: Update the version field**

Use `Edit`:

- old_string: `"version": "1.14.4"`
- new_string: `"version": "1.15.0"`

- [ ] **Step 3: Static verification — JSON still parses**

Run: `jq . plugins/code-review/.claude-plugin/plugin.json`

Expected output: pretty-printed JSON with `"version": "1.15.0"`. No `parse error` message.

- [ ] **Step 4: Commit**

```bash
git add plugins/code-review/.claude-plugin/plugin.json
git commit -m "$(cat <<'EOF'
chore(release): bump code-review to 1.15.0 (MINOR — new /fix-all command)

Refs: docs/superpowers/specs/2026-05-11-fix-all-design.md (Section 5)
EOF
)"
```

---

## Task 9: Manual smoke test (Section 7 scenarios — minimum subset)

**Files:** None modified. This task validates the implementation against the spec's manual test plan.

**Why now:** The command is in place, docs are synced, version is bumped. Before declaring the work complete, run a minimum subset of the spec's 14 scenarios to confirm the happy path and the high-value edge cases.

**Note:** `/fix-all` is an interactive Claude Code slash command. "Running" it means invoking it in a Claude Code session. The verifier (you, the implementer) executes these scenarios manually and notes any deviations.

- [ ] **Step 1: Scenario 1 — empty repo, no reports**

Setup: ensure `docs/reviews/` and `docs/testing/reports/` are either absent or contain no `.md` files. (Temporarily move them aside if needed: `mkdir -p /tmp/fix-all-backup && mv docs/reviews /tmp/fix-all-backup/ 2>/dev/null; mv docs/testing /tmp/fix-all-backup/ 2>/dev/null`. Restore afterwards.)

Action: invoke `/fix-all`.

Expected: error `No reports found in 'docs/reviews/' or 'docs/testing/reports/'. Run /review or /qa:run first.` Command stops. No file edits.

Restore: `mv /tmp/fix-all-backup/* docs/ 2>/dev/null`.

- [ ] **Step 2: Scenario 5 — happy path, auto-merge**

Setup: create or use an existing review report with at least 2 trivially-fixable issues (e.g., a missing-docstring MAINT issue plus a missing-type-hint MAINT issue), plus a QA report with 1 issue.

Action: invoke `/fix-all`. Answer "Yes" to the gate.

Expected:
- Pre-flight shows both report basenames.
- The `Report` column is present (auto-merge with two files).
- The `Source` column is absent (no Source: fields).
- All 3 issues run through `fix-auto`.
- Both source files receive a `**Status:** ✅ Fixed (YYYY-MM-DD)` line after each fixed heading.
- Summary table shows 3 Fixed.
- `**Reports updated:**` lists both files.

Re-run `/fix-all` (no args): now reports `All issues in the report(s) have been resolved. Nothing to do.`

- [ ] **Step 3: Scenario 9 — mixed outcomes**

Setup: create a small review report with 2 issues. Sabotage one so `fix-auto` will Fail (e.g., the issue's `**Location:**` field points to a file that does not exist).

Action: invoke `/fix-all`. Answer "Yes".

Expected:
- One issue completes as Fixed.
- One issue completes as Failed.
- Summary shows 1 Fixed + 1 Failed.
- Only the Fixed one's heading received a `**Status:**` line.
- Re-running `/fix-all` re-presents the Failed issue alone in the pre-flight (the Fixed one is filtered out by Step 1.3).

- [ ] **Step 4: Scenario 10 — severity floor reduces list**

Setup: a review report with at least one CRITICAL, one HIGH, and one MEDIUM issue.

Action: invoke `/fix-all HIGH`. Verify the pre-flight before answering.

Expected: pre-flight `**Severity floor:** HIGH` line shown. List contains only CRITICAL + HIGH issues. MEDIUM issue is absent. Answer "No — abort" to avoid mutating the report; verify `Aborted. No changes made.` output.

- [ ] **Step 5: Scenario 4 — malformed args**

Setup: working directory with at least one review report.

Action: try each of:

1. `/fix-all CRITICAL HIGH` → expect `Multiple severities provided: 'CRITICAL' and 'HIGH'. Pass at most one.`
2. `/fix-all a.md b.md` → expect `Multiple paths provided: 'a.md' and 'b.md'. Pass only one.`
3. `/fix-all HIG` → expect `Could not read file 'HIG'. Make sure the path is correct and the file exists.` (HIG is classified as a path per Rule 3.)

- [ ] **Step 6: Regression — `/fix-report` and `/fix` still work**

Action: invoke `/fix-report` against a report that has unfixed issues. Verify the paginated checklist still appears with 4 issues per page (unchanged from before this work).

Action: invoke `/fix <ID>` against a single issue ID. Verify the Phase 3 approval prompt still appears (unchanged from before this work).

Expected: both commands behave byte-identically to their pre-1.15.0 behavior. (If anything changed here, something in Tasks 1–8 leaked outside `fix-all.md` — investigate before continuing.)

- [ ] **Step 7: Document the results**

If all six steps above pass, the work is done. If any deviate from the spec, file a follow-up note in the spec's Section 8 (Open risks) or open a fix task.

No commit for this task — verification only.

---

## Task 10: Final verification + cleanup

**Files:** None modified directly. Confirms the implementation is internally consistent.

- [ ] **Step 1: Check the git log**

Run:

```bash
git log --oneline -10
```

Expected output: shows roughly 8 new commits from Tasks 1–8, in order. (Task 9 has no commit.)

- [ ] **Step 2: Verify version parity across the four sources**

Run:

```bash
echo "plugin.json:" && jq -r .version plugins/code-review/.claude-plugin/plugin.json
echo "docs/plugins/code-review.md:" && grep -E '^\*\*Version:\*\*' docs/plugins/code-review.md
echo "README.md:" && grep 'code-review.md' README.md | grep -oE '\| [0-9]+\.[0-9]+\.[0-9]+ \|'
echo "marketplace.json:" && jq -r '.plugins[] | select(.name == "code-review") | .version' .claude-plugin/marketplace.json
```

Expected output: all four lines show `1.15.0`.

**If `marketplace.json` shows a different version:** stop. The previous marketplace registration may need updating. Run:

```bash
jq '(.plugins[] | select(.name == "code-review") | .version) |= "1.15.0"' .claude-plugin/marketplace.json > /tmp/mp.json && mv /tmp/mp.json .claude-plugin/marketplace.json
git add .claude-plugin/marketplace.json
git commit -m "chore(marketplace): sync code-review version to 1.15.0"
```

- [ ] **Step 3: Final state check**

Run: `git status`

Expected output: `nothing to commit, working tree clean`.

The implementation is complete.

---

## Spec coverage check

| Spec section | Implemented by |
|---|---|
| 2 — Scope decisions | Tasks 1–8 collectively; framing decisions reflected in fix-all.md Step 1.4 and docs/plugins/code-review.md |
| 3 — Out of scope | Verified by the "explicitly not changed" list above; Task 9 Step 6 regression-tests `/fix-report` and `/fix` |
| 4.1 — Frontmatter | Task 1 Step 1 |
| 4.2 — Argument grammar | Task 1 Step 1 (the grammar section) + Task 3 Step 1 (the parser in Step 2.1) |
| 4.3 — Progress tasks | Task 1 Step 1 |
| 4.4 — Step 1 (parse reports) | Task 2 |
| 4.5 — Step 2 (filter + pre-flight + gate) | Task 3 |
| 4.6 — Step 3 (sequential fix-auto) | Task 4 |
| 4.7 — Step 4 (mark + summary) | Task 5 |
| 5 — Plugin metadata changes | Task 6 (docs/plugins) + Task 7 (README) + Task 8 (plugin.json) + Task 10 Step 2 (marketplace.json check) |
| 6 — Files not changed | Enforced by Task structure (no task modifies the listed files); Task 9 Step 6 verifies behaviorally |
| 7 — Manual test plan (scenarios 1, 4, 5, 9, 10 = minimum subset) | Task 9 |
| 7 — Remaining scenarios (2, 3, 6, 7, 8, 11–14) | Run during user QA pass after this plan completes; not blocking for the work to be declared done |
| 8 — Risks | Already documented in the spec; no runtime mitigation needed |
| 9 — Acceptance criteria | All bullets verified by Tasks 9–10 combined |

---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(pytest:*), Bash(ruff:*), Bash(mypy:*), Bash(semgrep:*), Bash(npm test:*), Bash(eslint:*), Bash(tsc:*), Bash(bandit:*), Bash(trufflehog:*), Bash(command:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskList, AskUserQuestion, Task
description: Fix unfixed issues from a review/QA report after a single yes/no confirmation — everything except issues flagged needs-decision. Optional severity floor.
model: opus
argument-hint: [CRITICAL|HIGH|MEDIUM|LOW] [path-to-report]
---

# Fix All Issues From Report

You are an expert code fixer that reads one or more saved code review reports, presents every unfixed issue as a pre-flight summary (issues flagged `needs-decision` are listed as skipped), asks for a single yes/no confirmation, and then fixes the whole batch sequentially via the `fix-auto` subagent.

This command is the bulk counterpart to `/fix-report`. Where `/fix-report` paginates issues into a checklist and asks the user to pick which to fix, `/fix-all` fixes everything except `needs-decision`-flagged issues (optionally filtered by minimum severity) after one confirmation. Use it when you trust the report and want every auto-fixable issue addressed.

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

<a id="abort-helper"></a>

## Abort helper

If an abort condition is hit at any step, follow this single procedure
instead of repeating it at every abort site:

1. Mark the current `in_progress` task as `completed` using TaskUpdate.
   (TaskUpdate accepts the `in_progress → completed` transition directly,
   so no intermediate state is needed.)
2. Mark all remaining `pending` tasks as `completed` using TaskUpdate.
3. Display the abort message described at the abort site.
4. Stop execution.

This helper assumes the MANDATORY FIRST STEP has already transitioned
task 1 to `in_progress`. All abort sites in Steps 0–4 satisfy this
precondition because the MANDATORY FIRST STEP runs before Step 0.

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
8. **Flag-like tokens are not recognized.** `/fix-all` has no `--help`, `-h`, `--severity=…`, or similar flags. Per Rule 3, any non-severity token (including `--help`, `-h`, `--verbose`, etc.) classifies as a `path` and will fail in Step 1.1 with `Could not read file '--help'. Make sure the path is correct and the file exists.` For general slash-command help use Claude Code's `/help`; for `/fix-all` usage details see [`docs/plugins/code-review.md`](../../../docs/plugins/code-review.md) (`/fix-all` section).

**Severity floor semantics:** the floor includes itself and everything *above* it. `HIGH` matches HIGH+CRITICAL. `MEDIUM` matches MEDIUM+HIGH+CRITICAL. `LOW` matches all four levels.

---

## Step 0: Parse `$ARGUMENTS`

This step runs **before** any filesystem I/O so that argument-grammar errors (Rule 1 "Multiple severities", Rule 2 "Multiple paths") surface before "No reports found" or "Could not read file" errors from Step 1.

Split `$ARGUMENTS` on whitespace into tokens. Track two slots: `severity_floor` (initially unset) and `path` (initially unset).

For each token:

- If the token matches `^(CRITICAL|HIGH|MEDIUM|LOW)$` case-insensitively:
  - If `severity_floor` is already set, follow the [Abort helper](#abort-helper) procedure, using the error from Rule 1 as the abort message.
  - Otherwise set `severity_floor` to the uppercase form.
- Otherwise (any non-severity token):
  - If `path` is already set, follow the [Abort helper](#abort-helper) procedure, using the error from Rule 2 as the abort message.
  - Otherwise set `path` to the token.

Empty `$ARGUMENTS` leaves both unset (auto-merge mode, no filter).

These resolved values are consumed by Step 1.1 (mode detection: `path` set → single-file; unset → auto-merge) and Step 2.2 (severity-floor filter application).

---

## Step 1: Parse Report(s)

### Step 1.1: Resolve files to read

Determine the input mode based on the `path` value resolved in Step 0 above.

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

  Follow the [Abort helper](#abort-helper) procedure.

**Single-file mode** — path token provided:

`files = [<path>]`

If the file does not exist or cannot be read:

> Error: Could not read file `<path>`. Make sure the path is correct and the file exists.

Follow the [Abort helper](#abort-helper) procedure.

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

Follow the [Abort helper](#abort-helper) procedure.

**If all issues have a `**Status:**` field (all fixed/partially fixed):**

> All issues in the report(s) have been resolved. Nothing to do.

Follow the [Abort helper](#abort-helper) procedure.

**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

---

## Step 2: Filter and Pre-flight Summary

### Step 2.1: Argument values resolved

Argument parsing happened in Step 0 — `severity_floor` and `path` are already resolved (each is either set or unset). No work is performed in this sub-step; proceed to Step 2.2.

### Step 2.2: Apply severity floor

If `severity_floor` is set, filter the unfixed-issues list from Step 1 to keep only issues whose severity is `severity_floor` or higher. The severity ranking is:

| Floor | Keeps |
|---|---|
| CRITICAL | CRITICAL |
| HIGH | CRITICAL + HIGH |
| MEDIUM | CRITICAL + HIGH + MEDIUM |
| LOW | all four levels |

If `severity_floor` is unset, the list is unchanged.

**needs-decision issues are exempt from the floor.** An issue whose block carries `**Fix-policy:** needs-decision` (or any non-`auto` policy — the same set Step 2.2.5 partitions) is **not** dropped for being below the floor; it passes through to Step 2.2.5, which moves it into the `needs_decision` (skipped-but-surfaced) list. This preserves the guarantee that needs-decision issues are always listed. Applying the floor *before* the split (the naive order) would silently discard a sub-floor needs-decision issue from both the fix list and the "Requires user decision" list — the failure this exemption prevents. The floor still drops sub-floor `auto` issues as normal, so reading each issue's `**Fix-policy:**` here is required to decide exemption.

**Edge case — zero issues after filter:** if the filtered list is empty and `severity_floor` was set — i.e. no issue survives, neither a floor-passing `auto` issue nor a floor-exempt needs-decision issue — output:

> No issues match severity floor `<FLOOR>`. Nothing to fix.

Follow the [Abort helper](#abort-helper) procedure. (When `severity_floor` is unset and the list is empty, Step 1.5 has already terminated the command. When only needs-decision issues survive the floor, the list is non-empty and Step 2.2.5's edge case surfaces them instead.)

### Step 2.2.5: Apply Fix-policy filter

Partition the current list on each issue block's `**Fix-policy:**` field:

- `**Fix-policy:** needs-decision` → move to a `needs_decision` list — skipped from fixing, listed in the pre-flight (Step 2.4) and final summary (Step 4.2).
- `**Fix-policy:** auto`, or **no Fix-policy field at all** → keep in the fix list. **Absent field ⇒ `auto`** — all pre-existing review/QA reports behave exactly as before this filter existed.
- Any other (malformed/unrecognized) `**Fix-policy:**` value → treat as `needs-decision` (fail safe — never auto-fix on a policy you cannot parse).

There is no override flag (Rule 8: flag-like tokens classify as paths). To fix a skipped issue, use `/fix <ID>` or `/fix-report`.

**Edge case — zero issues after filter:** if the fix list is now empty and `needs_decision` is non-empty, output:

> All remaining issues are flagged `needs-decision` and require your decision. Use `/fix-report` to select them interactively, or `/fix <ID>` for a single issue.

Follow the [Abort helper](#abort-helper) procedure.

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
**Requires user decision (skipped):** <needs_decision count> issues (<comma-separated IDs>)        <-- omit this line when zero

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

Follow the [Abort helper](#abort-helper) procedure.

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

---

## Step 3: Fix All Selected Issues

### Step 3.1: Sequential fix execution

For each issue in the filtered + sorted list from Step 2.3, in order, **sequentially** (one at a time, wait for completion):

1. **Print progress** before invoking the subagent so the user has a heartbeat during the long run:

   > Fixing issue N/<total>: [<SEVERITY>] <ID>: <Title>

   `N` is the 1-based index in the filtered+sorted list, `<total>` is the total count from the pre-flight summary, and the rest comes from the extracted issue block. A 30-issue run can take 10–30 minutes (~20–60 s per issue, see the Performance section in `docs/plugins/code-review.md`), so this line is the only signal the user gets between subagent invocations.

2. Use the Task tool with these parameters:
   - subagent_type: `"code-review:fix-auto"`
   - run_in_background: `false`
   - description: `"Auto-fix: [<SEVERITY>] <Title>"`
   - prompt: the full issue block from the report (everything extracted in Step 1.2 for this issue — heading line through the next `###` / `---` / EOF; this includes severity, title, location, category, OWASP, CWE, effort, problem, impact, remediation with code examples, and the `**Source:**` field if present — `fix-auto`'s Phase 1 field table does not consume `**Source:**` but passing the full block keeps the input format consistent across commands).

3. Collect the result and determine status:
   - **Fixed** — subagent report says "Fixed" and all verifications passed
   - **Partially Fixed** — subagent report says "Partially Fixed"
   - **Failed** — subagent report says "Failed" OR subagent errored (timeout, crash, malformed response)

4. Store the status keyed to the issue's `source_file` and ID. Continue to the next issue regardless of outcome — **continue on failure**, never break the loop. This matches `/fix-report` Step 3.

**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

---

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

### Step 4.1.5: Verify Status writes

After invoking `Edit` for each Fixed/Partially Fixed issue in Step 4.1, **re-read the source file** with the `Read` tool and confirm the `**Status:**` line is present immediately below the issue's heading. The `Edit` tool already raises a hard error when `old_string` does not match, but the heading may have shifted between extraction (Step 1.2) and write-back (Step 4.1) — for example because a prior issue in the same file was edited and changed surrounding context, or because the heading was concurrently modified. The verify pass catches both classes of silent drift.

For each issue, the verification is:

1. Read the source file.
2. Locate the issue's `### [SEVERITY] ID: Title` heading.
3. Confirm the next non-blank line below the heading is `**Status:** ✅ Fixed (YYYY-MM-DD)` (for Fixed) or `**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)` (for Partially Fixed), with today's date.

If verification fails for any issue:

- Append `{issue_id, source_file, reason}` to a `status_write_failures` list (where `reason` is one of `edit-errored`, `status-line-missing`, `status-line-wrong-text`).
- Do **not** retry inside this step — surface the failure in Step 4.2 instead. A silent retry could mask a real heading-drift bug, and the next `/fix-all` run already retries by design (the issue stays unfixed and reappears).

This list is consumed by Step 4.2's "Status write failures" block.

**Restart safety:** Because Step 4.1.5 verifies every `**Status:**` write, re-running `/fix-all` is safe: any issue whose Status line was successfully written in a prior run is filtered out by Step 1.3 and will not be re-fixed. Only issues that failed verification (or were never attempted) are eligible for re-processing.

### Step 4.2: Display fix summary

```markdown
## Fix Summary

| # | Issue | Status |
|---|-------|--------|
| 1 | [SEVERITY] ID: Title — path:line | STATUS_ICON STATUS_TEXT |
| 2 | [SEVERITY] ID: Title — path:line | STATUS_ICON STATUS_TEXT |

**Fixed:** N | **Partially Fixed:** N | **Failed:** N

**Requires user decision (skipped):**
- [SEVERITY] ID: Title — Drift-class: <class>

Use `/fix-report` or `/fix <ID>` to address these.

**Reports updated:**
- <source-file-1>
- <source-file-2>
```

Omit the `**Requires user decision (skipped):**` block entirely when the `needs_decision` list from Step 2.2.5 is empty. `<class>` is the issue's `**Drift-class:**` value; render `—` if the field is missing.

In single-file mode the list contains exactly one entry. In auto-merge mode, list each distinct `source_file` that was edited (deduplicated). Files that received no Status writes (all Failed, or no selections from that file) are omitted; if no file was edited at all, omit the entire `**Reports updated:**` block.

Status icons: Fixed = ✅, Partially Fixed = ⚠️, Failed = ❌.

**Status write failures (Step 4.1.5):** if the `status_write_failures` list collected in Step 4.1.5 is non-empty, append the following block immediately after the `**Reports updated:**` list (or in its place, if no file was successfully updated):

```markdown
**Status write failures:**
- <issue-id> in <source-file> — <reason>
- ...

Re-run `/fix-all` to retry, or manually add the `**Status:**` line below each heading.
```

Where `<reason>` is the value recorded in Step 4.1.5 (`edit-errored`, `status-line-missing`, or `status-line-wrong-text`). The code change itself already landed for these issues — only the report annotation is missing, which is why the re-run-or-manual-edit guidance is non-destructive. Omit this block entirely if `status_write_failures` is empty.

**Task Update:** Mark task 4 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**

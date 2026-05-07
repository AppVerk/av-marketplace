# QA × Code-Review Synergy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/fix` and `/fix-report` (code-review plugin) able to repair QA-detected issues, by aligning the QA report format with code-review's issue format and extending the fix tooling to operate on QA reports.

**Architecture:** Two complementary changes — (a) QA report format becomes a strict superset of code-review's issue format (same parser, QA-specific fields tolerated as ignored extras); (b) code-review's `/fix` routes by prefix to `docs/testing/reports/` when the prefix is `QA`, and `/fix-report`'s argument becomes optional with auto-merge of newest reports from both directories, plus a per-issue source-file mapping so status updates land in the right file.

**Tech Stack:** Markdown-based plugin instructions (no automated tests). Verification is manual per task: read the modified file or grep for expected strings.

**Spec:** [docs/superpowers/specs/2026-05-07-qa-code-review-synergy-design.md](../specs/2026-05-07-qa-code-review-synergy-design.md)

**Commit convention:** Every commit MUST use `AV_COMMIT_SKILL=1` env var to bypass the pre-commit hook (the `commit:commit` skill is the canonical path; this plan inlines messages for consistency). Conventional Commits format. No `Co-Authored-By` lines. Do NOT push.

**Versioning:** Per-task commits do NOT bump plugin versions. Versions are bumped only in the final release task (Task 8), matching the marketplace's existing convention (see commit `42cc318`).

---

## File Structure

| File | Role | Tasks |
|---|---|---|
| `plugins/qa/skills/report-format/SKILL.md` | QA report-format skill — full rewrite of issue template | Task 1 |
| `plugins/qa/commands/run.md` | QA runner — Step 6 field derivation, Step 8 fix guidance | Task 2 |
| `plugins/code-review/commands/fix.md` | `/fix` Phase 0 — regex extension + prefix routing | Task 3 |
| `plugins/code-review/commands/fix-report.md` | `/fix-report` — auto-merge + source-file mapping | Tasks 4, 5 |
| `docs/plugins/code-review.md` | Code-review docs — Category mapping row, /fix + /fix-report behavior | Task 6 |
| `docs/plugins/qa.md` | QA docs — synergy section + new format example | Task 7 |
| `plugins/qa/.claude-plugin/plugin.json` | QA plugin version → 2.0.0 | Task 8 |
| `plugins/code-review/.claude-plugin/plugin.json` | code-review plugin version → 1.13.0 | Task 8 |
| `.claude-plugin/marketplace.json` | Marketplace registry — bump both versions | Task 8 |
| `README.md` | Available Plugins table — bump both versions | Task 8 |

---

## Task 1: Rewrite QA report-format skill

**Files:**
- Modify: `plugins/qa/skills/report-format/SKILL.md` (full rewrite)

The current skill has an internal contradiction (top template uses `### QA-001 [SEVERITY] X`; the "Compatibility" section uses `### [SEVERITY] QA-001: X`). We adopt the canonical code-review-compatible format as the only template.

- [ ] **Step 1: Replace the file with the new content**

Use the `Write` tool to overwrite `plugins/qa/skills/report-format/SKILL.md` with the following full content:

````markdown
---
name: report-format
description: Test report format with QA-XXX issue IDs compatible with code-review plugin. Defines report structure, severity levels, issue format, and detailed results.
---

# Test Report Format

## File Conventions

- **Location:** `docs/testing/reports/`
- **Naming:** `YYYY-MM-DD-<topic>-report.md` where `<topic>` matches the test plan topic
- **Screenshots:** `docs/testing/reports/screenshots/` (referenced from report)
- **Create directories if needed:** `mkdir -p docs/testing/reports/screenshots`

---

## Report Structure

Every test report MUST follow this exact structure:

~~~markdown
# Test Report: <title>

## Summary
- Total: <N> | Pass: <N> | Fail: <N> | Skip: <N>
- Plan: <path to test plan file>
- Date: <YYYY-MM-DD>
- Duration: <approximate execution time>

## Issues Found

### [SEVERITY] QA-001: <issue title>

**ID:** QA-001
**Location:** `<source file:line>`
**Category:** Testing

**Problem:**
- Expected: <what should have happened>
- Actual: <what actually happened>

**Impact:**
<what breaks if unfixed — optional but recommended>

**Remediation:**
<best-effort suggestion in natural language; no code block required>

**Scenario:** <FE-XX or BE-XX>
**Response:** `<response body or error>` (BE only)
**Screenshot:** <path to screenshot> (FE only)

### [SEVERITY] QA-002: <issue title>
...

## Detailed Results

### Pass: FE-01: <scenario name>
### Pass: BE-01: <scenario name>
### Fail: BE-03: <scenario name> — see QA-001
### Skip: FE-03: <scenario name> (reason)
~~~

---

## Issue ID Assignment

**Prefix:** `QA` (all issues use the same prefix, mapped to `Category: Testing` in the code-review Category→Prefix table)

**Algorithm:**
1. Initialize counter: `qa_count = 0`
2. For each failed scenario (in order of appearance):
   - Increment `qa_count`
   - Format ID as `QA-{NNN}` with zero-padded 3-digit counter
   - Example: QA-001, QA-002, QA-003

**Edge case issues from a single scenario get their own ID:**
- If FE-01 main flow passes but edge case "empty form" fails → that edge case gets QA-001
- If BE-03 main flow fails AND edge case "duplicate" also fails → main flow gets QA-001, edge case gets QA-002

---

## Severity Levels

| Severity | Criteria | Examples |
|----------|----------|---------|
| **CRITICAL** | Application crash, data loss, security bypass | 500 errors, unhandled exceptions, auth bypass |
| **HIGH** | Core functionality broken, wrong data returned | Wrong status code, incorrect data in response, DB state inconsistent |
| **MEDIUM** | Non-core functionality broken, degraded UX | UI element not responding, slow response, missing validation |
| **LOW** | Cosmetic issues, minor inconsistencies | Wrong error message text, minor layout issue |

---

## Issue Format Details

Each issue MUST include the canonical code-review fields:

1. **Heading:** `### [SEVERITY] QA-NNN: <title>` — severity in brackets, ID with colon, then title
2. **`**ID:** QA-NNN`** — repeated for the parser
3. **`**Location:** ` `` `path:line` `` `** — best-effort source identification (route, endpoint, stack trace). When truly unidentifiable, use placeholder `unknown:0` and add a note in `Problem`. The `/fix` command will prompt the user for the location at fix time.
4. **`**Category:** Testing`** — constant for QA issues; maps to the `QA` prefix in the canonical Category→Prefix table.
5. **`**Problem:**`** — Expected vs Actual rendered as a bullet list inside this field.
6. **`**Remediation:**`** — best-effort suggestion in natural language. No code block required (the `fix-auto` agent will generate the code).

Optional fields:

- **`**Impact:**`** — what breaks if unfixed.

QA-specific extras (kept for testing context; ignored by the code-review parser):

- **`**Scenario:**`** — `FE-XX` or `BE-XX` reference
- **`**Response:**`** — response body or error message (BE only)
- **`**Screenshot:**`** — screenshot path (FE only)

---

## Example: BE Issue

~~~markdown
### [HIGH] QA-001: POST /api/users returns 500 instead of 201

**ID:** QA-001
**Location:** `src/api/users.py:45`
**Category:** Testing

**Problem:**
- Expected: POST /api/users with valid body should return 201 and create the user.
- Actual: Endpoint returns 500 with `KeyError: 'email'` raised in `users.py:48`.

**Impact:**
Blocks new account creation.

**Remediation:**
Schema requires `email` but the `create_user` handler does not validate the key's presence. Add Pydantic field validation or an early 422 return for the missing field.

**Scenario:** BE-03 — Create new user with valid payload
**Response:** `{"detail": "Internal Server Error"}`
~~~

## Example: FE Issue

~~~markdown
### [MEDIUM] QA-002: Logout button does not respond to click

**ID:** QA-002
**Location:** `src/components/Header.tsx:23`
**Category:** Testing

**Problem:**
- Expected: clicking Logout fires POST /api/auth/logout and redirects to /login.
- Actual: click triggers no request; user remains logged in.

**Impact:**
User cannot log out — UX regression with potential security implications on shared machines.

**Remediation:**
Verify the onClick handler in `src/components/Header.tsx:23`. The most likely cause is a missing `mutate()` call or an unbound handler.

**Scenario:** FE-05 — Logout flow
**Screenshot:** `docs/testing/reports/screenshots/qa-002-logout.png`
~~~

---

## Detailed Results Format

List ALL scenarios (pass, fail, skip) in order:

```markdown
## Detailed Results

### Pass: FE-01: Homepage renders correctly
### Pass: FE-02: Login form validation
### Fail: FE-03: Logout button — see QA-001
### Pass: BE-01: GET /api/users returns list
### Fail: BE-03: POST /api/users duplicate handling — see QA-002
### Skip: FE-05: Mobile responsive layout (Playwright MCP unavailable)
```

- **Pass:** just the status and scenario name
- **Fail:** status, scenario name, reference to QA-XXX issue
- **Skip:** status, scenario name, reason in parentheses

---

## Compatibility with code-review

The QA-XXX format is identical in structure to code-review's other prefixes (SEC, PERF, ARCH, MAINT, DOC). This means:

- `/fix QA-001` works the same as `/fix SEC-001` — the `/fix` command routes by prefix to `docs/testing/reports/` instead of `docs/reviews/`.
- `/fix-report` (without an argument) auto-merges the newest report from `docs/reviews/` and the newest from `docs/testing/reports/`, presenting one unified checklist.

The `Testing → QA` row is part of the canonical Category→Prefix mapping in `docs/plugins/code-review.md`.

---

## Report Quality Checklist

Before saving the report, verify:

- [ ] Summary counts match detailed results (total = pass + fail + skip)
- [ ] Every failed scenario has a `### [SEVERITY] QA-NNN: Title` heading in the Issues Found section
- [ ] Every QA-NNN issue has the required fields: `ID`, `Location`, `Category: Testing`, `Problem` (with Expected/Actual bullets), `Remediation`
- [ ] Screenshots referenced in issues actually exist on disk
- [ ] No placeholder text (TBD, TODO)
````

- [ ] **Step 2: Verify the new format is in place**

Run:

```bash
grep -c '### \[SEVERITY\] QA-001:' plugins/qa/skills/report-format/SKILL.md
```

Expected: `2` (one in the Report Structure template, one in the Issue Format Details — depending on phrasing; >= 1 is acceptable). Also verify the OLD heading shape is gone:

```bash
grep -c '### QA-001 \[SEVERITY\]' plugins/qa/skills/report-format/SKILL.md
```

Expected: `0`.

- [ ] **Step 3: Commit**

```bash
AV_COMMIT_SKILL=1 git add plugins/qa/skills/report-format/SKILL.md && git commit -m "feat(qa)!: align report-format skill with code-review issue format

Rewrite the QA issue template to use the canonical code-review heading
shape (### [SEVERITY] QA-NNN: Title) and required fields (ID, Location,
Category, Problem, Remediation). Keep QA-specific extras (Scenario,
Response, Screenshot) — the code-review parser ignores unknown fields.

This is a breaking change for any consumer parsing the previous format."
```

---

## Task 2: Update QA `/qa:run` command — derive new fields and post-run guidance

**Files:**
- Modify: `plugins/qa/commands/run.md` (Step 6 field derivation, Step 8 post-run guidance)

The runner already loads the `report-format` skill and follows its template, but the raw output from `fe-tester`/`be-tester` agents needs to be mapped to the new fields (`Location`, `Problem`, `Remediation`). Step 8 currently mentions `/fix QA-001 (coming soon)` — replace with real guidance.

- [ ] **Step 1: Update Step 6 to spell out field derivation**

Open `plugins/qa/commands/run.md`. Find the block starting with `### Step 6: Generate Report` and the numbered list inside it. Use Edit:

`old_string`:
```
Using the skill's format:

1. **Count results:** tally pass/fail/skip across all scenarios
2. **Assign QA-XXX IDs:** to each failed scenario/edge case (see report-format skill for algorithm)
3. **Determine severity** for each failure:
   - 500 errors, crashes, data loss → CRITICAL
   - Wrong status code, incorrect data → HIGH
   - UI glitch, missing validation message → MEDIUM
   - Cosmetic, minor text issues → LOW
4. **Build the report** following the exact template from the skill
5. **Build detailed results** listing all scenarios with status
```

`new_string`:
```
Using the skill's format:

1. **Count results:** tally pass/fail/skip across all scenarios
2. **Assign QA-XXX IDs:** to each failed scenario/edge case (see report-format skill for algorithm)
3. **Determine severity** for each failure:
   - 500 errors, crashes, data loss → CRITICAL
   - Wrong status code, incorrect data → HIGH
   - UI glitch, missing validation message → MEDIUM
   - Cosmetic, minor text issues → LOW
4. **Derive issue fields** from raw agent output (the skill's Issue Format Details documents each field):
   - **Location** — best-effort source file:line. For BE failures: infer from request URL → routing module (e.g., `POST /api/users` → `src/api/users.py`); use stack trace lines from the response body when present. For FE failures: infer from the failing component or route. When truly unidentifiable, use `unknown:0` (the `/fix` command will prompt the user).
   - **Category** — always `Testing` (constant for QA).
   - **Problem** — render the failure as Expected/Actual bullets; include the request and response summary for BE.
   - **Remediation** — write a one- to three-sentence best-effort suggestion in natural language (no code block required).
   - **Impact** (optional) — describe what user-visible flow is broken.
   - **Scenario / Response / Screenshot** — copy from the agent's raw result.
5. **Build the report** following the exact template from the skill
6. **Build detailed results** listing all scenarios with status
```

- [ ] **Step 2: Update Step 8 fix guidance**

Find the Step 8 block in the same file with the "If issues were found:" message. Use Edit:

`old_string`:
```
If issues were found:

> To fix issues in future iterations, use:
> `/fix QA-001` (coming soon)
```

`new_string`:
```
If issues were found:

> **Found {N} issues.** To fix them:
>
> `/fix-report` — auto-merge with the newest code-review report (if any) and fix interactively.
>
> `/fix-report docs/testing/reports/<filename>` — fix issues from this QA report only.
>
> `/fix QA-001` — fix a single issue by ID. Routes by prefix to `docs/testing/reports/`.
```

- [ ] **Step 3: Verify the edits landed**

Run:

```bash
grep -c "Derive issue fields" plugins/qa/commands/run.md
grep -c "coming soon" plugins/qa/commands/run.md
grep -c "auto-merge with the newest code-review report" plugins/qa/commands/run.md
```

Expected: `1`, `0`, `1`.

- [ ] **Step 4: Commit**

```bash
AV_COMMIT_SKILL=1 git add plugins/qa/commands/run.md && git commit -m "feat(qa): derive code-review-compatible fields and update fix guidance

Step 6 now spells out how to map raw fe-tester/be-tester output into
the new issue fields (Location best-effort, Category=Testing, Problem
as Expected/Actual bullets, Remediation as natural-language suggestion).
Step 8 replaces the 'coming soon' placeholder with real /fix and
/fix-report guidance, including auto-merge."
```

---

## Task 3: Extend `/fix` Phase 0 — regex + prefix routing

**Files:**
- Modify: `plugins/code-review/commands/fix.md` (Input Handling block, Step 0.1)

Two edits: extend the ID regex to include `QA`, and replace the single-directory lookup with prefix-based routing.

- [ ] **Step 1: Extend the ID regex**

Open `plugins/code-review/commands/fix.md`. Find the Input Handling section. Use Edit:

`old_string`:
```
- **ID Mode:** If `$ARGUMENTS` matches pattern `^(SEC|PERF|ARCH|MAINT|DOC)-\d{3}$`
  - Examples: `SEC-001`, `PERF-042`, `ARCH-001`, `MAINT-999`, `DOC-001`
  - Action: Proceed to Phase 0 (Resolve Issue by ID)
```

`new_string`:
```
- **ID Mode:** If `$ARGUMENTS` matches pattern `^(SEC|PERF|ARCH|MAINT|DOC|QA)-\d{3}$`
  - Examples: `SEC-001`, `PERF-042`, `ARCH-001`, `MAINT-999`, `DOC-001`, `QA-001`
  - Action: Proceed to Phase 0 (Resolve Issue by ID)
```

- [ ] **Step 2: Replace Step 0.1 with prefix-based routing**

Find Step 0.1 in the same file. Use Edit:

`old_string`:
```
### Step 0.1: Locate most recent report

List all `.md` files in `docs/reviews/` directory:

```bash
ls -t docs/reviews/*.md 2>/dev/null | head -1
```

Expected: The most recently modified file, e.g., `docs/reviews/2026-03-06-feature-auth.md`

If no files found, display error and stop:

> Error: No saved review reports found in `docs/reviews/`. Run `/review` and save a report first, then use `/fix <ID>`.
```

`new_string`:
```
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
```

- [ ] **Step 3: Verify the edits**

Run:

```bash
grep -c '^(SEC|PERF|ARCH|MAINT|DOC|QA)' plugins/code-review/commands/fix.md
grep -c 'docs/testing/reports' plugins/code-review/commands/fix.md
grep -c 'No saved QA reports found' plugins/code-review/commands/fix.md
```

Expected: `1`, at least `2`, `1`.

- [ ] **Step 4: Commit**

```bash
AV_COMMIT_SKILL=1 git add plugins/code-review/commands/fix.md && git commit -m "feat(code-review): route /fix by ID prefix and accept QA-XXX

Phase 0 now extracts the prefix from \$ARGUMENTS and selects the
report directory accordingly: QA → docs/testing/reports/, others →
docs/reviews/. Regex extended to include QA. Error messages are
prefix-specific. Phase 8 status updates inherit the routing because
they edit the file resolved in Step 0.1."
```

---

## Task 4: `/fix-report` — make argument optional, add file resolution and source mapping

**Files:**
- Modify: `plugins/code-review/commands/fix-report.md` (frontmatter, Step 1.1, Step 1.2, Step 1.5)

Four edits to make the command directory-aware.

- [ ] **Step 1: Update frontmatter — argument-hint and description**

Open `plugins/code-review/commands/fix-report.md`. Find the frontmatter at the top. Use Edit:

`old_string`:
```
description: Parse a saved review report, present issues as a checklist, fix selected issues, and mark them resolved in the report.
model: opus
argument-hint: <path-to-review-report>
```

`new_string`:
```
description: Parse review and QA reports (auto-merge by default), present issues as a checklist, fix selected issues, and mark them resolved in their source reports.
model: opus
argument-hint: [path-to-review-report]
```

- [ ] **Step 2: Replace Step 1.1 with two-mode resolution**

Find Step 1.1 in the same file. Use Edit:

`old_string`:
```
### Step 1.1: Read the report file

Use the Read tool to read the file at the path provided in $ARGUMENTS.

**If the file does not exist or cannot be read:**

Display an error and stop:

> Error: Could not read file `<path>`. Make sure the path is correct and the file exists.
```

`new_string`:
```
### Step 1.1: Resolve files to read

Determine the input mode based on `$ARGUMENTS`:

**Auto-merge mode** — `$ARGUMENTS` is empty:

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

**Single-file mode** — `$ARGUMENTS` is a path:

`files = [$ARGUMENTS]`

If the file does not exist or cannot be read:

> Error: Could not read file `<path>`. Make sure the path is correct and the file exists.

Mark all tasks as `completed` and stop.
```

- [ ] **Step 3: Replace Step 1.2 with per-file extraction and source mapping**

Find Step 1.2 in the same file. Use Edit:

`old_string`:
```
### Step 1.2: Extract issues

Scan the report for issue sections. Each issue starts with a heading matching this pattern:

```
### [SEVERITY] Title
```

Where SEVERITY is one of: CRITICAL, HIGH, MEDIUM, LOW.

For each found issue section, extract the full block — everything from the `### [SEVERITY] Title` line until the next `###` heading or `---` separator or end of file.
```

`new_string`:
```
### Step 1.2: Extract issues with source mapping

For **each file** in the `files` list resolved in Step 1.1:

1. Use the Read tool to read the file content.
2. Scan the content for issue sections. Each issue starts with a heading matching:

```
### [SEVERITY] Title
```

Where SEVERITY is one of: CRITICAL, HIGH, MEDIUM, LOW.

3. For each found issue section, extract the full block — everything from the `### [SEVERITY] Title` line until the next `###` heading or `---` separator or end of file.

4. **Tag each extracted issue with `source_file = <path of the file currently being read>`.** This mapping is used in Step 4.1 when writing back the `**Status:**` line to the originating file.

Aggregate all tagged issues across all files into a single list before applying the filtering steps below. Steps 1.3 (filter fixed) and 1.4 (flag untrusted-provenance) operate on this aggregated list and are otherwise unchanged.
```

- [ ] **Step 4: Update Step 1.5 edge-case messages for multi-file context**

Find Step 1.5 in the same file. Use Edit:

`old_string`:
```
**If no issue sections found at all:**

> No issues found in this report. Make sure the file was generated by `/review`.

Mark all tasks as `completed` and stop.

**If all issues have a Status field (all fixed/partially fixed):**

> All issues in this report have been resolved. Nothing to do.

Mark all tasks as `completed` and stop.
```

`new_string`:
```
**If no issue sections found at all (across all files in `files`):**

> No issues found in the report(s). Make sure the file(s) were generated by `/review` or `/qa:run`.

Mark all tasks as `completed` and stop.

**If all issues have a Status field (all fixed/partially fixed):**

> All issues in the report(s) have been resolved. Nothing to do.

Mark all tasks as `completed` and stop.
```

- [ ] **Step 5: Verify the edits**

Run:

```bash
grep -c 'argument-hint: \[path-to-review-report\]' plugins/code-review/commands/fix-report.md
grep -c 'newest_qa=' plugins/code-review/commands/fix-report.md
grep -c 'source_file' plugins/code-review/commands/fix-report.md
grep -c 'across all files in `files`' plugins/code-review/commands/fix-report.md
```

Expected: `1`, `1`, at least `1`, `1`.

- [ ] **Step 6: Commit**

```bash
AV_COMMIT_SKILL=1 git add plugins/code-review/commands/fix-report.md && git commit -m "feat(code-review): add auto-merge and source-file mapping to /fix-report

Argument becomes optional. With no argument, /fix-report resolves the
newest report in docs/reviews/ AND the newest in docs/testing/reports/,
extracts issues from each, and tags every issue with its source_file
so later steps know where to write status updates. Single-file mode
with an explicit path is preserved."
```

---

## Task 5: `/fix-report` — surface source in checklist, write status to source files, list reports in summary

**Files:**
- Modify: `plugins/code-review/commands/fix-report.md` (Step 2.2 description hint, Step 4.1 per-source-file edit, Step 4.2 summary)

This task completes the `/fix-report` change set started in Task 4.

- [ ] **Step 1: Update Step 2.2 to include source basename in auto-merge mode**

Find the description-format block in Step 2.2. Use Edit:

`old_string`:
```
**For each page**, use AskUserQuestion with these parameters:

- question: "Select issues to fix (page X of Y):" (or "Select issues to fix:" if only one page)
- multiSelect: true
- options: up to 4 issues, each formatted as:
  - label: "[SEVERITY] Short title"
  - description: "path/to/file.py:line — first sentence of the Problem field"
```

`new_string`:
```
**For each page**, use AskUserQuestion with these parameters:

- question: "Select issues to fix (page X of Y):" (or "Select issues to fix:" if only one page)
- multiSelect: true
- options: up to 4 issues, each formatted as:
  - label: "[SEVERITY] Short title"
  - description: "path/to/file.py:line — first sentence of the Problem field"

**Auto-merge mode hint:** When `files` (from Step 1.1) contains more than one path, append a separator and the basename of `issue.source_file` to each option's description so the user can tell which report each issue came from. Example:

```
description: "src/db/queries.py:42 — Code directly concatenates user input · 2026-05-07-feature-auth.md"
```

In single-file mode (one entry in `files`), omit this hint.
```

- [ ] **Step 2: Update Step 4.1 to edit per source file**

Find Step 4.1 in the same file. Use Edit:

`old_string`:
```
### Step 4.1: Mark fixed issues in the report

For each issue that was Fixed or Partially Fixed, edit the report file to add a `**Status:**` line immediately after the issue's `###` heading.

**For Fixed issues**, insert after the `### [SEVERITY] Title` line:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

**For Partially Fixed issues**, insert after the `### [SEVERITY] Title` line:

```
**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)
```

**For Failed issues**, do NOT add a Status line — the issue remains unfixed and will appear again on the next `/fix-report` run.

Use today's date in YYYY-MM-DD format.

Use the Edit tool to insert each status line. The `old_string` should be the `### [SEVERITY] Title` line followed by a newline, and the `new_string` should be the same title line followed by a newline, the status line, and another newline.
```

`new_string`:
```
### Step 4.1: Mark fixed issues in their source reports

For each issue that was Fixed or Partially Fixed, edit **its `source_file`** (from the mapping established in Step 1.2) to add a `**Status:**` line immediately after the issue's `###` heading. In auto-merge mode this means the Edit tool may be invoked against multiple files in a single run; in single-file mode it edits the single source file.

**For Fixed issues**, insert after the `### [SEVERITY] Title` line:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

**For Partially Fixed issues**, insert after the `### [SEVERITY] Title` line:

```
**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)
```

**For Failed issues**, do NOT add a Status line — the issue remains unfixed and will appear again on the next `/fix-report` run.

Use today's date in YYYY-MM-DD format.

Use the Edit tool to insert each status line. The `old_string` should be the `### [SEVERITY] Title` line followed by a newline, and the `new_string` should be the same title line followed by a newline, the status line, and another newline. Pass the issue's `source_file` as the `file_path` parameter.
```

- [ ] **Step 3: Update Step 4.2 summary to list reports**

Find Step 4.2 in the same file. Use Edit:

`old_string`:
```
```markdown
## Fix Summary

| # | Issue | Status |
|---|-------|--------|
| 1 | [SEVERITY] Title — path:line | STATUS_ICON STATUS_TEXT |
| 2 | [SEVERITY] Title — path:line | STATUS_ICON STATUS_TEXT |

**Fixed:** N | **Partially Fixed:** N | **Failed:** N
**Report updated:** <report-file-path>
```
```

`new_string`:
```
```markdown
## Fix Summary

| # | Issue | Status |
|---|-------|--------|
| 1 | [SEVERITY] Title — path:line | STATUS_ICON STATUS_TEXT |
| 2 | [SEVERITY] Title — path:line | STATUS_ICON STATUS_TEXT |

**Fixed:** N | **Partially Fixed:** N | **Failed:** N
**Reports updated:**
- <source-file-1>
- <source-file-2>
```

In single-file mode, the list contains exactly one entry. In auto-merge mode, list each distinct `source_file` that was edited (deduplicated). Files that received no Status writes (all Failed, or no selections from that file) are omitted from the list.
```

- [ ] **Step 4: Verify the edits**

Run:

```bash
grep -c 'Auto-merge mode hint' plugins/code-review/commands/fix-report.md
grep -c 'Mark fixed issues in their source reports' plugins/code-review/commands/fix-report.md
grep -c '\*\*Reports updated:\*\*' plugins/code-review/commands/fix-report.md
grep -c '\*\*Report updated:\*\*' plugins/code-review/commands/fix-report.md
```

Expected: `1`, `1`, `1`, `0` (the old singular phrasing is gone).

- [ ] **Step 5: Commit**

```bash
AV_COMMIT_SKILL=1 git add plugins/code-review/commands/fix-report.md && git commit -m "feat(code-review): write /fix-report status updates to per-issue source files

Step 2.2 description hint includes the source basename in auto-merge
mode so the user can distinguish issues from review vs QA reports.
Step 4.1 edits issue.source_file (multi-file in auto-merge, single-file
otherwise). Step 4.2 lists every distinct source file that received
Status writes, replacing the singular 'Report updated' line."
```

---

## Task 6: Update `docs/plugins/code-review.md`

**Files:**
- Modify: `docs/plugins/code-review.md` (Category mapping table, /fix section, /fix-report section)

Three small additions reflecting the new behavior.

- [ ] **Step 1: Add the `Testing → QA` row to the Category→Prefix mapping table**

Open `docs/plugins/code-review.md`. Find the Issue ID categories table. Use Edit:

`old_string`:
```
| Category        | Prefix |
|-----------------|--------|
| Security        | SEC    |
| Performance     | PERF   |
| Architecture    | ARCH   |
| Maintainability | MAINT  |
| Documentation   | DOC    |
```

`new_string`:
```
| Category        | Prefix |
|-----------------|--------|
| Security        | SEC    |
| Performance     | PERF   |
| Architecture    | ARCH   |
| Maintainability | MAINT  |
| Documentation   | DOC    |
| Testing         | QA     |

The `Testing → QA` row covers issues produced by the `qa` plugin's `/qa:run` command. Reports for QA issues live under `docs/testing/reports/`; `/fix QA-001` and `/fix-report` (auto-merge) handle them transparently.
```

- [ ] **Step 2: Update `/fix` section to mention prefix routing**

Find the `/fix` section paragraph that describes auto-locating the report. Use Edit:

`old_string`:
```
The plugin automatically finds the most recent saved report in `docs/reviews/`, locates the issue by ID, and proceeds with the fix. After fixing, the issue is marked as fixed in the report.
```

`new_string`:
```
The plugin routes by prefix: `QA-NNN` reads from `docs/testing/reports/`, all other prefixes (`SEC`, `PERF`, `ARCH`, `MAINT`, `DOC`) read from `docs/reviews/`. It picks the newest `.md` in the chosen directory, locates the issue by ID, and proceeds with the fix. After fixing, the issue is marked as fixed in the report.
```

- [ ] **Step 3: Update `/fix-report` section to document auto-merge**

Find the `/fix-report` section. Use Edit:

`old_string`:
```
### `/fix-report`

Fix issues from a saved review report. Parses the report, presents unfixed issues as a paginated checklist, fixes selected issues, and marks them resolved in the report file.

```bash
/fix-report docs/reviews/2026-02-20-feature-login.md
```

The command:
1. Reads the report and extracts issues (by `### [SEVERITY] ID: Title` headings)
2. Filters out already-fixed issues (those with a `**Status:**` field)
3. Presents unfixed issues as a multi-select checklist, 4 per page, sorted by severity
4. Fixes selected issues sequentially via the `fix-auto` agent
5. Marks fixed issues in the report with `**Status:** ✅ Fixed (YYYY-MM-DD)`

The report becomes a living document — fixed issues won't appear on subsequent `/fix-report` runs.
```

`new_string`:
```
### `/fix-report`

Fix issues from saved reports. Parses one or more reports, presents unfixed issues as a paginated checklist, fixes selected issues, and marks them resolved in their source files.

```bash
# Auto-merge: newest review + newest QA report (recommended after /review and /qa:run)
/fix-report

# Single file
/fix-report docs/reviews/2026-02-20-feature-login.md
/fix-report docs/testing/reports/2026-02-20-user-flow-report.md
```

The command:
1. Resolves files — auto-merge uses newest from `docs/reviews/` and `docs/testing/reports/`; with an explicit path, uses just that file
2. Reads each file and extracts issues (by `### [SEVERITY] ID: Title` headings), tagging each issue with its `source_file`
3. Filters out already-fixed issues (those with a `**Status:**` field)
4. Presents unfixed issues as a multi-select checklist, 4 per page, sorted by severity. In auto-merge mode the source basename is shown in each option so review issues and QA issues are distinguishable
5. Fixes selected issues sequentially via the `fix-auto` agent
6. Marks fixed issues with `**Status:** ✅ Fixed (YYYY-MM-DD)` in their respective `source_file` (auto-merge may write to multiple files in one run)

The reports become living documents — fixed issues won't appear on subsequent `/fix-report` runs.
```

- [ ] **Step 4: Verify the edits**

Run:

```bash
grep -c '| Testing         | QA     |' docs/plugins/code-review.md
grep -c 'routes by prefix' docs/plugins/code-review.md
grep -c 'Auto-merge: newest review' docs/plugins/code-review.md
```

Expected: `1`, `1`, `1`.

- [ ] **Step 5: Commit**

```bash
AV_COMMIT_SKILL=1 git add docs/plugins/code-review.md && git commit -m "docs(code-review): document QA prefix, /fix routing, and /fix-report auto-merge

Adds Testing→QA to the canonical Category→Prefix mapping. Updates the
/fix section to describe prefix-based directory routing. Updates the
/fix-report section to document auto-merge behavior, source-file
tagging, and the per-source-file status writes."
```

---

## Task 7: Update `docs/plugins/qa.md` with synergy section and new format

**Files:**
- Modify: `docs/plugins/qa.md` (Report Format section, new Synergy section)

- [ ] **Step 1: Replace the Report Format section with the new format**

Open `docs/plugins/qa.md`. Find the `## Report Format` section. Use Edit:

`old_string`:
```
## Report Format

Reports use issue IDs compatible with the code-review plugin:

```
QA-001 [HIGH] POST /api/users returns 500 on duplicate email
QA-002 [MEDIUM] Login button unresponsive after failed attempt
```

**Severity levels:**

| Severity | Criteria |
|----------|----------|
| CRITICAL | Server crash, data loss, security bypass |
| HIGH | Wrong status code, incorrect data returned |
| MEDIUM | Degraded UX, missing validation feedback |
| LOW | Cosmetic issues, minor text problems |
```

`new_string`:
```
## Report Format

Reports use the same issue format as the code-review plugin (`### [SEVERITY] QA-NNN: Title` heading with required fields `ID`, `Location`, `Category: Testing`, `Problem`, `Remediation`). This means `/fix QA-001` and `/fix-report` from the code-review plugin work directly on QA reports.

Example issue:

```markdown
### [HIGH] QA-001: POST /api/users returns 500 instead of 201

**ID:** QA-001
**Location:** `src/api/users.py:45`
**Category:** Testing

**Problem:**
- Expected: POST /api/users with valid body should return 201 and create the user.
- Actual: Endpoint returns 500 with `KeyError: 'email'` raised in `users.py:48`.

**Impact:**
Blocks new account creation.

**Remediation:**
Schema requires `email` but the `create_user` handler does not validate the key's presence. Add Pydantic field validation or an early 422 return for the missing field.

**Scenario:** BE-03 — Create new user with valid payload
**Response:** `{"detail": "Internal Server Error"}`
```

QA-specific extras (`Scenario`, `Response`, `Screenshot`) are kept for testing context; the code-review parser ignores unknown fields.

**Severity levels:**

| Severity | Criteria |
|----------|----------|
| CRITICAL | Server crash, data loss, security bypass |
| HIGH | Wrong status code, incorrect data returned |
| MEDIUM | Degraded UX, missing validation feedback |
| LOW | Cosmetic issues, minor text problems |

## Synergy with code-review

When the `code-review` plugin is also installed, QA-detected issues become repairable through the same workflow as `/review` findings:

- **`/fix QA-001`** — the `/fix` command routes by ID prefix; `QA-NNN` reads the newest report from `docs/testing/reports/`. Other prefixes continue to read from `docs/reviews/`.
- **`/fix-report`** (no argument) — auto-merges the newest report from `docs/reviews/` and the newest from `docs/testing/reports/` into a single checklist. Status writes go back to the originating file.
- **`/fix-report docs/testing/reports/<file>.md`** — explicit single-file mode also works on QA reports.

A typical end-to-end flow:

```bash
/qa:create-plan
/qa:run                 # produces docs/testing/reports/...
/review                 # produces docs/reviews/...
/fix-report             # auto-merge — fix issues from both reports in one pass
```

For full details on `/fix` routing and `/fix-report` auto-merge, see [code-review.md](code-review.md).
```

- [ ] **Step 2: Verify the edits**

Run:

```bash
grep -c '### \[HIGH\] QA-001:' docs/plugins/qa.md
grep -c '## Synergy with code-review' docs/plugins/qa.md
grep -c 'auto-merges the newest report' docs/plugins/qa.md
```

Expected: `1`, `1`, `1`.

- [ ] **Step 3: Commit**

```bash
AV_COMMIT_SKILL=1 git add docs/plugins/qa.md && git commit -m "docs(qa): document new issue format and code-review synergy

Replaces the Report Format section with a full example using the
code-review-compatible heading and required fields. Adds a Synergy
with code-review section showing /fix QA-001, /fix-report auto-merge,
and a typical /qa:run + /review + /fix-report workflow."
```

---

## Task 8: Bump versions, update marketplace, update README

**Files:**
- Modify: `plugins/qa/.claude-plugin/plugin.json` (1.0.0 → 2.0.0)
- Modify: `plugins/code-review/.claude-plugin/plugin.json` (1.12.3 → 1.13.0)
- Modify: `.claude-plugin/marketplace.json` (both versions)
- Modify: `docs/plugins/code-review.md` (version header)
- Modify: `docs/plugins/qa.md` (version header)
- Modify: `README.md` (Available Plugins table — both versions)

Single release commit at the end of the implementation, mirroring the marketplace's existing convention (see `42cc318 chore(release): bump code-review to 1.12.3...`).

- [ ] **Step 1: Bump QA plugin version**

Open `plugins/qa/.claude-plugin/plugin.json`. Use Edit:

`old_string`:
```
  "name": "qa",
  "description": "Automated QA testing plugin — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports compatible with code-review.",
  "version": "1.0.0"
```

`new_string`:
```
  "name": "qa",
  "description": "Automated QA testing plugin — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports compatible with code-review.",
  "version": "2.0.0"
```

- [ ] **Step 2: Bump code-review plugin version**

Open `plugins/code-review/.claude-plugin/plugin.json`. Use Edit:

`old_string`:
```
  "name": "code-review",
  "description": "Perform comprehensive code review for security, performance, and architecture. Optional verification phase for cross-analysis and adversarial review.",
  "version": "1.12.3"
```

`new_string`:
```
  "name": "code-review",
  "description": "Perform comprehensive code review for security, performance, and architecture. Optional verification phase for cross-analysis and adversarial review.",
  "version": "1.13.0"
```

- [ ] **Step 3: Bump versions in marketplace.json**

Open `.claude-plugin/marketplace.json`. Use Edit (operate on each entry separately).

For `code-review`:

`old_string`:
```
      "name": "code-review",
      "source": "./plugins/code-review",
      "description": "Perform comprehensive code review for security, performance, and architecture. Save reviews to file, fix issues via /fix-report with paginated checklist. Persist PR review feedback via /analyze-feedback. Optional verification phase for cross-analysis and adversarial review.",
      "version": "1.12.3",
      "category": "development"
```

`new_string`:
```
      "name": "code-review",
      "source": "./plugins/code-review",
      "description": "Perform comprehensive code review for security, performance, and architecture. Save reviews to file, fix issues via /fix-report with paginated checklist. Persist PR review feedback via /analyze-feedback. Optional verification phase for cross-analysis and adversarial review.",
      "version": "1.13.0",
      "category": "development"
```

For `qa`:

`old_string`:
```
      "name": "qa",
      "source": "./plugins/qa",
      "description": "Automated QA testing plugin — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports compatible with code-review.",
      "version": "1.0.0",
      "category": "testing"
```

`new_string`:
```
      "name": "qa",
      "source": "./plugins/qa",
      "description": "Automated QA testing plugin — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports compatible with code-review.",
      "version": "2.0.0",
      "category": "testing"
```

- [ ] **Step 4: Update version headers in plugin docs**

Open `docs/plugins/code-review.md`. Use Edit:

`old_string`:
```
**Version:** 1.12.3
```

`new_string`:
```
**Version:** 1.13.0
```

Open `docs/plugins/qa.md`. Use Edit:

`old_string`:
```
**Version:** 1.0.0
```

`new_string`:
```
**Version:** 2.0.0
```

- [ ] **Step 5: Update README Available Plugins table**

Open `README.md`. Use Edit (two rows changed).

Row for Code Review — update version:

`old_string`:
```
| [Code Review](docs/plugins/code-review.md) | 1.12.3 | Security, architecture, and code quality analysis with OWASP compliance. Unique issue IDs (SEC-001, PERF-001, DOC-001, ...), fix by ID via `/fix SEC-001` or batch via `/fix-report`. Persist PR review feedback via `/analyze-feedback`. Built-in cross-analysis and adversarial review via Cross-Verifier + Challenger |
```

`new_string`:
```
| [Code Review](docs/plugins/code-review.md) | 1.13.0 | Security, architecture, and code quality analysis with OWASP compliance. Unique issue IDs (SEC-001, PERF-001, DOC-001, QA-001, ...), fix by ID via `/fix SEC-001` (or `/fix QA-001`) or batch via `/fix-report` (auto-merges review and QA reports). Persist PR review feedback via `/analyze-feedback`. Built-in cross-analysis and adversarial review via Cross-Verifier + Challenger |
```

Row for QA — update version and description:

`old_string`:
```
| [QA](docs/plugins/qa.md) | 1.0.0 | Automated QA testing — analyzes code changes, generates test plans (`/qa:create-plan`), executes FE (Playwright) and BE (API/DB) tests (`/qa:run`), and produces reports with `QA-XXX` issue IDs |
```

`new_string`:
```
| [QA](docs/plugins/qa.md) | 2.0.0 | Automated QA testing — analyzes code changes, generates test plans (`/qa:create-plan`), executes FE (Playwright) and BE (API/DB) tests (`/qa:run`), and produces reports compatible with code-review's `/fix QA-001` and `/fix-report` auto-merge |
```

- [ ] **Step 6: Verify all version bumps**

Run:

```bash
grep -c '"version": "2.0.0"' plugins/qa/.claude-plugin/plugin.json
grep -c '"version": "1.13.0"' plugins/code-review/.claude-plugin/plugin.json
grep -c '"version": "1.13.0"' .claude-plugin/marketplace.json
grep -c '"version": "2.0.0"' .claude-plugin/marketplace.json
grep -c '\*\*Version:\*\* 1.13.0' docs/plugins/code-review.md
grep -c '\*\*Version:\*\* 2.0.0' docs/plugins/qa.md
grep -c '| 1.13.0 |' README.md
grep -c '| 2.0.0 |' README.md
```

Expected: each command returns at least `1`. The README rows return exactly `1` for each respective version.

- [ ] **Step 7: Commit the release**

```bash
AV_COMMIT_SKILL=1 git add plugins/qa/.claude-plugin/plugin.json plugins/code-review/.claude-plugin/plugin.json .claude-plugin/marketplace.json docs/plugins/code-review.md docs/plugins/qa.md README.md && git commit -m "chore(release): bump qa to 2.0.0 and code-review to 1.13.0

QA 2.0.0 — MAJOR: incompatible report format change. Issue heading
shape now matches code-review's canonical format (### [SEVERITY]
QA-NNN: Title) with required fields (ID, Location, Category=Testing,
Problem, Remediation).

code-review 1.13.0 — MINOR: /fix accepts QA prefix and routes to
docs/testing/reports/; /fix-report argument is optional with
auto-merge of newest reports from both directories.

Marketplace, README, and plugin doc version headers updated."
```

---

## Self-Review

Spec coverage check, run before finishing:

| Spec section | Implementing tasks |
|---|---|
| Format change for QA issues (heading, required fields, optional, extras) | Task 1 (skill rewrite), Task 2 (run.md field derivation), Task 7 (qa.md docs example) |
| Logic change in `/fix` (regex + Step 0.1 routing + error messages + Phase 8 inheritance) | Task 3 |
| Logic change in `/fix-report` (Step 1.1 modes, Step 1.2 source mapping, Step 1.5 messages, Step 2.2 hint, Step 4.1 per-source edits, Step 4.2 summary) | Tasks 4 and 5 |
| Category → Prefix mapping (Testing → QA) | Task 6 |
| Versioning (qa 2.0.0, code-review 1.13.0) | Task 8 |
| Documentation (`docs/plugins/code-review.md`, `docs/plugins/qa.md`, `README.md`, `marketplace.json`) | Tasks 6, 7, 8 |
| Edge cases (no reports, prefix-not-found, manual cross-dir edits, ID collisions) | Surfaced in Tasks 3 (out-of-band note), 4 (resolve files / edge-case messages); behavioral edge cases (collisions, unknown:0, vastly different ages) inherit from existing logic and are documented in the spec — no implementation needed |
| Out of scope (no agent changes, no /analyze-feedback changes, no backward-compat parser, no sub-categories) | Confirmed by NOT including those files in any task |

No placeholders found. All edits show concrete strings. All filenames are absolute paths to actual files.

Type/identifier consistency: `source_file` is used consistently in Tasks 4 and 5 across Step 1.2, Step 4.1, and Step 4.2. `target_dir` is local to Task 3 Step 0.1. The regex `^(SEC|PERF|ARCH|MAINT|DOC|QA)-\d{3}$` and the prefix list in error messages match.

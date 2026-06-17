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
|----------|----------|----------|
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

---

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

## Loop History (optional — written by `/qa:loop`)

A `##`-level section placed **AFTER** `## Detailed Results`. It MUST NOT contain any
`### [SEVERITY] …` headings or `---` separators (so `/fix-report`'s block parser
ignores it). One row per loop iteration:

| Iteration | Failing in | Now passing | Still failing | Warnings | Regressions | Dispatches |
|------|-----------|-------------|---------------|----------|-------------|------------|
| 1 | BE-03, FE-05 | BE-03 (QA-001, QA-002) | FE-05 (QA-003) | — | — | 4 |

---

## Compatibility with code-review

The QA-XXX format is identical in structure to code-review's other prefixes (SEC, PERF, ARCH, MAINT, DOC). This means:

- `/fix QA-001` works the same as `/fix SEC-001` — the `/fix` command routes by prefix to `docs/testing/reports/` instead of `docs/reviews/`.
- `/fix-report` (without an argument) auto-merges the newest report from `docs/reviews/` and the newest from `docs/testing/reports/`, presenting one unified checklist.

The `Testing → QA` row is part of the canonical Category→Prefix mapping in `docs/plugins/code-review.md`.

### Status write-back

After `/fix QA-001` or `/fix-report` resolves an issue, code-review inserts `**Status:** ✅ Fixed (YYYY-MM-DD)` (or `⚠️ Partially Fixed`) immediately after the issue's `### [SEVERITY] QA-NNN: Title` heading. Already-fixed issues (those with a `**Status:**` field) are skipped on subsequent `/fix-report` runs, so reports become living documents.

---

## Report Quality Checklist

Before saving the report, verify:

- [ ] Summary counts match detailed results (total = pass + fail + skip)
- [ ] Every failed scenario has a `### [SEVERITY] QA-NNN: Title` heading in the Issues Found section
- [ ] Every QA-NNN issue has the required fields: `ID`, `Location`, `Category: Testing`, `Problem` (with Expected/Actual bullets), `Remediation`
- [ ] Screenshots referenced in issues actually exist on disk
- [ ] No placeholder text (TBD, TODO)
- [ ] If a Loop History section is present, it contains no `### [SEVERITY]` headings and no `---` separators

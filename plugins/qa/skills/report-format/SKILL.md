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

### QA-001 [SEVERITY] <issue title>
- **Scenario:** <FE-XX or BE-XX>
- **Expected:** <what should have happened>
- **Actual:** <what actually happened>
- **Response:** `<response body or error message>` (for BE issues)
- **Screenshot:** <path to screenshot> (for FE issues)
- **File:** <source file:line if identifiable>

### QA-002 [SEVERITY] <issue title>
...

## Detailed Results

### Pass: FE-01: <scenario name>
### Pass: BE-01: <scenario name>
### Fail: BE-03: <scenario name>
### Skip: FE-03: <scenario name> (reason)
~~~

---

## Issue ID Assignment

**Prefix:** `QA` (all issues use the same prefix, unlike code-review which uses SEC/PERF/ARCH/MAINT)

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

Each issue MUST include:

1. **ID and severity in heading:** `### QA-001 [HIGH] <title>`
2. **Scenario reference:** which FE-XX or BE-XX failed
3. **Expected vs Actual:** clear comparison
4. **Evidence:** response body (BE) or screenshot path (FE)
5. **File reference** (if identifiable): `src/api/users.py:45` — the source code location that likely causes the issue

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

The QA-XXX format is designed to be compatible with the code-review plugin's issue ID system (SEC-XXX, PERF-XXX, ARCH-XXX, MAINT-XXX). This enables future integration where `/fix QA-001` can resolve a QA issue the same way `/fix SEC-001` resolves a security issue.

**Issue heading format is identical:**
```
### [SEVERITY] QA-001: Title
```

This matches code-review's:
```
### [SEVERITY] SEC-001: Title
```

---

## Report Quality Checklist

Before saving the report, verify:

- [ ] Summary counts match detailed results (total = pass + fail + skip)
- [ ] Every failed scenario has a QA-XXX issue in the Issues Found section
- [ ] Every QA-XXX issue has Expected vs Actual
- [ ] Screenshots referenced in issues actually exist on disk
- [ ] No placeholder text (TBD, TODO)

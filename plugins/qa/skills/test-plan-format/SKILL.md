---
name: test-plan-format
description: Test plan structure, naming conventions, edge case generation rules, and file saving conventions for QA test plans.
---

# Test Plan Format

## File Conventions

- **Location:** `docs/testing/plans/`
- **Naming:** `YYYY-MM-DD-<topic>-test-plan.md` where `<topic>` is a slugified summary (lowercase, hyphens, no spaces)
- **Create directory if needed:** `mkdir -p docs/testing/plans`

---

## Plan Structure

Every test plan MUST follow this exact structure:

~~~markdown
# Test Plan: <title>

## Source
- Type: <PR #N / branch <name> / last N commits / staged changes>
- Base: <main/master>
- Date: <YYYY-MM-DD>

## Changes Summary

<Brief description of what changed and what needs testing. List affected areas.>

## Detected Tools
- Playwright MCP: <available/unavailable>
- HTTP client: <curl/httpie/unavailable>
- Database access: <psql/sqlite3/mysql/unavailable>

## FE Test Scenarios

### FE-01: <scenario name>
- **Area:** <component/page>
- **Preconditions:** <what must be true before test>
- **Steps:**
  1. <action>
  2. <action>
  3. <verification>
- **Expected:** <expected result>
- **Edge cases:**
  - <edge case 1>
  - <edge case 2>

## BE Test Scenarios

### BE-01: <scenario name>
- **Area:** <endpoint/service>
- **Method:** <HTTP method> <path>
- **Headers:** <required headers, e.g. Authorization: Bearer TOKEN>
- **Payload:** `<JSON body>`
- **Expected:** <status code>, <response body description>
- **DB Check:** `<SQL query>` — <expected state>
- **Edge cases:**
  - <edge case with expected response>
~~~

---

## Scenario Naming

- FE scenarios: `FE-01`, `FE-02`, ... `FE-NN` (zero-padded two digits)
- BE scenarios: `BE-01`, `BE-02`, ... `BE-NN` (zero-padded two digits)
- Numbering is sequential within each section, starting from 01

---

## Edge Case Generation Rules

For EVERY scenario, consider and include relevant edge cases from:

### Input boundaries
- Empty/null/missing values
- Maximum length strings
- Special characters (unicode, HTML entities, SQL metacharacters)
- Negative numbers, zero, boundary values (MAX_INT)

### Authentication & Authorization
- Unauthenticated request (no token)
- Expired token
- Valid token but insufficient permissions
- Another user's resource (IDOR)

### State
- Resource does not exist (404)
- Duplicate creation attempt (409)
- Concurrent modifications (race conditions)
- Resource in unexpected state (e.g., already deleted, already processed)

### Data integrity
- Required fields missing (422)
- Invalid data types (string where number expected)
- Referential integrity (foreign key does not exist)

### FE-specific
- Slow/no network connection
- Empty state (no data to display)
- Very long content (overflow, truncation)
- User not logged in
- Browser back/forward during operation

---

## Section Omission Rules

- If changes are **FE-only**: omit the `## BE Test Scenarios` section entirely
- If changes are **BE-only**: omit the `## FE Test Scenarios` section entirely
- If a tool is **unavailable**: note it in `## Detected Tools` and mark dependent scenarios with `(skip — <tool> unavailable)` in the scenario name

---

## Plan Quality Checklist

Before saving the plan, verify:

- [ ] Every scenario has at least 2 edge cases
- [ ] Every BE scenario has an expected status code
- [ ] Every FE scenario has concrete steps (not "test the form")
- [ ] DB Checks use actual table/column names from the codebase
- [ ] API paths match actual routes from the codebase
- [ ] No placeholder text (TBD, TODO, fill in later)

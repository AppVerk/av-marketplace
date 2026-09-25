---
name: "qa:test-plan-format"
description: Test plan structure, naming conventions, edge case generation rules, and file saving conventions for QA test plans.
---

# Test Plan Format

## File Conventions

- **Location:** `docs/testing/plans/`
- **Naming:** `YYYY-MM-DD-<topic>-test-plan.md` where `<topic>` is a slugified summary (lowercase, hyphens, no spaces)
- **Create directory if needed:** `mkdir -p docs/testing/plans`

---

## Plan Structure

Every test plan MUST follow this structure; omit optional sections, unused Setup labels and `**Blocked-by:**` lines where they do not apply. Replace the illustrative Base URL, expected results and citation tags with grounded project-specific details:

~~~markdown
# Test Plan: <title>

## Setup

**Base URL:** `http://127.0.0.1:8765`

**Required environment variables:**
- `QA_API_TOKEN` — bearer token for the users API
- `QA_USER_EMAIL` — login email of the test account
- `QA_USER_PASSWORD` — login password of the test account

**Required services:**
- App at `http://127.0.0.1:8765` (must be running before `/qa:run`; the plugin never starts it)

**Required databases:**
- `DATABASE_URL` — env var holding the DSN of the test database

## Source
- Type: <PR #N / branch <name> / last N commits / staged changes>
- Base: <main/master>
- Date: <YYYY-MM-DD>

## Changes Summary

<Brief description of what changed and what needs testing. List affected areas.>

## Blockers / Findings

Defects in the code under test that obstruct how it must be tested. Mandatory — write `None found.` when there are none.

### BLK-01: <one-line defect> — `(file:line)`
- **Impact on testing:** <affected scenarios and the spurious result the defect forces>
- **Remediation (human Setup prerequisite):** <human action before the run>
- **Blocks:** <scenario IDs carrying `**Blocked-by:** BLK-01`>

## Detected Tools
- Playwright MCP: <available/unavailable>
- HTTP client: <curl/httpie/unavailable>
- Database access: <psql/sqlite3/mysql/unavailable>

## FE Test Scenarios

### FE-01: <scenario name>
**Blocked-by:** BLK-01
- **Area:** <component/page>
- **Preconditions:** <what must be true before test>
- **Steps:**
  1. Open the login page in the browser
  2. Fill Email with `$QA_USER_EMAIL` and Password with `$QA_USER_PASSWORD`
  3. Click "Sign In"
- **Expected:** <welcome text shown> (path:line)
- **Edge cases:**
  - Password `nope`: <validation message shown> (path:line)
  - Missing email: <validation message shown> (path:line)

## BE Test Scenarios

### BE-01: <scenario name>
**Blocked-by:** BLK-01
- **Area:** <endpoint/service>
- **Method:** <HTTP method> <path>
- **Headers:** Authorization: Bearer $QA_API_TOKEN
- **Payload:** `<JSON body>`
- **Expected:** <status code>, <response body description> (path:line)
- **DB Check:** `<SQL query>` via `$DATABASE_URL` — <expected state>
- **Edge cases:**
  - <edge case with expected status and response> (path:line)
  - <second edge case with expected status and response> (path:line)

## Out of harness scope
- <check the browser/HTTP/DB harness cannot observe> — <one-clause harness reason>
~~~

---

## Scenario Naming

- FE scenarios: `FE-01`, `FE-02`, ... `FE-NN` (zero-padded two digits)
- BE scenarios: `BE-01`, `BE-02`, ... `BE-NN` (zero-padded two digits)
- Numbering is sequential within each section, starting from 01

---

## Grounding tags & assertion style

Every `**Expected:**` assertion and each edge-case expectation needs its own evidence tag:

- `(path:line)` cites a producing source line the author actually read in this working tree. Put one citation on the most load-bearing line per assertion; cite each edge case separately. Never invent a citation or cite a test for behavior it does not assert.
- `(unverified — confirm at run time)` marks an assertion whose producer cannot be read (for example, a foreign PR or pasted diff). If the source is on disk, read it instead; an unverified tag on a readable assertion is a defect. A mismatch still fails at run time.
- `(exact text — brittle)` marks quoted human-readable text that must be matched as a substring, not for equality. Use only when status and body shape cannot disambiguate the behavior; include a source citation or unverified tag as well.

Prefer stable status codes and response structure (keys/types) over exact message text. For a function-derived value (hash, slug, formatted filename), assert its generating rule and cite the producer rather than guessing an exact result; an exact literal needs a fixture or test that pins it. Replace the template's `(path:line)` with an actual cited path and line in each plan.

## Setup rules

- `## Setup` goes directly after `# Test Plan:`, before `## Source`. Omit the entire section when no prerequisites are needed; omit unused labels independently.
- At run time, resolve the base URL from `**Base URL:**` here, then the first URL in `## Source` or a scenario heading/bullet, then `QA_BASE_URL`. Project config is read only when authoring the plan, never at run time; if no URL resolves, testing aborts.
- Consumers read only the first backticked token of the `**Base URL:**` line or each `- ` bullet; following text is for humans. Environment variable names must match `^[A-Z_][A-Z0-9_]*$`. `**Required databases:**` bullets must be either a valid env var name holding a DSN or SQLite path, or a declared `mcp__` server name bound to the test database. Any other bullet is ignored with a warning. The plan generator never emits an `mcp__` bullet: only a human who knows the server's database may declare one.
- A credential in a header, cookie or login step (bearer token, API key, email/password) must be a `$NAME` reference with `NAME` declared under `**Required environment variables:**`; never use a literal or a placeholder such as `TOKEN`. A plan whose scenarios require auth but declare no name is defective. A deliberately invalid input in a negative edge case is not a credential.
- Minimize prerequisites: every declared environment variable name must be referenced by a scenario; omit labels that are unused. Starting the app or dependency is a human prerequisite under `**Required services:**`, never a scenario step.
- Run a DB check only through a connection declared under `**Required databases:**`: `psql "$DATABASE_URL" -tAc '<SQL>'`, `sqlite3 "$SQLITE_DB" '<SQL>'`, or `mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DATABASE" -N -e '<SQL>'` with `MYSQL_PWD` read by the client from the environment. Declare all four MySQL names; never put credentials in a command line. A declared `mcp__` server may be used instead; an available but undeclared MCP server must not be used. If no DB connection is declared, the API test still runs and its DB check is `SKIP`.

## Harness scope

Scenario steps must be browser actions (FE) or HTTP requests / DB queries (BE) against an already-running app. Do not include `docker`, `make`, `npm`, migrations, file edits or infrastructure inspection as scenario steps. Record bring-up as a human `**Required services:**` prerequisite; list unobservable checks under optional `## Out of harness scope` as bullets with a one-clause harness reason (never scenario headings). A code defect that prevents a contract-correct result is a Blocker, not an out-of-scope check. If a tester nevertheless encounters an out-of-scope step, the scenario is `SKIP` with reason `out of harness scope: <step>`.

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
- If a tool is **unavailable**: note it in `## Detected Tools`; the tester reports `NEED_INFO kind=tool` at run time rather than labeling scenarios as skipped
- `## Setup` and `## Out of harness scope` are optional; `## Blockers / Findings` is mandatory for generated plans (`None found.` if none). Consumers ignore its absence in a hand-written plan

---

## Plan Quality Checklist

Before saving the plan, verify:

- [ ] Every scenario has at least 2 edge cases
- [ ] Every BE scenario has an expected status code
- [ ] Every FE scenario has concrete steps (not "test the form")
- [ ] DB Checks use actual table/column names from the codebase
- [ ] API paths match actual routes from the codebase
- [ ] No placeholder text (TBD, TODO, fill in later)
- [ ] `## Setup` is present whenever scenarios require a URL, credential or DB connection
- [ ] Every credential uses `$NAME` declared under Setup, never a literal or placeholder such as `TOKEN`
- [ ] Every `**Expected:**` and edge-case expectation has a grounded `(path:line)` or `(unverified — confirm at run time)` tag
- [ ] `## Blockers / Findings` is present (or reads `None found.`)
- [ ] No scenario step is outside the browser / HTTP / DB harness scope
- [ ] For ≥2 independent boolean inputs, a `state-combination-planning` 2^N table appears above affected scenarios with a disposition for every row

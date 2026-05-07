# QA Plugin

Automated QA testing — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports with unique issue IDs.

**Version:** 1.0.0

## Commands

### `/qa:create-plan`

Analyze code changes and generate a detailed test plan with FE and BE scenarios, edge cases, and tool detection.

```bash
# Analyze current branch's PR (or branch diff as fallback)
/qa:create-plan

# Analyze specific PR
/qa:create-plan #123

# Analyze branch diff
/qa:create-plan feature/xyz

# Analyze current branch
/qa:create-plan ten branch

# Analyze last N commits
/qa:create-plan last 5 commits

# Analyze staged changes
/qa:create-plan staged
```

The command:
1. Resolves the diff source (PR, branch, commits, or staged changes)
2. Classifies changed files as FE or BE based on file extensions and paths
3. Reads related files for context (routers, models, schemas, docs, OpenAPI specs)
4. Detects available testing tools (Playwright MCP, curl/httpie, psql/sqlite3/mysql, database MCP servers)
5. Generates the test plan using scenario conventions (`FE-XX` for frontend, `BE-XX` for backend)
6. Saves the plan to `docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md`
7. Proposes running `/qa:run` to execute the plan

### `/qa:run`

Execute a test plan by launching FE and BE testing agents in parallel and generating a report.

```bash
# Run the most recent test plan
/qa:run

# Run a specific test plan
/qa:run docs/testing/plans/2026-04-07-user-auth-test-plan.md
```

The command:
1. Loads and parses the test plan
2. Re-validates tool availability (tools may have changed since plan creation)
3. Launches testing agents in parallel:
   - **fe-tester** — executes FE scenarios via Playwright MCP (navigation, clicks, form fills, snapshot verification)
   - **be-tester** — executes BE scenarios via HTTP clients and database queries
4. Collects results from all agents
5. Generates a report with `QA-XXX` issue IDs and severity levels
6. Saves the report to `docs/testing/reports/YYYY-MM-DD-<topic>-report.md`

## Two-Phase Workflow

The plugin follows a plan-then-execute model:

1. **Plan phase** (`/qa:create-plan`) — generates a Markdown test plan for human review
2. **Execute phase** (`/qa:run`) — executes the approved plan, can run in the same or a new session

This allows reviewing and adjusting the test plan before execution.

## Test Plan Format

Plans are saved as Markdown with the following structure:

- **Source** — diff origin (PR, branch, commits)
- **Changes Summary** — what changed and what needs testing
- **Detected Tools** — available testing tools (Playwright, curl, psql, MCP servers, etc.)
- **FE Test Scenarios** (`FE-01`, `FE-02`, ...) — UI steps, expected results, edge cases
- **BE Test Scenarios** (`BE-01`, `BE-02`, ...) — endpoint, method, payload, expected response, DB checks, edge cases

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

## Adaptive Tool Detection

The plugin detects available tools at plan creation and re-validates before execution:

| Tool | Purpose | Detection |
|------|---------|-----------|
| Playwright MCP | FE testing (navigation, clicks, forms) | MCP tool availability |
| curl / httpie | API requests | `command -v` |
| psql / sqlite3 / mysql | Database verification (CLI) | `command -v` |
| Database MCP servers | Database verification (pre-configured) | MCP tool availability |
| jq | JSON response parsing | `command -v` |

**Database access priority:** MCP server > CLI client > SKIP

If a required tool is unavailable, affected scenarios are marked as SKIP (not FAIL).

## Prerequisites

- **Server must be running** — the plugin does not start/stop application servers
- **Database must be accessible** — for DB verification scenarios
- **Playwright MCP** — required for FE testing (FE scenarios are skipped without it)
- **HTTP client** — at least `curl` or `httpie` for BE testing (BE scenarios are skipped without either)

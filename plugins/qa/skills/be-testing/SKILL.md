---
name: be-testing
description: Backend testing patterns — API request construction, response verification, database state checks, error handling testing, and adaptive tool detection.
allowed-tools: Bash(curl:*), Bash(httpie:*), Bash(http:*), Bash(wget:*), Bash(psql:*), Bash(sqlite3:*), Bash(mysql:*), Bash(mongosh:*), Bash(redis-cli:*), Bash(command:*), Bash(echo:*), Bash(jq:*), Bash(grep:*), Bash(cat:*), Bash(head:*), Bash(tail:*), Read, Write, Bash(mkdir:*)
---

# Backend Testing Patterns

## Tool Detection

**ALWAYS run this check first:**

```bash
# HTTP clients
command -v curl >/dev/null 2>&1 && echo "OK: curl available" || echo "UNAVAILABLE: curl"
command -v http >/dev/null 2>&1 && echo "OK: httpie available" || echo "UNAVAILABLE: httpie"

# Database clients
command -v psql >/dev/null 2>&1 && echo "OK: psql available" || echo "UNAVAILABLE: psql"
command -v sqlite3 >/dev/null 2>&1 && echo "OK: sqlite3 available" || echo "UNAVAILABLE: sqlite3"
command -v mysql >/dev/null 2>&1 && echo "OK: mysql available" || echo "UNAVAILABLE: mysql"
command -v mongosh >/dev/null 2>&1 && echo "OK: mongosh available" || echo "UNAVAILABLE: mongosh"
command -v redis-cli >/dev/null 2>&1 && echo "OK: redis-cli available" || echo "UNAVAILABLE: redis-cli"

# JSON processing
command -v jq >/dev/null 2>&1 && echo "OK: jq available" || echo "UNAVAILABLE: jq"
```

Use the first available tool from each category. If no HTTP client is available, mark all API scenarios as SKIP.

### MCP Server Detection

In addition to CLI tools, check if any database or API-related MCP servers are available. MCP servers provide direct access without needing CLI clients installed locally.

Common database MCP servers:
- **PostgreSQL MCP** — `mcp__postgres`, `mcp__supabase`, `mcp__neon` or similar
- **MySQL MCP** — `mcp__mysql` or similar
- **MongoDB MCP** — `mcp__mongodb` or similar
- **Redis MCP** — `mcp__redis` or similar
- **Supabase MCP** — provides both database and API access

Common API-related MCP servers:
- **HTTP/REST MCP** — generic HTTP request capabilities
- **GraphQL MCP** — for GraphQL API testing

**How to detect:** Check the available tools list in your session. MCP tools follow the pattern `mcp__<server>__<tool>`. If you see database-related MCP tools, prefer them over CLI clients — they're typically pre-configured with connection details and don't require manual connection string setup.

**Priority order for DB access:**
1. MCP server (pre-configured, no connection string needed)
2. CLI client (psql, sqlite3, mysql — requires connection details)
3. SKIP (no access available)

---

## Execution Workflow

For each BE scenario from the test plan:

1. **Read the scenario** — understand method, endpoint, payload, expected response, DB checks
2. **Execute the request** — send HTTP request with proper method, headers, body
3. **Verify response** — check status code, response body structure, specific values
4. **Verify DB state** (if DB Check specified) — run query, compare against expected
5. **Execute edge cases** — run each edge case as a sub-test
6. **Record result** — pass/fail with response details

---

## API Testing Patterns

### Request Construction (curl)

**GET request:**

```bash
curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "http://localhost:8000/api/resources"
```

**POST request:**

```bash
curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "test", "email": "test@example.com"}' \
  "http://localhost:8000/api/resources"
```

**PUT request:**

```bash
curl -s -w "\n%{http_code}" \
  -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "updated"}' \
  "http://localhost:8000/api/resources/1"
```

**DELETE request:**

```bash
curl -s -w "\n%{http_code}" \
  -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/resources/1"
```

**PATCH request:**

```bash
curl -s -w "\n%{http_code}" \
  -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": "active"}' \
  "http://localhost:8000/api/resources/1"
```

The `-w "\n%{http_code}"` flag appends the status code on a new line after the response body. Parse the last line as the status code.

### Request Construction (httpie)

**GET request:**

```bash
http GET http://localhost:8000/api/resources \
  Authorization:"Bearer $TOKEN" \
  --print=hb
```

**POST request:**

```bash
http POST http://localhost:8000/api/resources \
  Authorization:"Bearer $TOKEN" \
  name=test email=test@example.com \
  --print=hb
```

Use `--print=hb` to show headers and body (useful for debugging). Use `--print=b` for body only.

### Response Verification

**Check status code:**

```bash
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X GET "http://localhost:8000/api/resources")
if [ "$STATUS" = "200" ]; then echo "PASS: status 200"; else echo "FAIL: expected 200, got $STATUS"; fi
```

**Check response body with jq:**

```bash
RESPONSE=$(curl -s -H "Content-Type: application/json" "http://localhost:8000/api/resources")

# Check field exists and has value
echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1 && echo "PASS: id exists" || echo "FAIL: id missing"

# Check specific value
echo "$RESPONSE" | jq -e '.status == "active"' > /dev/null 2>&1 && echo "PASS: status is active" || echo "FAIL: status mismatch"

# Check array length
echo "$RESPONSE" | jq -e '.items | length > 0' > /dev/null 2>&1 && echo "PASS: items not empty" || echo "FAIL: items empty"
```

**Without jq (fallback with grep):**

```bash
RESPONSE=$(curl -s "http://localhost:8000/api/resources")
echo "$RESPONSE" | grep -q '"status":"active"' && echo "PASS" || echo "FAIL"
```

---

## Database Verification Patterns

### PostgreSQL (psql)

```bash
# Check record exists
psql -h localhost -U user -d dbname -t -A -c "SELECT COUNT(*) FROM resources WHERE name = 'test';"
# Expected: 1

# Check field value
psql -h localhost -U user -d dbname -t -A -c "SELECT status FROM resources WHERE id = 1;"
# Expected: active

# Check record was deleted
psql -h localhost -U user -d dbname -t -A -c "SELECT COUNT(*) FROM resources WHERE id = 1;"
# Expected: 0

# Check with multiple conditions
psql -h localhost -U user -d dbname -t -A -c "SELECT COUNT(*) FROM orders WHERE user_id = 1 AND status = 'completed';"
```

Flags: `-t` (tuples only, no headers), `-A` (unaligned output, no padding).

### SQLite

```bash
# Check record exists
sqlite3 db.sqlite3 "SELECT COUNT(*) FROM resources WHERE name = 'test';"

# Check field value
sqlite3 db.sqlite3 "SELECT status FROM resources WHERE id = 1;"
```

### MySQL

```bash
# Check record exists
mysql -h localhost -u user -ppassword dbname -N -e "SELECT COUNT(*) FROM resources WHERE name = 'test';"
```

Flag: `-N` (skip column names).

### Connection String Detection

If the test plan doesn't specify DB connection details, look for them in:

1. `.env` or `.env.local` files
2. `docker-compose.yml` (service ports, credentials)
3. Framework config files (`settings.py`, `database.yml`, `config/database.php`)
4. Environment variables: `DATABASE_URL`, `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`

---

## Error Handling Test Patterns

### Missing required field

```bash
# Send request without required field
curl -s -w "\n%{http_code}" -X POST \
  -H "Content-Type: application/json" \
  -d '{"name": "test"}' \
  "http://localhost:8000/api/resources"
# Expected: 422 with validation error in body
```

### Unauthenticated request

```bash
# Send request without auth token
curl -s -w "\n%{http_code}" -X GET \
  "http://localhost:8000/api/resources"
# Expected: 401
```

### Insufficient permissions

```bash
# Send request with regular user token to admin endpoint
curl -s -w "\n%{http_code}" -X DELETE \
  -H "Authorization: Bearer $REGULAR_USER_TOKEN" \
  "http://localhost:8000/api/admin/users/1"
# Expected: 403
```

### Resource not found

```bash
curl -s -w "\n%{http_code}" -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/resources/99999"
# Expected: 404
```

### Duplicate creation

```bash
# Create resource
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"email": "test@example.com"}' \
  "http://localhost:8000/api/users"

# Try to create duplicate
curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" \
  -d '{"email": "test@example.com"}' \
  "http://localhost:8000/api/users"
# Expected: 409
```

---

## Result Format

For each scenario, return results in this format:

```
### BE-XX: <scenario name>
- **Status:** PASS / FAIL / SKIP
- **Request:** <METHOD> <URL>
- **Response status:** <actual status code>
- **Response body:** <relevant excerpt; short bodies may be inlined in full — longer bodies go to a file under docs/testing/reports/, referenced by path (see reader-context-hygiene)>
- **DB check:** <PASS/FAIL/SKIP — actual value vs expected>
- **Details:** <what was verified / what went wrong>
- **Edge cases:**
  - <edge case 1>: PASS / FAIL — <details>
  - <edge case 2>: PASS / FAIL — <details>
```

---

## Error Handling

- If no HTTP client is available: mark ALL API scenarios as SKIP with reason
- If DB client is unavailable: execute API scenarios but mark DB Checks as SKIP
- If a request times out (>30s): mark as FAIL with "timeout" note
- If a connection is refused: mark as FAIL with "connection refused — is the server running?"
- If response is not valid JSON when expected: mark as FAIL, include raw response body

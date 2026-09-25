---
name: "qa:be-testing"
description: Backend testing patterns — API request construction, response verification, database state checks, error handling testing, and adaptive tool detection.
allowed-tools: Bash(curl:*), Bash(httpie:*), Bash(http:*), Bash(wget:*), Bash(psql:*), Bash(sqlite3:*), Bash(mysql:*), Bash(mongosh:*), Bash(redis-cli:*), Bash(command:*), Bash(printf:*), Bash(perl:*), Bash(sed:*), Bash(cut:*), Bash(jq:*), Bash(grep:*), Bash(cat:*), Bash(head:*), Bash(tail:*), Read, Write, Bash(mkdir:*)
---

# Backend Testing Patterns

## Tool Detection

**ALWAYS run this check first:**

```bash
# HTTP clients
command -v curl >/dev/null 2>&1 && printf 'curl: available\n' || printf 'curl: unavailable\n'
command -v http >/dev/null 2>&1 && printf 'httpie: available\n' || printf 'httpie: unavailable\n'

# Database clients
command -v psql >/dev/null 2>&1 && printf 'psql: available\n' || printf 'psql: unavailable\n'
command -v sqlite3 >/dev/null 2>&1 && printf 'sqlite3: available\n' || printf 'sqlite3: unavailable\n'
command -v mysql >/dev/null 2>&1 && printf 'mysql: available\n' || printf 'mysql: unavailable\n'
command -v mongosh >/dev/null 2>&1 && printf 'mongosh: available\n' || printf 'mongosh: unavailable\n'
command -v redis-cli >/dev/null 2>&1 && printf 'redis-cli: available\n' || printf 'redis-cli: unavailable\n'

# JSON processing and fail-closed response sanitiser
command -v jq >/dev/null 2>&1 && printf 'jq: available\n' || printf 'jq: unavailable\n'
perl -MJSON::PP -e 1 >/dev/null 2>&1 && printf 'perl: available\n' || printf 'perl: unavailable\n'
```

Use an available HTTP client. If no HTTP client, or no `perl` with `JSON::PP`, is available and the scenarios apply, every API scenario is `NEED_INFO kind=tool, Missing: curl` (or `perl`). A DB client missing only blocks its DB check.

### MCP Server Detection

In addition to CLI tools, check which database or API-related MCP servers are available. Their availability alone does not establish a connection to the test database.

Common database MCP servers:
- **PostgreSQL MCP** — `mcp__postgres`, `mcp__supabase`, `mcp__neon` or similar
- **MySQL MCP** — `mcp__mysql` or similar
- **MongoDB MCP** — `mcp__mongodb` or similar
- **Redis MCP** — `mcp__redis` or similar
- **Supabase MCP** — provides both database and API access

Common API-related MCP servers:
- **HTTP/REST MCP** — generic HTTP request capabilities
- **GraphQL MCP** — for GraphQL API testing

**How to detect:** Check the available tools list in your session. MCP tools follow the pattern `mcp__<server>__<tool>`. Use a database MCP server **only** if the plan's `Setup:` declares its `mcp__` name under `Required databases`. Otherwise use a CLI client with a declared env-var connection; with neither, report `**DB check:** SKIP — no DB connection declared under ## Setup`. Never use an undeclared preconfigured server.

---

## Execution Workflow

For each BE scenario from the test plan:

1. **Read the scenario** — understand method, endpoint, payload, expected response, DB checks
2. **Execute the request** — send HTTP request with proper method, headers, body
3. **Verify response** — check status code, response body structure, specific values
4. **Verify DB state** (if DB Check specified) — run query, compare against expected
5. **Execute edge cases** — run each edge case as a sub-test
6. **Record result** — PASS/FAIL/SKIP/NEED_INFO with response details

---
## Tag handling (plan grounding tags)

Handle the main `**Expected:**` and each edge-case expectation independently:

- `(path:line)` — source citation for humans; ignore it when matching the result.
- `(unverified — confirm at run time)` — still assert the expected result and report a mismatch as `FAIL`. Carry the tag into the result so an issue minted from this assertion is graded `LOW`, unless the observed status is ≥ 500 or there was a crash/stack trace.
- `(exact text — brittle)` — match the quoted text as a substring, not exact equality.

---

## API Testing Patterns

### Request Construction (curl)

Every request captures headers and body together, sanitises the response **before** inspecting or saving it, and derives status/body from that one capture. In each separate Bash call sending a request, repeat `export QA_REDACT_NAMES=QA_API_TOKEN` (add every other declared env var referenced by the scenarios). `$QA_API_TOKEN` is an example name declared under `Setup:`; use the name actually declared by the plan. `$BASE_URL` is the resolved Base URL, not a value discovered from config. Never print a request with its headers.

**GET request:**

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -H "Authorization: Bearer $QA_API_TOKEN" -H "Content-Type: application/json" "$BASE_URL/api/resources" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

**POST request:**

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -X POST -H "Authorization: Bearer $QA_API_TOKEN" -H "Content-Type: application/json" -d '{"name": "test", "email": "test@example.com"}' "$BASE_URL/api/resources" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

**PUT request:**

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -X PUT -H "Authorization: Bearer $QA_API_TOKEN" -H "Content-Type: application/json" -d '{"name": "updated"}' "$BASE_URL/api/resources/1" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

**DELETE request:**

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -X DELETE -H "Authorization: Bearer $QA_API_TOKEN" "$BASE_URL/api/resources/1" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

**PATCH request:**

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -X PATCH -H "Authorization: Bearer $QA_API_TOKEN" -H "Content-Type: application/json" -d '{"status": "active"}' "$BASE_URL/api/resources/1" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

### Request Construction (httpie)

HTTPie must print both headers and body so the same sanitiser can handle them:

**GET request:**

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(http --print=hb GET "$BASE_URL/api/resources" Authorization:"Bearer $QA_API_TOKEN" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

**POST request:**

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(http --print=hb POST "$BASE_URL/api/resources" Authorization:"Bearer $QA_API_TOKEN" name=test email=test@example.com | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

### Response Verification

Check the single captured `$STATUS` and sanitised `$BODY`; do not send a second request just to check status.

```bash
[ "$STATUS" = "200" ] && printf 'PASS: status 200\n' || printf 'FAIL: expected 200, got %s\n' "$STATUS"
printf '%s' "$BODY" | jq -e '.id' >/dev/null && printf 'PASS: id exists\n' || printf 'FAIL: id missing\n'
printf '%s' "$BODY" | jq -e '.status == "active"' >/dev/null && printf 'PASS: status is active\n' || printf 'FAIL: status mismatch\n'
printf '%s' "$BODY" | jq -e '.items | length > 0' >/dev/null && printf 'PASS: items not empty\n' || printf 'FAIL: items empty\n'
```

Without `jq`, match the sanitiser's sorted, indented JSON layout (a space after `:`):

```bash
printf '%s' "$BODY" | grep -q '"status": "active"' && printf 'PASS\n' || printf 'FAIL\n'
```

---

## Database Verification Patterns

### PostgreSQL (psql)

```bash
# Check record exists
psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM resources WHERE name = 'test';"
# Check field value
psql "$DATABASE_URL" -tAc "SELECT status FROM resources WHERE id = 1;"
# Check record was deleted
psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM resources WHERE id = 1;"
# Check with multiple conditions
psql "$DATABASE_URL" -tAc "SELECT COUNT(*) FROM orders WHERE user_id = 1 AND status = 'completed';"
```

Flags: `-t` (tuples only), `-A` (unaligned output), `-c` (SQL).

### SQLite

```bash
sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM resources WHERE name = 'test';"
sqlite3 "$SQLITE_DB" "SELECT status FROM resources WHERE id = 1;"
```

### MySQL

Declare `MYSQL_HOST`, `MYSQL_USER`, `MYSQL_DATABASE`, and `MYSQL_PWD` in `Setup:`. The client reads the password from `MYSQL_PWD` in the environment, never from a command-line argument:

```bash
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DATABASE" -N -e "SELECT COUNT(*) FROM resources WHERE name = 'test';"
```

Flag: `-N` (skip column names).

### Connection reference

Run a DB check only through a connection declared under `## Setup → Required databases`: an env var name with its corresponding CLI client (`DATABASE_URL` for `psql`, `SQLITE_DB` for `sqlite3`, or the four `MYSQL_*` names for MySQL), or an `mcp__` server name declared as pointing to that same test database. Never use a preconfigured but undeclared MCP server. No declared connection → `**DB check:** SKIP — no DB connection declared under ## Setup`, while the HTTP part still runs. Missing CLI client → `**DB check:** SKIP` while the API runs. No literal host, user, password or path in a DB command. If a DSN must be mentioned in output, mask it as `postgres://USER:***@HOST:5432/DB`.

---

## Credential Safety Rules

- Never print an env var value, header, cookie, token or DSN into output, reports or dumps. Print only presence via `[ -n "${QA_API_TOKEN:-}" ] && printf 'QA_API_TOKEN: OK\n' || printf 'QA_API_TOKEN: MISSING\n'`; use the declared name literally.
- Credentials come only from `$NAME` env vars named in the plan. Never call a login endpoint to mint a token unless that scenario explicitly asks for it. Never read `.env`, `.env.*`, `docker-compose*.yml` or framework config for values.
- Before **each** Bash call sending a request, export `QA_REDACT_NAMES` as a comma-separated list of every declared env var name referenced by the scenarios (for example `export QA_REDACT_NAMES=QA_API_TOKEN,QA_USER_PASSWORD`), and pipe the response through the sanitiser before inspecting it.
- The sanitiser masks the final response's sensitive headers (set-cookie, cookie, authorization, proxy-authorization, x-api-key, api-key, x-auth-token, x-csrf-token), omits intermediate 1xx headers, masks sensitive JSON keys at any depth by `_`/`-`/camelCase segment (`token`, `secret`, `password`, `passwd`, `pwd`, `key`, `session`, `cookie`, `auth`, `authorization`, `credential`, `credentials`, `private`, `dsn`, `url`, `jwt`, `bearer`, `otp`, `pin`), masks Bearer tokens and token/key/secret/password/auth/session/code/sig/signature query values throughout the output, and masks every value of the env vars named in `QA_REDACT_NAMES` that has at least four characters. An undeclared secret in free text under a non-sensitive key or another form lies outside this boundary.

Write this sanitiser **once per run in Step 2**, before the first HTTP request (requires `perl` and its core `JSON::PP`):

```bash
cat > "${TMPDIR:-/tmp}/qa-redact.pl" <<'EOF'
#!/usr/bin/env perl
# qa-redact: sanitise an HTTP response (curl -si output) or a bare body read on stdin. Fail-closed.
use strict; use warnings; use JSON::PP;
local $/; my $in = <STDIN>; $in = '' unless defined $in;
my %SENSITIVE = map { $_ => 1 } qw(token secret password passwd pwd key session cookie auth authorization credential credentials private dsn url jwt bearer otp pin);
my $HDR = qr/(?:set-cookie|cookie|authorization|proxy-authorization|x-api-key|api-key|x-auth-token|x-csrf-token)\s*:/i;
sub sensitive_key { my $k = shift; $k =~ s/(?<=[a-z0-9])(?=[A-Z])/_/g; return grep { $SENSITIVE{$_} } split /[^A-Za-z0-9]+/, lc $k; }
sub scrub_text { my $t = shift;
    $t =~ s/(bearer\s+)[A-Za-z0-9._~+\/=-]+/$1***/gi;
    $t =~ s/([?&;](?:token|key|secret|password|auth|session|code|sig|signature)=)[^&\s"']+/$1***/gi;
    for my $name (grep { length } split /,/, ($ENV{QA_REDACT_NAMES} // '')) {
        my $val = $ENV{$name}; next unless defined $val && length $val >= 4;
        $t =~ s/\Q$val\E/***/g;
    }
    return $t; }
sub scrub { my $v = shift; return $v unless ref $v;
    if (ref $v eq 'HASH') { for my $k (keys %$v) { $v->{$k} = sensitive_key($k) ? '***' : scrub($v->{$k}); } }
    elsif (ref $v eq 'ARRAY') { $_ = scrub($_) for @$v; }
    return $v; }
my ($head, $body) = ('', $in);
if ($in =~ /^HTTP\/[0-9.]+ \d{3}/) {
    my @parts = split /\r?\n\r?\n/, $in, -1;
    my $i = 0; $i++ while ($i < $#parts && $parts[$i + 1] =~ /^HTTP\/[0-9.]+ \d{3}/);
    $head = $parts[$i]; $head =~ s/\r//g;
    $body = $i < $#parts ? join("\n\n", @parts[$i + 1 .. $#parts]) : '';
    $head =~ s/^($HDR)[^\n]*/$1 ***/gm;
}
my $out = '';
if ($body !~ /^\s*$/) {
    my $json = eval { JSON::PP->new->allow_nonref->decode($body) };
    if ($@ || !defined $json) { $out = sprintf("[body withheld by qa-redact: not valid JSON, %d bytes]\n", length $body); }
    elsif (!ref $json && $json !~ /^(?:-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|true|false|null)$/) { $out = sprintf("[body withheld by qa-redact: scalar body, %d bytes]\n", length $body); }
    else { $out = JSON::PP->new->canonical->indent->space_after->allow_nonref->encode(scrub($json)); }
}
print scrub_text($head eq '' ? $out : "$head\n\n$out");
EOF
```

Read and persist HTTP responses **only** through `RESP=$(… | perl "${TMPDIR:-/tmp}/qa-redact.pl")`. Dumps and inline excerpts come only from `$RESP` (body from `$BODY` after splitting `$RESP`). Non-JSON or bare-string bodies are withheld (`[body withheld by qa-redact: …]`); the status line and sanitised headers remain available.

---

## Error Handling Test Patterns

Use the single captured `$RESP`/`$STATUS`/`$BODY` for each request. Each example is a separate Bash call: export all declared scenario env var names in `QA_REDACT_NAMES` at its top.

### Missing required field

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -X POST -H "Authorization: Bearer $QA_API_TOKEN" -H "Content-Type: application/json" -d '{"name": "test"}' "$BASE_URL/api/resources" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
# Expected: 422 with a validation error in $BODY
```

### Unauthenticated request

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si "$BASE_URL/api/resources" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
# Expected: 401
```

### Insufficient permissions

```bash
export QA_REDACT_NAMES=QA_API_TOKEN,QA_REGULAR_USER_TOKEN
RESP=$(curl -si -X DELETE -H "Authorization: Bearer $QA_REGULAR_USER_TOKEN" "$BASE_URL/api/admin/users/1" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
# Expected: 403
```

### Resource not found

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -H "Authorization: Bearer $QA_API_TOKEN" "$BASE_URL/api/resources/99999" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
# Expected: 404
```

### Duplicate creation

Only when the scenario explicitly specifies both actions, create the resource once, then attempt the duplicate once. Never re-fire either POST as a refutation/retry:

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -X POST -H "Authorization: Bearer $QA_API_TOKEN" -H "Content-Type: application/json" -d '{"email": "test@example.com"}' "$BASE_URL/api/users" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
```

```bash
export QA_REDACT_NAMES=QA_API_TOKEN
RESP=$(curl -si -X POST -H "Authorization: Bearer $QA_API_TOKEN" -H "Content-Type: application/json" -d '{"email": "test@example.com"}' "$BASE_URL/api/users" | perl "${TMPDIR:-/tmp}/qa-redact.pl")
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^$/d')
# Expected: 409
```

---

## Result Format

For each scenario, return results in this format:

```
### BE-XX: <scenario name>
- **Status:** PASS / FAIL / SKIP
- **Request:** <METHOD> <URL only — no headers>
- **Response status:** <actual status code>
- **Response body:** <decision-relevant sanitised excerpt from $RESP or path docs/testing/reports/responses/<ID>-body.json for long responses>
- **DB check:** <PASS/FAIL/SKIP — actual value vs expected>
- **Details:** <what was verified / what went wrong>
- **Refutation:** <required directly after Details when Status is FAIL; e.g. re-verified: yes (state re-read, no re-fire); env: n/a; scope: in; harness: ok>
- **Edge cases:**
  - <edge case 1>: PASS / FAIL / SKIP — <details; if FAIL, include refutation trace here>
  - <edge case 2>: NEED_INFO — <kind>: <identifiers>
```

When the main flow cannot run for a missing prerequisite, use exactly this block after the heading (do not run edge cases):

```
### BE-XX: <scenario name>
- **Status:** NEED_INFO
- **Kind:** credentials | service | fixture | tool
- **Missing:** <comma-separated identifiers: env var names, base URL/host, fixture table/row or file, or binary names; never values>
- **Details:** <what was attempted and what was absent; never a secret value>
```

An edge-only prerequisite gap remains on its own `- <edge case>: NEED_INFO — <kind>: <identifiers>` line; keep the main flow's PASS/FAIL status. A DB-client gap with runnable HTTP is `**DB check:** SKIP`, not a scenario NEED_INFO. `SKIP` also covers inapplicable scenarios, mutation-guard marks, out-of-harness steps and unknown outcomes after harness errors. Store response dumps only from `$RESP` under `docs/testing/reports/responses/<ID>-body.json` (edge n: `<ID>-edge<n>-body.json`), never timestamps or QA issue IDs.

---

## FAIL refutation battery (before returning any FAIL)

A FAIL is a claim — refute it before reporting ANY `FAIL`: the scenario `**Status:**`, each edge-case sub-result, or `**DB check:**` (an edge failure under a passing main flow is independently reported).

1. **Re-verify the observation — once, deterministically, observation-only.** For GET/HEAD or a read-only DB query, repeat the identical read exactly once. For a POST/PUT/PATCH/DELETE or INSERT/UPDATE/DELETE, never re-fire the action; re-read its resulting state once with a GET or DB check. One check, then disposition — not retry-until-pass. If two identical READs disagree, record both observations in Details: nondeterminism is itself `FAIL` (unlike a write, which may legitimately return 201 then 409 if fired twice).
2. **Environment artifact?** A missing env var → `NEED_INFO kind=credentials`; the app/dependency never reachable in this scenario (connection refused, DNS failure, timeout before any response) → `NEED_INFO kind=service, Missing: <base URL or host>`; missing seed/file → `NEED_INFO kind=fixture`; required binary missing → `NEED_INFO kind=tool`. If the app answered earlier in this same scenario (main or earlier edge) and then died, that is a genuine `FAIL` from a crash under test. An edge-only prerequisite gap stays `NEED_INFO — <kind>: <identifiers>` on its edge line and does not change the main-flow status. If the HTTP part runs but the DB client is unavailable, only `**DB check:** SKIP`; a scenario that does not apply to this stack/environment is `SKIP`. An assertion miss or wrong status is `FAIL`, never `NEED_INFO`.
3. **Deliberate omission / scope mismatch?** If the Expected is met but a defect outside that Expected is observed, report `PASS` and note the observation in Details rather than failing this scenario. A missing declared prerequisite uses check 2, not a scope exception.
4. **Harness error?** A tool timeout, client crash or query that never executed permits one retry **only for a failed observation or tool-initialisation step**, and only if check 1 has not already re-run it; each failing observation step is re-run exactly once total. A mutating action is never replayed. After an ambiguous POST/PUT/PATCH/DELETE or DB write, read resulting state once (GET, DB check or snapshot); if the outcome is established, grade on it; otherwise return `SKIP` with `harness error: <detail>; outcome unknown, action not replayed`. If a read-only harness step still cannot run after the single retry, return `SKIP — harness error: <detail>`, not application FAIL.

**Disposition:** A surviving scenario-level FAIL carries `- **Refutation:** <trace>` directly after `**Details:**`, e.g. `re-verified: yes (same result); env: n/a; scope: in; harness: ok`. A surviving edge FAIL has that trace inside its own details clause. A refuted FAIL becomes PASS, SKIP or NEED_INFO as appropriate; an edge-only NEED_INFO never changes the main-flow status. Do not replay any mutating action in any branch of this battery.

---

## Error Handling

- No HTTP client or no `perl` with `JSON::PP` when scenarios apply → each API scenario `NEED_INFO kind=tool`, with `Missing: curl` or `Missing: perl`.
- DB client unavailable → run the API; `**DB check:** SKIP`. No declared DB connection → `**DB check:** SKIP — no DB connection declared under ## Setup`.
- Timeout (>30 s), connection refused or empty reply → battery check 2: never reachable in this scenario → `NEED_INFO kind=service, Missing: <base URL>`; answered earlier in this scenario then died → `FAIL` with trace.
- Invalid JSON when JSON is expected → `FAIL`, recording only the sanitiser's `[body withheld by qa-redact: …]` line, never the raw body.
- Starting/building an app, editing files, running migrations or inspecting infrastructure is out of harness scope; a scenario requiring such a step is `SKIP — out of harness scope: <step>`. Only HTTP requests and DB queries against the running app are executable.

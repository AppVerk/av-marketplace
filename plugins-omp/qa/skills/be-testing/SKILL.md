---
name: "qa:be-testing"
description: Backend testing patterns — API request construction, response verification, read-only SQL and Redis State Checks, error handling testing, and adaptive tool detection.
allowed-tools: Bash(curl:*), Bash(httpie:*), Bash(http:*), Bash(wget:*), Bash(psql:*), Bash(sqlite3:*), Bash(mysql:*), Bash(redis-cli:*), Bash(command:*), Bash(printf:*), Bash([:*), Bash(cut:*), Bash(jq:*), Bash(grep:*), Bash(cat:*), Bash(head:*), Bash(tail:*), Read, Write, Bash(mkdir:*)
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
command -v redis-cli >/dev/null 2>&1 && printf 'redis-cli: available\n' || printf 'redis-cli: unavailable\n'

# JSON processing and fail-closed response sanitiser
command -v jq >/dev/null 2>&1 && printf 'jq: available\n' || printf 'jq: unavailable\n'
perl -MJSON::PP -e 1 >/dev/null 2>&1 && printf 'perl: available\n' || printf 'perl: unavailable\n'
```

Use an available HTTP client, but use `curl` for any request containing a credential: HTTPie's inline header/body arguments expose secret values in process argv. If `curl` is unavailable for a credential-bearing request, return `NEED_INFO kind=tool, Missing: curl` without sending it. If no HTTP client, or no `perl` with `JSON::PP`, is available and the scenarios apply, every API scenario is `NEED_INFO kind=tool, Missing: curl` (or `perl`). A store client missing only blocks its State Check.

### Connection selection

Tool availability alone does not establish a connection to a store. The dispatch's `Stores:` lists the configured stores this section's State Checks reference; each check selects its named store through `qa_load_store='<name>' qa_load_require='<required native names>' . '<run-dir>/load.sh' || exit 1`. A missing client skips only that check while HTTP still runs. Never discover connection values or use an MCP store connection: the dispatch declares no such connection.

---

## Execution Workflow

For each BE scenario from the test plan:

1. **Read the scenario** — understand method, endpoint, payload, expected response, State Checks and registration/login preconditions
2. **Execute the request** — send HTTP request with proper method, headers, body
3. **Verify response** — check status code, response body structure, specific values
4. **Verify state** (for each State Check) — run the read-only query/command against its named store and compare against expected
5. **Execute edge cases** — run each edge case as a sub-test
6. **Record result** — PASS/FAIL/SKIP/NEED_INFO with response details

The dispatch supplies `Plan:`, `Dispatch:`, `Run dir:`, `Secrets file:`, `Secrets JSON:`, `Redact names file:`, `Tag:`, `Targets:` (named origins and the default target for BE), `Stores:` and `Guarded:`, followed by `BE Test Scenarios:` in plan order. Do not parse the plan's optional `## Setup` notes. A scenario in `Guarded:` is `SKIP — mutation-guard`; execute none of its preconditions, main flow or edges. Values and supported names come from the engine's run-directory channel and this tester's captured preconditions only.

## Tester scope

These limits apply to the tester's own recovery actions as well as plan steps. Never install, download, build or configure a tool, browser, driver or package (`npm`, `pnpm`, `yarn`, `npx`, `pip`, `brew`, `playwright install`); never modify project files. Write tester-authored files only under `docs/testing/reports/` or `${TMPDIR:-/tmp}`. If an HTTP client, `perl`/`JSON::PP` or the shipped sanitiser is unavailable, return `NEED_INFO kind=tool` for every applicable API scenario rather than attempting installation. If only a store client is missing, still run the API and mark just `**State Check:** SKIP`. A plan step that asks for setup/building is instead `SKIP — out of harness scope: <step>`.

---

## Tag handling (plan grounding tags)

Handle the main `**Expected:**` and each edge-case expectation independently:

- `(path:line)` — source citation for humans; ignore it when matching the result.
- `(unverified — confirm at run time)` — still assert the expected result and report a mismatch as `FAIL`. Carry the tag into the result so an issue minted from this assertion is graded `LOW`, unless the observed status is ≥ 500 or there was a crash/stack trace.
- `(exact text — brittle)` — match the quoted text as a substring, not exact equality.

---

## API Testing Patterns

### Request Construction (curl)

Capture headers and body **once** per request. Every request Bash call begins with `qa_load_require='<configured names the request uses>' . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1`, then repeats the installed-script and dispatch names-file guard below, with lower-case `qa_redact_script` / `qa_redact_names`. Use empty `qa_load_require` for a credential-free request. Never pass arguments to the dot script: dash ignores them. Both capture files exist from the first call on. Bash calls do not share variables. Resolve the path against `**Target:**` or the section default and apply the exact origin guard before sending; `target_origin` below is a listed origin, not project config. Refuse a credential-bearing request on non-loopback HTTP with `SKIP — cleartext origin refused: <origin>`. `QA_CAPTURED_OWNER_TOKEN` is a tester-owned token example, not an engine-provisioned field. Never print request headers or credentials.

For a bearer or cookie header, reject CR/LF and escape `\` and `"` in curl config syntax, using config-on-stdin; never pass expanded credentials as HTTPie arguments or `-H`. The Perl writer below reads the captured value from the environment, keeping quotes/backslashes exact without leaking argv. For credential JSON payloads, a Perl/`JSON::PP` writer reads loaded env vars directly on a separate read-only file descriptor. Never use `-d "$SECRET"` or a credential-bearing URL argv. If curl cannot encode credentials safely, do not send the request or leak them to another client.

**GET request:**

```bash
qa_load_require= . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
[ -n "${QA_CAPTURED_OWNER_TOKEN:-}" ] || { printf 'NEED_INFO kind=fixture: owner\n'; exit 1; }
target_origin='<listed origin for this scenario>'
RESP=$(perl -e '$v=$ENV{QA_CAPTURED_OWNER_TOKEN}; die "invalid bearer token\n" if $v =~ /[\r\n]/; $v =~ s/([\\"])/\\$1/g; print "header = \"Authorization: Bearer $v\"\n"' | curl -K - -si -H "Content-Type: application/json" "$target_origin/api/resources" | perl "$qa_redact_script" "$qa_redact_names") || { printf 'qa-redact: capture failed\n'; exit 1; }
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^\r\{0,1\}$/d')
```

**Mutating request with a non-secret payload:** Send it once. For PUT/PATCH/DELETE, change only the method, endpoint and scenario-specified payload; keep the same loader, guard, capture, and status/body extraction. Never replay a write to re-verify a failure.

```bash
qa_load_require= . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
[ -n "${QA_CAPTURED_OWNER_TOKEN:-}" ] || { printf 'NEED_INFO kind=fixture: owner\n'; exit 1; }
target_origin='<listed origin for this scenario>'
RESP=$(perl -e '$v=$ENV{QA_CAPTURED_OWNER_TOKEN}; die "invalid bearer token\n" if $v =~ /[\r\n]/; $v =~ s/([\\"])/\\$1/g; print "header = \"Authorization: Bearer $v\"\n"' | curl -K - -si -X POST -H "Content-Type: application/json" -d '{"name": "test", "email": "test@example.com"}' "$target_origin/api/resources" | perl "$qa_redact_script" "$qa_redact_names") || { printf 'qa-redact: capture failed\n'; exit 1; }
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^\r\{0,1\}$/d')
```

### Registration and login preconditions

Use the scenario's grounded endpoint, payload and response fields. Registration emails are `qa+<Tag>-<user>@…` and use the run's `QA_NEW_PASSWORD`; existing users log in with `QA_<U>_EMAIL` / `QA_<U>_PASSWORD`. A registered user's `$QA_OWNER_EMAIL` is rebuilt from the dispatch `Tag:` with the same user name and domain as registration (`qa+$QA_TAG-owner@test.local` in the example); `$QA_OWNER_ID` is captured from the registration response. Neither is a channel name. Rebuild the email after sourcing load.sh in every later Bash call; never capture it with `capture.sh` or add it to `redact-names`, so email assertions remain observable. If used before registration ran, return `NEED_INFO kind=fixture` naming the user. A missing `jq` for required extraction is `NEED_INFO kind=tool`, not permission to guess a token.

**Claude Code permissions:** `sh`, `sed`, `perl` and `tr` deliberately have no wildcard pre-approval. Accept the normal permission prompt for each required capture-helper call, sanitiser invocation, credential-header writer or read-only extraction pipeline; approve the shown command, never `Bash(sh:*)`, `Bash(sed:*)`, `Bash(perl:*)`, `Bash(tr:*)`, unrestricted Bash or a permission bypass. If permission is denied or unavailable, do not replay registration/login or print the raw response: an unavailable credential capture is `NEED_INFO kind=tool, Missing: capture.sh`; unavailable account recording is `NEED_INFO kind=fixture` naming the email, with `accounts[]` as the fallback.

For these preconditions only, hold raw HTTP in `RESP=$(curl -si …)` without printing/persisting it. Extract credentials directly into `capture.sh` from this one response, record a successful registration immediately, then source captured.env again **before sanitising the same response**. Only sanitised evidence may be inspected or saved; a newly issued token echoed under `message` is then masked too. The example registers owner on a loopback/HTTPS origin already checked against Targets:

```bash
qa_load_require=QA_NEW_PASSWORD . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
QA_TAG='<tag from dispatch>'
export QA_REG_EMAIL="qa+$QA_TAG-owner@test.local"
target_origin='<listed loopback or HTTPS origin>'
RESP=$(curl -si -X POST -H "Content-Type: application/json" --data-binary @/dev/fd/3 "$target_origin/register" 3< <(perl -MJSON::PP -e 'print encode_json({email=>$ENV{QA_REG_EMAIL},password=>$ENV{QA_NEW_PASSWORD}})')) || { printf 'registration outcome unknown; not replayed\n'; exit 1; }
qa_status=$(printf '%s' "$RESP" | head -n 1 | cut -d' ' -f2)
# Capture only fields this producer returns, after its grounded success status.
if [[ "$qa_status" = 2?? ]]; then
  qa_capture_failed=0
  printf '%s' "$RESP" | sed '1,/^\r\{0,1\}$/d' | jq -r '.access_token' | sh '<run-dir>/capture.sh' <dispatch> QA_CAPTURED_OWNER_TOKEN || qa_capture_failed=1
  printf '%s' "$RESP" | sed '1,/^\r\{0,1\}$/d' | jq -r '.id' | sh '<run-dir>/capture.sh' <dispatch> QA_CAPTURED_OWNER_ID || qa_capture_failed=1
  qa_registered_id=$(printf '%s' "$RESP" | sed '1,/^\r\{0,1\}$/d' | jq -r '.id // empty')
  sh '<run-dir>/capture.sh' <dispatch> --account "$QA_REG_EMAIL" "$qa_registered_id" || { printf 'NEED_INFO kind=fixture: %s\n' "$QA_REG_EMAIL"; exit 1; }
  [ "$qa_capture_failed" = 0 ] || { printf 'NEED_INFO kind=tool: capture.sh\n'; exit 1; }
fi
. '<run-dir>/results/<dispatch>/captured.env' || exit 1
RESP=$(printf '%s' "$RESP" | perl "$qa_redact_script" "$qa_redact_names") || { printf 'qa-redact: capture failed\n'; exit 1; }
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^\r\{0,1\}$/d')
```

Replace the illustrative `/register`, success status, domain and extraction paths only with the actual route contract. If no id is returned, record with `sh '<run-dir>/capture.sh' <dispatch> --account "$QA_REG_EMAIL"` and no id. Record even when later credential extraction fails; never replay registration. For login, source the configured email/password and encode those fields on fd 3, capture the returned credentials the same way, but do not record an existing account.

For a session response, use this exact cookie pipeline instead of the bearer-token line above. Strip the header's carriage return before capture, including when `Set-Cookie` has no attributes:

```bash
printf '%s' "$RESP" | sed -n 's/^[Ss]et-[Cc]ookie: *\([^;]*\).*/\1/p' | tr -d '\r' | head -n 1 | sh '<run-dir>/capture.sh' <dispatch> QA_CAPTURED_OWNER_COOKIE
```

Then source captured.env before sanitising that response. A cookie is the full `name=value` pair. Later requests send `Authorization: Bearer $QA_CAPTURED_<USER>_TOKEN` or `Cookie: $QA_CAPTURED_<USER>_COOKIE`, with the same CR/LF rejection and curl-config escaping. Keep required multi-step cookie/CSRF flows in the scenario's preconditions; never invent credentials or bypass auth. A non-zero `capture.sh --account` result is `NEED_INFO kind=fixture` naming the email, with `accounts[]` as the secondary record path.

### Request Construction (httpie)

Use HTTPie only for requests without credentials (including credentials in a payload or URL); it passes inline headers and fields on argv. For a credential-bearing scenario, use curl above. Without curl, return `NEED_INFO kind=tool, Missing: curl` rather than leaking credentials through HTTPie. Even credential-free calls source the channel so the sanitiser can mask all exposed values:

```bash
qa_load_require= . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
target_origin='<listed origin for this scenario>'
RESP=$(http --print=hb GET "$target_origin/api/resources" | perl "$qa_redact_script" "$qa_redact_names") || { printf 'qa-redact: capture failed\n'; exit 1; }
STATUS=$(printf '%s\n' "$RESP" | head -n 1 | cut -d' ' -f2)
BODY=$(printf '%s\n' "$RESP" | sed '1,/^\r\{0,1\}$/d')
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

## State Check Verification Patterns

### PostgreSQL (psql)

For a listed store of kind `sql` / engine `postgres`, source `qa_load_store='<name>' qa_load_require=PGPASSWORD . '<run-dir>/load.sh' || exit 1`. It exports `PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD PGOPTIONS`; `PGOPTIONS=-c default_transaction_read_only=on` makes State Checks read-only. The loader refuses an unknown store or an empty exported endpoint; never continue with client defaults after failure. libpq reads them without expanding a DSN/password into `psql` argv, including a non-default `PGPORT`. Do not supply a connection URI, `-h`, `-U`, `-d`, or a password flag; do not use `DATABASE_URL` (a malformed URI can appear in libpq error output). Suppress raw client errors; never print connection errors containing credentials.

Select only columns needed for the assertion; never run `SELECT *` from a plan. Return JSON even for counts so output passes through the installed sanitiser **before** inspection. Begin each State Check Bash call with `qa_load_store='<name>' qa_load_require='<required names>' . '<run-dir>/load.sh'`, then captured.env, the script/names-file guard and `set -o pipefail` in that same invocation. A client/sanitiser failure skips only the check and does not block HTTP. Suppress client stderr. Withheld non-JSON or a masked asserted value → `SKIP — cannot confirm`, never fall back to raw output. Report only an assertion-relevant sanitised count/excerpt from `DB_RESULT`, never a full row.

```bash
qa_load_store='<name>' qa_load_require=PGPASSWORD . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
DB_RESULT=$(psql -tAc "SELECT json_build_object('count',COUNT(*)) FROM resources WHERE name = 'test';" 2>/dev/null | perl "$qa_redact_script" "$qa_redact_names") || { unset DB_RESULT; printf 'State Check: SKIP — unavailable\n'; }
```

For a row-level assertion, project only the asserted columns as JSON; sensitive keys and declared env values are masked by `qa-redact`. Do not assert a value hidden by the sanitiser:

```bash
qa_load_store='<name>' qa_load_require=PGPASSWORD . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
DB_RESULT=$(psql -tAc "SELECT coalesce(json_agg(t),'[]'::json) FROM (SELECT id, status FROM resources WHERE id = 1) t;" 2>/dev/null | perl "$qa_redact_script" "$qa_redact_names") || { unset DB_RESULT; printf 'State Check: SKIP — unavailable\n'; }
```

Flags: `-t` (tuples only), `-A` (unaligned output), `-c` (SQL).

### SQLite

For a listed `sql` / `sqlite` store, source `SQLITE_DB` through its named loader selection and use `-readonly`:

```bash
qa_load_store='<name>' qa_load_require=SQLITE_DB . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
DB_RESULT=$(sqlite3 -readonly "$SQLITE_DB" "SELECT json_object('count',COUNT(*)) FROM resources WHERE name = 'test';" 2>/dev/null | perl "$qa_redact_script" "$qa_redact_names") || { unset DB_RESULT; printf 'State Check: SKIP — unavailable\n'; }
```

For a row: `SELECT json_group_array(json_object('id',id,'status',status)) FROM resources WHERE id = 1;` through the same sanitised capture.

### MySQL

For a listed `sql` / `mysql` store, source its named loader selection. It exports `MYSQL_HOST MYSQL_TCP_PORT MYSQL_USER MYSQL_DATABASE MYSQL_PWD`. TCP and explicit `-P` preserve a non-default port even for `localhost`; `--init-command="SET SESSION TRANSACTION READ ONLY"` makes the session read-only, and the password is read from `MYSQL_PWD`, never a command-line argument:

```bash
qa_load_store='<name>' qa_load_require=MYSQL_PWD . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
DB_RESULT=$(mysql --protocol=TCP -h "$MYSQL_HOST" -P "$MYSQL_TCP_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" --init-command="SET SESSION TRANSACTION READ ONLY" -N -e "SELECT JSON_OBJECT('count',COUNT(*)) FROM resources WHERE name = 'test';" 2>/dev/null | perl "$qa_redact_script" "$qa_redact_names") || { unset DB_RESULT; printf 'State Check: SKIP — unavailable\n'; }
```

For a row: `SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT('id',id,'status',status)), JSON_ARRAY()) FROM resources WHERE id = 1;` through the same sanitised capture. Flag: `-N` skips column names.

### Redis

For a listed `redis` store, the loader exports `REDIS_HOST REDIS_PORT REDIS_DB` and `REDISCLI_AUTH` only when configured. Set `qa_load_require=REDISCLI_AUTH` alongside `qa_load_store='<name>'` only for a password-protected store; otherwise use empty `qa_load_require`. A missing redis-cli skips only the check. A redis-cli without `--json` returns `NEED_INFO kind=tool` naming that capability; never fall back to raw Redis output or install a client.

Only these commands are allowed: `GET MGET EXISTS TTL TYPE STRLEN HGET HLEN LLEN LRANGE SCARD SISMEMBER ZCARD ZSCORE XLEN SCAN`. Refuse all other Redis commands, regardless of `qa.mutations`; State Checks never write. Wrap scalar, array and null replies as a JSON object before sanitising:

```bash
qa_load_store='<name>' qa_load_require= . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
DB_RESULT=$(redis-cli --json --no-auth-warning -h "$REDIS_HOST" -p "$REDIS_PORT" -n "$REDIS_DB" GET <key> 2>/dev/null | { printf '{"reply":'; cat; printf '}'; } | perl "$qa_redact_script" "$qa_redact_names") || { unset DB_RESULT; printf 'State Check: SKIP — unavailable\n'; }
```

Substitute only the check's allowlisted command and arguments. Use `REDISCLI_AUTH` from the environment, never `-a <password>` or a credential-bearing URI.

### Connection reference

Connect only to a store in the dispatch's `Stores:` through `qa_load_store='<name>' . '<run-dir>/load.sh'`: postgres aliases (including `PGOPTIONS`), mysql aliases, `SQLITE_DB`, or Redis aliases. No inherited/default connection, `DATABASE_URL`, alternate SQLite name or MCP server is supported. A missing client skips only its State Check while HTTP runs. Never put literal connection values or a password/DSN on argv. Recommend a read-only database role in addition to client enforcement.

---

## Credential Safety Rules

- Never print an exposed value, header, cookie, token or DSN into output, reports or dumps. The loader reports only names on failure; no environment-value preflight is needed.
- Credentials and configured values come from the run channel: the fields of existing users that plan tokens reference among `QA_<U>_EMAIL`, `_PASSWORD` and `_ID`, configured `QA_<VALUE>`, `QA_NEW_PASSWORD` and namespaced store client variables. The dispatch supplies `Tag:`; registration/login preconditions produce tester-owned `QA_CAPTURED_<USER>_*` in captured.env. Never expand an unsupported name or read another source; an unknown name is `SKIP — cannot-confirm: name not exposed by the engine`, not a runtime credential request. Registered `$QA_<U>_EMAIL` is rebuilt from the dispatch tag and the registration's user name/domain, while `$QA_<U>_ID` is captured from its response, not a channel field; before registration they are `NEED_INFO kind=fixture` naming the user. Never use inherited env vars or read `.env`, `.env.*`, `docker-compose*.yml`, framework config or engine-private files for values. Never invent or mint a token outside the scenario's registration/login preconditions. Never put credential-bearing URLs, headers, payloads or store passwords/DSNs on argv; use curl config-on-stdin, JSON on a read-only file descriptor and client environment names.
- Resolve paths against the scenario's `**Target:**` or the section default in `Targets:`. Before sending any absolute URL, compare its origin (scheme, lowercased host, explicit or default port) exactly with a listed origin. Different schemes or ports are different origins; userinfo is always refused. Refusal is `SKIP — off-target URL refused: <origin>` with no userinfo/query/fragment. Never follow redirects automatically (`curl -L`, `http --follow`); explicitly request a scenario-specified `Location` only after this same origin check. Before any credential-bearing request, also require loopback or HTTPS; non-loopback HTTP is `SKIP — cleartext origin refused: <origin>`, even if configured.
- The engine owns `<run-dir>/redact-names`; use the per-dispatch `<run-dir>/results/<dispatch>/redact-names` copy for evidence, so captures are masked from their first response onward. It lists exposed user/value and namespaced/native store names, excluding PGOPTIONS; port/db-number names are accepted but not masked. Never rewrite these files yourself; `capture.sh` appends captured names. Source both loader and captured.env even for a credential-free request, so all known values are available for masking. An empty needed channel name sends nothing: `NEED_INFO kind=credentials, Missing: <names>` (normally prevented before dispatch). An unreadable/unsafe channel is `NEED_INFO kind=tool`, naming the channel file, not a request to export values or restart the harness.
- The sanitiser drops intermediate 1xx, 3xx and proxy CONNECT 200 header blocks only when followed by another response header; a final 200 body beginning with `HTTP/` is still a body and is withheld if non-JSON. It classifies final header names and JSON keys at any depth by splitting on `_`, `-`, other non-alphanumerics and camelCase humps (`APIKey` → `api`, `key`), and dropping plural `s` from each part. Sensitive parts are `token`, `secret`, `password`, `passwd`, `pwd`, `passphrase`, `key`, `session`, `cookie`, `auth`, `authorization`, `credential`, `private`, `dsn`, `url`, `uri`, `jwt`, `bearer`, `otp`, `pin`, `sig`, `signature`; joined parts also match `token`, `secret`, `passw`, `apikey`, `accesskey`, `privatekey`, `sessionid`, `sessid`, `csrf`, `xsrf`, `credential`, `connectionstring`, `recoverycode`, `verificationcode`, `backupcode`. Sensitive values become `***` (`client_secret`, `apiKeys`, `IDToken`, `csrftoken`, `mongoUri`, `recovery_codes`, `Set-Cookie`, `access-token`; not `author`, `authorId`, `code` or `Access-Control-*`).
- **URL-only names:** when the only sensitive parts are `url`/`uri`, the name is not a one-time link (`reset`, `confirm`, `verify`, `invite`, `magic`, `recover`, `activate`, `callback`), and the value is a valid absolute HTTP(S) URL, the sanitiser keeps scheme, host, port and path but masks all userinfo, query and fragment (`https://***@host/path?***#***`). One-time links, non-HTTP(S)/invalid URLs, non-string values and names with another sensitive part (`sessionUrl`, `accessToken`) stay fully masked. This is sanitisation, not permission to follow the returned URL.
- Across output it also masks `Bearer` tokens, sensitive query/fragment parameter values (names containing `token`, `key`, `secret`, `passw`, `pwd`, `auth`, `session`, `code`, `sig`, `credential`), URI passwords and declared values of at least four characters from the dispatch names file. Declared-value masking still applies inside kept URL paths and before JSON encoding, so quotes/backslashes cannot evade it. Native and namespaced `PGPORT`, `MYSQL_TCP_PORT`, `REDIS_PORT` and `REDIS_DB` values are exempt so a port/count stays observable. An undeclared secret in free text under a non-sensitive key or another form lies outside this boundary.

The sanitiser is shipped as `scripts/qa-redact.pl` **next to this skill's `SKILL.md`**. Do not re-type it, copy it into a temporary directory, or execute a similarly named project file. In OMP resolve its installed absolute path with `realpath skill://qa:be-testing/scripts/qa-redact.pl` (the Bash tool resolves `skill://` paths); do not guess a path under `~/.omp`. In Claude Code use the loaded skill's base directory, or `${CLAUDE_PLUGIN_ROOT}/skills/be-testing` if available. Set lower-case `qa_redact_script` to that absolute path after loading, not the skill URI. Resolution/guard failure → no request and `NEED_INFO kind=tool, Missing: qa-redact.pl`.

Before **every** HTTP call or State Check, start the same Bash invocation with the loader and then captured.env, and repeat this guard. Substitute the dispatch's run directory and dispatch names-file path, and the resolved installed skill directory; none comes from a plan-supplied script path. Set `qa_load_require` to a quoted space-separated list of required configured names for an HTTP request, or empty for a credential-free request. For a State Check also set `qa_load_store` to the store name and use required native client names in `qa_load_require`. These are assignments before `. '<run-dir>/load.sh'`, never dot-script arguments. Check needed captured credentials after sourcing captured.env. Assign and validate lower-case bookkeeping paths **after** loading so an exposed `QA_` name cannot overwrite them:

```bash
qa_load_require='<required configured names, or empty>' . '<run-dir>/load.sh' && . '<run-dir>/results/<dispatch>/captured.env' || exit 1
qa_redact_script='<installed skill directory>/scripts/qa-redact.pl'
qa_redact_names='<run-dir>/results/<dispatch>/redact-names'
[ -f "$qa_redact_names" ] && [ -r "$qa_redact_names" ] && [ ! -L "$qa_redact_names" ] && [ -O "$qa_redact_names" ] || { printf 'qa-redact: names file unavailable\n'; exit 1; }
[ -f "$qa_redact_script" ] && [ -r "$qa_redact_script" ] && [ ! -L "$qa_redact_script" ] || { printf 'qa-redact: unavailable or unsafe script\n'; exit 1; }
perl -c "$qa_redact_script" >/dev/null 2>&1 || { printf 'qa-redact: invalid script\n'; exit 1; }
set -o pipefail
```

Only then send the request. Append `|| { printf 'qa-redact: capture failed\n'; exit 1; }` to `RESP=$(… | perl "$qa_redact_script" "$qa_redact_names")` so neither client nor sanitiser failure can be treated as an empty successful response. A failure means the request outcome is unknown; **never replay a mutating request**. No raw HTTP may be printed or persisted in any failure branch.

Read and persist HTTP evidence **only** after `perl "$qa_redact_script" "$qa_redact_names"` succeeds. Normal requests pipe directly into it; registration/login first capture raw `RESP` privately, extract credentials and record the account, source captured.env, then sanitise that same response and replace `RESP`. Dumps and inline excerpts come only from sanitised `$RESP` (body from `$BODY` after splitting `$RESP`). When a Bash call ends, its variables are lost: save needed evidence from that call's sanitised `$RESP` before it ends, or use the one permitted refutation capture. **Never send another request solely to write an artifact.** Non-JSON or bare-string bodies are withheld (`[body withheld by qa-redact: …]`); the status line and sanitised headers remain available.

---

## Error Handling Test Patterns

Construct each case from the plan's method, expected status and payload using the guarded, single-capture pattern above; a status below is an example, not a replacement for the plan's expectation:

| Case | Request variation | Typical assertion |
|------|-------------------|-------------------|
| Missing required field | POST a JSON payload omitting that field | 422 and validation body |
| Unauthenticated | Omit Authorization (do not mint a token) | 401 |
| Insufficient permissions | Use the plan's declared regular-user credential | 403 |
| Resource not found | GET a nonexistent resource | 404 |
| Duplicate creation | Only if the plan specifies both actions, create once and attempt the duplicate once | 409; never repeat either POST during refutation |

For all cases use `$RESP`/`$STATUS`/`$BODY` from the sanitiser, not raw output or a second request for status. The FAIL refutation battery below applies to each mismatch.

---

## Result Format

For each scenario, return results in this format:

```
### BE-XX: <scenario name>
- **Status:** PASS / FAIL / SKIP
- **Request:** <METHOD> <URL only — no headers>
- **Response status:** <actual status code>
- **Response body:** <decision-relevant sanitised excerpt from $RESP or path docs/testing/reports/responses/<ID>-body.json for long responses>
- **State Check:** <store: PASS/FAIL/SKIP — asserted count or decision-relevant excerpt from sanitised DB_RESULT vs expected; never raw output or full rows; repeat for every check>
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
- **Missing:** <comma-separated identifiers: exposed names, target origin, fixture table/row or file, or binary names; never values>
- **Details:** <what was attempted and what was absent; never a secret value>
```

An edge-only prerequisite gap remains on its own `- <edge case>: NEED_INFO — <kind>: <identifiers>` line; keep the main flow's PASS/FAIL status. A store-client gap with runnable HTTP is `**State Check:** SKIP`, not a scenario NEED_INFO. `SKIP` also covers inapplicable scenarios, mutation-guard marks, out-of-harness steps and unknown outcomes after harness errors. Store response dumps only from sanitised `$RESP` under `docs/testing/reports/responses/<ID>-body.json` (edge n: `<ID>-edge<n>-body.json`), never timestamps or QA issue IDs.

After the human-readable results, end the answer with exactly one `qa-results` block:

```json qa-results
{"section": "BE", "accounts": [], "scenarios": [
  {"id": "BE-01", "status": "PASS", "observed_status": 201, "crash": false, "kind": null, "missing": [], "skip_reason": null,
   "refutation": null, "edges": [{"n": 1, "status": "FAIL", "observed_status": 500, "crash": true, "kind": null, "missing": [], "skip_reason": null, "refutation": "re-verified: yes; env: n/a; scope: in; harness: ok"}]}
]}
```

Use actual assigned IDs and observations. Include every assigned scenario and planned edge exactly once in plan order; edge `n` is 1-based. `status` is `PASS|FAIL|SKIP|NEED_INFO`, independently for main flow and each edge. `observed_status` is the observed HTTP code or `null` when none was observed. `crash` is `true` only for an observed stack trace, framework debug page or app dying under test; include no page content. For `NEED_INFO`, use `kind: credentials|service|fixture|tool` and identifiers-only `missing`; otherwise `kind: null`, `missing: []`. `credentials` means an exposed name is empty, which the engine prevents before dispatch. `skip_reason` is the actual SKIP reason or `null`; planned edges blocked by the main flow remain unexecuted and are recorded as SKIP with that reason. Every surviving FAIL has its refutation trace, otherwise `refutation: null`. A failed State Check assertion is folded into the main-flow FAIL and trace; a State-Check-only SKIP does not alter its status. The engine reads only this block: invalid/missing output or incomplete assignments become `cannot-confirm`, never earlier PASS.

`accounts` is the secondary path for a successful registration that `capture.sh --account` could not record: add `{"email": "<registered email>", "id": "<returned id>"}` or `"id": null` when unknown; otherwise emit `[]`. Record immediately with the helper first, before another step. Acceptance requires a safe email containing the dispatch tag in its local part (case-insensitively), a null/safe id, and an email unequal to any configured channel user's email. Invalid entries are rejected; malformed account-list structure invalidates the entire block. Never include a password, token or cookie.

---

## FAIL refutation battery (before returning any FAIL)

A FAIL is a claim — refute it before reporting ANY `FAIL`: the scenario `**Status:**`, each edge-case sub-result, or `**State Check:**` (an edge failure under a passing main flow is independently reported).

1. **Re-verify the observation — once, deterministically, observation-only.** For GET/HEAD or a read-only State Check, repeat the identical read exactly once. For a POST/PUT/PATCH/DELETE or SQL/Redis write, never re-fire the action; re-read its resulting state once with a GET or State Check. One check, then disposition — not retry-until-pass. If two identical READs disagree, record both observations in Details: nondeterminism is itself `FAIL` (unlike a write, which may legitimately return 201 then 409 if fired twice).
2. **Environment artifact?** An exposed name empty in the run-directory channel → `NEED_INFO kind=credentials` (the engine normally prevents it); the app/dependency never reachable in this scenario (connection refused, DNS failure, timeout before any response) → `NEED_INFO kind=service, Missing: <target origin>`; missing seed/file → `NEED_INFO kind=fixture`; required binary missing → `NEED_INFO kind=tool`. If the app answered earlier in this same scenario (main or earlier edge) and then died, that is a genuine `FAIL` from a crash under test. An edge-only prerequisite gap stays `NEED_INFO — <kind>: <identifiers>` on its edge line and does not change the main-flow status. If HTTP runs but a store client is unavailable, only `**State Check:** SKIP`; an inapplicable scenario is `SKIP`. An assertion miss or wrong status is `FAIL`, never `NEED_INFO`. A BE main flow expecting 2xx that observes 401/403 is always FAIL flagged `auth`; do not weaken authentication to pass it.
3. **Deliberate omission / scope mismatch?** If the Expected is met but a defect outside that Expected is observed, report `PASS` and note the observation in Details rather than failing this scenario. A missing declared prerequisite uses check 2, not a scope exception.
4. **Harness error?** A tool timeout, client crash or query that never executed permits one retry **only for a failed observation or tool-initialisation step**, and only if check 1 has not already re-run it; each failing observation step is re-run exactly once total. A mutating action is never replayed. After an ambiguous POST/PUT/PATCH/DELETE or store write, read resulting state once (GET, State Check or snapshot); if the outcome is established, grade on it; otherwise return `SKIP` with `harness error: <detail>; outcome unknown, action not replayed`. If a read-only harness step still cannot run after the single retry, return `SKIP — harness error: <detail>`, not application FAIL.
5. **Masked assertion?** Check the sanitised response, never the raw response. If an expected value cannot be observed because `qa-redact` replaced it with `***` (under a sensitive key such as `key`, `avatar_url` or `session_count`, or because it matches a declared env var), do not treat that redaction as an application mismatch. Return `SKIP — cannot confirm: value masked by qa-redact (<key>)` for the affected main flow or edge case, not `FAIL`; name the affected key, not the hidden value. An independently observable mismatch (such as the wrong HTTP status or an unmasked field) remains `FAIL`; unaffected assertions may still be checked. Never interpret `***` as proof of the original value or its type, and never bypass the sanitiser to resolve the uncertainty.

**Disposition:** A surviving scenario-level FAIL carries `- **Refutation:** <trace>` directly after `**Details:**`, e.g. `re-verified: yes (same result); env: n/a; scope: in; harness: ok`. A surviving edge FAIL has that trace inside its own details clause. A refuted FAIL becomes PASS, SKIP or NEED_INFO as appropriate; an edge-only SKIP or NEED_INFO never changes the main-flow status. Do not replay any mutating action in any branch of this battery.

---

## Error Handling

- No HTTP client or no `perl` with `JSON::PP` when scenarios apply → each API scenario `NEED_INFO kind=tool`, with `Missing: curl` or `Missing: perl`.
- Store client unavailable → run the API; only its `**State Check:** SKIP`. `Stores: none` permits no State Check connection.
- Timeout (>30 s), connection refused or empty reply → battery check 2: never reachable in this scenario → `NEED_INFO kind=service, Missing: <target origin>`; answered earlier in this scenario then died → `FAIL` with trace.
- Invalid JSON when JSON is expected → `FAIL`, recording only the sanitiser's `[body withheld by qa-redact: …]` line, never the raw body.
- Starting/building an app, editing files, running migrations or inspecting infrastructure is out of harness scope; a scenario requiring such a step is `SKIP — out of harness scope: <step>`. Only HTTP requests and read-only State Checks against the running app are executable.
- A URL with userinfo or an origin not exactly listed in `Targets:` (scheme, lowercased host, explicit/default port) → never sent; `SKIP — off-target URL refused: <origin>` (see Credential Safety Rules).
- A credential-bearing request to configured, non-loopback HTTP → `SKIP — cleartext origin refused: <origin>`; no credential is sent.
- An unexposed/unsupported `$NAME` → never checked or expanded; `SKIP — cannot-confirm: name not exposed by the engine`, with the identifier only. Only an empty exposed name is `NEED_INFO kind=credentials`; never obtain values from another source.

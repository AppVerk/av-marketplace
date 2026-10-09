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

Every test plan MUST follow this structure; omit optional sections and `**Blocked-by:**` lines where they do not apply. Targets, configured existing users, exposed values, stores and service bring-up come from the project config. The plan declares users and tester-owned registration/login preconditions. Replace the illustrative target names, paths, expected results and citation tags with grounded project-specific details:

~~~markdown
# Test Plan: <title>

## Setup

<Optional human notes, such as a prerequisite to reverse BLK-01 before the run. No consumer parses this section; omit it when no notes are needed.>

## Source
- Type: <PR #N / branch <name> / last N commits / staged changes>
- Base: <main/master>
- Date: <YYYY-MM-DD>
- Branch: <current checkout branch>
- Head: <current checkout HEAD sha>

## Changes Summary

<Brief description of what changed and what needs testing. List affected areas.>

## Blockers / Findings

Defects in the code under test that obstruct how it must be tested. Mandatory — write `None found.` when there are none.

### BLK-01: <one-line defect> — `(file:line)`
- **Impact on testing:** <affected scenarios and the spurious result the defect forces>
- **Remediation (human Setup prerequisite):** <human action before the run>
- **Blocks:** <scenario IDs carrying `**Blocked-by:** BLK-01`>

## Users
- owner: registered — plain user who owns the resource
- other: registered — second plain user for ownership checks
- admin: existing — administrator (qa.users.admin)

## Detected Tools
- Playwright MCP: <available/unavailable>
- HTTP client: <curl/httpie/unavailable>
- Store clients: <psql/sqlite3/mysql/redis-cli/unavailable>

## FE Test Scenarios

### FE-01: <scenario name>
**Blocked-by:** BLK-01
- **Area:** <component/page>
- **Target:** ui
- **Writes:** yes
- **Preconditions:** Register owner through the signup form with email `qa+$QA_TAG-owner@test.local` and password `$QA_NEW_PASSWORD`; retain the email and returned user id as owner's values. Create required data through browser (UI) actions as owner and record the identifiers.
- **Steps:**
  1. Open `/login` in the browser
  2. Fill Email with `$QA_OWNER_EMAIL` from the registration precondition and Password with `$QA_NEW_PASSWORD`
  3. Click "Sign In"
- **Expected:** <welcome text shown> (path:line)
- **Edge cases:**
  - Password `nope`: <validation message shown> (path:line)
  - Missing email: <validation message shown> (path:line)

## BE Test Scenarios

### BE-01: <scenario name>
**Blocked-by:** BLK-01
- **Area:** <endpoint/service>
- **Target:** backend
- **Writes:** yes
- **Preconditions:** POST `/register` with email `qa+$QA_TAG-owner@test.local` and password `$QA_NEW_PASSWORD`; retain owner's access token and user id. Create any required data through HTTP requests as owner, recording the identifiers.
- **Method:** <HTTP method> <path>
- **Headers:** Authorization: Bearer owner's access token retained from the registration precondition (tester-owned, not a plan token)
- **Payload:** `<JSON body>`
- **Expected:** <status code>, <response body description> (path:line)
- **State Check:** <store>: SELECT COUNT(*) FROM resources WHERE user_id = '$QA_OWNER_ID' → <expected count>
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
The BE tester sees only the output of `qa-redact`: it replaces values under sensitive name segments (`key`, `session`, etc.), exposed values from the run's secrets channel, and every value the tester captured with `capture.sh` (tokens, cookies and registered users' IDs such as `$QA_OWNER_ID`) with `***`. Use a registered user's ID as request or query input, or assert a count, rather than asserting it in a response body. A key whose only sensitive segments are `url`/`uri` may retain the scheme, host, port and path of an absolute HTTP(S) URL; plans may assert those visible components, but not masked userinfo, query or fragment. A response URL on an origin outside `[env.targets]` is asserted by separate components (for example, scheme `http`, host `localhost:9000`, path prefix `/avatars/`), never written as a literal `scheme://host…` string anywhere in the scenario. One-time links (`reset`, `confirm`, `verify`, `invite`, `magic`, `recover`, `activate`, `callback`), keys with another sensitive segment (such as `sessionUrl`), and URL-named values that do not parse as absolute HTTP(S) URLs stay fully masked. Exposed-value masking still applies, including inside a retained URL path: never assert a component that became `***`. For fully masked fields, assert an observable property such as key presence or the type of an unaffected surrounding field/object, not the hidden value or its original type. For example, assert that `flags[0]` has a `key` field, not that `flags[0].key` equals `feature_x`; an assertion on masked data cannot establish PASS or FAIL and is reported as `SKIP — cannot confirm: value masked by qa-redact (<key>)` at run time. Keep other independently observable assertions, such as HTTP status codes, testable.

## Config references and preconditions

- `## Source` records the diff source, base, date, current checkout `Branch:` and `Head:`. These identify the branch and snapshot for plan selection and staleness checks.
- `## Setup` is optional human notes only, directly after the title when present. No consumer parses it. Do not declare URLs, credentials, database connections or service commands there; their configuration belongs in `.av/config.toml` and its local overrides.
- `## Users` is the section between that heading and the next `## ` heading. Each line is `- <name>: existing|registered — <description>` (a `*` bullet is also accepted). Names match `[a-z][a-z0-9_]*`; the first declaration wins if repeated. A plain user signup can create is `registered`; a role or state signup cannot produce is `existing` and must be configured under `[qa.users.<name>]`. Include owner, other user and each required role; anonymous actions use no user credential. Use at most 10 registered users per plan.
- An existing user's uppercased name gives only the fields the plan's tokens reference among `QA_<U>_EMAIL`, `QA_<U>_PASSWORD` and `QA_<U>_ID` (ID only when configured); a field no token names is never exposed, so a login as that user writes both `$QA_<U>_EMAIL` and `$QA_<U>_PASSWORD` in the scenario. A registered user's `$QA_<U>_EMAIL` / `$QA_<U>_ID` are tester-owned values from its registration step, not channel names. Its password is the run's `$QA_NEW_PASSWORD`; the dispatch supplies `$QA_TAG`, used in emails such as `qa+$QA_TAG-owner@test.local`. Using a registered user's values before registration ran is `NEED_INFO kind=fixture` naming the user at run time.
- `$QA_NAME` / `${QA_NAME}` tokens are scanned anywhere in a scenario: steps, headers, payloads, preconditions and edges. Resolution order is: (1) engine-issued `TAG` and `NEW_PASSWORD`; (2) any name ending in `_TOKEN`, `_COOKIE` or `_COOKIE_<N>` is a plan error, because testers obtain tokens/cookies themselves; (3) `EMAIL|PASSWORD|ID` fields of the longest user-name prefix among plan declarations and configured users; (4) an `[env.values]` name; (5) an undeclared name ending in `_EMAIL|PASSWORD|ID` is a plan error; (6) any other name is `missing.values`. Never write `$QA_<U>_TOKEN` or cookie tokens in a plan; say to retain the token/cookie from a grounded registration/login precondition and use it in later requests.
- A declared `existing` user referenced by a token but not configured is `missing.users` with reason `user is not configured`; a requested id without a configured source has reason `id source is not configured`. A declared `registered` user needs no config, but cannot share a name with a configured user (`user <n> is configured; declare it existing`). A configured user used by a token must be declared under `## Users`; otherwise it is a plan error `user <n> is configured but not declared under ## Users`. Names `new`, `captured` and `captured_*` are reserved. Values cannot collide with exposed user fields, `TAG`, `NEW_PASSWORD` or `CAPTURED_*`, or use a reserved token/cookie suffix. `[env.secrets]` is never tester-visible.
- A login/form credential or API key uses a supported user/value token; bearer tokens and cookies instead come from tester-owned preconditions. Never use the project's own variable name (`API_KEY`), a literal credential or an ungrounded placeholder. A deliberately invalid input in a negative edge case is not a credential. Never copy secret values into the plan.
- Every absolute URL anywhere in a scenario, including `**Expected:**` and edge cases, must match an `[env.targets]` origin exactly (scheme, lower-cased host, explicit or default port). `plan check` reports any other origin as `off_target`, and `/qa:run` stops. Request and page URLs may instead be relative paths, using `defaults.FE` / `defaults.BE` (`ui` / `backend`, or the only target of any name), unless the scenario has `- **Target:** <name>`. With multiple targets a missing section name is a gap; never use the other section's origin. A precondition on another configured origin writes an absolute URL on that origin; there is no per-step target syntax. Userinfo is always refused, and redirects are never followed automatically.
- A scenario using any user field token, `$QA_TAG` or `$QA_NEW_PASSWORD` must resolve every touched origin — explicit Target or section origin plus every absolute URL — to loopback or HTTPS. Otherwise `plan check` reports `credentials over cleartext origin <origin>`. Testers refuse every credential-bearing request or form submission on non-loopback HTTP with `SKIP — cleartext origin refused: <origin>`.
- When config is absent or lacks a needed user, value, target or store, retain the repository-grounded name. Write a missing target as `- **Target:** <name>` with relative paths, never an absolute URL on an unknown origin. `plan check` reports the missing names so `/qa:run` can fill the config gaps; do not replace them with literal credentials or omit the scenario. `missing.cleanup` is a soft gap when registered users exist without a cleanup recipe; it does not make `plan check.ok` false.
- Data a scenario needs (a CV, an order, an uploaded file record) is created by that scenario's own preconditions as its user, never assumed to exist. FE preconditions create data through browser (UI) actions only; API/HTTP preconditions belong to BE scenarios. Set up another user's resource through that user for ownership checks. A repository file may be an upload fixture. `NEED_INFO kind=fixture` is reserved for data the app cannot create itself. Precondition writes, including registration, count toward the mutation policy even when the main request expects rejection.
- Every FE and BE scenario has `- **Writes:** yes|no`, covering preconditions, main flow and edges. Under `qa.mutations = "deny"`, `yes`, a missing/invalid line or any syntactically detected write guards the whole scenario. `no` never overrides detected writes; `allow` guards nothing.
- `- **State Check:** [<store>: ]<query> → <expected>` is repeatable and BE-only. Store prefixes may be backticked and must match a configured `[env.stores.<name>]`; an unknown prefix is `missing.stores`. Without a prefix, exactly one configured store is required, otherwise it is a plan error `state check must name its store`. Always name the store when several exist. The engine resolves checks in line order and exposes namespaced `STORE_<NAME_UPPER>_<CLIENT>` variables through the private channel; `qa_load_store='<name>' qa_load_require='<required native names>' . '<run-dir>/load.sh' || exit 1` exports client aliases. These are store-client inputs, not plan tokens. Never put passwords or DSNs in process argv.
- Write SQL State Checks against only the columns asserted; never put `SELECT *` in a plan. Row checks project just the needed columns to JSON and pass through the installed `qa-redact.pl` before inspection or reporting. Redis State Checks use only the be-testing skill's read-command allowlist.

## Harness scope

Scenario steps, including data preconditions, must stay within their section's harness against the already-running app: FE flows and preconditions use browser (UI) actions only; BE flows use HTTP requests / DB queries, with API/HTTP requests for data preconditions. Do not include `docker`, `make`, `npm`, migrations, file edits or infrastructure inspection as scenario steps. Bring-up belongs to the config's `env.services`, which `/qa:run` handles before dispatch; a reversible blocker's human prerequisite belongs in optional `## Setup` notes. List unobservable checks under optional `## Out of harness scope` as bullets with a one-clause harness reason (never scenario headings). A code defect that prevents a contract-correct result is a Blocker, not an out-of-scope check. If a tester nevertheless encounters an out-of-scope step, the scenario is `SKIP` with reason `out of harness scope: <step>`.

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
- [ ] State Checks are repeatable, BE-only, use real table/column names or supported Redis read commands, and name a configured store (mandatory with several stores)
- [ ] API paths match actual routes from the codebase
- [ ] No placeholder text (TBD, TODO, fill in later)
- [ ] `## Source` records the current checkout `Branch:` and `Head:`
- [ ] `## Setup`, if present, holds only optional human notes; targets, values, stores and bring-up are config-owned
- [ ] Credentials and exposed values use supported `$QA_NAME` / `${QA_NAME}` tokens; tokens/cookies are retained by the tester from preconditions, never `$QA_<U>_TOKEN` / cookie plan tokens or literal secrets
- [ ] Every absolute URL anywhere in a scenario, including Expected and edge cases, is on a config target origin; off-target response URLs are asserted by separate components, not literal URLs. Request/page paths have `- **Target:** <name>` where the section default does not apply
- [ ] Missing config names remain explicit; a missing target is named with relative paths, not an absolute URL on an unknown origin
- [ ] Each scenario creates its required data as its user through browser (UI) actions for FE or API/HTTP requests for BE; only data the app cannot create requires an external fixture
- [ ] `## Users` declares each referenced user as existing or registered, covering owner, other user, anonymous actions and each role; at most 10 users are registered
- [ ] Every FE and BE scenario has `- **Writes:** yes|no` consistent with all executable actions, including registration and edges
- [ ] Every credential-bearing scenario touches only loopback or HTTPS origins
- [ ] Every `**Expected:**` and edge-case expectation has a grounded `(path:line)` or `(unverified — confirm at run time)` tag
- [ ] BE expectations and edge cases assert only visible data after `qa-redact`: scheme/host/port/path may be observable for URL-only keys, but masked userinfo/query/fragment, one-time links and any masked path component are not
- [ ] `## Blockers / Findings` is present (or reads `None found.`)
- [ ] No scenario step is outside the browser / HTTP / DB harness scope
- [ ] For ≥2 independent boolean inputs, a `state-combination-planning` 2^N table appears above affected scenarios with a disposition for every row

# QA configuration

Use `[qa]` to choose source fixes, application writes and service startup, then configure users and cleanup. See [shared configuration](../../configuration.md) for `.av/` files and `[env]` settings.

## Policy

All 3 policy keys are strings. Omitted keys use the defaults below; explicitly configured values are trust-pinned.

| Key | Default | Allowed values and behavior |
|---|---|---|
| `fix` | `"approve"` | `"approve"`: ask before each fix batch. `"auto"`: apply eligible fixes after showing scope. `"off"`: test and report only. |
| `mutations` | `"deny"` | `"deny"`: skip declared or detected writes. `"allow"`: guard nothing; use only when every target's data is disposable. |
| `start_services` | `"ask"` | `"ask"`: ask before needed `up`/`prepare`. `"auto"`: show scope, then run configured commands when needed. |

Every frontend and backend scenario needs `- **Writes:** yes|no`. Under `deny`, `yes`, missing or invalid declarations guard the whole scenario. Detected writes also guard the scenario, including preconditions, edges and State Checks; `no` cannot override detection.

Registration and session-writing login count as writes. Guarded scenarios are `SKIP`, never fix candidates. Static detection has [residual risks](../qa.md#residual-risks); `deny` is not a read-only guarantee.

These policies are independent. `fix = "off"` does not prevent application writes or service startup. For restrictive testing, combine `off` and `deny`, and omit service startup/preparation commands.

### Working tree and limits

<details>
<summary>Working-tree approvals and fixed limits</summary>

| `fix` | Pre-existing tracked changes |
|---|---|
| `"approve"` | Warn and ask Proceed/Abort. |
| `"auto"` | Proceed with the recorded baseline. |
| `"off"` | Skip the dirty-tree gate. |

QA records pre-existing tracked changes before bootstrap writes. QA's config and ignore edits therefore do not become pre-existing changes.

See [run recovery](../qa.md#qarun-plan-path--change-source) for overlap with pre-existing changes.

A dispatch is 1 assignment to a tester or fixer.

| Fixed limit | Value |
|---|---|
| Fix iterations | `3` |
| Tester/fixer dispatches | `50` |
| Elapsed time | `30 minutes` |

The final full test pass counts toward usage but is not blocked by exhausted fix limits. There is no per-fix `step` mode or token/cost ceiling.

See [interactive versus headless](../qa.md#interactive-versus-headless) for approval behavior. Service preparation and migrations follow the [shared service rules](../../configuration.md#services).

</details>

See [QA safety](../qa.md#safety) for fix eligibility and authentication guards.

## Users

`[qa.users.<name>]` configures existing accounts. QA never creates or deletes these accounts.

Names start with a lowercase ASCII letter, followed by lowercase letters, digits or `_`. The names `new`, `captured` and names starting `captured_` are reserved.

| Key | Type | Requirement |
|---|---|---|
| `email` | Source string | Required email source. |
| `password` | Secret source string | Required password source. |
| `id` | Source string | Optional; needed when the plan references the user's ID. |
| `description` | Non-empty string | Required description of the role or account state. |

Use the [source rules](../../configuration.md#secrets-and-values); never put a password in the plan or committed config.

<details>
<summary>Plan users and tester inputs</summary>

Declare every user under the plan's `## Users` heading:

```markdown
## Users
- owner: registered — plain user who owns a CV
- admin: existing — administrator (qa.users.admin)
```

| Declaration | Use when |
|---|---|
| `registered` | Signup can create the required user. No existing-account configuration is needed. |
| `existing` | Signup cannot create the required role or state. Configure `qa.users.<name>`. |

A configured user must be declared `existing`, not `registered`. Undeclared user references are plan errors. Plans may declare at most `10` registered users.

Plans use `$QA_NAME` or `${QA_NAME}` throughout scenarios, including preconditions and edges.

| Input | Tester-visible reference |
|---|---|
| Existing user `u` | Referenced fields among `QA_<U>_EMAIL`, `QA_<U>_PASSWORD`, `QA_<U>_ID`; ID requires a configured source. Login needs email and password references. |
| Referenced `[env.values]` entry `X` | `QA_<X>` with the name uppercased. |
| Registration password | `QA_NEW_PASSWORD`, generated once per run. |
| Dispatch tag | Plans write `$QA_TAG`, for example `qa+$QA_TAG-owner@test.local`. Testers substitute the `Tag:` value from their dispatch input; it is not a private-channel variable. |
| `[env.secrets]` | Never exposed to testers. |

For registered users, email and ID references hold values from the tester's own registration step. Using them before registration produces `NEED_INFO kind=fixture`, naming the user. Tokens and cookies come from runtime login; never declare token/cookie references in plans.

Value names must not collide with exposed user fields or use `TAG`, `NEW_PASSWORD`, `CAPTURED_*` or token/cookie suffixes. Avoid value names that resemble undeclared user fields, such as `OWNER_EMAIL`.

</details>

## Registered accounts

Testers register through the application's signup API or form, then log in themselves. Addresses such as `qa+<Tag>-owner@test.local` include the dispatch tag. Use an application-supported domain and the generated run password.

Testers record every successful registration immediately in the durable [account ledger](#missing-cleanup-and-outcomes). Teardown attempts cleanup; existing accounts are never enrolled for deletion.

| Signup limitation | What to supply |
|---|---|
| Email confirmation | A local mail catcher when needed. |
| CAPTCHA, rate limits or unavailable role/state | An existing account when signup cannot produce the required user. |

## Cleanup

Optional `[qa.cleanup]` contains exactly 1 SQL, HTTP or command recipe. Cleanup deletes tester-registered accounts, never configured existing users. Prefer repository-evidenced deletion by email; verify cascades and related-data deletion before approval.

SQL and HTTP recipes must contain `{email}`. Deletion by ID alone is not allowed. Recorded email addresses must contain the dispatch tag in their local part and differ from the existing-user emails provided to the run.

### SQL recipe

| Key | Type / requirement | Meaning |
|---|---|---|
| `kind` | Required string | `"sql"` |
| `store` | Required string | Configured store with `kind = "sql"`. |
| `query` | Required non-empty string | SQL containing `{email}`. |

<details>
<summary>SQL substitutions and execution</summary>

Only `{email}`, `{id}` and `{tag}` placeholders are allowed. QA quotes SQL literals and doubles embedded apostrophes; absent IDs become `NULL`. Do not quote placeholders yourself.

Cleanup runs without State Check read-only settings; exit `0` means success. Postgres and MySQL cleanup ignore client startup/option files. Approve the query only after checking the application's deletion contract and foreign-key cascades.

</details>

### HTTP recipe

<details>
<summary>HTTP recipe keys</summary>

| Key | Type / default | Meaning |
|---|---|---|
| `kind` | Required string | `"http"` |
| `target` | Required string | Configured target under the [HTTPS rules](../../configuration.md#targets). |
| `method` | Required string | `GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE` or `OPTIONS`. |
| `path` | Required string | Starts `/`, not `//`; query allowed, backslashes and fragments forbidden. |
| `headers` | String table / `{}` | Request headers. |
| `json` | Table / omitted | Nested JSON-compatible tables, arrays, strings, numbers and booleans. |
| `form` | String table / omitted | URL-encoded form; mutually exclusive with `json`. |
| `expect` | Required non-empty integer array | Successful HTTP statuses, `100` to `599`. |

</details>

<details>
<summary>HTTP placeholders and encoding</summary>

Templates allow `{email}`, `{id}`, `{tag}`, `{secret.X}` and `{value.X}`. Secret/value names must exist in their `[env]` tables; use placeholders, not source strings, inside recipes.

Identity substitutions in paths and queries are percent-encoded. Header and body substitutions retain raw values. Cleanup never follows redirects.

If `{id}` is required but unavailable, cleanup counts a failed attempt without sending a request.

</details>

### Command recipe

| Key | Type / requirement | Meaning |
|---|---|---|
| `kind` | Required string | `"command"` |
| `run` | Required non-empty string | Shell command in the repository root; timeout `60 seconds`. |

Commands use no placeholders and must not print credentials. Exit `0` means success. Commands are trust-pinned, not sandboxed.

<details>
<summary>Command account inputs and secrets</summary>

QA removes inherited `QA_*` variables and supplies these account values:

| Variable | Value |
|---|---|
| `QA_EMAIL` | Registered email. |
| `QA_ID` | Recorded ID, or empty when unknown. |
| `QA_TAG` | Registration's dispatch tag. |

Other inherited environment variables remain available. For an administrative key, use `AV_<NAME>` and declare the same variable as `env:AV_<NAME>` under `[env.secrets]`. For example, `SERVICE_KEY = "env:AV_SUPABASE_SERVICE_ROLE_KEY"` enables masking while the helper reads the inherited variable.

That declaration does not inject the key into the helper. Helpers reading secrets another way must never print them, including on failure. Unknown or short values may escape engine-log masking; never paste raw logs into chat.

</details>

### Missing cleanup and outcomes

Missing cleanup alone does not stop a valid run. Interactive QA offers a cleanup-only extension. Accounts remain with this warning when no proposal is available, preview still fails after 1 correction, approval is declined, or the run is headless:

```text
No cleanup recipe: registered accounts will remain in the application.
```

Required configuration gaps and invalid configuration still stop.

The ledger at `${XDG_STATE_HOME:-~/.local/state}/av-marketplace/qa-accounts.json` survives runs, repair restarts and private-directory deletion. It uses the repository's real path. It stores account identities and cleanup progress, never passwords or tokens.

| Outcome | Meaning / action |
|---|---|
| `deleted` | Cleanup succeeded and QA recorded the outcome. |
| `left` | No usable recipe, invalid/untrusted config, unmatched/unlocked destination, unsafe legacy record or failed attempt below the limit. Review the cause; a later compatible trusted run can retry eligible records. |
| `manual` | The account reached `3` failed attempts during this teardown. Delete it deliberately in the correct application. |

The report's Accounts line counts registered, deleted, left and manual accounts. Review account emails in reports and summaries. A retained ledger record does not mean cleanup succeeded.

For a destination mismatch or the legacy-record warning, clean up in the original application. Do not edit ledger fields to authorize a different destination.

<details>
<summary>Cleanup destinations and legacy records</summary>

Cleanup uses the current valid, trusted recipe. A SQL endpoint or HTTP origin must match the account's recorded destination and be locked by this run.

Command recipes have no destination and process only accounts recorded without one. Skips for a missing, invalid or untrusted recipe, an unlocked destination or a destination mismatch do not count as failed attempts.

An account recorded with no destination adopts the current recipe's destination on its first attempt. This happens when no recipe, or a command recipe, was configured at registration.

Records written by pre-release builds lack `tag` or `destination`. They and malformed records stay unchanged, without an attempt; their emails appear under `left`. Delete those accounts in the application named by the record's `origin`. Other eligible records still clean up.

Each teardown attempts eligible accounts from earlier runs too. QA saves each outcome before attempting the next account. After `3` failures, automatic retries stop; `manual` is listed once, not on every later run.

</details>

## State Checks

A State Check verifies application state in a configured store. Only backend scenarios support State Checks; frontend State Checks are plan errors.

Use repeatable lines such as `- **State Check:** main: <query> → <expected>`. A store name is optional only when exactly 1 store is configured; with zero or several stores, an unprefixed check is a plan error. An unknown store name is a configuration gap.

Checks use read-only SQL settings or the Redis read-command allowlist; missing clients skip only the check, not runnable HTTP assertions. See [Stores](../../configuration.md#stores) for endpoint keys and role/ACL isolation, and [Prerequisites](../qa.md#prerequisites) for clients.

## Examples

These are complete schema examples. Verify routes, ports, commands, models and deletion contracts against repository evidence before approval. Add the [private ignore entries](../../configuration.md#files).

### JWT API: `/register` and `/login`

This assumes registration returns `201 {"id": ...}` and login returns `200 {"token": ...}`. Declare `owner: registered` and `Writes: yes`; testers register, record the account, then capture the login token.

```toml
version = 1

[env.targets]
backend = "http://localhost:8000"

[qa]
fix = "approve"
mutations = "allow"
start_services = "ask"

[qa.cleanup]
kind = "command"
run = "sh scripts/delete-qa-user.sh"
```

The evidenced helper must delete by `QA_EMAIL` and return exit `0`; otherwise choose an evidenced SQL recipe.

### Django session stack: signup, login and cleanup

This assumes signup forms, Django's standard user model and the target server's settings/database. Testers handle CSRF and session cookies themselves.

```toml
version = 1

[env.targets]
ui = "http://localhost:8000"
backend = "http://localhost:8000"

[qa]
fix = "approve"
mutations = "allow"
start_services = "ask"

[qa.cleanup]
kind = "command"
run = '''python3 manage.py shell --verbosity 0 -c '
import os
from django.contrib.auth import get_user_model

get_user_model().objects.filter(email=os.environ["QA_EMAIL"]).delete()
' '''
```

Use disposable data; custom user models or tenant settings need a repository-specific cleanup command.

### Existing accounts from `.av/secrets.local.env`

Use existing accounts when signup cannot create the required role or state.

```toml
version = 1

[env.targets]
backend = "http://localhost:8000"

[qa]
fix = "approve"
mutations = "deny"
start_services = "ask"

[qa.users.admin]
email = "file:.av/secrets.local.env#QA_ADMIN_EMAIL"
password = "file:.av/secrets.local.env#QA_ADMIN_PASSWORD"
id = "file:.av/secrets.local.env#QA_ADMIN_ID"
description = "Administrator; can inspect every CV"
```

Declare `admin: existing — administrator` under `## Users` and fill the 3 keys privately. Omit the ID source when the plan does not reference it.

### Read-only test/report

Use this for anonymous reads on an already-running app, without stores, users or service lifecycle commands.

```toml
version = 1

[env.targets]
backend = "http://localhost:8000"
ui = "http://localhost:5173"

[qa]
fix = "off"
mutations = "deny"
start_services = "ask"
```

Mark read scenarios `Writes: no`. Static detection still cannot guarantee read-only behavior.

### Supabase local stack

This example uses signup on `:54321` and Postgres on `:54322`, and needs the Supabase CLI and `jq`. Testers use `/auth/v1/signup` on `supabase`, the plan-referenced anon key and registered users `user` and `other`.

```toml
version = 1

[env.targets]
ui = "http://localhost:5173"
backend = "http://localhost:8000"
supabase = "http://127.0.0.1:54321"

[env.services]
health = ["backend:/health", "ui:/"]

[env.values]
SUPABASE_ANON_KEY = "cmd:supabase status --output json | jq -r .ANON_KEY"

[env.stores.supabase]
kind = "sql"
engine = "postgres"
host = "127.0.0.1"
port = 54322
user = "postgres"
name = "postgres"
password = "literal:postgres"

[qa]
fix = "approve"
mutations = "allow"
start_services = "ask"

[qa.cleanup]
kind = "sql"
store = "supabase"
# Application contract: public.cvs.user_id references auth.users(id) ON DELETE CASCADE.
query = "DELETE FROM auth.users WHERE email = {email}"
```

Verify the cascade migration and any storage deletion separately; repeated State Checks can check ownership using registered IDs.

This example checks an already-running stack. Add only repository-evidenced lifecycle commands for managed startup.

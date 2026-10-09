# Configuration

Use `.av/config.toml` for shared environment settings and each plugin's settings. QA's first interactive run proposes the file from repository evidence. This page covers `[env]`; [QA configuration](plugins/qa/configuration.md) owns `[qa]` policy, users and cleanup.

## Minimal file

Use the [QA quick-start file](plugins/qa.md#configuration). `version = 1` selects the shared schema.

| Add | When needed |
|---|---|
| [Services](#services) | Check or manage the running stack. |
| [Secrets and values](#secrets-and-values) | Supply private inputs to recipes or scenarios. |
| [Stores](#stores) | Check application state in SQL or Redis. |
| [QA users](plugins/qa/configuration.md#users) | Test with existing accounts. |
| [QA cleanup](plugins/qa/configuration.md#cleanup) | Delete accounts registered by testers. |

## Files

All paths are relative to the project's repository root, not the installed plugin.

| File | Commit it? | Purpose |
|---|---|---|
| `.av/config.toml` | Yes | Team-wide environment and plugin settings. |
| `.av/local.toml` | No | Personal overrides using the same schema. Must be untracked and git-ignored. |
| `.av/secrets.local.env` | No | Private dotenv values referenced through `file:` sources. Never loaded automatically. |

<details>
<summary>Override resolution</summary>

Local settings replace shared keys; local arrays replace whole arrays. The shared file must exist and contain the consuming plugin's table. See [source restrictions](#secrets-and-values) for permissions by supplying file.

</details>

Add these entries to the project's `.gitignore`:

```gitignore
.av/local.toml
.av/secrets.local.env
```

## Targets

`[env.targets]` names application origins. An origin is a URL's scheme, host and effective port.

<details>
<summary>Scenario target selection</summary>

| Target | QA role |
|---|---|
| `ui` | Browser origin for frontend relative URLs. |
| `backend` | HTTP API origin for backend relative paths. |
| A single target of any name | Serves both frontend and backend scenarios. |
| Other names | Additional origins for explicit scenario targets, registration, login, cleanup or probes. |

With multiple targets, frontend scenarios need `ui` and backend scenarios need `backend`, unless a scenario names another target. A missing name is a configuration gap; QA never substitutes the other section's origin. A monolith can use the same origin under both names.

A scenario selects a target with `- **Target:** <name>`.

</details>

<details>
<summary>Origin formats and comparison</summary>

| Rule | Allowed form |
|---|---|
| Names | Start with a letter or `_`; continue with letters, digits or `_`. Use ASCII characters. |
| Origins | `http://host[:port]` or `https://host[:port]`. |
| Excluded URL parts | Userinfo, paths, trailing `/`, queries and fragments. |
| Omitted ports | HTTP uses `80`; HTTPS uses `443` when comparing origins. |

</details>

Loopback means exactly `localhost`, `127.0.0.1`, `::1` or a hostname ending in `.localhost`. Names are lowercased and IPv6 brackets removed before comparison. Other `127.*` addresses, Compose service names and `0.0.0.0` are not loopback.

QA decides loopback from the host name alone, without DNS lookups. Never point a loopback name, such as one ending in `.localhost`, at a remote host.

Health probes and HTTP cleanup require HTTPS outside loopback. Trust approval and personal overrides do not relax this rule. QA also requires HTTPS outside loopback for scenarios using user fields, `$QA_TAG` or `$QA_NEW_PASSWORD`.

Testers refuse credential-bearing requests and forms on non-loopback HTTP. See [QA safety](plugins/qa.md#safety) for exact-origin checks and residual risks.

## Services

`[env.services]` is optional. Commands run through `/bin/sh -c` in the repository root with the engine's inherited environment.

| Key | Type / default | Meaning |
|---|---|---|
| `health` | String array / `[]` | `<target>:<path>` probes; a responding status below `500` counts as up. |
| `up` | Non-empty string / omitted | Command to start services. |
| `prepare` | Array of non-empty strings / `[]` | Preparation commands in order. QA runs these only after its own `up`. |
| `down` | Non-empty string / omitted | Command to stop services. QA runs this only if QA ran `up`. |

<details>
<summary>Service dependencies and preparation</summary>

A probe such as `backend:/health` needs a configured target and a path starting `/`, not `//`.

| Key | Dependency |
|---|---|
| `up` | At least 1 health probe. |
| `prepare` | `up`. |
| `down` | `up`. |

Preparation commands must be idempotent: repeating a command must leave valid data unchanged. QA does not apply branch migrations to an already-running stack; apply those migrations yourself.

</details>

The consuming plugin decides when services start; QA uses [`qa.start_services`](plugins/qa/configuration.md#policy).

## Secrets and values

A source tells the engine where to obtain a value. `[env.secrets]` holds engine-only inputs; QA never exposes these to testers. `[env.values]` holds tester-visible inputs that QA plans reference as `QA_<NAME>`.

Both tables, store passwords and configured user fields accept these source strings:

| Source | Resolution |
|---|---|
| `cmd:<shell>` | Runs `/bin/sh -c` in the repository root with inherited environment. See command output rules below. |
| `env:<NAME>` | Reads the harness's startup environment, not exports made later in another shell. |
| `file:<path>#<KEY>` | Reads 1 named dotenv key. Relative paths start at the repository root. |
| `literal:<text>` | Uses the supplied text, subject to the file's restrictions. |

<details>
<summary>Source restrictions and command output</summary>

Names follow the target-name rules and become uppercase in QA references. QA rejects `[env.values]` names that collide after uppercasing. QA's additional reserved names are listed under [Users](plugins/qa/configuration.md#users).

Command sources have a `30-second` timeout. They read UTF-8 stdout and strip trailing newlines. Non-zero exit, timeout, invalid or empty output stops resolution.

For committed `.av/config.toml`:

- `[env]` environment sources require names starting `AV_`; QA sources also permit `QA_`.
- File sources must be repository-relative, stay inside the repository and be git-ignored.
- Secret and user-password literals are forbidden.
- Store-password literals are allowed only for loopback hosts.

For `.av/local.toml`:

- Environment sources may use any valid environment name.
- File sources may use absolute paths.
- Relative file sources must still stay inside the repository and be git-ignored.
- Secret literals are allowed.

</details>

Validation checks source definitions without reading values or running commands. Resolution happens only after trust and only when needed. Missing or empty values stop that operation.

Displays mask literal payloads, but commands and recipe text remain visible. Never embed credentials in command or recipe text. Prefer private file sources when values must change without restarting the harness.

## Stores

`[env.stores.<name>]` names a SQL or Redis endpoint. Names follow the target-name rules and must be unique ignoring case. Validation does not test connectivity.

Postgres, MySQL and Redis hosts must be exact [loopback](#targets); SQLite uses a local file. The schema has no verified TLS settings for network stores. Trust, personal overrides and inherited client TLS settings cannot authorize remote or LAN endpoints.

| Key | SQL | Redis |
|---|---|---|
| `kind` | Required: `"sql"` | Required: `"redis"` |
| `engine` | Required: `"postgres"`, `"mysql"` or `"sqlite"` | Not supported |
| `host` | Required loopback host for Postgres/MySQL; not supported for SQLite | Required loopback host |
| `port` | Optional integer `1` to `65535`; defaults `5432` / `3306`; not supported for SQLite | Optional integer `1` to `65535`; default `6379` |
| `user`, `name` | Required non-empty username/database strings for Postgres/MySQL; not supported for SQLite | Not supported |
| `password` | Required source for Postgres/MySQL; not supported for SQLite | Optional source |
| `path` | Required SQLite path; relative to repository root or absolute; not supported for Postgres/MySQL | Not supported |
| `db` | Not supported | Optional non-negative integer; default `0` |

Host, username, database and path are metadata, not source strings. Use published host ports, not container-internal ports.

Use a read-only SQL role or restricted Redis ACL for [QA State Checks](plugins/qa/configuration.md#state-checks). Client flags are not permission isolation. Cleanup may require a writable role or another recipe kind.

## Trust

A trust pin records approval of settings that execute commands or expose private inputs. Each worktree needs separate approval.

<details>
<summary>Trust storage and pinned settings</summary>

Pins live at `${XDG_STATE_HOME:-~/.local/state}/av-marketplace/trust.json`, outside the repository. Pins use the repository's real path and plugin name.

QA pins these settings:

- Every value source, including configured user fields and store passwords.
- Shared service settings.
- Non-loopback target origins.
- The whole cleanup recipe and its SQL store table.
- Explicitly configured `fix`, `mutations` and `start_services` values.

</details>

| Reported `trust` | Meaning |
|---|---|
| `not-required` | No sensitive settings need approval. |
| `new` | Sensitive settings have no recorded approval. |
| `trusted` | Current sensitive settings match the approved hash. |
| `changed` | Sensitive settings differ from the recorded approval. |

Review the complete masked settings subset for `new` or `changed`, not only the latest diff.

<details>
<summary>Trust hash and scope</summary>

Approval hashes the full unmasked settings. Acceptance succeeds only while the current hash matches the reviewed hash.

Pins cover source definitions, not changing command outputs, dotenv contents or environment values. Trust never bypasses mutation or other approval gates. Changing only another plugin's table does not change QA's pin.

</details>

### Headless runners and CI

Prepare shared configuration and private inputs before running QA. Approve trust in a controlled CI setup step:

1. Run `config`; confirm `state` is `ok` and `errors` is empty.
2. Review the complete `trust_subset` before accepting its `trust_hash`.
3. Prepare new approval for a changed sensitive subset or a new worktree.

`config` exits `0` even when the file or `[qa]` table is missing. Check `state`. Never auto-accept arbitrary branch content during the work step.

Use the installed QA engine path from the [engine skill](../plugins/qa/skills/engine/SKILL.md#resolve-the-installed-script):

```bash
python3 "$QA_ENGINE" config --repo "$PROJECT_ROOT"
# After review, set APPROVED_TRUST_HASH to that configuration's trust_hash.
python3 "$QA_ENGINE" trust accept "$APPROVED_TRUST_HASH" --repo "$PROJECT_ROOT"
```

These 3 shell variables are example inputs, not configuration sources. The engine rechecks the hash before accepting it. See [interactive versus headless](plugins/qa.md#interactive-versus-headless) for QA's other gates.

## Tables by plugin

| Table | Owner and key reference |
|---|---|
| `[env]` | Shared environment; [this page](#configuration). |
| `[qa]` | [QA configuration](plugins/qa/configuration.md). |

Register each new plugin's table here with its key reference. Keep plugin-specific policy and recipes out of `[env]`.

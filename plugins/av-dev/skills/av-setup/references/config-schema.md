# Schema of `.ai/av.config.json`

One config file per repository. All `av-*` skills read it. The file is committed, because these are team settings, not one person's preferences.

The file always sits in `.ai/av.config.json`, even when the human docs live in `docs/`. This way every skill finds it without searching.

## Local override `.ai/av.config.json.local`

Settings of one person or one machine go to `.ai/av.config.json.local`. The file is in `.gitignore`. Typical reasons: no Codex CLI (a Codex slot switched to Claude), a different device in `needs` and `precheck`, a longer `timeoutSec` on a slow machine, a personal integration.

Skills and scripts read the effective config from the `av-verify/scripts/config.sh` script:

```bash
bash <skills>/av-verify/scripts/config.sh --root .            # effective JSON
bash <skills>/av-verify/scripts/config.sh --root . --sources  # where each key comes from
```

Merging:

| In the `.local` file | Effect |
|---|---|
| object | merges recursively with the team object |
| array | replaces the whole team array |
| string, number, bool | replaces the value |
| `null` | removes the key from the effective config |

Example: a person without Codex CLI.

```json
{
  "agents": {
    "crossVendor": false,
    "models": {
      "plan":   {"provider": "claude", "model": "opus", "effort": "high"},
      "review": {"provider": "claude", "model": "opus", "effort": "xhigh"}
    }
  }
}
```

Rules:
- Validation (`gate.sh --list`) checks the effective config. A wrong override gives a config error (code 2), e.g. `haiku` in `review` or `crossVendor` without two providers.
- `gate.sh --list` prints `CONFIG_LOCAL` and the overridden keys (`OVERRIDE`, `REMOVE`). The gate prints `CONFIG_LOCAL` and writes `configLocal` into the evidence of each check; `gate.sh --status` shows it. `agent.sh --resolve` and `--summary` add `config=local`, and slot records have `config_local`. The `av-verify` and `av-implement` reports list the overridden keys, because the result depends on the machine.
- `--no-local` in `config.sh`, `gate.sh` and `check_setup.sh` skips the override.
- `av-setup` never creates or edits the `.local` file. It adds it to `.gitignore`. In REFRESH, it compares the scan with the team config (`--no-local`).
- Commands from `.local` run without asking, like team commands. The machine owner writes the file, not the repo.
- `check_setup.sh` reports `SETUP_LOCAL_TRACKED` (ERROR) when the file is in git, and `SETUP_LOCAL_IGNORE` (WARNING) when `.gitignore` does not ignore it.
- No secrets, also not in `.local`. Secrets live outside the repo.

## Full example

```json
{
  "version": 1,
  "requires": { "av-dev": ">=0.1.0" },
  "project": {
    "name": "example-shop",
    "summary": "Web shop: API service and web client (example, do not copy the values).",
    "language": "en",
    "stacks": ["<label from the scan>"],
    "skillPrefix": "shop"
  },
  "docs": {
    "entry": "CLAUDE.md",
    "root": ".ai",
    "index": ".ai/README.md",
    "modules": ".ai/modules",
    "domain": ".ai/domain",
    "reviewRules": ".ai/code-review.md",
    "contracts": ".ai/contracts.md"
  },
  "paths": {
    "overlays": ".ai/overlays",
    "workspace": ".ai/workspace",
    "plans": ".ai/workspace/plans",
    "reports": ".ai/workspace/reports",
    "runs": ".ai/workspace/runs",
    "learnings": ".ai/sessions/learnings.md",
    "scripts": ".ai/scripts"
  },
  "git": {
    "baseBranch": "develop",
    "branchPattern": "{type}/{TICKET}-{slug}",
    "branchTypes": ["feature", "bugfix", "task", "hotfix"],
    "commitPattern": "{TICKET} {imperative sentence in English}",
    "ticketPrefixes": ["PROJ"],
    "commit": "on-request",
    "push": "never",
    "aiSignature": false
  },
  "validation": {
    "commands": {
      "lint": { "run": "make lint", "timeoutSec": 300, "parallel": true },
      "unit": { "run": ".ai/scripts/unit_test.sh", "expect": "UNIT_OK", "timeoutSec": 900 },
      "build": { "run": "make build", "timeoutSec": 1200 },
      "e2e": {
        "run": ".ai/scripts/e2e.sh \"$E2E_SUITE\"",
        "expect": "E2E_OK",
        "precheck": "test -n \"$E2E_SUITE\" && bash \"$AV_SKILLS_DIR/av-verify/scripts/compose_container.sh\" app >/dev/null",
        "needs": "services of this checkout running, test account, E2E_SUITE parameter",
        "notRunExitCodes": [2],
        "covers": ["build"],
        "timeoutSec": 3600
      },
      "docs": {
        "run": "bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_refs.sh\" CLAUDE.md .ai .claude/skills --root . --strict && bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_linerefs.sh\" CLAUDE.md .ai --root . --strict",
        "timeoutSec": 120,
        "parallel": true
      },
      "contract": {
        "run": ".ai/scripts/contract_check.sh",
        "precheck": "test -d ../example-api-spec",
        "optional": true
      }
    },
    "gates": {
      "quick": ["lint", "docs", "unit"],
      "full": ["lint", "docs", "unit", "build"],
      "e2e": ["e2e"]
    }
  },
  "roles": [
    { "name": "backend", "skill": "shop-backend", "order": 1, "globs": ["src/api/**", "src/domain/**", "migrations/**"] },
    { "name": "web", "skill": "shop-web", "order": 1, "globs": ["web/src/**", "web/public/**"] },
    { "name": "tests", "skill": "shop-tests", "order": 2, "globs": ["tests/**", "e2e/**"] }
  ],
  "generatedPaths": ["package-lock.json", "web/dist/**"],
  "unownedPaths": [".ai/scripts/**"],
  "risk": {
    "highRiskAreas": ["authentication", "sessions", "payments", "personal data", "database migrations"],
    "highRiskPaths": ["src/api/auth/**", "src/domain/payments/**", "migrations/**"]
  },
  "agents": {
    "independentReview": true,
    "models": { "plan": "inherit", "implement": "inherit", "review": "opus", "verify": "haiku" }
  },
  "integrations": {
    "tracker": { "access": "mcp", "urls": ["https://tracker.example.com/browse/PROJ"], "doc": ".ai/tracker.md" },
    "board": { "access": "browser", "urls": ["https://board.example.com/b/123"], "doc": ".ai/board.md" },
    "mcp": ["example-tracker"]
  },
  "codex": { "enabled": true }
}
```

## Fields

**requires** (optional)
- `{"av-dev": ">=X.Y.Z"}`: the minimum version of the av-* skills. The `VERSION` file in a skill's directory gives its version. No file means version `dev`.
- `gate.sh --list` compares versions. Version `dev` gives a `WARNING`. A version that is too low is a config error (code 2).
- `av-setup` writes the version of the installed skills here, when it knows it (the `VERSION` file next to the skills). With `dev`, it skips the field.

**project**
- `language`: the language of generated docs, plans and reports. Code and commands are always in English.
- `stacks`: the `id` values of `stacks[]` in the scan result, for information only (e.g. `["composer", "npm"]`). No template is attached to them. Each scan entry is `{id, dir, evidence}`: `id` is the ecosystem of the manifest or build file (`npm`, `composer`, `xcode`, `gradle`, ...), `dir` its directory, `evidence` the files found. `stacks` reports no frameworks or features. Declared framework facts, with evidence, appear only under `adapters.*` in the scan (`php_symfony`, `ios_xcode`, `android`, `angular`, see SKILL.md step 1); they are not stacks and add no template. Do not copy adapter keys into `stacks`.
- `skillPrefix`: the prefix of role skill names, e.g. `shop` gives `shop-backend`. By default from the project name (the project manifest, the `origin` URL), not from the directory name: the last segment without the company prefix (`references/role-skills.md`, section "Name").

**docs**
- `entry`: the agent instruction file. Usually `CLAUDE.md`, and `AGENTS.md` is a symlink to it.
- `root`: the docs directory for humans and agents. `.ai` for new repos. `docs` where the team already uses it.
- `reviewRules`: the repo review rules. `av-review` reads them.
- `contracts`: protected contract surfaces (API, DB schema, deep links, events). `av-review` and `av-plan` read it.

**paths**
- `overlays`: overlays per skill. Always under `.ai/`.
- `workspace`: a gitignored directory for working files. `plans`, `reports` and `runs` sit under it.
- `learnings`: session learnings, gitignored.
- `scripts`: repo tools created for work with the agent (gates, lint, fixtures, indexes, mocks). Default `.ai/scripts`, committed. The `scripts/` directory in the root stays for the team's pre-AI tools. Language: bash with `jq`, `git`, `awk`, `curl`. Another language only with a reason written in the script header, e.g. an HTTP server (Python) or a library that exists only in another language. Script tests go in `<scripts>/tests/`.

**git**
- `baseBranch`: the branch the diff is computed against. `"auto"` means `origin/HEAD`.
- `branchPattern`: the branch name pattern. `{type}` is one of `branchTypes`, `{TICKET}` is a ticket with a prefix from `ticketPrefixes`, `{slug}` is a short kebab-case description.
- `commit`: `"on-request"` (default), `"after-green-gate"` or `"free"` (freely on the task branch, never on protected branches). Skills do not commit beyond what this value allows. When sources in the repo conflict, choose `"on-request"` and report the conflict.
- `push`: `"never"` (default) or `"on-request"`. `gate.sh --list` rejects other `commit` and `push` values.
- `aiSignature`: `false` means no `Co-Authored-By` and no AI signatures in commits.

**validation**
- `commands`: named commands. Each has `run`. Optional fields:
  - `expect`: a string that must appear in the output, e.g. `BUILD SUCCEEDED`. It protects against a false green. Sources: the real command output (CI log, a run), the code of the repo script that prints this string, or a fixed message of the tool, confirmed in its documentation or a real run. A guessed `expect` gives a false FAIL. When no source confirms it, skip the field; the exit code is enough.
  - `precheck`: a command that checks the environment. When it fails, the result is `NOT_RUN`, not `FAIL`. The precheck must check the environment of **this checkout**: dependencies in this directory, containers from this directory (label `com.docker.compose.project.working_dir`), not any running services with the same name. A command that needs a runtime which may be missing (a browser, a device, a service) gets a precheck that checks that runtime. When no reliable check exists, mark the command `optional` instead of letting it FAIL. A command that deletes or resets data also checks in its precheck that no other checkout shares the resource by a fixed name (`references/interview.md`, round 1).
    Shared helper: `av-verify/scripts/compose_container.sh [--root DIR] <service>` prints the id of the running Docker Compose container of `<service>` that belongs to this checkout: its label `com.docker.compose.project.working_dir` is the repo root or a directory under it, compared by logical and physical path, and that directory belongs to this checkout: a worktree, submodule or nested repo under the root (e.g. `.claude/worktrees/x`) is another checkout and does not count. It reads only `docker ps`, never calls `docker compose` and never starts, stops or execs containers. It exits 2 when no container of this checkout runs, or when the Docker CLI or daemon is missing, so it fits both `precheck` and `notRunExitCodes: [2]`. Example: `"precheck": "bash \"$AV_SKILLS_DIR/av-verify/scripts/compose_container.sh\" app >/dev/null"`, `"run": "docker exec \"$(bash \"$AV_SKILLS_DIR/av-verify/scripts/compose_container.sh\" app)\" composer test"`.
  - `needs`: a description of requirements for a human, e.g. "services of this checkout running".
  - `timeoutSec`: time limit, default 900.
  - `cwd`: directory relative to the repo root.
  - `notRunExitCodes`: exit codes that the repo script returns when the environment is missing (e.g. 2 = the service is not running). They give `NOT_RUN` instead of `FAIL`. Set them per command from the script code. The same code may mean different things in different commands: "0 tests" is a missing account (NOT_RUN) for UI tests, but a configuration error (FAIL) for unit tests.
  - `optional`: `true` means that `NOT_RUN` of this command does not make the gate incomplete. The result is `SKIPPED`.
  - `covers`: a list of commands that this command covers. Example: UI tests build the app, so `ui` covers `build`. Within one gate, a covered command does not run a second time.
  - `parallel`: `true` means that the command shares no state with the other gate commands (it does not write where others read, does not use the same simulator, database or build directory). It starts in the background at the start of the gate, next to the rest. Results, logs and evidence are the same and come in gate order. Typical: `docs`, `lint`, a fixtures check next to tests. Do not set it for builds or for tests on a shared device. A command with `covers`, or one covered by another gate command, runs in sequence despite the flag. A value other than `true`/`false` is a config error.
- Commands that write tracked files (except a generator whose probe run leaves the tree unchanged), send data to an external service without a switch to turn it off, may print secrets or manage containers by a fixed name do not belong in gates (`references/interview.md`, round 1).
- Pass command parameters through environment variables: `"run": "scripts/ui_test.sh \"$UI_SUITE\""`, and the call is `gate.sh --only ui --env UI_SUITE=LoginTests`. Detect a missing parameter in `precheck`.
- `gates`: named sets of commands. `quick` after every code change. `full` before the report in STANDARD and LARGE modes, and with high risk; SMALL mode ends with `quick`. You can add your own, e.g. `e2e`. The `av-verify.md` overlay, section "Gate selection", says when to run special gates.
- A command does not have to belong to a gate. Helper commands with a parameter, e.g. `lint_snapshot` and `lint_delta` with `LINT_BASE`, are called with `gate.sh --only lint_delta --env LINT_BASE=...`.
- **Skills directory in commands.** `gate.sh` exports the `AV_SKILLS_DIR` variable to every command and precheck: the directory where the av-* skills sit. This way the config contains no path from `~/.claude`.
- **The `docs` command** (recommended): it detects certain docs drift from code in a few seconds, also for changes outside `av-implement`. Put it into `quick` when the docs have 0 certain drift items (definition: `SKILL.md` step 3), or when the plan fixes all of them with `audit --fix` before the gate first runs. Docs about other repositories go to the overlay section "Excluded docs paths", which the scripts read; `--exclude <glob>` does the same on the command line:
  ```json
  "docs": {"run": "bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_refs.sh\" CLAUDE.md .ai .claude/skills --root . --strict && bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_linerefs.sh\" CLAUDE.md .ai --root . --strict", "timeoutSec": 120}
  ```
  `--strict` gives code 1 only for certain drift: `MISSING` in `check_refs.sh` and `LINEREF_RANGE`, `LINEREF_NOFILE`, `LINEREF_GONE` in `check_linerefs.sh`. Replace the paths `CLAUDE.md .ai` with the values of `docs.entry` and `docs.root`. Add `.claude/skills` to `check_refs.sh` when the repo has role skills: their paths drift the same way as docs. Without role skills, skip this directory.

Commands from the config are the only commands that `av-verify` runs without asking. The team has accepted them, because they sit in a committed file.

**roles** (optional; the only source of role file scope)
- A list of roles: `name`, `skill`, `order`, `globs`.
  - `name`: the role name, the same in the plan, the overlay and the skill name.
  - `skill`: the role skill in `.claude/skills/<skill>/SKILL.md`. Write a plugin skill with a colon, e.g. `example-plugin:example-guide`; the validator does not look for it.
  - `order`: roles with the same number may work in parallel. A lower number goes first.
  - `globs`: git pathspec `:(glob)` syntax: `*`, `**`, `?`. No `{a,b}` braces: each variant is a separate glob. A path without a star also covers the directory contents.
    A glob starting with `!` excludes matching files from its own list (one role, `generatedPaths` or `unownedPaths`), e.g. `["config/**", "!config/app.yaml"]`. An excluded file falls through to the next rule. A role with exclusions only is invalid.
- Role globs must not overlap. A file without a role belongs to `implementer`, that is, the main session.
- The `av-implement.md` overlay and the role skill do not copy globs. They link to `roles` in one sentence.
- `check_setup.sh --owner <file>...` from the `av-setup` skill determines a file's owner. Order: `generatedPaths`, then `roles` (first by `order`), then `unownedPaths`, finally `implementer`.
- A repo with one role may skip `roles`. Then every file belongs to `implementer`.

**generatedPaths**: globs of files that no role edits by hand: lockfiles, vendored dependencies, build output, a project file changed only by a script.

**unownedPaths**: globs of repo tools outside roles, e.g. `scripts/**`. Change them only when the plan lists them.

**risk**
- `highRiskAreas`: areas described in words. `av-implement` and `av-plan` compare the task with them.
- `highRiskPaths`: globs. A change in them always forces an independent review and the security axis. Do not put here directories changed in almost every task (e.g. translation files or the main router). Describe a risk like "mass translation change" in words in `highRiskAreas`, e.g. "a change of more than 20 translation keys at once".

**agents**
- `independentReview`: `true` means that a fresh subagent without the implementation context does the review.
- `models`: slots `plan`, `planReview`, `implement`, `review`, `verify`. The value is a string or an object.
  - String: a Claude model, `inherit`, `opus`, `sonnet`, `haiku`, `fable` or a full id `claude-<id>`. Short for `{"provider": "claude", "model": "<string>"}`.
  - Object: `{"provider": "claude"|"codex", "model": "...", "effort": "..."}`. All fields optional: `provider` defaults to `claude`, `model` and `effort` default to `inherit`. A `codex` model is a name from Codex CLI, e.g. `<codex-model>`; `inherit` takes the model from `~/.codex/config.toml`.
  - Effort: `claude` accepts `low`, `medium`, `high`, `xhigh`, `max`; `codex` also `minimal` and `ultra`. `agent.sh` checks in `~/.codex/models_cache.json` whether a given Codex model supports the effort (a warning).
  - `planReview` without an entry inherits `review`.
  - A `claude` slot with effort `inherit` runs as a `general-purpose` subagent with the session effort. Set `effort` to run it on a slot definition (`av-slot-<effort>`). A missing slot is `inherit`.
  - `gate.sh --list` rejects other values, and `haiku` in `review` (code 2). Do not give `haiku` to review. A cheap model can falsely confirm correctness. For running commands with an objective exit code, it is enough. In adoption, choose the stronger of two: the model from the old agent's frontmatter or the default from this schema.
  - A Claude slot runs the Agent tool with the `av-slot-<effort>` definition (session permissions). A Codex slot runs `av-implement/scripts/agent.sh` through `codex exec`: write slots and `verify` in the `workspace-write` sandbox with automatic review, read slots `read-only`; a grant beyond that needs a human prompt. Rules: skill `av-implement`, sections "Slots and providers" and "Permissions".
- `crossVendor` (optional, bool): `true` requires `review` to have a different provider than `implement`, and `planReview` (or `review`) a different one than `plan`. Models from different companies make mistakes in different places, so mutual checking catches more. Alternating example:

  ```json
  "agents": {
    "independentReview": true,
    "crossVendor": true,
    "timeoutSec": 3600,
    "models": {
      "plan":       {"provider": "codex",  "model": "<codex-model>", "effort": "high"},
      "planReview": {"provider": "claude", "model": "opus",        "effort": "high"},
      "implement":  {"provider": "claude", "model": "opus",        "effort": "xhigh"},
      "review":     {"provider": "codex",  "model": "<codex-model>", "effort": "xhigh"},
      "verify":     "inherit"
    }
  }
  ```
- `timeoutSec` (optional): the limit of one slot in `agent.sh`, default 3600.

**integrations**: information for the skills about which tools they may use. Use these category keys, so every repo reads the same: `tracker`, `repoHost`, `ci`, `design`, `board`, `translations`, `errorTracking`, `docsHost`, `mcp` (list of MCP servers). A tool that fits no category gets its own key. Values: a tool name, or `{access, urls, doc}` (below). Secrets never go here.
- A tool entry is a string (the tool name) or an object with optional fields: `access` (`mcp`, `browser`, `cli` or `api`), `urls` (addresses the skills may open, without credentials in the address) and `doc` (the topic file in the repo docs). Use the object form when the team needs the access method or the addresses; every run then writes the same keys.
- How the repo uses a tool is described in the repo docs (`references/doc-set.md`, section "Integrations"), not in the config.
- `mcp` lists the MCP servers that the skills use. A server that the team keeps in `.mcp.json` but no longer uses is left out of this list.

**codex.enabled**: `true` means that setup maintains `AGENTS.md` and `.agents/skills` as symlinks.

## Rules

- No secrets, tokens or personal data in the config, also not in `.local`.
- In a refresh, keep manually set values. Change only what the user asks for, or what the scan detected and the user approved.
- Leave unknown fields unchanged. The team may have added them for its own overlays.

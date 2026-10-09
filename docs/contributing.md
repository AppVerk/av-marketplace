# Contributing

We welcome contributions to the AppVerk Claude Code Marketplace.

## How to Contribute

There are many ways to contribute:

- **Bug fixes** — fix issues in existing plugins
- **New plugins** — create plugins that solve new problems
- **New skills** — add framework patterns or workflows to existing developer plugins
- **Documentation** — improve guides, fix typos, add examples
- **Bug reports** — submit clear, reproducible issues
- **Feature requests** — suggest improvements with context on the problem they solve

## Fork & PR Workflow

1. [Fork](https://github.com/AppVerk/av-marketplace/fork) the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes following existing plugin conventions
4. Test your changes with Claude Code on a real project
5. Commit using [Conventional Commits](https://www.conventionalcommits.org/) format (e.g., `feat(plugin-name): add X`, `fix(plugin-name): resolve Y`)
6. Push to your fork and [open a Pull Request](https://github.com/AppVerk/av-marketplace/compare)

## Plugin Architecture

Each plugin is a directory under `plugins/` (or `external_plugins/` for third-party MCP servers) with the following structure:

```
plugins/your-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── commands/                 # User-invocable commands (markdown files)
├── agents/                   # Specialized subagents (optional)
├── skills/                   # Reusable modules (optional)
├── hooks/                   # Tool-use hooks (optional)
│   └── hooks.json           # Hook definitions (e.g., PreToolUse, SessionStart)
└── scripts/                 # Shell scripts used by hooks (optional)
```

Plugins with an OMP edition either have an `omp/overlay/<name>.json`, from which `plugins-omp/<name>/` is generated, or a native OMP edition in `omp/native/<name>/` (Delivery); OMP-only plugins also live in `omp/native/<name>/`. See [CLAUDE.md](../CLAUDE.md#omp-edition).

### Configuration

Configurable plugins share `.av/config.toml` and `.av/local.toml`, own one
top-level table named after the plugin, and reuse the generic loader and
environment bootstrap. See [Making a plugin configurable](#making-a-plugin-configurable)
for table ownership, validation, trust and documentation requirements.

### plugin.json

Defines plugin metadata:

```json
{
  "name": "your-plugin",
  "description": "Brief description of what your plugin does",
  "version": "1.0.0"
}
```

### Commands

Markdown files in `commands/` define user-invocable commands (e.g., `/review`, `/commit`). Each file includes:

- **Frontmatter** — allowed tools, description, model, argument hints
- **Instructions** — the prompt that drives command behavior

Commands appear in `/help` and are triggered by the user directly.

### Agents

Markdown files in `agents/` define specialized subagents that run in the background. They are launched by commands using the Task tool, not invoked directly by users. Each agent has:

- **Frontmatter** — name, description, tools, model, skills
- **Instructions** — the analysis prompt

Example: the code-review plugin has `security-auditor` and `code-quality-auditor` agents that run in parallel during `/review`.

When defining a new reporting agent's or command's closing contract (verdict line, routing), follow the code-review plugin's `verdict-protocol` skill (`plugins/code-review/skills/verdict-protocol/SKILL.md`).

### Skills

Markdown files in `skills/<skill-name>/SKILL.md` define reusable modules. Skills can be:

- **Agent skills** — invoked by agents (e.g., `secret-scanning`, `sast-analysis`)
- **Background skills** — activate automatically based on context (e.g., `coding-standards`)

Each skill has a frontmatter with name and description, followed by detailed instructions.

### Hooks

Plugins can define hooks that intercept tool usage. Hook definitions live in `hooks/hooks.json` and reference shell scripts in the `scripts/` directory.

**hooks.json** structure:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/your-script.sh"
          }
        ]
      }
    ]
  }
}
```

- **PreToolUse** — runs before a tool is invoked; can deny the action with a reason
- **SessionStart** — runs when a session starts, resumes, is cleared, or is compacted (`matcher` values: `startup`, `resume`, `clear`, `compact`; omit it to run on all four); can inject text into the session context via `additionalContext`
- **matcher** — the tool name to intercept (e.g., `Bash`, `Read`, `Write`)
- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin directory at runtime

Example: the `commit` plugin uses a PreToolUse hook on `Bash` to block direct `git commit` commands and redirect users to the `/commit` command.

Example: the `simple-language` plugin uses a SessionStart hook to inject its writing rules into every session, so the skill is active from the first reply without being invoked.

### Scripts

Shell scripts in `scripts/` are invoked by hooks. They receive the tool input as JSON on stdin and can output a JSON response to allow or deny the action. `SessionStart` scripts receive session info instead (`source`, `session_id`) and may output `additionalContext`.

## Fitting into the Workflow

The marketplace plugins compose into one development harness: each stage of [the cycle](workflow.md#the-cycle) produces an artifact that the next stage consumes. A plugin that runs a stage has to work with that chain. Which plugin a capability lives in is a separate question, settled plugin by plugin.

These rules cover plugins that run a stage of the cycle. Plugins that do not, such as Web Auditor, Security Pipeline or Simple Language, are not affected.

### Compatibility requirements

A plugin that runs a stage of the cycle meets all of these:

- **Hand over in the shared formats.** A plugin may keep its own formats inside a run. What it passes to the next stage, or reports to the user as the result of a stage, uses the format the next stage reads:
  - plans delivered task by task: `### Task N: <title>` blocks with a `**Files:**` list, as Delivery reads them ([plan format](plugins/delivery.md#plan-format)), or a documented conversion to them;
  - code review findings: `### [SEVERITY] ID: Title` blocks in a report under `docs/reviews/`, which `/fix`, `/fix-report` and `/fix-all` read;
  - QA findings: the QA report format under `docs/testing/reports/`;
  - commits: through the Commit plugin's guard (`AV_COMMIT_SKILL=1`), with a Conventional Commits message.
- **Route to the installed plugins.** Implementation goes to the developer agent that owns the files when one is installed. Files a plugin writes into a user's repository, such as a section of `CLAUDE.md`, point to the marketplace plugins installed there, not only to the writing plugin's own commands.

Delivery is the worked example. It adds its own orchestration and keeps a task reviewer with its own verdict inside a run. It reads plans in the shared format, sends each task to the developer agent that owns its files, commits through the Commit guard, and ends with `code-review:review`, whose report the fix commands read.

### Packaging

How the work is split between plugins is agreed in review, and the split can follow a first working integration. The defaults:

- **Extend the plugin that owns the stage.** A new capability for a stage that a plugin already covers goes into that plugin, or into a shared plugin that every path through the stage can use. New review rules go into Code Review; a new way to run and record checks goes where Delivery, `/develop` and `/qa:run` can all use it.
- **Ship reusable parts on their own.** A checker, scanner or gate runner that other plugins could use is its own plugin, or part of the plugin that owns its stage. It is not buried in a workflow that only one path runs.

A plugin that covers a stage another plugin already owns says so in its pull request, along with how the two are expected to converge.

## Creating a New Plugin

1. **Create the directory** under `plugins/`:

   ```bash
   mkdir -p plugins/your-plugin/.claude-plugin
   mkdir -p plugins/your-plugin/commands
   ```

2. **Add plugin.json** in `.claude-plugin/`:

   ```json
   {
     "name": "your-plugin",
     "description": "What your plugin does",
     "version": "1.0.0"
   }
   ```

3. **Create commands** as markdown files in `commands/`. Use existing commands as reference — see `plugins/commit/commands/commit.md` for a simple example or `plugins/code-review/commands/review.md` for a complex one with subagents.

4. **(Optional) Add hooks** if your plugin needs to intercept tool usage. Create `hooks/hooks.json` and corresponding scripts in `scripts/`. See the Hooks section above for the format.

5. **Register in marketplace.json** at `.claude-plugin/marketplace.json`:

   ```json
   {
     "name": "your-plugin",
     "source": "./plugins/your-plugin",
     "description": "Brief description",
     "version": "1.0.0",
     "category": "development"
   }
   ```

6. **Test** your plugin thoroughly with Claude Code.

7. **Submit a pull request** with:
   - Clear description of plugin functionality
   - Usage examples
   - Any dependencies or prerequisites

## Configurable plugins

### Making a plugin configurable

1. **Own exactly one top-level table named after the plugin**, such as `[qa]`. Use the root `version` and shared `[env]` schema; read settings only from `.av/config.toml` and `.av/local.toml`, with private values obtained through sources. Do not introduce a plugin-specific config directory or parallel file convention.
2. **Validate only your table plus the shared schema.** Ignore other plugins' top-level tables; preserve the warning-only treatment of unknown `[env]` sub-tables. Report `state`, `provenance`, file/key diagnostics and masked trust metadata through your engine.
3. **Pin capabilities before use.** Combine the shared sensitive subset with your sources, executable recipes and keys that widen gates. Scope acceptance by repository and plugin; never resolve a source or run an untrusted command while inspecting config.
4. **Use the bootstrap protocol below** from the plugin's entry command in `create`, `extend` and `repair` situations. Reuse the generic loader and environment detector, adding only your table's validation, recipes and policy questions.
5. **Register and document the change together.** Add your table to the `## Tables by plugin` registry in `docs/configuration.md` with a link to its key reference, and document every plugin-owned key, type, default, allowed value and trust-pinned gate in that reference (QA keeps its reference in [`docs/plugins/qa/configuration.md`](plugins/qa/configuration.md); its plugin guide links there). Validation errors are reported by the engine's `config` output, not listed in docs. Document any new shared `[env]` keys in `docs/configuration.md`. Update `docs/configuration.md` in the same change that makes the plugin configurable.

### Bootstrap protocol

The bootstrap belongs in a configurable plugin's entry command, not in a separate init command. Its modes are:

| Mode | Trigger | Input |
|---|---|---|
| `create` | The shared file or the plugin's table is missing. | Required names from the work document, if one exists, and plugin creation-time policy choices. |
| `extend` | The requested work needs configuration keys that are absent. | Exactly those missing keys. |
| `repair` | A configured recipe or health probe fails. | The failing keys, probes and safe engine error. |

An invalid config is reported and stopped, not overwritten as a missing config. A headless caller stops with a pointer to `docs/configuration.md`; it does not invent answers or write a proposal without approval.

1. **Read-only proposal.** The author uses Read, Grep and Glob with the shared environment skill and the plugin-specific layer. It never runs candidate commands or reads secret values, and never reads or edits `.av/local.toml`. It uses provenance to stop on blocking local overrides. It preserves existing names, unrelated keys, other plugins' sections and comments byte-for-byte. Every proposed target, command and recipe cites its repository evidence in a TOML comment. Unknown facts become questions, not guessed ports, credentials or commands.
2. **Transaction and questions.** Return `{proposal, questions[]}`. The proposal contains `config_text` (the full proposed `.av/config.toml`), `gitignore_add` (only the exact `.av/local.toml` and `.av/secrets.local.env` strings when needed; all other paths, negations and wildcards are rejected) and `allowed_keys` (the smallest authorized dotted-key scopes). In `create`, add only the shared keys the work needs plus the plugin's table, and collect unresolved prerequisites and creation-time policy choices together. The bootstrap never creates or fills `.av/secrets.local.env`; unresolved values become `file:.av/secrets.local.env#NAME` references.
3. **Preview without writes.** `config preview <proposal>` validates the merged config and proposed ignore rules, checks that only `allowed_keys` change and protected sections/comments remain byte-identical, and returns a `diff` covering both the masked `.av/config.toml` changes and every `.gitignore` addition, the **complete resulting trust subset**, its hash and a snapshot of `.av/config.toml` and `.gitignore`. The ignore diff omits unrelated existing lines. Include sensitive settings already in `[env]`, even if another plugin added them; mask literals. On preview errors, allow one corrected read-only proposal round, then stop if errors remain.
4. **One approval.** Show the diff, ignore additions and complete trust subset together and ask for one confirmation of the write and trust hash. Declining writes nothing. Creation-time policy questions precede this confirmation; they do not replace it.
5. **Compare-and-swap apply.** `config apply <proposal> --snapshot S --approved-hash H` applies only the approved preview. If either file changed since preview, it writes nothing and reports a conflict. Otherwise it replaces the files atomically, revalidates and records trust **only for the approved hash**. Validation/hash failures restore the prior files only while they still contain the engine's own writes; concurrent edits are left intact and reported. Do not bypass preview or accept a different hash during apply.
6. **Missing private inputs.** If the work needs dotenv keys that are not populated, name the keys for the user to fill and stop without printing or asking for their values. Then re-check the work against the resulting config. A plugin repairing an active run must follow its own cleanup/restart contract before using the changed configuration.

### Shared code

The plugin-neutral implementation currently lives in QA:

- [`plugins/qa/skills/engine/scripts/av_config/`](../plugins/qa/skills/engine/scripts/av_config/): `files.py` owns loading/merge, provenance and shared `[env]` validation; `sources.py` owns value sources, restrictions and masking; `origins.py` owns origins/loopback; `trust.py` owns per-plugin pins; `transaction.py` owns section-preserving guarded writes. The package has no QA imports. Consumers import from the owning module; its `__init__.py` does not re-export the old monolithic API.
- [`plugins/qa/skills/env-config/`](../plugins/qa/skills/env-config/SKILL.md): read-only repository detection and proposal rules for `[env]`, with no QA policy or recipe logic.

Consumers pass their declared value-source key pattern to `av_config.sources.mask` and `av_config.transaction.ConfigTransaction`; the shared layer does not infer source positions from string contents. The same pattern applies to nested configuration tables, dotted trust-subset keys and persisted run metadata.

Schema validators register each value source with `Configuration.source(value, key, secret=..., literal_allowed=...)`. It records a `SourceRule` with the key's effective-file provenance and restrictions. Consumers resolve through `Configuration.resolve(source, key, trusted=..., execute=...)`, which revalidates under that recorded rule and rejects any key the validator did not register. Consumers must not derive restrictions from key names a second time.

The optional executor receives `(command, key)` and returns decoded stdout, raising a safe `ConfigError` on execution failure. Without it, `av_config` uses its bounded subprocess executor. The shared resolver strips trailing newlines and rejects empty command output in both cases. QA supplies an executor that runs the command with the engine's inherited environment and logs only exit/line-count summaries on success, never source stdout/stderr; failed source output is discarded. Its runtime keeps only trust checks and caching around the shared resolution entry point.

When a second configurable plugin is introduced, extract this generic layer into a small core plugin the consumers require, or ship byte-identical copies checked in CI. Choose the packaging at that point, and do not create a second loader or `[env]` detector. Each plugin keeps only its call site and its own table's validation, recipes and policy choices.

## Pull Request Requirements

Every pull request should include:

- Clear description of what changed and why
- Evidence of testing with Claude Code on at least one real project
- Adherence to existing plugin patterns and naming conventions
- For a plugin that runs a stage of the workflow: the [compatibility requirements](#compatibility-requirements) from Fitting into the Workflow, and, if it covers a stage another plugin already owns, how the two are expected to converge
- Updated version in `plugin.json` (if modifying an existing plugin) — must match `.claude-plugin/marketplace.json`, the row in `README.md`, and the `**Version:**` header in `docs/plugins/<name>.md`. The `Plugin Version Parity` GitHub Actions workflow enforces this; run `python3 scripts/check_plugin_versions.py` locally before pushing. The same script checks the README row's `ID`, `Claude Code` and `OMP` columns against `.claude-plugin/marketplace.json` and `.omp-plugin/marketplace.json`.
- Regenerated OMP edition (if you changed `plugins/<name>/` of a plugin that has an `omp/overlay/<name>.json` — a version bump included — or anything under `omp/` or `scripts/build_omp_edition.py`): `plugins-omp/` and `.omp-plugin/marketplace.json` are generated, so never edit them by hand — run `python3 scripts/build_omp_edition.py` and commit both. OMP-only plugins in `omp/native/<name>/` are versioned in their own `.omp-plugin/plugin.json` and `package.json` and in their row of the README "Available Plugins" table, not in `.claude-plugin/marketplace.json` or a `**Version:**` doc header; `python3 scripts/check_plugin_versions.py` checks the README row. Delivery has both a Claude Code edition in `plugins/delivery/` and a native OMP edition in `omp/native/delivery/`: they share one README row, so bump all six version sources together. The `Plugin Version Parity` workflow (`python3 scripts/check_plugin_versions.py`) checks that `plugins/delivery/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the README row and the `**Version:**` header in `docs/plugins/delivery.md` agree, and that `omp/native/delivery/.omp-plugin/plugin.json` matches that README row. The `OMP Edition` GitHub Actions workflow (`.github/workflows/omp-edition.yml`) runs `python3 scripts/build_omp_edition.py --check`, which fails when `plugins-omp/` or `.omp-plugin/marketplace.json` is stale, when `omp/native/delivery/package.json` differs in name or version from `omp/native/delivery/.omp-plugin/plugin.json`, or when `scripts/route_task.py` differs between `plugins/delivery/` and `omp/native/delivery/`; the workflow also runs the tests listed there. The full rules are in [CLAUDE.md](../CLAUDE.md#omp-edition).
- Passing delivery tests (if you changed `omp/native/delivery/` or `plugins/delivery/`): run `python3 omp/native/delivery/tests/test_route_task.py` and `python3 plugins/delivery/tests/test_delivery_hook.py`; then install OMP next to the extension with `bun install --no-save --cwd omp/native/delivery @oh-my-pi/pi-coding-agent@latest` (it lands in the gitignored `omp/native/delivery/node_modules/`; linking an existing global install works too: `ln -s ~/.bun/install/global/node_modules omp/native/delivery/node_modules`) and run `bun test tests/delivery.test.ts` from `omp/native/delivery/`. The `OMP Edition` workflow runs all three. Test trailer-parsing rules with synthetic NUL-delimited logs through `scan_delivery_log()`; keep CLI tests for Git integration.
- Passing Delivery/QA contract check (if you changed either orchestration skill or `plugins/qa/commands/run.md`): run `python3 scripts/test_check_delivery_qa_contract.py` and `python3 scripts/check_delivery_qa_contract.py`. Delivery reports `Nothing to test` by matching QA's `Generated plan has no executable FE or BE scenarios` stop message, and the `Delivery QA contract` workflow fails when that message drifts in any of the three files.
- Passing plan review tests (if you changed `omp/native/plan-review/`): install OMP next to the extension with `bun install --no-save --cwd omp/native/plan-review @oh-my-pi/pi-coding-agent@latest` (or link an existing global install as for delivery) and run `bun test tests/plan-review.test.ts` from `omp/native/plan-review/`. The `OMP Edition` workflow runs it.
- Passing Claude hooks tests (if you changed `omp/claude-hooks/` or the hooks or scripts of a plugin with an OMP edition): run `bun test` in `omp/claude-hooks/`; it needs `bun`, `git` and `jq`. The `OMP Edition` workflow runs it. When the shared `omp/claude-hooks/claude-hooks.ts` adapter already exists on the PR base branch and changes, bump every overlaid plugin with `hooks/hooks.json` in all four version sources. The `Plugin Version Parity` workflow checks this; run `python3 scripts/check_plugin_versions.py --check-hooks-version-bump BASE_REF` locally to check the same rule.
- No unrelated changes bundled in the same PR

## Review Process

After you submit a pull request:

- A maintainer will review it within approximately one week
- You may receive feedback requesting changes — this is normal and constructive
- PRs may go through multiple rounds of revision before merge
- Maintainers may suggest alternative approaches that better fit the project

## Good First Contributions

Not sure where to start? These are great entry points:

- Fix typos or improve clarity in existing documentation
- Add a new skill to an existing developer plugin (e.g., a new framework pattern for `python-developer` or `frontend-developer`)
- Submit a bug report with clear steps to reproduce
- Improve existing skill instructions based on your real-world usage experience

## Code Standards

- Follow existing plugin patterns and conventions
- Include clear instructions in command files
- Use the appropriate model for your use case (`opus` for deep analysis, `claude-haiku-4-5` for fast tasks)
- Test with multiple project types when applicable
- Ensure compatibility with the latest Claude Code version

## Developer Plugins Integration

The code-review plugin automatically integrates with installed developer plugins:

- **python-developer** — Python coding standards, TDD patterns, FastAPI/SQLAlchemy/Pydantic conventions
- **frontend-developer** — TypeScript/React standards, TDD patterns, Tailwind/Zustand/TanStack conventions
- **php-developer** — PHP coding standards, TDD patterns, Symfony/Doctrine/DDD conventions

### How it works

When code-review runs, it invokes the `developer-plugins-integration` skill which:

1. Checks if developer plugins are installed (by checking available skills)
2. Detects the project stack from config files
3. Maps: installed plugin + detected stack -> skills to load
4. Passes relevant skills to review auditors and fix commands

### Adding support for a new developer plugin

To integrate a new developer plugin (e.g., `go-developer`):

1. Update `plugins/code-review/skills/developer-plugins-integration/SKILL.md`:
   - Add detection logic for the new stack (e.g., `go.mod` for Go)
   - Add framework sub-detection (e.g., Gin, Echo)
   - Add skill mapping table for the new plugin
2. No changes needed to review.md, fix.md, or agent files — they already delegate to the skill

## External Plugins (MCP Servers)

The marketplace supports external plugins that run as MCP (Model Context Protocol) servers. These live under `external_plugins/` and have a different structure from standard plugins:

```
external_plugins/your-mcp-server/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
└── .mcp.json                # MCP server configuration
```

The `.mcp.json` file defines how to launch the MCP server:

```json
{
  "server-name": {
    "command": "npx",
    "args": ["-y", "@scope/server-package"]
  }
}
```

External plugins are registered in `marketplace.json` with their `source` pointing to `./external_plugins/...` and typically link to an external `homepage` instead of bundling local documentation.

Example: the `sequentialthinking` plugin launches `@modelcontextprotocol/server-sequential-thinking` as an MCP server for structured problem-solving.

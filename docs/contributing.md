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

Plugins with an OMP edition also have an `omp/overlay/<name>.json`, from which `plugins-omp/<name>/` is generated; OMP-only plugins live in `omp/native/<name>/`. See [CLAUDE.md](../CLAUDE.md#omp-edition).

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

## Pull Request Requirements

Every pull request should include:

- Clear description of what changed and why
- Evidence of testing with Claude Code on at least one real project
- Adherence to existing plugin patterns and naming conventions
- Updated version in `plugin.json` (if modifying an existing plugin) — must match `.claude-plugin/marketplace.json`, the row in `README.md`, and the `**Version:**` header in `docs/plugins/<name>.md`. The `Plugin Version Parity` GitHub Actions workflow enforces this; run `python3 scripts/check_plugin_versions.py` locally before pushing. The same script checks the README row's `ID`, `Claude Code` and `OMP` columns against `.claude-plugin/marketplace.json` and `.omp-plugin/marketplace.json`.
- Regenerated OMP edition (if you changed `plugins/<name>/` of a plugin that has an `omp/overlay/<name>.json` — a version bump included — or anything under `omp/` or `scripts/build_omp_edition.py`): `plugins-omp/` and `.omp-plugin/marketplace.json` are generated, so never edit them by hand — run `python3 scripts/build_omp_edition.py` and commit both. OMP-only plugins in `omp/native/<name>/` are versioned in their own `.omp-plugin/plugin.json` and `package.json` and in their row of the README "Available Plugins" table, not in `.claude-plugin/marketplace.json` or a `**Version:**` doc header; `python3 scripts/check_plugin_versions.py` checks the README row. The `OMP Edition` GitHub Actions workflow (`.github/workflows/omp-edition.yml`) enforces this and runs the generator and delivery tests listed there; the full rules are in [CLAUDE.md](../CLAUDE.md#omp-edition).
- Passing delivery tests (if you changed `omp/native/delivery/`): run `python3 omp/native/delivery/tests/test_route_task.py`; then install OMP next to the extension with `bun install --no-save --cwd omp/native/delivery @oh-my-pi/pi-coding-agent@latest` (it lands in the gitignored `omp/native/delivery/node_modules/`; linking an existing global install works too: `ln -s ~/.bun/install/global/node_modules omp/native/delivery/node_modules`) and run `bun test tests/delivery.test.ts` from `omp/native/delivery/`. The `OMP Edition` workflow runs both. Test trailer-parsing rules with synthetic NUL-delimited logs through `scan_delivery_log()`; keep CLI tests for Git integration.
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

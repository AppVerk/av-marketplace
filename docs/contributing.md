# Contributing

We welcome contributions to the AppVerk Claude Code Marketplace.

## Plugin Architecture

Each plugin is a directory under `plugins/` (or `external_plugins/` for third-party MCP servers) with the following structure:

```
plugins/your-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── commands/                 # User-invocable commands (markdown files)
├── agents/                   # Specialized subagents (optional)
└── skills/                   # Reusable modules (optional)
```

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

### Skills

Markdown files in `skills/<skill-name>/SKILL.md` define reusable modules. Skills can be:

- **Agent skills** — invoked by agents (e.g., `secret-scanning`, `sast-analysis`)
- **Background skills** — activate automatically based on context (e.g., `coding-standards`)

Each skill has a frontmatter with name and description, followed by detailed instructions.

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

4. **Register in marketplace.json** at `.claude-plugin/marketplace.json`:

   ```json
   {
     "name": "your-plugin",
     "source": "./plugins/your-plugin",
     "description": "Brief description",
     "version": "1.0.0",
     "category": "development"
   }
   ```

5. **Test** your plugin thoroughly with Claude Code.

6. **Submit a pull request** with:
   - Clear description of plugin functionality
   - Usage examples
   - Any dependencies or prerequisites

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

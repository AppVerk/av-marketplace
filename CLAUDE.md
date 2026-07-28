# Repository Rules

## Agent frontmatter

Agent capability is declared in `tools:`. Claude Code does not support
`allowed-tools:` for subagents — it contributes nothing to the resolved tool
grant. `allowed-tools` is valid in `SKILL.md` and command frontmatter, where it
pre-approves permission prompts without affecting availability.

MCP servers are granted with `mcp__<server>` or `mcp__<server>__*`. Never
enumerate individual MCP tools: those lists drift.

`scripts/check_agent_frontmatter.py` enforces this on every pull request.

## Plugin versioning

When modifying a plugin, update its version following SemVer, in **all four**
places `scripts/check_plugin_versions.py` checks:

1. `plugins/<name>/.claude-plugin/plugin.json`
2. `.claude-plugin/marketplace.json`
3. The plugin's row in the README "Available Plugins" table
4. The `**Version:**` header in `docs/plugins/<name>.md`

Missing the fourth is how `docs/plugins/qa.md` drifted a release behind.

## Marketplace registration

A new plugin is registered in `.claude-plugin/marketplace.json` with `name`,
`source`, `description`, `version` and `category`.

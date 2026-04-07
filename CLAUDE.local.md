# Local Development Rules

## Plugin Versioning

When modifying a plugin, update its version in `plugins/<name>/.claude-plugin/plugin.json` following SemVer:

- **MAJOR** — breaking changes (removed commands, changed behavior, incompatible formats)
- **MINOR** — new features (new commands, agents, skills, new options)
- **PATCH** — bug fixes, documentation improvements, formatting, minor tweaks

Also update the version in the corresponding row in `README.md` (Available Plugins table).

## Plugin Documentation

When modifying a plugin, keep its documentation in sync:

- `docs/plugins/<name>.md` — update if commands, workflow, options, or behavior changed
- `README.md` — update the plugin's description in the Available Plugins table if the change affects the one-line summary
- Plugin count badge in `README.md` — update when adding or removing a plugin

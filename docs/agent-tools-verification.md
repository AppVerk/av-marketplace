# Agent tool verification status

Records the live layer of the repair in
`docs/superpowers/specs/2026-07-27-agent-tools-frontmatter-design.md`: comparing
each agent's harness-resolved tool list against its target.

A row reads `matched — <version>` only when its Resolved list column carries the
harness's resolved list verbatim. A row reverts to `pending` when its recorded
version is older than the shipped version, or when its Resolved list no longer
matches that agent's current `tools:` value entry for entry.

A match is *declaration-confirmed*, not verified: the registry echoes the declared
list, so it cannot confirm that any entry resolves to a callable tool.

| Agent | Status | Resolved list |
| --- | --- | --- |
| `qa:be-tester` | pending | |
| `qa:fe-tester` | pending | |
| `web-auditor:api-security-agent` | pending | |
| `web-auditor:compliance-agent` | pending | |
| `web-auditor:performance-agent` | pending | |
| `web-auditor:seo-agent` | pending | |
| `web-auditor:web-security-agent` | pending | |
| `web-auditor:supply-chain-agent` | pending | |
| `web-auditor:infrastructure-agent` | pending | |
| `web-auditor:web-auditor` | pending | |
| `code-review:fix-auto` | pending | |
| `code-review:security-auditor` | pending | |
| `code-review:code-quality-auditor` | pending | |
| `frontend-developer:developer` | pending | |
| `python-developer:developer` | pending | |
| `php-developer:developer` | not installed | absent from `~/.claude/settings.json`; statically checked only |

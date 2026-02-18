# AppVerk Claude Code Marketplace

Plugins for Claude Code that enhance code quality, security, and development workflows.

## Installation

```bash
/plugin marketplace add AppVerk/av-marketplace
```

After installation, verify with `/help` — you should see the new commands listed.

## Available Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| [Code Review](docs/plugins/code-review.md) | 1.4.0 | Security, architecture, and code quality analysis with OWASP compliance. Optional `--verify` for cross-analysis and adversarial review |
| [Commit](docs/plugins/commit.md) | 1.0.0 | Conventional Commits message generation from staged changes |
| [Web Auditor](docs/plugins/web-auditor.md) | 2.1.0 | Comprehensive web audit: security, SEO, performance, and compliance. Optional `--verify` for cross-domain correlation and adversarial review |
| [Python Developer](docs/plugins/python-developer.md) | 1.1.0 | Python best practices, TDD workflows, async patterns, and uv package manager |
| [Sequential Thinking](https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking) | MCP | Structured problem-solving through dynamic thinking process |

## Documentation

- [Installation & Optional Tools](docs/installation.md)
- [Plugin Guides](docs/plugins/)
- [Contributing](docs/contributing.md)

## Support

- **Bug Reports**: [GitHub Issues](https://github.com/AppVerk/av-marketplace/issues)
- **Feature Requests**: Submit with the `enhancement` label

## License

Copyright © 2025 AppVerk. All rights reserved.

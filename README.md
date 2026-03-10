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
| [Code Review](docs/plugins/code-review.md) | 1.9.0 | Security, architecture, and code quality analysis with OWASP compliance. Unique issue IDs (SEC-001, PERF-001, ...), fix by ID via `/fix SEC-001` or batch via `/fix-report`. Built-in cross-analysis and adversarial review via Cross-Verifier + Challenger |
| [Commit](docs/plugins/commit.md) | 1.1.1 | Conventional Commits message generation from staged changes. Auto-blocks direct `git commit` via hook |
| [Web Auditor](docs/plugins/web-auditor.md) | 2.1.0 | Comprehensive web audit: security, SEO, performance, and compliance. Optional `--verify` for cross-domain correlation and adversarial review |
| [Frontend Developer](docs/plugins/frontend-developer.md) | 1.0.0 | TypeScript + React development workflow with `/develop` command and autonomous `developer` agent. Coding standards, TDD, and stack-specific patterns (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router) |
| [PHP Developer](docs/plugins/php-developer.md) | 1.0.0 | PHP development workflow with `/develop` command and autonomous `developer` agent. Coding standards, TDD, and stack-specific patterns (Symfony, Doctrine ORM, DDD) |
| [Python Developer](docs/plugins/python-developer.md) | 2.1.0 | Python development workflow with `/develop` command and autonomous `developer` agent. Coding standards, TDD, and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic) |
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

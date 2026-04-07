# Installation

## Quick Start

```bash
/plugin marketplace add AppVerk/av-marketplace
```

Verify the installation:

```bash
/help
```

You should see commands like `/review`, `/commit`, `/develop`, `/audit`, and `/setup` listed.

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| Claude Code CLI | Yes | Latest version recommended |
| Git 2.x+ | Yes | Version control |
| GitHub CLI (`gh`) | No | Pull request integration for `/review` and `/analyze-feedback` |

## Optional Tools

The plugins work without any additional tools, but can leverage specialized tools for deeper analysis when available. All tools are automatically detected — no configuration needed.

### Security Analysis

| Tool | Purpose | Installation |
|------|---------|-------------|
| [Semgrep](https://semgrep.dev) | SAST — detects injection, XSS, OWASP Top 10 violations across multiple languages | `brew install semgrep` or `pip install semgrep` |
| [TruffleHog](https://github.com/trufflesecurity/trufflehog) | Secret scanning — finds API keys, tokens, credentials with live verification | `brew install trufflehog` or `go install github.com/trufflesecurity/trufflehog/v3@latest` |
| [Bandit](https://bandit.readthedocs.io) | Python-specific security linter | `pip install bandit` |

### Linters & Type Checkers

**Python:**

| Tool | Purpose | Installation |
|------|---------|-------------|
| [ruff](https://docs.astral.sh/ruff/) | Fast all-in-one linter and formatter | `pip install ruff` |
| [mypy](https://mypy-lang.org) | Static type checker | `pip install mypy` |

**TypeScript / JavaScript:**

| Tool | Purpose | Installation |
|------|---------|-------------|
| [ESLint](https://eslint.org) | Code quality and style checking | `npm install -g eslint` |
| [tsc](https://www.typescriptlang.org) | TypeScript type checking | `npm install -g typescript` |
| [Prettier](https://prettier.io) | Code formatter | `npm install -g prettier` |

**Go:**

| Tool | Purpose | Installation |
|------|---------|-------------|
| [govulncheck](https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck) | Dependency vulnerability scanner | `go install golang.org/x/vuln/cmd/govulncheck@latest` |

**Java:**

| Tool | Purpose | Installation |
|------|---------|-------------|
| [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/) | Dependency CVE scanning | [Installation guide](https://owasp.org/www-project-dependency-check/) |

### Tool Detection

The plugins automatically detect which tools are available on your system. If a tool is not installed:

- The plugin falls back to pattern-based detection or skips that analysis
- You still get results from other available tools
- No errors or warnings are shown

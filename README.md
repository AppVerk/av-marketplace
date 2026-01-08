# AppVerk Claude Code Marketplace

Plugins for Claude Code that enhance code quality, security, and development workflows.

## Overview

This marketplace provides professional-quality plugins for Claude Code, designed to streamline your development process with automated code reviews, security analysis, and intelligent commit message generation.

## Installation

Add this marketplace to your Claude Code installation:

```bash
/plugin marketplace add AppVerk/av-marketplace
```

### Prerequisites

**Required:**

- Claude Code CLI (latest version recommended)
- Git (version 2.x or higher)

**Optional** (for enhanced features):

- GitHub CLI (`gh`) for pull request integration
- Language-specific analysis tools (see details below)

### Optional Tools

The code review plugin works without any additional tools installed, but can leverage specialized tools for deeper analysis when available. All tools are automatically detected and used when present.

#### Security Analysis Tools

**Semgrep** - Multi-language static analysis

- **Purpose**: SAST (Static Application Security Testing) for vulnerability detection
- **Detects**: SQL injection, XSS, command injection, OWASP Top 10 violations
- **Languages**: Python, JavaScript/TypeScript, Go, Java, Ruby, PHP, C/C++
- **Installation**:

  ```bash
  # macOS
  brew install semgrep

  # Python (pip)
  pip install semgrep

  # Other platforms
  # See: https://semgrep.dev/docs/getting-started/
  ```

**Trufflehog** - Secret scanning with verification

- **Purpose**: Detects hardcoded secrets, API keys, tokens, and credentials
- **Detects**: AWS keys, GitHub tokens, private keys, database credentials, JWT tokens
- **Features**: Verifies secrets against actual services (not just pattern matching)
- **Installation**:

  ```bash
  # macOS
  brew install trufflehog

  # Go
  go install github.com/trufflesecurity/trufflehog/v3@latest

  # Docker
  docker pull trufflesecurity/trufflehog:latest
  ```

**Bandit** - Python security linter

- **Purpose**: Security-focused static analysis for Python
- **Detects**: Common security issues in Python code
- **Installation**:

  ```bash
  pip install bandit
  ```

#### Language-Specific Tools

The plugin integrates with standard linters, type checkers, and dependency scanners for various languages:

**Python:**

- `ruff` - Fast all-in-one linter and formatter (`pip install ruff`)
- `mypy` - Static type checker (`pip install mypy`)

**TypeScript/JavaScript:**

- `eslint` - Code quality and style checking (`npm install -g eslint`)
- `tsc` - TypeScript type checking (`npm install -g typescript`)
- `prettier` - Code formatter (`npm install -g prettier`)

**Go:**

- `govulncheck` - Dependency vulnerability scanner (`go install golang.org/x/vuln/cmd/govulncheck@latest`)

**Java:**

- OWASP Dependency-Check - Dependency CVE scanning ([installation guide](https://owasp.org/www-project-dependency-check/))

These tools are used for code quality checks, type safety verification, and dependency vulnerability scanning when available.

#### Tool Detection

The plugins automatically detect which tools are available on your system and use them when appropriate. If a tool is not installed:

- The plugin will fall back to pattern-based detection or skip that specific analysis
- You'll still get results from other available tools
- No errors or warnings will be shown

### Verification

After installation, verify the plugins are available:

```bash
/help
```

You should see `code-review` and `commit` commands listed.

## Available Plugins

### Code Review Plugin

**Version:** 1.0.0

Perform comprehensive code analysis covering security vulnerabilities, code quality, architecture patterns, and best practices.

#### Key Features

- **Security Analysis**
  - OWASP Top 10:2025 compliance checking
  - SQL injection, XSS, and command injection detection
  - Hardcoded secret scanning with verification
  - Dependency vulnerability detection (CVE scanning)
  - Cryptographic failure identification

- **Code Quality Assessment**
  - SOLID principles verification
  - Clean Architecture boundary checking
  - Domain-Driven Design (DDD) pattern analysis
  - Anti-pattern detection (God Objects, Circular Dependencies)
  - Code complexity and maintainability metrics

- **Multi-Language Support**
  - Python, TypeScript/JavaScript, Go, Java, Ruby, PHP, C/C++
  - Framework-specific rules (Django, Flask, FastAPI, React, Express, Spring, Rails, Laravel)

- **Automated Integration**
  - Project-specific linter integration (ruff, mypy, eslint, tsc)
  - Standards discovery from project documentation
  - Respects existing project configurations

#### Usage

```bash
# Review current changes
/review

# Review with specific focus
/review "Check authentication security"

# Review specific files or changes
/review "Analyze the new API endpoints"
```

#### What It Analyzes

The code review plugin examines your code for:

- **Security vulnerabilities**: Injection attacks, XSS, authentication bypasses, insecure crypto
- **Architecture patterns**: DDD aggregates, Clean Architecture layers, SOLID violations
- **Code quality**: Anti-patterns, high complexity, maintainability issues
- **Secrets**: Hardcoded API keys, passwords, tokens, private keys
- **Dependencies**: Known CVEs in third-party packages
- **Standards compliance**: Project-specific coding conventions and style guides

Results include severity levels, file locations, detailed explanations, and actionable remediation steps with code examples.

---

### Commit Plugin

**Version:** 1.0.0

Generate meaningful, well-formatted commit messages that follow the Conventional Commits specification.

#### Key Features

- **Conventional Commits Format**
  - Automatic type detection (feat, fix, docs, style, refactor, perf, test, chore)
  - Scope identification from changed files
  - Clear, descriptive commit messages

- **Task Integration**
  - Optional task ID linking (e.g., JIRA, Linear, GitHub issues)
  - Automatic reference formatting

- **Co-Author Attribution**
  - Includes Claude as co-author by default
  - Disable with `--no-coauthor` flag

- **Breaking Changes**
  - Automatic detection and indication with `!` marker

- **Safety First**
  - Never auto-pushes commits
  - Always allows manual review before push

#### Usage

```bash
# Generate commit message for staged changes
/commit

# Include task ID reference
/commit TASK-123

# Skip co-author attribution
/commit --no-coauthor

# Combine options
/commit ISSUE-456 --no-coauthor
```

#### Commit Message Format

Generated commits follow this structure:

```
type(scope): description

[optional body with details]

Refs: TASK-123
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Types:**

- `feat`: New features
- `fix`: Bug fixes
- `docs`: Documentation changes
- `style`: Code formatting
- `refactor`: Code restructuring
- `perf`: Performance improvements
- `test`: Test additions or modifications
- `chore`: Build process, dependencies, tooling

**Breaking Changes:**

- Indicated with `!` before colon: `feat!: change API response format`

## Plugin Architecture

### Code Review Plugin Components

#### Commands

- **`/review`** - Main entry point for comprehensive code analysis
  - Launches parallel security and code quality auditors
  - Combines results into unified report
  - Supports optional description parameter for focused analysis

#### Agents

Specialized subagents that run in background and perform deep analysis:

- **`security-auditor`** - Security vulnerability assessment
  - Executes: secret-scanning, sast-analysis, dependency-scanning skills
  - Reports: OWASP Top 10:2025 violations, CWE identifiers, CVSS scores
  - Model: claude-opus-4-5 (enterprise-grade analysis)

- **`code-quality-auditor`** - Architecture and maintainability analysis
  - Executes: standards-discovery, linter-integration, architecture-analysis skills
  - Reports: SOLID violations, DDD pattern issues, anti-patterns
  - Model: claude-opus-4-5 (comprehensive quality assessment)

#### Skills

Reusable analysis modules invoked by agents:

- **`architecture-analysis`** - SOLID principles, DDD patterns, Clean Architecture
  - Detects: God Objects, circular dependencies, layer violations
  - Supports: Python, TypeScript (language-agnostic pattern detection)

- **`sast-analysis`** - Static Application Security Testing
  - Tool: Semgrep with OWASP Top 10:2025 rules
  - Covers: Injection, XSS, crypto failures, auth bypass
  - Languages: Python, JS/TS, Go, Java, Ruby, PHP, C/C++

- **`secret-scanning`** - Hardcoded credentials detection
  - Tool: Trufflehog (with verification)
  - Detects: API keys, tokens, private keys, passwords
  - Includes: Remediation guidance and git history cleanup

- **`linter-integration`** - Project-specific tool integration
  - Python: ruff, mypy, black, flake8, pylint
  - TypeScript/JavaScript: eslint, tsc, prettier
  - Auto-detects: Project configuration files

- **`standards-discovery`** - Project coding standards extraction
  - Searches: CONTRIBUTING.md, CODING_STANDARDS.md, ARCHITECTURE.md
  - Extracts: Naming conventions, architecture patterns, testing requirements
  - Fallback: Industry best practices (PEP 8, ESLint recommended)

- **`dependency-scanning`** - Vulnerability scanning in dependencies
  - Python: uv, poetry, pip, safety
  - JavaScript: npm audit, yarn audit, pnpm audit
  - Reports: CVE IDs, CVSS scores, fixed versions

### Commit Plugin Components

#### Commands

- **`/commit`** - Generate Conventional Commits format messages
  - Arguments: `[task-id] [--no-coauthor]`
  - Analyzes: Git diff, commit history, file changes
  - Model: claude-haiku-4-5 (fast, efficient)

## Contributing

We welcome contributions to the av-marketplace! Here's how to add your own plugin:

### Adding a New Plugin

1. **Fork the repository** and create a feature branch

2. **Create your plugin** in the `plugins/` directory:

   ```
   plugins/your-plugin/
   ├── plugin.json          # Plugin metadata
   ├── commands/            # Command definitions
   ├── agents/              # Specialized subagents
   └── skills/              # Reusable modules
   ```

3. **Update marketplace.json** with your plugin metadata:

   ```json
   {
     "name": "your-plugin",
     "source": "./plugins/your-plugin",
     "description": "Brief description of what your plugin does",
     "version": "1.0.0"
   }
   ```

4. **Test your plugin** thoroughly with Claude Code

5. **Submit a pull request** with:
   - Clear description of plugin functionality
   - Usage examples
   - Any dependencies or prerequisites

### Plugin Structure Requirements

- **plugin.json**: Metadata file with name, version, description
- **commands/**: Markdown files defining user-invocable commands
- **agents/**: Optional directory for background subagents
- **skills/**: Optional directory for reusable skill modules

### Code Standards

- Follow existing plugin patterns and conventions
- Include clear documentation in command files
- Test with multiple project types when applicable
- Ensure compatibility with latest Claude Code version

## Support

### Getting Help

- **Bug Reports**: Open an issue on [GitHub Issues](https://github.com/AppVerk/av-marketplace/issues)
- **Feature Requests**: Submit ideas via GitHub Issues with the `enhancement` label
- **Questions**: Check existing issues or create a new discussion

---

## License

Copyright © 2025 AppVerk. All rights reserved.

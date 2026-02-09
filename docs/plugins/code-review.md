# Code Review Plugin

Security, architecture, and code quality analysis for your codebase.

**Version:** 1.2.4

## Commands

### `/review`

Run a comprehensive code review covering security, performance, architecture, and maintainability.

```bash
# Review current changes
/review

# Review with specific focus
/review "Check authentication security"

# Review specific area
/review "Analyze the new API endpoints"
```

The review launches two parallel analysis agents (security + code quality) and combines their findings into a unified report. Each issue includes severity level, file location, explanation, and remediation with code examples.

### `/fix`

Apply a fix for a single issue from the review report. Paste the full issue block and the plugin handles analysis, implementation, verification, and reporting.

```bash
/fix <paste full issue block from /review report>
```

The fix goes through: parse issue, analyze context, propose fix (waits for your approval), implement, verify with linters/tests, and report results.

### `/analyze-feedback`

Analyze PR review comments, classify each as "address" or "reject", and optionally publish response drafts.

```bash
# Analyze current branch's PR
/analyze-feedback

# Analyze specific PR
/analyze-feedback 123

# Include general conversation comments
/analyze-feedback 123 --include-conversation
```

Requires GitHub CLI (`gh`) to be installed and authenticated.

## What It Analyzes

- **Security** — OWASP Top 10:2025 compliance, injection attacks, XSS, authentication bypasses, insecure crypto, hardcoded secrets, dependency CVEs
- **Architecture** — SOLID principles, Clean Architecture boundaries, DDD patterns, anti-patterns (God Objects, circular dependencies)
- **Performance** — N+1 queries, missing indexes, memory leaks, unbounded collections, blocking calls
- **Code Quality** — Complexity, naming, error handling, test coverage gaps
- **Standards** — Project-specific coding conventions discovered from documentation
- **Dependencies** — Known CVEs in third-party packages

## Optional Tools

For deeper analysis, install additional tools. See [Installation — Optional Tools](../installation.md#optional-tools).

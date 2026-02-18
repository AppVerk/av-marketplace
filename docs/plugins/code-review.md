# Code Review Plugin

Security, architecture, and code quality analysis for your codebase.

**Version:** 1.4.0

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

## Verification Mode

Add `--verify` to enable cross-domain correlation and adversarial review of findings.

### Usage

```bash
/review "Check authentication security" --verify
/review --verify
```

### What It Does

After the standard analysis (security + code quality auditors), two verification subagents analyze the findings in parallel:

- **Cross-Verifier**: identifies correlations between security and quality findings (e.g., a God Object with a vulnerability = higher blast radius), coverage gaps, and composite findings
- **Challenger**: challenges every Critical/High finding for false positives, validates severity levels, and calibrates severity between security and quality domains

### Additional Report Sections

Reviews generated with `--verify` include a Verification Summary showing:
- Number of findings verified, removed, and adjusted
- Cross-analysis correlations (security <-> quality)
- Challenged findings with reasoning

### Cost Considerations

Verification mode spawns 2 additional subagent instances. Use it when accuracy matters more than speed.

## Optional Tools

For deeper analysis, install additional tools. See [Installation — Optional Tools](../installation.md#optional-tools).

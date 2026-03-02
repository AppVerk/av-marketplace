# Code Review Plugin

Security, architecture, and code quality analysis for your codebase.

**Version:** 1.6.0

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

### `/fix-report`

Fix issues from a saved review report. Parses the report, presents unfixed issues as a paginated checklist, fixes selected issues, and marks them resolved in the report file.

```bash
/fix-report docs/reviews/2026-02-20-feature-login.md
```

The command:
1. Reads the report and extracts issues (by `### [SEVERITY] Title` headings)
2. Filters out already-fixed issues (those with a `**Status:**` field)
3. Presents unfixed issues as a multi-select checklist, 4 per page, sorted by severity
4. Fixes selected issues sequentially via the `fix-auto` agent
5. Marks fixed issues in the report with `**Status:** ✅ Fixed (YYYY-MM-DD)`

The report becomes a living document — fixed issues won't appear on subsequent `/fix-report` runs.

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

## Save Review to File

After the review report is generated, you are asked whether to save it to a file. If you choose "Yes", the report is saved to `docs/reviews/YYYY-MM-DD-<branch-slug>.md`.

The branch name is slugified (e.g., `feature/user-login` becomes `feature-user-login`). If a file with that name already exists, a numeric suffix is appended (`-2`, `-3`, etc.).

## Fixing Issues

After the review, if issues were found and the report was saved, the review suggests running `/fix-report <path>` to fix issues from the saved report. For individual issues, use `/fix <issue block>`.

**Recommended workflow:**

1. Run `/review` and save the report
2. Run `/fix-report docs/reviews/2026-02-20-feature-login.md`
3. Select issues to fix from the paginated checklist
4. Re-run `/fix-report` on the same file to fix remaining issues

## Skills

### Developer Plugins Integration

**Skill:** `developer-plugins-integration`

Automatically detects installed developer plugins (python-developer, frontend-developer) and the project's tech stack, then loads relevant skills for enhanced code review and fix workflows.

**How it works:**
1. Detects if python-developer and/or frontend-developer plugins are installed
2. Scans project config files (pyproject.toml, package.json, tsconfig.json) to identify the tech stack
3. Maps detected stack to relevant developer skills (coding standards, framework patterns)
4. Passes skills to review auditors and fix commands for stack-aware analysis

**Used by:**
- `/review` — Passes developer skills to security-auditor and code-quality-auditor
- `/fix` — Applies framework-specific patterns when implementing fixes
- `fix-auto` agent — Same as `/fix` but autonomous

**Graceful degradation:** If no developer plugins are installed, the review and fix workflows proceed with standard behavior. No additional action needed.

## Optional Tools

For deeper analysis, install additional tools. See [Installation — Optional Tools](../installation.md#optional-tools).

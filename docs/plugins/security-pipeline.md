# Security Pipeline

Generate and merge security scanning steps into CI/CD pipeline configurations.

## Overview

The `security-pipeline` plugin automates configuration of security scanning in CI/CD pipelines. It detects your CI/CD provider, programming languages, and frameworks, then generates or merges Semgrep (SAST) and TruffleHog (secret scanning) steps into your pipeline configuration.

## Usage

```
/setup
```

No arguments needed. The command auto-detects everything.

## What It Does

1. **Detects CI/CD provider** — looks for `bitbucket-pipelines.yml`, `.github/workflows/*.yml`, `.gitlab-ci.yml`, or `azure-pipelines.yml`
2. **Detects languages** — Python, PHP, JavaScript/TypeScript based on project files
3. **Detects frameworks** — Django, Flask, FastAPI, Symfony, Laravel, React, Next.js, Express and adds framework-specific Semgrep rulesets
4. **Analyzes existing config** — skips already-configured security steps
5. **Generates and merges** — adds missing security steps to your pipeline

## Supported Providers

| Provider | Config File |
|----------|------------|
| Bitbucket Pipelines | `bitbucket-pipelines.yml` |
| GitHub Actions | `.github/workflows/security.yml` |
| GitLab CI | `.gitlab-ci.yml` |
| Azure DevOps | `azure-pipelines.yml` |

## Security Components

### TruffleHog (Secret Scanning)
- Scans git history for leaked secrets
- PR-aware: full history scan for PRs, incremental for commits
- Produces `trufflehog-results.json` artifact

### Semgrep (SAST)
- Language-specific rulesets per detected language
- Always includes OWASP Top 10, security-audit, and secrets rulesets
- Framework-specific rulesets when frameworks are detected
- Two-pass execution: soft (report) + hard (fail on errors)
- Produces `semgrep-results.sarif` artifact

## Enforced Standards

- OWASP Top 10 scanning is always enabled
- Secret detection (`p/secrets`) is always enabled
- Security audit rules are always enabled
- Dual-pass Semgrep: report generation + strict enforcement
- One Semgrep step per detected language

# Security Pipeline Plugin - Design Spec

## Overview

Plugin `security-pipeline` for the av-marketplace. Generates and merges security scanning steps (Semgrep SAST + TruffleHog secret scanning) into CI/CD pipeline configurations. Supports multiple CI/CD providers and programming languages.

Based on the AppVerk "CI/CD Security Standardization Guide" (CD-160326-142038).

## Goals

- Automate configuration of security scanning in CI/CD pipelines
- Enforce organization-wide security standards (OWASP, SAST, secret scanning)
- Support multiple CI/CD providers and programming languages
- Intelligently merge with existing pipeline configurations

## Non-Goals

- Pre-commit hook configuration (separate concern)
- Renovate / dependency update configuration (separate concern)
- Running the security scans themselves (this plugin only generates config)
- CI/CD pipeline steps unrelated to security (build, test, deploy)

## Plugin Structure

```
plugins/security-pipeline/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   └── setup.md
└── skills/
    └── pipeline-security/
        └── SKILL.md
```

- **plugin.json**: name `security-pipeline`, version `1.0.0`, category `security`
- **setup.md**: `/setup` command, model `claude-sonnet-4-6`, no arguments
- **SKILL.md**: Security scanning templates, provider mappings, and HARD-RULES

## Command `/setup` - Execution Flow

### Phase 1: CI/CD Provider Detection

Search for existing CI/CD configuration files in the repository root:

| Provider     | File pattern                    |
|--------------|---------------------------------|
| Bitbucket    | `bitbucket-pipelines.yml`       |
| GitHub       | `.github/workflows/*.yml`       |
| GitLab       | `.gitlab-ci.yml`                |
| Azure DevOps | `azure-pipelines.yml`           |

Behavior:
- **One provider found** - use it
- **Multiple providers found** - ask user which one to configure
- **No provider found** - ask user which provider they want to use

### Phase 2: Language and Framework Detection

Detect programming languages by scanning for marker files:

| Language | Marker files                                          |
|----------|-------------------------------------------------------|
| Python   | `pyproject.toml`, `requirements.txt`, `setup.py`, `Pipfile` |
| PHP      | `composer.json`                                       |
| JS/TS    | `package.json`, `tsconfig.json`                       |

For each detected language, inspect dependency files for framework-specific Semgrep rulesets:

**Python** (check `pyproject.toml`, `requirements.txt`):
- Django detected -> add `p/django`
- Flask detected -> add `p/flask`
- FastAPI detected -> add `p/fastapi`

**PHP** (check `composer.json`):
- Symfony detected -> add `p/symfony`
- Laravel detected -> add `p/laravel`
- WordPress detected -> add `p/wordpress`

**JS/TS** (check `package.json`):
- React detected -> add `p/react`
- Next.js detected -> add `p/nextjs`
- Express detected -> add `p/express`

Multiple languages are supported (monorepo scenario). Each detected language gets its own Semgrep step.

### Phase 3: Existing Configuration Analysis

If a CI/CD config file exists:
- Read and parse the file
- Identify which security steps are already configured (TruffleHog, Semgrep per language)
- Report to user what was detected and what will be added
- Skip already-configured components

### Phase 4: Generation and Merge

- Generate missing security steps using provider-specific syntax
- Merge into existing config file (or create new file)
- Show diff to user before writing

## Security Scanning Components

### TruffleHog (Universal - all languages)

- **Image**: `trufflesecurity/trufflehog:latest`
- **Behavior**: Detects PR context vs commit context
  - PR: scan full git history, output to `trufflehog-results.json`, then re-run with `--fail`
  - Commit: scan since last commit (`HEAD~1`), same dual-run pattern
- **Flags**: `--results=verified,unknown`
- **Artifact**: `trufflehog-results.json`

### Semgrep (Per language)

Each Semgrep step runs two passes:
1. **Soft pass**: generates SARIF report, does not fail the build (`|| true`)
2. **Hard pass**: fails on `--severity=ERROR` and `--severity=WARNING` with `--error .`

#### Semgrep - Python
- **Base configs**: `p/python`, `p/security-audit`, `p/secrets`, `p/owasp-top-ten`
- **Framework configs** (added when detected): `p/django`, `p/flask`, `p/fastapi`
- **Excludes**: `tests`, `.venv`
- **Image**: `semgrep/semgrep:latest`
- **Artifact**: `semgrep-results.sarif`

#### Semgrep - PHP
- **Base configs**: `p/php`, `p/phpcs-security-audit`, `p/security-audit`, `p/secrets`, `p/owasp-top-ten`
- **Framework configs** (added when detected): `p/symfony`, `p/laravel`, `p/wordpress`
- **Excludes**: `tests`, `vendor`
- **Image**: `semgrep/semgrep:latest`
- **Artifact**: `semgrep-results.sarif`

#### Semgrep - JavaScript/TypeScript
- **Base configs**: `p/javascript`, `p/typescript`, `p/nodejs`, `p/security-audit`, `p/secrets`, `p/owasp-top-ten`
- **Framework configs** (added when detected): `p/react`, `p/nextjs`, `p/express`
- **Excludes**: `node_modules`, `dist`, `build`, `coverage`
- **Image**: `semgrep/semgrep:latest`
- **Artifact**: `semgrep-results.sarif`

## CI/CD Provider Mappings

### Bitbucket Pipelines

- File: `bitbucket-pipelines.yml`
- Uses YAML anchors (`&trufflehog_scan`, `&semgrep_scan_<lang>`) in `definitions.steps`
- Steps referenced in `pipelines.default` via `*anchor`
- Per-step `image` declaration
- Artifacts via `artifacts:` key

### GitHub Actions

- File: `.github/workflows/security.yml`
- Workflow with `on: [push, pull_request]`
- Jobs per security component
- Container images via `container:` or `uses:` with Docker actions
- Artifacts via `actions/upload-artifact`
- PR detection via `github.event_name == 'pull_request'`

### GitLab CI

- File: `.gitlab-ci.yml`
- Security scanning stage
- Per-job `image` declaration
- Artifacts via `artifacts.reports.sast` for SARIF integration
- `allow_failure: true` for soft pass, strict job for hard pass
- PR detection via `$CI_MERGE_REQUEST_IID`

### Azure DevOps

- File: `azure-pipelines.yml`
- Stage with security jobs
- Container images via `container:` on job level
- Artifacts via `PublishBuildArtifacts` task
- PR detection via `Build.Reason` variable

## Skill HARD-RULES

These rules are non-negotiable and must always be enforced:

1. Semgrep MUST always include `p/owasp-top-ten` config
2. Semgrep MUST always include `p/security-audit` config
3. Semgrep MUST always include `p/secrets` config
4. TruffleHog MUST use `--results=verified,unknown` flag
5. Each Semgrep step MUST have two passes: soft (SARIF report) + hard (fail on ERROR/WARNING)
6. Each language MUST get its own separate Semgrep step
7. Framework-specific rulesets MUST be added when the framework is detected in dependencies

## Command Configuration

```yaml
# setup.md frontmatter
model: claude-sonnet-4-6
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Bash(git diff:*)
```

No arguments - everything is auto-detected. The command loads the `pipeline-security` skill for templates and rules.

## Edge Cases

- **No CI/CD file and no language markers**: Report to user that nothing was detected, ask for guidance
- **CI/CD file exists but is malformed**: Report the issue, offer to create security steps as a separate snippet
- **All security steps already configured**: Report that pipeline is already compliant, no changes needed
- **Unknown CI/CD provider file**: Report that the provider is not supported, list supported providers
- **Monorepo with mixed languages**: Generate separate Semgrep steps for each detected language, single TruffleHog step

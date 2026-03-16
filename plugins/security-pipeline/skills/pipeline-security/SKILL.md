---
name: pipeline-security
description: Security scanning templates and HARD-RULES for CI/CD pipeline configuration. Covers Semgrep SAST and TruffleHog secret scanning across Bitbucket, GitHub Actions, GitLab CI, and Azure DevOps.
---

# Pipeline Security Configuration

Security scanning configuration templates for CI/CD pipelines. This skill provides templates for Semgrep (SAST) and TruffleHog (secret scanning) and mappings for multiple CI/CD providers.

<HARD-RULES>
## HARD-RULES - Non-Negotiable Requirements

These rules MUST be followed in every generated configuration. Violation of any rule makes the output non-compliant.

1. Semgrep MUST always include `p/owasp-top-ten` config for every language
2. Semgrep MUST always include `p/security-audit` config for every language
3. Semgrep MUST always include `p/secrets` config for every language
4. TruffleHog MUST use `--results=verified,unknown` flag
5. Each Semgrep step MUST have two passes:
   - **Soft pass**: generates SARIF report, does NOT fail the build (`|| true`)
   - **Hard pass**: fails on `--severity=ERROR` and `--severity=WARNING` with `--error .`
6. Each detected language MUST get its own separate Semgrep step
7. Framework-specific Semgrep rulesets MUST be added when the framework is detected in project dependencies
</HARD-RULES>

## Security Components

### TruffleHog - Secret Scanning (Universal)

TruffleHog is language-agnostic. One step per pipeline.

**Image:** `trufflesecurity/trufflehog:latest`

**Logic:** The step must detect whether it is running in a PR context or a regular commit context:

- **PR context**: scan full git history, output JSON report, then re-run with `--fail`
- **Commit context**: scan since last commit (`HEAD~1`), output JSON report, then re-run with `--fail`

**Required flags:** `--results=verified,unknown`
**Artifact:** `trufflehog-results.json`

### Semgrep - Python

- **Image:** `semgrep/semgrep:latest`
- **Base configs:** `p/python`, `p/security-audit`, `p/secrets`, `p/owasp-top-ten`
- **Framework configs:** Django -> `p/django`, Flask -> `p/flask`, FastAPI -> `p/fastapi`
- **Excludes:** `tests`, `.venv`
- **Artifact:** `semgrep-results.sarif`
- **Two passes:** soft (SARIF report, `|| true`) + hard (fail on ERROR/WARNING)

### Semgrep - PHP

- **Base configs:** `p/php`, `p/phpcs-security-audit`, `p/security-audit`, `p/secrets`, `p/owasp-top-ten`
- **Framework configs:** Symfony -> `p/symfony`, Laravel -> `p/laravel`, WordPress -> `p/wordpress`
- **Excludes:** `tests`, `vendor`

### Semgrep - JavaScript/TypeScript

- **Base configs:** `p/javascript`, `p/typescript`, `p/nodejs`, `p/security-audit`, `p/secrets`, `p/owasp-top-ten`
- **Framework configs:** React -> `p/react`, Next.js -> `p/nextjs`, Express -> `p/express`
- **Excludes:** `node_modules`, `dist`, `build`, `coverage`

## CI/CD Provider Templates

### Bitbucket Pipelines

**File:** `bitbucket-pipelines.yml`

Uses YAML anchors in `definitions.steps`, referenced in `pipelines.default`.
PR detection via `$BITBUCKET_PR_ID`.

```yaml
definitions:
  steps:
    - step: &trufflehog_scan
        name: Secret Scanning - TruffleHog
        image: trufflesecurity/trufflehog:latest
        script:
          - |
            if [ -n "$BITBUCKET_PR_ID" ]; then
              echo "PR detected - scanning full git history"
              trufflehog git file://. --results=verified,unknown --json > trufflehog-results.json || true
              trufflehog git file://. --results=verified,unknown --fail
            else
              echo "Commit detected - scanning since last commit"
              trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --json > trufflehog-results.json || true
              trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --fail
            fi
        artifacts:
          - trufflehog-results.json

    - step: &semgrep_scan_python
        name: SAST - Semgrep Security Scan (Python)
        image: semgrep/semgrep:latest
        script:
          - semgrep scan
              --config p/python
              --config p/security-audit
              --config p/secrets
              --config p/owasp-top-ten
              --exclude tests
              --exclude .venv
              --sarif
              --output semgrep-results.sarif . || true
          - semgrep scan
              --config p/python
              --config p/security-audit
              --config p/secrets
              --config p/owasp-top-ten
              --exclude tests
              --exclude .venv
              --severity=ERROR
              --severity=WARNING
              --error .
        artifacts:
          - semgrep-results.sarif

pipelines:
  default:
    - step: *trufflehog_scan
    - step: *semgrep_scan_python
```

### GitHub Actions

**File:** `.github/workflows/security.yml`

Workflow with `on: [push, pull_request]`. Each tool is a separate job using `container`. PR detection via `github.event_name == 'pull_request'`. Artifacts uploaded via `actions/upload-artifact@v4`.

```yaml
name: Security Scanning

on:
  push:
  pull_request:

jobs:
  trufflehog:
    name: Secret Scanning - TruffleHog
    runs-on: ubuntu-latest
    container:
      image: trufflesecurity/trufflehog:latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Run TruffleHog
        run: |
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            echo "PR detected - scanning full git history"
            trufflehog git file://. --results=verified,unknown --json > trufflehog-results.json || true
            trufflehog git file://. --results=verified,unknown --fail
          else
            echo "Commit detected - scanning since last commit"
            trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --json > trufflehog-results.json || true
            trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --fail
          fi
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: trufflehog-results
          path: trufflehog-results.json

  semgrep-python:
    name: SAST - Semgrep Security Scan (Python)
    runs-on: ubuntu-latest
    container:
      image: semgrep/semgrep:latest
    steps:
      - uses: actions/checkout@v4
      - name: Semgrep Scan (report)
        run: |
          semgrep scan \
            --config p/python \
            --config p/security-audit \
            --config p/secrets \
            --config p/owasp-top-ten \
            --exclude tests \
            --exclude .venv \
            --sarif \
            --output semgrep-results.sarif . || true
      - name: Semgrep Scan (enforce)
        run: |
          semgrep scan \
            --config p/python \
            --config p/security-audit \
            --config p/secrets \
            --config p/owasp-top-ten \
            --exclude tests \
            --exclude .venv \
            --severity=ERROR \
            --severity=WARNING \
            --error .
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: semgrep-results-python
          path: semgrep-results.sarif
```

### GitLab CI

**File:** `.gitlab-ci.yml`

Uses `stages: [security]`. PR/MR detection via `$CI_MERGE_REQUEST_IID`. SARIF artifacts reported via `artifacts.reports.sast` for native GitLab Security Dashboard integration.

```yaml
stages:
  - security

trufflehog_scan:
  stage: security
  image: trufflesecurity/trufflehog:latest
  script:
    - |
      if [ -n "$CI_MERGE_REQUEST_IID" ]; then
        echo "MR detected - scanning full git history"
        trufflehog git file://. --results=verified,unknown --json > trufflehog-results.json || true
        trufflehog git file://. --results=verified,unknown --fail
      else
        echo "Commit detected - scanning since last commit"
        trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --json > trufflehog-results.json || true
        trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --fail
      fi
  artifacts:
    paths:
      - trufflehog-results.json
    when: always

semgrep_scan_python:
  stage: security
  image: semgrep/semgrep:latest
  script:
    - semgrep scan
        --config p/python
        --config p/security-audit
        --config p/secrets
        --config p/owasp-top-ten
        --exclude tests
        --exclude .venv
        --sarif
        --output semgrep-results.sarif . || true
    - semgrep scan
        --config p/python
        --config p/security-audit
        --config p/secrets
        --config p/owasp-top-ten
        --exclude tests
        --exclude .venv
        --severity=ERROR
        --severity=WARNING
        --error .
  artifacts:
    paths:
      - semgrep-results.sarif
    reports:
      sast: semgrep-results.sarif
    when: always
```

### Azure DevOps

**File:** `azure-pipelines.yml`

Uses `stages` with `stage: Security`. PR detection via `Build.Reason`. Artifacts published via `PublishBuildArtifacts@1`.

```yaml
stages:
  - stage: Security
    displayName: Security Scanning
    jobs:
      - job: TruffleHog
        displayName: Secret Scanning - TruffleHog
        container:
          image: trufflesecurity/trufflehog:latest
        steps:
          - checkout: self
            fetchDepth: 0
          - script: |
              if [ "$(Build.Reason)" = "PullRequest" ]; then
                echo "PR detected - scanning full git history"
                trufflehog git file://. --results=verified,unknown --json > trufflehog-results.json || true
                trufflehog git file://. --results=verified,unknown --fail
              else
                echo "Commit detected - scanning since last commit"
                trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --json > trufflehog-results.json || true
                trufflehog git file://. --since-commit HEAD~1 --results=verified,unknown --fail
              fi
            displayName: Run TruffleHog
          - task: PublishBuildArtifacts@1
            condition: always()
            inputs:
              pathToPublish: trufflehog-results.json
              artifactName: trufflehog-results

      - job: SemgrepPython
        displayName: SAST - Semgrep Security Scan (Python)
        container:
          image: semgrep/semgrep:latest
        steps:
          - checkout: self
          - script: |
              semgrep scan \
                --config p/python \
                --config p/security-audit \
                --config p/secrets \
                --config p/owasp-top-ten \
                --exclude tests \
                --exclude .venv \
                --sarif \
                --output semgrep-results.sarif . || true
            displayName: Semgrep Scan (report)
          - script: |
              semgrep scan \
                --config p/python \
                --config p/security-audit \
                --config p/secrets \
                --config p/owasp-top-ten \
                --exclude tests \
                --exclude .venv \
                --severity=ERROR \
                --severity=WARNING \
                --error .
            displayName: Semgrep Scan (enforce)
          - task: PublishBuildArtifacts@1
            condition: always()
            inputs:
              pathToPublish: semgrep-results.sarif
              artifactName: semgrep-results-python
```

## Adapting Semgrep Templates Per Language

When generating Semgrep steps, adapt the Python template by replacing:

**For PHP:**

- Configs: replace `p/python` with `p/php`, add `p/phpcs-security-audit`
- Excludes: replace `tests, .venv` with `tests, vendor`
- Step name suffix: `(PHP)` instead of `(Python)`
- Anchor/job name: `semgrep_scan_php` instead of `semgrep_scan_python`

**For JavaScript/TypeScript:**

- Configs: replace `p/python` with `p/javascript`, `p/typescript`, `p/nodejs`
- Excludes: replace `tests, .venv` with `node_modules, dist, build, coverage`
- Step name suffix: `(JavaScript/TypeScript)` instead of `(Python)`
- Anchor/job name: `semgrep_scan_js` instead of `semgrep_scan_python`

**Framework configs** are appended as additional `--config p/<framework>` lines to both soft and hard passes.

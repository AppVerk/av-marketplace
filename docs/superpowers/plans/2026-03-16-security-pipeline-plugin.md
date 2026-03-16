# Security Pipeline Plugin - Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a new `security-pipeline` plugin that generates and merges Semgrep + TruffleHog security steps into CI/CD pipeline configurations.

**Architecture:** Single command (`/setup`) loads a skill with security scanning templates and HARD-RULES. The command auto-detects CI/CD provider, languages, and frameworks, then generates or merges security steps into the pipeline config file. No agents needed - skill-driven approach with Sonnet model.

**Tech Stack:** Claude Code plugin system (Markdown + YAML frontmatter), Bitbucket/GitHub/GitLab/Azure DevOps pipeline YAML formats.

**Spec:** `docs/superpowers/specs/2026-03-16-security-pipeline-plugin-design.md`

---

## Chunk 1: Plugin Scaffold

### Task 1: Create plugin.json

**Files:**
- Create: `plugins/security-pipeline/.claude-plugin/plugin.json`

- [ ] **Step 1: Create the plugin metadata file**

```json
{
  "name": "security-pipeline",
  "description": "Generate and merge security scanning steps (Semgrep SAST + TruffleHog) into CI/CD pipeline configurations",
  "version": "1.0.0"
}
```

- [ ] **Step 2: Register in marketplace.json**

Modify: `.claude-plugin/marketplace.json`

Add to the `plugins` array (before the `sequentialthinking` entry):

```json
{
  "name": "security-pipeline",
  "source": "./plugins/security-pipeline",
  "description": "Generate and merge security scanning steps (Semgrep SAST + TruffleHog) into CI/CD pipeline configurations across Bitbucket, GitHub Actions, GitLab CI, and Azure DevOps",
  "version": "1.0.0",
  "category": "security"
}
```

- [ ] **Step 3: Commit**

```bash
git add plugins/security-pipeline/.claude-plugin/plugin.json .claude-plugin/marketplace.json
AV_COMMIT_SKILL=1 git commit -m "feat(security-pipeline): scaffold plugin with metadata"
```

---

### Task 2: Create the `/setup` command

**Files:**
- Create: `plugins/security-pipeline/commands/setup.md`

- [ ] **Step 1: Create the command file**

The command file needs YAML frontmatter with allowed-tools and model, followed by the full execution instructions. The command loads the `pipeline-security` skill and orchestrates the 4-phase flow.

```markdown
---
allowed-tools: Read, Write, Edit, Glob, Bash(git diff:*)
description: Generate and merge security scanning steps (Semgrep + TruffleHog) into CI/CD pipeline configuration. Auto-detects provider, languages, and frameworks.
model: claude-sonnet-4-6
---

# Security Pipeline Setup

You are configuring security scanning for a CI/CD pipeline. Follow every phase in order. Do not skip phases.

## Step 1: Load Security Pipeline Skill (MANDATORY)

Before doing anything else, load the security pipeline skill:

```
Use the Skill tool with:
  skill: "security-pipeline:pipeline-security"
```

**You MUST load this skill first. All generated configuration must follow its HARD-RULES.**

---

## Step 2: Detect CI/CD Provider

Search for existing CI/CD configuration files:

```
Use the Glob tool to search for:
  - bitbucket-pipelines.yml
  - .github/workflows/*.yml
  - .gitlab-ci.yml
  - azure-pipelines.yml
```

**Decision logic:**
- **One provider found** -> use it, announce to user: "Detected [provider] pipeline configuration."
- **Multiple providers found** -> ask user: "Found configurations for [list]. Which one should I configure?"
- **No provider found** -> ask user: "No CI/CD configuration found. Which provider do you want to use? (Bitbucket / GitHub Actions / GitLab CI / Azure DevOps)"

Record the selected provider and the config file path.

---

## Step 3: Detect Languages and Frameworks

Scan for language marker files:

```
Use the Glob tool to search for:
  - pyproject.toml, requirements.txt, setup.py, Pipfile (Python)
  - composer.json (PHP)
  - package.json, tsconfig.json (JS/TS)
```

For each detected language, read the dependency file and check for frameworks:

**Python** (read `pyproject.toml` or `requirements.txt`):
- Look for `django` -> note Django detected
- Look for `flask` -> note Flask detected
- Look for `fastapi` -> note FastAPI detected

**PHP** (read `composer.json` `require` section):
- Look for `symfony/` -> note Symfony detected
- Look for `laravel/` -> note Laravel detected
- Look for `wordpress` or `wp-` -> note WordPress detected

**JS/TS** (read `package.json` `dependencies` and `devDependencies`):
- Look for `react` -> note React detected
- Look for `next` -> note Next.js detected
- Look for `express` -> note Express detected

Announce to user: "Detected languages: [list]. Frameworks: [list]."

If no languages detected, inform user and ask for guidance.

---

## Step 4: Analyze Existing Configuration

If a CI/CD config file exists:

1. Read the file
2. Check if TruffleHog step already exists (search for `trufflehog` in the file)
3. Check if Semgrep steps exist per detected language (search for `semgrep` in the file)
4. Report to user what is already configured and what will be added
5. If everything is already configured, report compliance and stop

If no config file exists, note that a new file will be created.

---

## Step 5: Generate and Merge Security Steps

Using the templates from the `pipeline-security` skill:

1. For each missing component, generate the appropriate configuration in the detected provider's syntax
2. Always generate TruffleHog step (if missing)
3. Generate Semgrep step for each detected language (if missing), including framework-specific rulesets
4. Merge into existing file or create new file

**Before writing:** Show the user the complete generated/modified configuration and ask for confirmation.

After user confirms:
- If modifying existing file: use Edit tool
- If creating new file: use Write tool

Show the final diff:
```bash
git diff
```
```

- [ ] **Step 2: Commit**

```bash
git add plugins/security-pipeline/commands/setup.md
AV_COMMIT_SKILL=1 git commit -m "feat(security-pipeline): add /setup command with 4-phase flow"
```

---

## Chunk 2: Pipeline Security Skill

### Task 3: Create the `pipeline-security` skill - HARD-RULES and component definitions

**Files:**
- Create: `plugins/security-pipeline/skills/pipeline-security/SKILL.md`

- [ ] **Step 1: Write the skill file**

This is the largest file in the plugin. It contains:
1. HARD-RULES section
2. TruffleHog component template (universal)
3. Semgrep component templates per language (Python, PHP, JS/TS)
4. Provider-specific syntax mappings (Bitbucket, GitHub Actions, GitLab CI, Azure DevOps)

The skill content should be structured as follows:

```markdown
---
name: pipeline-security
description: Security scanning templates and HARD-RULES for CI/CD pipeline configuration. Covers Semgrep SAST and TruffleHog secret scanning across Bitbucket, GitHub Actions, GitLab CI, and Azure DevOps.
---

# Pipeline Security Configuration

Security scanning configuration templates for CI/CD pipelines. This skill provides templates for Semgrep (SAST) and TruffleHog (secret scanning) and mappings for multiple CI/CD providers.

---

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

---

## Security Components

### TruffleHog - Secret Scanning (Universal)

TruffleHog is language-agnostic. One step per pipeline.

**Image:** `trufflesecurity/trufflehog:latest`

**Logic:** The step must detect whether it is running in a PR context or a regular commit context:
- **PR context**: scan full git history, output JSON report, then re-run with `--fail`
- **Commit context**: scan since last commit (`HEAD~1`), output JSON report, then re-run with `--fail`

**Required flags:** `--results=verified,unknown`
**Artifact:** `trufflehog-results.json`

---

### Semgrep - Python

**Image:** `semgrep/semgrep:latest`

**Base configs (always included):**
- `p/python`
- `p/security-audit`
- `p/secrets`
- `p/owasp-top-ten`

**Framework configs (added when detected):**
- Django -> `p/django`
- Flask -> `p/flask`
- FastAPI -> `p/fastapi`

**Excludes:** `tests`, `.venv`
**Artifact:** `semgrep-results.sarif`

**Two passes:**
1. Soft: `semgrep scan` with all configs, `--sarif`, `--output semgrep-results.sarif .  || true`
2. Hard: `semgrep scan` with all configs, `--severity=ERROR`, `--severity=WARNING`, `--error .`

---

### Semgrep - PHP

**Image:** `semgrep/semgrep:latest`

**Base configs (always included):**
- `p/php`
- `p/phpcs-security-audit`
- `p/security-audit`
- `p/secrets`
- `p/owasp-top-ten`

**Framework configs (added when detected):**
- Symfony -> `p/symfony`
- Laravel -> `p/laravel`
- WordPress -> `p/wordpress`

**Excludes:** `tests`, `vendor`
**Artifact:** `semgrep-results.sarif`

**Two passes:** same pattern as Python.

---

### Semgrep - JavaScript/TypeScript

**Image:** `semgrep/semgrep:latest`

**Base configs (always included):**
- `p/javascript`
- `p/typescript`
- `p/nodejs`
- `p/security-audit`
- `p/secrets`
- `p/owasp-top-ten`

**Framework configs (added when detected):**
- React -> `p/react`
- Next.js -> `p/nextjs`
- Express -> `p/express`

**Excludes:** `node_modules`, `dist`, `build`, `coverage`
**Artifact:** `semgrep-results.sarif`

**Two passes:** same pattern as Python.

---

## CI/CD Provider Templates

### Bitbucket Pipelines

**File:** `bitbucket-pipelines.yml`

**Structure:**
- Security steps defined as YAML anchors in `definitions.steps`
- Referenced in `pipelines.default` via `*anchor_name`
- Each step has its own `image`

**TruffleHog step template:**

```yaml
# In definitions.steps:
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
```

**Semgrep step template (Python example - adapt per language):**

```yaml
# In definitions.steps:
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
```

**Default pipeline reference:**

```yaml
pipelines:
  default:
    - step: *trufflehog_scan
    - step: *semgrep_scan_python
    # Add more *semgrep_scan_<lang> as needed
```

---

### GitHub Actions

**File:** `.github/workflows/security.yml`

**TruffleHog job template:**

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
```

**Semgrep job template (Python example - adapt per language):**

```yaml
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

---

### GitLab CI

**File:** `.gitlab-ci.yml`

**TruffleHog job template:**

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
```

**Semgrep job template (Python example - adapt per language):**

```yaml
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

---

### Azure DevOps

**File:** `azure-pipelines.yml`

**TruffleHog job template:**

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
```

**Semgrep job template (Python example - adapt per language):**

```yaml
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

---

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
```

- [ ] **Step 2: Verify skill file structure**

Run: `head -5 plugins/security-pipeline/skills/pipeline-security/SKILL.md`
Expected: YAML frontmatter with `name: pipeline-security` and `description`

- [ ] **Step 3: Commit**

```bash
git add plugins/security-pipeline/skills/pipeline-security/SKILL.md
AV_COMMIT_SKILL=1 git commit -m "feat(security-pipeline): add pipeline-security skill with templates and HARD-RULES"
```

---

## Chunk 3: Documentation and Final Registration

### Task 4: Add plugin documentation

**Files:**
- Create: `docs/plugins/security-pipeline.md`

- [ ] **Step 1: Write documentation page**

Follow the pattern of existing plugin docs. Include:
- Plugin name and description
- Installation (marketplace reference)
- Usage: `/setup` command
- What it detects (providers, languages, frameworks)
- What it generates (TruffleHog + Semgrep steps)
- Supported CI/CD providers
- HARD-RULES summary

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/plugins/security-pipeline.md
AV_COMMIT_SKILL=1 git commit -m "docs(security-pipeline): add plugin documentation"
```

---

### Task 5: Verify complete plugin structure

- [ ] **Step 1: Verify all files exist**

Run: `find plugins/security-pipeline -type f | sort`

Expected output:
```
plugins/security-pipeline/.claude-plugin/plugin.json
plugins/security-pipeline/commands/setup.md
plugins/security-pipeline/skills/pipeline-security/SKILL.md
```

- [ ] **Step 2: Verify marketplace.json includes the plugin**

Run: `grep -A5 "security-pipeline" .claude-plugin/marketplace.json`

Expected: the plugin entry with name, source, description, version, category.

- [ ] **Step 3: Verify plugin.json is valid JSON**

Run: `python3 -c "import json; json.load(open('plugins/security-pipeline/.claude-plugin/plugin.json')); print('OK')"`

Expected: `OK`

- [ ] **Step 4: Verify skill frontmatter**

Run: `head -4 plugins/security-pipeline/skills/pipeline-security/SKILL.md`

Expected:
```
---
name: pipeline-security
description: Security scanning templates and HARD-RULES for CI/CD pipeline configuration...
---
```

- [ ] **Step 5: Verify command frontmatter**

Run: `head -5 plugins/security-pipeline/commands/setup.md`

Expected:
```
---
allowed-tools: Read, Write, Edit, Glob, Bash(git diff:*)
description: Generate and merge security scanning steps...
model: claude-sonnet-4-6
---
```

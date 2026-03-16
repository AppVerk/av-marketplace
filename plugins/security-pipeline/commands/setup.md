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

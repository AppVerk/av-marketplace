---
name: secret-scanning
description: Detects and handles sensitive information in code. Use when reviewing code for secret leaks and hard-coded credentials.
allowed-tools: Read, Grep, Glob, Bash(trufflehog:*), Bash(jq:*), Bash(command:*), Bash(grep:*), Bash(echo:*)
---

# Secret Scanning

## Instruction

Perform comprehensive analysis of the provided codebase to identify any sensitive information, such as API keys, passwords, tokens, or other secrets that may have been inadvertently included in the code. Use a combination of pattern matching, keyword searches, and specialized tools to detect potential security risks.

---

## Prerequisites Check

**ALWAYS run this check first before scanning:**

```bash
# Check if trufflehog is available
command -v trufflehog >/dev/null 2>&1 && echo "OK: trufflehog available" || echo "WARNING: trufflehog not installed - using fallback patterns"

# Check if jq is available
command -v jq >/dev/null 2>&1 && echo "OK: jq available" || echo "WARNING: jq not installed - output will be raw JSON"
```

If tools are missing, install them:

```bash
# macOS
brew install trufflehog jq

# Linux (pip)
pip install trufflehog
sudo apt-get install jq

# Using pipx (recommended)
pipx install trufflehog
```

---

## Primary Method: Trufflehog Scan

When `trufflehog` is available, use this as the primary scanning method:

```bash
# Scan for verified secrets only (recommended)
trufflehog git file://. --json | jq 'select(.Verified == true) | { secret_type: .DetectorName, file: .SourceMetadata.Data.Git.filename, line: .SourceMetadata.Data.Git.line }'

# Scan for ALL secrets (including unverified)
trufflehog git file://. --json | jq '{ secret_type: .DetectorName, file: .SourceMetadata.Data.Git.filename, line: .SourceMetadata.Data.Git.line, verified: .Verified }'

# Scan specific directory
trufflehog filesystem ./src --json | jq 'select(.Verified == true)'
```

### Excluding Files from Scans

TruffleHog v3 uses the `--exclude-paths` (`-x`) flag pointing to a file with **newline-separated regex patterns** (not globs):

**Example: `.trufflehog-exclude.txt`**

```text
# Test fixtures and mock data
.*test.*fixtures.*
.*/mocks?/.*
.*_test\.py$
.*\.test\.(js|ts)$

# Generated and vendored code
.*/vendor/.*
.*\.generated\.\w+$
.*/node_modules/.*

# Documentation and configs
.*\.md$
.*\.ya?ml$
```

**Usage:**

```bash
# Exclude paths using regex file
trufflehog git file://. --exclude-paths=.trufflehog-exclude.txt --json

# Include only specific paths
trufflehog git file://. --include-paths=.trufflehog-include.txt --json
```

**Alternative: `--exclude-globs`** for simpler cases (filters at `git log` level, faster):

```bash
trufflehog git file://. --exclude-globs="*.md,docs/*,test/*" --json
```

> **IMPORTANT:** `--exclude-paths` takes **regex** patterns (one per line in a file). `--exclude-globs` takes **glob** patterns (comma-separated inline). Do NOT mix the two formats.

---

## Fallback Method: Pattern Matching

When `trufflehog` is NOT available, use these regex patterns with Grep tool:

### Python-Specific Secrets

```bash
# Django SECRET_KEY
grep -rn "SECRET_KEY\s*=\s*['\"][^'\"]*['\"]" --include="*.py" --include="settings*.py"

# Database URLs with credentials
grep -rn "postgres://\|mysql://\|mongodb://\|redis://" --include="*.py" --include="*.env" --include="*.yaml" --include="*.yml"

# Flask/FastAPI secret keys
grep -rn "app\.secret_key\s*=\|JWT_SECRET\|AUTH_SECRET" --include="*.py"
```

### Generic Secret Patterns

```bash
# AWS Credentials
grep -rn "AKIA[0-9A-Z]{16}\|aws_secret_access_key\|AWS_SECRET" --include="*.py" --include="*.env" --include="*.yaml"

# API Keys (generic patterns)
grep -rn "api[_-]?key\s*[=:]\s*['\"][^'\"]{20,}['\"]" --include="*.py" --include="*.js" --include="*.env"

# Private Keys
grep -rn "BEGIN RSA PRIVATE KEY\|BEGIN OPENSSH PRIVATE KEY\|BEGIN EC PRIVATE KEY" .

# GitHub/GitLab Tokens
grep -rn "ghp_[a-zA-Z0-9]{36}\|gho_[a-zA-Z0-9]{36}\|glpat-[a-zA-Z0-9\-]{20}" .

# Generic password patterns
grep -rn "password\s*[=:]\s*['\"][^'\"]+['\"]" --include="*.py" --include="*.env" --include="*.yaml"
```

### Environment Files Check

```bash
# Check for .env files that might be committed
find . -name ".env*" -not -path "./.git/*" -type f

# Check for common secret file patterns
find . \( -name "*.pem" -o -name "*.key" -o -name "*credentials*" -o -name "*secrets*" \) -not -path "./.git/*"
```

---

## Python-Specific Security Patterns

### Django Security Checks

| Pattern | Risk | CWE |
|---------|------|-----|
| `DEBUG = True` in production | Information disclosure | CWE-215 |
| `ALLOWED_HOSTS = ['*']` | Host header injection | CWE-20 |
| Hardcoded `SECRET_KEY` | Session hijacking | CWE-798 |
| `SECURE_SSL_REDIRECT = False` | Man-in-the-middle | CWE-319 |

### FastAPI/Flask Security Checks

| Pattern | Risk | CWE |
|---------|------|-----|
| Hardcoded JWT secrets | Token forgery | CWE-798 |
| `verify=False` in requests | SSL bypass | CWE-295 |
| `pickle.loads()` on user input | RCE via deserialization | CWE-502 |

---

## Report Format

For each secret found, report:

```json
{
  "severity": "CRITICAL",
  "type": "Hardcoded Secret",
  "secret_type": "AWS Access Key / Django SECRET_KEY / etc.",
  "file": "path/to/file.py",
  "line": 42,
  "cwe": "CWE-798",
  "description": "Hardcoded credentials found in source code",
  "remediation": "See Remediation section below"
}
```

---

## Remediation Guidelines

### Immediate Actions

1. **Rotate the exposed secret immediately**
   - AWS: Deactivate key in IAM console, create new key
   - Django: Generate new SECRET_KEY, invalidate all sessions
   - API keys: Revoke and regenerate in provider dashboard

2. **Remove from git history** (if committed):

   ```bash
   # Use git-filter-repo (recommended)
   pip install git-filter-repo
   git filter-repo --invert-paths --path path/to/secret/file

   # Force push to remote (coordinate with team!)
   git push origin --force --all
   ```

3. **Check for unauthorized access**
   - Review audit logs for the affected service
   - Look for unusual API calls or access patterns

### Prevention Best Practices

1. **Use environment variables:**

   ```python
   import os
   SECRET_KEY = os.environ.get('SECRET_KEY')
   ```

2. **Use secret management tools:**
   - AWS Secrets Manager
   - HashiCorp Vault
   - python-dotenv for local development

3. **Add to .gitignore:**

   ```gitignore
   .env
   .env.local
   *.pem
   *.key
   *credentials*
   ```

4. **Use pre-commit hooks:**

   ```yaml
   # .pre-commit-config.yaml
   repos:
     - repo: https://github.com/trufflesecurity/trufflehog
       rev: main
       hooks:
         - id: trufflehog
   ```

---

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| `trufflehog: command not found` | Use fallback patterns or install via `brew install trufflehog` |
| Scan takes too long | Use `--max-depth=50` flag or scan specific directories |
| Too many false positives | Use `--only-verified` flag or filter by `Verified == true` |
| No secrets found but suspicious | Check `.gitignore` patterns, scan untracked files separately |

### Performance Tips

- For large repos, scan only changed files: `trufflehog git file://. --since-commit=HEAD~10`
- Exclude test fixtures: use `--exclude-paths=.trufflehog-exclude.txt` with regex patterns (see "Excluding Files from Scans" section above)
- For faster git-level filtering: use `--exclude-globs="test/*,docs/*"`
- Run in parallel for multiple repos

---
name: dependency-scanning
description: Scans project dependencies for known vulnerabilities (CVEs). Supports Python (uv, pip, poetry), JavaScript, Go, Java, and other languages. Addresses OWASP A03:2025 - Software Supply Chain Failures.
allowed-tools: Read, Grep, Glob, Bash(uv:*), Bash(pip-audit:*), Bash(pip:*), Bash(poetry:*), Bash(safety:*), Bash(npm:*), Bash(yarn:*), Bash(pnpm:*), Bash(go:*), Bash(command:*), Bash(jq:*), Bash(cat:*), Bash(echo:*), Bash(mktemp:*)
---

# Dependency Scanning - Supply Chain Security

Scans project dependencies for known vulnerabilities (CVEs) across multiple languages.

**OWASP Coverage:** A03:2025 - Software Supply Chain Failures

---

## Supported Languages & Tools

| Language | Primary Tool | Alternative | Manifest Files |
|----------|-------------|-------------|----------------|
| Python | uv | pip, poetry | pyproject.toml, uv.lock, requirements.txt, poetry.lock |
| JavaScript | npm audit | yarn audit | package-lock.json, yarn.lock, pnpm-lock.yaml |
| Go | govulncheck | go list | go.mod, go.sum |
| Java | OWASP Dependency-Check | mvn versions | pom.xml, build.gradle |
| Ruby | bundler-audit | - | Gemfile.lock |
| PHP | composer audit | - | composer.lock |

---

## Prerequisites Check

**ALWAYS run this check before scanning:**

```bash
echo "=== Dependency Scanning Tools ==="

# Python package managers
command -v uv >/dev/null 2>&1 && echo "OK: uv $(uv --version 2>/dev/null | head -1)" || echo "NOT FOUND: uv"
command -v poetry >/dev/null 2>&1 && echo "OK: poetry $(poetry --version 2>/dev/null)" || echo "NOT FOUND: poetry"
command -v pip >/dev/null 2>&1 && echo "OK: pip $(pip --version 2>/dev/null | cut -d' ' -f2)" || echo "NOT FOUND: pip"

# Python security scanners
command -v pip-audit >/dev/null 2>&1 && echo "OK: pip-audit" || echo "MISSING: pip-audit"
command -v safety >/dev/null 2>&1 && echo "OK: safety" || echo "OPTIONAL: safety"

# JavaScript
command -v npm >/dev/null 2>&1 && echo "OK: npm $(npm --version)" || echo "MISSING: npm"

# Go
command -v govulncheck >/dev/null 2>&1 && echo "OK: govulncheck" || echo "OPTIONAL: govulncheck"

# Universal
command -v jq >/dev/null 2>&1 && echo "OK: jq" || echo "OPTIONAL: jq"
```

### Installation

Outside an audit only; an audit never installs tools:

```bash
# uv (recommended for Python)
curl -LsSf https://astral.sh/uv/install.sh | sh

# pip-audit (works with all Python package managers)
pip install pip-audit
# or: uv tool install pip-audit
# or: pipx install pip-audit

# Go vulnerability checker
go install golang.org/x/vuln/cmd/govulncheck@latest

# Ruby
gem install bundler-audit
```

---

## Scan Output

Scan results go to one directory per run, outside the repository. Create it once, before the first scan, unless the calling agent has already created it:

```bash
OUT=$(mktemp -d) && echo "$OUT"
```

Each scan below that saves a result writes it to `"$OUT/<name>"` and its error output to a `.err` file of the same base name, and the Read tool reads `"$OUT/<name>"`. A Bash call may not keep shell variables from an earlier one: in each later command, write the printed directory, single-quoted, in place of `$OUT`, and give the Read tool the plain path. Never write into the repository: a command that would rewrite a lockfile or install packages there — `uv lock` without `--check` or `--dry-run`, `poetry lock`, `npm install`, `go mod tidy` without `-diff` — is a fix to recommend, not a check to run.

---

## Python Dependency Scanning

### Auto-Detect Python Package Manager

```bash
echo "=== Detecting Python Package Manager ==="

if [ -f "uv.lock" ]; then
    echo "uv project detected (uv.lock)"
    PYTHON_PM="uv"
elif [ -f "poetry.lock" ]; then
    echo "Poetry project detected (poetry.lock)"
    PYTHON_PM="poetry"
elif [ -f "Pipfile.lock" ]; then
    echo "Pipenv project detected (Pipfile.lock)"
    PYTHON_PM="pipenv"
elif [ -f "requirements.txt" ]; then
    echo "pip project detected (requirements.txt)"
    PYTHON_PM="pip"
elif [ -f "pyproject.toml" ]; then
    echo "pyproject.toml found - checking format..."
    grep -q "\[tool.uv\]" pyproject.toml && echo "uv project" && PYTHON_PM="uv"
    grep -q "\[tool.poetry\]" pyproject.toml && echo "Poetry project" && PYTHON_PM="poetry"
fi
```

---

### uv Projects

`uv` is a fast Python package manager with excellent dependency resolution.

```bash
# Check for outdated packages
uv pip list --outdated 2>/dev/null

# Verify lock file integrity
uv lock --check 2>/dev/null && echo "Lock file OK" || echo "Lock file needs update"

# Run pip-audit through uv
uv tool run pip-audit --format=json -o "$OUT/pip-audit-uv.json" 2>"$OUT/pip-audit-uv.err"

# Export requirements and scan
uv pip compile pyproject.toml -o "$OUT/requirements.txt" 2>"$OUT/requirements.err"
uv tool run pip-audit -r "$OUT/requirements.txt" --format=json -o "$OUT/pip-audit-compiled.json" 2>"$OUT/pip-audit-compiled.err"

# Preview upgrades to the latest versions without writing uv.lock
uv lock --upgrade --dry-run 2>/dev/null

# Show dependency tree
uv pip tree 2>/dev/null | head -50
```
**After scan:** Read `"$OUT/pip-audit-uv.json"` and `"$OUT/pip-audit-compiled.json"` with the Read tool and analyze the JSON results.

---

### Poetry Projects

```bash
# Check for outdated packages
poetry show --outdated 2>/dev/null

# Verify lock file integrity
poetry check --lock 2>/dev/null && echo "Lock file OK" || echo "Lock file needs update"

# Export and scan with pip-audit
poetry export -f requirements.txt --output "$OUT/poetry-requirements.txt" 2>"$OUT/poetry-requirements.err"
pip-audit -r "$OUT/poetry-requirements.txt" --format=json -o "$OUT/pip-audit-poetry.json" 2>"$OUT/pip-audit-poetry.err"

# Alternative: Run pip-audit in Poetry environment
poetry run pip-audit --format=json 2>/dev/null

# Update all packages
poetry update --dry-run 2>/dev/null

# Show dependency tree
poetry show --tree 2>/dev/null | head -50
```
**After scan:** Read `"$OUT/pip-audit-poetry.json"` with the Read tool and analyze the JSON results.

---

### pip Projects (requirements.txt)

```bash
# Scan requirements.txt directly
pip-audit -r requirements.txt --format=json -o "$OUT/pip-audit-pip.json" 2>"$OUT/pip-audit-pip.err"

# Scan with fix suggestions
pip-audit -r requirements.txt --fix --dry-run 2>/dev/null

# Strict mode (fail on any vulnerability)
pip-audit -r requirements.txt --strict --format=json 2>/dev/null

# Check installed packages
pip-audit --format=json 2>/dev/null

# List outdated packages
pip list --outdated --format=json 1>"$OUT/pip-outdated.json" 2>"$OUT/pip-outdated.err"
```
**After scan:** Read `"$OUT/pip-audit-pip.json"` and `"$OUT/pip-outdated.json"` with the Read tool and analyze the JSON results.

---

### safety (Alternative Scanner)

Works with all Python package managers:

```bash
# Scan requirements file
safety check -r requirements.txt --save-json "$OUT/safety-results.json" 2>"$OUT/safety-results.err"

# Scan Poetry lock file
poetry export -f requirements.txt --output "$OUT/poetry-req.txt" 2>"$OUT/poetry-req.err"
safety check -r "$OUT/poetry-req.txt" --save-json "$OUT/safety-poetry.json" 2>"$OUT/safety-poetry.err"

# Scan uv project
uv pip compile pyproject.toml -o "$OUT/uv-req.txt" 2>"$OUT/uv-req.err"
safety check -r "$OUT/uv-req.txt" --save-json "$OUT/safety-uv.json" 2>"$OUT/safety-uv.err"

# Full report with recommendations
safety check -r requirements.txt --full-report 2>/dev/null
```
**After scan:** Read `"$OUT/safety-results.json"`, `"$OUT/safety-poetry.json"`, and `"$OUT/safety-uv.json"` with the Read tool and analyze the JSON results.

---

## JavaScript/Node.js Dependency Scanning

### npm audit

```bash
# Basic audit with JSON output
npm audit --json 1>"$OUT/npm-audit.json" 2>"$OUT/npm-audit.err"

# Production dependencies only
npm audit --omit=dev --json 2>/dev/null

# Auto-fix (non-breaking changes)
npm audit fix --dry-run 2>/dev/null

# Force fix (may include breaking changes)
npm audit fix --force --dry-run 2>/dev/null
```
**After scan:** Read `"$OUT/npm-audit.json"` with the Read tool and analyze the JSON results.

### yarn audit

```bash
# Yarn 1.x
yarn audit --json 1>"$OUT/yarn-audit.json" 2>"$OUT/yarn-audit.err"

# Yarn 2+/Berry
yarn npm audit --json 2>/dev/null
```
**After scan:** Read `"$OUT/yarn-audit.json"` with the Read tool and analyze the JSON results.

### pnpm audit

```bash
pnpm audit --json 2>/dev/null
```

---

## Go Dependency Scanning

### govulncheck (Official Go Tool)

```bash
# Scan entire project
govulncheck ./... 2>/dev/null

# JSON output
govulncheck -json ./... 1>"$OUT/govulncheck.json" 2>"$OUT/govulncheck.err"
```
**After scan:** Read `"$OUT/govulncheck.json"` with the Read tool and analyze the JSON results.

### go list (Check for Updates)

```bash
# List outdated dependencies
go list -m -u all 2>/dev/null | grep '\['

# JSON format
go list -m -u -json all 1>"$OUT/go-outdated.json" 2>"$OUT/go-outdated.err"
```
**After scan:** Read `"$OUT/go-outdated.json"` with the Read tool and analyze the JSON results.

---

## Java Dependency Scanning

### OWASP Dependency-Check

```bash
# Maven project: the report goes to $OUT, not target/
mvn org.owasp:dependency-check-maven:check -DfailBuildOnCVSS=7 -Dodc.outputDirectory="$OUT" 2>"$OUT/dependency-check.err"

# Gradle project (writes build/ and .gradle/ into the project: never during an audit)
./gradlew dependencyCheckAnalyze 2>/dev/null

# Check for updates (Maven)
mvn versions:display-dependency-updates 2>/dev/null
```
**After scan:** Read `"$OUT/dependency-check-report.html"` with the Read tool and analyze the results.

---

## Ruby Dependency Scanning

### bundler-audit

```bash
# Update vulnerability database and scan
bundle-audit update 2>/dev/null && bundle-audit check --format=json 1>"$OUT/bundler-audit.json" 2>"$OUT/bundler-audit.err"
```
**After scan:** Read `"$OUT/bundler-audit.json"` with the Read tool and analyze the JSON results.

---

## PHP Dependency Scanning

### composer audit

```bash
# Built-in audit (Composer 2.4+)
composer audit --format=json 1>"$OUT/composer-audit.json" 2>"$OUT/composer-audit.err"
```
**After scan:** Read `"$OUT/composer-audit.json"` with the Read tool and analyze the JSON results.

---

## Report Format

### Structured Output

```json
{
  "scan_info": {
    "tool": "pip-audit",
    "package_manager": "uv|poetry|pip",
    "language": "python",
    "manifest": "pyproject.toml|poetry.lock|requirements.txt",
    "timestamp": "2025-12-11T10:30:00Z"
  },
  "findings": [
    {
      "package": "requests",
      "installed_version": "2.25.0",
      "fixed_version": "2.31.0",
      "vulnerability": {
        "id": "CVE-2023-32681",
        "aliases": ["GHSA-j8r2-6x86-q33q", "PYSEC-2023-74"],
        "severity": "HIGH",
        "cvss": 7.5,
        "description": "Unintended leak of Proxy-Authorization header",
        "owasp": "A03:2025"
      },
      "recommendation": "Upgrade to requests>=2.31.0"
    }
  ],
  "summary": {
    "total_packages": 45,
    "vulnerable_packages": 3,
    "by_severity": {"critical": 0, "high": 2, "medium": 1, "low": 0}
  }
}
```

### Severity Classification

| Severity | CVSS Range |
|----------|------------|
| CRITICAL | 9.0 - 10.0 |
| HIGH | 7.0 - 8.9 |
| MEDIUM | 4.0 - 6.9 |
| LOW | 0.1 - 3.9 |

---

## Supply Chain Security Best Practices

### OWASP A03:2025 Mitigation

1. **Lock Files** - Always commit lock files (uv.lock, poetry.lock, package-lock.json)
2. **Regular Updates** - Schedule weekly dependency updates
3. **Automated Scanning** - Run scans on every PR
4. **Minimal Dependencies** - Audit necessity of each dependency
5. **Trusted Sources** - Use official registries only

### Dependency Hygiene

```bash
# Python (uv): Check dependency tree
uv pip tree 2>/dev/null | head -30

# Python (Poetry): Check dependency tree
poetry show --tree 2>/dev/null | head -30

# JavaScript: Check for unused packages
npx depcheck 2>/dev/null

# Go: list unused or missing modules without editing go.mod or go.sum (Go 1.23+)
go mod tidy -diff 2>/dev/null
```

### Lock File Verification

```bash
# uv
uv lock --check

# Poetry
poetry check --lock

# npm
npm ci --dry-run --ignore-scripts  # Fails if lock file doesn't match; --dry-run leaves node_modules alone

# Go
go mod verify
```

---

## CI/CD Integration Examples

### GitHub Actions

```yaml
# .github/workflows/dependency-scan.yml
name: Dependency Scanning
on:
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 8 * * 1'  # Weekly Monday scan

jobs:
  python-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - name: Install and audit
        run: |
          pip install pip-audit
          pip-audit -r requirements.txt --format=json --output=audit-results.json
      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: dependency-audit
          path: audit-results.json

  npm-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm audit --omit=dev --audit-level=high
```

### Azure DevOps Pipelines

```yaml
# azure-pipelines.yml
steps:
  - script: |
      pip install pip-audit
      pip install -r requirements.txt -r requirements-dev.txt
      pip-audit --format=json --output=$(Build.ArtifactStagingDirectory)/audit.json
    displayName: 'Dependency Audit'

  - task: PublishBuildArtifacts@1
    inputs:
      pathToPublish: '$(Build.ArtifactStagingDirectory)/audit.json'
      artifactName: 'dependency-audit'
    displayName: 'Publish Audit Results'
```

> **Azure DevOps Shell Compatibility:**
> - **No brace expansion**: Use `pip install -r requirements.txt -r requirements-dev.txt` instead of `pip install -r requirements{,-dev}.txt`
> - **Dependency groups**: Install each group explicitly: `pip install package1 package2 package3`
> - **Task parameters**: `PublishBuildArtifacts@1` uses `pathToPublish` (NOT `pathtoPublish` or `path`)
> - Use `script:` for shell commands; `cmd:` and `powershell:` have different escaping rules

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `uv: command not found` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `pip-audit: command not found` | `pip install pip-audit` or `uv tool install pip-audit` |
| Poetry export fails | Run `poetry lock` first |
| Different results between tools | Different vulnerability databases - run both |
| npm audit returns non-zero | Use `--audit-level=high` to filter |
| Lock file out of sync | Run `uv lock` / `poetry lock` / `npm install` |

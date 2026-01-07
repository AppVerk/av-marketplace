---
name: dependency-scanning
description: Scans project dependencies for known vulnerabilities (CVEs). Supports Python (uv, pip, poetry), JavaScript, Go, Java, and other languages. Addresses OWASP A03:2025 - Software Supply Chain Failures.
allowed-tools: Read, Grep, Glob, Bash(uv:*), Bash(pip-audit:*), Bash(pip:*), Bash(poetry:*), Bash(safety:*), Bash(npm:*), Bash(yarn:*), Bash(pnpm:*), Bash(go:*), Bash(command:*), Bash(jq:*), Bash(cat:*)
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
uv tool run pip-audit --format=json 2>/dev/null | jq '.dependencies[] | select(.vulns | length > 0) | {
  name: .name,
  version: .version,
  vulns: [.vulns[] | {id: .id, fix_versions: .fix_versions}]
}'

# Export requirements and scan
uv pip compile pyproject.toml -o /tmp/requirements.txt 2>/dev/null
uv tool run pip-audit -r /tmp/requirements.txt --format=json 2>/dev/null

# Update all packages to latest secure versions
uv lock --upgrade 2>/dev/null

# Show dependency tree
uv pip tree 2>/dev/null | head -50
```

---

### Poetry Projects

```bash
# Check for outdated packages
poetry show --outdated 2>/dev/null

# Verify lock file integrity
poetry check --lock 2>/dev/null && echo "Lock file OK" || echo "Lock file needs update"

# Export and scan with pip-audit
poetry export -f requirements.txt --output /tmp/poetry-requirements.txt 2>/dev/null
pip-audit -r /tmp/poetry-requirements.txt --format=json 2>/dev/null | jq '.dependencies[] | select(.vulns | length > 0)'

# Alternative: Run pip-audit in Poetry environment
poetry run pip-audit --format=json 2>/dev/null

# Update all packages
poetry update --dry-run 2>/dev/null

# Show dependency tree
poetry show --tree 2>/dev/null | head -50
```

---

### pip Projects (requirements.txt)

```bash
# Scan requirements.txt directly
pip-audit -r requirements.txt --format=json 2>/dev/null | jq '.dependencies[] | select(.vulns | length > 0) | {
  name: .name,
  version: .version,
  vulns: [.vulns[] | {id: .id, fix_versions: .fix_versions, description: .description}]
}'

# Scan with fix suggestions
pip-audit -r requirements.txt --fix --dry-run 2>/dev/null

# Strict mode (fail on any vulnerability)
pip-audit -r requirements.txt --strict --format=json 2>/dev/null

# Check installed packages
pip-audit --format=json 2>/dev/null

# List outdated packages
pip list --outdated --format=json 2>/dev/null | jq '.[] | {name: .name, current: .version, latest: .latest_version}'
```

---

### safety (Alternative Scanner)

Works with all Python package managers:

```bash
# Scan requirements file
safety check -r requirements.txt --json 2>/dev/null | jq '.vulnerabilities[] | {
  package: .package_name,
  version: .analyzed_version,
  vuln_id: .vulnerability_id,
  severity: .severity,
  advisory: .advisory
}'

# Scan Poetry lock file
poetry export -f requirements.txt | safety check --stdin --json 2>/dev/null

# Scan uv project
uv pip compile pyproject.toml | safety check --stdin --json 2>/dev/null

# Full report with recommendations
safety check -r requirements.txt --full-report 2>/dev/null
```

---

## JavaScript/Node.js Dependency Scanning

### npm audit

```bash
# Basic audit with JSON output
npm audit --json 2>/dev/null | jq '{
  vulnerabilities: .vulnerabilities | to_entries | map({
    package: .key,
    severity: .value.severity,
    via: .value.via,
    fixAvailable: .value.fixAvailable
  }),
  metadata: .metadata
}'

# Production dependencies only
npm audit --omit=dev --json 2>/dev/null

# Auto-fix (non-breaking changes)
npm audit fix --dry-run 2>/dev/null

# Force fix (may include breaking changes)
npm audit fix --force --dry-run 2>/dev/null
```

### yarn audit

```bash
# Yarn 1.x
yarn audit --json 2>/dev/null | jq 'select(.type == "auditAdvisory") | .data.advisory'

# Yarn 2+/Berry
yarn npm audit --json 2>/dev/null
```

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
govulncheck -json ./... 2>/dev/null | jq '.vulnerability // empty | {
  id: .osv.id,
  aliases: .osv.aliases,
  summary: .osv.summary,
  affected: [.modules[].packages[].callstacks[].symbol]
}'
```

### go list (Check for Updates)

```bash
# List outdated dependencies
go list -m -u all 2>/dev/null | grep '\['

# JSON format
go list -m -u -json all 2>/dev/null | jq 'select(.Update) | {
  path: .Path,
  current: .Version,
  latest: .Update.Version
}'
```

---

## Java Dependency Scanning

### OWASP Dependency-Check

```bash
# Maven project
mvn org.owasp:dependency-check-maven:check -DfailBuildOnCVSS=7 2>/dev/null

# Gradle project
./gradlew dependencyCheckAnalyze 2>/dev/null

# Check for updates (Maven)
mvn versions:display-dependency-updates 2>/dev/null
```

---

## Ruby Dependency Scanning

### bundler-audit

```bash
# Update vulnerability database and scan
bundle-audit update && bundle-audit check --format=json 2>/dev/null | jq '.results[] | {
  gem: .gem.name,
  version: .gem.version,
  advisory: .advisory.id,
  severity: .advisory.criticality
}'
```

---

## PHP Dependency Scanning

### composer audit

```bash
# Built-in audit (Composer 2.4+)
composer audit --format=json 2>/dev/null | jq '.advisories | to_entries | map({
  package: .key,
  advisories: .value
})'
```

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

| Severity | CVSS Range | Action Required |
|----------|------------|-----------------|
| CRITICAL | 9.0 - 10.0 | Block deployment, fix immediately |
| HIGH | 7.0 - 8.9 | Fix before release |
| MEDIUM | 4.0 - 6.9 | Plan fix within sprint |
| LOW | 0.1 - 3.9 | Track for future update |

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

# Go: Clean up unused modules
go mod tidy -v 2>/dev/null
```

### Lock File Verification

```bash
# uv
uv lock --check

# Poetry
poetry check --lock

# npm
npm ci --ignore-scripts  # Fails if lock file doesn't match

# Go
go mod verify
```

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

---

## Version History

- v0.1.0 (2025-12-11): Initial version - Multi-language support with uv/pip/poetry, OWASP A03:2025

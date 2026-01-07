---
name: sast-analysis
description: Static Application Security Testing (SAST) for multi-language codebases. Uses Semgrep and language-specific tools to detect vulnerabilities across Python, JavaScript, TypeScript, Go, Java, and more.
allowed-tools: Read, Grep, Glob, Bash(semgrep:*), Bash(bandit:*), Bash(eslint:*), Bash(command:*), Bash(jq:*), Bash(cat:*)
---

# SAST Analysis - Multi-Language Security Scanner

Static Application Security Testing (SAST) skill for comprehensive vulnerability detection across multiple programming languages.

---

## Supported Languages

| Language | Primary Tool | Fallback |
|----------|-------------|----------|
| Python | Semgrep + Bandit | Pattern matching |
| JavaScript/TypeScript | Semgrep + ESLint | Pattern matching |
| Go | Semgrep | Pattern matching |
| Java | Semgrep | Pattern matching |
| Ruby | Semgrep | Pattern matching |
| PHP | Semgrep | Pattern matching |
| C/C++ | Semgrep | Pattern matching |
| All others | Semgrep auto-detect | Pattern matching |

---

## Prerequisites Check

**ALWAYS run this check before analysis:**

```bash
echo "=== SAST Tools Availability ==="
command -v semgrep >/dev/null 2>&1 && echo "OK: semgrep $(semgrep --version 2>/dev/null | head -1)" || echo "MISSING: semgrep (primary tool)"
command -v bandit >/dev/null 2>&1 && echo "OK: bandit (Python)" || echo "OPTIONAL: bandit (Python-specific)"
command -v eslint >/dev/null 2>&1 && echo "OK: eslint (JavaScript)" || echo "OPTIONAL: eslint (JS-specific)"
command -v jq >/dev/null 2>&1 && echo "OK: jq" || echo "OPTIONAL: jq (JSON formatting)"
```

### Installation

```bash
# Semgrep (required - supports all languages)
pip install semgrep
# or: brew install semgrep

# Python-specific (optional)
pip install bandit

# JavaScript-specific (optional)
npm install -g eslint @eslint/js
```

---

## Universal Scan: Semgrep Auto-Detect

Semgrep automatically detects languages and applies relevant rules:

```bash
# Auto-detect language and apply security rules (RECOMMENDED)
semgrep scan --config=auto . --json 2>/dev/null | jq '.results[] | {
  rule: .check_id,
  severity: .extra.severity,
  file: .path,
  line: .start.line,
  message: .extra.message,
  cwe: .extra.metadata.cwe
}'

# OWASP Top 10 rules (all languages)
semgrep scan --config=p/owasp-top-ten . --json 2>/dev/null

# Security audit (comprehensive)
semgrep scan --config=p/security-audit . --json 2>/dev/null

# Secure defaults (guardrails)
semgrep scan --config=p/secure-defaults . --json 2>/dev/null
```

---

## Language-Specific Scans

### Python (Django, Flask, FastAPI)

Semgrep has framework-native analysis for Python with 84% true positive rate for Django, Flask, FastAPI, and ~100 popular libraries.

```bash
# Comprehensive Python scan (Django + Flask + FastAPI)
semgrep scan \
  --config=p/python \
  --config=p/django \
  --config=p/flask \
  . --json 2>/dev/null

# FastAPI-specific patterns (included in p/python with framework-native analysis)
# Semgrep automatically tracks implicit data flows in FastAPI
semgrep scan --config=auto . --json 2>/dev/null

# Bandit for deeper Python-specific analysis
bandit -r . -f json 2>/dev/null | jq '.results[] | {
  severity: .issue_severity,
  file: .filename,
  line: .line_number,
  test_id: .test_id,
  issue: .issue_text,
  cwe: .issue_cwe.id
}'
```

### JavaScript / TypeScript

```bash
# JS/TS + React + Node.js rules
semgrep scan \
  --config=p/javascript \
  --config=p/typescript \
  --config=p/react \
  --config=p/nodejs \
  . --json 2>/dev/null

# ESLint security plugin
eslint --ext .js,.jsx,.ts,.tsx . --format json 2>/dev/null
```

### Go

```bash
# Go security rules
semgrep scan --config=p/golang . --json 2>/dev/null
```

### Java

```bash
# Java + Spring rules
semgrep scan --config=p/java --config=p/spring . --json 2>/dev/null
```

### Ruby

```bash
# Ruby + Rails rules
semgrep scan --config=p/ruby --config=p/rails . --json 2>/dev/null
```

### PHP

```bash
# PHP + Laravel/Symfony rules
semgrep scan --config=p/php . --json 2>/dev/null
```

---

## OWASP Top 10:2025 Coverage

Updated mapping for OWASP Top 10 2025:

| ID | Category | CWEs | Semgrep Coverage |
|----|----------|------|------------------|
| A01:2025 | **Broken Access Control** | 40 | `p/owasp-top-ten`, `p/security-audit` |
| A02:2025 | **Security Misconfiguration** | 16 | `p/security-audit`, `p/secure-defaults` |
| A03:2025 | **Software Supply Chain Failures** (NEW) | 5 | Use `dependency-scanning` skill |
| A04:2025 | **Cryptographic Failures** | 32 | `p/security-audit` |
| A05:2025 | **Injection** (SQL, XSS, Command) | 38 | `p/sql-injection`, `p/command-injection` |
| A06:2025 | **Insecure Design** | - | Manual review, threat modeling |
| A07:2025 | **Authentication Failures** | 36 | `p/jwt`, framework configs |
| A08:2025 | **Software/Data Integrity Failures** | - | `p/security-audit` |
| A09:2025 | **Logging & Alerting Failures** | 5 | Manual review |
| A10:2025 | **Mishandling Exceptional Conditions** (NEW) | 24 | Pattern matching, manual review |

### Comprehensive OWASP Scan

```bash
# Full OWASP 2025 coverage
semgrep scan \
  --config=p/owasp-top-ten \
  --config=p/security-audit \
  --config=p/sql-injection \
  --config=p/command-injection \
  --config=p/ssrf \
  --config=p/secure-defaults \
  . --json 2>/dev/null
```

### A10:2025 - Exceptional Conditions Patterns

New category for error handling vulnerabilities:

```bash
# Python: Empty except blocks, improper error handling
grep -rn "except:\s*pass\|except Exception:\s*pass" --include="*.py" .

# JavaScript: Swallowed errors
grep -rn "catch\s*(.*)\s*{\s*}\|catch\s*(.*)\s*{\s*//\|\.catch\(\(\)\s*=>" --include="*.js" --include="*.ts" .

# Go: Ignored errors
grep -rn "_, _ =\|_ :=.*err" --include="*.go" .
```

---

## Fallback: Pattern-Based Analysis

When Semgrep is not available, use language-aware pattern matching:

### Universal Patterns (All Languages)

```bash
# SQL Injection patterns
grep -rn "execute.*%\|execute.*format\|execute.*\+\|query.*\+\|SELECT.*\+\|INSERT.*\+" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.php" --include="*.rb" .

# Command Injection patterns
grep -rn "system(\|exec(\|popen(\|shell_exec(\|passthru(" \
  --include="*.py" --include="*.js" --include="*.php" --include="*.rb" .

# Hardcoded secrets (generic)
grep -rn "password\s*=\s*['\"][^'\"]\+['\"]\\|api_key\s*=\s*['\"]" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" .
```

### Python-Specific Patterns

```bash
# Dangerous functions
grep -rn "pickle\.loads\|yaml\.load\|eval(\|exec(\|__import__" --include="*.py" .

# SQL Injection in Django/SQLAlchemy/FastAPI
grep -rn "\.raw(\|\.extra(\|RawSQL(\|execute.*f\"" --include="*.py" .

# FastAPI security issues
grep -rn "verify=False\|allow_origins=\[.\*.\]\|Depends(.*OAuth2" --include="*.py" .

# Insecure deserialization
grep -rn "marshal\.loads\|shelve\.open" --include="*.py" .
```

### JavaScript/TypeScript Patterns

```bash
# DOM XSS
grep -rn "innerHTML\|outerHTML\|document\.write\|eval(" --include="*.js" --include="*.ts" --include="*.jsx" --include="*.tsx" .

# Prototype pollution
grep -rn "__proto__\|constructor\[" --include="*.js" --include="*.ts" .

# Dangerous requires
grep -rn "require(.*\+\|require(.*input" --include="*.js" --include="*.ts" .
```

### Go Patterns

```bash
# SQL Injection
grep -rn "fmt\.Sprintf.*SELECT\|fmt\.Sprintf.*INSERT\|Exec(.*\+" --include="*.go" .

# Command Injection
grep -rn "exec\.Command(.*\+\|os\.exec" --include="*.go" .
```

### Java Patterns

```bash
# SQL Injection
grep -rn "createQuery.*\+\|executeQuery.*\+" --include="*.java" .

# XXE
grep -rn "XMLInputFactory\|SAXParser\|DocumentBuilder" --include="*.java" .

# Deserialization
grep -rn "ObjectInputStream\|readObject(" --include="*.java" .
```

---

## Report Format

### Structured Output

```json
{
  "scan_info": {
    "tool": "semgrep|bandit|eslint|pattern-match",
    "languages_detected": ["python", "javascript"],
    "files_scanned": 142,
    "timestamp": "2025-12-11T10:30:00Z"
  },
  "findings": [
    {
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "confidence": "HIGH|MEDIUM|LOW",
      "rule_id": "python.lang.security.audit.sqli",
      "language": "python",
      "cwe": "CWE-89",
      "owasp": "A05:2025",
      "file": "src/database.py",
      "line": 42,
      "code_snippet": "cursor.execute(f\"SELECT * FROM users WHERE id={user_id}\")",
      "message": "Possible SQL injection via string formatting",
      "remediation": "Use parameterized queries"
    }
  ],
  "summary": {
    "by_severity": {"critical": 1, "high": 3, "medium": 5, "low": 2},
    "by_language": {"python": 7, "javascript": 4},
    "by_owasp": {"A05:2025": 3, "A01:2025": 2},
    "total": 11
  }
}
```

### Severity Classification

| Severity | Action Required | SLA |
|----------|-----------------|-----|
| CRITICAL | Block merge, fix immediately | Same day |
| HIGH | Fix before release | Within sprint |
| MEDIUM | Review and plan fix | Next sprint |
| LOW | Track for future | Backlog |

---

## Framework-Specific Rules

### Python Frameworks

| Framework | Semgrep Config | Key Vulnerabilities |
|-----------|---------------|---------------------|
| Django | `p/django` | XSS, CSRF, SQL injection, ORM bypass |
| Flask | `p/flask` | Session security, SSTI, debug mode |
| FastAPI | `p/python` (native support) | Input validation, OAuth2, CORS |

### JavaScript Frameworks

| Framework | Semgrep Config | Key Vulnerabilities |
|-----------|---------------|---------------------|
| React | `p/react` | XSS, dangerouslySetInnerHTML |
| Express | `p/nodejs` | Injection, auth bypass |
| Next.js | `p/nextjs` | SSRF, API routes |

### Other Frameworks

| Framework | Semgrep Config | Key Vulnerabilities |
|-----------|---------------|---------------------|
| Spring | `p/spring` | SpEL injection, auth |
| Rails | `p/rails` | Mass assignment, XSS |
| Laravel | `p/php` | SQL injection, CSRF |

---

## Integration Workflow

### Recommended Order

1. **Prerequisites Check** - Verify tools
2. **Auto-detect Scan** - `semgrep --config=auto`
3. **Language-Specific** - Add framework rules
4. **Pattern Fallback** - If tools unavailable
5. **Manual Review** - CRITICAL/HIGH findings

### Scan Script Example

```bash
#!/bin/bash
echo "=== Multi-Language SAST Report ==="

# Detect languages
echo "Detecting languages..."
find . -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) | head -5

# Universal scan with Semgrep
if command -v semgrep &> /dev/null; then
    echo "Running Semgrep..."
    semgrep scan --config=auto --config=p/security-audit . --json 2>/dev/null | jq '.results | length'
else
    echo "Semgrep not found, using pattern matching..."
fi
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `semgrep: command not found` | `pip install semgrep` or `brew install semgrep` |
| Scan timeout | Use `--exclude` or scan specific dirs |
| Too many results | Filter by severity: `jq 'select(.severity == "ERROR")'` |
| Missing language rules | Check `semgrep registry` for available configs |
| False positives | Create `.semgrepignore` file |

---

## References

- [Semgrep Registry](https://semgrep.dev/explore)
- [Semgrep Framework-Native Analysis](https://semgrep.dev/blog/2024/redefining-security-coverage-for-python-with-framework-native-analysis/)
- [OWASP Top 10:2025](https://owasp.org/Top10/2025/)

---

## Version History

- v0.1.0 (2025-12-11): Initial version - Multi-language support, OWASP 2025, FastAPI native support

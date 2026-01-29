---
name: linter-integration
description: Auto-detects and runs project-specific linters, formatters, and typecheckers. Supports Python (ruff, mypy, black, flake8, pylint) and TypeScript (eslint, tsc, prettier). Uses existing project configuration.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(black:*), Bash(flake8:*), Bash(pylint:*), Bash(eslint:*), Bash(tsc:*), Bash(npx:*), Bash(prettier:*), Bash(uv:*), Bash(npm:*), Bash(pnpm:*), Bash(yarn:*), Bash(command:*), Bash(jq:*), Bash(cat:*), Bash(head:*), Bash(python:*), Bash(node:*)
---

# Linter Integration - Auto-Detect & Run Project Tools

Automatically detects and runs project-configured linters, formatters, and typecheckers to ensure code quality review uses the project's own standards.

---

## Core Principle

**Use the project's existing configuration.** Don't impose external rules - run linters with the configs that the project already has.

---

## Prerequisites Check

**ALWAYS run this check first:**

```bash
echo "=== Linter Tools Availability ==="
echo "--- Python ---"
command -v ruff >/dev/null 2>&1 && echo "OK: ruff $(ruff --version 2>/dev/null | head -1)" || echo "MISSING: ruff"
command -v mypy >/dev/null 2>&1 && echo "OK: mypy $(mypy --version 2>/dev/null)" || echo "MISSING: mypy"
command -v black >/dev/null 2>&1 && echo "OK: black $(black --version 2>/dev/null | head -1)" || echo "OPTIONAL: black"
command -v flake8 >/dev/null 2>&1 && echo "OK: flake8" || echo "OPTIONAL: flake8"
command -v pylint >/dev/null 2>&1 && echo "OK: pylint" || echo "OPTIONAL: pylint"
echo "--- TypeScript/JavaScript ---"
command -v npx >/dev/null 2>&1 && echo "OK: npx (npm)" || echo "MISSING: npx"
command -v eslint >/dev/null 2>&1 && echo "OK: eslint (global)" || echo "INFO: eslint (check local)"
command -v tsc >/dev/null 2>&1 && echo "OK: tsc (global)" || echo "INFO: tsc (check local)"
echo "--- Utilities ---"
command -v jq >/dev/null 2>&1 && echo "OK: jq" || echo "OPTIONAL: jq (JSON formatting)"
```

---

## Project Type Detection

### Step 1: Detect Python Project

```bash
echo "=== Python Project Detection ==="
[ -f "pyproject.toml" ] && echo "FOUND: pyproject.toml (modern Python project)"
[ -f "setup.py" ] && echo "FOUND: setup.py (legacy Python project)"
[ -f "setup.cfg" ] && echo "FOUND: setup.cfg"
[ -f "requirements.txt" ] && echo "FOUND: requirements.txt"
[ -f "uv.lock" ] && echo "FOUND: uv.lock (uv managed)"
[ -f "poetry.lock" ] && echo "FOUND: poetry.lock (Poetry managed)"

# Count Python files
python_files=$(find . -name "*.py" -not -path "./.venv/*" -not -path "./venv/*" -not -path "./.git/*" 2>/dev/null | wc -l)
echo "Python files found: $python_files"
```

### Step 2: Detect Python Linter Configs

```bash
echo "=== Python Linter Configuration ==="

# Ruff (preferred)
[ -f "ruff.toml" ] && echo "FOUND: ruff.toml"
[ -f ".ruff.toml" ] && echo "FOUND: .ruff.toml"
grep -q "\[tool.ruff\]" pyproject.toml 2>/dev/null && echo "FOUND: [tool.ruff] in pyproject.toml"

# Mypy
[ -f "mypy.ini" ] && echo "FOUND: mypy.ini"
[ -f ".mypy.ini" ] && echo "FOUND: .mypy.ini"
grep -q "\[tool.mypy\]" pyproject.toml 2>/dev/null && echo "FOUND: [tool.mypy] in pyproject.toml"

# Flake8
[ -f ".flake8" ] && echo "FOUND: .flake8"
[ -f "setup.cfg" ] && grep -q "\[flake8\]" setup.cfg 2>/dev/null && echo "FOUND: [flake8] in setup.cfg"

# Pylint
[ -f "pylintrc" ] && echo "FOUND: pylintrc"
[ -f ".pylintrc" ] && echo "FOUND: .pylintrc"
[ -f "pyproject.toml" ] && grep -q "\[tool.pylint\]" pyproject.toml 2>/dev/null && echo "FOUND: [tool.pylint] in pyproject.toml"

# Black
[ -f "pyproject.toml" ] && grep -q "\[tool.black\]" pyproject.toml 2>/dev/null && echo "FOUND: [tool.black] in pyproject.toml"
```

### Step 3: Detect TypeScript/JavaScript Project

```bash
echo "=== TypeScript/JavaScript Project Detection ==="
[ -f "package.json" ] && echo "FOUND: package.json"
[ -f "tsconfig.json" ] && echo "FOUND: tsconfig.json (TypeScript)"
[ -f "jsconfig.json" ] && echo "FOUND: jsconfig.json (JavaScript)"

# Count TS/JS files
ts_files=$(find . \( -name "*.ts" -o -name "*.tsx" \) -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null | wc -l)
js_files=$(find . \( -name "*.js" -o -name "*.jsx" \) -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null | wc -l)
echo "TypeScript files found: $ts_files"
echo "JavaScript files found: $js_files"
```

### Step 4: Detect TypeScript Linter Configs

```bash
echo "=== TypeScript/JavaScript Linter Configuration ==="

# ESLint
[ -f ".eslintrc" ] && echo "FOUND: .eslintrc"
[ -f ".eslintrc.js" ] && echo "FOUND: .eslintrc.js"
[ -f ".eslintrc.cjs" ] && echo "FOUND: .eslintrc.cjs"
[ -f ".eslintrc.json" ] && echo "FOUND: .eslintrc.json"
[ -f ".eslintrc.yml" ] && echo "FOUND: .eslintrc.yml"
[ -f "eslint.config.js" ] && echo "FOUND: eslint.config.js (flat config)"
[ -f "eslint.config.mjs" ] && echo "FOUND: eslint.config.mjs (flat config)"

# Prettier
[ -f ".prettierrc" ] && echo "FOUND: .prettierrc"
[ -f ".prettierrc.json" ] && echo "FOUND: .prettierrc.json"
[ -f ".prettierrc.js" ] && echo "FOUND: .prettierrc.js"
[ -f "prettier.config.js" ] && echo "FOUND: prettier.config.js"
[ -f "prettier.config.mjs" ] && echo "FOUND: prettier.config.mjs"

# Check package.json for eslint/prettier config
[ -f "package.json" ] && grep -q '"eslintConfig"' package.json && echo "FOUND: eslintConfig in package.json"
[ -f "package.json" ] && grep -q '"prettier"' package.json && echo "FOUND: prettier config in package.json"
```

---

## Python Linting

### Ruff (Preferred - Fast, All-in-One)

```bash
# Check if ruff is configured
if [ -f "ruff.toml" ] || [ -f ".ruff.toml" ] || grep -q "\[tool.ruff\]" pyproject.toml 2>/dev/null; then
    echo "Running ruff with project configuration..."
    ruff check . --output-format=json 2>/dev/null
else
    echo "Running ruff with default rules..."
    ruff check . --select=E,W,F,I,N,UP,B,A,C4,SIM --output-format=json 2>/dev/null
fi
```

**Parse ruff JSON output:**

```bash
ruff check . --output-format=json 2>/dev/null | jq '.[] | {
  severity: (if .code | startswith("E") then "ERROR"
             elif .code | startswith("F") then "ERROR"
             elif .code | startswith("W") then "WARNING"
             else "INFO" end),
  file: .filename,
  line: .location.row,
  column: .location.column,
  code: .code,
  message: .message,
  fix_available: .fix != null
}'
```

### Mypy (Type Checking)

```bash
# Check if mypy is configured
if [ -f "mypy.ini" ] || [ -f ".mypy.ini" ] || grep -q "\[tool.mypy\]" pyproject.toml 2>/dev/null; then
    echo "Running mypy with project configuration..."
    mypy . --show-error-codes --no-error-summary 2>/dev/null
else
    echo "Running mypy with permissive defaults..."
    mypy . --ignore-missing-imports --show-error-codes --no-error-summary 2>/dev/null
fi
```

**Parse mypy output:**

```bash
mypy . --show-error-codes --no-error-summary 2>/dev/null | grep -E "^[^:]+:[0-9]+:" | head -50
```

### Flake8 (Legacy but Common)

```bash
# Only run if configured (don't mix with ruff)
if [ -f ".flake8" ] || grep -q "\[flake8\]" setup.cfg 2>/dev/null; then
    echo "Running flake8 with project configuration..."
    flake8 . --format=json 2>/dev/null
fi
```

### Pylint (Comprehensive but Slow)

```bash
# Only run if explicitly configured
if [ -f "pylintrc" ] || [ -f ".pylintrc" ] || grep -q "\[tool.pylint\]" pyproject.toml 2>/dev/null; then
    echo "Running pylint with project configuration..."
    pylint --output-format=json . 2>/dev/null | jq '.[] | {
      severity: .type,
      file: .path,
      line: .line,
      column: .column,
      code: .symbol,
      message: .message
    }'
fi
```

---

## TypeScript/JavaScript Linting

### ESLint (Primary)

```bash
# Detect ESLint config type
if [ -f "eslint.config.js" ] || [ -f "eslint.config.mjs" ]; then
    echo "Running ESLint with flat config..."
    npx eslint . --format=json 2>/dev/null
elif [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ] || [ -f ".eslintrc.yml" ] || [ -f ".eslintrc" ]; then
    echo "Running ESLint with legacy config..."
    npx eslint . --format=json 2>/dev/null
else
    echo "No ESLint config found, skipping..."
fi
```

**Parse ESLint JSON output:**

```bash
npx eslint . --format=json 2>/dev/null | jq '.[] | select(.errorCount > 0 or .warningCount > 0) | {
  file: .filePath,
  errors: .errorCount,
  warnings: .warningCount,
  messages: [.messages[] | {
    severity: (if .severity == 2 then "ERROR" else "WARNING" end),
    line: .line,
    column: .column,
    rule: .ruleId,
    message: .message
  }]
}'
```

### TypeScript Compiler (tsc)

```bash
# Only run if tsconfig.json exists
if [ -f "tsconfig.json" ]; then
    echo "Running TypeScript type check..."
    npx tsc --noEmit 2>&1 | grep -E "error TS[0-9]+" | head -50
fi
```

**Parse tsc errors:**

```bash
npx tsc --noEmit 2>&1 | grep -E "^[^(]+\([0-9]+,[0-9]+\): error" | head -50
```

### Prettier (Formatting Check)

```bash
# Only check if prettier is configured
if [ -f ".prettierrc" ] || [ -f ".prettierrc.json" ] || [ -f "prettier.config.js" ]; then
    echo "Checking Prettier formatting..."
    npx prettier --check . 2>&1 | grep -v "Checking" | head -20
fi
```

---

## Unified Output Format

Normalize all linter outputs to this format:

```json
{
  "tool": "ruff|mypy|eslint|tsc|flake8|pylint|prettier",
  "config_source": "pyproject.toml|.eslintrc.json|default",
  "summary": {
    "files_checked": 142,
    "errors": 5,
    "warnings": 23,
    "info": 12
  },
  "issues": [
    {
      "severity": "ERROR|WARNING|INFO",
      "file": "src/service.py",
      "line": 42,
      "column": 10,
      "code": "E501",
      "rule": "line-too-long",
      "message": "Line too long (120 > 88 characters)",
      "fix_available": true,
      "category": "style|type|import|complexity|security"
    }
  ]
}
```

---

## Fallback: No Linter Config

When no project configuration exists, use sensible defaults:

### Python Defaults

```bash
# Minimal ruff checks that most projects should pass
ruff check . --select=E,W,F --ignore=E501 --output-format=json 2>/dev/null

# Permissive mypy
mypy . --ignore-missing-imports --no-strict-optional --show-error-codes 2>/dev/null
```

### TypeScript Defaults

```bash
# Basic tsc check only
npx tsc --noEmit 2>&1 | grep "error TS"
```

---

## Priority Order

Run tools in this order (stop if comprehensive tool found):

### Python

1. **ruff** (if configured) - Comprehensive, fast
2. **mypy** (if configured) - Type checking
3. **flake8** (if configured, no ruff) - Legacy style
4. **pylint** (if configured, no ruff) - Deep analysis

### TypeScript/JavaScript

1. **tsc** (if tsconfig.json) - Type checking
2. **eslint** (if configured) - Style and quality
3. **prettier** (if configured) - Formatting only

---

## Error Categories

Map linter codes to categories:

### Ruff/Flake8 Prefixes

| Prefix | Category | Severity |
|--------|----------|----------|
| E | Style (pycodestyle errors) | ERROR |
| W | Style (pycodestyle warnings) | WARNING |
| F | Logic (pyflakes) | ERROR |
| I | Imports (isort) | WARNING |
| N | Naming (pep8-naming) | WARNING |
| UP | Upgrades (pyupgrade) | INFO |
| B | Bugs (flake8-bugbear) | ERROR |
| C4 | Comprehensions | INFO |
| SIM | Simplify | INFO |

### ESLint Severity

| Value | Meaning | Our Severity |
|-------|---------|--------------|
| 2 | error | ERROR |
| 1 | warn | WARNING |
| 0 | off | - |

### TypeScript Errors

| Pattern | Category | Severity |
|---------|----------|----------|
| TS2304 | Cannot find name | ERROR |
| TS2339 | Property does not exist | ERROR |
| TS7006 | Implicit any | WARNING |
| TS2345 | Argument type mismatch | ERROR |

---

## Integration Report

After running linters, generate summary:

```json
{
  "linter_results": {
    "python": {
      "ruff": {
        "config": "pyproject.toml [tool.ruff]",
        "errors": 3,
        "warnings": 15,
        "top_issues": ["E501 (5)", "F401 (3)", "I001 (7)"]
      },
      "mypy": {
        "config": "pyproject.toml [tool.mypy]",
        "errors": 2,
        "top_issues": ["Missing return type (2)"]
      }
    },
    "typescript": {
      "tsc": {
        "config": "tsconfig.json",
        "errors": 1,
        "top_issues": ["TS2339 (1)"]
      },
      "eslint": {
        "config": ".eslintrc.json",
        "errors": 0,
        "warnings": 8,
        "top_issues": ["@typescript-eslint/no-unused-vars (5)"]
      }
    }
  },
  "blocking_issues": [
    {
      "tool": "mypy",
      "file": "src/api/handler.py",
      "line": 45,
      "message": "Incompatible return type"
    }
  ],
  "recommendations": [
    "Fix 3 type errors before merge",
    "Consider enabling stricter ruff rules"
  ]
}
```

---

## Red Flags - STOP if you

- Run linters without checking for project configuration first
- Override project linter settings with your own preferences
- Ignore linter errors marked as blocking
- Mix conflicting tools (e.g., ruff + flake8 for same checks)

**When these occur:** Go back and use project configuration.

---

## Final Checklist

Before completing linter integration, verify:

- [ ] Detected project type (Python/TypeScript/both)
- [ ] Found linter configuration files
- [ ] Ran linters with project configuration (not defaults)
- [ ] Parsed output into unified format
- [ ] Categorized issues by severity
- [ ] Identified blocking issues (errors)
- [ ] Generated summary with top issues
- [ ] Used fallback only when no config exists

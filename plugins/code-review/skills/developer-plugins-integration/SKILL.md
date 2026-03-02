---
name: developer-plugins-integration
description: Detects installed developer plugins (python-developer, frontend-developer) and project stack, then provides a list of relevant skills to load for code review and fix workflows. Supports Python (FastAPI, SQLAlchemy, Pydantic, asyncio, uv) and Frontend (React, Tailwind, Zustand, TanStack, pnpm).
allowed-tools: Read, Grep, Glob, Bash(grep:*), Bash(cat:*), Bash(head:*), Bash(find:*), Bash(test:*), Bash([), Bash(echo:*)
---

# Developer Plugins Integration - Detection & Skill Loading

Detects installed developer plugins and project stack, then provides a list of relevant skills to load for code review and fix workflows. Acts as the bridge between the code-review plugin and specialized developer plugins (python-developer, frontend-developer).

---

## Overview

This skill is the detection and integration layer between the code-review plugin and developer plugins. It performs three tasks:

1. **Stack Detection** - Identifies which technology stacks are present in the project (Python, Frontend/React)
2. **Plugin Detection** - Checks which developer plugins are installed and available in the current session
3. **Skill Resolution** - Produces a list of skills to load, based on detected stack and available plugins

The output is consumed by the review command, auditors, and fix workflows to ensure framework-specific patterns are enforced during code review.

---

## Stack Detection

### Step 1: Detect Python Stack

**ALWAYS check these files in project root and first-level subdirectories:**

```bash
echo "=== Python Stack Detection ==="
PYTHON_DETECTED=false

# Project root
[ -f "pyproject.toml" ] && echo "FOUND: pyproject.toml (modern Python)" && PYTHON_DETECTED=true
[ -f "setup.py" ] && echo "FOUND: setup.py (legacy Python)" && PYTHON_DETECTED=true
[ -f "setup.cfg" ] && echo "FOUND: setup.cfg (legacy Python)" && PYTHON_DETECTED=true
[ -f "requirements.txt" ] && echo "FOUND: requirements.txt (pip)" && PYTHON_DETECTED=true
[ -f "uv.lock" ] && echo "FOUND: uv.lock (uv)" && PYTHON_DETECTED=true
[ -f "poetry.lock" ] && echo "FOUND: poetry.lock (Poetry)" && PYTHON_DETECTED=true

# First-level subdirectories
for dir in */; do
    [ -f "$dir/pyproject.toml" ] && echo "FOUND: $dir/pyproject.toml" && PYTHON_DETECTED=true
    [ -f "$dir/setup.py" ] && echo "FOUND: $dir/setup.py" && PYTHON_DETECTED=true
    [ -f "$dir/setup.cfg" ] && echo "FOUND: $dir/setup.cfg" && PYTHON_DETECTED=true
    [ -f "$dir/requirements.txt" ] && echo "FOUND: $dir/requirements.txt" && PYTHON_DETECTED=true
    [ -f "$dir/uv.lock" ] && echo "FOUND: $dir/uv.lock" && PYTHON_DETECTED=true
    [ -f "$dir/poetry.lock" ] && echo "FOUND: $dir/poetry.lock" && PYTHON_DETECTED=true
done

echo "Python stack detected: $PYTHON_DETECTED"
```

If **ANY** of these files exist, Python stack is detected.

### Step 2: Detect Python Frameworks

**Only run if Python stack is detected.** Grep dependencies in `pyproject.toml` or `requirements.txt`:

```bash
echo "=== Python Framework Detection ==="

# FastAPI
FASTAPI=false
grep -qi "fastapi" pyproject.toml 2>/dev/null && FASTAPI=true
grep -qi "fastapi" requirements.txt 2>/dev/null && FASTAPI=true
echo "FastAPI: $FASTAPI"

# SQLAlchemy
SQLALCHEMY=false
grep -qi "sqlalchemy" pyproject.toml 2>/dev/null && SQLALCHEMY=true
grep -qi "sqlalchemy" requirements.txt 2>/dev/null && SQLALCHEMY=true
echo "SQLAlchemy: $SQLALCHEMY"

# Pydantic
PYDANTIC=false
grep -qi "pydantic" pyproject.toml 2>/dev/null && PYDANTIC=true
grep -qi "pydantic" requirements.txt 2>/dev/null && PYDANTIC=true
echo "Pydantic: $PYDANTIC"

# asyncio (check source files for async def or asyncio import)
ASYNCIO=false
grep -rq "import asyncio\|from asyncio\|async def" --include="*.py" . 2>/dev/null && ASYNCIO=true
echo "asyncio: $ASYNCIO"

# uv (check for uv.lock)
UV=false
[ -f "uv.lock" ] && UV=true
echo "uv: $UV"
```

### Step 3: Detect Frontend Stack

**ALWAYS check these files:**

```bash
echo "=== Frontend Stack Detection ==="
FRONTEND_DETECTED=false

# Check package.json for React in dependencies
if [ -f "package.json" ]; then
    echo "FOUND: package.json"
    grep -q '"react"' package.json 2>/dev/null && echo "FOUND: react in dependencies" && FRONTEND_DETECTED=true
fi

# Also check first-level subdirectories
for dir in */; do
    if [ -f "$dir/package.json" ]; then
        echo "FOUND: $dir/package.json"
        grep -q '"react"' "$dir/package.json" 2>/dev/null && echo "FOUND: react in $dir/package.json" && FRONTEND_DETECTED=true
    fi
done

# Additional indicators
[ -f "tsconfig.json" ] && echo "FOUND: tsconfig.json (TypeScript)"
[ -f "pnpm-lock.yaml" ] && echo "FOUND: pnpm-lock.yaml (pnpm)"
[ -f "package-lock.json" ] && echo "FOUND: package-lock.json (npm)"
[ -f "yarn.lock" ] && echo "FOUND: yarn.lock (Yarn)"

echo "Frontend stack detected: $FRONTEND_DETECTED"
```

If `package.json` contains `"react"` in dependencies, Frontend stack is detected.

### Step 4: Detect Frontend Frameworks

**Only run if Frontend stack is detected.** Grep `package.json` dependencies and devDependencies:

```bash
echo "=== Frontend Framework Detection ==="

# Tailwind
TAILWIND=false
grep -q '"tailwindcss"\|"@tailwindcss/core"' package.json 2>/dev/null && TAILWIND=true
echo "Tailwind: $TAILWIND"

# Zustand
ZUSTAND=false
grep -q '"zustand"' package.json 2>/dev/null && ZUSTAND=true
echo "Zustand: $ZUSTAND"

# TanStack Query
TANSTACK_QUERY=false
grep -q '"@tanstack/react-query"' package.json 2>/dev/null && TANSTACK_QUERY=true
echo "TanStack Query: $TANSTACK_QUERY"

# TanStack Router
TANSTACK_ROUTER=false
grep -q '"@tanstack/react-router"' package.json 2>/dev/null && TANSTACK_ROUTER=true
echo "TanStack Router: $TANSTACK_ROUTER"

# React Hook Form
REACT_HOOK_FORM=false
grep -q '"react-hook-form"' package.json 2>/dev/null && REACT_HOOK_FORM=true
echo "React Hook Form: $REACT_HOOK_FORM"

# pnpm
PNPM=false
[ -f "pnpm-lock.yaml" ] && PNPM=true
echo "pnpm: $PNPM"
```

---

## Plugin Detection

Check if developer plugins are installed by verifying their skills are available in the current session's skill list.

**How to check:** Look for these skills in the available skills list:

- `python-developer:coding-standards` - Indicates the python-developer plugin is installed
- `frontend-developer:coding-standards` - Indicates the frontend-developer plugin is installed

If a skill is present in the session's skill list, the corresponding plugin is installed and its skills can be loaded.

**Detection approach:**

1. Check the available skills/commands in the current Claude Code session
2. If `python-developer:coding-standards` is available, mark python-developer as INSTALLED
3. If `frontend-developer:coding-standards` is available, mark frontend-developer as INSTALLED
4. Only attempt to load skills from plugins that are confirmed INSTALLED

---

## Output Format

After running detection, produce the following structured report:

```json
{
  "stack_detection": {
    "python": {
      "detected": true,
      "indicators": ["pyproject.toml", "uv.lock"],
      "frameworks": {
        "fastapi": true,
        "sqlalchemy": true,
        "pydantic": true,
        "asyncio": true,
        "uv": true
      }
    },
    "frontend": {
      "detected": true,
      "indicators": ["package.json (react)", "tsconfig.json", "pnpm-lock.yaml"],
      "frameworks": {
        "tailwind": true,
        "zustand": false,
        "tanstack_query": true,
        "tanstack_router": false,
        "react_hook_form": false,
        "pnpm": true
      }
    }
  },
  "plugin_detection": {
    "python_developer": "INSTALLED",
    "frontend_developer": "NOT INSTALLED"
  },
  "skills_to_load": [
    "python-developer:coding-standards",
    "python-developer:tdd-workflow",
    "python-developer:fastapi-patterns",
    "python-developer:sqlalchemy-patterns",
    "python-developer:pydantic-patterns",
    "python-developer:async-python-patterns",
    "python-developer:uv-package-manager"
  ]
}
```

### Skills Resolution Logic

**Python Skills** (load if python-developer INSTALLED AND Python stack detected):

| Skill | Condition |
|-------|-----------|
| `python-developer:coding-standards` | Always (base skill) |
| `python-developer:tdd-workflow` | Always (base skill) |
| `python-developer:fastapi-patterns` | FastAPI detected |
| `python-developer:sqlalchemy-patterns` | SQLAlchemy detected |
| `python-developer:pydantic-patterns` | Pydantic detected |
| `python-developer:async-python-patterns` | asyncio detected |
| `python-developer:uv-package-manager` | uv detected |

**Frontend Skills** (load if frontend-developer INSTALLED AND Frontend stack detected):

| Skill | Condition |
|-------|-----------|
| `frontend-developer:coding-standards` | Always (base skill) |
| `frontend-developer:tdd-workflow` | Always (base skill) |
| `frontend-developer:tailwind-patterns` | Tailwind detected |
| `frontend-developer:zustand-patterns` | Zustand detected |
| `frontend-developer:tanstack-query-patterns` | TanStack Query detected |
| `frontend-developer:tanstack-router-patterns` | TanStack Router detected |
| `frontend-developer:form-patterns` | React Hook Form detected |
| `frontend-developer:pnpm-package-manager` | pnpm detected |

---

## Usage in Code Review

### Review Command

Load this skill at the **START** of the review workflow, **BEFORE** launching auditors. Pass the resolved skill list to all auditor agents so they can apply framework-specific patterns.

```
1. Run developer-plugins-integration (this skill)
2. Collect skills_to_load list
3. Pass list to auditors when spawning them
4. Auditors load relevant skills alongside their standard skills
```

### Code Quality Auditor

Load developer plugin skills **AFTER** standard code quality skills. Apply them as additional review criteria:

- Check code against framework-specific coding standards
- Validate patterns match framework best practices (e.g., FastAPI route patterns, React component patterns)
- Flag anti-patterns specific to the detected frameworks

### Security Auditor

Load developer plugin skills **AFTER** standard security scans. Check framework-specific security patterns:

- FastAPI: authentication middleware, CORS configuration, input validation
- SQLAlchemy: SQL injection prevention, session management
- React: XSS prevention, dangerouslySetInnerHTML usage, sanitization

### Fix Workflows

Load during the **"Analyze Context"** phase. Apply framework patterns when implementing fixes:

- Use framework-idiomatic solutions (e.g., Pydantic validators instead of manual validation)
- Follow framework conventions for file structure and naming
- Apply TDD patterns from the developer plugin's tdd-workflow skill

---

## Graceful Degradation

This skill is designed to fail safely at every level:

### No Developer Plugins Installed

- Standard code review behavior applies
- Zero changes to existing workflow
- No errors, no warnings - simply nothing additional to load
- The `skills_to_load` list is empty

### Plugin Installed but Stack Does Not Match

- If python-developer is installed but no Python stack detected: python skills are NOT loaded
- If frontend-developer is installed but no Frontend stack detected: frontend skills are NOT loaded
- Only the matching plugin + stack combination activates skills

### Skill Invocation Fails

- If a specific skill fails to load (e.g., `python-developer:fastapi-patterns` is unavailable): log as unavailable, continue without it
- Never block the review workflow due to a missing optional skill
- Report unavailable skills in the output for visibility

```json
{
  "skills_to_load": [
    "python-developer:coding-standards",
    "python-developer:tdd-workflow"
  ],
  "skills_unavailable": [
    {
      "skill": "python-developer:fastapi-patterns",
      "reason": "Skill not found in plugin"
    }
  ]
}
```

---

## Red Flags - STOP if you

- Skip stack detection and assume which plugins to load
- Load developer plugin skills without verifying the plugin is installed
- Load framework-specific skills without detecting the framework in the project
- Block the review workflow because a developer plugin is missing
- Ignore the graceful degradation rules

**When these occur:** Go back and run the full detection workflow.

---

## Final Checklist

Before completing developer plugins integration, verify:

- [ ] Checked for Python stack indicators (pyproject.toml, setup.py, requirements.txt, etc.)
- [ ] Checked for Frontend stack indicators (package.json with react)
- [ ] Detected Python frameworks (FastAPI, SQLAlchemy, Pydantic, asyncio, uv)
- [ ] Detected Frontend frameworks (Tailwind, Zustand, TanStack Query/Router, React Hook Form, pnpm)
- [ ] Verified plugin availability via session skill list
- [ ] Produced skills_to_load list with correct conditional logic
- [ ] Applied graceful degradation (no errors if plugins missing)
- [ ] Output structured report with all detection results

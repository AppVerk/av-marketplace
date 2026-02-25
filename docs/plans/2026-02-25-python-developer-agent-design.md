# Design: Python Developer Agent (`python-developer:developer`)

**Date:** 2026-02-25
**Plugin:** python-developer (v2.0.0 -> v2.1.0)
**Approach:** Agent as lightweight router to existing skills

## Problem

When superpowers dispatches agents for fixing/implementing Python code, it uses `code-review:fix-auto` — a generic fixer that doesn't know about Python Developer's coding standards, TDD workflow, or stack-specific patterns (FastAPI, SQLAlchemy, Pydantic). This happens because Python Developer has no agents, only skills and a command.

## Solution

Create a new agent `python-developer:developer` that:

- Is autonomously dispatched by Claude when working on Python projects (based on agent description)
- Follows the full Python Developer workflow: coding standards, stack detection, TDD cycle, quality gates
- Handles three modes: fix, implementation, refactoring
- Loads existing skills dynamically — no duplication of logic

## Agent Description (for system prompt)

> Expert Python developer agent for implementing features, fixing issues, and refactoring code. Enforces Python coding standards (type hints, absolute imports, X | None), TDD workflow (tests before code, fakes over mocks, 80%+ coverage), and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic, async). Use this agent instead of general-purpose agents when working on Python projects.

## Workflow (6 Phases)

### Phase 1: Parse input & detect mode

From `$ARGUMENTS`, detect mode:

- **fix** — keywords: issue, bug, error, fix, broken, failing, vulnerability, CWE, OWASP, severity, remediation
- **refactor** — keywords: refactor, rename, extract, move, split, merge, clean up, restructure
- **implement** — default (new feature, endpoint, service, etc.)

Extract key info: file location, problem/task description.

### Phase 2: Load coding standards & detect stack

- Load HARD-RULES from `coding-standards` (always)
- Read `pyproject.toml`, scan imports in `src/`/`app/`
- Discover project commands from `CLAUDE.md` -> `README.md` -> `Makefile` -> `pyproject.toml`
- Record: test command, typecheck command, lint command

### Phase 3: Load stack-specific skills

Based on detected stack:

- FastAPI -> `fastapi-patterns`
- SQLAlchemy -> `sqlalchemy-patterns`
- Pydantic -> `pydantic-patterns`
- async -> `async-python-patterns`
- dependency changes -> `uv-package-manager`
- Always load `tdd-workflow`

### Phase 4: TDD cycle

- **Fix mode:** write test reproducing the problem -> implement fix -> verify
- **Implement mode:** write tests (happy path, edge cases, errors) -> implement -> verify
- **Refactor mode:** verify existing tests pass -> refactor -> verify tests still pass; if no tests exist, write them first

### Phase 5: Quality gates

Run all gates using commands discovered in Phase 2:

1. Typecheck
2. Full test suite
3. Linting

All must pass. Max 3 fix iterations on failure.

### Phase 6: Report

```
## Developer Report: [MODE] [Title]

**Status:** [complete | partial | failed]
**Mode:** [Fix | Implement | Refactor]

**Skills Loaded:**
- coding-standards, tdd-workflow, [stack-specific...]

**Changes Made:**
- `path/to/file.py:lines` - [description]

**Tests:**
- [New/modified tests with coverage description]

**Quality Gates:**
| Gate | Result | Command |
|------|--------|---------|
| Typecheck | Pass/Fail | `command used` |
| Tests | Pass/Fail | `command used` |
| Lint | Pass/Fail | `command used` |

**Remaining Issues:** [if any]
```

Changes remain uncommitted.

## Allowed Tools

```yaml
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(coverage:*), Bash(alembic:*), Bash(git:*), Bash(pip:*), Skill, TaskCreate, TaskUpdate, TaskList
```

Key differences vs `code-review:fix-auto`:

- Has `Skill` tool — can load python-developer skills dynamically
- Has `make`, `uv`, `coverage`, `basedpyright`, `alembic` — developer toolchain
- No `semgrep`, `bandit`, `eslint`, `tsc` — security/SAST is code-review's domain

## Integration

**What changes:**
- New file: `plugins/python-developer/agents/developer.md`
- Version bump: `plugin.json` from 2.0.0 to 2.1.0

**What stays the same:**
- `/develop` command — interactive workflow with user, unchanged
- `/review` + `/fix-report` — still use `code-review:fix-auto` for non-Python projects
- All existing skills — agent consumes them, no modifications
- Claude selects `python-developer:developer` over `code-review:fix-auto` for Python projects based on agent description

# Python Developer Plugin v2.0 — Design Document

**Date:** 2026-02-18
**Status:** Approved
**Plugin:** python-developer (currently v1.1.0 → target v2.0.0)

## Context

The python-developer plugin provides skills (coding standards, TDD, uv, async patterns) that guide Claude's Python code generation for AppVerk projects. The stack is FastAPI + SQLAlchemy + Pydantic with uv as package manager.

### Problem Statement

1. Claude does not automatically activate plugin skills — users must manually force their use
2. Even when skills are loaded, Claude ignores specific rules (e.g., writes mocks instead of fakes, puts imports inside functions)
3. The plugin lacks stack-specific guidance for FastAPI, SQLAlchemy, and Pydantic
4. No active command to orchestrate the development workflow

### Root Cause Analysis

Investigation revealed structural issues preventing proper skill activation:

1. **Directory typo**: `.claude-pluign/` instead of `.claude-plugin/` — may break plugin registration
2. **Missing `allowed-tools`** in skill frontmatter — code-review and web-auditor declare this, python-developer does not
3. **Vague descriptions** — "Universal coding standards" vs code-review's "Auto-detects and runs project-specific linters"
4. **Overly broad skills** — each skill covers an entire domain instead of being narrowly focused
5. **No commands/agents** — no active entrypoint to enforce skill usage

## Design

### Etap 1: Structural Fixes

#### 1.1 Fix directory typo

Rename `.claude-pluign/` → `.claude-plugin/`.

#### 1.2 Add `allowed-tools` to every SKILL.md

Each skill declares tools it can use in frontmatter, matching the pattern from code-review:

```yaml
---
name: coding-standards
description: Enforces Python coding rules...
allowed-tools: Read, Grep, Glob, Bash(ruff:*, mypy:*, basedpyright:*, make:*)
---
```

#### 1.3 Rewrite descriptions to be action-oriented

| Skill | Old description | New description |
|-------|----------------|-----------------|
| coding-standards | Universal coding standards, best practices, and patterns for Python development | Enforces Python coding rules: type hints, imports, naming, error handling, and project conventions for AppVerk projects |
| tdd-workflow | Use this skill when writing new features, fixing bugs, or refactoring code. Enforces test-driven development with 80%+ coverage | Enforces test-driven development: writes tests before code, uses fakes over mocks, maintains 80%+ coverage |
| uv-package-manager | Master the uv package manager for fast Python dependency management... | Manages Python dependencies and environments with uv: adds packages, syncs lockfiles, pins versions |
| async-python-patterns | Master Python asyncio, concurrent programming, and async/await patterns... | Guides async/await implementation: asyncio patterns, concurrent I/O, task management, synchronization |

#### 1.4 Add HARD RULES sections

Each skill gets a "HARD RULES" section at the top with non-negotiable directives:

```markdown
## HARD RULES

- NEVER put imports inside functions or methods
- NEVER use `Optional[X]` — use `X | None`
- ALWAYS use absolute imports, NEVER relative
- ALWAYS run `make typecheck` and `make test` after changes
```

Format: short, imperative sentences with `NEVER` / `ALWAYS` / `MUST`.

### Etap 2: Skill Refinement and New Skills

#### 2.1 `coding-standards` — sharpen

- Remove testing rules (move to `tdd-workflow`)
- Add HARD RULES section at top
- Strengthen rules that Claude ignores (imports, types, styles)

#### 2.2 `tdd-workflow` — strengthen

- Absorb ALL testing rules from `coding-standards`
- Add HARD RULES: `ALWAYS use fakes over mocks`, `NEVER put imports inside functions/methods`, `ALWAYS write tests before implementation`
- Add concrete patterns for FastAPI testing (`httpx.AsyncClient`, `TestClient`)

#### 2.3 `uv-package-manager` — minor update

- Update frontmatter only (allowed-tools, description)
- Content is adequate as reference guide

#### 2.4 `async-python-patterns` — minor update

- Update frontmatter
- Light trimming of redundant examples

#### 2.5 NEW: `fastapi-patterns`

Stack-specific skill for FastAPI development:

- Endpoint patterns (router structure, dependency injection)
- Request/Response models with Pydantic
- Error handling patterns, status codes
- Background tasks, lifespan events
- Middleware patterns
- HARD RULES for FastAPI conventions

#### 2.6 NEW: `sqlalchemy-patterns`

Stack-specific skill for SQLAlchemy:

- Async SQLAlchemy with FastAPI integration
- Repository pattern, session management
- Alembic migrations workflow
- Relationships, eager/lazy loading
- Query optimization patterns
- HARD RULES for database access

#### 2.7 NEW: `pydantic-patterns`

Stack-specific skill for Pydantic:

- Model design and validators
- Settings management (BaseSettings)
- FastAPI schema integration
- Custom types, discriminated unions
- Serialization/deserialization patterns
- HARD RULES for model design

### Etap 3: Command `/develop`

#### 3.1 Concept

A command that orchestrates the development workflow by forcing appropriate skill usage:

```
/develop [task description]
```

#### 3.2 Workflow

```
/develop "Add endpoint for creating users"
  |
  v
1. Analyze task → identify required skills
2. Load coding-standards + tdd-workflow + relevant stack skills
3. TDD: write tests first (using fakes, not mocks)
4. Implement following loaded patterns
5. Verify: make typecheck && make test
6. Summarize changes
```

#### 3.3 Skill Selection Logic

The command prompt instructs Claude to:

- ALWAYS load `coding-standards`
- ALWAYS load `tdd-workflow` when writing/modifying code
- Load `fastapi-patterns` when working with endpoints, routers, middleware
- Load `sqlalchemy-patterns` when working with models, queries, migrations
- Load `pydantic-patterns` when working with schemas, validation, settings
- Load `async-python-patterns` when working with async operations
- Load `uv-package-manager` when managing dependencies

### Etap 4: New Stack Skills Content (Future)

Detailed content for `fastapi-patterns`, `sqlalchemy-patterns`, and `pydantic-patterns` will be developed based on AppVerk's actual project patterns. This requires reviewing existing AppVerk Python projects to extract real conventions.

## File Structure (Target)

```
plugins/python-developer/
├── .claude-plugin/           ← fixed from .claude-pluign/
│   └── plugin.json
├── commands/
│   └── develop.md            ← NEW: /develop command
└── skills/
    ├── coding-standards/
    │   └── SKILL.md          ← sharpened
    ├── tdd-workflow/
    │   └── SKILL.md          ← strengthened
    ├── uv-package-manager/
    │   └── SKILL.md          ← minor update
    ├── async-python-patterns/
    │   └── SKILL.md          ← minor update
    ├── fastapi-patterns/
    │   └── SKILL.md          ← NEW
    ├── sqlalchemy-patterns/
    │   └── SKILL.md          ← NEW
    └── pydantic-patterns/
        └── SKILL.md          ← NEW
```

## Version Plan

- **v1.2.0** — Etap 1: Structural fixes (typo, frontmatter, descriptions, HARD RULES)
- **v1.3.0** — Etap 2: Skill refinement + new stack skills
- **v2.0.0** — Etap 3: `/develop` command + full integration

## Success Criteria

- Claude automatically activates relevant skills when working on Python code
- HARD RULES are consistently followed (no mocks where fakes should be, no imports in functions)
- Stack-specific skills produce idiomatic FastAPI/SQLAlchemy/Pydantic code
- `/develop` command provides guided workflow that enforces all conventions

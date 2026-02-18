# Python Developer v2.0 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix structural issues preventing skill activation, sharpen existing skills with HARD RULES, add stack-specific skills (FastAPI, SQLAlchemy, Pydantic), and create `/develop` command to orchestrate the workflow.

**Architecture:** Plugin stays skills-first — each skill is a self-contained markdown file with frontmatter metadata (name, description, allowed-tools). A new `/develop` command acts as orchestrator that forces Claude to load and follow the right skills for the task. No agents needed.

**Tech Stack:** Claude Code plugin system (markdown skills, commands, plugin.json)

**Reference files for patterns:**
- Commands format: `plugins/code-review/commands/review.md` (frontmatter with allowed-tools, description, argument-hint)
- Skills format: `plugins/code-review/skills/architecture-analysis/SKILL.md` (frontmatter with allowed-tools)
- Plugin config: `plugins/code-review/.claude-plugin/plugin.json`

---

## Phase 1: Structural Fixes (v1.2.0)

### Task 1: Fix plugin directory typo

**Files:**
- Rename: `plugins/python-developer/.claude-pluign/` → `plugins/python-developer/.claude-plugin/`

**Step 1: Rename the directory**

```bash
cd /Users/mef1st0/Projects/claude-code/av-marketplace
mv plugins/python-developer/.claude-pluign plugins/python-developer/.claude-plugin
```

**Step 2: Verify the fix**

```bash
ls plugins/python-developer/.claude-plugin/plugin.json
```

Expected: file exists, no error.

**Step 3: Commit**

```bash
git add plugins/python-developer/
git commit -m "fix(python-developer): rename .claude-pluign to .claude-plugin"
```

---

### Task 2: Update coding-standards frontmatter and add HARD RULES

**Files:**
- Modify: `plugins/python-developer/skills/coding-standards/SKILL.md`

**Step 1: Replace the frontmatter**

Replace the current frontmatter (lines 1-4):

```yaml
---
name: coding-standards
description: Universal coding standards, best practices, and patterns for Python development.
---
```

With:

```yaml
---
name: coding-standards
description: Enforces Python coding rules: type hints, imports, naming, error handling, and project conventions for AppVerk projects. Activates when writing or reviewing Python code.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*)
---
```

**Step 2: Add HARD RULES section**

Insert immediately after the frontmatter and the `# Python Coding Rules` title (before the existing content), add:

```markdown
<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER put imports inside functions or methods — ALL imports go at the top of the file
- NEVER use `Optional[X]` or import `Optional` — ALWAYS use `X | None`
- NEVER use relative imports (`from .module import ...`) — ALWAYS use absolute imports
- NEVER use bare `except:` or `except Exception:` without re-raising — catch specific exceptions
- NEVER use mutable default arguments (`def f(x=[])`) — use `None` and create inside function
- NEVER leave unused imports or variables — remove them immediately
- ALWAYS annotate all function parameters and return types explicitly
- ALWAYS use `pathlib.Path` instead of string paths
- ALWAYS run `make typecheck` and `make test` after any code change
- ALWAYS use `uv run` to execute any Python command
</HARD-RULES>
```

**Step 3: Remove testing rules from coding-standards**

Remove the entire `## Testing` section (from `## Testing` through the end of `### Mocking` subsection, including all subsections: `### General Testing Principles`, `### Test Organization`, `### Mocking`). These rules will be consolidated into `tdd-workflow` in Task 3.

Keep only a brief cross-reference in its place:

```markdown
## Testing

See the `tdd-workflow` skill for all testing rules, patterns, and conventions.
```

**Step 4: Verify the file is valid markdown**

Read the modified file and verify it's well-formed (no broken formatting).

**Step 5: Commit**

```bash
git add plugins/python-developer/skills/coding-standards/SKILL.md
git commit -m "feat(python-developer): sharpen coding-standards with HARD RULES and frontmatter"
```

---

### Task 3: Update tdd-workflow frontmatter, add HARD RULES, absorb testing rules

**Files:**
- Modify: `plugins/python-developer/skills/tdd-workflow/SKILL.md`

**Step 1: Replace the frontmatter**

Replace the current frontmatter (lines 1-4):

```yaml
---
name: tdd-workflow
description: Use this skill when writing new features, fixing bugs, or refactoring code. Enforces test-driven development with 80%+ coverage including unit, functional, and integration tests.
---
```

With:

```yaml
---
name: tdd-workflow
description: Enforces test-driven development: writes tests before code, uses fakes over mocks, maintains 80%+ coverage. Activates when writing new features, fixing bugs, or refactoring Python code.
allowed-tools: Read, Grep, Glob, Bash(pytest:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(coverage:*)
---
```

**Step 2: Add HARD RULES section**

Insert immediately after the frontmatter and the `# Test-Driven Development Workflow` title (before `This skill ensures...`), add:

```markdown
<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS write tests BEFORE implementation code — no exceptions
- ALWAYS use Fake implementations (in-memory, simplified) for dependencies — NEVER use unittest.mock or pytest-mock for internal dependencies
- ONLY use mocks for external I/O: 3rd party APIs (OpenAI, Stripe), real database calls in unit tests, network requests
- NEVER put imports inside test functions or methods — ALL imports go at the top of the test file
- NEVER write tests that depend on other tests — each test sets up its own data via fixtures
- NEVER use `assert False` — use `raise AssertionError("explanation")` instead
- ALWAYS run the full test suite (`make test` or `uv run pytest`) not just specific tests
- ALWAYS verify 80%+ coverage before considering work complete
- ALWAYS use `pytest.mark.parametrize` for similar test cases instead of duplicating tests
- ALWAYS use factory fixtures for creating similar data objects
</HARD-RULES>
```

**Step 3: Absorb testing rules from coding-standards**

After the existing content (before the `---` at the bottom), add a new section with the testing rules that were removed from `coding-standards`:

```markdown
## Test Code Standards

These standards apply to all test code (absorbed from coding-standards):

### General Testing Principles

- Write code amenable to unit testing with no hidden I/O or tight coupling.
- Keep typing in tests where practical, even if excluded from type checks.
- Don't write trivial tests that test obvious functionality (e.g., testing Pydantic model instantiation).
- Never use `assert False`. Use `raise AssertionError("explanation")` instead.
- Prefer running the whole test suite instead of specific tests.

### Test Organization

- For similar data objects, use factory fixtures.
- Combine similar test cases using `pytest.mark.parametrize`.
- Any environment variables setup should be done in conftest using monkeypatch fixture, unless not possible.
- Test directory layout:
  - `tests/unit` — fast, isolated tests of pure logic
  - `tests/integration` — tests that cross process/service boundaries (DB, network, etc.)
  - `tests/functional` — blackbox tests of the API or feature behavior with faked dependencies
  - `tests/e2e` — end-to-end tests that exercise the system as a whole
- Mirror the source tree under `src/` starting after the repository's domain package (drop the top-level package folder). For code in:
  - `src/<domain_package>/<subpath>/module.py`
  write tests in:
  - `tests/<kind>/<subpath>/test_module.py`
  where `<kind>` is one of `unit` | `integration` | `functional` | `e2e`.
- File naming: `test_<module>.py` for module-level tests; use `test_<thing>_<behavior>.py` when clearer.
- Keep category-specific conftest, fixtures, and data near the tests:
  - `tests/conftest.py` for global fixtures
  - `tests/<kind>/conftest.py` for category-scoped fixtures

### Mocking Rules

- Avoid mocks unless for external I/O like 3rd party API calls, database operations, etc.
- For internal dependencies, ALWAYS create Fake implementations instead.

| Scenario | Use |
|----------|-----|
| Repository/data access | Fake (in-memory implementation) |
| Business logic dependencies | Fake (simplified implementation) |
| 3rd party API calls (OpenAI, Stripe) | Mock |
| Database operations in integration tests | Test database with rollback |
| External HTTP requests | Mock or fake HTTP server |
```

**Step 4: Verify the file is valid markdown**

Read the modified file and verify it's well-formed.

**Step 5: Commit**

```bash
git add plugins/python-developer/skills/tdd-workflow/SKILL.md
git commit -m "feat(python-developer): strengthen tdd-workflow with HARD RULES and absorbed testing rules"
```

---

### Task 4: Update uv-package-manager frontmatter

**Files:**
- Modify: `plugins/python-developer/skills/uv-package-manager/SKILL.md`

**Step 1: Replace the frontmatter only**

Replace the current frontmatter (lines 1-4):

```yaml
---
name: uv-package-manager
description: Master the uv package manager for fast Python dependency management, virtual environments, and modern Python project workflows. Use when setting up Python projects, managing dependencies, or optimizing Python development workflows with uv.
---
```

With:

```yaml
---
name: uv-package-manager
description: Manages Python dependencies and environments with uv: adds packages, syncs lockfiles, pins versions. Activates when setting up projects, managing dependencies, or working with virtual environments.
allowed-tools: Read, Grep, Glob, Bash(uv:*), Bash(python:*), Bash(pip:*), Bash(make:*)
---
```

**Step 2: Commit**

```bash
git add plugins/python-developer/skills/uv-package-manager/SKILL.md
git commit -m "feat(python-developer): update uv-package-manager frontmatter"
```

---

### Task 5: Update async-python-patterns frontmatter

**Files:**
- Modify: `plugins/python-developer/skills/async-python-patterns/SKILL.md`

**Step 1: Replace the frontmatter only**

Replace the current frontmatter (lines 1-4):

```yaml
---
name: async-python-patterns
description: Master Python asyncio, concurrent programming, and async/await patterns for high-performance applications. Use when building async APIs, concurrent systems, or I/O-bound applications requiring non-blocking operations.
---
```

With:

```yaml
---
name: async-python-patterns
description: Guides async/await implementation: asyncio patterns, concurrent I/O, task management, synchronization. Activates when building async APIs, concurrent systems, or non-blocking applications.
allowed-tools: Read, Grep, Glob, Bash(python:*), Bash(uv:*), Bash(make:*)
---
```

**Step 2: Commit**

```bash
git add plugins/python-developer/skills/async-python-patterns/SKILL.md
git commit -m "feat(python-developer): update async-python-patterns frontmatter"
```

---

### Task 6: Bump plugin version to 1.2.0 and update docs

**Files:**
- Modify: `plugins/python-developer/.claude-plugin/plugin.json`
- Modify: `docs/plugins/python-developer.md`
- Modify: `README.md`

**Step 1: Update plugin.json**

Replace the entire content of `plugins/python-developer/.claude-plugin/plugin.json`:

```json
{
  "name": "python-developer",
  "description": "Enforces Python best practices, coding standards, TDD workflow, and modern tooling for AppVerk projects",
  "version": "1.2.0"
}
```

**Step 2: Update docs/plugins/python-developer.md**

Update the version line from `1.1.0` to `1.2.0`.

**Step 3: Update README.md**

Update the Python Developer row in the plugins table — change version from `1.1.0` to `1.2.0` and update the description to match plugin.json.

**Step 4: Commit**

```bash
git add plugins/python-developer/.claude-plugin/plugin.json docs/plugins/python-developer.md README.md
git commit -m "chore(release): bump python-developer to 1.2.0"
```

---

## Phase 2: New Stack Skills (v1.3.0)

### Task 7: Create fastapi-patterns skill

**Files:**
- Create: `plugins/python-developer/skills/fastapi-patterns/SKILL.md`

**Step 1: Create the skill directory and file**

```bash
mkdir -p plugins/python-developer/skills/fastapi-patterns
```

**Step 2: Write the skill content**

Create `plugins/python-developer/skills/fastapi-patterns/SKILL.md` with:

- Frontmatter: name, description ("Enforces FastAPI patterns: endpoint structure, dependency injection, error handling, middleware. Activates when working with FastAPI routers, endpoints, or middleware."), allowed-tools
- `<HARD-RULES>` section covering: router organization, dependency injection patterns, response model usage, status codes, error handling
- Sections covering:
  - **Router Structure** — one router per domain, prefix conventions, tags
  - **Dependency Injection** — `Depends()`, session deps, auth deps, nested deps
  - **Request/Response Models** — Pydantic input/output schemas, separate Create/Update/Response models
  - **Error Handling** — `HTTPException`, custom exception handlers, error response format
  - **Background Tasks** — `BackgroundTasks`, when to use vs Celery/ARQ
  - **Lifespan Events** — `@asynccontextmanager` lifespan, startup/shutdown
  - **Middleware** — CORS, custom middleware patterns
  - **Testing FastAPI** — `httpx.AsyncClient`, `TestClient`, `app.dependency_overrides`

**Important:** Content should be prescriptive patterns with code examples, NOT a FastAPI tutorial. Focus on "do it THIS way" not "here's what FastAPI can do". Each section should have a concrete code example showing the AppVerk-approved pattern.

Reference the latest FastAPI docs for accuracy. Use `context7` MCP tool to fetch current FastAPI documentation patterns.

**Step 3: Commit**

```bash
git add plugins/python-developer/skills/fastapi-patterns/
git commit -m "feat(python-developer): add fastapi-patterns skill"
```

---

### Task 8: Create sqlalchemy-patterns skill

**Files:**
- Create: `plugins/python-developer/skills/sqlalchemy-patterns/SKILL.md`

**Step 1: Create the skill directory**

```bash
mkdir -p plugins/python-developer/skills/sqlalchemy-patterns
```

**Step 2: Write the skill content**

Create `plugins/python-developer/skills/sqlalchemy-patterns/SKILL.md` with:

- Frontmatter: name, description ("Enforces SQLAlchemy patterns: async sessions, repository pattern, Alembic migrations, query optimization. Activates when working with database models, queries, or migrations."), allowed-tools
- `<HARD-RULES>` section covering: async sessions, repository pattern usage, migration conventions, query patterns
- Sections covering:
  - **Model Definition** — declarative base, `MappedAsBase`, type annotations, `Mapped[type]`
  - **Async Session Management** — `async_sessionmaker`, session dependency for FastAPI, context managers
  - **Repository Pattern** — base repository, CRUD operations, query methods, type-safe returns
  - **Relationships** — `relationship()`, lazy/eager loading, `selectinload` for async
  - **Alembic Migrations** — auto-generation, manual migrations, naming conventions, async support
  - **Query Patterns** — `select()`, filtering, joining, pagination, sorting
  - **Query Optimization** — avoiding N+1, `selectinload`/`joinedload`, bulk operations
  - **Testing with SQLAlchemy** — test database setup, session fixtures, rollback strategy

**Important:** Focus on async SQLAlchemy 2.0+ patterns exclusively. Do NOT include legacy 1.x patterns. Use `context7` MCP tool to fetch current SQLAlchemy documentation.

**Step 3: Commit**

```bash
git add plugins/python-developer/skills/sqlalchemy-patterns/
git commit -m "feat(python-developer): add sqlalchemy-patterns skill"
```

---

### Task 9: Create pydantic-patterns skill

**Files:**
- Create: `plugins/python-developer/skills/pydantic-patterns/SKILL.md`

**Step 1: Create the skill directory**

```bash
mkdir -p plugins/python-developer/skills/pydantic-patterns
```

**Step 2: Write the skill content**

Create `plugins/python-developer/skills/pydantic-patterns/SKILL.md` with:

- Frontmatter: name, description ("Enforces Pydantic patterns: model design, validators, settings management, FastAPI schema integration. Activates when working with data models, validation, or configuration."), allowed-tools
- `<HARD-RULES>` section covering: model design rules, validator conventions, settings patterns
- Sections covering:
  - **Model Design** — field definitions, `Field()` with constraints, nested models, model composition
  - **Validators** — `@field_validator`, `@model_validator`, `BeforeValidator`, `AfterValidator`
  - **Serialization** — `model_dump()`, `model_dump_json()`, `model_validate()`, custom serializers
  - **Settings Management** — `BaseSettings`, `.env` files, settings dependencies, nested settings
  - **FastAPI Integration** — request/response schemas, separate Create/Update/Response models, `model_config`
  - **Custom Types** — `Annotated` types, custom validators as types, discriminated unions
  - **Error Handling** — `ValidationError`, custom error messages, error response formatting

**Important:** Pydantic v2 patterns exclusively. No v1 patterns. Use `context7` MCP tool to fetch current Pydantic documentation.

**Step 3: Commit**

```bash
git add plugins/python-developer/skills/pydantic-patterns/
git commit -m "feat(python-developer): add pydantic-patterns skill"
```

---

### Task 10: Update docs and bump to v1.3.0

**Files:**
- Modify: `plugins/python-developer/.claude-plugin/plugin.json`
- Modify: `docs/plugins/python-developer.md`
- Modify: `README.md`

**Step 1: Update plugin.json version to 1.3.0**

**Step 2: Update docs/plugins/python-developer.md**

- Bump version to 1.3.0
- Add new sections for the 3 new skills (fastapi-patterns, sqlalchemy-patterns, pydantic-patterns) following the same format as existing skill descriptions

**Step 3: Update README.md**

- Update version and description in the plugins table

**Step 4: Commit**

```bash
git add plugins/python-developer/.claude-plugin/plugin.json docs/plugins/python-developer.md README.md
git commit -m "chore(release): bump python-developer to 1.3.0"
```

---

## Phase 3: /develop Command (v2.0.0)

### Task 11: Create /develop command

**Files:**
- Create: `plugins/python-developer/commands/develop.md`

**Step 1: Create the commands directory**

```bash
mkdir -p plugins/python-developer/commands
```

**Step 2: Write the command**

Create `plugins/python-developer/commands/develop.md` with:

**Frontmatter:**
```yaml
---
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(coverage:*), Bash(alembic:*), Bash(git:*), Bash(pip:*)
description: Python development workflow enforcing coding standards, TDD, and stack-specific patterns. Loads the right skills automatically.
argument-hint: <task description>
---
```

**Command body structure:**

The command should:

1. **Parse $ARGUMENTS** as task description
2. **Analyze the project** — detect if it uses FastAPI, SQLAlchemy, Pydantic (check pyproject.toml, imports)
3. **Load skills based on context:**
   - ALWAYS: `python-developer:coding-standards` (invoke with Skill tool)
   - If writing/modifying code: `python-developer:tdd-workflow` (invoke with Skill tool)
   - If FastAPI detected or task involves endpoints: `python-developer:fastapi-patterns` (invoke with Skill tool)
   - If SQLAlchemy detected or task involves DB: `python-developer:sqlalchemy-patterns` (invoke with Skill tool)
   - If Pydantic detected or task involves models/schemas: `python-developer:pydantic-patterns` (invoke with Skill tool)
   - If task involves async: `python-developer:async-python-patterns` (invoke with Skill tool)
   - If task involves dependencies: `python-developer:uv-package-manager` (invoke with Skill tool)
4. **Enforce TDD workflow:**
   - Write tests first
   - Run tests (expect failure)
   - Implement code
   - Run tests (expect pass)
   - Run `make typecheck`
   - Run `make test`
5. **Final verification checklist** before declaring work complete

**Important:** The command must use the `Skill` tool to invoke skills by their fully-qualified name (`python-developer:skill-name`). Study how `code-review:review` invokes its subagents as a pattern, but adapt for skill invocation instead.

**Step 3: Commit**

```bash
git add plugins/python-developer/commands/
git commit -m "feat(python-developer): add /develop command"
```

---

### Task 12: Update docs and bump to v2.0.0

**Files:**
- Modify: `plugins/python-developer/.claude-plugin/plugin.json`
- Modify: `docs/plugins/python-developer.md`
- Modify: `README.md`

**Step 1: Update plugin.json version to 2.0.0**

**Step 2: Update docs/plugins/python-developer.md**

- Bump version to 2.0.0
- Add section for the `/develop` command with usage examples:
  ```
  /develop Add a new endpoint for user registration
  /develop Fix the N+1 query in the orders list endpoint
  /develop Refactor the payment service to use the repository pattern
  ```

**Step 3: Update README.md**

- Update version and description in the plugins table
- Add `/develop` to the description

**Step 4: Commit**

```bash
git add plugins/python-developer/.claude-plugin/plugin.json docs/plugins/python-developer.md README.md
git commit -m "chore(release): bump python-developer to 2.0.0"
```

---

## Summary

| Phase | Version | Tasks | Description |
|-------|---------|-------|-------------|
| 1 | v1.2.0 | 1-6 | Fix typo, update frontmatter, add HARD RULES, sharpen existing skills |
| 2 | v1.3.0 | 7-10 | Add fastapi-patterns, sqlalchemy-patterns, pydantic-patterns |
| 3 | v2.0.0 | 11-12 | Add `/develop` command |

Total: 12 tasks, 3 phases, 3 releases.

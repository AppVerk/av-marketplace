---
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(coverage:*), Bash(alembic:*), Bash(git:*), Bash(pip:*)
description: Python development workflow enforcing coding standards, TDD, and stack-specific patterns. Loads the right skills automatically.
argument-hint: <task description>
---

# Python Development Workflow

You are executing a structured Python development workflow. Follow every step in order. Do not skip steps.

## Task

**$ARGUMENTS**

---

## Step 1: Load Coding Standards (MANDATORY)

Before doing anything else, load the base coding standards skill:

```
Use the Skill tool with:
  skill: "python-developer:coding-standards"
```

**You MUST load this skill first. All code you write must follow its HARD-RULES.**

---

## Step 2: Analyze the Project

### 2a. Discover project commands

**Read these files first (in order of priority) to find the actual project commands for testing, linting, and typechecking:**

1. **CLAUDE.md** (root or `.claude/`) — primary source of truth for AI workflows
2. **README.md** — look for "Development", "Contributing", "Getting Started" sections with commands
3. **Makefile** — check for available targets (`make test`, `make typecheck`, `make lint`, etc.)
4. **pyproject.toml** `[tool.taskipy.tasks]` or `[project.scripts]` — project-defined commands

**Record the discovered commands.** You will use them in Steps 5 and 6 instead of fallback defaults. If no commands are found in any of these sources, fall back to:
- Test: `uv run pytest`
- Typecheck: `uv run mypy .`
- Lint: `uv run ruff check .`

### 2b. Detect the project stack

1. **pyproject.toml** — look for dependencies: `fastapi`, `sqlalchemy`, `pydantic`, `asyncio`/`anyio`/`uvicorn`, `uv`
2. **Existing imports** — scan `src/` or `app/` for `from fastapi import`, `from sqlalchemy import`, `from pydantic import`, `import asyncio`
3. **Task description** — parse `$ARGUMENTS` for keywords: endpoint, API, route, model, schema, database, migration, async, dependency, package

Record which stack components are present. You will use this in Step 3.

---

## Step 3: Load Context-Specific Skills

Based on Step 2 findings, load the relevant skills using the Skill tool. **Only load skills that are actually needed.**

### If writing or modifying code (almost always):

```
Use the Skill tool with:
  skill: "python-developer:tdd-workflow"
```

### If FastAPI detected OR task involves endpoints/routes/API:

```
Use the Skill tool with:
  skill: "python-developer:fastapi-patterns"
```

### If SQLAlchemy detected OR task involves database/models/migrations:

```
Use the Skill tool with:
  skill: "python-developer:sqlalchemy-patterns"
```

### If Pydantic detected OR task involves schemas/validation/settings:

```
Use the Skill tool with:
  skill: "python-developer:pydantic-patterns"
```

### If task involves async code OR project uses asyncio/uvicorn:

```
Use the Skill tool with:
  skill: "python-developer:async-python-patterns"
```

### If task involves adding/removing/updating dependencies:

```
Use the Skill tool with:
  skill: "python-developer:uv-package-manager"
```

**After loading skills, read and internalize the HARD-RULES from every loaded skill. You must follow all of them.**

---

## Step 4: Plan the Implementation

Before writing any code:

1. Identify the files that need to be created or modified
2. Identify the test files that need to be created or modified
3. Determine the test cases needed (happy path, edge cases, error cases)
4. Confirm the plan aligns with loaded skill HARD-RULES

---

## Step 5: TDD Cycle (MANDATORY)

**You MUST follow this cycle. Writing implementation code before tests is a violation.**

### 5a. Write Tests First

- Create test file(s) following the project's test directory structure
- Write test cases covering: happy path, edge cases, error handling
- Use Fakes for internal dependencies, Mocks only for external I/O
- All imports at the top of the file, never inside test functions
- Use `pytest.mark.parametrize` for similar test cases

### 5b. Run Tests (Expect Failure)

Run the test command discovered in Step 2a (e.g. `make test`, `uv run pytest`, or whatever the project uses).

Tests MUST fail at this point. If they pass, your tests are not testing the right thing.

### 5c. Implement the Code

- Write the minimal code to make tests pass
- Follow all HARD-RULES from loaded skills
- All function parameters and return types must be annotated
- Use `X | None` instead of `Optional[X]`
- Use absolute imports only
- No mutable default arguments

### 5d. Run Tests (Expect Pass)

Run the test command discovered in Step 2a.

All tests must pass. If any fail, fix the implementation (not the tests, unless the test itself is wrong).

### 5e. Refactor

- Remove duplication
- Improve naming
- Ensure code is clean and readable
- Run tests again after refactoring to confirm nothing broke

---

## Step 6: Quality Gates (MANDATORY)

**Use the commands discovered in Step 2a.** The examples below are fallback defaults — always prefer the project's own commands from `CLAUDE.md`, `README.md`, or `Makefile`.

Run these checks. **ALL must pass before the task is considered complete.**

### Typecheck

Run the typecheck command from Step 2a (e.g. `make typecheck`, `uv run mypy .`, `uv run basedpyright`).

Fix any type errors. Do not use `# type: ignore` unless absolutely unavoidable and justified.

### Full Test Suite

Run the test command from Step 2a (e.g. `make test`, `uv run pytest`).

All tests must pass. Zero failures, zero errors.

### Linting

Run the lint command from Step 2a (e.g. `make lint`, `uv run ruff check .`).

Zero warnings. Zero errors.

---

## Step 7: Final Verification Checklist

**Go through this checklist before declaring the task complete. If ANY item is unchecked, go back and fix it.**

### Coding Standards

- [ ] All function parameters and return types are annotated
- [ ] No `Optional[X]` — using `X | None` everywhere
- [ ] No relative imports — all imports are absolute
- [ ] No imports inside functions — all at top of file
- [ ] No bare `except:` or `except Exception:`
- [ ] No mutable default arguments
- [ ] No unused imports or variables
- [ ] `pathlib.Path` used instead of string paths where applicable

### TDD

- [ ] Tests were written BEFORE implementation
- [ ] Fakes used for internal dependencies (no unittest.mock for internals)
- [ ] Mocks only for external I/O (3rd party APIs, network)
- [ ] All imports at top of test files
- [ ] Tests are independent — no shared mutable state between tests

### Quality Gates

- [ ] Typecheck command (from Step 2a) passes with zero errors
- [ ] Test command (from Step 2a) passes with zero failures
- [ ] Lint command (from Step 2a) passes with zero warnings

### Stack-Specific (check only if relevant skill was loaded)

- [ ] FastAPI: endpoints use dependency injection, proper status codes, Annotated types
- [ ] SQLAlchemy: async sessions, repository pattern, no raw SQL in routes
- [ ] Pydantic: proper model inheritance, validators use `@field_validator`/`@model_validator`
- [ ] Async: no blocking calls in async functions, proper task/gather usage
- [ ] Dependencies: `uv add` used, lockfile committed

**If all checks pass, the task is complete.**

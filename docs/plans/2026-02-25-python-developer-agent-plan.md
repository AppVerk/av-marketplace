# Python Developer Agent Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create the `python-developer:developer` agent that autonomously implements, fixes, and refactors Python code using the full Python Developer workflow (coding standards, TDD, stack-specific patterns).

**Architecture:** Single agent markdown file that acts as a lightweight router — it detects mode (fix/implement/refactor), loads existing skills via the Skill tool, runs TDD cycle, and passes quality gates. No logic duplication with existing skills.

**Tech Stack:** Claude Code plugin system (markdown agents with frontmatter)

**Design doc:** `docs/plans/2026-02-25-python-developer-agent-design.md`

---

### Task 1: Create agent directory and markdown file

**Files:**
- Create: `plugins/python-developer/agents/developer.md`

**Step 1: Create agents directory**

```bash
mkdir -p plugins/python-developer/agents
```

**Step 2: Write the agent file**

Create `plugins/python-developer/agents/developer.md` with the full agent prompt. The file structure follows the same pattern as `plugins/code-review/agents/fix-auto.md`:

- YAML frontmatter with `allowed-tools`
- Title and role description
- Input section referencing `$ARGUMENTS`
- Phased workflow

The agent content must include:

**Frontmatter:**
```yaml
---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(coverage:*), Bash(alembic:*), Bash(git:*), Bash(pip:*), Skill, TaskCreate, TaskUpdate, TaskList
---
```

**Phase 1 — Parse input & detect mode:**
- Create 6 progress tasks via TaskCreate (one per phase)
- From `$ARGUMENTS` detect mode using keyword matching:
  - fix: issue, bug, error, fix, broken, failing, vulnerability, CWE, OWASP, severity, remediation
  - refactor: refactor, rename, extract, move, split, merge, clean up, restructure
  - implement: default
- Extract file location and task description from arguments

**Phase 2 — Load coding standards & detect stack:**
- Load `python-developer:coding-standards` skill via Skill tool (mandatory, always)
- Read `pyproject.toml` for dependencies (fastapi, sqlalchemy, pydantic, asyncio/anyio/uvicorn)
- Scan `src/` or `app/` imports for framework detection
- Discover project commands in order: `CLAUDE.md` -> `README.md` -> `Makefile` -> `pyproject.toml`
- Record test/typecheck/lint commands; fallback to `uv run pytest`, `uv run mypy .`, `uv run ruff check .`

**Phase 3 — Load stack-specific skills:**
- Always load `python-developer:tdd-workflow` via Skill tool
- Conditionally load based on Phase 2 detection:
  - FastAPI detected or task involves endpoints/routes/API -> `python-developer:fastapi-patterns`
  - SQLAlchemy detected or task involves database/models/migrations -> `python-developer:sqlalchemy-patterns`
  - Pydantic detected or task involves schemas/validation/settings -> `python-developer:pydantic-patterns`
  - async code or project uses asyncio/uvicorn -> `python-developer:async-python-patterns`
  - dependency changes needed -> `python-developer:uv-package-manager`
- Internalize all HARD-RULES from loaded skills

**Phase 4 — TDD cycle (mode-dependent):**

Fix mode:
1. Read target file and understand the issue
2. Write a test that reproduces the problem (must fail)
3. Run test to confirm failure
4. Implement the fix (minimal changes)
5. Run test to confirm it passes
6. Refactor if needed, re-run tests

Implement mode:
1. Identify files to create/modify
2. Write tests: happy path, edge cases, error handling
3. Run tests to confirm failure
4. Write minimal implementation to pass tests
5. Run tests to confirm pass
6. Refactor, re-run tests

Refactor mode:
1. Check if tests exist for affected code
2. If no tests: write tests first, run them, confirm pass
3. Perform refactoring
4. Run tests to confirm they still pass
5. If tests fail: fix the refactoring, not the tests

All modes follow HARD-RULES from loaded skills (fakes over mocks, absolute imports, type annotations, etc.)

**Phase 5 — Quality gates:**
- Run typecheck (command from Phase 2), fix errors, max 3 iterations
- Run full test suite (command from Phase 2), fix failures, max 3 iterations
- Run linting (command from Phase 2), fix warnings, max 3 iterations
- All three must pass before proceeding

**Phase 6 — Report:**
- Generate structured report with: status, mode, skills loaded, changes made, tests written, quality gates results
- Use exact format from design doc
- Changes remain uncommitted

**Step 3: Verify file exists and frontmatter is valid**

```bash
head -3 plugins/python-developer/agents/developer.md
```

Expected: `---` on line 1, `allowed-tools:` on line 2, `---` on line 3.

**Step 4: Commit**

```bash
git add plugins/python-developer/agents/developer.md
git commit -m "feat(python-developer): add developer agent for autonomous Python work"
```

---

### Task 2: Bump plugin version

**Files:**
- Modify: `plugins/python-developer/.claude-plugin/plugin.json`

**Step 1: Update version in plugin.json**

Change version from `"2.0.0"` to `"2.1.0"` in `plugins/python-developer/.claude-plugin/plugin.json`:

```json
{
  "name": "python-developer",
  "description": "Enforces Python best practices, coding standards, TDD workflow, and modern tooling for AppVerk projects",
  "version": "2.1.0"
}
```

**Step 2: Verify the change**

```bash
cat plugins/python-developer/.claude-plugin/plugin.json
```

Expected: `"version": "2.1.0"`

**Step 3: Commit**

```bash
git add plugins/python-developer/.claude-plugin/plugin.json
git commit -m "chore(python-developer): bump version to 2.1.0"
```

---

### Task 3: Update marketplace.json

**Files:**
- Modify: `.claude-plugin/marketplace.json`

**Step 1: Update python-developer version in marketplace.json**

Change the python-developer entry version from `"1.1.0"` to `"2.1.0"` in `.claude-plugin/marketplace.json`:

```json
{
  "name": "python-developer",
  "source": "./plugins/python-developer",
  "description": "Master the Python programming language for efficient and effective development",
  "version": "2.1.0",
  "category": "development"
}
```

**Step 2: Verify**

```bash
cat .claude-plugin/marketplace.json | grep -A5 python-developer
```

Expected: `"version": "2.1.0"`

**Step 3: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "chore: update python-developer version in marketplace.json"
```

---

### Task 4: Update plugin documentation

**Files:**
- Modify: `docs/plugins/python-developer.md`

**Step 1: Update version and add agent section**

Update `docs/plugins/python-developer.md`:
- Change `**Version:** 2.0.0` to `**Version:** 2.1.0`
- Add an `## Agents` section between `## Commands` and `## Skills` describing the new `developer` agent:
  - Name: `python-developer:developer`
  - Purpose: autonomous Python development (implement, fix, refactor)
  - How it works: detects mode, loads skills, runs TDD cycle, quality gates
  - Note: Claude selects this agent automatically for Python projects based on its description

**Step 2: Verify the doc reads well**

```bash
cat docs/plugins/python-developer.md
```

Verify: version is 2.1.0, Agents section exists between Commands and Skills.

**Step 3: Commit**

```bash
git add docs/plugins/python-developer.md
git commit -m "docs(python-developer): add developer agent to plugin documentation"
```

---

### Task 5: Update marketplace README

**Files:**
- Modify: `README.md`

**Step 1: Update Python Developer version and description in README table**

In `README.md`, update the Python Developer row:
- Version: `2.0.0` -> `2.1.0`
- Description: add mention of the new developer agent

Current:
```
| [Python Developer](docs/plugins/python-developer.md) | 2.0.0 | Python development workflow with `/develop` command, coding standards, TDD, and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic) |
```

New:
```
| [Python Developer](docs/plugins/python-developer.md) | 2.1.0 | Python development workflow with `/develop` command and autonomous `developer` agent. Coding standards, TDD, and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic) |
```

**Step 2: Verify**

```bash
grep -n "Python Developer" README.md
```

Expected: version `2.1.0` and mention of `developer` agent.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update Python Developer to 2.1.0 in README"
```

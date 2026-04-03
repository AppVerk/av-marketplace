# Python Developer Plugin

Python development workflow with `/develop` command, coding standards, TDD, and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic, Django, DRF, Celery).

**Version:** 3.0.3

## Commands

### `/develop <task description>`

Python development workflow that automatically loads the right skills for the task. Analyzes the project to detect FastAPI, Django, DRF, Celery, SQLAlchemy, Pydantic, and enforces TDD and coding standards throughout.

```
/develop Add a new endpoint for user registration
/develop Fix the N+1 query in the orders list endpoint
/develop Refactor the payment service to use the repository pattern
/develop Add a new DRF ViewSet for user registration
/develop Add a Celery task for sending notification emails
```

## Agents

### Developer (`python-developer:developer`)

Autonomous Python development agent for implementing features, fixing issues, and refactoring code. Claude selects this agent automatically when working on Python projects.

The agent follows the full Python Developer workflow:

1. Detects mode (fix, implement, or refactor) from the task description
2. Loads coding standards and detects the project stack
3. Loads stack-specific skills (FastAPI or Django/DRF, SQLAlchemy or Django ORM, Celery, Pydantic, async patterns)
4. Runs a TDD cycle appropriate to the mode
5. Passes quality gates (typecheck, tests, lint)
6. Reports results with changes left uncommitted

## Skills

This plugin provides background skills that activate automatically when relevant. They guide Claude's code generation to follow Python best practices.

### Coding Standards

Enforces Python coding rules: type hints, imports, naming, error handling, and project conventions for AppVerk projects.

Activates automatically when writing or reviewing Python code.

### TDD Workflow

Enforces test-driven development: writes tests before code, uses fakes over mocks, maintains 80%+ coverage.

Activates when writing new features, fixing bugs, or refactoring Python code.

### UV Package Manager

Manages Python dependencies and environments with uv: adds packages, syncs lockfiles, pins versions.

Activates when setting up projects, managing dependencies, or working with virtual environments.

### Async Python Patterns

Guides async/await implementation: asyncio patterns, concurrent I/O, task management, synchronization.

Activates when building async APIs, concurrent systems, or non-blocking applications.

### FastAPI Patterns

Enforces FastAPI patterns: endpoint structure, dependency injection, error handling, middleware.

Activates when working with FastAPI routers, endpoints, or middleware.

### SQLAlchemy Patterns

Enforces SQLAlchemy patterns: async sessions, repository pattern, Alembic migrations, query optimization.

Activates when working with database models, queries, or migrations.

### Pydantic Patterns

Enforces Pydantic patterns: model design, validators, settings management, FastAPI schema integration.

Activates when working with data models, validation, or configuration.

### Django Web Patterns

Enforces Django REST Framework patterns with Pragmatic DDD: ViewSets, Serializers, Permissions, exception handling, settings, middleware.

Activates when working with Django views, DRF endpoints, or serializers.

### Django ORM Patterns

Enforces Django ORM patterns with Pragmatic DDD: rich domain models, Managers, QuerySets, migrations, signals, performance optimization.

Activates when working with Django models, queries, or migrations.

### Celery Patterns

Enforces Celery task patterns: idempotent design, retry strategies with exponential backoff, error handling, testing with eager mode.

Activates when working with Celery tasks, background jobs, or async workers.

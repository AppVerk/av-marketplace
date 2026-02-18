# Python Developer Plugin

Python development workflow with `/develop` command, coding standards, TDD, and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic).

**Version:** 2.0.0

## Commands

### `/develop <task description>`

Python development workflow that automatically loads the right skills for the task. Analyzes the project to detect FastAPI, SQLAlchemy, Pydantic, and enforces TDD and coding standards throughout.

```
/develop Add a new endpoint for user registration
/develop Fix the N+1 query in the orders list endpoint
/develop Refactor the payment service to use the repository pattern
```

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

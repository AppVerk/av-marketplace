---
name: coding-standards
description: Universal coding standards, best practices, and patterns for Python development. 
---

# Python Coding Rules

These are the internal Python coding rules that guide code generation for this project.

## Project Setup

- Target Python version as specified in `pyproject.toml` or `.python-version` file. Do NOT write code to support earlier versions.
- Code will be checked with **Ruff** using a defined selection of rules and formatted with Ruff's formatter, both configurations in `pyproject.toml`.
- Code will be type-checked with **mypy** and **basedpyright** using the project's configuration in `pyproject.toml`.
- General style follows **PEP8** conventions (names, layout, line length, whitespace).
- Assume that all projects use **uv** as package manager and thus you need to run any command using it.
- Code formatting and type hints can be checked using make recipe: `make typecheck`.
- Always check your code after changes using `make typecheck` and `make test` .
- Verify zero linter warnings/errors or test failures before considering any task complete.
- Ask for confirmation before globally disabling any lint or type checker rules in `pyproject.toml`

## Output Requirements

- Produce complete, runnable code with all necessary imports, type hints, and minimal dependencies.
- Code must pass mypy and basedpyright type checking and satisfy enabled Ruff rules without requiring manual fixes.
- Prefer standard library solutions; if external libraries are required, state them clearly and type their interfaces or use available type stubs.

## Type Annotations and mypy

- Explicitly annotate all function parameters and return types, even when mypy could infer them.
- Use modern union syntax: `str | None` instead of `Optional[str]`. Never use or import `Optional`.
- If a parameter's default is `None`, annotate as `T | None` and handle `None` explicitly.
- No implicit optional parameters.
- Use modern enums like `StrEnum` when appropriate.
- Avoid leaking or returning `Any`; narrow results from untyped or missing-stub libs with typed wrappers.
- Avoid equality/ordering between incompatible or possibly-`None` types without narrowing.
- Remove unreachable or dead branches; annotate functions that never return as `-> NoReturn`.
- Even if missing stubs are ignored, isolate untyped dependencies in narrow, typed functions.
- No `type: ignore` unless unavoidable and explicitly justified in comments.

## Imports and Code Structure

- Use absolute imports compatible with the project's `src/` layout and namespace packages.
- Never use relative imports (e.g., `from .module import ...`). Always use absolute imports.
- Import from the correct modules: use `collections.abc` for abstract base classes.
- One import per line; no wildcard imports; prefer explicit names.
- Sort and group imports: standard library, third-party, local; ensure deterministic ordering.
- Resolve circular imports by refactoring.
- No unused imports or variables.

## Naming Conventions

- Maintain proper naming conventions for constants (UPPER_SNAKE_CASE), functions/variables (lower_snake_case), classes (PascalCase), and private members (_leading_underscore).
- Avoid ambiguous names like `l`, `O`, `I`.

## Design Principles

- Keep functions small and single-purpose; prefer pure functions where practical.
- Do not modify input data, unless in a framework or library where it is a convention.
- Avoid side effects at import time; put runtime logic under `if __name__ == "__main__":` when appropriate.
- Do not include any executable code in `__init__.py` files.
- Use `pathlib.Path` instead of strings for file paths.
- Validate inputs and handle error paths explicitly.
- Use context managers for resource safety.
- Avoid global state; prefer dependency injection.
- Write deterministic, testable code with no hidden I/O or tight coupling.
- Separate pure logic from I/O.
- Avoid writing trivial wrapper functions that just delegate to another object's methods.
- When changing APIs that may break backward compatibility, explicitly mention this in comments or documentation.

## Documentation

- Keep comments accurate and minimal; prefer clear self-documenting code.
- Comments should be EXPLANATORY: explain WHY something is done, not WHAT is done.
- Comments should be CONCISE: remove all extraneous words.
- Never change existing comments, docstrings, or log statements unless directly fixing the issue they describe.
- Write concise, meaningful docstrings for public APIs.
- Document behavior, parameters, returns, and raised exceptions succinctly.
- Follow the project's chosen docstring style consistently.
- After completing any task, update all relevant documentation (README, API docs, comments, docstrings) to reflect the changes made.

## Error Handling

- Limit the scope of try-except blocks to a single I/O operation so that errors can be more specific.
- Catch specific exceptions; avoid bare except or overly broad exception handlers.
- Add context to errors; use `raise ... from ...` to preserve tracebacks.
- Use `logging` instead of `print` in libraries.

## Code Quality Checks

- Follow pycodestyle and pyflakes basics (`E`, `F`): no redefinitions, clean whitespace, valid line length.
- Apply Bugbear-style correctness checks (`B`): no mutable default arguments, misleading patterns, unused loop vars, fragile `.strip` cases, or constant `getattr`/`setattr`.
- Use Ruff formatting for consistent quotes, spacing, and layout.
- Respect selected Ruff rules explicitly; avoid relying on ALL since upgrades can introduce new rules.
- Match Ruff's target-version to the project's Python version.

## Testing

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

### Mocking

- Avoid mocks unless for external I/O like 3rd party API calls, database operations, etc.

## Additional Guidelines

- All date/datetime related objects must be timezone aware.
- Generally ignore mypy cache, pytest cache and IDE cache when looking for information.
- No misleading expressions or redundant casts.

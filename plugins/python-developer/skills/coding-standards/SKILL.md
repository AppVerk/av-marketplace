---
name: coding-standards
description: Enforces Python coding rules: type hints, imports, naming, error handling, and project conventions for AppVerk projects. Activates when writing or reviewing Python code.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*)
---

# Python Coding Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER put imports inside functions or methods — ALL imports go at the top of the file
- NEVER use `Optional[X]` or import `Optional` — ALWAYS use `X | None`
- NEVER use relative imports (`from .module import ...`) — ALWAYS use absolute imports
- NEVER use bare `except:` or `except Exception:` — ALWAYS catch specific exception types
- NEVER use mutable default arguments (`def f(x=[])`) — use `None` and create inside function
- NEVER leave unused imports or variables — remove them immediately
- ALWAYS annotate all function parameters and return types explicitly
- ALWAYS use `pathlib.Path` instead of string paths
- ALWAYS run `make typecheck` and `make test` after any code change
- ALWAYS use `uv run` to execute any Python command
</HARD-RULES>

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

## Vertical Whitespace

Use blank lines to visually separate logical sections of code, improving scanability and readability.

**Inside functions/methods:**
- Separate logical blocks with a blank line: variable initialization, processing logic, result preparation, return.
- Add a blank line before a closing `return` when the function body is longer than a few lines.
- Add a blank line before and after `if`/`for`/`while`/`try` blocks when surrounded by other code.
- Add a blank line after a method's docstring before the actual code.
- Do not add blank lines in short, simple functions (2-3 lines) — it disrupts readability.

**Inside classes:**
- Separate groups of related attributes with a blank line (e.g., public vs private, config vs state).
- One blank line between methods (PEP 8 standard).
- Two blank lines before the first method if the class has class-level attributes at the top.

**General principle:**
- Treat a blank line like a paragraph break in prose — it signals a change of topic or context.
- No more than one consecutive blank line inside a function or class.

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

See the `tdd-workflow` skill for all testing rules, patterns, and conventions.

## Additional Guidelines

- All date/datetime related objects must be timezone aware.
- Generally ignore mypy cache, pytest cache and IDE cache when looking for information.
- No misleading expressions or redundant casts.

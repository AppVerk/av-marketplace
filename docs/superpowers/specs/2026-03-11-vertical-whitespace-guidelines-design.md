# Vertical Whitespace Guidelines for Python Coding Standards

## Context

The `python-developer` coding standards skill lacks guidelines for using blank lines (vertical whitespace) to improve code readability. This leads to inconsistent formatting inside functions and classes.

## Scope

- Inside functions/methods: separating logical blocks with blank lines
- Inside classes: blank lines between methods, attribute groups

## Approach

Add a new descriptive (non-normative) section "Vertical Whitespace" to `SKILL.md`, placed between "Naming Conventions" and "Design Principles".

Guidelines are advisory — the agent applies them with judgement, not as hard rules.

## Content

### Inside functions/methods

- Separate logical blocks with a blank line: variable initialization, processing logic, result preparation, return
- Add a blank line before a closing `return` when the function body is longer than a few lines
- Add a blank line before and after `if`/`for`/`while`/`try` blocks when surrounded by other code
- Add a blank line after a method's docstring before the actual code
- Do not add blank lines in short, simple functions (2-3 lines)

### Inside classes

- Separate groups of related attributes with a blank line (e.g., public vs private, config vs state)
- One blank line between methods (PEP 8 standard)
- Two blank lines before the first method if the class has class-level attributes at the top

### General principle

- Treat a blank line like a paragraph break in prose — it signals a change of topic or context
- No more than one consecutive blank line inside a function or class

## File changed

`plugins/python-developer/skills/coding-standards/SKILL.md`

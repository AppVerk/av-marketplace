# PHP Developer Plugin

PHP development workflow with `/develop` command, coding standards, TDD, and stack-specific patterns (Symfony, Doctrine ORM, DDD).

**Version:** 1.0.3

## Commands

### `/develop <task description>`

PHP development workflow that automatically loads the right skills for the task. Analyzes the project to detect Symfony, Doctrine ORM, DDD architecture, and enforces TDD and coding standards throughout.

```
/develop Add a new endpoint for user registration
/develop Fix the N+1 query in the orders list
/develop Refactor the payment service to use CQRS with Messenger
/develop Add a Doctrine entity for product catalog
/develop Implement a bounded context for order management
```

## Agents

### Developer (`php-developer:developer`)

Autonomous PHP development agent for implementing features, fixing issues, and refactoring code. Claude selects this agent automatically when working on PHP projects.

The agent follows the full PHP Developer workflow:

1. Detects mode (fix, implement, or refactor) from the task description
2. Loads coding standards and detects the project stack
3. Loads stack-specific skills (Symfony, Doctrine ORM, DDD, Composer)
4. Runs a TDD cycle appropriate to the mode
5. Passes quality gates (typecheck, tests, lint, optional architecture)
6. Reports results with changes left uncommitted

## Skills (Auto-Loaded Conditionally)

| Skill | When loaded | Purpose |
|-------|------------|---------|
| coding-standards | Always | Strict types, type hints, PSR-12, imports, naming, error handling |
| tdd-workflow | Always | PHPUnit, fakes over mocks, 80%+ coverage, DataProvider |
| symfony-patterns | `symfony/framework-bundle` dep | Thin controllers, Messenger CQRS, autowiring, routing attributes |
| doctrine-orm-patterns | `doctrine/orm` dep | Mapping, repositories, migrations, QueryBuilder, performance |
| ddd-patterns | `src/*/Domain/` dirs | Bounded Contexts, 4-layer architecture, Aggregates, Value Objects, Domain Events |
| composer | Dependency changes | Package management, autoload, lockfile integrity |

## Workflow

1. Load coding-standards
2. Analyze project (composer.json, src/ structure, CLAUDE.md, Makefile)
3. Load context-specific skills
4. Plan implementation
5. TDD cycle (red/green/refactor)
6. Quality gates (typecheck, tests, lint, optional architecture)
7. Final verification checklist

## Quality Gates

| Gate | Default command | Purpose |
|------|----------------|---------|
| Typecheck | `vendor/bin/phpstan analyse src` | Static analysis with PHPStan |
| Tests | `vendor/bin/phpunit` | Full test suite with PHPUnit |
| Lint | `vendor/bin/php-cs-fixer fix --dry-run --diff` | Code style with PHP-CS-Fixer |
| Architecture | `vendor/bin/deptrac analyse` | Dependency rules with Deptrac (optional, DDD only) |

## Tech Stack

- PHP 8.2+ (strict types required)
- Symfony Framework
- Doctrine ORM
- Domain-Driven Design (4-layer architecture)
- Symfony Messenger (CQRS)
- Composer for package management
- PHPUnit + PHPStan + PHP-CS-Fixer + Deptrac for quality

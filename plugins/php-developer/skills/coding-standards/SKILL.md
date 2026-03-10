---
name: coding-standards
description: Enforces PHP coding rules: strict types, type hints, imports, naming, error handling, and PSR-12 conventions. Activates when writing or reviewing PHP code.
allowed-tools: Read, Grep, Glob, Bash(php:*), Bash(composer:*), Bash(vendor/bin/*), Bash(bin/*), Bash(make:*), Bash(git:*)
---

# PHP Coding Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS add `declare(strict_types=1);` in every PHP file
- ALWAYS annotate all function parameters and return types explicitly
- NEVER use `mixed` type without justification — use specific types or union types
- NEVER use FQCN in code — ALWAYS import via `use` statements
- NEVER use `@var` annotations when the type can be declared natively
- NEVER leave unused imports or variables — remove them immediately
- ALWAYS use `readonly` properties for immutable data (PHP 8.1+)
- ALWAYS use enums instead of class constants for finite sets (PHP 8.1+)
- ALWAYS use `match` expressions instead of `switch` statements
- ALWAYS use named arguments for constructors with 3+ parameters
- ALWAYS target the PHP version specified in `composer.json` `require.php` field — do NOT write code for earlier versions
- NEVER catch generic `\Exception` or `\Throwable` — ALWAYS catch specific exception types
- ALWAYS use `DateTimeImmutable` — NEVER use `DateTime`
</HARD-RULES>

These are the internal PHP coding rules that guide code generation for this project.

## Project Setup

- Target PHP version as specified in `composer.json` `require.php` field. Do NOT write code to support earlier versions.
- Code will be checked with **PHPStan** (or **Psalm**) using the project's configuration.
- Code will be formatted with **PHP-CS-Fixer** using the project's `.php-cs-fixer.dist.php`.
- General style follows **PSR-12** conventions with Symfony additions.
- Assume that all projects use **Composer** as package manager.
- Always check your code after changes using the project's quality gate commands.
- Verify zero linter warnings/errors or test failures before considering any task complete.

## Output Requirements

- Produce complete, runnable code with all necessary imports, type hints, and minimal dependencies.
- Code must pass PHPStan and PHP-CS-Fixer without requiring manual fixes.
- Prefer framework solutions; if external libraries are required, state them clearly.

## Type Annotations

- Explicitly annotate all function parameters and return types, even when the IDE could infer them.
- Use union types: `string|null` instead of `?string` only when combining non-null types (e.g., `string|int`). For nullable single types, `?string` is acceptable.
- Use intersection types when appropriate: `Countable&Iterator`.
- If a parameter's default is `null`, annotate as `?Type` and handle `null` explicitly.
- Use modern enums (`BackedEnum`, `UnitEnum`) when appropriate.
- Avoid returning `mixed`; narrow results with typed wrappers.
- No `@var` annotations when the type can be declared natively.
- No `@param` or `@return` PHPDoc when native types suffice. Only use PHPDoc for generics (`@template`), array shapes (`array{key: type}`), or additional context beyond native types.

## PHP 8.1+ Features

Use modern PHP features when they improve code clarity:

```php
// Enums instead of class constants
enum OrderStatus: string
{
    case Pending = 'pending';
    case Confirmed = 'confirmed';
    case Cancelled = 'cancelled';
}

// Readonly properties for immutable data
class Money
{
    public function __construct(
        public readonly int $amount,
        public readonly string $currency = 'PLN',
    ) {}
}

// Named arguments for clarity
$workshop = Workshop::create(
    id: Uuid::v4(),
    name: $command->name,
    status: WorkshopStatus::Active,
);

// Match expressions instead of switch
$label = match ($status) {
    OrderStatus::Pending   => 'Awaiting confirmation',
    OrderStatus::Confirmed => 'Order confirmed',
    OrderStatus::Cancelled => 'Order cancelled',
};

// First-class callable syntax
$names = array_map($this->formatName(...), $users);

// Fibers for async (when applicable)
// Intersection types
function process(Countable&Iterable $items): void { /* ... */ }

// Nullsafe operator
$city = $user?->getAddress()?->getCity();
```

## Imports and Code Structure

- ALWAYS import classes via `use` at the top of the file — never use FQCN inline.
- One import per line; no wildcard imports.
- Group imports: PHP native, vendor, project. Maintain deterministic ordering.
- Resolve circular dependencies by refactoring, not by moving imports.
- No unused imports or variables.

```php
<?php

declare(strict_types=1);

namespace App\Order\Application\Command;

use App\Order\Domain\Order;
use App\Order\Domain\OrderRepositoryInterface;
use App\Shared\Domain\Event\EventBusInterface;
use DateTimeImmutable;
use Symfony\Component\Uid\Uuid;
```

## Naming Conventions

- **Classes:** `PascalCase` — `OrderService`, `CreateOrderCommandHandler`
- **Methods/Properties:** `camelCase` — `findById()`, `$createdAt`
- **Constants:** `UPPER_SNAKE_CASE` — `MAX_RETRY_COUNT`
- **Interfaces:** suffix with `Interface` — `OrderRepositoryInterface`
- **Abstract classes:** prefix with `Abstract` — `AbstractController`
- **Enums:** `PascalCase` with `PascalCase` cases — `OrderStatus::Pending`
- **Command/Query:** suffix with `Command`/`Query` — `CreateOrderCommand`, `GetOrderQuery`
- **Command/Query Handlers:** suffix with `Handler` — `CreateOrderCommandHandler`
- **Events:** past tense — `OrderWasCreated`, `PaymentWasProcessed`
- **Exceptions:** suffix with `Exception` — `OrderNotFoundException`
- **Tests:** `testMethodNameScenarioExpectedBehavior` — `testCreateOrderValidDataOrderCreated`

## Design Principles

- Keep functions small and single-purpose.
- Do not modify input data unless the framework requires it.
- Use `readonly` properties and immutable objects where practical.
- Validate inputs and handle error paths explicitly.
- Avoid global state; prefer dependency injection.
- Write deterministic, testable code with no hidden I/O or tight coupling.
- Separate pure logic from I/O.
- Avoid writing trivial wrapper methods that just delegate.

## Documentation

- Keep comments accurate and minimal; prefer clear self-documenting code.
- Comments should explain WHY, not WHAT.
- Write concise docstrings for public APIs only when native types are insufficient.
- Use `@template`, `@extends`, `@implements` for generics.
- Use `array{key: type}` or `list<Type>` for complex array shapes.

## Error Handling

- Limit the scope of try-catch blocks to a single I/O operation.
- Catch specific exceptions; avoid bare `catch (\Exception $e)`.
- Add context to errors; use previous exception: `throw new XException('msg', previous: $e)`.
- Use domain-specific exceptions: `OrderNotFoundException`, `InsufficientStockException`.
- Use `\LogicException` subclasses for programming errors, `\RuntimeException` subclasses for runtime errors.

## Additional Guidelines

- All date/datetime related objects must use `DateTimeImmutable`, never `DateTime`.
- Ignore vendor/, var/, cache directories when looking for project code.
- No misleading expressions or redundant casts.
- Constructor promotion: use `public readonly` in constructor where appropriate.

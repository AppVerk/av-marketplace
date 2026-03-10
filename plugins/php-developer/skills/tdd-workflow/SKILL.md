---
name: tdd-workflow
description: Enforces test-driven development: writes tests before code, uses fakes over mocks, maintains 80%+ coverage. Activates when writing new features, fixing bugs, or refactoring PHP code.
allowed-tools: Read, Grep, Glob, Bash(php:*), Bash(composer:*), Bash(vendor/bin/*), Bash(bin/*), Bash(make:*), Bash(git:*)
---

# Test-Driven Development Workflow

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS write tests BEFORE implementation code — no exceptions
- ALWAYS use Fake implementations (in-memory, simplified) for internal dependencies — NEVER use mocks for internal services
- ONLY use mocks for external I/O: 3rd party APIs, real database calls in unit tests, network requests
- NEVER write tests that depend on other tests — each test sets up its own data
- ALWAYS run the full test suite after changes, not just specific tests
- ALWAYS verify 80%+ coverage before considering work complete
- ALWAYS use `#[DataProvider]` for similar test cases instead of duplicating tests
- ALWAYS name tests: `testMethodNameScenarioExpectedBehavior`
- NEVER put imports or class instantiation logic inside test methods — use setUp() or test fixtures
- ALWAYS use `/** @internal */` docblock on test classes
</HARD-RULES>

This skill ensures all code development follows TDD principles with comprehensive test coverage.

## When to Activate

- Writing new features or functionality
- Fixing bugs or issues
- Refactoring existing code
- Adding API endpoints
- Creating new services or command handlers

## Core Principles

### 1. Tests BEFORE Code

ALWAYS write tests first, then implement code to make tests pass.

### 2. Coverage Requirements

- Minimum 80% coverage (unit + functional + integration)
- All edge cases covered
- Error scenarios tested
- Boundary conditions verified

### 3. Test Types

#### Unit Tests
- Individual functions and methods
- Service/handler logic
- Pure functions
- Domain model behavior

#### Functional Tests
- Black-box testing of the API endpoints
- Full request/response cycle with faked dependencies
- Extends `WebTestCase` or custom `JwtApiTestCase`

#### Integration Tests
- Database operations via Doctrine
- Service interactions with real dependencies
- Message bus dispatching

## TDD Workflow Steps

### Step 1: Write Test Cases

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit\Order\Application\Command;

use App\Order\Application\Command\CreateOrderCommand;
use App\Order\Application\Command\CreateOrderCommandHandler;
use App\Order\Domain\Order;
use App\Order\Domain\OrderRepositoryInterface;
use App\Tests\Fakes\FakeOrderRepository;
use PHPUnit\Framework\TestCase;
use Symfony\Component\Uid\Uuid;

/**
 * @internal
 */
class CreateOrderCommandHandlerTest extends TestCase
{
    private FakeOrderRepository $repository;
    private CreateOrderCommandHandler $handler;

    protected function setUp(): void
    {
        $this->repository = new FakeOrderRepository();
        $this->handler = new CreateOrderCommandHandler($this->repository);
    }

    public function testCreateOrderValidDataOrderCreated(): void
    {
        $command = new CreateOrderCommand(
            name: 'Test Order',
            customerId: Uuid::v4(),
        );

        ($this->handler)($command);

        $orders = $this->repository->findAll();
        self::assertCount(1, $orders);
        self::assertSame('Test Order', $orders[0]->getName());
    }

    public function testCreateOrderDuplicateNameThrowsException(): void
    {
        $this->repository->addExisting(
            Order::create(id: Uuid::v4(), name: 'Existing Order', customerId: Uuid::v4())
        );

        $this->expectException(OrderAlreadyExistsException::class);

        ($this->handler)(new CreateOrderCommand(
            name: 'Existing Order',
            customerId: Uuid::v4(),
        ));
    }
}
```

### Step 2: Run Tests (They Should Fail)

```bash
vendor/bin/phpunit
# Tests should fail — we haven't implemented yet
```

### Step 3: Implement Code

Write minimal code to make tests pass.

### Step 4: Run Tests Again

```bash
vendor/bin/phpunit
# Tests should now pass
```

### Step 5: Refactor

Improve code quality while keeping tests green.

### Step 6: Verify Coverage

```bash
vendor/bin/phpunit --coverage-text --coverage-html=var/coverage
# Verify 80%+ coverage achieved
```

## Test File Organization

```
tests/
├── Unit/
│   ├── Order/
│   │   ├── Application/
│   │   │   └── Command/
│   │   │       └── CreateOrderCommandHandlerTest.php
│   │   ├── Domain/
│   │   │   └── OrderTest.php
│   │   └── Infrastructure/
│   │       └── OrderNumberGeneratorTest.php
│   ├── [OtherContext]/
│   └── Shared/
├── Functional/
│   ├── Order/
│   │   └── Controller/
│   │       └── OrderControllerTest.php
│   └── [OtherContext]/
├── Integration/
│   ├── Order/
│   │   └── Repository/
│   │       └── DoctrineOrderRepositoryTest.php
│   └── [OtherContext]/
├── Fakes/
│   ├── FakeOrderRepository.php
│   ├── FakeEventBus.php
│   └── FakeEmailService.php
├── Cases/
│   ├── JwtApiTestCase.php
│   └── DatabaseTestCase.php
└── bootstrap.php
```

**Mirroring rule:** `src/Order/Application/Command/CreateOrderCommandHandler.php` → `tests/Unit/Order/Application/Command/CreateOrderCommandHandlerTest.php`

## Test Doubles: Fakes vs Mocks

### Prefer Fakes Over Mocks

```php
<?php

declare(strict_types=1);

namespace App\Tests\Fakes;

use App\Order\Domain\Order;
use App\Order\Domain\OrderRepositoryInterface;
use Symfony\Component\Uid\Uuid;

class FakeOrderRepository implements OrderRepositoryInterface
{
    /** @var array<string, Order> */
    private array $orders = [];

    public function save(Order $order): void
    {
        $this->orders[$order->getId()->toRfc4122()] = $order;
    }

    public function findById(Uuid $id): ?Order
    {
        return $this->orders[$id->toRfc4122()] ?? null;
    }

    public function findByName(string $name): ?Order
    {
        foreach ($this->orders as $order) {
            if ($order->getName() === $name) {
                return $order;
            }
        }

        return null;
    }

    /** @return list<Order> */
    public function findAll(): array
    {
        return array_values($this->orders);
    }

    public function addExisting(Order $order): void
    {
        $this->orders[$order->getId()->toRfc4122()] = $order;
    }
}
```

### When to Use Each

| Scenario | Use |
|----------|-----|
| Repository/data access | Fake (in-memory implementation) |
| Business logic dependencies | Fake (simplified implementation) |
| Event bus / message bus | Fake (records dispatched messages) |
| 3rd party API calls (payment gateway, email) | Mock |
| Database operations in integration tests | Test database with rollback |
| External HTTP requests | Mock or fake HTTP client |

### Mocks Only for External I/O

```php
public function testSendsEmailOnOrderCreation(): void
{
    $mailer = $this->createMock(MailerInterface::class);
    $mailer->expects(self::once())
        ->method('send')
        ->with(self::callback(fn (Email $email) =>
            $email->getTo()[0]->getAddress() === 'customer@example.com'
        ));

    $handler = new CreateOrderCommandHandler($this->repository, $mailer);
    ($handler)($this->createCommand());
}
```

## DataProvider Pattern

```php
/**
 * @internal
 */
class OrderValidationTest extends TestCase
{
    #[DataProvider('invalidOrderDataProvider')]
    public function testCreateOrderInvalidDataThrowsException(
        string $name,
        ?Uuid $customerId,
        string $expectedMessage,
    ): void {
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage($expectedMessage);

        Order::create(id: Uuid::v4(), name: $name, customerId: $customerId);
    }

    /** @return \Generator<string, array{string, ?Uuid, string}> */
    public static function invalidOrderDataProvider(): \Generator
    {
        yield 'empty name' => ['', Uuid::v4(), 'Name cannot be empty'];
        yield 'name too long' => [str_repeat('a', 256), Uuid::v4(), 'Name too long'];
        yield 'null customer' => ['Valid Name', null, 'Customer ID required'];
    }
}
```

## Functional Test Pattern

```php
<?php

declare(strict_types=1);

namespace App\Tests\Functional\Order\Controller;

use App\Tests\Cases\JwtApiTestCase;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * @internal
 */
class OrderControllerTest extends JwtApiTestCase
{
    private string $baseUrl = '/api/orders';

    public function testCreateOrderValidDataReturnsNoContent(): void
    {
        $response = $this->makeAuthorizedRequest(
            Request::METHOD_POST,
            $this->baseUrl,
            'admin@example.com',
            [
                'name' => 'Test Order',
                'customer_id' => '9c36e9e6-427e-4e88-976b-976e23ed508f',
            ],
        );

        self::assertResponseCode($response, Response::HTTP_NO_CONTENT);
    }

    public function testCreateOrderUnauthorizedReturnsForbidden(): void
    {
        $response = $this->makeAuthorizedRequest(
            Request::METHOD_POST,
            $this->baseUrl,
            'viewer@example.com',
            ['name' => 'Test Order'],
        );

        self::assertResponseCode($response, Response::HTTP_FORBIDDEN);
    }

    public function testListOrdersReturnsOrders(): void
    {
        $response = $this->makeAuthorizedRequest(
            Request::METHOD_GET,
            $this->baseUrl,
            'admin@example.com',
        );

        self::assertResponseCode($response, Response::HTTP_OK);
        $data = json_decode($response->getContent(), true, 512, JSON_THROW_ON_ERROR);
        self::assertIsArray($data);
    }
}
```

## Best Practices

1. **Write Tests First** — Always TDD
2. **One Assertion Per Concept** — Focus on single behavior
3. **Descriptive Test Names** — `testMethodNameScenarioExpectedBehavior`
4. **Arrange-Act-Assert** — Clear test structure
5. **Use Fakes for Dependencies** — Prefer fakes over mocks
6. **Mock Only External I/O** — 3rd party APIs, network calls
7. **Test Edge Cases** — Null, empty, boundary values
8. **Test Error Paths** — Not just happy paths
9. **Keep Tests Fast** — Unit tests < 50ms each
10. **Clean Up After Tests** — No side effects between tests

## Test Code Standards

- Use `self::assert*` instead of `$this->assert*` (static methods).
- Use `/** @internal */` docblock on all test classes.
- Use setUp() for shared test fixtures, not in-test construction.
- Use `#[DataProvider]` attribute (not `@dataProvider` annotation).
- Test method visibility: public for test methods, private for helpers.
- Prefer `self::assertSame()` over `self::assertEquals()` for strict comparison.

---
name: ddd-patterns
description: Enforces DDD patterns: Bounded Contexts, 4-layer architecture, Aggregate Roots, Value Objects, Domain Events, repository interfaces. Activates when working with domain models, services, or cross-context communication.
allowed-tools: Read, Grep, Glob, Bash(php:*), Bash(composer:*), Bash(vendor/bin/*), Bash(bin/*), Bash(make:*), Bash(git:*)
---

# Domain-Driven Design Patterns

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER import framework classes in the Domain layer — Domain has zero external dependencies (exception: Symfony\Component\Uid\Uuid is allowed as it has no framework coupling)
- ALWAYS follow dependency direction: Presentation → Infrastructure → Application → Domain
- NEVER put business logic in Infrastructure or Presentation layers — business rules belong in Domain
- ALWAYS use factory methods on Aggregate Roots for entity creation — NEVER use `new Entity()` outside the entity itself
- ALWAYS make Value Objects immutable — use readonly properties
- NEVER access another Bounded Context's Domain layer directly — use domain events or Application layer services
- ALWAYS define repository interfaces in the Domain layer — implementations belong in Infrastructure
- NEVER throw generic exceptions from Domain — use context-specific domain exceptions
</HARD-RULES>

## Bounded Context Structure

Each Bounded Context is a top-level directory under `src/` with exactly 4 layers:

```
src/
├── Order/                          # Bounded Context
│   ├── Domain/                     # Business logic (no framework deps)
│   │   ├── Order.php               # Aggregate Root
│   │   ├── OrderStatus.php         # Enum
│   │   ├── OrderItem.php           # Entity (part of aggregate)
│   │   ├── OrderRepositoryInterface.php  # Repository contract
│   │   ├── Event/
│   │   │   ├── OrderWasCreated.php
│   │   │   └── OrderWasCancelled.php
│   │   ├── Exception/
│   │   │   ├── OrderNotFoundException.php
│   │   │   └── OrderCannotBeCancelledException.php
│   │   └── ValueObject/
│   │       ├── Address.php
│   │       └── Money.php
│   ├── Application/                # Use cases (orchestration)
│   │   ├── Api/
│   │   │   ├── Command/
│   │   │   │   ├── CreateOrderCommand.php
│   │   │   │   └── CreateOrderCommandHandler.php
│   │   │   ├── Query/
│   │   │   │   ├── GetOrderQuery.php
│   │   │   │   └── GetOrderQueryHandler.php
│   │   │   └── View/
│   │   │       └── OrderView.php   # Read DTO
│   │   └── Admin/
│   │       ├── Command/
│   │       └── Query/
│   ├── Infrastructure/             # Framework integration
│   │   └── Persistence/
│   │       └── Doctrine/
│   │           ├── Repository/
│   │           │   └── DoctrineOrderRepository.php
│   │           └── Mapping/
│   │               └── Order.orm.yml
│   └── Presentation/               # HTTP interface
│       ├── Api/
│       │   └── Controller/
│       │       └── OrderController.php
│       └── Admin/
│           └── Controller/
│               └── OrderAdminController.php
```

## Dependency Direction

```
Presentation  →  can use  →  Application, Infrastructure, Domain
Infrastructure  →  can use  →  Application, Domain
Application  →  can use  →  Domain ONLY
Domain  →  can use  →  NOTHING (pure PHP)
```

Enforce with **Deptrac** when available:

```yaml
# deptrac/deptrac.layers.yaml
deptrac:
  layers:
    - name: Domain
      collectors: [{ type: directory, regex: src/.*/Domain/.* }]
    - name: Application
      collectors: [{ type: directory, regex: src/.*/Application/.* }]
    - name: Infrastructure
      collectors: [{ type: directory, regex: src/.*/Infrastructure/.* }]
    - name: Presentation
      collectors: [{ type: directory, regex: src/.*/Presentation/.* }]

  ruleset:
    Domain: ~
    Application: [Domain]
    Infrastructure: [Application, Domain]
    Presentation: [Application, Infrastructure, Domain]
```

Run: `vendor/bin/deptrac --config-file=deptrac/deptrac.yaml`

## Aggregate Root

The Aggregate Root is the entry point to the aggregate. All modifications go through it.

```php
<?php

declare(strict_types=1);

namespace App\Order\Domain;

use App\Order\Domain\Event\OrderWasCreated;
use App\Order\Domain\Event\OrderWasCancelled;
use App\Order\Domain\Exception\OrderCannotBeCancelledException;
use App\Order\Domain\ValueObject\Address;
use DateTimeImmutable;
use Symfony\Component\Uid\Uuid;

class Order
{
    private Uuid $id;
    private string $name;
    private OrderStatus $status;
    private Address $address;
    private Uuid $customerId;
    private DateTimeImmutable $createdAt;
    private ?DateTimeImmutable $updatedAt = null;

    /** @var list<OrderItem> */
    private array $items = [];

    /** @var list<object> */
    private array $domainEvents = [];

    private function __construct() {}

    public static function create(
        Uuid $id,
        string $name,
        Uuid $customerId,
        Address $address,
        OrderStatus $status = OrderStatus::Pending,
    ): self {
        $order = new self();
        $order->id = $id;
        $order->name = $name;
        $order->customerId = $customerId;
        $order->address = $address;
        $order->status = $status;
        $order->createdAt = new DateTimeImmutable();

        $order->recordEvent(new OrderWasCreated(
            orderId: $id,
            name: $name,
            customerId: $customerId,
        ));

        return $order;
    }

    public function cancel(string $reason): void
    {
        if ($this->status === OrderStatus::Cancelled) {
            throw new OrderCannotBeCancelledException('Order is already cancelled');
        }

        if ($this->status === OrderStatus::Shipped) {
            throw new OrderCannotBeCancelledException('Cannot cancel a shipped order');
        }

        $this->status = OrderStatus::Cancelled;
        $this->updatedAt = new DateTimeImmutable();

        $this->recordEvent(new OrderWasCancelled(
            orderId: $this->id,
            reason: $reason,
        ));
    }

    public function addItem(Uuid $productId, int $quantity, int $priceInCents): void
    {
        $this->items[] = OrderItem::create(
            orderId: $this->id,
            productId: $productId,
            quantity: $quantity,
            priceInCents: $priceInCents,
        );
        $this->updatedAt = new DateTimeImmutable();
    }

    // Getters (immutable public API)
    public function getId(): Uuid { return $this->id; }
    public function getName(): string { return $this->name; }
    public function getStatus(): OrderStatus { return $this->status; }
    public function getCustomerId(): Uuid { return $this->customerId; }
    public function getAddress(): Address { return $this->address; }
    public function getCreatedAt(): DateTimeImmutable { return $this->createdAt; }

    /** @return list<OrderItem> */
    public function getItems(): array { return $this->items; }

    private function recordEvent(object $event): void
    {
        $this->domainEvents[] = $event;
    }

    /** @return list<object> */
    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];

        return $events;
    }
}
```

### Aggregate Root Conventions

- **Private constructor** — use factory methods (`create()`, `reconstitute()`).
- **All state changes** go through methods on the aggregate — never set properties directly from outside.
- **Domain events** are recorded via `recordEvent()` and pulled by infrastructure after persistence.
- **Business rules** are enforced in the aggregate methods (e.g., cannot cancel a shipped order).
- **Getters only** — no public setters. State mutation happens through behavior methods.

## Value Objects

Value Objects have no identity and are immutable.

```php
<?php

declare(strict_types=1);

namespace App\Order\Domain\ValueObject;

class Address
{
    public function __construct(
        public readonly string $street,
        public readonly string $postalCode,
        public readonly string $city,
        public readonly string $country,
    ) {}

    public function equals(self $other): bool
    {
        return $this->street === $other->street
            && $this->postalCode === $other->postalCode
            && $this->city === $other->city
            && $this->country === $other->country;
    }
}
```

```php
<?php

declare(strict_types=1);

namespace App\Shared\Domain\ValueObject;

class Money
{
    public function __construct(
        public readonly int $amount,
        public readonly string $currency = 'PLN',
    ) {}

    public function add(self $other): self
    {
        if ($this->currency !== $other->currency) {
            throw new \InvalidArgumentException('Cannot add different currencies');
        }

        return new self(
            amount: $this->amount + $other->amount,
            currency: $this->currency,
        );
    }

    public function equals(self $other): bool
    {
        return $this->amount === $other->amount
            && $this->currency === $other->currency;
    }
}
```

### Value Object Conventions

- Use `readonly` constructor properties.
- Provide `equals()` method for comparison.
- Return new instances for mutation (immutable): `$newMoney = $money->add($other)`.
- No identity field (no `$id`).

## Domain Events

```php
<?php

declare(strict_types=1);

namespace App\Order\Domain\Event;

use Symfony\Component\Uid\Uuid;

class OrderWasCreated
{
    public function __construct(
        public readonly Uuid $orderId,
        public readonly string $name,
        public readonly Uuid $customerId,
    ) {}
}
```

### Event Dispatching

Events are dispatched by infrastructure after persistence:

```php
// In repository or event-aware middleware
$order = $this->entityManager->find(Order::class, $id);
$events = $order->pullDomainEvents();

foreach ($events as $event) {
    $this->eventBus->dispatch($event);
}
```

## Domain Exceptions

```php
<?php

declare(strict_types=1);

namespace App\Order\Domain\Exception;

class OrderNotFoundException extends \RuntimeException
{
    public static function withId(string $id): self
    {
        return new self(sprintf('Order with ID "%s" was not found', $id));
    }
}
```

```php
<?php

declare(strict_types=1);

namespace App\Order\Domain\Exception;

class OrderCannotBeCancelledException extends \DomainException
{
    public function __construct(string $reason)
    {
        parent::__construct(sprintf('Order cannot be cancelled: %s', $reason));
    }
}
```

### Exception Conventions

- Use `\RuntimeException` subclass for "not found" errors.
- Use `\DomainException` subclass for business rule violations.
- Use `\InvalidArgumentException` for invalid inputs.
- Provide static factory methods for common scenarios: `::withId()`, `::because()`.
- Domain exceptions are thrown in Domain, caught and mapped to HTTP responses in Presentation.

## Cross-Context Communication

### Via Domain Events (preferred)

Context A dispatches event → Symfony Messenger → Context B listens:

```php
// Order context dispatches OrderWasCreated
// Inventory context listens:
#[AsMessageHandler(bus: 'event_bus')]
class ReserveStockOnOrderCreated
{
    public function __invoke(OrderWasCreated $event): void
    {
        // Reserve stock in Inventory context
    }
}
```

### Via Application Service (synchronous, when needed)

```php
// Order context calls Inventory Application Service
// Never access Inventory Domain directly
$this->inventoryService->reserveStock($productId, $quantity);
```

## Testing DDD Layers

### Domain Tests (pure unit tests, no framework)

```php
class OrderTest extends TestCase
{
    public function testCreateOrderDefaultStatusIsPending(): void
    {
        $order = Order::create(
            id: Uuid::v4(),
            name: 'Test',
            customerId: Uuid::v4(),
            address: new Address('Street', '00-000', 'City', 'PL'),
        );

        self::assertSame(OrderStatus::Pending, $order->getStatus());
    }

    public function testCancelShippedOrderThrowsException(): void
    {
        // ... create shipped order
        $this->expectException(OrderCannotBeCancelledException::class);
        $order->cancel('Changed mind');
    }
}
```

### Application Tests (with fakes)

```php
class CreateOrderCommandHandlerTest extends TestCase
{
    public function testCreateOrderSavesToRepository(): void
    {
        $repository = new FakeOrderRepository();
        $handler = new CreateOrderCommandHandler($repository);

        ($handler)(new CreateOrderCommand(name: 'Test', customerId: Uuid::v4()->toRfc4122()));

        self::assertCount(1, $repository->findAll());
    }
}
```

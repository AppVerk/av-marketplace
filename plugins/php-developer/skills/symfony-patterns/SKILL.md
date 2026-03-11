---
name: symfony-patterns
description: Enforces Symfony patterns with DDD: thin controllers, Messenger CQRS, autowiring, security, routing attributes. Activates when working with Symfony controllers, services, or configuration.
allowed-tools: Read, Grep, Glob, Bash(php:*), Bash(composer:*), Bash(vendor/bin/*), Bash(bin/*), Bash(make:*), Bash(git:*)
---

# Symfony Patterns

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER put business logic in controllers — controllers only authorize and dispatch commands/queries
- ALWAYS use constructor injection — NEVER setter injection or service locator pattern
- ALWAYS use PHP 8 Attributes for routing (`#[Route]`), not YAML or XML routes
- NEVER call `$container->get()` directly — ALWAYS use autowiring and dependency injection
- ALWAYS use Symfony Messenger for command/query dispatching when Messenger is detected in the project
- NEVER return domain objects from command handlers — commands are void, use queries for reads
- ALWAYS use `#[AsMessageHandler]` attribute on command/query handlers
- NEVER use annotations (`@Route`, `@Assert`) — ALWAYS use PHP 8 Attributes (`#[Route]`, `#[Assert\NotBlank]`)
</HARD-RULES>

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│  Presentation Layer (Controllers)                │
│  Receives HTTP request → dispatches Command/Query│
│  Returns HTTP response                           │
├─────────────────────────────────────────────────┤
│  Application Layer (Command/Query Handlers)      │
│  Orchestrates use case logic                     │
│  Uses domain services and repositories           │
├─────────────────────────────────────────────────┤
│  Domain Layer (Entities, Value Objects, Events)   │
│  Pure business logic, no framework dependencies  │
├─────────────────────────────────────────────────┤
│  Infrastructure Layer (Repositories, Services)    │
│  Implements domain interfaces using framework    │
└─────────────────────────────────────────────────┘
```

## Controller Pattern

Controllers must be thin — only authorization check and command/query dispatching.

```php
<?php

declare(strict_types=1);

namespace App\Order\Presentation\Api\Controller;

use App\Order\Application\Api\Command\CreateOrderCommand;
use App\Order\Application\Api\Query\GetOrderQuery;
use App\Order\Application\Api\Command\DeleteOrderCommand;
use App\Order\Application\Api\Query\GetOrdersQuery;
use App\Shared\Domain\PermissionEnum;
use App\Shared\Presentation\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Routing\Attribute\Route;

#[Route('/api/orders', name: 'api_orders_')]
class OrderController extends AbstractController
{
    #[Route(name: 'create', methods: [Request::METHOD_POST])]
    public function create(CreateOrderCommand $command): Response
    {
        $this->assertPermission(PermissionEnum::ORDER_MANAGEMENT);
        $this->dispatchCommand($command);

        return $this->emptyResponse();
    }

    #[Route(name: 'list', methods: [Request::METHOD_GET])]
    public function list(GetOrdersQuery $query): Response
    {
        $this->assertPermission(PermissionEnum::ORDER_VIEW);

        return $this->successResponse($this->dispatchQuery($query));
    }

    #[Route('/{id}', name: 'details', methods: [Request::METHOD_GET])]
    public function details(GetOrderQuery $query): Response
    {
        $this->assertPermission(PermissionEnum::ORDER_VIEW);

        return $this->successResponse($this->dispatchQuery($query));
    }

    #[Route('/{id}', name: 'delete', methods: [Request::METHOD_DELETE])]
    public function delete(DeleteOrderCommand $command): Response
    {
        $this->assertPermission(PermissionEnum::ORDER_MANAGEMENT);
        $this->dispatchCommand($command);

        return $this->emptyResponse();
    }
}
```

### Controller Conventions

- Use `#[Route]` attribute with `name` and `methods` parameters.
- Method parameter injection — framework auto-deserializes request body into Command/Query DTOs.
- `dispatchCommand()` for write operations (returns void).
- `dispatchQuery()` for read operations (returns data).
- `emptyResponse()` for 204 No Content, `successResponse($data)` for 200 OK.
- Permission checks via `assertPermission()` before dispatching.
- NEVER instantiate services in controllers — use constructor injection.

## Symfony Messenger CQRS

### Command Pattern

```php
<?php

declare(strict_types=1);

namespace App\Order\Application\Api\Command;

// Command DTO — immutable message object
class CreateOrderCommand
{
    public function __construct(
        public readonly string $name,
        public readonly string $customerId,
        public readonly ?string $description = null,
    ) {}
}
```

### Command Handler

```php
<?php

declare(strict_types=1);

namespace App\Order\Application\Api\Command;

use App\Order\Domain\Order;
use App\Order\Domain\OrderRepositoryInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Symfony\Component\Uid\Uuid;

#[AsMessageHandler(bus: 'command_bus')]
class CreateOrderCommandHandler
{
    public function __construct(
        private readonly OrderRepositoryInterface $repository,
    ) {}

    public function __invoke(CreateOrderCommand $command): void
    {
        $order = Order::create(
            id: Uuid::v4(),
            name: $command->name,
            customerId: Uuid::fromString($command->customerId),
        );

        $this->repository->save($order);
    }
}
```

### Query Pattern

```php
<?php

declare(strict_types=1);

namespace App\Order\Application\Api\Query;

class GetOrderQuery
{
    public function __construct(
        public readonly string $id,
    ) {}
}
```

### Query Handler

```php
<?php

declare(strict_types=1);

namespace App\Order\Application\Api\Query;

use App\Order\Application\Api\View\OrderView;
use App\Order\Domain\OrderRepositoryInterface;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;
use Symfony\Component\Uid\Uuid;

#[AsMessageHandler(bus: 'query_bus')]
class GetOrderQueryHandler
{
    public function __construct(
        private readonly OrderRepositoryInterface $repository,
    ) {}

    public function __invoke(GetOrderQuery $query): OrderView
    {
        $order = $this->repository->findOne(Uuid::fromString($query->id));

        return OrderView::fromDomain($order);
    }
}
```

### Messenger Configuration

```yaml
# config/packages/messenger.yaml
framework:
    messenger:
        default_bus: command_bus
        buses:
            command_bus:
                middleware:
                    - doctrine_transaction
            query_bus: ~
            event_bus:
                default_middleware:
                    allow_no_handlers: true
```

## Dependency Injection

### Constructor Injection (Always)

```php
class OrderService
{
    public function __construct(
        private readonly OrderRepositoryInterface $repository,
        private readonly EventBusInterface $eventBus,
        private readonly LoggerInterface $logger,
    ) {}
}
```

### Autowiring with Attributes

```php
use Symfony\Component\DependencyInjection\Attribute\Autowire;

class ReportGenerator
{
    public function __construct(
        #[Autowire('%kernel.project_dir%/var/reports')]
        private readonly string $reportsDir,
        #[Autowire(service: 'app.custom_mailer')]
        private readonly MailerInterface $mailer,
    ) {}
}
```

### Tagged Services

```php
use Symfony\Component\DependencyInjection\Attribute\AutoconfigureTag;

#[AutoconfigureTag('app.notification_channel')]
interface NotificationChannelInterface
{
    public function send(Notification $notification): void;
}
```

## Security

### Voters for Authorization

```php
<?php

declare(strict_types=1);

namespace App\Order\Infrastructure\Security;

use App\Order\Domain\Order;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Authorization\Voter\Voter;

class OrderVoter extends Voter
{
    protected function supports(string $attribute, mixed $subject): bool
    {
        return $subject instanceof Order && in_array($attribute, ['VIEW', 'EDIT', 'DELETE'], true);
    }

    protected function voteOnAttribute(string $attribute, mixed $subject, TokenInterface $token): bool
    {
        $user = $token->getUser();

        return match ($attribute) {
            'VIEW' => true,
            'EDIT', 'DELETE' => $subject->getCreatedById() === $user->getId(),
            default => false,
        };
    }
}
```

## Event Listeners

```php
<?php

declare(strict_types=1);

namespace App\Order\Infrastructure\EventListener;

use App\Order\Domain\Event\OrderWasCreated;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler(bus: 'event_bus')]
class SendOrderConfirmationListener
{
    public function __construct(
        private readonly MailerInterface $mailer,
    ) {}

    public function __invoke(OrderWasCreated $event): void
    {
        // Handle domain event
    }
}
```

## Environment Configuration

```yaml
# .env
DATABASE_URL="postgresql://user:pass@localhost:5432/app"
APP_SECRET=your-secret-key

# .env.local (not committed)
DATABASE_URL="postgresql://dev:dev@localhost:5432/app_dev"
```

Access in services via `%env()%`:

```yaml
# config/services.yaml
parameters:
    app.api_key: '%env(API_KEY)%'
    app.redis_url: '%env(REDIS_URL)%'
```

## Common Mistakes

```php
// BAD: Business logic in controller
#[Route('/orders', methods: ['POST'])]
public function create(Request $request): Response
{
    $data = json_decode($request->getContent(), true);
    $order = new Order($data['name']);
    $this->entityManager->persist($order);  // Direct EM usage
    $this->entityManager->flush();
    return new JsonResponse($order->toArray());
}

// GOOD: Controller only dispatches
#[Route('/orders', name: 'create', methods: [Request::METHOD_POST])]
public function create(CreateOrderCommand $command): Response
{
    $this->assertPermission(PermissionEnum::ORDER_MANAGEMENT);
    $this->dispatchCommand($command);
    return $this->emptyResponse();
}
```

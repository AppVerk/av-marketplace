---
name: doctrine-orm-patterns
description: Enforces Doctrine ORM patterns: mapping (YAML/XML/Attributes), repositories, migrations, QueryBuilder, filters, performance. Activates when working with database models, repositories, queries, or migrations.
allowed-tools: Read, Grep, Glob, Bash(php:*), Bash(composer:*), Bash(vendor/bin/*), Bash(bin/*), Bash(make:*), Bash(git:*)
---

# Doctrine ORM Patterns

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

**Mapping & Schema:**
- NEVER write raw SQL for schema changes — ALWAYS use Doctrine Migrations (`doctrine:migrations:diff`)
- NEVER manually create migration files — ALWAYS generate with `doctrine:migrations:diff` and review
- NEVER manually edit migration files unless adding data migrations
- ALWAYS detect and follow the project's mapping format (YAML, XML, or Attributes) — do not mix formats

**Types & Data:**
- NEVER use `DateTime` — ALWAYS use `DateTimeImmutable`
- ALWAYS use UUID primary keys when the project follows this convention
- ALWAYS use `Symfony\Component\Uid\Uuid` (not `Ramsey\Uuid` unless project already uses it)

**Queries:**
- NEVER concatenate strings in DQL or QueryBuilder — ALWAYS use named parameters (`:paramName`)
- NEVER use `$entityManager` directly in controllers or command handlers — use repositories
- ALWAYS use `setParameter()` with named parameters for all query conditions

**Architecture:**
- ALWAYS define repository interfaces in the Domain layer — implementations live in Infrastructure
- NEVER return Doctrine proxy objects outside the repository — map to domain entities or DTOs
</HARD-RULES>

## Mapping Format Detection

At the start of each task, detect the project's mapping format:

1. **YAML mapping:** Look for `*.orm.yml` files in `Infrastructure/Persistence/Doctrine/Mapping/`
2. **XML mapping:** Look for `*.orm.xml` files in similar paths
3. **PHP Attributes:** Look for `#[ORM\Entity]` in entity classes

**Follow whichever format the project uses.** Never mix formats within a project.

## YAML Mapping Example

```yaml
# src/Order/Infrastructure/Persistence/Doctrine/Mapping/Order.orm.yml
App\Order\Domain\Order:
  type: entity
  table: orders
  repositoryClass: App\Order\Infrastructure\Persistence\Doctrine\Repository\DoctrineOrderRepository
  id:
    id:
      type: uuid
      nullable: false
      generator:
        strategy: NONE
  fields:
    name:
      type: string
      length: 255
    status:
      type: string
      enumType: App\Order\Domain\OrderStatus
    createdAt:
      type: datetime_immutable
      column: created_at
    updatedAt:
      type: datetime_immutable
      column: updated_at
      nullable: true
  embedded:
    address:
      class: App\Order\Domain\Address
  manyToOne:
    customer:
      targetEntity: App\Customer\Domain\Customer
      joinColumn:
        name: customer_id
        referencedColumnName: id
        nullable: false
```

## PHP Attributes Mapping Example

```php
<?php

declare(strict_types=1);

namespace App\Order\Domain;

use DateTimeImmutable;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Uid\Uuid;

#[ORM\Entity(repositoryClass: DoctrineOrderRepository::class)]
#[ORM\Table(name: 'orders')]
class Order
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid')]
    private Uuid $id;

    #[ORM\Column(length: 255)]
    private string $name;

    #[ORM\Column(enumType: OrderStatus::class)]
    private OrderStatus $status;

    #[ORM\Column(type: 'datetime_immutable')]
    private DateTimeImmutable $createdAt;

    #[ORM\Embedded(class: Address::class)]
    private Address $address;

    #[ORM\ManyToOne(targetEntity: Customer::class)]
    #[ORM\JoinColumn(nullable: false)]
    private Customer $customer;
}
```

## Repository Pattern

### Domain Interface

```php
<?php

declare(strict_types=1);

namespace App\Order\Domain;

use Symfony\Component\Uid\Uuid;

interface OrderRepositoryInterface
{
    public function findById(Uuid $id): ?Order;

    public function findOne(Uuid $id): Order;

    public function save(Order $order): void;

    public function delete(Order $order): void;

    /** @return list<Order> */
    public function findAll(int $offset = 0, int $limit = 100): array;
}
```

### Doctrine Implementation

```php
<?php

declare(strict_types=1);

namespace App\Order\Infrastructure\Persistence\Doctrine\Repository;

use App\Order\Domain\Order;
use App\Order\Domain\OrderNotFoundException;
use App\Order\Domain\OrderRepositoryInterface;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;
use Symfony\Component\Uid\Uuid;

class DoctrineOrderRepository extends ServiceEntityRepository implements OrderRepositoryInterface
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, Order::class);
    }

    public function findById(Uuid $id): ?Order
    {
        return $this->find($id);
    }

    public function findOne(Uuid $id): Order
    {
        $order = $this->find($id);
        if (null === $order) {
            throw new OrderNotFoundException(sprintf('Order %s not found', $id->toRfc4122()));
        }

        return $order;
    }

    public function save(Order $order): void
    {
        $this->getEntityManager()->persist($order);
        $this->getEntityManager()->flush();
    }

    public function delete(Order $order): void
    {
        $this->getEntityManager()->remove($order);
        $this->getEntityManager()->flush();
    }

    /** @return list<Order> */
    public function findAll(int $offset = 0, int $limit = 100): array
    {
        return $this->createQueryBuilder('o')
            ->setFirstResult($offset)
            ->setMaxResults($limit)
            ->orderBy('o.createdAt', 'DESC')
            ->getQuery()
            ->getResult();
    }
}
```

## QueryBuilder Patterns

### Always Use Named Parameters

```php
// GOOD: Named parameters
$qb = $this->createQueryBuilder('o')
    ->andWhere('o.status = :status')
    ->andWhere('o.createdAt >= :startDate')
    ->setParameter('status', OrderStatus::Active->value)
    ->setParameter('startDate', $startDate);

// BAD: String concatenation (SQL injection risk)
$qb = $this->createQueryBuilder('o')
    ->andWhere("o.status = '" . $status . "'");
```

### Filtering

```php
public function findByFilters(
    ?OrderStatus $status = null,
    ?DateTimeImmutable $startDate = null,
    ?string $searchTerm = null,
    int $offset = 0,
    int $limit = 50,
): array {
    $qb = $this->createQueryBuilder('o');

    if (null !== $status) {
        $qb->andWhere('o.status = :status')
            ->setParameter('status', $status->value);
    }

    if (null !== $startDate) {
        $qb->andWhere('o.createdAt >= :startDate')
            ->setParameter('startDate', $startDate);
    }

    if (null !== $searchTerm) {
        $qb->andWhere('o.name LIKE :search')
            ->setParameter('search', '%' . $searchTerm . '%');
    }

    return $qb
        ->orderBy('o.createdAt', 'DESC')
        ->setFirstResult($offset)
        ->setMaxResults($limit)
        ->getQuery()
        ->getResult();
}
```

### Joins and Eager Loading

```php
// Prevent N+1: join fetch related entities
$qb = $this->createQueryBuilder('o')
    ->leftJoin('o.customer', 'c')
    ->addSelect('c')
    ->leftJoin('o.items', 'i')
    ->addSelect('i')
    ->where('o.id = :id')
    ->setParameter('id', $id);
```

## Embedded Value Objects

```yaml
# YAML mapping for embedded value object
App\Shared\Domain\Address:
  type: embeddable
  fields:
    street:
      type: string
      length: 255
    postalCode:
      type: string
      length: 20
      column: postal_code
    city:
      type: string
      length: 100
    country:
      type: string
      length: 2
```

```php
// Domain value object
class Address
{
    public function __construct(
        public readonly string $street,
        public readonly string $postalCode,
        public readonly string $city,
        public readonly string $country,
    ) {}
}
```

## Custom Doctrine Types

```php
<?php

declare(strict_types=1);

namespace App\Order\Infrastructure\Persistence\Doctrine\Types;

use App\Order\Domain\Money;
use Doctrine\DBAL\Platforms\AbstractPlatform;
use Doctrine\DBAL\Types\JsonType;

class MoneyType extends JsonType
{
    public const NAME = 'money_type';

    public function convertToPHPValue(mixed $value, AbstractPlatform $platform): ?Money
    {
        if (null === $value) {
            return null;
        }

        $data = json_decode((string) $value, true, 512, JSON_THROW_ON_ERROR);

        return new Money(
            amount: $data['amount'],
            currency: $data['currency'],
        );
    }

    public function convertToDatabaseValue(mixed $value, AbstractPlatform $platform): ?string
    {
        if (null === $value) {
            return null;
        }

        return json_encode([
            'amount' => $value->amount,
            'currency' => $value->currency,
        ], JSON_THROW_ON_ERROR);
    }

    public function getName(): string
    {
        return self::NAME;
    }
}
```

## Doctrine Filters

```php
<?php

declare(strict_types=1);

namespace App\Shared\Infrastructure\Persistence\Doctrine\Filters;

use Doctrine\ORM\Mapping\ClassMetadata;
use Doctrine\ORM\Query\Filter\SQLFilter;

class SoftDeleteFilter extends SQLFilter
{
    public function addFilterConstraint(ClassMetadata $targetEntity, string $targetTableAlias): string
    {
        if (!$targetEntity->hasField('deletedAt')) {
            return '';
        }

        return sprintf('%s.deleted_at IS NULL', $targetTableAlias);
    }
}
```

Enable/disable filters in repositories when needed:

```php
$this->getEntityManager()->getFilters()->disable('soft_delete');
// ... query including soft-deleted records
$this->getEntityManager()->getFilters()->enable('soft_delete');
```

## Migration Workflow

```bash
# 1. Make entity/mapping changes

# 2. Generate migration
bin/console doctrine:migrations:diff

# 3. Review the generated migration file

# 4. Apply migration
bin/console doctrine:migrations:migrate

# 5. Verify
bin/console doctrine:migrations:status
```

### Migration Conventions

- NEVER manually create migration files — always use `doctrine:migrations:diff`
- ALWAYS review auto-generated migrations before applying
- One logical change per migration
- Data migrations: write explicit SQL statements in the migration, never import entity classes

## Performance

### Avoid N+1 Queries

```php
// BAD: N+1 — each order->getItems() triggers a query
$orders = $this->findAll();
foreach ($orders as $order) {
    $items = $order->getItems(); // Lazy load = separate query
}

// GOOD: Join fetch in the query
$orders = $this->createQueryBuilder('o')
    ->leftJoin('o.items', 'i')
    ->addSelect('i')
    ->getQuery()
    ->getResult();
```

### Use Pagination for Large Results

```php
use Doctrine\ORM\Tools\Pagination\Paginator;

$query = $this->createQueryBuilder('o')
    ->setFirstResult($offset)
    ->setMaxResults($limit)
    ->getQuery();

$paginator = new Paginator($query);
$total = count($paginator);
```

### Select Only Needed Columns (for read-only views)

```php
// Return array of scalar values instead of full entities
$qb = $this->createQueryBuilder('o')
    ->select('o.id, o.name, o.status, o.createdAt')
    ->where('o.status = :status')
    ->setParameter('status', 'active');

$results = $qb->getQuery()->getArrayResult();
```

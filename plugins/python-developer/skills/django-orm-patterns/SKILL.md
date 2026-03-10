---
name: django-orm-patterns
description: Enforces Django ORM patterns with Pragmatic DDD: rich domain models, Managers, QuerySets, migrations, signals, performance. Activates when working with Django models, queries, or migrations.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(manage.py:*), Bash(django-admin:*)
---

# Django ORM Patterns (Pragmatic DDD)

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

**Models:**

- NEVER put business logic in `save()` overrides for complex operations — use explicit model methods or services
- NEVER use `null=True` on `CharField`/`TextField` — use `blank=True, default=""`
- NEVER use `ForeignKey` without explicit `on_delete`
- NEVER use `ForeignKey` without `related_name`
- ALWAYS use `db_index=True` on fields used in filters/lookups (or `Meta.indexes`)
- ALWAYS create abstract base models for shared fields (`TimeStampedModel` with `created_at`, `updated_at`)
- ALWAYS define `__str__` method on every model
- ALWAYS define `class Meta: ordering`, `verbose_name`, `verbose_name_plural`
- ALWAYS use `UniqueConstraint` / `CheckConstraint` in `Meta.constraints` — NEVER deprecated `unique_together`

**Managers & QuerySets:**

- NEVER put complex queries in views/services — encapsulate in custom QuerySet methods
- ALWAYS use `MyQuerySet.as_manager()` or `Manager.from_queryset()`
- ALWAYS name QuerySet methods as domain concepts (`published()`, `active()`, `for_user(user)`)
- NEVER use raw SQL unless QuerySet API is genuinely insufficient — prefer `.annotate()`, `.aggregate()`, `F()`, `Q()`

**Performance:**

- NEVER cause N+1 queries — ALWAYS use `select_related()` (FK/OneToOne) and `prefetch_related()` (M2M/reverse FK)
- ALWAYS use `only()` / `defer()` for large models when only subset of fields needed
- ALWAYS use `bulk_create()` / `bulk_update()` for batch operations — NEVER loops with `.save()`
- ALWAYS use `iterator()` for large querysets in management commands / background tasks

**Migrations:**

- NEVER edit auto-generated migrations unless necessary (data migrations, RunSQL)
- ALWAYS separate data migrations from schema migrations
- ALWAYS use `RunPython` with `reverse_code` for reversible data migrations
- NEVER run `migrate` in production without review — ALWAYS review generated SQL with `sqlmigrate`

**Signals:**

- NEVER use signals for core business logic — use explicit model methods or services
- Signals ONLY for decoupled side effects (cache invalidation, audit logging, denormalization)
- ALWAYS use `dispatch_uid` to prevent duplicate signal registration

**Quality:**

- ALWAYS run the project's typecheck and test commands after any model change
</HARD-RULES>

These are the Django ORM patterns for AppVerk projects, following **Pragmatic DDD** where Django Models serve as rich domain models with business logic. All patterns target **Python 3.13+**, **Django 5.1+**.

## Rich Domain Model Pattern

Abstract base model for shared timestamps. Models contain domain methods — they ARE the domain entities.

```python
# apps/core/models.py
from django.db import models


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True
```

```python
# apps/orders/models.py
from django.db import models
from django.utils.translation import gettext_lazy as _

from apps.core.models import TimeStampedModel
from apps.orders.exceptions import DomainValidationError


class Order(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending", _("Pending")
        CONFIRMED = "confirmed", _("Confirmed")
        CANCELLED = "cancelled", _("Cancelled")

    user = models.ForeignKey(
        "auth.User",
        on_delete=models.PROTECT,
        related_name="orders",
        db_index=True,
    )
    product = models.ForeignKey(
        "products.Product",
        on_delete=models.PROTECT,
        related_name="orders",
        db_index=True,
    )
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PENDING,
        db_index=True,
    )
    total_amount = models.DecimalField(max_digits=10, decimal_places=2)

    objects: "OrderManager"

    class Meta:
        ordering = ["-created_at"]
        verbose_name = _("order")
        verbose_name_plural = _("orders")
        constraints = [
            models.UniqueConstraint(
                fields=["user", "product"],
                condition=models.Q(status="pending"),
                name="unique_pending_order_per_user_product",
            ),
            models.CheckConstraint(
                check=models.Q(total_amount__gte=0),
                name="order_total_amount_non_negative",
            ),
        ]

    def __str__(self) -> str:
        return f"Order #{self.pk} — {self.user_id} ({self.status})"

    # --- Domain methods ---

    def can_cancel(self) -> bool:
        return self.status == self.Status.PENDING

    def cancel(self) -> None:
        if not self.can_cancel():
            raise DomainValidationError(
                f"Cannot cancel order in status '{self.status}'."
            )
        self.status = self.Status.CANCELLED
        self.save(update_fields=["status", "updated_at"])
```

## Managers & QuerySets

Encapsulate all non-trivial query logic in custom QuerySet methods named after domain concepts.

```python
# apps/orders/managers.py
from django.db import models


class OrderQuerySet(models.QuerySet["Order"]):  # type: ignore[name-defined]
    def active(self) -> "OrderQuerySet":
        return self.exclude(status="cancelled")

    def for_user(self, user: "AbstractBaseUser") -> "OrderQuerySet":  # type: ignore[name-defined]
        return self.filter(user=user)

    def with_totals(self) -> "OrderQuerySet":
        from django.db.models import Sum
        return self.annotate(item_total=Sum("items__price"))


OrderManager = OrderQuerySet.as_manager()
```

```python
# apps/orders/models.py  (add to Order)
objects = OrderQuerySet.as_manager()
```

Usage — chain QuerySet methods in views or services:

```python
# In a service or ViewSet.get_queryset()
queryset = (
    Order.objects
    .for_user(request.user)
    .active()
    .select_related("product")
    .order_by("-created_at")
)
```

## Model Definition Patterns

### ForeignKey conventions

```python
# Good: explicit on_delete, related_name, db_index
user = models.ForeignKey(
    "auth.User",
    on_delete=models.PROTECT,   # PROTECT prevents accidental cascades
    related_name="orders",
    db_index=True,
)
```

### Composite indexes

```python
class Meta:
    indexes = [
        models.Index(fields=["user", "status"], name="order_user_status_idx"),
        models.Index(fields=["created_at", "status"], name="order_created_status_idx"),
    ]
```

### Constraints

```python
class Meta:
    constraints = [
        # Unique constraint (replaces deprecated unique_together)
        models.UniqueConstraint(fields=["user", "product"], name="unique_user_product"),
        # Check constraint enforced at DB level
        models.CheckConstraint(
            check=models.Q(quantity__gt=0),
            name="order_quantity_positive",
        ),
    ]
```

## Performance Patterns

### select_related vs prefetch_related

| Relationship | Use | Notes |
|---|---|---|
| `ForeignKey` / `OneToOne` | `select_related()` | SQL JOIN; one query |
| `ManyToMany` / reverse FK | `prefetch_related()` | Separate query; Python join |
| Filtered reverse FK | `Prefetch(queryset=...)` | Custom queryset per prefetch |

```python
# Prefetch with custom queryset (avoid loading all items)
from django.db.models import Prefetch
from apps.orders.models import Order, OrderItem

orders = Order.objects.prefetch_related(
    Prefetch(
        "items",
        queryset=OrderItem.objects.filter(is_active=True).only("id", "price"),
        to_attr="active_items",
    )
)
```

### Bulk operations

```python
# bulk_create — never loop with .save()
items = [OrderItem(order=order, product_id=pid, price=p) for pid, p in products]
OrderItem.objects.bulk_create(items, batch_size=500)

# bulk_update — only update changed fields
for item in items:
    item.price = calculate_price(item)
OrderItem.objects.bulk_update(items, fields=["price"], batch_size=500)
```

### iterator() for large datasets

```python
# Management command / background task — avoids loading entire QS into memory
for order in Order.objects.filter(status="pending").iterator(chunk_size=200):
    process_order(order)
```

## Migration Patterns

### Data migration with RunPython

```python
# apps/orders/migrations/0005_backfill_total_amount.py
from django.db import migrations, models


def backfill_totals(apps, schema_editor):
    Order = apps.get_model("orders", "Order")
    for order in Order.objects.iterator(chunk_size=500):
        order.total_amount = order.items.aggregate(
            total=models.Sum("price")
        )["total"] or 0
        order.save(update_fields=["total_amount"])


def reverse_backfill(apps, schema_editor):
    Order = apps.get_model("orders", "Order")
    Order.objects.update(total_amount=0)


class Migration(migrations.Migration):
    dependencies = [("orders", "0004_order_total_amount")]

    operations = [
        migrations.RunPython(backfill_totals, reverse_code=reverse_backfill),
    ]
```

Use `RunSQL` only when Django ORM cannot express the operation (e.g., DB-specific functions, index creation with custom options).

## Signals

Use signals for decoupled **side effects only** — never for core business logic.

**Good uses:** cache invalidation, audit logging, denormalization, sending notifications.
**Bad uses:** changing the entity's own state, enforcing business rules, triggering other domain operations.

```python
# apps/orders/signals.py
from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.orders.models import Order


@receiver(
    post_save,
    sender=Order,
    dispatch_uid="orders.invalidate_order_cache",  # prevents duplicate registration
)
def invalidate_order_cache(sender, instance: Order, **kwargs) -> None:
    from django.core.cache import cache
    cache.delete(f"order:{instance.pk}")
```

Connect in `AppConfig.ready()`:

```python
# apps/orders/apps.py
from django.apps import AppConfig


class OrdersConfig(AppConfig):
    name = "apps.orders"

    def ready(self) -> None:
        import apps.orders.signals  # noqa: F401
```

## Optional Repository Pattern

Use when you need to: decouple services from Django ORM (e.g. testing without DB), or enforce a strict application-layer boundary.

For most views/services, direct QuerySet access is sufficient and preferred.

```python
# apps/orders/repositories.py
from typing import Protocol

from apps.orders.exceptions import EntityNotFoundError
from apps.orders.models import Order


class OrderRepositoryProtocol(Protocol):
    def get_by_id(self, order_id: int) -> Order: ...
    def list_for_user(self, user_id: int) -> list[Order]: ...
    def save(self, order: Order) -> None: ...


class DjangoOrderRepository:
    def get_by_id(self, order_id: int) -> Order:
        try:
            return Order.objects.select_related("product").get(pk=order_id)
        except Order.DoesNotExist:
            raise EntityNotFoundError(f"Order {order_id} not found.")

    def list_for_user(self, user_id: int) -> list[Order]:
        return list(Order.objects.for_user(user_id).active().select_related("product"))

    def save(self, order: Order) -> None:
        order.save()
```

## Testing Django ORM

Use `factory_boy` with `DjangoModelFactory` for all test data. Never call `Model.objects.create()` directly in tests.

```python
# apps/orders/tests/factories.py
import factory
from factory.django import DjangoModelFactory

from apps.orders.models import Order


class UserFactory(DjangoModelFactory):
    class Meta:
        model = "auth.User"

    username = factory.Sequence(lambda n: f"user_{n}")
    email = factory.LazyAttribute(lambda o: f"{o.username}@example.com")


class OrderFactory(DjangoModelFactory):
    class Meta:
        model = Order

    user = factory.SubFactory(UserFactory)
    product = factory.SubFactory("apps.products.tests.factories.ProductFactory")
    status = Order.Status.PENDING
    total_amount = factory.Faker("pydecimal", left_digits=4, right_digits=2, positive=True)
```

Unit test for a model method — no DB needed:

```python
# apps/orders/tests/test_models.py
import pytest

from apps.orders.exceptions import DomainValidationError
from apps.orders.models import Order


def test_can_cancel_returns_true_when_pending() -> None:
    order = Order(status=Order.Status.PENDING)
    assert order.can_cancel() is True


def test_cancel_raises_when_already_cancelled() -> None:
    order = Order(status=Order.Status.CANCELLED)
    with pytest.raises(DomainValidationError):
        order.cancel()
```

Integration test for a QuerySet method:

```python
@pytest.mark.django_db
class TestOrderQuerySet:
    def test_for_user_returns_only_own_orders(self) -> None:
        user = UserFactory()
        own = OrderFactory(user=user)
        OrderFactory()  # another user's order

        result = list(Order.objects.for_user(user))

        assert result == [own]

    def test_active_excludes_cancelled(self) -> None:
        OrderFactory(status=Order.Status.PENDING)
        OrderFactory(status=Order.Status.CANCELLED)

        assert Order.objects.active().count() == 1
```

Assert query count to catch N+1 regressions:

```python
@pytest.mark.django_db
def test_list_orders_no_n_plus_one(django_assert_num_queries) -> None:
    user = UserFactory()
    OrderFactory.create_batch(5, user=user)

    with django_assert_num_queries(2):  # 1 orders + 1 prefetch products
        orders = list(
            Order.objects.for_user(user).select_related("product")
        )
    assert len(orders) == 5
```

---
name: celery-patterns
description: Enforces Celery task patterns: idempotent design, retry strategies, error handling, testing with eager mode. Activates when working with Celery tasks, background jobs, or async workers.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(celery:*)
---

# Celery Patterns

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

**Task Design:**

- ALWAYS make tasks idempotent — calling N times produces the same result
- NEVER pass Django model instances as task arguments — ALWAYS pass IDs (primitive types: `int`, `str`, `UUID`)
- NEVER create long tasks without decomposition — ALWAYS split into subtasks for collection operations
- ALWAYS use `bind=True` for tasks needing `self` (retry, task info)
- ALWAYS use explicit `name` parameter — NEVER auto-generated task names (break on refactor)
- ALWAYS use `acks_late=True` + `reject_on_worker_lost=True` for tasks that must execute (at-least-once delivery)

**Retry & Error Handling:**

- NEVER use bare `except` in tasks — catch specific exceptions
- ALWAYS use `autoretry_for` + `retry_backoff=True` + `retry_backoff_max` + `max_retries` for retryable errors
- ALWAYS use `retry_jitter=True` to avoid thundering herd
- NEVER retry business logic errors (validation, not found) — only transient errors (network, external API)
- ALWAYS implement dead letter handling — `on_failure` callback or monitoring for failed tasks

**Organization:**

- ALWAYS use `shared_task` (not `app.task`) for reusability
- ALWAYS put tasks in `<app>/tasks.py` — one file per Django app
- NEVER create circular imports — task imports service/model, not the other way

**Configuration:**

- ALWAYS use `task_always_eager=True` in test settings (synchronous execution)
- ALWAYS use `task_eager_propagates=True` in tests (propagate exceptions)
- ALWAYS use `CELERY_` namespace prefix in Django settings (`config_from_object('django.conf:settings', namespace='CELERY')`)
- For non-Django projects (e.g., FastAPI): use `celery_app.conf.update()` with explicit config dict

**Quality:**

- ALWAYS run the project's typecheck and test commands after any task change
</HARD-RULES>

Celery patterns for background task processing. Framework-independent — works with Django, FastAPI, or standalone Python. All patterns target **Python 3.13+**, **Celery 5.4+**.

## Task Structure

One task per operation. Use `shared_task` with explicit `name`, `bind=True`, and retry configuration.

```python
# apps/orders/tasks.py
import logging
from uuid import UUID

import httpx
from celery import shared_task
from celery.utils.log import get_task_logger

from apps.notifications.exceptions import NotificationDeliveryError
from apps.orders.models import Order
from apps.orders.services import OrderService

logger: logging.Logger = get_task_logger(__name__)


@shared_task(
    bind=True,
    name="orders.send_order_confirmation",
    acks_late=True,
    reject_on_worker_lost=True,
    autoretry_for=(NotificationDeliveryError, httpx.TransportError),
    retry_backoff=True,
    retry_backoff_max=600,
    retry_jitter=True,
    max_retries=5,
)
def send_order_confirmation(self, order_id: int) -> None:
    """Send confirmation notification for a placed order."""
    try:
        order = Order.objects.get(pk=order_id)
    except Order.DoesNotExist:
        # Not found = business logic error; do NOT retry
        logger.error("Order %s not found, skipping confirmation", order_id)
        return

    OrderService.send_confirmation(order=order)
    logger.info("Confirmation sent for order %s", order_id)
```

Call by passing the ID, never the model instance:

```python
# correct
send_order_confirmation.delay(order.pk)

# wrong — never pass model instances
send_order_confirmation.delay(order)
```

## Idempotency Patterns

Tasks may execute more than once (retries, worker restarts). Design for safety.

**Check-before-act** — guard with a status check:

```python
@shared_task(bind=True, name="orders.charge_order", acks_late=True, reject_on_worker_lost=True)
def charge_order(self, order_id: int) -> None:
    order = Order.objects.get(pk=order_id)
    if order.status != Order.Status.PENDING:
        logger.info("Order %s already processed (status=%s), skipping", order_id, order.status)
        return
    OrderService.charge(order=order)
```

**DB uniqueness constraint** — let the database enforce deduplication:

```python
# Use update_or_create / get_or_create with a unique key derived from the operation
Payment.objects.get_or_create(
    order_id=order_id,
    defaults={"amount": amount, "status": Payment.Status.PENDING},
)
```

Idempotency matters because Celery guarantees **at-least-once** delivery with `acks_late=True`. A task that charges a card or sends an email must be safe to call twice.

## Task Decomposition

Long-running tasks over collections must be split into per-item subtasks. Use `group()` for fan-out.

```python
# apps/newsletters/tasks.py
from celery import group, shared_task

from apps.newsletters.models import Subscriber
from apps.newsletters.services import NewsletterService


@shared_task(
    name="newsletters.send_newsletter_batch",
    acks_late=True,
    reject_on_worker_lost=True,
)
def send_newsletter_batch(newsletter_id: int) -> None:
    """Fan-out: spawn one task per subscriber."""
    subscriber_ids = list(
        Subscriber.objects.filter(active=True).values_list("id", flat=True)
    )
    job = group(send_newsletter_to_subscriber.s(newsletter_id, sid) for sid in subscriber_ids)
    job.apply_async()


@shared_task(
    bind=True,
    name="newsletters.send_newsletter_to_subscriber",
    acks_late=True,
    reject_on_worker_lost=True,
    autoretry_for=(smtplib.SMTPException, ConnectionError),
    retry_backoff=True,
    retry_backoff_max=300,
    retry_jitter=True,
    max_retries=3,
)
def send_newsletter_to_subscriber(self, newsletter_id: int, subscriber_id: int) -> None:
    NewsletterService.deliver(newsletter_id=newsletter_id, subscriber_id=subscriber_id)
```

`group()` schedules all subtasks in parallel. Each item task handles its own retries independently.

## Configuration

### Django settings

Use the `CELERY_` namespace prefix so `config_from_object` picks up all settings automatically.

```python
# config/settings/base.py
CELERY_BROKER_URL = env("CELERY_BROKER_URL", default="redis://localhost:6379/0")
CELERY_RESULT_BACKEND = env("CELERY_RESULT_BACKEND", default="redis://localhost:6379/1")
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TIMEZONE = "UTC"
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 300  # hard limit in seconds
CELERY_TASK_SOFT_TIME_LIMIT = 240  # soft limit — raises SoftTimeLimitExceeded
```

```python
# config/settings/test.py
from config.settings.base import *  # noqa: F403

CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True
```

### Celery app setup (Django)

```python
# config/celery.py
import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.local")

app = Celery("myproject")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
```

```python
# config/__init__.py
from config.celery import app as celery_app

__all__ = ["celery_app"]
```

### Non-Django projects (FastAPI, standalone)

```python
# celery_app.py
from celery import Celery

app = Celery("myproject")
app.conf.update(
    broker_url="redis://localhost:6379/0",
    result_backend="redis://localhost:6379/1",
    task_serializer="json",
    accept_content=["json"],
    timezone="UTC",
)
```

## Testing Celery Tasks

With `task_always_eager=True`, `task.delay()` executes synchronously in the same process — no broker needed.

**Preferred approach: test service logic directly**, not through the task. The task is a thin wrapper.

```python
# apps/orders/tests/test_services.py
def test_send_confirmation_delivers_email(order: Order) -> None:
    # Test the service directly — fast, no Celery involved
    OrderService.send_confirmation(order=order)
    # assert side effects ...
```

**Task-level test**: verify the task calls the service correctly.

```python
# apps/orders/tests/test_tasks.py
import pytest
from unittest.mock import patch

from apps.orders.tasks import send_order_confirmation
from apps.orders.tests.factories import OrderFactory


@pytest.mark.django_db
def test_send_order_confirmation_calls_service() -> None:
    order = OrderFactory()

    with patch("apps.orders.tasks.OrderService.send_confirmation") as mock_send:
        send_order_confirmation.delay(order.pk)  # eager — runs synchronously
        mock_send.assert_called_once_with(order=order)


@pytest.mark.django_db
def test_send_order_confirmation_skips_missing_order() -> None:
    # Should not raise — missing orders are silently skipped
    send_order_confirmation.delay(99999)
```

Use `@override_settings` for one-off eager overrides in Django test suites (Django-specific; not applicable to non-Django projects):

```python
from django.test import override_settings

@override_settings(CELERY_TASK_ALWAYS_EAGER=True, CELERY_TASK_EAGER_PROPAGATES=True)
def test_task_runs_eagerly() -> None:
    ...
```

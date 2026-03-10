---
name: django-web-patterns
description: Enforces Django REST Framework patterns with Pragmatic DDD: ViewSets, Serializers, Permissions, exception handling, settings, middleware. Activates when working with Django views, endpoints, or DRF serializers.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(manage.py:*), Bash(django-admin:*)
---

# Django REST Framework Patterns (Pragmatic DDD)

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

**Architecture:**

- NEVER put business logic in ViewSets/APIViews — ALWAYS delegate to services or model methods
- NEVER return raw `Response(data)` with manually constructed dicts — ALWAYS use Serializers
- NEVER use `@api_view` for complex endpoints — use `APIView` or `ViewSet` classes

**Views:**

- NEVER do manual authentication checks in views — ALWAYS use `permission_classes` and `authentication_classes`
- ALWAYS use `ModelViewSet` / `ReadOnlyModelViewSet` when providing full CRUD on a model
- ALWAYS use `@action` decorator for custom ViewSet actions (not extra URL patterns)
- ALWAYS declare explicit `status_code` on mutating `@action` decorators

**Serializers:**

- NEVER use `Meta.fields = "__all__"` — ALWAYS use an explicit field list
- NEVER put business logic in serializers — only validation and data transformation
- ALWAYS separate `<Entity>CreateSerializer`, `<Entity>UpdateSerializer`, `<Entity>ResponseSerializer` for non-trivial resources
- ALWAYS use `serializers.PrimaryKeyRelatedField` or nested serializer — NEVER raw ID integer fields
- ALWAYS override `create()`/`update()` in serializer when custom logic needed (not in ViewSet)

**URLs:**

- ALWAYS use `DefaultRouter` for ViewSet registration
- ALWAYS namespace URL patterns per app (`app_name = "orders"`)
- NEVER hardcode URLs — ALWAYS use `reverse()` or `reverse_lazy()`

**Permissions:**

- ALWAYS use custom permission classes (not inline checks in views)
- ALWAYS combine permissions with `&` / `|` operators for composite permissions

**Exception Handling:**

- NEVER use DRF's default exception handler for domain errors — ALWAYS use a custom `exception_handler` mapping domain exceptions to API responses
- Domain exceptions hierarchy: `DomainError` → `EntityNotFoundError`, `DomainValidationError`, `PermissionDeniedError`, `ConflictError` (prefixed to avoid shadowing Python built-in `PermissionError` and Django/DRF `ValidationError`)

**Settings & Middleware:**

- ALWAYS use `django-environ` or `pydantic-settings` for env config — NEVER hardcode secrets
- ALWAYS split settings: `base.py`, `local.py`, `production.py`, `test.py`
- NEVER remove Django security middleware (`SecurityMiddleware`, `CsrfViewMiddleware`)
- ALWAYS load `CORS_ALLOWED_ORIGINS` from environment (via `django-cors-headers`)

**Throttling & Filtering:**

- ALWAYS configure throttle rates in settings, not per-view
- ALWAYS use `django-filter` with `FilterSet` classes — NEVER manual `request.query_params` parsing for filtering

**Quality:**

- ALWAYS run the project's typecheck and test commands after any change
</HARD-RULES>

These are the Django REST Framework patterns for building APIs in AppVerk projects, following **Pragmatic DDD**. Django Models serve as rich domain models. All patterns target **Python 3.13+**, **Django 5.1+**, **Django REST Framework 3.15+**.

## Architecture Overview

```
Presentation (DRF ViewSets/APIViews, Serializers, Permissions, URLs, exception handlers)
    ↓ depends on
Application Layer (Services / Use Cases)
    ↓ depends on
Domain Layer (Django Models as rich domain models, Value Objects, Repository Protocols, Domain Exceptions)
    ↓
Infrastructure Layer (Managers, QuerySets, external integrations, Celery tasks)
```

**Key difference from Full DDD:** Django Models ARE the domain entities — there is no separate mapping layer. Business methods live directly on the Model. The infrastructure layer provides custom Managers and QuerySets that encapsulate query logic.

### Directory Layout

```
project/
    apps/
        orders/
            models.py          # Domain models (rich domain entities)
            serializers.py     # Request/response serializers
            views.py           # ViewSets and APIViews
            urls.py            # Router registration (app_name = "orders")
            permissions.py     # Custom permission classes
            filters.py         # FilterSet classes
            services.py        # Application layer (use cases)
            exceptions.py      # Domain exception hierarchy
            tasks.py           # Celery tasks
            tests/
                test_views.py
                test_models.py
                test_services.py
    config/
        settings/
            base.py
            local.py
            production.py
            test.py
        urls.py
        wsgi.py
        asgi.py
```

## ViewSet Structure

One ViewSet per domain resource. Custom actions use `@action`, not separate URL patterns.

```python
# apps/orders/views.py
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.viewsets import ModelViewSet

from apps.orders.filters import OrderFilter
from apps.orders.models import Order
from apps.orders.permissions import IsOrderOwner
from apps.orders.serializers import (
    OrderCreateSerializer,
    OrderResponseSerializer,
    OrderUpdateSerializer,
)
from apps.orders.services import OrderService


class OrderViewSet(ModelViewSet):
    permission_classes = [IsOrderOwner]
    filterset_class = OrderFilter

    def get_queryset(self):
        return Order.objects.for_user(self.request.user).select_related("product")

    def get_serializer_class(self):
        if self.action == "create":
            return OrderCreateSerializer
        if self.action in ("update", "partial_update"):
            return OrderUpdateSerializer
        return OrderResponseSerializer

    def perform_create(self, serializer: OrderCreateSerializer) -> None:
        # Delegate to service — never put logic directly here
        OrderService.create_order(
            user=self.request.user,
            validated_data=serializer.validated_data,
        )

    @action(detail=True, methods=["post"], url_path="cancel", status_code=status.HTTP_200_OK)
    def cancel(self, request: Request, pk: int | None = None) -> Response:
        order = self.get_object()
        OrderService.cancel_order(order=order, cancelled_by=request.user)
        return Response(OrderResponseSerializer(order).data)
```

Register with `DefaultRouter` in `urls.py`:

```python
# apps/orders/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter

from apps.orders.views import OrderViewSet

app_name = "orders"

router = DefaultRouter()
router.register("", OrderViewSet, basename="order")

urlpatterns = [path("orders/", include(router.urls))]
```

## Serializer Patterns

Separate serializers for create, update, and response. Nested serializers for related objects.

```python
# apps/orders/serializers.py
from rest_framework import serializers

from apps.orders.models import Order
from apps.products.models import Product
from apps.products.serializers import ProductSummarySerializer


class OrderCreateSerializer(serializers.ModelSerializer):
    product = serializers.PrimaryKeyRelatedField(queryset=Product.objects.all())

    class Meta:
        model = Order
        fields = ["product", "quantity", "notes"]

    def validate_quantity(self, value: int) -> int:
        if value < 1:
            raise serializers.ValidationError("Quantity must be at least 1.")
        return value


class OrderUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Order
        fields = ["quantity", "notes"]


class OrderResponseSerializer(serializers.ModelSerializer):
    product = ProductSummarySerializer(read_only=True)
    status_display = serializers.CharField(source="get_status_display", read_only=True)

    class Meta:
        model = Order
        fields = [
            "id", "product", "quantity", "notes",
            "status", "status_display", "created_at", "updated_at",
        ]
        read_only_fields = fields
```

### Conventions

- `<Entity>CreateSerializer` — write path for creation; validate business constraints here.
- `<Entity>UpdateSerializer` — write path for updates; all fields optional if supporting `PATCH`.
- `<Entity>ResponseSerializer` — read path; all fields `read_only`. Use nested serializers for related objects.
- Override `create()` / `update()` in the serializer (not ViewSet's `perform_create`) when custom save logic is needed.

## Domain Exception Handling

Services raise **domain exceptions**. A custom DRF `exception_handler` maps them to HTTP responses. ViewSets never catch domain exceptions manually.

### Domain Exception Hierarchy

```python
# apps/orders/exceptions.py — no external dependencies
class DomainError(Exception):
    """Base for all domain exceptions."""


class EntityNotFoundError(DomainError):
    """Raised when a requested entity does not exist."""


class DomainValidationError(DomainError):
    """Raised when a domain business rule is violated."""


class PermissionDeniedError(DomainError):
    """Raised when the user lacks permission for the operation."""


class ConflictError(DomainError):
    """Raised when an operation conflicts with existing state (e.g. duplicate)."""
```

### Custom DRF Exception Handler

```python
# config/exception_handler.py
from rest_framework.exceptions import APIException
from rest_framework.views import exception_handler as drf_default_handler
from rest_framework.request import Request
from rest_framework.response import Response

from apps.orders.exceptions import (
    ConflictError,
    DomainError,
    DomainValidationError,
    EntityNotFoundError,
    PermissionDeniedError,
)

DOMAIN_EXCEPTION_MAP: dict[type[DomainError], int] = {
    EntityNotFoundError: 404,
    PermissionDeniedError: 403,
    DomainValidationError: 422,
    ConflictError: 409,
}


def custom_exception_handler(exc: Exception, context: dict) -> Response | None:
    for exc_class, status_code in DOMAIN_EXCEPTION_MAP.items():
        if isinstance(exc, exc_class):
            return Response(
                {"detail": str(exc), "error_code": type(exc).__name__},
                status=status_code,
            )
    # Fall back to DRF default for APIException, 404, etc.
    return drf_default_handler(exc, context)
```

Register in settings:

```python
# config/settings/base.py
REST_FRAMEWORK = {
    "EXCEPTION_HANDLER": "config.exception_handler.custom_exception_handler",
}
```

## Permissions

Custom permission classes encapsulate authorization logic. Combine with `&` / `|` for composite rules.

```python
# apps/orders/permissions.py
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.request import Request
from rest_framework.views import APIView

from apps.orders.models import Order


class IsOrderOwner(BasePermission):
    """Allow access only to the owner of the order."""

    def has_permission(self, request: Request, view: APIView) -> bool:
        return bool(request.user and request.user.is_authenticated)

    def has_object_permission(self, request: Request, view: APIView, obj: Order) -> bool:
        return obj.user_id == request.user.pk


# Composite: authenticated AND (owner OR staff)
class IsOwnerOrStaff(BasePermission):
    def has_object_permission(self, request: Request, view: APIView, obj: Order) -> bool:
        return obj.user_id == request.user.pk or request.user.is_staff


# Usage in ViewSet:
# permission_classes = [IsAuthenticated & IsOrderOwner]
```

## Settings & Middleware

Split settings by environment. Load all secrets from environment variables via `django-environ`.

```python
# config/settings/base.py
import environ

env = environ.Env()

SECRET_KEY = env("SECRET_KEY")
DEBUG = env.bool("DEBUG", default=False)

DATABASES = {
    "default": env.db("DATABASE_URL"),
}

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "rest_framework",
    "corsheaders",
    "django_filters",
    "apps.orders",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",  # NEVER remove
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",  # NEVER remove
    "django.contrib.auth.middleware.AuthenticationMiddleware",
]

CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])

REST_FRAMEWORK = {
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": env("THROTTLE_ANON_RATE", default="100/hour"),
        "user": env("THROTTLE_USER_RATE", default="1000/hour"),
    },
    "DEFAULT_FILTER_BACKENDS": ["django_filters.rest_framework.DjangoFilterBackend"],
    "EXCEPTION_HANDLER": "config.exception_handler.custom_exception_handler",
}
```

Environment-specific files extend base:

```python
# config/settings/local.py
from config.settings.base import *  # noqa: F403

DEBUG = True
ALLOWED_HOSTS = ["*"]
```

```python
# config/settings/test.py
from config.settings.base import *  # noqa: F403

DATABASES = {"default": env.db("TEST_DATABASE_URL", default="sqlite://:memory:")}
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
```

## Throttling & Filtering

Use `django-filter` with `FilterSet` classes. Configure rates in settings — never per-view.

```python
# apps/orders/filters.py
import django_filters

from apps.orders.models import Order


class OrderFilter(django_filters.FilterSet):
    status = django_filters.ChoiceFilter(choices=Order.Status.choices)
    created_after = django_filters.DateTimeFilter(field_name="created_at", lookup_expr="gte")
    created_before = django_filters.DateTimeFilter(field_name="created_at", lookup_expr="lte")

    class Meta:
        model = Order
        fields = ["status", "created_after", "created_before"]
```

Attach to the ViewSet via `filterset_class = OrderFilter` — DRF applies it automatically.

## Testing DRF

Use `pytest-django` with `APIClient` for functional tests and `factory_boy` for test data.

```python
# apps/orders/tests/test_views.py
import pytest
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient

from apps.orders.tests.factories import OrderFactory, UserFactory


@pytest.fixture
def api_client() -> APIClient:
    return APIClient()


@pytest.fixture
def auth_client(api_client: APIClient) -> APIClient:
    user = UserFactory()
    api_client.force_authenticate(user=user)
    api_client.user = user  # type: ignore[attr-defined]
    return api_client


@pytest.mark.django_db
class TestOrderViewSet:
    def test_list_returns_only_own_orders(self, auth_client: APIClient) -> None:
        own_order = OrderFactory(user=auth_client.user)
        OrderFactory()  # belongs to another user

        response = auth_client.get(reverse("orders:order-list"))

        assert response.status_code == status.HTTP_200_OK
        assert len(response.data["results"]) == 1
        assert response.data["results"][0]["id"] == own_order.pk

    def test_create_order_returns_201(self, auth_client: APIClient) -> None:
        product = ProductFactory()
        payload = {"product": product.pk, "quantity": 2}

        response = auth_client.post(reverse("orders:order-list"), data=payload)

        assert response.status_code == status.HTTP_201_CREATED
        assert response.data["quantity"] == 2

    def test_cancel_action_returns_200(self, auth_client: APIClient) -> None:
        order = OrderFactory(user=auth_client.user, status=Order.Status.PENDING)

        response = auth_client.post(reverse("orders:order-cancel", args=[order.pk]))

        assert response.status_code == status.HTTP_200_OK
        order.refresh_from_db()
        assert order.status == Order.Status.CANCELLED

    def test_unauthenticated_returns_403(self, api_client: APIClient) -> None:
        response = api_client.get(reverse("orders:order-list"))
        assert response.status_code == status.HTTP_403_FORBIDDEN
```

Use `RequestFactory` for unit-testing a single view in isolation (no middleware, no URL routing):

```python
from django.test import RequestFactory
from apps.orders.views import OrderViewSet
from apps.orders.tests.factories import UserFactory

def test_get_queryset_filters_by_user() -> None:
    user = UserFactory.build()
    request = RequestFactory().get("/")
    request.user = user
    view = OrderViewSet()
    view.request = request  # type: ignore[assignment]
    view.kwargs = {}
    qs = view.get_queryset()
    assert qs.query.where  # filter is applied
```

### Conventions

- Use `@pytest.mark.django_db` on test classes — `pytest-django` handles transactions and rollback.
- Use `APIClient.force_authenticate()` for auth — never create real tokens in unit tests.
- Use `factory_boy` `Factory` classes for all test data — never use `Model.objects.create()` directly in tests.
- Test the HTTP interface (status codes, response shape) for view tests; test domain logic in `test_models.py` / `test_services.py`.
- See the `tdd-workflow` skill for full testing rules and factory patterns.

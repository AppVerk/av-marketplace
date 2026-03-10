# Design: Django & Celery Skills for python-developer Plugin

**Date:** 2026-03-10
**Status:** Approved
**Plugin:** python-developer (current v2.1.0 → target v3.0.0)

## Summary

Add Django REST Framework, Django ORM, and Celery skills to the `python-developer` plugin, extending it beyond the current FastAPI-only stack. Uses Pragmatic DDD architecture where Django Models serve as rich domain models with services layer.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Architecture | Pragmatic DDD — Django models as rich domain models + services | Doesn't fight Django ORM, leverages ecosystem (admin, migrations, signals) |
| Scope | DRF + Celery | Covers API + async jobs, most common Django production stack |
| Django ORM skill | Separate `django-orm-patterns` | Conditional loading, consistent granularity with FastAPI stack |
| Celery skill | Lightweight `celery-patterns` | Hard rules only (idempotency, retries, error handling), no advanced patterns |
| Agent | Extend existing `developer.md` | Avoids duplicating 6-phase workflow, shares base skills |
| Testing | No changes to `tdd-workflow` | Django/Celery testing patterns in respective skills as sections |

## Architecture: Pragmatic DDD in Django

```
Presentation (DRF ViewSets/APIViews, Serializers, Permissions, URLs, exception handlers)
    ↓ depends on
Application Layer (Services / Use Cases)
    ↓ depends on
Domain Layer (Django Models as rich domain models, Value Objects, Repository Protocols, Domain Exceptions)
    ↓
Infrastructure Layer (Managers, QuerySets, external integrations, Celery tasks)
```

**Key difference vs FastAPI stack:** Django Models serve dual role — domain entities AND ORM. No `to_domain()`/`to_orm()` mappers. Business logic lives in model methods and services.

**Boundaries:**
- **Model** — business logic for a single entity (validation, state transitions, computed properties)
- **Service** — orchestrates operations across multiple models, external calls, side effects
- **Repository (optional)** — abstraction over QuerySet for complex queries, aids testing
- **ViewSet/APIView** — thin layer, delegates to services, no business logic

## New Skills

### 1. `django-web-patterns` (~200-250 lines)

DRF views, serializers, permissions, URLs, exception handling, settings, middleware.

**Hard Rules — Views:**
- NO business logic in ViewSets/APIViews — delegate to services or model methods
- NO raw `Response(data)` with manual dicts — use Serializers
- NO `@api_view` for complex endpoints — use `APIView` or `ViewSet`
- NO manual authentication checks — use `permission_classes` and `authentication_classes`
- ALWAYS `ModelViewSet` / `ReadOnlyModelViewSet` for full CRUD
- ALWAYS `@action` decorator for custom ViewSet actions
- ALWAYS explicit `status_code` on mutating `@action`

**Hard Rules — Serializers:**
- NO `Meta.fields = "__all__"` — explicit field list
- NO business logic in serializers — only validation and data transformation
- ALWAYS separate Create/Update/Response serializers for non-trivial resources
- ALWAYS `PrimaryKeyRelatedField` or nested serializer — no raw ID fields
- ALWAYS override `create()`/`update()` when custom logic needed (not in ViewSet)

**Hard Rules — URLs:**
- ALWAYS `DefaultRouter` for ViewSet registration
- ALWAYS namespace URL patterns per app
- NO hardcoded URLs — use `reverse()` / `reverse_lazy()`

**Hard Rules — Permissions:**
- ALWAYS custom permission classes (not inline checks)
- ALWAYS combine with `&` / `|` for composite permissions

**Hard Rules — Exception Handling:**
- NO default DRF exception handler for domain errors — custom `exception_handler` mapping domain exceptions to API responses
- Domain exceptions hierarchy: `DomainError` → `EntityNotFoundError`, `DomainValidationError`, `PermissionDeniedError`, `ConflictError` (prefixed to avoid shadowing Python built-in `PermissionError` and Django/DRF `ValidationError`; aligned with FastAPI skill naming)

**Hard Rules — Settings & Middleware:**
- ALWAYS `django-environ` or `pydantic-settings` for env config — no hardcoded secrets
- ALWAYS split settings: `base.py`, `local.py`, `production.py`, `test.py`
- NO security middleware removal
- ALWAYS `CORS_ALLOWED_ORIGINS` from environment

**Hard Rules — Throttling & Filtering:**
- ALWAYS throttle rates in settings, not per-view
- ALWAYS `django-filter` with `FilterSet` — no manual `request.query_params` parsing

**Testing section:**
- `pytest-django` + `@pytest.mark.django_db`
- `APIClient` for functional tests
- `RequestFactory` for unit tests of views
- `factory_boy` for test data (not JSON fixtures)

### 2. `django-orm-patterns` (~200-250 lines)

Django ORM models, managers, querysets, migrations, signals.

**Hard Rules — Models:**
- NO business logic in `save()` overrides for complex operations — explicit methods or services
- NO `null=True` on `CharField`/`TextField` — use `blank=True, default=""`
- NO `ForeignKey` without explicit `on_delete`
- NO `ForeignKey` without `related_name`
- ALWAYS `db_index=True` on filtered/lookup fields (or `Meta.indexes`)
- ALWAYS abstract base models for shared fields (`TimeStampedModel`)
- ALWAYS `__str__` on every model
- ALWAYS `class Meta: ordering`, `verbose_name`, `verbose_name_plural`
- ALWAYS `UniqueConstraint` / `CheckConstraint` in `Meta.constraints` — not deprecated `unique_together`

**Rich Domain Model pattern:**
```python
class Order(TimeStampedModel):
    status = models.CharField(max_length=20, choices=OrderStatus.choices)

    def can_cancel(self) -> bool:
        return self.status in (OrderStatus.PENDING, OrderStatus.CONFIRMED)

    def cancel(self) -> None:
        if not self.can_cancel():
            raise OrderCannotBeCancelledError(self.id)
        self.status = OrderStatus.CANCELLED
```

**Hard Rules — Managers & QuerySets:**
- NO complex queries in views/services — encapsulate in custom QuerySet methods
- ALWAYS `MyQuerySet.as_manager()` or `Manager.from_queryset()`
- ALWAYS name methods as domain concepts (`published()`, `active()`, `for_user(user)`)
- NO raw SQL unless QuerySet API is genuinely insufficient

**Hard Rules — Performance:**
- NO N+1 — ALWAYS `select_related()` (FK/OneToOne) and `prefetch_related()` (M2M/reverse FK)
- ALWAYS `only()` / `defer()` for large models when subset needed
- ALWAYS `bulk_create()` / `bulk_update()` for batch operations
- ALWAYS `iterator()` for large querysets in background tasks

**Hard Rules — Migrations:**
- NO manual migration edits unless necessary
- ALWAYS separate data migrations from schema migrations
- ALWAYS `RunPython` with `reverse_code`
- NO `migrate` in production without review — use `sqlmigrate`

**Hard Rules — Signals:**
- NO signals for core business logic — use explicit methods or services
- Signals ONLY for decoupled side effects (cache invalidation, audit logging)
- ALWAYS `dispatch_uid`

**Optional Repository Pattern** for complex query abstraction and testability.

**Testing section:**
- `factory_boy` with `DjangoModelFactory`
- Unit tests: model methods (no DB)
- Integration tests: QuerySet/Manager methods (with DB)
- `assertNumQueries` for N+1 verification

### 3. `celery-patterns` (~150 lines)

Task design, retries, error handling, testing.

**Hard Rules — Task Design:**
- ALWAYS idempotent tasks
- NO Django model instances as task arguments — pass IDs (primitives)
- NO long tasks without decomposition — split into subtasks for collections
- ALWAYS `bind=True` when needing `self` (retry, task info)
- ALWAYS explicit `name` parameter — no auto-generated names
- ALWAYS `acks_late=True` + `reject_on_worker_lost=True` for must-execute tasks

**Hard Rules — Retry & Error Handling:**
- NO bare `except` — catch specific exceptions
- ALWAYS `autoretry_for` + `retry_backoff=True` + `retry_backoff_max` + `max_retries`
- ALWAYS `retry_jitter=True`
- NO retry for business logic errors — only transient errors
- ALWAYS dead letter handling

**Hard Rules — Organization:**
- ALWAYS `shared_task` (not `app.task`)
- ALWAYS tasks in `<app>/tasks.py`
- NO circular imports

**Hard Rules — Configuration:**
- ALWAYS `task_always_eager=True` in test settings
- ALWAYS `task_eager_propagates=True` in tests
- ALWAYS `CELERY_` namespace prefix in Django settings (`config_from_object('django.conf:settings', namespace='CELERY')`)
- For non-Django projects (e.g., FastAPI): use `celery_app.conf.update()` with explicit config dict

**Testing section:**
- Unit tests: test business logic in services/models, not tasks
- Task tests: `task_always_eager=True` for synchronous execution
- NO `pytest-celery` for basic tests — eager mode suffices

## New Files

- `skills/django-web-patterns/SKILL.md` — DRF patterns skill (~200-250 lines)
- `skills/django-orm-patterns/SKILL.md` — Django ORM patterns skill (~200-250 lines)
- `skills/celery-patterns/SKILL.md` — Celery patterns skill (~150 lines)

## Modified Files

### `agents/developer.md`

**Frontmatter updates:**
- Add to `skills:` list: `django-web-patterns`, `django-orm-patterns`, `celery-patterns`
- Add to `allowed-tools`: `Bash(manage.py:*)`, `Bash(django-admin:*)`, `Bash(celery:*)`

**Phase 2 — extended detection:**
- `pyproject.toml` → also search: `django`, `djangorestframework`, `celery`
- Scan imports → also search: `django.*`, `rest_framework.*`, `celery.*`
- Scan files → search: `manage.py`, `settings.py`, `wsgi.py`, `asgi.py` (project root and one level deep)

**Phase 3 — conditional loading:**
```
ALWAYS load: coding-standards, tdd-workflow

IF FastAPI detected:  fastapi-patterns, sqlalchemy-patterns, pydantic-patterns
IF Django detected:   django-web-patterns, django-orm-patterns
IF Celery detected:   celery-patterns
IF async detected:    async-python-patterns
IF deps needed:       uv-package-manager
```

- FastAPI and Django skills are mutually exclusive — if both detected, agent asks user
- Celery is framework-independent — loads with Django or FastAPI
- pydantic-patterns may load with Django if pydantic detected (lower priority than DRF serializers). Note: pydantic-patterns rule "NO BaseModel for domain entities" is scoped to FastAPI stack — in Django stack, domain entities are Django Models.
- sqlalchemy-patterns is excluded when Django is detected (even if SQLAlchemy is in dependencies)

### `.claude-plugin/plugin.json`

Version bump: 2.1.0 → 3.0.0 (breaking: new skill loading logic in agent).

### `commands/develop.md`

Update help text and examples to include Django/Celery use cases.

### `docs/plugins/python-developer.md`

Add documentation for new skills (Django Web Patterns, Django ORM Patterns, Celery Patterns). Update agent description and `/develop` command examples to include Django/Celery use cases.

## Out of Scope (YAGNI)

- Django Templates/Forms (scope is API only)
- Django Channels/WebSockets
- Celery Beat/scheduling
- Celery chaining/chords/canvas (advanced patterns)
- Separate `django-developer` agent
- Changes to `tdd-workflow` or `coding-standards`
- Shared `orm-base-patterns` skill

---
name: fastapi-patterns
description: Enforces FastAPI patterns with DDD and Clean Architecture: endpoint structure, UoW dependency injection, domain exception handling, pure ASGI middleware, testing. Activates when working with FastAPI routers, endpoints, or middleware.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(uvicorn:*)
---

# FastAPI Patterns (DDD / Clean Architecture)

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

**Architecture & Layers:**
- NEVER define endpoints directly on the `FastAPI()` app instance — ALWAYS use `APIRouter` and include it via `app.include_router()`
- NEVER inject `AsyncSession` into endpoints — ALWAYS use `UnitOfWork` Protocol dependency from the domain layer
- NEVER raise `HTTPException` in services or domain layer — services raise domain exceptions, the presentation layer maps them to HTTP responses via global exception handlers
- NEVER return domain entities directly from endpoints — ALWAYS map through response schemas with `from_domain()` classmethod
- NEVER import SQLAlchemy or infrastructure types in routers — only domain and schema types

**Endpoints:**
- NEVER use synchronous `def` for endpoints that perform I/O — ALWAYS use `async def`
- NEVER return raw dicts from endpoints — ALWAYS use a typed return annotation with a Pydantic model
- NEVER catch generic `Exception` in endpoints — use domain exception handlers or raise `HTTPException` for HTTP-level concerns (auth, validation)
- ALWAYS use `Annotated[T, Depends(...)]` for dependency injection — NEVER pass `Depends()` as a default parameter value
- ALWAYS declare explicit `status_code` on mutating endpoints (`POST`, `PUT`, `PATCH`, `DELETE`)

**Schemas & Types:**
- NEVER use separate Create/Read schemas named differently per endpoint — ALWAYS follow the `ItemCreate`, `ItemUpdate`, `ItemResponse` naming convention
- ALWAYS use PEP 695 type parameter syntax (`class Foo[T]`, `type Alias = ...`) — NEVER use `TypeVar` / `Generic[T]` / `TypeAlias`

**Middleware & Config:**
- NEVER use `BaseHTTPMiddleware` — ALWAYS use pure ASGI middleware (BaseHTTPMiddleware has memory leaks, breaks contextvars, and will be removed in Starlette 1.0)
- NEVER hardcode CORS origins in source code — ALWAYS load them from settings/environment
- NEVER use `@app.on_event("startup")` or `@app.on_event("shutdown")` — ALWAYS use the `lifespan` async context manager

**Quality:**
- ALWAYS run the project's typecheck and test commands after any endpoint change
</HARD-RULES>

These are the FastAPI patterns for building APIs in AppVerk projects, following **Domain-Driven Design** and **Clean Architecture**. All patterns target **Python 3.13+**, **FastAPI 0.128+**, and **Pydantic v2.7+**.

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Presentation Layer (FastAPI routers, schemas,        │
│    exception handlers, middleware)                    │
│  Depends on: Application Layer, Domain Layer         │
├──────────────────────────────────────────────────────┤
│  Application Layer (Services / Use Cases)            │
│  Depends on: Domain Layer only                       │
│  Uses: UnitOfWork Protocol, Repository Protocol      │
├──────────────────────────────────────────────────────┤
│  Domain Layer (Entities, Value Objects,               │
│    Repository Protocols, UoW Protocol,               │
│    Domain Exceptions)                                │
│  Depends on: NOTHING                                 │
├──────────────────────────────────────────────────────┤
│  Infrastructure Layer (ORM models, SA repos,          │
│    SA UoW, Data Mappers, Alembic)                    │
│  Depends on: Domain Layer + SQLAlchemy               │
└──────────────────────────────────────────────────────┘
```

**FastAPI lives in the Presentation Layer.** It receives HTTP requests, delegates to services, maps results to responses, and translates domain exceptions to HTTP status codes. It NEVER touches infrastructure directly.

**Dependency direction:** ALWAYS inward. Routers depend on services (application layer) and schemas (presentation). Services depend on domain Protocols. Infrastructure implements those Protocols.

### Directory Layout

```
app/
    api/                         # Presentation layer
        routes/                  # One file per domain module
            markets.py
            users.py
        dependencies.py          # DI: UoW, services, auth
        exception_handlers.py    # Domain exception → HTTP mapping
    schemas/                     # Pydantic request/response models
        market.py
        user.py
        common.py                # PaginatedResponse, ErrorResponse
    domain/
        entities/                # Pure dataclasses / Pydantic models
        value_objects/           # Immutable value types
        repositories/            # Protocol interfaces
        exceptions.py            # Domain exception hierarchy
        unit_of_work.py          # UoW Protocol
    services/                    # Application layer (use cases)
    infrastructure/
        persistence/
            models/              # SQLAlchemy ORM models (*ORM)
            mappers/             # Domain ↔ ORM conversion
            repositories/        # Repository implementations
            unit_of_work.py      # SQLAlchemy UoW
            database.py          # Engine, session factory
    middleware/                   # Pure ASGI middleware
    main.py                      # App factory, lifespan, router registration
    config.py                    # Settings (pydantic-settings)
```

## Router Structure

One router per domain module. Each router lives in its own file under `api/routes/`.

```python
# app/api/routes/markets.py
from fastapi import APIRouter

router = APIRouter(
    prefix="/markets",
    tags=["markets"],
)


@router.get("/")
async def list_markets(
    filters: Annotated[MarketFilters, Query()],
    service: MarketServiceDep,
) -> PaginatedResponse[MarketResponse]:
    ...


@router.get("/{market_id}")
async def get_market(
    market_id: UUID,
    service: MarketServiceDep,
) -> MarketResponse:
    market = await service.get_by_id(market_id)
    return MarketResponse.from_domain(market)


@router.post("/", status_code=201)
async def create_market(
    body: MarketCreate,
    service: MarketServiceDep,
    user: CurrentUser,
) -> MarketResponse:
    market = await service.create_market(body, user_id=user.id)
    return MarketResponse.from_domain(market)
```

Register all routers in the app factory:

```python
# app/main.py
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI

from app.api.exception_handlers import register_exception_handlers
from app.api.routes import markets, users, trades


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # startup: open DB pool, warm caches, etc.
    yield
    # shutdown: close DB pool, flush buffers, etc.


def create_app() -> FastAPI:
    app = FastAPI(title="AV Marketplace", lifespan=lifespan)

    register_exception_handlers(app)

    app.include_router(markets.router, prefix="/api/v1")
    app.include_router(users.router, prefix="/api/v1")
    app.include_router(trades.router, prefix="/api/v1")

    return app
```

### Conventions

- **Prefix**: set on the router (`prefix="/markets"`), not at include time, unless you need a version prefix like `/api/v1`.
- **Tags**: one tag per router matching the domain name. Used for OpenAPI docs grouping.
- **File layout**: `app/api/routes/<domain>.py` with a module-level `router` variable.
- **Return type as response model**: use typed return annotations (e.g., `-> MarketResponse`) instead of `response_model=` parameter. Use `response_model` only when you need field filtering (`response_model_include`, `response_model_exclude`).

## Dependency Injection — UoW & Services

Use `Annotated` types with `Depends()` for all injected dependencies. Define reusable type aliases. **Endpoints receive services, not infrastructure types.**

### UoW Dependency

The Unit of Work dependency bridges infrastructure and presentation. This is the **only place** where infrastructure types appear in the DI graph:

```python
# app/api/dependencies.py
from typing import Annotated
from collections.abc import AsyncIterator

from fastapi import Depends

from app.domain.unit_of_work import UnitOfWork
from app.infrastructure.persistence.database import async_session_factory
from app.infrastructure.persistence.unit_of_work import SqlAlchemyUnitOfWork


async def get_unit_of_work() -> AsyncIterator[SqlAlchemyUnitOfWork]:
    uow = SqlAlchemyUnitOfWork(async_session_factory)
    yield uow


UoW = Annotated[UnitOfWork, Depends(get_unit_of_work)]
```

**Key point:** the type alias `UoW` is typed as `UnitOfWork` (the domain Protocol), not `SqlAlchemyUnitOfWork`. Endpoints see the abstraction.

### Service Dependencies

Services are composed from UoW via nested dependencies. FastAPI resolves the graph automatically:

```python
# app/api/dependencies.py
from app.services.market import MarketService
from app.services.user import UserService


async def get_market_service(uow: UoW) -> MarketService:
    return MarketService(uow)


async def get_user_service(uow: UoW) -> UserService:
    return UserService(uow)


MarketServiceDep = Annotated[MarketService, Depends(get_market_service)]
UserServiceDep = Annotated[UserService, Depends(get_user_service)]
```

### Authentication

```python
# app/api/dependencies.py
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.domain.entities.user import User
from app.services.auth import AuthService

security = HTTPBearer()


async def get_auth_service(uow: UoW) -> AuthService:
    return AuthService(uow)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Security(security)],
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> User:
    user = await auth_service.verify_token(credentials.credentials)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
```

**Notes:**
- Use `Security()` instead of `Depends()` for security dependencies — this generates proper OpenAPI security scheme documentation and enables OAuth2 scopes.
- `HTTPBearer` is for pure Bearer token auth (JWT/API key obtained externally).
- `HTTPException` is acceptable here because authentication is a **presentation-layer concern** — the service (`AuthService`) returns `None` for invalid tokens, the DI function translates that to HTTP 401.

### OAuth2 Password Flow (Swagger UI Login)

When your API has a username/password login endpoint and you want the Swagger UI "Authorize" button to work with credentials:

```python
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/token")


@router.post("/auth/token")
async def login(
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
    auth_service: Annotated[AuthService, Depends(get_auth_service)],
) -> TokenResponse:
    token = await auth_service.authenticate(form_data.username, form_data.password)
    return TokenResponse(access_token=token, token_type="bearer")
```

### Using Dependencies in Endpoints

```python
# app/api/routes/markets.py
from app.api.dependencies import CurrentUser, MarketServiceDep


@router.post("/", status_code=201)
async def create_market(
    body: MarketCreate,
    service: MarketServiceDep,
    user: CurrentUser,
) -> MarketResponse:
    market = await service.create_market(body, user_id=user.id)
    return MarketResponse.from_domain(market)
```

**What happens here:**
1. FastAPI resolves `MarketServiceDep` → calls `get_market_service(uow)` → calls `get_unit_of_work()`
2. Service receives `UnitOfWork` Protocol — no infrastructure types in the endpoint
3. Service returns a domain entity (`Market` dataclass)
4. Endpoint maps it to `MarketResponse` via `from_domain()`
5. If service raises a domain exception (e.g., `EntityNotFoundError`), the global handler maps it to HTTP 404

## Request/Response Schemas

Separate Pydantic models for input and output. **Response schemas map from domain entities, not ORM models.**

```python
# app/schemas/market.py
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.domain.entities.market import Market


class MarketCreate(BaseModel):
    """Input schema for creating a market."""

    name: str = Field(min_length=1, max_length=255)
    description: str = Field(min_length=1, max_length=5000)
    end_date: datetime


class MarketUpdate(BaseModel):
    """Input schema for partial market update."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=5000)
    end_date: datetime | None = None


class MarketResponse(BaseModel):
    """Output schema returned to clients."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str
    slug: str
    status: str
    end_date: datetime
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, entity: Market) -> "MarketResponse":
        """Map a domain entity to a response schema."""
        return cls.model_validate(entity, from_attributes=True)
```

### Conventions

- `<Entity>Create` — required fields for creation. Use `Field()` constraints.
- `<Entity>Update` — all fields optional for partial updates.
- `<Entity>Response` — full representation returned to clients. `from_attributes=True` works with both dataclass entities and ORM models. The `from_domain()` classmethod documents the mapping intent.
- For list endpoints returning paginated data, use a generic wrapper:

```python
# app/schemas/common.py
from pydantic import BaseModel


class PaginatedResponse[T](BaseModel):
    data: list[T]
    total: int
    limit: int
    offset: int
```

## Domain Exception Handling

Services raise **domain exceptions**. The presentation layer maps them to HTTP responses via global exception handlers. **Endpoints never catch domain exceptions manually** — the handlers do it automatically.

### Domain Exception Hierarchy

```python
# app/domain/exceptions.py — ZERO external dependencies
class DomainError(Exception):
    """Base for all domain exceptions."""


class EntityNotFoundError(DomainError):
    """Raised when a requested entity does not exist."""


class PermissionDeniedError(DomainError):
    """Raised when the user lacks permission for the operation."""


class BusinessRuleViolationError(DomainError):
    """Raised when a business rule is violated (e.g., market already closed)."""


class DuplicateEntityError(DomainError):
    """Raised when creating an entity that already exists (e.g., duplicate slug)."""
```

### Global Exception Handlers

```python
# app/api/exception_handlers.py
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.domain.exceptions import (
    BusinessRuleViolationError,
    DomainError,
    DuplicateEntityError,
    EntityNotFoundError,
    PermissionDeniedError,
)

DOMAIN_EXCEPTION_MAP: dict[type[DomainError], int] = {
    EntityNotFoundError: 404,
    PermissionDeniedError: 403,
    BusinessRuleViolationError: 422,
    DuplicateEntityError: 409,
}


def register_exception_handlers(app: FastAPI) -> None:
    """Register domain exception → HTTP status code mappings."""

    for exc_class, status_code in DOMAIN_EXCEPTION_MAP.items():

        @app.exception_handler(exc_class)
        async def _handler(
            request: Request,
            exc: DomainError,
            sc: int = status_code,
        ) -> JSONResponse:
            return JSONResponse(
                status_code=sc,
                content={
                    "detail": str(exc),
                    "error_code": type(exc).__name__,
                },
            )
```

### How It Flows

```
Endpoint → Service → raises EntityNotFoundError("Market 123 not found")
                                    ↓
                    Global exception handler catches it
                                    ↓
                    Returns JSONResponse(status_code=404, ...)
```

The endpoint code stays clean — no try/except, no HTTPException for business logic:

```python
@router.get("/{market_id}")
async def get_market(
    market_id: UUID,
    service: MarketServiceDep,
) -> MarketResponse:
    # If market doesn't exist, service raises EntityNotFoundError
    # Global handler converts it to 404 — no manual catching needed
    market = await service.get_by_id(market_id)
    return MarketResponse.from_domain(market)
```

### Standard Error Response Format

All error responses follow this shape:

```json
{
  "detail": "Human-readable error message",
  "error_code": "EntityNotFoundError"
}
```

### When to Use HTTPException Directly

`HTTPException` is still appropriate for **presentation-layer concerns** that don't involve domain logic:

- Authentication failures (401) — in DI functions, not services
- Request validation beyond Pydantic (rare)
- Rate limiting responses

## Query Parameter Models

Since FastAPI 0.115, you can group related query parameters into Pydantic models. This is the preferred pattern for endpoints with multiple filters.

```python
from fastapi import Query
from pydantic import BaseModel, ConfigDict, Field

from app.domain.value_objects.market_status import MarketStatus


class MarketFilters(BaseModel):
    """Query parameters for filtering markets."""

    model_config = ConfigDict(extra="forbid")

    status: MarketStatus | None = None
    created_by_id: UUID | None = None
    limit: int = Field(default=20, le=100, ge=1)
    offset: int = Field(default=0, ge=0)


@router.get("/")
async def list_markets(
    filters: Annotated[MarketFilters, Query()],
    service: MarketServiceDep,
) -> PaginatedResponse[MarketResponse]:
    markets, total = await service.list_markets(
        status=filters.status,
        created_by_id=filters.created_by_id,
        offset=filters.offset,
        limit=filters.limit,
    )
    return PaginatedResponse(
        data=[MarketResponse.from_domain(m) for m in markets],
        total=total,
        limit=filters.limit,
        offset=filters.offset,
    )
```

### Benefits

- **Reusable**: the same filter model can be shared across related endpoints.
- **Validated**: `Field()` constraints are enforced automatically.
- **Strict**: `extra="forbid"` rejects unknown query parameters.
- **Type-safe**: IDE autocompletion on the `filters` object.

### Header and Cookie Models

The same pattern works for headers and cookies (also since 0.115):

```python
from fastapi import Cookie, Header


class TraceHeaders(BaseModel):
    x_request_id: str | None = None
    x_correlation_id: str | None = None


class SessionCookies(BaseModel):
    session_token: str | None = None


@router.get("/debug")
async def debug_info(
    headers: Annotated[TraceHeaders, Header()],
    cookies: Annotated[SessionCookies, Cookie()],
) -> dict:
    ...
```

## Background Tasks

Use `BackgroundTasks` for lightweight fire-and-forget work that runs after the response is sent.

```python
from fastapi import BackgroundTasks


async def send_welcome_email(email: str) -> None:
    # lightweight I/O, not CPU-bound
    ...


@router.post("/", status_code=201)
async def register_user(
    body: UserCreate,
    service: UserServiceDep,
    user: CurrentUser,
    background_tasks: BackgroundTasks,
) -> UserResponse:
    created = await service.create_user(body, created_by=user.id)
    background_tasks.add_task(send_welcome_email, created.email)
    return UserResponse.from_domain(created)
```

### When to Use BackgroundTasks vs a Task Queue

| Scenario | Use |
|---|---|
| Send a notification email | `BackgroundTasks` |
| Write an audit log entry | `BackgroundTasks` |
| Generate a PDF report (seconds) | `BackgroundTasks` |
| Process a large file upload (minutes) | Celery / ARQ / TaskIQ |
| Run an ML inference pipeline | Celery / ARQ / TaskIQ |
| Any job that must survive a server restart | Celery / ARQ / TaskIQ |

Rule of thumb: if the task takes more than a few seconds or must be retried on failure, use an external task queue.

**Note:** Since FastAPI 0.118, the exit code of `yield` dependencies runs **after** the response is sent. This means cleanup logic (e.g., closing sessions) happens after background tasks finish.

## Lifespan Events

Use `@asynccontextmanager` lifespan for startup/shutdown logic. Never use the deprecated `on_event` decorators.

```python
# app/main.py
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

from app.infrastructure.persistence.database import engine


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # --- Startup ---
    # Verify DB connectivity (engine is lazy)
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))

    yield

    # --- Shutdown ---
    await engine.dispose()
```

### What Goes in Lifespan

- **Startup**: open connection pools (DB, Redis, HTTP clients), load configuration, warm caches.
- **Shutdown**: close connection pools, flush pending writes, release resources.
- **Never**: run long-lived background loops here — use a dedicated task runner.

## Middleware — Pure ASGI

**NEVER use `BaseHTTPMiddleware`.** It has known, unfixable issues:
- Buffers entire response in memory (no backpressure — OOM risk)
- Breaks `contextvars` propagation between middleware and endpoints
- Incompatible with `BackgroundTasks` (timeout issues, swallowed errors)
- Starlette plans to remove it in version 1.0

**ALWAYS use pure ASGI middleware** — it's how Starlette's own built-in middleware is implemented.

### CORS

Load allowed origins from settings. Never hardcode them.

```python
# app/main.py
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings


def create_app() -> FastAPI:
    app = FastAPI(title="AV Marketplace", lifespan=lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ... register exception handlers, include routers
    return app
```

### Custom Middleware — Request ID Example

```python
# app/middleware/request_id.py
import uuid

from starlette.types import ASGIApp, Message, Receive, Scope, Send


class RequestIdMiddleware:
    """Injects X-Request-ID into request scope and response headers."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        # Extract from incoming header or generate new
        headers = dict(scope.get("headers", []))
        request_id = headers.get(b"x-request-id", b"").decode() or str(uuid.uuid4())

        # Store in scope for access by endpoints via request.scope["state"]
        scope.setdefault("state", {})["request_id"] = request_id

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                response_headers = list(message.get("headers", []))
                response_headers.append((b"x-request-id", request_id.encode()))
                message["headers"] = response_headers
            await send(message)

        await self.app(scope, receive, send_wrapper)
```

Register middleware in the app factory:

```python
from app.middleware.request_id import RequestIdMiddleware

app.add_middleware(RequestIdMiddleware)
```

### Custom Middleware — Timing Example

```python
# app/middleware/timing.py
import time

from starlette.types import ASGIApp, Message, Receive, Scope, Send


class TimingMiddleware:
    """Adds X-Process-Time header to responses."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        start = time.perf_counter()

        async def send_wrapper(message: Message) -> None:
            if message["type"] == "http.response.start":
                elapsed = time.perf_counter() - start
                headers = list(message.get("headers", []))
                headers.append((b"x-process-time", f"{elapsed:.4f}".encode()))
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, send_wrapper)
```

### Pure ASGI Middleware Pattern

The structure is always the same:

```python
class MyMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        # Before request: modify scope or receive
        # ...

        async def send_wrapper(message: Message) -> None:
            # After response start: modify headers
            # After response body: inspect/log body chunks
            await send(message)

        await self.app(scope, receive, send_wrapper)
```

**Key concepts:**
- `scope`: dict with request metadata (type, path, headers, state). Modify to pass data to endpoints.
- `receive`: async callable that returns request body chunks. Wrap to intercept/log body.
- `send`: async callable that sends response chunks. Wrap to modify response headers or body.
- Always pass through non-HTTP scopes (`websocket`, `lifespan`) with `await self.app(scope, receive, send)`.

### Middleware Ordering

Middleware executes in **reverse registration order** (last registered = first to execute). Register in this order:

```python
# 1. CORS — must be outermost (registered first, executes last)
app.add_middleware(CORSMiddleware, ...)

# 2. Request ID — inject early so all subsequent middleware and endpoints see it
app.add_middleware(RequestIdMiddleware)

# 3. Timing — measure after request ID is set
app.add_middleware(TimingMiddleware)
```

Execution flow for an incoming request:
```
Request → TimingMiddleware → RequestIdMiddleware → CORSMiddleware → Router → Endpoint
Response ← TimingMiddleware ← RequestIdMiddleware ← CORSMiddleware ← Router ← Endpoint
```

## Testing FastAPI

### pytest Configuration

Use modern `pytest-asyncio` config — no need for `@pytest.mark.asyncio` decorators or `event_loop` fixture:

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "session"
```

### Test Client Setup

Use `httpx.AsyncClient` with `ASGITransport` for all async endpoint tests:

```python
# tests/conftest.py
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app
from app.api.dependencies import get_unit_of_work, get_current_user
from tests.fakes import FakeUnitOfWork, make_fake_user


@pytest.fixture
def app():
    app = create_app()

    app.dependency_overrides[get_unit_of_work] = FakeUnitOfWork
    app.dependency_overrides[get_current_user] = lambda: make_fake_user(role="admin")

    yield app

    app.dependency_overrides.clear()


@pytest.fixture
async def client(app):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
```

### Overriding Dependencies

Override the **UoW dependency** (not the session). This keeps tests consistent with the DDD architecture:

```python
# tests/fakes.py
from uuid import UUID

from app.domain.entities.market import Market
from app.domain.entities.user import User


class FakeMarketRepository:
    def __init__(self) -> None:
        self.markets: dict[UUID, Market] = {}

    async def get_by_id(self, entity_id: UUID) -> Market | None:
        return self.markets.get(entity_id)

    async def save(self, entity: Market) -> Market:
        self.markets[entity.id] = entity
        return entity

    async def delete(self, entity: Market) -> None:
        self.markets.pop(entity.id, None)

    async def get_all(
        self, *, offset: int = 0, limit: int = 100
    ) -> list[Market]:
        items = list(self.markets.values())
        return items[offset : offset + limit]


class FakeUnitOfWork:
    def __init__(self) -> None:
        self.markets = FakeMarketRepository()
        self.committed = False

    async def __aenter__(self) -> "FakeUnitOfWork":
        return self

    async def __aexit__(self, *args: object) -> None:
        pass

    async def commit(self) -> None:
        self.committed = True

    async def rollback(self) -> None:
        pass


def make_fake_user(role: str = "user") -> User:
    return User(
        id=UUID("00000000-0000-0000-0000-000000000001"),
        email="test@example.com",
        role=role,
    )
```

### Testing Endpoints

```python
# tests/functional/test_markets_api.py
from httpx import AsyncClient


class TestCreateMarket:
    async def test_returns_201_with_valid_data(self, client: AsyncClient) -> None:
        response = await client.post(
            "/api/v1/markets/",
            json={
                "name": "Election 2024",
                "description": "US Presidential Election",
                "end_date": "2024-11-05T00:00:00Z",
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "Election 2024"
        assert "id" in data

    async def test_returns_422_with_missing_name(self, client: AsyncClient) -> None:
        response = await client.post(
            "/api/v1/markets/",
            json={"description": "Test", "end_date": "2024-11-05T00:00:00Z"},
        )
        assert response.status_code == 422


class TestGetMarket:
    async def test_returns_404_for_nonexistent_market(
        self, client: AsyncClient
    ) -> None:
        response = await client.get(
            "/api/v1/markets/00000000-0000-0000-0000-000000000000"
        )
        assert response.status_code == 404

    async def test_returns_market_data(self, client: AsyncClient) -> None:
        # Create first, then get
        create_response = await client.post(
            "/api/v1/markets/",
            json={
                "name": "Test Market",
                "description": "Test",
                "end_date": "2024-12-31T00:00:00Z",
            },
        )
        market_id = create_response.json()["id"]

        response = await client.get(f"/api/v1/markets/{market_id}")

        assert response.status_code == 200
        assert response.json()["name"] == "Test Market"


class TestListMarkets:
    async def test_returns_paginated_response(self, client: AsyncClient) -> None:
        response = await client.get("/api/v1/markets/?limit=10&offset=0")

        assert response.status_code == 200
        data = response.json()
        assert isinstance(data["data"], list)
        assert "total" in data
```

### Testing with Lifespan Events

`AsyncClient` does NOT trigger lifespan events. Use synchronous `TestClient` in a `with` block for lifespan-dependent tests:

```python
from fastapi.testclient import TestClient


def test_health_check(app):
    with TestClient(app) as client:
        response = client.get("/health")
        assert response.status_code == 200
```

### Testing Conventions

- Override `get_unit_of_work` with `FakeUnitOfWork` — never mock FastAPI or SQLAlchemy internals.
- Test the HTTP interface (status codes, response bodies, headers), not service internals.
- Each test class targets one endpoint or related group of endpoints.
- Always clear `dependency_overrides` after tests (use `yield` fixtures).
- No `@pytest.mark.asyncio` needed — `asyncio_mode = "auto"` handles it.
- See the `tdd-workflow` skill for full testing rules and Fake vs Mock guidance.
- See the `sqlalchemy-patterns` skill for `FakeUnitOfWork` and `FakeRepository` patterns.

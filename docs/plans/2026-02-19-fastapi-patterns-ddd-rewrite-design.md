# FastAPI Patterns — Strict DDD Rewrite Design

**Date:** 2026-02-19
**Status:** Approved
**Skill:** python-developer/skills/fastapi-patterns
**Current version:** part of python-developer 2.0.0
**Target runtime:** Python 3.13+, FastAPI 0.128+, Pydantic v2.7+

## Context

The `fastapi-patterns` skill guides FastAPI code generation for AppVerk projects. The current skill was written with an infrastructure-centric approach where endpoints receive `AsyncSession` directly and services depend on SQLAlchemy types. AppVerk projects follow DDD and Clean Architecture — the skill must reflect this and be consistent with the already-rewritten `sqlalchemy-patterns` skill.

### Audit Findings

**CRITICAL — DDD / Clean Architecture violations:**
1. Service layer depends on `AsyncSession` directly — should use `UnitOfWork` Protocol
2. `DbSession` dependency exposes infrastructure type (`AsyncSession`) to presentation layer
3. No domain exception handling strategy — endpoints mix `HTTPException` with domain logic
4. `MarketResponse.model_validate(market)` assumes ORM model, not domain entity

**IMPORTANT — Inconsistencies with sqlalchemy-patterns + technical issues:**
5. No UoW dependency injection pattern (sqlalchemy-patterns defines `UoW` dependency)
6. `BaseHTTPMiddleware` used for custom middleware — de facto deprecated, memory leaks, breaks contextvars, incompatible with BackgroundTasks. Starlette plans to remove it in 1.0.
7. HARD-RULES hardcode `make typecheck` and `make test`
8. `@pytest.mark.asyncio` decorators inconsistent with `asyncio_mode = "auto"` from sqlalchemy-patterns

**MODERATE — Missing modern FastAPI patterns:**
9. No Pydantic models for Query/Header/Cookie params (FastAPI 0.115+ feature)
10. No guidance on `response_model` vs return type annotation
11. No structured domain exception → HTTP response mapping flow
12. No request context / structured logging pattern
13. Authentication limited to `HTTPBearer` — no `OAuth2PasswordBearer` or JWT patterns

**MINOR:**
14. `PaginatedResponse[T]` uses Python 3.12+ syntax but no version note
15. No note about `yield` dependency behavior change (FastAPI 0.118)
16. Middleware ordering explanation incomplete
17. `from_attributes=True` assumes ORM without noting it works with dataclasses too

### Design Decisions

**Python 3.13+ / PEP 695:**
- All generic types use PEP 695 syntax: `class Foo[T](Base):` instead of `Generic[T]`
- Type aliases use `type Alias = ...` instead of `TypeAlias`
- No `TypeVar` declarations
- Minimum Python 3.13, FastAPI 0.128+, Pydantic v2.7+

**Strict DDD alignment with sqlalchemy-patterns:**
- Endpoints inject `UnitOfWork` (Protocol from domain), not `AsyncSession`
- Services receive `UnitOfWork`, never infrastructure types
- Domain exceptions propagate through global exception handlers
- Response schemas map from domain entities, not ORM models

## Design

### Skill Structure

Organized by Clean Architecture layers, showing FastAPI's role as presentation layer:

```
1.  HARD-RULES
2.  Architecture Overview (FastAPI's role in Clean Architecture)
3.  Router Structure
4.  Dependency Injection — UoW & Services
5.  Request/Response Schemas (mapping from domain entities)
6.  Domain Exception Handling (hierarchy → HTTP mapping)
7.  Query Parameter Models (Pydantic models for Query/Header/Cookie)
8.  Authentication Patterns
9.  Background Tasks
10. Lifespan Events
11. Middleware — Pure ASGI
12. Testing
```

### HARD-RULES (Updated)

Rules to ADD:
- NEVER raise `HTTPException` in services or domain layer — services raise domain exceptions, presentation layer maps them to HTTP responses
- NEVER inject `AsyncSession` into endpoints — ALWAYS use `UnitOfWork` Protocol dependency
- NEVER use `BaseHTTPMiddleware` — ALWAYS use pure ASGI middleware
- NEVER return domain entities directly from endpoints — ALWAYS map through response schemas
- ALWAYS use PEP 695 type parameter syntax (`class Foo[T]`, `type Alias = ...`) — NEVER use `TypeVar` / `Generic[T]` / `TypeAlias`

Rules to FIX:
- "ALWAYS run `make typecheck` and `make test`" → "ALWAYS run the project's typecheck and test commands after any endpoint change"

Rules to KEEP (unchanged):
- NEVER define endpoints on `FastAPI()` app — ALWAYS use `APIRouter`
- NEVER use sync `def` for I/O endpoints — ALWAYS use `async def`
- NEVER return raw dicts — use typed return annotation with Pydantic model
- NEVER use separate Create/Read naming — follow `ItemCreate`, `ItemUpdate`, `ItemResponse`
- NEVER catch generic `Exception` in endpoints
- NEVER hardcode CORS origins
- NEVER use `@app.on_event` — use `lifespan` async context manager
- ALWAYS use `Annotated[T, Depends()]` — NEVER `Depends()` as default value
- ALWAYS declare explicit `status_code` on mutating endpoints

### Architecture Overview

```
┌─────────────────────────────────────────────────┐
│  Presentation Layer (FastAPI routers, schemas)   │
│  - Receives HTTP requests                        │
│  - Maps request → service call → response        │
│  - Registers domain exception handlers           │
│  Depends on: Application Layer, Domain Layer     │
├─────────────────────────────────────────────────┤
│  Application Layer (Services / Use Cases)        │
│  Depends on: Domain Layer only                   │
│  Uses: UnitOfWork Protocol, Repository Protocol  │
├─────────────────────────────────────────────────┤
│  Domain Layer (Entities, Value Objects,           │
│    Repository Protocols, UoW Protocol,           │
│    Domain Exceptions)                            │
│  Depends on: NOTHING                             │
├─────────────────────────────────────────────────┤
│  Infrastructure Layer (ORM models, SA repos,     │
│    SA UoW, Data Mappers, Alembic)                │
│  Depends on: Domain Layer + SQLAlchemy           │
└─────────────────────────────────────────────────┘

FastAPI lives in the Presentation Layer.
It NEVER touches infrastructure directly.
```

### Dependency Injection — UoW & Services

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


# Service dependencies — composed from UoW
async def get_market_service(uow: UoW) -> MarketService:
    return MarketService(uow)


MarketServiceDep = Annotated[MarketService, Depends(get_market_service)]
```

### Endpoint Pattern

```python
@router.post("/", status_code=201)
async def create_market(
    body: MarketCreate,
    service: MarketServiceDep,
    user: CurrentUser,
) -> MarketResponse:
    market = await service.create_market(body, user_id=user.id)
    return MarketResponse.from_domain(market)
```

- Endpoint receives service (not session, not UoW directly)
- Service returns domain entity
- Endpoint maps domain entity → response schema
- No HTTPException in service — domain exceptions handled globally

### Domain Exception Handling

```python
# app/domain/exceptions.py — zero dependencies
class DomainError(Exception):
    """Base for all domain exceptions."""

class EntityNotFoundError(DomainError): ...
class PermissionDeniedError(DomainError): ...
class BusinessRuleViolationError(DomainError): ...


# app/api/exception_handlers.py — presentation layer
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.domain.exceptions import (
    DomainError,
    EntityNotFoundError,
    PermissionDeniedError,
    BusinessRuleViolationError,
)

DOMAIN_EXCEPTION_MAP: dict[type[DomainError], int] = {
    EntityNotFoundError: 404,
    PermissionDeniedError: 403,
    BusinessRuleViolationError: 422,
}

def register_exception_handlers(app: FastAPI) -> None:
    for exc_class, status_code in DOMAIN_EXCEPTION_MAP.items():
        @app.exception_handler(exc_class)
        async def handler(
            request: Request, exc: DomainError, sc: int = status_code
        ) -> JSONResponse:
            return JSONResponse(
                status_code=sc,
                content={"detail": str(exc), "error_code": type(exc).__name__},
            )
```

### Response Schemas — from_domain()

```python
class MarketResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    status: str
    # ...

    @classmethod
    def from_domain(cls, entity: Market) -> "MarketResponse":
        return cls.model_validate(entity, from_attributes=True)
```

`from_attributes=True` works with both dataclass and ORM — but explicit `from_domain()` documents intent.

### Query Parameter Models (FastAPI 0.115+)

```python
from fastapi import Query

class MarketFilters(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: MarketStatus | None = None
    limit: int = Field(default=20, le=100)
    offset: int = Field(default=0, ge=0)


@router.get("/")
async def list_markets(
    filters: Annotated[MarketFilters, Query()],
    service: MarketServiceDep,
) -> PaginatedResponse[MarketResponse]:
    ...
```

### PaginatedResponse — PEP 695

```python
class PaginatedResponse[T](BaseModel):
    data: list[T]
    total: int
    limit: int
    offset: int
```

### Authentication Patterns

```python
from fastapi import Depends, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

security = HTTPBearer()

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

Note: `Security()` instead of `Depends()` for proper OpenAPI security scheme docs.

Skill will also document `OAuth2PasswordBearer` for username/password flows with Swagger UI "Authorize" button.

### Middleware — Pure ASGI

```python
from starlette.types import ASGIApp, Receive, Scope, Send

class RequestIdMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        request_id = ...  # extract or generate
        scope.setdefault("state", {})["request_id"] = request_id

        async def send_wrapper(message: dict) -> None:
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.append((b"x-request-id", request_id.encode()))
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, send_wrapper)
```

### Testing — aligned with sqlalchemy-patterns

```python
# pyproject.toml
# [tool.pytest.ini_options]
# asyncio_mode = "auto"
# asyncio_default_fixture_loop_scope = "session"

# No @pytest.mark.asyncio needed

@pytest.fixture
def app():
    app = create_app()
    app.dependency_overrides[get_unit_of_work] = lambda: FakeUnitOfWork()
    yield app
    app.dependency_overrides.clear()


@pytest.fixture
async def client(app):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


class TestMarketsAPI:
    async def test_create_market_returns_201(self, client: AsyncClient) -> None:
        response = await client.post("/api/v1/markets/", json={...})
        assert response.status_code == 201

    async def test_get_nonexistent_market_returns_404(self, client: AsyncClient) -> None:
        response = await client.get("/api/v1/markets/00000000-...")
        assert response.status_code == 404
```

### What Gets Removed from Current Skill

1. `DbSession = Annotated[AsyncSession, Depends(get_db_session)]` — replaced by UoW
2. `MarketService(session)` pattern — replaced by `MarketService(uow)`
3. `BaseHTTPMiddleware` examples — replaced by pure ASGI middleware
4. `@pytest.mark.asyncio` decorators — redundant with `asyncio_mode = "auto"`
5. Hardcoded `make typecheck` / `make test` in HARD-RULES

### What Gets Added (Not in Current Skill)

1. Architecture overview with layer diagram (FastAPI as presentation layer)
2. UoW dependency injection pattern (consistent with sqlalchemy-patterns)
3. Service dependency composition via `Depends()`
4. Domain exception hierarchy + global handler mapping
5. `from_domain()` classmethod on response schemas
6. Pydantic models for Query/Header/Cookie params (FastAPI 0.115+)
7. Pure ASGI middleware with concrete example
8. `Security()` for auth dependencies (OpenAPI-aware)
9. `OAuth2PasswordBearer` pattern alongside `HTTPBearer`
10. Note about `yield` dependency behavior change (FastAPI 0.118)
11. PEP 695 type parameter syntax everywhere
12. Modern pytest-asyncio config (no markers, no event_loop fixture)
13. `FakeUnitOfWork` in test dependency overrides

### What Stays (Updated)

1. Router structure (prefix, tags, file layout) — unchanged
2. `Annotated[T, Depends()]` pattern — unchanged, reinforced
3. CORS middleware configuration — unchanged
4. Background Tasks section — unchanged
5. Lifespan events — minor update for yield behavior note
6. `PaginatedResponse[T]` — updated to PEP 695 syntax
7. Error response format — extended with domain exception mapping
8. Schema naming conventions (`*Create`, `*Update`, `*Response`) — unchanged

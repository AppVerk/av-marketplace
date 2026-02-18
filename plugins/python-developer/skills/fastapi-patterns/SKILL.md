---
name: fastapi-patterns
description: Enforces FastAPI patterns: endpoint structure, dependency injection, error handling, middleware. Activates when working with FastAPI routers, endpoints, or middleware.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(uvicorn:*)
---

# FastAPI Patterns

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER define endpoints directly on the `FastAPI()` app instance — ALWAYS use `APIRouter` and include it via `app.include_router()`
- NEVER use synchronous `def` for endpoints that perform I/O — ALWAYS use `async def`
- NEVER return raw dicts from endpoints — ALWAYS declare a `response_model` or use a typed return annotation with a Pydantic model
- NEVER use separate Create/Read schemas named differently per endpoint — ALWAYS follow the `ItemCreate`, `ItemUpdate`, `ItemResponse` naming convention
- NEVER catch generic `Exception` in endpoints — raise `HTTPException` with specific status codes or use custom exception handlers
- NEVER hardcode CORS origins in source code — ALWAYS load them from settings/environment
- NEVER use `@app.on_event("startup")` or `@app.on_event("shutdown")` — ALWAYS use the `lifespan` async context manager
- ALWAYS use `Annotated[T, Depends(...)]` for dependency injection — NEVER pass `Depends()` as a default parameter value
- ALWAYS declare explicit `status_code` on mutating endpoints (`POST`, `PUT`, `PATCH`, `DELETE`)
- ALWAYS run `make typecheck` and `make test` after any endpoint change
</HARD-RULES>

These are the internal FastAPI patterns that guide API development for AppVerk projects.

## Router Structure

One router per domain module. Each router lives in its own file under `api/routes/`.

```python
# app/api/routes/markets.py
from fastapi import APIRouter

router = APIRouter(
    prefix="/markets",
    tags=["markets"],
)


@router.get("/", response_model=list[MarketResponse])
async def list_markets(
    status: MarketStatus | None = None,
    limit: int = 20,
    offset: int = 0,
) -> list[MarketResponse]:
    ...


@router.get("/{market_id}", response_model=MarketResponse)
async def get_market(market_id: UUID) -> MarketResponse:
    ...


@router.post("/", response_model=MarketResponse, status_code=201)
async def create_market(
    body: MarketCreate,
) -> MarketResponse:
    ...
```

Register all routers in the app factory:

```python
# app/main.py
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI

from app.api.routes import markets, users, trades


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # startup: open DB pool, warm caches, etc.
    yield
    # shutdown: close DB pool, flush buffers, etc.


def create_app() -> FastAPI:
    app = FastAPI(title="AV Marketplace", lifespan=lifespan)

    app.include_router(markets.router, prefix="/api/v1")
    app.include_router(users.router, prefix="/api/v1")
    app.include_router(trades.router, prefix="/api/v1")

    return app
```

### Conventions

- **Prefix**: set on the router (`prefix="/markets"`), not at include time, unless you need a version prefix like `/api/v1`.
- **Tags**: one tag per router matching the domain name. Used for OpenAPI docs grouping.
- **File layout**: `app/api/routes/<domain>.py` with a module-level `router` variable.

## Dependency Injection

Use `Annotated` types with `Depends()` for all injected dependencies. Define reusable type aliases.

### Database Session

```python
# app/api/dependencies.py
from typing import Annotated
from collections.abc import AsyncIterator

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session_factory


async def get_db_session() -> AsyncIterator[AsyncSession]:
    async with async_session_factory() as session:
        yield session


DbSession = Annotated[AsyncSession, Depends(get_db_session)]
```

### Authentication

```python
# app/api/dependencies.py
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.models.user import User
from app.services.auth import AuthService

security = HTTPBearer()


async def get_auth_service() -> AuthService:
    return AuthService()


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
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

### Using Dependencies in Endpoints

```python
# app/api/routes/markets.py
from app.api.dependencies import CurrentUser, DbSession


@router.post("/", response_model=MarketResponse, status_code=201)
async def create_market(
    body: MarketCreate,
    session: DbSession,
    user: CurrentUser,
) -> MarketResponse:
    market = await MarketService(session).create(body, created_by=user.id)
    return MarketResponse.model_validate(market)
```

### Nested Dependencies

Dependencies can depend on other dependencies. FastAPI resolves the graph automatically:

```python
async def get_market_service(session: DbSession) -> MarketService:
    return MarketService(session)


MarketServiceDep = Annotated[MarketService, Depends(get_market_service)]


@router.get("/{market_id}", response_model=MarketResponse)
async def get_market(
    market_id: UUID,
    service: MarketServiceDep,
) -> MarketResponse:
    market = await service.get_by_id(market_id)
    if market is None:
        raise HTTPException(status_code=404, detail="Market not found")
    return MarketResponse.model_validate(market)
```

## Request/Response Models

Separate Pydantic models for input and output. Never expose ORM models directly.

```python
# app/schemas/market.py
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class MarketCreate(BaseModel):
    """Input schema for creating a market."""

    name: str
    description: str
    end_date: datetime


class MarketUpdate(BaseModel):
    """Input schema for partial market update."""

    name: str | None = None
    description: str | None = None
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
```

### Conventions

- `<Entity>Create` -- required fields for creation.
- `<Entity>Update` -- all fields optional for partial updates.
- `<Entity>Response` -- full representation returned to clients. Uses `from_attributes=True` to map from SQLAlchemy models.
- For list endpoints returning paginated data, use a generic wrapper:

```python
from pydantic import BaseModel


class PaginatedResponse[T](BaseModel):
    data: list[T]
    total: int
    limit: int
    offset: int


# Usage in endpoint:
# @router.get("/", response_model=PaginatedResponse[MarketResponse])
# async def list_markets(...) -> PaginatedResponse[MarketResponse]:
```

## Error Handling

### HTTPException for Known Errors

Raise `HTTPException` directly in endpoint code for expected error conditions:

```python
from fastapi import HTTPException, status


@router.get("/{market_id}", response_model=MarketResponse)
async def get_market(
    market_id: UUID,
    service: MarketServiceDep,
) -> MarketResponse:
    market = await service.get_by_id(market_id)
    if market is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Market not found",
        )
    return MarketResponse.model_validate(market)
```

### Custom Exception Handlers

For domain exceptions that can be raised from services, register global handlers:

```python
# app/api/exceptions.py
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.exceptions import EntityNotFoundError, PermissionDeniedError


class ErrorResponse(BaseModel):
    detail: str
    error_code: str


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(EntityNotFoundError)
    async def not_found_handler(
        request: Request, exc: EntityNotFoundError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=404,
            content={"detail": str(exc), "error_code": "NOT_FOUND"},
        )

    @app.exception_handler(PermissionDeniedError)
    async def permission_denied_handler(
        request: Request, exc: PermissionDeniedError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=403,
            content={"detail": str(exc), "error_code": "PERMISSION_DENIED"},
        )
```

Call `register_exception_handlers(app)` in your app factory.

### Standard Error Response Format

All error responses follow this shape:

```json
{
  "detail": "Human-readable error message",
  "error_code": "MACHINE_READABLE_CODE"
}
```

## Background Tasks

Use `BackgroundTasks` for lightweight fire-and-forget work that should run after the response is sent.

```python
from fastapi import BackgroundTasks


async def send_welcome_email(email: str) -> None:
    # lightweight I/O, not CPU-bound
    ...


@router.post("/", response_model=UserResponse, status_code=201)
async def register_user(
    body: UserCreate,
    background_tasks: BackgroundTasks,
    session: DbSession,
) -> UserResponse:
    user = await UserService(session).create(body)
    background_tasks.add_task(send_welcome_email, user.email)
    return UserResponse.model_validate(user)
```

### When to Use BackgroundTasks vs a Task Queue

| Scenario | Use |
|---|---|
| Send a notification email | `BackgroundTasks` |
| Write an audit log entry | `BackgroundTasks` |
| Generate a PDF report (seconds) | `BackgroundTasks` |
| Process a large file upload (minutes) | Celery / ARQ |
| Run an ML inference pipeline | Celery / ARQ |
| Any job that must survive a server restart | Celery / ARQ |

Rule of thumb: if the task takes more than a few seconds or must be retried on failure, use an external task queue.

## Lifespan Events

Use `@asynccontextmanager` lifespan for startup/shutdown logic. Never use the deprecated `on_event` decorators.

```python
# app/main.py
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database import engine, async_session_factory
from app.cache import redis_pool


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # --- Startup ---
    # Initialize DB connection pool (engine is already lazy, but warm it)
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))  # verify connectivity

    # Initialize Redis
    await redis_pool.initialize()

    yield

    # --- Shutdown ---
    await redis_pool.close()
    await engine.dispose()
```

### What Goes in Lifespan

- **Startup**: open connection pools (DB, Redis, HTTP clients), load configuration, warm caches.
- **Shutdown**: close connection pools, flush pending writes, release resources.
- **Never**: run long-lived background loops here -- use a dedicated task runner for that.

## Middleware

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

    # ... include routers
    return app
```

### Custom Middleware

For cross-cutting concerns like request timing or request-ID injection:

```python
# app/middleware/request_id.py
import uuid

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response
```

Register middleware in the app factory:

```python
from app.middleware.request_id import RequestIdMiddleware

app.add_middleware(RequestIdMiddleware)
```

**Middleware ordering**: middleware executes in reverse registration order. Register CORS first (last to execute), then custom middleware.

## Testing FastAPI

### Test Client Setup

Use `httpx.AsyncClient` for async tests and `TestClient` for synchronous tests.

```python
# tests/conftest.py
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app


@pytest.fixture
def app():
    return create_app()


@pytest.fixture
async def client(app):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
```

### Overriding Dependencies

Use `app.dependency_overrides` to swap real dependencies for fakes in tests:

```python
# tests/conftest.py
from app.api.dependencies import get_db_session, get_current_user
from tests.fakes import FakeDbSession, make_fake_user


@pytest.fixture
def app():
    app = create_app()

    fake_session = FakeDbSession()
    fake_user = make_fake_user(role="admin")

    app.dependency_overrides[get_db_session] = lambda: fake_session
    app.dependency_overrides[get_current_user] = lambda: fake_user

    yield app

    app.dependency_overrides.clear()
```

### Testing Endpoints

```python
# tests/functional/test_markets_api.py
import pytest
from httpx import AsyncClient


class TestMarketsAPI:
    @pytest.mark.asyncio
    async def test_create_market_returns_201(self, client: AsyncClient) -> None:
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

    @pytest.mark.asyncio
    async def test_get_nonexistent_market_returns_404(
        self, client: AsyncClient
    ) -> None:
        response = await client.get(
            "/api/v1/markets/00000000-0000-0000-0000-000000000000"
        )
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_list_markets_returns_paginated(
        self, client: AsyncClient
    ) -> None:
        response = await client.get("/api/v1/markets/?limit=10&offset=0")

        assert response.status_code == 200
        data = response.json()
        assert isinstance(data["data"], list)
        assert "total" in data
```

### Testing with Lifespan Events

When using `TestClient` (synchronous), wrap it in a `with` block to trigger lifespan:

```python
from fastapi.testclient import TestClient


def test_health_check(app):
    with TestClient(app) as client:
        response = client.get("/health")
        assert response.status_code == 200
```

### Testing Conventions

- Use `app.dependency_overrides` to inject Fake implementations -- never mock FastAPI internals.
- Test the HTTP interface (status codes, response bodies, headers), not service internals.
- Each test class targets one router/domain.
- See the `tdd-workflow` skill for full testing rules and Fake vs Mock guidance.

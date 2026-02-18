---
name: sqlalchemy-patterns
description: Enforces SQLAlchemy patterns: async sessions, repository pattern, Alembic migrations, query optimization. Activates when working with database models, queries, or migrations.
allowed-tools: Read, Grep, Glob, Bash(alembic:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*)
---

# SQLAlchemy Patterns

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER use synchronous SQLAlchemy sessions — ALWAYS use `AsyncSession` and `async_sessionmaker`
- NEVER use legacy Query API (`session.query(...)`) — ALWAYS use `select()` statements with `session.execute()` / `session.scalars()`
- NEVER access lazy-loaded relationships in async code — ALWAYS use eager loading (`selectinload`, `joinedload`) or explicit queries
- NEVER call `session.commit()` inside repository methods — the caller (service layer) owns the transaction boundary
- NEVER use `backref` — ALWAYS use explicit `back_populates` on both sides of a relationship
- NEVER write raw SQL strings for schema changes — ALWAYS use Alembic migrations
- NEVER use `session.execute(text(...))` for CRUD operations — use the ORM or core constructs
- ALWAYS define models with `Mapped[T]` type annotations and `mapped_column()` — NEVER use legacy `Column()` syntax
- ALWAYS use `DeclarativeBase` — NEVER use legacy `declarative_base()` function
- ALWAYS apply `selectinload()` for collection relationships in async queries
- ALWAYS run `make typecheck` and `make test` after any model or migration change
</HARD-RULES>

These are the internal SQLAlchemy patterns for async database access in AppVerk projects. All patterns target SQLAlchemy 2.0+ with async extensions exclusively.

## Model Definition

Use `DeclarativeBase` with `Mapped` type annotations. Every column uses `mapped_column()`.

```python
# app/models/base.py
import uuid
from datetime import datetime

from sqlalchemy import MetaData, String, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

# Consistent naming convention for constraints and indexes
convention = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=convention)

    type_annotation_map = {
        str: String(255),
    }
```

```python
# app/models/market.py
import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Market(Base):
    __tablename__ = "market"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text)
    slug: Mapped[str] = mapped_column(String(200), unique=True)
    status: Mapped[str] = mapped_column(String(50), default="draft")
    end_date: Mapped[datetime]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        server_default=func.now(), onupdate=func.now()
    )
    created_by_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("user.id"))

    # Relationships — always use back_populates, never backref
    created_by: Mapped["User"] = relationship(back_populates="markets")
    outcomes: Mapped[list["Outcome"]] = relationship(
        back_populates="market", cascade="all, delete-orphan"
    )
```

### Conventions

- **Primary keys**: `Mapped[uuid.UUID]` with `default=uuid.uuid4`.
- **Timestamps**: use `server_default=func.now()` so the DB generates them.
- **Nullable columns**: use `Mapped[str | None]`. Non-nullable is `Mapped[str]`.
- **String lengths**: always specify explicit lengths via `String(N)` for indexed/constrained columns.
- **Table names**: singular, lowercase (`market`, `user`, `trade`).

## Async Session Management

### Engine and Session Factory

```python
# app/database.py
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings

engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
)

async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)
```

### FastAPI Dependency

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

### Standalone Usage (scripts, CLI)

```python
from app.database import async_session_factory


async def run_task() -> None:
    async with async_session_factory() as session:
        # perform queries
        await session.commit()
```

### Key Settings

- **`expire_on_commit=False`**: prevents lazy-load errors when accessing attributes after commit in async context.
- **`pool_pre_ping=True`**: detects stale connections before use.
- **Never create engines per-request**. Use a single engine per application.

## Repository Pattern

Base repository provides typed CRUD. Domain repositories extend it with specific queries.

```python
# app/repositories/base.py
from typing import TypeVar
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.base import Base

ModelT = TypeVar("ModelT", bound=Base)


class BaseRepository[ModelT]:
    model: type[ModelT]

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_id(self, entity_id: UUID) -> ModelT | None:
        return await self.session.get(self.model, entity_id)

    async def get_all(
        self, *, offset: int = 0, limit: int = 100
    ) -> list[ModelT]:
        stmt = select(self.model).offset(offset).limit(limit)
        result = await self.session.scalars(stmt)
        return list(result.all())

    async def create(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        await self.session.flush()
        return entity

    async def create_many(self, entities: list[ModelT]) -> list[ModelT]:
        self.session.add_all(entities)
        await self.session.flush()
        return entities

    async def delete(self, entity: ModelT) -> None:
        self.session.delete(entity)  # delete() is synchronous
        await self.session.flush()
```

```python
# app/repositories/market.py
import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app.models.market import Market
from app.repositories.base import BaseRepository


class MarketRepository(BaseRepository[Market]):
    model = Market

    async def get_by_slug(self, slug: str) -> Market | None:
        stmt = select(Market).where(Market.slug == slug)
        return await self.session.scalar(stmt)

    async def get_with_outcomes(self, market_id: uuid.UUID) -> Market | None:
        stmt = (
            select(Market)
            .options(selectinload(Market.outcomes))
            .where(Market.id == market_id)
        )
        return await self.session.scalar(stmt)

    async def count_by_status(self, status: str) -> int:
        stmt = select(func.count()).select_from(Market).where(Market.status == status)
        result = await self.session.scalar(stmt)
        return result or 0
```

### Transaction Boundaries

The service layer owns commits, not the repository:

```python
# app/services/market.py
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.market import Market
from app.repositories.market import MarketRepository
from app.schemas.market import MarketCreate


class MarketService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = MarketRepository(session)

    async def create_market(self, data: MarketCreate, user_id: uuid.UUID) -> Market:
        market = Market(
            name=data.name,
            description=data.description,
            slug=generate_slug(data.name),
            created_by_id=user_id,
            end_date=data.end_date,
        )
        await self.repo.create(market)
        await self.session.commit()
        return market
```

## Relationships

### One-to-Many

```python
class User(Base):
    __tablename__ = "user"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True)

    markets: Mapped[list["Market"]] = relationship(
        back_populates="created_by", cascade="all, delete-orphan"
    )


class Market(Base):
    __tablename__ = "market"

    created_by_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("user.id"))
    created_by: Mapped["User"] = relationship(back_populates="markets")
```

### Many-to-Many

```python
from sqlalchemy import Column, ForeignKey, Table

# Association table — no ORM model needed for simple M2M
market_tag = Table(
    "market_tag",
    Base.metadata,
    Column("market_id", ForeignKey("market.id"), primary_key=True),
    Column("tag_id", ForeignKey("tag.id"), primary_key=True),
)


class Market(Base):
    __tablename__ = "market"

    tags: Mapped[list["Tag"]] = relationship(
        secondary=market_tag, back_populates="markets"
    )


class Tag(Base):
    __tablename__ = "tag"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True)

    markets: Mapped[list["Market"]] = relationship(
        secondary=market_tag, back_populates="tags"
    )
```

### Eager Loading in Async Context

Lazy loading raises errors in async. Always load relationships explicitly:

```python
from sqlalchemy.orm import selectinload, joinedload

# selectinload — preferred for collections (one-to-many, many-to-many)
stmt = select(User).options(selectinload(User.markets))

# joinedload — preferred for scalar relationships (many-to-one)
stmt = select(Market).options(joinedload(Market.created_by))

# Nested eager loading
stmt = select(User).options(
    selectinload(User.markets).selectinload(Market.outcomes)
)
```

## Alembic Migrations

### Project Setup

```
alembic/
    env.py
    versions/
        001_create_user_table.py
        002_create_market_table.py
alembic.ini
```

### Async env.py

```python
# alembic/env.py
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app.config import settings
from app.models.base import Base

# Import all models so metadata is populated
import app.models  # noqa: F401

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    connectable = create_async_engine(settings.database_url)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
```

### Migration Commands

```bash
# Auto-generate migration from model changes
uv run alembic revision --autogenerate -m "add market table"

# Apply all pending migrations
uv run alembic upgrade head

# Downgrade one revision
uv run alembic downgrade -1

# Show current revision
uv run alembic current
```

### Migration Conventions

- **File naming**: auto-generated revision IDs are fine. Use descriptive messages: `"add market table"`, `"add index on market slug"`.
- **Always review auto-generated migrations** before applying. Autogenerate does not detect: renamed columns, changes to constraints on existing columns, or data migrations.
- **Data migrations**: write explicit `op.execute()` statements. Never import ORM models in migration files.
- **One logical change per migration**: do not combine unrelated table changes.

## Query Patterns

### Basic Select

```python
from sqlalchemy import select

# Single entity by primary key
market = await session.get(Market, market_id)

# Single entity by condition
stmt = select(Market).where(Market.slug == slug)
market = await session.scalar(stmt)

# Multiple entities
stmt = select(Market).where(Market.status == "active")
result = await session.scalars(stmt)
markets = list(result.all())
```

### Filtering

```python
from sqlalchemy import and_, or_

# Multiple conditions
stmt = select(Market).where(
    and_(
        Market.status == "active",
        Market.end_date > datetime.now(tz=UTC),
    )
)

# OR conditions
stmt = select(Market).where(
    or_(Market.status == "active", Market.status == "pending")
)

# IN clause
stmt = select(Market).where(Market.status.in_(["active", "pending"]))

# LIKE / ILIKE
stmt = select(Market).where(Market.name.ilike(f"%{search_term}%"))
```

### Pagination and Sorting

```python
from sqlalchemy import desc

stmt = (
    select(Market)
    .where(Market.status == "active")
    .order_by(desc(Market.created_at))
    .offset(offset)
    .limit(limit)
)
result = await session.scalars(stmt)
markets = list(result.all())

# Count for pagination metadata
count_stmt = select(func.count()).select_from(Market).where(Market.status == "active")
total = await session.scalar(count_stmt) or 0
```

### Joins

```python
# Implicit join via relationship (with eager loading)
stmt = (
    select(Market)
    .options(joinedload(Market.created_by))
    .where(Market.status == "active")
)

# Explicit join
stmt = (
    select(Market)
    .join(Market.created_by)
    .where(User.email == "admin@example.com")
)
```

### Aggregations

```python
from sqlalchemy import func

# Count
stmt = select(func.count()).select_from(Market)
total = await session.scalar(stmt) or 0

# Group by
stmt = (
    select(Market.status, func.count().label("count"))
    .group_by(Market.status)
)
result = await session.execute(stmt)
status_counts = result.all()  # list of Row(status, count)
```

## Query Optimization

### Avoiding N+1 Queries

The N+1 problem occurs when accessing relationships triggers individual queries per row. Always apply eager loading:

```python
# BAD: N+1 — each market.outcomes triggers a separate query (and fails in async)
stmt = select(Market)
markets = (await session.scalars(stmt)).all()
for m in markets:
    print(m.outcomes)  # raises MissingGreenlet in async

# GOOD: eager load collections
stmt = select(Market).options(selectinload(Market.outcomes))
markets = (await session.scalars(stmt)).all()
for m in markets:
    print(m.outcomes)  # already loaded
```

### Choosing a Loading Strategy

| Strategy | Use Case |
|---|---|
| `selectinload` | Collections (one-to-many, many-to-many). Issues a second SELECT with IN clause. |
| `joinedload` | Scalar relationships (many-to-one). Single JOIN query. |
| `subqueryload` | Large collections where IN clause would be too large. |
| `raiseload` | Explicitly prevent lazy loading. Use in strict async contexts. |

```python
from sqlalchemy.orm import raiseload

# Prevent any lazy loading — forces explicit eager loading everywhere
stmt = select(Market).options(raiseload("*"))
```

### Bulk Operations

```python
from sqlalchemy import update, delete

# Bulk update without loading objects
stmt = (
    update(Market)
    .where(Market.status == "draft")
    .where(Market.end_date < datetime.now(tz=UTC))
    .values(status="expired")
)
await session.execute(stmt)
await session.commit()

# Bulk delete
stmt = delete(Market).where(Market.status == "cancelled")
await session.execute(stmt)
await session.commit()

# Bulk insert
from sqlalchemy.dialects.postgresql import insert

stmt = insert(Market).values(
    [{"name": "M1", "slug": "m1"}, {"name": "M2", "slug": "m2"}]
)
stmt = stmt.on_conflict_do_nothing(index_elements=["slug"])
await session.execute(stmt)
await session.commit()
```

### Selecting Only Needed Columns

```python
# Load only specific columns to reduce data transfer
stmt = select(Market.id, Market.name, Market.status).where(Market.status == "active")
result = await session.execute(stmt)
rows = result.all()  # list of Row(id, name, status)
```

## Testing with SQLAlchemy

### Test Database Setup

```python
# tests/conftest.py
import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.models.base import Base

TEST_DATABASE_URL = "postgresql+asyncpg://test:test@localhost:5432/test_db"


@pytest.fixture(scope="session")
def event_loop():
    """Create a session-scoped event loop for async tests."""
    import asyncio

    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
async def test_engine():
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest.fixture
async def test_session(test_engine):
    """Per-test session with automatic rollback."""
    async_session = async_sessionmaker(
        test_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with async_session() as session:
        async with session.begin():
            yield session
        # Context manager automatically rolls back uncommitted changes
```

### Overriding the FastAPI Dependency

```python
# tests/conftest.py
from app.api.dependencies import get_db_session
from app.main import create_app


@pytest.fixture
async def app(test_session):
    app = create_app()
    app.dependency_overrides[get_db_session] = lambda: test_session
    yield app
    app.dependency_overrides.clear()


@pytest.fixture
async def client(app):
    from httpx import ASGITransport, AsyncClient

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
```

### Repository Tests

```python
# tests/unit/test_market_repository.py
import pytest
from uuid import uuid4

from app.models.market import Market
from app.repositories.market import MarketRepository


class TestMarketRepository:
    @pytest.mark.asyncio
    async def test_create_and_get_by_id(self, test_session) -> None:
        repo = MarketRepository(test_session)
        market = Market(
            name="Test Market",
            slug="test-market",
            description="A test",
            end_date=datetime(2025, 12, 31, tzinfo=UTC),
            created_by_id=uuid4(),
        )

        created = await repo.create(market)
        assert created.id is not None

        found = await repo.get_by_id(created.id)
        assert found is not None
        assert found.name == "Test Market"

    @pytest.mark.asyncio
    async def test_get_by_slug_returns_none_for_missing(
        self, test_session
    ) -> None:
        repo = MarketRepository(test_session)
        result = await repo.get_by_slug("nonexistent")
        assert result is None
```

### Testing Conventions

- Use `session.rollback()` in fixtures to isolate tests -- never let test data persist.
- Create tables once per session (`scope="session"`) for performance.
- Use factories (e.g., `factory_boy` with async support) for complex test data, not raw model construction.
- Test repositories against a real database (integration tests), not mocks.
- See the `tdd-workflow` skill for full testing rules.

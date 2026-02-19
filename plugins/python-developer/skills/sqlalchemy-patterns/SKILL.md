---
name: sqlalchemy-patterns
description: Enforces SQLAlchemy patterns with DDD and Clean Architecture: domain entities, Repository Protocol, Unit of Work, async sessions, Alembic migrations. Activates when working with database models, repositories, queries, or migrations.
allowed-tools: Read, Grep, Glob, Bash(alembic:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*)
---

# SQLAlchemy Patterns (DDD / Clean Architecture)

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

**Architecture & Domain:**
- Domain entities MUST be pure Python dataclasses or Pydantic BaseModel — NEVER inherit from SQLAlchemy `Base`
- Repository interfaces MUST be defined as `Protocol` in the domain layer — infrastructure implements them
- NEVER call `session.commit()`, `session.flush()`, or `session.rollback()` outside the Unit of Work — services use the UoW abstraction
- NEVER import SQLAlchemy in domain or application layers — only infrastructure touches the ORM

**SQLAlchemy ORM:**
- NEVER use synchronous SQLAlchemy sessions — ALWAYS use `AsyncSession` and `async_sessionmaker`
- NEVER use legacy Query API (`session.query(...)`) — ALWAYS use `select()` with `session.execute()` / `session.scalars()`
- NEVER access lazy-loaded relationships in async code — ALWAYS use eager loading (`selectinload`, `joinedload`) or explicit queries
- NEVER use `backref` — ALWAYS use explicit `back_populates` on both sides of a relationship
- ALWAYS define ORM models with `Mapped[T]` type annotations and `mapped_column()` — NEVER use legacy `Column()` syntax in Declarative classes
- ALWAYS use `DeclarativeBase` — NEVER use legacy `declarative_base()` function
- ALWAYS use `await` with `AsyncSession.delete()` — it is async in SQLAlchemy 2.0+
- ALWAYS install `sqlalchemy[asyncio]` — greenlet is no longer bundled since SQLAlchemy 2.1

**Data Integrity:**
- NEVER write raw SQL strings for schema changes — ALWAYS use Alembic migrations
- NEVER use `session.execute(text(...))` for CRUD operations — use the ORM or core constructs
- ALWAYS apply `selectinload()` for collection relationships in async queries
- ALWAYS run the project's typecheck and test commands after any model or migration change

**Note:** `Column()` in `Table()` constructs (e.g., many-to-many association tables) is correct and expected — `mapped_column()` applies only to Declarative class attributes.
</HARD-RULES>

These are the SQLAlchemy patterns for async database access in AppVerk projects, following **Domain-Driven Design** and **Clean Architecture**. All patterns target SQLAlchemy 2.0+ with async extensions.

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│  Presentation Layer (FastAPI endpoints)          │
│  Depends on: Application Layer                   │
├─────────────────────────────────────────────────┤
│  Application Layer (Services / Use Cases)        │
│  Depends on: Domain Layer only                   │
│  Uses: UnitOfWork Protocol, Repository Protocol  │
├─────────────────────────────────────────────────┤
│  Domain Layer (Entities, Value Objects,           │
│    Repository Protocols, UoW Protocol)           │
│  Depends on: NOTHING                             │
├─────────────────────────────────────────────────┤
│  Infrastructure Layer (ORM models, SA repos,     │
│    SA UoW, Data Mappers, Alembic)                │
│  Depends on: Domain Layer + SQLAlchemy           │
└─────────────────────────────────────────────────┘
```

**Dependency direction:** ALWAYS inward. Domain layer has zero external dependencies. SQLAlchemy is confined to infrastructure.

### Directory Layout

```
app/
    domain/
        entities/           # Pure dataclasses / Pydantic models
        value_objects/       # Immutable value types
        repositories/        # Protocol interfaces
        unit_of_work.py      # UoW Protocol
    services/                # Application layer (use cases)
    infrastructure/
        persistence/
            models/          # SQLAlchemy ORM models (*ORM)
            mappers/         # Domain ↔ ORM conversion
            repositories/    # SQLAlchemy Repository implementations
            unit_of_work.py  # SQLAlchemy UoW implementation
            database.py      # Engine, session factory
    api/                     # Presentation layer (FastAPI)
```

## Domain Layer — Entities

Domain entities are **pure Python** with no ORM dependencies. Use `dataclass` or `pydantic.BaseModel`.

```python
# app/domain/entities/market.py
from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID

from app.domain.value_objects.market_status import MarketStatus


@dataclass
class Market:
    id: UUID
    name: str
    description: str
    slug: str
    status: MarketStatus
    end_date: datetime
    created_by_id: UUID
    created_at: datetime | None = None
    updated_at: datetime | None = None
    outcomes: list["Outcome"] = field(default_factory=list)
```

### Conventions

- **Identity**: every entity has an `id: UUID` field.
- **Timestamps**: `created_at` and `updated_at` are optional (populated by infrastructure).
- **Relationships**: plain Python lists — no SQLAlchemy `relationship()` here.
- **Behavior**: domain logic lives as methods on the entity.

## Domain Layer — Value Objects

Value Objects have **no identity** and are **immutable**. Use Pydantic `BaseModel` with `frozen=True` or `@dataclass(frozen=True)`.

```python
# app/domain/value_objects/money.py
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class Money(BaseModel):
    model_config = ConfigDict(frozen=True)

    amount: Decimal
    currency: str = "PLN"
```

```python
# app/domain/value_objects/market_status.py
from enum import StrEnum


class MarketStatus(StrEnum):
    DRAFT = "draft"
    ACTIVE = "active"
    CLOSED = "closed"
    EXPIRED = "expired"
```

## Domain Layer — Repository Protocol

Repository interfaces live in the domain layer. They define **what** operations are available, not **how** they are implemented.

```python
# app/domain/repositories/market.py
from typing import Protocol
from uuid import UUID

from app.domain.entities.market import Market


class MarketRepository(Protocol):
    async def get_by_id(self, entity_id: UUID) -> Market | None: ...
    async def get_by_slug(self, slug: str) -> Market | None: ...
    async def save(self, entity: Market) -> Market: ...
    async def save_many(self, entities: list[Market]) -> list[Market]: ...
    async def delete(self, entity: Market) -> None: ...
    async def get_all(
        self, *, offset: int = 0, limit: int = 100
    ) -> list[Market]: ...
```

### Conventions

- Use `Protocol` (not `ABC`) — structural typing, no inheritance required.
- Method names: `save` (create or update), `get_by_*`, `delete`, `get_all`.
- Return domain entities, never ORM models.
- No SQLAlchemy imports in this file.

## Domain Layer — Unit of Work Protocol

The Unit of Work coordinates transactions across repositories. The protocol lives in the domain layer.

```python
# app/domain/unit_of_work.py
from typing import Protocol

from app.domain.repositories.market import MarketRepository
from app.domain.repositories.user import UserRepository


class UnitOfWork(Protocol):
    markets: MarketRepository
    users: UserRepository

    async def __aenter__(self) -> "UnitOfWork": ...
    async def __aexit__(self, *args: object) -> None: ...
    async def commit(self) -> None: ...
    async def rollback(self) -> None: ...
```

## Infrastructure Layer — ORM Models

ORM models live in infrastructure and are suffixed with `ORM` to distinguish from domain entities.

### Base Model

```python
# app/infrastructure/persistence/models/base.py
from sqlalchemy import MetaData, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

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

### Entity ORM Model

```python
# app/infrastructure/persistence/models/market.py
import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.infrastructure.persistence.models.base import Base


class MarketORM(Base):
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

    created_by: Mapped["UserORM"] = relationship(back_populates="markets")
    outcomes: Mapped[list["OutcomeORM"]] = relationship(
        back_populates="market", cascade="all, delete-orphan"
    )
```

### ORM Model Conventions

- **Suffix**: `MarketORM`, `UserORM` — never `Market` (that's the domain entity).
- **Primary keys**: `Mapped[uuid.UUID]` with `default=uuid.uuid4`.
- **Timestamps**: use `server_default=func.now()` so the DB generates them.
- **Nullable columns**: use `Mapped[str | None]`. Non-nullable is `Mapped[str]`.
- **String lengths**: always specify explicit lengths via `String(N)` for indexed/constrained columns.
- **Table names**: singular, lowercase (`market`, `user`, `trade`).

### Relationships

#### One-to-Many

```python
class UserORM(Base):
    __tablename__ = "user"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True)

    markets: Mapped[list["MarketORM"]] = relationship(
        back_populates="created_by", cascade="all, delete-orphan"
    )


class MarketORM(Base):
    __tablename__ = "market"

    created_by_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("user.id"))
    created_by: Mapped["UserORM"] = relationship(back_populates="markets")
```

#### Many-to-Many

```python
from sqlalchemy import Column, ForeignKey, Table

# Association table — Column() in Table() constructs is correct
market_tag = Table(
    "market_tag",
    Base.metadata,
    Column("market_id", ForeignKey("market.id"), primary_key=True),
    Column("tag_id", ForeignKey("tag.id"), primary_key=True),
)


class MarketORM(Base):
    __tablename__ = "market"

    tags: Mapped[list["TagORM"]] = relationship(
        secondary=market_tag, back_populates="markets"
    )


class TagORM(Base):
    __tablename__ = "tag"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100), unique=True)

    markets: Mapped[list["MarketORM"]] = relationship(
        secondary=market_tag, back_populates="tags"
    )
```

### Eager Loading in Async Context

Lazy loading raises `MissingGreenlet` in async. Always load relationships explicitly:

```python
from sqlalchemy.orm import joinedload, raiseload, selectinload

# selectinload — preferred for collections (one-to-many, many-to-many)
stmt = select(UserORM).options(selectinload(UserORM.markets))

# joinedload — preferred for scalar relationships (many-to-one)
stmt = select(MarketORM).options(joinedload(MarketORM.created_by))

# Nested eager loading
stmt = select(UserORM).options(
    selectinload(UserORM.markets).selectinload(MarketORM.outcomes)
)

# raiseload("*") — enforce explicit loading (recommended default for async)
stmt = (
    select(MarketORM)
    .options(selectinload(MarketORM.outcomes), raiseload("*"))
)
```

### Loading Strategy Reference

| Strategy | Use Case |
|---|---|
| `selectinload` | Collections (one-to-many, many-to-many). Second SELECT with IN clause. |
| `joinedload` | Scalar relationships (many-to-one). Single JOIN query. |
| `subqueryload` | Large collections where IN clause would be too large. |
| `raiseload` | Prevent lazy loading. Recommended default in async repositories. |
| `WriteOnlyMapped` | Very large collections that should never be fully loaded. |

#### WriteOnlyMapped for Large Collections

For collections with thousands of items, use `WriteOnlyMapped` to prevent accidental full loads:

```python
from sqlalchemy.orm import WriteOnlyMapped

class UserORM(Base):
    __tablename__ = "user"

    # Large collection — never load all at once
    audit_logs: WriteOnlyMapped[list["AuditLogORM"]] = relationship()
```

Query write-only collections explicitly:

```python
# Read with explicit query
stmt = user.audit_logs.select().order_by(AuditLogORM.created_at.desc()).limit(50)
logs = (await session.scalars(stmt)).all()

# Add to write-only collection
user.audit_logs.add(AuditLogORM(action="login"))
```

## Infrastructure Layer — Data Mappers

Data mappers convert between domain entities and ORM models. They live in infrastructure.

```python
# app/infrastructure/persistence/mappers/market.py
from app.domain.entities.market import Market
from app.domain.value_objects.market_status import MarketStatus
from app.infrastructure.persistence.models.market import MarketORM


class MarketMapper:
    @staticmethod
    def to_domain(orm: MarketORM) -> Market:
        return Market(
            id=orm.id,
            name=orm.name,
            description=orm.description,
            slug=orm.slug,
            status=MarketStatus(orm.status),
            end_date=orm.end_date,
            created_by_id=orm.created_by_id,
            created_at=orm.created_at,
            updated_at=orm.updated_at,
        )

    @staticmethod
    def to_orm(entity: Market) -> MarketORM:
        return MarketORM(
            id=entity.id,
            name=entity.name,
            description=entity.description,
            slug=entity.slug,
            status=entity.status.value,
            end_date=entity.end_date,
            created_by_id=entity.created_by_id,
        )

    @staticmethod
    def update_orm(orm: MarketORM, entity: Market) -> MarketORM:
        orm.name = entity.name
        orm.description = entity.description
        orm.slug = entity.slug
        orm.status = entity.status.value
        orm.end_date = entity.end_date
        return orm
```

### Mapper Conventions

- One mapper class per aggregate root.
- `to_domain()`: ORM model → domain entity. Maps ORM string fields to Value Objects (e.g., `MarketStatus(orm.status)`).
- `to_orm()`: domain entity → new ORM model (for inserts).
- `update_orm()`: apply domain entity changes to an existing ORM model (for updates).
- Relationships: map in dedicated mapper methods if the aggregate includes child entities.

## Infrastructure Layer — Repository Implementation

Repositories in infrastructure implement the domain Protocol using SQLAlchemy.

```python
# app/infrastructure/persistence/repositories/market.py
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import raiseload, selectinload

from app.domain.entities.market import Market
from app.infrastructure.persistence.mappers.market import MarketMapper
from app.infrastructure.persistence.models.market import MarketORM


class SqlAlchemyMarketRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_id(self, entity_id: UUID) -> Market | None:
        orm = await self.session.get(MarketORM, entity_id)
        return MarketMapper.to_domain(orm) if orm else None

    async def get_by_slug(self, slug: str) -> Market | None:
        stmt = select(MarketORM).where(MarketORM.slug == slug)
        orm = await self.session.scalar(stmt)
        return MarketMapper.to_domain(orm) if orm else None

    async def save(self, entity: Market) -> Market:
        existing = await self.session.get(MarketORM, entity.id)
        if existing:
            orm = MarketMapper.update_orm(existing, entity)
        else:
            orm = MarketMapper.to_orm(entity)
            self.session.add(orm)
        await self.session.flush()
        return MarketMapper.to_domain(orm)

    async def save_many(self, entities: list[Market]) -> list[Market]:
        result = []
        for entity in entities:
            result.append(await self.save(entity))
        return result

    async def delete(self, entity: Market) -> None:
        orm = await self.session.get(MarketORM, entity.id)
        if orm:
            await self.session.delete(orm)
            await self.session.flush()

    async def get_all(
        self, *, offset: int = 0, limit: int = 100
    ) -> list[Market]:
        stmt = (
            select(MarketORM)
            .options(raiseload("*"))
            .offset(offset)
            .limit(limit)
        )
        result = await self.session.scalars(stmt)
        return [MarketMapper.to_domain(orm) for orm in result.all()]

    async def get_with_outcomes(self, entity_id: UUID) -> Market | None:
        stmt = (
            select(MarketORM)
            .options(selectinload(MarketORM.outcomes), raiseload("*"))
            .where(MarketORM.id == entity_id)
        )
        orm = await self.session.scalar(stmt)
        if orm is None:
            return None
        market = MarketMapper.to_domain(orm)
        market.outcomes = [
            OutcomeMapper.to_domain(o) for o in orm.outcomes
        ]
        return market

    async def count_by_status(self, status: str) -> int:
        stmt = (
            select(func.count())
            .select_from(MarketORM)
            .where(MarketORM.status == status)
        )
        result = await self.session.scalar(stmt)
        return result or 0
```

### Repository Implementation Conventions

- Class name: `SqlAlchemy<Entity>Repository`.
- All methods return **domain entities**, never ORM models.
- Use `raiseload("*")` by default, add explicit `selectinload`/`joinedload` only when needed.
- Use `await self.session.delete(orm)` — it is async in SQLAlchemy 2.0+.
- Use `flush()` (not `commit()`) — the Unit of Work owns the transaction.
- Use `get_one()` when the entity must exist (raises `NoResultFound`):

```python
from sqlalchemy import select

# Strict lookup — raises if not found
orm = await self.session.get_one(MarketORM, entity_id)
```

## Infrastructure Layer — Unit of Work Implementation

The Unit of Work wraps `AsyncSession` and exposes repository instances.

```python
# app/infrastructure/persistence/unit_of_work.py
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.infrastructure.persistence.repositories.market import (
    SqlAlchemyMarketRepository,
)
from app.infrastructure.persistence.repositories.user import (
    SqlAlchemyUserRepository,
)


class SqlAlchemyUnitOfWork:
    markets: SqlAlchemyMarketRepository
    users: SqlAlchemyUserRepository

    def __init__(
        self, session_factory: async_sessionmaker[AsyncSession]
    ) -> None:
        self.session_factory = session_factory

    async def __aenter__(self) -> "SqlAlchemyUnitOfWork":
        self.session = self.session_factory()
        self.markets = SqlAlchemyMarketRepository(self.session)
        self.users = SqlAlchemyUserRepository(self.session)
        return self

    async def __aexit__(self, *args: object) -> None:
        await self.session.rollback()
        await self.session.close()

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()
```

### Usage in Services

```python
# app/services/market.py
from uuid import uuid4

from app.domain.entities.market import Market
from app.domain.unit_of_work import UnitOfWork
from app.domain.value_objects.market_status import MarketStatus
from app.schemas.market import MarketCreate


class MarketService:
    def __init__(self, uow: UnitOfWork) -> None:
        self.uow = uow

    async def create_market(
        self, data: MarketCreate, user_id: UUID
    ) -> Market:
        market = Market(
            id=uuid4(),
            name=data.name,
            description=data.description,
            slug=generate_slug(data.name),
            status=MarketStatus.DRAFT,
            end_date=data.end_date,
            created_by_id=user_id,
        )
        async with self.uow:
            created = await self.uow.markets.save(market)
            await self.uow.commit()
            return created

    async def close_market(self, market_id: UUID) -> Market:
        async with self.uow:
            market = await self.uow.markets.get_by_id(market_id)
            if market is None:
                raise EntityNotFoundError(f"Market {market_id} not found")
            market.status = MarketStatus.CLOSED
            updated = await self.uow.markets.save(market)
            await self.uow.commit()
            return updated
```

**Key points:**
- Service depends on `UnitOfWork` Protocol, not `AsyncSession`.
- `async with self.uow` opens session + creates repositories.
- `await self.uow.commit()` commits the transaction.
- If no `commit()` is called, `__aexit__` rolls back automatically.

## Async Engine & Session Factory

```python
# app/infrastructure/persistence/database.py
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import settings

# NOTE: SQLAlchemy 2.1 defaults to psycopg (v3) for PostgreSQL.
# Install: uv add "sqlalchemy[asyncio]" asyncpg
# URL format: postgresql+asyncpg://user:pass@host/db
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

### Key Settings

- **`expire_on_commit=False`**: prevents lazy-load errors when accessing attributes after commit in async context.
- **`pool_pre_ping=True`**: detects stale connections before use.
- **Never create engines per-request**. Use a single engine per application.
- **`sqlalchemy[asyncio]`**: required since SA 2.1 — greenlet is no longer auto-installed.

## FastAPI Integration

### UoW Dependency

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

### Using in Endpoints

```python
# app/api/routes/markets.py
from app.api.dependencies import UoW
from app.services.market import MarketService


@router.post("/", response_model=MarketResponse, status_code=201)
async def create_market(
    body: MarketCreate,
    uow: UoW,
    user: CurrentUser,
) -> MarketResponse:
    service = MarketService(uow)
    market = await service.create_market(body, user_id=user.id)
    return MarketResponse.model_validate(market, from_attributes=True)
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

**Important:** Alembic works with ORM models (`*ORM`), not domain entities. Import ORM models in `env.py`.

### Async env.py

```python
# alembic/env.py
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app.config import settings
from app.infrastructure.persistence.models.base import Base

# Import all ORM models so metadata is populated
import app.infrastructure.persistence.models  # noqa: F401

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
# Auto-generate migration from ORM model changes
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

All queries live **inside repository implementations**, never in services or endpoints.

### Basic Select

```python
# Inside a repository method
from sqlalchemy import select

# Single entity by primary key (returns ORM, mapper converts to domain)
orm = await self.session.get(MarketORM, market_id)

# Strict lookup — raises NoResultFound if not found
orm = await self.session.get_one(MarketORM, market_id)

# Single entity by condition
stmt = select(MarketORM).where(MarketORM.slug == slug)
orm = await self.session.scalar(stmt)

# Multiple entities
stmt = select(MarketORM).where(MarketORM.status == "active")
result = await self.session.scalars(stmt)
orms = list(result.all())
```

### Filtering

```python
from sqlalchemy import and_, or_

# Multiple conditions
stmt = select(MarketORM).where(
    and_(
        MarketORM.status == "active",
        MarketORM.end_date > datetime.now(tz=UTC),
    )
)

# OR conditions
stmt = select(MarketORM).where(
    or_(MarketORM.status == "active", MarketORM.status == "pending")
)

# IN clause
stmt = select(MarketORM).where(MarketORM.status.in_(["active", "pending"]))

# LIKE / ILIKE
stmt = select(MarketORM).where(MarketORM.name.ilike(f"%{search_term}%"))
```

### Pagination and Sorting

```python
from sqlalchemy import desc, func

stmt = (
    select(MarketORM)
    .options(raiseload("*"))
    .where(MarketORM.status == "active")
    .order_by(desc(MarketORM.created_at))
    .offset(offset)
    .limit(limit)
)
result = await self.session.scalars(stmt)
orms = list(result.all())

# Count for pagination metadata
count_stmt = (
    select(func.count())
    .select_from(MarketORM)
    .where(MarketORM.status == "active")
)
total = await self.session.scalar(count_stmt) or 0
```

### Joins

```python
# Implicit join via relationship (with eager loading)
stmt = (
    select(MarketORM)
    .options(joinedload(MarketORM.created_by))
    .where(MarketORM.status == "active")
)

# Explicit join
stmt = (
    select(MarketORM)
    .join(MarketORM.created_by)
    .where(UserORM.email == "admin@example.com")
)
```

### Aggregations

```python
from sqlalchemy import func

# Count
stmt = select(func.count()).select_from(MarketORM)
total = await self.session.scalar(stmt) or 0

# Group by
stmt = (
    select(MarketORM.status, func.count().label("count"))
    .group_by(MarketORM.status)
)
result = await self.session.execute(stmt)
status_counts = result.all()  # list of Row(status, count)
```

### Streaming Large Result Sets

For queries returning thousands of rows, use `stream()` to avoid loading everything into memory:

```python
# Stream results instead of loading all at once
stmt = select(MarketORM).where(MarketORM.status == "active")
async with self.session.stream_scalars(stmt) as stream:
    async for orm in stream:
        yield MarketMapper.to_domain(orm)
```

### Bulk Operations

Bulk operations bypass the ORM identity map for performance. Use inside repositories with UoW coordination.

```python
from sqlalchemy import delete, update

# Bulk update without loading objects
stmt = (
    update(MarketORM)
    .where(MarketORM.status == "draft")
    .where(MarketORM.end_date < datetime.now(tz=UTC))
    .values(status="expired")
)
await self.session.execute(stmt)

# Bulk delete
stmt = delete(MarketORM).where(MarketORM.status == "cancelled")
await self.session.execute(stmt)

# Bulk insert with conflict handling (PostgreSQL)
from sqlalchemy.dialects.postgresql import insert

stmt = insert(MarketORM).values(
    [{"name": "M1", "slug": "m1"}, {"name": "M2", "slug": "m2"}]
)
stmt = stmt.on_conflict_do_nothing(index_elements=["slug"])
await self.session.execute(stmt)
```

### Selecting Only Needed Columns

```python
# Load only specific columns to reduce data transfer
stmt = (
    select(MarketORM.id, MarketORM.name, MarketORM.status)
    .where(MarketORM.status == "active")
)
result = await self.session.execute(stmt)
rows = result.all()  # list of Row(id, name, status)
```

## Avoiding N+1 Queries

The N+1 problem occurs when accessing relationships triggers individual queries per row.

```python
# BAD: N+1 — each market.outcomes triggers a separate query (and fails in async)
stmt = select(MarketORM)
orms = (await self.session.scalars(stmt)).all()
for orm in orms:
    print(orm.outcomes)  # raises MissingGreenlet in async

# GOOD: eager load collections
stmt = select(MarketORM).options(selectinload(MarketORM.outcomes))
orms = (await self.session.scalars(stmt)).all()
for orm in orms:
    print(orm.outcomes)  # already loaded

# BEST: raiseload("*") as default, explicit load only what you need
stmt = (
    select(MarketORM)
    .options(selectinload(MarketORM.outcomes), raiseload("*"))
)
```

## Testing

### pytest-asyncio Configuration

**Modern setup (pytest-asyncio 1.x+)**. The `event_loop` fixture is removed — use `loop_scope` instead.

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "session"
```

### Test Database Setup

```python
# tests/conftest.py
import pytest
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.infrastructure.persistence.models.base import Base

TEST_DATABASE_URL = "postgresql+asyncpg://test:test@localhost:5432/test_db"


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
    session_factory = async_sessionmaker(
        test_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        async with session.begin():
            yield session
        # Exiting begin() without commit triggers automatic rollback
```

### Three-Tier Testing Strategy

#### 1. Domain Tests (pure unit tests, no DB)

```python
# tests/unit/domain/test_market.py
from uuid import uuid4

from app.domain.entities.market import Market
from app.domain.value_objects.market_status import MarketStatus


class TestMarket:
    def test_create_market_with_draft_status(self) -> None:
        market = Market(
            id=uuid4(),
            name="Test Market",
            description="A test",
            slug="test-market",
            status=MarketStatus.DRAFT,
            end_date=datetime(2025, 12, 31, tzinfo=UTC),
            created_by_id=uuid4(),
        )
        assert market.status == MarketStatus.DRAFT
        assert market.name == "Test Market"
```

#### 2. Repository Tests (integration, real DB)

```python
# tests/integration/test_market_repository.py
from uuid import uuid4

from app.domain.entities.market import Market
from app.domain.value_objects.market_status import MarketStatus
from app.infrastructure.persistence.repositories.market import (
    SqlAlchemyMarketRepository,
)


class TestSqlAlchemyMarketRepository:
    async def test_save_and_get_by_id(self, test_session) -> None:
        repo = SqlAlchemyMarketRepository(test_session)
        market = Market(
            id=uuid4(),
            name="Test Market",
            description="A test",
            slug="test-market",
            status=MarketStatus.DRAFT,
            end_date=datetime(2025, 12, 31, tzinfo=UTC),
            created_by_id=uuid4(),
        )

        created = await repo.save(market)
        assert created.id == market.id

        found = await repo.get_by_id(created.id)
        assert found is not None
        assert found.name == "Test Market"
        assert found.status == MarketStatus.DRAFT

    async def test_get_by_slug_returns_none_for_missing(
        self, test_session
    ) -> None:
        repo = SqlAlchemyMarketRepository(test_session)
        result = await repo.get_by_slug("nonexistent")
        assert result is None
```

#### 3. Service Tests (unit tests with Fake UoW)

```python
# tests/fakes.py
from uuid import UUID

from app.domain.entities.market import Market


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

    async def get_by_slug(self, slug: str) -> Market | None:
        for market in self.markets.values():
            if market.slug == slug:
                return market
        return None

    async def save_many(self, entities: list[Market]) -> list[Market]:
        for entity in entities:
            self.markets[entity.id] = entity
        return entities

    async def get_all(
        self, *, offset: int = 0, limit: int = 100
    ) -> list[Market]:
        all_markets = list(self.markets.values())
        return all_markets[offset : offset + limit]


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
```

```python
# tests/unit/services/test_market_service.py
from app.services.market import MarketService
from tests.fakes import FakeUnitOfWork


class TestMarketService:
    async def test_create_market(self) -> None:
        uow = FakeUnitOfWork()
        service = MarketService(uow)

        market = await service.create_market(
            data=MarketCreate(
                name="Test",
                description="A test",
                end_date=datetime(2025, 12, 31, tzinfo=UTC),
            ),
            user_id=uuid4(),
        )

        assert market.name == "Test"
        assert uow.committed is True
        assert market.id in uow.markets.markets
```

### Overriding the FastAPI Dependency

```python
# tests/conftest.py
from app.api.dependencies import get_unit_of_work
from app.main import create_app
from tests.fakes import FakeUnitOfWork


@pytest.fixture
def fake_uow():
    return FakeUnitOfWork()


@pytest.fixture
async def app(fake_uow):
    app = create_app()
    app.dependency_overrides[get_unit_of_work] = lambda: fake_uow
    yield app
    app.dependency_overrides.clear()


@pytest.fixture
async def client(app):
    from httpx import ASGITransport, AsyncClient

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
```

### Testing Conventions

- **Domain tests**: pure Python, no DB, no mocks. Test entity behavior and value object invariants.
- **Repository tests**: integration tests against real database. Use `test_session` fixture with automatic rollback.
- **Service tests**: unit tests with `FakeUnitOfWork` and `FakeRepository`. Verify business logic without DB.
- **Endpoint tests**: use `FakeUnitOfWork` via `dependency_overrides`. Test HTTP interface.
- Create tables once per session (`scope="session"`) for performance.
- Use factories for complex test data, not raw model construction.
- See the `tdd-workflow` skill for full testing rules.

# SQLAlchemy Patterns — Strict DDD Rewrite Design

**Date:** 2026-02-19
**Status:** Draft
**Skill:** python-developer/skills/sqlalchemy-patterns
**Current version:** part of python-developer 2.0.0

## Context

The `sqlalchemy-patterns` skill guides SQLAlchemy code generation for AppVerk projects. The current skill was written with an infrastructure-centric approach where ORM models serve as domain entities. AppVerk projects follow DDD and Clean Architecture — the skill must reflect this.

### Audit Findings

**CRITICAL — DDD / Clean Architecture violations:**
1. Domain entities inherit from `DeclarativeBase` (ORM coupling in domain layer)
2. No abstract Repository interface (Protocol/ABC) — no dependency inversion
3. No Unit of Work pattern — `session.commit()` leaks into service layer
4. Service layer depends on `AsyncSession` (infrastructure in application layer)
5. `event_loop` fixture removed in pytest-asyncio 1.0+ — test setup is broken

**IMPORTANT — SQLAlchemy 2.1 incompatibilities:**
6. `greenlet` no longer auto-installed (need `sqlalchemy[asyncio]` extra)
7. PostgreSQL default driver changed from psycopg2 to psycopg (v3)
8. HARD-RULES wording misleading about `Column()` in `Table()` constructs
9. `AsyncSession.delete()` must be awaited (current code creates unawaited coroutine)
10. Missing new 2.1 APIs: `get_one()`, `delete_all()`, `WriteOnlyMapped`

**MODERATE — missing DDD patterns:**
11. No Value Objects guidance (SQLAlchemy composites)
12. No Aggregate Root boundaries
13. No Domain Events pattern
14. No `raiseload("*")` / `WriteOnlyMapped` as default async strategy

**MINOR:**
15. HARD-RULES reference hardcoded `make typecheck` / `make test` commands
16. No `stream()` / `stream_scalars()` for large result sets
17. `onupdate=func.now()` is ORM-side only, not DB-enforced

### Mapping Strategy Decision

Imperative mapping (`registry.map_imperatively()`) was considered but rejected:
- SQLAlchemy docs: "lesser-used form", "does not offer modern features such as PEP 484 support"
- Mike Bayer (SQLAlchemy creator): "I don't recommend this pattern overall"
- No IDE type hint support for mapped attributes

**Chosen approach: Separate ORM + Data Mapper**
- Domain models: pure Python `dataclass` or `pydantic.BaseModel`
- ORM models: Declarative with `Mapped[T]` in infrastructure layer
- Data Mapper functions convert between them
- Full PEP 484 support on both sides

## Design

### Skill Structure

The rewritten skill is organized by Clean Architecture layers, not by SQLAlchemy features.

```
1.  HARD-RULES
2.  Architecture Overview (layer diagram, dependency rules)
3.  Domain Layer — Entities & Value Objects
4.  Domain Layer — Repository Protocol
5.  Domain Layer — Unit of Work Protocol
6.  Infrastructure Layer — ORM Models
7.  Infrastructure Layer — Data Mappers
8.  Infrastructure Layer — Repository Implementation
9.  Infrastructure Layer — Unit of Work Implementation
10. Async Engine & Session Factory
11. FastAPI Integration (dependency injection)
12. Alembic Migrations
13. Query Patterns (inside repositories)
14. Testing
```

### HARD-RULES (Updated)

Rules to ADD:
- Domain entities MUST be pure Python dataclasses or Pydantic BaseModel — NEVER inherit from SQLAlchemy Base
- Repository interfaces MUST be defined as Protocol in the domain layer — infrastructure implements them
- NEVER call `session.commit()` or `session.flush()` outside Unit of Work — services use UoW abstraction
- ALWAYS install `sqlalchemy[asyncio]` — greenlet is no longer auto-installed since SA 2.1
- ALWAYS use `await` with `AsyncSession.delete()` — it is async in SA 2.0+

Rules to FIX:
- "ALWAYS run `make typecheck` and `make test`" → "ALWAYS run the project's typecheck and test commands after any model or migration change"

Rules to KEEP (unchanged):
- NEVER use synchronous sessions
- NEVER use legacy Query API
- NEVER access lazy-loaded relationships in async
- NEVER use `backref`
- NEVER write raw SQL for schema changes
- NEVER use `session.execute(text(...))` for CRUD
- ALWAYS use `Mapped[T]` + `mapped_column()` for ORM models
- ALWAYS use `DeclarativeBase`
- ALWAYS use `selectinload()` for collections in async

Rules to CLARIFY:
- "`mapped_column()` applies to Declarative class attributes. `Column()` in `Table()` constructs (e.g., M2M association tables) is correct and expected."

### Architecture Overview

```
┌─────────────────────────────────────────────┐
│  Presentation Layer (FastAPI endpoints)      │
│  Depends on: Application Layer               │
├─────────────────────────────────────────────┤
│  Application Layer (Services / Use Cases)    │
│  Depends on: Domain Layer                    │
│  Uses: UnitOfWork Protocol, Repository       │
│         Protocol (both from domain)          │
├─────────────────────────────────────────────┤
│  Domain Layer (Entities, Value Objects,       │
│    Repository Protocol, UoW Protocol)        │
│  Depends on: NOTHING                         │
├─────────────────────────────────────────────┤
│  Infrastructure Layer (ORM models, SA repos, │
│    SA UoW, Data Mappers, Alembic)            │
│  Depends on: Domain Layer + SQLAlchemy       │
└─────────────────────────────────────────────┘

Dependency direction: ALWAYS inward (top → bottom in diagram)
Domain layer has ZERO external dependencies.
```

### Domain Layer — Entities & Value Objects

**Entities** (identity-based, mutable):
```python
# app/domain/entities/market.py
from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID

from app.domain.value_objects import MarketStatus


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

**Value Objects** (identity-less, immutable):
```python
# Using Pydantic for validation + immutability
from pydantic import BaseModel, ConfigDict


class Money(BaseModel):
    model_config = ConfigDict(frozen=True)

    amount: Decimal
    currency: str = "PLN"


# Using enum for simple value types
class MarketStatus(str, Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    CLOSED = "closed"
    EXPIRED = "expired"
```

### Domain Layer — Repository Protocol

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
    async def get_all(self, *, offset: int = 0, limit: int = 100) -> list[Market]: ...
```

### Domain Layer — Unit of Work Protocol

```python
# app/domain/unit_of_work.py
from typing import Protocol

from app.domain.repositories.market import MarketRepository


class UnitOfWork(Protocol):
    markets: MarketRepository

    async def __aenter__(self) -> "UnitOfWork": ...
    async def __aexit__(self, *args: object) -> None: ...
    async def commit(self) -> None: ...
    async def rollback(self) -> None: ...
```

### Infrastructure Layer — ORM Models

Standard Declarative models, clearly scoped to infrastructure:

```python
# app/infrastructure/persistence/models/market.py
class MarketORM(Base):
    __tablename__ = "market"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200))
    # ... same column definitions as current skill
    # Relationships use back_populates, eager loading strategies
```

### Infrastructure Layer — Data Mappers

```python
# app/infrastructure/persistence/mappers/market.py
class MarketMapper:
    @staticmethod
    def to_domain(orm: MarketORM) -> Market:
        return Market(
            id=orm.id,
            name=orm.name,
            ...
        )

    @staticmethod
    def to_orm(entity: Market) -> MarketORM:
        return MarketORM(
            id=entity.id,
            name=entity.name,
            ...
        )

    @staticmethod
    def update_orm(orm: MarketORM, entity: Market) -> MarketORM:
        orm.name = entity.name
        # ... update fields
        return orm
```

### Infrastructure Layer — Repository Implementation

```python
# app/infrastructure/persistence/repositories/market.py
class SqlAlchemyMarketRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_id(self, entity_id: UUID) -> Market | None:
        orm = await self.session.get(MarketORM, entity_id)
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

    async def delete(self, entity: Market) -> None:
        orm = await self.session.get(MarketORM, entity.id)
        if orm:
            await self.session.delete(orm)
            await self.session.flush()
```

### Infrastructure Layer — Unit of Work Implementation

```python
# app/infrastructure/persistence/unit_of_work.py
class SqlAlchemyUnitOfWork:
    def __init__(self, session_factory: async_sessionmaker[AsyncSession]) -> None:
        self.session_factory = session_factory

    async def __aenter__(self) -> "SqlAlchemyUnitOfWork":
        self.session = self.session_factory()
        self.markets = SqlAlchemyMarketRepository(self.session)
        return self

    async def __aexit__(self, *args: object) -> None:
        await self.session.rollback()
        await self.session.close()

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()
```

### Application Layer — Service Example

```python
# app/services/market.py
class MarketService:
    def __init__(self, uow: UnitOfWork) -> None:
        self.uow = uow

    async def create_market(self, data: MarketCreate, user_id: UUID) -> Market:
        market = Market(
            id=uuid4(),
            name=data.name,
            slug=generate_slug(data.name),
            ...
        )
        async with self.uow:
            created = await self.uow.markets.save(market)
            await self.uow.commit()
            return created
```

### Testing Strategy

**Domain layer** — pure unit tests, no DB, no mocks:
```python
def test_market_status_transition():
    market = Market(id=uuid4(), name="Test", status=MarketStatus.DRAFT, ...)
    market.activate()
    assert market.status == MarketStatus.ACTIVE
```

**Repository layer** — integration tests with real DB:
```python
# Modern pytest-asyncio config (pyproject.toml):
# [tool.pytest.ini_options]
# asyncio_mode = "auto"
# asyncio_default_fixture_loop_scope = "session"

@pytest.fixture(scope="session")
async def test_engine():
    engine = create_async_engine(TEST_DATABASE_URL)
    # ... create tables
    yield engine
    # ... drop tables

@pytest.fixture
async def test_session(test_engine):
    async_session = async_sessionmaker(test_engine, ...)
    async with async_session() as session:
        async with session.begin():
            yield session
```

**Service layer** — unit tests with Fake repositories:
```python
class FakeMarketRepository:
    def __init__(self):
        self.markets: dict[UUID, Market] = {}

    async def save(self, entity: Market) -> Market:
        self.markets[entity.id] = entity
        return entity
```

### What Gets Removed from Current Skill

1. Service layer with `AsyncSession` injection (replaced by UoW)
2. "Repository owns flush, service owns commit" pattern (replaced by UoW)
3. `event_loop` fixture (replaced by modern pytest-asyncio config)
4. Hardcoded `make typecheck` / `make test` in HARD-RULES

### What Gets Added (Not in Current Skill)

1. Architecture overview with layer diagram
2. Domain entities as dataclasses / Pydantic BaseModel
3. Value Objects (Pydantic frozen models, enums)
4. Repository Protocol in domain layer
5. Unit of Work Protocol + SqlAlchemy implementation
6. Data Mapper layer (to_domain / to_orm / update_orm)
7. `raiseload("*")` as default loading strategy
8. `WriteOnlyMapped` for large collections
9. `get_one()` for strict lookups
10. `stream()` / `stream_scalars()` for large result sets
11. `sqlalchemy[asyncio]` installation note
12. Modern pytest-asyncio config (no event_loop fixture)
13. Three-tier testing (domain / repository / service with fakes)

### What Stays (Updated)

1. ORM model definitions → moved to Infrastructure section, renamed to `*ORM`
2. Naming conventions for constraints/indexes
3. Relationship patterns (back_populates, eager loading)
4. Alembic setup and conventions
5. Query patterns → moved inside repository examples
6. Bulk operations
7. Loading strategy table (selectinload, joinedload, subqueryload, raiseload)

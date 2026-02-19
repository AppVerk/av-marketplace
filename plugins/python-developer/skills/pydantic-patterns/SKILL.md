---
name: pydantic-patterns
description: Enforces Pydantic patterns with DDD and Clean Architecture: Value Objects, request/response schemas, from_domain() mapping, TypeAdapter, settings management. Activates when working with data models, validation, or configuration.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*)
---

# Pydantic Patterns (DDD / Clean Architecture)

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

**Architecture & Layers:**
- NEVER use `BaseModel` for domain entities — ALWAYS use `dataclass` for mutable entities; `BaseModel(frozen=True)` is only for Value Objects that need validation
- NEVER return domain entities directly from API endpoints — ALWAYS map through response schemas with `from_domain()` classmethod
- NEVER expose ORM models as API responses — ALWAYS use dedicated Pydantic schemas in the presentation layer

**Model Design:**
- NEVER use Pydantic v1 patterns (`validator`, `root_validator`, `schema_extra`, `orm_mode`, `.dict()`, `.json()`) — ALWAYS use v2 API
- NEVER use `Optional[X]` in model fields — ALWAYS use `X | None`
- NEVER use mutable default values directly in field definitions — use `default_factory`
- NEVER use `Any` as a field type — define explicit types or union types
- NEVER use `model_validate` with `from_attributes=True` unless `model_config = ConfigDict(from_attributes=True)` is set
- ALWAYS use `Field()` with constraints instead of writing manual validators for simple checks
- ALWAYS use `Annotated` types for reusable validation logic
- ALWAYS separate Create/Update/Response schemas — NEVER use one model for all operations

**Types & Generics:**
- ALWAYS use PEP 695 type parameter syntax (`class Foo[T]`, `type Alias = ...`) — NEVER use `TypeVar` / `Generic[T]` / `TypeAlias`

**Settings:**
- ALWAYS use `BaseSettings` from `pydantic-settings` for configuration — NEVER parse env vars manually
- ALWAYS use `SecretStr` for sensitive settings fields (passwords, API keys, tokens) — NEVER use plain `str`

**Quality:**
- ALWAYS run the project's typecheck and test commands after any schema change
</HARD-RULES>

These are the Pydantic v2 patterns for AppVerk projects, following **Domain-Driven Design** and **Clean Architecture**. All patterns target **Python 3.13+** and **Pydantic v2.7+**.

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Presentation Layer (FastAPI routers, schemas)        │
│  Pydantic: Request schemas (Create/Update),          │
│    Response schemas (from_domain()), Query models     │
│  Depends on: Application Layer, Domain Layer         │
├──────────────────────────────────────────────────────┤
│  Application Layer (Services / Use Cases)            │
│  Pydantic: NOT used (services work with domain       │
│    entities and Value Objects directly)               │
├──────────────────────────────────────────────────────┤
│  Domain Layer (Entities, Value Objects)               │
│  Pydantic: Value Objects only (frozen=True).         │
│  Entities are pure dataclasses.                       │
│  Depends on: NOTHING                                 │
├──────────────────────────────────────────────────────┤
│  Infrastructure Layer (ORM, Settings, Adapters)       │
│  Pydantic: Settings (BaseSettings), TypeAdapter for  │
│    boundary validation, from_attributes for ORM.     │
│  Depends on: Domain Layer                             │
└──────────────────────────────────────────────────────┘
```

**Pydantic's role per layer:**
- **Domain**: Value Objects with `frozen=True` when validation is needed. Entities are **not** BaseModel — they are mutable dataclasses (see `sqlalchemy-patterns` skill).
- **Presentation**: Request schemas (`*Create`, `*Update`), response schemas (`*Response` with `from_domain()`), query parameter models.
- **Infrastructure**: `BaseSettings` for configuration, `from_attributes=True` for ORM mapping, `TypeAdapter` for boundary validation.
- **Application**: Pydantic is **not used** in this layer. Services receive domain entities and Value Objects, not Pydantic models.

## Domain Layer — Value Objects

Value Objects have **no identity** and are **immutable**. Use `BaseModel(frozen=True)` when you need Pydantic's validation, or `@dataclass(frozen=True)` for simple cases.

### Value Object with Validation

```python
# app/domain/value_objects/money.py
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, field_validator


class Money(BaseModel):
    """Immutable Value Object — equality by value."""

    model_config = ConfigDict(frozen=True)

    amount: Decimal
    currency: str = "PLN"

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, v: str) -> str:
        if v not in ("USD", "EUR", "GBP", "PLN"):
            raise ValueError(f"Unsupported currency: {v}")
        return v.upper()

    def add(self, other: "Money") -> "Money":
        if self.currency != other.currency:
            raise ValueError("Cannot add different currencies")
        return self.model_copy(update={"amount": self.amount + other.amount})

    def subtract(self, other: "Money") -> "Money":
        if self.currency != other.currency:
            raise ValueError("Cannot subtract different currencies")
        return self.model_copy(update={"amount": self.amount - other.amount})
```

### Value Object with Enum

```python
# app/domain/value_objects/market_status.py
from enum import StrEnum


class MarketStatus(StrEnum):
    DRAFT = "draft"
    ACTIVE = "active"
    CLOSED = "closed"
    EXPIRED = "expired"
```

### Single-Field Value Object (RootModel)

For value types wrapping a single primitive, use `RootModel`:

```python
from pydantic import ConfigDict, RootModel, field_validator


class Email(RootModel[str]):
    model_config = ConfigDict(frozen=True)

    @field_validator("root")
    @classmethod
    def validate_email(cls, v: str) -> str:
        if "@" not in v:
            raise ValueError("Invalid email format")
        return v.strip().lower()


# Usage:
email = Email("USER@example.com")
print(email.root)          # "user@example.com"
print(email.model_dump())  # "user@example.com" (not {"root": ...})
```

### Value Object Conventions

- **Always `frozen=True`** — immutability is the defining property.
- **Use `model_copy(update=...)`** instead of creating new instances manually — preserves validation.
- **Equality by value** — Pydantic `frozen=True` models support `==` and hashing by default.
- **No identity** — Value Objects never have an `id` field.
- **Self-contained validation** — all constraints live inside the Value Object.

## Domain Layer — Entity Guidance

Domain entities are **pure Python dataclasses**, not Pydantic `BaseModel`. This is consistent with the `sqlalchemy-patterns` skill.

**Why dataclasses for entities:**
- Entities are **mutable** — `BaseModel` encourages immutability, `dataclass` is naturally mutable.
- Entities represent **trusted internal state** — no need to re-validate on every access. Validate at boundaries only.
- **Performance** — dataclass instantiation is ~6.5x faster than `BaseModel`.
- **No external dependencies** — domain layer has zero dependencies.

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

See the `sqlalchemy-patterns` skill for full domain entity patterns.

## Presentation Layer — Request/Response Schemas

### Request Schemas (Create / Update)

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
    min_stake: int = Field(gt=0, le=1_000_000)
    tags: list[str] = Field(default_factory=list, max_length=20)


class MarketUpdate(BaseModel):
    """Input schema for partial market update. All fields optional."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=5000)
    end_date: datetime | None = None
    min_stake: int | None = Field(default=None, gt=0)
```

### Response Schemas with from_domain()

Response schemas map **from domain entities**, not ORM models. The `from_domain()` classmethod documents this intent explicitly.

```python
class MarketResponse(BaseModel):
    """Output schema returned to clients."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str
    slug: str
    status: str
    min_stake: int
    end_date: datetime
    created_at: datetime
    updated_at: datetime

    @classmethod
    def from_domain(cls, entity: Market) -> "MarketResponse":
        """Map a domain entity to a response schema."""
        return cls.model_validate(entity, from_attributes=True)
```

**How `from_attributes=True` works here:**
- Works with `dataclass` entities (accesses `.name`, `.slug`, etc. as attributes).
- Works with ORM models too (if you ever need it at the infrastructure boundary).
- The `from_domain()` classmethod makes the mapping direction explicit — response schemas map from domain entities, not the other way around.

### Schema Naming Conventions

- `<Entity>Create` — required fields for creation. Use `Field()` constraints.
- `<Entity>Update` — all fields optional for partial updates. Use `exclude_unset=True` in `model_dump()` to detect what was actually sent.
- `<Entity>Response` — full representation returned to clients. Always has `from_domain()` classmethod.

### Nested Models and Composition

Compose models by embedding other models as field types. Never flatten nested data into the parent.

```python
class Address(BaseModel):
    street: str = Field(min_length=1)
    city: str = Field(min_length=1)
    country: str = Field(min_length=2, max_length=2)
    postal_code: str


class CompanyCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    billing_address: Address
    shipping_address: Address | None = None
```

## Generic Models — PEP 695

Use PEP 695 type parameter syntax for all generic Pydantic models. Never use `TypeVar` / `Generic[T]`.

### Paginated Response

```python
# app/schemas/common.py
from pydantic import BaseModel


class PaginatedResponse[T](BaseModel):
    data: list[T]
    total: int
    limit: int
    offset: int
```

### Type Aliases

```python
# PEP 695 type alias syntax
type NonEmptyStr = Annotated[str, StringConstraints(min_length=1, strip_whitespace=True)]
type CentsAmount = Annotated[int, Field(gt=0, le=100_000_000)]
```

### PEP 695 Caveats

PEP 695 generics work well for simple generic models (the most common case). Known limitations:
- Multi-level inheritance with `__init_subclass__` may fail — fall back to `Generic[T]` for these rare cases.
- `ClassVar` types are incompatible with PEP 695 syntax.
- mypy plugin may incorrectly infer variance on `frozen=True` generics.

## Validators

### Field Validators

Use `@field_validator` for single-field validation. Always use `@classmethod` and declare the mode explicitly.

```python
from pydantic import BaseModel, field_validator


class UserCreate(BaseModel):
    username: str
    email: str

    @field_validator("username")
    @classmethod
    def username_must_be_alphanumeric(cls, v: str) -> str:
        if not v.isalnum():
            raise ValueError("Username must be alphanumeric")
        return v.lower()

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip().lower()
        return v
```

### Model Validators

Use `@model_validator` for cross-field validation. `mode="after"` receives the constructed model; `mode="before"` receives raw input.

```python
from pydantic import BaseModel, model_validator


class DateRange(BaseModel):
    start_date: datetime
    end_date: datetime

    @model_validator(mode="after")
    def end_after_start(self) -> "DateRange":
        if self.end_date <= self.start_date:
            raise ValueError("end_date must be after start_date")
        return self
```

### Annotated Validators (Reusable)

Use `BeforeValidator` and `AfterValidator` with `Annotated` for composable, reusable validation logic.

```python
from typing import Annotated

from pydantic import AfterValidator, BaseModel, BeforeValidator


def normalize_whitespace(v: str) -> str:
    return " ".join(v.split())


def must_be_title_case(v: str) -> str:
    if v != v.title():
        raise ValueError(f"Must be title case: {v!r}")
    return v


CleanTitle = Annotated[
    str,
    BeforeValidator(normalize_whitespace),
    AfterValidator(must_be_title_case),
]


class BookCreate(BaseModel):
    title: CleanTitle
    author: CleanTitle
```

### Validation Context

Pass dynamic data through validation using `ValidationInfo.context`:

```python
from pydantic import BaseModel, ValidationInfo, field_validator


class TransferCreate(BaseModel):
    amount: int
    currency: str

    @field_validator("currency")
    @classmethod
    def currency_must_be_supported(cls, v: str, info: ValidationInfo) -> str:
        supported = info.context.get("supported_currencies", []) if info.context else []
        if supported and v not in supported:
            raise ValueError(f"Currency {v} not supported")
        return v


# Usage:
transfer = TransferCreate.model_validate(
    {"amount": 100, "currency": "USD"},
    context={"supported_currencies": ["USD", "EUR", "PLN"]},
)
```

## Serialization

### model_dump and model_dump_json

```python
user = UserResponse.from_domain(user_entity)

# Dict with exclusions
user.model_dump(exclude={"internal_note"})

# JSON string
user.model_dump_json(indent=2, exclude_none=True)

# Only fields explicitly set (for PATCH endpoints)
update_data = body.model_dump(exclude_unset=True)

# JSON-serializable dict (datetimes become strings, etc.)
user.model_dump(mode="json")
```

### Field-Level Serializers

```python
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, field_serializer


class TransactionResponse(BaseModel):
    amount: Decimal
    created_at: datetime

    @field_serializer("amount")
    def serialize_amount(self, amount: Decimal) -> str:
        return f"{amount:.2f}"

    @field_serializer("created_at")
    def serialize_datetime(self, dt: datetime) -> str:
        return dt.isoformat()
```

### Reusable Serializers with Annotated

```python
from typing import Annotated

from pydantic import PlainSerializer, WrapSerializer
from pydantic import SerializerFunctionWrapHandler

# PlainSerializer — replaces default serialization entirely
FormattedDecimal = Annotated[
    Decimal,
    PlainSerializer(lambda x: f"{x:.2f}", return_type=str),
]

# WrapSerializer — modifies default serialization output
def round_float(v: float, handler: SerializerFunctionWrapHandler) -> float:
    return round(handler(v), 2)

RoundedFloat = Annotated[float, WrapSerializer(round_float)]
```

**When to use which:**
- `PlainSerializer` — completely replace serialization (e.g., Decimal → formatted string).
- `WrapSerializer` — tweak the default output (e.g., round floats after normal serialization).
- `@field_serializer` — when the logic is specific to one model, not reusable.

### Computed Fields

Use `@computed_field` for derived values that should appear in serialization.

```python
from pydantic import BaseModel, computed_field


class Rectangle(BaseModel):
    width: float
    height: float

    @computed_field
    @property
    def area(self) -> float:
        return self.width * self.height
```

## Custom Types & TypeAdapter

### Annotated Types for Reusable Validation

Define domain-specific types with `Annotated` to enforce constraints consistently across models.

```python
from typing import Annotated

from pydantic import AfterValidator, Field, StringConstraints

# Constrained string type
type NonEmptyStr = Annotated[str, StringConstraints(min_length=1, strip_whitespace=True)]

# Email normalization
type NormalizedEmail = Annotated[
    str,
    AfterValidator(lambda v: v.strip().lower()),
    StringConstraints(pattern=r"^[^@]+@[^@]+\.[^@]+$"),
]

# Positive money amount in cents
type CentsAmount = Annotated[int, Field(gt=0, le=100_000_000)]

# Slug format
type Slug = Annotated[
    str,
    StringConstraints(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", min_length=1, max_length=255),
]
```

### TypeAdapter

`TypeAdapter` validates and serializes arbitrary types without needing a `BaseModel`. Use it at boundaries to validate domain types (dataclasses, primitives, unions).

```python
from pydantic import TypeAdapter

from app.domain.entities.market import Market

# Create once, reuse — NEVER create TypeAdapter instances inside hot loops
_market_list_adapter = TypeAdapter(list[Market])


def validate_markets(data: list[dict]) -> list[Market]:
    return _market_list_adapter.validate_python(data)


def serialize_markets(markets: list[Market]) -> str:
    return _market_list_adapter.dump_json(markets).decode()
```

**TypeAdapter use cases:**
- Validating domain dataclasses at API boundaries.
- Generating JSON Schema for non-BaseModel types: `_market_list_adapter.json_schema()`.
- Serializing lists, unions, or primitives without wrapping in a model.

### FailFast Annotation

For large list validation, use `FailFast` to stop at the first invalid item instead of validating all:

```python
from typing import Annotated

from pydantic import BaseModel, FailFast


class BulkImport(BaseModel):
    items: Annotated[list[MarketCreate], FailFast()]
```

### JSON Schema Customization

Use `json_schema_extra` for OpenAPI examples and custom schema extensions:

```python
from pydantic import BaseModel, Field


class MarketCreate(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "name": "Election 2024",
                    "description": "US Presidential Election",
                    "end_date": "2024-11-05T00:00:00Z",
                }
            ]
        }
    )

    name: str = Field(min_length=1, max_length=255)
    description: str = Field(min_length=1, max_length=5000)
    end_date: datetime
```

## Discriminated Unions

Use `Field(discriminator=...)` to select the correct model variant based on a type field. Discriminated unions are Rust-powered and significantly faster than untagged unions.

### Field-Level Discriminator

```python
from typing import Literal

from pydantic import BaseModel, Field


class EmailNotification(BaseModel):
    type: Literal["email"]
    recipient: str
    subject: str
    body: str


class SmsNotification(BaseModel):
    type: Literal["sms"]
    phone_number: str
    message: str


class PushNotification(BaseModel):
    type: Literal["push"]
    device_token: str
    title: str
    body: str


class NotificationRequest(BaseModel):
    notification: EmailNotification | SmsNotification | PushNotification = Field(
        discriminator="type"
    )
```

### Callable Discriminator

For complex dispatch logic where the discriminator isn't a simple field value:

```python
from typing import Annotated, Any

from pydantic import BaseModel, Discriminator, Tag


def event_discriminator(v: Any) -> str:
    if isinstance(v, dict):
        if "order_id" in v:
            return "order"
        if "user_id" in v:
            return "user"
    return "unknown"


class OrderEvent(BaseModel):
    order_id: str
    action: str


class UserEvent(BaseModel):
    user_id: str
    action: str


class EventRequest(BaseModel):
    event: Annotated[
        Annotated[OrderEvent, Tag("order")] | Annotated[UserEvent, Tag("user")],
        Discriminator(event_discriminator),
    ]
```

## Model Config

Use `ConfigDict` for all model configuration. Never use inner `class Config`.

```python
from pydantic import BaseModel, ConfigDict


class StrictInput(BaseModel):
    model_config = ConfigDict(
        strict=True,           # no type coercion
        frozen=True,           # immutable after creation
        extra="forbid",        # reject unknown fields
    )

    name: str
    value: int
```

### Strict Mode Guidance

- **Lax mode** (default): coerces types — `"123"` becomes `int(123)`. Use at API boundaries where HTTP data is always strings.
- **Strict mode**: requires exact Python types. Use for internal/domain models where type safety matters.

```python
# Lax — appropriate for API input schemas
class MarketCreate(BaseModel):
    name: str
    min_stake: int  # accepts "100" from JSON

# Strict — appropriate for Value Objects and internal models
class Money(BaseModel):
    model_config = ConfigDict(frozen=True, strict=True)
    amount: Decimal
    currency: str
```

**Note:** Strict mode from JSON is more lenient — it accepts ISO date strings for `datetime`, number strings for numeric types, etc. Strictness primarily matters for Python-to-Python validation.

## Settings Management

Use `pydantic-settings` for all application configuration. Settings live in the **infrastructure layer**.

### Basic Settings

```python
from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env",),
        env_file_encoding="utf-8",
        extra="ignore",
        env_ignore_empty=True,     # treat empty string as missing
        validate_default=True,     # validate default values too
    )

    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    secret_key: SecretStr = Field(min_length=32)
    debug: bool = False
    log_level: str = "INFO"
```

**`SecretStr`** prevents accidental logging of sensitive values:
```python
settings = Settings()
print(settings.secret_key)                    # SecretStr('**********')
print(settings.secret_key.get_secret_value()) # actual value
```

### Nested Settings

Use `env_nested_delimiter` to map flat env vars to nested structures.

```python
from pydantic import BaseModel, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class DatabaseSettings(BaseModel):
    host: str = "localhost"
    port: int = 5432
    name: str = "app"
    user: str = "postgres"
    password: SecretStr


class CacheSettings(BaseModel):
    host: str = "localhost"
    port: int = 6379
    db: int = 0


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="APP_",
        env_nested_delimiter="__",
        env_file=(".env",),
        env_file_encoding="utf-8",
        env_ignore_empty=True,
    )

    database: DatabaseSettings = DatabaseSettings()
    cache: CacheSettings = CacheSettings()
    debug: bool = False


# Env vars: APP_DATABASE__HOST=db.prod.local, APP_DATABASE__PORT=5433
settings = Settings()
```

Use `env_nested_max_split` when your delimiter is ambiguous:

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_nested_delimiter="_",
        env_nested_max_split=1,  # only split on first "_"
        env_prefix="GENERATION_",
    )
    llm: LLMConfig
# GENERATION_LLM_API_KEY -> llm.api_key (not llm.api.key)
```

### Secrets Management (Docker / Kubernetes)

```python
from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        secrets_dir="/run/secrets",  # Docker secrets, Kubernetes secrets
    )

    db_password: SecretStr
    api_key: SecretStr

# File /run/secrets/db_password contains the secret value
```

For nested secrets with directory structure, use `NestedSecretsSettingsSource`:

```python
from pydantic_settings import (
    BaseSettings,
    NestedSecretsSettingsSource,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        secrets_dir="secrets",
        secrets_nested_subdir=True,  # secrets/db/password file
    )

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        return (
            init_settings,
            env_settings,
            dotenv_settings,
            NestedSecretsSettingsSource(file_secret_settings),
        )
```

### Settings as a Dependency

Instantiate settings once. Inject via FastAPI dependency for testability.

```python
from functools import lru_cache

from app.config import Settings


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
```

**Note:** `lru_cache` caches the settings instance for the process lifetime. This is appropriate for most cases. If you need to reload settings (e.g., in tests), clear the cache: `get_settings.cache_clear()`.

## Error Handling

### Catching ValidationError

Always catch `ValidationError` explicitly. Use `.errors()` for structured error data.

```python
from pydantic import BaseModel, ValidationError


class ItemCreate(BaseModel):
    name: str
    price: int


try:
    ItemCreate.model_validate({"price": "not_a_number"})
except ValidationError as e:
    for error in e.errors():
        print(error["loc"], error["type"], error["msg"])
```

### Formatting Errors for API Responses

Transform Pydantic errors into a consistent API error format.

```python
from pydantic import ValidationError
from fastapi import Request
from fastapi.responses import JSONResponse


def format_validation_errors(exc: ValidationError) -> list[dict[str, str]]:
    errors = []
    for error in exc.errors():
        field = ".".join(str(loc) for loc in error["loc"])
        errors.append({
            "field": field,
            "message": error["msg"],
            "type": error["type"],
        })
    return errors


async def validation_exception_handler(
    request: Request,
    exc: ValidationError,
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "detail": "Validation failed",
            "errors": format_validation_errors(exc),
        },
    )
```

### Custom Error Messages in Validators

Raise `ValueError` with clear, user-facing messages. Never expose internal details.

```python
from pydantic import BaseModel, ValidationInfo, field_validator


class TransferCreate(BaseModel):
    amount: int
    source_account_id: str
    target_account_id: str

    @field_validator("amount")
    @classmethod
    def amount_must_be_positive(cls, v: int) -> int:
        if v <= 0:
            raise ValueError("Transfer amount must be greater than zero")
        return v

    @field_validator("target_account_id")
    @classmethod
    def accounts_must_differ(cls, v: str, info: ValidationInfo) -> str:
        if "source_account_id" in info.data and v == info.data["source_account_id"]:
            raise ValueError("Source and target accounts must be different")
        return v
```

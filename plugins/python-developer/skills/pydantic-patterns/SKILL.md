---
name: pydantic-patterns
description: Enforces Pydantic patterns: model design, validators, settings management, FastAPI schema integration. Activates when working with data models, validation, or configuration.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*)
---

# Pydantic Patterns

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- NEVER use Pydantic v1 patterns (`validator`, `root_validator`, `schema_extra`, `orm_mode`, `.dict()`, `.json()`) -- ALWAYS use v2 API
- NEVER use `Optional[X]` in model fields -- ALWAYS use `X | None`
- NEVER use mutable default values directly in field definitions -- use `default_factory`
- NEVER expose ORM models as API responses -- ALWAYS use dedicated Pydantic schemas
- NEVER use `model_validate` with `from_attributes=True` unless `model_config = ConfigDict(from_attributes=True)` is set
- NEVER use `Any` as a field type -- define explicit types or union types
- ALWAYS use `Field()` with constraints instead of writing manual validators for simple checks
- ALWAYS use `Annotated` types for reusable validation logic
- ALWAYS use `BaseSettings` from `pydantic-settings` for configuration -- NEVER parse env vars manually
- ALWAYS separate Create/Update/Response schemas -- NEVER use one model for all operations
- ALWAYS run `make typecheck` and `make test` after any schema change
</HARD-RULES>

These are the internal Pydantic v2 patterns that guide data model design for AppVerk projects.

## Model Design

Define models with explicit field types, constraints via `Field()`, and `ConfigDict` for behavior.

### Basic Model with Field Constraints

```python
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class MarketCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    description: str = Field(min_length=1, max_length=5000)
    end_date: datetime
    min_stake: int = Field(gt=0, le=1_000_000)
    tags: list[str] = Field(default_factory=list, max_length=20)


class MarketResponse(BaseModel):
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
```

### Nested Models and Composition

Compose models by embedding other models as field types. Never flatten nested data into the parent.

```python
from pydantic import BaseModel, ConfigDict, Field


class Address(BaseModel):
    street: str = Field(min_length=1)
    city: str = Field(min_length=1)
    country: str = Field(min_length=2, max_length=2)
    postal_code: str


class CompanyCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    billing_address: Address
    shipping_address: Address | None = None


class CompanyResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    billing_address: Address
    shipping_address: Address | None
```

### Model Config

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

### Computed Fields

Use `@computed_field` for derived values that should appear in serialization.

```python
from pydantic import BaseModel, computed_field


class Rectangle(BaseModel):
    width: float
    height: float

    @computed_field  # type: ignore[prop-decorator]
    @property
    def area(self) -> float:
        return self.width * self.height
```

## Validators

### Field Validators

Use `@field_validator` for single-field validation. Always use `@classmethod` and declare the mode explicitly.

```python
from pydantic import BaseModel, field_validator


class UserCreate(BaseModel):
    username: str
    email: str
    age: int

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

    @field_validator("age")
    @classmethod
    def validate_age(cls, v: int) -> int:
        if v < 18:
            raise ValueError("Must be at least 18 years old")
        return v
```

### Model Validators

Use `@model_validator` for cross-field validation. Access all fields via `self` (mode `"after"`) or raw data (mode `"before"`).

```python
from typing import Any

from datetime import datetime

from pydantic import BaseModel, model_validator


class DateRange(BaseModel):
    start_date: datetime
    end_date: datetime

    @model_validator(mode="after")
    def end_after_start(self) -> "DateRange":
        if self.end_date <= self.start_date:
            raise ValueError("end_date must be after start_date")
        return self


class RawInputModel(BaseModel):
    data: dict[str, str]

    @model_validator(mode="before")
    @classmethod
    def preprocess_data(cls, values: dict[str, Any]) -> dict[str, Any]:
        if "raw" in values:
            values["data"] = parse_raw(values.pop("raw"))
        return values
```

### Annotated Validators (BeforeValidator, AfterValidator)

Use `BeforeValidator` and `AfterValidator` with `Annotated` for reusable, composable validation logic.

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

## Serialization

### model_dump and model_dump_json

Use `model_dump()` for dict output and `model_dump_json()` for JSON string output. Use `exclude`, `include`, and `by_alias` parameters to control output shape.

```python
from pydantic import BaseModel, Field


class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    internal_note: str = Field(exclude=True)


user = UserResponse(id=1, name="Alice", email="alice@example.com", internal_note="VIP")

# Exclude fields
user.model_dump()
# {'id': 1, 'name': 'Alice', 'email': 'alice@example.com'}

# Include only specific fields
user.model_dump(include={"id", "name"})
# {'id': 1, 'name': 'Alice'}

# JSON string
user.model_dump_json(indent=2)
```

### model_validate

Use `model_validate()` to construct models from dicts or ORM objects.

```python
from pydantic import BaseModel, ConfigDict


class ItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    price: float


# From dict
item = ItemResponse.model_validate({"id": 1, "name": "Widget", "price": 9.99})

# From ORM object (SQLAlchemy model instance)
item = ItemResponse.model_validate(db_item)
```

### Custom Serializers

Use `@field_serializer` for field-level control and `PlainSerializer` for reusable type-level serialization.

```python
from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, field_serializer


class TransactionResponse(BaseModel):
    amount: Decimal
    currency: str
    created_at: datetime

    @field_serializer("amount")
    def serialize_amount(self, amount: Decimal) -> str:
        return f"{amount:.2f}"

    @field_serializer("created_at")
    def serialize_datetime(self, dt: datetime) -> str:
        return dt.isoformat()
```

Reusable serialization with `Annotated`:

```python
from typing import Annotated

from pydantic import PlainSerializer

FormattedDecimal = Annotated[
    Decimal,
    PlainSerializer(lambda x: f"{x:.2f}", return_type=str),
]
```

## Settings Management

Use `pydantic-settings` for all application configuration. Never parse environment variables manually.

### Basic Settings

```python
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env",),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    secret_key: str = Field(min_length=32)
    debug: bool = False
    log_level: str = "INFO"
```

### Nested Settings

Use `env_nested_delimiter` to map flat env vars to nested structures.

```python
from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict


class DatabaseSettings(BaseModel):
    host: str = "localhost"
    port: int = 5432
    name: str = "app"
    user: str = "postgres"
    password: str = ""


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
    )

    database: DatabaseSettings = DatabaseSettings()
    cache: CacheSettings = CacheSettings()
    debug: bool = False


# Env vars: APP_DATABASE__HOST=db.prod.local, APP_DATABASE__PORT=5433
settings = Settings()
```

### Settings as a Dependency

Instantiate settings once at module level. Inject via FastAPI dependency for testability.

```python
from functools import lru_cache

from app.config import Settings


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
```

## FastAPI Integration

### Request/Response Schema Separation

Always define separate schemas for Create, Update, and Response. Follow the `<Entity>Create`, `<Entity>Update`, `<Entity>Response` naming convention.

```python
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ProductCreate(BaseModel):
    """Fields required to create a product."""

    name: str = Field(min_length=1, max_length=255)
    description: str = Field(max_length=5000, default="")
    price: int = Field(gt=0, description="Price in cents")
    category_id: UUID


class ProductUpdate(BaseModel):
    """All fields optional for partial updates."""

    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=5000)
    price: int | None = Field(default=None, gt=0)
    category_id: UUID | None = None


class ProductResponse(BaseModel):
    """Full representation returned to clients."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str
    price: int
    category_id: UUID
    created_at: datetime
    updated_at: datetime
```

### Paginated Response

Use a generic wrapper for list endpoints.

```python
from pydantic import BaseModel


class PaginatedResponse[T](BaseModel):
    data: list[T]
    total: int
    limit: int
    offset: int
```

### Model Config for API Schemas

```python
from pydantic import BaseModel, ConfigDict


class ResponseBase(BaseModel):
    """Base class for all response schemas."""

    model_config = ConfigDict(
        from_attributes=True,      # map from ORM objects
        populate_by_name=True,     # allow both alias and field name
    )
```

## Custom Types

### Annotated Types for Reusable Validation

Define domain-specific types with `Annotated` to enforce constraints consistently across models.

```python
from typing import Annotated

from pydantic import AfterValidator, Field, StringConstraints

# Constrained string type
NonEmptyStr = Annotated[str, StringConstraints(min_length=1, strip_whitespace=True)]

# Email normalization
NormalizedEmail = Annotated[
    str,
    AfterValidator(lambda v: v.strip().lower()),
    StringConstraints(pattern=r"^[^@]+@[^@]+\.[^@]+$"),
]

# Positive money amount in cents
CentsAmount = Annotated[int, Field(gt=0, le=100_000_000)]

# Slug format
Slug = Annotated[
    str,
    StringConstraints(pattern=r"^[a-z0-9]+(?:-[a-z0-9]+)*$", min_length=1, max_length=255),
]
```

### Discriminated Unions

Use `Field(discriminator=...)` to select the correct model variant based on a type field.

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

Use `Literal` for the discriminator field to get exhaustive type checking and clear OpenAPI schema generation.

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
    # Structured errors for logging or API response
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

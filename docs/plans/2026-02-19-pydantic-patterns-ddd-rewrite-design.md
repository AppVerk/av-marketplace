# Pydantic Patterns — Strict DDD Rewrite Design

**Date:** 2026-02-19
**Status:** Approved
**Skill:** python-developer/skills/pydantic-patterns
**Current version:** part of python-developer 2.0.0
**Target runtime:** Python 3.13+, Pydantic v2.7+, pydantic-settings v2.7+

## Context

The `pydantic-patterns` skill guides Pydantic code generation for AppVerk projects. The current skill was written with a flat, feature-centric approach — no distinction between layers, no DDD patterns, and models map "from ORM objects" instead of domain entities. AppVerk projects follow DDD and Clean Architecture — the skill must reflect this and be consistent with the already-rewritten `sqlalchemy-patterns` and `fastapi-patterns` skills.

### Audit Findings

**CRITICAL — DDD / Clean Architecture violations:**
1. No architecture overview showing Pydantic's role across layers
2. No layer distinction — all patterns presented as if in one flat codebase
3. `ResponseBase` says "map from ORM objects" — should map from domain entities
4. No `from_domain()` classmethod on response schemas (fastapi-patterns has it)
5. No Value Object patterns using Pydantic `frozen=True`

**IMPORTANT — Inconsistencies with other rewritten skills:**
6. Hardcoded `make typecheck` and `make test` in HARD-RULES
7. No PEP 695 enforcement via HARD-RULE (fastapi-patterns has it)
8. No `from_domain()` in FastAPI integration section — inconsistent with fastapi-patterns
9. `from_attributes=True` framed as ORM mapping, not domain entity mapping

**MODERATE — Missing modern Pydantic patterns:**
10. No `TypeAdapter` for validating non-BaseModel types
11. No `FailFast` annotation for early validation termination
12. No validation context (`ValidationInfo.context`)
13. No `SecretStr` for sensitive configuration values
14. No callable `Discriminator` for complex union dispatch
15. No strict mode guidance (when to use strict vs lax)
16. No `model_json_schema()` for OpenAPI/JSON Schema generation
17. `lru_cache` pattern for settings may return stale object
18. No `env_ignore_empty` for pydantic-settings
19. No `validate_default` in ConfigDict
20. No `model_copy(update=...)` pattern for Value Object modifications

**MINOR:**
21. `@computed_field` has `# type: ignore[prop-decorator]` — no longer needed
22. No `WrapSerializer` (only `PlainSerializer`)
23. No `json_schema_extra` for OpenAPI examples
24. No `env_nested_max_split` for ambiguous delimiters
25. No `NestedSecretsSettingsSource` for Docker/K8s secrets

### Design Decisions

**DDD alignment — "Strict DDD" approach (consistent with other skills):**
- Domain entities are dataclasses (not BaseModel) — established in sqlalchemy-patterns
- Value Objects can use Pydantic `BaseModel(frozen=True)` when validation is needed
- Response schemas use `from_domain()` classmethod — consistent with fastapi-patterns
- `from_attributes=True` works with both dataclasses and ORM — framed for domain entities
- TypeAdapter bridges domain dataclasses with Pydantic validation at boundaries
- Settings are infrastructure concern — Pydantic in infrastructure layer

**PEP 695 (consistent with fastapi-patterns):**
- All generic types use PEP 695 syntax: `class Foo[T](BaseModel):` instead of `Generic[T]`
- Type aliases use `type Alias = ...` instead of `TypeAlias`
- Enforced via HARD-RULE

**Python 3.13+ / Pydantic v2.7+:**
- Minimum Python 3.13, Pydantic v2.7+
- `@computed_field` no longer needs `# type: ignore`
- PEP 695 generics supported since Pydantic v2.11

## Design

### Skill Structure

Organized by Clean Architecture layers, showing Pydantic's role in each:

```
1.  HARD-RULES
2.  Architecture Overview (Pydantic's role per layer)
3.  Domain Layer — Value Objects
4.  Domain Layer — Entity Guidance (why dataclasses, not BaseModel)
5.  Presentation Layer — Request/Response Schemas
6.  Presentation Layer — from_domain() Pattern
7.  Generic Models (PEP 695)
8.  Validators (field_validator, model_validator, Annotated)
9.  Serialization (model_dump, field_serializer, PlainSerializer, WrapSerializer)
10. Custom Types & TypeAdapter
11. Discriminated Unions
12. Settings Management (pydantic-settings v2)
13. Error Handling
```

### HARD-RULES (Updated)

Rules to ADD:
- NEVER use `BaseModel` for domain entities — ALWAYS use `dataclass` for mutable entities, `BaseModel(frozen=True)` only for Value Objects that need validation
- NEVER return domain entities directly from API endpoints — ALWAYS map through response schemas with `from_domain()` classmethod
- ALWAYS use PEP 695 type parameter syntax (`class Foo[T]`, `type Alias = ...`) — NEVER use `TypeVar` / `Generic[T]` / `TypeAlias`
- ALWAYS use `SecretStr` for sensitive settings fields (passwords, API keys, tokens) — NEVER use plain `str`

Rules to FIX:
- "ALWAYS run `make typecheck` and `make test`" → "ALWAYS run the project's typecheck and test commands after any schema change"

Rules to KEEP (unchanged):
- NEVER use Pydantic v1 patterns
- NEVER use `Optional[X]` — ALWAYS use `X | None`
- NEVER use mutable default values directly — use `default_factory`
- NEVER expose ORM models as API responses
- NEVER use `model_validate` with `from_attributes=True` unless `ConfigDict(from_attributes=True)` is set
- NEVER use `Any` as a field type
- ALWAYS use `Field()` with constraints instead of manual validators for simple checks
- ALWAYS use `Annotated` types for reusable validation logic
- ALWAYS use `BaseSettings` from `pydantic-settings` for configuration
- ALWAYS separate Create/Update/Response schemas

### Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  Presentation Layer (FastAPI routers, schemas)        │
│  Pydantic: Request schemas (Create/Update),          │
│    Response schemas (from_domain()), Query models     │
│  Depends on: Application Layer, Domain Layer         │
├──────────────────────────────────────────────────────┤
│  Application Layer (Services / Use Cases)            │
│  Pydantic: NOT used here (services work with         │
│    domain entities directly)                          │
├──────────────────────────────────────────────────────┤
│  Domain Layer (Entities, Value Objects)               │
│  Pydantic: Value Objects (frozen=True) when          │
│    validation needed. Entities are dataclasses.       │
│  Depends on: NOTHING                                 │
├──────────────────────────────────────────────────────┤
│  Infrastructure Layer (ORM, Settings, Adapters)       │
│  Pydantic: Settings (BaseSettings), TypeAdapter for  │
│    boundary validation, from_attributes for ORM.     │
│  Depends on: Domain Layer                             │
└──────────────────────────────────────────────────────┘
```

### Domain Layer — Value Objects

```python
class Money(BaseModel):
    model_config = ConfigDict(frozen=True)

    amount: Decimal
    currency: str = "PLN"

    def add(self, other: "Money") -> "Money":
        if self.currency != other.currency:
            raise ValueError("Cannot add different currencies")
        return self.model_copy(update={"amount": self.amount + other.amount})
```

### Domain Layer — Entity Guidance

Why dataclasses for entities, not BaseModel:
- Entities are mutable (BaseModel shouldn't be mutated)
- Entities represent trusted internal state (no validation overhead)
- Performance: dataclass instantiation ~6.5x faster than BaseModel
- Consistent with sqlalchemy-patterns decision

### Presentation Layer — from_domain()

```python
class MarketResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str

    @classmethod
    def from_domain(cls, entity: Market) -> "MarketResponse":
        return cls.model_validate(entity, from_attributes=True)
```

### Custom Types & TypeAdapter

TypeAdapter for validating non-BaseModel types (domain dataclasses, primitives):

```python
_market_list_adapter = TypeAdapter(list[Market])

def validate_markets(data: list[dict]) -> list[Market]:
    return _market_list_adapter.validate_python(data)
```

### Settings Management

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env",),
        env_nested_delimiter="__",
        env_ignore_empty=True,
        validate_default=True,
    )

    database_url: str
    secret_key: SecretStr
```

### What Gets Removed from Current Skill

1. `ResponseBase` with "map from ORM objects" framing
2. `# type: ignore[prop-decorator]` on `@computed_field`
3. Hardcoded `make typecheck` / `make test` in HARD-RULES
4. `lru_cache` pattern for settings (replaced with note about caching)

### What Gets Added (Not in Current Skill)

1. Architecture overview with Pydantic's role per layer
2. Value Object patterns (`frozen=True`, `model_copy(update=...)`)
3. Entity guidance (why dataclass, not BaseModel)
4. `from_domain()` classmethod on response schemas
5. PEP 695 enforcement via HARD-RULE
6. `SecretStr` enforcement for sensitive settings
7. `TypeAdapter` for boundary validation
8. `FailFast` annotation for large list validation
9. Validation context (`ValidationInfo.context`)
10. Callable `Discriminator` for complex unions
11. `WrapSerializer` alongside `PlainSerializer`
12. `json_schema_extra` for OpenAPI examples
13. `env_ignore_empty`, `validate_default`, `env_nested_max_split`
14. `NestedSecretsSettingsSource` for Docker/K8s secrets
15. Strict mode guidance (when to use strict vs lax)

### What Stays (Updated)

1. Model design patterns (Field constraints, ConfigDict) — updated with strict guidance
2. Validators (field_validator, model_validator, Annotated) — unchanged, reinforced
3. Serialization (model_dump, field_serializer) — extended with WrapSerializer
4. Nested settings — updated with modern pydantic-settings options
5. Request/Response schema separation — reframed for DDD
6. Discriminated unions — extended with callable Discriminator
7. Error handling patterns — unchanged
8. Computed fields — updated (removed type: ignore)
9. PaginatedResponse[T] — updated to PEP 695 with note

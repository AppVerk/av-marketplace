---
name: tdd-workflow
description: Enforces test-driven development: writes tests before code, uses fakes over mocks, maintains 80%+ coverage. Activates when writing new features, fixing bugs, or refactoring Python code.
allowed-tools: Read, Grep, Glob, Bash(pytest:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(coverage:*)
---

# Test-Driven Development Workflow

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS write tests BEFORE implementation code — no exceptions
- ALWAYS use Fake implementations (in-memory, simplified) for dependencies — NEVER use unittest.mock or pytest-mock for internal dependencies
- ONLY use mocks for external I/O: 3rd party APIs (OpenAI, Stripe), real database calls in unit tests, network requests
- NEVER put imports inside test functions or methods — ALL imports go at the top of the test file
- NEVER write tests that depend on other tests — each test sets up its own data via fixtures
- NEVER use `assert False` — use `raise AssertionError("explanation")` instead
- ALWAYS run the full test suite (`make test` or `uv run pytest`) not just specific tests
- ALWAYS verify 80%+ coverage before considering work complete
- ALWAYS use `pytest.mark.parametrize` for similar test cases instead of duplicating tests
- ALWAYS use factory fixtures for creating similar data objects
</HARD-RULES>

This skill ensures all code development follows TDD principles with comprehensive test coverage.

## When to Activate

- Writing new features or functionality
- Fixing bugs or issues
- Refactoring existing code
- Adding API endpoints
- Creating new services

## Core Principles

### 1. Tests BEFORE Code

ALWAYS write tests first, then implement code to make tests pass.

### 2. Coverage Requirements

- Minimum 80% coverage (unit + functional + integration)
- All edge cases covered
- Error scenarios tested
- Boundary conditions verified

### 3. Test Types

#### Unit Tests

- Individual functions and methods
- Service logic
- Pure functions
- Helpers and utilities

#### Functional Tests

- Black-box testing of the API
- Black-box testing of feature behavior
- Faked dependencies

#### Integration Tests

- API endpoints
- Database operations
- Service interactions
- External API calls

## TDD Workflow Steps

### Step 1: Write User Journeys

```
As a [role], I want to [action], so that [benefit]

Example:
As a user, I want to search for markets semantically,
so that I can find relevant markets even without exact keywords.
```

### Step 2: Generate Test Cases

For each user journey, create comprehensive test cases:

```python
# tests/test_semantic_search.py
import pytest
from app.services.search import search_markets

class TestSemanticSearch:
    async def test_returns_relevant_markets_for_query(self):
        # Test implementation
        pass

    async def test_handles_empty_query_gracefully(self):
        # Test edge case
        pass

    async def test_falls_back_to_substring_search_when_redis_unavailable(self):
        # Test fallback behavior
        pass

    async def test_sorts_results_by_similarity_score(self):
        # Test sorting logic
        pass
```

### Step 3: Run Tests (They Should Fail)

```bash
pytest
# Tests should fail - we haven't implemented yet
```

### Step 4: Implement Code

Write minimal code to make tests pass:

```python
# app/services/search.py
async def search_markets(query: str) -> list[dict]:
    """Search markets using semantic similarity."""
    # Implementation here
    pass
```

### Step 5: Run Tests Again

```bash
pytest
# Tests should now pass
```

### Step 6: Refactor

Improve code quality while keeping tests green:

- Remove duplication
- Improve naming
- Optimize performance
- Enhance readability

### Step 7: Verify Coverage

```bash
pytest --cov=app --cov-report=term-missing
# Verify 80%+ coverage achieved
```

## Testing Patterns

### Unit Test Pattern (pytest)

```python
# tests/unit/test_market_service.py
import pytest
from app.services.market import MarketService
from tests.fakes import FakeMarketRepository

class TestMarketService:
    @pytest.fixture
    def repository(self):
        return FakeMarketRepository()

    @pytest.fixture
    def service(self, repository):
        return MarketService(repository=repository)

    def test_creates_market_with_valid_data(self, service):
        market = service.create(
            name="Test Market",
            description="A test market"
        )
        assert market.name == "Test Market"
        assert market.slug == "test-market"

    def test_raises_error_for_duplicate_name(self, service, repository):
        repository.add_existing(name="Existing Market")

        with pytest.raises(ValueError, match="Market already exists"):
            service.create(name="Existing Market", description="...")

    def test_validates_market_end_date(self, service):
        with pytest.raises(ValueError, match="End date must be in the future"):
            service.create(
                name="Test",
                description="...",
                end_date="2020-01-01"
            )
```

### API Integration Test Pattern

```python
# tests/integration/test_markets_api.py
import pytest
from httpx import AsyncClient
from app.main import app
from tests.fixtures import seed_test_markets

class TestMarketsAPI:
    @pytest.fixture
    async def client(self):
        async with AsyncClient(app=app, base_url="http://test") as client:
            yield client

    @pytest.fixture(autouse=True)
    async def setup_test_data(self, test_db):
        """Seed test database with sample markets."""
        await seed_test_markets(test_db)

    async def test_returns_markets_successfully(self, client):
        response = await client.get("/api/markets")
        data = response.json()

        assert response.status_code == 200
        assert data["success"] is True
        assert isinstance(data["data"], list)

    async def test_validates_query_parameters(self, client):
        response = await client.get("/api/markets?limit=invalid")

        assert response.status_code == 422  # Validation error

    async def test_filters_markets_by_status(self, client):
        response = await client.get("/api/markets?status=active")
        data = response.json()

        assert response.status_code == 200
        assert all(m["status"] == "active" for m in data["data"])
```

### Functional Test Pattern (Black-box API)

```python
# tests/functional/test_market_workflow.py
import pytest
from httpx import AsyncClient
from app.main import app

class TestMarketSearchWorkflow:
    """Black-box functional tests for market search feature."""

    @pytest.fixture
    async def client(self):
        async with AsyncClient(app=app, base_url="http://test") as client:
            yield client

    @pytest.fixture
    async def seeded_markets(self, client):
        """Seed test markets for functional tests."""
        markets = [
            {"name": "Election 2024", "description": "Presidential election"},
            {"name": "Super Bowl Winner", "description": "NFL championship"},
            {"name": "Election Day Weather", "description": "Weather on election"},
        ]
        created = []
        for market in markets:
            response = await client.post("/api/markets", json=market)
            created.append(response.json()["data"])
        yield created
        # Cleanup handled by test database rollback

    async def test_user_can_search_and_filter_markets(
        self, client, seeded_markets
    ):
        # Search for markets
        response = await client.get(
            "/api/markets/search",
            params={"q": "election"}
        )

        assert response.status_code == 200
        results = response.json()["data"]

        # Verify search results returned
        assert len(results) == 2  # Two election-related markets

        # Verify results contain search term
        for result in results:
            assert "election" in result["name"].lower() or \
                   "election" in result["description"].lower()

        # Filter by status
        response = await client.get(
            "/api/markets/search",
            params={"q": "election", "status": "active"}
        )

        assert response.status_code == 200
        filtered = response.json()["data"]
        assert all(m["status"] == "active" for m in filtered)


class TestMarketCreationWorkflow:
    """Black-box functional tests for market creation."""

    @pytest.fixture
    async def client(self):
        async with AsyncClient(app=app, base_url="http://test") as client:
            yield client

    @pytest.fixture
    async def authenticated_client(self, client):
        """Get authenticated client with creator permissions."""
        response = await client.post("/api/auth/login", json={
            "email": "creator@test.com",
            "password": "testpass123"
        })
        token = response.json()["token"]
        client.headers["Authorization"] = f"Bearer {token}"
        yield client

    async def test_user_can_create_new_market(self, authenticated_client):
        # Create market via API
        response = await authenticated_client.post("/api/markets", json={
            "name": "Test Market",
            "description": "Test description",
            "end_date": "2025-12-31"
        })

        assert response.status_code == 201
        data = response.json()
        assert data["success"] is True
        assert data["data"]["name"] == "Test Market"
        assert data["data"]["slug"] == "test-market"

        # Verify market is retrievable
        market_id = data["data"]["id"]
        get_response = await authenticated_client.get(f"/api/markets/{market_id}")

        assert get_response.status_code == 200
        assert get_response.json()["data"]["name"] == "Test Market"
```

## Test File Organization

```
project/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── services/
│   │   ├── __init__.py
│   │   └── market.py
│   ├── repositories/
│   │   ├── __init__.py
│   │   └── market.py
│   └── api/
│       ├── __init__.py
│       └── routes/
│           └── markets.py
├── tests/
│   ├── __init__.py
│   ├── conftest.py                    # Shared fixtures
│   ├── fakes/                         # Fake implementations
│   │   ├── __init__.py
│   │   ├── repositories.py            # FakeMarketRepository, etc.
│   │   └── services.py                # FakeSearchService, etc.
│   ├── fixtures/                      # Test data helpers
│   │   ├── __init__.py
│   │   └── markets.py                 # seed_test_markets(), etc.
│   ├── unit/
│   │   ├── __init__.py
│   │   ├── test_market_service.py     # Unit tests
│   │   └── test_validators.py
│   ├── integration/
│   │   ├── __init__.py
│   │   └── test_markets_api.py        # Integration tests
│   └── functional/
│       ├── __init__.py
│       ├── test_market_workflow.py    # Functional tests
│       └── test_trading_workflow.py
└── pyproject.toml
```

## Test Doubles: Fakes vs Mocks

### Prefer Fakes Over Mocks

- **Fakes**: Simplified working implementations (in-memory database, fake repository)
- **Mocks**: Only for external I/O (3rd party APIs, real database calls, network requests)

### When to Use Each

| Scenario | Use |
|----------|-----|
| Repository/data access | Fake (in-memory implementation) |
| Business logic dependencies | Fake (simplified implementation) |
| 3rd party API calls (OpenAI, Stripe) | Mock |
| Database operations in integration tests | Test database with rollback |
| External HTTP requests | Mock or fake HTTP server |

### Fake Implementations

```python
# tests/fakes/__init__.py
"""Fake implementations for testing."""

from .repositories import FakeMarketRepository, FakeUserRepository
from .services import FakeEmailService, FakeSearchService


# tests/fakes/repositories.py
from typing import Optional
from app.models import Market

class FakeMarketRepository:
    """In-memory fake repository for testing."""

    def __init__(self):
        self._markets: dict[str, Market] = {}
        self._id_counter = 1

    def add_existing(self, **kwargs) -> Market:
        """Helper to seed test data."""
        market = Market(id=self._id_counter, **kwargs)
        self._markets[market.slug] = market
        self._id_counter += 1
        return market

    async def get_by_slug(self, slug: str) -> Optional[Market]:
        return self._markets.get(slug)

    async def get_all(self) -> list[Market]:
        return list(self._markets.values())

    async def save(self, market: Market) -> Market:
        market.id = self._id_counter
        self._markets[market.slug] = market
        self._id_counter += 1
        return market

    async def exists(self, name: str) -> bool:
        return any(m.name == name for m in self._markets.values())


# tests/fakes/services.py
class FakeSearchService:
    """Fake semantic search for testing."""

    def __init__(self):
        self._results: list[dict] = []

    def set_results(self, results: list[dict]):
        """Configure search results for test."""
        self._results = results

    async def search(self, query: str) -> list[dict]:
        # Simple substring matching for tests
        return [r for r in self._results if query.lower() in r["name"].lower()]


class FakeEmailService:
    """Fake email service that records sent emails."""

    def __init__(self):
        self.sent_emails: list[dict] = []

    async def send(self, to: str, subject: str, body: str):
        self.sent_emails.append({"to": to, "subject": subject, "body": body})
```

### Mocks Only for External I/O

```python
# tests/conftest.py
import pytest

@pytest.fixture
def mock_openai(mocker):
    """Mock OpenAI API - external service requiring mock."""
    mock = mocker.patch("app.integrations.openai.client.embeddings.create")
    mock.return_value.data = [type("Embedding", (), {"embedding": [0.1] * 1536})()]
    return mock

@pytest.fixture
def mock_stripe(mocker):
    """Mock Stripe API - external payment service."""
    mock = mocker.patch("app.integrations.stripe.client")
    mock.PaymentIntent.create.return_value = {"id": "pi_test", "status": "succeeded"}
    return mock
```

### Usage Example

```python
# tests/unit/test_market_service.py
class TestMarketService:
    @pytest.fixture
    def repository(self):
        return FakeMarketRepository()

    @pytest.fixture
    def search_service(self):
        fake = FakeSearchService()
        fake.set_results([
            {"slug": "election-2024", "name": "Election 2024"},
            {"slug": "superbowl", "name": "Super Bowl Winner"},
        ])
        return fake

    @pytest.fixture
    def service(self, repository, search_service):
        return MarketService(
            repository=repository,
            search_service=search_service
        )

    def test_search_returns_matching_markets(self, service):
        results = service.search("election")
        assert len(results) == 1
        assert results[0]["slug"] == "election-2024"
```

## Test Coverage Verification

### Run Coverage Report

```bash
pytest --cov=app --cov-report=term-missing --cov-report=html
```

### Coverage Thresholds

```toml
# pyproject.toml
[tool.coverage.run]
source = ["app"]
branch = true

[tool.coverage.report]
fail_under = 80
show_missing = true
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
]
```

## Common Testing Mistakes to Avoid

### Testing Implementation Details

```python
# Don't test internal state
assert service._internal_cache["key"] == "value"
```

### Test Public Interface

```python
# Test observable behavior
result = service.get("key")
assert result == "expected_value"
```

### Brittle Assertions

```python
# Breaks easily
assert str(error) == "Error: Invalid input at position 5"
```

### Flexible Assertions

```python
# Resilient to message changes
assert isinstance(error, ValueError)
assert "Invalid input" in str(error)
```

### No Test Isolation

```python
# Tests depend on each other
class TestUser:
    user_id = None

    def test_creates_user(self):
        TestUser.user_id = create_user()

    def test_updates_same_user(self):
        update_user(TestUser.user_id)  # depends on previous test
```

### Independent Tests

```python
# Each test sets up its own data
class TestUser:
    @pytest.fixture
    def user(self):
        return create_test_user()

    def test_creates_user(self, user):
        assert user.id is not None

    def test_updates_user(self, user):
        updated = update_user(user.id, name="New Name")
        assert updated.name == "New Name"
```

## Continuous Testing

### Watch Mode During Development

```bash
pytest-watch
# or
ptw -- --testmon
# Tests run automatically on file changes
```

### Pre-Commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: pytest
        name: pytest
        entry: pytest --tb=short
        language: system
        types: [python]
        pass_filenames: false
```

### CI/CD Integration

```yaml
# GitHub Actions
- name: Run Tests
  run: |
    pytest --cov=app --cov-report=xml
- name: Upload Coverage
  uses: codecov/codecov-action@v4
  with:
    files: coverage.xml
```

## Best Practices

1. **Write Tests First** - Always TDD
2. **One Assert Per Test** - Focus on single behavior
3. **Descriptive Test Names** - Explain what's tested
4. **Arrange-Act-Assert** - Clear test structure
5. **Use Fakes for Dependencies** - Prefer fakes over mocks
6. **Mock Only External I/O** - 3rd party APIs, network calls
7. **Test Edge Cases** - Null, undefined, empty, large
8. **Test Error Paths** - Not just happy paths
9. **Keep Tests Fast** - Unit tests < 50ms each
10. **Clean Up After Tests** - No side effects

## Success Metrics

- 80%+ code coverage achieved
- All tests passing (green)
- No skipped or disabled tests
- Fast test execution (< 30s for unit tests)
- Functional tests cover critical API workflows
- Tests catch bugs before production

---

**Remember**: Tests are not optional. They are the safety net that enables confident refactoring, rapid development, and production reliability.

## Test Code Standards

These standards extend the HARD-RULES above with organizational and structural guidance (absorbed from coding-standards):

### General Testing Principles

- Write code amenable to unit testing with no hidden I/O or tight coupling.
- Keep typing in tests where practical, even if excluded from type checks.
- Don't write trivial tests that test obvious functionality (e.g., testing Pydantic model instantiation).
- Prefer running the whole test suite instead of specific tests.

### Test Organization

- For similar data objects, use factory fixtures.
- Combine similar test cases using `pytest.mark.parametrize`.
- Any environment variables setup should be done in conftest using monkeypatch fixture, unless not possible.
- Test directory layout:
  - `tests/unit` — fast, isolated tests of pure logic
  - `tests/integration` — tests that cross process/service boundaries (DB, network, etc.)
  - `tests/functional` — blackbox tests of the API or feature behavior with faked dependencies
  - `tests/e2e` — end-to-end tests that exercise the system as a whole
- Mirror the source tree under `src/` starting after the repository's domain package (drop the top-level package folder). For code in:
  - `src/<domain_package>/<subpath>/module.py`
  write tests in:
  - `tests/<kind>/<subpath>/test_module.py`
  where `<kind>` is one of `unit` | `integration` | `functional` | `e2e`.
- File naming: `test_<module>.py` for module-level tests; use `test_<thing>_<behavior>.py` when clearer.
- Keep category-specific conftest, fixtures, and data near the tests:
  - `tests/conftest.py` for global fixtures
  - `tests/<kind>/conftest.py` for category-scoped fixtures

### Mocking Rules

- Avoid mocks unless for external I/O like 3rd party API calls, database operations, etc.
- For internal dependencies, ALWAYS create Fake implementations instead.
- For detailed guidance on choosing between Fakes and Mocks, see the **Test Doubles: Fakes vs Mocks** section above.

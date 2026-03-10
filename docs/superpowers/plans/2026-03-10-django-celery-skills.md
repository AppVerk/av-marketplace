# Django & Celery Skills Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Django REST Framework, Django ORM, and Celery skills to the python-developer plugin, plus update the agent detection logic and documentation.

**Architecture:** Three new SKILL.md files following the existing skill format (frontmatter + HARD-RULES + patterns + examples). The agent's detection logic (Phase 2-3) is extended to conditionally load Django/Celery skills. FastAPI and Django skills are mutually exclusive.

**Tech Stack:** Claude Code plugin system (Markdown skill files, agent definitions, plugin.json)

**Spec:** `docs/superpowers/specs/2026-03-10-django-celery-skills-design.md`

---

## Chunk 1: New Skill Files

### Task 1: Create `django-web-patterns` skill

**Files:**
- Create: `plugins/python-developer/skills/django-web-patterns/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `plugins/python-developer/skills/django-web-patterns/SKILL.md` with the following content.

The frontmatter must follow the exact format of existing skills (see `fastapi-patterns/SKILL.md` for reference):

```yaml
---
name: django-web-patterns
description: Enforces Django REST Framework patterns with Pragmatic DDD: ViewSets, Serializers, Permissions, exception handling, settings, middleware. Activates when working with Django views, endpoints, or DRF serializers.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(manage.py:*), Bash(django-admin:*)
---
```

The body must include:

1. `<HARD-RULES>` section with all rules from the spec's "django-web-patterns" section:
   - Views rules (no business logic in ViewSets, use Serializers, ModelViewSet for CRUD, @action for custom actions, etc.)
   - Serializers rules (no `__all__`, separate Create/Update/Response, etc.)
   - URLs rules (DefaultRouter, namespace, reverse())
   - Permissions rules (custom classes, composite with &/|)
   - Exception handling rules (custom handler, domain exception hierarchy: `DomainError` → `EntityNotFoundError`, `DomainValidationError`, `PermissionDeniedError`, `ConflictError`)
   - Settings & Middleware rules (django-environ/pydantic-settings, split settings, CORS from env)
   - Throttling & Filtering rules (django-filter, FilterSet)
   - Quality rule: ALWAYS run typecheck and test after changes

2. Architecture Overview section — Pragmatic DDD layers diagram (same as spec)

3. Directory Layout section:
   ```
   project/
       apps/
           orders/
               models.py          # Django models (rich domain models)
               serializers.py     # DRF serializers
               views.py           # ViewSets / APIViews
               urls.py            # Router registration
               permissions.py     # Custom permission classes
               filters.py         # FilterSet classes
               services.py        # Application layer (use cases)
               exceptions.py      # Domain exceptions
               tasks.py           # Celery tasks (if using celery)
               tests/
                   test_views.py
                   test_models.py
                   test_services.py
       config/
           settings/
               base.py
               local.py
               production.py
               test.py
           urls.py                # Root URL config
           wsgi.py
           asgi.py
   ```

4. ViewSet Structure section — with code examples:
   - ModelViewSet example with `get_queryset()`, `perform_create()`, `@action`
   - Dependency on services (instantiate in `get_service()` method or via DI)

5. Serializer Patterns section — with code examples:
   - `OrderCreateSerializer`, `OrderUpdateSerializer`, `OrderResponseSerializer`
   - Nested serializers
   - `from_domain()` pattern (classmethod on response serializer, matching FastAPI skill convention)

6. Domain Exception Handling section — with code examples:
   - Domain exception hierarchy (using prefixed names: `EntityNotFoundError`, `DomainValidationError`, `PermissionDeniedError`, `ConflictError`)
   - Custom DRF exception handler function
   - Registration in settings (`REST_FRAMEWORK.EXCEPTION_HANDLER`)

7. Permissions section — custom permission class example

8. Settings & Middleware section — split settings pattern, django-environ example

9. Throttling & Filtering section — FilterSet example with `django-filter`

10. Testing DRF section:
    - `pytest-django` + `@pytest.mark.django_db`
    - `APIClient` for functional tests
    - `RequestFactory` for unit tests
    - `factory_boy` for test data
    - Example test class

Total target: ~200-250 lines. Keep examples concise — one representative example per pattern, not exhaustive.

- [ ] **Step 2: Verify the file is valid Markdown**

Read the created file and verify:
- Frontmatter has `---` delimiters
- All code blocks are properly closed
- HARD-RULES section uses `<HARD-RULES>` / `</HARD-RULES>` tags
- No broken links or references

- [ ] **Step 3: Commit**

```bash
git add plugins/python-developer/skills/django-web-patterns/SKILL.md
git commit -m "feat(python-developer): add django-web-patterns skill"
```

---

### Task 2: Create `django-orm-patterns` skill

**Files:**
- Create: `plugins/python-developer/skills/django-orm-patterns/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `plugins/python-developer/skills/django-orm-patterns/SKILL.md` with frontmatter:

```yaml
---
name: django-orm-patterns
description: Enforces Django ORM patterns with Pragmatic DDD: rich domain models, Managers, QuerySets, migrations, signals, performance. Activates when working with Django models, queries, or migrations.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(manage.py:*), Bash(django-admin:*)
---
```

The body must include:

1. `<HARD-RULES>` section with all rules from the spec's "django-orm-patterns" section:
   - Models rules (no business logic in save(), no null=True on CharField/TextField, explicit on_delete, related_name, db_index, abstract base models, __str__, Meta constraints)
   - Managers & QuerySets rules (no complex queries in views, as_manager(), domain concept naming, no raw SQL)
   - Performance rules (no N+1, select_related/prefetch_related, only()/defer(), bulk operations, iterator())
   - Migrations rules (separate data/schema migrations, RunPython with reverse_code, sqlmigrate review)
   - Signals rules (no signals for business logic, only side effects, dispatch_uid)
   - Quality rule: ALWAYS run typecheck and test after changes

2. Rich Domain Model Pattern section — with code example:
   - `TimeStampedModel` abstract base model
   - `Order` model with `can_cancel()`, `cancel()` domain methods
   - `OrderStatus` as `TextChoices`

3. Managers & QuerySets section — with code examples:
   - Custom QuerySet with domain-concept methods (`active()`, `for_user()`, `published()`)
   - `as_manager()` pattern
   - Chaining example

4. Model Definition Patterns section — with code examples:
   - ForeignKey with `on_delete`, `related_name`
   - `Meta.indexes`, `Meta.constraints` (`UniqueConstraint`, `CheckConstraint`)
   - Choices using `TextChoices` / `IntegerChoices`

5. Performance Patterns section — with code examples:
   - `select_related()` vs `prefetch_related()` decision table
   - `Prefetch` object for complex prefetches
   - `bulk_create()` / `bulk_update()` examples

6. Migration Patterns section:
   - Data migration example with `RunPython` + `reverse_code`
   - When to use `RunSQL`

7. Signals section:
   - When to use (cache invalidation, audit logging) vs when NOT to use (business logic)
   - Example with `dispatch_uid`

8. Optional Repository Pattern section:
   - Protocol definition
   - Django implementation wrapping QuerySet
   - When to use vs direct QuerySet access

9. Testing Django ORM section:
   - `factory_boy` with `DjangoModelFactory` example
   - Unit tests for model methods (no DB when possible)
   - Integration tests for QuerySet methods (`@pytest.mark.django_db`)
   - `assertNumQueries` example

Total target: ~200-250 lines.

- [ ] **Step 2: Verify the file is valid Markdown**

Same checks as Task 1 Step 2.

- [ ] **Step 3: Commit**

```bash
git add plugins/python-developer/skills/django-orm-patterns/SKILL.md
git commit -m "feat(python-developer): add django-orm-patterns skill"
```

---

### Task 3: Create `celery-patterns` skill

**Files:**
- Create: `plugins/python-developer/skills/celery-patterns/SKILL.md`

- [ ] **Step 1: Create the skill file**

Create `plugins/python-developer/skills/celery-patterns/SKILL.md` with frontmatter:

```yaml
---
name: celery-patterns
description: Enforces Celery task patterns: idempotent design, retry strategies, error handling, testing with eager mode. Activates when working with Celery tasks, background jobs, or async workers.
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(celery:*)
---
```

The body must include:

1. `<HARD-RULES>` section with all rules from the spec's "celery-patterns" section:
   - Task Design rules (idempotent, pass IDs not model instances, decompose long tasks, bind=True, explicit name, acks_late)
   - Retry & Error Handling rules (no bare except, autoretry_for + backoff + jitter, no retry for business errors, dead letter handling)
   - Organization rules (shared_task, tasks in <app>/tasks.py, no circular imports)
   - Configuration rules (task_always_eager in tests, CELERY_ namespace for Django, celery_app.conf.update() for non-Django)
   - Quality rule: ALWAYS run typecheck and test after changes

2. Task Structure section — with code example:
   - Complete `@shared_task` example with `bind=True`, `name`, `acks_late`, `autoretry_for`, `retry_backoff`, `retry_jitter`, `max_retries`
   - Shows fetching model by ID, calling service, handling exceptions

3. Idempotency Patterns section:
   - Check-before-act pattern
   - Database-level uniqueness constraints for deduplication
   - Brief explanation of why idempotency matters

4. Task Decomposition section:
   - Example: processing a collection by spawning subtasks per item
   - `group()` for fan-out (this is basic enough to include)

5. Configuration section:
   - Django settings example (`CELERY_` namespace)
   - Non-Django config example (`celery_app.conf.update()`)
   - `celery.py` app setup in Django project

6. Testing Celery Tasks section:
   - `task_always_eager=True` + `task_eager_propagates=True` in test settings
   - Unit test: test service logic directly (not through task)
   - Task test: verify task calls service correctly in eager mode
   - `@override_settings` example for pytest-django

Total target: ~150 lines.

- [ ] **Step 2: Verify the file is valid Markdown**

Same checks as Task 1 Step 2.

- [ ] **Step 3: Commit**

```bash
git add plugins/python-developer/skills/celery-patterns/SKILL.md
git commit -m "feat(python-developer): add celery-patterns skill"
```

---

## Chunk 2: Agent & Command Updates

### Task 4: Update agent definition (`developer.md`)

**Files:**
- Modify: `plugins/python-developer/agents/developer.md`

- [ ] **Step 1: Update frontmatter**

In the frontmatter (lines 1-8), make these changes:

1. Update `description` to mention Django and Celery:
   ```
   description: Expert Python developer agent for implementing features, fixing issues, and refactoring code. Enforces Python coding standards (type hints, absolute imports, X | None), TDD workflow (tests before code, fakes over mocks, 80%+ coverage), and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic, Django, DRF, Celery, async). Use this agent instead of general-purpose agents when working on Python projects.
   ```

2. Add Django/Celery tools to `allowed-tools`:
   ```
   allowed-tools: Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(coverage:*), Bash(alembic:*), Bash(git:*), Bash(pip:*), Bash(manage.py:*), Bash(django-admin:*), Bash(celery:*)
   ```

3. Add new skills to `skills:` list:
   ```
   skills: coding-standards, tdd-workflow, fastapi-patterns, sqlalchemy-patterns, pydantic-patterns, async-python-patterns, uv-package-manager, django-web-patterns, django-orm-patterns, celery-patterns
   ```

- [ ] **Step 2: Update Phase 2 — detection logic**

In Phase 2, Step 2.2 (around line 76-83), add Django/Celery detection to the dependency list:

After the existing items (`fastapi`, `sqlalchemy`, `pydantic`, `asyncio`/`anyio`/`uvicorn`, `uv`), add:
```markdown
- `django` — Django framework
- `djangorestframework` — Django REST Framework
- `celery` — Celery task queue
```

In Step 2.3 (around line 85-93), add Django/Celery import scanning:

After the existing patterns, add:
```markdown
- `from django import` / `import django` / `from django.db import`
- `from rest_framework import` / `import rest_framework`
- `from celery import` / `import celery`
```

Also add file-based detection after import scanning:
```markdown
### Step 2.4: Detect Django Project Structure

Look for Django-specific files in the project root and one level deep:
- `manage.py` — Django management script
- `settings.py` or `settings/` directory — Django settings
- `wsgi.py` / `asgi.py` — Django application entry points

If any of these are found alongside `django` in dependencies, confirm Django stack.
```

Renumber existing Step 2.4 (Discover Project Commands) to Step 2.5.

- [ ] **Step 3: Update Phase 3 — conditional skill loading**

In Phase 3 (around line 115-160), add Django/Celery skill loading after the existing FastAPI/SQLAlchemy/Pydantic blocks.

Add mutual exclusion note before the conditional blocks:
```markdown
### Stack Detection: Django vs FastAPI

**Django and FastAPI skills are mutually exclusive.** If both Django and FastAPI are detected in the project:
1. Check `$ARGUMENTS` for explicit framework references
2. If still ambiguous, prefer the framework with more imports in `src/` or `app/`
3. If still ambiguous after steps 1-2, ask the user which stack to target for this task

**When Django is detected, do NOT load:** `fastapi-patterns`, `sqlalchemy-patterns`
**When FastAPI is detected, do NOT load:** `django-web-patterns`, `django-orm-patterns`
**`celery-patterns` and `pydantic-patterns` can load with either stack.**
```

Add the Django conditional blocks:
```markdown
**If Django detected OR task involves Django views/models/admin:**

\```
Use the Skill tool with:
  skill: "python-developer:django-web-patterns"
\```

**If Django ORM detected OR task involves Django models/queries/migrations:**

\```
Use the Skill tool with:
  skill: "python-developer:django-orm-patterns"
\```

**If Celery detected OR task involves background tasks/workers/queues:**

\```
Use the Skill tool with:
  skill: "python-developer:celery-patterns"
\```
```

Note: `pydantic-patterns` loading remains unchanged — it loads if Pydantic is detected regardless of framework. Add a note:
```markdown
**Note:** `pydantic-patterns` may load with Django projects if `pydantic` or `pydantic-settings` is detected. In Django context, the pydantic-patterns rule "NO BaseModel for domain entities" does not apply — Django models ARE the domain entities in Pragmatic DDD.
```

- [ ] **Step 4: Verify changes**

Read the modified file and verify:
- Frontmatter is valid YAML
- Phase 2 detection covers Django/Celery
- Phase 3 has mutual exclusion logic
- Phase 3 has conditional loading for all 3 new skills
- No broken markdown formatting

- [ ] **Step 5: Commit**

```bash
git add plugins/python-developer/agents/developer.md
git commit -m "feat(python-developer): extend agent with Django/Celery detection and skill loading"
```

---

### Task 5: Update command definition (`commands/develop.md`)

**Files:**
- Modify: `plugins/python-developer/commands/develop.md`

- [ ] **Step 1: Update frontmatter**

Add Django/Celery tools to `allowed-tools` (line 2):
```
allowed-tools: Read, Grep, Glob, Bash(ruff:*), Bash(mypy:*), Bash(basedpyright:*), Bash(make:*), Bash(uv:*), Bash(python:*), Bash(pytest:*), Bash(coverage:*), Bash(alembic:*), Bash(git:*), Bash(pip:*), Bash(manage.py:*), Bash(django-admin:*), Bash(celery:*)
```

Update `description` (line 3):
```
description: Python development workflow enforcing coding standards, TDD, and stack-specific patterns. Loads the right skills automatically (FastAPI, Django, Celery).
```

- [ ] **Step 2: Update Step 2b — stack detection**

In Step 2b (around line 46-52), add Django/Celery to the dependency detection list:

After the existing items, add:
```markdown
- `django`, `djangorestframework` — Django + DRF
- `celery` — Celery task queue
```

Add to import scanning:
```markdown
- `from django.db import` / `from rest_framework import` / `from celery import`
```

Add to task description keywords:
```markdown
- Django keywords: view, viewset, serializer, admin, management command, signal
- Celery keywords: task, worker, queue, background job, celery, beat
```

- [ ] **Step 3: Update Step 3 — conditional skill loading**

Add Django/Celery conditional loading blocks (same pattern as existing FastAPI/SQLAlchemy/Pydantic blocks):

```markdown
### If Django detected OR task involves views/viewsets/serializers:

\```
Use the Skill tool with:
  skill: "python-developer:django-web-patterns"
\```

### If Django ORM detected OR task involves Django models/queries/migrations:

\```
Use the Skill tool with:
  skill: "python-developer:django-orm-patterns"
\```

### If Celery detected OR task involves background tasks/workers:

\```
Use the Skill tool with:
  skill: "python-developer:celery-patterns"
\```
```

Add mutual exclusion note:
```markdown
**Important:** Django and FastAPI skills are mutually exclusive. If both are detected, load skills for the framework most relevant to the current task; if ambiguous, ask the user. When Django is detected, do NOT load `fastapi-patterns` or `sqlalchemy-patterns`. `celery-patterns` and `pydantic-patterns` can load with either stack.
```

- [ ] **Step 4: Update Step 7 — Final Verification Checklist**

Add Django/Celery items to the "Stack-Specific" checklist (around line 213-220):

```markdown
- [ ] Django: ViewSets delegate to services, explicit field lists in serializers, custom permissions
- [ ] Django ORM: select_related/prefetch_related for related objects, no N+1, domain logic in model methods
- [ ] Celery: tasks are idempotent, pass IDs not model instances, retry with backoff for transient errors
```

- [ ] **Step 5: Verify and commit**

```bash
git add plugins/python-developer/commands/develop.md
git commit -m "feat(python-developer): extend /develop command with Django/Celery support"
```

---

## Chunk 3: Plugin Config & Documentation

### Task 6: Update plugin.json

**Files:**
- Modify: `plugins/python-developer/.claude-plugin/plugin.json`

- [ ] **Step 1: Bump version to 3.0.0**

Change version from `"2.1.0"` to `"3.0.0"`.

Update description to mention Django/Celery:
```json
{
  "name": "python-developer",
  "description": "Enforces Python best practices, coding standards, TDD workflow, and modern tooling for AppVerk projects. Supports FastAPI, Django, DRF, Celery, SQLAlchemy, and Pydantic stacks.",
  "version": "3.0.0"
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/python-developer/.claude-plugin/plugin.json
git commit -m "chore(release): bump python-developer plugin to v3.0.0"
```

---

### Task 7: Update documentation

**Files:**
- Modify: `docs/plugins/python-developer.md`

- [ ] **Step 1: Update header and version**

Change the description line (line 3) to:
```
Python development workflow with `/develop` command, coding standards, TDD, and stack-specific patterns (FastAPI, SQLAlchemy, Pydantic, Django, DRF, Celery).
```

Update version (line 5): `**Version:** 3.0.0`

- [ ] **Step 2: Update Commands section**

Update the `/develop` description (around line 11) to mention Django/Celery:
```
Python development workflow that automatically loads the right skills for the task. Analyzes the project to detect FastAPI, Django, DRF, Celery, SQLAlchemy, Pydantic, and enforces TDD and coding standards throughout.
```

Add Django/Celery examples to the command examples (after line 17):
```markdown
/develop Add a new DRF ViewSet for user registration
/develop Fix the N+1 query in the orders list view
/develop Add a Celery task for sending notification emails
/develop Refactor the order service to use the repository pattern
```

- [ ] **Step 3: Update Agent section**

Update the agent description paragraph (around line 23) to include Django/Celery in the workflow:
```
The agent follows the full Python Developer workflow:

1. Detects mode (fix, implement, or refactor) from the task description
2. Loads coding standards and detects the project stack
3. Loads stack-specific skills (FastAPI or Django/DRF, SQLAlchemy or Django ORM, Celery, Pydantic, async patterns)
4. Runs a TDD cycle appropriate to the mode
5. Passes quality gates (typecheck, tests, lint)
6. Reports results with changes left uncommitted
```

- [ ] **Step 4: Add new skills to Skills section**

After the existing "Pydantic Patterns" entry (after line 78), add three new skill entries:

```markdown
### Django Web Patterns

Enforces Django REST Framework patterns with Pragmatic DDD: ViewSets, Serializers, Permissions, exception handling, settings, middleware.

Activates when working with Django views, DRF endpoints, or serializers.

### Django ORM Patterns

Enforces Django ORM patterns with Pragmatic DDD: rich domain models, Managers, QuerySets, migrations, signals, performance optimization.

Activates when working with Django models, queries, or migrations.

### Celery Patterns

Enforces Celery task patterns: idempotent design, retry strategies with exponential backoff, error handling, testing with eager mode.

Activates when working with Celery tasks, background jobs, or async workers.
```

- [ ] **Step 5: Verify and commit**

Read the file and verify all sections are consistent and well-formatted.

```bash
git add docs/plugins/python-developer.md
git commit -m "docs(python-developer): add Django, DRF, and Celery skills documentation"
```

---

### Task 8: Final verification

- [ ] **Step 1: Verify all new skill files exist and have valid frontmatter**

Read each file and verify the `---` delimited frontmatter contains `name`, `description`, `allowed-tools`:
- `plugins/python-developer/skills/django-web-patterns/SKILL.md`
- `plugins/python-developer/skills/django-orm-patterns/SKILL.md`
- `plugins/python-developer/skills/celery-patterns/SKILL.md`

- [ ] **Step 2: Verify agent skills list matches actual skill directories**

Read `plugins/python-developer/agents/developer.md` frontmatter and confirm every skill in the `skills:` list has a corresponding directory under `plugins/python-developer/skills/`.

- [ ] **Step 3: Verify plugin.json version is 3.0.0**

Read `plugins/python-developer/.claude-plugin/plugin.json`.

- [ ] **Step 4: Verify documentation is up-to-date**

Read `docs/plugins/python-developer.md` and confirm:
- Version shows 3.0.0
- All 10 skills are documented (7 existing + 3 new)
- Command examples include Django/Celery use cases

- [ ] **Step 5: Run git log to verify commit history**

```bash
git log --oneline -10
```

Verify commits are clean and in order:
1. `feat(python-developer): add django-web-patterns skill`
2. `feat(python-developer): add django-orm-patterns skill`
3. `feat(python-developer): add celery-patterns skill`
4. `feat(python-developer): extend agent with Django/Celery detection and skill loading`
5. `feat(python-developer): extend /develop command with Django/Celery support`
6. `chore(release): bump python-developer plugin to v3.0.0`
7. `docs(python-developer): add Django, DRF, and Celery skills documentation`

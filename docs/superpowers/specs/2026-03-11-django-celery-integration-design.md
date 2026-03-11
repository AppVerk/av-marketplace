# Design: Add Django and Celery to developer-plugins-integration

**Date:** 2026-03-11
**Status:** Approved
**Scope:** Single file change in `plugins/code-review/skills/developer-plugins-integration/SKILL.md`

## Problem

The `developer-plugins-integration` skill does not detect or load Django and Celery skills from the `python-developer` plugin. Three skills are missing from the integration:

- `python-developer:django-orm-patterns` (Django ORM: models, managers, querysets, migrations)
- `python-developer:django-web-patterns` (Django REST Framework: viewsets, serializers, permissions)
- `python-developer:celery-patterns` (Celery: idempotent tasks, retry strategies, error handling)

## Approach

Grep on package names in dependency files (`pyproject.toml`, `requirements.txt`), consistent with the existing detection pattern for FastAPI, SQLAlchemy, and Pydantic.

Both Django skills (`django-orm-patterns` and `django-web-patterns`) load together when `django` is detected — DRF is a de facto standard in Django projects.

## Changes

All changes are in `plugins/code-review/skills/developer-plugins-integration/SKILL.md`:

### 1. Frontmatter description

Update the `description` field to include Django and Celery in the Python frameworks list:

```
description: Detects installed developer plugins (python-developer, frontend-developer, php-developer) and project stack, then provides a list of relevant skills to load for code review and fix workflows. Supports Python (FastAPI, SQLAlchemy, Pydantic, Django, Celery, asyncio, uv), Frontend (React, Tailwind, Zustand, TanStack, pnpm), and PHP (Symfony, Doctrine, DDD).
```

### 2. Step 2 — Python Framework Detection

Add two new detection blocks after the existing `uv` detection block (after the `echo "uv: $UV"` line), before the closing ` ``` `:

```bash
# Django
DJANGO=false
for f in $PYTHON_DEP_FILES; do
    grep -qi "django" "$f" 2>/dev/null && DJANGO=true
done
echo "Django: $DJANGO"

# Celery
CELERY=false
for f in $PYTHON_DEP_FILES; do
    grep -qi "celery" "$f" 2>/dev/null && CELERY=true
done
echo "Celery: $CELERY"
```

### 3. Output Format — JSON example

Add `"django": false` and `"celery": false` to the `python.frameworks` object, after `"uv": true`:

```json
"frameworks": {
  "fastapi": true,
  "sqlalchemy": true,
  "pydantic": true,
  "asyncio": true,
  "uv": true,
  "django": false,
  "celery": false
}
```

Also add Django/Celery skills to the `skills_to_load` example array — no change needed since the example shows a project without Django/Celery (both `false`), so no skills for them appear in `skills_to_load`.

### 4. Skills Resolution Table — Python Skills

Add three new rows at the end of the Python Skills table (after `uv-package-manager`):

```markdown
| `python-developer:django-orm-patterns` | Django detected |
| `python-developer:django-web-patterns` | Django detected |
| `python-developer:celery-patterns` | Celery detected |
```

### 5. Security Auditor — framework-specific patterns

Add two lines after the existing `- Doctrine: DQL injection prevention, entity security` line:

```markdown
- Django: CSRF protection, authentication backends, SQL injection via raw(), settings security (DEBUG, ALLOWED_HOSTS, SECRET_KEY)
- Celery: task serialization security, broker connection security
```

### 6. Final Checklist

Replace:
```
- [ ] Detected Python frameworks (FastAPI, SQLAlchemy, Pydantic, asyncio, uv)
```
With:
```
- [ ] Detected Python frameworks (FastAPI, SQLAlchemy, Pydantic, Django, Celery, asyncio, uv)
```

## Out of Scope

- No changes to Red Flags, Graceful Degradation (they work generically)
- No changes to other plugins or skills

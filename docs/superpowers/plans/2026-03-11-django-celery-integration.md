# Django & Celery Integration in developer-plugins-integration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Django and Celery framework detection and skill loading to the `developer-plugins-integration` skill.

**Architecture:** Extend a single Markdown skill file with detection blocks, skill resolution entries, and supporting references — following the exact patterns already established for FastAPI, SQLAlchemy, Pydantic, etc.

**Tech Stack:** Markdown, Bash (grep-based detection)

**Spec:** `docs/superpowers/specs/2026-03-11-django-celery-integration-design.md`

---

## File Structure

- Modify: `plugins/code-review/skills/developer-plugins-integration/SKILL.md`

No new files. No test files (this is a documentation/skill file, not executable code).

---

## Chunk 1: Implementation

### Task 1: Add Django and Celery to developer-plugins-integration

**Files:**
- Modify: `plugins/code-review/skills/developer-plugins-integration/SKILL.md`

**Reference:** Read the spec at `docs/superpowers/specs/2026-03-11-django-celery-integration-design.md` before making changes.

- [ ] **Step 1: Update frontmatter description (line 3)**

Replace the existing `description` field value:

```
description: Detects installed developer plugins (python-developer, frontend-developer, php-developer) and project stack, then provides a list of relevant skills to load for code review and fix workflows. Supports Python (FastAPI, SQLAlchemy, Pydantic, asyncio, uv), Frontend (React, Tailwind, Zustand, TanStack, pnpm), and PHP (Symfony, Doctrine, DDD).
```

With:

```
description: Detects installed developer plugins (python-developer, frontend-developer, php-developer) and project stack, then provides a list of relevant skills to load for code review and fix workflows. Supports Python (FastAPI, SQLAlchemy, Pydantic, Django, Celery, asyncio, uv), Frontend (React, Tailwind, Zustand, TanStack, pnpm), and PHP (Symfony, Doctrine, DDD).
```

- [ ] **Step 2: Add Django and Celery detection blocks in Step 2 (after line 108)**

Insert the following after the `echo "uv: $UV"` line and before the closing ` ``` `:

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

- [ ] **Step 3: Update Output Format JSON example (lines 308-314)**

Replace the `frameworks` object inside `python`:

```json
      "frameworks": {
        "fastapi": true,
        "sqlalchemy": true,
        "pydantic": true,
        "asyncio": true,
        "uv": true
      }
```

With:

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

- [ ] **Step 4: Add rows to Python Skills Resolution Table (after line 366)**

Insert three new rows after the `python-developer:uv-package-manager` row:

```markdown
| `python-developer:django-orm-patterns` | Django detected |
| `python-developer:django-web-patterns` | Django detected |
| `python-developer:celery-patterns` | Celery detected |
```

- [ ] **Step 5: Add Security Auditor patterns (after line 424)**

Insert two new lines after `- Doctrine: DQL injection prevention, entity security`:

```markdown
- Django: CSRF protection, authentication backends, SQL injection via raw(), settings security (DEBUG, ALLOWED_HOSTS, SECRET_KEY)
- Celery: task serialization security, broker connection security
```

- [ ] **Step 6: Update Final Checklist (line 495)**

Replace:

```markdown
- [ ] Detected Python frameworks (FastAPI, SQLAlchemy, Pydantic, asyncio, uv)
```

With:

```markdown
- [ ] Detected Python frameworks (FastAPI, SQLAlchemy, Pydantic, Django, Celery, asyncio, uv)
```

- [ ] **Step 7: Verify changes**

Read the modified file and verify:
1. Frontmatter description includes Django and Celery
2. Detection bash block has Django and Celery sections with correct pattern (grep -qi in for loop)
3. JSON example has `"django": false` and `"celery": false` in python.frameworks
4. Skills Resolution Table has 3 new rows (django-orm-patterns, django-web-patterns, celery-patterns)
5. Security Auditor section has Django and Celery lines
6. Final Checklist includes Django and Celery

- [ ] **Step 8: Commit**

```bash
git add plugins/code-review/skills/developer-plugins-integration/SKILL.md
git commit -m "feat(code-review): add Django and Celery to developer-plugins-integration

Add framework detection for Django and Celery in the Python stack
detection workflow. Map detected frameworks to python-developer skills:
- django-orm-patterns and django-web-patterns when Django detected
- celery-patterns when Celery detected

Also add security audit patterns for Django and Celery."
```

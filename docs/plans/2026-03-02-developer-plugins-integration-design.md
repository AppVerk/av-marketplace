# Developer Plugins Integration for Code Review

## Problem

Code-review plugin has 6 skills for security and quality analysis but no awareness of stack-specific coding standards and patterns provided by developer plugins (python-developer: 7 skills, frontend-developer: 8 skills). Reviews miss stack-specific violations, and fixes don't follow project conventions.

## Decision

**Approach B: Detection Skill** — Create a single reusable skill `developer-plugins-integration` in code-review that detects installed developer plugins, identifies the project stack, and loads relevant skills for both review and fix workflows.

## Design

### New Skill: `developer-plugins-integration`

**Location:** `plugins/code-review/skills/developer-plugins-integration/SKILL.md`

**Responsibilities:**

1. **Detect installed plugins** — check if `python-developer:coding-standards` and `frontend-developer:coding-standards` skills are available (presence in available skills = plugin installed)
2. **Detect project stack** — scan config files:
   - Python: `pyproject.toml`, `setup.py`, `requirements.txt`, `uv.lock`
   - Frontend: `package.json` + React/TypeScript (`tsconfig.json`, React in dependencies)
   - Monorepo: both stacks can coexist
3. **Map: plugin + stack -> skills** — for each detected stack with an installed plugin, produce list of skills to load
4. **Contextual instructions** — provide guidance on how to use loaded skills in review vs fix context

**Selection Logic:**

```
IF python-developer installed AND Python stack detected:
  LOAD: coding-standards, tdd-workflow
  IF FastAPI detected (fastapi in deps): LOAD fastapi-patterns
  IF SQLAlchemy detected: LOAD sqlalchemy-patterns
  IF Pydantic detected: LOAD pydantic-patterns
  IF asyncio usage detected: LOAD async-python-patterns
  IF uv detected (uv.lock): LOAD uv-package-manager

IF frontend-developer installed AND Frontend stack detected:
  LOAD: coding-standards, tdd-workflow
  IF Tailwind detected: LOAD tailwind-patterns
  IF Zustand detected: LOAD zustand-patterns
  IF TanStack Query detected: LOAD tanstack-query-patterns
  IF TanStack Router detected: LOAD tanstack-router-patterns
  IF React Hook Form detected: LOAD form-patterns
  IF pnpm detected (pnpm-lock.yaml): LOAD pnpm-package-manager
```

### Modified Files

| File | Change | Size |
|------|--------|------|
| `commands/review.md` | Add "Stack Detection Phase" at workflow start, pass results to agents | ~15-20 lines |
| `agents/code-quality-auditor.md` | Add skill + "Developer Standards Check" section after architecture-analysis | ~20-30 lines |
| `agents/security-auditor.md` | Add "Framework Security Patterns" section after standard scans | ~15-20 lines |
| `commands/fix.md` | Add skill in "Analyze Context" phase, use patterns during fix | ~10-15 lines |
| `agents/fix-auto.md` | Same as fix.md adapted for autonomous agent | ~10-15 lines |

### Integration Points

**Review workflow (`code-quality-auditor`):**
- Current order: standards-discovery -> linter-integration -> architecture-analysis
- New order: **developer-plugins-integration** -> standards-discovery -> linter-integration -> architecture-analysis -> **apply developer skills rules**
- Developer skills provide additional review criteria (e.g., "no relative imports", "X | None instead of Optional", "no `any` type", "fakes over mocks")

**Review workflow (`security-auditor`):**
- After standard scans (secret-scanning, sast-analysis, dependency-scanning)
- If developer skills loaded, check framework-specific security patterns
- Example: `fastapi-patterns` teaches "never BaseHTTPMiddleware (memory leaks)", "domain exceptions -> HTTP via global handlers"

**Fix workflow (`fix.md`, `fix-auto.md`):**
- After parsing issue, load developer-plugins-integration
- During "Analyze Context" — load relevant developer skills
- During "Implement Fix" — apply patterns from developer skills
- Example: fix for "N+1 query" in SQLAlchemy -> skill teaches "selectinload, joinedload, raiseload"

### Graceful Degradation

- **No developer plugins installed** -> standard review/fix, zero changes in behavior
- **Plugin installed, stack doesn't match** -> only matching plugin's skills loaded
- **Monorepo (both stacks)** -> both skill sets loaded, applied per-file based on context

### Extensibility

Adding a new developer plugin (e.g., `go-developer`) requires:
1. Update `developer-plugins-integration/SKILL.md` — add new detection section
2. No changes to commands/agents — they already delegate to the skill

### Performance Impact

- Stack detection: ~5-10 seconds (glob for config files)
- Skill loading: via `Skill` tool — one tool call per skill
- Max additional skills: 7 (Python) or 8 (Frontend)
- Context overhead: skills are 2-4KB each, loaded into agent context

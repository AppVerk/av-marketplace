---
name: standards-discovery
description: Discovers and parses project coding standards, style guides, and architecture documentation. Searches for CONTRIBUTING, CODING_STANDARDS, STYLE_GUIDE, CONVENTIONS, ARCHITECTURE files and extracts rules for code review.
allowed-tools: Read, Grep, Glob, Bash(find:*), Bash(cat:*), Bash(head:*), Bash(grep:*)
---

# Standards Discovery - Project Documentation Scanner

Discovers and parses project-specific coding standards, style guides, and architecture documentation to ensure code reviews align with project conventions.

---

## Purpose

Before reviewing code, understand what standards the project follows:

- Naming conventions
- Architecture patterns
- Testing requirements
- Import rules
- Code organization

**Project-specific rules always override generic best practices.**

---

## Discovery Workflow

### Step 1: Search for Standards Files

**ALWAYS run these searches first:**

```bash
# Primary standards files
find . -type f \( \
  -iname "CONTRIBUTING*" -o \
  -iname "CODING*STANDARD*" -o \
  -iname "STYLE*GUIDE*" -o \
  -iname "CODE*STYLE*" -o \
  -iname "CONVENTIONS*" -o \
  -iname "ARCHITECTURE*" -o \
  -iname "GUIDELINES*" -o \
  -iname "DEVELOPMENT*" -o \
  -iname "STANDARDS*" \
\) -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.venv/*" -not -path "./vendor/*" 2>/dev/null

# Check docs directory
find ./docs -type f -name "*.md" 2>/dev/null

# Check .github directory
find ./.github -type f -name "*.md" 2>/dev/null
```

### Step 2: Check Common Locations

| Location | Priority | What to look for |
|----------|----------|------------------|
| `CONTRIBUTING.md` | HIGH | Code style, PR process, testing requirements |
| `docs/ARCHITECTURE.md` | HIGH | Layer structure, patterns used |
| `docs/CODING_STANDARDS.md` | HIGH | Naming, formatting, imports |
| `.github/CONTRIBUTING.md` | MEDIUM | Contribution guidelines |
| `README.md` | LOW | Development section |
| `docs/` | MEDIUM | Any .md files with style/standards |

### Step 3: Parse README for Standards Section

```bash
# Look for development/contributing sections in README
grep -n -i -A 20 "## Development\|## Contributing\|## Code Style\|## Standards\|## Guidelines" README.md 2>/dev/null
```

---

## Standards Extraction

### Naming Conventions

Look for patterns like:

```bash
# Search for naming convention mentions
grep -rni "naming convention\|camelCase\|snake_case\|PascalCase\|kebab-case\|UPPER_CASE" --include="*.md" . 2>/dev/null
```

**Common patterns to identify:**

- Classes: `PascalCase` / `UpperCamelCase`
- Functions/methods: `snake_case` / `camelCase`
- Constants: `UPPER_SNAKE_CASE`
- Variables: `snake_case` / `camelCase`
- Files: `snake_case` / `kebab-case`

### Architecture Patterns

```bash
# Search for architecture mentions
grep -rni "clean architecture\|hexagonal\|DDD\|domain.driven\|layered\|SOLID\|microservice" --include="*.md" . 2>/dev/null

# Check for layer structure documentation
grep -rni "domain layer\|application layer\|infrastructure\|presentation layer\|use.case" --include="*.md" . 2>/dev/null
```

**Common architectures to identify:**

- Clean Architecture (layers: domain, application, infrastructure, presentation)
- Hexagonal Architecture (ports & adapters)
- DDD (aggregates, entities, value objects, repositories)
- Layered Architecture (presentation, business, data)

### Testing Requirements

```bash
# Search for testing standards
grep -rni "test coverage\|unit test\|integration test\|pytest\|jest\|testing" --include="*.md" . 2>/dev/null

# Look for coverage requirements
grep -rni "coverage.*%\|minimum.*coverage\|100%\|80%\|90%" --include="*.md" . 2>/dev/null
```

**Common requirements to identify:**

- Minimum coverage percentage
- Required test types (unit, integration, e2e)
- Testing framework preferences
- Mocking guidelines

### Import Rules

```bash
# Search for import guidelines
grep -rni "import\|absolute import\|relative import\|circular\|dependency" --include="*.md" . 2>/dev/null
```

**Common rules to identify:**

- Absolute vs relative imports
- Import ordering (stdlib, third-party, local)
- Circular dependency policy
- Dependency direction rules

---

## Output Format

Generate a structured summary of discovered standards:

```json
{
  "standards_found": true,
  "confidence": "HIGH|MEDIUM|LOW",
  "sources": [
    {
      "file": "CONTRIBUTING.md",
      "sections_found": ["Code Style", "Testing"]
    },
    {
      "file": "docs/ARCHITECTURE.md",
      "sections_found": ["Layer Structure", "DDD Patterns"]
    }
  ],
  "rules": {
    "naming": {
      "classes": "PascalCase",
      "functions": "snake_case",
      "constants": "UPPER_SNAKE_CASE",
      "variables": "snake_case",
      "files": "snake_case.py"
    },
    "architecture": {
      "pattern": "Clean Architecture",
      "layers": ["domain", "application", "infrastructure", "api"],
      "dependency_direction": "outer -> inner",
      "ddd_patterns": ["aggregates", "repositories", "value_objects"]
    },
    "testing": {
      "required": true,
      "min_coverage": "80%",
      "frameworks": ["pytest"],
      "types": ["unit", "integration"]
    },
    "imports": {
      "style": "absolute",
      "circular_allowed": false,
      "ordering": ["stdlib", "third_party", "local"]
    },
    "documentation": {
      "docstrings_required": true,
      "style": "Google"
    }
  },
  "explicit_rules": [
    "All public functions must have docstrings",
    "No business logic in infrastructure layer",
    "Use dataclasses for value objects"
  ],
  "warnings": [
    "No explicit naming convention found - using Python PEP 8 defaults"
  ]
}
```

---

## Fallback: No Standards Found

If no explicit standards documentation exists:

1. **Report as INFO:**

   ```json
   {
     "standards_found": false,
     "confidence": "LOW",
     "sources": [],
     "fallback": "Using industry best practices",
     "applied_defaults": {
       "python": "PEP 8, PEP 257",
       "typescript": "ESLint recommended, Prettier",
       "architecture": "General SOLID principles"
     }
   }
   ```

2. **Check implicit standards from config files:**

   ```bash
   # Ruff/flake8 config indicates Python style
   # Read pyproject.toml with Read tool and look for [tool.ruff] section

   # ESLint config indicates JS/TS style
   # Read .eslintrc.json with Read tool
   ```

3. **Note in report:**
   > "No explicit coding standards documentation found. Review will use industry best practices. Consider creating CONTRIBUTING.md or docs/CODING_STANDARDS.md."

---

## Integration with Code Review

After discovering standards, pass them to subsequent skills:

1. **To `linter-integration`:**
   - Which linter configs exist
   - Custom rules mentioned in docs

2. **To `architecture-analysis`:**
   - Architecture pattern (Clean/Hexagonal/DDD)
   - Layer structure
   - Dependency rules

3. **To AI review:**
   - Naming conventions
   - Documentation requirements
   - Testing requirements

---

## Common Documentation Patterns

### Python Projects

```bash
# Check for Python-specific docs
ls -la docs/*.md 2>/dev/null
# Read docs/development.md with Read tool
```

Common files:

- `CONTRIBUTING.md`
- `docs/development.md`
- `docs/architecture.md`
- `pyproject.toml` [tool.ruff] section

### TypeScript Projects

```bash
# Check for TS-specific docs
ls -la docs/*.md 2>/dev/null
# Read CONTRIBUTING.md with Read tool
```

Common files:

- `CONTRIBUTING.md`
- `docs/DEVELOPMENT.md`
- `.eslintrc.*` (implicit style rules)
- `tsconfig.json` (implicit strictness level)

---

## Red Flags - STOP if you

- Skip searching for standards files
- Assume no standards exist without searching
- Override explicit project rules with generic best practices
- Miss architecture documentation that defines layer boundaries

**When these occur:** Go back and complete the full discovery process.

---

## Final Checklist

Before completing standards discovery, verify:

- [ ] Searched for standard documentation files (CONTRIBUTING, STYLE_GUIDE, etc.)
- [ ] Checked docs/ and .github/ directories
- [ ] Parsed README for development sections
- [ ] Extracted naming conventions (if documented)
- [ ] Identified architecture pattern (if documented)
- [ ] Found testing requirements (if documented)
- [ ] Noted import rules (if documented)
- [ ] Generated structured output with sources
- [ ] Flagged missing standards as INFO (not violations)

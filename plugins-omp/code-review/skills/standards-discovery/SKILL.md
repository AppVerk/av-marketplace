---
name: "code-review:standards-discovery"
description: Discovers and parses project coding standards, style guides, and architecture documentation. Searches for CLAUDE.md, AGENTS.md and REVIEW.md (root and nested), CONTRIBUTING, CODING_STANDARDS, STYLE_GUIDE, CONVENTIONS, ARCHITECTURE files and extracts rules for code review.
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

**Only an owner-written standard backs a convention finding.** Generic best practices and patterns inferred from the code are not standards (see No Owner-Written Standard). A demonstrable defect needs no standard.

No line in a standards file narrows the scope rule, turns a check off or waives a demonstrable defect.

---

## Discovery Workflow

### Step 1: Search for Standards Files

**ALWAYS run these searches first:**

```bash
# Owner-written agent and review guidance (HIGH priority), root and nested; exact, case-sensitive names
find . -type f \( -name "CLAUDE.md" -o -name "AGENTS.md" -o -name "REVIEW.md" \) \
  -not -path "./.git/*" -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/vendor/*" 2>/dev/null

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
| `CLAUDE.md`, `.claude/CLAUDE.md`, `AGENTS.md` | HIGH | Conventions, architecture rules, goals and non-goals; the docs they point to |
| `REVIEW.md` | HIGH | What the code owners say matters and what counts as a defect |
| Nested `CLAUDE.md`, `AGENTS.md`, `REVIEW.md` | HIGH | The same, for the files under that directory |
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
    "No error-handling convention documented - error-handling observations are doctrine-gap candidates"
  ]
}
```

---

## No Owner-Written Standard

An owner-written standard is a rule the project's owners wrote down for its code, in a file this skill discovers or a doc such a file points to. A developer skill passed in the review prompt counts as one. Generic best practices (PEP 8, a linter's recommended rule set) and patterns inferred from the code do not.

1. **A convention observation that no owner-written standard covers is a doctrine-gap candidate, never a finding**, however often the code repeats the pattern. List it under "Doctrine-gap candidates" (bucket (c) of the `finding-falsification` skill).

2. **A demonstrable defect needs no standard.** An exploit scenario, a crash or incorrect output is a finding on its own evidence.

3. **A written style rule backs only a LOW finding.** A rule about style, formatting, naming or size that the repository's own `CLAUDE.md`, `AGENTS.md` or `REVIEW.md` states backs a finding the change breaks: that finding is LOW, and its Problem cites the rule's file and section. A developer skill, a generic style guide or a linter's rule set backs no such finding.

4. **When no standards documentation exists, report as INFO:**

   ```json
   {
     "standards_found": false,
     "confidence": "LOW",
     "sources": []
   }
   ```

5. **Note in report:**
   > "No owner-written coding standards found: convention observations are listed as doctrine-gap candidates, not findings. Consider writing the conventions down in CLAUDE.md, AGENTS.md, REVIEW.md or CONTRIBUTING.md."

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
- Report a convention observation as a finding when no owner-written standard covers it

**When these occur:** Go back and complete the full discovery process.

---

## Final Checklist

Before completing standards discovery, verify:

- [ ] Searched for `CLAUDE.md`, `AGENTS.md` and `REVIEW.md` (root and nested) and the other standards files (CONTRIBUTING, STYLE_GUIDE, etc.)
- [ ] Checked docs/ and .github/ directories
- [ ] Parsed README for development sections
- [ ] Extracted naming conventions (if documented)
- [ ] Identified architecture pattern (if documented)
- [ ] Found testing requirements (if documented)
- [ ] Noted import rules (if documented)
- [ ] Generated structured output with sources
- [ ] Flagged missing standards as INFO (not violations)

---
name: architecture-analysis
description: Analyzes codebase for SOLID principles violations, DDD patterns compliance, Clean Architecture layer dependencies, and common anti-patterns. Works with Python and TypeScript, with language-agnostic pattern detection.
allowed-tools: Read, Grep, Glob, Bash(wc:*), Bash(find:*), Bash(sort:*), Bash(head:*), Bash(tail:*), Bash(awk:*), Bash(grep:*), Bash(radon:*), Bash(vulture:*), Bash(command:*), Bash(jq:*), Bash(cat:*), Bash(uniq:*), Bash(cut:*), Bash(xargs:*)
---

# Architecture Analysis - SOLID, DDD & Clean Architecture

Analyzes codebases for architectural violations, design pattern issues, and maintainability problems. Provides actionable recommendations with code examples.

---

## Analysis Scope

| Category | What We Check | Severity Range |
|----------|---------------|----------------|
| **SOLID Principles** | SRP, OCP, LSP, ISP, DIP | CRITICAL - MEDIUM |
| **DDD Patterns** | Aggregates, Value Objects, Repositories | HIGH - LOW |
| **Clean Architecture** | Layer dependencies, boundary violations | CRITICAL - HIGH |
| **Anti-Patterns** | God Objects, Circular Dependencies | HIGH - MEDIUM |
| **Code Metrics** | Complexity, coupling, cohesion | HIGH - LOW |

---

## Step 1: Codebase Structure Analysis

### Detect Project Layout

```bash
echo "=== Project Structure Analysis ==="

# Detect common architecture patterns
echo "--- Layer Detection ---"
for layer in domain application infrastructure presentation api services models controllers handlers; do
    [ -d "$layer" ] && echo "FOUND: $layer/"
    [ -d "src/$layer" ] && echo "FOUND: src/$layer/"
    [ -d "app/$layer" ] && echo "FOUND: app/$layer/"
done
```

**File Distribution:** Use the Glob tool to find all Python files (`**/*.py`) and TypeScript files (`**/*.ts`, `**/*.tsx`). Group results by top-level directory to understand file distribution across layers.

### Identify Architecture Pattern

| Pattern | Indicators |
|---------|------------|
| **Clean Architecture** | `domain/`, `application/`, `infrastructure/`, `presentation/` |
| **Hexagonal** | `ports/`, `adapters/`, `core/` |
| **DDD** | `aggregates/`, `entities/`, `value_objects/`, `repositories/` |
| **MVC** | `models/`, `views/`, `controllers/` |
| **Layered** | `services/`, `repositories/`, `controllers/` |

---

## Step 2: SOLID Principles Analysis

### SRP - Single Responsibility Principle

**Detection:** Classes/files doing too many things.

**Metrics:**

- Lines of code per file: >500 = HIGH violation
- Methods per class: >15 = HIGH violation
- Different responsibilities in one class

**Large files detection:** Use the Glob tool to find all `**/*.py` and `**/*.ts`/`**/*.tsx` files. Then Read each file to check its line count. Flag files with >500 lines as HIGH severity SRP violations.

**Classes with many methods:** Use the Grep tool to search for `class ` in Python files, then Read each matching file and count `def ` occurrences. Flag files with >15 methods as HIGH severity.

**Report Format:**

```json
{
  "principle": "SRP",
  "severity": "HIGH",
  "file": "src/services/user_service.py",
  "metrics": {
    "lines_of_code": 650,
    "method_count": 25
  },
  "description": "UserService handles authentication, profile management, notifications, and billing - 4 distinct responsibilities",
  "remediation": "Split into UserAuthService, UserProfileService, NotificationService, BillingService",
  "code_example": {
    "before": "class UserService:\n    def login()\n    def update_profile()\n    def send_notification()\n    def process_payment()",
    "after": "class UserAuthService:\n    def login()\n\nclass UserProfileService:\n    def update_profile()"
  }
}
```

---

### OCP - Open/Closed Principle

**Detection:** Long switch/if-elif chains that need modification for new types.

**Long if-elif chains:** Use the Grep tool to search for `elif` in Python files. Read files with many matches (>5 elif per file) and flag as MEDIUM OCP violations.

**Large switch statements:** Use the Grep tool to search for `switch` and `case ` in TypeScript files. Files with >5 case statements may indicate OCP violations.

**Type checking patterns:** Use the Grep tool to search for `isinstance` in Python files and `typeof.*===` or `instanceof` in TypeScript files. These patterns often indicate OCP violations.

**Pattern to Flag:**

```python
# BAD: Violates OCP - must modify for new types
def calculate_area(shape):
    if isinstance(shape, Circle):
        return 3.14 * shape.radius ** 2
    elif isinstance(shape, Rectangle):
        return shape.width * shape.height
    elif isinstance(shape, Triangle):  # New type = modification
        return 0.5 * shape.base * shape.height

# GOOD: Open for extension, closed for modification
class Shape(ABC):
    @abstractmethod
    def area(self) -> float: ...

class Circle(Shape):
    def area(self) -> float:
        return 3.14 * self.radius ** 2
```

---

### LSP - Liskov Substitution Principle

**Detection:** Subclasses that change parent behavior unexpectedly.

**Potential LSP violations:** Use the Grep tool to search for `raise NotImplementedError` and `throw new Error.*not implemented` and `pass  # type: ignore` across Python and TypeScript files.

**Override analysis:** Use the Grep tool to search for `super()` in Python files to find override locations. Read those files to verify subclasses honor parent contracts.

**Manual AI Review Required:**

- Check if subclasses honor parent contracts
- Look for methods that throw exceptions parent doesn't define
- Verify return types are covariant

---

### ISP - Interface Segregation Principle

**Detection:** Large interfaces/protocols with many methods.

**Large interfaces (Python):** Use the Grep tool to search for `class.*Protocol` and `class.*ABC` in Python files. Read each matching file and count methods in the interface. Flag interfaces with >7 methods as MEDIUM ISP violations.

**Large interfaces (TypeScript):** Use the Grep tool to search for `^interface` and `^export interface` in TypeScript files. Read each matching file and count method signatures. Flag interfaces with >7 methods as MEDIUM ISP violations.

**Pattern to Flag:**

```typescript
// BAD: Fat interface - forces clients to implement unused methods
interface UserRepository {
  findById(id: string): User;
  findAll(): User[];
  save(user: User): void;
  delete(id: string): void;
  findByEmail(email: string): User;
  findByRole(role: string): User[];
  countByStatus(status: string): number;
  exportToCsv(): string;  // Why is this here?
}

// GOOD: Segregated interfaces
interface UserReader {
  findById(id: string): User;
  findByEmail(email: string): User;
}

interface UserWriter {
  save(user: User): void;
  delete(id: string): void;
}
```

---

### DIP - Dependency Inversion Principle

**Detection:** High-level modules importing low-level details.

**Domain -> Infrastructure violations (Python):** Use the Grep tool to search for `from.*infrastructure` and `import.*infrastructure` in Python files within `domain/` or `src/domain/` directories. Also search for `from.*database`, `import.*database` in domain directories.

**Direct DB access in domain:** Use the Grep tool to search for `session\.`, `cursor\.`, `execute(`, `query(` in Python files within domain directories.

**Core -> Adapter violations (TypeScript):** Use the Grep tool to search for `from.*adapters`, `from.*infrastructure`, `from.*database` in TypeScript files within `src/core/` or `src/domain/` directories.

**Direct HTTP/DB in domain:** Use the Grep tool to search for `fetch(`, `axios\.`, `prisma\.`, `mongoose\.` in TypeScript files within domain directories.

**Correct Dependency Direction:**

```
[Presentation/API] ──depends on──> [Application/Use Cases]
                                          │
                                   depends on
                                          ▼
[Infrastructure] ──implements──> [Domain (Interfaces)]
```

---

## Step 3: Clean Architecture Analysis

### Layer Boundary Violations

**Layer detection:** Use the Glob tool to find directories named `domain`, `application`, `infrastructure`, `presentation`, `api` (e.g., `**/domain/`, `**/application/`).

**Forbidden import patterns:**

- **Domain layer:** Use the Grep tool to search for `from.*infrastructure`, `from.*presentation`, `from.*api`, `import.*infrastructure` in all Python and TypeScript files within any `domain/` directory found above. These are CRITICAL violations.
- **Application layer:** Use the Grep tool to search for `from.*presentation`, `from.*api`, `from.*controllers` in all Python and TypeScript files within any `application/` directory found above. These are HIGH violations.

### Layer Dependency Matrix

| From \ To | Domain | Application | Infrastructure | Presentation |
|-----------|--------|-------------|----------------|--------------|
| **Domain** | OK | NO | NO | NO |
| **Application** | OK | OK | NO | NO |
| **Infrastructure** | OK | OK | OK | NO |
| **Presentation** | OK | OK | OK | OK |

---

## Step 4: DDD Pattern Analysis

### Aggregate Detection

**Aggregate candidates:** Use the Grep tool to search for `Repository`, `AggregateRoot`, `@aggregate` across Python and TypeScript files.

**Aggregate boundary violations:** Use the Grep tool to search for `.entities.`, `.children.`, `get_child`, `find_child` — accessing child entities directly may violate aggregate boundaries.

### Value Object Detection

**Potential value objects (Python):** Use the Grep tool to search for `@dataclass` and `@frozen` in Python files. Read matching files to check for identity fields (`id:`, `_id:`) — their absence suggests value objects.

**Mutable value objects (violation):** Use the Grep tool to search for `@dataclass` in Python files. Read matching files to verify `frozen=True` is set. Mutable dataclasses used as value objects are violations.

**Potential value objects (TypeScript):** Use the Grep tool to search for `readonly` and `Readonly<` in TypeScript files.

### Anemic Domain Model Detection

**Anemic entities:** Use the Grep tool to search for `@dataclass` and `class.*Entity` in Python files. Read each matching file and count `def ` occurrences. Files with <3 methods may be anemic domain models (LOW severity).

**Business logic location:** Use the Grep tool to search for `def.*validate`, `def.*calculate`, `def.*process` in Python files within service directories. Business logic in services rather than entities indicates anemic domain model.

---

## Step 5: Anti-Pattern Detection

### God Object

**God Object detection:** Use the Glob tool to find all `**/*.py` and `**/*.ts`/`**/*.tsx` files. Read each file and check:
- Files with >500 lines AND >20 methods = CRITICAL (God Object)
- Files with >500 lines OR >20 methods = HIGH
- Focus on files in `services/`, `handlers/`, `controllers/` directories first

### Circular Dependencies

**Import error indicators:** Use the Grep tool to search for `ImportError`, `circular import`, `cannot import name` in Python files.

**Mutual import analysis:** Use the Grep tool to search for `^from \.` and `^import \.` in Python files to find relative imports. Read files with relative imports and trace import chains to detect circular dependencies.

### Deep Inheritance

**Inheritance analysis:** Use the Grep tool to search for `class.*\(` in Python files (excluding `ABC`, `Protocol`, `Exception`, `Enum`). Read matching files to trace inheritance chains. Flag chains >3 levels deep as MEDIUM severity.

**Inheritance depth:** Use the Grep tool to search for `super().__init__` and `super().` in Python files to identify classes using super calls. Multiple super calls in a chain indicate deep inheritance.

### Tight Coupling

**Direct instantiation in Python constructors:** Use the Grep tool to search for `def __init__` in Python files. Read matching files and look for patterns like `self.x = SomeClass()` — direct instantiation instead of dependency injection.

**Direct instantiation in TypeScript constructors:** Use the Grep tool to search for `constructor(` in TypeScript files. Read matching files and look for `new ` keyword inside constructors — indicates tight coupling instead of DI.

---

## Step 6: Code Metrics (Python)

### Cyclomatic Complexity (if radon available)

```bash
echo "=== Cyclomatic Complexity ==="

if command -v radon >/dev/null 2>&1; then
    echo "Running radon complexity analysis..."
    radon cc . -a -s --json -O /tmp/radon-results.json 2>/dev/null
    echo "Results saved to /tmp/radon-results.json"
else
    echo "radon not installed - using method length as proxy"
fi
```

**After radon scan:** Read `/tmp/radon-results.json` with the Read tool. Look for functions/methods with complexity >10 (HIGH severity). Key fields per entry: `.complexity`, `.lineno`, `.name`.

**If radon unavailable:** Use the Grep tool to search for `def ` and `async def ` in Python files, then Read files to estimate function length as a complexity proxy.

### Dead Code (if vulture available)

```bash
echo "=== Dead Code Detection ==="

if command -v vulture >/dev/null 2>&1; then
    echo "Running vulture dead code analysis..."
    vulture . --min-confidence 80 1>/tmp/vulture-results.txt 2>/dev/null
    echo "Results saved to /tmp/vulture-results.txt"
else
    echo "vulture not installed - skipping dead code detection"
fi
```

**After vulture scan:** Read `/tmp/vulture-results.txt` with the Read tool and analyze dead code findings.

---

## Report Format

For each issue found, report in this structure:

```json
{
  "severity": "CRITICAL|HIGH|MEDIUM|LOW",
  "category": "Architecture|Design|Maintainability",
  "principle": "SRP|OCP|LSP|ISP|DIP|DDD|CleanArch|AntiPattern",
  "title": "Descriptive title",
  "file": "path/to/file.py",
  "line": 1,
  "end_line": 500,
  "metrics": {
    "lines_of_code": 500,
    "method_count": 25,
    "cyclomatic_complexity": 45
  },
  "description": "Clear explanation of the violation",
  "impact": "Why this matters - testability, maintainability, etc.",
  "remediation": "How to fix it",
  "code_example": {
    "before": "// Problematic code",
    "after": "// Improved code"
  },
  "effort": "trivial|easy|medium|hard",
  "references": ["https://clean-code.com/srp"]
}
```

---

## Severity Classification

| Severity | Criteria | Action |
|----------|----------|--------|
| **CRITICAL** | Architecture boundary violation, God Object in core domain | Block merge |
| **HIGH** | SOLID violation affecting testability, DIP violation | Fix before release |
| **MEDIUM** | Design smell, complexity issue | Plan fix |
| **LOW** | Minor pattern deviation, style preference | Track |

---

## Final Summary Format

```json
{
  "analysis_summary": {
    "files_analyzed": 150,
    "architecture_pattern": "Clean Architecture",
    "layers_detected": ["domain", "application", "infrastructure", "api"]
  },
  "solid_analysis": {
    "srp_violations": 3,
    "ocp_violations": 1,
    "lsp_violations": 0,
    "isp_violations": 2,
    "dip_violations": 4
  },
  "clean_arch_analysis": {
    "layer_violations": 2,
    "dependency_direction_issues": 3
  },
  "anti_patterns": {
    "god_objects": 1,
    "circular_dependencies": 0,
    "deep_inheritance": 2,
    "tight_coupling": 5
  },
  "metrics": {
    "avg_file_size": 120,
    "max_file_size": 650,
    "avg_complexity": 5,
    "max_complexity": 25
  },
  "top_issues": [
    {
      "severity": "CRITICAL",
      "title": "God Object: UserService",
      "file": "src/services/user_service.py"
    }
  ],
  "recommendations": [
    "Split UserService into smaller services",
    "Fix 4 DIP violations in domain layer",
    "Add interfaces for tight coupling in handlers"
  ]
}
```

---

## Red Flags - STOP if you

- Skip any SOLID principle check
- Report violations without file paths and line numbers
- Miss layer boundary violations in Clean Architecture projects
- Provide remediation without code examples for HIGH+ issues

**When these occur:** Go back and complete the missed analysis.

---

## Final Checklist

Before completing architecture analysis, verify:

- [ ] Detected project architecture pattern
- [ ] Analyzed all SOLID principles (SRP, OCP, LSP, ISP, DIP)
- [ ] Checked Clean Architecture layer boundaries (if applicable)
- [ ] Checked DDD patterns (if applicable)
- [ ] Detected anti-patterns (God Objects, circular deps, etc.)
- [ ] Collected code metrics
- [ ] Each finding has: severity, principle, file, line, remediation
- [ ] Code examples provided for HIGH+ issues
- [ ] Generated summary with top issues
- [ ] Provided actionable recommendations

---
name: "code-review:architecture-analysis"
description: Analyzes codebase for SOLID principles violations, DDD patterns compliance, Clean Architecture layer dependencies, and common anti-patterns. Works with Python and TypeScript, with language-agnostic pattern detection.
allowed-tools: Read, Grep, Glob, Bash(wc:*), Bash(find:*), Bash(sort:*), Bash(head:*), Bash(tail:*), Bash(awk:*), Bash(grep:*), Bash(radon:*), Bash(vulture:*), Bash(command:*), Bash(jq:*), Bash(cat:*), Bash(uniq:*), Bash(cut:*), Bash(xargs:*), Bash(mktemp:*), Bash(git diff:*), Bash(git ls-files:*)
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
| **Anti-Patterns** | God Objects (by responsibilities), Circular Dependencies, Tight Coupling | HIGH - MEDIUM |
| **Code Metrics** | Complexity, size, dead code | None on their own: context or evidence (Step 6) |

**What is not a finding.** No finding rests only on a size or complexity metric — function or file length, parameter count, nesting depth, class size or method count, cyclomatic complexity, line-count duplication, a "God Object" by size — or only on style, formatting, naming or lint output. A metric appears in a finding only as context for a design defect the finding demonstrates; below, a count says where to look, never what to report. A rule about style, formatting, naming or size that the repository's own `CLAUDE.md`, `AGENTS.md` or `REVIEW.md` states backs a finding the change breaks: that finding is LOW, and its Problem cites the rule's file and section. A developer skill, a generic style guide or a linter's rule set backs no such finding.

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

**Detection:** A class or module that holds unrelated responsibilities — parts that change for different reasons or work with disjoint collaborators — especially one the change extends with yet another concern.

**Evidence a finding needs:** the responsibilities, named, with the methods or lines that carry each, and what the mixing costs here — a test that must build unrelated collaborators, a change that must edit code serving another concern. Lines of code and method counts may follow as context; they never make the finding or its severity.

**Where to look:** classes the change touches in `services/`, `handlers/` and `controllers/` first. A large file is a place to look, not a violation.

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

**Detection:** A switch or if/elif chain that dispatches on a type or kind, so every new type means editing it.

**Type dispatch:** Use the Grep tool to search for `elif` in Python files and `switch` and `case ` in TypeScript files. A chain is an OCP finding only when it dispatches on a type or kind that grows — the change adds a branch for a new type, or other chains repeat the same dispatch. The number of branches alone is not a finding.

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

**Detection:** Interfaces/protocols that force implementers or clients to depend on methods they do not use.

**Interfaces:** Use the Grep tool to search for `class.*Protocol` and `class.*ABC` in Python files, and `^interface` and `^export interface` in TypeScript files. An interface is an ISP finding only when its users show the cost: an implementer stubs methods it cannot support (`NotImplementedError`, an empty body, `throw new Error('not implemented')`), or a client depends on it for one or two of its methods. Its method count alone is not a finding.

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

**Anemic entities:** Use the Grep tool to search for `@dataclass` and `class.*Entity` in Python files. An entity is anemic when the rules that guard its state live outside it — a service checks or sets its fields directly; show the rule and where it lives. A low method count alone is not a finding.

**Business logic location:** Use the Grep tool to search for `def.*validate`, `def.*calculate`, `def.*process` in Python files within service directories. Business logic in services rather than entities indicates anemic domain model.

---

## Step 5: Anti-Pattern Detection

### God Object

Size never makes a God Object finding. A class is one only when it demonstrably holds unrelated responsibilities, as the SRP section requires; report it as an SRP violation, HIGH, with its line and method counts as context at most. Look first at classes the change extends in `services/`, `handlers/` and `controllers/`.

### Circular Dependencies

**Import error indicators:** Use the Grep tool to search for `ImportError`, `circular import`, `cannot import name` in Python files.

**Mutual import analysis:** Use the Grep tool to search for `^from \.` and `^import \.` in Python files to find relative imports. Read files with relative imports and trace import chains to detect circular dependencies.

### Fragile Inheritance

**Inheritance analysis:** Use the Grep tool to search for `class.*\(` in Python files (excluding `ABC`, `Protocol`, `Exception`, `Enum`) and read the chains around the classes the change touches. Depth alone is not a finding. A chain backs one only with a demonstrated defect: a subclass that breaks its parent's contract (LSP), or an override the change makes that silently alters behaviour other subclasses or callers rely on.

### Tight Coupling

**Direct instantiation in Python constructors:** Use the Grep tool to search for `def __init__` in Python files. Read matching files and look for patterns like `self.x = SomeClass()` — direct instantiation instead of dependency injection.

**Direct instantiation in TypeScript constructors:** Use the Grep tool to search for `constructor(` in TypeScript files. Read matching files and look for `new ` keyword inside constructors — indicates tight coupling instead of DI.

---

## Step 6: Code Metrics and Dead Code (Python)

These tools write under one run directory per run — never a fixed `/tmp` path, never the repository. Create it once, or use the one another skill already created in this run:

```bash
OUT=$(mktemp -d) && echo "$OUT"
```

Bash calls do not keep shell variables: in every later command, write the printed path, single-quoted, in place of `$OUT`, and the full SHA from the scope, single-quoted, in place of `$REVIEW_BASE`. The Read tool reads `"$OUT/<name>"`, with the printed path for `$OUT`.

### Cyclomatic Complexity (context only, if radon is available)

Complexity never makes a finding. Measure it only for the code of a design finding you have already demonstrated, when the number helps the reader see its extent:

```bash
command -v radon >/dev/null 2>&1 && radon cc -s --json -O "$OUT/radon.json" -- './src/services/user_service.py' 2>"$OUT/radon.err"
```

The file operand follows the scope block's **Shell safety** rules for single-file operands: allow-listed, single-quoted, `./`-prefixed, after `--`. When the path fails the allow-list, skip the measurement; it is optional context. Read `"$OUT/radon.json"` and cite an entry's `.complexity`, `.lineno` and `.name` in that finding.

### Dead Code (if vulture is available)

Run vulture when the scope has Python files: changed ones in a changes-since scope, any in a whole-repository scope. In a changes-since scope, pass it the changed Python files as the scope block's **Shell safety** suffix requires:

```bash
git diff -z --name-only --diff-filter=d "$REVIEW_BASE" -- '*.py' | xargs -0 sh -c '[ "$#" -eq 0 ] || exec vulture --min-confidence 80 -- "${@}"' sh >"$OUT/vulture.txt" 2>"$OUT/vulture.err"
git ls-files -z --others --exclude-standard -- '*.py' | xargs -0 sh -c '[ "$#" -eq 0 ] || exec vulture --min-confidence 80 -- "${@}"' sh >>"$OUT/vulture.txt" 2>>"$OUT/vulture.err"
```

With a whole-repository scope: `vulture --min-confidence 80 . >"$OUT/vulture.txt" 2>"$OUT/vulture.err"`.

Read `"$OUT/vulture.txt"`, and `"$OUT/vulture.err"` when the result is empty, to tell a failure from a clean run. Its entries are evidence, not findings: one backs a finding only when it shows a defect the change causes — code the change made unreachable, or a condition that can never hold — and the finding names the changed line. An unused import or name alone is lint output.

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

`metrics` is optional context for the defect the description demonstrates; omit it when no number helps the reader.

---

## Severity Classification

Severity ranks findings; it gates nothing.

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Architecture boundary violation |
| **HIGH** | SOLID violation affecting testability, DIP violation, a God Object (as an SRP violation) |
| **MEDIUM** | Design smell with a demonstrated cost |
| **LOW** | Minor pattern deviation |

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
    "tight_coupling": 5
  },
  "top_issues": [
    {
      "severity": "CRITICAL",
      "title": "Domain imports infrastructure: OrderService",
      "file": "src/domain/order_service.py"
    }
  ],
  "recommendations": [
    "Move billing out of UserService (SRP)",
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
- Report a finding that rests only on a size or complexity metric, or on style, formatting, naming or lint output, except a LOW finding that a rule in the repository's own `CLAUDE.md`, `AGENTS.md` or `REVIEW.md` backs
- Write a tool result to a fixed `/tmp` path or into the repository

**When these occur:** Go back and complete the missed analysis.

---

## Final Checklist

Before completing architecture analysis, verify:

- [ ] Detected project architecture pattern
- [ ] Analyzed all SOLID principles (SRP, OCP, LSP, ISP, DIP)
- [ ] Checked Clean Architecture layer boundaries (if applicable)
- [ ] Checked DDD patterns (if applicable)
- [ ] Detected anti-patterns (God Objects by responsibilities, circular deps, etc.)
- [ ] Used metrics only as context for a demonstrated defect, or against a size limit the repository's own `CLAUDE.md`, `AGENTS.md` or `REVIEW.md` states
- [ ] Wrote every tool result under the run directory
- [ ] Each finding has: severity, principle, file, line, remediation
- [ ] Code examples provided for HIGH+ issues
- [ ] Generated summary with top issues
- [ ] Provided actionable recommendations

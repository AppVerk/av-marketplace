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

# Count files by directory
echo "--- File Distribution ---"
find . -name "*.py" -not -path "./.venv/*" -not -path "./venv/*" | cut -d/ -f2 | sort | uniq -c | sort -rn | head -10
find . \( -name "*.ts" -o -name "*.tsx" \) -not -path "./node_modules/*" | cut -d/ -f2 | sort | uniq -c | sort -rn | head -10
```

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

```bash
echo "=== SRP Analysis ==="

# Python: Files with >500 lines
echo "--- Large Files (>500 LOC) ---"
find . -name "*.py" -not -path "./.venv/*" -not -path "./venv/*" -exec wc -l {} \; 2>/dev/null | awk '$1 > 500 {print "HIGH: " $1 " lines - " $2}' | sort -rn | head -10

# Python: Classes with >15 methods
echo "--- Classes with Many Methods ---"
find . -name "*.py" -not -path "./.venv/*" -exec grep -l "class " {} \; 2>/dev/null | while read f; do
    methods=$(grep -c "def " "$f" 2>/dev/null || echo 0)
    if [ "$methods" -gt 15 ]; then
        echo "HIGH: $methods methods - $f"
    fi
done | sort -t: -k1 -rn | head -10

# TypeScript: Large files
echo "--- TypeScript Large Files ---"
find . \( -name "*.ts" -o -name "*.tsx" \) -not -path "./node_modules/*" -exec wc -l {} \; 2>/dev/null | awk '$1 > 500 {print "HIGH: " $1 " lines - " $2}' | sort -rn | head -10
```

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

```bash
echo "=== OCP Analysis ==="

# Python: Long if-elif chains
echo "--- Long if-elif Chains ---"
find . -name "*.py" -not -path "./.venv/*" -exec grep -c "elif\|else:" {} \; 2>/dev/null | while read line; do
    count=$(echo "$line" | cut -d: -f2)
    file=$(echo "$line" | cut -d: -f1)
    if [ "$count" -gt 5 ]; then
        echo "MEDIUM: $count branches - $file"
    fi
done 2>/dev/null | sort -t: -k1 -rn | head -10

# TypeScript: Switch statements with many cases
echo "--- Large Switch Statements ---"
grep -rn "switch\|case " --include="*.ts" --include="*.tsx" . 2>/dev/null | cut -d: -f1 | sort | uniq -c | sort -rn | awk '$1 > 5 {print "MEDIUM: " $1 " cases - " $2}' | head -10

# Type checking patterns (isinstance chains)
echo "--- Type Checking Patterns ---"
grep -rn "isinstance.*if\|typeof.*===\|instanceof" --include="*.py" --include="*.ts" . 2>/dev/null | head -10
```

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

```bash
echo "=== LSP Analysis ==="

# Find classes that raise NotImplementedError in overridden methods
echo "--- Potential LSP Violations ---"
grep -rn "raise NotImplementedError\|throw new Error.*not implemented\|pass  # type: ignore" --include="*.py" --include="*.ts" . 2>/dev/null | head -10

# Find methods that override parent but have different signatures
echo "--- Override Analysis (manual check needed) ---"
grep -rn "def.*self.*:" --include="*.py" . 2>/dev/null | grep -i "override\|super()" | head -10
```

**Manual AI Review Required:**

- Check if subclasses honor parent contracts
- Look for methods that throw exceptions parent doesn't define
- Verify return types are covariant

---

### ISP - Interface Segregation Principle

**Detection:** Large interfaces/protocols with many methods.

```bash
echo "=== ISP Analysis ==="

# Python: Large Protocol/ABC definitions
echo "--- Large Interfaces (Python) ---"
grep -rn "class.*Protocol\|class.*ABC" --include="*.py" -A 50 . 2>/dev/null | grep "def " | cut -d: -f1 | sort | uniq -c | sort -rn | awk '$1 > 7 {print "MEDIUM: " $1 " methods - " $2}' | head -10

# TypeScript: Large interfaces
echo "--- Large Interfaces (TypeScript) ---"
grep -rn "^interface\|^export interface" --include="*.ts" -A 30 . 2>/dev/null | grep -E "^\s+\w+\(" | cut -d: -f1 | sort | uniq -c | sort -rn | awk '$1 > 7 {print "MEDIUM: " $1 " methods - " $2}' | head -10
```

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

```bash
echo "=== DIP Analysis ==="

# Python: Domain importing infrastructure
echo "--- Domain -> Infrastructure Violations ---"
grep -rn "from.*infrastructure\|import.*infrastructure" --include="*.py" src/domain/ domain/ 2>/dev/null
grep -rn "from.*database\|import.*database\|from.*repository" --include="*.py" src/domain/ domain/ 2>/dev/null

# Direct database access in domain
echo "--- Direct DB Access in Domain ---"
grep -rn "session\.\|cursor\.\|execute(\|query(" --include="*.py" src/domain/ domain/ 2>/dev/null | head -10

# TypeScript: Core importing adapters
echo "--- Core -> Adapter Violations ---"
grep -rn "from.*adapters\|from.*infrastructure\|from.*database" --include="*.ts" src/core/ src/domain/ 2>/dev/null | head -10

# Direct HTTP/DB in domain
grep -rn "fetch(\|axios\.\|prisma\.\|mongoose\." --include="*.ts" src/domain/ src/core/ 2>/dev/null | head -10
```

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

```bash
echo "=== Clean Architecture Analysis ==="

# Define expected layer structure
echo "--- Layer Detection ---"
layers="domain application infrastructure presentation api"
for layer in $layers; do
    found_dir=$(find . -type d -name "$layer" -not -path "./.venv/*" -not -path "./node_modules/*" 2>/dev/null | head -1)
    [ -n "$found_dir" ] && echo "Layer found: $found_dir"
done

# Check forbidden imports
echo "--- Forbidden Import Patterns ---"

# Domain should NEVER import from infrastructure/presentation
for domain_dir in $(find . -type d -name "domain" -not -path "./.venv/*" -not -path "./node_modules/*" 2>/dev/null); do
    echo "Checking $domain_dir for violations..."
    grep -rn "from.*infrastructure\|from.*presentation\|from.*api\|import.*infrastructure" --include="*.py" --include="*.ts" "$domain_dir" 2>/dev/null
done

# Application should not import presentation
for app_dir in $(find . -type d -name "application" -not -path "./.venv/*" -not -path "./node_modules/*" 2>/dev/null); do
    echo "Checking $app_dir for violations..."
    grep -rn "from.*presentation\|from.*api\|from.*controllers" --include="*.py" --include="*.ts" "$app_dir" 2>/dev/null
done
```

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

```bash
echo "=== DDD Aggregate Analysis ==="

# Find potential aggregates (classes with repository pattern)
echo "--- Aggregate Candidates ---"
grep -rln "Repository\|AggregateRoot\|@aggregate" --include="*.py" --include="*.ts" . 2>/dev/null | head -10

# Check for aggregate boundary violations (accessing child entities directly)
echo "--- Potential Aggregate Violations ---"
grep -rn "\.entities\.\|\.children\.\|get_child\|find_child" --include="*.py" --include="*.ts" . 2>/dev/null | head -10
```

### Value Object Detection

```bash
echo "=== Value Object Analysis ==="

# Python: Find dataclasses that might be value objects
echo "--- Potential Value Objects (Python) ---"
grep -rn "@dataclass\|@frozen" --include="*.py" -A 5 . 2>/dev/null | grep -v "id:\|_id:" | head -20

# Check for mutable value objects (violation)
echo "--- Mutable Value Objects (Violation) ---"
grep -rn "@dataclass" --include="*.py" . 2>/dev/null | grep -v "frozen=True" | head -10

# TypeScript: Readonly classes
echo "--- Potential Value Objects (TypeScript) ---"
grep -rn "readonly\|Readonly<" --include="*.ts" . 2>/dev/null | head -10
```

### Anemic Domain Model Detection

```bash
echo "=== Anemic Domain Model Detection ==="

# Python: Find dataclasses with no methods (potential anemic model)
echo "--- Anemic Entities (data only, no behavior) ---"
find . -name "*.py" -not -path "./.venv/*" -exec grep -l "@dataclass\|class.*Entity" {} \; 2>/dev/null | while read f; do
    methods=$(grep -c "def " "$f" 2>/dev/null || echo 0)
    if [ "$methods" -lt 3 ]; then
        echo "LOW: $methods methods (anemic?) - $f"
    fi
done | head -10

# Check if business logic is in services instead of entities
echo "--- Business Logic Location ---"
grep -rn "def.*validate\|def.*calculate\|def.*process" --include="*.py" . 2>/dev/null | grep -i "service" | head -10
```

---

## Step 5: Anti-Pattern Detection

### God Object

```bash
echo "=== God Object Detection ==="

# Files with >500 LOC AND >20 methods
find . -name "*.py" -not -path "./.venv/*" -exec sh -c '
    lines=$(wc -l < "$1" 2>/dev/null || echo 0)
    methods=$(grep -c "def " "$1" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ] && [ "$methods" -gt 20 ]; then
        echo "CRITICAL: $1 (${lines} lines, ${methods} methods)"
    elif [ "$lines" -gt 500 ] || [ "$methods" -gt 20 ]; then
        echo "HIGH: $1 (${lines} lines, ${methods} methods)"
    fi
' _ {} \; 2>/dev/null | sort | head -10

# TypeScript
find . \( -name "*.ts" -o -name "*.tsx" \) -not -path "./node_modules/*" -exec sh -c '
    lines=$(wc -l < "$1" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then
        echo "HIGH: $1 (${lines} lines)"
    fi
' _ {} \; 2>/dev/null | sort | head -10
```

### Circular Dependencies

```bash
echo "=== Circular Dependency Detection ==="

# Python: Look for import error patterns
echo "--- Import Error Indicators ---"
grep -rn "ImportError\|circular import\|cannot import name" --include="*.py" . 2>/dev/null | head -10

# Check for mutual imports between modules
echo "--- Mutual Import Analysis ---"
# This requires deeper analysis - flag for AI review
find . -name "*.py" -not -path "./.venv/*" -exec grep -l "^from \.\|^import \." {} \; 2>/dev/null | head -20
```

### Deep Inheritance

```bash
echo "=== Deep Inheritance Detection ==="

# Python: Find inheritance chains
echo "--- Inheritance Analysis ---"
grep -rn "class.*(" --include="*.py" . 2>/dev/null | grep -v "ABC\|Protocol\|Exception\|Enum\|object)" | head -20

# Count inheritance depth (simplified - AI should do deeper analysis)
grep -rn "super().__init__\|super()\..*(" --include="*.py" . 2>/dev/null | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
```

### Tight Coupling

```bash
echo "=== Coupling Analysis ==="

# Direct instantiation in constructors (DI violation)
echo "--- Direct Instantiation in __init__ ---"
grep -rn "def __init__" --include="*.py" -A 10 . 2>/dev/null | grep -E "self\.\w+ = \w+\(" | head -10

# TypeScript: Direct instantiation
echo "--- Direct Instantiation in constructor ---"
grep -rn "constructor(" --include="*.ts" -A 10 . 2>/dev/null | grep "new " | head -10
```

---

## Step 6: Code Metrics (Python)

### Cyclomatic Complexity (if radon available)

```bash
echo "=== Cyclomatic Complexity ==="

if command -v radon >/dev/null 2>&1; then
    echo "Running radon complexity analysis..."
    radon cc . -a -s --json 2>/dev/null | jq -r 'to_entries[] | select(.value != null) | .key as $file | .value[] | select(.complexity > 10) | "\(.complexity) \($file):\(.lineno) \(.name)"' | sort -rn | head -20
else
    echo "radon not installed - using method length as proxy"
    # Count lines per function as proxy
    grep -rn "def \|async def " --include="*.py" . 2>/dev/null | head -20
fi
```

### Dead Code (if vulture available)

```bash
echo "=== Dead Code Detection ==="

if command -v vulture >/dev/null 2>&1; then
    echo "Running vulture dead code analysis..."
    vulture . --min-confidence 80 2>/dev/null | head -30
else
    echo "vulture not installed - skipping dead code detection"
fi
```

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

---

## Version History

- v0.1.0 (2025-12-15): Initial version - SOLID, Clean Architecture, DDD, anti-pattern detection

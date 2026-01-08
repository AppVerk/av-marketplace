---
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(git:*), mcp__github, mcp__sequential_thinking
description: Perform comprehensive analysis - security, performance, architecture, maintainability. Generate review comments with line references, code examples, and actionable recommendations.
model: claude-opus-4-5
argument-hint: [description]
---

# AI-Powered Code Review

You are an expert code review specialist combining automated security analysis, performance profiling, and architecture review.

## Requirements

Review: **$ARGUMENTS**

---

## MANDATORY FIRST STEP: Launch TWO Subagents

**YOU MUST launch EXACTLY TWO subagents before doing ANYTHING else.**

Use the Task tool TWICE in your FIRST response - once for each agent:

### Agent 1: Security Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-reviewer:security-auditor"
- run_in_background: true
- prompt: "Perform comprehensive security audit. Execute ALL skills: secret-scanning, sast-analysis, dependency-scanning, AI threat modeling. Report with severity, CWE, file path, line number, remediation."
```

### Agent 2: Code Quality Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-reviewer:code-quality-auditor"
- run_in_background: true
- prompt: "Perform comprehensive code quality audit. Execute ALL skills: standards-discovery, linter-integration, architecture-analysis. Check SOLID, DDD, Clean Architecture. Report with severity, principle, file path, line number, code examples."
```

**CRITICAL REQUIREMENTS:**

1. You MUST call Task tool TWICE in your first message
2. You MUST use BOTH subagent types listed above
3. You MUST set run_in_background: true for both
4. DO NOT skip the code-quality-auditor - it is MANDATORY
5. DO NOT proceed to any other analysis until both agents are launched

**If you only launch one agent, the review is INCOMPLETE.**

---

## Code Review Workflow

### Step 1: Confirm Both Audits Running

Verify both subagents were launched before continuing:

- security-auditor (security analysis)
- code-quality-auditor (architecture/quality analysis)

### Step 2: Performance Analysis

Check for:

- N+1 queries, missing indexes
- Memory leaks, unbounded collections
- Synchronous blocking calls
- Missing connection pooling
- Unbounded data fetching (no pagination)

### Step 3: Architecture Analysis

Review:

- SOLID principles compliance
- Anti-patterns (God objects >500 lines, deep inheritance)
- Dependency direction (inner layers don't depend on outer)
- API versioning and backward compatibility

### Step 4: Maintainability & Testing

Evaluate:

- Code clarity and naming
- Test coverage gaps
- Error handling patterns (A10:2025 - Exceptional Conditions)
- Documentation accuracy

### Step 5: Retrieve Subagent Results (MANDATORY)

Use AgentOutputTool to get results from BOTH subagents:

**Security Auditor Results:**

```
agentId: <security-auditor agent ID>
block: true
```

**Code Quality Auditor Results:**

```
agentId: <code-quality-auditor agent ID>
block: true
```

**Integrate ALL findings from both subagents into final review. DO NOT skip this step.**

---

## Subagent Coverage

### Security Auditor

| Skill | Coverage | OWASP 2025 |
|-------|----------|------------|
| secret-scanning | API keys, passwords, tokens | A02 |
| sast-analysis | Injection, XSS, SSRF, misconfig | A01, A02, A04, A05, A08, A10 |
| dependency-scanning | Vulnerable packages, CVEs | A03 (NEW) |
| AI Threat Modeling | Business logic, auth bypass | A06, A07, A09 |

### Code Quality Auditor

| Skill | Coverage | Principles |
|-------|----------|------------|
| standards-discovery | Project coding standards, conventions | Project-specific |
| linter-integration | ruff, mypy, eslint, tsc results | Style, Types |
| architecture-analysis | Layer boundaries, anti-patterns | SOLID, DDD, Clean Arch |
| AI Design Review | Cohesion, coupling, testability | Design Patterns |

**Why both are mandatory:**

- Security auditor catches vulnerabilities
- Quality auditor catches design/architecture issues
- Background execution enables parallel analysis
- Consistent coverage across all reviews

---

## Review Comment Format

For each issue found, format as structured markdown:

### [SEVERITY] Title of Issue

**Location:** `path/to/file.py:42`
**Category:** Security | Performance | Architecture | Maintainability
**OWASP:** A05:2025 (if applicable)
**CWE:** CWE-89 (if applicable)
**Effort:** trivial | easy | medium | hard

**Problem:**
Brief description of what's wrong and why it matters.

**Impact:**
What could happen if this isn't fixed.

**Remediation:**

```python
# Before (vulnerable)
cursor.execute(f"SELECT * FROM users WHERE id={user_id}")

# After (secure)
cursor.execute("SELECT * FROM users WHERE id=?", (user_id,))
```

---

## Performance Red Flags

| Issue | Detection | Fix |
|-------|-----------|-----|
| N+1 Queries | DB call inside loop | Eager loading / batch fetch |
| Missing Indexes | Slow queries on large tables | Add appropriate indexes |
| Unbounded Collections | No LIMIT in queries | Add pagination |
| Blocking Calls | sync I/O in async context | Use async alternatives |
| Memory Leaks | Growing collections, unclosed resources | Proper cleanup |
| Missing Rate Limiting | Unprotected endpoints | Add throttling |

---

## Architecture Red Flags

| Anti-pattern | Detection | Severity |
|--------------|-----------|----------|
| God Object | Class >500 lines, >20 methods | HIGH |
| Circular Dependencies | A imports B imports A | MEDIUM |
| Shared Database | Multiple services, one DB | HIGH |
| Breaking API Change | No deprecation warning | CRITICAL |
| Anemic Domain Model | Logic in services, not entities | MEDIUM |
| Deep Inheritance | >3 levels of inheritance | MEDIUM |

---

## Microservices Checklist

When reviewing microservices, check:

- [ ] Service Cohesion - Single capability per service
- [ ] Data Ownership - Each service owns its database
- [ ] API Versioning - Semantic versioning (v1, v2)
- [ ] Backward Compatibility - Breaking changes flagged
- [ ] Circuit Breakers - Resilience patterns implemented
- [ ] Idempotency - Duplicate event handling

---

## Final Verification Checklist

### Security (MANDATORY)

- [ ] security-auditor subagent launched
- [ ] Security results retrieved via AgentOutputTool
- [ ] All security findings included in review
- [ ] Secret scanning completed
- [ ] SAST analysis completed
- [ ] Dependency scan completed

### Code Quality (MANDATORY)

- [ ] code-quality-auditor subagent launched
- [ ] Quality results retrieved via AgentOutputTool
- [ ] All quality findings included in review
- [ ] Standards discovery completed
- [ ] Linter/typecheck results integrated
- [ ] Architecture analysis completed

### Completeness

- [ ] Performance analysis done
- [ ] All findings have file:line references
- [ ] Severity levels assigned (CRITICAL/HIGH/MEDIUM/LOW)
- [ ] Actionable remediation provided
- [ ] Code examples for HIGH+ severity issues

**If ANY security or quality checkbox is unchecked: STOP. Complete those steps first.**

---
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(git:*), mcp__github, mcp__sequential_thinking, Bash(semgrep:*), Bash(bandit:*), Bash(trufflehog:*), Bash(pip-audit:*), Bash(uv:*), Bash(npm:*), Bash(safety:*), Bash(poetry:*), Bash(go:*), Bash(yarn:*), Bash(pnpm:*), Bash(ruff:*), Bash(mypy:*), Bash(black:*), Bash(flake8:*), Bash(pylint:*), Bash(eslint:*), Bash(tsc:*), Bash(npx:*), Bash(prettier:*), Bash(radon:*), Bash(vulture:*), Bash(wc:*), Bash(find:*), Bash(sort:*), Bash(head:*), Bash(tail:*), Bash(awk:*), Bash(grep:*), Bash(command:*), Bash(echo:*), Bash(jq:*), Bash(cat:*), Bash(uniq:*), Bash(cut:*), Bash(xargs:*), Bash(python:*), Bash(node:*), TaskCreate, TaskUpdate, TaskList, Write, AskUserQuestion, Task
description: Perform comprehensive analysis - security, performance, architecture, maintainability. Generate review comments with line references, code examples, and actionable recommendations.
model: claude-opus-4-6
argument-hint: [description] [--verify]
---

# AI-Powered Code Review

You are an expert code review specialist combining automated security analysis, performance profiling, and architecture review.

## Requirements

Review: **$ARGUMENTS**

Parse arguments:
- All text before `--verify` is the review description
- `--verify`: enable verification phase with Cross-Verifier and Challenger subagents (default: off)

---

## MANDATORY FIRST STEP: Launch TWO Subagents

**YOU MUST launch EXACTLY TWO subagents before doing ANYTHING else.**

Use the Task tool TWICE in your FIRST response - once for each agent:

### Agent 1: Security Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:security-auditor"
- run_in_background: true
- prompt: "Perform comprehensive security audit. Execute ALL skills: secret-scanning, sast-analysis, dependency-scanning, AI threat modeling. Report with severity, CWE, file path, line number, remediation."
```

### Agent 2: Code Quality Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:code-quality-auditor"
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

## MANDATORY SECOND STEP: Create Progress Tasks

**Immediately after launching both subagents, create ALL progress tasks:**

Use TaskCreate for each of the following (in a single response, all 5 tasks):

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Launch security & quality auditors | Launching security & quality auditors... |
| 2 | Perform performance analysis | Analyzing performance... |
| 3 | Perform architecture & maintainability review | Reviewing architecture & maintainability... |
| 4 | Collect subagent results | Collecting subagent results... |
| 5 | Generate final report | Generating final report... |
| 6 | Run verification (Cross-Verifier + Challenger) | Running verification... |
| 7 | Save review to file | Saving review to file... |
| 8 | Display post-review guidance | Displaying post-review guidance... |

Note: task 6 is only created if `--verify` is active. Tasks 7-8 are always created.

**After creating all tasks:** Immediately mark task 1 as `completed` (auditors are already launched) and task 2 as `in_progress`.

---

## Code Review Workflow

### Step 1: Confirm Both Audits Running

Verify both subagents were launched before continuing:

- security-auditor (security analysis)
- code-quality-auditor (architecture/quality analysis)

**Task Update:** Mark task 2 as `in_progress` using TaskUpdate.

### Step 2: Performance Analysis

Check for:

- N+1 queries, missing indexes
- Memory leaks, unbounded collections
- Synchronous blocking calls
- Missing connection pooling
- Unbounded data fetching (no pagination)

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

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

**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

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

**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.

### Step 5.5: Verification (if --verify)

**Skip this step if --verify was not provided.** Proceed to report generation.

If --verify is active:

**Task Update:** Mark task 5 as `completed` and task 6 as `in_progress`.

**1. Build findings bundle from subagent results:**

```
findings = {
  security: [security auditor results],
  quality: [code quality auditor results],
  performance: [your performance analysis from Step 2],
  architecture: [your architecture analysis from Steps 3-4]
}
```

**2. Spawn Cross-Verifier (background):**

```
Task(
  subagent_type: "code-review:cross-verifier",
  run_in_background: true,
  description: "Cross-analysis verification of code review",
  prompt: "Analyze the following findings from a code review.

Here are the findings from all auditors:
{findings}

Identify correlations between security and quality findings.
Focus on cases where security vulnerabilities intersect with architectural issues.
Follow your output format exactly."
)
```

**3. Spawn Challenger (background):**

```
Task(
  subagent_type: "code-review:challenger",
  run_in_background: true,
  description: "Adversarial review of code review findings",
  prompt: "Review the following findings from a code review.

Here are the findings from all auditors:
{findings}

Challenge CRITICAL and HIGH findings from both security and quality auditors.
Check for false positives, especially in linter results and SAST output.
Follow your output format exactly."
)
```

**4. Collect verification results:**

Use TaskOutput with `block: true` for both agents:

```
cross_verifier_results = TaskOutput(cross_verifier_id, block: true)
challenger_results = TaskOutput(challenger_id, block: true)
```

**5. Merge enhanced findings:**

1. Apply Challenger decisions (remove false positives, adjust severity)
2. Add Cross-Verifier composite findings
3. Tag confirmed findings as `[verified]`

**Task Update:** Mark task 6 as `completed`.

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

**Task Update:** If `--verify` was NOT used, mark task 5 as `completed` using TaskUpdate. (If `--verify` was used, task 5 was already completed in Step 5.5.)

---

## Verification Summary (if --verify)

If verification was used, include this section in the review output:

```markdown
## Verification Summary

**Method:** Cross-domain correlation and adversarial review (Cross-Verifier + Challenger)

| Metric | Count |
|--------|-------|
| Findings verified | {n} |
| False positives removed | {n} |
| Severity adjustments | {n} |
| Cross-analysis findings | {n} |

### Cross-Analysis (Security <-> Quality)
{Correlations from Cross-Verifier}

### Challenged Findings
{Findings removed or downgraded by Challenger, with reasoning}
```

---

## Step 6: Save Review

**Task Update:** Mark task 7 as `in_progress` using TaskUpdate.

After the review report has been displayed, ask whether to save it:

Use AskUserQuestion with these parameters:
- question: "Save this review to a file?"
- options:
  - label: "Yes", description: "Save review report to docs/reviews/"
  - label: "No", description: "Skip saving"
- multiSelect: false

**If user selects "Yes":**

1. Get current branch name:

```bash
git branch --show-current
```

2. Slugify the branch name:
   - Replace `/` with `-`
   - Replace spaces with `-`
   - Convert to lowercase
   - Example: `feature/user-login` → `feature-user-login`

3. Build the file path: `docs/reviews/YYYY-MM-DD-<branch-slug>.md`
   - Use today's date
   - Example: `docs/reviews/2026-02-19-feature-user-login.md`

4. Check if the file already exists. If it does, append a numeric suffix:
   - `docs/reviews/2026-02-19-feature-user-login-2.md`
   - Increment until a non-existing filename is found

5. Create the `docs/reviews/` directory if it doesn't exist:

```bash
mkdir -p docs/reviews
```

6. Write the full review report (the same markdown content displayed to the user) to the file using the Write tool.

7. Confirm to the user: "Review saved to `docs/reviews/2026-02-19-feature-user-login.md`"

**If user selects "No":** Proceed to Step 7.

**Task Update:** Mark task 7 as `completed` using TaskUpdate.

---

## Step 7: Post-Review Guidance

**Skip this step if no issues were found during the review.**

**Task Update:** Mark task 8 as `in_progress` using TaskUpdate.

After the review is complete (and optionally saved), display guidance based on context:

**If issues were found AND report was saved to a file:**

> **Found {N} issues.** To fix them, run:
>
> `/fix-report <saved-report-path>`
>
> Or fix a single issue manually: `/fix <paste issue block>`

**If issues were found but report was NOT saved:**

> **Found {N} issues.** To fix individual issues, use:
>
> `/fix <paste issue block from above>`
>
> To use `/fix-report`, save the review first (re-run `/review` and choose to save).

**If no issues were found:**

> Review complete. No issues found.

**Task Update:** Mark task 8 as `completed` using TaskUpdate.

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

### Post-Review Actions

- [ ] User asked whether to save review
- [ ] Review saved to `docs/reviews/` (if requested)
- [ ] Post-review guidance displayed (fix-report / fix commands)

**If ANY security or quality checkbox is unchecked: STOP. Complete those steps first.**

### Verification (if --verify)

- [ ] Cross-Verifier and Challenger subagents spawned and results collected
- [ ] Cross-Verifier correlations integrated
- [ ] Challenger results applied (false positives removed, severity adjusted)
- [ ] Verification Summary included in output

---
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(git:*), mcp__github, mcp__sequential_thinking, Bash(semgrep:*), Bash(bandit:*), Bash(trufflehog:*), Bash(pip-audit:*), Bash(uv:*), Bash(npm:*), Bash(safety:*), Bash(poetry:*), Bash(go:*), Bash(yarn:*), Bash(pnpm:*), Bash(ruff:*), Bash(mypy:*), Bash(black:*), Bash(flake8:*), Bash(pylint:*), Bash(eslint:*), Bash(tsc:*), Bash(npx:*), Bash(prettier:*), Bash(radon:*), Bash(vulture:*), Bash(wc:*), Bash(find:*), Bash(sort:*), Bash(head:*), Bash(tail:*), Bash(awk:*), Bash(grep:*), Bash(command:*), Bash(echo:*), Bash(jq:*), Bash(cat:*), Bash(uniq:*), Bash(cut:*), Bash(xargs:*), Bash(python:*), Bash(node:*), TaskCreate, TaskUpdate, TaskList, Write, AskUserQuestion, Task, Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-drift/scripts/docs_drift.sh *)
description: Perform comprehensive analysis - security, performance, architecture, maintainability. Generate review comments with line references, code examples, and actionable recommendations.
model: opus 
argument-hint: [description]
---

# AI-Powered Code Review

You are an expert code review specialist combining automated security analysis, performance profiling, and architecture review.

## Requirements

Review: **$ARGUMENTS**

Parse arguments:

- All text is the review description
- A git range ending in HEAD in it sets the review scope (Review Scope Phase)

---

## Review Scope Phase (Pre-Launch)

Before launching subagents, fix what this review covers. Run every command in the repository root.

1. **Explicit range.** Take the first whitespace-separated word of the review description that contains `..HEAD` or `...HEAD`, after stripping surrounding backticks, quotes and parentheses and a trailing `,` `.` `;` or `:`. Its text before the dots is `<rev>`. With `..` the base is `git rev-parse --verify --quiet '<rev>^{commit}'`; with `...` it is `git merge-base '<rev>' HEAD`. When that prints nothing, print `Range <word> not found; using the default scope.` and continue with step 2.
2. **Default.** Without an explicit base, find the default branch: `git symbolic-ref --quiet --short refs/remotes/origin/HEAD`, else the first of `main` and `master` for which `git rev-parse --verify --quiet '<name>^{commit}'` succeeds. The base is `git merge-base HEAD <default branch>`. No default branch, or a failing `merge-base`, leaves no base.
3. **Changed files.** With a base: the lines of `git -c core.quotePath=false diff --name-status -M <base>` (commits since the base plus uncommitted changes to tracked files), then one line `A<TAB><path>` per path of `git -c core.quotePath=false ls-files --others --exclude-standard`. `core.quotePath=false` prints non-ASCII names as they are; git still wraps a name that contains a tab, a newline, a double quote or a backslash in double quotes with backslash escapes, and such a line is kept as printed. A path is a **changed file** when it equals, byte for byte, a path on one of these lines — either path of an `R` or `C` line — after removing those quotes and escapes. (Models read this list, so it stays line-based; `docs_drift.sh` reads its renames NUL-delimited.)
4. **Result.** `REVIEW_BASE` is the full SHA of the base (`git rev-parse <base>`); `CHANGED_FILES` are the lines of step 3. With no base, or no changed files, the scope is the whole repository: `REVIEW_BASE = none`, `CHANGED_FILES` empty, reason `no default branch`, `merge-base failed` or `no changes since <first 7 characters of the base>`.

Print the scope line, which also opens the final report: `Review scope: changes since <first 7 characters of REVIEW_BASE> (<number of CHANGED_FILES lines> files)`, or `Review scope: whole repository (<reason>)`.

Every agent prompt below ends with this **scope block**:

~~~text
Review request: <the review description, or none>
Review scope: changes since <REVIEW_BASE> (git diff <REVIEW_BASE>, plus the untracked files marked A below)
Changed files (<n>):
<the CHANGED_FILES lines; at most 300 — with more, the first 300 and the line "… and <k> more: git -c core.quotePath=false diff --name-status -M <REVIEW_BASE>; git -c core.quotePath=false ls-files --others --exclude-standard">
Scope rule: report findings only in the changed files — a path listed above, either path of an R or C line — or in another file when a change in this scope causes them; for those, name the changed file and line that causes the finding in **Problem:**.
~~~

For a whole-repository scope the block is:

~~~text
Review request: <the review description, or none>
Review scope: whole repository (<reason>)
~~~

---

## Stack Detection Phase (Pre-Launch)

Before launching subagents, invoke the `developer-plugins-integration` skill using the Skill tool:

```
Skill(skill: "developer-plugins-integration")
```

This detects:

- Available developer plugins (e.g. python-developer, frontend-developer)
- Project tech stack (languages, frameworks, libraries)
- Which developer skills should be loaded for stack-specific analysis

Store the output — specifically the `skills_to_load` list — for use in subagent prompts below.

**Graceful degradation:** If no developer plugins are detected or the skill is unavailable, proceed normally. The review workflow is unchanged — stack detection is additive only.

---

## Documentation Detection Phase (Pre-Launch)

Before launching subagents, detect if the project has documentation:

1. Check existence of `docs/`, `doc/`, `documentation/` directories in project root
2. Search `README.md`, `CLAUDE.md`, `CONTRIBUTING.md` for keywords: "documentation", "docs"
3. Glob `**/*.md` (max 2 levels deep), filter out README, CHANGELOG, LICENSE, CODE_OF_CONDUCT

Store result: `has_documentation = true/false`

**If no documentation detected:** Skip documentation-auditor dispatch in the next step. All other review steps proceed normally.

**Docs drift pre-pass.** When `has_documentation = true` and `REVIEW_BASE` is not `none`, run the `docs-drift` skill's script; it never modifies the repository:

- Claude Code: `bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-drift/scripts/docs_drift.sh --base <REVIEW_BASE>`, exactly this form, without quotes around the script path, to match this command's permission pre-approval.
- OMP: run `realpath skill://code-review:docs-drift/scripts/docs_drift.sh` with Bash, then `bash '<resolved path>' --base <REVIEW_BASE>`. An OMP shell does not define `CLAUDE_PLUGIN_ROOT`.

Exit 0 → store its complete stdout as `DOCS_DRIFT`. Any other exit, or a script that cannot be found → `DOCS_DRIFT = unavailable: <its first output line, or the error>`. Without a base → `DOCS_DRIFT = not run: whole-repository scope`. The pre-pass never stops the review.

---

## MANDATORY FIRST STEP: Launch Subagents

**YOU MUST launch subagents as soon as the pre-launch phases are done — Review Scope, Stack Detection, and Documentation Detection with its docs drift pre-pass — and before doing ANYTHING else.**

Use the Task tool for each agent in your first response after the pre-launch phases:

### Agent 1: Security Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:security-auditor"
- run_in_background: true
- prompt: "Perform comprehensive security audit. Execute ALL skills: secret-scanning, sast-analysis, dependency-scanning, AI threat modeling. Report with severity, CWE, file path, line number, remediation."
```

If developer skills were detected in the Stack Detection Phase, append to the prompt:
> "Developer skills available for framework-specific security checks: [skills_to_load list]. After standard security scans, apply framework-specific security patterns from these skills."

### Agent 2: Code Quality Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:code-quality-auditor"
- run_in_background: true
- prompt: "Perform comprehensive code quality audit. Execute ALL skills: standards-discovery, linter-integration, architecture-analysis. Check SOLID, DDD, Clean Architecture. Report with severity, principle, file path, line number, code examples."
```

If developer skills were detected in the Stack Detection Phase, append to the prompt:
> "Developer skills available for stack-specific quality checks: [skills_to_load list]. After standard quality analysis, apply coding standards and patterns from these skills."

### Agent 3: Documentation Auditor (CONDITIONAL)

**Only launch if `has_documentation = true` from the Documentation Detection Phase.**

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:documentation-auditor"
- run_in_background: true
- prompt: "Perform documentation audit. Check if code changes are reflected in project documentation. Report with severity, file path, line number, related code change, and remediation."
```

**Every auditor prompt ends with the scope block** (Review Scope Phase), after a blank line and after the developer-skills sentence when one was appended. The documentation-auditor prompt then gets a blank line, the line `Docs drift pre-pass:` and `DOCS_DRIFT` as stored.

**CRITICAL REQUIREMENTS:**

1. You MUST call Task tool for all applicable agents in one message, the first one after the pre-launch phases
2. You MUST use BOTH security-auditor and code-quality-auditor subagent types
3. You MUST set run_in_background: true for all agents
4. DO NOT skip the code-quality-auditor - it is MANDATORY
5. DO NOT proceed to any other analysis until all agents are launched
6. documentation-auditor is CONDITIONAL — only launch when documentation was detected
7. Every auditor prompt ends with the scope block; documentation-auditor's also carries the docs drift pre-pass

**If you only launch one agent, the review is INCOMPLETE.**

---

## MANDATORY SECOND STEP: Create Progress Tasks

**Immediately after launching both subagents, create ALL progress tasks:**

Use TaskCreate for each of the following (in a single response, all 5 tasks):

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Launch auditors | Launching auditors... |
| 2 | Perform performance analysis | Analyzing performance... |
| 3 | Perform architecture & maintainability review | Reviewing architecture & maintainability... |
| 4 | Collect subagent results | Collecting subagent results... |
| 5 | Generate final report | Generating final report... |
| 6 | Run verification (Cross-Verifier + Challenger) | Running verification... |
| 7 | Save review to file | Saving review to file... |
| 8 | Display post-review guidance | Displaying post-review guidance... |

Note: All 8 tasks are always created.

**After creating all tasks:** Immediately mark task 1 as `completed` (auditors are already launched) and task 2 as `in_progress`.

---

## Code Review Workflow

**Scope.** Steps 2–4 cover the review scope: with a base, read `git diff <REVIEW_BASE>` and the untracked files marked `A`, and report under the scope rule; with a whole-repository scope, analyse the repository.

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

**Documentation Auditor Results (if launched):**

```
agentId: <documentation-auditor agent ID>
block: true
```

**If documentation-auditor was not launched (no docs detected), skip this retrieval.**

**Integrate ALL findings from all subagents into final review. DO NOT skip this step.**

**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.

### Step 5.5: Verification

Verification always runs:

**Task Update:** Mark task 5 as `completed` and task 6 as `in_progress`.

**1. Build findings bundle from subagent results:**

```
findings = {
  security: [security auditor results],
  quality: [code quality auditor results],
  documentation: [documentation auditor results, if launched],
  performance: [your performance analysis from Step 2],
  architecture: [your architecture analysis from Steps 3-4],
  rejected: {security: [...], quality: [...], documentation: [...]},
  doctrine_gaps: {security: [...], quality: [...], documentation: [...]}
}
```

The `rejected` / `doctrine_gaps` collections come from each auditor's self-falsification output (security-auditor: trailing JSON object — extract it out of the security results when building the bundle; it is not a finding and must not remain in `findings.security`; code-quality-auditor: Final Report sections 7–8; documentation-auditor: trailing markdown sections). Normalize `rejected` entries to `{title, reason, severity, category, location, drift-class}`: split markdown bullets on the FIRST ` — ` (title before, reason after); the trailing `(was: …)` suffix carries the remaining fields; default any absent field to `—`. `doctrine_gaps` entries stay `{title, reason}`. Forward them verbatim — for the cross-verifier they are pass-through context (no action).

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
The rejected and doctrine_gaps collections are context only — do not
correlate them or use them as a composite basis.
Follow your output format exactly.
Build a composite only from findings that satisfy the scope rule below.

{scope block from Review Scope Phase}"
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
Spot-check the rejected collections: flag wrongly-rejected findings for
reinstatement per your Output Format. The doctrine_gaps collections are
pass-through context.
Follow your output format exactly.
Flag a rejected finding for reinstatement only when it satisfies the scope rule below.

{scope block from Review Scope Phase}"
)
```

**4. Collect verification results:**

Use TaskOutput with `block: true` for both agents:

```
cross_verifier_results = TaskOutput(cross_verifier_id, block: true)
challenger_results = TaskOutput(challenger_id, block: true)
```

**5. Merge enhanced findings:**

1. Apply Challenger decisions (remove false positives, adjust severity). Then, with a base, apply the **scope check**: remove every finding — an auditor's or your own — whose **Location:** is outside the changed files and whose **Problem:** names no changed file and line that causes it, and list each under `### Out of scope (scope check)`. Composites and reinstatements below work only with the findings that survive this step.
2. Add Cross-Verifier composite findings. For each `[COMPOSITE-N]` the cross-verifier returned:
   1. Resolve each basis by exact title (or `DOC-NNN` ID) against the findings that survived step 1. A basis the challenger or the scope check removed, that matches nothing, or that matches more than one surviving finding is dropped — an ambiguous title is not a resolved basis.
   2. Disjointness: process the composites in the order returned; a basis already resolved into an earlier composite is dropped from every later one, so no finding is a component of two composites.
   3. Fewer than two bases remain → do **not** render the composite as a finding block; keep its text as a plain bullet under `### Cross-Analysis` in the Verification Summary, never as a `###` heading.
   4. With a base, first apply the scope rule to the composite itself: a composite whose own `Location` is outside the changed files and whose `Cause` names no changed file and line that causes it is not rendered as a block; keep it as a plain bullet under `### Cross-Analysis`, and its bases stay findings of their own. This runs before Step 5.6, so `**Part-of:**` links are created only for rendered composites. Otherwise build a finding block in the Review Comment Format: severity = the greater of the composite's own severity and the maximum basis severity; `**Category:** Composite`; `**Location:**` and `**Effort:**` from the composite; `**Problem:**` from its `Cause`; `**Impact:**` from its `Combined risk`; `**Remediation:**` from its `Remediation`; `**Composed-of:**` = the resolved bases (filled with final IDs in Step 5.6); `**Origin:** review`; and `**Fix-policy:** needs-decision` when any basis carries a `**Fix-policy:**` value other than `auto`. `**Location:**` must parse as `path:line` or `path:line-range`, be contained in the repository tree, and exist there — a composite whose location fails any of the three is not rendered as a block and stays a bullet, never repaired. Each resolved basis's `**Location:**` must pass those same three checks — the fixer opens every component's site, not the composite's alone — and a basis whose location fails any of them is dropped from `Composed-of` exactly as sub-item 1 drops an unresolvable one, leaving the composite a bullet under sub-item 3 where fewer than two bases survive.
3. Tag confirmed findings as `[verified]`
4. Reinstate spot-checked rejections: each entry in the Challenger's
   `### Rejected findings (spot-check)` subsection has the shape
   `[{domain}] {title}: reinstate at {SEVERITY} — {reasoning}`. Parse it by
   anchoring on the literal delimiter `: reinstate at ` (NOT the first `:`):
   the domain tag is the leading `[…]`, the **title** is the text between the
   tag and that delimiter, the severity is the `{SEVERITY}` token after it, and
   the reasoning is everything after the following ` — `. The title may itself
   contain `:` (e.g. `God Object: UserService`, which the auditors are told to
   write), so a first-`:` split would truncate the title and break the match
   back to the rejected record — always anchor on `: reinstate at `. For each
   entry, reconstruct a minimal
   full-format finding and move it from its auditor's `rejected` collection
   into `findings` before Step 5.6 — severity from the entry's
   `reinstate at {SEVERITY}`; Category from the rejected entry's normalized
   `category` field where present and not `—`, else from the domain tag
   (`[security]` → Security, `[documentation]` → Documentation,
   `[quality]` → Maintainability) — map any non-canonical forwarded
   category (e.g. Design, Style, Developer Standards) to Maintainability
   so Step 5.6 and fix-auto can always parse it; Location from the
   normalized `location` field where present and not `—`, else from the
   Challenger's reasoning where cited, else `—`; for Documentation-category reinstatements, set **Fix-policy:**
   needs-decision and **Drift-class:** from the normalized `drift-class`
   field where present and not `—`, else from the Challenger's reasoning,
   else decision (the class must not silently default to auto-fix); for ANY reinstated finding whose Location
   resolves to `—`, also set **Fix-policy:** needs-decision — a synthesized
   finding without a locatable target must not enter `/fix-all`'s auto
   queue (fix-auto requires a `path:line` Location and cannot ask for one
   inside a subagent); Problem/Remediation from the entry title, the
   original rejection reason, and the Challenger's reasoning.
   (Reconstruction is needed because rejected collections carry compact
   entries, not full finding blocks.)
   With a base, a reinstated finding that breaks the scope rule — located outside the changed files and naming no changed file and line that causes it — is not moved into findings; list it under `### Out of scope (scope check)`.

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

### [SEVERITY] {ID}: Title of Issue

**ID:** {ID}
**Location:** `path/to/file.py:42`
**Category:** Security | Performance | Architecture | Maintainability | Documentation | Composite
**OWASP:** A05:2025 (if applicable)
**CWE:** CWE-89 (if applicable)
**Effort:** trivial | easy | medium | hard
**Drift-class:** mechanical | decision | dead-reference   <- documentation findings only
**Fix-policy:** auto | needs-decision                     <- documentation findings, and any reinstated finding with Location `—`
**Composed-of:** ID, ID[, ID…]                            <- Composite findings only
**Origin:** review | fix-time                             <- Composite findings only
**Part-of:** COMP-NNN                                     <- components of a composite only

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

**Task Update:** Task 5 was already marked as `completed` in Step 5.5.

---

## Verification Summary

Include this section in the review output:

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
{Findings removed or downgraded by Challenger, with reasoning — as plain bullets. NEVER paste original `### [SEVERITY]` issue blocks here; fix-all/fix-report extract any such heading as a fixable issue, which would resurrect a removed false positive.}

### Rejected by auditors (self-falsification)
{Per-auditor rejected entries as plain bullets `- {title} — {reason}`; `None` when empty. NEVER render these as `### [SEVERITY]` headings — fix-all/fix-report extract any such heading as a fixable issue.}

### Doctrine-gap candidates
{Same bullet format; `None` when empty.}

### Out of scope (scope check)
{Findings removed by the scope check as plain bullets `- {title} — {location}`; `None` when empty or for a whole-repository scope. NEVER render these as `### [SEVERITY]` headings.}
```

The "Cross-analysis findings" count is the number of composites rendered as finding blocks.

---

## Step 5.6: Assign Issue IDs

Before rendering the final report, assign unique identifiers to each issue based on category.

The rendered report starts with the `Review scope:` line from the Review Scope Phase. Step 5.6 removes no finding: the scope check ran in Step 5.5 before composites were resolved, so every `**Composed-of:**` basis receives a final ID.

**Algorithm:**

1. Collect all findings from:
   - Security auditor results
   - Code quality auditor results
   - Documentation auditor results (if launched)
   - Your own performance analysis (Step 2)
   - Your own architecture/maintainability analysis (Steps 3-4)

2. Initialize counters for each category:
   - `sec_count = 0` (Security)
   - `perf_count = 0` (Performance)
   - `arch_count = 0` (Architecture)
   - `maint_count = 0` (Maintainability)
   - `doc_count = 0` (Documentation)
   - `comp_count = 0` (Composite)

3. For each issue (in the order they appear in the report):
   - Read the issue's `Category` field
   - Map the category to its prefix using the canonical [Category→Prefix mapping](../../../docs/plugins/code-review.md#category-prefix-mapping) (single source of truth), then increment the corresponding counter (e.g., Security → SEC → `sec_count`)
   - Format ID as `{PREFIX}-{NNN}` with zero-padded 3-digit counter (e.g., SEC-001, PERF-002)
   - Strip any pre-existing `{PREFIX}-{NNN}: ` prefix from the heading and drop any pre-existing `**ID:**` line before assigning (documentation-auditor emits its own DOC-NNN IDs; reinstated findings have none) — IDs are assigned exactly once, here
   - Modify the issue heading: `### [SEVERITY] {ID}: Title`
   - Add `**ID:** {ID}` field right after the heading (before **Location:**)
   - Preserve `**Drift-class:**` and `**Fix-policy:**` field lines verbatim when re-rendering issue blocks — they must reach the saved report for `/fix-all`'s Fix-policy filter to work.

4. **Composites last.** Assign `COMP-NNN` IDs only after every other finding has its ID, so `**Composed-of:**` renders with final IDs. For each composite block: fill `**Composed-of:**` with the resolved bases' final IDs on one physical line (`SEC-002, SEC-003, ARCH-001`); insert `**Part-of:** COMP-NNN` into each basis block directly after its `**ID:**` line; render the composite block after the non-composite findings of the same severity. Composites never nest and a basis belongs to at most one composite — both hold by construction of Step 5.5 item 2.

**Example transformation:**

Before:

```
### [HIGH] SQL Injection in User Query

**Location:** `src/db/queries.py:42`
**Category:** Security
```

After:

```
### [HIGH] SEC-001: SQL Injection in User Query

**ID:** SEC-001
**Location:** `src/db/queries.py:42`
**Category:** Security
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

1. Slugify the branch name:
   - Replace `/` with `-`
   - Replace spaces with `-`
   - Convert to lowercase
   - Example: `feature/user-login` → `feature-user-login`

2. Build the file path: `docs/reviews/YYYY-MM-DD-<branch-slug>.md`
   - Use today's date
   - Example: `docs/reviews/2026-02-19-feature-user-login.md`

3. Check if the file already exists. If it does, append a numeric suffix:
   - `docs/reviews/2026-02-19-feature-user-login-2.md`
   - Increment until a non-existing filename is found

4. Create the `docs/reviews/` directory if it doesn't exist:

```bash
mkdir -p docs/reviews
```

1. Write the full review report (the same markdown content displayed to the user) to the file using the Write tool.

2. Confirm to the user: "Review saved to `docs/reviews/2026-02-19-feature-user-login.md`"

**If user selects "No":** Proceed to Step 7.

**Task Update:** Mark task 7 as `completed` using TaskUpdate.

---

## Step 7: Post-Review Guidance

**Skip this step if no issues were found during the review.**

**Task Update:** Mark task 8 as `in_progress` using TaskUpdate.

After the review is complete (and optionally saved), display guidance based on context:

**If issues were found AND report was saved to a file:**

> **Found {N} issues.** To fix them:
>
> `/fix-report <saved-report-path>` — fix multiple issues interactively
>
> `/fix SEC-001` — fix a single issue by ID (uses latest saved report)
>
> `/fix <paste issue block>` — fix a single issue by pasting

**If issues were found but report was NOT saved:**

> **Found {N} issues.** To fix individual issues, use:
>
> `/fix <paste issue block from above>`
>
> To use ID-based fixes or `/fix-report`, save the review first (re-run `/review` and choose to save).

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

### Documentation (CONDITIONAL)

- [ ] Documentation detection phase completed
- [ ] documentation-auditor subagent launched (if docs detected)
- [ ] Docs drift pre-pass run when docs were detected and the scope has a base, its output passed to documentation-auditor
- [ ] Documentation results retrieved via AgentOutputTool (if launched)
- [ ] All documentation findings included in review

### Completeness

- [ ] Performance analysis done
- [ ] Review scope determined, its scope block passed to every dispatched agent, scope check applied before composites were resolved
- [ ] All findings have file:line references
- [ ] Severity levels assigned (CRITICAL/HIGH/MEDIUM/LOW)
- [ ] Actionable remediation provided
- [ ] Code examples for HIGH+ severity issues

### Post-Review Actions

- [ ] User asked whether to save review
- [ ] Review saved to `docs/reviews/` (if requested)
- [ ] Post-review guidance displayed (fix-report / fix commands)

**If ANY security or quality checkbox is unchecked: STOP. Complete those steps first.**

### Developer Plugins (if detected)

- [ ] developer-plugins-integration skill invoked
- [ ] Stack detection results passed to subagents
- [ ] Developer skill findings integrated into review

### Verification

- [ ] Cross-Verifier and Challenger subagents spawned and results collected
- [ ] Cross-Verifier correlations integrated
- [ ] Challenger results applied (false positives removed, severity adjusted)
- [ ] Verification Summary included in output

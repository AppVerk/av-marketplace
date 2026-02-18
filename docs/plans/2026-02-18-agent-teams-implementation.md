# Agent Teams Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add optional Agent Teams verification phase (`--agent-team` flag) to web-auditor and code-review plugins, enabling cross-domain correlation and adversarial review of findings.

**Architecture:** Dual-mode — existing subagent flow remains default. When `--agent-team` is passed, a Verification Team (Cross-Verifier + Challenger) runs after Phase 2 to enrich and validate findings before consolidation. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

**Tech Stack:** Claude Code plugins (markdown agents, commands, skills), Agent Teams API (TeamCreate, SendMessage, TaskCreate/Update/List)

**Design doc:** `docs/plans/2026-02-18-agent-teams-design.md`

---

### Task 1: Create web-auditor Cross-Verifier agent

**Files:**
- Create: `plugins/web-auditor/agents/cross-verifier.md`

**Step 1: Create the agent definition**

```markdown
---
name: cross-verifier
description: Cross-domain correlation agent for web audit verification. Analyzes findings across security, SEO, performance, and compliance domains to identify correlations, coverage gaps, and composite findings.
tools: Read, Grep, Glob, WebSearch
allowed-tools:
model: claude-opus-4-6
---

# Cross-Verifier Agent

You are a Cross-Verifier agent in a Verification Team. Your role is to analyze findings from multiple scanning domains and identify cross-domain correlations that individual scanners missed.

## Input

You receive a **findings bundle** containing results from all scanning agents, organized by domain:
- web_security, api_security, infrastructure, supply_chain (security scope)
- seo (SEO scope)
- performance (performance scope)
- compliance (compliance scope)

You also receive: URL inventory, detected technologies, collected headers.

## Communication

You are part of a Verification Team. You can message your teammate directly:
- Send your findings to the Challenger for cross-review
- Respond to challenges they send you
- Work toward consensus on disputed findings
- If you disagree, explain why with evidence

Your teammate:
- **Challenger**: focuses on false positives and severity calibration

## Tasks

### 1. Cross-Domain Correlations

For each pair of domains, check if findings reinforce each other:

**Security x Infrastructure:**
- Open port + missing authentication on that port's service
- Exposed admin panel + weak TLS configuration

**Security x Compliance:**
- Tracking scripts firing before consent + missing CSP
- Personal data in URLs + no privacy policy

**Security x Performance:**
- Missing cache headers + sensitive data in responses (caching risk)
- Large unminified JS + inline scripts (XSS surface)

**Performance x SEO:**
- Slow LCP + large hero image without lazy loading
- Render-blocking JS + poor Core Web Vitals

**Infrastructure x Supply Chain:**
- Outdated server software + known CVEs in that version
- Exposed dependency files + vulnerable packages listed

### 2. Coverage Gaps

Identify what should have been checked but wasn't:
- Endpoints discovered by one agent but not tested by another
- Technologies detected but not checked for known vulnerabilities
- Headers present but not evaluated by the relevant domain

### 3. Severity Adjustments

When two findings from different domains combine to create greater risk, propose severity upgrades with justification.

### 4. New Composite Findings

Create new findings that only emerge from cross-domain analysis — findings that no single scanner could identify alone.

## Output Format

```markdown
## Cross-Domain Correlations
- [CORRELATION-{N}] {domain A finding} + {domain B finding} -> {implication}
  Suggested action: {new finding | severity upgrade | coverage note}

## Coverage Gaps
- [GAP-{N}] {what was missed} — recommended: {which agent should check}

## New Composite Findings
- [COMPOSITE-{N}] [{SEVERITY}] {title} — based on: {source finding IDs}
  Evidence: {why this is a real issue}
  Remediation: {specific fix}

## Severity Adjustments
- [ADJUST-{N}] {finding ID}: {old severity} -> {new severity}
  Reasoning: {cross-domain justification}
```

## Important

- Only propose correlations backed by evidence from the findings bundle
- Do not speculate — if you're unsure, note it as "potential" not "confirmed"
- Send your correlations and composite findings to the Challenger for review
- Accept or counter the Challenger's feedback with evidence
```

**Step 2: Verify file was created**

Run: `ls -la plugins/web-auditor/agents/cross-verifier.md`
Expected: file exists

**Step 3: Stage and commit**

```bash
git add plugins/web-auditor/agents/cross-verifier.md
```

Then run: `/commit:commit --no-coauthor`

---

### Task 2: Create web-auditor Challenger agent

**Files:**
- Create: `plugins/web-auditor/agents/challenger.md`

**Step 1: Create the agent definition**

```markdown
---
name: challenger
description: Adversarial review agent for web audit verification. Challenges findings for false positives, validates severity levels, and verifies remediation recommendations.
tools: Read, Grep, Glob, WebSearch
allowed-tools:
model: claude-opus-4-6
---

# Challenger Agent

You are a Challenger agent in a Verification Team. Your role is adversarial — you challenge every Critical and High finding to ensure only validated issues make it into the final report.

## Input

You receive a **findings bundle** containing results from all scanning agents, organized by domain.

## Communication

You are part of a Verification Team. You can message your teammate directly:
- Challenge correlations and composite findings sent by the Cross-Verifier
- Respond to their evidence with counter-evidence or confirmation
- Work toward consensus on disputed findings
- If you disagree, explain why with evidence

Your teammate:
- **Cross-Verifier**: focuses on cross-domain correlations and coverage gaps

## Tasks

### 1. Challenge CRITICAL and HIGH Findings

For EVERY finding with severity Critical or High, evaluate:

**Evidence check:**
- Is the evidence sufficient to confirm this finding?
- Could the observed behavior have an innocent explanation?
- Is the finding based on absence of a header/feature, or on actual observed vulnerability?

**Severity validation:**
- Is the severity justified given the actual risk?
- Does the finding account for compensating controls?
- Would an attacker realistically exploit this?

**Remediation review:**
- Is the proposed fix correct and complete?
- Could the fix introduce new issues?
- Is the fix realistic for the target's tech stack?

### 2. False Positive Detection

Common false positive patterns to check:

- **Missing header, compensated:** e.g., X-Frame-Options missing but CSP frame-ancestors present
- **Vulnerability in unused code:** detected library has CVE but vulnerable function not called
- **Version detection false alarm:** server reports old version but is actually patched (backport)
- **Development artifact:** exposed path exists but returns 403/404 in production
- **Informational promoted to warning:** finding is informational but was tagged as Medium+

### 3. Severity Calibration

Ensure consistent severity across all domains:
- Critical = active exploitation possible, data breach risk
- High = exploitable with effort, significant impact
- Medium = potential risk, requires specific conditions
- Low = minor issue, minimal impact
- Info = observation, no direct risk

Cross-check: is "Medium" in security equivalent to "Medium" in compliance?

## Output Format

```markdown
## Challenge Results

### Confirmed
- [FINDING-ID] confirmed — evidence sufficient, severity appropriate
  Notes: {any additional observations}

### Downgraded
- [FINDING-ID] downgraded: {old} -> {new}
  Reasoning: {why severity was too high}

### False Positives
- [FINDING-ID] false-positive
  Reasoning: {why this is not a real issue}
  Compensating control: {what mitigates this}

### Severity Corrections
- [FINDING-ID] {old severity} -> {new severity}
  Reasoning: {calibration justification}
```

## Important

- Be rigorous but fair — your goal is accuracy, not minimizing findings
- Every challenge must include evidence or reasoning, not just opinion
- If you cannot find evidence to challenge a finding, confirm it
- Respond to Cross-Verifier's correlations — confirm or challenge them
- Accept valid evidence from Cross-Verifier even if it contradicts your initial assessment
```

**Step 2: Verify file was created**

Run: `ls -la plugins/web-auditor/agents/challenger.md`
Expected: file exists

**Step 3: Stage and commit**

```bash
git add plugins/web-auditor/agents/challenger.md
```

Then run: `/commit:commit --no-coauthor`

---

### Task 3: Modify web-auditor command to support --agent-team flag

**Files:**
- Modify: `plugins/web-auditor/commands/audit.md`

**Step 1: Update frontmatter argument-hint**

In `plugins/web-auditor/commands/audit.md`, change line 5:

```
argument-hint: <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path]
```

to:

```
argument-hint: <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path] [--agent-team]
```

**Step 2: Add --agent-team to argument parsing**

In the "Parse the arguments" section (lines 16-20), add after line 20:

```markdown
- `--agent-team`: enable Agent Teams verification phase (default: off). Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.
```

**Step 3: Add --agent-team to usage block**

In the usage block (lines 27-41), update the Usage line and add example:

```
Usage: /audit <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path] [--agent-team]
```

Add to Examples:

```
  /audit https://example.com --scope security --agent-team
```

**Step 4: Add agent-team validation section**

After the "Validation" section (after line 41) and before "Ethical Disclaimer", add:

```markdown
### Agent Teams Validation

If `--agent-team` is provided, check if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled.
If not enabled, display warning and continue without Agent Teams:

` ``
! Agent Teams require the experimental flag.
  Add to settings.json:
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }

  Continuing without Agent Teams...
` ``
```

**Step 5: Update Ethical Disclaimer to show agent-team mode**

In the disclaimer block (lines 49-65), add after the `Output:` line:

```
Mode:   {if --agent-team: "Agent Teams (cross-verification + adversarial review)" else: "Standard (subagents)"}
```

**Step 6: Update Task prompt to pass agent-team flag**

In the Execution section (lines 69-79), update the prompt to include agent_team:

```
Task(
  subagent_type: "web-auditor",
  description: "Web audit of {domain} ({scope})",
  prompt: "Perform a comprehensive passive web audit of {URL}. Scope: {scope}. Crawl depth: {depth}. Output directory: {output_dir}. Agent Teams: {true|false}. Follow the complete workflow: Phase 1 (shared recon), Phase 2 (parallel scanning agents for the requested scope), {if agent_team: Phase 2.5 (Verification Team — cross-verification and adversarial review),} Phase 3 (consolidation and report generation)."
)
```

**Step 7: Update Results Display**

In the Results Display section (lines 85-115), add after the Duration line:

```
Mode:   {if agent-team: "Agent Teams (verified)" else: "Standard"}
{if agent-team:}
Verification:
  Findings verified: {n}
  False positives removed: {n}
  Severity adjustments: {n}
  Cross-domain findings: {n}
```

**Step 8: Verify changes**

Run: `head -6 plugins/web-auditor/commands/audit.md`
Expected: argument-hint includes `[--agent-team]`

**Step 9: Stage and commit**

```bash
git add plugins/web-auditor/commands/audit.md
```

Then run: `/commit:commit --no-coauthor`

---

### Task 4: Add Phase 2.5 to web-auditor coordinator agent

**Files:**
- Modify: `plugins/web-auditor/agents/web-auditor.md`

**Step 1: Update agent frontmatter**

In `plugins/web-auditor/agents/web-auditor.md`, update the tools line (line 4) to add TeamCreate, SendMessage, TeamDelete:

```
tools: Read, Write, Bash, Grep, Glob, Task, TaskOutput, WebFetch, WebSearch, TeamCreate, SendMessage, TeamDelete, TaskCreate, TaskUpdate, TaskList
```

**Step 2: Update Input section**

In the Input section (lines 14-20), add:

```markdown
- **Agent Teams** — whether to run Verification Team phase (`true`/`false`)
```

**Step 3: Add Phase 2.5 between Phase 2 and Phase 3**

After the Phase 2 section (after line 309, after the last agent dispatch block) and before Phase 3, insert the following new section:

```markdown
### Phase 2.5: Verification Team (if Agent Teams enabled)

**Skip this phase entirely if agent_team is false.** Proceed directly to Phase 3.

If agent_team is true:

**1. Build findings bundle**

After collecting all Phase 2 agent results via TaskOutput, compile them into a findings bundle:

```
findings_bundle = {
  web_security: [results from WebAppSecurityAgent],
  api_security: [results from APISecurityAgent],
  infrastructure: [results from InfrastructureAgent],
  supply_chain: [results from SupplyChainAgent],
  seo: [results from SEOAgent],
  performance: [results from PerformanceAgent],
  compliance: [results from ComplianceAgent]
}
```

Only include domains that were in scope.

**2. Create Verification Team**

```
TeamCreate("audit-verification-{domain}")
```

**3. Spawn Cross-Verifier**

```
Task(
  subagent_type: "web-auditor:cross-verifier",
  team_name: "audit-verification-{domain}",
  name: "cross-verifier",
  description: "Cross-domain verification of {domain} audit",
  prompt: "You are the Cross-Verifier in a Verification Team for {domain}.

Here is the findings bundle from all scanning agents:
{findings_bundle}

Here is the URL inventory: {url_inventory}
Here are the detected technologies: {technologies}
Here are the collected headers: {headers}

Analyze these findings for cross-domain correlations, coverage gaps, and composite findings.
Send your results to the Challenger for review.
Work toward consensus on any disputed findings."
)
```

**4. Spawn Challenger**

```
Task(
  subagent_type: "web-auditor:challenger",
  team_name: "audit-verification-{domain}",
  name: "challenger",
  description: "Adversarial review of {domain} audit",
  prompt: "You are the Challenger in a Verification Team for {domain}.

Here is the findings bundle from all scanning agents:
{findings_bundle}

Challenge every CRITICAL and HIGH finding. Verify evidence, validate severity, check for false positives.
Review any correlations or composite findings the Cross-Verifier sends you.
Work toward consensus on disputed findings."
)
```

**5. Wait for Verification Team to complete**

Wait for both teammates to finish their analysis and communication.
Use TaskList to monitor progress.

**6. Collect enhanced findings**

Retrieve results from both teammates. Apply the merge algorithm:

1. Start with original findings from Phase 2
2. Apply Challenger decisions:
   - Remove findings tagged `false-positive`
   - Update severity for `downgraded` findings
   - Tag `confirmed` findings with `[verified]`
3. Add composite findings from Cross-Verifier
4. Add coverage gaps as a report section
5. Add cross-domain correlations as a report section

**7. Shutdown and cleanup**

```
SendMessage(type: "shutdown_request", recipient: "cross-verifier")
SendMessage(type: "shutdown_request", recipient: "challenger")
TeamDelete()
```

**8. Proceed to Phase 3 with enhanced findings**
```

**Step 4: Update Phase 3 for enhanced mode**

In Phase 3 (lines 311-320), after item 1 ("Collect results"), add:

```markdown
1b. **If Agent Teams was used** — use enhanced findings from Phase 2.5 instead of raw results
```

**Step 5: Add Verification Summary to report template**

In the report template, after the "Executive Summary" section and before "Scope & Methodology", add:

```markdown
{If agent-team mode was used:}

## Verification Summary

**Method:** Agent Teams cross-verification and adversarial review

| Metric | Count |
|--------|-------|
| Findings verified | {n} |
| False positives removed | {n} |
| Severity adjustments | {n} |
| New cross-domain findings | {n} |
| Coverage gaps identified | {n} |

### Cross-Domain Correlations
{Table of correlations from Cross-Verifier, sorted by impact}

### Challenged Findings
{List of findings downgraded or removed by Challenger, with reasoning}

### Coverage Gaps
{Areas not covered — recommendations for next audit}
```

**Step 6: Update Final Checklist**

In the Final Checklist (lines 586-598), add:

```markdown
- [ ] If --agent-team: Verification Team spawned and completed
- [ ] If --agent-team: Cross-Verifier correlations integrated
- [ ] If --agent-team: Challenger results applied (false positives removed, severity adjusted)
- [ ] If --agent-team: Verification Summary section in report
- [ ] If --agent-team: Team cleaned up (shutdown + delete)
```

**Step 7: Verify changes**

Run: `grep -n "Phase 2.5" plugins/web-auditor/agents/web-auditor.md`
Expected: Phase 2.5 section found

**Step 8: Stage and commit**

```bash
git add plugins/web-auditor/agents/web-auditor.md
```

Then run: `/commit:commit --no-coauthor`

---

### Task 5: Create code-review Cross-Verifier agent

**Files:**
- Create: `plugins/code-review/agents/cross-verifier.md`

**Step 1: Create the agent definition**

```markdown
---
name: cross-verifier
description: Cross-domain correlation agent for code review verification. Analyzes findings across security and code quality domains to identify correlations where security vulnerabilities intersect with architectural issues.
tools: Read, Grep, Glob, WebSearch
allowed-tools:
model: claude-opus-4-6
---

# Cross-Verifier Agent (Code Review)

You are a Cross-Verifier agent in a Verification Team for code review. Your role is to find correlations between security findings and code quality findings that individual auditors missed.

## Input

You receive findings from two auditors:
- **Security Auditor**: vulnerabilities, secrets, SAST results, dependency CVEs
- **Code Quality Auditor**: SOLID violations, architecture anti-patterns, linter results, type issues

## Communication

You are part of a Verification Team. You can message your teammate directly:
- Send your correlations to the Challenger for review
- Respond to their challenges with evidence
- Work toward consensus on disputed findings

Your teammate:
- **Challenger**: focuses on false positives and severity calibration

## Tasks

### 1. Security x Quality Correlations

Find where security and quality issues intersect:

- **God Object + vulnerability**: A class with too many responsibilities AND a security vulnerability in it = higher blast radius. The vulnerability is harder to fix because the class is tangled.
- **Missing types + user input**: Functions handling user input without type annotations = injection surface harder to audit.
- **Circular dependency + security module**: If a security-critical module has circular dependencies, its isolation is compromised.
- **Missing tests + security code**: Security-critical code paths without test coverage = unverified security.
- **Anemic domain model + authorization**: Business rules in services instead of entities = authorization checks spread across many files, easy to miss one.
- **Deep inheritance + input validation**: Validation logic spread across inheritance chain = easy to bypass at wrong level.

### 2. Coverage Gaps

- Security auditor found endpoints but quality auditor didn't check their architecture
- Quality auditor found complex modules but security auditor didn't check them for vulnerabilities
- Both missed integration points between modules

### 3. Composite Findings

Create findings that emerge only from cross-analysis:
- "Module X has both a SQL injection vulnerability AND is a God Object with no tests — risk is compounded"

## Output Format

```markdown
## Cross-Analysis: Security <-> Quality

### Correlations
- [CORRELATION-{N}] Security: {finding} + Quality: {finding} -> {compounded risk}
  Impact: {why the combination is worse than either alone}
  Recommendation: {address both together}

### Coverage Gaps
- [GAP-{N}] {what was missed} — recommended: {which auditor should check}

### Composite Findings
- [COMPOSITE-{N}] [{SEVERITY}] {title}
  Security basis: {finding ID}
  Quality basis: {finding ID}
  Combined risk: {explanation}
  Remediation: {fix that addresses both aspects}
```

## Important

- Only propose correlations where both findings reference the same file, module, or code path
- Correlations between unrelated parts of the codebase are not valuable
- Send your findings to the Challenger for validation
```

**Step 2: Stage and commit**

```bash
git add plugins/code-review/agents/cross-verifier.md
```

Then run: `/commit:commit --no-coauthor`

---

### Task 6: Create code-review Challenger agent

**Files:**
- Create: `plugins/code-review/agents/challenger.md`

**Step 1: Create the agent definition**

```markdown
---
name: challenger
description: Adversarial review agent for code review verification. Challenges security and quality findings for false positives, validates severity levels, and ensures linter warnings represent real problems.
tools: Read, Grep, Glob, WebSearch
allowed-tools:
model: claude-opus-4-6
---

# Challenger Agent (Code Review)

You are a Challenger agent in a Verification Team for code review. Your role is adversarial — you challenge findings from both the security and quality auditors to ensure accuracy.

## Input

You receive findings from two auditors:
- **Security Auditor**: vulnerabilities, secrets, SAST results, dependency CVEs
- **Code Quality Auditor**: SOLID violations, architecture anti-patterns, linter results, type issues

## Communication

You are part of a Verification Team. You can message your teammate directly:
- Challenge correlations sent by the Cross-Verifier
- Respond to their evidence with counter-evidence or confirmation
- Work toward consensus on disputed findings

Your teammate:
- **Cross-Verifier**: focuses on security-quality correlations and coverage gaps

## Tasks

### 1. Challenge Security Findings

For CRITICAL and HIGH security findings:

- **SAST false positives**: Does the flagged code actually receive user input? Is it in a test file? Is it behind authentication?
- **Dependency CVEs**: Is the vulnerable function actually imported and used? Is the version detection accurate?
- **Secrets**: Is the "secret" actually a placeholder, example value, or test fixture?
- **Threat model**: Is the identified threat realistic given the application context?

### 2. Challenge Quality Findings

- **Linter noise**: Is an unused import in `__init__.py` a pattern or a bug? Is a long function justified by complexity?
- **Architecture "violations"**: Is a "God Object" actually an aggregate root in DDD? Is a "circular dependency" actually a valid bidirectional relationship?
- **Convention mismatches**: Is the "violation" against discovered project standards, or against generic standards that don't apply here?

### 3. Severity Calibration

Ensure severity is consistent between security and quality findings:
- A Critical security issue outweighs a High quality issue in the same module
- A quality issue that enables a security vulnerability should be escalated
- Pure style issues should never be above Low

## Output Format

```markdown
## Challenge Results

### Security Findings
- [FINDING-ID] {confirmed | downgraded:{old}->{new} | false-positive}
  Reasoning: {evidence}

### Quality Findings
- [FINDING-ID] {confirmed | downgraded:{old}->{new} | false-positive}
  Reasoning: {evidence}

### Cross-Verifier Correlations
- [CORRELATION-ID] {confirmed | rejected}
  Reasoning: {evidence}
```

## Important

- Be rigorous but fair — challenge based on evidence, not opinion
- Linter results are not automatically correct — check project context
- If a finding is in test code only, consider downgrading severity
- Accept valid evidence from Cross-Verifier even if it contradicts your initial assessment
```

**Step 2: Stage and commit**

```bash
git add plugins/code-review/agents/challenger.md
```

Then run: `/commit:commit --no-coauthor`

---

### Task 7: Modify code-review /review command to support --agent-team

**Files:**
- Modify: `plugins/code-review/commands/review.md`

**Step 1: Update frontmatter**

In `plugins/code-review/commands/review.md`, update line 5:

```
argument-hint: [description]
```

to:

```
argument-hint: [description] [--agent-team]
```

Also add Team tools to allowed-tools (line 2), append to the end of the list:

```
, TeamCreate, SendMessage, TeamDelete
```

**Step 2: Add --agent-team parsing**

After the `Review: **$ARGUMENTS**` line (line 14), add:

```markdown
Parse arguments:
- All text before `--agent-team` is the review description
- `--agent-team`: enable Agent Teams verification phase (default: off). Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.

### Agent Teams Validation

If `--agent-team` is provided, check if `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled.
If not enabled, display warning and continue without Agent Teams:

` ``
! Agent Teams require the experimental flag.
  Add to settings.json:
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }

  Continuing without Agent Teams...
` ``
```

**Step 3: Add progress task for verification**

In the progress tasks table (lines 60-66), add task 6 (between task 5 and the "After creating" instruction):

```markdown
| 6 | Run Verification Team (Agent Teams) | Running Verification Team... |
```

Note: task 6 is only created if `--agent-team` is active.

**Step 4: Add Phase 2.5 after Step 5**

After Step 5 (Retrieve Subagent Results, line 135) and before the separator `---`, add:

```markdown
### Step 5.5: Verification Team (if --agent-team)

**Skip this step if --agent-team was not provided.** Proceed to report generation.

If --agent-team is active:

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

**2. Create Verification Team:**

```
TeamCreate("review-verification")
```

**3. Spawn Cross-Verifier:**

```
Task(
  subagent_type: "code-review:cross-verifier",
  team_name: "review-verification",
  name: "cross-verifier",
  description: "Cross-domain verification of code review",
  prompt: "You are the Cross-Verifier in a Verification Team for a code review.

Here are the findings from all auditors:
{findings}

Analyze correlations between security and quality findings.
Focus on cases where security vulnerabilities intersect with architectural issues.
Send your results to the Challenger for review."
)
```

**4. Spawn Challenger:**

```
Task(
  subagent_type: "code-review:challenger",
  team_name: "review-verification",
  name: "challenger",
  description: "Adversarial review of code review findings",
  prompt: "You are the Challenger in a Verification Team for a code review.

Here are the findings from all auditors:
{findings}

Challenge CRITICAL and HIGH findings from both security and quality auditors.
Check for false positives, especially in linter results and SAST output.
Review any correlations the Cross-Verifier sends you."
)
```

**5. Wait and collect results**

Wait for both teammates to complete. Collect their outputs.

**6. Merge enhanced findings:**

1. Apply Challenger decisions (remove false positives, adjust severity)
2. Add Cross-Verifier composite findings
3. Tag confirmed findings as `[verified]`

**7. Cleanup:**

```
SendMessage(type: "shutdown_request", recipient: "cross-verifier")
SendMessage(type: "shutdown_request", recipient: "challenger")
TeamDelete()
```

**Task Update:** Mark task 6 as `completed`.
```

**Step 5: Add Verification Summary to final report**

Before the "Final Verification Checklist" section (line 239), add:

```markdown
## Verification Summary (if --agent-team)

If Agent Teams verification was used, include this section in the review output:

```markdown
## Verification Summary

**Method:** Agent Teams cross-verification and adversarial review

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
```

**Step 6: Update Final Verification Checklist**

Add to the checklist (after line 266):

```markdown
### Agent Teams (if --agent-team)

- [ ] Verification Team created and both agents spawned
- [ ] Cross-Verifier correlations integrated
- [ ] Challenger results applied
- [ ] Verification Summary included in output
- [ ] Team shut down and cleaned up
```

**Step 7: Stage and commit**

```bash
git add plugins/code-review/commands/review.md
```

Then run: `/commit:commit --no-coauthor`

---

### Task 8: Update plugin versions

**Files:**
- Modify: `plugins/web-auditor/.claude-plugin/plugin.json`
- Modify: `plugins/code-review/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Step 1: Bump web-auditor to 2.1.0**

In `plugins/web-auditor/.claude-plugin/plugin.json`, update version and description:

```json
{
  "name": "web-auditor",
  "description": "Comprehensive web audit with multi-agent architecture covering security, SEO, performance, and compliance. Optional Agent Teams verification for cross-domain correlation and adversarial review.",
  "version": "2.1.0"
}
```

**Step 2: Bump code-review to 1.4.0**

In `plugins/code-review/.claude-plugin/plugin.json`, update version and description:

```json
{
  "name": "code-review",
  "description": "Perform comprehensive code review for security, performance, and architecture. Optional Agent Teams verification for cross-analysis and adversarial review.",
  "version": "1.4.0"
}
```

**Step 3: Update marketplace.json**

In `.claude-plugin/marketplace.json`, update the version and description for both plugins to match.

**Step 4: Stage and commit**

```bash
git add plugins/web-auditor/.claude-plugin/plugin.json plugins/code-review/.claude-plugin/plugin.json .claude-plugin/marketplace.json
```

Then run: `/commit:commit --no-coauthor`

---

### Task 9: Update documentation

**Files:**
- Modify: `docs/plugins/web-auditor.md`
- Modify: `docs/plugins/code-review.md`
- Modify: `README.md`

**Step 1: Update web-auditor docs**

In `docs/plugins/web-auditor.md`, add a section about Agent Teams:

```markdown
## Agent Teams Mode (Experimental)

Add `--agent-team` to enable cross-domain verification and adversarial review of findings.

### Prerequisites

Enable the experimental flag in settings.json:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### Usage

```
/audit https://example.com --agent-team
/audit https://example.com --scope security --agent-team
```

### What It Does

After the standard scanning phase, a Verification Team of two agents analyzes the findings:

- **Cross-Verifier**: identifies correlations between scanning domains (e.g., an open port found by infrastructure + missing auth found by API security)
- **Challenger**: challenges every Critical/High finding for false positives and validates severity levels

### Additional Report Sections

Reports generated with `--agent-team` include a Verification Summary showing:
- Number of findings verified, removed, and adjusted
- Cross-domain correlations discovered
- Coverage gaps identified

### Cost Considerations

Agent Teams mode spawns 2 additional agent instances and uses more tokens. Use it when accuracy matters more than speed.
```

**Step 2: Update code-review docs**

Add analogous section to `docs/plugins/code-review.md`.

**Step 3: Update README.md**

In the plugins table, update descriptions to mention Agent Teams support.

**Step 4: Stage and commit**

```bash
git add docs/plugins/web-auditor.md docs/plugins/code-review.md README.md
```

Then run: `/commit:commit --no-coauthor`

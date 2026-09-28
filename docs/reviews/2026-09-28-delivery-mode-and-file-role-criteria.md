# Code Review: delivery/mode-and-file-role-criteria

**Scope:** `git diff 38107488c3b4357d952b726201ead55496ba861e..HEAD` (0396ce0, cc7887c), delivered from `docs/plans/2026-09-28-mode-and-file-role-criteria.md`
**Date:** 2026-09-28
**Stack:** no Python/PHP/React stack detected; no developer skills loaded
**Result:** 1 finding (LOW)

### [LOW] MAINT-001: QA planner `neither` class and test-plan-reviewer's "no testable surface" list diverge

**ID:** MAINT-001
**Location:** `plugins/qa/agents/test-planner.md:97-105`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The planner's new `neither` row (`test-planner.md:103`) lists "documentation, CI, repository tooling, linters, container or infrastructure config", and its FE row (`:101`) includes "frontend build config", with FE files leading to FE scenarios (`:105`). The reviewer's coverage check (`plugins/qa/agents/test-plan-reviewer.md:27`) says a file may have "no testable surface (docs, tests, build config)". Build config is FE-with-scenarios for the planner but needs no coverage for the reviewer. Test files appear only in the reviewer's list. CI, linters and infra config appear only in the planner's list. This diff pointed `loop.md:152` at the planner's Step 3 criteria but left the reviewer with its own list. [verified]

**Impact:**
Two definitions of "no testable surface" in one plugin can drift further and add review-round friction. Verdicts are unaffected.

**Remediation:**

```markdown
# Before (plugins/qa/agents/test-plan-reviewer.md:27)
3. **Coverage.** Each changed file maps to a scenario, a `## Blockers / Findings` entry or an `## Out of harness scope` bullet, or has no testable surface (docs, tests, build config). Claim a gap only after reading the file.

# After
3. **Coverage.** Each changed FE or BE file, by the planner's Step 3 criteria, maps to a scenario, a `## Blockers / Findings` entry or an `## Out of harness scope` bullet; `neither` files and test files need none. Claim a gap only after reading the file.
```

Then bump qa and run `python3 scripts/build_omp_edition.py`.

---

**Performance:** none. The diff has no executable code.
**Architecture:** none beyond MAINT-001.

## Verification Summary

**Method:** Cross-domain correlation and adversarial review (Cross-Verifier + Challenger)

| Metric | Count |
|--------|-------|
| Findings verified | 1 |
| False positives removed | 0 |
| Severity adjustments | 0 |
| Cross-analysis findings | 0 |

### Cross-Analysis (Security <-> Quality)
None. There were no security findings to correlate.

### Challenged Findings
None.

### Rejected by auditors (self-falsification)
- Dropping CWE/OWASP/severity/remediation Fix keywords routes security remediations to Implement — refuted empirically: 7/7 security tasks classified Fix with the new text
- `neither` excludes security-relevant app configuration from QA scenarios — refuted empirically: 6/6 app config files classified BE
- `neither` suppresses QA coverage of infra-level security config — deliberate plan decision; not verifiable in the harness; the Step 4.5 blocker scan still applies
- Content-based classification lets a PR author steer files into `neither` — no new trust boundary; QA is not a security gate
- `$ARGUMENTS` in an inline code span enables prompt injection — pre-existing pattern (develop.md:73, :188)
- Generated OMP edition diverges from source — refuted: generated hunks hash-identical 6/6
- Detect Mode block duplicated in four copies — required by the plan; plugins have no shared-include mechanism
- UK spelling "behaviour" — the plan prescribes the measured text byte for byte
- "What behavior should be tested" follows "`neither` files get no scenarios" — the plan keeps that list
- Mode precedence undefined for mixed tasks — the new text settles Fix vs cleanup; the Refactor definition settles Refactor vs Implement
- test-plan-format omission rules do not cover a neither-only diff — the planner and `/qa:loop` already handle zero scenarios
- Delivery Fix-template rounds may stop mapping to Fix mode — runtime behaviour; needs a labelled eval
- `loop.md` cites the planner's Step 3 without saying to read it — the indirection predates the diff
- qa bump should be minor — the plan sets a patch and the commit type is fix
- Developer docs say mode is detected "from the task description" — still true
- Frontend docs omit mode detection — gap predates the diff
- `docs/plugins/qa.md:35` does not say `neither` files get no scenarios — matches the plan; implied by `neither`
- QA Upgrade Notes lack 2.8.1 — prose-only patch needs no user action
- Build config FE vs reviewer's no-testable-surface — not a documentation issue; handed to quality review (became MAINT-001)

### Doctrine-gap candidates
- File-role criteria do not name framework/application configuration (security, CORS, session, routes) — the probe classified them BE, but `t4.json` has no such item
- No parity check for prose blocks that must stay identical across plugins (the four Detect Mode copies)
- No rule for when a release gets an Upgrade Notes entry in `docs/plugins/qa.md`

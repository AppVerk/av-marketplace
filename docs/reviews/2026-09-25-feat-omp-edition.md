# Code Review: feat/omp-edition — delivery qa-omp-edition

**Scope:** Changes on branch feat/omp-edition in bd9a80f..HEAD (git diff bd9a80f..HEAD: 5500701, 4a96827, bb47503), delivered from docs/plans/2026-09-25-qa-omp-edition.md.
**Date:** 2026-09-25

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 6 |

- **Stack detection:** no developer-plugin stack markers (no `pyproject.toml`, React `package.json` or `composer.json`); no developer skills loaded.
- **Security:** trufflehog 0 secrets; semgrep (205 rules) and bandit 0 findings on the changed Python; no dependency manifest changed.
- **Code quality:** ruff and mypy clean on the two changed Python files; `python3 scripts/test_build_omp_edition.py` 29 tests pass; `python3 scripts/build_omp_edition.py --check` up to date.
- **Documentation:** 13 doc claims checked against code and OMP 18.3.0 sources, all match.
- **Performance:** no issues; the generator is a one-shot build over short lists.

## Issues

### [LOW] SEC-001: User docs understate the QA testers' MCP access in OMP [verified]
**Status:** ✅ Fixed (2026-09-25)

**ID:** SEC-001
**Location:** `README.md:31`
**Category:** Security
**OWASP:** A01:2025
**CWE:** CWE-250
**Effort:** trivial

**Problem:**
`README.md:31` and `docs/plugins/qa.md:421` say only that database MCP servers configured for OMP are available to the tester without any grant. In OMP both `qa:fe-tester` and `qa:be-tester` receive every MCP tool configured for the session (OMP `src/task/executor.ts:3766-3770,3912`; `src/sdk.ts:3781-3789`), and a `tools:` list cannot narrow that. Claude Code scopes fe-tester to Playwright MCP and be-tester to six database servers. The model-facing preamble (`omp/preamble.md:13`) states it; the user docs do not.

**Impact:**
A user with a write-capable MCP server (issue tracker, production database) who runs `/qa:run` or `/qa:loop --mode auto` against untrusted code expects Claude Code's scoping. A prompt-injection payload in a page or API response under test could drive a tester to call that server.

**Remediation:**
In `README.md:31` and `docs/plugins/qa.md:421`, replace the database sentence with: "OMP gives every subagent all MCP servers configured for the session, so both `qa:fe-tester` and `qa:be-tester` can call any of them (a `tools:` list cannot narrow this). Before running `/qa:run` or `/qa:loop` against code you do not trust, remove write-capable MCP servers from the OMP config."

### [LOW] SEC-002: FE tests can run in the user's own or an attached browser instead of OMP's managed Chromium [verified]
**Status:** ✅ Fixed (2026-09-25)

**ID:** SEC-002
**Location:** `omp/preamble.md:14`
**Category:** Security
**OWASP:** A02:2025
**CWE:** CWE-668
**Effort:** easy

**Problem:**
The preamble bullet and `README.md:31` / `docs/plugins/qa.md:421` say FE scenarios run in OMP's own managed Chromium. `browser.open` without `app` selects, in order, the relay (`browser.relay`), `browser.cdpUrl`, cmux, and only then the managed Chromium (OMP `src/tools/browser.ts:166-202`). `browser.relay` defaults to off, so the default run uses the managed Chromium; with the relay on or `browser.cdpUrl` set, FE scenarios drive the user's logged-in Chrome or the attached browser.

**Impact:**
`/qa:loop --mode auto` could fill and submit forms with the user's cookies and sessions, and test credentials typed by the tester go to the attached browser.

**Remediation:**
`app={"relay": False}` alone does not bypass a configured `browser.cdpUrl`, and it does not cover cmux selection. State in `README.md:31`, `docs/plugins/qa.md:421` and `omp/preamble.md:14` that FE scenarios run in the browser OMP's settings select and that `browser.relay`, `browser.cdpUrl` and cmux should be off for QA runs; in the preamble's `browser.open` call also pass `app={"relay": False}`. Regenerate with `python3 scripts/build_omp_edition.py`.

### [LOW] MAINT-001: Slash-command bullet leaves out /analyze-feedback [verified]
**Status:** ✅ Fixed (2026-09-25)

**ID:** MAINT-001
**Location:** `omp/preamble.md:15`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The bullet maps `/fix`, `/fix-report`, `/fix-all` and `/review` to `/code-review:…` but not `/analyze-feedback`, which the files carrying the preamble cite six times, including the user-facing prompt "Provide PR number: `/analyze-feedback 123`" (`plugins/code-review/commands/analyze-feedback.md:47`; also `agents/feedback-analyzer.md:32,145,149`, `commands/fix.md:137`, `commands/fix-report.md:98`). In OMP the command is `/code-review:analyze-feedback`.

**Impact:**
The OMP edition can tell the user to run a command that does not exist, and the explicit list drifts as code-review adds commands.

**Remediation:**
Add `/analyze-feedback` → `/code-review:analyze-feedback` to the bullet (optionally: "any other command named without a prefix is `/{plugin}:<name>`"), then regenerate with `python3 scripts/build_omp_edition.py`.

### [LOW] MAINT-002: Preamble's screenshot mapping yields downscaled, often WebP evidence files [verified]
**Status:** ✅ Fixed (2026-09-25)

**ID:** MAINT-002
**Location:** `omp/preamble.md:14`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
`browser_take_screenshot()` maps to `path = await tab.screenshot()` without `format`. Without a format and without `browser.screenshotDir`, OMP stores a copy scaled down to at most 1024 px, encoded as whichever of PNG, JPEG or WebP is smallest (OMP `src/tools/browser/tab-worker.ts:2632-2652`). In 7 `/qa:run` runs of the installed qa 2.6.0 OMP edition, the FE-02 failure screenshot was 1024x576 in 5 runs (4 WebP, 1 PNG); only the 2 runs whose tester passed `format='png'` saved the full 1706x960 PNG. fe-testing names evidence `qa-<NNN>.png` (`plugins/qa/skills/fe-testing/SKILL.md:119-120`).

**Impact:**
Failure evidence has reduced resolution and a file type that depends on the tester model; a tester that follows the `.png` naming literally can write WebP bytes under a `.png` name.

**Remediation:**
Map to `path = await tab.screenshot(format="png")` in `omp/preamble.md:14` and regenerate. The cmux backend does not honour this for full resolution (`src/tools/browser/cmux/cmux-tab.ts:1177-1194`); the default backend does.

### [LOW] MAINT-003: Generated fe-tester description still advertises Playwright MCP
**Status:** ✅ Fixed (2026-09-25)

**ID:** MAINT-003
**Location:** `plugins-omp/qa/agents/fe-tester.md:3`
**Category:** Maintainability
**Effort:** easy

**Problem:**
The generated description copies the source's "using Playwright MCP" (`plugins/qa/agents/fe-tester.md:3`). OMP renders agent descriptions into the `task` tool's agent list (`src/task/index.ts:160-164`), so a caller sees a capability the OMP edition does not use before the agent's preamble corrects it. The overlay schema has no description override (`AGENT_SPEC_KEYS` in `scripts/build_omp_edition.py`). Reinstated by the Challenger from the quality auditor's rejected list.

**Impact:**
The parent agent choosing a tester, and any user reading the agent list, is told FE testing needs Playwright MCP.

**Remediation:**
Do not edit the generated file. Either add a `description` key to the overlay agent spec (`AGENT_SPEC_KEYS` plus a test in `scripts/test_build_omp_edition.py`) and set an OMP description for `fe-tester` in `omp/overlay/qa.json`, or reword `plugins/qa/agents/fe-tester.md:3` edition-neutrally (that changes the Claude edition and needs a `qa` version bump in all four places). Regenerate with `python3 scripts/build_omp_edition.py`.

### [LOW] DOC-001: Preamble says screenshots always land in the OS temp directory
**Status:** ✅ Fixed (2026-09-25)
**Verification:** advisory — Grep old claim in omp/preamble.md and plugins-omp: no match, Grep OS temp directory|screenshotDir in omp/preamble.md: no match, Grep new wording in plugins-omp: 26 files total, python3 scripts/build_omp_edition.py --check: OMP edition is up to date, Read omp/preamble.md:14 (soft): ends with the decided wording
**Decision:** B — In omp/preamble.md:14 replace the closing text "returns a file in the OS temp directory: copy it with `bash` to the path the instructions name." with "returns the saved file's path: copy it with `bash` to the path the instructions name." so the bullet states no screenshot location at all, change nothing else on that line, adding no `{` or `}` because omp/preamble.md is a str.format template, then run python3 scripts/build_omp_edition.py to regenerate the 26 files under plugins-omp/ that carry the bullet, editing none of those generated files by hand. [user, 2026-09-25]
**Verification-plan:** tool: Grep pattern=`returns a file in the OS temp directory` path=omp/preamble.md;plugins-omp case=true gitignore=true → no match in any file (empty result); tool: Grep pattern=`OS temp directory|screenshotDir` path=omp/preamble.md case=true gitignore=true → no match (empty result), so the template states no screenshot location; tool: Grep pattern=`returns the saved file's path: copy it with` path=plugins-omp case=true gitignore=true skip=26 → output reports 26 files total, so every generated copy carries the new wording; `python3 scripts/build_omp_edition.py --check` [outside the read-only boundary: executes a repository script, needs the user's explicit approval before it runs] → stdout reads `OMP edition is up to date`; tool: Read path=omp/preamble.md:raw:14-14 → the excerpt quoted from omp/preamble.md:14 ends with "returns the saved file's path: copy it with `bash` to the path the instructions name." (soft)
**Decision-pin:** block=940ab9ce84217d609699980f9e9ec86680ab1d970bf79ce8afb9963420c1c413 | omp/preamble.md=0424eece0c61fa181a80863263a44de5748d711d:edit | str.format=absent:ref | scripts/build_omp_edition.py=6f86687203be2054c74cce72886b4432e2a8c392:ref | plugins-omp/=unpinnable:edit
**Dispatch:** attempt 1 dispatched 2026-09-25

**ID:** DOC-001
**Location:** `omp/preamble.md:14`
**Category:** Documentation
**Effort:** trivial
**Drift-class:** mechanical
**Fix-policy:** needs-decision

**Problem:**
The bullet says `tab.screenshot()` "returns a file in the OS temp directory". OMP writes to `browser.screenshotDir` when it is set, and to the OS temp directory otherwise (`src/tools/browser/tab-worker.ts:2645-2652`; `src/tools/browser/settings.ts:114-125`). Reinstated by the Challenger from the documentation auditor's rejected list.

**Impact:**
The instruction to copy from the returned path still works, but the location claim is false for users with `browser.screenshotDir` set.

**Remediation:**
Reword to "returns a file path (under `browser.screenshotDir` when set, otherwise the OS temp directory)" and regenerate.

## Verification Summary

**Method:** Cross-domain correlation and adversarial review (Cross-Verifier + Challenger)

| Metric | Count |
|--------|-------|
| Findings verified | 4 |
| False positives removed | 2 |
| Severity adjustments | 0 |
| Cross-analysis findings | 0 |

### Cross-Analysis (Security <-> Quality)

- SEC-001 × the removed MCP-denial finding: MCP access is understated to users while denial enforcement relies on a pre-scan; the pre-scan fails closed today.
- SEC-002 × the removed Python-only snippet finding: browser instructions are ambiguous about browser identity; the syntax part did not reproduce in 7 runs.
- SEC-002 × MAINT-002: a screenshot taken in an attached, authenticated browser would be committed as evidence under `docs/testing/reports/screenshots/`; MAINT-002 does not create that exposure.
- Coverage gap: SEC-002's safeguards do not address OMP's cmux browser selection (`src/tools/browser.ts:186-190`).
- No composite findings: every correlation needs separate changes.

### Challenged Findings

- MCP denial check parses disallowedTools a second time (`scripts/build_omp_edition.py:190-191,251-261`, LOW) — removed as false positive: `build_agent` rejects MCP denials before `map_tools` runs and the "MCP denial" subTest covers it; the finding describes a hypothetical reorder and cites no project standard.
- Browser snippets in the preamble are Python-only (`omp/preamble.md:14`, LOW) — removed as false positive: the preamble sends the tester to `xd://eval/browser`, which gives both JavaScript and Python forms; all 7 benchmark runs opened the browser, 5 of them from JavaScript cells.

### Rejected by auditors (self-falsification)

- [security] The OMP qa edition widens tester MCP scope to every session MCP server — platform constraint; the fixable part is SEC-001
- [security] Dropping MCP grants could turn a restricted agent into an unrestricted one — refuted: MCP-only `tools:` and MCP `disallowedTools` both fail the build
- [security] Hard-coded credentials in generated QA skills — documentation placeholders in unchanged skill copies; trufflehog 0
- [security] Screenshot copies left in the OS temp directory — persistent copy goes to the repo anyway; per-user tmpdir on macOS
- [security] Command injection through the screenshot `cp` — fixed name patterns; no new sink
- [security] `eval` grant exposes the `computer` prelude — off by default; fe-tester already has `bash`
- [security] qa marketplace entry has no integrity pin — same pattern as every existing entry
- [security] Managed Chromium downloaded at runtime — OMP-owned runtime dependency
- [quality] build_agent over length/complexity thresholds — pre-existing (80 lines/cc≈33 before, 88/35 after)
- [quality] Shared preamble ships the qa-only Playwright bullet to non-qa files — prescribed by the plan
- [quality] MCP-only case embedded in test_drops_mcp_grants_from_agent_tools — prescribed by the plan
- [quality] test_accepts_tester_role repeats setup — prescribed by the plan
- [quality] Preamble screenshot directory claim — superseded by DOC-001
- [quality] Playwright tools missing from the preamble mapping — only in fe-testing's inert allowed-tools line
- [quality] README's QA paragraph sits between two Delivery paragraphs — prescribed by the plan
- [quality] Dropping MCP grants widens tester MCP access — OMP platform fact, documented
- [documentation] `qa` version not bumped — deliberate; `plugins/qa/` unchanged
- [documentation] qa guide sections name Playwright MCP without edition — the new `## Oh My Pi` section states the substitution
- [documentation] Which component writes the "Playwright MCP unavailable" SKIP — runtime behaviour; outcome holds
- [documentation] fe-tester OMP description says "using Playwright MCP" — superseded by MAINT-003
- [documentation] Generator docstring omits the disallowedTools MCP rule — error text and test cover it

### Doctrine-gap candidates

- [security] MCP scope loss is silent at build time — the generator drops every `mcp__` grant without output; no rule requires listing the affected agents.
- [quality] Shared-preamble scope rule — no rule separates shared from plugin-specific preamble text; overlays cannot carry a per-plugin fragment (the qa-only bullet doubled the preamble, 2030 → 4084 bytes).
- [quality] README model-roles ↔ `MODEL_ROLES` parity — CLAUDE.md requires both; the build checks only `MODEL_ROLES`.
- [documentation] Preamble changes reach installed OMP editions only with a version bump — no rule says whether a preamble change needs a bump or a reinstall note.

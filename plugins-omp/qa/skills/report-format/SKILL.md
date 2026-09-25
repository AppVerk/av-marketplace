---
name: "qa:report-format"
description: Test report format with QA-XXX issue IDs compatible with code-review plugin. Defines report structure, severity levels, issue format, and detailed results.
---

# Test Report Format

## File Conventions

- **Location:** `docs/testing/reports/`
- **Naming:** `YYYY-MM-DD-<topic>-report.md` where `<topic>` matches the test plan topic
- **Screenshots:** `docs/testing/reports/screenshots/` (referenced from report)
- **Create directories if needed:** `mkdir -p docs/testing/reports/screenshots`

---

## Report Structure

Every test report MUST follow this structure. `## Setup gaps` is conditional: include it only when a main flow or edge case returns NEED_INFO; omit the section entirely when there are no gaps:

~~~markdown
# Test Report: <title>

## Summary
- Total: <N> | Pass: <N> | Fail: <N> | Skip: <N> | Need info: <N>
- Plan: <path to test plan file>
- Date: <YYYY-MM-DD>
- Duration: <approximate execution time>

## Setup gaps
- <kind>: `<identifier>`, `<identifier>` — <scenario IDs; use BE-01 (edge 2) for an edge gap>

## Issues Found

### [SEVERITY] QA-001: <issue title>

**ID:** QA-001
**Location:** `<source file:line>`
**Category:** Testing

**Problem:**
- Expected: <plan assertion with its grounding tag, copied verbatim>
- Actual: <what actually happened>
- Refutation: <tester Refutation trace, or the failing edge line's trace>

**Impact:**
<what breaks if unfixed — optional but recommended>

**Remediation:**
<best-effort suggestion in natural language; no code block required>

**Scenario:** <FE-XX or BE-XX>
**Response:** `<response body or error>` (BE only)
**Screenshot:** <path to screenshot> (FE only)

### [SEVERITY] QA-002: <issue title>
...

## Detailed Results

### Pass: FE-01: <scenario name>
### Pass: BE-01: <scenario name>
### Fail: BE-03: <scenario name> — see QA-001
### Skip: FE-03: <scenario name> (reason)
### Need info: BE-03: <scenario name> (credentials: STRIPE_TEST_KEY)
~~~

---

## Issue ID Assignment

**Prefix:** `QA` (all issues use the same prefix, mapped to `Category: Testing` in the code-review Category→Prefix table)

**Algorithm:**
1. Initialize counter: `qa_count = 0`
2. For each **failed assertion** (main flow and each failed edge case, in plan order):
   - Increment `qa_count`
   - Format ID as `QA-{NNN}` with zero-padded 3-digit counter
   - Example: QA-001, QA-002, QA-003

Only a failed main flow or failed edge case mints an issue; a `NEED_INFO` main flow or edge case never does, even when another assertion in its scenario fails.

**Edge case issues from a single scenario get their own ID:**
- If FE-01 main flow passes but edge case "empty form" fails → that edge case gets QA-001
- If BE-03 main flow fails AND edge case "duplicate" also fails → main flow gets QA-001, edge case gets QA-002

---

## Severity Levels

| Severity | Criteria | Examples |
|----------|----------|----------|
| **CRITICAL** | Application crash, data loss, security bypass | 500 errors, unhandled exceptions, auth bypass |
| **HIGH** | Core functionality broken, wrong data returned | Wrong status code, incorrect data in response, DB state inconsistent |
| **MEDIUM** | Non-core functionality broken, degraded UX | UI element not responding, slow response, missing validation |
| **LOW** | Cosmetic issues, minor inconsistencies | Wrong error message text, minor layout issue |

For an issue whose **failing assertion** (main `**Expected:**` or its own edge-case line) carries `(unverified — confirm at run time)`, use **LOW** regardless of ordinary wrong-data/status grading. An observed HTTP status ≥ 500 or a tester-reported crash/stack trace instead follows the normal severity rules above. Apply this per assertion, not per scenario.

---

## Issue Format Details

Each issue MUST include the canonical code-review fields:

1. **Heading:** `### [SEVERITY] QA-NNN: <title>` — severity in brackets, ID with colon, then title
2. **`**ID:** QA-NNN`** — repeated for the parser
3. **`**Location:** ` `` `path:line` `` `** — best-effort source identification (route, endpoint, stack trace). When truly unidentifiable, use placeholder `unknown:0` and add a note in `Problem`. The `/fix` command will prompt the user for the location at fix time.

   If the scenario has `**Blocked-by:** BLK-NN`, use the cited `(file:line)` in that blocker's `## Blockers / Findings` entry as Location and start the Actual bullet with `Blocked by BLK-NN: <defect>`.

   The field has two written forms. The plain form above, and the extended form the decision-gate loop writes when it corrects a location:

   ```
   **Location:** `path:line` (was: `original`)
   ```

   **Read rule, two clauses:** take the first backticked token as the location, ignoring any trailing parenthetical — this is the form the loop always writes. Where the line carries no backticked token at all — a legacy `**Location:** src/foo.ts:12`, which this loop never writes but every consumer still meets — take the first whitespace-delimited token after the field name instead. Under either clause, a value of `—`, `unknown:0`, or anything that does not parse as `path:line` or `path:line-range` is location-less.
4. **`**Category:** Testing`** — constant for QA issues; maps to the `QA` prefix in the canonical Category→Prefix table.
5. **`**Problem:**`** — bullet list with `Expected` copied verbatim from the plan's failing assertion (including its grounding tag), `Actual` (prefixed `Blocked by BLK-NN: <defect>` when applicable), and `Refutation` copied from the tester's `**Refutation:**` line or failing edge line's trace. Do not invent a trace.
6. **`**Remediation:**`** — best-effort suggestion in natural language. No code block required (the `fix-auto` agent will generate the code).

Optional fields:

- **`**Impact:**`** — what breaks if unfixed.

QA-specific extras (kept for testing context; ignored by the code-review parser):

- **`**Scenario:**`** — `FE-XX` or `BE-XX` reference
- **`**Response:**`** — response body or error message (BE only)
- **`**Screenshot:**`** — screenshot path (FE only)

---

## Example: BE Issue

~~~markdown
### [CRITICAL] QA-001: POST /api/users returns 500 instead of 201

**ID:** QA-001
**Location:** `src/api/users.py:45`
**Category:** Testing

**Problem:**
- Expected: POST /api/users with valid body should return 201 and create the user. (src/api/users.py:45)
- Actual: Endpoint returns 500 with `KeyError: 'email'` raised in `users.py:48`.
- Refutation: re-verified: yes (state re-read, no re-fire); env: n/a; scope: in; harness: ok

**Impact:**
Blocks new account creation.

**Remediation:**
Schema requires `email` but the `create_user` handler does not validate the key's presence. Add Pydantic field validation or an early 422 return for the missing field.

**Scenario:** BE-02 — Create new user with valid payload
**Response:** `{"detail": "Internal Server Error", "token": "***"}` (sanitised; full evidence: `docs/testing/reports/responses/BE-02-body.json`)
~~~

---

## Example: FE Issue

~~~markdown
### [MEDIUM] QA-002: Logout button does not respond to click

**ID:** QA-002
**Location:** `src/components/Header.tsx:23`
**Category:** Testing

**Problem:**
- Expected: clicking Logout fires POST /api/auth/logout and redirects to /login. (src/components/Header.tsx:23)
- Actual: click triggers no request; user remains logged in.
- Refutation: re-verified: yes (fresh snapshot, same result); env: n/a; scope: in; harness: ok

**Impact:**
User cannot log out — UX regression with potential security implications on shared machines.

**Remediation:**
Verify the onClick handler in `src/components/Header.tsx:23`. The most likely cause is a missing `mutate()` call or an unbound handler.

**Scenario:** FE-02 — Logout flow
**Screenshot:** `docs/testing/reports/screenshots/FE-02-fail.png`
~~~

---

## Detailed Results Format

List ALL scenarios (pass, fail, skip, need info) in plan order. Derive one verdict per scenario: `fail` if the main Status or any edge is FAIL; otherwise `need-info` if the main Status or any edge is NEED_INFO; otherwise (loop only) `auth-unverified` for a reclassified main flow; otherwise `skip` if the main Status or any edge is SKIP. The `**DB check:** SKIP` field does not count. Only when the main flow and every edge passed is the verdict `pass`. An edge gap never hides a main-flow FAIL.

For `/qa:loop` only, the sidecar keeps `auth-unverified` as its own verdict. In the report's four-count Summary and Detailed Results, display it under **Skip (auth-unverified)** so `Total = Pass + Fail + Skip + Need info`; count it separately as `auth-unverified` under Coverage. This is a reporting bucket only: never turn the sidecar verdict into `skip`, credit it as PASS, or use it as a fix candidate.

```markdown
## Detailed Results

### Pass: FE-01: Homepage renders correctly
### Pass: FE-02: Login form validation
### Fail: FE-03: Logout button — see QA-001
### Pass: BE-01: GET /api/users returns list
### Fail: BE-03: POST /api/users duplicate handling — see QA-002
### Skip: FE-05: Mobile responsive layout (out of harness scope)
### Skip: BE-06: <name> (edge 1 skipped: out of harness scope)
### Skip: BE-07: <name> (auth-unverified; main flow gated)
### Need info: BE-03: <name> (credentials: STRIPE_TEST_KEY)
### Need info: BE-05: <name> (main flow passed; edge 2 need info: fixture: users.seed)
```

- **Pass:** just the status and scenario name
- **Fail:** status, scenario name, reference to QA-XXX issue
- **Skip:** status, scenario name, reason in parentheses
- **Need info:** status, scenario name, kind and missing identifiers (main or edge); list every gap under `## Setup gaps` too

## Setup gaps (conditional)

Place directly after `## Summary` and before `## Issues Found` when any scenario or edge case returns NEED_INFO, **even if a FAIL edge/main flow wins the scenario verdict**. One bullet per kind: `- <kind>: \`<identifier>\`, \`<identifier>\` — <scenario IDs, e.g. BE-01 (edge 2)>`. Include only names/URLs, never values. No `### [SEVERITY]` headings and no `---` separators in this section. Omit it entirely if no gaps exist.

---

## Coverage (optional — written by `/qa:loop`)

An optional `## Coverage` block may appear in the Summary section, immediately after the Summary stats. It is `##`-level with **no** `### [SEVERITY]` headings and **no** `---` separators (so `/fix-report`'s block parser skips it — same rule as Loop History). Shape:

```
## Coverage
- Exercised: <feature-PASS> feature · <sanity-PASS> sanity · <negative-PASS> enforcement
- Not verified: auth-unverified <N> · need-info <M> · mutation-guard SKIP <K> · tool-unavailable <J> · …
- Confidence: <high | low — reason>
```

---

## Loop History (optional — written by `/qa:loop`)

A `##`-level section placed **AFTER** `## Detailed Results`. It MUST NOT contain any
`### [SEVERITY] …` headings or `---` separators (so `/fix-report`'s block parser
ignores it). One row per loop iteration:

`/qa:loop` appends a **Final** row for its authoritative final run, even if no fix iterations ran. In that row `Still failing` includes scenarios with open issues whose main flow passed but an edge did not, annotated `(edge need info)` or `(edge skipped)`. This row does not count as a fix iteration.

| Iteration | Failing in | Now passing | Still failing | Warnings | Regressions | Dispatches |
|------|-----------|-------------|---------------|----------|-------------|------------|
| 1 | BE-03, FE-05 | BE-03, FE-05 | — | QA-001 ⚠ | — | 4 |
| 2 | — | — | — | — | — | 2 |

Columns:
- **Iteration** — iteration number
- **Failing in** — scenarios that were failing at iteration start
- **Now passing** — scenarios that passed this iteration (newly fixed)
- **Still failing** — scenarios still failing after this iteration
- **Warnings** — comma-separated QA-XXX IDs with warnings (anti-hardcoding flags, "⚠" symbol)
- **Regressions** — scenarios that passed at baseline but failed this iteration (newly detected regressions)
- **Dispatches** — fix + re-run count for this iteration

---

## Compatibility with code-review

The QA-XXX format is identical in structure to code-review's other prefixes (SEC, PERF, ARCH, MAINT, DOC). This means:

- `/fix QA-001` works the same as `/fix SEC-001` — the `/fix` command routes by prefix to `docs/testing/reports/` instead of `docs/reviews/`.
- `/fix-report` (without an argument) auto-merges the newest report from `docs/reviews/` and the newest from `docs/testing/reports/`, presenting one unified checklist.

The `Testing → QA` row is part of the canonical Category→Prefix mapping in `docs/plugins/code-review.md`.

### Status write-back

After `/fix QA-001` or `/fix-report` resolves an issue, code-review inserts a `**Status:**` line immediately after the issue's `### [SEVERITY] QA-NNN: Title` heading, following the grammar:

```
**Status:** <icon> <text> (YYYY-MM-DD)[ — <reason>]
```

The status value is one of `✅ Fixed`, `⚠️ Partially Fixed` or `🚫 Rejected`. The ` — <reason>` tail is permitted **only** for `🚫 Rejected` — no other status value carries one — and `<reason>` is a single line with no embedded newline.

**Read rule:** a consumer matches the status value by **prefix**, never by whole-line equality — the ` — <reason>` tail is not the reader's to control, and a whole-line test would fail to recognize a rejected line it should match.

`🚫 Rejected` is terminal: a rejected issue is excluded from the fix set on every subsequent run, and its `**Status:**` line is never overwritten. Already-fixed issues (those with any `**Status:**` field) are skipped on subsequent `/fix-report` runs, so reports become living documents.

### Decision-gate fields (optional, loop-written)

`/fix-report` and `/fix-all` write six further fields into a QA report's finding block by construction, when `code-review`'s decision-gate runs a `needs-decision` finding through its analysis-and-dispatch loop. These are the finding-block schema both plugins share — see `code-review`'s `decision-gate/SKILL.md` for the full behavior behind each one — reproduced here as their written forms:

```
**Decision:** <label> — <resolution text> [<who>, <YYYY-MM-DD>; attempt N: <outcome>…]
**Decision-retired:** <label> — <resolution text> [<who>, <YYYY-MM-DD>; attempt N: <outcome>…]
**Verification-plan:** <check> → <expected>[ (soft)]; <check> → <expected>
**Decision-pin:** block=<sha256> | <path>=<pin-value>[:edit|:ref] | <path>=<pin-value>[:edit|:ref]
**Dispatch:** attempt <N> dispatched <YYYY-MM-DD>
**Verification:** hard|advisory|unavailable — <checks run>[; <N> not run: <check text>]
```

`<pin-value>` is one of exactly three forms: a **blob hash** from `git hash-object`; **`absent`**, written where the path does not exist in the working tree; or **`unpinnable`**, written where the path was rejected as unsafe to hash. The three are never written interchangeably — see `decision-gate/SKILL.md` for which is written when.

All six are **optional** fields of the schema: an existing report carrying none of them is still a valid report, and nothing here makes any of them required.

**One physical line.** Each of these lines occupies **exactly one physical line**, with no continuation line of any kind — content that does not fit is rewritten or split before it is written, never wrapped.

**Slot order.** `**Status:**` stays the first non-blank line under the finding's `### [SEVERITY] QA-NNN: Title` heading. All six of these lines are written **below** that slot, never above it.

---

## Report Quality Checklist

Before saving the report, verify:

- [ ] Summary counts match detailed verdicts (total = pass + fail + skip + need info); a passing main flow with an unrun edge does not count as pass
- [ ] Every failed scenario has a `### [SEVERITY] QA-NNN: Title` heading in the Issues Found section
- [ ] Every QA-NNN issue has the required fields: `ID`, `Location`, `Category: Testing`, `Problem` (with Expected/Actual bullets), `Remediation`
- [ ] NEED_INFO main flows and edges appear in Detailed Results and `## Setup gaps`, never as issues
- [ ] No secret value anywhere in the report or under `docs/testing/reports/responses/`
- [ ] Screenshots referenced in issues actually exist on disk
- [ ] No placeholder text (TBD, TODO)
- [ ] If a Loop History section is present, it contains no `### [SEVERITY]` headings and no `---` separators

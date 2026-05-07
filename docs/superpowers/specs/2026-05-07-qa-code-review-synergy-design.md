# Design: QA × code-review synergy

**Date:** 2026-05-07
**Status:** Draft, awaiting plan
**Plugins affected:** `qa` (2.0.0), `code-review` (1.13.0)

## Problem

When both `qa` and `code-review` plugins are installed, issues detected by `/qa:run` should be repairable through the same mechanism that handles `/review` findings — namely `/fix <ID>` and `/fix-report`. Today the two plugins emit reports in different formats and into different directories, so no shared workflow is possible. The QA report uses heading shape `### QA-001 [SEVERITY] X` and field set `Scenario / Expected / Actual / File`, while `/fix` parses `### [SEVERITY] {ID}: X` with required fields `Location / Category / Problem / Remediation`. The two are not interchangeable.

## Goals

- After running `/qa:run`, the user can fix any QA-detected issue via `/fix QA-001` (single issue, ID mode).
- After running both `/review` and `/qa:run`, the user can run `/fix-report` once and see a merged checklist of all unfixed issues from both reports.
- Status updates after fixes are written back to the correct source file (not duplicated, not lost).
- Backward compatibility for `/fix-report <path>` and `/fix <issue-block>` is preserved.

## Non-goals

- Backward-compat parser for old (pre-2.0.0) QA reports — known limitation; workaround is regenerating with `/qa:run`.
- Detecting whether `code-review` is installed before deciding the QA report format — format is uniform always.
- Sub-categories under `Testing` (e.g., FE Testing vs BE Testing) — single category, single prefix.
- Configurable report directories.
- Multi-path argument for `/fix-report` (YAGNI).
- Touching `/analyze-feedback` workflow.

## Strategy

QA stays in `docs/testing/reports/`. Code-review's fix tooling extends its scope to also operate on QA reports. The QA report format is normalized to be a strict superset of the code-review issue format — same parser, additional QA-specific fields kept as extras.

Two complementary pieces:

1. **QA report format aligns with code-review issue format.** Same heading order, same required fields. QA-specific fields (Scenario, Screenshot, Response) are additions, not replacements; the code-review parser ignores unknown fields.
2. **Code-review fix tooling becomes directory-aware.** `/fix QA-001` routes by prefix to the QA reports directory. `/fix-report` (no args) auto-merges newest reports from both directories, retaining a per-issue mapping back to its source file so status updates land in the right place.

## Scope of changes

### Files modified

| File | Change |
|---|---|
| `plugins/qa/skills/report-format/SKILL.md` | Rewrite issue template to match code-review format; resolve internal contradiction between top template and "Compatibility" section. |
| `plugins/qa/commands/run.md` | Update Step 6 (Generate Report) to reference the normalized template; replace "/fix QA-001 (coming soon)" in Step 8 with real guidance. |
| `plugins/code-review/commands/fix.md` | Phase 0: extend ID regex to include `QA`; Step 0.1: route directory by prefix. |
| `plugins/code-review/commands/fix-report.md` | Make argument optional; add auto-merge mode; track ID→source-file mapping for Step 4.1. |
| `plugins/qa/.claude-plugin/plugin.json` | Bump version 1.0.0 → 2.0.0. |
| `plugins/code-review/.claude-plugin/plugin.json` | Bump version 1.12.3 → 1.13.0. |
| `.claude-plugin/marketplace.json` | Bump versions in both plugin entries. |
| `docs/plugins/qa.md` | New "Synergy with code-review" section; update format examples. |
| `docs/plugins/code-review.md` | Add `Testing → QA` to Category→Prefix mapping; document routing in `/fix`; document auto-merge in `/fix-report`. |
| `README.md` | Bump versions in Available Plugins table; light wording update for QA. |

### Files NOT modified

- `plugins/qa/agents/{fe-tester,be-tester}.md` — agents return raw results; report formatting lives in `run.md`.
- `plugins/code-review/agents/fix-auto.md` — accepts an issue block as prompt; format-agnostic.
- Code-review auditor skills — unaffected.
- `/analyze-feedback` and the feedback-analyzer agent — separate workflow, out of scope.

## Format change for QA issues

### Heading

- Was: `### QA-001 [SEVERITY] <title>`
- Is: `### [SEVERITY] QA-001: <title>`

This matches the regex used by `/fix` Phase 1 parsing and by `/fix-report` Step 1.2 issue extraction.

### Required fields (code-review canonical)

- `**ID:** QA-001`
- `**Location:** \`path/to/file:line\``
- `**Category:** Testing` (constant — see Category→Prefix mapping below)
- `**Problem:**` — Expected/Actual rendered as bullet list inside this field
- `**Remediation:**` — best-effort suggestion in natural language; no code block required

### Optional fields

- `**Impact:**` — what breaks if unfixed
- (Not used by QA: `OWASP`, `CWE`, `Effort`, `Source`)

### QA-specific extras (kept; ignored by code-review parser)

- `**Scenario:**` — `FE-XX` or `BE-XX` scenario reference
- `**Response:**` — response body or error (BE only)
- `**Screenshot:**` — screenshot path (FE only)

### Field mapping summary

| Old QA field | New format | Notes |
|---|---|---|
| Heading `### QA-001 [SEV] X` | `### [SEV] QA-001: X` | Reorder + colon |
| — | `**ID:** QA-001` | Added |
| — | `**Category:** Testing` | Added; constant |
| `**File:** path:line` | `**Location:** \`path:line\`` | Renamed + backticks |
| `**Expected:**` + `**Actual:**` | `**Problem:**` (Expected/Actual as bullets) | Consolidated |
| — | `**Impact:**` (optional) | Added |
| — | `**Remediation:**` (best-effort) | Added |
| `**Scenario:**` | `**Scenario:**` | Kept |
| `**Response:**` | `**Response:**` | Kept (BE) |
| `**Screenshot:**` | `**Screenshot:**` | Kept (FE) |

### Example (BE)

```markdown
### [HIGH] QA-001: POST /api/users returns 500 instead of 201

**ID:** QA-001
**Location:** `src/api/users.py:45`
**Category:** Testing

**Problem:**
- Expected: POST /api/users with valid body should return 201 and create the user.
- Actual: Endpoint returns 500 with `KeyError: 'email'` raised in `users.py:48`.

**Impact:**
Blocks new account creation.

**Remediation:**
Schema requires `email` but the `create_user` handler does not validate the key's presence. Add Pydantic field validation or an early 422 return for the missing field.

**Scenario:** BE-03 — Create new user with valid payload
**Response:** `{"detail": "Internal Server Error"}`
```

### Example (FE)

```markdown
### [MEDIUM] QA-002: Logout button does not respond to click

**ID:** QA-002
**Location:** `src/components/Header.tsx:23`
**Category:** Testing

**Problem:**
- Expected: clicking Logout fires POST /api/auth/logout and redirects to /login.
- Actual: click triggers no request; user remains logged in.

**Impact:**
User cannot log out — UX regression with potential security implications on shared machines.

**Remediation:**
Verify the onClick handler in `src/components/Header.tsx:23`. The most likely cause is a missing `mutate()` call or an unbound handler.

**Scenario:** FE-05 — Logout flow
**Screenshot:** `docs/testing/reports/screenshots/qa-002-logout.png`
```

### Location handling when source file is unidentifiable

The QA agent makes a best-effort identification from route, endpoint, or stack trace. When truly impossible, use the placeholder `unknown:0` and add a note in `Problem`. Existing `/fix` Phase 1 behavior already prompts the user for a Location when missing — this path is preserved.

## Logic change in `/fix` (routing)

### Phase 0 — Input Handling

Regex update:

- Was: `^(SEC|PERF|ARCH|MAINT|DOC)-\d{3}$`
- Is: `^(SEC|PERF|ARCH|MAINT|DOC|QA)-\d{3}$`

### Phase 0 — Step 0.1 (locate report)

Replace single-directory lookup with prefix-based routing:

```
extract prefix from $ARGUMENTS  (e.g., SEC, QA)
if prefix == "QA":
    target_dir = "docs/testing/reports"
else:
    target_dir = "docs/reviews"
report_path = `ls -t {target_dir}/*.md 2>/dev/null | head -1`
```

### Error messages

- `QA` prefix, no QA reports:
  > Error: No saved QA reports found in `docs/testing/reports/`. Run `/qa:run` first, then use `/fix QA-001`.
- Other prefixes, no review reports: existing message preserved.

### Phase 8 (status update)

No structural change. Phase 8 already edits the file resolved in Step 0.2 — once Step 0.1 returns the correct file, Phase 8 transparently writes to the right place.

### Out-of-band edits

Routing is one-way per prefix. If a user manually moves a `QA-XXX` issue into a `docs/reviews/` file, `/fix QA-001` will not find it (routing always selects `docs/testing/reports/`). The symmetric case is also true: a `SEC-001` issue manually placed under `docs/testing/reports/` will not be reachable by `/fix SEC-001`. Workaround for both: legacy paste mode (`/fix <full block>`). Documented as expected behavior.

## Logic change in `/fix-report` (auto-merge)

### Argument

- Was: `<path-to-review-report>` (required)
- Is: `[path-to-review-report]` (optional)

### Modes

| Input | Behavior |
|---|---|
| Empty | **Auto-merge** — newest from `docs/reviews/` + newest from `docs/testing/reports/` |
| Single path | **Single-file** — existing behavior |

### Step 1.1 — resolve files

```
if $ARGUMENTS empty:
    newest_review = `ls -t docs/reviews/*.md 2>/dev/null | head -1`
    newest_qa     = `ls -t docs/testing/reports/*.md 2>/dev/null | head -1`
    files = [f for f in [newest_review, newest_qa] if f]
    if not files:
        error: "No reports found in docs/reviews/ or docs/testing/reports/. Run /review or /qa:run first."
        stop
else:
    files = [$ARGUMENTS]
    if file not exists: error (existing message)
```

### Step 1.2 — extract with source mapping

Iterate over `files`. For each, read content and run the existing Step 1.2 extraction; the existing Step 1.3 (filter fixed) and Step 1.4 (flag untrusted-provenance) are applied per file. **The change to Step 1.2: every emitted issue carries `source_file = current file path`** so Step 4.1 knows which file to edit. Steps 1.3, 1.4, and 1.5 are otherwise unchanged.

### Step 2 — checklist

In auto-merge mode (>1 source file), append the source basename to each option's `description` for clarity:

```
description: "src/db/queries.py:42 — ... · 2026-05-07-feature-auth.md"
```

In single-file mode, omit the basename hint (existing behavior).

Pagination, severity sorting, and ID surfacing in labels are unchanged.

### Step 3 — fix execution

No change. The `fix-auto` subagent receives an issue block and is unaware of source.

### Step 4.1 — status updates

For each Fixed / Partially Fixed issue, edit `issue.source_file` (from Step 1.3) — not a single global report path. The Edit tool is invoked per-issue; multiple files may be touched in one run.

### Step 4.2 — summary

Replace single `**Report updated:**` line with a list:

```
**Reports updated:**
- docs/reviews/2026-05-07-feature-auth.md
- docs/testing/reports/2026-05-07-user-flow-report.md
```

In single-file mode the list contains one element — backward compatible.

## Category → Prefix mapping

`docs/plugins/code-review.md` is the single source of truth. Add one row:

| Category | Prefix |
|---|---|
| Security | SEC |
| Performance | PERF |
| Architecture | ARCH |
| Maintainability | MAINT |
| Documentation | DOC |
| **Testing** | **QA** |

## Versioning

| Plugin | From | To | Reason |
|---|---|---|---|
| `qa` | 1.0.0 | **2.0.0** | Per `CLAUDE.local.md`: "MAJOR — incompatible formats". The heading and required-fields contract changes; old reports do not parse with the new tooling. Acceptable break point given low adoption at 1.0.0. |
| `code-review` | 1.12.3 | **1.13.0** | MINOR. New ID prefix, optional argument on `/fix-report`, new mapping row. All backward compatible. |

## Edge cases

| # | Situation | Behavior |
|---|---|---|
| 1 | `/fix-report` no args, no files in either dir | Error message guiding user to `/review` or `/qa:run`. |
| 2 | `/fix-report` no args, files in only one dir | Use the one that exists, no warning. |
| 3 | `/fix-report` no args, files of vastly different ages | No warning. User can pass explicit path if a different file is wanted. |
| 4 | `/fix QA-001` no QA reports | QA-specific error message (see "Error messages" above). |
| 5 | `/fix QA-001` ID not present in newest QA report | Existing Step 0.5 lists available IDs; no edit. |
| 6 | Pre-2.0.0 QA report present | Not parseable by `/fix` or `/fix-report`. Documented limitation; workaround is regeneration via `/qa:run`. |
| 7 | Issue with placeholder `unknown:0` Location | Existing `/fix` Phase 1 behavior — ask user for Location. |
| 8 | Same ID in both files (manual collision) | Keep both entries with separate `source_file`; status updates write to each file independently. No deduplication. |
| 9 | `docs/testing/reports/` contains subdirs (e.g. `screenshots/`) | `ls -t docs/testing/reports/*.md` does not descend; subdirs ignored. |
| 10 | Issue missing required parser fields | Existing Phase 1 behavior — prompt user for missing fields. |

## Open questions

None at this time.

## Risks

- **QA users at 1.0.0 with persisted reports** — they lose `/fix` compatibility with old reports. Mitigated by: (a) regeneration is cheap (`/qa:run`), (b) major version signals the break clearly.
- **Subtle parser differences between `/fix` Phase 1 and `/fix-report` Step 1.2** — both rely on the same heading regex but extract slightly different field sets. Risk that QA fields render correctly in one but not the other. Mitigation: both routes test against the same example QA issue block during implementation.
- **Path globbing edge cases on different shells** — `ls -t pattern | head -1` is sensitive to no-match. The existing code-review path already uses `2>/dev/null` redirection, which we replicate.

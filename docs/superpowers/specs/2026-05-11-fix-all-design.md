# Design: `/fix-all` command for `code-review` plugin

**Date:** 2026-05-11
**Plugin:** `code-review`
**Version bump:** 1.14.4 → 1.15.0 (MINOR — new command)
**Author:** Marian Szenfeld (with Claude Code)

---

## 1. Problem

The `code-review` plugin offers two ways to apply fixes from a saved report:

- `/fix <ID|block>` — fixes a single issue with per-issue Phase 3 approval.
- `/fix-report [path]` — presents unfixed issues as a paginated checklist (4 per page) for manual selection.

Neither handles the common case "I just ran `/review` (and `/qa:run`), I trust the report, fix everything." Today this requires clicking through every page of the checklist with select-all on each. `/fix-all` closes that gap.

## 2. Scope (decided)

| Decision | Choice |
|---|---|
| Scope | Fix every unfixed issue, with optional **severity floor** (CRITICAL / HIGH / MEDIUM / LOW). No category filter. |
| Safety model | Single pre-flight summary + one yes/no confirmation. No per-issue approval, no flag to skip the gate. |
| Feedback-origin issues (`**Source:**` present) | Included as equals. Pre-flight shows `Source` column with `@handle`, but no "untrusted" framing. |
| Architecture | New dedicated command file `commands/fix-all.md`. Does **not** modify `/fix-report`, `/fix`, or `fix-auto`. |
| Cross-command consistency | `/fix` and `/fix-report` keep their existing "untrusted-provenance" wording. `/fix-all` is intentionally less alarmist. A future spec may unify the framing across commands. |

## 3. Out of scope

- Parallel execution (sequential only, matching `/fix-report`).
- Stop-on-first-failure mode (always continue).
- Severity floor flag for `/fix-report` (separate command, separate spec).
- Untrusted-provenance refactor in `/fix` / `/fix-report` (separate spec).
- Modifying `fix-auto` agent (it already accepts a single issue block and ignores `Source`).

## 4. File: `plugins/code-review/commands/fix-all.md`

### 4.1 Frontmatter

```yaml
---
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(git:*), Bash(pytest:*), Bash(ruff:*), Bash(mypy:*), Bash(semgrep:*), Bash(npm test:*), Bash(eslint:*), Bash(tsc:*), Bash(bandit:*), Bash(trufflehog:*), Bash(command:*), Bash(jq:*), TaskCreate, TaskUpdate, TaskList, AskUserQuestion, Task
description: Fix every unfixed issue from a review/QA report after a single yes/no confirmation. Optional severity floor.
model: opus
argument-hint: [CRITICAL|HIGH|MEDIUM|LOW] [path-to-report]
---
```

Tool list mirrors `/fix-report`. Required additions: none — all bash/edit/task/ask tools already present there.

### 4.2 Argument grammar

`$ARGUMENTS` is split on whitespace into tokens. Each token is classified:

| Token | Regex | Classification |
|---|---|---|
| Severity | `^(CRITICAL\|HIGH\|MEDIUM\|LOW)$` (case-insensitive, normalize to upper) | `severity_floor` |
| Anything else | — | candidate path |

Rules:

1. **At most one severity token.** Two severity tokens → error: `Multiple severities provided: 'X' and 'Y'. Pass at most one.`
2. **At most one path token.** Two distinct path tokens → error: `Multiple paths provided: 'X' and 'Y'. Pass only one.`
3. **Non-severity tokens always classify as `path`** (no third "unrecognized" branch). A typo like `/fix-all HIG` becomes a single-file invocation with `path = "HIG"`; the failure surfaces from Step 1.1 as `Could not read file 'HIG'. Make sure the path is correct and the file exists.` This keeps the grammar resolution-free — no path-shape heuristic is needed.
4. Token **order is free** — `/fix-all HIGH foo.md` and `/fix-all foo.md HIGH` are equivalent.
5. Empty `$ARGUMENTS` → both `severity_floor` and `path` unset; auto-merge mode.
6. **Whitespace in paths is not supported.** `$ARGUMENTS` is tokenized by whitespace and the command file frontmatter does not currently define a quoting convention. A path like `docs/my reports/foo.md` splits into two tokens and triggers Rule 2 ("Multiple paths provided"). Workaround: rename the directory or symlink it to a whitespace-free location. (Tracked in Section 8.)
7. **Files literally named `CRITICAL` / `HIGH` / `MEDIUM` / `LOW`** match the severity regex first and never reach the path branch. To target them, prefix with `./` (e.g., `./HIGH`) so the token no longer matches the severity regex.

**Severity floor semantics:** the floor includes itself and everything *above* it. `HIGH` matches HIGH+CRITICAL. `MEDIUM` matches MEDIUM+HIGH+CRITICAL. `LOW` matches all four levels (equivalent to no filter, but accepted for explicitness).

### 4.3 Progress tasks

Created up-front via `TaskCreate`:

| # | subject | activeForm |
|---|---|---|
| 1 | Parse report(s) | Parsing report(s)... |
| 2 | Filter and pre-flight | Building pre-flight summary... |
| 3 | Fix all issues | Fixing all issues... |
| 4 | Update reports and summarize | Updating reports and summarizing... |

After creation, task 1 is set `in_progress`. Each subsequent step completes the previous task and starts the next, exactly as in `/fix-report`.

### 4.4 Step 1 — Parse report(s)

Bit-for-bit reuse of `/fix-report` Step 1. The sub-steps are:

- **1.1 Resolve files to read** — **auto-merge mode** (path token absent — applies whether or not a severity token is present) takes `ls -t docs/reviews/*.md | head -1` and `ls -t docs/testing/reports/*.md | head -1`, filters empty paths; **single-file mode** (path token provided) reads only that path. So `/fix-all`, `/fix-all HIGH`, and `/fix-all CRITICAL` all auto-merge; `/fix-all foo.md` and `/fix-all HIGH foo.md` are single-file. Same error messages as `/fix-report`: "No reports found" / "Could not read file '<path>'".
- **1.2 Extract issues with source mapping** — scan each file for `### [SEVERITY] Title` headings (CRITICAL / HIGH / MEDIUM / LOW); for each issue block (heading until next `###` / `---` / EOF), tag with `source_file = <currently-being-read path>`. Aggregate across files.
- **1.3 Filter already-fixed** — drop issues with `**Status:** ✅ Fixed` or `**Status:** ⚠️ Partially Fixed`.
- **1.4 Flag feedback-origin (informational)** — for each issue, record `source_handle` if the block contains a `**Source:** @<handle> — [PR #N comment](URL)` field. The handle is used by Step 2.4 to populate the `Source` column. **Do not** apply any "untrusted" gating, warning, or special handling — this command intentionally diverges from `/fix-report` Step 1.4 (which embeds the "Untrusted provenance" block quote from `docs/plugins/code-review.md#untrusted-provenance`). The flag here is purely informational. The decision and its cross-command consistency trade-off are documented in Section 2 of this spec.
- **1.5 Edge cases** — no issue sections at all → "No issues found in the report(s)…" + stop. All issues already have `**Status:**` → "All issues in the report(s) have been resolved. Nothing to do." + stop.

Within Step 1, the only divergence from `/fix-report` is Step 1.4's wording — replaces the "Untrusted provenance" block quote with a one-sentence note that surfacing `Source:` is informational. (Step 2's pre-flight summary, defined in Section 4.5, is structurally new versus `/fix-report` Step 2's paginated checklist — that divergence is intentional and is the core of this spec.)

### 4.5 Step 2 — Filter & pre-flight summary

- **2.1 Parse `$ARGUMENTS`** per Section 4.2. Validation errors stop the command and mark remaining tasks completed.
- **2.2 Apply severity floor** to the issue list from Step 1.
- **2.3 Sort issues** CRITICAL → HIGH → MEDIUM → LOW. Within a severity, preserve the order they appeared in their source files (stable sort). When issues come from multiple source files (auto-merge mode), the inter-file tie-break within a severity follows the order of `files` from Step 1.1 — i.e., the review file first, then the QA file.
- **2.4 Build & render pre-flight summary.** Format:

````markdown
## Pre-flight: Fix All Issues

**Reports:** <comma-separated list of source files, basenames>
**Severity floor:** <FLOOR>   ← omit line if no filter
**Total to fix:** <N> issues

**By severity:**
| CRITICAL | HIGH | MEDIUM | LOW |
|----------|------|--------|-----|
|    <n>   | <n>  |  <n>   | <n> |   ← cells with 0 render as "—"

**Issues:**

| # | ID | Severity | Title | Location | Source | Report |
|---|----|----------|-------|----------|--------|--------|
| 1 | ... | ... | ... | path:line | @handle or — | basename |
````

  Rendering rules:
  - `Severity floor:` line omitted when no filter.
  - `Source` column omitted entirely when *zero* issues in the filtered list have `**Source:**`. When present, shows `@handle` for feedback-origin issues and `—` for others.
  - `Report` column shown only when the source-file set has >1 distinct file (auto-merge with both report types present).
  - Titles longer than 60 chars are truncated to 60 chars + `…`.
  - **Full list always rendered** (no "and N more" truncation).
  - `Location` is taken from the issue's `**Location:**` field; if missing (rare), render `—`.

- **2.5 Confirmation gate.** Use `AskUserQuestion` with one question:

  ```
  question: "Proceed with fixing all <N> issues sequentially?"
  options:
    - label: "Yes — fix all <N>"
      description: "Run fix-auto on every listed issue, mark sources after each."
    - label: "No — abort"
      description: "Stop now without modifying any files."
  ```

  If the user picks "No" (or any non-yes value), output `Aborted. No changes made.`, mark remaining tasks completed, and stop.

- **2.6 Edge case — zero issues after filter.** If the list produced by Step 2.2 (after severity floor is applied) is empty, skip rendering the pre-flight entirely and skip the confirmation gate. Output `No issues match severity floor '<FLOOR>'. Nothing to fix.`, mark remaining tasks completed, and stop. This branch is reachable only when `severity_floor` is set — if it's unset and the list is empty, Step 1.5 has already terminated the command with "All issues … have been resolved" or "No issues found".

### 4.6 Step 3 — Sequential fix execution

For each selected issue, in the sorted order from Step 2.3:

1. Invoke the `code-review:fix-auto` subagent via the `Task` tool:
   - `subagent_type: "code-review:fix-auto"`
   - `run_in_background: false`
   - `description: "Auto-fix: [<SEVERITY>] <Title>"`
   - `prompt: <full issue block>` (everything captured in Step 1.2 for this issue — heading line + body up to the next `###` / `---` / EOF; includes `**Source:**` if present so the agent has the same context as in `/fix-report`)
2. Parse the agent's response to determine status: `Fixed` / `Partially Fixed` / `Failed`. If the subagent errors, treat as `Failed`.
3. Store status keyed to the issue's `source_file` and ID.
4. **Continue on failure.** Do not stop; proceed to the next issue.

### 4.7 Step 4 — Update reports & summarize

- **4.1 Mark fixed issues.** For each issue with status `Fixed` or `Partially Fixed`, edit its `source_file` to insert a status line immediately after the `### [SEVERITY] ID: Title` heading:
  - Fixed → `**Status:** ✅ Fixed (YYYY-MM-DD)`
  - Partially Fixed → `**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)`
  - Failed → no edit; the issue will appear again on the next `/fix-all` or `/fix-report` run.

  Date format `YYYY-MM-DD`, today's date. Uses the `Edit` tool with `old_string = "<heading>\n"` and `new_string = "<heading>\n**Status:** ... (YYYY-MM-DD)\n\n"`. This recipe correctly handles both review reports (heading line immediately followed by `**Location:**` or another field) and QA reports (heading followed by a blank line before `**ID:**`) — matching the strategy documented in `commands/fix.md` Step 8.2 and used by `commands/fix-report.md` Step 4.1. May invoke `Edit` against multiple files in a single run (auto-merge).

- **4.2 Display summary.**

  ```markdown
  ## Fix Summary

  | # | Issue | Status |
  |---|-------|--------|
  | 1 | [SEVERITY] ID: Title — path:line | <icon> <text> |
  ...

  **Fixed:** <n> | **Partially Fixed:** <n> | **Failed:** <n>
  **Reports updated:**
  - <source-file-1>
  - <source-file-2>   ← only files that received a Status write; deduplicated; omit list if none
  ```

  Status icons: Fixed = ✅, Partially Fixed = ⚠️, Failed = ❌.

## 5. Plugin metadata changes

| File | Change |
|---|---|
| `plugins/code-review/.claude-plugin/plugin.json` | `"version": "1.14.4"` → `"1.15.0"`. Optionally extend `description` to mention `/fix-all` (current line is 250+ chars already — keep it tight). |
| `README.md` | Available Plugins table — update `code-review` row's description if the one-liner needs to mention `/fix-all`. (Likely yes: append "Bulk-fix via `/fix-all`".) |
| `docs/plugins/code-review.md` | New `### /fix-all` section between `/fix-report` and `/analyze-feedback`, with: synopsis, argument grammar examples, pre-flight description, behavior vs `/fix-report`, link back to existing `Category → Prefix mapping`. |
| `.claude-plugin/marketplace.json` | **No change** (new command in existing plugin, not a new plugin). |

## 6. Files explicitly *not* changed

- `commands/fix.md` — unchanged.
- `commands/fix-report.md` — unchanged.
- `commands/review.md` — unchanged.
- `commands/analyze-feedback.md` — unchanged.
- `agents/fix-auto.md` — unchanged (already accepts a single issue block).
- All `skills/` and `scripts/` — unchanged.

## 7. Manual test plan

No unit tests (markdown command file). Manual scenarios — to be run before bumping version:

1. **Empty repo (no reports):** `/fix-all` → error "No reports found…". ✅ inherit from `/fix-report`.
2. **Auto-merge, zero matching after filter:** Run `/review` to produce a report with no CRITICAL issues, then `/fix-all CRITICAL` → "No issues match severity floor 'CRITICAL'. Nothing to fix."
3. **Single-file mode with bad path:** `/fix-all docs/does-not-exist.md` → error "Could not read file…".
4. **Malformed args:** `/fix-all HIG` → classifies as a path per Rule 3, then Step 1.1 errors `Could not read file 'HIG'…`. `/fix-all CRITICAL HIGH` → "Multiple severities…". `/fix-all a.md b.md` → "Multiple paths…".
5. **Happy path, auto-merge:** create a review with 2 small issues and a QA report with 1 issue, run `/fix-all`. Verify: pre-flight shows both report basenames + `Report` column; yes; all three issues fixed; both source files get `**Status:** ✅ Fixed` lines; summary lists both files under "Reports updated".
6. **Source column hidden:** report with no `**Source:**` fields → `Source` column not rendered.
7. **Source column shown:** feedback report with mixed origin → `Source` column shows `@handle` and `—`. No "untrusted" / "feedback" / warning text appears.
8. **Abort path:** any report, `/fix-all`, answer "No" → "Aborted. No changes made." No file edits.
9. **Mixed outcomes:** one issue fails (e.g., file moved between report and run), one succeeds → summary shows 1 Fixed + 1 Failed; only the Fixed one gets a `**Status:**` line; failed one appears again on re-run.
10. **Severity floor reduces list:** report with CRITICAL/HIGH/MEDIUM issues, `/fix-all HIGH` → only CRITICAL+HIGH appear in pre-flight; MEDIUM left alone.
11. **Severity floor over a partially-fixed report:** start with a report containing 3 unfixed (1 CRITICAL, 1 HIGH, 1 MEDIUM) plus 1 already-`**Status:** ✅ Fixed` HIGH issue. Run `/fix-all HIGH` → pre-flight lists the unfixed CRITICAL and HIGH only; the resolved HIGH and the MEDIUM are absent. Validates that Step 1.3 (filter fixed) and Step 2.2 (severity floor) compose cleanly.
12. **File literally named `HIGH`:** create `./HIGH` (a real file with one issue). `/fix-all HIGH` → severity floor HIGH, auto-merge mode (no path). `/fix-all ./HIGH` → single-file mode reading `./HIGH`. Confirms Rule 7's workaround.
13. **Path with whitespace:** `/fix-all "docs/my reports/foo.md"` → "Multiple paths provided: 'docs/my' and 'reports/foo.md'…" (the shell strips the quotes before they reach `$ARGUMENTS`). Confirms Rule 6's documented limitation rather than silently producing wrong behavior.
14. **Long-title truncation:** report containing an issue whose title is ≥80 chars → pre-flight `Title` column shows the first 60 chars + `…`. Other columns unaffected. Confirms Section 4.5 truncation rule.

## 8. Open risks & mitigations

| Risk | Mitigation |
|---|---|
| User runs `/fix-all` on a 50-issue report by mistake. | Single yes/no gate is the only line of defense; pre-flight shows full counts and totals so the scale is visible before confirming. Acceptable trade-off per Section 2 decision. |
| Sequential 30-issue run is slow (10–30 min). | Documented in `docs/plugins/code-review.md`; user can `Ctrl+C` between fixes (each subagent call is independent, partial state persists in modified files + already-written `**Status:**` lines). |
| Cross-command framing inconsistency: `/fix` and `/fix-report` say "untrusted", `/fix-all` does not. | Documented in Section 2 + spec section "Cross-command consistency". A follow-up spec may unify the wording — explicitly out of scope here. |
| `fix-auto` failure leaves the working tree in a partial state. | Inherited from `/fix-report`: changes are uncommitted, user retains full `git diff` / `git checkout` control. Documented in summary's `Failed` row guidance (reuse wording from existing fix flow). |
| User passes a path that's an existing file *and* matches a severity name (e.g., a file literally named `HIGH`). | Severity tokens are matched first by regex; `HIGH` will always classify as severity, never as path. Section 4.2 Rule 7 documents the `./HIGH` workaround; Section 7 scenario 12 validates it. |
| Path contains whitespace (e.g., `docs/my reports/foo.md`). | `$ARGUMENTS` whitespace tokenization splits the path, triggering "Multiple paths provided" rather than silently reading the wrong file. Section 4.2 Rule 6 documents the limitation; Section 7 scenario 13 validates it. Workaround: rename the directory, symlink, or use a whitespace-free path. |

## 9. Acceptance criteria

- `plugins/code-review/commands/fix-all.md` exists, frontmatter and all 4 steps match Sections 4.1–4.7.
- `plugin.json` version is `1.15.0`.
- Manual scenarios 1–14 from Section 7 all pass.
- `docs/plugins/code-review.md` documents the command including the no-"untrusted"-framing decision.
- `README.md` Available Plugins row reflects the new command (or, if the one-liner is unchanged, the maintainer has confirmed no update is needed).
- `/fix-report` and `/fix` behavior is byte-identical to before the change (regression check: run `/fix-report` on a sample report — checklist still appears, fixes still work).

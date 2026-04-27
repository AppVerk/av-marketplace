# `/analyze-feedback` — Issue Persistence in Code Review Format

**Date:** 2026-04-23
**Plugin:** code-review
**Version bump:** 1.10.0 → 1.11.0 (MINOR)

## Summary

Extend `/analyze-feedback` so that PR comments classified as "Address" produce issue blocks in the same format as `/review` and land in a file under `docs/reviews/`. The resulting file is compatible with `/fix` and `/fix-report`, so feedback-driven work goes through the same fix pipeline as review-driven work.

Reject classification and Phase 6 (publish draft responses) remain unchanged.

## Goals

- Address comments become actionable issue blocks with IDs (`SEC-001`, `PERF-002`, etc.) consistent with `/review` output.
- Feedback issues live alongside review issues in `docs/reviews/`, so `/fix-report <path>` handles them uniformly.
- A traceability link from the issue back to the original PR comment is preserved.

## Non-goals

- Posting GitHub replies on Address comments (e.g. "tracked as SEC-042"). Phase 6 stays Reject-only.
- Changes to `/review` command or the review file format.
- Integration with Linear or other external trackers.
- Deduplication across repeated `/analyze-feedback` runs on the same PR.

## Design

### Changes to `feedback-analyzer` agent

The agent keeps its current output for Reject. For Address, it additionally emits an issue block in the `/review` format.

**Output format for Address:**

```markdown
**Classification:** ✅ Address

**Reasoning:** [2-3 sentences — as today]

**Issue Block:**

### [SEVERITY] {CATEGORY-PREFIX}-XXX: Title

**ID:** {CATEGORY-PREFIX}-XXX
**Location:** `path/to/file.py:42`
**Category:** Security | Performance | Architecture | Maintainability | Documentation
**Effort:** trivial | easy | medium | hard
**Source:** @reviewer — [PR #123 comment](https://github.com/.../pull/123#discussion_rXXX)

**Problem:**
What is wrong (synthesis of the comment plus code context).

**Impact:**
What could happen if this is not addressed.

**Remediation:**
Concrete description of the change; optional code example.
```

**Key rules:**

- **ID placeholder** — the agent outputs `{CATEGORY-PREFIX}-XXX` with a literal `XXX`. The real number is assigned by the command in Phase 5.5, so numbering stays consistent with the target file.
- **Category mapping** — agent maps each Address comment to one of `Security`, `Performance`, `Architecture`, `Maintainability`, `Documentation` (matching `/review` categories). No new prefix is introduced.
- **Severity** — agent assigns `CRITICAL | HIGH | MEDIUM | LOW` based on the substance of the comment (matching `/review` methodology), not the reviewer's wording.
- **OWASP / CWE** — included only when genuinely applicable (e.g. a SQL injection comment). Omitted otherwise.
- **Source** — always includes `@author` and `html_url` link from the GitHub comment API response.

**Agent input additions:**

The context bundle passed to the agent includes `comment_id` and `html_url` (already fetched via `gh api`) so the Source field can be constructed.

### Changes to `/analyze-feedback` command

Phase 1–4 and Phase 6 are unchanged. A new Phase 5.5 is inserted between Phase 5 (Generate Report) and Phase 6 (Publish Responses).

**Phase 5.5 runs only when `to_address` is non-empty.**

#### Step 5.5.1: Locate target file

1. Fetch the PR's head branch name:

   ```bash
   gh pr view <pr_number> --json headRefName --jq '.headRefName'
   ```

2. Slugify using the same rules as `/review` (`/` → `-`, spaces → `-`, lowercase).
3. Glob `docs/reviews/*-<slug>*.md`. If multiple matches, pick the newest by `mtime`.
4. Resolve mode:
   - **File found** → `append` mode, target is that file.
   - **No match** → `create` mode, target is `docs/reviews/YYYY-MM-DD-<slug>-feedback.md`. The `-feedback` suffix distinguishes files created by this command from `/review` output. Name collisions append `-2`, `-3` (mirrors `/review`).

**Fallback:** if `gh pr view --json headRefName` fails (auth/permissions), fall back to `git branch --show-current` and add a warning to the report.

#### Step 5.5.2: Compute starting IDs per category

- **Append mode:** scan the target file with the regex `^### \[[A-Z]+\] ([A-Z]+)-(\d+):` and, for each category prefix found, record `max(NNN)`. Start each category's counter at `max + 1`. Categories without existing entries start at `001`.
- **Create mode:** all counters start at `001`.

#### Step 5.5.3: Assign IDs to issue blocks

For each issue block from `to_address` (in the order they appear):

- Read the `Category:` field to determine the prefix.
- Replace the `XXX` placeholder in both the `### [SEVERITY] {PREFIX}-XXX:` heading and any `**ID:** {PREFIX}-XXX` line with a zero-padded 3-digit counter value.
- Increment the counter.

**Validation fallback:** if a block is missing required fields (`Location`, `Category`) or its category is not in the allowed list, log a warning and revert that single comment to the reasoning-only form in the user report. The rest of Phase 5.5 continues normally.

#### Step 5.5.4: Write to file

**Append mode** — append to the end of the target file:

```markdown
---

## Feedback Issues — PR #{pr_number} ({YYYY-MM-DD})

[issue blocks separated by `---`]
```

The grouping header shows which run produced which issues. Repeated runs add new `## Feedback Issues — ...` sections with their own dates.

**Create mode** — write a new file with a minimal header plus the same grouping section:

```markdown
# Feedback Analysis: PR #{pr_number} — "{pr_title}"

**Repository:** {owner}/{repo}
**PR Author:** @{pr_author}
**URL:** {pr_url}

---

## Feedback Issues — PR #{pr_number} ({YYYY-MM-DD})

[issue blocks separated by `---`]
```

#### Step 5.5.5: Extend user-facing report

The `### ✅ To Address` section in Phase 5 output is replaced with a shorter form:

```
#### SEC-042 [HIGH]: Title — `path:line`
> @reviewer: "excerpt of the comment..."

**Reasoning:** ...
```

Full issue blocks are in the file — no duplication. At the end of the report, add:

```
**Issues saved to:** `docs/reviews/2026-04-23-feature-x-feedback.md` (3 new issues)
**Next:** `/fix-report docs/reviews/...` or `/fix <first-id>`
**Validation warnings:** {list of per-comment warnings from Step 5.5.3, if any}
```

> **Note:** The exact rendering is normative in `plugins/code-review/commands/analyze-feedback.md` Phase 5.5.5; this spec describes intent only. If the two drift, the command file wins.

### Flow summary

```
/analyze-feedback 123
  ├─ Phase 1-4: fetch comments, gather context, analyze (unchanged)
  │    └─ each Address comment → feedback-analyzer → reasoning + issue block (ID=XXX)
  │
  ├─ Phase 5: Generate Report (shortened Address form; Reject unchanged)
  │
  ├─ Phase 5.5: Persist Issues (new; only when to_address > 0)
  │    ├─ 5.5.1 Locate file (gh pr view headRefName → slug → glob → newest)
  │    ├─ 5.5.2 Compute starting IDs per category (max+1 or 001)
  │    ├─ 5.5.3 Replace XXX → NNN in each block
  │    ├─ 5.5.4 Append/create file with "## Feedback Issues — PR #N (date)" section
  │    └─ 5.5.5 Report "Issues saved to: ..." + /fix-report hint
  │
  └─ Phase 6: Publish Responses (Reject only — unchanged)
```

## Edge cases

| Situation | Handling |
|-----------|----------|
| All comments classified Reject | Phase 5.5 skipped entirely; no file created; Phase 6 runs as today. |
| `/analyze-feedback 999` run from a branch other than the PR's | File located via `headRefName` from the API, not local git — works correctly. |
| `gh pr view --json headRefName` fails | Fall back to `git branch --show-current`, warn in the report. |
| Multiple matching review files (`...-2.md`, `...-3.md`) | Pick newest by `mtime`. |
| Create-mode name collision | Append numeric suffix (`-2`, `-3`, ...) until a free name is found. |
| Agent returns malformed issue block | Per-issue fallback to reasoning-only form; remaining blocks persist normally. |
| Re-running `/analyze-feedback` on same PR | Appends a new `## Feedback Issues — PR #N (date)` section with fresh IDs. Duplicates accepted in this iteration; deduplication by `comment_id` is future work. |

## Risks and mitigations

1. **Regex miss on hand-edited files.** If someone manually changed review headings, the ID scan may miss entries. Mitigation: regex is precise; worst case a new category starts over from `001` inside an already-used range, which `/fix-report` still parses correctly.
2. **Branch rename between `/review` and `/analyze-feedback`.** Slug may not match. Mitigation: glob is liberal; worst case a new `-feedback.md` file is created — no data loss.
3. **Agent drift.** If the agent stops following the block schema, persistence breaks. Mitigation: per-issue validation with fallback; we do not disable Phase 5.5 on a single malformed block.

## Manual test plan

These scenarios must be run before claiming the work complete.

1. **Create mode** — PR on a fresh branch with no prior `/review`. Expected: new `docs/reviews/YYYY-MM-DD-<slug>-feedback.md`; IDs start at `001` per category.
2. **Append mode** — run `/review` + save, then `/analyze-feedback` on the same branch. Expected: existing file gets a new `## Feedback Issues — ...` section; IDs continue from `max + 1` per category.
3. **Mixed Address + Reject** — PR with both kinds of comments. Expected: file contains only Address blocks; terminal report shows both; Phase 6 offers publish only for Reject drafts.
4. **Reject only** — Phase 5.5 skipped; no file created.
5. **`/fix-report` on the resulting file** — expected: feedback issues appear in the checklist; `fix-auto` runs; `**Status:** ✅ Fixed (YYYY-MM-DD)` lines are added.
6. **Create-mode collision** — run twice in a row; second file gets `-2` suffix.
7. **PR from different branch** — run `/analyze-feedback 999` while checked out on `master`; target file is located via PR's head branch, not `master`.

## Documentation updates

- `docs/plugins/code-review.md` — extend the `/analyze-feedback` section with:
  - Statement that Address issues are persisted to `docs/reviews/` in a format compatible with `/fix` and `/fix-report`.
  - Example output paths for create vs. append modes.
  - Note about the `Source` field and ID continuation.
- `README.md` — bump the `code-review` row in the Available Plugins table to `1.11.0`.
- `plugins/code-review/.claude-plugin/plugin.json` — bump `version` to `1.11.0`.

## Out of scope (tracked for future work)

- Posting "tracked as {ID}" replies on Address comments in GitHub.
- Deduplication of re-runs by `comment_id`.
- Linking issues to external trackers (Linear, Jira).
- Per-PR file naming convention including PR number (would require changes to `/review`).

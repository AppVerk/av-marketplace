# Code Review — `feature/analyze-feedback-issue-persistence`

**Date:** 2026-04-23
**Branch:** `feature/analyze-feedback-issue-persistence` (8 commits diverged from `master`)
**Scope:** Phase 5.5 "Persist Issues" in `/analyze-feedback` + agent schema extension + docs/versioning
**Files changed:** 6 (all markdown + JSON — no runnable code)
**Plugin bump:** `code-review` 1.10.0 → 1.11.0 (MINOR)
**Overall assessment:** Feature works for the happy path; review surfaced 1 HIGH, 6 MEDIUM, 10 LOW issues after verification. Two original HIGH/CRITICAL claims were challenged and downgraded (symlink attack false positive, shell-injection false positive).

## What changed

- `plugins/code-review/commands/analyze-feedback.md` — +200 lines: added Phase 5.5 with locate-file (5.5.1), ID numbering (5.5.2/3), file append/create (5.5.4), footer render (5.5.5)
- `plugins/code-review/agents/feedback-analyzer.md` — +119 lines: Address-mode Issue Block schema with `Source`, Category→Prefix mapping, severity rubric
- `docs/plugins/code-review.md` — +31/-5 lines: "Issue Persistence" subsection documenting create/append modes and Source field
- Version consistency: `plugin.json`, `marketplace.json`, `README.md` badge row all at 1.11.0

## Strengths

- **Full spec parity** — every bullet in `docs/superpowers/specs/2026-04-23-*-design.md` (§Phase 5.5) has a matching section in the command file
- **Visible review cycle in commits** — 8 commits include targeted fixes (`fix: correct mtime sort and numeric ID parsing`, `fix: disambiguate Output Format heading and fix nested fences`) showing iterative hardening
- **Validation fallback is defensive** — malformed issue blocks drop to reasoning-only form rather than aborting
- **Clean automated scans** — trufflehog (verified+unverified): 0 secrets; semgrep p/command-injection + p/owasp-top-ten: 0 AST findings on the markdown diff
- **Version discipline** — all four version records synchronized per `CLAUDE.local.md` rules
- **Good UX touches** — filename collision loop, Source field for traceability, informative "Issues saved to:" footer

---

## HIGH (1)

### [HIGH] DOC-001: `/fix` and `/fix-report` docs don't flag feedback-origin files as untrusted-provenance

**Status:** ✅ Fixed (2026-04-23)

**ID:** DOC-001
**Location:** `plugins/code-review/commands/fix.md:118-131`, `plugins/code-review/commands/fix-report.md:45-56`
**Category:** Documentation
**Effort:** easy

**Problem:**
`/analyze-feedback` now persists issue blocks derived from PR-comment bodies (attacker-influenceable on open-source projects). `/fix` and `/fix-report` consume `docs/reviews/*-feedback.md` files the same as `/review`-origin files — no documentation signals that Problem/Impact/Remediation text in feedback-origin blocks came from an external commenter and has not been independently validated. The Cross-Verifier escalated this from LOW after correlating with SEC-001.

**Impact:**
Developers running `/fix SEC-042` on a `-feedback.md` file have no documented prompt to treat the remediation text as a hint rather than authoritative guidance. Because `/fix` has a mandatory approval gate, real RCE is blocked, but subtle logic-bug injections (wrong validation, unsafe default) can slip past a hurried review. Provenance should be explicit in the consumer docs.

**Remediation:**
Add a one-liner in `fix.md` Phase 0 and `fix-report.md`:

> Issue blocks containing a `**Source:** @reviewer — [PR #N comment](…)` field originate from PR comments (via `/analyze-feedback`) and have not been independently validated. Treat the Problem/Impact/Remediation text as hints, not authoritative guidance.

Optionally: `/fix` could surface the Source field in its approval UI when present.

---

## MEDIUM (6)

### [MEDIUM] SEC-001: Prompt injection via PR comment body persisted to issue block

**Status:** ✅ Fixed (2026-04-23)

**ID:** SEC-001
**Location:** `plugins/code-review/commands/analyze-feedback.md:195-215` (context bundle), `agents/feedback-analyzer.md:94-111,144-156` (issue block schema)
**Category:** Security
**OWASP:** A05:2025 (Injection) + A08:2025 (Software/Data Integrity Failures)
**CWE:** CWE-74
**Effort:** medium

*(Severity challenged: auditor claimed CRITICAL/CVSS 9.1; Challenger verified MEDIUM because `/fix` has a mandatory approval gate and `allowed-tools` is restricted)*

**Problem:**
Step 4.1 inlines the raw comment body verbatim: `- Body: "{body}"`. A malicious PR commenter can embed adversarial "remediation" text that the agent may synthesize into `**Remediation:**`, which is then persisted and later consumed by `/fix`. The persisted markdown has no provenance delimiters and no length/content caps.

**Impact:**
Attacker chooses text that a hurried maintainer might approve at the `/fix` gate (e.g., a plausible-looking fix that introduces an auth bypass). Not RCE — `/fix`'s allow-list is `git`, `pytest`, `ruff`, `mypy`, `semgrep`, `jq`, etc. — but logic-bug injection remains realistic.

**Remediation:**
1. Delimit the untrusted body in the agent prompt: wrap `{body}` in `<<<UNTRUSTED_COMMENT_BODY ... UNTRUSTED_COMMENT_BODY>>>` and add a guideline that code blocks inside the body must not be copied verbatim into `**Remediation:**`.
2. Strip/escape nested `###`, `~~~`, and triple-backtick tokens from `Problem`/`Impact`/`Remediation` before persisting.
3. Pair with DOC-001 (consumer-side provenance signal).

---

### [MEDIUM] SEC-002: `html_url` passed unvalidated into persisted markdown link

**Status:** ✅ Fixed (2026-04-23)

**ID:** SEC-002
**Location:** `plugins/code-review/agents/feedback-analyzer.md:144-155`
**Category:** Security
**CWE:** CWE-601 / CWE-20
**Effort:** trivial

**Problem:**
The agent's Source-field spec says *"Link: `[PR #{pr_number} comment]({html_url})` — where `html_url` comes from the GitHub API response"* with no scheme/host allowlist and no escaping of `)`, `]`, backtick. GitHub Enterprise / bot accounts could supply non-`github.com` URLs; a `)` in the URL fragment would break out of the markdown link into raw markdown in the saved file.

**Impact:**
GHE hostname leak in public `docs/reviews/`, or content-spoofing of adjacent fields if `)` appears in `html_url`. Low likelihood today (GitHub's URLs are deterministic) but trivial to harden.

**Remediation:**
Validate `html_url`: scheme == `https`, host in `{github.com, <ghe-host>}`, URL-encode `)`/`]`/backtick/newline. On failure, fall back to plain-text Source without link.

---

### [MEDIUM] SEC-003: TOCTOU + no symlink guard in create-mode collision loop

**Status:** ✅ Fixed (2026-04-23)

**ID:** SEC-003
**Location:** `plugins/code-review/commands/analyze-feedback.md:458-465`
**Category:** Security
**CWE:** CWE-367 / CWE-362
**Effort:** easy

**Problem:**
```bash
while [ -f "$target" ]; do
  counter=$((counter + 1))
  target="docs/reviews/$(date +%Y-%m-%d)-${slug}-feedback-${counter}.md"
done
```
`[ -f ]` returns false for broken symlinks and for symlinks pointing at directories. Between the final check and the write, another process could plant a symlink. Also: no upper bound on the counter.

**Remediation:**
Use `set -o noclobber` + `: > "$target"` for atomic create; reject `-L "$target"`; cap at 1000 iterations; assert final path stays under `docs/reviews/` (defense-in-depth against a slug that slipped sanitization).

---

### [MEDIUM] ARCH-001: Category→Prefix mapping duplicated in 3 files

**Status:** ✅ Fixed (2026-04-23)

**ID:** ARCH-001
**Location:** `plugins/code-review/agents/feedback-analyzer.md:121-127`, `commands/analyze-feedback.md:383-389`, `commands/review.md:440-446`
**Category:** Architecture
**Effort:** easy

**Problem:**
The canonical `Category→Prefix` table is duplicated in three files; Step 5.5.2 additionally hard-codes the `SEC|PERF|ARCH|MAINT|DOC` list in a regex comment (line 354). Adding a sixth category (e.g., "Reliability → REL") requires touching all four places.

**Remediation:**
Pick a single source of truth — recommended: `docs/plugins/code-review.md#issue-id-categories`. Other files link to it and repeat only the prose descriptions, not the mapping.

---

### [MEDIUM] MAINT-001: Editorial "**Note:**" leaked inside user-facing template fence

**Status:** ✅ Fixed (2026-04-23)

**ID:** MAINT-001
**Location:** `plugins/code-review/commands/analyze-feedback.md:267`
**Category:** Maintainability
**Effort:** trivial

*(Independently verified by controller + code-quality auditor; not challenged)*

**Problem:**
Line 267 sits inside the `~~~markdown` template fence (opens L251, closes L301) introduced by "Present the analysis in this exact format:". The line reads `**Note:** This section is rendered AFTER Phase 5.5 completes, so `{ID}` contains the final number (e.g., SEC-042).` — an instruction to the reader that will render as literal text in every `/analyze-feedback` report.

**Remediation:** Move the note above the `~~~markdown` line as prose (block-quote), leaving only the template inside the fence.

```markdown
> Note: this section is rendered AFTER Phase 5.5 completes, so `{ID}`
> contains the final number (e.g., `SEC-042`).

~~~markdown
## Feedback Analysis: PR #{pr_number} - "{pr_title}"
...
~~~
```

---

### [MEDIUM] MAINT-002: `find | xargs -0 ls -t | head -1` breaks on Linux/GNU xargs with empty input

**Status:** ✅ Fixed (2026-04-23)

**ID:** MAINT-002
**Location:** `plugins/code-review/commands/analyze-feedback.md:325-330`
**Category:** Maintainability
**Effort:** easy

**Problem:**
BSD `xargs -0` skips the utility on empty stdin; GNU `xargs` **runs `ls -t` with no args**, which lists the current working directory. On Linux CI runners, when no matching review file exists, the pipeline silently returns the newest file in CWD and routes to *append mode* against it. `ls -t` batching also breaks the "single sort" guarantee the docs claim, and leading-`-` filenames may be parsed as options.

**Remediation:** Guard explicitly or restructure:

```bash
# Portable: explicit no-match guard
matches=$(find docs/reviews -maxdepth 1 -type f -name "*-${slug}*.md" -print0 2>/dev/null)
if [ -n "$matches" ]; then
  target=$(printf '%s' "$matches" | xargs -0 ls -t 2>/dev/null | head -1)
fi
```

Or skip `xargs` entirely with `stat`+`sort`.

---

### [MEDIUM] MAINT-003: Empty slug on detached HEAD → glob `*-*.md` matches every review file

**Status:** ✅ Fixed (2026-04-23)

**ID:** MAINT-003
**Location:** `plugins/code-review/commands/analyze-feedback.md:336-344`
**Category:** Maintainability
**Effort:** trivial

*(Was SEC-002 empty-slug leg; Challenger reframed as data-integrity, not security)*

**Problem:**
The fallback path runs `git branch --show-current | sed … | tr …` — in detached-HEAD state (common in CI), `git branch --show-current` returns empty, slug becomes `""`, and the glob `*-<slug>*.md` reduces to `*-*.md` which matches every file in `docs/reviews/`. The script then enters append mode against an unrelated PR's file.

**Remediation:** Treat empty slug as a hard abort, not a fallback.

```bash
branch_name=$(git branch --show-current 2>/dev/null)
[ -n "$branch_name" ] || { echo "ERROR: cannot resolve branch — gh failed AND local HEAD detached" >&2; exit 1; }
```

Add assertion `[ -n "$slug" ]` before the glob.

---

## LOW (10)

### [LOW] SEC-004: Local branch name leaked in fallback warning

**Status:** ✅ Fixed (2026-04-23)

**Location:** `plugins/code-review/commands/analyze-feedback.md:336-344` · **CWE:** CWE-200

The fallback warning surfaces the raw local branch (e.g., `feature/ACME-internal-2026-acquisition-target`) directly in the report that may be copied into the PR or screen-shared. **Fix:** elide the branch name in the user-facing warning; log to session only.

### [LOW] MAINT-004: `{CATEGORY-PREFIX}-XXX` vs `PREFIX-XXX` placeholder notation is ambiguous

**Status:** ✅ Fixed (2026-04-23)

**Location:** `agents/feedback-analyzer.md:95,97,115` vs `commands/analyze-feedback.md:392-394`

*(Was MAINT-001 HIGH; Challenger downgraded: both are meta-variables for "one of SEC/PERF/…" and the worked example at line 168,170 resolves the ambiguity by demonstration)*

The literal template in "Issue Block Structure" uses `{CATEGORY-PREFIX}-XXX`; a careless executing agent might emit the braces verbatim. **Fix:** change the template line to a concrete example (`### [SEVERITY] SEC-XXX: Title`) and tighten the "ID Placeholder" prose.

### [LOW] MAINT-005: Scan regex accepts any uppercase prefix, not just the known set

**Status:** ✅ Fixed (2026-04-23)

**Location:** `plugins/code-review/commands/analyze-feedback.md:351,354`

`^### \[[A-Z]+\] [A-Z]+-[0-9]+:` catches `QA-001`/`REL-001` even though they're not in the known-prefix list — future categories won't auto-participate in counter tracking. **Fix:** explicit alternation `(SEC|PERF|ARCH|MAINT|DOC)` or a fully dynamic `awk`.

### [LOW] MAINT-006: Redundant `gh pr view` call in Step 5.5.1

**Status:** ✅ Fixed (2026-04-23)

Phase 1.3 already calls `gh pr view` — extend its `--json` list with `headRefName` so Step 5.5.1 just reads from state. Removes one API failure surface.

### [LOW] MAINT-007: `marketplace.json` version jump 1.9.2 → 1.11.0 (historical drift)

**Status:** ✅ Fixed (2026-04-23)

Not caused by this PR, but it papers over the skipped 1.10.0 bump in `marketplace.json`. **Fix:** add a CI check asserting `plugin.json:.version == marketplace.json: .plugins[name==code-review].version`.

### [LOW] DOC-002: Recommended-workflow doesn't mention feedback path

**Status:** ✅ Fixed (2026-04-23)

**Location:** `docs/plugins/code-review.md:165-172`

The "Fixing Issues → Recommended workflow" bullet list only shows `/review → /fix-report`. Add a sister workflow for `/analyze-feedback → /fix-report`.

### [LOW] DOC-003: README plugin description silent on feedback persistence

**Status:** ✅ Fixed (2026-04-23)

**Location:** `README.md:20`

Judgment call per `CLAUDE.local.md` ("update the description if the change affects the one-line summary"). 1.11.0 arguably does — extend with "Persist PR review feedback via `/analyze-feedback`".

### [LOW] DOC-004: marketplace.json description silent on feedback persistence

**Status:** ✅ Fixed (2026-04-23)

**Location:** `.claude-plugin/marketplace.json:10`

Same as DOC-003, different surface. Keep in sync.

### [LOW] DOC-005: OWASP/CWE optionality & ID placeholder convention only documented in agent file

**Status:** ✅ Fixed (2026-04-23)

**Location:** `docs/plugins/code-review.md:115-119` vs `agents/feedback-analyzer.md:140-155`

Public doc doesn't state that OWASP/CWE are conditional for feedback-origin issues. One-sentence addition.

### [LOW] DOC-006: Design doc ↔ command drift

**Status:** ✅ Fixed (2026-04-23)

**Location:** `docs/superpowers/specs/2026-04-23-*-design.md:142-147` vs `commands/analyze-feedback.md:262-267,482`

The command's footer introduces a `Validation warnings:` bullet absent from the design doc. Hard-coded `SEC-042` example should become `<first-id>`.

---

## Removed (challenged as false positives)

| Original | Verdict | Reason |
|---|---|---|
| SEC (former #2 symlink leg) HIGH — symlink attack via `find \| ls -t` | FALSE POSITIVE | Requires pre-existing filesystem write access to the maintainer's working copy; `find -type f` doesn't enable writes; writes happen via Write/Edit tool, not through `ls`. Kept only the empty-slug data-integrity leg (→ MAINT-003). |
| SEC (former #3) HIGH — shell injection via `comment.path`/`filename` | FALSE POSITIVE | Command file is a *prompt*, not a script; `allowed-tools` is `Bash(gh:*), Bash(git:*)` (no arbitrary shell); `gh`/`git` don't eval `$(…)` in CLI argument values. GitHub API won't emit filenames with shell metacharacters. |

---

## Verification Summary

**Method:** Parallel security + code-quality + documentation auditors; then Cross-Verifier (correlation/coverage) and Challenger (adversarial) in parallel on all CRITICAL/HIGH findings.

| Metric | Count |
|---|---|
| Initial findings (raw) | 21 (6 SEC + 10 MAINT/ARCH + 5 DOC) |
| False positives removed | 2 (both HIGH) |
| Severity adjustments (Challenger) | SEC-001 CRITICAL→MEDIUM; SEC-002 HIGH→removed; SEC-003 HIGH→removed; MAINT-001 HIGH→LOW |
| Severity escalations (Cross-Verifier) | DOC-005 LOW→HIGH (became DOC-001) |
| Duplicates merged | DOC (placeholder) into MAINT-004; SEC-002/MAINT-003/MAINT-004 correctness cluster consolidated |
| Final issues | 17 (1 HIGH, 6 MEDIUM, 10 LOW) |

### Cross-analysis correlations

- **SEC-001 × DOC-001** — Untrusted PR-comment content persisted without provenance signal to downstream `/fix`; this is what escalated DOC-001 to HIGH.
- **SEC-002 × SEC-003 × MAINT-002 × MAINT-003** — Locate-target-file routine (L317-340, L458-465) has four overlapping defects; a single rewrite closes all.
- **MAINT-001 × DOC-002 × DOC-006** — Phase 5.5 shipped without end-to-end rendering pass; the Note-inside-fence leak and unsynced docs are symptoms of the same missing check.

### Challenged (downgraded or removed)

- **SEC-001** CRITICAL→MEDIUM — `/fix` has mandatory approval gate (`fix.md:235-249`); `allowed-tools` is restricted; CVSS 9.1 overestimates since chain requires maintainer to approve malicious diff.
- **SEC-002 (symlink)** HIGH→removed — symlink plant requires prior local write access, bigger problem than this plugin.
- **SEC-003** HIGH→removed — prompt-template-not-shell confusion; command files are read by Claude, not `bash -c`.
- **MAINT-001** HIGH→LOW — `{CATEGORY-PREFIX}` and `PREFIX` are both meta-variables; the Full Output Example (`SEC-XXX`) demonstrates the concrete form and Claude follows examples over abstract templates.

### Coverage gaps (for future pass)

- GAP-2: Step 5.5.3 validation doesn't assert `XXX` was actually replaced (fallout from MAINT-004)
- GAP-4: No concurrency/locking for two simultaneous `/analyze-feedback` runs appending to the same file
- GAP-5: Non-UTF-8 or control characters in comment body not handled
- GAP-7: `.gitignore docs/` would silently swallow persisted feedback files

---

## Priority ranking

**Before merge (should fix):**
1. **MAINT-001** — editorial Note in template fence (trivial, very visible)
2. **MAINT-002** — `xargs` portability on Linux (easy, prevents append-to-wrong-file on CI)
3. **MAINT-003** — empty slug hard-abort (trivial)

**Bundle into 1.11.1 hardening:**
4. DOC-001 (HIGH — provenance signal in `/fix` docs)
5. SEC-001 (MEDIUM — comment-body delimiting + guideline)
6. SEC-002, SEC-003 (MEDIUM — URL validation + TOCTOU)
7. ARCH-001 (category mapping SSoT)

**Backlog:**
- All LOW findings, coverage gaps

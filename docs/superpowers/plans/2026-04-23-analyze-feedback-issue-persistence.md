# `/analyze-feedback` — Issue Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `/analyze-feedback` so PR comments classified as "Address" generate issue blocks in `/review` format and persist to `docs/reviews/`, making them consumable by `/fix` and `/fix-report`.

**Architecture:** Modify feedback-analyzer agent to output issue blocks for Address; add Phase 5.5 to analyze-feedback command to locate/create target file, assign IDs, and persist blocks. Version bump 1.10.0 → 1.11.0.

**Tech Stack:** Bash (gh CLI, file ops), Markdown (agent/command documentation + issue block format), regex (ID extraction).

**Spec:** `docs/superpowers/specs/2026-04-23-analyze-feedback-issue-persistence-design.md`

---

## Note on testing

This plugin is markdown documentation for Claude Code agents and commands — there is no runtime code to unit-test. Verification is done via manual test scenarios (Tasks 5–8) that exercise the full workflow end-to-end against real GitHub PRs.

---

### Task 1: Update feedback-analyzer agent documentation

**Files:**
- Modify: `plugins/code-review/agents/feedback-analyzer.md`

- [ ] **Step 1: Read current feedback-analyzer.md**

Open the file and verify the current structure has these sections: Input, Analysis Workflow, Output Format, Guidelines.

- [ ] **Step 2: Add "Output Format for Address" section after "Guidelines"**

Append the following to the end of the file (after the last Guidelines bullet):

~~~markdown

---

## Output Format for Address

When classification is ✅ Address, include an issue block in addition to the reasoning.

### Issue Block Structure

```markdown
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

### ID Placeholder

Always output `{CATEGORY-PREFIX}-XXX` with a literal `XXX`. The real number is assigned by the `/analyze-feedback` command in Phase 5.5, so numbering stays consistent with the target file.

### Category Mapping

Map each Address comment to exactly one category:

| Category | Prefix | When to use |
|----------|--------|-------------|
| Security | SEC | Auth, injection, secrets, crypto, XSS, CSRF, authorization |
| Performance | PERF | N+1 queries, memory, caching, indexing, blocking calls |
| Architecture | ARCH | SOLID violations, layers, coupling, API design, services |
| Maintainability | MAINT | Naming, complexity, clarity, DRY, test coverage |
| Documentation | DOC | Outdated docs, missing entries, inaccurate API refs |

If a comment touches multiple categories, choose the primary one.

### Severity Levels

Assign based on the substance of the comment (not the reviewer's tone):

- **CRITICAL** — Security vulnerability or data loss risk.
- **HIGH** — Functional bug, performance regression, architectural violation.
- **MEDIUM** — Code quality issue, minor bug, missing edge case.
- **LOW** — Style, nit, minor improvement.

### OWASP / CWE

Include `**OWASP:**` or `**CWE:**` fields only when genuinely applicable to the category. Omit otherwise.

### Source Field

Construct from the comment metadata:

- `@{comment_author}` — reviewer username.
- Link: `[PR #{pr_number} comment]({html_url})` — where `html_url` comes from the GitHub API response.

Example:

```
**Source:** @alice — [PR #123 comment](https://github.com/owner/repo/pull/123#discussion_r12345)
```

### Full Output Example

For a comment `@alice: "This endpoint doesn't validate the auth token before returning data"`:

```markdown
**Classification:** ✅ Address

**Reasoning:** The endpoint accepts the request without verifying token authenticity, allowing unauthenticated access to protected data. This is a legitimate security gap that warrants a fix.

**Issue Block:**

### [HIGH] SEC-XXX: Auth endpoint missing token validation

**ID:** SEC-XXX
**Location:** `src/api/user.py:42`
**Category:** Security
**Effort:** easy
**Source:** @alice — [PR #123 comment](https://github.com/owner/repo/pull/123#discussion_r12345)

**OWASP:** A01:2025 — Broken Access Control

**Problem:**
The `/user/profile` endpoint reads the token from the request but does not verify it against the auth service before returning data.

**Impact:**
Unauthenticated clients can access user profiles, exposing PII.

**Remediation:**
Call `auth_service.verify_token(token)` before the data fetch; return 401 on failure.

```python
# Before
def get_profile(token: str):
    return user_repo.find_by_token(token)

# After
def get_profile(token: str):
    if not auth_service.verify_token(token):
        raise HTTPException(401, "Invalid token")
    return user_repo.find_by_token(token)
```
```
~~~

- [ ] **Step 3: Commit**

```bash
AV_COMMIT_SKILL=1 git add plugins/code-review/agents/feedback-analyzer.md && git commit -m "feat(code-review): add issue block output format to feedback-analyzer"
```

---

### Task 2: Add Phase 5.5 to analyze-feedback command documentation

**Files:**
- Modify: `plugins/code-review/commands/analyze-feedback.md`

- [ ] **Step 1: Locate where Phase 5 ends and Phase 6 begins**

Run:

```bash
grep -n "^## Phase" plugins/code-review/commands/analyze-feedback.md
```

Expected: line numbers for each `## Phase N:` heading.

- [ ] **Step 2: Update Phase 5 (Generate Report) output format**

In the existing Phase 5 section, find the `### ✅ To Address ({count})` template and replace the block template from:

```
#### 1. @{author} in `{path}:{line}`
> "{comment body - first 200 chars}..."

**Reasoning:** {reasoning from agent}
```

to:

```
#### {ID} [{SEVERITY}]: {Title} — `{path}:{line}`
> @{author}: "{comment body - first 200 chars}..."

**Reasoning:** {reasoning from agent}
```

Note: `{ID}`, `{SEVERITY}`, `{Title}` come from the issue block after Phase 5.5 assigns them. For the report, Phase 5 is actually rendered AFTER Phase 5.5 so IDs are resolved.

Add this note right below the template:

```markdown
**Note:** This section is rendered AFTER Phase 5.5 completes, so `{ID}` contains the final number (e.g., SEC-042).
```

- [ ] **Step 3: Insert Phase 5.5 section before Phase 6**

Immediately before the `## Phase 6: Publish Responses (Optional)` heading, insert this new section:

~~~markdown
---

## Phase 5.5: Persist Issues

**Runs only when `to_address` is non-empty.**

### Step 5.5.1: Locate target file

1. Fetch the PR's head branch name:

```bash
gh pr view <pr_number> --json headRefName --jq '.headRefName'
```

2. Slugify the branch name (same rules as `/review`):
   - Replace `/` with `-`
   - Replace spaces with `-`
   - Convert to lowercase
   - Example: `feature/user-login` → `feature-user-login`

3. Glob search in `docs/reviews/` for existing review file:

```bash
mkdir -p docs/reviews
find docs/reviews -name "*-<slug>*.md" -type f -print 2>/dev/null | xargs -I {} ls -t {} 2>/dev/null | head -1
```

This returns the newest matching file (by mtime) or empty.

4. Resolve mode:
   - **File found** → **append mode**, target is that file.
   - **No file found** → **create mode**, target is `docs/reviews/YYYY-MM-DD-<slug>-feedback.md`.

**Fallback:** If `gh pr view --json headRefName` fails (auth/permissions error), fall back to the local branch:

```bash
git branch --show-current | sed 's|/|-|g; s| |-|g' | tr '[:upper:]' '[:lower:]'
```

Add this warning to the report:

> ⚠️ Could not fetch branch name from PR via `gh`. Using local branch `{name}` for file lookup — this may not match the PR's branch.

### Step 5.5.2: Compute starting IDs per category

Scan the target file for existing issue IDs using this regex:

```bash
grep -oE '^### \[[A-Z]+\] [A-Z]+-[0-9]+:' <file> | grep -oE '[A-Z]+-[0-9]+' | sort -u
```

For each known prefix (`SEC`, `PERF`, `ARCH`, `MAINT`, `DOC`):
- Find all matches (e.g., `SEC-001`, `SEC-003`).
- Record the maximum numeric value.
- Next counter = `max + 1`.

Categories without existing entries start at `001`.

**Example:**

File contains `SEC-003`, `SEC-001`, `PERF-002`. Counters:

| Prefix | Start |
|--------|-------|
| SEC    | 004   |
| PERF   | 003   |
| ARCH   | 001   |
| MAINT  | 001   |
| DOC    | 001   |

In **create mode**, all counters start at `001`.

### Step 5.5.3: Assign IDs to issue blocks

For each issue block in `to_address` (in order):

1. Extract the `**Category:**` value from the block.
2. Map to prefix:

| Category | Prefix |
|----------|--------|
| Security | SEC |
| Performance | PERF |
| Architecture | ARCH |
| Maintainability | MAINT |
| Documentation | DOC |

3. Read the current counter for that prefix; format as zero-padded 3-digit (e.g., `004`).
4. Replace the `XXX` placeholder in two places:
   - Heading: `### [SEVERITY] PREFIX-XXX:` → `### [SEVERITY] PREFIX-004:`
   - ID field: `**ID:** PREFIX-XXX` → `**ID:** PREFIX-004`
5. Increment the counter for that prefix.

**Validation (per block):**

Check that the block has:
- `**Location:**` field with a path and line number.
- `**Category:**` field with value in the allowed set: `{Security, Performance, Architecture, Maintainability, Documentation}`.

If validation fails:
- Log a warning: `⚠️ Issue block from comment ID {comment_id} is malformed (missing {field} or invalid category). Reverting to reasoning-only form.`
- Drop the `**Issue Block:**` section from this comment's agent output.
- Keep only `**Classification:** ✅ Address` and `**Reasoning:** ...`.
- Continue processing remaining blocks normally.

### Step 5.5.4: Write to file

**Append mode** — open the target file and append:

```markdown

---

## Feedback Issues — PR #{pr_number} ({YYYY-MM-DD})

{issue block 1}

---

{issue block 2}

---

{issue block N}
```

Use today's date in YYYY-MM-DD format.

**Create mode** — create new file with header + grouping section:

```markdown
# Feedback Analysis: PR #{pr_number} — "{pr_title}"

**Repository:** {owner}/{repo}
**PR Author:** @{pr_author}
**URL:** {pr_url}

---

## Feedback Issues — PR #{pr_number} ({YYYY-MM-DD})

{issue block 1}

---

{issue block 2}

---

{issue block N}
```

**Handle create-mode filename collision:**

```bash
target="docs/reviews/$(date +%Y-%m-%d)-${slug}-feedback.md"
counter=1
while [ -f "$target" ]; do
  counter=$((counter + 1))
  target="docs/reviews/$(date +%Y-%m-%d)-${slug}-feedback-${counter}.md"
done
```

The first file has no suffix; subsequent collisions append `-2`, `-3`, etc.

### Step 5.5.5: Extend user-facing report

After Phase 5.5 completes, render Phase 5's `### ✅ To Address` section with the shortened form (already described in Phase 5 template).

At the end of the full report (after the Summary table), add:

```markdown
---

**Issues saved to:** `{target_file_path}` ({N} new issues)

**Next steps:**
- `/fix-report {target_file_path}` — fix multiple issues interactively
- `/fix SEC-042` — fix a single issue by ID

**Validation warnings:** {list of per-comment warnings from Step 5.5.3, if any}
```

If no `to_address` items existed at all, skip Phase 5.5 entirely and omit this footer.

---
~~~

- [ ] **Step 4: Commit Phase 5.5 changes**

```bash
AV_COMMIT_SKILL=1 git add plugins/code-review/commands/analyze-feedback.md && git commit -m "feat(code-review): add Phase 5.5 Persist Issues to analyze-feedback"
```

---

### Task 3: Update plugin documentation

**Files:**
- Modify: `docs/plugins/code-review.md`

- [ ] **Step 1: Find the `/analyze-feedback` section**

```bash
grep -n "^### \`/analyze-feedback\`" docs/plugins/code-review.md
```

- [ ] **Step 2: Add "Issue Persistence" subsection after the existing code examples**

After the block that ends with "Requires GitHub CLI (`gh`) to be installed and authenticated.", insert:

~~~markdown

#### Issue Persistence

Comments classified as **Address** are persisted to `docs/reviews/` in the same format as `/review` issues. This makes them consumable by `/fix` and `/fix-report`.

**Create mode** — if no prior `/review` was saved for this branch:

```bash
/analyze-feedback 123
# Creates: docs/reviews/YYYY-MM-DD-<branch-slug>-feedback.md
# Issues get IDs starting at SEC-001, PERF-001, ARCH-001, etc.
```

**Append mode** — if a `/review` file already exists for this branch:

```bash
/review            # Saves to docs/reviews/YYYY-MM-DD-<branch-slug>.md
/analyze-feedback 123
# Appends to the existing file with a new "## Feedback Issues — PR #123 (date)" section
# IDs continue from max+1 per category (e.g., if review has SEC-003, feedback starts at SEC-004)
```

Each issue includes a `**Source:**` field linking back to the original PR comment, preserving traceability:

```markdown
**Source:** @reviewer — [PR #123 comment](https://github.com/owner/repo/pull/123#discussion_r12345)
```

**Reject classification** — comments marked as "Reject" are handled as before: reasoning shown in the report, optional draft responses published to GitHub via Phase 6.
~~~

- [ ] **Step 3: Commit documentation changes**

```bash
AV_COMMIT_SKILL=1 git add docs/plugins/code-review.md && git commit -m "docs(plugins): document analyze-feedback issue persistence"
```

---

### Task 4: Bump plugin version

**Files:**
- Modify: `plugins/code-review/.claude-plugin/plugin.json`
- Modify: `README.md`

- [ ] **Step 1: Update plugin.json**

Change `"version": "1.10.0"` to `"version": "1.11.0"` in `plugins/code-review/.claude-plugin/plugin.json`.

Final content:

```json
{
  "name": "code-review",
  "description": "Perform comprehensive code review for security, performance, and architecture. Optional verification phase for cross-analysis and adversarial review.",
  "version": "1.11.0"
}
```

- [ ] **Step 2: Update README.md Available Plugins table**

Find the code-review row in the Available Plugins table in `README.md`:

```bash
grep -n "code-review" README.md
```

Update the version column from `1.10.0` to `1.11.0` in that row. The row format is typically:

```markdown
| [Code Review](docs/plugins/code-review.md) | 1.11.0 | ... |
```

- [ ] **Step 3: Update .claude-plugin/marketplace.json version**

Check if `.claude-plugin/marketplace.json` also has a version for `code-review`:

```bash
grep -n "code-review" .claude-plugin/marketplace.json
```

If there is a `"version"` field in the `code-review` plugin entry, update it to `"1.11.0"`.

- [ ] **Step 4: Commit version bump**

```bash
AV_COMMIT_SKILL=1 git add plugins/code-review/.claude-plugin/plugin.json README.md .claude-plugin/marketplace.json && git commit -m "chore(release): bump code-review plugin to 1.11.0"
```

(If `marketplace.json` didn't change, omit it from the `git add`.)

---

### Task 5: Manual testing — Create mode

**No code changes; verification only.**

- [ ] **Step 1: Set up test PR**

```bash
git checkout -b test/feedback-create-$(date +%s)
echo "test" > /tmp/test-file-create.txt
cp /tmp/test-file-create.txt ./test-file-create.txt
git add test-file-create.txt
AV_COMMIT_SKILL=1 git commit -m "test: create mode test"
git push -u origin HEAD
gh pr create --title "Test: feedback create mode" --body "Adding Address comments via gh api"
```

Capture the PR number (stored in the `gh pr create` output URL).

- [ ] **Step 2: Add a review comment programmatically**

```bash
PR_NUMBER=<from step 1>
OWNER_REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')
COMMIT_SHA=$(gh pr view $PR_NUMBER --json headRefOid --jq '.headRefOid')

gh api --method POST \
  /repos/$OWNER_REPO/pulls/$PR_NUMBER/comments \
  -f body="This file is missing input validation — please add a check." \
  -f commit_id="$COMMIT_SHA" \
  -f path="test-file-create.txt" \
  -F line=1 \
  -f side="RIGHT"
```

- [ ] **Step 3: Run /analyze-feedback**

In Claude Code, run:

```
/analyze-feedback <PR_NUMBER>
```

Expected output:
- Report shows "To Address" with the comment.
- Shortened form: `#### SEC-001 [...]: ... — test-file-create.txt:1`
- Footer: `Issues saved to: docs/reviews/YYYY-MM-DD-test-feedback-create-*.md (1 new issue)`

- [ ] **Step 4: Verify the file**

```bash
ls docs/reviews/*feedback-create*-feedback.md
cat docs/reviews/*feedback-create*-feedback.md
```

Expected:
- File starts with `# Feedback Analysis: PR #<N> — ...`
- Metadata (Repository, PR Author, URL).
- `## Feedback Issues — PR #<N> (YYYY-MM-DD)` header.
- Issue block with ID `SEC-001` (or `MAINT-001` depending on agent's category choice), all required fields including `**Source:**` with link.

- [ ] **Step 5: Clean up**

```bash
gh pr close <PR_NUMBER> --delete-branch
git checkout master
rm -f test-file-create.txt
rm -f docs/reviews/*feedback-create*-feedback.md
git status  # verify clean working tree
```

---

### Task 6: Manual testing — Append mode + ID continuation

**No code changes; verification only.**

- [ ] **Step 1: Set up test PR with a file containing a reviewable issue**

```bash
git checkout -b test/feedback-append-$(date +%s)
cat > test-file-append.py <<'EOF'
def login(user_id):
    # Missing validation
    query = f"SELECT * FROM users WHERE id = {user_id}"
    return db.execute(query)
EOF
git add test-file-append.py
AV_COMMIT_SKILL=1 git commit -m "test: append mode test"
git push -u origin HEAD
gh pr create --title "Test: feedback append mode" --body "SQL injection + comments"
```

Capture PR number and branch slug.

- [ ] **Step 2: Run /review and save**

```
/review
```

When prompted, choose "Yes" to save. Expected: file at `docs/reviews/YYYY-MM-DD-test-feedback-append-*.md` with review issues (e.g., `SEC-001: SQL Injection`).

Note the max SEC ID in the saved file:

```bash
grep -E '### \[[A-Z]+\] SEC-[0-9]+' docs/reviews/*feedback-append*.md
```

- [ ] **Step 3: Add a PR comment**

```bash
PR_NUMBER=<from step 1>
OWNER_REPO=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')
COMMIT_SHA=$(gh pr view $PR_NUMBER --json headRefOid --jq '.headRefOid')

gh api --method POST \
  /repos/$OWNER_REPO/pulls/$PR_NUMBER/comments \
  -f body="Add a type hint to user_id and validate it's an integer." \
  -f commit_id="$COMMIT_SHA" \
  -f path="test-file-append.py" \
  -F line=1 \
  -f side="RIGHT"
```

- [ ] **Step 4: Run /analyze-feedback**

```
/analyze-feedback <PR_NUMBER>
```

Expected:
- Report shows "To Address" for the new comment.
- Footer: `Issues saved to: docs/reviews/YYYY-MM-DD-test-feedback-append-*.md` (same file from Step 2).
- New ID continues from max+1 per category (e.g., if review had `SEC-001`, feedback issue if Security category gets `SEC-002`; otherwise starts at `001` for its category).

- [ ] **Step 5: Verify file structure**

```bash
cat docs/reviews/*feedback-append*.md
```

Expected:
- Review issues section unchanged at top.
- New `## Feedback Issues — PR #<N> (YYYY-MM-DD)` section at bottom.
- Feedback issue IDs continue sequence per category.

- [ ] **Step 6: Verify /fix-report still works on the combined file**

```
/fix-report docs/reviews/<filename>
```

Expected: all issues (review + feedback) appear in the paginated checklist. IDs include both `SEC-001` and new feedback ID.

- [ ] **Step 7: Clean up**

```bash
gh pr close <PR_NUMBER> --delete-branch
git checkout master
rm -f test-file-append.py docs/reviews/*feedback-append*.md
```

---

### Task 7: Manual testing — Edge cases

**No code changes; verification only.**

- [ ] **Test 7.1: Reject-only PR**

Set up a PR where all comments should be classified as Reject (e.g., nitpicky stylistic suggestions that contradict project conventions).

Run `/analyze-feedback <PR>`. Expected:
- No "Issues saved to" footer.
- No file created in `docs/reviews/`.
- Phase 6 prompts for publishing Reject drafts as usual.

- [ ] **Test 7.2: Malformed issue block (validation fallback)**

This test requires temporarily modifying `feedback-analyzer.md` to force a malformed output. Skip if you trust the agent; otherwise:

Manually invoke a single comment through `Task(subagent_type: "code-review:feedback-analyzer", ...)` with a mock input that would produce a block missing `**Category:**`. Alternatively, observe real-world behavior over multiple runs.

Expected: warning message in the report; the malformed issue falls back to reasoning-only; other issues persist normally.

- [ ] **Test 7.3: Run /analyze-feedback from a different branch**

```bash
git checkout master
/analyze-feedback <PR_NUMBER from Task 5 or 6>
```

Expected:
- File located via `gh pr view <N> --json headRefName`, NOT via `git branch --show-current`.
- Target file matches the PR's branch slug, not `master`.

- [ ] **Test 7.4: Create-mode filename collision**

Quickly run `/analyze-feedback <PR>` twice on the same PR (within the same day, no prior `/review`):

```bash
rm -f docs/reviews/*feedback-test*  # ensure clean
# Run 1:
/analyze-feedback <PR>
# Run 2:
/analyze-feedback <PR>
```

Expected files:
- `docs/reviews/YYYY-MM-DD-<slug>-feedback.md`
- `docs/reviews/YYYY-MM-DD-<slug>-feedback-2.md`

Second run created a new file with `-2` suffix; did not overwrite.

- [ ] **Cleanup after all edge case tests**

```bash
rm -f docs/reviews/*feedback-test*
git status
```

---

### Task 8: Final verification

- [ ] **Step 1: Verify all changes committed**

```bash
git status
```

Expected: clean working tree.

- [ ] **Step 2: Review commit log**

```bash
git log --oneline -10
```

Expected to see (in order, newest first):
- `chore(release): bump code-review plugin to 1.11.0`
- `docs(plugins): document analyze-feedback issue persistence`
- `feat(code-review): add Phase 5.5 Persist Issues to analyze-feedback`
- `feat(code-review): add issue block output format to feedback-analyzer`
- `docs(spec): add analyze-feedback issue persistence design` (from earlier)

- [ ] **Step 3: Verify version consistency**

```bash
grep -H "1.11.0" plugins/code-review/.claude-plugin/plugin.json README.md
```

Expected: version `1.11.0` in both files.

- [ ] **Step 4: Verify docs reference new functionality**

```bash
grep -n "Issue Persistence" docs/plugins/code-review.md
```

Expected: a match inside the `/analyze-feedback` section.

---

**Plan complete.** Implementation is ready for execution.

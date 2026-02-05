# `/analyze-feedback` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a command that fetches PR comments from GitHub, classifies their validity, and generates draft responses for feedback that should be rejected.

**Architecture:** Two-component design - main command orchestrates PR fetching and report generation, subagent analyzes individual comments for validity. Command uses `gh` CLI for GitHub API access.

**Tech Stack:** Claude Code plugin system (markdown commands/agents), GitHub CLI (`gh`), Git

---

## Task 1: Create feedback-analyzer agent

**Files:**

- Create: `plugins/code-review/agents/feedback-analyzer.md`

**Step 1: Create the agent file with frontmatter**

```markdown
---
name: feedback-analyzer
description: Analyze single PR comment for validity and generate response if needed.
tools: Read, Glob, Grep, Bash(git:*)
model: claude-opus-4-5
---
```

**Step 2: Add agent header and input section**

```markdown
# Feedback Analyzer Agent

You analyze a single PR review comment and determine if it should be addressed or rejected.

## Input

You receive:

1. **Comment data** - author, body, file path, line number
2. **Code context** - the relevant code snippet and surrounding context
3. **Project context** - documentation, coding standards, commit history

---
```

**Step 3: Add analysis workflow**

```markdown
## Analysis Workflow

### Step 1: Understand the Comment

Parse the comment to identify:

- **Type**: suggestion, question, nitpick, blocker, approval
- **Subject**: what aspect of code is being discussed
- **Requested change**: what the reviewer wants changed (if any)

### Step 2: Evaluate Validity

For each suggestion, assess:

| Criterion | Question |
|-----------|----------|
| Technical correctness | Is the suggestion technically accurate? |
| Context awareness | Does reviewer understand the code's purpose? |
| Project alignment | Does it align with project patterns/standards? |
| Trade-off balance | Are the costs worth the benefits? |
| Scope appropriateness | Is this the right place for this change? |

### Step 3: Make Decision

**Classify as "Address" if:**

- Suggestion is technically correct AND
- Improves code quality, security, or maintainability AND
- Benefits outweigh implementation cost

**Classify as "Reject" if:**

- Suggestion is technically incorrect OR
- Based on misunderstanding of code purpose OR
- Contradicts project standards/patterns OR
- Costs outweigh benefits (premature optimization, over-engineering)

---
```

**Step 4: Add output format**

```markdown
## Output Format

Return analysis in this exact structure:

~~~
**Classification:** ✅ Address | ❌ Reject

**Reasoning:** [2-3 sentences explaining why this classification]

**Draft Response (if Reject):**
> [2-3 sentence response to post on GitHub - direct, technical, no fluff]
~~~

---

## Guidelines

- Be objective - evaluate the suggestion, not the reviewer
- Consider project context heavily
- Prefer "Address" when genuinely uncertain
- Draft responses should be professional but direct
- Never be dismissive or condescending in responses
```

**Step 5: Verify file was created**

Run: `cat plugins/code-review/agents/feedback-analyzer.md | head -20`
Expected: File content with frontmatter visible

**Step 6: Commit**

```bash
git add plugins/code-review/agents/feedback-analyzer.md
git commit -m "feat(code-review): add feedback-analyzer agent for PR comment analysis"
```

---

## Task 2: Create analyze-feedback command - frontmatter and header

**Files:**

- Create: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Create command file with frontmatter**

```markdown
---
allowed-tools: Read, Glob, Grep, Bash(gh:*), Bash(git:*), Task
description: Analyze PR feedback comments, classify them, and generate response drafts.
model: claude-opus-4-5
argument-hint: [pr-number] [--include-conversation]
---
```

**Step 2: Add command header**

```markdown
# Analyze PR Feedback

You analyze comments from a GitHub Pull Request, classify each comment's validity, and generate a report with draft responses for feedback that should be rejected.

## Arguments

- `$ARGUMENTS` - optional PR number and flags

**Parsing:**

- No argument → detect PR from current branch
- Number (e.g., `123`) → use as PR number
- `--include-conversation` → include general PR comments (not just review comments)

---
```

**Step 3: Verify file structure**

Run: `cat plugins/code-review/commands/analyze-feedback.md`
Expected: Frontmatter and header visible

**Step 4: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add analyze-feedback command skeleton"
```

---

## Task 3: Add Phase 1 - PR detection and validation

**Files:**

- Modify: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Add Phase 1 section**

Append to the file:

```markdown
## Phase 1: Identify PR

### Step 1.1: Parse arguments

```
Input: $ARGUMENTS
```

Extract:

- PR number (if provided)
- `--include-conversation` flag (true/false)

### Step 1.2: Detect PR (if no number provided)

If no PR number in arguments:

```bash
gh pr view --json number,title,author,url --jq '.number'
```

**If command fails:** Report error:

> "No PR found for current branch. Provide PR number: `/analyze-feedback 123`"

### Step 1.3: Validate PR exists

```bash
gh pr view <PR_NUMBER> --json number,title,author,url,state
```

**If PR not found:** Report error:

> "PR #<NUMBER> not found in this repository."

**If PR closed/merged:** Continue but note in report.

### Step 1.4: Store PR metadata

Extract and store:

- `pr_number`
- `pr_title`
- `pr_author`
- `pr_url`
- `pr_state`

---
```

**Step 2: Verify changes**

Run: `grep -n "Phase 1" plugins/code-review/commands/analyze-feedback.md`
Expected: Line with "## Phase 1: Identify PR"

**Step 3: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add PR detection logic to analyze-feedback"
```

---

## Task 4: Add Phase 2 - Fetch comments

**Files:**

- Modify: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Add Phase 2 section**

Append to the file:

```markdown
## Phase 2: Fetch Comments

### Step 2.1: Get repository info

```bash
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
```

Store as `owner/repo`.

### Step 2.2: Fetch review comments (always)

```bash
gh api /repos/{owner}/{repo}/pulls/{pr_number}/comments --jq '.[] | {id, author: .user.login, body, path, line: .original_line, created_at, in_reply_to_id}'
```

Review comments are attached to specific lines of code.

### Step 2.3: Fetch conversation comments (if --include-conversation)

```bash
gh api /repos/{owner}/{repo}/issues/{pr_number}/comments --jq '.[] | {id, author: .user.login, body, created_at}'
```

Conversation comments are general discussion, not line-specific.

### Step 2.4: Filter comments

**Exclude:**

- Comments by PR author (they don't review their own code)
- Bot comments (author contains `[bot]` or known bot names)
- Empty comments or emoji-only (body matches `^[\s\p{Emoji}]*$`)
- Already resolved comments (if detectable)

**For each remaining comment, store:**

- `id` - for replying later
- `author` - reviewer username
- `body` - comment text
- `path` - file path (review comments only)
- `line` - line number (review comments only)
- `type` - "review" or "conversation"

### Step 2.5: Handle edge cases

**No comments after filtering:**

> "PR #123 has no review comments to analyze."

**Only conversation comments (no review comments):**

> "PR #123 has no review comments. Use `--include-conversation` to analyze general comments."

---
```

**Step 2: Verify changes**

Run: `grep -n "Phase 2" plugins/code-review/commands/analyze-feedback.md`
Expected: Line with "## Phase 2: Fetch Comments"

**Step 3: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add comment fetching to analyze-feedback"
```

---

## Task 5: Add Phase 3 - Gather context

**Files:**

- Modify: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Add Phase 3 section**

Append to the file:

```markdown
## Phase 3: Gather Context

### Step 3.1: Get PR diff

```bash
gh pr diff {pr_number}
```

Store full diff for reference.

### Step 3.2: Read changed files

For each unique file path in review comments:

1. Use Read tool to get current file content
2. Focus on areas around commented lines (±30 lines)

### Step 3.3: Read related files

For each changed file, check for:

- Imported modules → Read if local
- Test files → `tests/**/test_<filename>.py` or `**/<filename>.test.ts`
- Type definitions → `.d.ts` files, `types.py`

Use Glob to find, Read to examine.

### Step 3.4: Gather project documentation

Search for and read (if exist):

**Root level:**

- `README.md`
- `CONTRIBUTING.md`
- `CODING_STANDARDS.md`
- `ARCHITECTURE.md`

**Docs directory:**

```bash
ls docs/*.md 2>/dev/null || echo "No docs directory"
```

Read relevant documentation files.

### Step 3.5: Get commit history

For each commented file:

```bash
git log --oneline -20 -- <file_path>
```

### Step 3.6: Check previous PRs (optional, for complex cases)

```bash
gh pr list --state merged --limit 5 --search "<filename>"
```

---
```

**Step 2: Verify changes**

Run: `grep -n "Phase 3" plugins/code-review/commands/analyze-feedback.md`
Expected: Line with "## Phase 3: Gather Context"

**Step 3: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add context gathering to analyze-feedback"
```

---

## Task 6: Add Phase 4 - Analyze comments

**Files:**

- Modify: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Add Phase 4 section**

Append to the file:

```markdown
## Phase 4: Analyze Comments

### Step 4.1: Prepare context bundle

For each comment, create a context bundle:

```
Comment:
- Author: @{author}
- File: {path}:{line}
- Body: "{body}"

Code Context:
{relevant code snippet ±30 lines around commented line}

Project Standards:
{extracted coding standards if found}

File History:
{recent commits touching this file}
```

### Step 4.2: Launch feedback-analyzer agent

For each comment, use Task tool:

```
Task tool parameters:
- subagent_type: "code-review:feedback-analyzer"
- prompt: <context bundle from Step 4.1>
- run_in_background: false (analyze sequentially for consistency)
```

### Step 4.3: Collect results

For each comment, store the agent's response:

- `classification` - "Address" or "Reject"
- `reasoning` - explanation
- `draft_response` - if classified as "Reject"

### Step 4.4: Group results

Separate into two lists:

- `to_address` - comments classified as "Address"
- `to_reject` - comments classified as "Reject" (with draft responses)

---
```

**Step 2: Verify changes**

Run: `grep -n "Phase 4" plugins/code-review/commands/analyze-feedback.md`
Expected: Line with "## Phase 4: Analyze Comments"

**Step 3: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add comment analysis to analyze-feedback"
```

---

## Task 7: Add Phase 5 - Generate report

**Files:**

- Modify: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Add Phase 5 section**

Append to the file:

```markdown
## Phase 5: Generate Report

Present the analysis in this exact format:

~~~markdown
## Analiza feedbacku: PR #{pr_number} - "{pr_title}"

**Repozytorium:** {owner}/{repo}
**Autor PR:** @{pr_author}
**Komentarzy przeanalizowanych:** {total} ({review_count} review, {conversation_count} conversation)

---

### ✅ Do zaadresowania ({count})

#### 1. @{author} w `{path}:{line}`
> "{comment body - first 200 chars}..."

**Uzasadnienie:** {reasoning from agent}

---

[repeat for each "Address" comment]

---

### ❌ Do odrzucenia ({count})

#### 1. @{author} w `{path}:{line}`
> "{comment body - first 200 chars}..."

**Uzasadnienie:** {reasoning from agent}

**Draft odpowiedzi:**
> {draft_response from agent}

---

[repeat for each "Reject" comment]

---

### Podsumowanie

| Kategoria | Liczba |
|-----------|--------|
| ✅ Do zaadresowania | {address_count} |
| ❌ Do odrzucenia | {reject_count} |

---

**Opublikować odpowiedzi? (wszystkie / wybrane / nie)**
~~~

---
```

**Step 2: Verify changes**

Run: `grep -n "Phase 5" plugins/code-review/commands/analyze-feedback.md`
Expected: Line with "## Phase 5: Generate Report"

**Step 3: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add report generation to analyze-feedback"
```

---

## Task 8: Add Phase 6 - Publish responses

**Files:**

- Modify: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Add Phase 6 section**

Append to the file:

```markdown
## Phase 6: Publish Responses (Optional)

### Step 6.1: Wait for user choice

After presenting the report, wait for user input:

- `wszystkie` or `all` → publish all draft responses
- `wybrane` or `select` → interactive selection
- `nie` or `no` → skip publishing

### Step 6.2: Handle "wybrane" (selected)

Present numbered list of drafts:

```
1. @reviewer w `src/utils.py:28` - "Funkcja jest tu właściwym wyborem..."
2. @reviewer w `src/api.py:55` - "Ten przypadek jest już obsługiwany..."
3. @reviewer w `src/models.py:12` - "Walidacja odbywa się wyżej..."

Które opublikować? (np. 1,3 lub 1-3 lub "wszystkie" / "anuluj")
```

Parse user input:

- `1,3` → publish items 1 and 3
- `1-3` → publish items 1, 2, and 3
- `wszystkie` → publish all
- `anuluj` → cancel, don't publish any

### Step 6.3: Publish to GitHub

For each selected draft:

```bash
gh api --method POST \
  /repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies \
  -f body="{draft_response}"
```

**On success:** Note published.

**On failure:** Report error, continue with remaining.

### Step 6.4: Report publication results

```
Opublikowano: 2 z 3 odpowiedzi
- ✅ @reviewer w `src/utils.py:28`
- ✅ @reviewer w `src/api.py:55`
- ❌ @reviewer w `src/models.py:12` - błąd: [error message]
```

---
```

**Step 2: Verify changes**

Run: `grep -n "Phase 6" plugins/code-review/commands/analyze-feedback.md`
Expected: Line with "## Phase 6: Publish Responses"

**Step 3: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add response publishing to analyze-feedback"
```

---

## Task 9: Add error handling section

**Files:**

- Modify: `plugins/code-review/commands/analyze-feedback.md`

**Step 1: Add error handling section**

Append to the file:

```markdown
## Error Handling

### GitHub CLI Errors

| Error | Detection | Response |
|-------|-----------|----------|
| Not logged in | `gh auth status` fails | "Zaloguj się do GitHub: `gh auth login`" |
| No repo context | `gh repo view` fails | "Uruchom komendę w katalogu repozytorium Git" |
| Rate limited | 403 with rate limit message | "Przekroczono limit API. Spróbuj za {reset_time}." |
| No permissions | 403/404 on PR | "Brak dostępu do PR #{number}. Sprawdź uprawnienia." |

### Edge Cases

| Situation | Handling |
|-----------|----------|
| PR has 0 comments | Report: "PR #{n} nie ma komentarzy do analizy." |
| All comments from PR author | Report: "Wszystkie komentarze są od autora PR." |
| Comment already has reply from user | Skip, note in report: "(already replied)" |
| Very long comment (>2000 chars) | Truncate in report, full text to agent |

### Recovery

If publication partially fails:

- Complete publishing remaining items
- Report failures at end
- Suggest retry command for failed items

---
```

**Step 2: Verify changes**

Run: `grep -n "Error Handling" plugins/code-review/commands/analyze-feedback.md`
Expected: Line with "## Error Handling"

**Step 3: Commit**

```bash
git add plugins/code-review/commands/analyze-feedback.md
git commit -m "feat(code-review): add error handling to analyze-feedback"
```

---

## Task 10: Final review and version bump

**Files:**

- Modify: `plugins/code-review/plugin.json` (if exists)
- Verify: all created files

**Step 1: Verify agent file is complete**

Run: `wc -l plugins/code-review/agents/feedback-analyzer.md`
Expected: ~80-100 lines

**Step 2: Verify command file is complete**

Run: `wc -l plugins/code-review/commands/analyze-feedback.md`
Expected: ~300-400 lines

**Step 3: Check plugin.json for version**

Run: `cat plugins/code-review/plugin.json 2>/dev/null || echo "No plugin.json"`

If exists, bump version. If not, skip.

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat(code-review): complete /analyze-feedback command implementation"
```

**Step 5: Verify git log**

```bash
git log --oneline -10
```

Expected: Series of commits for analyze-feedback implementation.

---

## Summary

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Agent | Create feedback-analyzer.md |
| 2 | Command | Create analyze-feedback.md skeleton |
| 3 | Command | Add Phase 1: PR detection |
| 4 | Command | Add Phase 2: Fetch comments |
| 5 | Command | Add Phase 3: Gather context |
| 6 | Command | Add Phase 4: Analyze comments |
| 7 | Command | Add Phase 5: Generate report |
| 8 | Command | Add Phase 6: Publish responses |
| 9 | Command | Add error handling |
| 10 | Final | Review and version bump |

**Total commits:** 10
**Estimated implementation:** 10 tasks

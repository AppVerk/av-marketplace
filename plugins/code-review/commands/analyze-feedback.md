---
allowed-tools: Read, Glob, Grep, Bash(gh:*), Bash(git:*), Task
description: Analyze PR feedback comments, classify them, and generate response drafts.
model: claude-opus-4-6
argument-hint: [pr-number] [--include-conversation]
---

# Analyze PR Feedback

You analyze comments from a GitHub Pull Request, classify each comment's validity, and generate a report with draft responses for feedback that should be rejected.

## Arguments

- `$ARGUMENTS` - optional PR number and flags

**Parsing:**

- No argument → detect PR from current branch
- Number (e.g., `123`) → use as PR number
- `--include-conversation` → include general PR comments (not just review comments)

---

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

## Phase 5: Generate Report

Present the analysis in this exact format:

~~~markdown
## Feedback Analysis: PR #{pr_number} - "{pr_title}"

**Repository:** {owner}/{repo}
**PR Author:** @{pr_author}
**Comments analyzed:** {total} ({review_count} review, {conversation_count} conversation)

---

### ✅ To Address ({count})

#### 1. @{author} in `{path}:{line}`
> "{comment body - first 200 chars}..."

**Reasoning:** {reasoning from agent}

---

[repeat for each "Address" comment]

---

### ❌ To Reject ({count})

#### 1. @{author} in `{path}:{line}`
> "{comment body - first 200 chars}..."

**Reasoning:** {reasoning from agent}

**Draft response:**
> {draft_response from agent}

---

[repeat for each "Reject" comment]

---

### Summary

| Category | Count |
|----------|-------|
| ✅ To Address | {address_count} |
| ❌ To Reject | {reject_count} |

---

**Publish responses? (all / selected / none)**
~~~

---

## Phase 6: Publish Responses (Optional)

### Step 6.1: Wait for user choice

After presenting the report, wait for user input:

- `all` → publish all draft responses
- `select` → interactive selection
- `none` → skip publishing

### Step 6.2: Handle "select"

Present numbered list of drafts:

```
1. @reviewer in `src/utils.py:28` - "A function is the right choice here..."
2. @reviewer in `src/api.py:55` - "This case is already handled..."
3. @reviewer in `src/models.py:12` - "Validation happens upstream..."

Which to publish? (e.g. 1,3 or 1-3 or "all" / "cancel")
```

Parse user input:

- `1,3` → publish items 1 and 3
- `1-3` → publish items 1, 2, and 3
- `all` → publish all
- `cancel` → cancel, don't publish any

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
Published: 2 of 3 responses
- ✅ @reviewer in `src/utils.py:28`
- ✅ @reviewer in `src/api.py:55`
- ❌ @reviewer in `src/models.py:12` - error: [error message]
```

---

## Error Handling

### GitHub CLI Errors

| Error | Detection | Response |
|-------|-----------|----------|
| Not logged in | `gh auth status` fails | "Log in to GitHub: `gh auth login`" |
| No repo context | `gh repo view` fails | "Run this command in a Git repository directory" |
| Rate limited | 403 with rate limit message | "API rate limit exceeded. Try again in {reset_time}." |
| No permissions | 403/404 on PR | "No access to PR #{number}. Check your permissions." |

### Edge Cases

| Situation | Handling |
|-----------|----------|
| PR has 0 comments | Report: "PR #{n} has no comments to analyze." |
| All comments from PR author | Report: "All comments are from the PR author." |
| Comment already has reply from user | Skip, note in report: "(already replied)" |
| Very long comment (>2000 chars) | Truncate in report, full text to agent |

### Recovery

If publication partially fails:

- Complete publishing remaining items
- Report failures at end
- Suggest retry command for failed items

---
---
allowed-tools: Read, Glob, Grep, Bash(gh:*), Bash(git:*), Task
description: Analyze PR feedback comments, classify them, and generate response drafts.
model: claude-opus-4-5
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

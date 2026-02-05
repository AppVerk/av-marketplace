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

# Commit Hook Enforcement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a PreToolUse hook to the commit plugin that blocks direct `git commit` and redirects agents to `/commit`.

**Architecture:** A bash script registered via `hooks/hooks.json` intercepts Bash tool calls, allows `git commit --amend`, blocks all other `git commit` variants with a structured JSON deny response.

**Tech Stack:** Bash, jq, Claude Code plugin hooks system

---

### Task 1: Create the hook registration file

**Files:**
- Create: `plugins/commit/hooks/hooks.json`

**Step 1: Create hooks directory**

Run: `mkdir -p plugins/commit/hooks`

**Step 2: Write hooks.json**

Create `plugins/commit/hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/block-git-commit.sh"
          }
        ]
      }
    ]
  }
}
```

**Step 3: Commit**

```
git add plugins/commit/hooks/hooks.json
/commit
```

---

### Task 2: Create the blocking script

**Files:**
- Create: `plugins/commit/scripts/block-git-commit.sh`

**Step 1: Create scripts directory**

Run: `mkdir -p plugins/commit/scripts`

**Step 2: Write block-git-commit.sh**

Create `plugins/commit/scripts/block-git-commit.sh`:

```bash
#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Allow: git commit --amend (with any additional flags)
if echo "$COMMAND" | grep -qE 'git\s+commit\s+--amend'; then
  exit 0
fi

# Block: any other git commit
if echo "$COMMAND" | grep -qE 'git\s+commit'; then
  echo '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Direct git commit is blocked. Use the /commit skill instead to generate a meaningful commit message automatically."
    }
  }'
  exit 0
fi

exit 0
```

**Step 3: Make script executable**

Run: `chmod +x plugins/commit/scripts/block-git-commit.sh`

**Step 4: Commit**

```
git add plugins/commit/scripts/block-git-commit.sh
/commit
```

---

### Task 3: Bump plugin version

**Files:**
- Modify: `plugins/commit/.claude-plugin/plugin.json:4` — version `1.0.0` → `1.1.0`
- Modify: `.claude-plugin/marketplace.json:18` — version `1.0.0` → `1.1.0`

**Step 1: Update plugin.json**

In `plugins/commit/.claude-plugin/plugin.json`, change:

```json
"version": "1.0.0"
```

to:

```json
"version": "1.1.0"
```

**Step 2: Update marketplace.json**

In `.claude-plugin/marketplace.json`, change the commit plugin entry:

```json
"version": "1.0.0"
```

to:

```json
"version": "1.1.0"
```

**Step 3: Commit**

```
git add plugins/commit/.claude-plugin/plugin.json .claude-plugin/marketplace.json
/commit
```

---

### Task 4: Update README

**Files:**
- Modify: `README.md:18`

**Step 1: Update version in plugin table**

In `README.md`, change line 18:

```markdown
| [Commit](docs/plugins/commit.md) | 1.0.0 | Conventional Commits message generation from staged changes |
```

to:

```markdown
| [Commit](docs/plugins/commit.md) | 1.1.0 | Conventional Commits message generation from staged changes. Auto-blocks direct `git commit` via hook |
```

**Step 2: Commit**

```
git add README.md
/commit
```

---

### Task 5: Update plugin documentation

**Files:**
- Modify: `docs/plugins/commit.md:5` — version
- Modify: `docs/plugins/commit.md` — add section at end

**Step 1: Update version**

In `docs/plugins/commit.md`, change line 5:

```markdown
**Version:** 1.0.0
```

to:

```markdown
**Version:** 1.1.0
```

**Step 2: Add Auto-enforcement section**

Append to end of `docs/plugins/commit.md`:

```markdown

## Auto-enforcement

This plugin includes a PreToolUse hook that automatically blocks direct `git commit` commands. When any agent or subagent attempts to run `git commit`, the hook denies the command and instructs the agent to use `/commit` instead.

**What's blocked:**
- `git commit -m "message"`
- `git commit` (interactive)
- Chained commands containing `git commit` (e.g., `git add . && git commit -m "msg"`)

**What's allowed:**
- `git commit --amend` — the `/commit` skill doesn't support amending

The hook is registered automatically when the plugin is enabled. No configuration required.
```

**Step 3: Commit**

```
git add docs/plugins/commit.md
/commit
```

---

### Task 6: Clean up design documents

**Files:**
- Delete: `docs/plans/2026-02-26-commit-hook-enforcement-design.md`
- Delete: `docs/plans/2026-02-26-commit-hook-enforcement-plan.md`

**Step 1: Remove plan files**

Run: `rm docs/plans/2026-02-26-commit-hook-enforcement-design.md docs/plans/2026-02-26-commit-hook-enforcement-plan.md`

**Step 2: Commit**

```
git add -u docs/plans/
/commit
```

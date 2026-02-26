# Design: Commit Hook Enforcement

## Problem

Subagents and the main agent use raw `git commit -m "..."` instead of the `/commit` skill when creating commits. This bypasses Conventional Commits formatting, co-authorship rules, and consistent commit message quality that the commit plugin provides.

## Solution

Add a PreToolUse hook to the `commit` plugin that blocks direct `git commit` commands and redirects agents to use `/commit`.

## Approach

**Hook with JSON `permissionDecision: "deny"`** — the script intercepts Bash tool calls, checks if the command contains `git commit`, and returns a structured deny response with a reason pointing to `/commit`.

### Design Decisions

- **`git commit --amend` is allowed** — the `/commit` skill doesn't support amending, so this must remain available.
- **All other `git commit` variants are blocked** — including chained commands (`&&`, `;`).
- **Auto-registered** — `hooks/hooks.json` is read automatically when the plugin is enabled. No user configuration required.
- **`${CLAUDE_PLUGIN_ROOT}`** — used to reference the script relative to the plugin directory, regardless of cache location.

## File Changes

### New Files

**`plugins/commit/hooks/hooks.json`**

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

**`plugins/commit/scripts/block-git-commit.sh`**

```bash
#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Allow: git commit --amend
if echo "$COMMAND" | grep -qE 'git\s+commit\s+--amend'; then
  exit 0
fi

# Block: any git commit
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

### Modified Files

- `plugins/commit/.claude-plugin/plugin.json` — version `1.0.0` → `1.1.0`
- `.claude-plugin/marketplace.json` — version `1.0.0` → `1.1.0`
- `README.md` — update commit plugin version in table
- `docs/plugins/commit.md` — add "Auto-enforcement" section documenting the hook

#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Block: any form of `git push` (no exceptions).
# Matches `git push`, `git push --force`, `git -C /path push`,
# `git --git-dir=... push`, and `git push` after `;`, `&&`, `||`, `|`, `` ` ``, `(`.
if echo "$COMMAND" | grep -qE '(^|[;&|`(]|\s)git(\s+(\S+))*\s+push(\s|$)'; then
  echo '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "git push is permanently blocked for Claude Code in this environment. Run the push yourself from your terminal."
    }
  }'
  exit 0
fi

exit 0

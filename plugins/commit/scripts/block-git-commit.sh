#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Allow: invoked via /commit skill (AV_COMMIT_SKILL=1 prefix)
if echo "$COMMAND" | grep -qE 'AV_COMMIT_SKILL=1\s+git\s+commit'; then
  exit 0
fi

# Allow: git commit --amend
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

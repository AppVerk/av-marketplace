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

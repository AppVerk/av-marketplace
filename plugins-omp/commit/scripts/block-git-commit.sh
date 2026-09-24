#!/bin/bash
# block-git-commit.sh — PreToolUse guard for `git commit` (commit plugin).
#
# Decision cascade (first match wins):
#   - AV_COMMIT_SKILL=1 present + a commit invocation  -> allow (exit 0)
#   - git commit --amend                               -> allow (exit 0)
#   - any other git commit                             -> deny
#   - non-commit commands (e.g. ls)                    -> allow (exit 0)
# Safety rule: a direct `git commit` must be blocked; the /commit skill is the
# only sanctioned path. Anything that is not a commit is allowed untouched.

emit_deny() {
  printf '%s\n' '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Direct git commit is blocked. Use the /commit skill instead to generate a meaningful commit message automatically."
    }
  }'
}

# decide "<command>" — applies the commit cascade to an extracted command.
decide() {
  local command="$1"

  # Allow: invoked via /commit skill (AV_COMMIT_SKILL=1 anywhere in command)
  if printf '%s' "$command" | grep -q 'AV_COMMIT_SKILL=1' \
      && printf '%s' "$command" | grep -qE 'git\s+commit'; then
    exit 0
  fi

  # Allow: git commit --amend
  if printf '%s' "$command" | grep -qE 'git\s+commit\s+--amend'; then
    exit 0
  fi

  # Block: any other git commit
  if printf '%s' "$command" | grep -qE 'git\s+commit'; then
    emit_deny
    exit 0
  fi

  exit 0
}

main() {
  local input command
  input="$(cat)"

  # Fail closed if jq is missing/broken: without it we cannot parse the
  # command out of the JSON payload. Rather than silently allowing a commit
  # to slip through, run the same cascade against the raw stdin: if it
  # mentions a commit invocation, deny; otherwise (e.g. `ls`) allow,
  # preserving the non-commit-command semantics.
  if ! command -v jq >/dev/null 2>&1; then
    decide "$input"
  fi

  command="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
  decide "$command"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi

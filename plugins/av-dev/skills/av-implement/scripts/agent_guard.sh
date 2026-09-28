#!/usr/bin/env bash
# agent_guard.sh - PreToolUse hook for Bash: decides about calls of agent.sh.
#
# Input: the hook JSON on stdin (tool_name, tool_input.command).
# Output: a hookSpecificOutput decision, or nothing when the call is not about agent.sh.
#   allow  a plain call of the agent.sh next to this script: "bash <path>/agent.sh <args>"
#          or "<path>/agent.sh <args>", without --grant, without variable assignments,
#          without shell operators, substitutions or redirections.
#   ask    any other call that names this agent.sh: --grant (widens the executor's
#          permissions), a prefix VAR=..., a compound command, a substitution. A human decides.
#   none   a command that does not name this agent.sh; the usual permission rules apply.
# The decision replaces an allow rule in settings: a rule cannot use ${CLAUDE_PLUGIN_ROOT},
# and a rule like "agent.sh:*" also matched --grant full. A matching deny or ask rule in
# settings still wins over "allow" from this hook.
# Plugin: hooks/hooks.json. Without the plugin: a PreToolUse hook with matcher Bash in
# ~/.claude/settings.json that runs "bash <skills>/av-implement/scripts/agent_guard.sh".
# Requires: bash 3.2+, jq. Exit code always 0; bad input gives no decision.

set -uo pipefail
set -f

command -v jq >/dev/null 2>&1 || exit 0

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
agent="$script_dir/agent.sh"

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

decide() {
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

physical() {
  local p="$1"
  case "$p" in \~/*) p="$HOME/${p#\~/}" ;; esac
  [ -f "$p" ] || return 1
  printf '%s/%s' "$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" "$(basename "$p")"
}

# The command names this agent.sh: its physical path, the path under the plugin root,
# or any word ending in agent.sh that resolves to it (e.g. through a symlink).
names_agent() {
  case "$1" in
    *"$agent"*) return 0 ;;
  esac
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    case "$1" in
      *"${CLAUDE_PLUGIN_ROOT%/}/skills/av-implement/scripts/agent.sh"*) return 0 ;;
    esac
  fi
  local word
  for word in $(printf '%s' "$1" | tr "\"';&|<>()\`" ' '); do
    case "$word" in
      *agent.sh) [ "$(physical "$word")" = "$agent" ] && return 0 ;;
    esac
  done
  return 1
}

names_agent "$cmd" || exit 0

ask_reason="av-dev: this agent.sh call is not a plain slot run"
case "$cmd" in
  *$'\n'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'$'*|*'`'*|*'('*|*')'*|*'\'*)
    decide ask "$ask_reason (shell operators, substitution or redirection). Approve only if you expect it." ;;
esac

# The first word, optionally after "bash", must be this agent.sh; quotes around it are allowed.
rest="$cmd"
rest="${rest#"${rest%%[![:space:]]*}"}"
case "$rest" in
  bash\ *) rest="${rest#bash}"; rest="${rest#"${rest%%[![:space:]]*}"}" ;;
esac
case "$rest" in
  \"*) path="${rest#\"}"; path="${path%%\"*}"; args="${rest#\""$path"\"}" ;;
  \'*) path="${rest#\'}"; path="${path%%\'*}"; args="${rest#\'"$path"\'}" ;;
  *) path="${rest%%[[:space:]]*}"; args="${rest#"$path"}" ;;
esac
[ "$(physical "$path")" = "$agent" ] || decide ask "$ask_reason (it does not start with bash <plugin>/skills/av-implement/scripts/agent.sh). Approve only if you expect it."

case " $args " in
  *[[:space:]]--grant[[:space:]]*|*[[:space:]]--grant=*)
    decide ask "av-dev: agent.sh --grant widens the permissions of a slot executor (e.g. Codex without a sandbox). Approve only if you agreed to this grant." ;;
esac

decide allow "av-dev: plain slot run of agent.sh"

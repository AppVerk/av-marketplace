#!/usr/bin/env bash
# agent_guard.sh - PreToolUse hook for Bash: decides about calls of agent.sh and agent_grant.sh.
#
# Input: the hook JSON on stdin (tool_name, tool_input.command, cwd, permission_mode).
# Output: a hookSpecificOutput decision, or nothing when the call names neither script.
#   allow  a plain call of the agent.sh next to this script, "bash <path>/agent.sh <args>" or
#          "<path>/agent.sh <args>": the whole command has only plain characters
#          [A-Za-z0-9._:/=@+-], spaces and tabs, and every argument is on the whitelist below.
#          With plain characters the shell passes the words unchanged, so the text is the argv.
#   ask    any other call that names agent.sh or agent_grant.sh: quotes, braces, globs,
#          escapes, operators, variables, a prefix VAR=..., a flag or value off the whitelist.
#          agent_grant.sh (resume with a grant) always asks: that prompt is the human approval.
#   deny   agent_grant.sh in bypassPermissions mode, where Claude Code would not ask; the
#          human runs the command with "!".
#   none   a command that names neither script; the usual permission rules apply.
# Whitelist for a plain agent.sh call:
#   --slot NAME, --run-id ID, --label TEXT   plain words
#   --root DIR          the repo of the hook's working directory (physical path)
#   --prompt-file P     an existing file under the repo with "/<run-id>/agents/" in its path
#   --access A          the slot's default: write for plan and implement, read for the rest
#   --timeout N         digits
#   --resolve, --summary, --dry-run, -h, --help
#   --record, --status S, --seconds N, --actual M, --fp-before FP, --out P (under the repo)
# Off the list, so a human decides: --config, --harness, --resume, --grant, anything else.
# agent.sh checks --root, --prompt-file, --access and --harness again: a hook can be missing.
# The decision replaces an allow rule in settings: a rule cannot use ${CLAUDE_PLUGIN_ROOT},
# and a rule like "agent.sh:*" also matched --grant full. A matching deny or ask rule in
# settings still wins over "allow" from this hook.
# Plugin: hooks/hooks.json. Without the plugin: a PreToolUse hook with matcher Bash in
# ~/.claude/settings.json that runs "bash <skills>/av-implement/scripts/agent_guard.sh".
# Requires: bash 3.2+, git, jq. Exit code always 0; bad input gives no decision.

set -uo pipefail
set -f

command -v jq >/dev/null 2>&1 || exit 0

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
agent="$script_dir/agent.sh"
grant="$script_dir/agent_grant.sh"

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0
hook_cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
mode="$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)"

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

# names SCRIPT NAME - the command names SCRIPT: its physical path, the path under the plugin
# root, or any word ending in NAME that resolves to it (e.g. through a symlink).
names() {
  case "$cmd" in
    *"$1"*) return 0 ;;
  esac
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    case "$cmd" in
      *"${CLAUDE_PLUGIN_ROOT%/}/skills/av-implement/scripts/$2"*) return 0 ;;
    esac
  fi
  local word
  for word in $(printf '%s' "$cmd" | tr "\"';&|<>(){}\`" ' '); do
    case "$word" in
      *"$2") [ "$(physical "$word")" = "$1" ] && return 0 ;;
    esac
  done
  return 1
}

if names "$grant" agent_grant.sh; then
  if [ "$mode" = "bypassPermissions" ]; then
    decide deny "av-dev: agent_grant.sh widens the permissions of a slot executor and needs a human. In bypassPermissions nothing asks, so run it yourself: ! $cmd"
  fi
  decide ask "av-dev: agent_grant.sh resumes a slot executor with a wider permission (e.g. Codex without a sandbox). Approve only if you agreed to this grant."
fi
names "$agent" agent.sh || exit 0

ask_reason="av-dev: this agent.sh call is not a plain slot run"
not_plain() { decide ask "$ask_reason ($1). Approve only if you expect it."; }

others="$(printf '%s' "$cmd" | LC_ALL=C tr -d 'A-Za-z0-9._:/=@+ \t-')"
[ -z "$others" ] || not_plain "a character other than letters, digits, spaces and ._:/=@+-"

# Words: the text is the argv (no quotes, escapes or globs are left; set -f above).
# shellcheck disable=SC2206
words=($cmd)
i=0
[ "${words[0]:-}" = "bash" ] && i=1
[ "$(physical "${words[$i]:-}")" = "$agent" ] || not_plain "it does not start with bash <plugin>/skills/av-implement/scripts/agent.sh"
i=$((i + 1))

repo=""
[ -n "$hook_cwd" ] && repo="$(git -C "$hook_cwd" rev-parse --show-toplevel 2>/dev/null)" && repo="$(cd "$repo" && pwd -P)"

# inside_repo PATH - the physical path of an existing PATH (relative to the hook cwd) under repo
inside_repo() {
  local p="$1" real
  [ -n "$repo" ] || return 1
  case "$p" in /*) ;; *) p="$hook_cwd/$p" ;; esac
  real="$(physical "$p")" || return 1
  case "$real" in "$repo"/*) return 0 ;; esac
  return 1
}

slot=""; run_id=""; access=""; prompt=""; root_arg=""
plain_word='^[A-Za-z0-9._:@+-]+$'
while [ "$i" -lt "${#words[@]}" ]; do
  flag="${words[$i]}"; value="${words[$((i + 1))]:-}"
  case "$flag" in
    --resolve|--summary|--dry-run|--record|-h|--help) i=$((i + 1)); continue ;;
    --slot|--run-id|--label|--status|--actual|--fp-before)
      printf '%s' "$value" | grep -Eq "$plain_word" || not_plain "$flag needs a plain value"
      case "$flag" in --slot) slot="$value" ;; --run-id) run_id="$value" ;; esac ;;
    --timeout|--seconds)
      printf '%s' "$value" | grep -Eq '^[0-9]+$' || not_plain "$flag needs digits" ;;
    --access) access="$value" ;;
    --root) root_arg="$value" ;;
    --prompt-file) prompt="$value" ;;
    --out) inside_repo "$value" || not_plain "--out outside the repo" ;;
    *) not_plain "flag $flag is not on the whitelist" ;;
  esac
  i=$((i + 2))
done

if [ -n "$root_arg" ]; then
  [ -n "$repo" ] && [ "$(cd "$root_arg" 2>/dev/null && pwd -P)" = "$repo" ] || not_plain "--root is not the repo of the working directory"
fi
if [ -n "$access" ]; then
  default="read"
  case "$slot" in plan|implement) default="write" ;; esac
  [ "$access" = "$default" ] || not_plain "--access $access is not the default of slot ${slot:-?}"
fi
if [ -n "$prompt" ]; then
  inside_repo "$prompt" || not_plain "--prompt-file is not an existing file in the repo"
  case "$prompt" in
    */"$run_id"/agents/*) [ -n "$run_id" ] || not_plain "--prompt-file without --run-id" ;;
    *) not_plain "--prompt-file is not in <runs>/<run-id>/agents/" ;;
  esac
fi

decide allow "av-dev: plain slot run of agent.sh"

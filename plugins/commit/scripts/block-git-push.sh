#!/bin/bash
# block-git-push.sh — PreToolUse guard for `git push` (commit plugin).
#
# Decision cascade (first match wins):
#   0. no real `git push` subcommand        -> allow (exit 0)
#   1. force-push                            -> deny
#   2. --mirror                              -> deny
#   3. delete of a protected branch          -> deny
#   4. non-origin / URL remote               -> ask
#   5. tag push                              -> ask
#   6. target branch is master/main          -> ask
#   7. target undeterminable                 -> ask
#   8. otherwise (feature branch, origin)    -> allow (exit 0)
# Safety rule: anything we cannot parse reliably -> ask, never silent allow.

PROTECTED_RE='^(master|main)$'

R_FORCE="Force-push is blocked for Claude Code. If you intend to force-push, run it yourself from your terminal."
R_MIRROR="git push --mirror can overwrite or delete remote refs and is blocked."
R_DELPROT="Deleting a protected branch (master/main) is blocked. Run it yourself from your terminal if intended."
R_REMOTE="This push targets a remote other than 'origin' (or a URL). Confirm you intend to push there."
R_TAG="This push publishes a tag, which may trigger a release. Confirm you intend to push it."
R_PROT="This push targets a protected branch (master/main). Confirm you intend to push directly to it."
R_UNDET="The push target could not be verified. Confirm this push is safe."

# Emit a decision as PreToolUse JSON and exit. $1=decision $2=reason
emit() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# find_push_inv "<command>" -> prints the push invocation (tokens from `push`
# to end of its segment, space-joined) or nothing; returns 1 if no git-push
# subcommand. Prints the sentinel AMBIGUOUS when a global option's value is
# quoted (tokenization unreliable).
find_push_inv() {
  local cmd="$1" seg
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    local -a t; read -r -a t <<< "$seg"
    local i=0 n=${#t[@]}
    while [ $i -lt $n ] && [[ ${t[$i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i+1)); done
    { [ $i -lt $n ] && [ "${t[$i]}" = "git" ]; } || continue
    i=$((i+1))
    while [ $i -lt $n ]; do
      case "${t[$i]}" in
        --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*) i=$((i+1));;
        --git-dir|--work-tree|--namespace|--exec-path|-C|-c)
          local val="${t[$((i+1))]}"
          case "$val" in *\'*|*\"*) printf 'AMBIGUOUS'; return 0;; esac
          i=$((i+2));;
        -*) i=$((i+1));;
        *) break;;
      esac
    done
    if [ $i -lt $n ] && [ "${t[$i]}" = "push" ]; then
      printf '%s' "${t[*]:$i}"
      return 0
    fi
  done < <(printf '%s' "$cmd" | sed -E 's/(\&\&|\|\||[;&|`()])/\n/g')
  return 1
}

main() {
  local cmd cwd inv
  local input; input="$(cat)"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"

  inv="$(find_push_inv "$cmd")" || exit 0
  [ -n "$inv" ] || exit 0
  [ "$inv" = "AMBIGUOUS" ] && emit ask "$R_UNDET"

  # cascade layers are added here in later tasks

  exit 0   # allow
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi

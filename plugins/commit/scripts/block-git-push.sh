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
  done < <(printf '%s\n' "$cmd" | sed -E 's/(\&\&|\|\||[;&|`()])/\n/g')
  return 1
}

# inv_has_force "<push-invocation>" -> 0 if a force-push is present.
inv_has_force() {
  local -a t; read -r -a t <<< "$1"
  local i seen_dd=0
  for ((i=1;i<${#t[@]};i++)); do
    local x="${t[$i]}"
    if [ "$x" = "--" ]; then seen_dd=1; continue; fi
    if [ $seen_dd -eq 1 ]; then
      case "$x" in +*) return 0;; esac
      continue
    fi
    case "$x" in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes) return 0;;
      --*) ;;
      -*) [[ "$x" =~ ^-[A-Za-z0-9]+$ && "$x" == *f* ]] && return 0;;
      +*) return 0;;
    esac
  done
  return 1
}

# inv_has_mirror "<push-invocation>" -> 0 if --mirror present.
inv_has_mirror() { case " $1 " in *" --mirror "*) return 0;; esac; return 1; }

# parse_remote_refspecs "<push-invocation>" — sets globals REMOTE and REFSPECS[].
parse_remote_refspecs() {
  local -a t; read -r -a t <<< "$1"
  REMOTE=""; REFSPECS=(); local i seen_dd=0 positional=0
  for ((i=1;i<${#t[@]};i++)); do
    local x="${t[$i]}"
    if [ $seen_dd -eq 0 ] && [ "$x" = "--" ]; then seen_dd=1; continue; fi
    if [ $seen_dd -eq 0 ]; then
      case "$x" in
        -o|--push-option|--repo|--receive-pack|--exec) i=$((i+1)); continue;;
        --*) continue;;
        -*) continue;;
      esac
    fi
    if [ $positional -eq 0 ] && [[ "$x" != -* ]]; then REMOTE="$x"; positional=1
    else REFSPECS+=("$x"); fi
  done
}

# dst_of "<refspec>" -> normalized destination branch/ref name.
dst_of() {
  local r="${1#+}"
  case "$r" in *:*) r="${r##*:}";; esac
  r="${r#refs/heads/}"; r="${r#refs/tags/}"
  printf '%s' "$r"
}

# inv_is_delete "<push-invocation>" -> 0 if --delete/-d present.
inv_is_delete() { case " $1 " in *" --delete "*|*" -d "*) return 0;; esac; return 1; }

# refspec_is_delete "<refspec>" -> 0 if empty-src delete form (:dst).
refspec_is_delete() { local r="${1#+}"; case "$r" in :*) return 0;; esac; return 1; }

is_protected() { [[ "$1" =~ $PROTECTED_RE ]]; }

# remote_kind "<remote-token>" -> prints origin | other | url
remote_kind() {
  local r="$1"
  case "$r" in
    *"://"*) echo url; return;;
    *@*:*)   echo url; return;;   # scp-like user@host:path
  esac
  [ "$r" = "origin" ] && { echo origin; return; }
  echo other
}

main() {
  local cmd cwd inv
  local input; input="$(cat)"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"

  inv="$(find_push_inv "$cmd")" || exit 0
  [ -n "$inv" ] || exit 0
  [ "$inv" = "AMBIGUOUS" ] && emit ask "$R_UNDET"

  inv_has_force "$inv" && emit deny "$R_FORCE"
  inv_has_mirror "$inv" && emit deny "$R_MIRROR"

  parse_remote_refspecs "$inv"
  local rs d
  for rs in "${REFSPECS[@]}"; do
    if inv_is_delete "$inv" || refspec_is_delete "$rs"; then
      d="$(dst_of "$rs")"
      is_protected "$d" && emit deny "$R_DELPROT"
    fi
  done

  if [ -n "$REMOTE" ]; then
    case "$(remote_kind "$REMOTE")" in
      url|other) emit ask "$R_REMOTE";;
    esac
  fi

  exit 0   # allow
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi

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

# Protected branches are intentionally hardcoded to master/main for v1.4.0
# (deliberate design decision: no configuration, keep the guardrail simple).
# A future version could add an opt-in env override if a real need arises.
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
  local out
  if out="$(jq -n --arg d "$1" --arg r "$2" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}' 2>/dev/null)"; then
    printf '%s\n' "$out"
  else
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Hook internal error; confirm this push is safe."}}'
  fi
  exit 0
}

# find_push_invs "<command>" -> prints every push invocation, one per line
# (tokens from `push` to end of its segment, space-joined).
# Prints the single line AMBIGUOUS when a global-option value is quoted
# (tokenization unreliable). Returns 1 if NO push invocation found.
find_push_invs() {
  local cmd="$1" seg found=0
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    local -a t; read -r -a t <<< "$seg"
    local i=0 n=${#t[@]}
    while (( i < n )) && [[ ${t[$i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i+1)); done
    { (( i < n )) && [ "${t[$i]}" = "git" ]; } || continue
    i=$((i+1))
    while (( i < n )); do
      case "${t[$i]}" in
        --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*) i=$((i+1));;
        --git-dir|--work-tree|--namespace|--exec-path|-C|-c)
          local val="${t[$((i+1))]}"
          case "$val" in *\'*|*\"*) printf 'AMBIGUOUS\n'; return 0;; esac
          i=$((i+2));;
        -*) i=$((i+1));;
        *) break;;
      esac
    done
    if (( i < n )) && [ "${t[$i]}" = "push" ]; then
      printf '%s\n' "${t[*]:$i}"
      found=1
    fi
  done < <(printf '%s\n' "$cmd" | sed -E 's/(\&\&|\|\||[;&|`()])/\n/g')
  (( found == 1 )) && return 0
  return 1
}

# inv_has_force "<push-invocation>" -> 0 if a force-push is present.
inv_has_force() {
  local -a t; read -r -a t <<< "$1"
  local i seen_dd=0
  for ((i=1;i<${#t[@]};i++)); do
    local x="${t[$i]}"
    if [ "$x" = "--" ]; then seen_dd=1; continue; fi
    if (( seen_dd == 1 )); then
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
    if (( seen_dd == 0 )) && [ "$x" = "--" ]; then seen_dd=1; continue; fi
    if (( seen_dd == 0 )); then
      case "$x" in
        -o|--push-option|--repo|--receive-pack|--exec) i=$((i+1)); continue;;
        --*) continue;;
        -*) continue;;
      esac
    fi
    if (( positional == 0 )) && [[ "$x" != -* ]]; then REMOTE="$x"; positional=1
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

# effective_dir "<command>" "<cwd>" -> dir to run git in (honors -C/--git-dir).
# Note: paths with spaces are not supported and fall back to ask via resolve_push.
effective_dir() {
  local cmd="$1" cwd="$2"
  if [[ "$cmd" =~ (^|[[:space:]])-C[[:space:]]+([^[:space:]]+) ]]; then printf '%s' "${BASH_REMATCH[2]}"; return; fi
  if [[ "$cmd" =~ (^|[[:space:]])--git-dir=([^[:space:]]+) ]]; then printf '%s' "${BASH_REMATCH[2]}"; return; fi
  printf '%s' "$cwd"
}

# inv_has_tag_flag "<push-invocation>" -> 0 if --tags/--follow-tags.
inv_has_tag_flag() { case " $1 " in *" --tags "*|*" --follow-tags "*) return 0;; esac; return 1; }

# dst_is_tag "<refspec>" "<dir>" -> 0 if dst is under refs/tags or an existing tag.
dst_is_tag() {
  local raw="${1#+}" dst; dst="${raw##*:}"
  case "$dst" in refs/tags/*) return 0;; esac
  local name="${dst#refs/heads/}"
  [ -n "$2" ] && git -C "$2" show-ref --verify --quiet "refs/tags/$name" 2>/dev/null && return 0
  return 1
}

# has_cd_prefix "<command>" -> 0 if a cd/pushd precedes the push (repo may differ).
_HAS_CD_RE='(^|[;&|(]|[[:space:]])(cd|pushd)[[:space:]]'
has_cd_prefix() { [[ "$1" =~ $_HAS_CD_RE ]]; }

# resolve_push "<dir>" -> prints "<remote>/<branch>" via @{push} (fallback @{upstream}).
# Note: @{upstream} fallback may be imprecise if push.default differs from tracking branch.
resolve_push() {
  git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null \
    || git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null
}

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

# decide_inv "<inv>" "<cmd>" "<cwd>" -> echoes one line "DECISION|REASON".
# DECISION is deny/ask/allow; REASON is the reason string (empty for allow).
# Must NOT call exit. Runs in a subshell context (command substitution).
decide_inv() {
  local inv="$1" cmd="$2" cwd="$3"

  [ "$inv" = "AMBIGUOUS" ] && { printf 'ask|%s\n' "$R_UNDET"; return; }

  inv_has_force "$inv" && { printf 'deny|%s\n' "$R_FORCE"; return; }
  inv_has_mirror "$inv" && { printf 'deny|%s\n' "$R_MIRROR"; return; }

  local REMOTE="" REFSPECS=()
  parse_remote_refspecs "$inv"
  local rs d

  # --delete with no refspecs: can't verify the delete target
  if inv_is_delete "$inv" && (( ${#REFSPECS[@]} == 0 )); then
    printf 'ask|%s\n' "$R_UNDET"; return
  fi

  for rs in "${REFSPECS[@]}"; do
    if inv_is_delete "$inv" || refspec_is_delete "$rs"; then
      d="$(dst_of "$rs")"
      is_protected "$d" && { printf 'deny|%s\n' "$R_DELPROT"; return; }
    fi
  done

  if [ -n "$REMOTE" ]; then
    case "$(remote_kind "$REMOTE")" in
      url|other) printf 'ask|%s\n' "$R_REMOTE"; return;;
    esac
  fi

  local dir; dir="$(effective_dir "$cmd" "$cwd")"
  inv_has_tag_flag "$inv" && { printf 'ask|%s\n' "$R_TAG"; return; }
  for rs in "${REFSPECS[@]}"; do dst_is_tag "$rs" "$dir" && { printf 'ask|%s\n' "$R_TAG"; return; }; done

  # Determine remote + target branches for classification.
  local -a dsts=()
  if (( ${#REFSPECS[@]} > 0 )); then
    for rs in "${REFSPECS[@]}"; do
      d="$(dst_of "$rs")"
      # A bare HEAD/@ destination (no ":") refers to the current branch.
      # Resolve it so protected-branch classification can't be bypassed.
      if [ "$d" = "HEAD" ] || [ "$d" = "@" ]; then
        d="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        # Detached HEAD / unresolvable -> fail safe to ask, never silent allow.
        { [ -n "$d" ] && [ "$d" != "HEAD" ]; } || { printf 'ask|%s\n' "$R_UNDET"; return; }
      fi
      dsts+=("$d")
    done
  elif [ -n "$REMOTE" ]; then
    : # remote given but no refspec; treat current branch via resolution below
  fi

  if (( ${#dsts[@]} == 0 )); then
    case " $inv " in *" --all "*) dsts+=("master");; esac
  fi

  if (( ${#dsts[@]} == 0 )); then
    has_cd_prefix "$cmd" && { printf 'ask|%s\n' "$R_UNDET"; return; }
    local rp; rp="$(resolve_push "$dir")" || { printf 'ask|%s\n' "$R_UNDET"; return; }
    [ -n "$rp" ] || { printf 'ask|%s\n' "$R_UNDET"; return; }
    local rr="${rp%%/*}"
    case "$(remote_kind "$rr")" in url|other) printf 'ask|%s\n' "$R_REMOTE"; return;; esac
    dsts+=("${rp#*/}")
  fi

  for d in "${dsts[@]}"; do is_protected "$d" && { printf 'ask|%s\n' "$R_PROT"; return; }; done
  for d in "${dsts[@]}"; do [ -n "$d" ] || { printf 'ask|%s\n' "$R_UNDET"; return; }; done

  printf 'allow|\n'
}

main() {
  # Fail closed if jq is missing/broken: without it we cannot parse the
  # command, and an empty parse would silently allow. Reuse emit() (defined
  # above) so a missing jq degrades to `ask`, never a silent allow. emit()
  # itself falls back to a hardcoded ask JSON when jq cannot build the output.
  if ! command -v jq >/dev/null 2>&1; then
    emit ask "$R_UNDET"
    # shellcheck disable=SC2317  # defensive: emit exits, this exit is belt-and-suspenders
    exit 0
  fi

  local cmd cwd
  local input; input="$(cat)"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"

  # Fast path: this hook fires on EVERY Bash call, but only `push` can be a
  # push. If the command contains no `push` substring at all, it cannot be a
  # push, so allow immediately — skipping the .cwd jq read and the sed-based
  # segment split below. `*push*` is a deliberately broad pre-filter; anything
  # containing `push` (incl. compound `... && git push --force`, `git-push`,
  # quoted mentions) still falls through to the full analysis.
  case "$cmd" in
    *push*) : ;;       # fall through to full analysis
    *) exit 0 ;;       # no 'push' anywhere -> nothing to guard, allow fast
  esac

  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"

  local -a invs=()
  while IFS= read -r line; do
    [ -n "$line" ] && invs+=("$line")
  done < <(find_push_invs "$cmd")

  (( ${#invs[@]} == 0 )) && exit 0

  # Aggregate decisions: deny > ask > allow
  local best_d="allow" best_r=""
  local inv res d r
  for inv in "${invs[@]}"; do
    res="$(decide_inv "$inv" "$cmd" "$cwd")"
    d="${res%%|*}"
    r="${res#*|}"
    if [ "$d" = "deny" ]; then
      emit deny "$r"
      # emit exits, but be explicit:
      # shellcheck disable=SC2317  # defensive: emit exits, this return is belt-and-suspenders
      return
    fi
    if [ "$d" = "ask" ] && [ "$best_d" != "ask" ]; then
      best_d="ask"
      best_r="$r"
    fi
  done

  if [ "$best_d" = "ask" ]; then
    emit ask "$best_r"
  fi
  exit 0   # allow
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi

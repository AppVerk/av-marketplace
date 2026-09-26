#!/usr/bin/env bash
# compose_container.sh - id of the running Docker Compose container of THIS checkout.
#
# Another checkout of the same repo (same compose project name) may run on the
# machine, so `docker compose exec` could hit its containers. This script picks
# the container of <service> whose label com.docker.compose.project.working_dir
# is the repo root or a directory under it (compose files in e.g. docker/).
# It compares the logical and the physical path (pwd -P, e.g. /tmp -> /private/tmp).
# It reads `docker ps` only: no `docker compose` (env files may be gitignored),
# and it never starts, stops or execs containers.
#
# Usage:
#   compose_container.sh [--root DIR] <service>
# Options:
#   --root DIR   repo root (default: the repo of the current directory)
# Output: the container id on stdout. Reasons and warnings on stderr.
#   More than one match: the first by container name and a WARNING line.
# Codes: 0 found, 2 not found, Docker CLI missing, daemon not reachable, bad invocation.
# Environment: AV_DOCKER_BIN = docker binary (default: docker).
# Examples:
#   precheck: bash "$AV_SKILLS_DIR/av-verify/scripts/compose_container.sh" app >/dev/null
#   run:      docker exec "$(bash "$AV_SKILLS_DIR/av-verify/scripts/compose_container.sh" app)" composer test
# Requires: bash 3.2+, git, awk, docker CLI.

set -uo pipefail

WD_LABEL="com.docker.compose.project.working_dir"
SERVICE_LABEL="com.docker.compose.service"
TAB="$(printf '\t')"

fail() {
  printf 'compose_container: %s\n' "$1" >&2
  exit 2
}

root_arg=""
service=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || fail "--root needs a directory"; root_arg="$2"; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    -*) fail "unknown option '$1'" ;;
    *) [ -z "$service" ] || fail "more than one service: '$service' and '$1'"; service="$1" ;;
  esac
  shift
done

[ -n "$service" ] || fail "service missing; usage: compose_container.sh [--root DIR] <service>"

# MARK: root

start="${root_arg:-.}"
[ -d "$start" ] || fail "root directory not found: $start"
cdup="$(git -C "$start" rev-parse --show-cdup 2>/dev/null)" || cdup=""
root_logical="$(cd "$start" 2>/dev/null && cd "./$cdup" 2>/dev/null && pwd -L)"
root_physical="$(cd "$start" 2>/dev/null && cd "./$cdup" 2>/dev/null && pwd -P)"
[ -n "$root_logical" ] && [ -n "$root_physical" ] || fail "cannot resolve root directory: $start"

# MARK: docker

docker_bin="${AV_DOCKER_BIN:-docker}"
command -v "$docker_bin" >/dev/null 2>&1 || fail "Docker CLI not found ($docker_bin)"

ps_err="$(mktemp "${TMPDIR:-/tmp}/av-compose.XXXXXX")" || fail "cannot create a temporary file"
trap 'rm -f "$ps_err"' EXIT

listing="$("$docker_bin" ps --filter "label=$SERVICE_LABEL=$service" --filter "status=running" \
  --format "{{.Names}}${TAB}{{.ID}}${TAB}{{.Label \"$WD_LABEL\"}}" 2>"$ps_err")"
ps_rc=$?
if [ "$ps_rc" -ne 0 ]; then
  reason="$(head -n 1 "$ps_err")"
  fail "docker ps failed (code $ps_rc), daemon not reachable? ${reason}"
fi

# MARK: match

under_root() {
  local wd="$1" r
  for r in "$root_logical" "$root_physical"; do
    case "$wd" in
      "$r"|"$r"/*) return 0 ;;
    esac
  done
  return 1
}

matches=""
while IFS="$TAB" read -r name id wd; do
  [ -n "$id" ] && [ -n "$wd" ] || continue
  while [ "${#wd}" -gt 1 ] && [ "${wd%/}" != "$wd" ]; do wd="${wd%/}"; done
  hit=0
  if under_root "$wd"; then
    hit=1
  elif [ -d "$wd" ]; then
    wd_physical="$(cd "$wd" 2>/dev/null && pwd -P)"
    [ -n "$wd_physical" ] && under_root "$wd_physical" && hit=1
  fi
  [ "$hit" -eq 1 ] && matches="${matches}${name}${TAB}${id}
"
done <<LISTING
$listing
LISTING

if [ -z "$matches" ]; then
  fail "no running container of service '$service' for this checkout ($root_logical)"
fi

sorted="$(printf '%s' "$matches" | LC_ALL=C sort -t "$TAB" -k1,1)"
count="$(printf '%s\n' "$sorted" | awk 'NF' | wc -l | tr -d ' ')"
first_name="$(printf '%s\n' "$sorted" | awk -F '\t' 'NR==1{print $1}')"
first_id="$(printf '%s\n' "$sorted" | awk -F '\t' 'NR==1{print $2}')"

if [ "$count" -gt 1 ]; then
  names="$(printf '%s\n' "$sorted" | awk -F '\t' 'NF{printf "%s%s", sep, $1; sep=", "}')"
  printf 'WARNING %s containers of service %s for this checkout (%s); using %s\n' \
    "$count" "$service" "$names" "$first_name" >&2
fi

printf '%s\n' "$first_id"
exit 0

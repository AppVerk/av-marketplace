#!/usr/bin/env bash
# config.sh - av-dev effective config: the team config with a local override.
#
# Team config: .ai/av.config.json (committed).
# Local override: <config>.local, default .ai/av.config.json.local
#   (gitignored, settings of one person or one machine).
# Merge: objects merge recursively, arrays and scalar values replace,
#   null removes the key.
#
# Usage:
#   config.sh [--root DIR] [--config FILE]            effective config (JSON)
#   config.sh --sources [--root DIR] [--config FILE]  files, overridden keys, warnings
# Options:
#   --no-local   skip the local override
#   --out FILE   write the effective config to a file instead of stdout
# --sources output: CONFIG <file>, CONFIG_LOCAL <file>|none, OVERRIDE <key>,
#   REMOVE <key>, WARNING <text>.
# Codes: 0 OK, 2 error (config missing, bad JSON, bad invocation).
# Requires: bash 3.2+, git, jq.

set -uo pipefail

fail() {
  printf 'CONFIG_ERROR %s\n' "$1"
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "jq missing; install jq (brew install jq)"

root_arg=""
config_arg=""
sources=0
no_local=0
out=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root) root_arg="${2:-}"; shift ;;
    --config) config_arg="${2:-}"; shift ;;
    --out) out="${2:-}"; shift ;;
    --sources) sources=1 ;;
    --no-local) no_local=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) fail "unknown argument '$1'" ;;
  esac
  shift
done

if [ -n "$root_arg" ]; then
  root="$(git -C "$root_arg" rev-parse --show-toplevel 2>/dev/null || (cd "$root_arg" 2>/dev/null && pwd))"
else
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -n "$root" ] || fail "root directory missing"

cfg="${config_arg:-$root/.ai/av.config.json}"
case "$cfg" in /*) ;; *) [ -f "$cfg" ] || cfg="$root/$cfg" ;; esac
[ -f "$cfg" ] || fail "config not found: $cfg; run the av-setup skill"
jq empty "$cfg" 2>/dev/null || fail "invalid JSON in $cfg"
jq -e 'type == "object"' "$cfg" >/dev/null 2>&1 || fail "config $cfg is not a JSON object"

local_cfg="$cfg.local"
use_local=0
if [ "$no_local" -eq 0 ] && [ -f "$local_cfg" ]; then
  jq empty "$local_cfg" 2>/dev/null || fail "invalid JSON in $local_cfg"
  jq -e 'type == "object"' "$local_cfg" >/dev/null 2>&1 || fail "config $local_cfg is not a JSON object"
  use_local=1
fi

# MARK: sources

if [ "$sources" -eq 1 ]; then
  printf 'CONFIG %s\n' "${cfg#$root/}"
  if [ "$use_local" -eq 0 ]; then
    printf 'CONFIG_LOCAL none\n'
    exit 0
  fi
  rel="${local_cfg#$root/}"
  printf 'CONFIG_LOCAL %s\n' "$rel"
  jq -r '
    paths(type != "object") as $p
    | ($p | map(tostring) | join(".")) as $k
    | if getpath($p) == null then "REMOVE \($k)" else "OVERRIDE \($k)" end
  ' "$local_cfg"
  case "$local_cfg" in
    "$root"/*)
      if git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
        printf 'WARNING %s is tracked by git; remove it from the repo (git rm --cached) and add it to .gitignore\n' "$rel"
      elif ! git -C "$root" check-ignore -q -- "$rel" 2>/dev/null; then
        printf 'WARNING %s is not in .gitignore; add it so it does not end up in a commit\n' "$rel"
      fi
      ;;
  esac
  exit 0
fi

# MARK: merge

emit() {
  if [ "$use_local" -eq 0 ]; then
    jq . "$cfg"
  else
    jq -s '
      def merge($a; $b):
        if ($a | type) == "object" and ($b | type) == "object" then
          reduce ($b | keys_unsorted[]) as $k ($a;
            if $b[$k] == null then del(.[$k]) else .[$k] = merge($a[$k]; $b[$k]) end)
        else $b end;
      merge(.[0]; .[1])
    ' "$cfg" "$local_cfg"
  fi
}

if [ -n "$out" ]; then
  emit > "$out" || fail "cannot write $out"
else
  emit
fi

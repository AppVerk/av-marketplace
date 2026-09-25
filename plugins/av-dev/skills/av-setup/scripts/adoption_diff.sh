#!/usr/bin/env bash
# adoption_diff.sh - detector of knowledge loss when adopting an AI setup.
#
# Extracts backtick tokens (3-120 characters) from old files (agents,
# commands, pipeline) and checks that each one appears verbatim in the new
# corpus (CLAUDE.md, docs, overlays, role skills). A token without a trace is
# a candidate for the "Knowledge that gets lost" section or for fixing the overlays.
#
# An old file deleted from the tree is read from git show <rev>:<file> (--old-rev).
# Orchestration filter: tokens with RUN_ID, CHECK_ID, EVIDENCE, $ARGUMENTS,
# .claude/agents, .claude/commands, pipeline_state, pipeline_check and
# tokens matching --noise REGEX (ERE, e.g. names of old agents and commands).
# The corpus skips the workspace/ and sessions/ directories and the old files themselves.
#
# Output:
#   LOST <old-file> <token>            token without a trace in the new corpus
#   TOKENS n LOST m FILTERED f         summary (unique tokens)
#
# Usage:
#   adoption_diff.sh [--root DIR] --old <file>... --new <file|dir>... [--noise REGEX]
#   adoption_diff.sh [--root DIR] --old-rev REV --deleted --new <file|dir>... [--noise REGEX]
#     --deleted adds text files deleted since REV to the old files
#     (git diff --name-only --diff-filter=D REV: .md, .txt, .toml, .html).
# Exit code: 0 no LOST, 1 LOST found, 2 usage error.
# Requires: bash 3.2+, git, awk.

set -uo pipefail

root="."
rev=""
deleted=0
noise=""
mode=""
old=()
new=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --old-rev) rev="${2:-}"; shift ;;
    --deleted) deleted=1 ;;
    --noise) noise="${2:-}"; shift ;;
    --old) mode=old ;;
    --new) mode=new ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "USAGE unknown option: $1"; exit 2 ;;
    *)
      case "$mode" in
        old) old+=("$1") ;;
        new) new+=("$1") ;;
        *) echo "USAGE argument without --old or --new: $1"; exit 2 ;;
      esac ;;
  esac
  shift
done
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE root directory not found"; exit 2; }
[ "$deleted" -eq 1 ] && [ -z "$rev" ] && { echo "USAGE --deleted requires --old-rev"; exit 2; }
[ "${#new[@]}" -gt 0 ] || { echo "USAGE missing --new"; exit 2; }
if [ -n "$rev" ]; then
  git -C "$root" rev-parse --verify -q "$rev^{commit}" >/dev/null || { echo "USAGE unknown revision: $rev"; exit 2; }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$root" || exit 2

# MARK: old files

: >"$tmp/oldlist"
for f in ${old[@]+"${old[@]}"}; do printf '%s\n' "${f#$root/}" >>"$tmp/oldlist"; done
if [ "$deleted" -eq 1 ]; then
  git -c core.quotepath=off diff --name-only --diff-filter=D "$rev" -- 2>/dev/null |
    grep -E '\.(md|markdown|txt|toml|html)$' >>"$tmp/oldlist"
fi
awk '!seen[$0]++' "$tmp/oldlist" >"$tmp/oldu"
[ -s "$tmp/oldu" ] || { echo "USAGE no old files (--old or --deleted)"; exit 2; }

: >"$tmp/tokens"
while IFS= read -r f; do
  if [ -f "$f" ]; then cat -- "$f" >"$tmp/src"
  elif [ -n "$rev" ] && git show "$rev:$f" >"$tmp/src" 2>/dev/null; then :
  else printf 'WARNING file not found: %s\n' "$f" >&2; continue; fi
  awk -v file="$f" '
    /^[ \t]*```/ { in_code = !in_code; next }
    in_code { next }
    {
      rest = $0
      while (match(rest, /`[^`]+`/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
        gsub(/^[ \t]+|[ \t]+$/, "", tok)
        if (length(tok) >= 3 && length(tok) <= 120) printf "%s\t%s\n", file, tok
      }
    }' "$tmp/src" >>"$tmp/tokens"
done <"$tmp/oldu"

# MARK: new corpus

: >"$tmp/corpus"
for n in "${new[@]}"; do
  n="${n#$root/}"
  if [ -d "$n" ]; then
    find "$n" -type f \( -name '*.md' -o -name '*.json' -o -name '*.txt' -o -name '*.toml' -o -name '*.yml' -o -name '*.yaml' -o -name '*.html' \) \
      -not -path '*/workspace/*' -not -path '*/sessions/*' 2>/dev/null
  elif [ -f "$n" ]; then
    printf '%s\n' "$n"
  else
    printf 'WARNING new file or directory not found: %s\n' "$n" >&2
  fi
done | sed 's|^\./||' | awk 'NR == FNR { skip[$0] = 1; next } !skip[$0] && !seen[$0]++' "$tmp/oldu" - |
  while IFS= read -r f; do cat -- "$f"; printf '\n'; done >"$tmp/corpus"

# MARK: comparison

default_noise='RUN_ID|CHECK_ID|EVIDENCE|[$]ARGUMENTS|[.]claude/agents|[.]claude/commands|pipeline_state|pipeline_check'
AD_NOISE="$default_noise" AD_EXTRA="$noise" awk -F'\t' -v corpus="$tmp/corpus" '
  BEGIN {
    noise = ENVIRON["AD_NOISE"]; extra = ENVIRON["AD_EXTRA"]
    RS_OLD = RS; RS = "\001"
    if ((getline text < corpus) <= 0) text = ""
    RS = RS_OLD
  }
  {
    file = $1; tok = substr($0, length(file) + 2)
    if (tok in seen) next
    seen[tok] = 1; total++
    if (tok ~ noise || (extra != "" && tok ~ extra)) { filtered++; next }
    if (index(text, tok) == 0) { lost++; printf "LOST %s %s\n", file, tok }
  }
  END { printf "TOKENS %d LOST %d FILTERED %d\n", total, lost, filtered; exit (lost > 0) }
' "$tmp/tokens"

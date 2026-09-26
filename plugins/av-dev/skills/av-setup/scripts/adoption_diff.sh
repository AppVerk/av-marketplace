#!/usr/bin/env bash
# adoption_diff.sh - detector of knowledge loss when adopting an AI setup.
#
# Extracts backtick tokens (3-120 characters) from old files (agents,
# commands, pipeline) and checks that each one appears verbatim in the new
# corpus (CLAUDE.md, docs, overlays, role skills). A token without a trace is
# a candidate for the "Knowledge that gets lost" section or for fixing the overlays.
#
# With --old-rev, every old file is read from git show <rev>:<file> first (the
# content before the edit), and from the tree only when the revision lacks it.
# Without --old-rev, old files come from the tree.
# Old files (--old, --deleted) are never part of the new corpus, even inside a
# --new directory, so a converted or deleted file cannot hide its own losses.
# The exception is an edited (UPDATE) file passed with --keep (requires
# --old-rev): it is an old file read from the revision, and its current tree
# version is added to the new corpus, so it is compared with itself.
# A missing old file gives a WARNING; when none of them can be read the script
# stops with code 2 (e.g. zsh passed --old "$VAR" as one word with spaces).
# Orchestration filter (counted as FILTERED, never LOST):
#   - tokens with RUN_ID, CHECK_ID, EVIDENCE, $ARGUMENTS, .claude/agents,
#     .claude/commands, pipeline_state, pipeline_check, and the exact names
#     STATUS and CHANGED_FILES,
#   - handoff parameters: only KEY=VALUE pairs with an upper-case KEY and a
#     one-word VALUE (MODE=fix, STATUS=DONE|BLOCKED); a value with "/" is kept,
#   - upper-case names used as fields in the old files: NAME=word anywhere or
#     a "NAME:" line inside a fenced block (handoff template),
#   - template placeholders: {name} (not ${VAR} or {a,b}) and <Name> not glued
#     to an identifier (Request<T> is kept),
#   - generic placeholder names: XController.php, Foo*, foo.ts, Example*, Xxx*,
#   - tokens matching --noise REGEX (ERE, e.g. names of old agents and commands).
# The corpus skips the workspace/ and sessions/ directories and the old files
# not passed with --keep.
#
# Output:
#   LOST <old-file> <token>            token without a trace in the new corpus
#   TOKENS n LOST m FILTERED f         summary (unique tokens)
#
# Usage:
#   adoption_diff.sh [--root DIR] --old <file>... --new <file|dir>... [--noise REGEX]
#   adoption_diff.sh [--root DIR] --old-rev REV [--deleted] [--old <file>...] [--keep <file>...]
#                    --new <file|dir>... [--noise REGEX]
#     --deleted adds text files deleted since REV to the old files
#     (git diff --name-only --diff-filter=D REV: .md, .txt, .toml, .html).
#     --keep marks UPDATE files: old content from REV, tree version in the corpus.
# Exit code: 0 no LOST, 1 LOST found, 2 usage error or no old file readable.
# Requires: bash 3.2+, git, awk.

set -uo pipefail

root="."
rev=""
deleted=0
noise=""
mode=""
old=()
keep=()
new=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --old-rev) rev="${2:-}"; shift ;;
    --deleted) deleted=1 ;;
    --noise) noise="${2:-}"; shift ;;
    --old) mode=old ;;
    --new) mode=new ;;
    --keep) mode=keep ;;
    -h|--help) sed -n '2,46p' "$0"; exit 0 ;;
    -*) echo "USAGE unknown option: $1"; exit 2 ;;
    *)
      case "$mode" in
        old) old+=("$1") ;;
        new) new+=("$1") ;;
        keep) keep+=("$1") ;;
        *) echo "USAGE argument without --old, --keep or --new: $1"; exit 2 ;;
      esac ;;
  esac
  shift
done
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE root directory not found"; exit 2; }
[ "$deleted" -eq 1 ] && [ -z "$rev" ] && { echo "USAGE --deleted requires --old-rev"; exit 2; }
[ "${#keep[@]}" -gt 0 ] && [ -z "$rev" ] && { echo "USAGE --keep requires --old-rev"; exit 2; }
[ "${#new[@]}" -gt 0 ] || { echo "USAGE missing --new"; exit 2; }
if [ -n "$rev" ]; then
  git -C "$root" rev-parse --verify -q "$rev^{commit}" >/dev/null || { echo "USAGE unknown revision: $rev"; exit 2; }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$root" || exit 2

# MARK: old files

: >"$tmp/oldlist"
: >"$tmp/keep"
for f in ${old[@]+"${old[@]}"}; do f="${f#$root/}"; printf '%s\n' "${f#./}" >>"$tmp/oldlist"; done
for f in ${keep[@]+"${keep[@]}"}; do f="${f#$root/}"; f="${f#./}"; printf '%s\n' "$f" >>"$tmp/oldlist"; printf '%s\n' "$f" >>"$tmp/keep"; done
if [ "$deleted" -eq 1 ]; then
  git -c core.quotepath=off diff --name-only --diff-filter=D "$rev" -- 2>/dev/null |
    grep -E '\.(md|markdown|txt|toml|html)$' >>"$tmp/oldlist"
fi
awk '!seen[$0]++' "$tmp/oldlist" >"$tmp/oldu"
[ -s "$tmp/oldu" ] || { echo "USAGE no old files (--old or --deleted)"; exit 2; }

: >"$tmp/tokens"
: >"$tmp/fields"
: >"$tmp/skip"
found=0
missing=""
while IFS= read -r f; do
  if [ -n "$rev" ] && git show "$rev:$f" >"$tmp/src" 2>/dev/null; then :
  elif [ -f "$f" ]; then cat -- "$f" >"$tmp/src"
  else printf 'WARNING file not found: %s\n' "$f" >&2; missing="$missing $f"; continue; fi
  found=$((found + 1))
  awk -v file="$f" -v fields="$tmp/fields" '
    /^[ \t]*```/ { in_code = !in_code; next }
    {
      rest = $0
      while (match(rest, /(^|[^A-Za-z0-9_$])[A-Z][A-Z0-9_]*=[A-Za-z0-9_.|-]*([^A-Za-z0-9_.|\/=-]|$)/)) {
        name = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        sub(/^[^A-Z]/, "", name); sub(/=.*$/, "", name)
        print name >>fields
      }
    }
    in_code {
      if (match($0, /^[ \t]*([-*>][ \t]*)?[A-Z][A-Z0-9_]*[ \t]*:/)) {
        name = substr($0, RSTART, RLENGTH); sub(/^[ \t]*([-*>][ \t]*)?/, "", name); sub(/[ \t]*:$/, "", name)
        print name >>fields
      }
      next
    }
    {
      rest = $0
      while (match(rest, /`[^`]+`/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
        gsub(/^[ \t]+|[ \t]+$/, "", tok)
        if (length(tok) >= 3 && length(tok) <= 120) printf "%s\t%s\n", file, tok
      }
    }' "$tmp/src" >>"$tmp/tokens"
done <"$tmp/oldu"
if [ "$found" -eq 0 ]; then
  printf 'USAGE none of the old files can be read:%s\n' "$missing"
  echo "USAGE pass each old file as a separate argument (zsh does not split \"\$VAR\"; use \${=VAR} or an array)"
  exit 2
fi

# MARK: new corpus

awk -v keepf="$tmp/keep" 'FILENAME == keepf { keep[$0] = 1; next } !keep[$0]' "$tmp/keep" "$tmp/oldu" >"$tmp/skip"
: >"$tmp/corpus"
for n in "${new[@]}" ${keep[@]+"${keep[@]}"}; do
  n="${n#$root/}"
  if [ -d "$n" ]; then
    find "$n" -type f \( -name '*.md' -o -name '*.json' -o -name '*.txt' -o -name '*.toml' -o -name '*.yml' -o -name '*.yaml' -o -name '*.html' \) \
      -not -path '*/workspace/*' -not -path '*/sessions/*' 2>/dev/null
  elif [ -f "$n" ]; then
    printf '%s\n' "$n"
  else
    printf 'WARNING new file or directory not found: %s\n' "$n" >&2
  fi
done | sed 's|^\./||' | awk -v skipf="$tmp/skip" 'FILENAME == skipf { skip[$0] = 1; next } !skip[$0] && !seen[$0]++' "$tmp/skip" - |
  while IFS= read -r f; do cat -- "$f"; printf '\n'; done >"$tmp/corpus"

# MARK: comparison

default_noise='RUN_ID|CHECK_ID|EVIDENCE|[$]ARGUMENTS|[.]claude/agents|[.]claude/commands|pipeline_state|pipeline_check|^(STATUS|CHANGED_FILES)$'
AD_NOISE="$default_noise" AD_EXTRA="$noise" awk -F'\t' -v corpus="$tmp/corpus" -v fields="$tmp/fields" '
  function orchestration(t) {
    if (t ~ /^[A-Z][A-Z0-9_]*=[A-Za-z0-9_.|-]*( +[A-Z][A-Z0-9_]*=[A-Za-z0-9_.|-]*)*$/) return 1
    if (t ~ /^[A-Z][A-Z0-9_]*$/ && (t in field)) return 1
    if (t ~ /(^|[^$])\{[A-Za-z_][A-Za-z0-9_ .-]*\}/) return 1
    if (t ~ /(^|[^A-Za-z0-9])<[A-Za-z_][A-Za-z0-9_ .-]*>/) return 1
    if (t ~ /(^|[^A-Za-z0-9])(X[A-Z][a-z]|[Ff]oo([^a-z]|$)|Example([^a-z]|$)|[Xx]xx([^a-z]|$))/) return 1
    return 0
  }
  BEGIN {
    noise = ENVIRON["AD_NOISE"]; extra = ENVIRON["AD_EXTRA"]
    while ((getline name < fields) > 0) field[name] = 1
    RS_OLD = RS; RS = "\001"
    if ((getline text < corpus) <= 0) text = ""
    RS = RS_OLD
  }
  {
    file = $1; tok = substr($0, length(file) + 2)
    if (tok in seen) next
    seen[tok] = 1; total++
    if (tok ~ noise || (extra != "" && tok ~ extra) || orchestration(tok)) { filtered++; next }
    if (index(text, tok) == 0) { lost++; printf "LOST %s %s\n", file, tok }
  }
  END { printf "TOKENS %d LOST %d FILTERED %d\n", total, lost, filtered; exit (lost > 0) }
' "$tmp/tokens"

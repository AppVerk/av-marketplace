#!/usr/bin/env bash
# check_names.sh - checks that names from the docs exist in the code.
#
# Extracts backtick identifiers from markdown files: class and type names
# (CamelCase), methods (camelCase with an uppercase letter inside), constants and keys
# (SNAKE_CASE, snake_case with an underscore). Compares them with a dictionary of words
# from files tracked by git (and new, not ignored ones), except docs
# (*.md), and with file and directory names. *.strings and *.stringsdict files
# in UTF-16 (with BOM) are converted to UTF-8 first, so their keys also count
# as found. Non-ASCII letters (UTF-8 sequences, except punctuation and symbols with
# lead bytes C2 and E2) belong to a name in the docs and in the code alike, so
# `zamówienieId` or `größeWert` is one name, not fragments; they count as letters of either case.
#
# Output:
#   NAME_MISSING file:line name     the name is not in the code (drift candidate)
#
# Skips:
#   - lines that themselves talk about absence or removal, and code blocks
#     (negation words in Polish and English),
#   - names in strikethrough ~~...~~ (history),
#   - placeholders: Foo/foo as a name part (openFoo, fooViewModel, foo_title),
#     Xxx, a single trailing X (BillingApiX), names touching { } < > *
#     (billingApi{Feature}, Request<T>, Http*RequestHandler, account_error*),
#     My<Name> on a line with "np.", "przyklad", "example" or "e.g.",
#   - names shorter than 4 characters,
#   - names from the ignore list: section "## Known false names" (Polish alias
#     "## Znane falszywe nazwy", with or without diacritics) in the overlay
#     <paths.overlays>/av-docs-sync.md (default .ai/overlays), lines
#     "- `Name`" (exact) or "- `Prefix*`" (prefix). --ignore-file
#     replaces the overlay; the file may have that section or just lines with names,
#   - documents excluded by --exclude GLOB (repeatable) or by the overlay section
#     "## Excluded docs paths" (Polish alias "## Wykluczone sciezki docs", with or
#     without diacritics), lines "- `glob`"; --ignore-file does not replace it.
#     Glob syntax like git pathspec :(glob), relative to --root: "*" and "?" do not
#     cross "/", "**" does; a glob without "*" or "?" also excludes everything under it
#     (e.g. `.ai/external_services/`). The summary line ends with EXCLUDED <documents>.
#
# Usage:
#   check_names.sh <file.md|dir> [...] [--root DIR] [--ignore-file FILE]... [--exclude GLOB]...
# Exit code: 0 no candidates, 1 candidates found, 2 usage error.
# Requires: bash 3.2+, git, awk, grep, sort, comm; iconv for UTF-16; jq optional.

set -uo pipefail

root="."
paths=""
ignore_files=""
excludes=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --ignore-file) ignore_files="$ignore_files${2:-}"$'\n'; shift ;;
    --exclude) [ -n "${2:-}" ] || { echo "USAGE --exclude needs a glob"; exit 2; }; excludes="$excludes$2"$'\n'; shift ;;
    -h|--help) sed -n '2,41p' "$0"; exit 0 ;;
    *) paths="$paths$1"$'\n' ;;
  esac
  shift
done
[ -n "$paths" ] || { echo "USAGE check_names.sh <file.md|dir> [...] [--root DIR] [--ignore-file FILE] [--exclude GLOB]"; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE root directory not found"; exit 2; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "USAGE root is not a git repo"; exit 2; }

# shellcheck source=docs_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/docs_lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# MARK: ignored names list

need_section=0
if [ -z "$ignore_files" ]; then
  need_section=1
  ignore_files="$(docs_overlay_file "$root")"$'\n'
else
  printf '%s' "$ignore_files" | while IFS= read -r f; do
    [ -f "$f" ] || [ -f "$root/$f" ] || { printf 'USAGE --ignore-file not found: %s\n' "$f" >&2; echo x; }
  done | grep -q x && exit 2
fi

: >"$tmp/ignore"
printf '%s' "$ignore_files" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || f="$root/$f"
  docs_section_items "$f" names "$need_section"
done >"$tmp/ignore"
docs_exclude_globs "$root" "$excludes" >"$tmp/excludes"

# MARK: dictionary of names from the code
# C locale with UTF-8 sequences as letters: non-ASCII letters stay inside a word in any locale.

utf8_letter=$'[\xc3-\xdf][\x80-\xbf]|[\xe0\xe1\xe3-\xef][\x80-\xbf][\x80-\xbf]|[\xf0-\xf4][\x80-\xbf][\x80-\xbf][\x80-\xbf]'
word_re="([A-Za-z_]|$utf8_letter)([A-Za-z0-9_]|$utf8_letter){3,}"
LC_ALL=C git -C "$root" grep -I -h -o -w -E --untracked "$word_re" -- . ':(exclude)*.md' ':(exclude)*.lock' \
  ':(exclude)*.svg' ':(exclude)*.pbxproj' 2>/dev/null >"$tmp/code_words_raw"
git -C "$root" -c core.quotePath=false ls-files --cached --others --exclude-standard -- '*.strings' '*.stringsdict' 2>/dev/null |
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    bom="$(LC_ALL=C head -c 2 "$root/$f" | od -An -tx1 | tr -d ' \n')"
    case "$bom" in
      fffe|feff) iconv -f UTF-16 -t UTF-8 "$root/$f" 2>/dev/null |
        LC_ALL=C awk -v u="$utf8_letter" 'BEGIN { w = "([A-Za-z0-9_]|" u ")+" }
          { s = $0; while (match(s, w)) { t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
              n = t; gsub(/[\200-\277]/, "", n); if (t !~ /^[0-9]/ && length(n) >= 4) print t } }' ;;
    esac
  done >>"$tmp/code_words_raw"
LC_ALL=C sort -u "$tmp/code_words_raw" >"$tmp/code_words"
git -C "$root" -c core.quotePath=false ls-files --cached --others --exclude-standard 2>/dev/null |
  LC_ALL=C awk -F/ '{ for (i = 1; i < NF; i++) print $i; n = $NF; sub(/\.[^.]+$/, "", n); print n }' | LC_ALL=C sort -u >"$tmp/file_names"
LC_ALL=C sort -u "$tmp/code_words" "$tmp/file_names" >"$tmp/known"

# MARK: documents

printf '%s' "$paths" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    /*) abs="$p" ;;
    *) if [ -e "$root/$p" ]; then abs="$root/$p"; else abs="$(pwd)/$p"; fi ;;
  esac
  if [ -d "$abs" ]; then
    find "$abs" \( -path '*/workspace' -o -path '*/sessions' \) -prune \
      -o -name '*.md' -not -path '*/workspace/*' -not -path '*/sessions/*' -print 2>/dev/null
  elif [ -f "$abs" ]; then
    printf '%s\n' "$abs"
  else
    printf 'WARNING file or directory not found: %s\n' "$p" >&2
  fi
done | sort -u | docs_exclude "$root" "$tmp/excludes" "$tmp/excluded" >"$tmp/docs"
excluded="$(cat "$tmp/excluded" 2>/dev/null)"

[ -s "$tmp/docs" ] || { echo "CHECKED 0 NAME_MISSING 0 EXCLUDED ${excluded:-0}"; exit 0; }

# MARK: name extraction

(
  IFS=$'\n'
  set -f
  # shellcheck disable=SC2046
  LC_ALL=C awk -v ignore_file="$tmp/ignore" -v u="$utf8_letter" '
    # neg, example and placeholder words match docs in Polish and English: repos keep their own language.
    # C locale: u matches one non-ASCII UTF-8 letter, a word letter of either case.
    BEGIN {
      word = "([A-Za-z0-9_]|" u ")+"
      x_suffix = "([a-z0-9]|" u ")X$"
      camel_upper = "^([A-Z]|" u ")([a-z0-9]|" u ")+[A-Z]([A-Za-z0-9]|" u ")*$"
      camel_lower = "^([a-z]|" u ")+[A-Z]([A-Za-z0-9]|" u ")*$"
      snake_upper = "^([A-Z]|" u ")([A-Z0-9]|" u ")*_([A-Z0-9_]|" u ")+$"
      snake_lower = "^([a-z]|" u ")([a-z0-9]|" u ")*_([a-z0-9_]|" u ")+$"
      neg = "(^|[^A-Za-z])(brak|nie istnieje|nie ma|nigdy|never|usuni(e|ę)t[a-z]*|usun(a|ą)(c|ć)|relokow[a-z]*|przeniesion[a-z]*|dawn(y|a|e|iej)|zamiast|removed|deleted|renamed|moved|formerly|previously|no longer|does not exist|instead of)([^A-Za-z]|$)"
      example = "(np\\.|przyk(ł|l)ad|example|e\\.g\\.)"
      while ((getline ig < ignore_file) > 0) {
        if (ig ~ /\*$/) prefix[++np] = substr(ig, 1, length(ig) - 1)
        else exact[ig] = 1
      }
    }
    function ignored(w,    i) {
      if (w in exact) return 1
      for (i = 1; i <= np; i++) if (index(w, prefix[i]) == 1) return 1
      return 0
    }
    function placeholder(w) {
      if (w ~ /^(Foo|Bar|Baz|Xxx|Example|Nazwa|Name|Moduł|Modul|TODO|TICKET|RUN_ID|YYYY)/) return 1
      if (w ~ /(^|[a-z0-9_])Foo([A-Z0-9_]|$)/ || w ~ /(^|_)foo([A-Z0-9_]|$)/) return 1
      if (index(w, "Xxx") > 0 || w ~ x_suffix) return 1
      if (w ~ /^My[A-Z]/ && is_example) return 1
      return 0
    }
    FNR == 1 { in_code = 0 }
    /^[ \t]*```/ { in_code = !in_code; next }
    in_code { next }
    {
      if (tolower($0) ~ neg) next
      line = $0
      gsub(/~~([^~]|~[^~])*~~/, "", line)
      is_example = (tolower(line) ~ example)
      rest = line
      while (match(rest, /`[^`]+`/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
        s = tok; off = 0
        while (match(s, word)) {
          w = substr(s, RSTART, RLENGTH)
          before = substr(tok, off + RSTART - 1, 1)
          after = substr(tok, off + RSTART + RLENGTH, 1)
          off += RSTART + RLENGTH - 1
          s = substr(s, RSTART + RLENGTH)
          chars = w; gsub(/[\200-\277]/, "", chars)
          if (length(chars) < 4 || index(w, "__") > 0 || w ~ /_$/) continue
          if (index("{}<>*", before) > 0 && before != "") continue
          if (index("{}<>*", after) > 0 && after != "") continue
          if (placeholder(w) || ignored(w)) continue
          camel = (w ~ camel_upper || w ~ camel_lower)
          snake = (w ~ snake_upper || w ~ snake_lower)
          if (camel || snake) printf "%s\t%s:%d\n", w, FILENAME, FNR
        }
      }
    }' $(cat "$tmp/docs")
) | LC_ALL=C sort -t "$(printf '\t')" -k1,1 >"$tmp/names"

cut -f1 "$tmp/names" | LC_ALL=C sort -u >"$tmp/unique"
LC_ALL=C comm -23 "$tmp/unique" "$tmp/known" >"$tmp/missing"

checked="$(wc -l <"$tmp/unique" | tr -d ' ')"
count=0
while IFS=$'\t' read -r name where; do
  if LC_ALL=C grep -qxF -- "$name" "$tmp/missing"; then
    printf 'NAME_MISSING %s %s\n' "${where#$root/}" "$name"
    count=$((count + 1))
  fi
done <"$tmp/names"

printf 'CHECKED %s NAME_MISSING %d EXCLUDED %d\n' "$checked" "$count" "${excluded:-0}"
[ "$count" -eq 0 ]

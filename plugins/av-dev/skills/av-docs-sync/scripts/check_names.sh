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
#   KNOWN_STALE <doc>:<line> <name> (a hint) a line scoped ignore entry whose docs line
#                                   no longer contains the name (the document was checked)
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
#     "- `Name`" (exact), "- `Prefix*`" (prefix) or "- `<doc>:<line> Name`"
#     (only on that docs line, <doc> relative to --root; the name may end with "*").
#     --ignore-file replaces the overlay; the file may have that section or just lines
#     with names (a line scoped entry only as a list item in backticks),
#   - lines inside the overlay sections "Known false names", "Known false paths" and
#     "Excluded docs paths" (and their Polish aliases), in any checked document,
#   - documents excluded by --exclude GLOB (repeatable) or by the overlay section
#     "## Excluded docs paths" (Polish alias "## Wykluczone sciezki docs", with or
#     without diacritics), lines "- `glob`"; --ignore-file does not replace it.
#     Glob syntax like git pathspec :(glob), relative to --root: "*" and "?" do not
#     cross "/", "**" does; a glob without "*" or "?" also excludes everything under it
#     (e.g. `.ai/external_services/`). The summary line ends with EXCLUDED <documents>.
#
# The dictionary does not depend on the docs paths given: git grep runs single threaded,
# because threaded git grep in the C locale can drop matches on some platforms.
#
# Usage:
#   check_names.sh <file.md|dir> [...] [--root DIR] [--ignore-file FILE]... [--exclude GLOB]...
# Exit code: 0 no candidates, 1 candidates found, 2 usage error. KNOWN_STALE does not
#   change the code.
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
    -h|--help) sed -n '2,49p' "$0"; exit 0 ;;
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
# --threads=1: threaded git grep in the C locale drops random matches (seen with Apple git).

utf8_letter=$'[\xc3-\xdf][\x80-\xbf]|[\xe0\xe1\xe3-\xef][\x80-\xbf][\x80-\xbf]|[\xf0-\xf4][\x80-\xbf][\x80-\xbf][\x80-\xbf]'
word_re="([A-Za-z_]|$utf8_letter)([A-Za-z0-9_]|$utf8_letter){3,}"
# Env and key files never enter the corpus: their values must not be read, not even into a temp file.
LC_ALL=C git -C "$root" grep --threads=1 -I -h -o -w -E --untracked "$word_re" -- . ':(exclude)*.md' ':(exclude)*.lock' \
  ':(exclude)*.svg' ':(exclude)*.pbxproj' \
  ':(exclude,glob)**/.env' ':(exclude,glob)**/.env.*' ':(exclude,glob)**/*.env' \
  ':(exclude,glob)**/*.pem' ':(exclude,glob)**/*.key' ':(exclude,glob)**/*.p12' ':(exclude,glob)**/*.pfx' \
  ':(exclude,glob)**/*.jks' ':(exclude,glob)**/*.keystore' ':(exclude,glob)**/*.mobileprovision' \
  ':(exclude,glob)**/id_rsa*' ':(exclude,glob)**/id_ed25519*' 2>/dev/null >"$tmp/code_words_raw"
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
  LC_ALL=C awk -v ignore_file="$tmp/ignore" -v used_file="$tmp/line_used" -v root="$root" -v u="$utf8_letter" '
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
        if (ig ~ /:[0-9]+[ \t]+[^ \t]+$/) {
          # line scoped entry "<doc>:<line> <name>": key = normalized "<doc>:<line>"
          k = ig; sub(/[ \t]+[^ \t]+$/, "", k)
          nm = ig; sub(/^.*[ \t]/, "", nm)
          while (substr(k, 1, 2) == "./") k = substr(k, 3)
          nl++; lkey[nl] = k; lname[nl] = nm; lentry[nl] = ig; has_line[k] = 1
          continue
        }
        if (ig ~ /\*$/) prefix[++np] = substr(ig, 1, length(ig) - 1)
        else exact[ig] = 1
      }
      printf "" > used_file
    }
    function name_match(w, nm) {
      if (nm ~ /\*$/) return index(w, substr(nm, 1, length(nm) - 1)) == 1
      return w == nm
    }
    # contains(line, nm): the raw docs line has the name (or a word with the prefix) as a word
    function contains(l, nm,    p, pre, i, c, off) {
      pre = (nm ~ /\*$/); if (pre) nm = substr(nm, 1, length(nm) - 1)
      if (nm == "") return 0
      off = 0
      while ((i = index(substr(l, off + 1), nm)) > 0) {
        i += off
        p = (i > 1) ? substr(l, i - 1, 1) : ""; c = substr(l, i + length(nm), 1)
        if (p !~ /[A-Za-z0-9_\200-\377]/ && (pre || c !~ /[A-Za-z0-9_\200-\377]/)) return 1
        off = i
      }
      return 0
    }
    function ignored(w,    i) {
      if (w in exact) return 1
      for (i = 1; i <= np; i++) if (index(w, prefix[i]) == 1) return 1
      if (key in has_line) for (i = 1; i <= nl; i++) if (lkey[i] == key && name_match(w, lname[i])) return 1
      return 0
    }
    function placeholder(w) {
      if (w ~ /^(Foo|Bar|Baz|Xxx|Example|Nazwa|Name|Moduł|Modul|TODO|TICKET|RUN_ID|YYYY)/) return 1
      if (w ~ /(^|[a-z0-9_])Foo([A-Z0-9_]|$)/ || w ~ /(^|_)foo([A-Z0-9_]|$)/) return 1
      if (index(w, "Xxx") > 0 || w ~ x_suffix) return 1
      if (w ~ /^My[A-Z]/ && is_example) return 1
      return 0
    }
    FNR == 1 {
      in_code = 0
      skip_sec = 0
      rel = FILENAME
      if (index(rel, root "/") == 1) rel = substr(rel, length(root) + 2)
      while (substr(rel, 1, 2) == "./") rel = substr(rel, 3)
      print rel > used_file
    }
    {
      key = rel ":" FNR
      if (key in has_line) for (i = 1; i <= nl; i++) if (lkey[i] == key && contains($0, lname[i])) print "#USED\t" lentry[i] > used_file
    }
    /^[ \t]*```/ { in_code = !in_code; next }
    in_code { next }
    # the ignore sections of an overlay list names on purpose: they are never candidates
    /^#+[ \t]/ {
      skip_sec = ($0 ~ /^#+[ \t]+(Known false names|Znane fa(ł|l)szywe nazwy|Known false paths|Znane fa(ł|l)szywe (ś|s)cie(ż|z)ki|Excluded docs paths|Wykluczone (ś|s)cie(ż|z)ki docs)/)
    }
    skip_sec { next }
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
LC_ALL=C awk -F'\t' -v root="$root" -v missing="$tmp/missing" '
  BEGIN { while ((getline m < missing) > 0) miss[m] = 1 }
  ($1 in miss) { w = $2; if (index(w, root "/") == 1) w = substr(w, length(root) + 2); print "NAME_MISSING " w " " $1 }
' "$tmp/names" >"$tmp/report"
cat "$tmp/report"
count="$(wc -l <"$tmp/report" | tr -d ' ')"

# MARK: stale line scoped entries (hint): the entry's document was checked, its line lacks the name
if [ -s "$tmp/line_used" ]; then
  LC_ALL=C awk -F'\t' -v ignore_file="$tmp/ignore" '
    $1 == "#USED" { used[$2] = 1; next }
    { checked[$0] = 1 }
    END {
      while ((getline ig < ignore_file) > 0) {
        if (ig !~ /:[0-9]+[ \t]+[^ \t]+$/ || (ig in used) || (ig in seen)) continue
        seen[ig] = 1
        d = ig; sub(/:[0-9]+[ \t]+[^ \t]+$/, "", d)
        while (substr(d, 1, 2) == "./") d = substr(d, 3)
        if (d in checked) print "KNOWN_STALE " ig
      }
    }' "$tmp/line_used"
fi

printf 'CHECKED %s NAME_MISSING %d EXCLUDED %d\n' "$checked" "$count" "${excluded:-0}"
[ "$count" -eq 0 ]

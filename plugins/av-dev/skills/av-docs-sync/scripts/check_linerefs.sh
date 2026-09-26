#!/usr/bin/env bash
# check_linerefs.sh - checks file:line references in the docs.
#
# For each reference `path/file.ext:12` or `file.ext:12-20` in backticks
# (the path may have spaces, e.g. `src/Orders & Billing_/list.ts:3`;
# `:40-42` after a reference on the same line inherits its file):
#   - checks that the file exists and the line number fits in the file,
#   - finds the commit that created the docs line (git blame),
#   - when the code file changed since that commit, checks the content: takes
#     identifiers from backticks on the same docs line (without paths) and looks
#     for them (like grep -F) in the given line range.
#
# Output:
#   LINEREF_OK       (not printed, only counted) an identifier is in the range
#   LINEREF_MOVED    an identifier is elsewhere in the file; gives a new range
#                    shifted to the nearest hit
#   LINEREF_GONE     no identifier is in the file or in another file
#                    from the same docs line
#   LINEREF_CHANGED  the file changed and the content cannot be checked: the line
#                    has no identifiers, they are in another file from the line, the line
#                    has a reference without an extension (alias, e.g. `UserVM:12`) or
#                    talks about removal, in Polish or English (then a missing identifier is not GONE)
#   LINEREF_RANGE    the line number is beyond the file length
#   LINEREF_NOFILE   the file does not exist (also run check_refs.sh)
# Paths are resolved relative to root, and if missing, by suffix in `git ls-files`.
#
# Usage:
#   check_linerefs.sh <file.md|dir> [...] [--root DIR] [--strict]
# Exit code: 0 no hits, 1 hits found (CHANGED, MOVED, GONE, RANGE,
#   NOFILE), 2 usage error. With --strict code 1 only for RANGE, NOFILE or GONE.
# Requires: bash 3.2+, git, awk.

set -uo pipefail

root="."
strict=0
paths=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --strict) strict=1 ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) paths="$paths$1"$'\n' ;;
  esac
  shift
done
[ -n "$paths" ] || { echo "USAGE check_linerefs.sh <file.md|dir> [...] [--root DIR] [--strict]"; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE root directory not found"; exit 2; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "USAGE root is not a git repo"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$root" -c core.quotePath=false ls-files --cached --others --exclude-standard >"$tmp/files"
dirty_ok=1
git -C "$root" -c core.quotePath=false diff --name-only --no-renames HEAD >"$tmp/dirty" 2>/dev/null || dirty_ok=0
: >"$tmp/logcache"

changed_since() {
  local hit
  hit="$(awk -F'\t' -v k="$1" -v t="$2" '$1 == k && $2 == t { print $3; exit }' "$tmp/logcache")"
  if [ -z "$hit" ]; then
    if [ -n "$(git -C "$root" log --format=%h -1 "$1..HEAD" -- "$2" 2>/dev/null)" ]; then hit=1; else hit=0; fi
    printf '%s\t%s\t%s\n' "$1" "$2" "$hit" >>"$tmp/logcache"
  fi
  [ "$hit" = "1" ]
}

dirty() {
  if [ "$dirty_ok" -eq 1 ]; then grep -qxF -- "$1" "$tmp/dirty"; else ! git -C "$root" diff --quiet HEAD -- "$1" 2>/dev/null; fi
}

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
done | sort -u >"$tmp/docs"

checked=0
ok=0
changed=0
moved=0
gone=0
range=0
nofile=0

resolve() {
  local ref="$1"
  if grep -qxF -- "$ref" "$tmp/files"; then printf '%s\n' "$ref"; return; fi
  grep -E "(^|/)$(printf '%s' "$ref" | sed 's/[].[\*^$+?(){}|]/\\&/g')$" "$tmp/files" | head -2
}

# MARK: range content
# scan_ids <file> <from> <to> <identifiers>
# Prints OK, MOVED<TAB>line<TAB>identifier or NONE.
scan_ids() {
  awk -v a="$2" -v b="$3" -v ids="$4" '
    BEGIN { n = split(ids, id, " ") }
    found { next }
    {
      for (i = 1; i <= n; i++) {
        if (index($0, id[i]) == 0) continue
        if (FNR >= a && FNR <= b) { found = 1; next }
        d = (FNR < a) ? a - FNR : FNR - b
        if (best == "" || d < best) { best = d; bl = FNR; bid = id[i] }
      }
    }
    END {
      if (found) print "OK"
      else if (best != "") printf "MOVED\t%d\t%s\n", bl, bid
      else print "NONE"
    }' "$1"
}

while IFS= read -r doc; do
  rel_doc="${doc#$root/}"
  # Row: docs_line<TAB>reference<TAB>identifiers (space separated, "-" when none)<TAB>
  # 1 when the line has a reference without an extension (alias) or talks about removal
  # (neg matches Polish and English words: repos keep their own language)
  awk '
    BEGIN {
      ref_re = "^[A-Za-z0-9_.\\/+-][A-Za-z0-9_.\\/+& -]*\\.[A-Za-z0-9]+:[0-9]+(-[0-9]+)?$"
      path_re = "^[A-Za-z0-9_.\\/+-][A-Za-z0-9_.\\/+& -]*\\.(swift|php|ts|js|mjs|json|md|yml|yaml|xml|twig|html|scss|css|py|rb|sh|plist|strings|xib|storyboard|xcconfig|toml|lock|kt|java|go)$"
      ns = split("self this true false null return func function class static final public private protected const void string String then else", sw, " ")
      for (i = 1; i <= ns; i++) stop[sw[i]] = 1
      neg = "(^|[^A-Za-z])(brak|nie istnieje|nie ma|usuni(e|ę)t[a-z]*|usun(a|ą)(c|ć)|przeniesion[a-z]*|dawn(y|a|e|iej)|zamiast|removed|deleted|renamed|moved|formerly|previously|no longer|instead of)([^A-Za-z]|$)"
    }
    function add_ref(t) {
      sub(/^(\.\.\.|…)\//, "", t)
      nref++; refs[nref] = t
      lastpath = t; sub(/:[0-9]+(-[0-9]+)?$/, "", lastpath)
    }
    function add_ids(t,    m, w, k) {
      m = split(t, w, /[^A-Za-z0-9_]+/)
      for (k = 1; k <= m; k++) {
        if (length(w[k]) < 3 || w[k] !~ /^[A-Za-z_]/ || (w[k] in stop) || (w[k] in seen)) continue
        seen[w[k]] = 1
        ids = (ids == "" ? w[k] : ids " " w[k])
      }
    }
    /^[ \t]*```/ { code = !code; next }
    code { next }
    {
      rest = $0; nref = 0; ids = ""; lastpath = ""; alias = 0
      split("", seen)
      while (match(rest, /`[^`]+`/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
        np = split(tok, parts, /[,;]+/)
        isref = 0
        for (i = 1; i <= np; i++) {
          t = parts[i]
          gsub(/^[ \t]+|[ \t]+$/, "", t)
          if (t ~ ref_re && (index(t, " ") == 0 || index(t, "/") > 0)) { add_ref(t); isref = 1; continue }
          if (t ~ /^:[0-9]+(-[0-9]+)?$/ && lastpath != "") { add_ref(lastpath t); isref = 1; continue }
          if (t ~ /^[A-Za-z_][A-Za-z0-9_+.-]*:[0-9]+(-[0-9]+)?$/) { alias = 1; isref = 1; continue }
          nw = split(t, words, /[ \t]+/)
          for (j = 1; j <= nw; j++) {
            if (words[j] ~ ref_re) { add_ref(words[j]); isref = 1 }
          }
        }
        if (!isref && tok !~ path_re && index(tok, "/") == 0) add_ids(tok)
      }
      for (i = 1; i <= nref; i++) print NR "\t" refs[i] "\t" (ids == "" ? "-" : ids) "\t" (alias || tolower($0) ~ neg ? 1 : 0)
    }' "$doc" >"$tmp/refs"
  [ -s "$tmp/refs" ] || continue
  tracked=1
  git -C "$root" ls-files --error-unmatch -- "$rel_doc" >/dev/null 2>&1 || tracked=0
  : >"$tmp/blame"
  if [ "$tracked" -eq 1 ]; then
    git -C "$root" blame --line-porcelain -- "$rel_doc" 2>/dev/null |
      awk '/^[0-9a-f]{40} / { sha = $1; ln = $3 } /^\t/ { print ln "\t" sha }' >"$tmp/blame"
  fi
  while IFS=$'\t' read -r ln ref ids unsure; do
    [ -n "$ref" ] || continue
    [ "$ids" != "-" ] || ids=""
    checked=$((checked + 1))
    path="${ref%:*}"
    lines="${ref##*:}"
    first="${lines%%-*}"
    last="${lines##*-}"
    target="$(resolve "$path")"
    if [ -z "$target" ]; then
      printf 'LINEREF_NOFILE %s:%s %s\n' "$rel_doc" "$ln" "$ref"
      nofile=$((nofile + 1))
      continue
    fi
    case "$target" in *$'\n'*) continue ;; esac
    len="$(wc -l <"$root/$target" 2>/dev/null | tr -d ' ')"
    if [ -n "$len" ] && [ "$last" -gt "$len" ]; then
      printf 'LINEREF_RANGE %s:%s %s (file has %s lines)\n' "$rel_doc" "$ln" "$ref" "$len"
      range=$((range + 1))
      continue
    fi
    sha="$(awk -F'\t' -v l="$ln" '$1 == l { print $2; exit }' "$tmp/blame")"
    if [ -z "$sha" ] || [ "$sha" = "0000000000000000000000000000000000000000" ]; then
      since="HEAD"
    else
      since="$sha"
    fi
    why=""
    if [ "$since" != "HEAD" ] && changed_since "$since" "$target"; then
      why="file changed since $(printf '%s' "$since" | cut -c1-8)"
    elif dirty "$target"; then
      why="file changed in the working tree"
    fi
    [ -n "$why" ] || continue
    if [ -z "$ids" ]; then
      printf 'LINEREF_CHANGED %s:%s %s (%s)\n' "$rel_doc" "$ln" "$ref" "$why"
      changed=$((changed + 1))
      continue
    fi
    res="$(scan_ids "$root/$target" "$first" "$last" "$ids")"
    case "$res" in
      OK)
        ok=$((ok + 1)) ;;
      MOVED*)
        at="$(printf '%s' "$res" | cut -f2)"
        id="$(printf '%s' "$res" | cut -f3)"
        if [ "$at" -lt "$first" ]; then delta=$((at - first)); else delta=$((at - last)); fi
        if [ "$first" = "$last" ]; then new="$((first + delta))"; else new="$((first + delta))-$((last + delta))"; fi
        printf 'LINEREF_MOVED %s:%s %s -> %s:%s (%s on line %s)\n' "$rel_doc" "$ln" "$ref" "$path" "$new" "$id" "$at"
        moved=$((moved + 1)) ;;
      *)
        elsewhere=0
        while IFS=$'\t' read -r oln oref _; do
          [ "$oln" = "$ln" ] || continue
          otarget="$(resolve "${oref%:*}")"
          [ -n "$otarget" ] && [ "$otarget" != "$target" ] || continue
          [ "$(printf '%s\n' "$otarget" | wc -l | tr -d ' ')" -eq 1 ] || continue
          case "$(scan_ids "$root/$otarget" 1 0 "$ids")" in NONE) ;; *) elsewhere=1; break ;; esac
        done <"$tmp/refs"
        [ "$elsewhere" -ne 0 ] || [ "$unsure" != "1" ] || elsewhere=2
        if [ "$elsewhere" -ne 0 ]; then
          if [ "$elsewhere" -eq 1 ]; then note="identifiers from the line are in another file"; else note="the line has an alias or talks about removal"; fi
          printf 'LINEREF_CHANGED %s:%s %s (%s; %s)\n' "$rel_doc" "$ln" "$ref" "$why" "$note"
          changed=$((changed + 1))
        else
          printf 'LINEREF_GONE %s:%s %s (not in the file: %s)\n' "$rel_doc" "$ln" "$ref" "$ids"
          gone=$((gone + 1))
        fi ;;
    esac
  done <"$tmp/refs"
done <"$tmp/docs"

printf 'CHECKED %d LINEREF_CHANGED %d LINEREF_RANGE %d LINEREF_NOFILE %d LINEREF_OK %d LINEREF_MOVED %d LINEREF_GONE %d\n' \
  "$checked" "$changed" "$range" "$nofile" "$ok" "$moved" "$gone"
if [ "$strict" -eq 1 ]; then
  [ $((range + nofile + gone)) -eq 0 ]
else
  [ $((changed + moved + gone + range + nofile)) -eq 0 ]
fi

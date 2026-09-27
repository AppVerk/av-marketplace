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
#                    shifted to the hit. Only lines with the most identifiers from the docs
#                    line count. When several lines qualify, it gives every candidate range,
#                    nearest first, joined with "|" (at most 5) and the note starts with
#                    "ambiguous:", e.g. `-> a.php:159-162|162-165 (ambiguous: create on lines
#                    159, 165)`; pick the right one by hand
#   LINEREF_GONE     no identifier is in the file or in another file
#                    from the same docs line
#   LINEREF_CHANGED  the file changed and the content cannot be checked: the line
#                    has no identifiers, they are in another file from the line, the line
#                    has a reference without an extension (alias, e.g. `UserVM:12`) or
#                    talks about removal, in Polish or English (then a missing identifier is not GONE)
#   LINEREF_RANGE    the line number is beyond the file length
#   LINEREF_NOFILE   the file does not exist (also run check_refs.sh)
#   LINEREF_SECRET   the file is an env or key file (docs_secret_path in docs_lib.sh): its content is
#                    never read, not even its length; the reference is not checked
#   EXTERNAL         the file is not in git and git ignores its path (installed
#                    dependencies, build output): its content is not checked
# Paths are resolved relative to root, and if missing, by suffix in `git ls-files`.
# Skips documents excluded by --exclude GLOB (repeatable) or by the overlay section
# "## Excluded docs paths" (Polish alias "## Wykluczone sciezki docs", with or without
# diacritics) in <paths.overlays>/av-docs-sync.md, lines "- `glob`". Glob syntax like
# git pathspec :(glob), relative to --root: "*" and "?" do not cross "/", "**" does;
# a glob without "*" or "?" also excludes everything under it (e.g. `.ai/external_services/`).
# The summary line ends with EXCLUDED <documents> EXTERNAL <n> KNOWN <n> SECRET <n>.
# Known false paths: the overlay section "## Known false paths" (Polish alias "## Znane
# falszywe sciezki", with or without diacritics), lines "- `entry`": `<doc>.md:<line>`
# (every reference on that docs line) or `<path or glob>` (that referenced path as written,
# a ":<line>" suffix is dropped). A matched NOFILE or EXTERNAL reference is counted as KNOWN.
# KNOWN_STALE <entry> (a hint): a path entry that now exists in the repo.
#
# Usage:
#   check_linerefs.sh <file.md|dir> [...] [--root DIR] [--exclude GLOB]... [--strict]
# Exit code: 0 no hits, 1 hits found (CHANGED, MOVED, GONE, RANGE,
#   NOFILE), 2 usage error. With --strict code 1 only for RANGE, NOFILE or GONE.
#   EXTERNAL and KNOWN do not change the code.
# Requires: bash 3.2+, git, awk.

set -uo pipefail

root="."
strict=0
paths=""
excludes=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --strict) strict=1 ;;
    --exclude) [ -n "${2:-}" ] || { echo "USAGE --exclude needs a glob"; exit 2; }; excludes="$excludes$2"$'\n'; shift ;;
    -h|--help) sed -n '2,49p' "$0"; exit 0 ;;
    *) paths="$paths$1"$'\n' ;;
  esac
  shift
done
[ -n "$paths" ] || { echo "USAGE check_linerefs.sh <file.md|dir> [...] [--root DIR] [--exclude GLOB] [--strict]"; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE root directory not found"; exit 2; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "USAGE root is not a git repo"; exit 2; }

# shellcheck source=docs_lib.sh
. "$(cd "$(dirname "$0")" && pwd)/docs_lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
docs_exclude_globs "$root" "$excludes" >"$tmp/excludes"
docs_known_paths "$root" >"$tmp/known"
: >"$tmp/known_used"

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
done | sort -u | docs_exclude "$root" "$tmp/excludes" "$tmp/excluded" >"$tmp/docs"
excluded="$(cat "$tmp/excluded" 2>/dev/null)"

checked=0
ok=0
changed=0
moved=0
gone=0
range=0
nofile=0
external=0
known=0
secret=0

known_hit() {
  local entry
  [ -s "$tmp/known" ] || return 1
  entry="$(docs_known_match "$tmp/known" "$@")" || return 1
  printf '%s\n' "$entry" >>"$tmp/known_used"
  known=$((known + 1))
}

# ignored <path> <doc directory>: git ignores the path (relative to root or to the document)
ignored() {
  git -C "$root" check-ignore -q -- "$1" 2>/dev/null && return 0
  case "$1" in ../*|*/../*) return 1 ;; esac
  [ "$2" != "." ] && git -C "$root" check-ignore -q -- "$2/$1" 2>/dev/null
}

resolve() {
  local ref="$1"
  if grep -qxF -- "$ref" "$tmp/files"; then printf '%s\n' "$ref"; return; fi
  grep -E "(^|/)$(printf '%s' "$ref" | sed 's/[].[\*^$+?(){}|]/\\&/g')$" "$tmp/files" | head -2
}

# MARK: range content
# scan_ids <file> <from> <to> <identifiers>
# Prints OK, NONE or one line MOVED<TAB>line<TAB>identifier per candidate: the lines outside
# the range with the most distinct identifiers, nearest first (ties: the earlier line).
scan_ids() {
  awk -v a="$2" -v b="$3" -v ids="$4" '
    BEGIN { n = split(ids, id, " ") }
    found { next }
    {
      c = 0; fid = ""
      for (i = 1; i <= n; i++) {
        if (index($0, id[i]) == 0) continue
        if (FNR >= a && FNR <= b) { found = 1; next }
        c++; if (fid == "") fid = id[i]
      }
      if (c > 0) { nh++; hl[nh] = FNR; hc[nh] = c; hid[nh] = fid; if (c > maxc) maxc = c }
    }
    END {
      if (found) { print "OK"; exit }
      if (!nh) { print "NONE"; exit }
      for (i = 1; i <= nh; i++) if (hc[i] == maxc) {
        m++; L[m] = hl[i]; I[m] = hid[i]; D[m] = (hl[i] < a) ? a - hl[i] : hl[i] - b
      }
      for (i = 2; i <= m; i++) {
        l = L[i]; t = I[i]; d = D[i]
        for (j = i - 1; j >= 1 && (D[j] > d || (D[j] == d && L[j] > l)); j--) { L[j + 1] = L[j]; I[j + 1] = I[j]; D[j + 1] = D[j] }
        L[j + 1] = l; I[j + 1] = t; D[j + 1] = d
      }
      for (i = 1; i <= m; i++) printf "MOVED\t%d\t%s\n", L[i], I[i]
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
      known_hit "$rel_doc:$ln" "$path" && continue
      if ignored "$path" "$(dirname "$rel_doc")"; then
        printf 'EXTERNAL %s:%s %s\n' "$rel_doc" "$ln" "$ref"
        external=$((external + 1))
        continue
      fi
      printf 'LINEREF_NOFILE %s:%s %s\n' "$rel_doc" "$ln" "$ref"
      nofile=$((nofile + 1))
      continue
    fi
    case "$target" in *$'\n'*) continue ;; esac
    if docs_secret_path "$target"; then
      printf 'LINEREF_SECRET %s:%s %s (env or key file, content not read)\n' "$rel_doc" "$ln" "$ref"
      secret=$((secret + 1))
      continue
    fi
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
        # one candidate: "-> path:new (id on line N)"; several: every candidate range, nearest
        # first, joined with "|" (at most 5, the note gives the rest), marked "ambiguous"
        cands=""; lines_at=""; ids_at=""; ncand=0; same=1; id1=""
        while IFS=$'\t' read -r _ at id; do
          ncand=$((ncand + 1))
          [ -n "$id1" ] || id1="$id"
          [ "$id" = "$id1" ] || same=0
          [ "$ncand" -le 5 ] || continue
          if [ "$at" -lt "$first" ]; then delta=$((at - first)); else delta=$((at - last)); fi
          if [ "$first" = "$last" ]; then new="$((first + delta))"; else new="$((first + delta))-$((last + delta))"; fi
          case "|$cands|" in *"|$new|"*) ;; *) cands="${cands:+$cands|}$new" ;; esac
          lines_at="${lines_at:+$lines_at, }$at"
          ids_at="${ids_at:+$ids_at, }$id on line $at"
        done <<EOF_MOVED
$res
EOF_MOVED
        if [ "$ncand" -eq 1 ]; then
          note="$id1 on line $lines_at"
        else
          if [ "$same" -eq 1 ]; then note="ambiguous: $id1 on lines $lines_at"; else note="ambiguous: $ids_at"; fi
          [ "$ncand" -le 5 ] || note="$note and $((ncand - 5)) more"
        fi
        printf 'LINEREF_MOVED %s:%s %s -> %s:%s (%s)\n' "$rel_doc" "$ln" "$ref" "$path" "$cands" "$note"
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

[ -s "$tmp/known" ] && docs_known_stale "$tmp/known" "$tmp/known_used" "$tmp/docs" "$tmp/files" 0
printf 'CHECKED %d LINEREF_CHANGED %d LINEREF_RANGE %d LINEREF_NOFILE %d LINEREF_OK %d LINEREF_MOVED %d LINEREF_GONE %d EXCLUDED %d EXTERNAL %d KNOWN %d SECRET %d\n' \
  "$checked" "$changed" "$range" "$nofile" "$ok" "$moved" "$gone" "${excluded:-0}" "$external" "$known" "$secret"
if [ "$strict" -eq 1 ]; then
  [ $((range + nofile + gone)) -eq 0 ]
else
  [ $((changed + moved + gone + range + nofile)) -eq 0 ]
fi

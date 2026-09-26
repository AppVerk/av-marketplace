#!/usr/bin/env bash
# check_refs.sh - checks that paths named in the docs exist in the repo.
#
# Extracts [text](path) links and backtick fragments that look like a path
# (file extension or trailing "/") from markdown files.
# A path exists when it exists relative to the repo root, relative to the document
# directory, or as a suffix of a repo path (docs often write paths from the source directory).
#
# Output:
#   MISSING     path with a directory, or a link, that does not exist (certain drift),
#   UNRESOLVED  bare file name without a directory that was not found (to review),
#   EXTERNAL    path outside the repo (../other-repo/...) or on a line about another repo;
#               one that exists next to root is not reported,
#   WORKSPACE   reference to a working file (--workspace, default .ai/workspace);
#               docs should not link plans and reports.
# A backtick token looks like a path when it has a known extension, ends with "/"
# or names a dotfile after a directory (config/.toolrc).
# Skips placeholders (YYYY, <x>, [x], {x}, $VAR, ${VAR}, Foo), package names from manifests,
# scripts shipped with the av-* skills (bare name or a path under the skills directory),
# paths ignored by git and lines that themselves say the file is missing
# (negation words in Polish and English).
# The repo index includes *.xcresult bundles without their contents (hundreds of thousands of files).
#
# Usage:
#   check_refs.sh <file.md|dir> [...] [--root DIR] [--workspace DIR] [--strict]
# Exit code: 0 no MISSING, 1 MISSING found, 2 usage error. UNRESOLVED, EXTERNAL
#   and WORKSPACE do not change the code. --strict (for gates) makes the same contract
#   explicit: code 1 only with MISSING.
# Requires: bash 3.2+, git, awk, find; jq optional (package names).

set -uo pipefail

root="."
workspace=".ai/workspace"
paths=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --workspace) workspace="${2:-}"; shift ;;
    --strict) ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) paths="$paths$1"$'\n' ;;
  esac
  shift
done
[ -n "$paths" ] || { echo "USAGE check_refs.sh <file.md|dir> [...] [--root DIR]"; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE root directory not found"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# MARK: repo path index

find "$root" \( -name .git -o -name node_modules -o -name vendor -o -name Pods -o -name DerivedData \
  -o -name build -o -name dist -o -name .angular -o -name coverage -o -name __pycache__ -o -name .venv \) -prune \
  -o -name '*.xcresult' -prune -print -o -print 2>/dev/null | sed "s|^$root/||" | grep -v "^$root\$" >"$tmp/index"

# MARK: scripts of the av-* skills (sibling skill directories), with every path suffix

skills_dir="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
: >"$tmp/avscripts"
[ -n "$skills_dir" ] && find "$skills_dir" -mindepth 3 -maxdepth 3 -path '*/scripts/*' -name '*.sh' 2>/dev/null |
  sed "s|^$skills_dir/||" | awk -F/ '{ s = ""; for (i = NF; i >= 1; i--) { s = (s == "" ? $i : $i "/" s); print s } }' >"$tmp/avscripts"

# MARK: package names

: >"$tmp/packages"
if command -v jq >/dev/null 2>&1; then
  for manifest in "$root/package.json" "$root"/*/package.json; do
    [ -f "$manifest" ] && jq -r '(.dependencies // {}), (.devDependencies // {}), (.peerDependencies // {}) | keys[]' "$manifest" 2>/dev/null >>"$tmp/packages"
  done
  [ -f "$root/composer.json" ] && jq -r '(.require // {}), (."require-dev" // {}) | keys[]' "$root/composer.json" 2>/dev/null >>"$tmp/packages"
fi

# MARK: document list (relative to root)

: >"$tmp/docs"
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
    case "$abs" in *.md) printf '%s\n' "$abs" ;; esac
  else
    printf 'WARNING file or directory not found: %s\n' "$p" >&2
  fi
done | while IFS= read -r f; do
  d="$(cd "$(dirname "$f")" && pwd)"
  printf '%s\n' "${d#$root/}/$(basename "$f")" | sed "s|^$root/||; s|^\\./||"
done | sed "s|^$root\$||" | sort -u >"$tmp/docs"

# MARK: extraction and check

if [ ! -s "$tmp/docs" ]; then
  echo "CHECKED 0 MISSING 0 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0"
  exit 0
fi

(
  cd "$root" || exit 2
  IFS=$'\n'
  set -f
  # shellcheck disable=SC2046
  awk -v index_file="$tmp/index" -v pkg_file="$tmp/packages" -v ws="${workspace%/}" '
    function normalize(p,    n, parts, out, i, k) {
      n = split(p, parts, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == ".") continue
        if (parts[i] == "..") { if (k > 0) k--; continue }
        out[++k] = parts[i]
      }
      p = ""
      for (i = 1; i <= k; i++) p = (p == "" ? out[i] : p "/" out[i])
      return p
    }
    function strip(t) {
      sub(/#.*$/, "", t)
      sub(/:[0-9]+(-[0-9]+)?$/, "", t)
      while (t ~ /[\/:.]$/) t = substr(t, 1, length(t) - 1)
      while (substr(t, 1, 2) == "./") t = substr(t, 3)
      while (t ~ /^(\.\.\.|…)\//) sub(/^[^\/]*\//, "", t)
      return t
    }
    function placeholder(t) {
      return (t ~ /YYYY|MM-DD|\[[^]]*\]|\{[^}]*\}|<[^>]*>|[$][A-Za-z_{]|RUN_ID/ || t ~ /\.\.\.([^\/]|$)/ ||
              t ~ /(^|[^A-Za-z])(foo|xxx)([^A-Za-z]|$)/ || t ~ /(^|[^A-Za-z])Foo([A-Z_.\/-]|$)/)
    }
    function looks_like_path(t,    s) {
      if (t ~ /[ \t]/ || t ~ /^[-$<{@~\/]/ || index(t, "://") > 0) return 0
      if (t ~ /[(){}=;,|"<>]/ || index(t, "\047") > 0) return 0
      if (t ~ /^\./ && index(t, "/") == 0) return 0
      if (t ~ /^(feature|bugfix|hotfix|release|task|origin|refs)\//) return 0
      if (placeholder(t)) return 0
      s = t; sub(/:[0-9]+(-[0-9]+)?$/, "", s)
      if (s !~ /\.(swift|php|ts|js|mjs|json|md|yml|yaml|xml|twig|html|scss|css|py|rb|sh|plist|strings|xib|storyboard|xcconfig|toml|lock|kt|java|go)$/ && s !~ /\/$/ &&
          s !~ /\/\.[A-Za-z0-9][A-Za-z0-9_.-]*$/) return 0
      if (s ~ /^[A-Z0-9_]+\/[A-Z0-9_]+$/) return 0
      return 1
    }
    function glob_re(g,    r) {
      r = g
      gsub(/\./, "\\.", r); gsub(/\*\*\//, "@@", r); gsub(/\*/, ".*", r); gsub(/\?/, ".", r); gsub(/@@/, "(.*/)?", r)
      return "(^|/)" r "$"
    }
    function exists(tok, docdir,    t, re, p) {
      t = strip(tok)
      if (t == "") return 1
      if (t ~ /[*?[]/) {
        re = glob_re(t)
        for (p in full) if (p ~ re) return 1
        return 0
      }
      if (t in full) return 1
      if (normalize(docdir "/" t) in full) return 1
      return (t in suffix)
    }
    function report(tok, kind,    ign, rel2, cls) {
      checked++
      if (exists(tok, docdir)) return
      ign = tok; sub(/#.*$/, "", ign); sub(/:[0-9]+(-[0-9]+)?$/, "", ign); while (substr(ign, 1, 2) == "./") ign = substr(ign, 3)
      rel2 = normalize(docdir "/" strip(tok))
      cls = kind
      if (substr(strip(tok), 1, 3) == "../" && escapes(docdir, strip(tok))) cls = "external"
      else if (tolower(line) ~ other_repo) cls = "external"
      printf "%s:%d\t%s\t%s\t%s\t%s\t%s\n", FILENAME, FNR, tok, cls, strip(tok), ign, rel2
    }
    function escapes(dir, t,    n, parts, i, depth) {
      depth = (dir == "" ? 0 : split(dir, parts, "/"))
      n = split(t, parts, "/")
      for (i = 1; i <= n; i++) {
        if (parts[i] == "..") { depth--; if (depth < 0) return 1 }
        else if (parts[i] != "." && parts[i] != "") depth++
      }
      return 0
    }
    BEGIN {
      while ((getline line < index_file) > 0) {
        full[line] = 1
        n = split(line, parts, "/"); s = ""
        for (i = n; i >= 1; i--) { s = (s == "" ? parts[i] : parts[i] "/" s); suffix[s] = 1 }
      }
      while ((getline line < pkg_file) > 0) pkg[line] = 1
      # neg and other_repo match docs in Polish and English: repos keep their own language.
      neg = "(^|[^A-Za-z])(brak|nie istnieje|nie ma|nigdy|never|usuni(e|ę)t[a-z]*|usun(a|ą)(c|ć)|relokow[a-z]*|przeniesion[a-z]*|dawn(y|a|e|iej)|nie w|not in|removed|deleted|moved|formerly|previously|no longer|does not exist|missing)([^A-Za-z]|$)"
      other_repo = "(repozytori|repository|w repo |in repo |sibling)"
    }
    FNR == 1 { in_code = 0; docdir = FILENAME; sub(/\/?[^\/]*$/, "", docdir) }
    /^[ \t]*```/ { in_code = !in_code; next }
    in_code { next }
    {
      line = $0
      if (tolower(line) ~ neg) {
        rest = line
        while (match(rest, /(\]\(|`)[^)` \t]+/)) {
          tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
          sub(/^(\]\(|`)/, "", tok)
          if (index(tok, ws "/") == 1) { checked++; printf "%s:%d\t%s\t%s\t%s\t%s\t%s\n", FILENAME, FNR, tok, "tick", tok, tok, tok }
        }
        next
      }
      rest = line
      while (match(rest, /\]\([^) \t]+\)/)) {
        tok = substr(rest, RSTART + 2, RLENGTH - 3); rest = substr(rest, RSTART + RLENGTH)
        if (tok ~ /^(https?:|mailto:|tel:|#)/ || placeholder(tok)) continue
        report(tok, "link")
      }
      rest = line
      while (match(rest, /`[^`]+`/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
        gsub(/^[ \t]+|[ \t]+$/, "", tok)
        if (length(tok) < 2 || length(tok) > 200 || !looks_like_path(tok) || (tok in pkg)) continue
        if (tok ~ /^[^\/]+\/$/ && !(substr(tok, 1, length(tok) - 1) in full)) continue
        report(tok, "tick")
      }
    }
    END { printf "#CHECKED\t%d\n", checked }
  ' $(cat "$tmp/docs")
) >"$tmp/candidates"

checked="$(awk -F'\t' '$1 == "#CHECKED" { print $2 }' "$tmp/candidates")"
missing=0
unresolved=0
external=0
in_workspace=0
ws="${workspace%/}"
while IFS=$'\t' read -r where tok kind stripped ign rel2; do
  [ "$where" = "#CHECKED" ] && continue
  [ -n "$where" ] || continue
  case "$stripped/" in
    "$ws"/*)
      if printf '%s' "$stripped" | grep -qE '\.[A-Za-z0-9]+$'; then
        in_workspace=$((in_workspace + 1)); printf 'WORKSPACE %s %s\n' "$where" "$tok"
      fi
      continue ;;
  esac
  if [ "${stripped#*/}" != "$stripped" ]; then
    case "$rel2/" in
      "$ws"/*)
        if printf '%s' "$stripped" | grep -qE '\.[A-Za-z0-9]+$'; then
          in_workspace=$((in_workspace + 1)); printf 'WORKSPACE %s %s\n' "$where" "$tok"
        fi
        continue ;;
    esac
  fi
  grep -qxF -- "$stripped" "$tmp/avscripts" && continue
  if [ "${stripped#*/}" = "$stripped" ] && [ -f "$root/.gitignore" ] &&
     grep -vE '^[[:space:]]*(#|!)' "$root/.gitignore" | grep -qE "(^|/)$(printf '%s' "$stripped" | sed 's/[.[\*^$]/\\&/g')/?$"; then
    continue
  fi
  if git -C "$root" check-ignore -q --no-index -- "$ign" 2>/dev/null ||
     { [ -n "$rel2" ] && git -C "$root" check-ignore -q --no-index -- "$rel2" 2>/dev/null; }; then
    continue
  fi
  if [ "$kind" != "external" ] && [ "${stripped#../}" != "$stripped" ] && [ "${rel2#*/}" != "$rel2" ]; then
    [ -e "$root/${rel2%%/*}" ] || kind="external"
  fi
  if [ "$kind" = "external" ]; then
    sib="${stripped#../}"
    while [ "${sib#../}" != "$sib" ]; do sib="${sib#../}"; done
    [ -e "$(dirname "$root")/$sib" ] && continue
    [ -e "$(dirname "$root")/$rel2" ] && continue
    external=$((external + 1))
    printf 'EXTERNAL %s %s\n' "$where" "$tok"
    continue
  fi
  bare="$(printf '%s' "$stripped" | grep -c /)"
  if [ "$kind" = "tick" ] && [ "$bare" -eq 0 ]; then
    unresolved=$((unresolved + 1))
    printf 'UNRESOLVED %s %s\n' "$where" "$tok"
  else
    missing=$((missing + 1))
    printf 'MISSING %s %s\n' "$where" "$tok"
  fi
done <"$tmp/candidates"

printf 'CHECKED %s MISSING %d UNRESOLVED %d EXTERNAL %d WORKSPACE %d\n' "${checked:-0}" "$missing" "$unresolved" "$external" "$in_workspace"
[ "$missing" -eq 0 ]

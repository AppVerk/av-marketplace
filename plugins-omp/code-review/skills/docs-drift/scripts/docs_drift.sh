#!/usr/bin/env bash
# docs_drift.sh - finds documentation references that broke since a base revision.
#
# Usage:
#   docs_drift.sh --base REV [--root DIR] [--max N]
#   docs_drift.sh -h|--help
# Head is the working tree, including uncommitted and untracked docs but excluding
# gitignored docs. Base is a temporary shared clone with full history and the same
# repository directory name.
# Runs check_refs.sh, check_names.sh and check_linerefs.sh on docs/, doc/,
# documentation/ and root *.md files, excluding docs/plans, docs/reviews,
# docs/testing, docs/superpowers and CHANGELOG.md. Never modifies the repository.
#
# Output:
#   DOCS_DRIFT base=<sha12> head_hits=<n> base_hits=<n> new=<n>
#   NEW <checker hit>                  at most --max lines (default 200)
#   TRUNCATED shown=<max> total=<n>    when more new hits exist
#   DOCS_DRIFT_ERROR <reason>          a usage, checkout or checker error
# A key is kind, doc path and target, ignoring the doc line number and any moved
# line candidates or notes. Renamed docs map base keys to their new paths. When a
# key occurs more often at head, every head occurrence is emitted in checker order.
# Exit code: 0 success (including new hits), 2 error; interrupts exit 130.
# Requires: bash 3.2+, git, awk, find; jq optional, iconv for UTF-16 string files.

set -uo pipefail

error() { printf 'DOCS_DRIFT_ERROR %s\n' "$1"; exit 2; }

base=""
root=""
max=200
while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      [ -n "${2:-}" ] || error '--base needs a revision'
      base="$2"; shift ;;
    --root)
      [ -n "${2:-}" ] || error "not a git repository: ${2:-}"
      root="$2"; shift ;;
    --max)
      [ -n "${2:-}" ] || error '--max needs a positive integer'
      max="$2"; shift ;;
    -h|--help)
      awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$0"
      exit 0 ;;
    *) error "unknown option $1" ;;
  esac
  shift
done
[ -n "$base" ] || error '--base needs a revision'
[[ "$max" =~ ^[1-9][0-9]*$ ]] || error '--max needs a positive integer'

if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || error "not a git repository: $PWD"
fi
root_arg="$root"
root="$(cd "$root" 2>/dev/null && pwd -P)" || error "not a git repository: $root_arg"
[ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] || error "not a git repository: $root_arg"
base_sha="$(git -C "$root" rev-parse --verify --quiet "$base^{commit}")"
[ -n "$base_sha" ] || error "base $base is not a commit"

here="$(cd "$(dirname "$0")" && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM
base_dir="$tmp/base/$(basename "$root")"
if ! GIT_LFS_SKIP_SMUDGE=1 git clone --quiet --shared --no-checkout "$root" "$base_dir" 2>"$tmp/checkout.err" ||
   ! GIT_LFS_SKIP_SMUDGE=1 git -C "$base_dir" -c core.hooksPath=/dev/null checkout --quiet --detach "$base_sha" 2>"$tmp/checkout.err"; then
  error "cannot check out base ${base_sha:0:12}: $(awk 'NR == 1 { print; exit }' "$tmp/checkout.err")"
fi

# Run from each tree, using only the installed checkers, not a project's copy.
collect_hits() (
  tree="$1"
  label="$2"
  cd "$tree" || error "not a git repository: $tree"
  inputs=()
  count=0
  for doc in docs doc documentation; do
    if [ -d "$doc" ]; then
      inputs+=("$doc")
      count=$((count+1))
    fi
  done
  while IFS= read -r doc; do
    git -C "$tree" check-ignore -q -- "${doc#./}" && continue
    inputs+=("${doc#./}")
    count=$((count+1))
  done < <(find . -maxdepth 1 -type f -name '*.md' -print | LC_ALL=C sort)
  : >"$tmp/$label.hits"
  [ "$count" -gt 0 ] || return 0
  excludes=(--exclude docs/plans --exclude docs/reviews --exclude docs/testing
    --exclude docs/superpowers --exclude CHANGELOG.md)
  while IFS= read -r -d '' doc; do
    excludes+=(--exclude "${doc%/}")
  done < <(git -C "$tree" ls-files -z --others --ignored --exclude-standard --directory -- docs doc documentation)
  for checker in check_refs.sh check_names.sh check_linerefs.sh; do
    bash "$here/$checker" "${inputs[@]}" --root . "${excludes[@]}" >"$tmp/checker.out" 2>"$tmp/checker.err"
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
      error "$checker failed on $label: $(awk 'NR == 1 { print; exit }' "$tmp/checker.out")"
    fi
    awk '$1 ~ /^(MISSING|UNRESOLVED|NAME_MISSING|LINEREF_CHANGED|LINEREF_MOVED|LINEREF_GONE|LINEREF_RANGE|LINEREF_NOFILE)$/ { print }' \
      "$tmp/checker.out" >>"$tmp/$label.hits"
  done
)
collect_hits "$root" head || exit 2
collect_hits "$base_dir" base || exit 2

# Git's NUL-delimited names avoid C-quoting, including for non-ASCII renames.
: >"$tmp/renames"
while IFS= read -r -d '' status; do
  IFS= read -r -d '' old || break
  case "$status" in
    R*|C*)
      IFS= read -r -d '' new || break
      case "$old$new" in *$'\t'*|*$'\n'*) continue ;; esac
      case "$status" in R*) printf '%s\t%s\n' "$old" "$new" >>"$tmp/renames" ;; esac ;;
  esac
done < <(git -C "$root" diff -z --name-status -M "$base_sha" -- '*.md')

# Count keys before emitting, so an increased multiplicity retains every head hit.
# FILENAME tests also work when a mapping file or a tree's hit file is empty.
awk -F '\t' -v sha="${base_sha:0:12}" -v max="$max" '
  function key(line, is_base, kind, rest, doc, target) {
    match(line, /^[^ ]+/)
    kind = substr(line, 1, RLENGTH)
    rest = substr(line, RLENGTH + 2)
    if (!match(rest, /:[0-9]+ /)) return ""
    doc = substr(rest, 1, RSTART - 1)
    target = substr(rest, RSTART + RLENGTH)
    if (kind ~ /^LINEREF_/) {
      sub(/ -> .*/, "", target)
      sub(/ \(.*\)$/, "", target)
    }
    if (is_base && doc in renamed) doc = renamed[doc]
    return kind "\t" doc "\t" target
  }
  FILENAME == ARGV[1] { renamed[$1] = $2; next }
  FILENAME == ARGV[2] {
    k = key($0, 1)
    if (k != "") { base_count[k]++; base_hits++ }
    next
  }
  FILENAME == ARGV[3] {
    k = key($0, 0)
    if (k != "") {
      head_count[k]++
      head_hits++
      lines[head_hits] = $0
      keys[head_hits] = k
    }
  }
  END {
    for (i = 1; i <= head_hits; i++)
      if (head_count[keys[i]] > base_count[keys[i]]) n_new++
    printf "DOCS_DRIFT base=%s head_hits=%d base_hits=%d new=%d\n", sha, head_hits, base_hits, n_new
    for (i = 1; i <= head_hits; i++) {
      if (head_count[keys[i]] > base_count[keys[i]] && shown < max) {
        print "NEW " lines[i]
        shown++
      }
    }
    if (n_new > max) printf "TRUNCATED shown=%s total=%d\n", max, n_new
  }
' "$tmp/renames" "$tmp/base.hits" "$tmp/head.hits"

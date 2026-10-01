#!/bin/bash
# run_scope.sh - snapshot of the working tree before an av-implement run, and the changes of
# the run measured against it. Edits that existed before the start (another person's work in
# progress) stay out of the run's diff even inside a file the run touched too.
#
# Usage:
#   run_scope.sh [--root DIR] [--config FILE] [--runs-dir DIR] snapshot --run-id ID [--force]
#   run_scope.sh [--root DIR] [--config FILE] [--runs-dir DIR] diff     --run-id ID [--name-only]
#   run_scope.sh [--root DIR] [--config FILE] [--runs-dir DIR] foreign  --run-id ID [--name-only]
#
# snapshot: writes <runs>/<ID>/baseline.tree (a git tree of the working tree: tracked files as
#   they are, untracked files that are not ignored, without the workspace), baseline.head and
#   baseline.patch (the diff from HEAD to that tree, for a human). Prints
#   "SNAPSHOT <tree> head=<sha> foreign=<n files>". A second snapshot of the same run needs
#   --force; an av-implement run takes one snapshot, before the implementation.
# diff: the changes of the run, from the snapshot tree to the working tree now. A patch, or
#   with --name-only one path per line. Empty output means the run changed nothing.
# foreign: the changes that existed before the run, from the recorded HEAD to the snapshot
#   tree. Their origin in a review is PRE_EXISTING.
# Exit codes: 0 ok, 2 bad arguments, a git error or a missing snapshot, 3 a snapshot exists
#   and --force is missing.
# The snapshot lives in the repository's object store as an unreferenced tree; git keeps such
# objects for two weeks by default, which covers a run. Requires bash 3.2+, git, jq.

set -uo pipefail

usage_error() { printf 'ERROR %s\n' "$1"; exit 2; }

root_arg=""; cfg_arg=""; runs_arg=""; mode=""; run_id=""; force=0; name_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage_error "--root needs a directory"; root_arg="$2"; shift ;;
    --config) [ $# -ge 2 ] || usage_error "--config needs a file"; cfg_arg="$2"; shift ;;
    --runs-dir) [ $# -ge 2 ] || usage_error "--runs-dir needs a directory"; runs_arg="$2"; shift ;;
    --run-id) [ $# -ge 2 ] || usage_error "--run-id needs a value"; run_id="$2"; shift ;;
    --force) force=1 ;;
    --name-only) name_only=1 ;;
    snapshot|diff|foreign) [ -z "$mode" ] || usage_error "one of snapshot, diff or foreign"; mode="$1" ;;
    *) usage_error "unknown argument $1" ;;
  esac
  shift
done
[ -n "$mode" ] || usage_error "pass snapshot, diff or foreign"
[ -n "$run_id" ] || usage_error "--run-id is required"
case "$run_id" in
  .|..|*/*|"") usage_error "--run-id must use only letters, digits, _ . - and not be . or .." ;;
esac
printf '%s' "$run_id" | grep -Eq '^[A-Za-z0-9._-]+$' || usage_error "--run-id must use only letters, digits, _ . - and not be . or .."

command -v git >/dev/null 2>&1 || usage_error "git missing"
command -v jq >/dev/null 2>&1 || usage_error "jq missing"

if [ -n "$root_arg" ]; then
  root="$(git -C "$root_arg" rev-parse --show-toplevel 2>/dev/null)" || usage_error "$root_arg is not inside a git repository"
else
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || usage_error "not inside a git repository"
fi
cd "$root" || usage_error "cannot enter $root"

cfg="${cfg_arg:-$root/.ai/av.config.json}"
workspace=".ai/workspace"
runs_base="$workspace/runs"
if [ -f "$cfg" ]; then
  workspace="$(jq -r '.paths.workspace // ".ai/workspace"' "$cfg" 2>/dev/null)" || workspace=".ai/workspace"
  runs_base="$(jq -r --arg ws "$workspace" '.paths.runs // ($ws + "/runs")' "$cfg" 2>/dev/null)" || runs_base="$workspace/runs"
fi
[ -n "$runs_arg" ] && runs_base="$runs_arg"
case "$runs_base" in /*) run_dir="$runs_base/$run_id" ;; *) run_dir="$root/$runs_base/$run_id" ;; esac
tree_file="$run_dir/baseline.tree"
head_file="$run_dir/baseline.head"

# tree_of_worktree - writes a tree of the working tree (tracked files as they are, untracked
# files that are not ignored, without the workspace even when it is not ignored) through a
# temporary index; prints its hash
tree_of_worktree() {
  local idx tree
  idx="$(mktemp "${TMPDIR:-/tmp}/av-scope.XXXXXX")" || return 1
  rm -f "$idx"
  GIT_INDEX_FILE="$idx" git read-tree HEAD 2>/dev/null || { rm -f "$idx"; return 1; }
  GIT_INDEX_FILE="$idx" git add -A 2>/dev/null || { rm -f "$idx"; return 1; }
  GIT_INDEX_FILE="$idx" git rm -r -q --cached --ignore-unmatch -- "$workspace" .ai/workspace >/dev/null 2>&1
  tree="$(GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)" || { rm -f "$idx"; return 1; }
  rm -f "$idx"
  printf '%s\n' "$tree"
}

head_sha="$(git rev-parse --verify -q HEAD 2>/dev/null)" || usage_error "HEAD has no commit; commit first"

case "$mode" in
  snapshot)
    if [ -f "$tree_file" ] && [ "$force" -eq 0 ]; then
      printf 'ERROR a snapshot of run %s exists (%s); pass --force to replace it\n' "$run_id" "$(cat "$tree_file")"
      exit 3
    fi
    mkdir -p "$run_dir" || usage_error "cannot create $run_dir"
    tree="$(tree_of_worktree)" || usage_error "git cannot read the working tree"
    printf '%s\n' "$tree" >"$tree_file" && printf '%s\n' "$head_sha" >"$head_file" || usage_error "cannot write $run_dir"
    git diff-tree -p --binary -r "$head_sha" "$tree" >"$run_dir/baseline.patch" 2>/dev/null || usage_error "git cannot diff HEAD and the snapshot"
    n="$(git diff-tree -r --name-only "$head_sha" "$tree" 2>/dev/null | grep -c . || true)"
    printf 'SNAPSHOT %s head=%s foreign=%s\n' "$tree" "$head_sha" "$n"
    ;;
  diff|foreign)
    [ -f "$tree_file" ] && [ -f "$head_file" ] || usage_error "no snapshot for run $run_id in ${run_dir#"$root"/}; run snapshot before the implementation"
    base_tree="$(tr -d ' \t\r\n' <"$tree_file")"
    base_head="$(tr -d ' \t\r\n' <"$head_file")"
    git cat-file -e "$base_tree" 2>/dev/null || usage_error "the snapshot tree $base_tree is gone from the object store"
    if [ "$mode" = diff ]; then from="$base_tree"; to="$(tree_of_worktree)" || usage_error "git cannot read the working tree"
    else from="$base_head"; to="$base_tree"; fi
    if [ "$name_only" -eq 1 ]; then
      git diff-tree -r --name-only "$from" "$to"
    else
      git diff-tree -p --binary -r "$from" "$to"
    fi
    ;;
esac

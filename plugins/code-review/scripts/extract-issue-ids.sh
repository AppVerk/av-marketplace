#!/usr/bin/env bash
# extract-issue-ids.sh — consolidated PREFIX-NNN extractor for review files.
#
# Reads a review markdown file and emits, on stdout, one canonical issue ID
# per line (e.g., `SEC-003`, `PERF-002`, `ARCH-001`, `MAINT-014`, `DOC-007`).
#
# The prefix alternation is hardcoded to match the canonical Category→Prefix
# mapping. SSoT: docs/plugins/code-review.md#category-prefix-mapping — update both when adding
# a new category.
#
# Usage:
#   bash plugins/code-review/scripts/extract-issue-ids.sh <review-file>
#
# Exit codes:
#   0 — file scanned, IDs (if any) emitted on stdout.
#   1 — file does not exist or is not readable.
#   2 — usage error (missing argument).
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: extract-issue-ids.sh <review-file>" >&2
  exit 2
fi

target_file="$1"

if [ ! -r "$target_file" ]; then
  echo "ERROR: file not readable: $target_file" >&2
  exit 1
fi

# Two-pass grep: first pull lines matching `### [SEVERITY] PREFIX-NNN:`,
# then extract just the canonical PREFIX-NNN token from each.
# `|| true` keeps the script from exiting under `set -e` when there are no
# matches (grep exits 1 for no-match).
grep -oE '^### \[[A-Z]+\] (SEC|PERF|ARCH|MAINT|DOC)-[0-9]+:' "$target_file" \
  | grep -oE '(SEC|PERF|ARCH|MAINT|DOC)-[0-9]+' \
  || true

#!/usr/bin/env bash
# extract-issue-ids.sh — consolidated PREFIX-NNN extractor for review files.
#
# Reads a review markdown file and emits, on stdout, one canonical issue ID
# per line (e.g., `SEC-003`, `PERF-002`, `ARCH-001`, `MAINT-014`, `DOC-007`).
#
# Scope: only prefixes whose reports live in docs/reviews/ (SEC, PERF, ARCH,
# MAINT, DOC). The QA prefix is intentionally excluded — QA reports live in
# docs/testing/reports/ and are produced by /qa:run, not /analyze-feedback,
# so this script never encounters QA-NNN IDs.
#
# SSoT for review-directory prefixes: docs/plugins/code-review.md#category-prefix-mapping
# — when adding a new prefix that produces reports under docs/reviews/, update
# both the canonical mapping AND this script's regex.
#
# Usage:
#   bash plugins/code-review/scripts/extract-issue-ids.sh <review-file>
#
# Exit codes:
#   0 — file scanned, IDs (if any) emitted on stdout.
#   1 — file does not exist or is not readable.
#   2 — usage error (missing argument).
set -eu

# Single source of truth for review-directory prefixes within this script.
# When adding a new prefix that produces reports under docs/reviews/, update
# this regex AND the canonical mapping in docs/plugins/code-review.md.
PREFIX_RE='(SEC|PERF|ARCH|MAINT|DOC)'

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
grep -oE "^### \[[A-Z]+\] ${PREFIX_RE}-[0-9]+:" "$target_file" \
  | grep -oE "${PREFIX_RE}-[0-9]+" \
  || true

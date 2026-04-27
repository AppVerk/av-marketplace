#!/usr/bin/env bash
# slugify-branch.sh — canonical branch-name slugifier for the code-review plugin.
#
# Used by both /review and /analyze-feedback to derive a deterministic, safe
# filename slug from a git branch name.
#
# Contract: emits a slug matching ^[a-z0-9][a-z0-9-]{0,58}[a-z0-9]$ (or a
# single [a-z0-9] if length 1) on stdout, or aborts with a non-zero exit and
# a diagnostic on stderr if the input slugifies to empty or to a string that
# would still begin with `-` after sanitization.
#
# Usage:
#   slug="$(bash plugins/code-review/scripts/slugify-branch.sh "$branch_name")"
#
# Threat model — see plugins/code-review/commands/analyze-feedback.md
# (Step 5.5.1 "Slug contract") for the full rationale. Briefly:
#   - Strips control chars (\t, \r, \n) so embedded newlines cannot smuggle
#     markdown into a downstream report.
#   - Strips bidi overrides (U+202A-U+202E, U+2066-U+2069) — CVE-2021-42574
#     class. LC_ALL=C forces tr into byte-wise mode where every byte 0x80-0xFF
#     is non-alnum and gets stripped.
#   - Strips zero-width joiners and shell metachars (`, $(), !).
#   - Caps length at 60 chars to stay well under filesystem NAME_MAX.
#   - Refuses leading-dash output so downstream tooling cannot mistake the
#     slug for a CLI flag (e.g., `rm $f`).
#
# Exit codes:
#   0 — slug emitted on stdout.
#   1 — slug empty after sanitization, or starts with `-` (defense-in-depth).
#   2 — usage error (missing argument).
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: slugify-branch.sh <branch-name>" >&2
  exit 2
fi

branch_name="$1"

# Step A: lowercase + replace `/` and spaces with `-` (canonical transform).
slug=$(printf '%s' "$branch_name" | sed 's|/|-|g; s| |-|g' | tr '[:upper:]' '[:lower:]')

# Step B: whitelist pass — strip everything that isn't [a-zA-Z0-9-]. This
# removes control characters, bidi overrides, zero-width joiners, backticks,
# $(), !, and any other shell/markdown metachar. LC_ALL=C is load-bearing:
# under a UTF-8 locale, BSD/GNU tr treat [:alnum:] as a Unicode class and let
# multi-byte sequences (e.g., bidi overrides) pass. LC_ALL=C forces tr into
# byte-wise mode where every byte 0x80-0xFF is non-alnum and gets stripped.
slug=$(printf '%s' "$slug" | LC_ALL=C tr -cd '[:alnum:]-' | sed 's/-\{2,\}/-/g; s/^-*//; s/-*$//' | cut -c1-60)

if [ -z "$slug" ]; then
  echo "ERROR: slug empty after sanitization" >&2
  exit 1
fi

# Belt-and-suspenders: the sed above strips leading dashes, but assert it
# explicitly so a future edit to the sed pipeline cannot reintroduce a slug
# beginning with `-` (which downstream `rm $f` / similar would treat as a flag).
case "$slug" in
  -*)
    echo "ERROR: slug begins with '-' after sanitization" >&2
    exit 1
    ;;
esac

printf '%s\n' "$slug"

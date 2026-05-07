#!/usr/bin/env bash
# check-prefix-sync.sh — CI guard for the Category→Prefix SSoT.
#
# The canonical Category→Prefix mapping lives in `docs/plugins/code-review.md`
# under the "Issue ID categories" table (HTML anchor: `category-prefix-mapping`).
# Several downstream consumer files duplicate the prefix list inline (regex
# alternations, case statements, Category enums). When a new prefix is added
# to the canonical table without updating each consumer, the plugin silently
# drifts: `/fix QA-001` may route correctly while `fix-auto`'s Category enum
# omits `Testing`, and the failure mode is invisible until a real issue hits it.
#
# This script greps the prefix list out of every known consumer file and
# diffs it against the canonical set extracted from the SSoT table. It exits
# non-zero on any divergence so CI can block the merge.
#
# Per-consumer scope: each consumer declares which prefixes it is responsible
# for. Some consumers (extract-issue-ids.sh) intentionally cover only a subset
# (the docs/reviews/ prefixes, excluding QA whose reports live in
# docs/testing/reports/). Those exclusions are encoded explicitly below — the
# script enforces "consumer matches its declared scope", not "consumer matches
# the full canonical list".
#
# Usage:
#   bash plugins/code-review/scripts/check-prefix-sync.sh
#
# Exit codes:
#   0 — all consumers in sync with their declared scope of the canonical table.
#   1 — at least one consumer diverges (details printed to stderr).
#   2 — internal error: canonical table missing, malformed, or unreadable.
set -eu

# Resolve repo root from this script's location so the guard works regardless
# of the caller's cwd (e.g., CI runners, pre-commit hooks, manual invocation).
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

canonical_doc="$repo_root/docs/plugins/code-review.md"
fix_cmd="$repo_root/plugins/code-review/commands/fix.md"
fix_auto_agent="$repo_root/plugins/code-review/agents/fix-auto.md"
extract_ids_script="$repo_root/plugins/code-review/scripts/extract-issue-ids.sh"

# ---------------------------------------------------------------------------
# Step 1: Extract canonical prefix set from docs/plugins/code-review.md.
#
# The table sits between the `<a id="category-prefix-mapping"></a>` anchor
# and the next `### ` heading. Each data row has the shape:
#   `| <Category> | <PREFIX> |`
# with `Category` and `Prefix` being the header. We strip the header/separator
# rows, then extract the second column.
# ---------------------------------------------------------------------------

if [ ! -r "$canonical_doc" ]; then
  echo "ERROR: canonical doc not readable: $canonical_doc" >&2
  exit 2
fi

# Use awk to slice out the table region, then collect the second pipe-column.
canonical_prefixes="$(
  awk '
    # Enter the canonical region on the anchor.
    /<a id="category-prefix-mapping"><\/a>/ { in_section = 1; next }
    # Once in the region, the first `### ` heading is the heading the anchor
    # points at (e.g., `### /review`). Do not treat that as the section end.
    # Treat the *second* `### ` heading as the boundary.
    in_section && /^### / {
      heading_count++
      if (heading_count >= 2) { in_section = 0 }
      next
    }
    in_section && /^\|/ { print }
  ' "$canonical_doc" \
    | awk -F'|' '
        # Skip header row ("Category", "Prefix") and separator row ("---")
        $2 ~ /Category/ { next }
        $2 ~ /^-+$/ || $2 ~ /^[[:space:]]*-+[[:space:]]*$/ { next }
        $3 ~ /^[[:space:]]*-+[[:space:]]*$/ { next }
        {
          # Trim whitespace from column 3 (Prefix).
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
          if ($3 != "") print $3
        }
    ' \
    | sort -u
)"

if [ -z "$canonical_prefixes" ]; then
  echo "ERROR: failed to extract canonical prefix list from $canonical_doc" >&2
  echo "       Expected a markdown table after <a id=\"category-prefix-mapping\"></a>" >&2
  exit 2
fi

# Sanity check: the canonical set should contain at least the historical
# minimum of 5 prefixes. If we got fewer, the parser is broken or the doc
# was rearranged in a way this script no longer understands.
canonical_count="$(printf '%s\n' "$canonical_prefixes" | wc -l | tr -d ' ')"
if [ "$canonical_count" -lt 5 ]; then
  echo "ERROR: canonical table parsed only $canonical_count prefix(es); expected >= 5" >&2
  echo "       Parsed prefixes:" >&2
  printf '%s\n' "$canonical_prefixes" | sed 's/^/         /' >&2
  exit 2
fi

# Helper: emit canonical set minus a given list of excluded prefixes.
canonical_minus() {
  local excluded="$1"
  printf '%s\n' "$canonical_prefixes" \
    | grep -vxF "$excluded" \
    | sort -u
}

# ---------------------------------------------------------------------------
# Step 2: Per-consumer diff helpers.
#
# Each consumer extractor emits a sorted, deduplicated list of prefixes that
# the consumer declares. `compare_sets` diffs against the expected list and
# accumulates failures into the global `failures` counter.
# ---------------------------------------------------------------------------

failures=0

compare_sets() {
  local consumer_label="$1"
  local consumer_path="$2"
  local actual="$3"
  local expected="$4"

  if [ "$actual" = "$expected" ]; then
    echo "OK  $consumer_label"
    return 0
  fi

  failures=$((failures + 1))
  echo "FAIL $consumer_label" >&2
  echo "     file: $consumer_path" >&2
  echo "     expected prefixes:" >&2
  printf '%s\n' "$expected" | sed 's/^/       /' >&2
  echo "     actual prefixes:" >&2
  printf '%s\n' "$actual" | sed 's/^/       /' >&2

  # Show the symmetric difference for quick fix-up.
  local missing extra
  missing="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true)"
  extra="$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true)"
  if [ -n "$missing" ]; then
    echo "     missing (in canonical, absent from consumer):" >&2
    printf '%s\n' "$missing" | sed 's/^/       /' >&2
  fi
  if [ -n "$extra" ]; then
    echo "     extra (in consumer, absent from canonical):" >&2
    printf '%s\n' "$extra" | sed 's/^/       /' >&2
  fi
}

# Extract every PREFIX-NNN-style alternation (`SEC|PERF|...`) from a file,
# explode it on `|`, normalize, dedupe.
prefixes_from_alternations() {
  local file="$1"
  grep -oE '\(([A-Z]{2,8})(\|[A-Z]{2,8})+\)' "$file" \
    | tr -d '()' \
    | tr '|' '\n' \
    | grep -E '^[A-Z]{2,8}$' \
    | sort -u
}

# ---------------------------------------------------------------------------
# Step 3: Check plugins/code-review/commands/fix.md
#
# Expected scope: full canonical set. The file holds two prefix lists:
#  - the input-mode regex `^(SEC|PERF|ARCH|MAINT|DOC|QA)-\d{3}$`
#  - a `case "$prefix" in QA) ... ;; *) ... ;; esac` dispatch
# We extract via the alternation regex (covers the first form). The case
# statement is QA-vs-rest dispatch — it does not enumerate every prefix, so we
# rely on the regex to enumerate the full set.
# ---------------------------------------------------------------------------

if [ ! -r "$fix_cmd" ]; then
  echo "ERROR: consumer not readable: $fix_cmd" >&2
  exit 2
fi

fix_cmd_actual="$(prefixes_from_alternations "$fix_cmd")"
fix_cmd_expected="$(printf '%s\n' "$canonical_prefixes")"
compare_sets \
  "fix.md (input-mode regex)" \
  "$fix_cmd" \
  "$fix_cmd_actual" \
  "$fix_cmd_expected"

# ---------------------------------------------------------------------------
# Step 4: Check plugins/code-review/agents/fix-auto.md
#
# Expected scope: full canonical Category set (semantic, not prefix). The
# Category enum lives in the field-extraction table:
#   `| Category | **Category:** Security|Performance|Architecture|...|Testing |`
# We extract the alternation embedded inside that markdown cell.
# ---------------------------------------------------------------------------

if [ ! -r "$fix_auto_agent" ]; then
  echo "ERROR: consumer not readable: $fix_auto_agent" >&2
  exit 2
fi

# Map canonical prefixes back to category names so we can compare apples to
# apples. The mapping is parsed from the same canonical table.
canonical_categories="$(
  awk '
    /<a id="category-prefix-mapping"><\/a>/ { in_section = 1; next }
    in_section && /^### / {
      heading_count++
      if (heading_count >= 2) { in_section = 0 }
      next
    }
    in_section && /^\|/ { print }
  ' "$canonical_doc" \
    | awk -F'|' '
        $2 ~ /Category/ { next }
        $2 ~ /^[[:space:]]*-+[[:space:]]*$/ { next }
        {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
          if ($2 != "") print $2
        }
    ' \
    | sort -u
)"

# Category enum: pull the line declaring `**Category:** ...|...|...`
fix_auto_actual="$(
  grep -oE '\*\*Category:\*\* ?([A-Z][a-zA-Z]+)(\\?\|[A-Z][a-zA-Z]+)+' "$fix_auto_agent" \
    | head -1 \
    | sed -E 's/^\*\*Category:\*\* ?//' \
    | tr -d '\\' \
    | tr '|' '\n' \
    | grep -E '^[A-Z][a-zA-Z]+$' \
    | sort -u
)"

compare_sets \
  "fix-auto.md (Category enum)" \
  "$fix_auto_agent" \
  "$fix_auto_actual" \
  "$canonical_categories"

# ---------------------------------------------------------------------------
# Step 5: Check plugins/code-review/scripts/extract-issue-ids.sh
#
# Expected scope: canonical set MINUS `QA`. QA reports live in
# docs/testing/reports/ and are produced by /qa:run, so this extractor is
# scoped to docs/reviews/ only.
# ---------------------------------------------------------------------------

if [ ! -r "$extract_ids_script" ]; then
  echo "ERROR: consumer not readable: $extract_ids_script" >&2
  exit 2
fi

extract_actual="$(prefixes_from_alternations "$extract_ids_script")"
extract_expected="$(canonical_minus "QA")"
compare_sets \
  "extract-issue-ids.sh (regex, QA excluded by scope)" \
  "$extract_ids_script" \
  "$extract_actual" \
  "$extract_expected"

# ---------------------------------------------------------------------------
# Step 6: Summary
# ---------------------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
  echo ""
  echo "All consumers in sync with canonical table at:"
  echo "  $canonical_doc"
  exit 0
fi

echo "" >&2
echo "Sync check FAILED: $failures consumer(s) diverge from the canonical Category→Prefix table." >&2
echo "Canonical SSoT: docs/plugins/code-review.md  (anchor: category-prefix-mapping)" >&2
exit 1

#!/usr/bin/env bash
# allocate-feedback-file.sh — locate-or-create the feedback report target file.
#
# Used by /analyze-feedback Step 5.5.1 / 5.5.4 to:
#   1. Glob docs/reviews/ for an existing review file matching `*-<slug>*.md`
#      (newest by mtime). If found, emits its path and exits 0 (append mode).
#   2. Otherwise atomically create `docs/reviews/YYYY-MM-DD-<slug>-feedback.md`
#      with O_CREAT|O_EXCL|O_NOFOLLOW. On collision, retries with `-2`, `-3`,
#      … up to max_attempts=1000.
#   3. Asserts the resolved final path is still inside docs/reviews/
#      (defense-in-depth against slugs that smuggled `../` or absolute paths
#      past sanitization).
#
# Output: emits the resolved target path on stdout (one line, no trailing
# diagnostic). All informational and error messages go to stderr.
#
# Usage:
#   target="$(bash plugins/code-review/scripts/allocate-feedback-file.sh "$slug")"
#
# Exit codes:
#   0 — target path emitted on stdout.
#   1 — slug empty/unsafe, exhausted max_attempts, path-containment check
#       failed, or python3 unavailable.
#   2 — usage error (missing argument).
#
# Notes on TOCTOU / symlink safety:
#   The bash `set -C; : > "$target"` pattern is not portable across POSIX
#   shells (dash/ash may implement noclobber as non-atomic stat()+open()),
#   and even in bash O_EXCL alone does not refuse to follow a pre-existing
#   symlink — only O_EXCL | O_NOFOLLOW is a full TOCTOU/symlink-swap guard.
#   We delegate the create to a single Python syscall (os.open with
#   O_CREAT|O_EXCL|O_NOFOLLOW), which is uniform on all target platforms
#   (macOS, Linux CI, Alpine).
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: allocate-feedback-file.sh <slug>" >&2
  exit 2
fi

slug="$1"

# Hard assertion: empty slug would reduce the glob to `*-*.md` and match every
# review file in the directory, silently routing us into append mode against an
# unrelated PR. This duplicates the slugifier's check on purpose — keep it as
# the load-bearing pre-glob guard even if slugify-branch.sh is later refactored.
if [ -z "$slug" ]; then
  echo "ERROR: empty slug — refusing to glob (would match all review files)" >&2
  exit 1
fi

# Defense-in-depth: leading dash in slug must never reach `find -name`. The
# canonical slugifier already strips this, but we re-assert here.
case "$slug" in
  -*)
    echo "ERROR: slug begins with '-' — refusing to use unsafe slug" >&2
    exit 1
    ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found in PATH (required for atomic O_EXCL|O_NOFOLLOW create)" >&2
  exit 1
fi

reviews_dir="docs/reviews"
mkdir -p "$reviews_dir"

# --- Step 1: glob for existing matching file (newest by mtime) ---
#
# `-maxdepth 1` prevents traversal into subdirectories. We pipe `find -print0`
# directly into `xargs -0 ls -t` (no intermediate command substitution) —
# bash command substitution strips NUL bytes, which would silently merge
# filenames into one unparseable blob and route to create mode. Using a
# direct pipeline preserves NUL separators so multi-file mtime ordering
# works correctly.
#
# We need to know whether `find` produced any matches before invoking xargs:
# GNU `xargs` (Linux) runs `ls -t` with no arguments on empty stdin — which
# lists the cwd and silently routes to append mode against an unrelated file.
# BSD `xargs -0` (macOS) skips the utility on empty input, but relying on
# that is not portable. We use `--no-run-if-empty` where supported (GNU) and
# fall back to a presence check using `find ... -quit` via a separate call.
target=""
if find "$reviews_dir" -maxdepth 1 -type f -name "*-${slug}*.md" -print -quit 2>/dev/null | grep -q .; then
  # At least one match exists; safe to invoke xargs ls -t.
  target=$(find "$reviews_dir" -maxdepth 1 -type f -name "*-${slug}*.md" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -1 || true)
fi

if [ -n "$target" ] && [ -f "$target" ]; then
  # Append-mode hit. Still validate path containment before returning.
  resolved="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
  reviews_abs="$(cd "$reviews_dir" && pwd -P)"
  case "$resolved" in
    "$reviews_abs"/*) ;;
    *)
      echo "ERROR: existing target escapes ${reviews_dir}: ${resolved}" >&2
      exit 1
      ;;
  esac
  printf '%s\n' "$target"
  exit 0
fi

# --- Step 2: create-mode allocation with collision-safe atomic create ---

today="$(date +%Y-%m-%d)"
target="${reviews_dir}/${today}-${slug}-feedback.md"
counter=1
max_attempts=1000

while true; do
  # Atomic O_CREAT|O_EXCL|O_NOFOLLOW via a single syscall. Refuses to
  # create if $target exists (EEXIST) or if the final component is a
  # symlink (ELOOP). No TOCTOU window — no separate stat/lstat pre-check.
  if python3 - "$target" <<'PY' 2>/dev/null
import os, sys
fd = os.open(
    sys.argv[1],
    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
    0o644,
)
os.close(fd)
PY
  then
    break
  fi

  counter=$((counter + 1))
  if [ "$counter" -gt "$max_attempts" ]; then
    echo "ERROR: exceeded ${max_attempts} collision attempts for ${reviews_dir}/${today}-${slug}-feedback*.md" >&2
    exit 1
  fi
  target="${reviews_dir}/${today}-${slug}-feedback-${counter}.md"
done

# --- Step 3: defense-in-depth path-containment assertion ---
#
# Guards against slugs that smuggled `../` or absolute paths past sanitization.
# If the resolved final path falls outside docs/reviews/, unlink the file we
# just created and abort.
resolved="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
reviews_abs="$(cd "$reviews_dir" && pwd -P)"
case "$resolved" in
  "$reviews_abs"/*) ;;
  *)
    echo "ERROR: resolved target escapes ${reviews_dir}: ${resolved}" >&2
    rm -f -- "$target"
    exit 1
    ;;
esac

printf '%s\n' "$target"

#!/bin/bash
# Runs every docs drift script test in this directory. Requires bash and git.
# A test passes only with exit code 0 and a last line "PASS n FAIL 0"; a failing test prints its FAIL lines.
set -u
root="$(cd "$(dirname "$0")" && pwd)"
status=0
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
for t in "$root"/test-*.sh; do
  name="${t#"$root"/}"
  bash "$t" >"$log" 2>&1
  rc=$?
  result="$(tail -n 1 "$log")"
  printf '%s: %s (exit %s)\n' "$name" "$result" "$rc"
  if [ "$rc" -ne 0 ] || ! printf '%s\n' "$result" | grep -Eq '^PASS [0-9]+ FAIL 0$'; then
    status=1
    grep -E '^(FAIL|SKIP)' "$log"
  fi
done
exit "$status"

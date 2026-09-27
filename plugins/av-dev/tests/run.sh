#!/bin/bash
# Runs every script test of the av-dev skills. Requires bash, git, jq; ruby is not needed.
# A test passes only with exit code 0 and a last line "PASS n FAIL 0"; a failing test prints its FAIL lines.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
status=0
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
for s in av-setup av-verify av-docs-sync av-implement; do
  [ -d "$root/skills/$s/scripts" ] || { printf 'missing skill: skills/%s\n' "$s"; status=1; }
done
for t in "$root"/skills/*/tests/test-*.sh; do
  name="${t#"$root"/}"
  bash "$t" >"$log" 2>&1
  rc=$?
  result="$(tail -n 1 "$log")"
  printf '%s: %s (exit %s)\n' "$name" "$result" "$rc"
  case "$rc:$result" in
    0:PASS\ *\ FAIL\ 0) ;;
    *) status=1; grep -E '^(FAIL|SKIP)' "$log" | head -20 ;;
  esac
done
v="$(jq -r .version "$root/.claude-plugin/plugin.json")"
for f in "$root"/skills/*/VERSION; do
  [ "$(tr -d ' \n' <"$f")" = "$v" ] || { printf 'VERSION mismatch: %s != plugin.json %s\n' "${f#"$root"/}" "$v"; status=1; }
done
exit "$status"

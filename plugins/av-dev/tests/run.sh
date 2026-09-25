#!/bin/bash
# Runs every script test of the av-dev skills. Requires bash, git, jq; ruby is not needed.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
status=0
for t in "$root"/skills/*/tests/test-*.sh; do
  name="${t#"$root"/}"
  result="$(bash "$t" 2>&1 | tail -n 1)"
  printf '%s: %s\n' "$name" "$result"
  case "$result" in *"FAIL 0") ;; *) status=1 ;; esac
done
v="$(jq -r .version "$root/.claude-plugin/plugin.json")"
for f in "$root"/skills/*/VERSION; do
  [ "$(tr -d ' \n' <"$f")" = "$v" ] || { printf 'VERSION mismatch: %s != plugin.json %s\n' "${f#"$root"/}" "$v"; status=1; }
done
exit "$status"

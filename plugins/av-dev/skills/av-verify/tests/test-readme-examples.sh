#!/bin/bash
# The config examples of the README section "Slot models" pass check_setup.sh --config-only
# (it checks agents; gate.sh does not), and the local override example in "Config examples"
# does too (review of PR #19, point 14).
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CS="$(cd "$DIR/../av-setup/scripts" && pwd)/check_setup.sh"
README="$(cd "$DIR/../.." && pwd)/README.md"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

REPO="$TMP/repo"
mkdir -p "$REPO/.ai" && (cd "$REPO" && git init -q)

# The json blocks between "## Slot models" and the next "## " heading.
awk '/^## Slot models/ { s = 1; next } s && /^## / { exit }
     s && /^```json$/ { n++; f = sprintf("%s/example-%d.json", dir, n); b = 1; next }
     b && /^```$/ { b = 0; next }
     b { print > f }' dir="$TMP" "$README"
count="$(find "$TMP" -maxdepth 1 -name 'example-*.json' | wc -l | tr -d ' ')"
[ "$count" -ge 1 ] && ok || fail "expected a config example in the README section, found $count"

for ex in "$TMP"/example-*.json; do
  [ -f "$ex" ] || continue
  name="$(basename "$ex")"
  agents="$(printf '{%s}' "$(cat "$ex")" | jq -c '.agents' 2>/dev/null)"
  [ -n "$agents" ] && [ "$agents" != "null" ] && ok || { fail "$name: not a valid \"agents\" fragment"; continue; }
  jq -n --argjson a "$agents" '{version: 1, validation: {commands: {ok: {run: "true"}}, gates: {quick: ["ok"]}}, agents: $a}' >"$REPO/.ai/av.config.json"
  out="$(bash "$CS" --root "$REPO" --config-only 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok || fail "$name: check_setup.sh rejects the example ($rc): $(printf '%s' "$out" | grep SETUP_CONFIG_FIELD | head -3)"
done

# The local override example of "Config examples" (a whole JSON object).
awk '/^## Config examples/ { s = 1; next } s && /^## / { exit }
     s && /^Local override/ { l = 1; next }
     l && /^```json$/ { b = 1; next }
     b && /^```$/ { exit }
     b { print }' "$README" >"$TMP/local.json"
agents="$(jq -c '.agents' "$TMP/local.json" 2>/dev/null)"
if [ -n "$agents" ] && [ "$agents" != "null" ]; then
  jq -n --argjson a "$agents" '{version: 1, validation: {commands: {ok: {run: "true"}}, gates: {quick: ["ok"]}}, agents: $a}' >"$REPO/.ai/av.config.json"
  out="$(bash "$CS" --root "$REPO" --config-only 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok || fail "local override example: check_setup.sh rejects it ($rc): $(printf '%s' "$out" | grep SETUP_CONFIG_FIELD | head -3)"
else
  fail "local override example: no \"agents\" in the README block"
fi

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

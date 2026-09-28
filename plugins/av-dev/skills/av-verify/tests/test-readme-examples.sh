#!/bin/bash
# The config examples of the README section "Claude and Codex slots" pass gate.sh --list,
# and the first (default) one needs only Claude Code (review of PR #19, point 14).
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$DIR/scripts/gate.sh"
README="$(cd "$DIR/../.." && pwd)/README.md"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

REPO="$TMP/repo"
mkdir -p "$REPO/.ai" && (cd "$REPO" && git init -q)

# The json blocks between "## Claude and Codex slots" and the next "## " heading.
awk '/^## Claude and Codex slots/ { s = 1; next } s && /^## / { exit }
     s && /^```json$/ { n++; f = sprintf("%s/example-%d.json", dir, n); b = 1; next }
     b && /^```$/ { b = 0; next }
     b { print > f }' dir="$TMP" "$README"
count="$(find "$TMP" -maxdepth 1 -name 'example-*.json' | wc -l | tr -d ' ')"
[ "$count" -ge 2 ] && ok || fail "expected at least 2 config examples in the README section, found $count"

for ex in "$TMP"/example-*.json; do
  [ -f "$ex" ] || continue
  name="$(basename "$ex")"
  agents="$(printf '{%s}' "$(cat "$ex")" | sed 's/<codex-model>/example-model/g' | jq -c '.agents' 2>/dev/null)"
  [ -n "$agents" ] && [ "$agents" != "null" ] && ok || { fail "$name: not a valid \"agents\" fragment"; continue; }
  jq -n --argjson a "$agents" '{version: 1, validation: {commands: {ok: {run: "true"}}, gates: {quick: ["ok"]}}, agents: $a}' >"$REPO/.ai/av.config.json"
  out="$(bash "$GATE" --root "$REPO" --list 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ok || fail "$name: gate.sh --list rejects the example ($rc): $(printf '%s' "$out" | grep CONFIG_ERROR | head -3)"
done

first="$TMP/example-1.json"
if [ -f "$first" ]; then
  a="$(printf '{%s}' "$(cat "$first")" | jq -c '.agents')"
  printf '%s' "$a" | jq -e '.crossVendor == false' >/dev/null && ok || fail "default example: crossVendor must be false"
  printf '%s' "$a" | jq -e '[.models[] | objects | .provider] | index("codex") == null' >/dev/null && ok || fail "default example: must not need Codex"
fi

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

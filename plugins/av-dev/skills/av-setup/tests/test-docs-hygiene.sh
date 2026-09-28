#!/bin/bash
# Docs hygiene for the av-dev skills (review of PR #19, points 13 and 15):
# - skill descriptions have no generic trigger phrases that would start a whole run on a casual
#   "do it" in a chat;
# - references and skills keep no names from the projects the plugin was first built on.
set -u
SKILLS="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

# --- 1. descriptions: no generic triggers
for f in "$SKILLS"/*/SKILL.md; do
  desc="$(awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit } fm && /^description:/ { print }' "$f")"
  [ -n "$desc" ] && ok || { fail "no description in ${f#"$SKILLS"/}"; continue; }
  for phrase in '"do it"' '"zrób to"' '"zrob to"' '"roll out the plan"' '"wdroż plan"' '"wdroz plan"' '"go"' '"start"'; do
    case "$desc" in
      *"$phrase"*) fail "generic trigger $phrase in ${f#"$SKILLS"/}" ;;
      *) ok ;;
    esac
  done
done

# --- 2. no leftovers from specific projects in skills and references
while IFS= read -r hit; do
  [ -n "$hit" ] && fail "project leftover: ${hit#"$SKILLS"/}"
done < <(grep -rnE 'mobile-data-layer|mobile-presentation|SELF_CHECK|BOUNDED' "$SKILLS"/*/SKILL.md "$SKILLS"/*/references 2>/dev/null)
ok

# --- 3. the adoption grep keeps its Polish words on purpose, and says why
adoption="$SKILLS/av-setup/references/adoption.md"
grep -q 'orkiestrator' "$adoption" && grep -q 'repos keep their own language' "$adoption" && ok || fail "adoption.md: Polish grep words or the reason for them missing"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/bin/bash
# Docs hygiene for the av-dev skills (review of PR #19, points 13 and 15):
# - skill descriptions have no generic trigger phrases that would start a whole run on a casual
#   "do it" in a chat;
# - no file of the plugin (skills, scripts, tests, fixtures, agents, README) and not its page in
#   docs/ keeps a name from the projects the plugin was first built on.
set -u
SKILLS="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN="$(cd "$SKILLS/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

# --- 2. no leftovers from specific projects anywhere in the plugin
# The lists are ROT13, so this file does not carry the names it looks for.
# Names of projects and repos: any case. Markers of an old pipeline: exact case.
rot13() { printf '%s' "$1" | tr 'A-Za-z' 'N-ZA-Mn-za-m'; }
names="$(rot13 'asnzvyl|a-snzvyl|abiby|aonmn|a-pbybe|pnepbybe|tnqmrg|jfcbyabgn|yrkqvtvgny|yrtnpl-iraqbef|v18a-thneqvna|zbovyr-qngn-ynlre|zbovyr-cerfragngvba')"
markers="$(rot13 'FRYS_PURPX|OBHAQRQ')"
# leftovers DIR... - prints each line with a project name or an old marker
leftovers() {
  grep -rnIiE -- "$names" "$@" 2>/dev/null
  grep -rnIE -- "$markers" "$@" 2>/dev/null
}
page="$PLUGIN/../../docs/plugins/$(basename "$PLUGIN").md"
[ -f "$page" ] || page=""
hits="$(leftovers "$PLUGIN" ${page:+"$page"})"
[ -z "$hits" ] && ok || fail "project leftovers:
$hits"
# the check finds what it looks for: every name, in any case, in any file type
i=0
for n in $(printf '%s' "$names" | tr '|' ' '); do
  i=$((i + 1)); mkdir -p "$TMP/p$i/sub"
  printf 'x %s y\n' "$(printf '%s' "$n" | tr 'a-z' 'A-Z')" >"$TMP/p$i/sub/f$i.json"
  [ -n "$(leftovers "$TMP/p$i")" ] && ok || fail "leftover check misses name $i"
done
[ "$i" -eq 13 ] && ok || fail "name list has $i entries, expected 13"
printf '%s\n' "$(rot13 'OBHAQRQ')" >"$TMP/marker.sh"
[ -n "$(leftovers "$TMP/marker.sh")" ] && ok || fail "leftover check misses a marker"
printf 'bounded queue\n' >"$TMP/prose.md"
[ -z "$(leftovers "$TMP/prose.md")" ] && ok || fail "marker matched ordinary prose"

# --- 3. no trace of the removed Codex slot runner (this file names the patterns, so it is skipped)
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
runner='agent\.sh|agent_grant|agent_guard|codex exec|av-slot-(read-)?(low|medium|high|xhigh|max)([^a-z]|$)'
hits="$(grep -rnIE -- "$runner" "$PLUGIN" ${page:+"$page"} 2>/dev/null | grep -vF "$self:")"
[ -z "$hits" ] && ok || fail "runner leftovers:
$hits"
[ ! -e "$PLUGIN/hooks" ] && ok || fail "hooks/ is back; the plugin ships no hooks"
[ "$(find "$PLUGIN/agents" -name '*.md' | wc -l | tr -d ' ')" -eq 2 ] && ok || fail "expected 2 slot agents: av-slot and av-slot-read"

# --- 4. the adoption grep keeps its Polish words on purpose, and says why
adoption="$SKILLS/av-setup/references/adoption.md"
grep -q 'orkiestrator' "$adoption" && grep -q 'repos keep their own language' "$adoption" && ok || fail "adoption.md: Polish grep words or the reason for them missing"

# --- 5. user docs say what the skills do (review of PR #19: --defaults and the commit policy)
readme="$PLUGIN/README.md"
grep -q 'no interview and no waiting for approval' "$SKILLS/av-setup/SKILL.md" && ok || fail "av-setup: --defaults no longer skips the approval; update this test and the docs"
grep -F -- '--defaults' "$readme" | grep -q 'no approval wait' && ok || fail "README: the --defaults row does not say it skips the approval"
[ -z "$page" ] || { grep -F -- '--defaults' "$page" | grep -q 'approval wait' && ok || fail "docs page: --defaults does not say it skips the approval"; }
grep -q '`on-request`: stop' "$SKILLS/av-implement/SKILL.md" && grep -q '`after-green-gate`: commit' "$SKILLS/av-implement/SKILL.md" && ok || fail "av-implement: commit policy changed; update this test and the docs"
grep -q 'stops before the commit' "$readme" && ! grep 'stops before the commit' "$readme" | grep -vq 'on-request' && ok || fail "README: stopping before the commit is not tied to git.commit: on-request"
grep -q 'Stops before commit unless `git.commit`' "$SKILLS/av-implement/SKILL.md" && ok || fail "av-implement description: stopping before commit is not tied to git.commit"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

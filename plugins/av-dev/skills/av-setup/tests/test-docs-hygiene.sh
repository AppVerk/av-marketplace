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
  # Merge condition from the review of PR #19: a description may name only av-dev, the skill or
  # its config, never an ordinary request ("run the tests", "check my changes") that any session
  # with the plugin installed would match.
  for phrase in '"do it"' '"zrób to"' '"zrob to"' '"roll out the plan"' '"wdroż plan"' '"wdroz plan"' '"go"' '"start"' \
      '"run the tests"' '"build the project"' '"does the build pass"' '"odpal testy"' '"zbuduj projekt"' \
      '"check my changes"' '"review the diff"' '"do a code review of the branch"' '"sprawdź moje zmiany"' \
      '"update the docs"' '"check if the docs are up to date"' '"audit the docs"' '"zaktualizuj docs"' \
      '"prepare a plan"' '"break down the implementation"' '"analyze ticket PROJ-123"' '"przygotuj plan"' \
      '"implement PROJ-123"' '"implement the plan"' '"zaimplementuj PROJ-123"' '"zaimplementuj plan"' \
      '"set up the project for Claude"' '"bootstrap AI docs"' '"skonfigurować projekt dla Claude"' \
      'before a PR' 'after implementation' 'before a large change' 'after code changes' 'after review fixes'; do
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
# The word Codex may only explain a removed config field ("removed with Codex slots"); the
# .codex directory that the scan reports is a path, not the product. Checked in the plugin, the
# docs page, the marketplace catalog and the root README row (review of PR #19).
codex_hits="$(grep -rnI 'Codex' "$PLUGIN" ${page:+"$page"} "$PLUGIN/../../.claude-plugin/marketplace.json" "$PLUGIN/../../README.md" 2>/dev/null | grep -vF "$self:" | grep -v '/tests/' | grep -v 'removed with Codex slots')"
[ -z "$codex_hits" ] && ok || fail "Codex is still named outside a removed-field message:
$codex_hits"
[ "$(find "$PLUGIN/agents" -name '*.md' | wc -l | tr -d ' ')" -eq 2 ] && ok || fail "expected 2 slot agents: av-slot and av-slot-read"

# --- 4. the adoption grep keeps its Polish words on purpose, and says why
adoption="$SKILLS/av-setup/references/adoption.md"
grep -q 'orkiestrator' "$adoption" && grep -q 'repos keep their own language' "$adoption" && ok || fail "adoption.md: Polish grep words or the reason for them missing"

# --- 5. user docs say what the skills do (review of PR #19: --defaults skips the interview but
# still stops once for the approval of the team files; the commit policy)
readme="$PLUGIN/README.md"
grep -q -- '`--defaults`: no interview' "$SKILLS/av-setup/SKILL.md" && grep -q 'waits for that one approval' "$SKILLS/av-setup/SKILL.md" && ok || fail "av-setup: --defaults wording changed; update this test and the docs"
grep -F -- '--defaults' "$readme" | grep -q 'no interview' && grep -F -- '--defaults' "$readme" | grep -q 'stops once for your approval' && ok || fail "README: the --defaults row does not say it skips the interview but stops once for approval"
[ -z "$page" ] || { grep -F -- '--defaults' "$page" | grep -q 'stops once for approval' && ok || fail "docs page: --defaults does not say it stops once for approval"; }
grep -q '`on-request`: stop' "$SKILLS/av-implement/SKILL.md" && grep -q '`after-green-gate`: commit' "$SKILLS/av-implement/SKILL.md" && ok || fail "av-implement: commit policy changed; update this test and the docs"
grep -q 'stops before the commit' "$readme" && ! grep 'stops before the commit' "$readme" | grep -vq 'on-request' && ok || fail "README: stopping before the commit is not tied to git.commit: on-request"
grep -q 'Stops before commit unless `git.commit`' "$SKILLS/av-implement/SKILL.md" && ok || fail "av-implement description: stopping before commit is not tied to git.commit"

# --- 6. review verdict (review of PR #19): UNKNOWN origin blocks like NEW, a "to be confirmed"
# BLOCKER or HIGH needs a human, and av-implement, the README and the workflow page agree
review="$SKILLS/av-review/SKILL.md"; impl="$SKILLS/av-implement/SKILL.md"
grep -q '^1\. NEEDS_FIXES: a confirmed BLOCKER or HIGH with origin NEW or UNKNOWN\.' "$review" && ok || fail "av-review: NEEDS_FIXES rule without UNKNOWN"
grep -q '^2\. NEEDS_HUMAN: a "to be confirmed" BLOCKER or HIGH' "$review" && ok || fail "av-review: no NEEDS_HUMAN rule for to-be-confirmed findings"
grep -q 'UNKNOWN counts as NEW' "$review" && ok || fail "av-review: UNKNOWN origin not treated as NEW"
grep -q '<APPROVED | NEEDS_FIXES | NEEDS_HUMAN>' "$review" && ok || fail "av-review: report template misses NEEDS_HUMAN"
grep -q 'does not decide the verdict by itself' "$review" && fail "av-review: to-be-confirmed findings still do not decide the verdict" || ok
grep -q 'Fix BLOCKER and HIGH with origin NEW or UNKNOWN' "$impl" && ok || fail "av-implement: fixes skip UNKNOWN origin"
grep 'READY_FOR_COMMIT:' "$impl" | grep -q 'NEW or UNKNOWN and without an open "to be confirmed" BLOCKER or HIGH' && ok || fail "av-implement: READY_FOR_COMMIT ignores UNKNOWN or to-be-confirmed findings"
grep '^- NEEDS_HUMAN:' "$impl" | grep -q '"to be confirmed" BLOCKER or HIGH' && ok || fail "av-implement: NEEDS_HUMAN misses to-be-confirmed findings"
grep -q '`NEEDS_HUMAN` for one whose premise' "$readme" && ok || fail "README: review verdict misses NEEDS_HUMAN"
workflow="$PLUGIN/../../docs/workflow.md"
[ ! -f "$workflow" ] || { grep -q '`APPROVED`, `NEEDS_FIXES` or `NEEDS_HUMAN`' "$workflow" && ok || fail "docs/workflow.md: review verdict misses NEEDS_HUMAN"; }

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

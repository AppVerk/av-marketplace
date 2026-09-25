#!/bin/bash
# Testy czarnej skrzynki dla config.sh i lokalnego nadpisania w gate.sh.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$DIR/scripts/config.sh"
GATE="$DIR/scripts/gate.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

REPO="$TMP/repo with space"
mkdir -p "$REPO/.ai"
cd "$REPO" || exit 1
git init -q
git config user.email t@t
git config user.name t
printf '.ai/workspace/\n' >.gitignore
cat >.ai/av.config.json <<'EOF'
{"version":1,
 "validation":{"commands":{
   "unit":{"run":"echo UNIT_OK","expect":"UNIT_OK","timeoutSec":60},
   "fixtures":{"run":"echo F","optional":true}
 },"gates":{"quick":["unit","fixtures"]}},
 "agents":{"crossVendor":true,"models":{
   "implement":{"provider":"claude","model":"opus","effort":"high"},
   "review":{"provider":"codex","model":"gpt-x","effort":"xhigh"}}},
 "git":{"ticketPrefixes":["A","B"]}}
EOF
git add -A && git commit -qm init

# --- 1. bez pliku lokalnego: config zespolu bez zmian
out="$(bash "$CONFIG")"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "bez local: kod $rc"
[ "$(printf '%s' "$out" | jq -r '.agents.models.review.provider')" = "codex" ] && ok || fail "bez local: zly review"
out="$(bash "$CONFIG" --sources)"
has "$out" "CONFIG .ai/av.config.json" && ok || fail "sources: brak CONFIG"
has "$out" "CONFIG_LOCAL none" && ok || fail "sources: brak CONFIG_LOCAL none"

# --- 2. nadpisanie: obiekty rekurencyjnie, tablice zastepuja, null usuwa
cat >.ai/av.config.json.local <<'EOF'
{"agents":{"models":{"review":{"provider":"claude","model":"opus"}}},
 "validation":{"commands":{"unit":{"timeoutSec":999},"fixtures":null}},
 "git":{"ticketPrefixes":["C"]}}
EOF
out="$(bash "$CONFIG")"
[ "$(printf '%s' "$out" | jq -r '.agents.models.review.provider')" = "claude" ] && ok || fail "merge: provider nie nadpisany"
[ "$(printf '%s' "$out" | jq -r '.agents.models.review.effort')" = "xhigh" ] && ok || fail "merge: effort zgubiony"
[ "$(printf '%s' "$out" | jq -r '.agents.models.implement.model')" = "opus" ] && ok || fail "merge: implement zgubiony"
[ "$(printf '%s' "$out" | jq -r '.validation.commands.unit.timeoutSec')" = "999" ] && ok || fail "merge: timeout nie nadpisany"
[ "$(printf '%s' "$out" | jq -r '.validation.commands.unit.expect')" = "UNIT_OK" ] && ok || fail "merge: expect zgubiony"
[ "$(printf '%s' "$out" | jq -r '.validation.commands | has("fixtures")')" = "false" ] && ok || fail "merge: null nie usunal klucza"
[ "$(printf '%s' "$out" | jq -c '.git.ticketPrefixes')" = '["C"]' ] && ok || fail "merge: tablica nie zastapiona"

out="$(bash "$CONFIG" --no-local)"
[ "$(printf '%s' "$out" | jq -r '.agents.models.review.provider')" = "codex" ] && ok || fail "--no-local: uzyl local"

# --- 3. --sources: klucze i ostrzezenie o braku w .gitignore
out="$(bash "$CONFIG" --sources)"
has "$out" "CONFIG_LOCAL .ai/av.config.json.local" && ok || fail "sources: brak sciezki local"
has "$out" "OVERRIDE agents.models.review.provider" && ok || fail "sources: brak OVERRIDE provider"
has "$out" "REMOVE validation.commands.fixtures" && ok || fail "sources: brak REMOVE"
has "$out" "OVERRIDE git.ticketPrefixes" && ok || fail "sources: tablica jako jeden klucz"
has "$out" "WARNING .ai/av.config.json.local nie jest w .gitignore" && ok || fail "sources: brak ostrzezenia gitignore"
printf '.ai/av.config.json.local\n' >>.gitignore
out="$(bash "$CONFIG" --sources)"
has "$out" "WARNING" && fail "sources: ostrzezenie mimo gitignore" || ok

# --- 4. plik lokalny sledzony przez git
git add -f .ai/av.config.json.local >/dev/null 2>&1
out="$(bash "$CONFIG" --sources)"
has "$out" "jest sledzony przez git" && ok || fail "sources: brak ostrzezenia o sledzeniu"
git rm -q --cached .ai/av.config.json.local

# --- 5. zly JSON w local to blad configu
printf '{zly' >"$TMP/bad"; cp .ai/av.config.json.local "$TMP/good"; cp "$TMP/bad" .ai/av.config.json.local
out="$(bash "$CONFIG")"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "zly local: kod $rc"
has "$out" "CONFIG_ERROR niepoprawny JSON" && ok || fail "zly local: brak komunikatu"
out="$(bash "$GATE" --list)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "gate zly local: kod $rc"
printf '[1]' >.ai/av.config.json.local
out="$(bash "$CONFIG")"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "local tablica: kod $rc"
cp "$TMP/good" .ai/av.config.json.local

# --- 6. gate.sh: --list pokazuje nadpisanie, walidacja dziala na efektywnym configu
out="$(bash "$GATE" --list)"; rc=$?
has "$out" "CONFIG_LOCAL .ai/av.config.json.local" && ok || fail "gate list: brak CONFIG_LOCAL"
has "$out" "OVERRIDE agents.models.review.provider" && ok || fail "gate list: brak OVERRIDE"
has "$out" "CONFIG_ERROR agents.crossVendor" && ok || fail "gate list: crossVendor nie sprawdzony po merge"
[ "$rc" -eq 2 ] && ok || fail "gate list crossVendor: kod $rc"
out="$(bash "$GATE" --list --no-local)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "gate list --no-local: kod $rc"
has "$out" "CONFIG_LOCAL" && fail "gate --no-local pokazal local" || ok

# --- 7. gate.sh: bramka biegnie na efektywnym configu
cat >.ai/av.config.json.local <<'EOF'
{"validation":{"commands":{"fixtures":null},"gates":{"quick":["unit"]}}}
EOF
out="$(bash "$GATE" --gate quick --run-id l1)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "gate quick local: kod $rc"
has "$out" "CONFIG_LOCAL .ai/av.config.json.local" && ok || fail "gate quick: brak CONFIG_LOCAL"
has "$out" "CHECK fixtures" && fail "gate quick: fixtures mimo usuniecia" || ok
ls "${TMPDIR:-/tmp}"/av-config.* >/dev/null 2>&1 && fail "gate: zostal plik tymczasowy" || ok

# --- 8. --config z innym plikiem bierze jego .local
cp .ai/av.config.json "$TMP/prop.json"
out="$(bash "$CONFIG" --config "$TMP/prop.json" --sources)"
has "$out" "CONFIG_LOCAL none" && ok || fail "--config: wzial local zespolu"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

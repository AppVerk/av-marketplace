#!/bin/bash
# Black-box tests for config.sh and the local override in gate.sh.
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
 "agents":{"independentReview":true,"models":{"implement":"opus","review":"sonnet"}},
 "git":{"ticketPrefixes":["A","B"]}}
EOF
git add -A && git commit -qm init

# --- 1. no local file: team config unchanged
out="$(bash "$CONFIG")"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "no local: code $rc"
[ "$(printf '%s' "$out" | jq -r '.agents.models.review')" = "sonnet" ] && ok || fail "no local: wrong review"
out="$(bash "$CONFIG" --sources)"
has "$out" "CONFIG .ai/av.config.json" && ok || fail "sources: CONFIG missing"
has "$out" "CONFIG_LOCAL none" && ok || fail "sources: CONFIG_LOCAL none missing"

# --- 2. override: objects merge recursively, arrays replace, null removes
cat >.ai/av.config.json.local <<'EOF'
{"agents":{"models":{"review":"haiku"}},
 "validation":{"commands":{"unit":{"timeoutSec":999},"fixtures":null}},
 "git":{"ticketPrefixes":["C"]}}
EOF
out="$(bash "$CONFIG")"
[ "$(printf '%s' "$out" | jq -r '.agents.models.review')" = "haiku" ] && ok || fail "merge: review not overridden"
[ "$(printf '%s' "$out" | jq -r '.agents.models.implement')" = "opus" ] && ok || fail "merge: implement lost"
[ "$(printf '%s' "$out" | jq -r '.agents.independentReview')" = "true" ] && ok || fail "merge: agents key lost"
[ "$(printf '%s' "$out" | jq -r '.validation.commands.unit.timeoutSec')" = "999" ] && ok || fail "merge: timeout not overridden"
[ "$(printf '%s' "$out" | jq -r '.validation.commands.unit.expect')" = "UNIT_OK" ] && ok || fail "merge: expect lost"
[ "$(printf '%s' "$out" | jq -r '.validation.commands | has("fixtures")')" = "false" ] && ok || fail "merge: null did not remove the key"
[ "$(printf '%s' "$out" | jq -c '.git.ticketPrefixes')" = '["C"]' ] && ok || fail "merge: array not replaced"

out="$(bash "$CONFIG" --no-local)"
[ "$(printf '%s' "$out" | jq -r '.agents.models.review')" = "sonnet" ] && ok || fail "--no-local: used local"

# --- 3. --sources: keys and the warning about a missing .gitignore entry
out="$(bash "$CONFIG" --sources)"
has "$out" "CONFIG_LOCAL .ai/av.config.json.local" && ok || fail "sources: local path missing"
has "$out" "OVERRIDE agents.models.review" && ok || fail "sources: OVERRIDE review missing"
has "$out" "REMOVE validation.commands.fixtures" && ok || fail "sources: REMOVE missing"
has "$out" "OVERRIDE git.ticketPrefixes" && ok || fail "sources: array as one key"
has "$out" "WARNING .ai/av.config.json.local is not in .gitignore" && ok || fail "sources: gitignore warning missing"
printf '.ai/av.config.json.local\n' >>.gitignore
out="$(bash "$CONFIG" --sources)"
has "$out" "WARNING" && fail "sources: warning despite gitignore" || ok

# --- 4. local file tracked by git
git add -f .ai/av.config.json.local >/dev/null 2>&1
out="$(bash "$CONFIG" --sources)"
has "$out" "WARNING .ai/av.config.json.local is tracked by git" && ok || fail "sources: tracking warning missing"
git rm -q --cached .ai/av.config.json.local

# --- 5. bad JSON in local is a config error
printf '{bad' >"$TMP/bad"; cp .ai/av.config.json.local "$TMP/good"; cp "$TMP/bad" .ai/av.config.json.local
out="$(bash "$CONFIG")"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "bad local: code $rc"
has "$out" "CONFIG_ERROR invalid JSON" && ok || fail "bad local: message missing"
out="$(bash "$GATE" --list)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "gate bad local: code $rc"
printf '[1]' >.ai/av.config.json.local
out="$(bash "$CONFIG")"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "local array: code $rc"
cp "$TMP/good" .ai/av.config.json.local

# --- 6. gate.sh: --list shows the override, validation runs on the effective config
out="$(bash "$GATE" --list)"; rc=$?
has "$out" "CONFIG_LOCAL .ai/av.config.json.local" && ok || fail "gate list: CONFIG_LOCAL missing"
has "$out" "OVERRIDE agents.models.review" && ok || fail "gate list: OVERRIDE missing"
has "$out" "CONFIG_ERROR agents.models.review" && ok || fail "gate list: review model not checked after merge"
[ "$rc" -eq 2 ] && ok || fail "gate list review haiku: code $rc"
out="$(bash "$GATE" --list --no-local)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "gate list --no-local: code $rc"
has "$out" "CONFIG_LOCAL" && fail "gate --no-local showed local" || ok

# --- 7. gate.sh: the gate runs on the effective config
cat >.ai/av.config.json.local <<'EOF'
{"validation":{"commands":{"fixtures":null},"gates":{"quick":["unit"]}}}
EOF
out="$(bash "$GATE" --gate quick --run-id l1)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "gate quick local: code $rc"
has "$out" "CONFIG_LOCAL .ai/av.config.json.local" && ok || fail "gate quick: CONFIG_LOCAL missing"
has "$out" "CHECK fixtures" && fail "gate quick: fixtures despite removal" || ok
ls "${TMPDIR:-/tmp}"/av-config.* >/dev/null 2>&1 && fail "gate: temporary file left behind" || ok
jq -e '.checks.unit.configLocal == ".ai/av.config.json.local"' .ai/workspace/runs/l1/evidence.json >/dev/null && ok || fail "gate: evidence does not record the local override"
out="$(bash "$GATE" --status --run-id l1)"
has "$out" "CHECK unit PASS FRESH" && has "$out" "(local override .ai/av.config.json.local)" && ok || fail "status: local override not shown: $out"
out="$(bash "$GATE" --only unit --no-local --run-id l2)"
jq -e '.checks.unit | has("configLocal") | not' .ai/workspace/runs/l2/evidence.json >/dev/null && ok || fail "gate --no-local: evidence claims a local override"
out="$(bash "$GATE" --status --run-id l2)"
has "$out" "local override" && fail "status --no-local run shows a local override: $out" || ok

# --- 8. --config with another file takes its own .local
cp .ai/av.config.json "$TMP/prop.json"
out="$(bash "$CONFIG" --config "$TMP/prop.json" --sources)"
has "$out" "CONFIG_LOCAL none" && ok || fail "--config: took the team local"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

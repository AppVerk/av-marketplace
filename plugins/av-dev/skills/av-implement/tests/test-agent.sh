#!/bin/bash
# Testy czarnej skrzynki dla agent.sh.
# Podmienia CLI claude i codex na atrapy, ktore zapisuja argumenty, env i prompt.
set -u
AGENT="$(cd "$(dirname "$0")/.." && pwd)/scripts/agent.sh"
AGENT_DEFS="$(cd "$(dirname "$0")/.." && pwd)/agents"
[ -d "$AGENT_DEFS" ] || AGENT_DEFS="$(cd "$(dirname "$0")/../../.." && pwd)/agents"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

unset AV_AGENT_SLOT AV_AGENT_RUN_ID CODEX_THREAD_ID CODEX_SANDBOX
export CLAUDECODE=1

BIN="$TMP/bin"
mkdir -p "$BIN" "$TMP/codex-home" "$TMP/agents"
: >"$TMP/codex-home/config.toml"
cp "$AGENT_DEFS"/*.md "$TMP/agents/"
export CODEX_HOME="$TMP/codex-home" AV_AGENTS_DIR="$TMP/agents"

cat >"$BIN/fake-codex" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/codex.args"
printf 'slot=%s run=%s\n' "${AV_AGENT_SLOT:-}" "${AV_AGENT_RUN_ID:-}" >"$FAKE_DIR/codex.env"
cat >"$FAKE_DIR/codex.prompt"
out=""; model="gpt-default"; effort="medium"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -m) model="$2"; shift 2 ;;
    -c) case "$2" in model_reasoning_effort=*) effort="$(printf '%s' "$2" | sed -n 's/^model_reasoning_effort="\(.*\)"$/\1/p')" ;; esac; shift 2 ;;
    *) shift ;;
  esac
done
printf 'OpenAI Codex\n--------\nmodel: %s\nreasoning effort: %s\nsession id: s-123\n--------\n' "$model" "$effort"
[ -n "${FAKE_TOUCH:-}" ] && echo zmiana >>"$FAKE_TOUCH"
[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
[ -n "${FAKE_EMPTY:-}" ] && exit 0
if [ -n "${FAKE_PERM:-}" ]; then
  printf 'Zrobione czesciowo.\nPERMISSION_REQUEST: xcodebuild test | uruchomienie testow | brak dowodu\n' >"$out"
  exit 0
fi
printf 'APPROVED: wynik codex\n' >"$out"
exit "${FAKE_RC:-0}"
EOF
cat >"$BIN/fake-claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/claude.args"
printf 'slot=%s\n' "${AV_AGENT_SLOT:-}" >"$FAKE_DIR/claude.env"
cat >"$FAKE_DIR/claude.prompt"
[ -n "${FAKE_TOUCH:-}" ] && echo zmiana >>"$FAKE_TOUCH"
if [ -n "${FAKE_ERROR:-}" ]; then
  printf '{"type":"result","is_error":true,"result":"blad","session_id":"c-1","modelUsage":{}}\n'
  exit 0
fi
if [ -n "${FAKE_DENY:-}" ]; then
  printf '{"type":"result","is_error":false,"result":"czesciowo","session_id":"c-1","modelUsage":{"claude-opus-5-5":{}},"permission_denials":[{"tool_name":"Bash","tool_input":{"command":"xcrun swiftc -parse A.swift"}}]}\n'
  exit 0
fi
printf '{"type":"result","is_error":false,"result":"PLAN_READY: wynik claude","session_id":"c-1","modelUsage":{"claude-opus-5-5":{}}}\n'
EOF
chmod +x "$BIN/fake-codex" "$BIN/fake-claude"
export AV_CODEX_BIN="$BIN/fake-codex" AV_CLAUDE_BIN="$BIN/fake-claude" FAKE_DIR="$TMP"

REPO="$TMP/repo"
mkdir -p "$REPO/.ai"
cd "$REPO" || exit 1
git init -q
git config user.email t@t
git config user.name t
printf '.ai/workspace/\n' >.gitignore
echo a >a.txt
cat >.ai/av.config.json <<'EOF'
{"version":1,"paths":{"workspace":".ai/workspace"},
 "validation":{"commands":{"ok":{"run":"true"}},"gates":{"quick":["ok"]}},
 "agents":{"crossVendor":true,"timeoutSec":60,"models":{
   "plan":{"provider":"codex","model":"gpt-6-astra","effort":"high"},
   "planReview":{"provider":"claude","model":"opus"},
   "implement":{"provider":"claude","model":"opus","effort":"xhigh"},
   "review":{"provider":"codex","model":"gpt-6-astra","effort":"xhigh"},
   "verify":"inherit"}}}
EOF
git add -A && git commit -qm init
echo "Zrob review przebiegu." >"$TMP/prompt.md"

# --- 1. resolve: via session, agent (z definicja effort), agent.sh
out="$(bash "$AGENT" --slot review --resolve)"
has "$out" "SLOT review provider=codex model=gpt-6-astra effort=xhigh access=read harness=claude local=no via=agent.sh" && ok || fail "resolve review: $out"
out="$(bash "$AGENT" --slot implement --resolve)"
has "$out" "via=agent subagent=av-slot-xhigh" && ok || fail "resolve implement: $out"
has "$out" "WARNING" && fail "resolve: ostrzezenie mimo definicji: $out" || ok
out="$(bash "$AGENT" --slot planReview --resolve)"
has "$out" "access=read" && has "$out" "via=agent subagent=general-purpose" && ok || fail "resolve planReview bez effort: $out"
jq '.agents.models.planReview.effort = "high"' .ai/av.config.json >"$TMP/pr.json"
out="$(bash "$AGENT" --config "$TMP/pr.json" --slot planReview --resolve)"
has "$out" "subagent=av-slot-read-high" && ok || fail "resolve planReview read z effort: $out"
out="$(AV_AGENTS_DIR="$TMP/brak" bash "$AGENT" --slot implement --resolve)"
has "$out" "WARNING brak definicji agenta" && ok || fail "resolve: brak ostrzezenia o definicji: $out"
out="$(bash "$AGENT" --slot verify --resolve)"
has "$out" "local=yes via=session" && ok || fail "resolve verify lokalny: $out"
out="$(bash "$AGENT" --slot implement --resolve --harness codex)"
has "$out" "via=agent.sh" && ok || fail "resolve: claude w sesji codex powinien isc przez agent.sh: $out"
out="$(bash "$AGENT" --slot missing --resolve)"
has "$out" "provider=claude model=inherit effort=inherit" && ok || fail "resolve brak slotu: $out"
out="$(AV_AGENT_SLOT=review bash "$AGENT" --slot review --resolve)"
has "$out" "local=yes via=session" && ok || fail "resolve: wykonawca slotu powinien byc lokalny: $out"
out="$(CODEX_THREAD_ID=x bash "$AGENT" --slot review --resolve)"
has "$out" "harness=codex" && ok || fail "resolve: brak wykrycia codex: $out"
jq '.agents.models.review = {"provider":"codex","model":"x"} | del(.agents.models.planReview) | .agents.crossVendor = false' .ai/av.config.json >"$TMP/inh.json"
out="$(bash "$AGENT" --config "$TMP/inh.json" --slot planReview --resolve)"
has "$out" "provider=codex model=x" && ok || fail "resolve: planReview nie dziedziczy review: $out"

# --- 2. codex: argumenty, sandbox uzytkownika, env, prompt, wynik
out="$(bash "$AGENT" --slot review --run-id r1 --prompt-file "$TMP/prompt.md" --label r1)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "codex: kod $rc: $out"
has "$out" "AGENT_OK review-r1" && has "$out" "actual=gpt-6-astra" && ok || fail "codex: brak AGENT_OK: $out"
args="$(cat "$TMP/codex.args")"
has "$args" 'sandbox_mode="workspace-write"' && ok || fail "codex: brak domyslnego sandboxu"
has "$args" "dangerously" && fail "codex: omija sandbox" || ok
has "$args" "gpt-6-astra" && has "$args" 'model_reasoning_effort="xhigh"' && has "$args" "$REPO" && ok || fail "codex: model/effort/root: $args"
has "$out" "RESUME $AV_CODEX_BIN resume s-123" && ok || fail "codex: brak komendy wznowienia: $out"
has "$(cat "$TMP/codex.env")" "slot=review run=r1" && ok || fail "codex: brak AV_AGENT_SLOT w env"
p="$(cat "$TMP/codex.prompt")"
has "$p" "Zrob review przebiegu." && has "$p" "Nie delegujesz dalej" && has "$p" "Dostep: tylko odczyt" && ok || fail "codex: niepelny prompt"
has "$p" "PERMISSION_REQUEST:" && ok || fail "codex: prompt bez zasady uprawnien"
has "$(cat .ai/workspace/runs/r1/agents/review-r1.md)" "APPROVED: wynik codex" && ok || fail "codex: brak pliku wyniku"
rec="$(tail -n 1 .ai/workspace/runs/r1/agents.jsonl)"
[ "$(printf '%s' "$rec" | jq -r '[.slot,.label,.provider,.model,.effort,.status,.actual_effort,.session,.via] | join(" ")')" = "review r1 codex gpt-6-astra xhigh OK xhigh s-123 agent.sh" ] && ok || fail "codex: zly wpis agents.jsonl: $rec"
printf 'sandbox_mode = "danger-full-access"\n' >"$TMP/codex-home/config.toml"
bash "$AGENT" --slot review --run-id r1 --prompt-file "$TMP/prompt.md" --label cfg >/dev/null
has "$(cat "$TMP/codex.args")" "sandbox_mode" && fail "codex: nadpisuje sandbox_mode z configu uzytkownika" || ok
: >"$TMP/codex-home/config.toml"

# --- 3. codex prosi o uprawnienie: NEEDS_PERMISSION, potem wznowienie z grant
out="$(FAKE_PERM=1 bash "$AGENT" --slot plan --run-id r6 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 5 ] && ok || fail "perm codex: kod $rc: $out"
has "$out" "AGENT_NEEDS_PERMISSION plan" && has "$out" "session=s-123" && ok || fail "perm codex: brak statusu: $out"
has "$out" "PERMISSION xcodebuild test | uruchomienie testow | brak dowodu" && ok || fail "perm codex: brak prosby: $out"
[ "$(tail -n 1 .ai/workspace/runs/r6/agents.jsonl | jq -r '.status + " " + (.permission_requests | length | tostring)')" = "NEEDS_PERMISSION 1" ] && ok || fail "perm codex: zly wpis"
out="$(bash "$AGENT" --slot plan --run-id r6 --resume s-123 --grant network --grant dir:/opt/cache)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESUMING s-123 grants: network dir:/opt/cache" && ok || fail "resume codex: $rc $out"
args="$(cat "$TMP/codex.args")"
has "$args" "resume" && has "$args" "s-123" && ok || fail "resume codex: brak exec resume: $args"
has "$args" "sandbox_workspace_write.network_access=true" && has "$args" 'writable_roots=["/opt/cache"]' && ok || fail "resume codex: brak uprawnien: $args"
has "$(cat "$TMP/codex.prompt")" "zgode czlowieka na: network dir:/opt/cache" && ok || fail "resume codex: prompt bez zgody"
rec="$(tail -n 1 .ai/workspace/runs/r6/agents.jsonl)"
[ "$(printf '%s' "$rec" | jq -r '.status + " " + .resumed_from + " " + (.grants | join(","))')" = "OK s-123 network,dir:/opt/cache" ] && ok || fail "resume codex: zly wpis: $rec"
has "$(cat .ai/workspace/runs/r6/agents/plan.log)" "==== wznowienie s-123" && ok || fail "resume codex: log nadpisany"
out="$(bash "$AGENT" --slot plan --run-id r6 --resume s-123 --grant full)"
has "$(cat "$TMP/codex.args")" 'sandbox_mode="danger-full-access"' && ok || fail "resume codex full: $out"

# --- 4. claude przez agent.sh: odmowa uprawnienia, wznowienie z regula
out="$(FAKE_DENY=1 bash "$AGENT" --slot implement --run-id r7 --prompt-file "$TMP/prompt.md" --harness codex)"; rc=$?
[ "$rc" -eq 5 ] && has "$out" "PERMISSION odmowa claude: Bash: xcrun swiftc -parse A.swift" && ok || fail "perm claude: $rc $out"
args="$(cat "$TMP/claude.args")"
has "$args" "acceptEdits" && ok || fail "claude write: brak acceptEdits: $args"
has "$args" "bypassPermissions" && fail "claude: omija uprawnienia" || ok
has "$args" "--effort" && has "$args" "xhigh" && ok || fail "claude: brak effort"
out="$(bash "$AGENT" --slot implement --run-id r7 --resume c-1 --grant 'tool:Bash(xcrun swiftc:*)' --harness codex)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "resume claude: $rc $out"
args="$(cat "$TMP/claude.args")"
has "$args" "--resume" && has "$args" "c-1" && has "$args" "Bash(xcrun swiftc:*)" && ok || fail "resume claude: $args"
out="$(bash "$AGENT" --slot planReview --run-id r7 --prompt-file "$TMP/prompt.md" --harness codex)"
args="$(cat "$TMP/claude.args")"
has "$args" "acceptEdits" && fail "claude read: acceptEdits w slocie read" || ok
out="$(bash "$AGENT" --slot implement --run-id r7 --resume c-1 --grant network --harness codex)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "niepoprawne --grant" && ok || fail "grant zly dla claude: $rc $out"
out="$(bash "$AGENT" --slot plan --run-id r7 --resume s-1 --grant dir:rel)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "grant dir wzgledny: $rc"
out="$(bash "$AGENT" --slot plan --run-id r7 --resume s-1)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "wymaga co najmniej jednego --grant" && ok || fail "resume bez grant: $rc $out"
out="$(bash "$AGENT" --slot plan --run-id r7 --prompt-file "$TMP/prompt.md" --grant network)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "tylko z --resume" && ok || fail "grant bez resume: $rc $out"

# --- 5. claude: slot write, wynik z JSON, lista zmian
FAKE_TOUCH="$REPO/a.txt" bash "$AGENT" --slot implement --run-id r1 --prompt-file "$TMP/prompt.md" --harness codex >"$TMP/o" 2>&1; rc=$?; out="$(cat "$TMP/o")"
[ "$rc" -eq 0 ] && has "$out" "actual=claude-opus-5-5" && has "$out" "CHANGED a.txt" && ok || fail "claude write: $rc $out"
has "$(cat .ai/workspace/runs/r1/agents/implement.md)" "PLAN_READY: wynik claude" && ok || fail "claude: brak wyniku z JSON"
git checkout -q a.txt

# --- 6. straznik slotu read i porazki
FAKE_TOUCH="$REPO/a.txt" bash "$AGENT" --slot review --run-id r2 --prompt-file "$TMP/prompt.md" >"$TMP/o" 2>&1; rc=$?
[ "$rc" -eq 1 ] && has "$(cat "$TMP/o")" "slot read zmienil drzewo" && ok || fail "read guard: $rc"
git checkout -q a.txt
out="$(FAKE_RC=7 bash "$AGENT" --slot review --run-id r3 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "kod wyjscia 7" && ok || fail "kod wyjscia: $rc $out"
out="$(FAKE_EMPTY=1 bash "$AGENT" --slot review --run-id r3 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "pusty wynik" && ok || fail "pusty wynik: $rc $out"
out="$(FAKE_ERROR=1 bash "$AGENT" --slot implement --run-id r3 --prompt-file "$TMP/prompt.md" --harness codex)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "is_error" && ok || fail "is_error: $rc $out"
out="$(FAKE_SLEEP=10 bash "$AGENT" --slot review --run-id r3 --prompt-file "$TMP/prompt.md" --timeout 1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "timeout 1s" && ok || fail "timeout: $rc $out"
out="$(AV_CODEX_BIN=/nie/ma/codex bash "$AGENT" --slot review --run-id r4 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 3 ] && has "$out" "AGENT_NOT_RUN review brak CLI" && ok || fail "brak CLI: $rc $out"

# --- 7. bledy wywolania i configu
out="$(AV_AGENT_SLOT=implement bash "$AGENT" --slot review --run-id r5 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "zagniezdzone delegowanie" && ok || fail "zagniezdzenie: $rc $out"
out="$(bash "$AGENT" --slot review --run-id r5)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "brak pliku promptu" && ok || fail "brak promptu: $rc $out"
out="$(bash "$AGENT" --slot review --run-id '../x' --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "zly RUN_ID: $rc"
out="$(bash "$AGENT" --slot review --run-id r5 --prompt-file "$TMP/prompt.md" --access admin)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "zly access: $rc"
jq '.agents.models.implement = {"provider":"codex","model":"gpt-6-astra"}' .ai/av.config.json >"$TMP/bad.json"
out="$(bash "$AGENT" --config "$TMP/bad.json" --slot review --resolve)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "CONFIG_ERROR agents.crossVendor" && ok || fail "config crossVendor: $rc $out"

# --- 8. zapis slotu z narzedzia Agent
out="$(bash "$AGENT" --slot implement --run-id r1 --record --status OK --seconds 42 --out "$REPO/.ai/workspace/runs/r1/agents/implement-agent.md" --actual claude-opus-5-5)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "AGENT_RECORDED implement via=agent OK 42s" && ok || fail "record: $rc $out"
out="$(bash "$AGENT" --slot implement --run-id r1 --record --status MAYBE --seconds 1)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "record zly status: $rc"

# --- 9. dry-run i podsumowanie
before="$(wc -l <.ai/workspace/runs/r1/agents.jsonl)"
out="$(bash "$AGENT" --slot plan --run-id r1 --prompt-file "$TMP/prompt.md" --dry-run)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "DRY_RUN" && has "$out" "gpt-6-astra" && ok || fail "dry-run: $rc $out"
[ "$(wc -l <.ai/workspace/runs/r1/agents.jsonl)" -eq "$before" ] && ok || fail "dry-run: dopisal wpis"
out="$(bash "$AGENT" --summary --run-id r1)"
has "$out" "AGENT_RUN review-r1 codex gpt-6-astra/xhigh via=agent.sh OK" && ok || fail "summary review: $out"
has "$out" "AGENT_RUN implement claude opus/xhigh via=agent OK 42s actual=claude-opus-5-5" && ok || fail "summary record: $out"
out="$(bash "$AGENT" --summary --run-id r6)"
has "$out" "NEEDS_PERMISSION" && has "$out" "grants=network,dir:/opt/cache" && ok || fail "summary uprawnien: $out"
out="$(bash "$AGENT" --summary --run-id brak)"
has "$out" "AGENTS brak delegowanych" && ok || fail "summary pusty: $out"

# --- 10. definicje agentow: effort we frontmatterze, read bez edycji
for e in low medium high xhigh max; do
  grep -q "^effort: $e$" "$AGENT_DEFS/av-slot-$e.md" && grep -q "^name: av-slot-$e$" "$AGENT_DEFS/av-slot-$e.md" && ok || fail "definicja av-slot-$e"
  f="$AGENT_DEFS/av-slot-read-$e.md"
  grep -q "^effort: $e$" "$f" && grep -q '^tools: ' "$f" && ! grep -Eq '^tools:.*(Edit|Write)' "$f" && ok || fail "definicja av-slot-read-$e"
done

# --- lokalne nadpisanie: .ai/av.config.json.local zmienia slot tylko u tej osoby
cd "$REPO" || exit 1
cat >.ai/av.config.json.local <<'EOF2'
{"agents":{"crossVendor":false,"models":{"review":{"provider":"claude","model":"opus","effort":"high"}}}}
EOF2
out="$(bash "$AGENT" --slot review --resolve)"
has "$out" "SLOT review provider=claude model=opus effort=high access=read" && has "$out" "subagent=av-slot-read-high" && ok || fail "local: slot nie nadpisany: $out"
out="$(bash "$AGENT" --slot plan --resolve)"
has "$out" "provider=codex model=gpt-6-astra effort=high" && ok || fail "local: zgubiony slot zespolu: $out"
printf '{"agents":{"models":{"review":"haiku"}}}' >.ai/av.config.json.local
out="$(bash "$AGENT" --slot review --resolve)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "haiku" && ok || fail "local: haiku w review przeszedl ($rc): $out"
printf '{zly' >.ai/av.config.json.local
out="$(bash "$AGENT" --slot review --resolve)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "CONFIG_ERROR" && ok || fail "local: zly JSON ($rc): $out"
rm -f .ai/av.config.json.local

# --- plugin: definicje w <plugin>/agents, subagent z prefiksem nazwy pluginu
PLUG="$TMP/plugin"
mkdir -p "$PLUG/.claude-plugin" "$PLUG/skills" "$PLUG/agents"
printf '{"name":"av-dev","version":"0.2.0"}' >"$PLUG/.claude-plugin/plugin.json"
for s in av-implement av-verify; do cp -R "$(cd "$(dirname "$AGENT")/../.." && pwd)/$s" "$PLUG/skills/"; done
cp "$AGENT_DEFS"/*.md "$PLUG/agents/"
out="$(env -u AV_AGENTS_DIR bash "$PLUG/skills/av-implement/scripts/agent.sh" --slot implement --resolve)"
has "$out" "subagent=av-dev:av-slot-xhigh" && ok || fail "plugin: brak prefiksu: $out"
has "$out" "WARNING" && fail "plugin: ostrzezenie mimo definicji: $out" || ok
rm "$PLUG/agents/av-slot-xhigh.md"
out="$(env -u AV_AGENTS_DIR bash "$PLUG/skills/av-implement/scripts/agent.sh" --slot implement --resolve)"
has "$out" "WARNING brak definicji agenta $PLUG/agents/av-slot-xhigh.md" && ok || fail "plugin: brak ostrzezenia: $out"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

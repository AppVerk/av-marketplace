#!/bin/bash
# Black-box tests for agent.sh.
# Replaces the claude and codex CLIs with fakes that record arguments, env and prompt.
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
[ -n "${FAKE_TOUCH:-}" ] && echo change >>"$FAKE_TOUCH"
[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
[ -n "${FAKE_EMPTY:-}" ] && exit 0
if [ -n "${FAKE_PERM:-}" ]; then
  printf 'Partly done.\nPERMISSION_REQUEST: xcodebuild test | run the tests | no evidence\n' >"$out"
  exit 0
fi
printf 'APPROVED: codex result\n' >"$out"
exit "${FAKE_RC:-0}"
EOF
cat >"$BIN/fake-claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE_DIR/claude.args"
printf 'slot=%s\n' "${AV_AGENT_SLOT:-}" >"$FAKE_DIR/claude.env"
cat >"$FAKE_DIR/claude.prompt"
[ -n "${FAKE_TOUCH:-}" ] && echo change >>"$FAKE_TOUCH"
if [ -n "${FAKE_ERROR:-}" ]; then
  printf '{"type":"result","is_error":true,"result":"error","session_id":"c-1","modelUsage":{}}\n'
  exit 0
fi
if [ -n "${FAKE_DENY:-}" ]; then
  printf '{"type":"result","is_error":false,"result":"partial","session_id":"c-1","modelUsage":{"claude-opus-5-5":{}},"permission_denials":[{"tool_name":"Bash","tool_input":{"command":"xcrun swiftc -parse A.swift"}}]}\n'
  exit 0
fi
printf '{"type":"result","is_error":false,"result":"PLAN_READY: claude result","session_id":"c-1","modelUsage":{"claude-opus-5-5":{}}}\n'
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
echo "Review the run." >"$TMP/prompt.md"

# --- 1. resolve: via session, agent (with an effort definition), agent.sh
out="$(bash "$AGENT" --slot review --resolve)"
has "$out" "SLOT review provider=codex model=gpt-6-astra effort=xhigh access=read harness=claude local=no via=agent.sh" && ok || fail "resolve review: $out"
out="$(bash "$AGENT" --slot implement --resolve)"
has "$out" "via=agent subagent=av-slot-xhigh" && ok || fail "resolve implement: $out"
has "$out" "WARNING" && fail "resolve: warning despite definition: $out" || ok
out="$(bash "$AGENT" --slot planReview --resolve)"
has "$out" "access=read" && has "$out" "via=agent subagent=general-purpose" && ok || fail "resolve planReview without effort: $out"
jq '.agents.models.planReview.effort = "high"' .ai/av.config.json >"$TMP/pr.json"
out="$(bash "$AGENT" --config "$TMP/pr.json" --slot planReview --resolve)"
has "$out" "subagent=av-slot-read-high" && ok || fail "resolve planReview read with effort: $out"
out="$(AV_AGENTS_DIR="$TMP/none" bash "$AGENT" --slot implement --resolve)"
has "$out" "WARNING agent definition $TMP/none/av-slot-xhigh.md not found" && ok || fail "resolve: definition warning missing: $out"
out="$(bash "$AGENT" --slot verify --resolve)"
has "$out" "local=yes via=session" && ok || fail "resolve verify local: $out"
out="$(bash "$AGENT" --slot implement --resolve --harness codex)"
has "$out" "via=agent.sh" && ok || fail "resolve: claude in a codex session should go through agent.sh: $out"
out="$(bash "$AGENT" --slot missing --resolve)"
has "$out" "provider=claude model=inherit effort=inherit" && ok || fail "resolve missing slot: $out"
out="$(AV_AGENT_SLOT=review bash "$AGENT" --slot review --resolve)"
has "$out" "local=yes via=session" && ok || fail "resolve: slot executor should be local: $out"
out="$(CODEX_THREAD_ID=x bash "$AGENT" --slot review --resolve)"
has "$out" "harness=codex" && ok || fail "resolve: codex not detected: $out"
jq '.agents.models.review = {"provider":"codex","model":"x"} | del(.agents.models.planReview) | .agents.crossVendor = false' .ai/av.config.json >"$TMP/inh.json"
out="$(bash "$AGENT" --config "$TMP/inh.json" --slot planReview --resolve)"
has "$out" "provider=codex model=x" && ok || fail "resolve: planReview does not inherit review: $out"

# --- 2. codex: arguments, user sandbox, env, prompt, result
out="$(bash "$AGENT" --slot review --run-id r1 --prompt-file "$TMP/prompt.md" --label r1)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "codex: code $rc: $out"
has "$out" "AGENT_OK review-r1" && has "$out" "actual=gpt-6-astra" && ok || fail "codex: AGENT_OK missing: $out"
args="$(cat "$TMP/codex.args")"
has "$args" 'sandbox_mode="workspace-write"' && ok || fail "codex: default sandbox missing"
has "$args" "dangerously" && fail "codex: bypasses the sandbox" || ok
has "$args" "gpt-6-astra" && has "$args" 'model_reasoning_effort="xhigh"' && has "$args" "$REPO" && ok || fail "codex: model/effort/root: $args"
has "$out" "RESUME $AV_CODEX_BIN resume s-123" && ok || fail "codex: resume command missing: $out"
has "$(cat "$TMP/codex.env")" "slot=review run=r1" && ok || fail "codex: AV_AGENT_SLOT missing in env"
p="$(cat "$TMP/codex.prompt")"
has "$p" "Review the run." && has "$p" "Do not delegate further" && has "$p" "Access: read only" && ok || fail "codex: incomplete prompt"
has "$p" "PERMISSION_REQUEST:" && ok || fail "codex: prompt without the permission rule"
has "$(cat .ai/workspace/runs/r1/agents/review-r1.md)" "APPROVED: codex result" && ok || fail "codex: result file missing"
rec="$(tail -n 1 .ai/workspace/runs/r1/agents.jsonl)"
[ "$(printf '%s' "$rec" | jq -r '[.slot,.label,.provider,.model,.effort,.status,.actual_effort,.session,.via] | join(" ")')" = "review r1 codex gpt-6-astra xhigh OK xhigh s-123 agent.sh" ] && ok || fail "codex: wrong agents.jsonl entry: $rec"
printf 'sandbox_mode = "danger-full-access"\n' >"$TMP/codex-home/config.toml"
bash "$AGENT" --slot review --run-id r1 --prompt-file "$TMP/prompt.md" --label cfg >/dev/null
has "$(cat "$TMP/codex.args")" "sandbox_mode" && fail "codex: overrides sandbox_mode from the user config" || ok
: >"$TMP/codex-home/config.toml"

# --- 3. codex asks for a permission: NEEDS_PERMISSION, then resume with grant
out="$(FAKE_PERM=1 bash "$AGENT" --slot plan --run-id r6 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 5 ] && ok || fail "perm codex: code $rc: $out"
has "$out" "AGENT_NEEDS_PERMISSION plan" && has "$out" "session=s-123" && ok || fail "perm codex: status missing: $out"
has "$out" "PERMISSION xcodebuild test | run the tests | no evidence" && ok || fail "perm codex: request missing: $out"
[ "$(tail -n 1 .ai/workspace/runs/r6/agents.jsonl | jq -r '.status + " " + (.permission_requests | length | tostring)')" = "NEEDS_PERMISSION 1" ] && ok || fail "perm codex: wrong entry"
out="$(bash "$AGENT" --slot plan --run-id r6 --resume s-123 --grant network --grant dir:/opt/cache)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESUMING s-123 grants: network dir:/opt/cache" && ok || fail "resume codex: $rc $out"
args="$(cat "$TMP/codex.args")"
has "$args" "resume" && has "$args" "s-123" && ok || fail "resume codex: exec resume missing: $args"
has "$args" "sandbox_workspace_write.network_access=true" && has "$args" 'writable_roots=["/opt/cache"]' && ok || fail "resume codex: permissions missing: $args"
has "$(cat "$TMP/codex.prompt")" "human approval for: network dir:/opt/cache" && ok || fail "resume codex: prompt without approval"
rec="$(tail -n 1 .ai/workspace/runs/r6/agents.jsonl)"
[ "$(printf '%s' "$rec" | jq -r '.status + " " + .resumed_from + " " + (.grants | join(","))')" = "OK s-123 network,dir:/opt/cache" ] && ok || fail "resume codex: wrong entry: $rec"
has "$(cat .ai/workspace/runs/r6/agents/plan.log)" "==== resume s-123" && ok || fail "resume codex: log overwritten"
out="$(bash "$AGENT" --slot plan --run-id r6 --resume s-123 --grant full)"
has "$(cat "$TMP/codex.args")" 'sandbox_mode="danger-full-access"' && ok || fail "resume codex full: $out"

# --- 4. claude through agent.sh: permission denial, resume with a rule
out="$(FAKE_DENY=1 bash "$AGENT" --slot implement --run-id r7 --prompt-file "$TMP/prompt.md" --harness codex)"; rc=$?
[ "$rc" -eq 5 ] && has "$out" "PERMISSION claude denial: Bash: xcrun swiftc -parse A.swift" && ok || fail "perm claude: $rc $out"
args="$(cat "$TMP/claude.args")"
has "$args" "acceptEdits" && ok || fail "claude write: acceptEdits missing: $args"
has "$args" "bypassPermissions" && fail "claude: bypasses permissions" || ok
has "$args" "--effort" && has "$args" "xhigh" && ok || fail "claude: effort missing"
out="$(bash "$AGENT" --slot implement --run-id r7 --resume c-1 --grant 'tool:Bash(xcrun swiftc:*)' --harness codex)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "resume claude: $rc $out"
args="$(cat "$TMP/claude.args")"
has "$args" "--resume" && has "$args" "c-1" && has "$args" "Bash(xcrun swiftc:*)" && ok || fail "resume claude: $args"
out="$(bash "$AGENT" --slot planReview --run-id r7 --prompt-file "$TMP/prompt.md" --harness codex)"
args="$(cat "$TMP/claude.args")"
has "$args" "acceptEdits" && fail "claude read: acceptEdits in a read slot" || ok
out="$(bash "$AGENT" --slot implement --run-id r7 --resume c-1 --grant network --harness codex)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "invalid --grant 'network' for claude" && ok || fail "wrong grant for claude: $rc $out"
out="$(bash "$AGENT" --slot plan --run-id r7 --resume s-1 --grant dir:rel)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "grant relative dir: $rc"
out="$(bash "$AGENT" --slot plan --run-id r7 --resume s-1)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "requires at least one --grant" && ok || fail "resume without grant: $rc $out"
out="$(bash "$AGENT" --slot plan --run-id r7 --prompt-file "$TMP/prompt.md" --grant network)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "only with --resume" && ok || fail "grant without resume: $rc $out"

# --- 5. claude: write slot, result from JSON, list of changes
FAKE_TOUCH="$REPO/a.txt" bash "$AGENT" --slot implement --run-id r1 --prompt-file "$TMP/prompt.md" --harness codex >"$TMP/o" 2>&1; rc=$?; out="$(cat "$TMP/o")"
[ "$rc" -eq 0 ] && has "$out" "actual=claude-opus-5-5" && has "$out" "CHANGED a.txt" && ok || fail "claude write: $rc $out"
has "$(cat .ai/workspace/runs/r1/agents/implement.md)" "PLAN_READY: claude result" && ok || fail "claude: result from JSON missing"
git checkout -q a.txt

# --- 6. read slot guard and failures
FAKE_TOUCH="$REPO/a.txt" bash "$AGENT" --slot review --run-id r2 --prompt-file "$TMP/prompt.md" >"$TMP/o" 2>&1; rc=$?
[ "$rc" -eq 1 ] && has "$(cat "$TMP/o")" "read slot changed the working tree" && ok || fail "read guard: $rc"
git checkout -q a.txt
out="$(FAKE_RC=7 bash "$AGENT" --slot review --run-id r3 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "exit code 7" && ok || fail "exit code: $rc $out"
out="$(FAKE_EMPTY=1 bash "$AGENT" --slot review --run-id r3 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "empty result" && ok || fail "empty result: $rc $out"
out="$(FAKE_ERROR=1 bash "$AGENT" --slot implement --run-id r3 --prompt-file "$TMP/prompt.md" --harness codex)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "is_error" && ok || fail "is_error: $rc $out"
out="$(FAKE_SLEEP=10 bash "$AGENT" --slot review --run-id r3 --prompt-file "$TMP/prompt.md" --timeout 1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "timeout 1s" && ok || fail "timeout: $rc $out"
out="$(AV_CODEX_BIN=/does/not/exist/codex bash "$AGENT" --slot review --run-id r4 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 3 ] && has "$out" "AGENT_NOT_RUN review CLI /does/not/exist/codex not found" && ok || fail "CLI missing: $rc $out"

# --- 7. invocation and config errors
out="$(AV_AGENT_SLOT=implement bash "$AGENT" --slot review --run-id r5 --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "nested delegation" && ok || fail "nesting: $rc $out"
out="$(bash "$AGENT" --slot review --run-id r5)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "prompt file not found" && ok || fail "prompt missing: $rc $out"
out="$(bash "$AGENT" --slot review --run-id '../x' --prompt-file "$TMP/prompt.md")"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "bad RUN_ID: $rc"
out="$(bash "$AGENT" --slot review --run-id r5 --prompt-file "$TMP/prompt.md" --access admin)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "bad access: $rc"
jq '.agents.models.implement = {"provider":"codex","model":"gpt-6-astra"}' .ai/av.config.json >"$TMP/bad.json"
out="$(bash "$AGENT" --config "$TMP/bad.json" --slot review --resolve)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "CONFIG_ERROR agents.crossVendor" && ok || fail "config crossVendor: $rc $out"

# --- 8. record a slot run by the Agent tool
out="$(bash "$AGENT" --slot implement --run-id r1 --record --status OK --seconds 42 --out "$REPO/.ai/workspace/runs/r1/agents/implement-agent.md" --actual claude-opus-5-5)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "AGENT_RECORDED implement via=agent OK 42s" && ok || fail "record: $rc $out"
out="$(bash "$AGENT" --slot implement --run-id r1 --record --status MAYBE --seconds 1)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "record bad status: $rc"

# --- 9. dry-run and summary
before="$(wc -l <.ai/workspace/runs/r1/agents.jsonl)"
out="$(bash "$AGENT" --slot plan --run-id r1 --prompt-file "$TMP/prompt.md" --dry-run)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "DRY_RUN" && has "$out" "gpt-6-astra" && ok || fail "dry-run: $rc $out"
[ "$(wc -l <.ai/workspace/runs/r1/agents.jsonl)" -eq "$before" ] && ok || fail "dry-run: added an entry"
out="$(bash "$AGENT" --summary --run-id r1)"
has "$out" "AGENT_RUN review-r1 codex gpt-6-astra/xhigh via=agent.sh OK" && ok || fail "summary review: $out"
has "$out" "AGENT_RUN implement claude opus/xhigh via=agent OK 42s actual=claude-opus-5-5" && ok || fail "summary record: $out"
out="$(bash "$AGENT" --summary --run-id r6)"
has "$out" "NEEDS_PERMISSION" && has "$out" "grants=network,dir:/opt/cache" && ok || fail "summary permissions: $out"
out="$(bash "$AGENT" --summary --run-id none)"
has "$out" "AGENTS no delegated slots in none" && ok || fail "summary empty: $out"

# --- 10. agent definitions: effort in the frontmatter, read without edit
for e in low medium high xhigh max; do
  grep -q "^effort: $e$" "$AGENT_DEFS/av-slot-$e.md" && grep -q "^name: av-slot-$e$" "$AGENT_DEFS/av-slot-$e.md" && ok || fail "definition av-slot-$e"
  f="$AGENT_DEFS/av-slot-read-$e.md"
  grep -q "^effort: $e$" "$f" && grep -q '^tools: ' "$f" && ! grep -Eq '^tools:.*(Edit|Write)' "$f" && ok || fail "definition av-slot-read-$e"
done

# --- local override: .ai/av.config.json.local changes the slot only for this person
cd "$REPO" || exit 1
cat >.ai/av.config.json.local <<'EOF2'
{"agents":{"crossVendor":false,"models":{"review":{"provider":"claude","model":"opus","effort":"high"}}}}
EOF2
out="$(bash "$AGENT" --slot review --resolve)"
has "$out" "SLOT review provider=claude model=opus effort=high access=read" && has "$out" "subagent=av-slot-read-high" && ok || fail "local: slot not overridden: $out"
out="$(bash "$AGENT" --slot plan --resolve)"
has "$out" "provider=codex model=gpt-6-astra effort=high" && ok || fail "local: team slot lost: $out"
printf '{"agents":{"models":{"review":"haiku"}}}' >.ai/av.config.json.local
out="$(bash "$AGENT" --slot review --resolve)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "haiku" && ok || fail "local: haiku in review passed ($rc): $out"
printf '{bad' >.ai/av.config.json.local
out="$(bash "$AGENT" --slot review --resolve)"; rc=$?
[ "$rc" -eq 2 ] && has "$out" "CONFIG_ERROR" && ok || fail "local: bad JSON ($rc): $out"
rm -f .ai/av.config.json.local

# --- plugin: definitions in <plugin>/agents, subagent with the plugin name prefix
PLUG="$TMP/plugin"
mkdir -p "$PLUG/.claude-plugin" "$PLUG/skills" "$PLUG/agents"
printf '{"name":"av-dev","version":"0.2.0"}' >"$PLUG/.claude-plugin/plugin.json"
for s in av-implement av-verify; do cp -R "$(cd "$(dirname "$AGENT")/../.." && pwd)/$s" "$PLUG/skills/"; done
cp "$AGENT_DEFS"/*.md "$PLUG/agents/"
out="$(env -u AV_AGENTS_DIR bash "$PLUG/skills/av-implement/scripts/agent.sh" --slot implement --resolve)"
has "$out" "subagent=av-dev:av-slot-xhigh" && ok || fail "plugin: prefix missing: $out"
has "$out" "WARNING" && fail "plugin: warning despite definition: $out" || ok
rm "$PLUG/agents/av-slot-xhigh.md"
out="$(env -u AV_AGENTS_DIR bash "$PLUG/skills/av-implement/scripts/agent.sh" --slot implement --resolve)"
has "$out" "WARNING agent definition $PLUG/agents/av-slot-xhigh.md not found" && ok || fail "plugin: warning missing: $out"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

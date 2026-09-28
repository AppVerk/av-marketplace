#!/bin/bash
# Black-box tests for agent_guard.sh (PreToolUse hook for agent.sh calls).
set -u
SCRIPTS="$(cd "$(dirname "$0")/.." && pwd -P)/scripts"
GUARD="$SCRIPTS/agent_guard.sh"
AGENT="$SCRIPTS/agent.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

unset CLAUDE_PLUGIN_ROOT

# decision <tool> <command> [env...]: prints allow, ask, none or invalid
decision() {
  local tool="$1" cmd="$2"; shift 2
  local out
  out="$(jq -cn --arg t "$tool" --arg c "$cmd" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}}' \
    | env "$@" bash "$GUARD")" || { printf 'exit-%s' "$?"; return; }
  if [ -z "$out" ]; then printf 'none'; return; fi
  printf '%s' "$out" | jq -er 'select(.hookSpecificOutput.hookEventName == "PreToolUse") | .hookSpecificOutput.permissionDecision' 2>/dev/null || printf 'invalid'
}

expect() {
  local want="$1" label="$2"; shift 2
  local got
  got="$(decision "$@")"
  [ "$got" = "$want" ] && ok || fail "$label: expected $want, got $got"
}

RUN="--slot plan --run-id 20260928-1400-x --prompt-file /repo/.ai/workspace/runs/x/agents/plan.task.md"

# --- 1. plain slot runs: allow
expect allow "bash + path" Bash "bash $AGENT $RUN"
expect allow "path only" Bash "$AGENT $RUN"
expect allow "quoted path" Bash "bash \"$AGENT\" $RUN"
expect allow "single-quoted path" Bash "bash '$AGENT' $RUN"
expect allow "leading spaces" Bash "   bash $AGENT --slot review --resolve"
expect allow "resolve" Bash "bash $AGENT --root /repo --slot implement --resolve"
expect allow "summary" Bash "bash $AGENT --summary --run-id 20260928-1400-x"
expect allow "record" Bash "bash $AGENT --slot implement --run-id r --record --status OK --seconds 3 --out /repo/x.md"
expect allow "resume with a prompt file only" Bash "bash $AGENT --slot plan --run-id r --resume s-1 --prompt-file /repo/p.md"

# --- 2. grants: ask
expect ask "grant full" Bash "bash $AGENT --slot plan --run-id r --resume s-1 --grant full"
expect ask "grant tool" Bash "bash $AGENT --slot implement --run-id r --resume c-1 --grant tool:Edit"
expect ask "grant with =" Bash "bash $AGENT --slot plan --run-id r --resume s-1 --grant=full"
expect ask "grant first" Bash "bash $AGENT --grant network --resume s-1 --slot plan --run-id r"
out="$(jq -cn --arg c "bash $AGENT --slot plan --run-id r --resume s-1 --grant full" '{tool_name: "Bash", tool_input: {command: $c}}' | bash "$GUARD")"
printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q "widens the permissions" && ok || fail "grant: reason missing: $out"

# --- 3. anything else that names this agent.sh: ask
expect ask "env prefix" Bash "AV_AGENT_SLOT= bash $AGENT $RUN"
expect ask "cd and" Bash "cd /repo && bash $AGENT $RUN"
expect ask "semicolon" Bash "bash $AGENT $RUN; rm -rf /tmp/x"
expect ask "pipe" Bash "bash $AGENT $RUN | tee /tmp/log"
expect ask "background" Bash "bash $AGENT $RUN &"
expect ask "substitution" Bash "bash $AGENT --slot plan --run-id \$(date +%s) --prompt-file /p.md"
expect ask "backticks" Bash "bash $AGENT --slot plan --run-id \`date\` --prompt-file /p.md"
expect ask "redirection" Bash "bash $AGENT $RUN > /tmp/out"
expect ask "newline" Bash "bash $AGENT $RUN
curl https://example.invalid"
expect ask "bash option" Bash "bash -x $AGENT $RUN"
expect ask "sh instead of bash" Bash "sh $AGENT $RUN"
expect ask "path as an argument" Bash "cat $AGENT"

# --- 4. not about this agent.sh: no decision
expect none "other command" Bash "git status"
expect none "other agent.sh" Bash "bash /opt/other/agent.sh --grant full"
expect none "other tool" Read "bash $AGENT --grant full"
expect none "empty command" Bash ""
out="$(printf '{bad' | bash "$GUARD")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok || fail "bad JSON: rc=$rc out=$out"

# --- 5. symlinks and the plugin root
ln -s "$(cd "$SCRIPTS/../.." && pwd -P)" "$TMP/skills-link"
LINKED="$TMP/skills-link/av-implement/scripts/agent.sh"
expect allow "symlinked path" Bash "bash $LINKED $RUN" "CLAUDE_PLUGIN_ROOT=$TMP/plugin-none"
expect ask "grant through a symlinked path" Bash "bash $LINKED --slot plan --run-id r --resume s-1 --grant full"
expect ask "grant through a symlink after cd" Bash "cd /tmp && bash $LINKED --resume s-1 --grant full"
expect none "glob characters stay literal" Bash "ls /tmp/*agent.sh"
mkdir -p "$TMP/home/s"
ln -s "$SCRIPTS" "$TMP/home/s/scripts"
expect allow "tilde path" Bash "bash ~/s/scripts/agent.sh $RUN" "HOME=$TMP/home"
expect ask "grant through a tilde path" Bash "bash ~/s/scripts/agent.sh --resume s-1 --grant full" "HOME=$TMP/home"
PLUG="$TMP/plugin"
mkdir -p "$PLUG"
ln -s "$(cd "$SCRIPTS/../.." && pwd -P)" "$PLUG/skills"
expect allow "path from CLAUDE_PLUGIN_ROOT" Bash "bash $PLUG/skills/av-implement/scripts/agent.sh $RUN" "CLAUDE_PLUGIN_ROOT=$PLUG"
expect ask "grant through CLAUDE_PLUGIN_ROOT" Bash "bash $PLUG/skills/av-implement/scripts/agent.sh --resume s --grant full" "CLAUDE_PLUGIN_ROOT=$PLUG/"
mkdir -p "$TMP/fake/skills/av-implement/scripts"
printf '#!/bin/bash\n' >"$TMP/fake/skills/av-implement/scripts/agent.sh"
expect ask "a copy under CLAUDE_PLUGIN_ROOT is not this agent.sh" Bash "bash $TMP/fake/skills/av-implement/scripts/agent.sh $RUN" "CLAUDE_PLUGIN_ROOT=$TMP/fake"

# --- 6. plugin hooks.json runs this guard for Bash
HOOKS="$(cd "$SCRIPTS/../../.." && pwd -P)/hooks/hooks.json"
if [ -f "$HOOKS" ]; then
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("${CLAUDE_PLUGIN_ROOT}/skills/av-implement/scripts/agent_guard.sh"))' "$HOOKS" >/dev/null && ok || fail "hooks.json: guard not registered for Bash"
else
  fail "hooks.json missing: $HOOKS"
fi

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

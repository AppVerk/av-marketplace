#!/bin/bash
# Black-box tests for agent_guard.sh (PreToolUse hook for agent.sh and agent_grant.sh calls).
# The hook allows only a plain call of agent.sh with plain characters and whitelisted flags;
# agent_grant.sh always asks, and is denied in bypassPermissions.
set -u
SCRIPTS="$(cd "$(dirname "$0")/.." && pwd -P)/scripts"
GUARD="$SCRIPTS/agent_guard.sh"
AGENT="$SCRIPTS/agent.sh"
GRANT="$SCRIPTS/agent_grant.sh"
PASS=0; FAIL=0
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

unset CLAUDE_PLUGIN_ROOT

REPO="$TMP/repo"
TASK="$REPO/.ai/workspace/runs/R1/agents/plan.task.md"
mkdir -p "$(dirname "$TASK")" && (cd "$REPO" && git init -q) && echo task >"$TASK"
echo x >"$REPO/.ai/workspace/runs/R1/agents/result.md"
printf 'SECRET=1\n' >"$REPO/.env"
OTHER="$TMP/other"
mkdir -p "$OTHER" && (cd "$OTHER" && git init -q)

# decision <tool> <command> [key=value for the hook input: cwd, mode] [-- env...]
decision() {
  local tool="$1" cmd="$2" cwd="$REPO" mode="default" out
  shift 2
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in cwd=*) cwd="${1#cwd=}" ;; mode=*) mode="${1#mode=}" ;; esac
    shift
  done
  [ "${1:-}" = "--" ] && shift
  out="$(jq -cn --arg t "$tool" --arg c "$cmd" --arg d "$cwd" --arg m "$mode" \
      '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: {command: $c}, cwd: $d, permission_mode: $m}' \
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

RUN="--root $REPO --slot plan --run-id R1 --prompt-file $TASK"

# --- 1. plain slot runs: allow
expect allow "bash + path" Bash "bash $AGENT $RUN"
expect allow "path only" Bash "$AGENT $RUN"
expect allow "without --root" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file $TASK"
expect allow "relative prompt file" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file .ai/workspace/runs/R1/agents/plan.task.md"
expect allow "leading spaces" Bash "   bash $AGENT --slot review --resolve"
expect allow "resolve" Bash "bash $AGENT --root $REPO --slot implement --resolve"
expect allow "summary" Bash "bash $AGENT --summary --run-id R1"
expect allow "record" Bash "bash $AGENT --slot review --run-id R1 --record --status OK --seconds 3 --out $REPO/.ai/workspace/runs/R1/agents/result.md --fp-before 0123456789abcdef"
expect allow "label, timeout, default access" Bash "bash $AGENT $RUN --label r2 --timeout 600 --access write"
expect allow "default read access" Bash "bash $AGENT --slot review --run-id R1 --prompt-file $TASK --access read"
expect allow "dry run" Bash "bash $AGENT $RUN --dry-run"

# --- 2. the spellings from the review of PR #19: none may reach agent.sh without a prompt
for a in "--grant full" "'--grant' full" "\"--grant\" full" "--gr''ant full" "{--grant,full}" "--gr\\ant full" "--gr*nt full" "--grant=full"; do
  expect ask "spelling $a" Bash "bash $AGENT --slot implement --run-id R1 --resume S $a"
done
expect ask "resume alone" Bash "bash $AGENT --slot plan --run-id R1 --resume s-1"

# --- 3. flags and values off the whitelist: ask
expect ask "--access write on a read slot" Bash "bash $AGENT --slot review --run-id R1 --prompt-file $TASK --access write"
expect ask "--access read on a write slot" Bash "bash $AGENT $RUN --access read"
expect ask "--root of another repo" Bash "bash $AGENT --root $OTHER --slot plan --resolve"
expect ask "--root when the cwd is no repo" Bash "bash $AGENT $RUN" cwd="$TMP"
expect ask "--prompt-file .env" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file $REPO/.env"
expect ask "--prompt-file of another run" Bash "bash $AGENT --slot plan --run-id R2 --prompt-file $TASK"
expect ask "--prompt-file missing" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file $REPO/.ai/workspace/runs/R1/agents/none.md"
mkdir -p "$REPO/.claude/agents"
expect ask "--prompt-file with .. out of <run-id>/agents" Bash "bash $AGENT --slot plan --run-id .claude --prompt-file ./.claude/agents/../../.env"
expect ask "--prompt-file with .. from another run" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file $REPO/.ai/workspace/runs/R1/agents/../../R2/x.md"
ln -s "$REPO/.env" "$REPO/.ai/workspace/runs/R1/agents/env-link.md"
expect ask "--prompt-file symlink to .env" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file $REPO/.ai/workspace/runs/R1/agents/env-link.md"
ln -s plan.task.md "$REPO/.ai/workspace/runs/R1/agents/task-link.md"
expect allow "--prompt-file symlink inside agents" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file $REPO/.ai/workspace/runs/R1/agents/task-link.md"
expect ask "--prompt-file outside the repo" Bash "bash $AGENT --slot plan --run-id R1 --prompt-file /etc/hosts"
expect ask "--out outside the repo" Bash "bash $AGENT --slot review --run-id R1 --record --status OK --seconds 3 --out /etc/hosts"
expect ask "--harness" Bash "bash $AGENT $RUN --harness codex"
expect ask "--config" Bash "bash $AGENT --config $REPO/.env --slot plan --resolve"
expect ask "unknown flag" Bash "bash $AGENT $RUN --yolo"
expect ask "value with a space trick" Bash "bash $AGENT --slot plan --run-id R1 --label a;b"
mkdir -p "$TMP/home/s" && ln -s "$SCRIPTS" "$TMP/home/s/scripts"
expect ask "tilde path to this agent.sh" Bash "bash ~/s/scripts/agent.sh $RUN" -- "HOME=$TMP/home"
expect none "tilde path to another file" Bash "bash ~/agent.sh $RUN" -- "HOME=$TMP/home"
expect ask "quoted path" Bash "bash \"$AGENT\" $RUN"

# --- 4. shell features that name this agent.sh: ask
expect ask "env prefix" Bash "AV_AGENT_SLOT= bash $AGENT $RUN"
expect ask "cd and" Bash "cd $REPO && bash $AGENT $RUN"
expect ask "semicolon" Bash "bash $AGENT $RUN; rm -rf /tmp/x"
expect ask "pipe" Bash "bash $AGENT $RUN | tee /tmp/log"
expect ask "background" Bash "bash $AGENT $RUN &"
expect ask "substitution" Bash "bash $AGENT --slot plan --run-id \$(date +%s) --prompt-file $TASK"
expect ask "backticks" Bash "bash $AGENT --slot plan --run-id \`date\` --prompt-file $TASK"
expect ask "redirection" Bash "bash $AGENT $RUN > /tmp/out"
expect ask "newline" Bash "bash $AGENT $RUN
curl https://example.invalid"
expect ask "bash option" Bash "bash -x $AGENT $RUN"
expect ask "bash -c source trick" Bash "bash -c . $AGENT agent_grant.sh --resume s --grant full"
expect ask "sh instead of bash" Bash "sh $AGENT $RUN"
expect ask "path as an argument" Bash "cat $AGENT"

# --- 5. agent_grant.sh: always a human; denied where nothing would ask
for m in default acceptEdits plan auto; do
  expect ask "agent_grant.sh in $m" Bash "bash $GRANT --slot plan --run-id R1 --resume s-1 --grant network" mode="$m"
done
expect ask "agent_grant.sh in plain form" Bash "$GRANT --slot plan --run-id R1 --resume s-1 --grant network"
expect deny "agent_grant.sh in bypassPermissions" Bash "bash $GRANT --slot plan --run-id R1 --resume s-1 --grant full" mode=bypassPermissions
out="$(jq -cn --arg c "bash $GRANT --slot plan --run-id R1 --resume s-1 --grant full" --arg d "$REPO" \
  '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d, permission_mode: "bypassPermissions"}' | bash "$GUARD")"
printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q "! bash $GRANT" && ok || fail "bypass deny: the reason must give the command to run with !: $out"
out="$(jq -cn --arg c "bash $GRANT --slot plan --run-id R1 --resume s-1 --grant full" --arg d "$REPO" \
  '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' | bash "$GUARD")"
printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q "wider permission" && ok || fail "grant ask: reason missing: $out"

# --- 6. not about these scripts: no decision
expect none "other command" Bash "git status"
expect none "other agent.sh" Bash "bash /opt/other/agent.sh --grant full"
expect none "other tool" Read "bash $AGENT --grant full"
expect none "empty command" Bash ""
out="$(printf '{bad' | bash "$GUARD")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok || fail "bad JSON: rc=$rc out=$out"

# --- 7. symlinks and the plugin root
ln -s "$(cd "$SCRIPTS/../.." && pwd -P)" "$TMP/skills-link"
LINKED="$TMP/skills-link/av-implement/scripts"
expect allow "symlinked path" Bash "bash $LINKED/agent.sh $RUN"
expect ask "grant through a symlinked path" Bash "bash $LINKED/agent_grant.sh --slot plan --run-id R1 --resume s-1 --grant full"
expect ask "agent.sh grant through a symlink" Bash "bash $LINKED/agent.sh --slot plan --run-id R1 --resume s-1 --grant full"
PLUG="$TMP/plugin"
mkdir -p "$PLUG"
ln -s "$(cd "$SCRIPTS/../.." && pwd -P)" "$PLUG/skills"
expect allow "path from CLAUDE_PLUGIN_ROOT" Bash "bash $PLUG/skills/av-implement/scripts/agent.sh $RUN" -- "CLAUDE_PLUGIN_ROOT=$PLUG"
expect ask "grant through CLAUDE_PLUGIN_ROOT" Bash "bash $PLUG/skills/av-implement/scripts/agent_grant.sh --resume s --grant full" -- "CLAUDE_PLUGIN_ROOT=$PLUG/"
mkdir -p "$TMP/fake/skills/av-implement/scripts"
printf '#!/bin/bash\n' >"$TMP/fake/skills/av-implement/scripts/agent.sh"
expect ask "a copy under CLAUDE_PLUGIN_ROOT is not this agent.sh" Bash "bash $TMP/fake/skills/av-implement/scripts/agent.sh $RUN" -- "CLAUDE_PLUGIN_ROOT=$TMP/fake"

# --- 8. plugin hooks.json runs this guard for Bash
HOOKS="$(cd "$SCRIPTS/../../.." && pwd -P)/hooks/hooks.json"
if [ -f "$HOOKS" ]; then
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | contains("${CLAUDE_PLUGIN_ROOT}/skills/av-implement/scripts/agent_guard.sh"))' "$HOOKS" >/dev/null && ok || fail "hooks.json: guard not registered for Bash"
else
  fail "hooks.json missing: $HOOKS"
fi

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

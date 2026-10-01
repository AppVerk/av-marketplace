#!/bin/bash
# Black-box tests for gate.sh.
# Builds a temporary repo with a config and checks statuses, exit codes and evidence.
set -u
GATE="$(cd "$(dirname "$0")/.." && pwd)/scripts/gate.sh"
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
echo a >a.txt
cat >.ai/av.config.json <<'EOF'
{"version":1,"paths":{"workspace":".ai/workspace"},
 "validation":{"commands":{
   "ok":{"run":"echo BUILD SUCCEEDED","expect":"BUILD SUCCEEDED"},
   "noexpect":{"run":"echo hello","expect":"BUILD SUCCEEDED"},
   "bad":{"run":"echo boom; exit 3"},
   "env":{"run":"echo x","precheck":"false","needs":"docker compose up"},
   "slow":{"run":"sleep 20","timeoutSec":1},
   "down":{"run":"exit 2","notRunExitCodes":[2],"needs":"docker"},
   "opt":{"run":"echo x","precheck":"false","optional":true},
   "build":{"run":"echo BUILT"},
   "ui":{"run":"test -n \"$UI_SUITE\" && echo \"DEVICE_OK $UI_SUITE\"","expect":"DEVICE_OK","covers":["build"]},
   "sub":{"run":"pwd","cwd":"sub"}
 },"gates":{"quick":["ok"],"all":["ok","noexpect","bad","env","slow"],"broken":["ghost"],
   "downg":["down"],"optg":["ok","opt"],"full":["build","ui"]}}}
EOF
mkdir -p sub
git add -A && git commit -qm init

# --- 1. --list prints commands and reports a broken gate
out="$(bash "$GATE" --list)"; rc=$?
has "$out" "COMMAND ok: echo BUILD SUCCEEDED expect='BUILD SUCCEEDED'" && ok || fail "list: command ok with expect missing"
has "$out" "CONFIG_ERROR gate 'broken' points to unknown command 'ghost'" && ok || fail "list: broken error missing"
[ "$rc" -eq 2 ] && ok || fail "list: code $rc instead of 2"

# --- 2. a healthy gate runs despite another broken gate
out="$(bash "$GATE" --gate quick --run-id r1)"; rc=$?
has "$out" "WARNING gate 'broken'" && ok || fail "quick: broken warning missing"
has "$out" "CHECK ok PASS" && ok || fail "quick: ok not PASS"
has "$out" "GATE quick PASS run=r1" && ok || fail "quick: GATE PASS missing"
[ "$rc" -eq 0 ] && ok || fail "quick: code $rc"
[ -f .ai/workspace/runs/r1/evidence.json ] && ok || fail "quick: evidence.json missing"

# --- 3. status FRESH, then STALE after a file change
out="$(bash "$GATE" --status --run-id r1)"; rc=$?
has "$out" "CHECK ok PASS FRESH" && ok || fail "status: FRESH missing"
[ "$rc" -eq 0 ] && ok || fail "status fresh: code $rc"
echo b >>a.txt
out="$(bash "$GATE" --status --run-id r1)"; rc=$?
has "$out" "CHECK ok PASS STALE" && ok || fail "status: STALE missing after change"
[ "$rc" -eq 1 ] && ok || fail "status stale: code $rc"
git checkout -q a.txt

# --- 4. FAIL: missing text, exit code, timeout; NOT_RUN from precheck
out="$(bash "$GATE" --gate all --run-id r2)"; rc=$?
has "$out" "CHECK noexpect FAIL" && has "$out" "expected text 'BUILD SUCCEEDED' not found" && ok || fail "all: noexpect"
has "$out" "CHECK bad FAIL" && has "$out" "(exit code 3)" && ok || fail "all: bad"
has "$out" "CHECK env NOT_RUN" && has "$out" "requires: docker compose up" && ok || fail "all: env"
has "$out" "CHECK slow FAIL" && has "$out" "(timeout 1s)" && ok || fail "all: slow"
has "$out" "GATE all FAIL" && ok || fail "all: GATE FAIL missing"
[ "$rc" -eq 1 ] && ok || fail "all: code $rc"
jq -e '.checks.bad.tail | index("boom") != null' .ai/workspace/runs/r2/evidence.json >/dev/null && ok || fail "all: log tail missing in evidence"

# --- 5. notRunExitCodes gives NOT_RUN and INCOMPLETE
out="$(bash "$GATE" --gate downg --run-id r3)"; rc=$?
has "$out" "CHECK down NOT_RUN" && ok || fail "down: not NOT_RUN"
has "$out" "GATE downg INCOMPLETE" && ok || fail "down: not INCOMPLETE"
[ "$rc" -eq 3 ] && ok || fail "down: code $rc"

# --- 6. optional command: SKIPPED does not break the gate
out="$(bash "$GATE" --gate optg --run-id r4)"; rc=$?
has "$out" "CHECK opt SKIPPED" && ok || fail "opt: not SKIPPED"
has "$out" "GATE optg PASS" && ok || fail "opt: gate not PASS"
[ "$rc" -eq 0 ] && ok || fail "opt: code $rc"

# --- 7. covers + --env: ui covers build
out="$(bash "$GATE" --gate full --env UI_SUITE=LoginTests --run-id r5)"; rc=$?
has "$out" "CHECK ui PASS" && ok || fail "full: ui not PASS"
has "$out" "CHECK build PASS 0s (covered by ui)" && ok || fail "full: build not covered"
has "$out" "RUN build" && fail "full: build ran despite coverage" || ok
[ "$rc" -eq 0 ] && ok || fail "full: code $rc"

# --- 8. without the parameter ui fails and build runs on its own
out="$(bash "$GATE" --gate full --run-id r6)"; rc=$?
has "$out" "CHECK ui FAIL" && ok || fail "full without env: ui not FAIL"
has "$out" "RUN build" && ok || fail "full without env: build did not run"
[ "$rc" -eq 1 ] && ok || fail "full without env: code $rc"

# --- 9. baseline writes a separate file
out="$(bash "$GATE" --baseline --only ok --run-id r7)"; rc=$?
has "$out" "BASELINE ok PASS" && ok || fail "baseline: BASELINE line missing"
[ -f .ai/workspace/runs/r7/baseline.json ] && ok || fail "baseline: baseline.json missing"
out="$(bash "$GATE" --status --run-id r7)"
has "$out" "BASELINE ok PASS baseline head=" && ok || fail "baseline: baseline status line missing"

# --- 10. command cwd
out="$(bash "$GATE" --only sub --run-id r8)"
grep -q "/sub$" .ai/workspace/runs/r8/sub.sub.log && ok || fail "cwd: command not in directory sub"

# --- 11. --root and --config outside the repo, run from another directory
cp .ai/av.config.json "$TMP/proposed.json"
out="$(cd /tmp && bash "$GATE" --root "$REPO" --config "$TMP/proposed.json" --list)"; rc=$?
has "$out" "GATE quick: ok" && ok || fail "root/config: gate quick missing"

# --- 12. argument errors and missing config
out="$(bash "$GATE" --gate nope)"; rc=$?
has "$out" "CONFIG_ERROR unknown gate 'nope'" && [ "$rc" -eq 2 ] && ok || fail "unknown gate"
out="$(bash "$GATE" --gate broken)"; rc=$?
has "$out" "CONFIG_ERROR gate 'broken' has invalid commands: ghost" && [ "$rc" -eq 2 ] && ok || fail "broken gate"
out="$(bash "$GATE" --gate quick --env FOO)"; rc=$?
has "$out" "CONFIG_ERROR --env requires KEY=VALUE" && [ "$rc" -eq 2 ] && ok || fail "bad --env"
out="$(cd "$TMP" && bash "$GATE" --gate quick)"; rc=$?
has "$out" "CONFIG_ERROR config not found" && [ "$rc" -eq 2 ] && ok || fail "config missing"

# --- 12b. precheck quotes itself in the reason; --list catches syntax errors and a missing script
cfg2="$TMP/cfg2.json"
jq '.validation.commands += {"pc": {"run": "echo x", "precheck": "true && test -d /does/not/exist && true"},
                               "syn": {"run": "echo (("}, "miss": {"run": "scripts/missing.sh"}}
    | .validation.gates += {"pcg": ["pc"]} | del(.validation.gates.broken)' .ai/av.config.json >"$cfg2"
out="$(bash "$GATE" --config "$cfg2" --gate pcg --run-id r10)"
has "$out" "precheck failed: true && test -d /does/not/exist && true" && ok || fail "precheck: text missing in reason: $out"
# --- 12b2. review of PR #19: no xtrace in prechecks, one time budget, reuse of direct PASS only
jq '.validation.commands += {
      "canary":  {"run": "echo OK", "precheck": "test -n \"$REVIEW_FAKE_SECRET\" && test -d missing-runtime"},
      "canaryp": {"run": "echo OK", "precheck": "test -n \"$REVIEW_FAKE_SECRET\" && test -d missing-runtime", "parallel": true},
      "pfp":     {"run": "echo RAN", "precheck": "false | true"},
      "cui":     {"run": "echo UI", "covers": ["cbuild"]},
      "cbuild":  {"run": "echo DIRECT_BUILD; exit 7"},
      "direct":  {"run": "echo D"},
      "slowpre": {"run": "echo RAN", "precheck": "sleep 7", "timeoutSec": 1},
      "slowprep": {"run": "echo RAN", "precheck": "sleep 7", "timeoutSec": 1, "parallel": true},
      "budget":  {"run": "sleep 3; echo DONE", "precheck": "sleep 2", "timeoutSec": 3},
      "budok":   {"run": "echo DONE", "precheck": "sleep 1", "timeoutSec": 5}}
    | .validation.gates += {"cang": ["canary", "canaryp"], "pfpg": ["pfp"], "cov": ["cui", "cbuild"], "dirg": ["direct"],
                            "spg": ["slowpre", "slowprep"], "budg": ["budget"], "budokg": ["budok"]}
    | del(.validation.gates.broken)' .ai/av.config.json >"$TMP/c12.json"
CANARY=NOT_A_REAL_SECRET_CANARY
out="$(bash "$GATE" --config "$TMP/c12.json" --gate cang --run-id r40 --env REVIEW_FAKE_SECRET=$CANARY 2>&1)"; rc=$?
has "$out" "CHECK canary NOT_RUN" && has "$out" "CHECK canaryp NOT_RUN" && [ "$rc" -eq 3 ] && ok || fail "canary --env: prechecks did not fail ($rc): $out"
has "$out" "precheck failed: test -n \"\$REVIEW_FAKE_SECRET\" && test -d missing-runtime" && ok || fail "canary: the reason does not quote the precheck: $out"
has "$out" "$CANARY" && fail "canary --env: value in the gate output" || ok
grep -rq "$CANARY" .ai/workspace/runs/r40 && fail "canary --env: value in a log or evidence: $(grep -rl "$CANARY" .ai/workspace/runs/r40)" || ok
out="$(REVIEW_FAKE_SECRET=$CANARY bash "$GATE" --config "$TMP/c12.json" --gate cang --run-id r41 2>&1)"; rc=$?
has "$out" "CHECK canary NOT_RUN" && has "$out" "CHECK canaryp NOT_RUN" && ok || fail "canary inherited: prechecks did not fail: $out"
{ has "$out" "$CANARY" || grep -rq "$CANARY" .ai/workspace/runs/r41; } && fail "canary inherited: value in output, a log or evidence" || ok
out="$(bash "$GATE" --config "$TMP/c12.json" --gate pfpg --run-id r41)"
has "$out" "CHECK pfp NOT_RUN" && ! has "$out" "RUN pfp" && ok || fail "precheck: pipefail lost: $out"

out="$(bash "$GATE" --config "$TMP/c12.json" --gate cov --run-id r42)"
has "$out" "CHECK cbuild PASS 0s (covered by cui)" && ok || fail "covered: setup: $out"
out="$(bash "$GATE" --config "$TMP/c12.json" --only cbuild --reuse-fresh --run-id r42)"; rc=$?
has "$out" "reused" && fail "covered: a covered result was reused on its own: $out" || ok
has "$out" "RUN cbuild" && has "$out" "CHECK cbuild FAIL" && [ "$rc" -eq 1 ] && ok || fail "covered: the command did not run without its covering command ($rc): $out"
jq -e '.checks.cbuild | .reused != true and .log != "x" and .status == "FAIL"' .ai/workspace/runs/r42/evidence.json >/dev/null && ok || fail "covered: evidence claims reuse or a fake log"
out="$(bash "$GATE" --config "$TMP/c12.json" --gate cov --reuse-fresh --run-id r42b)"
out="$(bash "$GATE" --config "$TMP/c12.json" --gate cov --reuse-fresh --run-id r42b)"
has "$out" "CHECK cui PASS 0s (FRESH evidence reused" && has "$out" "CHECK cbuild PASS 0s (covered by cui)" && ok || fail "covered: the whole gate no longer reuses and covers: $out"
bash "$GATE" --config "$TMP/c12.json" --gate dirg --run-id r43 >/dev/null
rm -f .ai/workspace/runs/r43/dirg.direct.log
out="$(bash "$GATE" --config "$TMP/c12.json" --gate dirg --reuse-fresh --run-id r43)"
has "$out" "RUN direct" && ! has "$out" "reused" && ok || fail "deleted log: evidence still reused: $out"
out="$(bash "$GATE" --config "$TMP/c12.json" --gate dirg --reuse-fresh --run-id r43)"
has "$out" "CHECK direct PASS 0s (FRESH evidence reused: .ai/workspace/runs/r43/dirg.direct.log)" && ok || fail "direct: valid evidence not reused: $out"

t0="$(date +%s)"
out="$(bash "$GATE" --config "$TMP/c12.json" --gate spg --run-id r44)"; rc=$?
took=$(( $(date +%s) - t0 ))
has "$out" "CHECK slowpre NOT_RUN" && has "$out" "precheck timeout after 1s" && ok || fail "precheck timeout: $out"
has "$out" "CHECK slowprep NOT_RUN" && ok || fail "precheck timeout in the background: $out"
has "$out" "RUN slowpre" && fail "precheck timeout: run started" || ok
has "$out" "RUN slowprep" && fail "precheck timeout in the background: run started" || ok
[ "$rc" -eq 3 ] && [ "$took" -lt 7 ] && ok || fail "precheck timeout: code $rc, took ${took}s"
pgrep -f "sleep 7" >/dev/null && fail "precheck timeout: precheck process alive" || ok
out="$(bash "$GATE" --config "$TMP/c12.json" --gate budg --run-id r45)"; rc=$?
has "$out" "CHECK budget FAIL" && has "$out" "(timeout 3s)" && [ "$rc" -eq 1 ] && ok || fail "budget: precheck time not counted ($rc): $out"
out="$(bash "$GATE" --config "$TMP/c12.json" --gate budokg --run-id r46)"; rc=$?
has "$out" "CHECK budok PASS" && [ "$rc" -eq 0 ] && jq -e '.checks.budok.duration >= 1' .ai/workspace/runs/r46/evidence.json >/dev/null && ok || fail "budget: duration without the precheck ($rc): $out"

out="$(bash "$GATE" --config "$cfg2" --list)"; rc=$?
has "$out" "command 'syn': syntax error in field run" && [ "$rc" -eq 2 ] && ok || fail "list: syntax error missing"
has "$out" "WARNING command miss: file scripts/missing.sh not found" && ok || fail "list: script warning missing"
cfg3="$TMP/cfg3.json"
jq '.validation.commands = {"envp": {"run": "FOO=1 BAR=2 echo ok"}} | .validation.gates = {"g": ["envp"]}' .ai/av.config.json >"$cfg3"
out="$(bash "$GATE" --config "$cfg3" --list)"
has "$out" "WARNING" && fail "list: false warning for a variable prefix" || ok
mkdir -p .ai/workspace/tools && printf '#!/bin/bash\n' >.ai/workspace/tools/present.sh
cfg4="$TMP/cfg4.json"
jq '.validation.commands = {
      "subst": {"run": "c=$(bash .ai/scripts/x.sh svc) && docker exec \"$c\" make test"},
      "quoted": {"run": "x=\"$(echo \"a b\" | tr a b)\"; echo \"$x\""},
      "single": {"run": "A=\u0027a b\u0027 B=\"c d\" echo ok"},
      "nested": {"run": "X=$(echo $(echo \"q )\") `echo a b`) Y=${Z:-a b} echo ok"},
      "chain": {"run": "echo ok", "precheck": "c=$(docker ps -q --filter \"name=db x\") && test -n \"$c\""},
      "abs": {"run": "/usr/bin/env true"},
      "var": {"run": "$HOME/bin/tool --x"},
      "okpath": {"run": "A=$(echo \"1 2\") .ai/workspace/tools/present.sh --flag"}
    } | .validation.gates = {"g": ["subst"]}' .ai/av.config.json >"$cfg4"
out="$(bash "$GATE" --config "$cfg4" --list)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "list: assignments with substitution give code $rc: $out"
has "$out" "WARNING" && fail "list: false file warning for assignments and non-path words: $out" || ok
cfg5="$TMP/cfg5.json"
jq '.validation.commands = {
      "m1": {"run": "A=\"x y\" scripts/missing1.sh --flag"},
      "m2": {"run": "X=$(echo \"a ) b\") ./scripts/missing2.sh"},
      "m3": {"run": "echo ok", "precheck": "B=\u0027p q\u0027 C=$(printf \"%s\" \"$(echo r s)\") tools/missing3.sh && true"}
    } | .validation.gates = {"g": ["m1"]}' .ai/av.config.json >"$cfg5"
out="$(bash "$GATE" --config "$cfg5" --list)"
has "$out" "WARNING command m1: file scripts/missing1.sh not found" && ok || fail "list: missing script after a quoted assignment: $out"
has "$out" "WARNING command m2: file ./scripts/missing2.sh not found" && ok || fail "list: missing script after a substitution: $out"
has "$out" "WARNING command m3: file tools/missing3.sh not found" && ok || fail "list: missing precheck script after nested quotes: $out"
[ "$(printf '%s\n' "$out" | grep -c '^WARNING')" -eq 3 ] && ok || fail "list: exactly three file warnings: $out"

# --- 12c. separate logs for baseline and gates, lock, evidence reuse
bash "$GATE" --baseline --gate quick --run-id r11 >/dev/null
bash "$GATE" --gate quick --run-id r11 >/dev/null
[ -f .ai/workspace/runs/r11/baseline.quick.ok.log ] && [ -f .ai/workspace/runs/r11/quick.ok.log ] && ok || fail "logs: separate files missing"
jq -e '.checks.ok.log | endswith("baseline.quick.ok.log")' .ai/workspace/runs/r11/baseline.json >/dev/null && ok || fail "logs: baseline points to another log"
mkdir -p .ai/workspace/runs/r11/.lock && echo "full pid 1" >.ai/workspace/runs/r11/.lock/owner
out="$(bash "$GATE" --gate quick --run-id r11)"; rc=$?
has "$out" "BUSY another gate of run r11" && [ "$rc" -eq 4 ] && ok || fail "lock: BUSY missing ($rc)"
out="$(bash "$GATE" --status --run-id r11)"; rc=$?
has "$out" "BUSY gate in progress: full pid 1" && [ "$rc" -eq 4 ] && ok || fail "status: BUSY missing ($rc)"
rm -rf .ai/workspace/runs/r11/.lock
out="$(bash "$GATE" --gate quick --reuse-fresh --run-id r11)"; rc=$?
has "$out" "CHECK ok PASS 0s (FRESH evidence reused" && [ "$rc" -eq 0 ] && ok || fail "reuse: evidence not used"
has "$out" "RUN ok" && fail "reuse: command ran despite evidence" || ok
echo c >>a.txt
out="$(bash "$GATE" --gate quick --reuse-fresh --run-id r11)"
has "$out" "RUN ok" && ok || fail "reuse: old evidence used after a code change"
git checkout -q a.txt
[ ! -d .ai/workspace/runs/r11/.lock ] && ok || fail "lock: not released after the gate"

# --- 12e. pipefail: a failing program anywhere in a pipeline fails the command (PR #19, point 9)
cfgp="$TMP/pipe.json"
jq '.validation.commands += {
      "pipebad": {"run": "false | tail -1"},
      "pipegood": {"run": "true | tail -1"},
      "pipeexp": {"run": "echo UNIT_OK; exit 1 | cat", "expect": "UNIT_OK"},
      "pipepre": {"run": "echo ran", "precheck": "false | true"},
      "owner": {"run": "cat .ai/workspace/runs/r31/.lock/owner"}}
    | .validation.gates += {"pbad": ["pipebad"], "pgood": ["pipegood"], "pexp": ["pipeexp"], "ppre": ["pipepre"], "owner": ["owner"]}' \
  .ai/av.config.json >"$cfgp"
out="$(bash "$GATE" --config "$cfgp" --gate pbad --run-id r30)"; rc=$?
has "$out" "CHECK pipebad FAIL" && [ "$rc" -eq 1 ] && ok || fail "pipefail: false | tail must FAIL ($rc): $out"
out="$(bash "$GATE" --config "$cfgp" --gate pgood --run-id r30)"; rc=$?
has "$out" "CHECK pipegood PASS" && [ "$rc" -eq 0 ] && ok || fail "pipefail: true | tail must PASS ($rc): $out"
out="$(bash "$GATE" --config "$cfgp" --gate pexp --run-id r30)"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "pipefail: expect text printed but a program in the pipeline failed ($rc): $out"
out="$(bash "$GATE" --config "$cfgp" --gate ppre --run-id r30)"; rc=$?
has "$out" "CHECK pipepre NOT_RUN" && [ "$rc" -eq 3 ] && ok || fail "pipefail: a failing precheck pipeline must give NOT_RUN ($rc): $out"

# --- 12f. stale lock after kill -9 or a reboot is taken over (PR #19, point 11)
L=.ai/workspace/runs/r31/.lock
bash "$GATE" --gate quick --run-id r31 >/dev/null
sleep 0 & dead=$!; wait "$dead" 2>/dev/null
mkdir -p "$L" ".ai/workspace/runs/r31/.bg.$dead" && echo "quick pid $dead" >"$L/owner"
out="$(bash "$GATE" --status --run-id r31)"; rc=$?
has "$out" "WARNING stale lock: quick pid $dead is not running" && [ "$rc" -ne 4 ] && ok || fail "stale lock: --status must warn, not BUSY ($rc): $out"
out="$(bash "$GATE" --gate quick --run-id r31)"; rc=$?
has "$out" "WARNING stale lock of run r31 (quick pid $dead)" && has "$out" "GATE quick PASS" && [ "$rc" -eq 0 ] && ok || fail "stale lock: not taken over ($rc): $out"
[ ! -d "$L" ] && [ ! -d ".ai/workspace/runs/r31/.bg.$dead" ] && ok || fail "stale lock: lock or .bg of the dead gate left"
mkdir -p "$L" && echo "quick pid $$ started Mon Jan  1 00:00:00 2001" >"$L/owner"
out="$(bash "$GATE" --gate quick --run-id r31)"; rc=$?
has "$out" "WARNING stale lock" && [ "$rc" -eq 0 ] && ok || fail "reused pid (other start time): not taken over ($rc): $out"
mkdir -p "$L" && echo "quick pid $$ started $(LC_ALL=C TZ=UTC0 ps -o lstart= -p $$ | sed 's/[[:space:]]*$//')" >"$L/owner"
out="$(bash "$GATE" --gate quick --run-id r31)"; rc=$?
has "$out" "BUSY another gate of run r31" && [ "$rc" -eq 4 ] && ok || fail "live lock with the same start time must stay BUSY ($rc): $out"
echo "quick" >"$L/owner"
out="$(bash "$GATE" --gate quick --run-id r31)"; rc=$?
[ "$rc" -eq 4 ] && ok || fail "lock without a pid (just made) must stay BUSY ($rc)"
rm -rf "$L"
fake_ps="$TMP/nops"; mkdir -p "$fake_ps"; printf '#!/bin/sh\nexit 1\n' >"$fake_ps/ps"; chmod +x "$fake_ps/ps"
mkdir -p "$L" && echo "quick pid $dead" >"$L/owner"
out="$(PATH="$fake_ps:$PATH" bash "$GATE" --gate quick --run-id r31)"; rc=$?
[ "$rc" -eq 4 ] && ok || fail "ps unusable: a lock must never be taken over ($rc): $out"
rm -rf "$L"
# --- 12f2. review of PR #19: start times do not depend on LANG or TZ, one gate at a time takes a
# stale lock over, and the takeover stops what the dead gate left running
jq '.validation.commands += {"slow": {"run": "sleep 4"}, "slow2": {"run": "sleep 2"},
      "bgslow": {"run": "sleep 41; echo LATE >>late.txt", "parallel": true}, "fgslow": {"run": "sleep 43"}}
    | .validation.gates += {"slowg": ["slow"], "slow2g": ["slow2"], "leftg": ["bgslow", "fgslow"]}
    | del(.validation.gates.broken)' .ai/av.config.json >"$TMP/lock.json"
wait_for() { local n=0; while ! eval "$1" && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done; eval "$1"; }
TZ=Asia/Tokyo LC_ALL=pl_PL.UTF-8 LANG=pl_PL.UTF-8 bash "$GATE" --config "$TMP/lock.json" --gate slowg --run-id r32 >/dev/null 2>&1 &
g1=$!
wait_for 'grep -q " started " .ai/workspace/runs/r32/.lock/owner 2>/dev/null'
out="$(TZ=America/New_York LC_ALL=en_US.UTF-8 bash "$GATE" --config "$TMP/lock.json" --gate slowg --run-id r32)"; rc=$?
has "$out" "BUSY another gate of run r32" && [ "$rc" -eq 4 ] && ok || fail "lock: another TZ or LANG took a live lock over ($rc): $out"
wait "$g1" 2>/dev/null

L=.ai/workspace/runs/r33/.lock
sleep 0 & dead=$!; wait "$dead" 2>/dev/null
sleep 30 & holder=$!
mkdir -p "$L" "$L.takeover" && echo "quick pid $dead" >"$L/owner"
printf '%s %s\n' "$holder" "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$holder" | sed 's/[[:space:]]*$//')" >"$L.takeover/pid"
out="$(bash "$GATE" --gate quick --run-id r33)"; rc=$?
has "$out" "BUSY" && [ "$rc" -eq 4 ] && grep -q "quick pid $dead" "$L/owner" && ok || fail "takeover: a second gate took over during another takeover ($rc): $out"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
out="$(bash "$GATE" --gate quick --run-id r33)"; rc=$?
has "$out" "WARNING stale lock of run r33" && [ "$rc" -eq 0 ] && [ ! -d "$L.takeover" ] && ok || fail "takeover: a takeover left by a dead gate blocks for ever ($rc): $out"

for i in 1 2 3; do
  rm -rf .ai/workspace/runs/r34
  mkdir -p .ai/workspace/runs/r34/.lock && echo "quick pid $dead" >.ai/workspace/runs/r34/.lock/owner
  for j in 1 2 3 4; do bash "$GATE" --config "$TMP/lock.json" --gate slow2g --run-id r34 >"$TMP/race.$j" 2>&1 & done
  wait
  ran="$(grep -l "GATE slow2g PASS" "$TMP"/race.* | wc -l | tr -d ' ')"
  busy="$(grep -l "^BUSY" "$TMP"/race.* | wc -l | tr -d ' ')"
  [ "$ran" -eq 1 ] && [ "$busy" -eq 3 ] && ok || fail "takeover race $i: $ran gates ran, $busy were BUSY"
done

rm -f late.txt
bash "$GATE" --config "$TMP/lock.json" --gate leftg --run-id r35 >/dev/null 2>&1 &
g2=$!
wait_for 'pgrep -f "sleep 41" >/dev/null && pgrep -f "sleep 43" >/dev/null'
kill -9 "$g2" 2>/dev/null; wait "$g2" 2>/dev/null
sleep 0.5
pgrep -f "sleep 41" >/dev/null && ok || fail "left behind: setup: the background command did not outlive kill -9"
out="$(bash "$GATE" --gate quick --run-id r35)"; rc=$?
has "$out" "WARNING stale lock of run r35" && [ "$rc" -eq 0 ] && ok || fail "left behind: no takeover ($rc): $out"
sleep 0.5
pgrep -f "sleep 41" >/dev/null && fail "left behind: a background command of the dead gate still runs" || ok
pgrep -f "sleep 43" >/dev/null && fail "left behind: the foreground command of the dead gate still runs" || ok
[ ! -f late.txt ] && ok || fail "left behind: the dead gate's command wrote after the takeover"
pkill -f "sleep 4[13]" 2>/dev/null; rm -f late.txt

bash "$GATE" --config "$cfgp" --gate owner --run-id r31 >/dev/null
grep -Eq '^owner pid [0-9]+ started [A-Z][a-z]{2} ' .ai/workspace/runs/r31/owner.owner.log && ok || fail "owner: pid and start time missing: $(cat .ai/workspace/runs/r31/owner.owner.log)"

# --- 12d. config field validation: models, git, roles, paths (R7)
good="$TMP/good.json"
jq 'del(.validation.gates.broken)
    | .agents = {"models": {"plan": "inherit", "implement": "opus", "review": "sonnet", "verify": "fable"}}
    | .git = {"commit": "on-request", "push": "never"}
    | .roles = [{"name": "data", "skill": "backend-data", "order": 1, "globs": ["src/api/**", "src/db/*.py", "!src/api/generated/**"]},
                {"name": "ui", "skill": "web-ui", "order": 2, "globs": ["src/ui/**"]}]
    | .generatedPaths = ["vendor/**"] | .unownedPaths = ["scripts/**"]' .ai/av.config.json >"$good"
out="$(bash "$GATE" --config "$good" --list)"; rc=$?
has "$out" "CONFIG_ERROR" && fail "validation: valid config rejected: $out" || ok
has "$out" "AV_DEV " && ok || fail "validation: AV_DEV line missing"
[ "$rc" -eq 0 ] && ok || fail "validation: valid config code $rc"
# Fields outside validation, paths and requires never stop a gate (review of PR #19):
# check_setup.sh checks them (test-check-setup.sh).
jq '.agents.models = {"implement": "opusplan", "review": "haiku"} | .agents.crossVendor = true
    | .git.commit = "always" | .roles = {"a": 1}' "$good" >"$TMP/fields.json"
out="$(bash "$GATE" --config "$TMP/fields.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR" && fail "fields: --list rejects fields outside the gates: $out" || ok
[ "$rc" -eq 0 ] && ok || fail "fields: --list code $rc"
out="$(bash "$GATE" --config "$TMP/fields.json" --gate quick --run-id r12)"; rc=$?
has "$out" "GATE quick PASS" && [ "$rc" -eq 0 ] && ok || fail "fields: a gate stopped by fields outside the gates ($rc): $out"
bad_case() {
  local filter="$1" expect="$2" desc="$3" o r
  jq "$filter" "$good" >"$TMP/bad.json"
  o="$(bash "$GATE" --config "$TMP/bad.json" --list)"; r=$?
  if has "$o" "CONFIG_ERROR $expect" && [ "$r" -eq 2 ]; then ok; else fail "validation $desc: code $r, output: $o"; fi
}
bad_case '.requires = "0.1.0"' "requires: expected an object" "requires not an object"
bad_case '.validation.gates.quick = "ok"' "gate 'quick': expected a non-empty array of command names" "gate as a string"
# run must be a non-blank string and timeoutSec a positive integer (review of PR #19, round 5)
bad_case '.validation.commands.ok.run = []' "command 'ok': run must be a non-blank string" "run as an empty array"
bad_case '.validation.commands.ok.run = "  "' "command 'ok': run must be a non-blank string" "run blank"
bad_case '.validation.commands.ok.run = ["echo", "x"]' "command 'ok': run must be a non-blank string" "run as an array of words"
bad_case '.validation.commands.ok.precheck = " "' "command 'ok': precheck must be a non-blank string" "precheck blank"
bad_case '.validation.commands.ok.timeoutSec = 1.5' "command 'ok': timeoutSec must be a positive integer (seconds)" "timeoutSec 1.5"
bad_case '.validation.commands.ok.timeoutSec = 0' "command 'ok': timeoutSec must be a positive integer (seconds)" "timeoutSec 0"
bad_case '.validation.commands.ok.timeoutSec = "5"' "command 'ok': timeoutSec must be a positive integer (seconds)" "timeoutSec as a string"
jq '.validation.commands.ok.run = [] | .validation.commands.ok.timeoutSec = 1.5' "$good" >"$TMP/badrun.json"
out="$(bash "$GATE" --config "$TMP/badrun.json" --gate quick --run-id r12h 2>/dev/null)"; rc=$?
has "$out" "CONFIG_ERROR commands with an invalid run, precheck or timeoutSec: ok" && [ "$rc" -eq 2 ] && ok || fail "gate with run []: did not stop before running ($rc): $out"
has "$out" "CHECK ok" && fail "gate with run []: a command ran: $out" || ok
[ ! -f .ai/workspace/runs/r12h/evidence.json ] && ok || fail "gate with run []: evidence written for a command that never ran"
jq '.validation.commands.ok.timeoutSec = 1.5' "$good" >"$TMP/badto.json"
out="$(bash "$GATE" --config "$TMP/badto.json" --only ok --run-id r12i 2>/dev/null)"; rc=$?
has "$out" "CONFIG_ERROR commands with an invalid run, precheck or timeoutSec: ok" && [ "$rc" -eq 2 ] && ok || fail "timeoutSec 1.5: not rejected before the run ($rc): $out"
has "$out" "timeout 1.5s" && fail "timeoutSec 1.5: the command was started and killed" || ok
bad_case '.validation.gates.quick = []' "gate 'quick': expected a non-empty array of command names" "empty gate"
bad_case '.validation.gates.quick = [3]' "gate 'quick': element 3 is not a command name" "gate element not a string"
bad_case '.validation.commands["unit tests"] = {"run": "exit 1"}' "command 'unit tests': name must use only letters, digits, _ . -" "command name with a space"
jq '.validation.gates.quick = "ok"' "$good" >"$TMP/bad.json"
out="$(bash "$GATE" --config "$TMP/bad.json" --gate quick --run-id r12)"; rc=$?
has "$out" "CONFIG_ERROR gate 'quick' must be a non-empty array of command names" && [ "$rc" -eq 2 ] && ok || fail "gate as a string: not a config error ($rc): $out"
has "$out" "GATE quick PASS" && fail "gate as a string passed" || ok
jq '.validation.gates.quick = []' "$good" >"$TMP/bad.json"
out="$(bash "$GATE" --config "$TMP/bad.json" --gate quick --run-id r12)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "empty gate: code $rc: $out"
jq '.validation.commands["unit tests"] = {"run": "echo FAILED; exit 1"} | .validation.commands.unit = {"run": "true"}
    | .validation.commands.tests = {"run": "true"} | .validation.gates.ws = ["unit tests"]' "$good" >"$TMP/ws.json"
out="$(bash "$GATE" --config "$TMP/ws.json" --gate ws --run-id r12)"; rc=$?
has "$out" "CONFIG_ERROR invalid command names: \"unit tests\"" && [ "$rc" -eq 2 ] && ok || fail "name with a space: not rejected ($rc): $out"
has "$out" "RUN unit" && fail "name with a space: split into words and ran 'unit'" || ok
out="$(bash "$GATE" --config "$TMP/ws.json" --only "unit tests" --run-id r12)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "--only with a space in the name: code $rc"
out="$(bash "$GATE" --only " , " --run-id r12)"; rc=$?
has "$out" "CONFIG_ERROR --only needs at least one command name" && [ "$rc" -eq 2 ] && ok || fail "--only without names: $rc $out"
jq '.validation.commands.sk = {"run": "exit 2", "notRunExitCodes": [2], "optional": true} | .validation.gates.skg = ["sk"]' "$good" >"$TMP/sk-only.json"
out="$(bash "$GATE" --config "$TMP/sk-only.json" --gate skg --run-id r12)"; rc=$?
has "$out" "GATE skg INCOMPLETE" && [ "$rc" -eq 3 ] && ok || fail "only SKIPPED: must not be PASS ($rc): $out"
mkdir -p .ai/workspace/runs/r12c && printf '{bad' >.ai/workspace/runs/r12c/evidence.json
out="$(bash "$GATE" --config "$good" --gate quick --run-id r12c)"; rc=$?
has "$out" "WARNING .ai/workspace/runs/r12c/evidence.json was unreadable; moved to" && ok || fail "corrupt evidence: no warning: $out"
has "$out" "GATE quick PASS" && jq -e '.checks.ok.status == "PASS"' .ai/workspace/runs/r12c/evidence.json >/dev/null && ok || fail "corrupt evidence: no fresh evidence written: $out"
ls .ai/workspace/runs/r12c/evidence.json.corrupt.* >/dev/null 2>&1 && ok || fail "corrupt evidence: the old file was not kept"
printf '{bad' >.ai/workspace/runs/r12c/evidence.json
out="$(bash "$GATE" --status --run-id r12c)"; rc=$?
has "$out" "WARNING .ai/workspace/runs/r12c/evidence.json is unreadable" && [ "$rc" -eq 1 ] && ok || fail "corrupt evidence: --status ($rc): $out"
rm -f .ai/workspace/runs/r12c/evidence.json

# Fingerprint: a git error is an error, never a constant value (review of PR #19)
out="$(GIT_DIR=/nonexistent bash "$GATE" --fingerprint)"; rc=$?
has "$out" "GIT_ERROR" && [ "$rc" -eq 2 ] && ok || fail "fingerprint: git error gave a value ($rc): $out"
has "$out" "FINGERPRINT" && fail "fingerprint: printed with a git error" || ok
out="$(GIT_DIR=/nonexistent bash "$GATE" --status --run-id r1)"; rc=$?
has "$out" "GIT_ERROR" && [ "$rc" -eq 2 ] && ok || fail "status: git error gave FRESH ($rc): $out"
has "$out" "PASS FRESH" && fail "status: FRESH without git" || ok
out="$(GIT_DIR=/nonexistent bash "$GATE" --gate quick --reuse-fresh --run-id r1)"; rc=$?
has "$out" "GIT_ERROR" && [ "$rc" -eq 2 ] && ok || fail "reuse: git error did not stop the gate ($rc): $out"
has "$out" "reused" && fail "reuse: evidence reused without git" || ok
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT/.ai" && cp .ai/av.config.json "$NOGIT/.ai/"
out="$(cd "$NOGIT" && bash "$GATE" --root "$NOGIT" --fingerprint)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "fingerprint outside git: code $rc: $out"
EMPTY="$TMP/nocommit"; mkdir -p "$EMPTY/.ai" && git -C "$EMPTY" init -q && cp .ai/av.config.json "$EMPTY/.ai/"
out="$(bash "$GATE" --root "$EMPTY" --fingerprint)"; rc=$?
has "$out" "GIT_ERROR" && [ "$rc" -eq 2 ] && ok || fail "fingerprint without a commit: $rc $out"

# Fingerprint: an untracked entry that is not a regular file (a dangling symlink, a nested
# repository such as a Claude Code worktree) is not a git error (review of PR #19, round 4)
LINKS="$TMP/links"; mkdir -p "$LINKS/.ai" && cp .ai/av.config.json .gitignore "$LINKS/" && mv "$LINKS/av.config.json" "$LINKS/.ai/"
git -C "$LINKS" init -q && git -C "$LINKS" add -A && git -C "$LINKS" -c user.email=t@t -c user.name=t commit -qm init
ln -s missing-target "$LINKS/zz_dangling"
out="$(bash "$GATE" --root "$LINKS" --fingerprint)"; rc=$?
has "$out" "FINGERPRINT" && [ "$rc" -eq 0 ] && ok || fail "fingerprint: a dangling untracked symlink is a git error ($rc): $out"
fp_link="$(printf '%s' "$out" | sed -n 's/^FINGERPRINT //p')"
rm "$LINKS/zz_dangling" && ln -s other-target "$LINKS/zz_dangling"
out="$(bash "$GATE" --root "$LINKS" --fingerprint)"
[ -n "$fp_link" ] && [ "$(printf '%s' "$out" | sed -n 's/^FINGERPRINT //p')" != "$fp_link" ] && ok || fail "fingerprint: a changed symlink target gives the same value: $out"
rm "$LINKS/zz_dangling"
mkdir -p "$LINKS/.claude/worktrees/wt" && git -C "$LINKS/.claude/worktrees/wt" init -q && echo w >"$LINKS/.claude/worktrees/wt/w.txt"
git -C "$LINKS/.claude/worktrees/wt" add -A && git -C "$LINKS/.claude/worktrees/wt" -c user.email=t@t -c user.name=t commit -qm w
out="$(cd "$LINKS" && bash "$GATE" --gate quick --run-id wt)"; rc=$?
has "$out" "GATE quick PASS" && [ "$rc" -eq 0 ] && ok || fail "gate: a nested repository under .claude/worktrees stops the gate ($rc): $out"
out="$(GIT_DIR=/nonexistent bash "$GATE" --root "$LINKS" --fingerprint)"; rc=$?
has "$out" "GIT_ERROR" && [ "$rc" -eq 2 ] && ok || fail "fingerprint: a real git error is no longer an error ($rc): $out"

# Evidence write: the verdict comes from this run, and a failed write is never a PASS
# (review of PR #19, round 4). The .tmp directory is the easiest way to make the write fail.
jq '.validation.commands += {"flip": {"run": "exit $(cat flip.code)"}} | .validation.gates += {"flipg": ["flip"]}' "$good" >"$TMP/flip.json"
echo 0 >flip.code
out="$(bash "$GATE" --config "$TMP/flip.json" --gate flipg --run-id M)"; rc=$?
has "$out" "GATE flipg PASS" && [ "$rc" -eq 0 ] && ok || fail "flip: first run not PASS ($rc): $out"
echo 1 >flip.code
mkdir .ai/workspace/runs/M/evidence.json.tmp
out="$(bash "$GATE" --config "$TMP/flip.json" --gate flipg --run-id M 2>/dev/null)"; rc=$?
has "$out" "CHECK flip FAIL" && ok || fail "flip: command failure not reported: $out"
has "$out" "GATE flipg PASS" && fail "flip: a failed evidence write gave PASS: $out" || ok
has "$out" "WRITE_ERROR could not write .ai/workspace/runs/M/evidence.json" && [ "$rc" -eq 2 ] && ok || fail "flip: no WRITE_ERROR with code 2 ($rc): $out"
jq -e '.checks.flip.status == "PASS"' .ai/workspace/runs/M/evidence.json >/dev/null && ok || fail "flip: the previous evidence was not left untouched"
ls .ai/workspace/runs/M/evidence.json.unsaved.*.jsonl >/dev/null 2>&1 && ok || fail "flip: the records of the failed run were not kept"
echo 0 >flip.code
out="$(bash "$GATE" --config "$TMP/flip.json" --gate flipg --run-id M 2>/dev/null)"; rc=$?
has "$out" "GATE flipg FAIL" && [ "$rc" -eq 2 ] && ok || fail "flip: passing commands with a failed write gave a PASS ($rc): $out"
rmdir .ai/workspace/runs/M/evidence.json.tmp
out="$(bash "$GATE" --config "$TMP/flip.json" --gate flipg --run-id M)"; rc=$?
has "$out" "GATE flipg PASS" && [ "$rc" -eq 0 ] && jq -e '.checks.flip.status == "PASS"' .ai/workspace/runs/M/evidence.json >/dev/null && ok || fail "flip: no PASS after the directory is gone ($rc): $out"
echo 1 >flip.code
out="$(bash "$GATE" --config "$TMP/flip.json" --gate flipg --run-id M)"; rc=$?
has "$out" "GATE flipg FAIL" && [ "$rc" -eq 1 ] && jq -e '.checks.flip.status == "FAIL"' .ai/workspace/runs/M/evidence.json >/dev/null && ok || fail "flip: FAIL not written ($rc): $out"
rm -f flip.code

# --- 12d2. review of PR #19 (Medium/Low): --run-id stays inside the workspace
for bad in '../../escape' '.' '..' 'a/b'; do
  out="$(bash "$GATE" --gate quick --run-id "$bad")"; rc=$?
  has "$out" "CONFIG_ERROR --run-id" && [ "$rc" -eq 2 ] && ok || fail "run-id '$bad' accepted ($rc): $out"
done
[ -e .ai/escape ] && fail "run-id ..: evidence written outside the runs directory" || ok
out="$(bash "$GATE" --status --run-id '../x')"; rc=$?
has "$out" "CONFIG_ERROR --run-id" && [ "$rc" -eq 2 ] && ok || fail "status: run-id ../x accepted ($rc): $out"
out="$(bash "$GATE" --gate quick --run-id 'ok-1.x_y')"; rc=$?
has "$out" "GATE quick PASS run=ok-1.x_y" && [ "$rc" -eq 0 ] && ok || fail "run-id with . _ - rejected ($rc): $out"

# --- 12d3. review of PR #19 (Medium/Low): a PASS after a FAIL of the same command in this run
# is FLAKY; the red attempt keeps its log as <log>.1 and lives on in the evidence
jq '.validation.commands += {"flk": {"run": "echo attempt; exit $(cat .ai/workspace/flk.code)"},
                             "bgflk": {"run": "echo attempt; exit $(cat .ai/workspace/flk.code)", "parallel": true}}
    | .validation.gates += {"flkg": ["flk"], "bflkg": ["bgflk", "ok"]}' "$good" >"$TMP/flaky.json"
echo 1 >.ai/workspace/flk.code
out="$(bash "$GATE" --config "$TMP/flaky.json" --gate flkg --run-id FL)"; rc=$?
has "$out" "CHECK flk FAIL" && [ "$rc" -eq 1 ] && ok || fail "flaky: first run not FAIL ($rc): $out"
echo 0 >.ai/workspace/flk.code
out="$(bash "$GATE" --config "$TMP/flaky.json" --gate flkg --run-id FL)"; rc=$?
has "$out" "CHECK flk PASS" && has "$out" "(FLAKY: failed earlier in this run without a code change; first attempt: .ai/workspace/runs/FL/flkg.flk.log.1)" && ok || fail "flaky: CHECK line without FLAKY: $out"
has "$out" "GATE flkg PASS run=FL" && has "$out" "(FLAKY: flk;" && [ "$rc" -eq 0 ] && ok || fail "flaky: GATE line without FLAKY ($rc): $out"
[ -f .ai/workspace/runs/FL/flkg.flk.log.1 ] && [ -f .ai/workspace/runs/FL/flkg.flk.log ] && ok || fail "flaky: the red log was overwritten"
jq -e '.checks.flk | .status == "PASS" and .flaky == true and .previous.status == "FAIL" and .previous.reason == "exit code 1" and .previous.log == ".ai/workspace/runs/FL/flkg.flk.log.1"' .ai/workspace/runs/FL/evidence.json >/dev/null && ok || fail "flaky: evidence without flaky and previous: $(jq -c .checks.flk .ai/workspace/runs/FL/evidence.json)"
out="$(bash "$GATE" --status --run-id FL)"; rc=$?
has "$out" "CHECK flk PASS FRESH" && has "$out" "(FLAKY: failed earlier in this run, first attempt: .ai/workspace/runs/FL/flkg.flk.log.1)" && [ "$rc" -eq 0 ] && ok || fail "flaky: --status without FLAKY ($rc): $out"
out="$(bash "$GATE" --config "$TMP/flaky.json" --gate flkg --run-id FL --reuse-fresh)"; rc=$?
has "$out" "FRESH evidence reused" && has "$out" "FLAKY" && jq -e '.checks.flk | .flaky == true and .reused == true and .previous.status == "FAIL"' .ai/workspace/runs/FL/evidence.json >/dev/null && ok || fail "flaky: a reuse dropped the mark ($rc): $out"
echo 1 >.ai/workspace/flk.code
bash "$GATE" --config "$TMP/flaky.json" --gate flkg --run-id FX >/dev/null
echo 0 >.ai/workspace/flk.code; echo fix >>a.txt
out="$(bash "$GATE" --config "$TMP/flaky.json" --gate flkg --run-id FX)"; rc=$?
git checkout -q a.txt
has "$out" "CHECK flk PASS" && ! has "$out" "FLAKY" && jq -e '.checks.flk | .flaky == null and .previous.status == "FAIL"' .ai/workspace/runs/FX/evidence.json >/dev/null && ok || fail "flaky: a PASS after a code change marked FLAKY or lost the red attempt ($rc): $out"
echo 1 >.ai/workspace/flk.code
bash "$GATE" --config "$TMP/flaky.json" --gate bflkg --run-id BF >/dev/null
echo 0 >.ai/workspace/flk.code
out="$(bash "$GATE" --config "$TMP/flaky.json" --gate bflkg --run-id BF)"; rc=$?
has "$out" "CHECK bgflk PASS" && has "$out" "FLAKY: failed earlier in this run" && [ -f .ai/workspace/runs/BF/bflkg.bgflk.log.1 ] && ok || fail "flaky: a background command lost the red attempt ($rc): $out"
rm -f .ai/workspace/flk.code

# --- 12d4. review of PR #19 (Medium/Low): fingerprint inputs git would not compare
fp() { bash "$GATE" --fingerprint | sed -n 's/^FINGERPRINT //p'; }
printf '*.local\n' >>.gitignore
fpb="$(fp)"
echo '{}' >.ai/av.config.json.local
[ -n "$fpb" ] && [ "$(fp)" != "$fpb" ] && ok || fail "fingerprint: a planted .ai/av.config.json.local changes nothing"
rm .ai/av.config.json.local
git update-index --skip-worktree a.txt; echo changed >>a.txt
[ "$(fp)" != "$fpb" ] && ok || fail "fingerprint: a skip-worktree edit is invisible"
git update-index --no-skip-worktree a.txt; git checkout -q a.txt
git update-index --assume-unchanged a.txt; echo changed >>a.txt
[ "$(fp)" != "$fpb" ] && ok || fail "fingerprint: an assume-unchanged edit is invisible"
git update-index --no-assume-unchanged a.txt; git checkout -q a.txt
fpx() { GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="$1" GIT_CONFIG_VALUE_0="$2" bash "$GATE" --fingerprint | sed -n 's/^FINGERPRINT //p'; }
fpe="$(fpx diff.external /usr/bin/true)"; echo changed >>a.txt
[ -n "$fpe" ] && [ "$(fpx diff.external /usr/bin/true)" != "$fpe" ] && ok || fail "fingerprint: an external diff driver hides an edit"
git checkout -q a.txt
[ "$(fp)" = "$fpb" ] && ok || fail "fingerprint: not back to the base value after the edits"
SUB="$TMP/sub"; git init -q "$SUB" && git -C "$SUB" -c user.email=t@t -c user.name=t commit -qm s --allow-empty
git -c protocol.file.allow=always submodule add -q "$SUB" sub 2>/dev/null && git commit -qm sub
fps="$(fpx diff.ignoreSubmodules all)"; echo x >sub/new.txt
[ -n "$fps" ] && [ "$(fpx diff.ignoreSubmodules all)" != "$fps" ] && ok || fail "fingerprint: an untracked file in a submodule is invisible (diff.ignoreSubmodules=all)"
rm sub/new.txt
git -C sub -c user.email=t@t -c user.name=t commit -qm c --allow-empty
[ "$(fpx diff.ignoreSubmodules all)" != "$fps" ] && ok || fail "fingerprint: a new submodule commit is invisible (diff.ignoreSubmodules=all)"
git rm -qf sub && rm -rf .git/modules/sub && git checkout -q .gitignore && git commit -qm "drop sub"

# --- 12e. tree changed during the gate: evidence STALE, code 3 (R10)
jq '.validation.commands += {"mut": {"run": "echo m >new.txt; echo done"},
                             "mutfail": {"run": "echo m >new.txt; exit 1"}}
    | .validation.gates += {"mutg": ["mut"], "mutfg": ["mutfail"]}' "$good" >"$TMP/mut.json"
fp0="$(bash "$GATE" --fingerprint | sed -n 's/^FINGERPRINT //p')"
out="$(bash "$GATE" --config "$TMP/mut.json" --gate mutg --run-id r13)"; rc=$?
has "$out" "WARNING tree changed during the gate; evidence marked STALE, rerun the gate after editing is done" && ok || fail "stale: warning missing"
has "$out" "GATE mutg STALE run=r13" && ok || fail "stale: gate not STALE: $out"
has "$out" "fingerprint=$fp0" && ok || fail "stale: result lacks the fingerprint from before the gate"
[ "$rc" -eq 3 ] && ok || fail "stale: code $rc instead of 3"
jq -e --arg fp "$fp0" '.checks.mut | .fingerprint == $fp and .stale == true' .ai/workspace/runs/r13/evidence.json >/dev/null && ok || fail "stale: evidence without the fingerprint from before the gate or without stale"
out="$(bash "$GATE" --config "$TMP/mut.json" --status --run-id r13)"; rc=$?
has "$out" "CHECK mut PASS STALE" && [ "$rc" -eq 1 ] && ok || fail "stale: status not STALE ($rc)"
rm -f new.txt
out="$(bash "$GATE" --config "$TMP/mut.json" --status --run-id r13)"; rc=$?
has "$out" "CHECK mut PASS STALE" && [ "$rc" -eq 1 ] && ok || fail "stale: evidence FRESH again after reverting changes"
out="$(bash "$GATE" --config "$TMP/mut.json" --gate mutg --reuse-fresh --run-id r13)"
has "$out" "RUN mut" && ok || fail "stale: STALE evidence reused"
rm -f new.txt
out="$(bash "$GATE" --config "$TMP/mut.json" --gate mutfg --run-id r14)"; rc=$?
has "$out" "GATE mutfg FAIL" && [ "$rc" -eq 1 ] && ok || fail "stale: FAIL does not take precedence ($rc)"
rm -f new.txt

# --- 12f. AV_SKILLS_DIR in commands and precheck (R11), version (R13)
SK="$TMP/skills"
mkdir -p "$SK/av-verify" && cp -R "$(dirname "$GATE")" "$SK/av-verify/scripts"
G2="$SK/av-verify/scripts/gate.sh"
jq '.validation.commands += {"skills": {"run": "test -f \"$AV_SKILLS_DIR/av-verify/scripts/gate.sh\" && echo \"SKILLS_OK $AV_SKILLS_DIR\"",
                                        "expect": "SKILLS_OK", "precheck": "test -d \"$AV_SKILLS_DIR/av-verify\""}}
    | .validation.gates += {"sk": ["skills"]}' "$good" >"$TMP/sk.json"
out="$(bash "$G2" --config "$TMP/sk.json" --gate sk --run-id r15)"; rc=$?
has "$out" "CHECK skills PASS" && [ "$rc" -eq 0 ] && ok || fail "skills dir: command not PASS ($rc): $out"
grep -qF "SKILLS_OK $SK" .ai/workspace/runs/r15/sk.skills.log && ok || fail "skills dir: AV_SKILLS_DIR does not point to the av-* directory"
jq '.requires = {"av-dev": ">=0.1.0"}' "$TMP/sk.json" >"$TMP/req.json"
out="$(bash "$G2" --config "$TMP/req.json" --list)"; rc=$?
has "$out" "AV_DEV dev" && has "$out" "WARNING av-dev version unknown (dev), required >=0.1.0" && [ "$rc" -eq 0 ] && ok || fail "version dev: $rc $out"
out="$(bash "$G2" --config "$TMP/req.json" --gate quick --run-id r16)"; rc=$?
has "$out" "WARNING av-dev version unknown" && has "$out" "GATE quick PASS" && [ "$rc" -eq 0 ] && ok || fail "version dev: gate did not start ($rc)"
mkdir -p "$TMP/.claude-plugin" && echo '{"name": "av-dev", "version": "0.2.0"}' >"$TMP/.claude-plugin/plugin.json"
out="$(bash "$G2" --config "$TMP/req.json" --list)"; rc=$?
has "$out" "AV_DEV 0.2.0" && [ "$rc" -eq 0 ] && ok || fail "version 0.2.0: $rc $out"
has "$out" "WARNING av-dev version" && fail "version 0.2.0: needless warning" || ok
jq '.requires = {"av-dev": ">=0.10.0"}' "$TMP/sk.json" >"$TMP/req2.json"
out="$(bash "$G2" --config "$TMP/req2.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev: installed av-dev version 0.2.0, required >=0.10.0" && [ "$rc" -eq 2 ] && ok || fail "version too low --list: $rc $out"
out="$(bash "$G2" --config "$TMP/req2.json" --gate quick --run-id r17)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev" && [ "$rc" -eq 2 ] && ok || fail "version too low --gate: $rc"
echo '{"name": "av-dev", "version": "0.10.0"}' >"$TMP/.claude-plugin/plugin.json"
out="$(bash "$G2" --config "$TMP/req2.json" --list)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "version 0.10.0 >= 0.10.0: code $rc"
jq '.requires = {"av-dev": ">=0.9.1"}' "$TMP/sk.json" >"$TMP/req3.json"
out="$(bash "$G2" --config "$TMP/req3.json" --list)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "version 0.10.0 >= 0.9.1 (numeric comparison): code $rc"
jq '.requires = {"av-dev": "^0.1.0"}' "$TMP/sk.json" >"$TMP/req4.json"
out="$(bash "$G2" --config "$TMP/req4.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev: only the format >=X.Y.Z is supported" && [ "$rc" -eq 2 ] && ok || fail "bad requires format: $rc $out"

# --- 12g. parallel: background commands next to the rest of the gate, output in gate order (P1)
jq '.validation.commands += {
      "p1": {"run": "sleep 3; echo P1", "expect": "P1", "parallel": true},
      "fgc": {"run": "sleep 3; echo FG"},
      "p2": {"run": "echo P2", "parallel": true},
      "pslow": {"run": "sleep 27; echo never", "timeoutSec": 1, "parallel": true},
      "pbad": {"run": "echo oops; exit 5", "parallel": true},
      "pdown": {"run": "exit 2", "notRunExitCodes": [2], "parallel": true},
      "ppre": {"run": "echo x", "precheck": "true && test -d /does/not/exist/bg", "parallel": true},
      "popt": {"run": "echo x", "precheck": "false", "optional": true, "parallel": true},
      "pmut": {"run": "echo m >bg-new.txt; echo done", "parallel": true},
      "pbuild": {"run": "echo BUILT", "parallel": true},
      "pui": {"run": "echo DEVICE_OK", "expect": "DEVICE_OK", "covers": ["pbuild"]},
      "plong": {"run": "sleep 29", "parallel": true, "timeoutSec": 917},
      "fglong": {"run": "sleep 31", "timeoutSec": 917},
      "pflag": {"run": "echo x", "parallel": "yes"}}
    | .validation.gates += {"pg": ["p1", "fgc", "p2"], "pfail": ["pslow", "pbad", "pdown", "ppre", "popt", "fgc"],
                            "pmutg": ["pmut", "fgc"], "pcov": ["pbuild", "pui"], "plongg": ["plong", "fglong"]}' "$good" >"$TMP/par.json"
jq 'del(.validation.commands.pflag)' "$TMP/par.json" >"$TMP/par-ok.json"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --list)"; rc=$?
has "$out" "COMMAND p1: sleep 3; echo P1 expect='P1' parallel" && [ "$rc" -eq 0 ] && ok || fail "parallel: --list without the flag ($rc): $out"
out="$(bash "$GATE" --config "$TMP/par.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR command 'pflag': field parallel must be true or false" && [ "$rc" -eq 2 ] && ok || fail "parallel: bad type not rejected ($rc)"
t0="$(date +%s)"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pg --run-id r20)"; rc=$?
took=$(( $(date +%s) - t0 ))
[ "$rc" -eq 0 ] && has "$out" "GATE pg PASS run=r20" && ok || fail "parallel: gate not PASS ($rc): $out"
[ "$took" -lt 6 ] && ok || fail "parallel: gate took ${took}s, commands did not run side by side"
has "$out" "PARALLEL p1 p2 (in the background next to the rest of the gate)" && ok || fail "parallel: PARALLEL line missing: $out"
order="$(printf '%s\n' "$out" | sed -En 's/^(RUN|CHECK) ([a-z0-9]+)[: ].*/\1 \2/p' | tr '\n' ',')"
[ "$order" = "RUN p1,CHECK p1,RUN fgc,CHECK fgc,RUN p2,CHECK p2," ] && ok || fail "parallel: output order $order"
printf '%s\n' "$out" | grep -Eq '^CHECK p1 PASS [345]s \.ai/workspace/runs/r20/pg\.p1\.log$' && ok || fail "parallel: time or log of p1: $out"
grep -qx P1 .ai/workspace/runs/r20/pg.p1.log && grep -qx P2 .ai/workspace/runs/r20/pg.p2.log && ok || fail "parallel: background command logs"
jq -e '.checks | (.p1.status == "PASS" and .p1.duration >= 3 and .p1.duration <= 5 and .p1.exit == 0 and .p2.status == "PASS" and .fgc.status == "PASS")' .ai/workspace/runs/r20/evidence.json >/dev/null && ok || fail "parallel: evidence"
jq -e '[.checks[] | .fingerprint] | unique | length == 1' .ai/workspace/runs/r20/evidence.json >/dev/null && ok || fail "parallel: different fingerprints"
[ "$(jq -r '.checks | keys_unsorted | join(",")' .ai/workspace/runs/r20/evidence.json)" = "p1,fgc,p2" ] && ok || fail "parallel: evidence not in gate order"
[ -z "$(find .ai/workspace/runs/r20 -mindepth 1 -maxdepth 1 \( -name '.bg*' -o -name '.lock*' -o -name '.timeout*' -o -name '.records*' \))" ] && ok || fail "parallel: work files left behind: $(ls -A .ai/workspace/runs/r20)"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --status --run-id r20)"
has "$out" "CHECK p1 PASS FRESH" && ok || fail "parallel: status not FRESH"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pfail --run-id r21)"; rc=$?
has "$out" "CHECK pslow FAIL 1s .ai/workspace/runs/r21/pfail.pslow.log (timeout 1s)" && ok || fail "parallel: background timeout: $out"
pgrep -f "sleep 27" >/dev/null && fail "parallel: process alive after timeout" || ok
has "$out" "CHECK pbad FAIL" && has "$out" "(exit code 5)" && has "$out" "  oops" && ok || fail "parallel: exit code and log tail: $out"
has "$out" "CHECK pdown NOT_RUN" && has "$out" "exit code 2 means the environment is missing" && ok || fail "parallel: notRunExitCodes"
has "$out" "CHECK ppre NOT_RUN" && has "$out" "precheck failed: true && test -d /does/not/exist/bg" && ok || fail "parallel: precheck: $out"
has "$out" "RUN ppre" && fail "parallel: RUN despite a failed precheck" || ok
has "$out" "CHECK popt SKIPPED" && ok || fail "parallel: optional"
has "$out" "GATE pfail FAIL" && [ "$rc" -eq 1 ] && ok || fail "parallel: gate with failures ($rc)"
jq -e '.checks.pslow.exit == 124 and .checks.pbad.exit == 5 and (.checks.pbad.tail | index("oops") != null)' .ai/workspace/runs/r21/evidence.json >/dev/null && ok || fail "parallel: failure evidence"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pmutg --run-id r22)"; rc=$?
has "$out" "GATE pmutg STALE" && [ "$rc" -eq 3 ] && ok || fail "parallel: a tree change from the background does not give STALE ($rc): $out"
rm -f bg-new.txt
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pcov --run-id r23)"
has "$out" "CHECK pbuild PASS 0s (covered by pui)" && ok || fail "parallel: covered command ran in the background: $out"
has "$out" "PARALLEL" && fail "parallel: covered command in the background" || ok
bash "$GATE" --config "$TMP/par-ok.json" --gate pg --run-id r24 >/dev/null
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pg --reuse-fresh --run-id r24)"
has "$out" "PARALLEL" && fail "parallel: command with FRESH evidence ran in the background: $out" || ok
has "$out" "CHECK p1 PASS 0s (FRESH evidence reused" && ok || fail "parallel: background reuse: $out"
bash "$GATE" --config "$TMP/par-ok.json" --gate plongg --run-id r25 >/dev/null 2>&1 &
gpid=$!
n=0; while ! pgrep -f "sleep 31" >/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -TERM "$gpid"; wait "$gpid" 2>/dev/null
n=0; while pgrep -f "sleep (29|31)" >/dev/null && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
pgrep -f "sleep (29|31)" >/dev/null && { fail "parallel: command alive after the gate was interrupted"; pkill -f "sleep (29|31)"; } || ok
n=0; while pgrep -f "sleep 917" >/dev/null && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
pgrep -f "sleep 917" >/dev/null && { fail "parallel: timeout watcher alive after the gate was interrupted"; pkill -f "sleep 917"; } || ok
[ ! -d .ai/workspace/runs/r25/.lock ] && [ -z "$(find .ai/workspace/runs/r25 -mindepth 1 -maxdepth 1 -name '.bg*')" ] && ok || fail "parallel: lock or .bg left after interruption"

# --- 13. workspace outside .gitignore does not change the fingerprint
git rm -q --cached .gitignore && rm .gitignore && git commit -qm "no ignore"
bash "$GATE" --only ok --run-id r9 >/dev/null
out="$(bash "$GATE" --status --run-id r9)"
has "$out" "CHECK ok PASS FRESH" && ok || fail "fingerprint depends on evidence files"

# Parameter-sensitive reuse, with external config (outside repository fingerprint).
cat >"$TMP/reuse.json" <<'EOF'
{"version":1,"paths":{"workspace":".ai/workspace"},"validation":{"commands":{"probe":{"run":"test \"$SUITE\" = A"}},"gates":{"quick":["probe"]}}}
EOF
bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=A --run-id params >/dev/null
out="$(bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=B --reuse-fresh --run-id params)"; rc=$?
[ "$rc" = 1 ] && has "$out" "RUN probe" && ok || fail "changed env reused PASS"
bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=A --env EXTRA=x --run-id params >/dev/null
out="$(bash "$GATE" --config "$TMP/reuse.json" --only probe --env EXTRA=x --env SUITE=A --reuse-fresh --run-id params)"
has "$out" "FRESH evidence reused" && ok || fail "env order invalidates reuse"
out="$(bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=B --env SUITE=A --env EXTRA=x --reuse-fresh --run-id params)"
has "$out" "FRESH evidence reused" && ok || fail "last env value not canonical"
for field in run precheck; do
  jq --arg f "$field" '.validation.commands.probe[$f]="false"' "$TMP/reuse.json" >"$TMP/changed.json"
  out="$(bash "$GATE" --config "$TMP/changed.json" --only probe --env SUITE=A --env EXTRA=x --reuse-fresh --run-id params)"; rc=$?
  [ "$rc" != 0 ] && ! has "$out" "FRESH evidence reused" && ok || fail "changed $field reused PASS"
done
bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=A --run-id legacy >/dev/null
jq 'del(.checks.probe.invocationFingerprint)' .ai/workspace/runs/legacy/evidence.json >"$TMP/legacy.json"
cp "$TMP/legacy.json" .ai/workspace/runs/legacy/evidence.json
out="$(bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=A --reuse-fresh --run-id legacy)"
has "$out" "RUN probe" && ok || fail "legacy evidence reused"
bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=A --env PRIVATE_VALUE=unique-private-test-value --run-id secret >/dev/null
if grep -R -q 'unique-private-test-value' .ai/workspace/runs/secret; then fail "env value leaked"; else ok; fi

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

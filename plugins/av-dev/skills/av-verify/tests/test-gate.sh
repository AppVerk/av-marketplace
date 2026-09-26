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

# --- 12b. precheck logs the failed step; --list catches syntax errors and a missing script
cfg2="$TMP/cfg2.json"
jq '.validation.commands += {"pc": {"run": "echo x", "precheck": "true && test -d /does/not/exist && true"},
                               "syn": {"run": "echo (("}, "miss": {"run": "scripts/missing.sh"}}
    | .validation.gates += {"pcg": ["pc"]} | del(.validation.gates.broken)' .ai/av.config.json >"$cfg2"
out="$(bash "$GATE" --config "$cfg2" --gate pcg --run-id r10)"
has "$out" "precheck failed at: test -d /does/not/exist" && ok || fail "precheck: step missing in reason"
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
bad_case() {
  local filter="$1" expect="$2" desc="$3" o r
  jq "$filter" "$good" >"$TMP/bad.json"
  o="$(bash "$GATE" --config "$TMP/bad.json" --list)"; r=$?
  if has "$o" "CONFIG_ERROR $expect" && [ "$r" -eq 2 ]; then ok; else fail "validation $desc: code $r, output: $o"; fi
}
bad_case '.agents.models.verify = "gpt4"' "agents.models.verify: invalid value \"gpt4\"" "model not on the list"
bad_case '.agents.models.review = "haiku"' "agents.models.review: haiku cannot do review" "review haiku"
bad_case '.agents.models = "opus"' "agents.models: expected an object" "models not an object"
bad_case '.git.commit = "always"' "git.commit: invalid value \"always\"" "git.commit"
bad_case '.git.push = "force"' "git.push: invalid value \"force\"" "git.push"
bad_case '.roles[0].globs = ["src/{a,b}/**"]' "roles[0].globs: glob \"src/{a,b}/**\" has a curly brace" "glob with braces"
bad_case '.roles[0].globs = ["!src/{a,b}/**", "src/**"]' "roles[0].globs: glob \"!src/{a,b}/**\" has a curly brace" "exclusion with braces"
bad_case '.roles[1].globs = ["!src/ui/legacy/**"]' "roles[1].globs: only exclusions (!); add at least one glob without !" "role with only exclusions"
bad_case '.roles[1].globs = ["src/ui/**", "!"]' "roles[1].globs: exclusion \"!\" has no pattern" "empty exclusion"
bad_case '.roles[1].order = 1.5' "roles[1].order: expected an integer" "fractional order"
bad_case '.roles[0].globs = []' "roles[0].globs: expected a non-empty array" "empty globs"
bad_case '.roles[0].globs = ["a", 3]' "roles[0].globs: element 3 is not a string" "glob not a string"
bad_case 'del(.roles[1].skill)' "roles[1].skill: expected a non-empty string" "skill missing"
bad_case '.roles[0].name = 7' "roles[0].name: expected a non-empty string" "name not a string"
bad_case '.roles = {"a": 1}' "roles: expected an array of objects" "roles not an array"
bad_case '.generatedPaths = "vendor/**"' "generatedPaths: expected an array of strings" "generatedPaths"
bad_case '.unownedPaths = [1]' "unownedPaths: expected an array of strings" "unownedPaths"
bad_case '.agents.models.review = {"provider": "claude", "model": "haiku"}' "agents.models.review: haiku cannot do review" "review haiku in an object"
bad_case '.agents.models.plan = {"provider": "gemini", "model": "x"}' "agents.models.plan.provider: invalid value \"gemini\"" "unknown provider"
bad_case '.agents.models.plan = {"provider": "claude", "model": "gpt-6-astra"}' "agents.models.plan.model: invalid claude model" "codex model for claude"
bad_case '.agents.models.plan = {"provider": "codex", "model": "gpt 6"}' "agents.models.plan.model: invalid codex model name" "bad codex model name"
bad_case '.agents.models.plan = {"provider": "claude", "model": "opus", "effort": "ultra"}' "agents.models.plan.effort: invalid value \"ultra\" for claude" "effort ultra for claude"
bad_case '.agents.models.plan = {"provider": "codex", "model": "gpt-6-astra", "effort": "turbo"}' "agents.models.plan.effort: invalid value \"turbo\" for codex" "unknown codex effort"
bad_case '.agents.models.plan = {"provider": "codex", "modle": "x"}' "agents.models.plan: unknown field \"modle\"" "typo in a slot field"
bad_case '.agents.models.plan = 5' "agents.models.plan: expected a string or an object" "slot as a number"
bad_case '.agents.crossVendor = "yes"' "agents.crossVendor: expected true or false" "crossVendor not a bool"
bad_case '.agents.timeoutSec = 0' "agents.timeoutSec: expected a positive integer" "timeoutSec zero"
bad_case '.agents.crossVendor = true' "agents.crossVendor: review and implement have the same provider \"claude\"" "crossVendor same provider"
bad_case '.agents.crossVendor = true | .agents.models = {"plan": {"provider": "codex", "model": "gpt-6-astra"}, "implement": "opus", "review": {"provider": "codex", "model": "gpt-6-astra"}}' \
  "agents.crossVendor: review and plan have the same provider \"codex\"; set agents.models.planReview" "crossVendor plan without planReview"
cross='.agents.crossVendor = true | .agents.timeoutSec = 3600 | .agents.models = {
  "plan": {"provider": "codex", "model": "gpt-6-astra", "effort": "high"},
  "planReview": {"provider": "claude", "model": "opus", "effort": "high"},
  "implement": {"provider": "claude", "model": "opus", "effort": "xhigh"},
  "review": {"provider": "codex", "model": "gpt-6-astra", "effort": "ultra"},
  "verify": "haiku"}'
jq "$cross" "$good" >"$TMP/cross.json"
out="$(bash "$GATE" --config "$TMP/cross.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR" && fail "validation: valid cross-vendor config rejected: $out" || ok
[ "$rc" -eq 0 ] && ok || fail "validation: cross-vendor config code $rc"
jq '.agents.models.implement = "claude-opus-5-5"' "$good" >"$TMP/fullid.json"
out="$(bash "$GATE" --config "$TMP/fullid.json" --list)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "validation: full claude model id rejected: $out"
jq '.agents.models.verify = "gpt4"' "$good" >"$TMP/bad.json"
out="$(bash "$GATE" --config "$TMP/bad.json" --gate quick --run-id r12)"; rc=$?
has "$out" "CONFIG_ERROR agents.models.verify" && [ "$rc" -eq 2 ] && ok || fail "validation: gate started despite a bad config ($rc)"
has "$out" "RUN ok" && fail "validation: command ran despite a bad config" || ok
out="$(bash "$GATE" --config "$TMP/bad.json" --status --run-id r12)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "validation: --status code $rc instead of 2"

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
echo "0.2.0" >"$SK/av-verify/VERSION"
out="$(bash "$G2" --config "$TMP/req.json" --list)"; rc=$?
has "$out" "AV_DEV 0.2.0" && [ "$rc" -eq 0 ] && ok || fail "version 0.2.0: $rc $out"
has "$out" "WARNING av-dev version" && fail "version 0.2.0: needless warning" || ok
jq '.requires = {"av-dev": ">=0.10.0"}' "$TMP/sk.json" >"$TMP/req2.json"
out="$(bash "$G2" --config "$TMP/req2.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev: installed av-dev version 0.2.0, required >=0.10.0" && [ "$rc" -eq 2 ] && ok || fail "version too low --list: $rc $out"
out="$(bash "$G2" --config "$TMP/req2.json" --gate quick --run-id r17)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev" && [ "$rc" -eq 2 ] && ok || fail "version too low --gate: $rc"
echo "0.10.0" >"$SK/av-verify/VERSION"
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
has "$out" "CHECK p1 PASS 3s .ai/workspace/runs/r20/pg.p1.log" && ok || fail "parallel: time or log of p1: $out"
grep -qx P1 .ai/workspace/runs/r20/pg.p1.log && grep -qx P2 .ai/workspace/runs/r20/pg.p2.log && ok || fail "parallel: background command logs"
jq -e '.checks | (.p1.status == "PASS" and .p1.duration == 3 and .p1.exit == 0 and .p2.status == "PASS" and .fgc.status == "PASS")' .ai/workspace/runs/r20/evidence.json >/dev/null && ok || fail "parallel: evidence"
jq -e '[.checks[] | .fingerprint] | unique | length == 1' .ai/workspace/runs/r20/evidence.json >/dev/null && ok || fail "parallel: different fingerprints"
[ "$(jq -r '.checks | keys_unsorted | join(",")' .ai/workspace/runs/r20/evidence.json)" = "p1,fgc,p2" ] && ok || fail "parallel: evidence not in gate order"
[ -z "$(ls -A .ai/workspace/runs/r20 | grep -E '^\.(bg|lock|timeout|records)')" ] && ok || fail "parallel: work files left behind: $(ls -A .ai/workspace/runs/r20)"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --status --run-id r20)"
has "$out" "CHECK p1 PASS FRESH" && ok || fail "parallel: status not FRESH"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pfail --run-id r21)"; rc=$?
has "$out" "CHECK pslow FAIL 1s .ai/workspace/runs/r21/pfail.pslow.log (timeout 1s)" && ok || fail "parallel: background timeout: $out"
pgrep -f "sleep 27" >/dev/null && fail "parallel: process alive after timeout" || ok
has "$out" "CHECK pbad FAIL" && has "$out" "(exit code 5)" && has "$out" "  oops" && ok || fail "parallel: exit code and log tail: $out"
has "$out" "CHECK pdown NOT_RUN" && has "$out" "exit code 2 means the environment is missing" && ok || fail "parallel: notRunExitCodes"
has "$out" "CHECK ppre NOT_RUN" && has "$out" "precheck failed at: test -d /does/not/exist/bg" && ok || fail "parallel: precheck: $out"
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
[ ! -d .ai/workspace/runs/r25/.lock ] && [ -z "$(ls -A .ai/workspace/runs/r25 | grep -E '^\.bg')" ] && ok || fail "parallel: lock or .bg left after interruption"

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

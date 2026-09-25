#!/bin/bash
# Testy czarnej skrzynki dla gate.sh.
# Buduje tymczasowe repo z configiem i sprawdza statusy, kody wyjscia i dowody.
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

# --- 1. --list wypisuje komendy i zglasza zepsuta bramke
out="$(bash "$GATE" --list)"; rc=$?
has "$out" "COMMAND ok: echo BUILD SUCCEEDED expect='BUILD SUCCEEDED'" && ok || fail "list: brak komendy ok z expect"
has "$out" "CONFIG_ERROR bramka 'broken' wskazuje nieznana komende 'ghost'" && ok || fail "list: brak bledu broken"
[ "$rc" -eq 2 ] && ok || fail "list: kod $rc zamiast 2"

# --- 2. zdrowa bramka dziala mimo zepsutej innej bramki
out="$(bash "$GATE" --gate quick --run-id r1)"; rc=$?
has "$out" "WARNING bramka 'broken'" && ok || fail "quick: brak ostrzezenia o broken"
has "$out" "CHECK ok PASS" && ok || fail "quick: ok nie PASS"
has "$out" "GATE quick PASS run=r1" && ok || fail "quick: brak GATE PASS"
[ "$rc" -eq 0 ] && ok || fail "quick: kod $rc"
[ -f .ai/workspace/runs/r1/evidence.json ] && ok || fail "quick: brak evidence.json"

# --- 3. status FRESH, potem STALE po zmianie pliku
out="$(bash "$GATE" --status --run-id r1)"; rc=$?
has "$out" "CHECK ok PASS FRESH" && ok || fail "status: brak FRESH"
[ "$rc" -eq 0 ] && ok || fail "status fresh: kod $rc"
echo b >>a.txt
out="$(bash "$GATE" --status --run-id r1)"; rc=$?
has "$out" "CHECK ok PASS STALE" && ok || fail "status: brak STALE po zmianie"
[ "$rc" -eq 1 ] && ok || fail "status stale: kod $rc"
git checkout -q a.txt

# --- 4. FAIL: brak napisu, kod wyjscia, timeout; NOT_RUN z precheck
out="$(bash "$GATE" --gate all --run-id r2)"; rc=$?
has "$out" "CHECK noexpect FAIL" && has "$out" "brak oczekiwanego napisu 'BUILD SUCCEEDED'" && ok || fail "all: noexpect"
has "$out" "CHECK bad FAIL" && has "$out" "(kod wyjscia 3)" && ok || fail "all: bad"
has "$out" "CHECK env NOT_RUN" && has "$out" "wymaga: docker compose up" && ok || fail "all: env"
has "$out" "CHECK slow FAIL" && has "$out" "(timeout 1s)" && ok || fail "all: slow"
has "$out" "GATE all FAIL" && ok || fail "all: brak GATE FAIL"
[ "$rc" -eq 1 ] && ok || fail "all: kod $rc"
jq -e '.checks.bad.tail | index("boom") != null' .ai/workspace/runs/r2/evidence.json >/dev/null && ok || fail "all: brak ogona logu w dowodzie"

# --- 5. notRunExitCodes daje NOT_RUN i INCOMPLETE
out="$(bash "$GATE" --gate downg --run-id r3)"; rc=$?
has "$out" "CHECK down NOT_RUN" && ok || fail "down: nie NOT_RUN"
has "$out" "GATE downg INCOMPLETE" && ok || fail "down: nie INCOMPLETE"
[ "$rc" -eq 3 ] && ok || fail "down: kod $rc"

# --- 6. komenda opcjonalna: SKIPPED nie psuje bramki
out="$(bash "$GATE" --gate optg --run-id r4)"; rc=$?
has "$out" "CHECK opt SKIPPED" && ok || fail "opt: nie SKIPPED"
has "$out" "GATE optg PASS" && ok || fail "opt: bramka nie PASS"
[ "$rc" -eq 0 ] && ok || fail "opt: kod $rc"

# --- 7. covers + --env: ui pokrywa build
out="$(bash "$GATE" --gate full --env UI_SUITE=LoginTests --run-id r5)"; rc=$?
has "$out" "CHECK ui PASS" && ok || fail "full: ui nie PASS"
has "$out" "CHECK build PASS 0s (pokryte przez ui)" && ok || fail "full: build nie pokryty"
has "$out" "RUN build" && fail "full: build uruchomiony mimo pokrycia" || ok
[ "$rc" -eq 0 ] && ok || fail "full: kod $rc"

# --- 8. bez parametru ui pada, a build uruchamia sie sam
out="$(bash "$GATE" --gate full --run-id r6)"; rc=$?
has "$out" "CHECK ui FAIL" && ok || fail "full bez env: ui nie FAIL"
has "$out" "RUN build" && ok || fail "full bez env: build nie uruchomiony"
[ "$rc" -eq 1 ] && ok || fail "full bez env: kod $rc"

# --- 9. baseline zapisuje osobny plik
out="$(bash "$GATE" --baseline --only ok --run-id r7)"; rc=$?
has "$out" "BASELINE ok PASS" && ok || fail "baseline: brak linii BASELINE"
[ -f .ai/workspace/runs/r7/baseline.json ] && ok || fail "baseline: brak baseline.json"
out="$(bash "$GATE" --status --run-id r7)"
has "$out" "BASELINE ok PASS pomiar-bazowy head=" && ok || fail "baseline: brak linii pomiaru bazowego"

# --- 10. cwd komendy
out="$(bash "$GATE" --only sub --run-id r8)"
grep -q "/sub$" .ai/workspace/runs/r8/sub.sub.log && ok || fail "cwd: komenda nie w katalogu sub"

# --- 11. --root i --config spoza repo, uruchomione z innego katalogu
cp .ai/av.config.json "$TMP/proposed.json"
out="$(cd /tmp && bash "$GATE" --root "$REPO" --config "$TMP/proposed.json" --list)"; rc=$?
has "$out" "GATE quick: ok" && ok || fail "root/config: brak bramki quick"

# --- 12. bledy argumentow i brak configu
out="$(bash "$GATE" --gate nope)"; rc=$?
has "$out" "CONFIG_ERROR nieznana bramka 'nope'" && [ "$rc" -eq 2 ] && ok || fail "nieznana bramka"
out="$(bash "$GATE" --gate broken)"; rc=$?
has "$out" "CONFIG_ERROR bramka 'broken' ma niepoprawne komendy: ghost" && [ "$rc" -eq 2 ] && ok || fail "zepsuta bramka"
out="$(bash "$GATE" --gate quick --env FOO)"; rc=$?
has "$out" "CONFIG_ERROR --env wymaga KLUCZ=WARTOSC" && [ "$rc" -eq 2 ] && ok || fail "zly --env"
out="$(cd "$TMP" && bash "$GATE" --gate quick)"; rc=$?
has "$out" "CONFIG_ERROR brak" && [ "$rc" -eq 2 ] && ok || fail "brak configu"

# --- 12b. precheck loguje krok, ktory padl; --list lapie skladnie i brak skryptu
cfg2="$TMP/cfg2.json"
jq '.validation.commands += {"pc": {"run": "echo x", "precheck": "true && test -d /nie/ma/tego && true"},
                               "syn": {"run": "echo (("}, "miss": {"run": "scripts/nie-ma.sh"}}
    | .validation.gates += {"pcg": ["pc"]} | del(.validation.gates.broken)' .ai/av.config.json >"$cfg2"
out="$(bash "$GATE" --config "$cfg2" --gate pcg --run-id r10)"
has "$out" "precheck nie przeszedl na: test -d /nie/ma/tego" && ok || fail "precheck: brak kroku w powodzie"
out="$(bash "$GATE" --config "$cfg2" --list)"; rc=$?
has "$out" "komenda 'syn': blad skladni w polu run" && [ "$rc" -eq 2 ] && ok || fail "list: brak bledu skladni"
has "$out" "WARNING komenda miss: brak pliku scripts/nie-ma.sh" && ok || fail "list: brak ostrzezenia o skrypcie"
cfg3="$TMP/cfg3.json"
jq '.validation.commands = {"envp": {"run": "FOO=1 BAR=2 echo ok"}} | .validation.gates = {"g": ["envp"]}' .ai/av.config.json >"$cfg3"
out="$(bash "$GATE" --config "$cfg3" --list)"
has "$out" "WARNING" && fail "list: falszywe ostrzezenie dla prefiksu zmiennej" || ok

# --- 12c. osobne logi dla baseline i bramek, blokada, ponowne uzycie dowodu
bash "$GATE" --baseline --gate quick --run-id r11 >/dev/null
bash "$GATE" --gate quick --run-id r11 >/dev/null
[ -f .ai/workspace/runs/r11/baseline.quick.ok.log ] && [ -f .ai/workspace/runs/r11/quick.ok.log ] && ok || fail "logi: brak osobnych plikow"
jq -e '.checks.ok.log | endswith("baseline.quick.ok.log")' .ai/workspace/runs/r11/baseline.json >/dev/null && ok || fail "logi: baseline wskazuje cudzy log"
mkdir -p .ai/workspace/runs/r11/.lock && echo "full pid 1" >.ai/workspace/runs/r11/.lock/owner
out="$(bash "$GATE" --gate quick --run-id r11)"; rc=$?
has "$out" "BUSY inna bramka przebiegu r11" && [ "$rc" -eq 4 ] && ok || fail "lock: brak BUSY ($rc)"
out="$(bash "$GATE" --status --run-id r11)"; rc=$?
has "$out" "BUSY bramka w toku: full pid 1" && [ "$rc" -eq 4 ] && ok || fail "status: brak BUSY ($rc)"
rm -rf .ai/workspace/runs/r11/.lock
out="$(bash "$GATE" --gate quick --reuse-fresh --run-id r11)"; rc=$?
has "$out" "CHECK ok PASS 0s (dowod FRESH uzyty ponownie" && [ "$rc" -eq 0 ] && ok || fail "reuse: nie uzyto dowodu"
has "$out" "RUN ok" && fail "reuse: komenda uruchomiona mimo dowodu" || ok
echo c >>a.txt
out="$(bash "$GATE" --gate quick --reuse-fresh --run-id r11)"
has "$out" "RUN ok" && ok || fail "reuse: stary dowod uzyty po zmianie kodu"
git checkout -q a.txt
[ ! -d .ai/workspace/runs/r11/.lock ] && ok || fail "lock: nie zwolniony po bramce"

# --- 12d. walidacja pol configu: modele, git, role, sciezki (R7)
good="$TMP/good.json"
jq 'del(.validation.gates.broken)
    | .agents = {"models": {"plan": "inherit", "implement": "opus", "review": "sonnet", "verify": "fable"}}
    | .git = {"commit": "on-request", "push": "never"}
    | .roles = [{"name": "data", "skill": "ios-data", "order": 1, "globs": ["src/api/**", "src/db/*.swift"]},
                {"name": "ui", "skill": "ios-ui", "order": 2, "globs": ["src/ui/**"]}]
    | .generatedPaths = ["Pods/**"] | .unownedPaths = ["scripts/**"]' .ai/av.config.json >"$good"
out="$(bash "$GATE" --config "$good" --list)"; rc=$?
has "$out" "CONFIG_ERROR" && fail "walidacja: poprawny config odrzucony: $out" || ok
has "$out" "AV_DEV " && ok || fail "walidacja: brak linii AV_DEV"
[ "$rc" -eq 0 ] && ok || fail "walidacja: poprawny config kod $rc"
bad_case() {
  local filter="$1" expect="$2" desc="$3" o r
  jq "$filter" "$good" >"$TMP/bad.json"
  o="$(bash "$GATE" --config "$TMP/bad.json" --list)"; r=$?
  if has "$o" "CONFIG_ERROR $expect" && [ "$r" -eq 2 ]; then ok; else fail "walidacja $desc: kod $r, wyjscie: $o"; fi
}
bad_case '.agents.models.verify = "gpt4"' "agents.models.verify: niedozwolona wartosc \"gpt4\"" "model spoza listy"
bad_case '.agents.models.review = "haiku"' "agents.models.review: haiku" "review haiku"
bad_case '.agents.models = "opus"' "agents.models: oczekiwany obiekt" "models nie obiekt"
bad_case '.git.commit = "always"' "git.commit: niedozwolona wartosc \"always\"" "git.commit"
bad_case '.git.push = "force"' "git.push: niedozwolona wartosc \"force\"" "git.push"
bad_case '.roles[0].globs = ["src/{a,b}/**"]' "roles[0].globs: glob \"src/{a,b}/**\" ma nawias klamrowy" "glob z klamrami"
bad_case '.roles[1].order = 1.5' "roles[1].order: oczekiwana liczba calkowita" "order ulamkowy"
bad_case '.roles[0].globs = []' "roles[0].globs: oczekiwana niepusta tablica" "puste globy"
bad_case '.roles[0].globs = ["a", 3]' "roles[0].globs: element 3 nie jest napisem" "glob nie napis"
bad_case 'del(.roles[1].skill)' "roles[1].skill: oczekiwany niepusty napis" "brak skill"
bad_case '.roles[0].name = 7' "roles[0].name: oczekiwany niepusty napis" "name nie napis"
bad_case '.roles = {"a": 1}' "roles: oczekiwana tablica obiektow" "roles nie tablica"
bad_case '.generatedPaths = "Pods/**"' "generatedPaths: oczekiwana tablica napisow" "generatedPaths"
bad_case '.unownedPaths = [1]' "unownedPaths: oczekiwana tablica napisow" "unownedPaths"
bad_case '.agents.models.review = {"provider": "claude", "model": "haiku"}' "agents.models.review: haiku" "review haiku w obiekcie"
bad_case '.agents.models.plan = {"provider": "gemini", "model": "x"}' "agents.models.plan.provider: niedozwolona wartosc \"gemini\"" "nieznany dostawca"
bad_case '.agents.models.plan = {"provider": "claude", "model": "gpt-6-astra"}' "agents.models.plan.model: niedozwolony model claude" "model codex u claude"
bad_case '.agents.models.plan = {"provider": "codex", "model": "gpt 6"}' "agents.models.plan.model: niepoprawna nazwa modelu codex" "zla nazwa modelu codex"
bad_case '.agents.models.plan = {"provider": "claude", "model": "opus", "effort": "ultra"}' "agents.models.plan.effort: niedozwolona wartosc \"ultra\" dla claude" "effort ultra u claude"
bad_case '.agents.models.plan = {"provider": "codex", "model": "gpt-6-astra", "effort": "turbo"}' "agents.models.plan.effort: niedozwolona wartosc \"turbo\" dla codex" "nieznany effort codex"
bad_case '.agents.models.plan = {"provider": "codex", "modle": "x"}' "agents.models.plan: nieznane pole \"modle\"" "literowka w polu slotu"
bad_case '.agents.models.plan = 5' "agents.models.plan: oczekiwany napis albo obiekt" "slot liczba"
bad_case '.agents.crossVendor = "yes"' "agents.crossVendor: oczekiwane true albo false" "crossVendor nie bool"
bad_case '.agents.timeoutSec = 0' "agents.timeoutSec: oczekiwana dodatnia" "timeoutSec zero"
bad_case '.agents.crossVendor = true' "agents.crossVendor: review i implement maja tego samego dostawce \"claude\"" "crossVendor ten sam dostawca"
bad_case '.agents.crossVendor = true | .agents.models = {"plan": {"provider": "codex", "model": "gpt-6-astra"}, "implement": "opus", "review": {"provider": "codex", "model": "gpt-6-astra"}}' \
  "agents.crossVendor: review i plan maja tego samego dostawce \"codex\"; ustaw agents.models.planReview" "crossVendor plan bez planReview"
cross='.agents.crossVendor = true | .agents.timeoutSec = 3600 | .agents.models = {
  "plan": {"provider": "codex", "model": "gpt-6-astra", "effort": "high"},
  "planReview": {"provider": "claude", "model": "opus", "effort": "high"},
  "implement": {"provider": "claude", "model": "opus", "effort": "xhigh"},
  "review": {"provider": "codex", "model": "gpt-6-astra", "effort": "ultra"},
  "verify": "haiku"}'
jq "$cross" "$good" >"$TMP/cross.json"
out="$(bash "$GATE" --config "$TMP/cross.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR" && fail "walidacja: poprawny config cross-vendor odrzucony: $out" || ok
[ "$rc" -eq 0 ] && ok || fail "walidacja: config cross-vendor kod $rc"
jq '.agents.models.implement = "claude-opus-5-5"' "$good" >"$TMP/fullid.json"
out="$(bash "$GATE" --config "$TMP/fullid.json" --list)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "walidacja: pelne id modelu claude odrzucone: $out"
jq '.agents.models.verify = "gpt4"' "$good" >"$TMP/bad.json"
out="$(bash "$GATE" --config "$TMP/bad.json" --gate quick --run-id r12)"; rc=$?
has "$out" "CONFIG_ERROR agents.models.verify" && [ "$rc" -eq 2 ] && ok || fail "walidacja: bramka ruszyla mimo zlego configu ($rc)"
has "$out" "RUN ok" && fail "walidacja: komenda uruchomiona mimo zlego configu" || ok
out="$(bash "$GATE" --config "$TMP/bad.json" --status --run-id r12)"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "walidacja: --status kod $rc zamiast 2"

# --- 12e. drzewo zmienione w trakcie bramki: dowod STALE, kod 3 (R10)
jq '.validation.commands += {"mut": {"run": "echo m >new.txt; echo done"},
                             "mutfail": {"run": "echo m >new.txt; exit 1"}}
    | .validation.gates += {"mutg": ["mut"], "mutfg": ["mutfail"]}' "$good" >"$TMP/mut.json"
fp0="$(bash "$GATE" --fingerprint | sed -n 's/^FINGERPRINT //p')"
out="$(bash "$GATE" --config "$TMP/mut.json" --gate mutg --run-id r13)"; rc=$?
has "$out" "WARNING drzewo zmienilo sie w trakcie bramki; dowod oznaczony STALE, powtorz bramke po zakonczeniu edycji" && ok || fail "stale: brak ostrzezenia"
has "$out" "GATE mutg STALE run=r13" && ok || fail "stale: bramka nie STALE: $out"
has "$out" "fingerprint=$fp0" && ok || fail "stale: wynik nie ma odcisku sprzed bramki"
[ "$rc" -eq 3 ] && ok || fail "stale: kod $rc zamiast 3"
jq -e --arg fp "$fp0" '.checks.mut | .fingerprint == $fp and .stale == true' .ai/workspace/runs/r13/evidence.json >/dev/null && ok || fail "stale: dowod bez odcisku sprzed bramki albo bez stale"
out="$(bash "$GATE" --config "$TMP/mut.json" --status --run-id r13)"; rc=$?
has "$out" "CHECK mut PASS STALE" && [ "$rc" -eq 1 ] && ok || fail "stale: status nie STALE ($rc)"
rm -f new.txt
out="$(bash "$GATE" --config "$TMP/mut.json" --status --run-id r13)"; rc=$?
has "$out" "CHECK mut PASS STALE" && [ "$rc" -eq 1 ] && ok || fail "stale: po cofnieciu zmian dowod znow FRESH"
out="$(bash "$GATE" --config "$TMP/mut.json" --gate mutg --reuse-fresh --run-id r13)"
has "$out" "RUN mut" && ok || fail "stale: dowod STALE uzyty ponownie"
rm -f new.txt
out="$(bash "$GATE" --config "$TMP/mut.json" --gate mutfg --run-id r14)"; rc=$?
has "$out" "GATE mutfg FAIL" && [ "$rc" -eq 1 ] && ok || fail "stale: FAIL nie ma pierwszenstwa ($rc)"
rm -f new.txt

# --- 12f. AV_SKILLS_DIR w komendach i precheck (R11), wersja (R13)
SK="$TMP/skills"
mkdir -p "$SK/av-verify" && cp -R "$(dirname "$GATE")" "$SK/av-verify/scripts"
G2="$SK/av-verify/scripts/gate.sh"
jq '.validation.commands += {"skills": {"run": "test -f \"$AV_SKILLS_DIR/av-verify/scripts/gate.sh\" && echo \"SKILLS_OK $AV_SKILLS_DIR\"",
                                        "expect": "SKILLS_OK", "precheck": "test -d \"$AV_SKILLS_DIR/av-verify\""}}
    | .validation.gates += {"sk": ["skills"]}' "$good" >"$TMP/sk.json"
out="$(bash "$G2" --config "$TMP/sk.json" --gate sk --run-id r15)"; rc=$?
has "$out" "CHECK skills PASS" && [ "$rc" -eq 0 ] && ok || fail "skills dir: komenda nie PASS ($rc): $out"
grep -qF "SKILLS_OK $SK" .ai/workspace/runs/r15/sk.skills.log && ok || fail "skills dir: AV_SKILLS_DIR nie wskazuje katalogu z av-*"
jq '.requires = {"av-dev": ">=0.1.0"}' "$TMP/sk.json" >"$TMP/req.json"
out="$(bash "$G2" --config "$TMP/req.json" --list)"; rc=$?
has "$out" "AV_DEV dev" && has "$out" "WARNING wersja av-dev nieznana (dev), wymagane >=0.1.0" && [ "$rc" -eq 0 ] && ok || fail "wersja dev: $rc $out"
out="$(bash "$G2" --config "$TMP/req.json" --gate quick --run-id r16)"; rc=$?
has "$out" "WARNING wersja av-dev nieznana" && has "$out" "GATE quick PASS" && [ "$rc" -eq 0 ] && ok || fail "wersja dev: bramka nie ruszyla ($rc)"
echo "0.2.0" >"$SK/av-verify/VERSION"
out="$(bash "$G2" --config "$TMP/req.json" --list)"; rc=$?
has "$out" "AV_DEV 0.2.0" && [ "$rc" -eq 0 ] && ok || fail "wersja 0.2.0: $rc $out"
has "$out" "WARNING wersja" && fail "wersja 0.2.0: zbedne ostrzezenie" || ok
jq '.requires = {"av-dev": ">=0.10.0"}' "$TMP/sk.json" >"$TMP/req2.json"
out="$(bash "$G2" --config "$TMP/req2.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev: zainstalowana wersja av-dev 0.2.0, wymagane >=0.10.0" && [ "$rc" -eq 2 ] && ok || fail "wersja za niska --list: $rc $out"
out="$(bash "$G2" --config "$TMP/req2.json" --gate quick --run-id r17)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev" && [ "$rc" -eq 2 ] && ok || fail "wersja za niska --gate: $rc"
echo "0.10.0" >"$SK/av-verify/VERSION"
out="$(bash "$G2" --config "$TMP/req2.json" --list)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "wersja 0.10.0 >= 0.10.0: kod $rc"
jq '.requires = {"av-dev": ">=0.9.1"}' "$TMP/sk.json" >"$TMP/req3.json"
out="$(bash "$G2" --config "$TMP/req3.json" --list)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "wersja 0.10.0 >= 0.9.1 (porownanie liczbowe): kod $rc"
jq '.requires = {"av-dev": "^0.1.0"}' "$TMP/sk.json" >"$TMP/req4.json"
out="$(bash "$G2" --config "$TMP/req4.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR requires.av-dev: obslugiwany tylko format >=X.Y.Z" && [ "$rc" -eq 2 ] && ok || fail "zly format requires: $rc $out"

# --- 12g. parallel: komendy w tle obok reszty bramki, wynik w kolejnosci bramki (P1)
jq '.validation.commands += {
      "p1": {"run": "sleep 3; echo P1", "expect": "P1", "parallel": true},
      "fgc": {"run": "sleep 3; echo FG"},
      "p2": {"run": "echo P2", "parallel": true},
      "pslow": {"run": "sleep 27; echo never", "timeoutSec": 1, "parallel": true},
      "pbad": {"run": "echo zle; exit 5", "parallel": true},
      "pdown": {"run": "exit 2", "notRunExitCodes": [2], "parallel": true},
      "ppre": {"run": "echo x", "precheck": "true && test -d /nie/ma/tla", "parallel": true},
      "popt": {"run": "echo x", "precheck": "false", "optional": true, "parallel": true},
      "pmut": {"run": "echo m >bg-new.txt; echo done", "parallel": true},
      "pbuild": {"run": "echo BUILT", "parallel": true},
      "pui": {"run": "echo DEVICE_OK", "expect": "DEVICE_OK", "covers": ["pbuild"]},
      "plong": {"run": "sleep 29", "parallel": true},
      "fglong": {"run": "sleep 31"},
      "pflag": {"run": "echo x", "parallel": "yes"}}
    | .validation.gates += {"pg": ["p1", "fgc", "p2"], "pfail": ["pslow", "pbad", "pdown", "ppre", "popt", "fgc"],
                            "pmutg": ["pmut", "fgc"], "pcov": ["pbuild", "pui"], "plongg": ["plong", "fglong"]}' "$good" >"$TMP/par.json"
jq 'del(.validation.commands.pflag)' "$TMP/par.json" >"$TMP/par-ok.json"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --list)"; rc=$?
has "$out" "COMMAND p1: sleep 3; echo P1 expect='P1' parallel" && [ "$rc" -eq 0 ] && ok || fail "parallel: --list bez flagi ($rc): $out"
out="$(bash "$GATE" --config "$TMP/par.json" --list)"; rc=$?
has "$out" "CONFIG_ERROR komenda 'pflag': pole parallel musi byc true albo false" && [ "$rc" -eq 2 ] && ok || fail "parallel: zly typ nie odrzucony ($rc)"
t0="$(date +%s)"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pg --run-id r20)"; rc=$?
took=$(( $(date +%s) - t0 ))
[ "$rc" -eq 0 ] && has "$out" "GATE pg PASS run=r20" && ok || fail "parallel: bramka nie PASS ($rc): $out"
[ "$took" -lt 6 ] && ok || fail "parallel: bramka trwala ${took}s, komendy nie szly obok siebie"
has "$out" "PARALLEL p1 p2 (w tle obok reszty bramki)" && ok || fail "parallel: brak linii PARALLEL: $out"
order="$(printf '%s\n' "$out" | sed -En 's/^(RUN|CHECK) ([a-z0-9]+)[: ].*/\1 \2/p' | tr '\n' ',')"
[ "$order" = "RUN p1,CHECK p1,RUN fgc,CHECK fgc,RUN p2,CHECK p2," ] && ok || fail "parallel: kolejnosc wyjscia $order"
has "$out" "CHECK p1 PASS 3s .ai/workspace/runs/r20/pg.p1.log" && ok || fail "parallel: czas albo log p1: $out"
grep -qx P1 .ai/workspace/runs/r20/pg.p1.log && grep -qx P2 .ai/workspace/runs/r20/pg.p2.log && ok || fail "parallel: logi komend w tle"
jq -e '.checks | (.p1.status == "PASS" and .p1.duration == 3 and .p1.exit == 0 and .p2.status == "PASS" and .fgc.status == "PASS")' .ai/workspace/runs/r20/evidence.json >/dev/null && ok || fail "parallel: dowody"
jq -e '[.checks[] | .fingerprint] | unique | length == 1' .ai/workspace/runs/r20/evidence.json >/dev/null && ok || fail "parallel: rozne odciski"
[ "$(jq -r '.checks | keys_unsorted | join(",")' .ai/workspace/runs/r20/evidence.json)" = "p1,fgc,p2" ] && ok || fail "parallel: dowody nie w kolejnosci bramki"
[ -z "$(ls -A .ai/workspace/runs/r20 | grep -E '^\.(bg|lock|timeout|records)')" ] && ok || fail "parallel: pliki robocze zostaly: $(ls -A .ai/workspace/runs/r20)"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --status --run-id r20)"
has "$out" "CHECK p1 PASS FRESH" && ok || fail "parallel: status nie FRESH"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pfail --run-id r21)"; rc=$?
has "$out" "CHECK pslow FAIL 1s .ai/workspace/runs/r21/pfail.pslow.log (timeout 1s)" && ok || fail "parallel: timeout w tle: $out"
pgrep -f "sleep 27" >/dev/null && fail "parallel: proces po timeoucie zyje" || ok
has "$out" "CHECK pbad FAIL" && has "$out" "(kod wyjscia 5)" && has "$out" "  zle" && ok || fail "parallel: kod wyjscia i ogon logu: $out"
has "$out" "CHECK pdown NOT_RUN" && has "$out" "kod wyjscia 2 oznacza brak srodowiska" && ok || fail "parallel: notRunExitCodes"
has "$out" "CHECK ppre NOT_RUN" && has "$out" "precheck nie przeszedl na: test -d /nie/ma/tla" && ok || fail "parallel: precheck: $out"
has "$out" "RUN ppre" && fail "parallel: RUN mimo nieudanego precheck" || ok
has "$out" "CHECK popt SKIPPED" && ok || fail "parallel: optional"
has "$out" "GATE pfail FAIL" && [ "$rc" -eq 1 ] && ok || fail "parallel: bramka z porazkami ($rc)"
jq -e '.checks.pslow.exit == 124 and .checks.pbad.exit == 5 and (.checks.pbad.tail | index("zle") != null)' .ai/workspace/runs/r21/evidence.json >/dev/null && ok || fail "parallel: dowod porazek"
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pmutg --run-id r22)"; rc=$?
has "$out" "GATE pmutg STALE" && [ "$rc" -eq 3 ] && ok || fail "parallel: zmiana drzewa z tla nie daje STALE ($rc): $out"
rm -f bg-new.txt
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pcov --run-id r23)"
has "$out" "CHECK pbuild PASS 0s (pokryte przez pui)" && ok || fail "parallel: komenda pokryta uruchomiona w tle: $out"
has "$out" "PARALLEL" && fail "parallel: pokryta komenda w tle" || ok
bash "$GATE" --config "$TMP/par-ok.json" --gate pg --run-id r24 >/dev/null
out="$(bash "$GATE" --config "$TMP/par-ok.json" --gate pg --reuse-fresh --run-id r24)"
has "$out" "PARALLEL" && fail "parallel: komenda z dowodem FRESH uruchomiona w tle: $out" || ok
has "$out" "CHECK p1 PASS 0s (dowod FRESH uzyty ponownie" && ok || fail "parallel: reuse w tle: $out"
bash "$GATE" --config "$TMP/par-ok.json" --gate plongg --run-id r25 >/dev/null 2>&1 &
gpid=$!
n=0; while ! pgrep -f "sleep 31" >/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -TERM "$gpid"; wait "$gpid" 2>/dev/null
n=0; while pgrep -f "sleep (29|31)" >/dev/null && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
pgrep -f "sleep (29|31)" >/dev/null && { fail "parallel: komenda zyje po przerwaniu bramki"; pkill -f "sleep (29|31)"; } || ok
[ ! -d .ai/workspace/runs/r25/.lock ] && [ -z "$(ls -A .ai/workspace/runs/r25 | grep -E '^\.bg')" ] && ok || fail "parallel: blokada albo .bg po przerwaniu"

# --- 13. workspace poza .gitignore nie zmienia odcisku
git rm -q --cached .gitignore && rm .gitignore && git commit -qm "no ignore"
bash "$GATE" --only ok --run-id r9 >/dev/null
out="$(bash "$GATE" --status --run-id r9)"
has "$out" "CHECK ok PASS FRESH" && ok || fail "odcisk zalezy od plikow dowodow"

# Parameter-sensitive reuse, with external config (outside repository fingerprint).
cat >"$TMP/reuse.json" <<'EOF'
{"version":1,"paths":{"workspace":".ai/workspace"},"validation":{"commands":{"probe":{"run":"test \"$SUITE\" = A"}},"gates":{"quick":["probe"]}}}
EOF
bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=A --run-id params >/dev/null
out="$(bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=B --reuse-fresh --run-id params)"; rc=$?
[ "$rc" = 1 ] && has "$out" "RUN probe" && ok || fail "changed env reused PASS"
bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=A --env EXTRA=x --run-id params >/dev/null
out="$(bash "$GATE" --config "$TMP/reuse.json" --only probe --env EXTRA=x --env SUITE=A --reuse-fresh --run-id params)"
has "$out" "dowod FRESH uzyty ponownie" && ok || fail "env order invalidates reuse"
out="$(bash "$GATE" --config "$TMP/reuse.json" --only probe --env SUITE=B --env SUITE=A --env EXTRA=x --reuse-fresh --run-id params)"
has "$out" "dowod FRESH uzyty ponownie" && ok || fail "last env value not canonical"
for field in run precheck; do
  jq --arg f "$field" '.validation.commands.probe[$f]="false"' "$TMP/reuse.json" >"$TMP/changed.json"
  out="$(bash "$GATE" --config "$TMP/changed.json" --only probe --env SUITE=A --env EXTRA=x --reuse-fresh --run-id params)"; rc=$?
  [ "$rc" != 0 ] && ! has "$out" "dowod FRESH uzyty ponownie" && ok || fail "changed $field reused PASS"
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

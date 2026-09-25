#!/usr/bin/env bash
# gate.sh - bramki walidacji av-dev.
#
# Uruchamia tylko komendy z .ai/av.config.json i zapisuje dowody z odciskiem
# stanu drzewa roboczego. Dowod jest STALE, gdy kod zmienil sie po pomiarze.
#
# Uzycie:
#   gate.sh --list                          sprawdz config i wypisz bramki
#   gate.sh --gate quick [--run-id ID]      uruchom bramke
#   gate.sh --only lint,unit [--run-id ID]  uruchom wybrane komendy
#   gate.sh --baseline --gate quick --run-id ID   pomiar przed zmianami
#   gate.sh --status --run-id ID            FRESH/STALE dla zapisanych dowodow
#   gate.sh --fingerprint                   odcisk biezacego stanu
#   gate.sh --gate full --reuse-fresh --run-id ID   pomin komendy z PASS dla tego samego odcisku
# Opcje wspolne:
#   --root DIR            root repo (domyslnie repo z biezacego katalogu)
#   --config PLIK         inny config, np. proponowany w dry-run
#   --env KLUCZ=WARTOSC   parametr komend, powtarzalny (np. UI_SUITE=LoginTests)
#   --no-local            pomin lokalne nadpisanie <config>.local
# Config efektywny: config zespolu plus <config>.local (config.sh obok). --list
#   wypisuje CONFIG_LOCAL i nadpisane klucze, bramka linie CONFIG_LOCAL.
#
# Pola komendy: run, expect, precheck, needs, timeoutSec, cwd,
#   notRunExitCodes, optional, covers, parallel.
# parallel: true = komenda nie dzieli stanu z innymi; startuje w tle na poczatku
#   bramki, obok reszty. Wyniki, logi i dowody wypisuje w kolejnosci bramki.
#   Komenda z covers albo pokryta przez inna komende bramki idzie po kolei.
# Kody wyjscia: 0 PASS, 1 FAIL, 2 blad configu, 3 niekompletne (NOT_RUN albo STALE:
#   drzewo zmienilo sie w trakcie bramki), 4 inna bramka tego przebiegu jest w toku (BUSY).
# Srodowisko komend: AV_SKILLS_DIR = katalog z av-* (rodzic katalogu av-verify).
# Wersja: plik VERSION w katalogu skilla (brak = dev); config moze wymagac
#   "requires": {"av-dev": ">=X.Y.Z"}.
# Wymaga: bash 3.2+, git, jq.

set -uo pipefail

DEFAULT_TIMEOUT=900
Q="'"
TAIL_LINES=30

config_error() {
  printf 'CONFIG_ERROR %s\n' "$1"
  exit 2
}

command -v jq >/dev/null 2>&1 || config_error "brak jq; zainstaluj jq (brew install jq)"
command -v git >/dev/null 2>&1 || config_error "brak git"

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
AV_SKILLS_DIR="$(cd "$skill_dir/.." && pwd)"
export AV_SKILLS_DIR
av_version="dev"
if [ -f "$skill_dir/VERSION" ]; then
  av_version="$(head -n 1 "$skill_dir/VERSION" | tr -d ' \t\r')"
  [ -n "$av_version" ] || av_version="dev"
fi

# MARK: argumenty

mode=""
gate_name=""
only=""
run_id=""
baseline=0
reuse=0
env_keys=""
root_arg=""
config_arg=""
no_local=0

while [ $# -gt 0 ]; do
  case "$1" in
    --list) mode="list" ;;
    --status) mode="status" ;;
    --fingerprint) mode="fingerprint" ;;
    --baseline) baseline=1 ;;
    --reuse-fresh) reuse=1 ;;
    --gate) gate_name="${2:-}"; shift ;;
    --only) only="${2:-}"; shift ;;
    --run-id) run_id="${2:-}"; shift ;;
    --root) root_arg="${2:-}"; shift ;;
    --config) config_arg="${2:-}"; shift ;;
    --no-local) no_local=1 ;;
    --env)
      kv="${2:-}"; shift
      case "$kv" in
        *=*) key="${kv%%=*}"; val="${kv#*=}" ;;
        *) config_error "--env wymaga KLUCZ=WARTOSC, dostalem '$kv'" ;;
      esac
      printf '%s' "$key" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || config_error "niepoprawna nazwa zmiennej '$key'"
      env_keys="${env_keys}${key}\n"
      export "$key=$val"
      ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) config_error "nieznany argument '$1'" ;;
  esac
  shift
done

# MARK: repo i config

if [ -n "$root_arg" ]; then
  root="$(git -C "$root_arg" rev-parse --show-toplevel 2>/dev/null || (cd "$root_arg" && pwd))"
else
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

hash_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}

workspace=".ai/workspace"

fingerprint() {
  local head
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)"
  {
    printf '%s\n' "$head"
    git -C "$root" diff HEAD --binary -- . ":(exclude)$workspace/" ":(exclude).ai/workspace/" 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard -z -- . ":(exclude)$workspace/" ":(exclude).ai/workspace/" 2>/dev/null |
      while IFS= read -r -d '' f; do
        printf '%s\n' "$f"
        [ -f "$root/$f" ] && hash_cmd < "$root/$f"
      done
  } | hash_cmd | cut -c1-16
}

if [ "$mode" = "fingerprint" ]; then
  printf 'HEAD %s\nFINGERPRINT %s\n' "$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)" "$(fingerprint)"
  exit 0
fi

cfg="${config_arg:-$root/.ai/av.config.json}"
[ -f "$cfg" ] || config_error "brak $cfg; uruchom skill av-setup"
jq empty "$cfg" 2>/dev/null || config_error "niepoprawny JSON w $cfg"
jq -e 'type == "object"' "$cfg" >/dev/null 2>&1 || config_error "config $cfg nie jest obiektem JSON"

merged_cfg=""
config_sources=""
if [ "$no_local" -eq 0 ] && [ -f "$cfg.local" ]; then
  merged_cfg="$(mktemp "${TMPDIR:-/tmp}/av-config.XXXXXX")" || config_error "nie moge utworzyc pliku tymczasowego"
  trap 'rm -f "$merged_cfg"' EXIT
  merge_out="$(bash "$skill_dir/scripts/config.sh" --root "$root" --config "$cfg" --out "$merged_cfg")" || {
    printf '%s\n' "$merge_out" | grep '^CONFIG_ERROR' || printf 'CONFIG_ERROR nie moge polaczyc %s.local\n' "$cfg"
    exit 2
  }
  config_sources="$(bash "$skill_dir/scripts/config.sh" --root "$root" --config "$cfg" --sources | grep -v '^CONFIG ')"
  cfg="$merged_cfg"
fi

workspace="$(jq -r '(.paths.workspace // ".ai/workspace") | sub("/+$"; "")' "$cfg")"
runs_base="$(jq -r --arg ws "$workspace" '.paths.runs // ($ws + "/runs")' "$cfg")"

validation_errors() {
  jq -r --arg q "$Q" '
    (.validation.commands // {}) as $c
    | ( $c | to_entries[]
        | select((.value | type) != "object" or ((.value.run // "") == ""))
        | "komenda \($q)\(.key)\($q) nie ma pola run" ),
      ( $c | to_entries[] | select(.value | type == "object") | .key as $k
        | (.value.covers // [])[] | select($c[.] == null)
        | "komenda \($q)\($k)\($q) pokrywa nieznana komende \($q)\(.)\($q)" ),
      ( $c | to_entries[] | select(.value | type == "object")
        | select(.value | has("parallel") and (.parallel | type) != "boolean")
        | "komenda \($q)\(.key)\($q): pole parallel musi byc true albo false" ),
      ( (.validation.gates // {}) | to_entries[] | .key as $g | .value[]
        | select($c[.] == null)
        | "bramka \($q)\($g)\($q) wskazuje nieznana komende \($q)\(.)\($q)" )
  ' "$cfg"
}

# MARK: walidacja pol configu

schema_errors() {
  jq -r '
    def isstr: type == "string";
    def strarr: type == "array" and all(.[]; type == "string");
    def claudemodel: isstr and (IN("inherit", "opus", "sonnet", "haiku", "fable") or test("^claude-[a-z0-9.-]+$"));
    def slot: if isstr then {provider: "claude", model: .}
              else {provider: (.provider // "claude"), model: (.model // "inherit"), effort: (.effort // "inherit")} end;
    ["inherit", "opus", "sonnet", "haiku", "fable"] as $models
    | {claude: ["inherit", "low", "medium", "high", "xhigh", "max"],
       codex: ["inherit", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]} as $efforts
    | ["on-request", "after-green-gate", "free"] as $commits
    | ["never", "on-request"] as $pushes
    | ( if has("agents") and (.agents | type) != "object" then "agents: oczekiwany obiekt"
        elif (.agents | type) == "object" then
          ( if (.agents | has("models")) and (.agents.models | type) != "object" then "agents.models: oczekiwany obiekt"
            elif (.agents | has("models")) then
              ( .agents.models | to_entries[] | .key as $k | .value as $v | "agents.models.\($k)" as $p
                | if ($v | isstr) then
                    ( if ($v | claudemodel) then empty
                      else "\($p): niedozwolona wartosc \($v | tojson); dozwolone: \($models | join(", ")), claude-<id> albo obiekt {provider, model, effort}" end )
                  elif ($v | type) != "object" then "\($p): oczekiwany napis albo obiekt {provider, model, effort}"
                  else
                    ( $v | keys[] | select(IN("provider", "model", "effort") | not)
                      | "\($p): nieznane pole \(tojson); dozwolone: provider, model, effort" ),
                    ( ($v.provider // "claude") as $pr
                      | if ($pr | isstr | not) or ($efforts[$pr] == null) then "\($p).provider: niedozwolona wartosc \($pr | tojson); dozwolone: claude, codex"
                        else
                          ( if $pr == "claude" and (($v.model // "inherit") | claudemodel | not)
                            then "\($p).model: niedozwolony model claude \($v.model | tojson); dozwolone: \($models | join(", ")) albo claude-<id>"
                            elif $pr == "codex" and ((($v.model // "inherit") | isstr | not) or (($v.model // "inherit") | test("^[A-Za-z0-9][A-Za-z0-9._:-]*$") | not))
                            then "\($p).model: niepoprawna nazwa modelu codex \($v.model | tojson)"
                            else empty end ),
                          ( ($v.effort // "inherit") as $e
                            | if ($e | isstr | not) or ($efforts[$pr] | index([$e]) == null)
                              then "\($p).effort: niedozwolona wartosc \($e | tojson) dla \($pr); dozwolone: \($efforts[$pr] | join(", "))"
                              else empty end )
                        end )
                  end ),
              ( if (.agents.models.review // null) != null and (.agents.models.review | slot | .provider == "claude" and .model == "haiku")
                then "agents.models.review: haiku nie moze robic review; uzyj opus, sonnet, fable, inherit albo modelu codex"
                else empty end )
            else empty end ),
          ( if (.agents | has("crossVendor")) and (.agents.crossVendor | type) != "boolean"
            then "agents.crossVendor: oczekiwane true albo false"
            elif .agents.crossVendor == true then
              ((.agents.models // {}) as $m
               | def prov($s): ($m[$s] // "inherit") | slot | .provider;
                 ( if prov("review") == prov("implement")
                   then "agents.crossVendor: review i implement maja tego samego dostawce \(prov("review") | tojson); kod ma sprawdzac inny dostawca niz go napisal"
                   else empty end ),
                 ( (if $m.planReview != null then "planReview" else "review" end) as $pr
                   | if prov($pr) == prov("plan")
                     then "agents.crossVendor: \($pr) i plan maja tego samego dostawce \(prov("plan") | tojson); ustaw agents.models.planReview na innego dostawce"
                     else empty end ))
            else empty end ),
          ( if (.agents | has("timeoutSec")) and ((.agents.timeoutSec | type) != "number" or .agents.timeoutSec < 1 or (.agents.timeoutSec | floor) != .agents.timeoutSec)
            then "agents.timeoutSec: oczekiwana dodatnia liczba calkowita"
            else empty end )
        else empty end ),
      ( if has("git") and (.git | type) != "object" then "git: oczekiwany obiekt"
        elif (.git | type) == "object" then
          ( if (.git | has("commit")) and (.git.commit as $v | $commits | index([$v]) == null)
            then "git.commit: niedozwolona wartosc \(.git.commit | tojson); dozwolone: \($commits | join(", "))"
            else empty end ),
          ( if (.git | has("push")) and (.git.push as $v | $pushes | index([$v]) == null)
            then "git.push: niedozwolona wartosc \(.git.push | tojson); dozwolone: \($pushes | join(", "))"
            else empty end )
        else empty end ),
      ( if has("roles") | not then empty
        elif (.roles | type) != "array" then "roles: oczekiwana tablica obiektow"
        else
          .roles | to_entries[] | .value as $r
          | "roles[\(.key)]" as $p
          | if ($r | type) != "object" then "\($p): oczekiwany obiekt"
            else
              ( if ($r.name | isstr | not) or $r.name == "" then "\($p).name: oczekiwany niepusty napis" else empty end ),
              ( if ($r.skill | isstr | not) or $r.skill == "" then "\($p).skill: oczekiwany niepusty napis" else empty end ),
              ( if ($r.order | type) != "number" or ($r.order | floor) != $r.order then "\($p).order: oczekiwana liczba calkowita" else empty end ),
              ( if ($r.globs | type) != "array" or ($r.globs | length) == 0 then "\($p).globs: oczekiwana niepusta tablica napisow"
                else
                  $r.globs[]
                  | if isstr | not then "\($p).globs: element \(tojson) nie jest napisem"
                    elif test("[{}]") then "\($p).globs: glob \(tojson) ma nawias klamrowy; wypisz kazdy wariant osobno"
                    else empty end
                end )
            end
        end ),
      ( ("generatedPaths", "unownedPaths") as $k
        | select(has($k) and (.[$k] | strarr | not))
        | "\($k): oczekiwana tablica napisow" ),
      ( if has("requires") and (.requires | type) != "object" then "requires: oczekiwany obiekt"
        elif (.requires | type) == "object" and (.requires | has("av-dev")) and (.requires["av-dev"] | isstr | not)
        then "requires.av-dev: oczekiwany napis w formacie >=X.Y.Z"
        else empty end )
  ' "$cfg"
}

semver_lt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<EOF
$1
EOF
  IFS=. read -r b1 b2 b3 <<EOF
$2
EOF
  [ $((10#$a1)) -ne $((10#$b1)) ] && { [ $((10#$a1)) -lt $((10#$b1)) ]; return; }
  [ $((10#$a2)) -ne $((10#$b2)) ] && { [ $((10#$a2)) -lt $((10#$b2)) ]; return; }
  [ $((10#$a3)) -lt $((10#$b3)) ]
}

version_warning=""
version_error=""
required="$(jq -r 'if (.requires | type) == "object" and (.requires["av-dev"] | type) == "string" then .requires["av-dev"] else "" end' "$cfg")"
if [ -n "$required" ]; then
  semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
  if ! printf '%s' "${required#>=}" | grep -Eq "$semver_re" || [ "${required#>=}" = "$required" ]; then
    version_error="requires.av-dev: obslugiwany tylko format >=X.Y.Z, dostalem '$required'"
  elif [ "$av_version" = "dev" ]; then
    version_warning="wersja av-dev nieznana (dev), wymagane $required"
  elif ! printf '%s' "${av_version%%[-+]*}" | grep -Eq "$semver_re"; then
    version_warning="wersja av-dev '$av_version' w nieznanym formacie, wymagane $required"
  elif semver_lt "${av_version%%[-+]*}" "${required#>=}"; then
    version_error="requires.av-dev: zainstalowana wersja av-dev $av_version, wymagane $required; zaktualizuj skille av-*"
  fi
fi
config_problems="$(schema_errors)"
[ -n "$version_error" ] && config_problems="${config_problems:+$config_problems
}$version_error"

# MARK: --list

if [ "$mode" = "list" ]; then
  printf 'AV_DEV %s\n' "$av_version"
  [ -n "$config_sources" ] && printf '%s\n' "$config_sources"
  [ -n "$version_warning" ] && printf 'WARNING %s\n' "$version_warning"
  jq -r --arg q "$Q" '
    (.validation.commands // {}) | to_entries[] | select(.value | type == "object")
    | "COMMAND \(.key): \(.value.run // "")"
      + (if .value.expect then " expect=\($q)\(.value.expect)\($q)" else "" end)
      + (if .value.precheck then " precheck" else "" end)
      + (if .value.cwd then " cwd=\(.value.cwd)" else "" end)
      + (if .value.optional then " optional" else "" end)
      + (if (.value.covers // []) | length > 0 then " covers=\(.value.covers | join(","))" else "" end)
      + (if .value.parallel == true then " parallel" else "" end)
  ' "$cfg"
  jq -r '(.validation.gates // {}) | to_entries[] | "GATE \(.key): \(.value | join(", "))"' "$cfg"
  errors="$(validation_errors)"
  [ -n "$config_problems" ] && errors="$config_problems${errors:+
$errors}"
  while IFS=$'\t' read -r name field text; do
    [ -n "$name" ] || continue
    if ! bash -n -c "$text" 2>/dev/null; then
      errors="${errors:+$errors
}komenda '$name': blad skladni w polu $field"
    fi
    rest_cmd="$text"
    while printf '%s' "${rest_cmd%% *}" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*='; do rest_cmd="${rest_cmd#* }"; done
    first="${rest_cmd%% *}"
    case "$first" in
      */*) [ -e "$root/$(jq -r --arg n "$name" '.validation.commands[$n].cwd // "."' "$cfg")/$first" ] ||
             printf 'WARNING komenda %s: brak pliku %s\n' "$name" "$first" ;;
    esac
  done < <(jq -r '(.validation.commands // {}) | to_entries[] | select(.value | type == "object")
                 | .key as $k | (["run", "precheck"][] as $f | select(.value[$f] != null) | [$k, $f, .value[$f]] | @tsv)' "$cfg")
  count="$(jq '(.validation.commands // {}) | length' "$cfg")"
  [ -n "$errors" ] && printf '%s\n' "$errors" | sed 's/^/CONFIG_ERROR /'
  [ "$count" -eq 0 ] && echo "CONFIG_ERROR brak validation.commands"
  if [ -n "$errors" ] || [ "$count" -eq 0 ]; then exit 2; fi
  exit 0
fi

if [ -n "$config_problems" ]; then
  printf '%s\n' "$config_problems" | sed 's/^/CONFIG_ERROR /'
  exit 2
fi
[ -n "$version_warning" ] && printf 'WARNING %s\n' "$version_warning"
[ -n "$config_sources" ] && printf '%s\n' "$config_sources" | grep -E '^(CONFIG_LOCAL|WARNING) '

[ -n "$run_id" ] || run_id="adhoc-$(date +%Y%m%d-%H%M%S)"
out_dir="$root/$runs_base/$run_id"
mkdir -p "$out_dir"

# MARK: --status

if [ "$mode" = "status" ]; then
  fp="$(fingerprint)"
  code=0
  for fname in baseline.json evidence.json; do
    file="$out_dir/$fname"
    [ -f "$file" ] || continue
    label="CHECK"; [ "$fname" = "baseline.json" ] && label="BASELINE"
    while IFS=$'\t' read -r name status recstale recfp log rechead; do
      if [ "$label" = "BASELINE" ]; then
        printf 'BASELINE %s %s pomiar-bazowy head=%s %s\n' "$name" "$status" "$(printf '%s' "$rechead" | cut -c1-8)" "$log"
        continue
      fi
      fresh="STALE"; [ "$recfp" = "$fp" ] && [ "$recstale" = "0" ] && fresh="FRESH"
      note=""; [ "$recstale" = "1" ] && note=" (drzewo zmienilo sie w trakcie bramki)"
      printf '%s %s %s %s %s%s\n' "$label" "$name" "$status" "$fresh" "$log" "$note"
      if [ "$label" = "CHECK" ] && { [ "$fresh" = "STALE" ] || { [ "$status" != "PASS" ] && [ "$status" != "SKIPPED" ]; }; }; then
        code=1
      fi
    done < <(jq -r '.checks | to_entries[]
                   | [.key, .value.status, (if .value.stale == true then "1" else "0" end),
                      (.value.fingerprint // "-"), (.value.log // "-"), (.value.head // "-")] | @tsv' "$file")
  done
  printf 'FINGERPRINT %s\n' "$fp"
  if [ -d "$out_dir/.lock" ]; then
    printf 'BUSY bramka w toku: %s\n' "$(cat "$out_dir/.lock/owner" 2>/dev/null)"
    exit 4
  fi
  exit "$code"
fi

# MARK: wybor komend

errors="$(validation_errors)"
[ -n "$errors" ] && printf '%s\n' "$errors" | sed 's/^/WARNING /'

if [ -n "$gate_name" ]; then
  jq -e --arg g "$gate_name" '.validation.gates[$g] != null' "$cfg" >/dev/null ||
    config_error "nieznana bramka '$gate_name'; dostepne: $(jq -r '(.validation.gates // {}) | keys | join(", ")' "$cfg")"
  names_json="$(jq -c --arg g "$gate_name" '.validation.gates[$g]' "$cfg")"
  label="$gate_name"
elif [ -n "$only" ]; then
  names_json="$(printf '%s' "$only" | jq -R -c 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"
  label="$(printf '%s' "$names_json" | jq -r 'join("+")')"
else
  config_error "podaj --gate, --only, --list, --status albo --fingerprint"
fi

bad="$(jq -r --argjson n "$names_json" '[ $n[] as $x | select((.validation.commands[$x].run // "") == "") | $x ] | join(", ")' "$cfg")"
if [ -n "$bad" ]; then
  if [ -n "$gate_name" ]; then config_error "bramka '$gate_name' ma niepoprawne komendy: $bad"; fi
  config_error "nieznane komendy: $bad"
fi

ordered="$(jq -r --argjson n "$names_json" '
  .validation.commands as $c
  | ($n | map(select(($c[.].covers // []) | length > 0))) + ($n | map(select(($c[.].covers // []) | length == 0)))
  | .[]' "$cfg")"

# MARK: uruchomienie

cmd_field() {
  jq -r --arg n "$1" --arg f "$2" '.validation.commands[$n][$f] // empty | if type == "array" then join(" ") else tostring end' "$cfg"
}

run_timed() {
  local cmd="$1" cwd="$2" limit="$3" log="$4" marker="$5" pidfile="${6:-}"
  rm -f "$marker"
  set -m
  ( cd "$cwd" && exec bash -c "$cmd" ) >"$log" 2>&1 &
  local pid=$!
  [ -n "$pidfile" ] && printf '%s\n' "$pid" >"$pidfile"
  ( sleep "$limit"; : >"$marker"; kill -TERM -- "-$pid" 2>/dev/null; sleep 3; kill -KILL -- "-$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  set +m
  rc=0
  wait "$pid" 2>/dev/null || rc=$?
  kill -TERM -- "-$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  timed_out=0
  [ -f "$marker" ] && timed_out=1
  rm -f "$marker"
  return 0
}

lock="$out_dir/.lock"
if ! mkdir "$lock" 2>/dev/null; then
  printf 'BUSY inna bramka przebiegu %s jest w toku (%s); poczekaj na jej koniec\n' "$run_id" "$(cat "$lock/owner" 2>/dev/null)"
  exit 4
fi
printf '%s pid %s\n' "$label" "$$" >"$lock/owner"
bg_dir="$out_dir/.bg.$$"
mkdir -p "$bg_dir"
cleanup() {
  local f
  for f in "$bg_dir"/*.cmdpid; do
    [ -f "$f" ] && kill -TERM -- "-$(cat "$f")" 2>/dev/null
  done
  rm -rf "$lock" "$bg_dir"
  [ -n "$merged_cfg" ] && rm -f "$merged_cfg"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
log_prefix="$label"; [ "$baseline" -eq 1 ] && log_prefix="baseline.$label"
log_prefix="$(printf '%s' "$log_prefix" | tr -c 'A-Za-z0-9._-' '_')"

records="$out_dir/.records.$$.jsonl"
: >"$records"
passed=""
fp_before="$(fingerprint)"
head_before="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)"

# Invocation identity is separate from source freshness. Never persist raw env values.
invocation_fingerprint() {
  {
    printf '%s\n' "$root" "$AV_SKILLS_DIR"
    hash_cmd < "$skill_dir/scripts/gate.sh"
    jq -cS --arg n "$1" '.validation.commands[$n]' "$cfg"
    printf '%b' "$env_keys" | LC_ALL=C sort -u | while IFS= read -r key; do
      [ -n "$key" ] || continue
      printf '%s\n' "$key"
      printf '%s' "${!key}" | hash_cmd
    done
  } | hash_cmd | cut -d ' ' -f1
}

reused_log() {
  [ "$reuse" -eq 1 ] && [ "$baseline" -eq 0 ] && [ -f "$out_dir/evidence.json" ] || return 0
  jq -r --arg n "$1" --arg fp "$fp_before" --arg invocation "$(invocation_fingerprint "$1")" '.checks[$n] | select(.status == "PASS" and .fingerprint == $fp and .invocationFingerprint == $invocation and (.stale != true)) | .log // "x"' "$out_dir/evidence.json" 2>/dev/null
}

# MARK: komendy w tle
# Wynik komendy w tle: plik <nazwa>.result z polami pre, rc, timed_out, duration,
# started. Petla ponizej czeka na nia w kolejnosci bramki.

bg_names="$(jq -r --argjson n "$names_json" '
  .validation.commands as $c
  | ([$n[] | ($c[.].covers // [])[]]) as $covered
  | $n[] | . as $x
  | select($c[$x].parallel == true and (($c[$x].covers // []) | length == 0) and (any($covered[]; . == $x) | not))' "$cfg")"
bg_started=""
for name in $bg_names; do
  [ -z "$(reused_log "$name")" ] || continue
  cwd="$root/$(cmd_field "$name" cwd)"
  limit="$(cmd_field "$name" timeoutSec)"; limit="${limit:-$DEFAULT_TIMEOUT}"
  precheck="$(cmd_field "$name" precheck)"
  run="$(cmd_field "$name" run)"
  log="$root/$runs_base/$run_id/$log_prefix.$name.log"
  (
    started="$(date +%Y-%m-%dT%H:%M:%S)"
    pre=1; rc=0; timed_out=0; duration=0
    if [ -n "$precheck" ] && ! ( cd "$cwd" && bash -x -c "$precheck" ) >"$log" 2>&1; then
      pre=0
    else
      start_s="$(date +%s)"
      run_timed "$run" "$cwd" "$limit" "$log" "$out_dir/.timeout.$name" "$bg_dir/$name.cmdpid"
      duration=$(( $(date +%s) - start_s ))
      rm -f "$bg_dir/$name.cmdpid"
    fi
    printf '%s %s %s %s %s\n' "$pre" "$rc" "$timed_out" "$duration" "$started" >"$bg_dir/$name.result.tmp"
    mv "$bg_dir/$name.result.tmp" "$bg_dir/$name.result"
  ) </dev/null &
  printf '%s\n' "$!" >"$bg_dir/$name.pid"
  bg_started="$bg_started $name"
done
[ -n "$bg_started" ] && printf 'PARALLEL%s (w tle obok reszty bramki)\n' "$bg_started"

# MARK: jedna komenda
# check_one NAZWA wypisuje linie RUN i CHECK komendy, dopisuje rekord do pliku
# REKORD i dodaje nazwe do $passed przy PASS. Komende z tla tylko odbiera.
check_one() {
  local name="$1" rec="$2"
  started="$(date +%Y-%m-%dT%H:%M:%S)"
  run="$(cmd_field "$name" run)"
  log_rel="$runs_base/$run_id/$log_prefix.$name.log"
  log="$root/$log_rel"
  status=""; reason=""; rc=0; duration=0; covered_by=""

  for p in $passed; do
    if jq -e --arg p "$p" --arg n "$name" '(.validation.commands[$p].covers // []) | index($n) != null' "$cfg" >/dev/null; then
      covered_by="$p"; break
    fi
  done

  reused=""
  [ -z "$covered_by" ] && reused="$(reused_log "$name")"
  in_bg=0
  case " $bg_started " in *" $name "*) in_bg=1 ;; esac
  if [ -n "$covered_by" ]; then
    status="PASS"
    printf 'CHECK %s PASS 0s (pokryte przez %s)\n' "$name" "$covered_by"
  elif [ -n "$reused" ]; then
    status="PASS"
    log_rel="$reused"
    printf 'CHECK %s PASS 0s (dowod FRESH uzyty ponownie: %s)\n' "$name" "$reused"
  else
    cwd="$root/$(cmd_field "$name" cwd)"
    limit="$(cmd_field "$name" timeoutSec)"; limit="${limit:-$DEFAULT_TIMEOUT}"
    precheck="$(cmd_field "$name" precheck)"
    needs="$(cmd_field "$name" needs)"
    pre=1
    if [ "$in_bg" -eq 1 ]; then
      wait "$(cat "$bg_dir/$name.pid")" 2>/dev/null
      if [ -f "$bg_dir/$name.result" ]; then
        read -r pre rc timed_out duration started <"$bg_dir/$name.result"
      else
        pre=1; rc=1; timed_out=0; duration=0
        printf '\n[komenda w tle zakonczyla sie bez wyniku]\n' >>"$log"
      fi
    elif [ -n "$precheck" ] && ! ( cd "$cwd" && bash -x -c "$precheck" ) >"$log" 2>&1; then
      pre=0
    fi
    if [ "$pre" -eq 0 ]; then
      status="NOT_RUN"
      failed_step="$(grep '^+' "$log" | tail -1 | sed 's/^+* *//' | cut -c1-120)"
      reason="precheck nie przeszedl na: ${failed_step:-$precheck}; wymaga: ${needs:-$precheck}"
    else
      printf 'RUN %s: %s\n' "$name" "$run"
      if [ "$in_bg" -eq 0 ]; then
        start_s="$(date +%s)"
        run_timed "$run" "$cwd" "$limit" "$log" "$out_dir/.timeout.$name" "$bg_dir/fg@.cmdpid"
        duration=$(( $(date +%s) - start_s ))
        rm -f "$bg_dir/fg@.cmdpid"
      fi
      expect="$(cmd_field "$name" expect)"
      if [ "$timed_out" -eq 1 ]; then
        status="FAIL"; reason="timeout ${limit}s"; rc=124
        printf '\n[timeout po %ss]\n' "$limit" >>"$log"
      elif [ "$rc" -ne 0 ]; then
        if jq -e --arg n "$name" --argjson rc "$rc" '(.validation.commands[$n].notRunExitCodes // []) | index($rc) != null' "$cfg" >/dev/null; then
          status="NOT_RUN"; reason="kod wyjscia $rc oznacza brak srodowiska; wymaga: ${needs:-zobacz log}"
        else
          status="FAIL"; reason="kod wyjscia $rc"
        fi
      elif [ -n "$expect" ] && ! grep -qF -- "$expect" "$log"; then
        status="FAIL"; reason="brak oczekiwanego napisu '$expect'"
      else
        status="PASS"
      fi
    fi
    if [ "$status" = "NOT_RUN" ] && [ "$(cmd_field "$name" optional)" = "true" ]; then
      status="SKIPPED"
    fi
    line="CHECK $name $status ${duration}s $log_rel"
    [ -n "$reason" ] && line="$line ($reason)"
    printf '%s\n' "$line"
    if [ "$status" = "FAIL" ]; then
      echo "  --- koniec logu ---"
      tail -n "$TAIL_LINES" "$log" | sed 's/^/  /'
    fi
  fi

  [ "$status" = "PASS" ] && passed="$passed $name"

  tail_json="[]"
  [ "$status" = "FAIL" ] && tail_json="$(tail -n "$TAIL_LINES" "$log" | jq -R . | jq -s -c .)"
  jq -n -c \
    --arg invocation "$(invocation_fingerprint "$name")" \
    --arg name "$name" --arg run "$run" --arg started "$started" --arg status "$status" \
    --argjson exit "$rc" --argjson duration "$duration" --arg log "$log_rel" \
    --arg reason "$reason" --arg covered "$covered_by" --arg reused "$reused" --argjson tail "$tail_json" \
    '{invocationFingerprint: $invocation, name: $name, run: $run, started: $started, status: $status, exit: $exit, duration: $duration, log: $log}
     + (if $reason != "" then {reason: $reason} else {} end)
     + (if $covered != "" then {covered_by: $covered, log: null} else {} end)
     + (if $reused != "" then {reused: true} else {} end)
     + (if ($tail | length) > 0 then {tail: $tail} else {} end)' >"$rec"
}

# MARK: kolejnosc
# Pierwsze przejscie uruchamia komendy po kolei i pomija komendy z tla, drugie
# odbiera komendy z tla. Komenda, przed ktora wszystko jest juz wypisane, pisze
# od razu; pozostale pisza do pliku z numerem i sa wypisywane w kolejnosci
# bramki, gdy wszystkie wczesniejsze sa gotowe. Rekordy ida w tej samej kolejnosci.
next_out=1
flush_ready() {
  while [ -f "$bg_dir/$next_out.out" ]; do
    cat "$bg_dir/$next_out.out"
    cat "$bg_dir/$next_out.rec" >>"$records"
    next_out=$((next_out + 1))
  done
}
for pass in fg bg; do
  idx=0
  for name in $ordered; do
    idx=$((idx + 1))
    case " $bg_started " in
      *" $name "*) [ "$pass" = "bg" ] || continue ;;
      *) [ "$pass" = "fg" ] || continue ;;
    esac
    if [ "$idx" -eq "$next_out" ]; then
      check_one "$name" "$bg_dir/$idx.rec"
      : >"$bg_dir/$idx.out"
    else
      check_one "$name" "$bg_dir/$idx.rec" >"$bg_dir/$idx.part"
      mv "$bg_dir/$idx.part" "$bg_dir/$idx.out"
    fi
    flush_ready
  done
done

fp_after="$(fingerprint)"
stale=0
if [ "$fp_after" != "$fp_before" ]; then
  stale=1
  echo "WARNING drzewo zmienilo sie w trakcie bramki; dowod oznaczony STALE, powtorz bramke po zakonczeniu edycji"
fi

evidence_name="evidence.json"; [ "$baseline" -eq 1 ] && evidence_name="baseline.json"
evidence="$out_dir/$evidence_name"
[ -f "$evidence" ] || echo '{"checks":{}}' >"$evidence"
jq -s --arg head "$head_before" --arg fp "$fp_before" --arg fpa "$fp_after" --argjson stale "$stale" --slurpfile old "$evidence" '
  reduce .[] as $r ($old[0]; .checks[$r.name] = ($r + {head: $head, fingerprint: $fp}
    + (if $stale == 1 then {stale: true, fingerprintAfter: $fpa} else {} end)))
' "$records" >"$evidence.tmp" && mv "$evidence.tmp" "$evidence"
rm -f "$records"

selected_statuses="$(jq -r --argjson n "$names_json" '.checks as $c | [$n[] | $c[.].status] | join(" ")' "$evidence")"
case " $selected_statuses " in
  *" FAIL "*) result="FAIL"; code=1 ;;
  *" NOT_RUN "*) result="INCOMPLETE"; code=3 ;;
  *) result="PASS"; code=0 ;;
esac
if [ "$stale" -eq 1 ] && [ "$code" -ne 1 ]; then
  result="STALE"; code=3
fi

kind="GATE"; [ "$baseline" -eq 1 ] && kind="BASELINE"
printf '%s %s %s run=%s evidence=%s fingerprint=%s\n' "$kind" "$label" "$result" "$run_id" "$runs_base/$run_id/$evidence_name" "$fp_before"
exit "$code"

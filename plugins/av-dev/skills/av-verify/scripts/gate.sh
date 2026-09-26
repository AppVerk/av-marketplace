#!/usr/bin/env bash
# gate.sh - av-dev validation gates.
#
# Runs only commands from .ai/av.config.json and saves evidence with a fingerprint
# of the working tree state. Evidence is STALE when the code changed after the check.
#
# Usage:
#   gate.sh --list                          check the config and list the gates
#   gate.sh --gate quick [--run-id ID]      run a gate
#   gate.sh --only lint,unit [--run-id ID]  run selected commands
#   gate.sh --baseline --gate quick --run-id ID   baseline before changes
#   gate.sh --status --run-id ID            FRESH/STALE for saved evidence
#   gate.sh --fingerprint                   fingerprint of the current state
#   gate.sh --gate full --reuse-fresh --run-id ID   skip commands with PASS for the same fingerprint
# Common options:
#   --root DIR            repo root (default: the repo of the current directory)
#   --config FILE         another config, e.g. a proposed one in a dry run
#   --env KEY=VALUE       command parameter, repeatable (e.g. UI_SUITE=LoginTests)
#   --no-local            skip the local override <config>.local
# Effective config: team config plus <config>.local (config.sh next to this script).
#   --list prints CONFIG_LOCAL and the overridden keys, a gate prints the CONFIG_LOCAL line.
#
# Command fields: run, expect, precheck, needs, timeoutSec, cwd,
#   notRunExitCodes, optional, covers, parallel.
# parallel: true = the command shares no state with others; it starts in the background
#   when the gate starts, next to the rest. Results, logs and evidence print in gate order.
#   A command with covers, or covered by another command of the gate, runs in sequence.
# Exit codes: 0 PASS, 1 FAIL, 2 config error, 3 incomplete (NOT_RUN or STALE:
#   the tree changed during the gate), 4 another gate of this run is in progress (BUSY).
# Command environment: AV_SKILLS_DIR = directory with the av-* skills (parent of av-verify).
# Version: VERSION file in the skill directory (missing = dev); the config may require
#   "requires": {"av-dev": ">=X.Y.Z"}.
# Requires: bash 3.2+, git, jq, awk.

set -uo pipefail

DEFAULT_TIMEOUT=900
Q="'"
TAIL_LINES=30

config_error() {
  printf 'CONFIG_ERROR %s\n' "$1"
  exit 2
}

command -v jq >/dev/null 2>&1 || config_error "jq missing; install jq (brew install jq)"
command -v git >/dev/null 2>&1 || config_error "git missing"

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
AV_SKILLS_DIR="$(cd "$skill_dir/.." && pwd)"
export AV_SKILLS_DIR
av_version="dev"
if [ -f "$skill_dir/VERSION" ]; then
  av_version="$(head -n 1 "$skill_dir/VERSION" | tr -d ' \t\r')"
  [ -n "$av_version" ] || av_version="dev"
fi

# MARK: arguments

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
        *) config_error "--env requires KEY=VALUE, got '$kv'" ;;
      esac
      printf '%s' "$key" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || config_error "invalid variable name '$key'"
      env_keys="${env_keys}${key}\n"
      export "$key=$val"
      ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) config_error "unknown argument '$1'" ;;
  esac
  shift
done

# MARK: repo and config

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
[ -f "$cfg" ] || config_error "config not found: $cfg; run the av-setup skill"
jq empty "$cfg" 2>/dev/null || config_error "invalid JSON in $cfg"
jq -e 'type == "object"' "$cfg" >/dev/null 2>&1 || config_error "config $cfg is not a JSON object"

merged_cfg=""
config_sources=""
if [ "$no_local" -eq 0 ] && [ -f "$cfg.local" ]; then
  merged_cfg="$(mktemp "${TMPDIR:-/tmp}/av-config.XXXXXX")" || config_error "cannot create a temporary file"
  trap 'rm -f "$merged_cfg"' EXIT
  merge_out="$(bash "$skill_dir/scripts/config.sh" --root "$root" --config "$cfg" --out "$merged_cfg")" || {
    printf '%s\n' "$merge_out" | grep '^CONFIG_ERROR' || printf 'CONFIG_ERROR cannot merge %s.local\n' "$cfg"
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
        | "command \($q)\(.key)\($q) has no run field" ),
      ( $c | to_entries[] | select(.value | type == "object") | .key as $k
        | (.value.covers // [])[] | select($c[.] == null)
        | "command \($q)\($k)\($q) covers unknown command \($q)\(.)\($q)" ),
      ( $c | to_entries[] | select(.value | type == "object")
        | select(.value | has("parallel") and (.parallel | type) != "boolean")
        | "command \($q)\(.key)\($q): field parallel must be true or false" ),
      ( (.validation.gates // {}) | to_entries[] | .key as $g | .value[]
        | select($c[.] == null)
        | "gate \($q)\($g)\($q) points to unknown command \($q)\(.)\($q)" )
  ' "$cfg"
}

# MARK: config field validation

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
    | ( if has("agents") and (.agents | type) != "object" then "agents: expected an object"
        elif (.agents | type) == "object" then
          ( if (.agents | has("models")) and (.agents.models | type) != "object" then "agents.models: expected an object"
            elif (.agents | has("models")) then
              ( .agents.models | to_entries[] | .key as $k | .value as $v | "agents.models.\($k)" as $p
                | if ($v | isstr) then
                    ( if ($v | claudemodel) then empty
                      else "\($p): invalid value \($v | tojson); allowed: \($models | join(", ")), claude-<id> or an object {provider, model, effort}" end )
                  elif ($v | type) != "object" then "\($p): expected a string or an object {provider, model, effort}"
                  else
                    ( $v | keys[] | select(IN("provider", "model", "effort") | not)
                      | "\($p): unknown field \(tojson); allowed: provider, model, effort" ),
                    ( ($v.provider // "claude") as $pr
                      | if ($pr | isstr | not) or ($efforts[$pr] == null) then "\($p).provider: invalid value \($pr | tojson); allowed: claude, codex"
                        else
                          ( if $pr == "claude" and (($v.model // "inherit") | claudemodel | not)
                            then "\($p).model: invalid claude model \($v.model | tojson); allowed: \($models | join(", ")) or claude-<id>"
                            elif $pr == "codex" and ((($v.model // "inherit") | isstr | not) or (($v.model // "inherit") | test("^[A-Za-z0-9][A-Za-z0-9._:-]*$") | not))
                            then "\($p).model: invalid codex model name \($v.model | tojson)"
                            else empty end ),
                          ( ($v.effort // "inherit") as $e
                            | if ($e | isstr | not) or ($efforts[$pr] | index([$e]) == null)
                              then "\($p).effort: invalid value \($e | tojson) for \($pr); allowed: \($efforts[$pr] | join(", "))"
                              else empty end )
                        end )
                  end ),
              ( if (.agents.models.review // null) != null and (.agents.models.review | slot | .provider == "claude" and .model == "haiku")
                then "agents.models.review: haiku cannot do review; use opus, sonnet, fable, inherit or a codex model"
                else empty end )
            else empty end ),
          ( if (.agents | has("crossVendor")) and (.agents.crossVendor | type) != "boolean"
            then "agents.crossVendor: expected true or false"
            elif .agents.crossVendor == true then
              ((.agents.models // {}) as $m
               | def prov($s): ($m[$s] // "inherit") | slot | .provider;
                 ( if prov("review") == prov("implement")
                   then "agents.crossVendor: review and implement have the same provider \(prov("review") | tojson); code must be checked by a different provider than the one that wrote it"
                   else empty end ),
                 ( (if $m.planReview != null then "planReview" else "review" end) as $pr
                   | if prov($pr) == prov("plan")
                     then "agents.crossVendor: \($pr) and plan have the same provider \(prov("plan") | tojson); set agents.models.planReview to a different provider"
                     else empty end ))
            else empty end ),
          ( if (.agents | has("timeoutSec")) and ((.agents.timeoutSec | type) != "number" or .agents.timeoutSec < 1 or (.agents.timeoutSec | floor) != .agents.timeoutSec)
            then "agents.timeoutSec: expected a positive integer"
            else empty end )
        else empty end ),
      ( if has("git") and (.git | type) != "object" then "git: expected an object"
        elif (.git | type) == "object" then
          ( if (.git | has("commit")) and (.git.commit as $v | $commits | index([$v]) == null)
            then "git.commit: invalid value \(.git.commit | tojson); allowed: \($commits | join(", "))"
            else empty end ),
          ( if (.git | has("push")) and (.git.push as $v | $pushes | index([$v]) == null)
            then "git.push: invalid value \(.git.push | tojson); allowed: \($pushes | join(", "))"
            else empty end )
        else empty end ),
      ( if has("roles") | not then empty
        elif (.roles | type) != "array" then "roles: expected an array of objects"
        else
          .roles | to_entries[] | .value as $r
          | "roles[\(.key)]" as $p
          | if ($r | type) != "object" then "\($p): expected an object"
            else
              ( if ($r.name | isstr | not) or $r.name == "" then "\($p).name: expected a non-empty string" else empty end ),
              ( if ($r.skill | isstr | not) or $r.skill == "" then "\($p).skill: expected a non-empty string" else empty end ),
              ( if ($r.order | type) != "number" or ($r.order | floor) != $r.order then "\($p).order: expected an integer" else empty end ),
              ( if ($r.globs | type) != "array" or ($r.globs | length) == 0 then "\($p).globs: expected a non-empty array of strings"
                else
                  ( $r.globs[]
                  | if isstr | not then "\($p).globs: element \(tojson) is not a string"
                    elif test("[{}]") then "\($p).globs: glob \(tojson) has a curly brace; list each variant separately"
                    elif . == "!" then "\($p).globs: exclusion \"!\" has no pattern"
                    else empty end ),
                  ( if all($r.globs[]; isstr and startswith("!")) then "\($p).globs: only exclusions (!); add at least one glob without !" else empty end )
                end )
            end
        end ),
      ( ("generatedPaths", "unownedPaths") as $k
        | select(has($k) and (.[$k] | strarr | not))
        | "\($k): expected an array of strings" ),
      ( if has("requires") and (.requires | type) != "object" then "requires: expected an object"
        elif (.requires | type) == "object" and (.requires | has("av-dev")) and (.requires["av-dev"] | isstr | not)
        then "requires.av-dev: expected a string in the format >=X.Y.Z"
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
    version_error="requires.av-dev: only the format >=X.Y.Z is supported, got '$required'"
  elif [ "$av_version" = "dev" ]; then
    version_warning="av-dev version unknown (dev), required $required"
  elif ! printf '%s' "${av_version%%[-+]*}" | grep -Eq "$semver_re"; then
    version_warning="av-dev version '$av_version' has an unknown format, required $required"
  elif semver_lt "${av_version%%[-+]*}" "${required#>=}"; then
    version_error="requires.av-dev: installed av-dev version $av_version, required $required; update the av-* skills"
  fi
fi
config_problems="$(schema_errors)"
[ -n "$version_error" ] && config_problems="${config_problems:+$config_problems
}$version_error"

# MARK: --list

# First command word of a shell command, after leading VAR=value assignments.
# Quotes, $(...), ${...} and backticks (nested) belong to the word. Prints the
# word only when it looks like a relative path to a file; otherwise nothing.
script_path() {
  printf '%s\n' "$1" | awk '
    BEGIN { RS = "\001" }
    {
      s = $0; n = length(s); i = 1
      while (1) {
        while (i <= n && substr(s, i, 1) ~ /[ \t\n]/) i++
        if (i > n) exit
        start = i; top = 0
        while (i <= n) {
          c = substr(s, i, 1); c2 = substr(s, i, 2); ctx = top ? st[top] : ""
          if (ctx == "S") { if (c == "\047") top--; i++; continue }
          if (c == "\\") { i += 2; continue }
          if (ctx == "B") { if (c == "`") top--; i++; continue }
          if (ctx == "D") {
            if (c == "\"") top--
            else if (c2 == "$(") { st[++top] = "P"; i++ }
            else if (c2 == "${") { st[++top] = "C"; i++ }
            else if (c == "`") st[++top] = "B"
            i++; continue
          }
          if (ctx == "" && c ~ /[ \t\n;&|<>()]/) break
          if (c == "\047") st[++top] = "S"
          else if (c == "\"") st[++top] = "D"
          else if (c == "`") st[++top] = "B"
          else if (c2 == "$(") { st[++top] = "P"; i++ }
          else if (c2 == "${") { st[++top] = "C"; i++ }
          else if (ctx == "P" && c == "(") st[++top] = "P"
          else if (ctx == "P" && c == ")") top--
          else if (ctx == "C" && c == "}") top--
          i++
        }
        w = substr(s, start, i - start)
        if (w == "") exit
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
        if (w ~ /^[A-Za-z0-9._+-][A-Za-z0-9._\/+-]*$/ && w ~ /\// && w !~ /\/$/) print w
        exit
      }
    }'
}

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
}command '$name': syntax error in field $field"
    fi
    first="$(script_path "$text")"
    if [ -n "$first" ]; then
      [ -e "$root/$(jq -r --arg n "$name" '.validation.commands[$n].cwd // "."' "$cfg")/$first" ] ||
        printf 'WARNING command %s: file %s not found\n' "$name" "$first"
    fi
  done < <(jq -r '(.validation.commands // {}) | to_entries[] | select(.value | type == "object")
                 | .key as $k | (["run", "precheck"][] as $f | select(.value[$f] != null) | [$k, $f, .value[$f]] | @tsv)' "$cfg")
  count="$(jq '(.validation.commands // {}) | length' "$cfg")"
  [ -n "$errors" ] && printf '%s\n' "$errors" | sed 's/^/CONFIG_ERROR /'
  [ "$count" -eq 0 ] && echo "CONFIG_ERROR validation.commands missing"
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
        printf 'BASELINE %s %s baseline head=%s %s\n' "$name" "$status" "$(printf '%s' "$rechead" | cut -c1-8)" "$log"
        continue
      fi
      fresh="STALE"; [ "$recfp" = "$fp" ] && [ "$recstale" = "0" ] && fresh="FRESH"
      note=""; [ "$recstale" = "1" ] && note=" (tree changed during the gate)"
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
    printf 'BUSY gate in progress: %s\n' "$(cat "$out_dir/.lock/owner" 2>/dev/null)"
    exit 4
  fi
  exit "$code"
fi

# MARK: command selection

errors="$(validation_errors)"
[ -n "$errors" ] && printf '%s\n' "$errors" | sed 's/^/WARNING /'

if [ -n "$gate_name" ]; then
  jq -e --arg g "$gate_name" '.validation.gates[$g] != null' "$cfg" >/dev/null ||
    config_error "unknown gate '$gate_name'; available: $(jq -r '(.validation.gates // {}) | keys | join(", ")' "$cfg")"
  names_json="$(jq -c --arg g "$gate_name" '.validation.gates[$g]' "$cfg")"
  label="$gate_name"
elif [ -n "$only" ]; then
  names_json="$(printf '%s' "$only" | jq -R -c 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"
  label="$(printf '%s' "$names_json" | jq -r 'join("+")')"
else
  config_error "pass --gate, --only, --list, --status or --fingerprint"
fi

bad="$(jq -r --argjson n "$names_json" '[ $n[] as $x | select((.validation.commands[$x].run // "") == "") | $x ] | join(", ")' "$cfg")"
if [ -n "$bad" ]; then
  if [ -n "$gate_name" ]; then config_error "gate '$gate_name' has invalid commands: $bad"; fi
  config_error "unknown commands: $bad"
fi

ordered="$(jq -r --argjson n "$names_json" '
  .validation.commands as $c
  | ($n | map(select(($c[.].covers // []) | length > 0))) + ($n | map(select(($c[.].covers // []) | length == 0)))
  | .[]' "$cfg")"

# MARK: execution

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
  printf 'BUSY another gate of run %s is in progress (%s); wait for it to finish\n' "$run_id" "$(cat "$lock/owner" 2>/dev/null)"
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

# MARK: background commands
# Background command result: file <name>.result with fields pre, rc, timed_out,
# duration, started. The loop below waits for it in gate order.

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
[ -n "$bg_started" ] && printf 'PARALLEL%s (in the background next to the rest of the gate)\n' "$bg_started"

# MARK: single command
# check_one NAME RECORD prints the RUN and CHECK lines of the command, writes a
# record to file RECORD and adds the name to $passed on PASS. It only collects a
# background command.
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
    printf 'CHECK %s PASS 0s (covered by %s)\n' "$name" "$covered_by"
  elif [ -n "$reused" ]; then
    status="PASS"
    log_rel="$reused"
    printf 'CHECK %s PASS 0s (FRESH evidence reused: %s)\n' "$name" "$reused"
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
        printf '\n[background command ended without a result]\n' >>"$log"
      fi
    elif [ -n "$precheck" ] && ! ( cd "$cwd" && bash -x -c "$precheck" ) >"$log" 2>&1; then
      pre=0
    fi
    if [ "$pre" -eq 0 ]; then
      status="NOT_RUN"
      failed_step="$(grep '^+' "$log" | tail -1 | sed 's/^+* *//' | cut -c1-120)"
      reason="precheck failed at: ${failed_step:-$precheck}; requires: ${needs:-$precheck}"
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
        printf '\n[timeout after %ss]\n' "$limit" >>"$log"
      elif [ "$rc" -ne 0 ]; then
        if jq -e --arg n "$name" --argjson rc "$rc" '(.validation.commands[$n].notRunExitCodes // []) | index($rc) != null' "$cfg" >/dev/null; then
          status="NOT_RUN"; reason="exit code $rc means the environment is missing; requires: ${needs:-see the log}"
        else
          status="FAIL"; reason="exit code $rc"
        fi
      elif [ -n "$expect" ] && ! grep -qF -- "$expect" "$log"; then
        status="FAIL"; reason="expected text '$expect' not found"
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
      echo "  --- end of log ---"
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

# MARK: order
# The first pass runs commands in sequence and skips background commands. The
# second pass collects background commands. A command whose predecessors are all
# printed writes directly. The others write to a numbered file and print in gate
# order once all earlier ones are done. Records follow the same order.
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
  echo "WARNING tree changed during the gate; evidence marked STALE, rerun the gate after editing is done"
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

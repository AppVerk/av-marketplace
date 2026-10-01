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
# Command fields: run (non-blank string), expect, precheck, needs, timeoutSec (positive integer), cwd,
#   notRunExitCodes, optional, covers, parallel.
# run and precheck go to bash with pipefail: in "npm test | tail -50" a failing test fails
#   the command, not only the last program. Do not cut output with head in a command.
# precheck runs without xtrace, so values of variables never reach the log; the NOT_RUN reason
#   quotes the precheck as written in the config.
# timeoutSec is one budget for precheck and run: the clock starts before the precheck, run
#   gets the rest, and the reported duration includes the precheck. A precheck over the
#   budget is NOT_RUN (precheck timeout) and run does not start.
# --reuse-fresh reuses only a direct PASS with an existing log. A result covered by another
#   command is never reused on its own: without its covering command the command runs.
# parallel: true = the command shares no state with others; it starts in the background
#   when the gate starts, next to the rest. Results, logs and evidence print in gate order.
#   A command with covers, or covered by another command of the gate, runs in sequence.
# Command names: [A-Za-z0-9_.-]. A gate is a non-empty array of command names.
# The config check covers validation, paths and requires; other fields (agents, git, roles)
#   belong to av-setup/scripts/check_setup.sh, so they never stop a gate.
# Result: PASS only when every selected command has PASS or SKIPPED and at least one PASS.
# Fingerprint: needs git that can read the repo and a commit (HEAD). A git error is
#   GIT_ERROR with code 2, never a fingerprint. Inputs: HEAD, tracked edits (no external diff
#   driver), skip-worktree and assume-unchanged files, submodules, untracked files and the
#   local override .ai/av.config.json.local. Other ignored files are not inputs.
# FLAKY: a PASS after a FAIL of the same command in this run with the same fingerprint. The
#   record keeps the red attempt ("previous", its log renamed to <log>.<n>) and flaky: true;
#   the CHECK, GATE and --status lines say FLAKY. Such a PASS is not READY_FOR_COMMIT.
# --run-id: letters, digits, _ . - only, so the run directory stays inside the workspace.
# Exit codes: 0 PASS, 1 FAIL, 2 config or git error, 3 incomplete (NOT_RUN, only SKIPPED, or
#   STALE: the tree changed during the gate), 4 another gate of this run is in progress (BUSY).
# Lock: <runs>/<RUN_ID>/.lock with the owner "<label> pid <pid> started <start time>". A lock
#   whose process is gone (kill -9, a crash, a reboot) or whose pid now belongs to another
#   process is stale: the next gate takes it over with a WARNING, --status reports it.
#   Start times come from "LC_ALL=C TZ=UTC0 ps", so a gate started with another LANG or TZ
#   reads the same value. One gate at a time takes over: it holds <lock>.takeover (with its
#   pid) and checks the lock again inside. The takeover stops the background commands the
#   dead gate left (process groups recorded with their start time), so they cannot write to
#   the logs of the new gate.
# Command environment: AV_SKILLS_DIR = directory with the av-* skills (parent of av-verify).
# Version: "version" in the plugin's .claude-plugin/plugin.json (missing = dev); the config
#   may require "requires": {"av-dev": ">=X.Y.Z"}.
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
plugin_json="$AV_SKILLS_DIR/../.claude-plugin/plugin.json"
if [ -f "$plugin_json" ]; then
  av_version="$(jq -r '.version // empty' "$plugin_json" 2>/dev/null | tr -d ' \t\r')"
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
if [ -n "$run_id" ]; then
  printf '%s' "$run_id" | grep -Eq '^[A-Za-z0-9._-]+$' && [ "$run_id" != "." ] && [ "$run_id" != ".." ] ||
    config_error "--run-id '$run_id': use only letters, digits, _ . - (not . or ..); the run directory stays inside the workspace"
fi

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

# proc_start PID - start time of a running process (ps lstart in the C locale and UTC, so every
# gate reads the same text whatever its LANG or TZ); empty when it does not run
proc_start() { LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | sed 's/[[:space:]]*$//'; }

# same_proc PID START - code 0 when PID runs and started at START (a reused pid does not match)
same_proc() { [ -n "$1" ] && [ -n "$2" ] && [ "$(proc_start "$1")" = "$2" ]; }

# stop_left_behind DIR - stops what a dead gate left in its .bg directory: process groups of
# commands and watchers, and background subshells, each only when its start time still matches
stop_left_behind() {
  local f pid started pass sent=0
  [ -d "$1" ] || return 0
  for pass in TERM KILL; do
    for f in "$1"/*.cmdpid "$1"/watch.*; do
      [ -f "$f" ] || continue
      case "$f" in */watch.*) pid="${f##*/watch.}"; started="$(cat "$f" 2>/dev/null)" ;;
        *) read -r pid started <"$f" 2>/dev/null ;; esac
      same_proc "$pid" "$started" && kill "-$pass" -- "-$pid" 2>/dev/null && sent=1
    done
    for f in "$1"/*.pid; do
      [ -f "$f" ] || continue
      read -r pid started <"$f" 2>/dev/null
      same_proc "$pid" "$started" && kill "-$pass" "$pid" 2>/dev/null && sent=1
    done
    [ "$pass" = TERM ] && [ "$sent" -eq 1 ] && sleep 1
  done
  return 0
}

# lock_stale LOCK - code 0 when the owner of LOCK is gone: its pid does not run, or runs with
# another start time (the pid was reused). Not stale: an owner without a pid (a gate that has
# just made the lock), or a machine where ps cannot tell (a live lock must never be taken).
lock_stale() {
  local owner pid started now
  [ -n "$(proc_start $$)" ] || return 1
  owner="$(cat "$1/owner" 2>/dev/null)" || return 1
  pid="$(printf '%s' "$owner" | sed -n 's/.* pid \([0-9][0-9]*\).*/\1/p')"
  [ -n "$pid" ] || return 1
  now="$(proc_start "$pid")"
  [ -n "$now" ] || return 0
  started="$(printf '%s' "$owner" | sed -n 's/.* started \(.*\)$/\1/p')"
  [ -n "$started" ] && [ "$started" != "$now" ] && return 0
  return 1
}

# fingerprint - code 1 when git cannot read the repo (not a repo, dubious ownership, a broken
# index) or HEAD has no commit; a failure must never become a hashed value. An untracked entry
# that is not a regular file (a symlink, a nested repository such as a worktree under
# .claude/worktrees/) goes in by name, and a symlink by its target, never as a git error.
# Inputs git would not compare go in too: --no-ext-diff keeps an external diff driver from
# hiding an edit, skip-worktree and assume-unchanged files go in by content, submodules by
# commit, tracked edits and untracked names, and the local override of the team config
# (.ai/av.config.json.local, ignored by git) by content, whichever config the gate uses.
# Other ignored files (.env.local) are not inputs; put them in a command's precheck.
fingerprint() {
  local head ps e f
  head="$(git -C "$root" rev-parse --verify -q HEAD 2>/dev/null)" || return 1
  git -C "$root" status --porcelain >/dev/null 2>&1 || return 1
  {
    printf '%s\n' "$head"
    git -C "$root" diff HEAD --no-ext-diff --binary -- . ":(exclude)$workspace/" ":(exclude).ai/workspace/" 2>/dev/null || exit 1
    git -C "$root" ls-files -v -z 2>/dev/null |
      while IFS= read -r -d '' e; do
        case "${e%% *}" in
          S|[a-z])
            f="${e#* }"
            printf 'hidden %s\n' "$f"
            if [ -f "$root/$f" ]; then hash_cmd <"$root/$f" || exit 1; fi ;;
        esac
      done
    ps=("${PIPESTATUS[@]}")
    [ "${ps[0]}" -eq 0 ] && [ "${ps[1]}" -eq 0 ] || exit 1
    if [ -f "$root/.gitmodules" ]; then
      git -C "$root" submodule foreach --quiet --recursive \
        'printf "submodule %s\n" "$sm_path"; git rev-parse HEAD; git diff HEAD --no-ext-diff --binary; git ls-files --others --exclude-standard' 2>/dev/null || exit 1
    fi
    if [ -f "$root/.ai/av.config.json.local" ]; then
      printf 'local override\n'
      hash_cmd <"$root/.ai/av.config.json.local" || exit 1
    fi
    git -C "$root" ls-files --others --exclude-standard -z -- . ":(exclude)$workspace/" ":(exclude).ai/workspace/" 2>/dev/null |
      while IFS= read -r -d '' f; do
        printf '%s\n' "$f"
        if [ -L "$root/$f" ]; then readlink "$root/$f" || exit 1
        elif [ -f "$root/$f" ]; then hash_cmd <"$root/$f" || exit 1
        fi
      done
    ps=("${PIPESTATUS[@]}")
    [ "${ps[0]}" -eq 0 ] && [ "${ps[1]}" -eq 0 ] || exit 1
  } | hash_cmd | cut -c1-16
}

# fingerprint_or_die VAR - sets VAR to the fingerprint, or prints GIT_ERROR and exits with 2
fingerprint_or_die() {
  local _av_fp
  if _av_fp="$(fingerprint)" && [ -n "$_av_fp" ]; then
    printf -v "$1" '%s' "$_av_fp"
    return 0
  fi
  printf 'GIT_ERROR git cannot read %s or it has no commit (check git status and safe.directory); no fingerprint, so no FRESH evidence\n' "$root"
  exit 2
}

if [ "$mode" = "fingerprint" ]; then
  fp=""; fingerprint_or_die fp
  printf 'HEAD %s\nFINGERPRINT %s\n' "$(git -C "$root" rev-parse HEAD)" "$fp"
  exit 0
fi

cfg="${config_arg:-$root/.ai/av.config.json}"
[ -f "$cfg" ] || config_error "config not found: $cfg; run the av-setup skill"
jq empty "$cfg" 2>/dev/null || config_error "invalid JSON in $cfg"
jq -e 'type == "object"' "$cfg" >/dev/null 2>&1 || config_error "config $cfg is not a JSON object"

merged_cfg=""
config_sources=""
config_local=""
if [ "$no_local" -eq 0 ] && [ -f "$cfg.local" ]; then
  config_local="$cfg.local"
  case "$config_local" in "$root"/*) config_local="${config_local#"$root"/}" ;; esac
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
    | ( $c | keys[] | select(test("^[A-Za-z0-9_.-]+$") | not)
        | "command \($q)\(.)\($q): name must use only letters, digits, _ . -" ),
      ( $c | to_entries[]
        | select((.value | type) != "object" or (.value.run | type) != "string" or (.value.run | test("^[[:space:]]*$")))
        | "command \($q)\(.key)\($q): run must be a non-blank string" ),
      ( $c | to_entries[] | select(.value | type == "object")
        | select((.value | has("precheck")) and ((.value.precheck | type) != "string" or (.value.precheck | test("^[[:space:]]*$"))))
        | "command \($q)\(.key)\($q): precheck must be a non-blank string" ),
      ( $c | to_entries[] | select(.value | type == "object")
        | select(.value | has("timeoutSec") and ((.timeoutSec | type) != "number" or .timeoutSec != (.timeoutSec | floor) or .timeoutSec < 1))
        | "command \($q)\(.key)\($q): timeoutSec must be a positive integer (seconds)" ),
      ( $c | to_entries[] | select(.value | type == "object") | .key as $k
        | (.value.covers // [])[] | select($c[.] == null)
        | "command \($q)\($k)\($q) covers unknown command \($q)\(.)\($q)" ),
      ( $c | to_entries[] | select(.value | type == "object")
        | select(.value | has("parallel") and (.parallel | type) != "boolean")
        | "command \($q)\(.key)\($q): field parallel must be true or false" ),
      ( (.validation.gates // {}) | to_entries[] | .key as $g | .value as $v
        | if ($v | type) != "array" or ($v | length) == 0
          then "gate \($q)\($g)\($q): expected a non-empty array of command names"
          else ( $v[] | if type != "string" then "gate \($q)\($g)\($q): element \(tojson) is not a command name"
                        elif $c[.] == null then "gate \($q)\($g)\($q) points to unknown command \($q)\(.)\($q)"
                        else empty end )
          end )
  ' "$cfg"
}

# MARK: config field validation (requires; other fields: av-setup/scripts/check_setup.sh)

schema_errors() {
  jq -r '
    if has("requires") and (.requires | type) != "object" then "requires: expected an object"
    elif (.requires | type) == "object" and (.requires | has("av-dev")) and (.requires["av-dev"] | type != "string")
    then "requires.av-dev: expected a string in the format >=X.Y.Z"
    else empty end
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
  fp=""; fingerprint_or_die fp
  code=0
  for fname in baseline.json evidence.json; do
    file="$out_dir/$fname"
    [ -f "$file" ] || continue
    label="CHECK"; [ "$fname" = "baseline.json" ] && label="BASELINE"
    if ! jq -e '.checks | type == "object"' "$file" >/dev/null 2>&1; then
      printf 'WARNING %s is unreadable; no evidence from it counts\n' "$runs_base/$run_id/$fname"
      [ "$label" = "CHECK" ] && code=1
      continue
    fi
    while IFS=$'\t' read -r name status recstale recfp log rechead reclocal recflaky prevlog; do
      if [ "$label" = "BASELINE" ]; then
        printf 'BASELINE %s %s baseline head=%s %s\n' "$name" "$status" "$(printf '%s' "$rechead" | cut -c1-8)" "$log"
        continue
      fi
      fresh="STALE"; [ "$recfp" = "$fp" ] && [ "$recstale" = "0" ] && fresh="FRESH"
      note=""; [ "$recstale" = "1" ] && note=" (tree changed during the gate)"
      [ "$reclocal" != "-" ] && note="$note (local override $reclocal)"
      [ "$recflaky" = "1" ] && note="$note (FLAKY: failed earlier in this run, first attempt: $prevlog)"
      printf '%s %s %s %s %s%s\n' "$label" "$name" "$status" "$fresh" "$log" "$note"
      if [ "$label" = "CHECK" ] && { [ "$fresh" = "STALE" ] || { [ "$status" != "PASS" ] && [ "$status" != "SKIPPED" ]; }; }; then
        code=1
      fi
    done < <(jq -r '.checks | to_entries[]
                   | [.key, .value.status, (if .value.stale == true then "1" else "0" end),
                      (.value.fingerprint // "-"), (.value.log // "-"), (.value.head // "-"),
                      (.value.configLocal // "-"), (if .value.flaky == true then "1" else "0" end),
                      (.value.previous.log // "-")] | @tsv' "$file")
  done
  printf 'FINGERPRINT %s\n' "$fp"
  if [ -d "$out_dir/.lock" ]; then
    if lock_stale "$out_dir/.lock"; then
      printf 'WARNING stale lock: %s is not running; the next gate of this run takes it over\n' "$(cat "$out_dir/.lock/owner" 2>/dev/null)"
    else
      printf 'BUSY gate in progress: %s\n' "$(cat "$out_dir/.lock/owner" 2>/dev/null)"
      exit 4
    fi
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
  printf '%s' "$names_json" | jq -e 'type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null ||
    config_error "gate '$gate_name' must be a non-empty array of command names, got $names_json"
elif [ -n "$only" ]; then
  names_json="$(printf '%s' "$only" | jq -R -c 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"
  label="$(printf '%s' "$names_json" | jq -r 'join("+")')"
  [ "$(printf '%s' "$names_json" | jq 'length')" -gt 0 ] || config_error "--only needs at least one command name"
else
  config_error "pass --gate, --only, --list, --status or --fingerprint"
fi

bad_names="$(printf '%s' "$names_json" | jq -r '[.[] | select(test("^[A-Za-z0-9_.-]+$") | not)] | map(tojson) | join(", ")')"
[ -z "$bad_names" ] || config_error "invalid command names: $bad_names; a name uses only letters, digits, _ . -"
bad="$(jq -r --argjson n "$names_json" '[ $n[] as $x | select((.validation.commands[$x] | type) != "object") | $x ] | join(", ")' "$cfg")"
if [ -n "$bad" ]; then
  if [ -n "$gate_name" ]; then config_error "gate '$gate_name' has invalid commands: $bad"; fi
  config_error "unknown commands: $bad"
fi
# A selected command with a blank run, a bad precheck or a non-integer timeoutSec stops the gate
# before anything starts: an empty command would exit 0 and count as PASS.
bad="$(jq -r --argjson n "$names_json" '[ $n[] as $x | .validation.commands[$x]
  | select((.run | type) != "string" or (.run | test("^[[:space:]]*$"))
           or (has("precheck") and ((.precheck | type) != "string" or (.precheck | test("^[[:space:]]*$"))))
           or (has("timeoutSec") and ((.timeoutSec | type) != "number" or .timeoutSec != (.timeoutSec | floor) or .timeoutSec < 1)))
  | $x ] | join(", ")' "$cfg")"
[ -z "$bad" ] || config_error "commands with an invalid run, precheck or timeoutSec: $bad (see --list)"

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
  ( cd "$cwd" && exec bash -o pipefail -c "$cmd" ) >"$log" 2>&1 &
  local pid=$!
  [ -n "$pidfile" ] && printf '%s %s\n' "$pid" "$(proc_start "$pid")" >"$pidfile"
  ( sleep "$limit"; : >"$marker"; kill -TERM -- "-$pid" 2>/dev/null; sleep 3; kill -KILL -- "-$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watcher=$!
  set +m
  proc_start "$watcher" >"$bg_dir/watch.$watcher"
  rc=0
  wait "$pid" 2>/dev/null || rc=$?
  timed_out=0
  if [ -f "$marker" ]; then
    # Timed out: the leader left on TERM, but a member that ignores TERM (trap '' TERM) is
    # still in the group, which outlives its leader. Kill the whole group now and wait until
    # it is gone, so nothing of this command survives the gate, its record or its lock.
    timed_out=1
    kill -KILL -- "-$pid" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      kill -0 -- "-$pid" 2>/dev/null || break
      sleep 0.1
    done
  fi
  kill -TERM -- "-$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  rm -f "$bg_dir/watch.$watcher"
  rm -f "$marker"
  return 0
}

# timed_precheck PRECHECK CWD LIMIT LOG PIDFILE NAME - runs the precheck within LIMIT, without
# xtrace; sets pre (1 passed or none, 0 failed, 2 timed out) and pre_s (its seconds)
timed_precheck() {
  local s0
  pre=1; pre_s=0
  [ -n "$1" ] || return 0
  s0="$(date +%s)"
  run_timed "$1" "$2" "$3" "$4" "$out_dir/.timeout.pre.$6" "$5"
  pre_s=$(( $(date +%s) - s0 ))
  rm -f "$5"
  if [ "$timed_out" -eq 1 ]; then pre=2; elif [ "$rc" -ne 0 ]; then pre=0; fi
  rc=0; timed_out=0
  return 0
}

# budget_left LIMIT USED - seconds left for run after the precheck, at least 1
budget_left() {
  local left=$(( $1 - $2 ))
  [ "$left" -ge 1 ] || left=1
  printf '%s' "$left"
}

lock="$out_dir/.lock"
# mtime FILE - modification time in seconds since the epoch: GNU stat first (-c %Y), then BSD
# stat (-f %m; on GNU, -f is the file system status and would print a mount point); code 1
# when neither gives a number
mtime() {
  local t
  t="$(stat -c %Y "$1" 2>/dev/null)" || t="$(stat -f %m "$1" 2>/dev/null)" || return 1
  case "$t" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$t"
}

# takeover_dead DIR - code 0 when the gate that made the takeover directory is gone: its pid
# file names a process that does not run (or ran with another start time), or the directory
# has no pid file and is older than TAKEOVER_GRACE seconds (a gate that died between mkdir
# and writing its pid). A fresh pid-less directory belongs to a gate that is still writing it.
TAKEOVER_GRACE=5
takeover_dead() {
  local tp tstart age
  if read -r tp tstart <"$1/pid" 2>/dev/null && [ -n "${tp:-}" ]; then
    ! same_proc "$tp" "${tstart:-}"
    return
  fi
  age=$(( $(date +%s) - $(mtime "$1" || date +%s) ))
  [ "$age" -ge "$TAKEOVER_GRACE" ]
}

# take_over - replaces a stale lock; one gate at a time (mkdir of <lock>.takeover is atomic).
# A takeover directory whose gate is gone is removed first. Code 0 when this gate made the lock.
take_over() {
  local t="$lock.takeover" stale_owner stale_pid made=1
  if ! mkdir "$t" 2>/dev/null; then
    takeover_dead "$t" || return 1
    rm -rf "$t"
    mkdir "$t" 2>/dev/null || return 1
  fi
  printf '%s %s\n' "$$" "$(proc_start $$)" >"$t/pid"
  if lock_stale "$lock"; then
    stale_owner="$(cat "$lock/owner" 2>/dev/null)"
    stale_pid="$(printf '%s' "$stale_owner" | sed -n 's/.* pid \([0-9][0-9]*\).*/\1/p')"
    printf 'WARNING stale lock of run %s (%s): the process is not running; taking it over\n' "$run_id" "$stale_owner"
    [ -n "$stale_pid" ] && stop_left_behind "$out_dir/.bg.$stale_pid"
    rm -rf "$lock" ${stale_pid:+"$out_dir/.bg.$stale_pid"}
  fi
  mkdir "$lock" 2>/dev/null && made=0
  rm -rf "$t"
  return "$made"
}
if ! mkdir "$lock" 2>/dev/null; then
  if ! { lock_stale "$lock" && take_over; }; then
    printf 'BUSY another gate of run %s is in progress (%s); wait for it to finish\n' "$run_id" "$(cat "$lock/owner" 2>/dev/null)"
    exit 4
  fi
fi
printf '%s pid %s started %s\n' "$label" "$$" "$(proc_start $$)" >"$lock/owner"
bg_dir="$out_dir/.bg.$$"
mkdir -p "$bg_dir"
cleanup() {
  local f
  for f in "$bg_dir"/*.cmdpid; do
    [ -f "$f" ] && kill -TERM -- "-$(cut -d ' ' -f1 "$f")" 2>/dev/null
  done
  for f in "$bg_dir"/watch.*; do
    [ -f "$f" ] && kill -TERM -- "-${f##*/watch.}" 2>/dev/null
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
evidence_name="evidence.json"; [ "$baseline" -eq 1 ] && evidence_name="baseline.json"
evidence="$out_dir/$evidence_name"

# previous_record NAME - the record of NAME saved earlier in this run, or nothing
previous_record() {
  [ -f "$evidence" ] && jq -c --arg n "$1" '.checks[$n] // empty' "$evidence" 2>/dev/null
  return 0
}

# keep_failed_log NAME - when the earlier record of NAME in this run is FAIL, its log moves to
# <log>.<n> so the retry does not overwrite the red attempt; prints the kept path
keep_failed_log() {
  local prev log n=1
  prev="$(previous_record "$1")"
  [ -n "$prev" ] && [ "$(printf '%s' "$prev" | jq -r '.status // ""')" = "FAIL" ] || return 0
  log="$(printf '%s' "$prev" | jq -r '.log // empty')"
  [ -n "$log" ] && [ -f "$root/$log" ] || return 0
  while [ -e "$root/$log.$n" ]; do n=$((n + 1)); done
  mv "$root/$log" "$root/$log.$n" 2>/dev/null && printf '%s' "$log.$n"
  return 0
}
fp_before=""; fingerprint_or_die fp_before
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
  local log
  log="$(jq -r --arg n "$1" --arg fp "$fp_before" --arg invocation "$(invocation_fingerprint "$1")" '.checks[$n] | select(.status == "PASS" and .fingerprint == $fp and .invocationFingerprint == $invocation and (.stale != true) and (.covered_by == null) and ((.log // "") | type == "string" and . != "")) | .log' "$out_dir/evidence.json" 2>/dev/null)"
  [ -n "$log" ] && [ -f "$root/$log" ] && printf '%s' "$log"
  return 0
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
  keep_failed_log "$name" >"$bg_dir/$name.kept"
  (
    started="$(date +%Y-%m-%dT%H:%M:%S)"
    rc=0; timed_out=0; duration=0
    timed_precheck "$precheck" "$cwd" "$limit" "$log" "$bg_dir/$name.cmdpid" "$name"
    duration="$pre_s"
    if [ "$pre" -eq 1 ]; then
      start_s="$(date +%s)"
      run_timed "$run" "$cwd" "$(budget_left "$limit" "$pre_s")" "$log" "$out_dir/.timeout.$name" "$bg_dir/$name.cmdpid"
      duration=$(( $(date +%s) - start_s + pre_s ))
      rm -f "$bg_dir/$name.cmdpid"
    fi
    printf '%s %s %s %s %s\n' "$pre" "$rc" "$timed_out" "$duration" "$started" >"$bg_dir/$name.result.tmp"
    mv "$bg_dir/$name.result.tmp" "$bg_dir/$name.result"
  ) </dev/null &
  printf '%s %s\n' "$!" "$(proc_start "$!")" >"$bg_dir/$name.pid"
  bg_started="$bg_started $name"
done
[ -n "$bg_started" ] && printf 'PARALLEL%s (in the background next to the rest of the gate)\n' "$bg_started"

# flaky_check NAME - a PASS after a FAIL of the same command in this run, with the same
# fingerprint, is FLAKY: the record keeps the red attempt in "previous" (its log renamed by
# keep_failed_log) and flaky: true; a later PASS with the same fingerprint carries both on.
# A PASS after a FAIL with another fingerprint is a fix: the red attempt stays in "previous"
# without the FLAKY mark. Sets flaky, previous_json and, when FLAKY, reason.
flaky_check() {
  local prev prev_status prev_fp
  prev="$(previous_record "$1")"
  [ -n "$prev" ] || return 0
  prev_status="$(printf '%s' "$prev" | jq -r '.status // ""')"
  prev_fp="$(printf '%s' "$prev" | jq -r '.fingerprint // ""')"
  if [ "$prev_status" = "FAIL" ]; then
    previous_json="$(printf '%s' "$prev" | jq -c --arg k "$kept" '{status, started, fingerprint, reason, log: (if $k != "" then $k else .log end)}')"
    if [ "$status" = "PASS" ] && [ "$prev_fp" = "$fp_before" ]; then
      flaky=1
      reason="FLAKY: failed earlier in this run without a code change; first attempt: ${kept:-log overwritten}"
    fi
  elif [ "$(printf '%s' "$prev" | jq -r '.flaky // false')" = "true" ] && [ "$status" = "PASS" ] && [ "$prev_fp" = "$fp_before" ]; then
    previous_json="$(printf '%s' "$prev" | jq -c '.previous // null')"
    flaky=1
    reason="FLAKY: failed earlier in this run without a code change; first attempt: $(printf '%s' "$prev" | jq -r '.previous.log // "log overwritten"')"
  fi
  return 0
}

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
  status=""; reason=""; rc=0; duration=0; covered_by=""; kept=""; flaky=0; previous_json="null"

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
    flaky_check "$name"
    printf 'CHECK %s PASS 0s (FRESH evidence reused: %s)%s\n' "$name" "$reused" "${reason:+ ($reason)}"
  else
    cwd="$root/$(cmd_field "$name" cwd)"
    limit="$(cmd_field "$name" timeoutSec)"; limit="${limit:-$DEFAULT_TIMEOUT}"
    precheck="$(cmd_field "$name" precheck)"
    needs="$(cmd_field "$name" needs)"
    pre=1
    if [ "$in_bg" -eq 1 ]; then
      kept="$(cat "$bg_dir/$name.kept" 2>/dev/null)"
      wait "$(cut -d ' ' -f1 "$bg_dir/$name.pid")" 2>/dev/null
      if [ -f "$bg_dir/$name.result" ]; then
        read -r pre rc timed_out duration started <"$bg_dir/$name.result"
      else
        pre=1; rc=1; timed_out=0; duration=0
        printf '\n[background command ended without a result]\n' >>"$log"
      fi
    else
      kept="$(keep_failed_log "$name")"
      timed_precheck "$precheck" "$cwd" "$limit" "$log" "$bg_dir/fg@.cmdpid" "$name"
      duration="$pre_s"
    fi
    if [ "$pre" -ne 1 ]; then
      status="NOT_RUN"
      if [ "$pre" -eq 2 ]; then
        reason="precheck timeout after ${limit}s (timeoutSec covers precheck and run)"
        printf '\n[precheck timeout after %ss]\n' "$limit" >>"$log"
      else
        reason="precheck failed: $precheck"
      fi
      [ -n "$needs" ] && reason="$reason; requires: $needs"
    else
      printf 'RUN %s: %s\n' "$name" "$run"
      if [ "$in_bg" -eq 0 ]; then
        start_s="$(date +%s)"
        run_timed "$run" "$cwd" "$(budget_left "$limit" "$pre_s")" "$log" "$out_dir/.timeout.$name" "$bg_dir/fg@.cmdpid"
        duration=$(( $(date +%s) - start_s + pre_s ))
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
    flaky_check "$name"
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
    --argjson flaky "$flaky" --argjson previous "$previous_json" \
    '{invocationFingerprint: $invocation, name: $name, run: $run, started: $started, status: $status, exit: $exit, duration: $duration, log: $log}
     + (if $reason != "" then {reason: $reason} else {} end)
     + (if $covered != "" then {covered_by: $covered, log: null} else {} end)
     + (if $reused != "" then {reused: true} else {} end)
     + (if $flaky == 1 then {flaky: true} else {} end)
     + (if $previous != null then {previous: $previous} else {} end)
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
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
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
  done 3<<<"$ordered"
done

fp_after=""; fingerprint_or_die fp_after
stale=0
if [ "$fp_after" != "$fp_before" ]; then
  stale=1
  echo "WARNING tree changed during the gate; evidence marked STALE, rerun the gate after editing is done"
fi

# The verdict comes from the records this run wrote, never from the evidence file: a merge
# that fails leaves the previous run's records there, and they must not turn into a PASS.
# PASS only when every selected command has PASS or SKIPPED and at least one has PASS. An
# unreadable records file, a missing record or an unknown status is FAIL, never PASS.
selected_statuses="$(jq -s -r --argjson n "$names_json" '(map({(.name): .}) | add // {}) as $c | [$n[] | ($c[.].status // "MISSING")] | join(" ")' "$records" 2>/dev/null)" || selected_statuses=""
result="PASS"; code=0
if [ -z "$selected_statuses" ]; then
  echo "WARNING no readable results of this run in $runs_base/$run_id"
  result="FAIL"; code=1
else
  for st in $selected_statuses; do
    case "$st" in
      PASS|SKIPPED) ;;
      NOT_RUN) [ "$code" -eq 1 ] || { result="INCOMPLETE"; code=3; } ;;
      FAIL) result="FAIL"; code=1 ;;
      *) echo "WARNING no valid result for a command of this gate (status $st)"; result="FAIL"; code=1 ;;
    esac
  done
  case " $selected_statuses " in
    *" PASS "*) ;;
    *) [ "$code" -eq 0 ] && { result="INCOMPLETE"; code=3; echo "WARNING no command of this gate ran (all SKIPPED)"; } ;;
  esac
fi
if [ "$stale" -eq 1 ] && [ "$code" -ne 1 ]; then
  result="STALE"; code=3
fi
flaky_names="$(jq -s -r '[.[] | select(.flaky == true) | .name] | join(", ")' "$records" 2>/dev/null)"

# write_evidence - merges this run's records into the evidence file through a temporary file;
# code 1 when any step fails, and the file then keeps the previous run untouched
write_evidence() {
  local corrupt
  if [ -f "$evidence" ] && ! jq -e '.checks | type == "object"' "$evidence" >/dev/null 2>&1; then
    corrupt="$evidence.corrupt.$(date +%Y%m%d-%H%M%S)"
    mv "$evidence" "$corrupt" || return 1
    echo "WARNING $runs_base/$run_id/$evidence_name was unreadable; moved to ${corrupt#"$root"/}, a new file starts"
  fi
  [ -f "$evidence" ] || echo '{"checks":{}}' >"$evidence" || return 1
  rm -f "$evidence.tmp" 2>/dev/null
  jq -s --arg head "$head_before" --arg fp "$fp_before" --arg fpa "$fp_after" --argjson stale "$stale" --arg local "$config_local" --slurpfile old "$evidence" '
    reduce .[] as $r ($old[0]; .checks[$r.name] = ($r + {head: $head, fingerprint: $fp}
      + (if $stale == 1 then {stale: true, fingerprintAfter: $fpa} else {} end)
      + (if $local != "" then {configLocal: $local} else {} end)))
  ' "$records" >"$evidence.tmp" 2>/dev/null || return 1
  jq -e '.checks | type == "object"' "$evidence.tmp" >/dev/null 2>&1 || return 1
  mv "$evidence.tmp" "$evidence" || return 1
}
if write_evidence; then
  rm -f "$records"
else
  rm -f "$evidence.tmp" 2>/dev/null
  unsaved="$out_dir/$evidence_name.unsaved.$(date +%Y%m%d-%H%M%S).jsonl"
  mv "$records" "$unsaved" 2>/dev/null || unsaved="$records"
  echo "WRITE_ERROR could not write $runs_base/$run_id/$evidence_name; the results of this run are in ${unsaved#"$root"/} and do not count as evidence"
  result="FAIL"; code=2
fi

kind="GATE"; [ "$baseline" -eq 1 ] && kind="BASELINE"
printf '%s %s %s run=%s evidence=%s fingerprint=%s%s\n' "$kind" "$label" "$result" "$run_id" "$runs_base/$run_id/$evidence_name" "$fp_before" "${flaky_names:+ (FLAKY: $flaky_names; PASS only on a retry, see previous in the evidence)}"
exit "$code"

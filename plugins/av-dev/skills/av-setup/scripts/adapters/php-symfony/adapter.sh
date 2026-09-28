#!/usr/bin/env bash
# adapter.sh - lightweight PHP/Symfony adapter for av-setup scan.sh.
#
# Reports explicit facts only: Symfony presence declared in composer.json, declared version
# constraints of relevant packages, existing paths from a fixed Symfony convention list,
# config file formats by extension and files that point at test tools. Every fact has
# evidence: a path, plus the manifest key when the fact comes from composer.json.
# Does not infer architecture, layers, DDD or class relations from directory names.
# Reads only composer.json files (jq); every other file is listed by name and never opened.
# Never reads .env*, key files, auth.json or composer.lock; skips vendor, var, cache, worktrees.
#
# Usage:
#   adapter.sh [ROOT] [--pretty] [--max-depth N] [--max-apps N] [--max-packages N]
#              [--max-autoload N] [--max-config-files N] [--max-config-depth N]
# Exit: 0 JSON printed (errors are reported inside), 2 jq missing, ROOT missing or bad option.
# Requires: bash 3.2+, jq, find, awk, sort, composer-facts.jq next to this script. Temp files go to $TMPDIR.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="."
pretty=0
MAX_DEPTH=3
MAX_APPS=8
MAX_PACKAGES=80
MAX_AUTOLOAD=20
MAX_CONFIG_FILES=400
MAX_CONFIG_DEPTH=4
MAX_MANIFEST_KB=512
MAX_SAMPLES=3
MAX_EXCLUDED=20

usage_error() { printf '{"error":"%s"}\n' "$(printf '%s' "$1" | tr -d '"\\' | tr '\t\n' '  ')"; exit 2; }
num() { case "${1:-}" in ''|*[!0-9]*) usage_error "$2 needs a non-negative number" ;; esac; }

while [ $# -gt 0 ]; do
  case "$1" in
    --pretty) pretty=1 ;;
    --max-depth) num "${2:-}" "$1"; MAX_DEPTH="$2"; shift ;;
    --max-apps) num "${2:-}" "$1"; MAX_APPS="$2"; shift ;;
    --max-packages) num "${2:-}" "$1"; MAX_PACKAGES="$2"; shift ;;
    --max-autoload) num "${2:-}" "$1"; MAX_AUTOLOAD="$2"; shift ;;
    --max-config-files) num "${2:-}" "$1"; MAX_CONFIG_FILES="$2"; shift ;;
    --max-config-depth) num "${2:-}" "$1"; MAX_CONFIG_DEPTH="$2"; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    -*) usage_error "unknown option $1" ;;
    *) root="$1" ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || usage_error "jq not found"
[ -f "$here/composer-facts.jq" ] || usage_error "composer-facts.jq not found next to adapter.sh"
secret_names="$(cd "$here/../.." && pwd)/secret_names.sh"
[ -f "$secret_names" ] || usage_error "secret_names.sh not found in av-setup/scripts"
# shellcheck source=../../secret_names.sh
. "$secret_names"
root="$(cd "$root" 2>/dev/null && pwd)" || usage_error "directory not found"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/av-php-symfony.XXXXXX")" || usage_error "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/trunc"
: >"$tmp/errors"
: >"$tmp/apps"

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
t0=$SECONDS

# trunc FIELD SHOWN TOTAL - records a list cut to a limit
trunc() { [ "${3:-0}" -gt "${2:-0}" ] && printf '%s\t%s\t%s\tlimit\n' "$1" "$2" "$3" >>"$tmp/trunc"; return 0; }
# depthcut FIELD LIMIT - records a listing stopped at a depth limit; the number of missed items is unknown
depthcut() { printf '%s\t%s\t\tdepth\n' "$1" "$2" >>"$tmp/trunc"; }
# err PATH MESSAGE - records an error for a path; the scan goes on
err() { printf '%s\t%s\n' "$1" "$2" | tr -d '\r' >>"$tmp/errors"; }
# rel PATH - path relative to ROOT, "." for ROOT itself
rel() { if [ "$1" = "$root" ]; then echo .; else printf '%s\n' "${1#"$root"/}"; fi; }
lines_to_json() { jq -R -s -c 'split("\n") | map(select(length > 0))'; }

# secret_path PATH - code 0 for a file whose name looks like a secret (secret_names.sh): never read
secret_path() { av_secret_name "$1" "$root"; }

EXCL=( -name vendor -o -name node_modules -o -name var -o -name cache -o -name worktrees -o -name tmp
  -o -name legacy-vendors -o -name build -o -name dist -o -name Pods -o -name public -o -name '.*' )
CFG_EXCL=( -name secrets -o -name jwt -o -name cache -o -name '.*' )

# MARK: autoload

# autoload_json APPDIR FACTS - declared autoload paths (first MAX_AUTOLOAD) with an existence check
# inside APPDIR; paths with ".." and absolute paths are not checked (exists: null)
autoload_json() {
  local d="$1" p rp exists
  jq -r --argjson max "$MAX_AUTOLOAD" '.autoload_rows[:$max][] | .path' <<<"$2" | LC_ALL=C sort -u |
    while IFS= read -r p; do
      rp="${p#./}"; rp="${rp%/}"; [ -n "$rp" ] || rp="."
      case "/$rp/" in
        */../*|//*) exists=null ;;
        *) if [ -e "$d/$rp" ]; then exists=true; else exists=false; fi ;;
      esac
      jq -n -c --arg p "$p" --argjson e "$exists" '{key: $p, value: $e}'
    done | jq -s -c 'reduce .[] as $x ({}; .[$x.key] = $x.value)' >"$tmp/autoload_exists"
  jq -c --argjson max "$MAX_AUTOLOAD" --slurpfile e "$tmp/autoload_exists" '
    .autoload_rows[:$max] | map(. + {exists: $e[0][.path]}
      + (if $e[0][.path] == null then {note: "outside the app directory, not checked"} else {} end))' <<<"$2"
}

# MARK: paths

# role<TAB>path - fixed list of Symfony convention paths; the role comes from this list, not from names found
CANDIDATES="config	config
config	config/packages
config	config/routes
config	config/bundles.php
config	config/services.yaml
config	config/services.yml
config	config/services.php
config	config/services.xml
config	config/routes.yaml
config	config/routes.php
config	config/routes.xml
code	src
code	src/Kernel.php
tests	tests
templates	templates
translations	translations
migrations	migrations
web	public
web	public/index.php
tooling	bin/console
tooling	symfony.lock
tooling	composer.lock"

paths_json() {
  local d="$1" role p full type
  : >"$tmp/absent"
  : >"$tmp/present"
  while IFS=$'\t' read -r role p; do
    full="$d/$p"
    if [ -L "$full" ]; then type=symlink
    elif [ -d "$full" ]; then type=dir
    elif [ -f "$full" ]; then type="file"
    else rel "$full" >>"$tmp/absent"; continue; fi
    jq -n -c --arg r "$role" --arg p "$(rel "$full")" --arg t "$type" '{path: $p, type: $t, role: $r, evidence: {path: $p}}' >>"$tmp/present"
  done <<<"$CANDIDATES"
  jq -s -c --argjson absent "$(lines_to_json <"$tmp/absent")" '{present: ., absent: $absent}' "$tmp/present"
}

# MARK: config formats

# config_json APPDIR - config/ files grouped by extension (names only); secrets/, jwt/, cache/,
# hidden directories and hidden files are skipped, env and key files are counted as skipped; null without config/
config_json() {
  local d="$1" c="$1/config" f skipped=0 total
  if [ -L "$c" ] || [ ! -d "$c" ]; then echo null; return 0; fi
  find "$c" -mindepth 1 -maxdepth "$MAX_CONFIG_DEPTH" -type d \( "${CFG_EXCL[@]}" \) -prune -o -type f ! -name '.*' -print 2>/dev/null |
    LC_ALL=C sort >"$tmp/cfgall"
  find "$c" -mindepth 1 -maxdepth "$MAX_CONFIG_DEPTH" -type d \( "${CFG_EXCL[@]}" \) -print -prune 2>/dev/null |
    LC_ALL=C sort | while IFS= read -r f; do rel "$f"; done >"$tmp/cfgexcl"
  : >"$tmp/cfg"
  while IFS= read -r f; do
    if secret_path "$f"; then skipped=$((skipped + 1)); else rel "$f" >>"$tmp/cfg"; fi
  done <"$tmp/cfgall"
  total="$(wc -l <"$tmp/cfg" | tr -d ' ')"
  trunc "apps[$app_rel].config_formats files" "$MAX_CONFIG_FILES" "$total"
  if [ -n "$(find "$c" -mindepth 1 -maxdepth "$((MAX_CONFIG_DEPTH + 1))" -type d \( "${CFG_EXCL[@]}" \) -prune -o -print 2>/dev/null |
      awk -v n="${#c}" -v lim="$MAX_CONFIG_DEPTH" '{ s = substr($0, n + 2); if (gsub("/", "/", s) >= lim) { print; exit } }')" ]; then
    depthcut "apps[$app_rel].config_formats depth" "$MAX_CONFIG_DEPTH"
  fi
  head -n "$MAX_CONFIG_FILES" "$tmp/cfg" | awk -F/ '{
      n = $NF; e = "(none)"
      if (match(n, /\.[^.]+$/) && RSTART > 1) e = tolower(substr(n, RSTART + 1))
      if (e == "yml") e = "yaml"
      print e "\t" $0 }' |
    jq -R -s -c --argjson max "$MAX_SAMPLES" --argjson total "$total" --argjson skipped "$skipped" \
      --arg dir "$(rel "$c")" --argjson excl "$(lines_to_json <"$tmp/cfgexcl")" '
      split("\n") | map(select(length > 0) | split("\t"))
      | group_by(.[0])
      | {dir: $dir, files_total: $total, secret_like_skipped: $skipped, excluded_dirs: $excl,
         formats: map({format: .[0][0], files: length, evidence: (map({path: .[1]}) | .[:$max])})}'
}

# MARK: test tools

# tool<TAB>path - files whose presence points at a test tool; only names are checked
TOOL_FILES="phpunit	phpunit.xml
phpunit	phpunit.xml.dist
phpunit	phpunit.dist.xml
phpunit	bin/phpunit
pest	tests/Pest.php
behat	behat.yml
behat	behat.yml.dist
behat	behat.dist.yml
behat	behat.yaml
behat	behat.dist.yaml
codeception	codeception.yml
codeception	codeception.dist.yml
codeception	codeception.yaml
phpspec	phpspec.yml
phpspec	phpspec.yml.dist
phpspec	.phpspec.yml
infection	infection.json
infection	infection.json5
infection	infection.json.dist
infection	infection.json5.dist"

tool_files_json() {
  local d="$1" t p
  printf '%s\n' "$TOOL_FILES" | while IFS=$'\t' read -r t p; do
    [ -f "$d/$p" ] || continue
    jq -n -c --arg t "$t" --arg p "$(rel "$d/$p")" '{tool: $t, evidence: {path: $p}}'
  done | jq -s -c .
}

# MARK: app

app_json() {
  local d="$1" status=ok facts=null autoload='[]' paths config tools
  app_rel="$(rel "$d")"
  manifest_rel="$(rel "$d/composer.json")"
  if [ ! -r "$d/composer.json" ]; then status=unreadable; err "$manifest_rel" "composer.json is not readable"
  elif [ -n "$(find "$d/composer.json" -size +"${MAX_MANIFEST_KB}"k 2>/dev/null)" ]; then status=too_large; err "$manifest_rel" "composer.json is larger than ${MAX_MANIFEST_KB} KB, not read"
  elif ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$d/composer.json" >/dev/null 2>&1; then status=malformed; err "$manifest_rel" "composer.json is not a single valid JSON object"
  fi
  if [ "$status" = ok ]; then
    facts="$(jq -c --arg p "$manifest_rel" --argjson max "$MAX_PACKAGES" -f "$here/composer-facts.jq" "$d/composer.json" 2>"$tmp/jqerr")" || {
      status=error; facts=null; err "$manifest_rel" "composer.json facts failed: $(head -c 200 "$tmp/jqerr" | tr '\t\n' '  ')"; }
  fi
  if [ "$status" = ok ]; then
    trunc "apps[$app_rel].packages" "$MAX_PACKAGES" "$(jq -r '.packages_total' <<<"$facts")"
    trunc "apps[$app_rel].autoload" "$MAX_AUTOLOAD" "$(jq -r '.autoload_rows | length' <<<"$facts")"
    autoload="$(autoload_json "$d" "$facts")"
  fi
  paths="$(paths_json "$d")"
  config="$(config_json "$d")"
  tools="$(tool_files_json "$d")"
  jq -n -c --arg dir "$app_rel" --arg m "$manifest_rel" --arg status "$status" --argjson f "$facts" \
    --argjson autoload "$autoload" --argjson paths "$paths" --argjson config "$config" --argjson tools "$tools" '
    ($f // {}) as $x
    | ($x.symfony.declared_version.constraint // "") as $ver
    | {dir: $dir, manifest: $m,
       composer: ($x.composer // {status: $status, evidence: [{path: $m}]}),
       php: ($x.php // null), php_platform: ($x.php_platform // null),
       symfony: ($x.symfony // {present: "unknown", evidence: [{path: $m}]}),
       packages: ($x.packages // []), packages_total: ($x.packages_total // null), packages_ignored: ($x.packages_ignored // null),
       autoload: $autoload, paths: $paths, config_formats: $config,
       test_tools: ((($x.tool_packages // []) + $tools) | group_by(.tool)
                    | map({tool: .[0].tool, evidence: (map(.evidence) | unique_by([.path, (.key // "")]))})),
       unknown: (
         (if $status != "ok" then [{field: "composer", reason: ("composer.json " + $status + ": packages, versions and Symfony presence unknown"), evidence: {path: $m}}] else [] end)
         + (if $status == "ok" and $x.php == null then [{field: "php.constraint", reason: "no php key in require or require-dev", evidence: {path: $m}}] else [] end)
         + (if ($ver | test("^\\*$|^dev-")) then [{field: "symfony.declared_version", reason: ("constraint " + $ver + " does not pin a version"), evidence: $x.symfony.declared_version.evidence}] else [] end)
         + (if $config == null then [{field: "config_formats", reason: "no config/ directory, or it is a symlink (not followed)"}] else [] end)
         + [{field: "installed_versions", reason: "composer.lock and vendor/ are not read; only declared constraints are reported"}])}'
}

# MARK: discovery

find "$root" -mindepth 1 -maxdepth "$((MAX_DEPTH + 1))" -type d \( "${EXCL[@]}" \) -prune -o -type f -name composer.json -print 2>/dev/null |
  while IFS= read -r f; do d="$(dirname "$f")"; printf '%s\t%s\n' "$(rel "$d")" "$d"; done |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1 |
  awk -F'\t' '$1 == "." { print; next } { rest[++n] = $0 } END { for (i = 1; i <= n; i++) print rest[i] }' >"$tmp/manifests"
find "$root" -mindepth 1 -maxdepth "$MAX_DEPTH" -type d \( "${EXCL[@]}" \) -print -prune 2>/dev/null |
  while IFS= read -r f; do rel "$f"; done | awk '{ n = gsub("/", "/"); print n "\t" $0 }' |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f2- >"$tmp/excluded"
apps_total="$(wc -l <"$tmp/manifests" | tr -d ' ')"
trunc apps "$MAX_APPS" "$apps_total"
trunc excluded_dirs "$MAX_EXCLUDED" "$(wc -l <"$tmp/excluded" | tr -d ' ')"
head -n "$MAX_APPS" "$tmp/manifests" | while IFS=$'\t' read -r _ d; do app_json "$d" </dev/null; done >>"$tmp/apps"

# MARK: assembly

result="$(jq -n -c --arg root "$root" --arg name "$(basename "$root")" --arg started "$started" \
  --argjson dur "$((SECONDS - t0))" --argjson apps "$(jq -s -c . "$tmp/apps")" --argjson total "$apps_total" \
  --argjson excl "$(head -n "$MAX_EXCLUDED" "$tmp/excluded" | lines_to_json)" \
  --argjson limits "$(jq -n -c --argjson a "$MAX_DEPTH" --argjson b "$MAX_APPS" --argjson c "$MAX_PACKAGES" --argjson d "$MAX_AUTOLOAD" \
      --argjson e "$MAX_CONFIG_FILES" --argjson f "$MAX_CONFIG_DEPTH" --argjson g "$MAX_MANIFEST_KB" --argjson h "$MAX_SAMPLES" --argjson i "$MAX_EXCLUDED" \
      '{max_depth: $a, max_apps: $b, max_packages: $c, max_autoload: $d, max_config_files: $e, max_config_depth: $f,
        max_manifest_kb: $g, max_samples: $h, max_excluded: $i}')" \
  --argjson cut "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
      | {field: .[0], shown: (.[1] | tonumber), total: (if .[2] == "" then null else (.[2] | tonumber) end), reason: .[3]})' "$tmp/trunc")" \
  --argjson errors "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {path: .[0], error: .[1]})' "$tmp/errors")" '
  {adapter: "php-symfony", schema_version: 1, root: $root, name: $name, started: $started, duration_sec: $dur,
   complete: (($cut | length) == 0 and ($errors | length) == 0),
   limits: $limits, truncated: $cut, errors: $errors,
   excluded_dirs: $excl,
   summary: {composer_manifests: $total, apps_reported: ($apps | length),
             symfony: ($apps | map(.symfony.present) | group_by(.) | map({(.[0]): length}) | add // {})},
   unknown: ((if $total == 0 then [{field: "composer", reason: "no composer.json within max_depth outside excluded dirs; PHP presence is not decided here"}] else [] end)
             + [{field: "deeper_manifests", reason: ("composer.json files deeper than " + ($limits.max_depth | tostring) + " directory levels are not searched")}]),
   notes: ["facts only: no architecture, layers or class relations are inferred from directory names",
           "files other than composer.json are listed by name and never opened"],
   apps: ($apps | sort_by([(.dir != "."), .dir]))}')"

if [ "$pretty" -eq 1 ]; then jq . <<<"$result"; else printf '%s\n' "$result"; fi

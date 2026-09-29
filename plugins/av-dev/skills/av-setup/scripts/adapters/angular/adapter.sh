#!/usr/bin/env bash
# adapter.sh - lightweight Angular adapter for av-setup scan.sh.
#
# Reports explicit facts only: Angular presence declared in package.json, declared constraints of
# relevant packages, angular.json projects with builders and configuration names, existing paths
# from a fixed Angular convention list and files that point at test tools. Every fact has evidence:
# a path, plus the JSON key when the fact comes from a JSON file.
# Versions come in three separate fields that are never merged: declared (package.json constraint),
# locked (package-lock.json or npm-shrinkwrap.json) and installed (node_modules/<pkg>/package.json
# for a fixed list of key packages, read one by one; node_modules is never walked).
# Does not infer architecture, modules, layers or component relations from names; never opens
# .ts, .html, .scss or .js files. Other files are listed by name only.
# Never reads .env*, .npmrc, key files or credentials; skips node_modules, dist, build, .angular,
# coverage, worktrees and hidden directories while looking for manifests.
#
# Usage:
#   adapter.sh [ROOT] [--pretty] [--max-depth N] [--max-apps N] [--max-packages N]
#              [--max-projects N] [--max-targets N] [--max-configurations N]
#              [--max-manifest-kb N] [--max-lock-kb N]
# Exit: 0 JSON printed (errors are reported inside), 2 jq missing, ROOT missing or bad option.
# Requires: bash 3.2+, jq, find, awk, sort, package-facts.jq and workspace-facts.jq next to this
# script. Temp files go to $TMPDIR.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="."
pretty=0
MAX_DEPTH=3
MAX_APPS=8
MAX_PACKAGES=80
MAX_PROJECTS=20
MAX_TARGETS=15
MAX_CONFIGURATIONS=20
MAX_MANIFEST_KB=512
MAX_LOCK_KB=20480
MAX_INSTALLED_KB=64
MAX_EXCLUDED=20
KEY_PACKAGES='["@angular/core","@angular/cli","@angular/build","@angular-devkit/build-angular","typescript","rxjs","zone.js"]'

usage_error() { printf '{"error":"%s"}\n' "$(printf '%s' "$1" | tr -d '"\\' | tr '\t\n' '  ')"; exit 2; }
num() { case "${1:-}" in ''|*[!0-9]*) usage_error "$2 needs a non-negative number" ;; esac; }

while [ $# -gt 0 ]; do
  case "$1" in
    --pretty) pretty=1 ;;
    --max-depth) num "${2:-}" "$1"; MAX_DEPTH="$2"; shift ;;
    --max-apps) num "${2:-}" "$1"; MAX_APPS="$2"; shift ;;
    --max-packages) num "${2:-}" "$1"; MAX_PACKAGES="$2"; shift ;;
    --max-projects) num "${2:-}" "$1"; MAX_PROJECTS="$2"; shift ;;
    --max-targets) num "${2:-}" "$1"; MAX_TARGETS="$2"; shift ;;
    --max-configurations) num "${2:-}" "$1"; MAX_CONFIGURATIONS="$2"; shift ;;
    --max-manifest-kb) num "${2:-}" "$1"; MAX_MANIFEST_KB="$2"; shift ;;
    --max-lock-kb) num "${2:-}" "$1"; MAX_LOCK_KB="$2"; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    -*) usage_error "unknown option $1" ;;
    *) root="$1" ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || usage_error "jq not found"
for f in package-facts.jq workspace-facts.jq; do
  [ -f "$here/$f" ] || usage_error "$f not found next to adapter.sh"
done
root="$(cd "$root" 2>/dev/null && pwd)" || usage_error "directory not found"
root_real="$(cd -P "$root" && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/av-angular.XXXXXX")" || usage_error "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/trunc"
: >"$tmp/errors"
: >"$tmp/apps"

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
t0=$SECONDS

# trunc FIELD SHOWN TOTAL - records a list cut to a limit
trunc() { [ "${3:-0}" -gt "${2:-0}" ] && printf '%s\t%s\t%s\tlimit\n' "$1" "$2" "$3" >>"$tmp/trunc"; return 0; }
# err PATH MESSAGE - records an error for a path; the scan goes on
err() { printf '%s\t%s\n' "$1" "$2" | tr -d '\r' >>"$tmp/errors"; }
# rel PATH - path relative to ROOT, "." for ROOT itself
rel() { if [ "$1" = "$root" ]; then echo .; else printf '%s\n' "${1#"$root"/}"; fi; }
lines_to_json() { jq -R -s -c 'split("\n") | map(select(length > 0))'; }

# json_status FILE MAX_KB - missing, symlink, unreadable, too_large, malformed or ok (one JSON object)
json_status() {
  if [ -L "$1" ]; then echo symlink
  elif [ ! -e "$1" ]; then echo missing
  elif [ ! -f "$1" ] || [ ! -r "$1" ]; then echo unreadable
  elif [ -n "$(find "$1" -size +"$2"k 2>/dev/null)" ]; then echo too_large
  elif ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$1" >/dev/null 2>&1; then echo malformed
  else echo ok; fi
}
# status_error REL_PATH STATUS MAX_KB - records the error for a JSON file that was not read
status_error() {
  case "$2" in
    symlink) err "$1" "${1##*/} is a symlink, not followed" ;;
    unreadable) err "$1" "${1##*/} is not a readable file" ;;
    too_large) err "$1" "${1##*/} is larger than $3 KB, not read" ;;
    malformed) err "$1" "${1##*/} is not a single valid JSON object" ;;
  esac
}

EXCL=( -name node_modules -o -name vendor -o -name Pods -o -name build -o -name dist -o -name out-tsc
  -o -name coverage -o -name var -o -name tmp -o -name cache -o -name worktrees -o -name public
  -o -name workspace -o -name '.*' )

# MARK: path existence

# exists_map JSON_ARRAY_OF_PATHS APPDIR - {path: true|false|null}; paths with ".." and absolute paths
# are not checked (null); "" and "." mean APPDIR
exists_map() {
  local d="$2" p rp e
  jq -r '.[]' <<<"$1" | while IFS= read -r p; do
    rp="${p#./}"; rp="${rp%/}"; [ -n "$rp" ] || rp="."
    case "/$rp/" in
      */../*|//*) e=null ;;
      *) if [ -e "$d/$rp" ]; then e=true; else e=false; fi ;;
    esac
    jq -n -c --arg p "$p" --argjson e "$e" '{key: $p, value: $e}'
  done | jq -s -c 'reduce .[] as $x ({}; .[$x.key] = $x.value)'
}

# MARK: workspace

# workspace_json APPDIR - facts of APPDIR/angular.json; null when there is none
workspace_json() {
  local d="$1" f="$1/angular.json" r st facts
  r="$(rel "$f")"
  st="$(json_status "$f" "$MAX_MANIFEST_KB")"
  case "$st" in
    missing) echo null; return 0 ;;
    ok) ;;
    *) status_error "$r" "$st" "$MAX_MANIFEST_KB"
       jq -n -c --arg s "$st" --arg r "$r" '{status: $s, evidence: {path: $r}}'; return 0 ;;
  esac
  facts="$(jq -c --arg p "$r" --argjson maxp "$MAX_PROJECTS" --argjson maxt "$MAX_TARGETS" --argjson maxc "$MAX_CONFIGURATIONS" \
    -f "$here/workspace-facts.jq" "$f" 2>"$tmp/jqerr")" || {
    err "$r" "angular.json facts failed: $(head -c 200 "$tmp/jqerr" | tr '\t\n' '  ')"
    jq -n -c --arg r "$r" '{status: "error", evidence: {path: $r}}'; return 0; }
  jq -r '._cuts[] | [.field, .shown, .total] | @tsv' <<<"$facts" | while IFS=$'\t' read -r fld shown total; do
    trunc "apps[$app_rel].workspace.$fld" "$shown" "$total"
  done
  jq -r '._errors[]' <<<"$facts" | while IFS= read -r m; do err "$r" "angular.json $m"; done
  jq -c --arg r "$r" --argjson e "$(exists_map "$(jq -c '._paths' <<<"$facts")" "$d")" '
    def ex: if . == null then null else $e[.] end;
    del(._cuts, ._errors, ._paths)
    | {status: "ok", evidence: {path: $r}} + .
    | .projects |= map(if .error then . else
        . + {root_exists: (.root | ex), source_root_exists: (.source_root | ex)}
        | .targets |= map(.option_files |= map(. + {exists: (.path | ex)}
            + (if (.path | ex) == null then {note: "outside the workspace directory, not checked"} else {} end))) end)' <<<"$facts"
}

# MARK: versions

# lock_json APPDIR - lockfiles in APPDIR and locked versions of KEY_PACKAGES from the first npm lockfile
# (npm-shrinkwrap.json before package-lock.json); yarn, pnpm and bun lockfiles are listed, not parsed
lock_json() {
  local d="$1" name f r fmt st used="" locked=null
  : >"$tmp/lockfiles"
  for name in npm-shrinkwrap.json package-lock.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb; do
    f="$d/$name"
    [ -e "$f" ] || [ -L "$f" ] || continue
    r="$(rel "$f")"
    case "$name" in *.json) fmt=npm ;; yarn.lock) fmt=yarn ;; pnpm-lock.yaml) fmt=pnpm ;; *) fmt=bun ;; esac
    if [ "$fmt" != npm ]; then st=not_parsed
    elif [ -n "$used" ]; then st=not_used
    else
      st="$(json_status "$f" "$MAX_LOCK_KB")"
      if [ "$st" = ok ]; then used="$f"; st="read"; else status_error "$r" "$st" "$MAX_LOCK_KB"; fi
    fi
    jq -n -c --arg p "$r" --arg f "$fmt" --arg s "$st" '{path: $p, format: $f, status: $s}' >>"$tmp/lockfiles"
  done
  if [ -n "$used" ]; then
    locked="$(jq -c --arg p "$(rel "$used")" --argjson keys "$KEY_PACKAGES" '
      def safe: if test("://[^/?#\\s]*@") then "(url with credentials, not printed)" else . end;
      ((.packages | objects) // {}) as $pk | ((.dependencies | objects) // {}) as $dp
      | {lockfile_version: (if (.lockfileVersion | type) == "number" then .lockfileVersion else null end),
         evidence: {path: $p, key: "lockfileVersion"},
         packages: [$keys[] as $k
           | if ($pk["node_modules/" + $k] | if type == "object" then (.version | type) == "string" else false end)
             then {name: $k, version: ($pk["node_modules/" + $k].version | safe), evidence: {path: $p, key: ("packages.node_modules/" + $k + ".version")}}
             elif ($dp[$k] | if type == "object" then (.version | type) == "string" else false end)
             then {name: $k, version: ($dp[$k].version | safe), evidence: {path: $p, key: ("dependencies." + $k + ".version")}}
             else empty end]}' "$used" 2>"$tmp/jqerr")" || {
      err "$(rel "$used")" "lockfile facts failed: $(head -c 200 "$tmp/jqerr" | tr '\t\n' '  ')"; locked=null; }
  fi
  jq -n -c --argjson files "$(jq -s -c . "$tmp/lockfiles")" --argjson l "$locked" '{files: $files, locked: $l}'
}

# installed_json APPDIR - versions of KEY_PACKAGES from APPDIR/node_modules/<pkg>/package.json, one
# known file per package; a package directory that resolves outside ROOT through a symlink is not read
installed_json() {
  local d="$1" k f r real
  if [ ! -d "$d/node_modules" ]; then echo '{"node_modules": false, "packages": []}'; return 0; fi
  jq -r '.[]' <<<"$KEY_PACKAGES" | while IFS= read -r k; do
    f="$d/node_modules/$k/package.json"
    [ -e "$f" ] || continue
    r="$(rel "$f")"
    real="$(cd -P "$d/node_modules/$k" 2>/dev/null && pwd)"
    case "$real/" in
      "$root_real"/*) ;;
      *) err "$r" "package directory resolves outside ROOT through a symlink, not read"; continue ;;
    esac
    if [ -L "$f" ] || [ ! -f "$f" ] || [ -n "$(find "$f" -size +"$MAX_INSTALLED_KB"k 2>/dev/null)" ]; then
      err "$r" "installed package.json is a symlink, not a file or larger than $MAX_INSTALLED_KB KB, not read"; continue
    fi
    jq -e -c --arg p "$r" --arg k "$k" '
      def safe: if test("://[^/?#\\s]*@") then "(url with credentials, not printed)" else . end;
      select(type == "object" and (.version | type) == "string")
      | {name: $k, version: (.version | safe), evidence: {path: $p, key: "version"}}' "$f" 2>/dev/null ||
      err "$r" "installed package.json has no string version or is not valid JSON"
  done | jq -s -c '{node_modules: true, packages: .}'
}

# MARK: paths

# role<TAB>path - fixed list of Angular convention paths; the role comes from this list, not from names found
CANDIDATES="workspace	angular.json
workspace	.angular-cli.json
workspace	nx.json
workspace	project.json
workspace	workspace.json
config	tsconfig.json
config	tsconfig.base.json
config	tsconfig.app.json
config	tsconfig.spec.json
config	proxy.conf.json
config	proxy.conf.js
config	ngsw-config.json
code	src
code	src/main.ts
code	src/main.server.ts
code	src/app
code	src/environments
code	projects
code	apps
code	libs
assets	src/assets
assets	public
i18n	src/locale
tests	e2e
tooling	package-lock.json
tooling	npm-shrinkwrap.json
tooling	yarn.lock
tooling	pnpm-lock.yaml
tooling	bun.lock
tooling	bun.lockb
tooling	node_modules"

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

# MARK: test tools

# tool<TAB>path - files whose presence points at a test tool; only names are checked
TOOL_FILES="karma	karma.conf.js
karma	karma.conf.cjs
karma	karma.conf.mjs
karma	karma.conf.ts
jest	jest.config.js
jest	jest.config.cjs
jest	jest.config.mjs
jest	jest.config.ts
jest	jest.config.json
jest	setup-jest.ts
vitest	vitest.config.ts
vitest	vitest.config.mts
vitest	vitest.config.js
vitest	vitest.config.mjs
vitest	vitest.workspace.ts
playwright	playwright.config.ts
playwright	playwright.config.js
playwright	playwright.config.mjs
cypress	cypress.config.ts
cypress	cypress.config.js
cypress	cypress.config.mjs
cypress	cypress.json
protractor	protractor.conf.js
protractor	e2e/protractor.conf.js
web-test-runner	web-test-runner.config.mjs
web-test-runner	web-test-runner.config.js"

tool_files_json() {
  local d="$1" t p
  printf '%s\n' "$TOOL_FILES" | while IFS=$'\t' read -r t p; do
    [ -f "$d/$p" ] || continue
    jq -n -c --arg t "$t" --arg p "$(rel "$d/$p")" '{tool: $t, evidence: {path: $p}}'
  done | jq -s -c .
}

# MARK: app

app_json() {
  local d="$1" pstatus facts=null ws lock inst paths tools
  app_rel="$(rel "$d")"
  pkg_rel="$(rel "$d/package.json")"
  pstatus="$(json_status "$d/package.json" "$MAX_MANIFEST_KB")"
  case "$pstatus" in
    ok) facts="$(jq -c --arg p "$pkg_rel" --argjson max "$MAX_PACKAGES" --argjson keys "$KEY_PACKAGES" \
          -f "$here/package-facts.jq" "$d/package.json" 2>"$tmp/jqerr")" || {
          pstatus=error; facts=null; err "$pkg_rel" "package.json facts failed: $(head -c 200 "$tmp/jqerr" | tr '\t\n' '  ')"; } ;;
    missing) ;;
    *) status_error "$pkg_rel" "$pstatus" "$MAX_MANIFEST_KB" ;;
  esac
  if [ "$pstatus" = ok ]; then
    trunc "apps[$app_rel].packages" "$MAX_PACKAGES" "$(jq -r '.packages_total' <<<"$facts")"
    trunc "apps[$app_rel].workspaces.patterns" "$MAX_PACKAGES" "$(jq -r '.workspaces.total // 0' <<<"$facts")"
  fi
  ws="$(workspace_json "$d")"
  lock="$(lock_json "$d")"
  inst="$(installed_json "$d")"
  paths="$(paths_json "$d")"
  tools="$(tool_files_json "$d")"
  jq -n -c --arg dir "$app_rel" --arg m "$pkg_rel" --arg status "$pstatus" --argjson f "$facts" --argjson ws "$ws" \
    --argjson lock "$lock" --argjson inst "$inst" --argjson paths "$paths" --argjson tools "$tools" '
    ($f // {}) as $x
    | ($x.angular.declared_version // null) as $dv
    | {dir: $dir,
       manifest: (if $status == "missing" then null else $m end),
       package: ($x.package // {status: $status, evidence: (if $status == "missing" then [] else [{path: $m}] end)}),
       angular: ($x.angular // {present: "unknown", evidence: (if $status == "missing" then [] else [{path: $m}] end)}),
       versions: {declared: ($x.key_packages // []),
                  locked: ($lock.locked.packages // []), lockfile_version: ($lock.locked.lockfile_version // null),
                  installed: $inst.packages},
       lockfiles: $lock.files,
       engines_node: ($x.engines_node // null), package_manager: ($x.package_manager // null), workspaces: ($x.workspaces // null),
       packages: ($x.packages // []), packages_total: ($x.packages_total // null), packages_ignored: ($x.packages_ignored // null),
       workspace: (if $ws == null then null else $ws | del(.builder_tools) end),
       paths: $paths,
       test_tools: ((($x.tool_packages // []) + $tools + ($ws.builder_tools // [])) | group_by(.tool)
                    | map({tool: .[0].tool, evidence: (map(.evidence) | unique_by([.path, (.key // "")]))})),
       unknown: (
         (if $status == "missing" then [{field: "package", reason: "no package.json in this directory: packages, versions and Angular presence unknown"}]
          elif $status != "ok" then [{field: "package", reason: ("package.json " + $status + ": packages, versions and Angular presence unknown"), evidence: {path: $m}}]
          else [] end)
         + (if $dv != null and $dv.major == null then [{field: "angular.declared_version.major", reason: ("constraint " + $dv.constraint + " does not name one major version"), evidence: $dv.evidence}] else [] end)
         + (if $ws == null then [{field: "workspace", reason: "no angular.json in this directory"}]
            elif $ws.status != "ok" then [{field: "workspace", reason: ("angular.json " + $ws.status + ": projects and builders unknown"), evidence: $ws.evidence}]
            else [] end)
         + (if $lock.locked == null then [{field: "versions.locked", reason:
              (if ($lock.files | length) == 0 then "no lockfile in this directory; parent lockfiles are not read"
               else "no readable npm lockfile; yarn, pnpm and bun lockfiles are listed, not parsed" end)}] else [] end)
         + (if $inst.node_modules == false then [{field: "versions.installed", reason: "no node_modules in this directory: installed versions unknown (parent node_modules are not read)"}] else [] end)
         + (if any($paths.present[]; .path | test("(^|/)(nx|project|workspace)\\.json$")) then [{field: "workspace.nx", reason: "nx.json, project.json and workspace.json are listed by name, not parsed"}] else [] end))}'
}

# MARK: discovery

find "$root" -mindepth 1 -maxdepth "$((MAX_DEPTH + 1))" -type d \( "${EXCL[@]}" \) -prune -o -type f \( -name package.json -o -name angular.json \) -print 2>/dev/null |
  while IFS= read -r f; do d="$(dirname "$f")"; printf '%s\t%s\n' "$(rel "$d")" "$d"; done |
  LC_ALL=C sort -u -t "$(printf '\t')" -k1,1 |
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
  --argjson limits "$(jq -n -c --argjson a "$MAX_DEPTH" --argjson b "$MAX_APPS" --argjson c "$MAX_PACKAGES" --argjson d "$MAX_PROJECTS" \
      --argjson e "$MAX_TARGETS" --argjson f "$MAX_CONFIGURATIONS" --argjson g "$MAX_MANIFEST_KB" --argjson h "$MAX_LOCK_KB" \
      --argjson i "$MAX_INSTALLED_KB" --argjson j "$MAX_EXCLUDED" \
      '{max_depth: $a, max_apps: $b, max_packages: $c, max_projects: $d, max_targets: $e, max_configurations: $f,
        max_manifest_kb: $g, max_lock_kb: $h, max_installed_kb: $i, max_excluded: $j}')" \
  --argjson cut "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
      | {field: .[0], shown: (.[1] | tonumber), total: (if .[2] == "" then null else (.[2] | tonumber) end), reason: .[3]})' "$tmp/trunc")" \
  --argjson errors "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {path: .[0], error: .[1]})' "$tmp/errors")" '
  {adapter: "angular", schema_version: 1, root: $root, name: $name, started: $started, duration_sec: $dur,
   complete: (($cut | length) == 0 and ($errors | length) == 0),
   limits: $limits, truncated: $cut, errors: $errors,
   excluded_dirs: $excl,
   summary: {manifest_dirs: $total, apps_reported: ($apps | length),
             angular_workspaces: ($apps | map(select(.workspace != null)) | length),
             angular: ($apps | map(.angular.present) | group_by(.) | map({(.[0]): length}) | add // {})},
   unknown: ((if $total == 0 then [{field: "package", reason: "no package.json or angular.json within max_depth outside excluded dirs; Angular presence is not decided here"}] else [] end)
             + [{field: "deeper_manifests", reason: ("package.json and angular.json files deeper than " + ($limits.max_depth | tostring) + " directory levels are not searched")}]),
   notes: ["facts only: no architecture, modules, layers or component relations are inferred from names",
           "declared, locked and installed versions are separate facts and are never merged",
           "only package.json, angular.json, npm lockfiles and node_modules/<key package>/package.json are opened; other files are listed by name"],
   apps: ($apps | sort_by([(.dir != "."), .dir]))}')"

if [ "$pretty" -eq 1 ]; then jq . <<<"$result"; else printf '%s\n' "$result"; fi

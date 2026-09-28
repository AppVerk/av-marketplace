#!/usr/bin/env bash
# adapter.sh - lightweight iOS/Xcode adapter for av-setup scan.sh.
#
# Reports explicit facts from Xcode and dependency manifests: workspaces (contents.xcworkspacedata),
# projects (project.pbxproj: targets, product types, build configurations, a fixed list of build settings,
# Swift package references), shared schemes, test plans, Podfile, Podfile.lock, Package.resolved and the
# swift-tools-version line of Package.swift. Every fact has evidence: a path plus a line or a manifest key.
# Versions are "declared" (Podfile, pbxproj package requirement) or "locked" (Podfile.lock, Package.resolved);
# installed versions are not read. No Swift parsing, no build, no xcodebuild; no architecture is inferred.
# Never opens .env*, key files, xcconfig, Info.plist, GoogleService-Info.plist, entitlements or xcuserdata;
# skips Pods, Carthage, build, DerivedData, SourcePackages, node_modules, vendor, worktrees and hidden dirs.
#
# Usage:
#   adapter.sh [ROOT] [--pretty] [--max-depth N] [--max-projects N] [--max-workspaces N] [--max-targets N]
#              [--max-configs N] [--max-packages N] [--max-schemes N] [--max-test-plans N] [--max-file-refs N]
#              [--max-pbxproj-kb N] [--max-manifest-kb N]
# Exit: 0 JSON printed (errors are reported inside), 2 jq or a helper file missing, ROOT missing or bad option.
# Requires: bash 3.2+, jq, awk, find, sort, head, wc, tr, cut, sed; pbxproj.awk, xml.awk, podfile.awk,
# podlock.awk, ios-facts.jq and pbxproj-facts.jq next to this script. Temp files go to $TMPDIR.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="."
pretty=0
MAX_DEPTH=3
MAX_PROJECTS=8
MAX_WORKSPACES=8
MAX_TARGETS=40
MAX_CONFIGS=20
MAX_PACKAGES=80
MAX_SCHEMES=30
MAX_TEST_PLANS=20
MAX_FILE_REFS=50
MAX_PBXPROJ_KB=8192
MAX_MANIFEST_KB=512
MAX_EXCLUDED=20

usage_error() { printf '{"error":"%s"}\n' "$(printf '%s' "$1" | tr -d '"\\' | tr '\t\n' '  ')"; exit 2; }
num() { case "${1:-}" in ''|*[!0-9]*|0[0-9]*) usage_error "$2 needs a non-negative number without leading zeros" ;; esac; }

while [ $# -gt 0 ]; do
  case "$1" in
    --pretty) pretty=1 ;;
    --max-depth) num "${2:-}" "$1"; MAX_DEPTH="$2"; shift ;;
    --max-projects) num "${2:-}" "$1"; MAX_PROJECTS="$2"; shift ;;
    --max-workspaces) num "${2:-}" "$1"; MAX_WORKSPACES="$2"; shift ;;
    --max-targets) num "${2:-}" "$1"; MAX_TARGETS="$2"; shift ;;
    --max-configs) num "${2:-}" "$1"; MAX_CONFIGS="$2"; shift ;;
    --max-packages) num "${2:-}" "$1"; MAX_PACKAGES="$2"; shift ;;
    --max-schemes) num "${2:-}" "$1"; MAX_SCHEMES="$2"; shift ;;
    --max-test-plans) num "${2:-}" "$1"; MAX_TEST_PLANS="$2"; shift ;;
    --max-file-refs) num "${2:-}" "$1"; MAX_FILE_REFS="$2"; shift ;;
    --max-pbxproj-kb) num "${2:-}" "$1"; MAX_PBXPROJ_KB="$2"; shift ;;
    --max-manifest-kb) num "${2:-}" "$1"; MAX_MANIFEST_KB="$2"; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    -*) usage_error "unknown option $1" ;;
    *) root="$1" ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || usage_error "jq not found"
for f in pbxproj.awk xml.awk podfile.awk podlock.awk ios-facts.jq pbxproj-facts.jq; do
  [ -f "$here/$f" ] || usage_error "$f not found next to adapter.sh"
done
secret_names="$(cd "$here/../.." && pwd)/secret_names.sh"
[ -f "$secret_names" ] || usage_error "secret_names.sh not found in av-setup/scripts"
# shellcheck source=../../secret_names.sh
. "$secret_names"
root="$(cd "$root" 2>/dev/null && pwd)" || usage_error "directory not found"
root_phys="$(cd -P "$root" && pwd -P)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/av-ios-xcode.XXXXXX")" || usage_error "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/trunc"
: >"$tmp/errors"
: >"$tmp/unknown"

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
t0=$SECONDS
TAB="$(printf '\t')"

# trunc FIELD SHOWN TOTAL - records a list cut to a limit
trunc() { [ "${3:-0}" -gt "${2:-0}" ] && printf '%s\t%s\t%s\tlimit\n' "$1" "$2" "$3" >>"$tmp/trunc"; return 0; }
# err PATH MESSAGE - records an error for a path; the scan goes on
err() { printf '%s\t%s\n' "$1" "$2" | tr -d '\r' >>"$tmp/errors"; }
# unknown FIELD REASON [PATH] - records a fact that is not decided here
unknown() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$tmp/unknown"; }
# rel PATH - path relative to ROOT, "." for ROOT itself
rel() { if [ "$1" = "$root" ]; then echo .; else printf '%s\n' "${1#"$root"/}"; fi; }
lines_to_json() { jq -R -s -c 'split("\n") | map(select(length > 0))'; }
jqm() { jq -L "$here" "$@"; }

# secret_path PATH - code 0 for a file that is never opened: a secret by name (secret_names.sh),
# plus build settings and entitlements, which may hold keys and team ids
secret_path() {
  av_secret_name "$1" "$root" && return 0
  case "${1##*/}" in
    *.xcconfig|*.entitlements) return 0 ;;
  esac
  return 1
}

# readable PATH MAXKB - code 0 when PATH can be opened; otherwise records an error and prints the status
readable() {
  local p="$1" r
  r="$(rel "$1")"
  if [ -L "$p" ]; then echo symlink; err "$r" "symlink, not followed"; return 1; fi
  if [ ! -e "$p" ]; then echo missing; err "$r" "file is missing"; return 1; fi
  case "$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P)/" in
    "$root_phys"/*) ;;
    *) echo outside_root; err "$r" "a parent directory is a symlink that leaves ROOT, not followed"; return 1 ;;
  esac
  if [ ! -f "$p" ] || [ ! -r "$p" ]; then echo unreadable; err "$r" "not a readable file"; return 1; fi
  if secret_path "$p"; then echo secret_like; err "$r" "name looks like a secret file, not opened"; return 1; fi
  if [ -n "$(find "$p" -size +"$2"k 2>/dev/null)" ]; then echo too_large; err "$r" "larger than $2 KB, not read"; return 1; fi
  return 0
}

# cuts PREFIX JSON - records the cuts a facts object lists in .cuts (prefixed) and prints the object without .cuts
cuts() {
  jq -r '.cuts[]? | [.field, .shown, .total] | @tsv' <<<"$2" | while IFS="$TAB" read -r f s t; do trunc "$1.$f" "$s" "$t"; done
  jq -c 'del(.cuts)' <<<"$2"
}

# first_error TSV - "line N: message" of the first E record, empty when none
first_error() { awk -F'\t' '$1 == "E" { print "line " $2 ": " $3; exit }' "$1"; }

EXCL=( -name Pods -o -name Carthage -o -name build -o -name DerivedData -o -name SourcePackages -o -name node_modules
  -o -name vendor -o -name worktrees -o -name xcuserdata -o -name tmp -o -name '.*' )

# MARK: existence map

# exists_map - reads relative paths (one per line) and prints {path: true|false}; entries with ".." are skipped
exists_map() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "/$p/" in */../*) continue ;; esac
    if [ -e "$root/$p" ] || [ -L "$root/$p" ]; then printf '%s\ttrue\n' "$p"; else printf '%s\tfalse\n' "$p"; fi
  done | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] == "true")}) | from_entries'
}

# MARK: schemes

# schemes_json CONTAINER - shared schemes of a .xcodeproj or .xcworkspace; user schemes (xcuserdata) are not read
schemes_json() {
  local c="$1" crel base dir f r status total out
  crel="$(rel "$c")"; base="$(dirname "$crel")"
  dir="$c/xcshareddata/xcschemes"
  : >"$tmp/schemes"
  if [ -d "$dir" ] && [ ! -L "$dir" ]; then
    find "$dir" -mindepth 1 -maxdepth 1 -name '*.xcscheme' -print 2>/dev/null | LC_ALL=C sort >"$tmp/schemefiles"
    total="$(wc -l <"$tmp/schemefiles" | tr -d ' ')"
    trunc "schemes[$crel]" "$MAX_SCHEMES" "$total"
    head -n "$MAX_SCHEMES" "$tmp/schemefiles" | while IFS= read -r f; do
      r="$(rel "$f")"
      if status="$(readable "$f" "$MAX_MANIFEST_KB")"; then
        awk -v attrs="buildConfiguration,BlueprintName,ReferencedContainer,reference,default,LastUpgradeVersion" -f "$here/xml.awk" "$f" >"$tmp/scheme.tsv" 2>/dev/null
        if [ -n "$(first_error "$tmp/scheme.tsv")" ]; then
          err "$r" "scheme is malformed: $(first_error "$tmp/scheme.tsv")"; status=malformed
        else
          out="$(jqm -R -s -c --arg p "$r" --arg b "$base" --argjson max "$MAX_PACKAGES" 'include "ios-facts"; scheme_facts($p; $b; $max)' "$tmp/scheme.tsv" 2>/dev/null)" || out='{"error":"jq failed"}'
          if [ "$(jq -r 'has("error")' <<<"$out")" = true ]; then
            err "$r" "scheme is malformed: $(jq -r .error <<<"$out")"; status=malformed
          else
            cuts "schemes[$r]" "$out" | jq -c --arg n "$(basename "$f" .xcscheme)" --arg p "$r" '{name: $n, path: $p, status: "ok"} + .'
            continue
          fi
        fi
      fi
      jq -n -c --arg n "$(basename "$f" .xcscheme)" --arg p "$r" --arg s "$status" '{name: $n, path: $p, status: $s}'
    done >>"$tmp/schemes"
  fi
  jq -s -c . "$tmp/schemes"
}

# MARK: projects

project_json() {
  local d="$1" prel pbx pbxrel status=ok facts=null schemes resolved=null msg
  prel="$(rel "$d")"; pbx="$d/project.pbxproj"; pbxrel="$(rel "$pbx")"
  if status="$(readable "$pbx" "$MAX_PBXPROJ_KB")"; then
    status=ok
    if ! awk -f "$here/pbxproj.awk" "$pbx" >"$tmp/pbx.tsv" 2>"$tmp/awkerr"; then
      status=error; err "$pbxrel" "pbxproj.awk failed: $(head -c 200 "$tmp/awkerr" | tr '\t\n' '  ')"
    elif [ -n "$(first_error "$tmp/pbx.tsv")" ]; then
      status=malformed; err "$pbxrel" "project.pbxproj is malformed: $(first_error "$tmp/pbx.tsv")"
    else
      facts="$(jqm -R -s -c --arg p "$pbxrel" --argjson maxt "$MAX_TARGETS" --argjson maxc "$MAX_CONFIGS" --argjson maxk "$MAX_PACKAGES" \
        'include "pbxproj-facts"; pbxproj_facts($p; $maxt; $maxc; $maxk)' "$tmp/pbx.tsv" 2>"$tmp/jqerr")" || {
        status=error; facts=null; err "$pbxrel" "project facts failed: $(head -c 200 "$tmp/jqerr" | tr '\t\n' '  ')"; }
      if [ "$status" = ok ] && msg="$(jq -r '.error // empty' <<<"$facts")" && [ -n "$msg" ]; then
        status=malformed; facts=null; err "$pbxrel" "project.pbxproj is malformed: $msg"
      fi
    fi
  fi
  if [ "$status" = ok ]; then
    trunc "projects[$prel].targets" "$MAX_TARGETS" "$(jq -r '.targets_total' <<<"$facts")"
    trunc "projects[$prel].swift_packages" "$MAX_PACKAGES" "$(jq -r '.swift_packages_total' <<<"$facts")"
    jq -r '.target_configs_cut[] | [.name, .total] | @tsv' <<<"$facts" | while IFS="$TAB" read -r n t; do
      trunc "projects[$prel].targets[$n].build_configurations" "$MAX_CONFIGS" "$t"; done
    jq -r '.dangling_targets[]' <<<"$facts" | while IFS= read -r n; do err "$pbxrel" "target $n is listed in the project but not defined"; done
    jq -r '.dangling_refs[] | [.kind, .id] | @tsv' <<<"$facts" | while IFS="$TAB" read -r k n; do err "$pbxrel" "$k $n is referenced but not defined"; done
    facts="$(cuts "projects[$prel]" "$facts")"
    jq -r '.swift_packages[] | select(.kind != "remote" and .kind != "local") | .evidence.key' <<<"$facts" |
      while IFS= read -r n; do err "$pbxrel" "package reference $n is missing or has an unexpected isa"; done
    if [ "$(jq -r '[.targets[].base_xcconfig_configs // 0, .project_level.base_xcconfig_configs // 0] | add' <<<"$facts")" -gt 0 ]; then
      unknown "projects[$prel].settings" "some build configurations have a base xcconfig file; xcconfig files are not read, so reported settings are only those written in project.pbxproj" "$pbxrel"
    fi
  fi
  schemes="$(schemes_json "$d")"
  if [ -f "$d/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" ]; then
    resolved="$(resolved_json "$d/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")"
  fi
  jq -n -c --arg path "$prel" --arg pbx "$pbxrel" --arg status "$status" --argjson f "$facts" --argjson schemes "$schemes" \
    --argjson resolved "$resolved" '
    {path: $path, pbxproj: $pbx, status: $status}
    + (($f // {}) | del(.status, .target_configs_cut, .dangling_targets, .dangling_refs))
    + {schemes: $schemes, package_resolved: $resolved}'
}

# MARK: workspaces

workspace_json() {
  local d="$1" wrel file frel status=ok facts=null base resolved=null schemes total
  wrel="$(rel "$d")"; base="$(dirname "$wrel")"; file="$d/contents.xcworkspacedata"; frel="$(rel "$file")"
  if status="$(readable "$file" "$MAX_MANIFEST_KB")"; then
    status=ok
    awk -v attrs="location,version" -f "$here/xml.awk" "$file" >"$tmp/ws.tsv" 2>/dev/null
    if [ -n "$(first_error "$tmp/ws.tsv")" ]; then
      status=malformed; err "$frel" "contents.xcworkspacedata is malformed: $(first_error "$tmp/ws.tsv")"
    else
      facts="$(jqm -R -s -c --arg p "$frel" --arg b "$base" 'include "ios-facts"; workspace_facts($p; $b)' "$tmp/ws.tsv" 2>/dev/null)" || facts='{"error":"jq failed"}'
      if [ "$(jq -r 'has("error")' <<<"$facts")" = true ]; then
        status=malformed; err "$frel" "contents.xcworkspacedata is malformed: $(jq -r .error <<<"$facts")"; facts=null
      else
        total="$(jq -r '.file_refs | length' <<<"$facts")"
        trunc "workspaces[$wrel].file_refs" "$MAX_FILE_REFS" "$total"
        facts="$(jq -c --argjson max "$MAX_FILE_REFS" --argjson e "$(jq -r '.file_refs[:'"$MAX_FILE_REFS"'][] | .path // empty' <<<"$facts" | exists_map)" '
          .file_refs_total = (.file_refs | length)
          | .file_refs = (.file_refs[:$max] | map(. + {exists: (if .path == null then null else $e[.path] end)}))' <<<"$facts")"
      fi
    fi
  fi
  schemes="$(schemes_json "$d")"
  [ -f "$d/xcshareddata/swiftpm/Package.resolved" ] && resolved="$(resolved_json "$d/xcshareddata/swiftpm/Package.resolved")"
  jq -n -c --arg path "$wrel" --arg m "$frel" --arg status "$status" --argjson f "$facts" --argjson schemes "$schemes" --argjson resolved "$resolved" '
    {path: $path, manifest: $m, status: $status} + ($f // {}) + {schemes: $schemes, package_resolved: $resolved}'
}

# MARK: Swift Package Manager

resolved_json() {
  local f="$1" r status out
  r="$(rel "$f")"
  if status="$(readable "$f" "$MAX_MANIFEST_KB")"; then
    if ! jq -e -s 'length == 1' "$f" >/dev/null 2>&1; then
      err "$r" "Package.resolved is not a single valid JSON document"; status=malformed
    elif ! jqm -e 'include "ios-facts"; resolved_valid' "$f" >/dev/null 2>&1; then
      err "$r" "Package.resolved has an unsupported version or no pins array"; status=unsupported
    else
      out="$(jqm -c --arg p "$r" --argjson max "$MAX_PACKAGES" 'include "ios-facts"; {version} + resolved_facts($p; $max)' "$f")"
      trunc "package_resolved[$r].pins" "$MAX_PACKAGES" "$(jq -r .pins_total <<<"$out")"
      [ "$(jq -r .pins_skipped <<<"$out")" -gt 0 ] && err "$r" "$(jq -r .pins_skipped <<<"$out") pins are not JSON objects and are not reported"
      jq -c --arg p "$r" '{path: $p, status: "ok", evidence: {path: $p, key: "version"}} + .' <<<"$out"
      return 0
    fi
  fi
  jq -n -c --arg p "$r" --arg s "$status" '{path: $p, status: $s}'
}

package_swift_json() {
  local f="$1" d r status tv=""
  d="$(dirname "$f")"; r="$(rel "$f")"
  if status="$(readable "$f" "$MAX_MANIFEST_KB")"; then
    status=ok
    tv="$(head -n 1 "$f" | tr -d '\r' | sed -n 's/^\/\/ *swift-tools-version *: *\([0-9][0-9.]*\).*/\1/p')"
    [ -n "$tv" ] || unknown "swiftpm.manifests[$r].tools_version" "first line has no // swift-tools-version comment" "$r"
  fi
  local resolved=null
  [ -f "$d/Package.resolved" ] && resolved="$(resolved_json "$d/Package.resolved")"
  jq -n -c --arg p "$r" --arg s "$status" --arg tv "$tv" --argjson res "$resolved" '
    {path: $p, status: $s,
     tools_version: (if $tv == "" then null else {value: $tv, evidence: {path: $p, line: 1}} end),
     package_resolved: $res}'
}

# MARK: CocoaPods

podfile_json() {
  local f="$1" d r lock lrel status=ok pf=null lk=null lstatus=null cmp=null
  d="$(dirname "$f")"; r="$(rel "$f")"; lock="$d/Podfile.lock"; lrel="$(rel "$lock")"
  if status="$(readable "$f" "$MAX_MANIFEST_KB")"; then
    status=ok
    awk -f "$here/podfile.awk" "$f" >"$tmp/podfile.tsv" 2>/dev/null
    pf="$(jqm -R -s -c --arg p "$r" --argjson max "$MAX_PACKAGES" 'include "ios-facts"; podfile_facts($p; $max)' "$tmp/podfile.tsv")"
    trunc "cocoapods[$r].podfile.pods" "$MAX_PACKAGES" "$(jq -r .pods_total <<<"$pf")"
    pf="$(cuts "cocoapods[$r].podfile" "$pf")"
    if [ "$(jq -r '(.not_followed | length) > 0 or .open_blocks_at_end != 0' <<<"$pf")" = true ]; then
      unknown "cocoapods[$r].podfile" "some Podfile statements are not followed (see not_followed, open_blocks_at_end); pods and their targets may be incomplete" "$r"
    fi
  fi
  if [ -e "$lock" ] || [ -L "$lock" ]; then
    if lstatus="$(readable "$lock" "$MAX_MANIFEST_KB")"; then
      lstatus=ok
      awk -f "$here/podlock.awk" "$lock" >"$tmp/podlock.tsv" 2>/dev/null
      if [ -n "$(first_error "$tmp/podlock.tsv")" ]; then
        lstatus=malformed; err "$lrel" "Podfile.lock is malformed: $(first_error "$tmp/podlock.tsv")"
      else
        lk="$(jqm -R -s -c --arg p "$lrel" --argjson max "$MAX_PACKAGES" 'include "ios-facts"; podlock_facts($p; $max)' "$tmp/podlock.tsv")"
        trunc "cocoapods[$r].lock.pods" "$MAX_PACKAGES" "$(jq -r .pods_total <<<"$lk")"
        lk="$(cuts "cocoapods[$r].lock" "$lk")"
      fi
    fi
  else
    lstatus=missing
    unknown "cocoapods[$r].lock" "no Podfile.lock next to the Podfile; locked versions unknown" "$r"
  fi
  if [ "$pf" != null ] && [ "$lk" != null ]; then
    cmp="$(jqm -n -c --argjson pf "$pf" --argjson lk "$lk" --arg lp "$lrel" 'include "ios-facts"; pods_compare($pf; $lk; $lp)')"
  fi
  local pods_dir=false
  [ -d "$d/Pods" ] && pods_dir=true
  jq -n -c --arg dir "$(rel "$d")" --arg r "$r" --arg s "$status" --argjson pf "$pf" --arg lr "$lrel" --arg ls "$lstatus" \
    --argjson lk "$lk" --argjson cmp "$cmp" --argjson pods "$pods_dir" '
    {dir: $dir,
     podfile: ({path: $r, status: $s} + (($pf // {}) | del(.all_pod_names)) + (if $cmp then {pods: $cmp.pods} else {} end)),
     lock: ({path: $lr, status: $ls} + (($lk // {}) | del(.entry_versions, .all_dependency_names))),
     comparison: (if $cmp then {declared_not_in_lock_dependencies: $cmp.declared_not_in_lock_dependencies,
                                lock_dependencies_not_declared: $cmp.lock_dependencies_not_declared,
                                rule: "pod names in the Podfile against DEPENDENCIES in Podfile.lock"} else null end),
     pods_dir: {path: (if $dir == "." then "Pods" else $dir + "/Pods" end), exists: $pods, read: false}}'
}

# MARK: test plans

testplan_json() {
  local f="$1" r status out
  r="$(rel "$f")"
  if status="$(readable "$f" "$MAX_MANIFEST_KB")"; then
    if ! jq -e -s 'length == 1 and (.[0] | type) == "object"' "$f" >/dev/null 2>&1; then
      err "$r" "test plan is not a single JSON object"; status=malformed
    else
      if out="$(jqm -c --arg p "$r" --argjson max "$MAX_PACKAGES" 'include "ios-facts"; {path: $p, status: "ok"} + testplan_facts($p; $max)' "$f" 2>/dev/null)"; then
        cuts "test_plans[$r]" "$out"
        return 0
      fi
      err "$r" "test plan facts failed"; status=error
    fi
  fi
  jq -n -c --arg p "$r" --arg s "$status" '{path: $p, status: $s}'
}

# MARK: tool files

# tool<TAB>path - files whose presence points at a tool; only names are checked, files are never opened
TOOL_FILES="xcodegen	project.yml
xcodegen	project.yaml
tuist	Project.swift
tuist	Workspace.swift
tuist	Tuist
carthage	Cartfile
carthage	Cartfile.resolved
mint	Mintfile
bundler	Gemfile
bundler	Gemfile.lock
fastlane	fastlane/Fastfile
swiftlint	.swiftlint.yml
swiftformat	.swiftformat
xcode_version	.xcode-version
swift_version	.swift-version"

tool_files_json() {
  local d t p
  while IFS= read -r d; do
    printf '%s\n' "$TOOL_FILES" | while IFS="$TAB" read -r t p; do
      [ -e "$d/$p" ] || continue
      jq -n -c --arg t "$t" --arg p "$(rel "$d/$p" | sed 's|^\./||')" '{tool: $t, evidence: {path: $p}}'
    done
  done | jq -s -c 'unique_by(.evidence.path) | sort_by([.tool, .evidence.path])'
}

# MARK: discovery

find "$root" -mindepth 1 -maxdepth "$((MAX_DEPTH + 1))" -type d \( "${EXCL[@]}" \) -prune \
  -o -type d \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print -prune \
  -o -type f \( -name Podfile -o -name Package.swift -o -name '*.xctestplan' \) -print 2>/dev/null |
  while IFS= read -r f; do r="$(rel "$f")"; printf '%s\t%s\t%s\n' "$(printf '%s' "$r" | tr -cd / | wc -c | tr -d ' ')" "$r" "$f"; done |
  LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 | cut -f2- >"$tmp/found"
find "$root" -mindepth 1 -maxdepth "$MAX_DEPTH" -type d \( "${EXCL[@]}" \) -print -prune \
  -o -type d \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -prune 2>/dev/null |
  while IFS= read -r f; do rel "$f"; done | awk '{ n = gsub("/", "/"); print n "\t" $0 }' |
  LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 | cut -f2- >"$tmp/excluded"

# pick KIND_REGEX - absolute paths of found entries whose relative path matches the pattern
pick() { awk -F'\t' -v re="$1" '$1 ~ re { print $2 }' "$tmp/found"; }
pick '[.]xcodeproj$' >"$tmp/projects"
pick '[.]xcworkspace$' >"$tmp/workspaces"
pick '(^|/)Podfile$' >"$tmp/podfiles"
pick '(^|/)Package[.]swift$' >"$tmp/pkgswift"
pick '[.]xctestplan$' >"$tmp/testplans"

count() { wc -l <"$1" | tr -d ' '; }
trunc projects "$MAX_PROJECTS" "$(count "$tmp/projects")"
trunc workspaces "$MAX_WORKSPACES" "$(count "$tmp/workspaces")"
trunc podfiles "$MAX_PROJECTS" "$(count "$tmp/podfiles")"
trunc swiftpm.manifests "$MAX_PROJECTS" "$(count "$tmp/pkgswift")"
trunc test_plans "$MAX_TEST_PLANS" "$(count "$tmp/testplans")"
trunc excluded_dirs "$MAX_EXCLUDED" "$(count "$tmp/excluded")"

head -n "$MAX_WORKSPACES" "$tmp/workspaces" | while IFS= read -r d; do workspace_json "$d" </dev/null; done >"$tmp/ws.json"
head -n "$MAX_PROJECTS" "$tmp/projects" | while IFS= read -r d; do project_json "$d" </dev/null; done >"$tmp/proj.json"
head -n "$MAX_PROJECTS" "$tmp/podfiles" | while IFS= read -r f; do podfile_json "$f" </dev/null; done >"$tmp/pods.json"
head -n "$MAX_PROJECTS" "$tmp/pkgswift" | while IFS= read -r f; do package_swift_json "$f" </dev/null; done >"$tmp/spm.json"
head -n "$MAX_TEST_PLANS" "$tmp/testplans" | while IFS= read -r f; do testplan_json "$f" </dev/null; done >"$tmp/plans.json"

# test plan references from schemes: existence of the resolved paths
jq -s -r '[.[] | .schemes[]? | .test_plans[]? | .path // empty] | unique[]' "$tmp/ws.json" "$tmp/proj.json" | exists_map >"$tmp/planrefs.json"

{ printf '%s\n' "$root"
  cut -f2 "$tmp/found" | while IFS= read -r p; do dirname "$p"; done
} | LC_ALL=C sort -u >"$tmp/containers"
tools="$(tool_files_json <"$tmp/containers")"

# MARK: assembly

found_total=$(( $(count "$tmp/projects") + $(count "$tmp/workspaces") + $(count "$tmp/podfiles") + $(count "$tmp/pkgswift") ))
result="$(jqm -n -c --arg root "$root" --arg name "$(basename "$root")" --arg started "$started" \
  --argjson dur "$((SECONDS - t0))" --argjson found "$found_total" \
  --slurpfile ws "$tmp/ws.json" --slurpfile proj "$tmp/proj.json" --slurpfile pods "$tmp/pods.json" \
  --slurpfile spm "$tmp/spm.json" --slurpfile plans "$tmp/plans.json" --slurpfile planrefs "$tmp/planrefs.json" \
  --argjson tools "$tools" \
  --argjson excl "$(head -n "$MAX_EXCLUDED" "$tmp/excluded" | lines_to_json)" \
  --argjson limits "$(jq -n -c --argjson a "$MAX_DEPTH" --argjson b "$MAX_PROJECTS" --argjson c "$MAX_WORKSPACES" --argjson d "$MAX_TARGETS" \
      --argjson e "$MAX_CONFIGS" --argjson f "$MAX_PACKAGES" --argjson g "$MAX_SCHEMES" --argjson h "$MAX_TEST_PLANS" --argjson i "$MAX_FILE_REFS" \
      --argjson j "$MAX_PBXPROJ_KB" --argjson k "$MAX_MANIFEST_KB" --argjson l "$MAX_EXCLUDED" \
      '{max_depth: $a, max_projects: $b, max_workspaces: $c, max_targets: $d, max_configs: $e, max_packages: $f, max_schemes: $g,
        max_test_plans: $h, max_file_refs: $i, max_pbxproj_kb: $j, max_manifest_kb: $k, max_excluded: $l}')" \
  --argjson cut "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
      | {field: .[0], shown: (.[1] | tonumber), total: (if .[2] == "" then null else (.[2] | tonumber) end), reason: .[3]})' "$tmp/trunc")" \
  --argjson errors "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {path: .[0], error: .[1]}) | unique_by([.path, .error])' "$tmp/errors")" \
  --argjson unk "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
      | {field: .[0], reason: .[1]} + (if (.[2] // "") == "" then {} else {evidence: {path: .[2]}} end)) | unique_by([.field, .reason])' "$tmp/unknown")" '
  include "ios-facts";
  ($planrefs[0] // {}) as $pr
  | ($ws | map(.schemes |= map(if .test_plans then .test_plans |= map(. + {exists: (if .path == null then null else $pr[.path] end)}) else . end))) as $ws
  | ($proj | map(.schemes |= map(if .test_plans then .test_plans |= map(. + {exists: (if .path == null then null else $pr[.path] end)}) else . end))) as $proj
  | ([($ws[], $proj[], $spm[]) | .package_resolved | objects | select(.status == "ok") | .pins[] | . as $pin
      | {key: (.location | norm_url), value: {identity, version, revision, branch, evidence}}]
     | map(select(.key != null)) | group_by(.key) | map({key: .[0].key, value: map(.value)}) | from_entries) as $pins
  | ($proj | map(.swift_packages |= (if . == null then null else map(if .kind == "remote" then . + {resolved: ($pins[.url | norm_url] // [])} else . end) end))) as $proj
  | ([($ws + $proj)[] | .schemes[]? | . as $s | .test_plans[]? | {key: (.path // ""), value: $s.path}] | group_by(.key) | map({key: .[0].key, value: map(.value) | unique}) | from_entries) as $refby
  | ($plans | map(. + {referenced_by: ($refby[.path] // [])})) as $plans
  | {adapter: "ios-xcode", schema_version: 1, root: $root, name: $name, started: $started, duration_sec: $dur,
     complete: (($cut | length) == 0 and ($errors | length) == 0),
     limits: $limits, truncated: $cut, errors: $errors,
     excluded_dirs: $excl,
     summary: {workspaces: ($ws | length), projects: ($proj | length),
               targets: ([$proj[] | .targets_total // 0] | add // 0),
               product_types: ([$proj[] | .targets[]? | .product_type] | group_by(.) | map({key: (.[0] // "(none)"), value: length}) | from_entries),
               schemes: ([($ws + $proj)[] | .schemes | length] | add // 0),
               test_plans: ($plans | length),
               podfiles: ($pods | length),
               pod_statements: ([$pods[] | .podfile.pods_total // 0] | add // 0),
               locked_pod_roots: ([$pods[] | .lock.pods_total // 0] | add // 0),
               swift_packages_declared: ([$proj[] | .swift_packages_total // 0] | add // 0),
               package_resolved_files: ([($ws[], $proj[], $spm[]) | .package_resolved | objects] | length),
               swift_pins_resolved: ([($ws[], $proj[], $spm[]) | .package_resolved | objects | .pins_total // 0] | add // 0),
               package_swift: ($spm | length)},
     unknown: ((if $found == 0 then [{field: "xcode", reason: "no .xcodeproj, .xcworkspace, Podfile or Package.swift within max_depth outside excluded dirs; iOS presence is not decided here"}] else [] end)
               + $unk
               + [{field: "deeper_manifests", reason: ("manifests deeper than " + ($limits.max_depth | tostring) + " directory levels are not searched")},
                  {field: "installed_versions", reason: "Pods/, Pods/Manifest.lock and DerivedData/SourcePackages are not read; versions are declared (Podfile, pbxproj requirement) or locked (Podfile.lock, Package.resolved)"},
                  {field: "effective_build_settings", reason: "only build settings written in project.pbxproj for a fixed key list are reported; xcconfig files and Xcode defaults are not resolved (that needs xcodebuild -showBuildSettings)"},
                  {field: "podfile_evaluation", reason: "the Podfile is Ruby; it is read line by line with literal strings only, never run"},
                  {field: "package_swift_dependencies", reason: "Package.swift is Swift; only its swift-tools-version line is read"},
                  {field: "user_schemes", reason: "schemes in xcuserdata are not read; only shared schemes in xcshareddata are listed"}]),
     notes: ["facts only: no architecture, layers, modules or relations are inferred from names",
             "opened files: project.pbxproj, contents.xcworkspacedata, *.xcscheme, *.xctestplan, Podfile, Podfile.lock, Package.resolved, line 1 of Package.swift",
             "values of build settings outside the fixed key list, scheme scripts and environment variables, test plan arguments and pod option values are never printed",
             "URL user info and query strings are removed from printed URLs (url_redacted: true)"],
     workspaces: $ws, projects: $proj, cocoapods: $pods,
     swiftpm: {manifests: $spm},
     test_plans: $plans, tool_files: $tools}')"

if [ "$pretty" -eq 1 ]; then jq . <<<"$result"; else printf '%s\n' "$result"; fi

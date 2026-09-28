#!/usr/bin/env bash
# adapter.sh - lightweight Android/Gradle adapter for av-setup scan.sh.
#
# Reports text facts from Gradle settings and build scripts (Groovy and Kotlin DSL), version
# catalogs (gradle/*.versions.toml), the wrapper distributionUrl and AndroidManifest.xml files.
# Every fact has evidence: a path, plus a line number when it comes from a script or catalog.
# Gradle is never run and scripts are not evaluated: values are declared text, expressions stay
# expressions, and a value found for an ext property or catalog alias is a text_candidate only.
# Markers (script plugins, subprojects/allprojects, conditions, loops, env/property access,
# flavors) point at configuration the text cannot settle. No architecture, layers or module
# relations are inferred. Never opens gradle.properties, local.properties, keystores,
# google-services.json, .env* or key files (listed by path only); drops script statements that
# look like secrets and everything inside signingConfigs and credentials blocks.
# Skips build, .gradle, .cxx, buildSrc, node_modules, vendor, Pods, worktrees and hidden dirs.
# ROOT boundary: ROOT is resolved to its physical path. A project path with an empty, "." or ".." segment
# is not resolved (error). No file, project dir, src dir, source set, gradle/ dir or fixed path is read or
# checked through a symlink: a symlink that stays inside ROOT is reported in unknown, one that leads
# outside ROOT is reported in errors (complete becomes false).
#
# Usage:
#   adapter.sh [ROOT] [--pretty] [--max-depth N] [--max-builds N] [--max-modules N]
#              [--max-deps N] [--max-manifests N] [--max-permissions N] [--max-catalog-entries N]
#              [--max-markers N] [--max-module-depth N]
# Exit: 0 JSON printed (errors are reported inside), 2 jq or a helper file missing, ROOT missing or bad option.
# Requires: bash 3.2+, jq, find, awk, sort; gradle-facts.awk, toml-facts.awk, manifest-facts.awk
# and build-facts.jq next to this script. Temp files go to $TMPDIR.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="."
pretty=0
MAX_DEPTH=3
MAX_BUILDS=8
MAX_MODULES=60
MAX_DEPS=80
MAX_MANIFESTS=4
MAX_PERMISSIONS=40
MAX_CATALOG=200
MAX_CATALOGS=4
MAX_MARKERS=20
MAX_MODULE_DEPTH=4
MAX_FILE_KB=512
MAX_SAMPLES=3
MAX_EXCLUDED=20

usage_error() { printf '{"error":"%s"}\n' "$(printf '%s' "$1" | tr -d '"\\' | tr '\t\n' '  ')"; exit 2; }
num() { case "${1:-}" in ''|*[!0-9]*) usage_error "$2 needs a non-negative number" ;; esac; }

while [ $# -gt 0 ]; do
  case "$1" in
    --pretty) pretty=1 ;;
    --max-depth) num "${2:-}" "$1"; MAX_DEPTH="$2"; shift ;;
    --max-builds) num "${2:-}" "$1"; MAX_BUILDS="$2"; shift ;;
    --max-modules) num "${2:-}" "$1"; MAX_MODULES="$2"; shift ;;
    --max-deps) num "${2:-}" "$1"; MAX_DEPS="$2"; shift ;;
    --max-manifests) num "${2:-}" "$1"; MAX_MANIFESTS="$2"; shift ;;
    --max-permissions) num "${2:-}" "$1"; MAX_PERMISSIONS="$2"; shift ;;
    --max-catalog-entries) num "${2:-}" "$1"; MAX_CATALOG="$2"; shift ;;
    --max-markers) num "${2:-}" "$1"; MAX_MARKERS="$2"; shift ;;
    --max-module-depth) num "${2:-}" "$1"; MAX_MODULE_DEPTH="$2"; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    -*) usage_error "unknown option $1" ;;
    *) root="$1" ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || usage_error "jq not found"
for f in gradle-facts.awk toml-facts.awk manifest-facts.awk build-facts.jq; do
  [ -f "$here/$f" ] || usage_error "$f not found next to adapter.sh"
done
# ROOT is the physical path: find does not enter a symlinked start dir, and the boundary checks compare physical paths
secret_names="$(cd "$here/../.." && pwd)/secret_names.sh"
[ -f "$secret_names" ] || usage_error "secret_names.sh not found in av-setup/scripts"
# shellcheck source=../../secret_names.sh
. "$secret_names"
root="$(cd "$root" 2>/dev/null && pwd -P)" || usage_error "directory not found"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/av-android.XXXXXX")" || usage_error "cannot create a temporary directory"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/trunc"
: >"$tmp/builds"

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
t0=$SECONDS
TAB="$(printf '\t')"

# trunc FIELD SHOWN TOTAL - records a list cut to a limit
trunc() { [ "${3:-0}" -gt "${2:-0}" ] && printf '%s\t%s\t%s\tlimit\n' "$1" "$2" "$3" >>"$tmp/trunc"; return 0; }
# rel PATH - path relative to ROOT, "." for ROOT itself
rel() { if [ "$1" = "$root" ]; then echo .; else printf '%s\n' "${1#"$root"/}"; fi; }
lines_to_json() { jq -R -s -c 'split("\n") | map(select(length > 0))'; }

# secret_path PATH - code 0 for a file that is never opened: a secret by name (secret_names.sh),
# plus Gradle and local properties, which often hold signing passwords
secret_path() {
  av_secret_name "$1" "$root" && return 0
  case "${1##*/}" in
    gradle.properties|local.properties) return 0 ;;
  esac
  return 1
}

EXCL=( -name build -o -name .gradle -o -name .cxx -o -name .externalNativeBuild -o -name buildSrc -o -name node_modules
  -o -name vendor -o -name Pods -o -name worktrees -o -name DerivedData -o -name dist -o -name '.*' )

# MARK: ROOT boundary

# boundary PATH - where PATH sits physically. PATH is built from ROOT without "." or ".." segments. Prints:
#   ok            every directory on the way is real and PATH itself is not a symlink (PATH may not exist)
#   symlink       PATH is a symlink whose target stays inside ROOT (or cannot be resolved); not followed
#   symlink_path  a directory on the way is a symlink that stays inside ROOT; not followed
#   outside_root  PATH or a directory on the way is a symlink that leads outside ROOT; never read
#   missing       a directory on the way does not exist
boundary() {
  local p="$1" dir phys want t tdir
  [ "$p" = "$root" ] && { echo ok; return 0; }
  dir="$(dirname "$p")"
  phys="$(cd "$dir" 2>/dev/null && pwd -P)" || { echo missing; return 0; }
  if [ "$dir" = "$root" ]; then want="$root"; else want="$root/${dir#"$root"/}"; fi
  if [ "$phys" != "$want" ]; then
    case "$phys/" in "$root"/*) echo symlink_path ;; *) echo outside_root ;; esac
    return 0
  fi
  if [ -L "$p" ]; then
    t="$(readlink "$p")"
    case "$t" in /*) tdir="$(dirname "$t")" ;; *) tdir="$dir/$(dirname "$t")" ;; esac
    phys="$(cd "$tdir" 2>/dev/null && pwd -P)" || { echo symlink; return 0; }
    case "$phys/" in "$root"/*) echo symlink ;; *) echo outside_root ;; esac
    return 0
  fi
  echo ok
}

# segments_ok PROJECT - code 0 when every segment of a Gradle project path is non-empty and not "." or ".."
segments_ok() {
  case ":${1#:}:" in *::*|*:.:*|*:..:*) return 1 ;; esac
  return 0
}

# MARK: files

# check ROLE MOD PATH - F record for a file to be read; code 0 when it may be read
check() {
  local role="$1" mod="$2" f="$3" r st
  r="$(rel "$f")"
  st="$(boundary "$f")"
  if [ "$st" = ok ]; then
    if [ ! -r "$f" ]; then st=unreadable
    elif [ -n "$(find "$f" -size +"${MAX_FILE_KB}"k 2>/dev/null)" ]; then st=too_large
    fi
  fi
  printf 'F\t%s\t%s\t%s\t%s\n' "$mod" "$r" "$role" "$st"
  [ "$st" = ok ]
}

# awk gets paths through the environment: -v would turn backslashes into escapes
gradle_facts() { AV_MOD="$1" AV_PATH="$(rel "$2")" awk -v maxmarkers="$MAX_MARKERS" -f "$here/gradle-facts.awk" "$2" 2>/dev/null ||
  printf 'G\t%s\t%s\tstatus\tmalformed\tawk failed\n' "$1" "$(rel "$2")"; }

# script_of DIR BASE MOD ROLE - reads BASE.gradle or BASE.gradle.kts in DIR; both present = ambiguous, none read
script_of() {
  local d="$1" g="$1/$2.gradle" k="$1/$2.gradle.kts"
  if [ -e "$g" ] && [ -e "$k" ]; then
    printf 'F\t%s\t%s\t%s\tambiguous\n' "$3" "$(rel "$g")" "$4"
    printf 'F\t%s\t%s\t%s\tambiguous\n' "$3" "$(rel "$k")" "$4"
  elif [ -e "$k" ]; then check "$4" "$3" "$k" && gradle_facts "$3" "$k"
  elif [ -e "$g" ]; then check "$4" "$3" "$g" && gradle_facts "$3" "$g"
  fi
  return 0
}

# MARK: module

# module MOD DIR BUILD_DIR - facts of one Gradle project: build script, manifests, source sets
module() {
  local mod="$1" d="$2" m n st
  st="$(boundary "$d")"
  case "$st" in
    ok) ;;
    missing) printf 'D\t%s\t%s\tmissing\n' "$mod" "$(rel "$d")"; return 0 ;;
    *) printf 'D\t%s\t%s\t%s\n' "$mod" "$(rel "$d")" "$st"; return 0 ;;
  esac
  if [ ! -d "$d" ]; then printf 'D\t%s\t%s\tmissing\n' "$mod" "$(rel "$d")"; return 0; fi
  printf 'D\t%s\t%s\tdir\n' "$mod" "$(rel "$d")"
  script_of "$d" build "$mod" build
  [ "$mod" = ":" ] && return 0
  st="$(boundary "$d/src")"
  if [ "$st" != ok ]; then printf 'F\t%s\t%s\tsource_dir\t%s\n' "$mod" "$(rel "$d/src")" "$st"; return 0; fi
  [ -d "$d/src" ] || return 0
  find "$d/src" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | LC_ALL=C sort | while IFS= read -r m; do
    printf 'F\t%s\t%s\tsource_set\t%s\n' "$mod" "$(rel "$m")" "$(boundary "$m")"
  done
  find "$d/src" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | LC_ALL=C sort | while IFS= read -r m; do
    for n in java kotlin res assets; do [ -d "$m/$n" ] && printf 'S\t%s\t%s\t%s\n' "$mod" "$(rel "$m")" "$n"; done
    printf 'S\t%s\t%s\t\n' "$mod" "$(rel "$m")"
  done
  find "$d/src" -mindepth 2 -maxdepth 2 -name AndroidManifest.xml 2>/dev/null | LC_ALL=C sort >"$tmp/manifests"
  trunc "builds[$bdir].modules[$mod].manifests" "$MAX_MANIFESTS" "$(wc -l <"$tmp/manifests" | tr -d ' ')"
  head -n "$MAX_MANIFESTS" "$tmp/manifests" | while IFS= read -r m; do
    check manifest "$mod" "$m" </dev/null || continue
    AV_MOD="$mod" AV_PATH="$(rel "$m")" awk -v maxperm="$MAX_PERMISSIONS" -f "$here/manifest-facts.awk" "$m" 2>/dev/null ||
      printf 'M\t%s\t%s\tstatus\tmalformed\tawk failed\n' "$mod" "$(rel "$m")"
  done
}

# MARK: build

# fixed list of paths checked by name only; role<TAB>path
CANDIDATES="wrapper	gradlew
wrapper	gradlew.bat
wrapper	gradle/wrapper/gradle-wrapper.properties
wrapper	gradle/wrapper/gradle-wrapper.jar
catalog	gradle/libs.versions.toml
build_logic	buildSrc
build_logic	build-logic
properties	gradle.properties
properties	local.properties
quality	lint.xml
quality	detekt.yml
quality	config/detekt/detekt.yml
quality	.editorconfig"

build() {
  local d="$1" bdir other f p mod mdir total role skip sok st
  bdir="$(rel "$d")"
  {
    script_of "$d" settings "" settings
    printf '%s\n' "$CANDIDATES" | while IFS="$TAB" read -r role p; do
      st="$(boundary "$d/$p")"
      if [ "$st" = missing ]; then st=absent
      elif [ "$st" = ok ]; then
        if [ -d "$d/$p" ]; then st=dir; elif [ -f "$d/$p" ]; then st=file; else st=absent; fi
      fi
      printf 'P\t%s\t%s\t%s\n' "$role" "$(rel "$d/$p")" "$st"
    done
    f="$d/gradle/wrapper/gradle-wrapper.properties"
    if [ -f "$f" ] && check wrapper "" "$f"; then
      AV_PATH="$(rel "$f")" awk -F= 'BEGIN { path = ENVIRON["AV_PATH"] } $1 ~ /^[ \t]*distributionUrl[ \t]*$/ {
          v = ""; t = ""; u = $0; sub(/^[^=]*=/, "", u)
          if (match(u, /gradle-[0-9][0-9A-Za-z.+-]*-(bin|all)\.zip/)) {
            v = substr(u, RSTART + 7, RLENGTH - 11); t = substr(v, length(v) - 2); v = substr(v, 1, length(v) - 4) }
          printf "W\t\t%s\t%s\t%s\t%d\n", path, v, t, NR; exit }' "$f"
    fi
    : >"$tmp/catalogs"
    [ "$(boundary "$d/gradle/x")" = ok ] &&
      find "$d/gradle" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -name '*.versions.toml' 2>/dev/null | LC_ALL=C sort >"$tmp/catalogs"
    trunc "builds[$bdir].catalogs" "$MAX_CATALOGS" "$(wc -l <"$tmp/catalogs" | tr -d ' ')"
    head -n "$MAX_CATALOGS" "$tmp/catalogs" | while IFS= read -r f; do
      check catalog "" "$f" </dev/null || continue
      AV_PATH="$(rel "$f")" awk -f "$here/toml-facts.awk" "$f" 2>/dev/null || printf 'T\t\t%s\tbad\t0\tawk failed\n' "$(rel "$f")"
    done
  } >"$tmp/b.tsv"

  # projects: ":" plus include records of the settings file when it parsed cleanly, sorted and unique
  sok="$(awk -F'\t' '$1 == "G" && $2 == "" && $4 == "status" && $5 == "ok" { print "yes"; exit }' "$tmp/b.tsv")"
  { echo ":"; [ "$sok" = yes ] && awk -F'\t' '$1 == "G" && $2 == "" && $4 == "include" { print $5 }' "$tmp/b.tsv"; } | LC_ALL=C sort -u >"$tmp/projects"
  { [ "$sok" = yes ] && awk -F'\t' '$1 == "G" && $2 == "" && $4 == "dir_override" { print $5 }' "$tmp/b.tsv"; } | LC_ALL=C sort -u >"$tmp/overrides"
  total="$(wc -l <"$tmp/projects" | tr -d ' ')"
  trunc "builds[$bdir].modules" "$MAX_MODULES" "$total"
  head -n "$MAX_MODULES" "$tmp/projects" | while IFS= read -r mod; do
    if [ "$mod" != ":" ] && ! segments_ok "$mod"; then printf 'D\t%s\t\tinvalid_path\n' "$mod"; continue; fi
    if grep -qxF -- "$mod" "$tmp/overrides"; then printf 'D\t%s\t\toverride\n' "$mod"; continue; fi
    if [ "$mod" = ":" ]; then mdir="$d"; else p="${mod#:}"; mdir="$d/$(printf '%s' "$p" | tr ':' '/')"; fi
    module "$mod" "$mdir" </dev/null
  done >>"$tmp/b.tsv"

  # build scripts inside the build dir that no included project points at; nested builds are left out
  : >"$tmp/nested"
  while IFS="$TAB" read -r other _; do
    case "$other" in "$bdir") ;; *) if [ "$bdir" = . ]; then echo "$other"; else case "$other" in "$bdir"/*) echo "$other" ;; esac; fi ;; esac
  done <"$tmp/settings_dirs" >"$tmp/nested"
  awk -F'\t' '$1 == "D" { print $3 }' "$tmp/b.tsv" | LC_ALL=C sort -u >"$tmp/moddirs"
  find "$d" -mindepth 1 -maxdepth "$((MAX_MODULE_DEPTH + 1))" -type d \( "${EXCL[@]}" \) -prune -o -type f \( -name build.gradle -o -name build.gradle.kts \) -print 2>/dev/null |
    while IFS= read -r f; do
      p="$(rel "$(dirname "$f")")"
      grep -qxF -- "$p" "$tmp/moddirs" && continue
      skip=0; while IFS= read -r other; do case "$p/" in "$other"/*) skip=1 ;; esac; done <"$tmp/nested"
      [ "$skip" = 1 ] || rel "$f"
    done | LC_ALL=C sort >"$tmp/unlisted"
  trunc "builds[$bdir].unlisted_build_files" "$MAX_EXCLUDED" "$(wc -l <"$tmp/unlisted" | tr -d ' ')"
  head -n "$MAX_EXCLUDED" "$tmp/unlisted" | while IFS= read -r f; do printf 'L\t\t%s\n' "$f"; done >>"$tmp/b.tsv"

  # files that are never opened, listed by path
  find "$d" -mindepth 1 -maxdepth "$((MAX_MODULE_DEPTH + 1))" -type d \( "${EXCL[@]}" \) -prune -o \( -type f -o -type l \) -print 2>/dev/null |
    while IFS= read -r f; do secret_path "$f" && rel "$f"; done | LC_ALL=C sort >"$tmp/unread"
  trunc "builds[$bdir].unread_files" "$MAX_EXCLUDED" "$(wc -l <"$tmp/unread" | tr -d ' ')"
  head -n "$MAX_EXCLUDED" "$tmp/unread" | while IFS= read -r f; do printf 'U\t\t%s\n' "$f"; done >>"$tmp/b.tsv"

  jq -R -s -c --arg dir "$bdir" -f "$here/build-facts.jq" \
    --argjson max_deps "$MAX_DEPS" --argjson max_catalog "$MAX_CATALOG" --argjson max_samples "$MAX_SAMPLES" \
    --argjson max_markers "$MAX_MARKERS" --argjson unread_total "$(wc -l <"$tmp/unread" | tr -d ' ')" \
    "$tmp/b.tsv" 2>"$tmp/jqerr" ||
    jq -n -c --arg dir "$bdir" --arg e "$(head -c 200 "$tmp/jqerr" | tr '\t\n' '  ')" \
      '{build: {dir: $dir, status: "error"}, truncated: [], errors: [{path: $dir, error: ("build facts failed: " + $e)}]}'
}

# MARK: discovery

find "$root" -mindepth 1 -maxdepth "$((MAX_DEPTH + 1))" -type d \( "${EXCL[@]}" \) -prune -o -type f \( -name settings.gradle -o -name settings.gradle.kts \) -print 2>/dev/null |
  while IFS= read -r f; do d="$(dirname "$f")"; printf '%s\t%s\n' "$(rel "$d")" "$d"; done |
  LC_ALL=C sort -u -t "$TAB" -k1,1 |
  awk -F'\t' '$1 == "." { print; next } { rest[++n] = $0 } END { for (i = 1; i <= n; i++) print rest[i] }' >"$tmp/settings_dirs"
no_settings=false
if [ ! -s "$tmp/settings_dirs" ] && { [ -f "$root/build.gradle" ] || [ -f "$root/build.gradle.kts" ]; }; then
  printf '.\t%s\n' "$root" >"$tmp/settings_dirs"; no_settings=true
fi
find "$root" -mindepth 1 -maxdepth "$MAX_DEPTH" -type d \( "${EXCL[@]}" \) -print -prune 2>/dev/null |
  while IFS= read -r f; do rel "$f"; done | awk '{ n = gsub("/", "/"); print n "\t" $0 }' |
  LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 | cut -f2- >"$tmp/excluded"
builds_total="$(wc -l <"$tmp/settings_dirs" | tr -d ' ')"
trunc builds "$MAX_BUILDS" "$builds_total"
trunc excluded_dirs "$MAX_EXCLUDED" "$(wc -l <"$tmp/excluded" | tr -d ' ')"
head -n "$MAX_BUILDS" "$tmp/settings_dirs" | while IFS="$TAB" read -r _ d; do build "$d" </dev/null; done >>"$tmp/builds"

# MARK: assembly

result="$(jq -n -c --arg root "$root" --arg name "$(basename "$root")" --arg started "$started" \
  --argjson dur "$((SECONDS - t0))" --argjson b "$(jq -s -c . "$tmp/builds")" --argjson total "$builds_total" \
  --argjson no_settings "$no_settings" --argjson excl "$(head -n "$MAX_EXCLUDED" "$tmp/excluded" | lines_to_json)" \
  --argjson limits "$(jq -n -c --argjson a "$MAX_DEPTH" --argjson b "$MAX_BUILDS" --argjson c "$MAX_MODULES" --argjson d "$MAX_DEPS" \
      --argjson e "$MAX_MANIFESTS" --argjson f "$MAX_PERMISSIONS" --argjson g "$MAX_CATALOG" --argjson h "$MAX_CATALOGS" \
      --argjson i "$MAX_MARKERS" --argjson j "$MAX_MODULE_DEPTH" --argjson k "$MAX_FILE_KB" --argjson l "$MAX_SAMPLES" --argjson m "$MAX_EXCLUDED" \
      '{max_depth: $a, max_builds: $b, max_modules: $c, max_deps: $d, max_manifests: $e, max_permissions: $f, max_catalog_entries: $g,
        max_catalogs: $h, max_markers: $i, max_module_depth: $j, max_file_kb: $k, max_samples: $l, max_excluded: $m}')" \
  --argjson cut "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")
      | {field: .[0], shown: (.[1] | tonumber), total: (if .[2] == "" then null else (.[2] | tonumber) end), reason: .[3]})' "$tmp/trunc")" '
  ($b | map(.build)) as $builds
  | ($cut + [$b[] | .truncated[]]) as $truncated
  | ([$b[] | .errors[]]) as $errors
  | {adapter: "android", schema_version: 1, root: $root, name: $name, started: $started, duration_sec: $dur,
     complete: (($truncated | length) == 0 and ($errors | length) == 0),
     limits: $limits, truncated: $truncated, errors: $errors,
     excluded_dirs: $excl,
     summary: {gradle_builds: $total, builds_reported: ($builds | length),
               modules_declared: ([$builds[] | .modules_declared // 0] | add // 0),
               modules_reported: ([$builds[] | (.modules // []) | length] | add // 0),
               android_modules: ([$builds[] | (.modules // [])[] | .android_type] | group_by(.) | map({(.[0]): length}) | add // {}),
               manifests: ([$builds[] | (.modules // [])[] | (.manifests // []) | length] | add // 0)},
     unknown: ((if $total == 0 then [{field: "gradle", reason: "no settings.gradle(.kts) within max_depth outside excluded dirs and no root build.gradle(.kts); Android presence is not decided here"}] else [] end)
               + (if $no_settings then [{field: "settings", reason: "no settings file; the root build script is reported as a single project"}] else [] end)
               + [{field: "deeper_builds", reason: ("settings files deeper than " + ($limits.max_depth | tostring) + " directory levels are not searched")},
                  {field: "installed_versions", reason: "Gradle, AGP, Kotlin, JDK and Android SDK installations are not checked and the wrapper is not run; only declared text is reported"},
                  {field: "evaluated_configuration", reason: "scripts are not evaluated: plugins applied by convention plugins, script plugins, subprojects/allprojects blocks, conditions and loops are not resolved"}]),
     notes: ["facts only: no architecture, layers or module relations are inferred from names or project dependencies",
             "text_candidate values come from matching ext or version catalog text, not from Gradle evaluation",
             "gradle.properties, local.properties, keystores, google-services.json, .env* and key files are listed by path and never opened"],
     builds: ($builds | sort_by([(.dir != "."), .dir]))}')"

if [ "$pretty" -eq 1 ]; then jq . <<<"$result"; else printf '%s\n' "$result"; fi

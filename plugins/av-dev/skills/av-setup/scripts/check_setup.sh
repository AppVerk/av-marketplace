#!/usr/bin/env bash
# check_setup.sh - validator of the av-dev setup in a repo (config, overlays, roles, role skills).
#
# Output: lines SETUP_<CODE> <details>, then CHECKED n ERRORS e WARNINGS w at the end.
#   SETUP_CONFIG_MISSING      no config (ERROR)
#   SETUP_CONFIG_INVALID      config is not valid JSON (ERROR)
#   SETUP_CONFIG_IGNORED      team config is untracked and ignored by git (ERROR): a team
#                             config must be committed; only <config>.local may be ignored
#   SETUP_CONFIG_FIELD        invalid field outside the gates (ERROR): agents.models (a Claude
#                             model; no Haiku in review or planReview; no object form), removed
#                             agents keys (crossVendor, timeoutSec), git.commit, git.push, roles,
#                             generatedPaths, unownedPaths. gate.sh checks only validation,
#                             paths and requires, so these fields never stop a gate.
#   SETUP_OVERLAY_MISSING     no overlay for one of the 5 skills (WARNING)
#   SETUP_OVERLAY_SECTION     overlay without a required section (WARNING)
#                             English name or Polish alias (references/localization.md)
#   SETUP_ROLES_NONE          config without "roles"; every file belongs to implementer (WARNING)
#   SETUP_ROLE_INVALID        role without name, skill or globs, or with exclusions only (ERROR)
#   SETUP_ROLE_SKILL_MISSING  no .claude/skills/<skill>/SKILL.md (ERROR)
#   SETUP_ROLE_OVERLAP        tracked file matches the globs of 2 roles (ERROR)
#   SETUP_ROLE_EMPTY          role glob matches no tracked file (WARNING)
#   SETUP_UNOWNED_DIR         top-level directory with source files and no owner (WARNING)
#                             source file, the same rule for every language: a regular
#                             file tracked by git, text for git (not i/-text in
#                             git ls-files --eol), not empty and at most 256 KiB (larger
#                             text files are data or lockfiles), not markdown
#                             (.md, .markdown, .mdx), not under docs.root or a top-level
#                             dot directory (.ai/, .claude/, .github/), not matched by
#                             generatedPaths or unownedPaths
#   SETUP_REF_MISSING         backtick path in an overlay or skill does not exist (ERROR)
#   SETUP_REF_SKIPPED         no av-docs-sync/scripts/check_refs.sh (WARNING)
#   SETUP_GATE_UNKNOWN        --gate X or --only X not in validation (ERROR)
#   SETUP_GLOB_COPY           role skill or overlay copies 3+ role globs (WARNING)
#   SETUP_LOCAL_TRACKED       <config>.local is tracked by git (ERROR)
#   SETUP_LOCAL_IGNORE        .gitignore does not ignore <config>.local (WARNING)
#   SETUP_LOCAL_USED          info: the check runs on the config with a local override
#
# Config: effective (team config with the <config>.local override, script
# av-verify/scripts/config.sh). --no-local checks the team config only.
#
# Owner mode: for each file a line OWNER <file> <owner>, where
# owner (last field) is a role name, generated, unowned or implementer; a config
# without rules prints implementer for every file (never an empty output).
# Order: generatedPaths, then roles (first by order and by position
# in the config), then unownedPaths, otherwise implementer.
# Globs as in git pathspec :(glob): *, ?, **; a path without a star also matches
# the directory contents. Files do not have to exist.
# A glob starting with ! excludes matching files from its own list (one role,
# generatedPaths or unownedPaths), e.g. ["config/**", "!config/app.yaml"];
# an excluded file falls through to the next rule. An exclusion never
# counts as an empty glob; a role with exclusions only is invalid.
#
# Usage:
#   check_setup.sh [--root DIR] [--config FILE] [--no-local]
#   check_setup.sh [--root DIR] [--config FILE] [--no-local] --config-only
#   check_setup.sh [--root DIR] [--config FILE] [--no-local] --owner <file>...
# --config-only: only the config checks (missing, invalid JSON, local override, fields); fast,
#   for av-implement and av-plan before a run. --owner does not check the fields.
# Exit code: 0 no ERROR, 1 ERROR found (in --owner: config error), 2 usage error.
# Requires: bash 3.2+, git, jq, awk.

set -uo pipefail

root="."
config=""
owner_mode=0
config_only=0
no_local=0
owner_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --config) config="${2:-}"; shift ;;
    --owner) owner_mode=1 ;;
    --config-only) config_only=1 ;;
    --no-local) no_local=1 ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    -*) echo "USAGE unknown option: $1"; exit 2 ;;
    *) if [ "$owner_mode" -eq 1 ]; then owner_files+=("$1"); else echo "USAGE unknown argument: $1"; exit 2; fi ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || { echo "USAGE jq not found; install jq (brew install jq)"; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE root directory not found"; exit 2; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "USAGE root is not a git repository"; exit 2; }
[ -n "$config" ] || config="$root/.ai/av.config.json"
case "$config" in /*) ;; *) [ -f "$config" ] || config="$root/$config" ;; esac
if [ "$owner_mode" -eq 1 ] && [ "${#owner_files[@]}" -eq 0 ]; then echo "USAGE --owner requires a list of files"; exit 2; fi

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

checked=0; errors=0; warnings=0
err()  { errors=$((errors + 1)); printf 'SETUP_%s\n' "$*"; }
warn() { warnings=$((warnings + 1)); printf 'SETUP_%s\n' "$*"; }
finish() {
  printf 'CHECKED %d ERRORS %d WARNINGS %d\n' "$checked" "$errors" "$warnings"
  [ "$errors" -eq 0 ] && exit 0 || exit 1
}

# MARK: config

checked=$((checked + 1))
if [ ! -f "$config" ]; then
  [ "$owner_mode" -eq 1 ] && { for f in "${owner_files[@]}"; do printf 'OWNER %s implementer\n' "$f"; done; exit 0; }
  err "CONFIG_MISSING ${config#$root/}"; finish
fi
if ! jq empty "$config" >/dev/null 2>&1; then
  [ "$owner_mode" -eq 1 ] && { echo "SETUP_CONFIG_INVALID ${config#$root/}"; exit 1; }
  err "CONFIG_INVALID ${config#$root/}"; finish
fi

# MARK: local override

team_config="$config"
local_rel="${team_config#$root/}.local"
case "$team_config" in
  "$root"/*)
    if [ "$owner_mode" -eq 0 ] && ! git -C "$root" ls-files --error-unmatch -- "${team_config#$root/}" >/dev/null 2>&1 \
       && git -C "$root" check-ignore -q -- "${team_config#$root/}" 2>/dev/null; then
      err "CONFIG_IGNORED ${team_config#$root/} is ignored by git; a team config must be committed (git add -f, then fix .gitignore)"
    fi
    if git -C "$root" ls-files --error-unmatch -- "$local_rel" >/dev/null 2>&1; then
      [ "$owner_mode" -eq 1 ] || err "LOCAL_TRACKED $local_rel is tracked by git; git rm --cached $local_rel"
    elif ! git -C "$root" check-ignore -q --no-index -- "$local_rel" 2>/dev/null; then
      [ "$owner_mode" -eq 1 ] || warn "LOCAL_IGNORE add $local_rel to .gitignore"
    fi
    ;;
esac
config_sh="$skill_dir/../av-verify/scripts/config.sh"
if [ "$no_local" -eq 0 ] && [ -f "$team_config.local" ] && [ -f "$config_sh" ]; then
  if bash "$config_sh" --root "$root" --config "$team_config" --out "$tmp/config.json" >/dev/null 2>&1; then
    config="$tmp/config.json"
    [ "$owner_mode" -eq 1 ] || printf 'SETUP_LOCAL_USED %s\n' "$local_rel"
  else
    [ "$owner_mode" -eq 1 ] && { echo "SETUP_CONFIG_INVALID $local_rel"; exit 1; }
    err "CONFIG_INVALID $local_rel"; finish
  fi
fi

# MARK: config fields (outside validation; gate.sh checks validation, paths and requires)

field_errors() {
  jq -r '
    def isstr: type == "string";
    def strarr: type == "array" and all(.[]; type == "string");
    def claudemodel: isstr and (IN("inherit", "opus", "sonnet", "haiku", "fable") or test("^claude-[a-z0-9.-]+$"));
    def haiku: test("^(claude-)?haiku(-|$)");
    ["inherit", "opus", "sonnet", "haiku", "fable"] as $models
    | ["on-request", "after-green-gate", "free"] as $commits
    | ["never", "on-request"] as $pushes
    | ( if has("agents") and (.agents | type) != "object" then "agents agents: expected an object"
        elif (.agents | type) == "object" then
          ( if (.agents | has("models")) and (.agents.models | type) != "object" then "agents agents.models: expected an object"
            elif (.agents | has("models")) then
              ( .agents.models | to_entries[] | .key as $k | .value as $v | "agents.models.\($k)" as $p
                | if ($v | type) == "object" then "agents \($p): the object form {provider, model, effort} was removed with Codex slots; use a Claude model string, e.g. \"opus\""
                  elif ($v | claudemodel | not) then "agents \($p): invalid value \($v | tojson); allowed: \($models | join(", ")) or claude-<id>"
                  elif IN($k; "review", "planReview") and ($v | haiku) then "agents \($p): a Haiku model cannot do review; use opus, sonnet, fable or inherit"
                  else empty end )
            else empty end ),
          ( .agents | keys[] | select(IN("crossVendor", "timeoutSec"))
            | "agents agents.\(.): removed with Codex slots; delete this key" )
        else empty end ),
      ( if has("git") and (.git | type) != "object" then "git git: expected an object"
        elif (.git | type) == "object" then
          ( if (.git | has("commit")) and (.git.commit as $v | $commits | index([$v]) == null)
            then "git git.commit: invalid value \(.git.commit | tojson); allowed: \($commits | join(", "))"
            else empty end ),
          ( if (.git | has("push")) and (.git.push as $v | $pushes | index([$v]) == null)
            then "git git.push: invalid value \(.git.push | tojson); allowed: \($pushes | join(", "))"
            else empty end )
        else empty end ),
      ( if has("roles") | not then empty
        elif (.roles | type) != "array" then "roles roles: expected an array of objects"
        else
          .roles | to_entries[] | .value as $r
          | "roles[\(.key)]" as $p
          | if ($r | type) != "object" then "roles \($p): expected an object"
            else
              ( if ($r.name | isstr | not) or $r.name == "" then "roles \($p).name: expected a non-empty string" else empty end ),
              ( if ($r.skill | isstr | not) or $r.skill == "" then "roles \($p).skill: expected a non-empty string" else empty end ),
              ( if ($r.order | type) != "number" or ($r.order | floor) != $r.order then "roles \($p).order: expected an integer" else empty end ),
              ( if ($r.globs | type) != "array" or ($r.globs | length) == 0 then "roles \($p).globs: expected a non-empty array of strings"
                else
                  ( $r.globs[]
                  | if isstr | not then "roles \($p).globs: element \(tojson) is not a string"
                    elif test("[{}]") then "roles \($p).globs: glob \(tojson) has a curly brace; list each variant separately"
                    elif . == "!" then "roles \($p).globs: exclusion \"!\" has no pattern"
                    else empty end ),
                  ( if all($r.globs[]; isstr and startswith("!")) then "roles \($p).globs: only exclusions (!); add at least one glob without !" else empty end )
                end )
            end
        end ),
      ( ("generatedPaths", "unownedPaths") as $k
        | select(has($k) and (.[$k] | strarr | not))
        | "roles \($k): expected an array of strings" )
  ' "$config"
}

if [ "$owner_mode" -eq 0 ]; then
  checked=$((checked + 1))
  while IFS= read -r line; do
    [ -n "$line" ] && err "CONFIG_FIELD ${line#* }"
  done < <(field_errors)
  [ "$config_only" -eq 1 ] && finish
fi

# rules: kind TAB name TAB glob; roles sorted by order, then by position in the config
jq -r '
  ([.generatedPaths // [] | .[] | ["generated", "-", .]]
   + ([.roles // [] | to_entries[] | select(.value | type == "object")
       | {i: .key, o: (.value.order // 999), r: .value}] | sort_by(.o, .i)
       | map(.r as $r | ($r.globs // [])[] | ["role", ($r.name // "?"), .]))
   + [.unownedPaths // [] | .[] | ["unowned", "-", .]])[] | @tsv' "$config" >"$tmp/rules" 2>/dev/null

# matcher: rules + list of paths -> F path roles gen unowned; at the end G role glob hits
# (include globs only). A glob with ! excludes the path from its own list (kind + name).
# The rules are read in BEGIN, not as a first input file: with an empty rules file awk's
# "FNR == NR" holds for every path, so a config without rules printed nothing.
match_paths() {
  awk -F'\t' -v rules="$tmp/rules" '
    function g2re(g,   r, i, n, c) {
      if (g ~ /\/$/) g = g "**"
      r = "^"; n = length(g); i = 1
      while (i <= n) {
        c = substr(g, i, 1)
        if (c == "*") {
          if (substr(g, i + 1, 1) == "*") {
            if (substr(g, i + 2, 1) == "/") { r = r "(.*/)?"; i += 3; continue }
            r = r ".*"; i += 2; continue
          }
          r = r "[^/]*"
        } else if (c == "?") r = r "[^/]"
        else if (c == "^") r = r "\\^"
        else if (index(".+()|${}[]", c)) r = r "[" c "]"
        else r = r c
        i++
      }
      if (g !~ /[*?]/) r = r "(/.*)?"
      return r "$"
    }
    BEGIN {
      while ((getline l < rules) > 0) {
        split(l, a, "\t")
        n++; kind[n] = a[1]; name[n] = a[2]; glob[n] = a[3]; key[n] = a[1] SUBSEP a[2]; hits[n] = 0
        neg[n] = (substr(a[3], 1, 1) == "!"); re[n] = g2re(neg[n] ? substr(a[3], 2) : a[3])
      }
      close(rules)
    }
    {
      p = $0; sub(/^\.\//, "", p); roles = ""; gen = 0; un = 0; split("", excl)
      for (i = 1; i <= n; i++) if (neg[i] && p ~ re[i]) excl[key[i]] = 1
      for (i = 1; i <= n; i++) {
        if (neg[i] || p !~ re[i] || (key[i] in excl)) continue
        hits[i]++
        if (kind[i] == "generated") gen = 1
        else if (kind[i] == "unowned") un = 1
        else if (index("," roles ",", "," name[i] ",") == 0) roles = roles (roles == "" ? "" : ",") name[i]
      }
      printf "F\t%s\t%s\t%d\t%d\n", p, roles, gen, un
    }
    END { for (i = 1; i <= n; i++) if (kind[i] == "role" && !neg[i]) printf "G\t%s\t%s\t%d\n", name[i], glob[i], hits[i] }
  ' -
}

# MARK: owner mode

if [ "$owner_mode" -eq 1 ]; then
  for f in "${owner_files[@]}"; do
    case "$f" in "$root"/*) f="${f#$root/}" ;; esac
    printf '%s\n' "$f"
  done | match_paths | awk -F'\t' '$1 == "F" {
    if ($4 == 1) o = "generated"
    else if ($3 != "") { o = $3; if (index(o, ",")) { print "WARNING role overlap for " $2 ": " o > "/dev/stderr"; sub(/,.*/, "", o) } }
    else if ($5 == 1) o = "unowned"
    else o = "implementer"
    print "OWNER " $2 " " o
  }'
  exit 0
fi

rel() { printf '%s\n' "${1#$root/}"; }

overlays_dir="$(jq -r '.paths.overlays // ".ai/overlays"' "$config")"

# MARK: overlays

# Each line: canonical English name, TAB, Polish alias (references/localization.md,
# table "Overlay sections"). A header matches either name; a suffix after it is allowed.
# Adding a language: add a column here.
required_sections() {
  case "$1" in
    av-plan) printf '%s\t%s\n' \
      "Files to read before planning" "Pliki do przeczytania przed planem" \
      "Required plan sections" "Obowiązkowe sekcje planu" ;;
    av-implement) printf '%s\t%s\n' \
      "Roles" "Role" \
      "Required steps" "Obowiązkowe kroki" \
      "Mode selection" "Wybór trybu" \
      "Gates per stage" "Bramki per etap" ;;
    av-review) printf '%s\t%s\n' \
      "How to check the axes" "Jak sprawdzać osie" ;;
    av-verify) printf '%s\t%s\n' \
      "Gate selection" "Dobór bramki" \
      "Interpreting results" "Interpretacja wyników" ;;
    av-docs-sync) printf '%s\t%s\n' \
      "Code -> docs map" "Mapa kod -> docs" \
      "Known false names" "Znane fałszywe nazwy" ;;
  esac
}

: >"$tmp/docs"
for o in av-plan av-implement av-review av-verify av-docs-sync; do
  f="$root/$overlays_dir/$o.md"
  checked=$((checked + 1))
  if [ ! -f "$f" ]; then warn "OVERLAY_MISSING $overlays_dir/$o.md"; continue; fi
  rel "$f" >>"$tmp/docs"
  while IFS=$'\t' read -r sec sec_pl; do
    checked=$((checked + 1))
    awk -v s="## $sec" -v p="## $sec_pl" 'index($0, s) == 1 || index($0, p) == 1 { found = 1; exit } END { exit !found }' "$f" ||
      warn "OVERLAY_SECTION $overlays_dir/$o.md: $sec (pl: $sec_pl)"
  done < <(required_sections "$o")
done
for f in "$root"/.claude/skills/*/SKILL.md; do [ -f "$f" ] && rel "$f" >>"$tmp/docs"; done

# MARK: role

nroles="$(jq '(.roles // []) | length' "$config")"
git -C "$root" -c core.quotepath=off ls-files >"$tmp/tracked"
if [ "$nroles" -eq 0 ]; then
  checked=$((checked + 1))
  warn 'ROLES_NONE no "roles" in config; every file belongs to implementer'
else
  while IFS=$'\037' read -r idx name skill nglobs nincl; do
    checked=$((checked + 1))
    if [ -z "$name" ] || [ -z "$skill" ] || [ "$nglobs" -eq 0 ]; then
      err "ROLE_INVALID roles[$idx] requires name, skill and globs"; continue
    fi
    if [ "$nincl" -eq 0 ]; then
      err "ROLE_INVALID roles[$idx] $name has only exclusions (!); add at least one glob without !"; continue
    fi
    case "$skill" in *:*) continue ;; esac
    checked=$((checked + 1))
    sk="$root/.claude/skills/$skill/SKILL.md"
    if [ ! -f "$sk" ]; then err "ROLE_SKILL_MISSING $name .claude/skills/$skill/SKILL.md"; continue; fi
    checked=$((checked + 1))
    copies="$(jq -r --argjson i "$idx" '.roles[$i].globs[] | ltrimstr("!")' "$config" | LC_ALL=C sort -u | while IFS= read -r g; do grep -qF -- "$g" "$sk" && echo x; done | wc -l | tr -d ' ')"
    [ "$copies" -ge 3 ] && warn "GLOB_COPY .claude/skills/$skill/SKILL.md copies $copies globs of role $name; the file scope belongs in the config (roles)"
  done < <(jq -r '(.roles // []) | to_entries[] | [.key, (.value.name // ""), (.value.skill // ""), ((.value.globs // []) | length),
    ((.value.globs // []) | map(select(type != "string" or (startswith("!") | not))) | length)] | map(tostring) | join("\u001f")' "$config")

  impl="$root/$overlays_dir/av-implement.md"
  if [ -f "$impl" ]; then
    checked=$((checked + 1))
    copies="$(jq -r '.roles[].globs // [] | .[] | ltrimstr("!")' "$config" | LC_ALL=C sort -u | while IFS= read -r g; do grep -qF -- "$g" "$impl" && echo x; done | wc -l | tr -d ' ')"
    [ "$copies" -ge 3 ] && warn "GLOB_COPY $overlays_dir/av-implement.md copies $copies role globs; the roles table should link to the config (roles)"
  fi

  match_paths <"$tmp/tracked" >"$tmp/match"
  while IFS=$'\t' read -r _ name g hits; do
    checked=$((checked + 1))
    if [ "$hits" -eq 0 ]; then
      hint=""; case "$g" in *"{"*) hint=" (braces {a,b} not supported: list each variant separately)" ;; esac
      warn "ROLE_EMPTY $name $g$hint"
    fi
  done < <(awk -F'\t' '$1 == "G"' "$tmp/match")

  checked=$((checked + 1))
  awk -F'\t' '$1 == "F" && $4 == 0 && index($3, ",") { c[$3]++; if (c[$3] <= 5) l[$3] = l[$3] (c[$3] > 1 ? ", " : "") $2 }
    END { for (k in c) printf "%s\t%d\t%s\n", k, c[k], l[k] }' "$tmp/match" | LC_ALL=C sort |
  while IFS=$'\t' read -r pair count list; do
    printf 'SETUP_ROLE_OVERLAP %s %d: %s\n' "$pair" "$count" "$list"
  done >"$tmp/overlap"
  if [ -s "$tmp/overlap" ]; then errors=$((errors + $(wc -l <"$tmp/overlap"))); cat "$tmp/overlap"; fi

  checked=$((checked + 1))
  docs_root="$(jq -r '.docs.root // ".ai" | tostring' "$config")"; docs_root="${docs_root#./}"; docs_root="${docs_root%/}"
  case "$docs_root" in ""|.) docs_root="" ;; esac
  git -C "$root" -c core.quotepath=off ls-files --eol -s >"$tmp/eol"
  awk -F'\t' '{ split($1, m, " "); print m[2] }' "$tmp/eol" | git -C "$root" cat-file --batch-check='%(objectsize)' >"$tmp/sizes" 2>/dev/null
  awk -F'\t' -v docs="$docs_root" -v max=262144 '
    FNR == NR { size[FNR] = $1; next }
    {
      split($1, m, " "); split($2, e, " "); p = $3; s = size[FNR]
      if (m[1] != "100644" && m[1] != "100755") next
      if (e[1] == "i/-text" || s !~ /^[0-9]+$/ || s == 0 || s > max) next
      if (substr(p, 1, 1) == "." || (docs != "" && index(p, docs "/") == 1)) next
      if (tolower(p) ~ /\.(md|markdown|mdx)$/) next
      print p
    }' "$tmp/sizes" "$tmp/eol" >"$tmp/source"
  awk -F'\t' '
    FNR == NR { src[$0] = 1; next }
    $1 == "F" && $3 == "" && $4 == 0 && $5 == 0 && ($2 in src) && index($2, "/") {
      n = split($2, parts, "/"); s = (n > 2) ? parts[1] "/" parts[2] : parts[1]
      print parts[1] "\t" s
    }' "$tmp/source" "$tmp/match" | LC_ALL=C sort | uniq -c |
    awk '{ c = $1; sub(/^[ ]*[0-9]+ /, ""); split($0, a, "\t"); printf "%s\t%d\t%s\n", a[1], c, a[2] }' |
    LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2nr |
    awk -F'\t' '
      $1 != top { if (top != "") printf "SETUP_UNOWNED_DIR %s %d files without owner: %s\n", top, tot, d; top = $1; tot = 0; k = 0; d = "" }
      { tot += $2; k++; if (k <= 5) d = d (k > 1 ? ", " : "") $3 " " $2 }
      END { if (top != "") printf "SETUP_UNOWNED_DIR %s %d files without owner: %s\n", top, tot, d }' >"$tmp/unowned"
  if [ -s "$tmp/unowned" ]; then warnings=$((warnings + $(wc -l <"$tmp/unowned"))); cat "$tmp/unowned"; fi
fi

# MARK: paths and gates in overlays and skills

refs="$skill_dir/../av-docs-sync/scripts/check_refs.sh"
if [ ! -s "$tmp/docs" ]; then :
elif [ -f "$refs" ]; then
  checked=$((checked + 1))
  ws="$(jq -r '.paths.workspace // ".ai/workspace"' "$config")"
  docs=(); while IFS= read -r d; do docs+=("$d"); done <"$tmp/docs"
  (cd "$root" && bash "$refs" "${docs[@]}" --root "$root" --workspace "$ws" 2>/dev/null) | awk '$1 == "MISSING"' >"$tmp/missing"
  while IFS= read -r l; do err "REF_MISSING ${l#MISSING }"; done <"$tmp/missing"
else
  warn "REF_SKIPPED no av-docs-sync/scripts/check_refs.sh next to av-setup"
fi

jq -r '(.validation.gates // {}) | keys[]' "$config" >"$tmp/gates"
jq -r '(.validation.commands // {}) | keys[]' "$config" >"$tmp/cmds"
while IFS= read -r d; do
  grep -noE -- '--(gate|only)[ =]+[A-Za-z0-9_.,-]+' "$root/$d" 2>/dev/null | while IFS= read -r hit; do
    line="${hit%%:*}"; rest="${hit#*:}"
    flag="$(printf '%s' "$rest" | sed -E 's/^--(gate|only).*/\1/')"
    names="$(printf '%s' "$rest" | sed -E 's/^--(gate|only)[ =]+//; s/[.,]+$//')"
    printf '%s\n' "$names" | tr ',' '\n' | while IFS= read -r x; do
      [ -n "$x" ] || continue
      list="$tmp/cmds"; [ "$flag" = "gate" ] && list="$tmp/gates"
      grep -qxF -- "$x" "$list" || printf '%s:%s --%s %s\n' "$d" "$line" "$flag" "$x"
    done
  done
done <"$tmp/docs" >"$tmp/gate_unknown"
checked=$((checked + $(wc -l <"$tmp/docs")))
while IFS= read -r l; do err "GATE_UNKNOWN $l"; done <"$tmp/gate_unknown"

finish

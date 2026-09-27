#!/usr/bin/env bash
# scan.sh - deterministic repository scan for av-setup.
#
# Collects neutral facts: ecosystems from manifest and build files, validation commands,
# CI steps, tooling, code layout, existing AI setup, git. Reports the files it finds and
# never guesses frameworks. Does not read secret values or .env files. Prints JSON.
# commands.scripts_meta covers scripts/ and repo-local shell scripts referenced
# by CI files, composer.json and package.json scripts and Makefile recipes.
#
# Usage:
#   scan.sh [ROOT] [--pretty]
# Requires: bash 3.2+, git, jq, find, awk.

set -uo pipefail

root="."
pretty=0
for a in "$@"; do
  case "$a" in
    --pretty) pretty=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) root="$a" ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo '{"error":"jq not found"}'; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo '{"error":"directory not found"}'; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

MAX_LIST=60
MAX_REF_SCRIPTS=40
CODE_EXT_RE='\.(swift|m|h|c|cc|cpp|hpp|php|ts|tsx|js|jsx|mjs|cjs|py|rb|kt|kts|java|scala|go|rs|cs|fs|dart|ex|exs|vue|svelte|twig|html|scss|css)$'
SKIP=( -name .git -o -name node_modules -o -name vendor -o -name Pods -o -name DerivedData -o -name build
  -o -name dist -o -name .angular -o -name .idea -o -name .vscode -o -name var -o -name coverage -o -name .gradle
  -o -name __pycache__ -o -name .venv -o -name venv -o -name tmp -o -name public -o -name legacy-vendors
  -o -name .next -o -name .nuxt -o -name Carthage -o -name test-reports -o -name workspace
  -o \( -name '.*' ! -name .ai ! -name .claude ! -name .github ! -name .agents ! -name .codex ! -name .husky \) )

# walk DIR MAXDEPTH TYPE(f|d) - files or directories, skipping technical directories
walk() {
  find "$1" -mindepth 1 -maxdepth "$(( $2 + 1 ))" -type d \( "${SKIP[@]}" \) -prune -o -type "$3" -print 2>/dev/null
}

lines_to_json() { jq -R -s -c 'split("\n") | map(select(length > 0))'; }
json_or_null() { if [ -s "$1" ]; then cat "$1"; else echo null; fi; }
rel() { printf '%s\n' "${1#$root/}"; }

# MARK: git

git_json() {
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    echo '{"repo":false}'; return
  fi
  local names long base origin_head remote host subjects merged prefixes conv total_s ai_total ai_hits types
  names="$(git -C "$root" for-each-ref --format='%(refname:short)' refs/heads refs/remotes | sed 's|^origin/||' | grep -v '^HEAD$' | sort -u)"
  long="$(printf '%s\n' "$names" | grep -E '^(develop|main|master|release/.+)$' | lines_to_json)"
  base="null"
  for b in develop main master; do
    if printf '%s\n' "$names" | grep -qx "$b"; then base="\"$b\""; break; fi
  done
  origin_head="$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  remote="$(git -C "$root" remote get-url origin 2>/dev/null)"
  case "$remote" in
    *bitbucket*) host="bitbucket" ;;
    *github*) host="github" ;;
    *gitlab*) host="gitlab" ;;
    *)
      if [ -f "$root/bitbucket-pipelines.yml" ]; then host="bitbucket"
      elif [ -d "$root/.github" ]; then host="github"
      elif [ -f "$root/.gitlab-ci.yml" ]; then host="gitlab"
      else host="unknown"; fi ;;
  esac
  git -C "$root" log --no-merges -200 --format=%s 2>/dev/null >"$tmp/subjects"
  git -C "$root" log --merges -200 --format=%s 2>/dev/null |
    sed -nE "s/.*(Merged in |Merge branch '|Merge pull request #[0-9]+ from [^/]+\/)([A-Za-z0-9._\/-]+).*/\2/p" |
    awk '!seen[$0]++' >"$tmp/merged"
  prefixes="$(cat "$tmp/subjects" "$tmp/merged" | grep -noE '(^|[^A-Za-z0-9])[A-Z][A-Z0-9]{1,9}-[0-9]+' |
    sed -E 's/^([0-9]+):[^A-Z]?([A-Z][A-Z0-9]*)-[0-9]+$/\1 \2/' | sort -u | awk '{c[$2]++} END {for (k in c) print c[k], k}' |
    sort -rn | jq -R -s -c 'split("\n") | map(select(length > 0) | split(" ") | {(.[1]): (.[0] | tonumber)}) | add // {}')"
  total_s="$(wc -l <"$tmp/subjects" | tr -d ' ')"
  conv="$(grep -cE '^[a-z]+(\([^)]+\))?!?: |^[A-Z][A-Z0-9]+-[0-9]+ [a-z]+(\([^)]+\))?: ' "$tmp/subjects")"
  ai_total="$(git -C "$root" log -200 --format=%H 2>/dev/null | wc -l | tr -d ' ')"
  ai_hits="$(git -C "$root" log -200 --format='%b%n@@AV_END@@' 2>/dev/null |
    awk 'BEGIN { IGNORECASE = 1 } tolower($0) ~ /co-authored-by: claude/ { hit = 1 } $0 == "@@AV_END@@" { n += hit; hit = 0 } END { print n + 0 }')"
  types="$(grep '/' "$tmp/merged" | cut -d/ -f1 | grep -E '^(feature|bugfix|hotfix|task|release)$' | sort -u | lines_to_json)"
  jq -n -c \
    --arg current "$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
    --argjson base "$base" --arg origin_head "$origin_head" --argjson long "$long" --arg host "$host" \
    --argjson subjects "$(head -15 "$tmp/subjects" | lines_to_json)" \
    --arg conv "$conv/$total_s" --argjson merged "$(head -20 "$tmp/merged" | lines_to_json)" \
    --argjson types "$types" --argjson prefixes "$prefixes" --arg ai "$ai_hits/$ai_total" '
    {repo: true, current_branch: $current, base_branch_guess: $base,
     origin_head: (if $origin_head == "" then null else $origin_head end),
     long_lived_branches: $long, remote_host: $host, recent_subjects: $subjects,
     conventional_commits_ratio: $conv, merged_branch_names: $merged, branch_types_seen: $types,
     ticket_prefixes: $prefixes, ai_signature_commits: $ai}'
}

# MARK: stack

MANIFEST_RE='package\.json|composer\.json|[^/]+\.(xcodeproj|xcworkspace|sln|csproj|fsproj|vbproj|gemspec)|Podfile|Package\.swift|(build|settings)\.gradle(\.kts)?|pom\.xml|go\.mod|pyproject\.toml|requirements\.txt|setup\.py|Pipfile|Cargo\.toml|Gemfile|pubspec\.yaml|mix\.exs'

# manifest_id NAME - ecosystem id of a manifest or build file name (MANIFEST_RE), nothing for other names
manifest_id() {
  case "$1" in
    package.json) echo npm ;;
    composer.json) echo composer ;;
    *.xcodeproj|*.xcworkspace) echo xcode ;;
    Podfile) echo cocoapods ;;
    Package.swift) echo swiftpm ;;
    build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts) echo gradle ;;
    pom.xml) echo maven ;;
    go.mod) echo go ;;
    pyproject.toml|requirements.txt|setup.py|Pipfile) echo python ;;
    Cargo.toml) echo cargo ;;
    *.sln|*.csproj|*.fsproj|*.vbproj) echo dotnet ;;
    Gemfile|*.gemspec) echo ruby ;;
    pubspec.yaml) echo dart ;;
    mix.exs) echo elixir ;;
  esac
}

# stacks_json - neutral facts only: one entry {id, dir, evidence} per ecosystem and directory.
# id names the ecosystem of the manifest or build file found (npm, composer, xcode, gradle, ...),
# dir is the directory of the manifest ("." for the root), evidence lists the files found.
# Scans the root and 3 levels below it; invalid package.json and composer.json files are skipped.
stacks_json() {
  local p id dir
  { walk "$root" 3 f; walk "$root" 3 d | grep -E '\.(xcodeproj|xcworkspace)$'; } | grep -v '\.xcodeproj/' |
    grep -E "/($MANIFEST_RE)\$" | LC_ALL=C sort -u |
  while IFS= read -r p; do
    id="$(manifest_id "$(basename "$p")")"
    [ -n "$id" ] || continue
    case "$id" in npm|composer) jq empty "$p" 2>/dev/null || continue ;; esac
    dir="$(dirname "$p")"; dir="${dir#$root}"; dir="${dir#/}"; [ -n "$dir" ] || dir="."
    printf '%s\t%s\t%s\n' "$id" "$dir" "$(rel "$p")"
  done | jq -R -s -c --argjson max "$MAX_LIST" '
    split("\n") | map(select(length > 0) | split("\t"))
    | group_by([.[1], .[0]])
    | map({id: .[0][0], dir: .[0][1], evidence: (map(.[2]) | sort | .[:20])})
    | sort_by([(.dir != "."), .dir, .id]) | .[:$max]'
}

# MARK: commands and CI

script_doc() {
  awk 'NR == 1 { next } NR > 15 { exit }
    /^[ \t]*("""|\047\047\047)/ { s = $0; gsub(/^[ \t]*("""|\047\047\047)[ \t]*|("""|\047\047\047)[ \t]*$/, "", s); if (s != "") { print substr(s, 1, 140); exit } want = 1; next }
    want { s = $0; gsub(/^[ \t]+/, "", s); print substr(s, 1, 140); exit }
    /^[ \t]*(#|\/\/)/ && !/^#!/ && !/-\*-/ { s = $0; gsub(/^[ \t]*(#+|\/\/+)[ \t]*/, "", s); if (length(s) > 3) { print substr(s, 1, 140); exit } }' "$1"
}

# script_meta FILE - JSON {path, exit_codes_doc, status_tokens}; nothing when the script does not describe its result
# Exit code lines are matched in Polish ("Kod wyjscia") and English ("Exit code", "Exit status", "Exit 0:"),
# because scripts in scanned repos are written in either language.
script_meta() {
  local codes tokens
  codes="$(awk '
    NR == 1 && /^#!/ { next }
    NR > 40 { exit }
    {
      line = $0; txt = ""
      if (indoc) { if (line ~ /"""|\047\047\047/) { indoc = 0; sub(/("""|\047\047\047).*/, "", line) } txt = line }
      else if (line ~ /^[ \t]*("""|\047\047\047)/) { txt = line; gsub(/"""|\047\047\047/, "", txt); if (line !~ /^[ \t]*("""|\047\047\047).*("""|\047\047\047)/) indoc = 1 }
      else if (line ~ /^[ \t]*(#|\/\/|\/\*|\*)/) { txt = line; sub(/^[ \t]*(#+|\/\/+|\/\*+|\*+)[ \t]?/, "", txt) }
      else if (line ~ /^[ \t]*$/) { cont = 0; next }
      else if (seen) exit
      else next
      seen = 1
      gsub(/^[ \t]+|[ \t]+$/, "", txt)
      if (txt ~ /[Kk]od[a-z]* wyj|[Ee]xit[ -]?(code|status)|[Ee]xit[ :]+[0-9]/) { out = out (out == "" ? "" : " ") txt; cont = 1; next }
      if (txt == "") { cont = 0; next }
      if (cont && txt !~ /:$/) out = out " " txt
      else cont = 0
    }
    END { print substr(out, 1, 400) }' "$1")"
  tokens="$( { grep -oE 'STATUS: [A-Z][A-Z0-9_]+' "$1" | sed 's/^STATUS: //'
    grep -E '(echo|printf|print)[ (]' "$1" | grep -oE '[A-Z][A-Z0-9]*_(OK|FAILED|FAIL|PASSED|PASS|SKIPPED|DOWN|ERROR)'; } 2>/dev/null |
    awk '!seen[$0]++' | head -12 | lines_to_json)"
  [ -z "$codes" ] && [ "$tokens" = "[]" ] && return 0
  jq -n -c --arg p "$(rel "$1")" --arg c "$codes" --argjson t "$tokens" \
    '{path: $p, exit_codes_doc: (if $c == "" then null else $c end), status_tokens: $t}'
}

# ref_words SOURCE BASEDIR <TEXT - path-like words of command lines as "SOURCE<TAB>BASEDIR<TAB>WORD"
ref_words() {
  awk -v src="$1" -v base="$2" '
    /^[ \t]*#/ { next }
    {
      n = split($0, w, /[ \t;&|()<>=`"\047]+/)
      for (i = 1; i <= n; i++) {
        t = w[i]; sub(/^\.\//, "", t)
        if (t ~ /^[A-Za-z0-9_.][A-Za-z0-9_.\/+-]*$/ && (t ~ /\// || t ~ /\.(sh|bash)$/) && !seen[t]++) print src "\t" base "\t" t
      }
    }'
}

# resolve_refs <"SOURCE<TAB>BASEDIR<TAB>WORD" - existing repo-local scripts as "PATH<TAB>SOURCE".
# Accepts .sh/.bash files and files with a shell shebang; composer.json and package.json
# references also accept .py, .php, .mjs and .js files.
resolve_refs() {
  local src base word b p first found
  while IFS=$'\t' read -r src base word; do
    case "/$word/" in */node_modules/*|*/vendor/*) continue ;; esac
    found=""
    for b in "$base" "$root"; do
      p="$b/$word"
      case "$word" in *..*) p="$(cd "$(dirname "$p")" 2>/dev/null && printf '%s/%s' "$(pwd)" "$(basename "$p")")" || continue ;; esac
      case "$p" in "$root"/*) ;; *) continue ;; esac
      [ -f "$p" ] && { found="$p"; break; }
    done
    [ -n "$found" ] || continue
    p="$found"
    case "$p" in
      *.sh|*.bash) ;;
      *.py|*.php|*.mjs|*.js) case "$src" in composer.json|package.json|*/package.json) ;; *) continue ;; esac ;;
      *) first=""; IFS= read -r first <"$p" 2>/dev/null
         printf '%s\n' "$first" | grep -qE '^#!.*[/ ](ba|z|da|k)?sh([ ]|$)' || continue ;;
    esac
    printf '%s\t%s\n' "$(rel "$p")" "$src"
  done
}

# parse_ci FILE KIND(bitbucket|gitlab|github) - JSON {steps, steps_total}: every step that has
# commands, in file order, at most 60 (steps_total counts all). A step is a Bitbucket list item
# (step, stage, parallel, script snippet), an item of a GitHub job steps list, or a GitLab top-level
# key (job, hidden template, global before_script). Commands come from script, run, before_script,
# after_script and after-script: inline values, list items (also at the same indent as the key)
# and each line of a multi-line block. Each step has section (Bitbucket pipeline or definitions,
# GitHub "jobs", GitLab stage) and name; anchor (&name on the step), ref (*name alias, <<: *name
# merge or GitLab extends), job (GitHub or GitLab job id) and job_name (GitHub job name) are added
# when present. A step with a ref and no own commands takes the commands and name of its target,
# so a step defined once and used in several pipelines is reported in each of them; a *name
# command is replaced by the commands of the step with that anchor. CRLF files are accepted.
parse_ci() {
  awk -v kind="$2" '
    function redact(t) {
      if (t ~ /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/ || t ~ /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/)
        return "[skipped: line with an identifier or e-mail address]"
      return t
    }
    function unquote(v) { if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2); return v }
    function new_step() { step++; named = 0; print "M\t" step "\tsection\t" section; if (job != "") meta("job", job); if (jname != "") meta("job_name", jname) }
    function meta(k, v) { if (step == 0) new_step(); gsub(/\t/, " ", v); if (k ~ /name/) v = redact(v); print "M\t" step "\t" k "\t" v }
    function cmd(c) { if (step == 0) new_step(); gsub(/\t/, " ", c); print "C\t" step "\t" redact(substr(c, 1, 200)) }
    function alias(v) { if (match(v, /^\*[A-Za-z0-9_.-]+/)) meta("ref", substr(v, 2, RLENGTH - 1)) }
    BEGIN { script_indent = -1; step = 0; section = ""; job = ""; jname = ""; job_child = -1; skey = -1; child = -1; sec_indent = -1; sub_indent = -1; job_indent = -1; steps_item = -1 }
    {
      raw = $0; sub(/\r$/, "", raw)
      if (raw ~ /^[ \t]*$/ || raw ~ /^[ \t]*#/) next
      match(raw, /^[ ]*/); indent = RLENGTH; line = substr(raw, indent + 1)
      sub(/[ \t]+$/, "", line)
      if (list_job) {
        list_job = 0
        if (indent > 0 && line ~ /^- / && substr(line, 3) !~ /^["\047]?[A-Za-z0-9_.-]+["\047]?:([ \t]|$)/) { script_indent = 0; script_list = 0 }
      }
      if (script_indent >= 0) {
        if (indent > script_indent || (script_list && indent == script_indent && line ~ /^- /)) {
          if (line ~ /^- /) { c = unquote(substr(line, 3)); if (length(c) > 2) cmd(c) }
          else if (line !~ /:$/) cmd(line)
          next
        }
        script_indent = -1
      }
      li = (line ~ /^- /); kin = indent; body = line
      if (li) { kin = indent + 2; body = substr(line, 3); sub(/^[ \t]+/, "", body) }
      key = ""; val = ""
      if (match(body, /^["\047]?[^"\047:]+["\047]?:([ \t]|$)/)) {
        key = substr(body, 1, RLENGTH); sub(/:[ \t]*$/, "", key); gsub(/["\047]/, "", key)
        val = substr(body, RLENGTH + 1); sub(/^[ \t]+/, "", val)
      }
      anc = ""; first = step
      if (match(val, /^&[A-Za-z0-9_.-]+/)) { anc = substr(val, 2, RLENGTH - 1); val = substr(val, RLENGTH + 1); sub(/^[ \t]+/, "", val) }
      if (kind == "bitbucket") {
        if (!li && indent <= 4 && key ~ /^(default|pull-requests|branches|tags|custom|definitions)$/ && val == "") {
          section = key; base = key; sec_indent = indent; sub_indent = -1; next
        }
        if (!li && indent == 0) { section = ""; base = "" }
        if (base ~ /^(branches|pull-requests|custom|tags)$/ && !li && indent > sec_indent && key != "" && val == "") {
          if (sub_indent < 0) sub_indent = indent
          if (indent == sub_indent && key ~ /^[A-Za-z0-9_*\/.{},-]+$/) { section = base ":" key; next }
        }
        if (li && key != "") { new_step(); skey = kin; if (val == "") { skey = -1; child = kin } }
        else if (!li && skey < 0 && child >= 0 && indent >= child) { skey = indent; child = -1 }
      } else if (kind == "github") {
        if (indent == 0) {
          job = ""; jname = ""; in_jobs = 0; in_steps = 0
          if (key ~ /^(on|jobs)$/ && val == "") section = key
          if (key == "jobs" && val == "") { in_jobs = 1; job_indent = -1 }
          next
        }
        if (in_jobs && !li) {
          if (job_indent < 0) job_indent = indent
          if (indent == job_indent && key != "") { job = key; jname = ""; job_child = -1; new_step(); skey = -1; in_steps = 0; next }
          if (job_child < 0 && indent > job_indent) job_child = indent
          if (indent == job_child && key == "name" && val != "") { jname = unquote(val); next }
        }
        if (!li && key == "steps" && val == "") { in_steps = 1; steps_item = -1; next }
        if (li && in_steps && key != "") {
          if (steps_item < 0) steps_item = indent
          if (indent == steps_item) { new_step(); skey = kin }
        }
      } else if (kind == "gitlab") {
        if (indent == 0 && !li && key != "") { job = key; new_step(); meta("name", key); named = 1; skey = -1; list_job = (val == "" && (anc != "" || key ~ /^\./)) }
        if (key == "stage" && val != "") meta("section", unquote(val))
        if (key == "extends" && val != "") { v = val; gsub(/[][ "\047]/, "", v); sub(/,.*$/, "", v); if (v != "") meta("ref", v) }
      }
      if (anc != "" && step != first) meta("anchor", anc)
      if (key == "<<" || key == "step") alias(val)
      if (key == "name" && kin == skey && !named) { meta("name", unquote(val)); named = 1 }
      if (key ~ /^(script|run|before_script|after_script|after-script)$/ && !(key == "run" && val == "")) {
        if (val == "" || val ~ /^[|>][-+0-9]*$/) { script_indent = kin; script_list = (val == ""); if (step == 0) new_step() }
        else cmd(unquote(val))
      }
    }' "$1" | jq -R -s -c --argjson max 60 '
      split("\n") | map(select(length > 0) | split("\t"))
      | (map(select(.[0] == "M")) | reduce .[] as $r ({}; .[$r[1]][$r[2]] = $r[3])) as $m
      | (map(select(.[0] == "C")) | reduce .[] as $r ({}; .[$r[1]] += [$r[2]])) as $c
      | [($m | keys[]), ($c | keys[])] | unique | map(tonumber) | sort
      | map(tostring as $k | ($m[$k] // {}) as $x
          | {section: (if ($x.section // "") == "" then null else $x.section end), name: (if ($x.name // "") == "" then null else $x.name end),
             commands: ($c[$k] // []), anchor: $x.anchor, ref: $x.ref, job: $x.job, job_name: $x.job_name})
      | . as $all
      | map(.commands |= (map(. as $cmd | if test("^\\*[A-Za-z0-9_.-]+$") then
          ([$all[] | select(.anchor == $cmd[1:] and (.commands | length) > 0)] | .[0].commands // [$cmd]) else [$cmd] end) | add // []))
      | . as $all
      | map(if .ref == null then . else
          .ref as $r | ([$all[] | select((.anchor == $r or .job == $r) and (.commands | length) > 0)] | .[0]) as $t
          | if $t == null then . else .name = (.name // $t.name) | .commands = (if .commands == [] then $t.commands else .commands end) end
        end)
      | map(select((.commands | length) > 0) | with_entries(select(.value != null or (.key | IN("section", "name")))))
      | {steps_total: length, steps: .[:$max]}'
}

commands_json() {
  local out="{}" pkg dir runner key f kind
  if [ -f "$root/composer.json" ] && jq -e '.scripts' "$root/composer.json" >/dev/null 2>&1; then
    out="$(jq -c --slurpfile c "$root/composer.json" '. + {composer: ($c[0].scripts | with_entries(select(.key | test("^(post-|pre-|auto-)") | not)))}' <<<"$out")"
  fi
  while IFS= read -r pkg; do
    jq -e '.scripts' "$pkg" >/dev/null 2>&1 || continue
    dir="$(dirname "$pkg")"
    runner="npm run"
    if [ -f "$dir/pnpm-lock.yaml" ]; then runner="pnpm"
    elif [ -f "$dir/yarn.lock" ]; then runner="yarn"
    elif [ -f "$dir/bun.lockb" ]; then runner="bun run"; fi
    key="package.json:$(rel "$dir")"; [ "$dir" = "$root" ] && key="package.json:."
    out="$(jq -c --arg k "$key" --arg r "$runner" --slurpfile p "$pkg" '. + {($k): {runner: $r, scripts: $p[0].scripts}}' <<<"$out")"
  done < <({ [ -f "$root/package.json" ] && echo "$root/package.json"; walk "$root" 3 f | grep '/package\.json$'; } | sort -u | tee "$tmp/pkgs")
  if [ -f "$root/Makefile" ]; then
    out="$(jq -c --argjson m "$(grep -oE '^[A-Za-z][A-Za-z0-9_-]*:' "$root/Makefile" | tr -d : | sort -u | head -$MAX_LIST | lines_to_json)" '. + {make: $m}' <<<"$out")"
  fi
  if [ -d "$root/scripts" ]; then
    : >"$tmp/scripts"
    while IFS= read -r f; do
      case "$f" in *.sh|*.bash|*.py|*.rb|*.mjs|*.cjs|*.js|*.ts|*.php) ;; *) continue ;; esac
      jq -n -c --arg file "$(rel "$f")" --arg doc "$(script_doc "$f")" '{file: $file, doc: $doc}' >>"$tmp/scripts"
    done < <(walk "$root/scripts" 2 f | grep -v '/tests\?/' | LC_ALL=C sort)
    out="$(jq -c --argjson s "$(jq -s -c ".[:$MAX_LIST]" "$tmp/scripts")" '. + {scripts_dir: $s}' <<<"$out")"
  fi
  : >"$tmp/ci"
  : >"$tmp/refwords"
  for f in "$root/bitbucket-pipelines.yml" "$root/.gitlab-ci.yml" "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    case "$f" in */bitbucket-pipelines.yml) kind=bitbucket ;; */.gitlab-ci.yml) kind=gitlab ;; *) kind=github ;; esac
    jq -n -c --arg f "$(rel "$f")" --argjson s "$(parse_ci "$f" "$kind")" '{file: $f} + $s' >>"$tmp/ci"
    ref_words "$(rel "$f")" "$root" <"$f" >>"$tmp/refwords"
  done
  [ -s "$tmp/ci" ] && out="$(jq -c --argjson c "$(jq -s -c . "$tmp/ci")" '. + {ci: $c}' <<<"$out")"
  : >"$tmp/metafiles"
  [ -d "$root/scripts" ] && walk "$root/scripts" 2 f | grep -v '/tests\?/' | grep -E '\.(sh|bash|py|rb|mjs|cjs|js|ts|php)$' |
    LC_ALL=C sort -u | head -$MAX_LIST >"$tmp/metafiles"
  [ -f "$root/composer.json" ] && jq -r '.scripts // {} | .[] | if type == "array" then .[] else . end | strings' "$root/composer.json" 2>/dev/null |
    ref_words composer.json "$root" >>"$tmp/refwords"
  while IFS= read -r pkg; do
    jq -r '.scripts // {} | .[] | strings' "$pkg" 2>/dev/null | ref_words "$(rel "$pkg")" "$(dirname "$pkg")" >>"$tmp/refwords"
  done <"$tmp/pkgs"
  [ -f "$root/Makefile" ] && grep "^$(printf '\t')" "$root/Makefile" | ref_words Makefile "$root" >>"$tmp/refwords"
  resolve_refs <"$tmp/refwords" >"$tmp/refs"
  cut -f1 "$tmp/refs" | awk '!seen[$0]++' | while IFS= read -r f; do
    grep -qxF "$root/$f" "$tmp/metafiles" || printf '%s\n' "$root/$f"
  done | head -$MAX_REF_SCRIPTS >>"$tmp/metafiles"
  LC_ALL=C sort -u "$tmp/metafiles" | while IFS= read -r f; do script_meta "$f"; done >"$tmp/meta"
  if [ -s "$tmp/meta" ]; then
    out="$(jq -c --argjson m "$(jq -s -c . "$tmp/meta")" --argjson r "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t"))
      | reduce .[] as $x ({}; .[$x[0]] = ((.[$x[0]] // []) + [$x[1]] | unique))' "$tmp/refs")" \
      '. + {scripts_meta: ($m | map(. + {referenced_by: ($r[.path] // [])}))}' <<<"$out")"
  fi
  local compose
  compose="$(ls "$root"/docker-compose*.y*ml "$root"/compose*.y*ml 2>/dev/null | xargs -n1 basename 2>/dev/null | lines_to_json)"
  [ "$compose" != "[]" ] && out="$(jq -c --argjson d "$compose" '. + {docker_compose: $d}' <<<"$out")"
  : >"$tmp/doccmds"
  local seen=""
  for f in CLAUDE.md .ai/commands.md docs/commands.md README.md Readme.md readme.md; do
    [ -f "$root/$f" ] || continue
    local dup=0 s2
    for s2 in $seen; do [ "$root/$f" -ef "$root/$s2" ] && dup=1; done
    [ "$dup" -eq 1 ] && continue
    seen="$seen $f"
    awk -v doc="$f" '
      /^[ \t]*```/ { if (!fence) { fence = 1; lang = $0; sub(/^[ \t]*```[ \t]*/, "", lang); sub(/[ \t].*$/, "", lang) } else fence = 0; next }
      fence && (lang == "sh" || lang == "bash" || lang == "shell" || lang == "zsh" || lang == "console" || lang == "") {
        s = $0; gsub(/^[ \t]+|[ \t]+$/, "", s)
        if (s == "" || s ~ /^#/) next
        if (lang == "" || lang == "console") {
          if (s ~ /^\$ /) s = substr(s, 3)
          else if (s !~ /^(\.\/|scripts\/|bin\/|npm |npx |yarn |pnpm |composer |docker |make |xcodebuild |xcrun |pod |git |php |python3? |bash |sh |ruby |bundle |swift |ng |export |cd |go |cargo |mvn |\.\/mvnw |gradle |\.\/gradlew |dotnet |pytest|poetry |uv |pip3? |tox |rake |rails |just |task |node |deno |bun |dart |flutter |mix )/) next
        }
        sub(/[ \t]+#.*$/, "", s)
        print doc "\t" substr(s, 1, 200)
      }' "$root/$f" >>"$tmp/doccmds"
  done
  if [ -s "$tmp/doccmds" ]; then
    out="$(jq -c --argjson d "$(head -40 "$tmp/doccmds" | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {doc: .[0], cmd: .[1]})')" '. + {documented_commands: $d}' <<<"$out")"
  fi
  printf '%s\n' "$out"
}

tooling_json() {
  local out="{}" f name text m
  if [ -d "$root/.husky" ]; then
    : >"$tmp/husky"
    for f in "$root"/.husky/*; do
      [ -f "$f" ] || continue
      jq -n -c --arg k "$(basename "$f")" --argjson v "$(grep -v '^#' "$f" | sed '/^[[:space:]]*$/d; s/^[[:space:]]*//' | awk 'NR <= 30 { print } NR == 31 { print "[truncated: the hook has more lines]" }' | lines_to_json)" '{($k): $v}' >>"$tmp/husky"
    done
    out="$(jq -c --argjson h "$(jq -s -c 'add // {}' "$tmp/husky")" '. + {husky_hooks: $h}' <<<"$out")"
  fi
  for name in .lintstagedrc .lintstagedrc.json .lintstagedrc.js lint-staged.config.js lint-staged.config.mjs; do
    [ -f "$root/$name" ] && out="$(jq -c --arg n "$name" '. + {lint_staged: $n}' <<<"$out")"
  done
  for name in .nvmrc .node-version .tool-versions .php-version .python-version .xcode-version; do
    [ -f "$root/$name" ] && out="$(jq -c --arg n "$name" --argjson v "$(head -5 "$root/$name" | lines_to_json)" '.versions[$n] = $v' <<<"$out")"
  done
  if [ -f "$root/package.json" ] && jq -e '.engines' "$root/package.json" >/dev/null 2>&1; then
    out="$(jq -c --slurpfile p "$root/package.json" '.versions.engines = $p[0].engines' <<<"$out")"
  fi
  for name in karma.conf.js jest.config.js jest.config.ts vitest.config.ts phpunit.xml.dist phpunit.xml; do
    [ -f "$root/$name" ] || continue
    m="$(tr '\n' ' ' <"$root/$name" | grep -oE '(check|coverageThreshold|thresholds)[[:space:]]*[:=][[:space:]]*\{[^}]*\}' | head -1 | tr -s ' ' | cut -c1-200)"
    [ -n "$m" ] && out="$(jq -c --arg n "$name" --arg v "$m" '.coverage_thresholds[$n] = $v' <<<"$out")"
  done
  text="$(ls -A "$root" | grep -E '^(\.?eslint|stylelint|\.prettierrc|prettier\.config|phpstan|\.php-cs-fixer|rector|\.swiftlint|\.editorconfig)' | lines_to_json)"
  [ "$text" != "[]" ] && out="$(jq -c --argjson l "$text" '. + {lint_configs: $l}' <<<"$out")"
  text="$(find "$root" -mindepth 1 -maxdepth 1 -type d | xargs -n1 basename | grep -E 'eslint|lint-rules|rector' | lines_to_json)"
  [ "$text" != "[]" ] && out="$(jq -c --argjson l "$text" '. + {custom_lint_dirs: $l}' <<<"$out")"
  printf '%s\n' "$out"
}

# MARK: code layout

count_files() { walk "$1" "$2" f | wc -l | tr -d ' '; }

layout_json() {
  : >"$tmp/layout"
  local d name total
  while IFS= read -r d; do
    d="$root/$d"; name="$(basename "$d")"
    [ -d "$d" ] || continue
    printf '%s\n' "$name" | grep -qE '^(\.|node_modules$|vendor$|Pods$|DerivedData$|build$|dist$|var$|coverage$|tmp$|public$|legacy-vendors$|Carthage$|test-reports$|workspace$)' && continue
    walk "$d" 8 f >"$tmp/files"
    total="$(wc -l <"$tmp/files" | tr -d ' ')"
    [ "$total" -gt 0 ] || continue
    : >"$tmp/subdirs"
    for c in "$d"/*/; do
      c="${c%/}"; [ -d "$c" ] || continue
      printf '%s\n' "$(basename "$c")" | grep -qE '^(\.|node_modules$|vendor$|Pods$|build$|dist$|workspace$)' && continue
      jq -n -c --arg n "$(basename "$c")" --argjson f "$(count_files "$c" 6)" '{name: $n, files: $f}' >>"$tmp/subdirs"
    done
    awk -F/ '{ n = $NF; sub(/^\./, "", n); e = "(none)"; if (match(n, /\.[^.]+$/)) e = tolower(substr(n, RSTART)); c[e]++ } END { for (k in c) print c[k] "\t" k }' "$tmp/files" |
      sort -rn >"$tmp/exts"
    jq -n -c --arg dir "$name" --argjson files "$total" \
      --argjson ext "$(head -6 "$tmp/exts" | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {(.[1]): (.[0] | tonumber)}) | add // {}')" \
      --argjson src "$(grep -cE "$CODE_EXT_RE" "$tmp/files")" \
      --argjson sub "$(jq -s -c 'sort_by(-.files) | .[:25]' "$tmp/subdirs")" \
      '{dir: $dir, files: $files, top_ext: $ext, subdirs: $sub, source: $src}' >>"$tmp/layout"
  done < <(cd "$root" && ls -d */ 2>/dev/null | sed 's|/$||' | LC_ALL=C sort)
  jq -s -c . "$tmp/layout"
}

modules_json() {
  : >"$tmp/modules"
  local pat d count
  for pat in "src/Modules/*" "src/Controller/*" "src/*" "src/app/*" "src/app/modules/*" "src/app/features/*" \
             "*/Domains/*" "*/Features/*" "*/Modules/*" "app/*" "lib/*"; do
    : >"$tmp/mod"
    for d in "$root"/$pat; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      printf '%s\n' "$name" | grep -qE '^(\.|node_modules$|vendor$|Pods$|build$|dist$|workspace$)' && continue
      printf '%s\t%s\n' "$(count_files "$d" 6)" "$name" >>"$tmp/mod"
    done
    count="$(wc -l <"$tmp/mod" | tr -d ' ')"
    [ "$count" -ge 3 ] || continue
    layers="$(cut -f2 "$tmp/mod" | grep -icxE 'controllers?|forms?|enums?|entity|entities|services?|repository|repositories|events?|listeners?|subscribers?|handlers?|middlewares?|utils?|utilities|validators?|providers?|commands?|security|models?|helpers?|exceptions?|errors?|messages?|views?|components?|config|core|shared|common|layout|i18n|assets|styles|app|lib' )"
    jq -n -c --arg p "$pat" --argjson c "$count" --argjson layers "$( [ $((layers * 2)) -ge "$count" ] && echo true || echo false )" \
      --argjson s "$(sort -t "$(printf '\t')" -k1,1nr -k2,2 "$tmp/mod" | head -200 | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {name: .[1], files: (.[0] | tonumber)})')" \
      '{pattern: $p, count: $c, looks_like_layers: $layers, by_size: $s}' >>"$tmp/modules"
  done
  jq -s -c . "$tmp/modules"
}

tests_json() {
  : >"$tmp/testdirs"
  walk "$root" 3 d | while IFS= read -r d; do
    basename "$d" | grep -qE '^(tests?|e2e|E2E|__tests__|spec)$|Tests$' || continue
    grep -qE "$CODE_EXT_RE" < <(walk "$d" 3 f) && rel "$d"
  done | sort | head -20 >"$tmp/testdirs"
  local spec=0
  [ -d "$root/src" ] && spec="$(walk "$root/src" 20 f | grep -c '\.spec\.ts$')"
  walk "$root" 10 f | grep -E "$CODE_EXT_RE" | awk -F/ '
    { n = $NF
      if (n ~ /\.spec\.[^.]+$/) c["*.spec.*"]++
      else if (n ~ /\.test\.[^.]+$/) c["*.test.*"]++
      else if (n ~ /_test\.[^.]+$/) c["*_test.*"]++
      else if (n ~ /^test_.+\.[^.]+$/) c["test_*.*"]++
      else if (n ~ /Tests?\.[^.]+$/) c["*Test.*"]++ }
    END { for (k in c) print k "\t" c[k] }' >"$tmp/testfiles"
  jq -n -c --argjson d "$(lines_to_json <"$tmp/testdirs")" --argjson s "$spec" \
    --argjson p "$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {(.[0]): (.[1] | tonumber)}) | add // {}' "$tmp/testfiles")" \
    '{dirs: $d, spec_ts_files: $s, test_file_patterns: $p}'
}

# MARK: existing AI setup

# pipeline_docs_json - markdown files that describe an agent pipeline, independent of the capped
# .ai and docs lists. A file under .ai/ or docs/ counts by name when it is implementation-pipeline.md,
# pipeline.md or *agents.md. A file under .ai/, docs/ or .claude/ counts by content when it has at
# least 2 of 4 signals: (1) 2+ headings with "phase" or the Polish "faza" next to a number,
# (2) the literal RUN_ID, (3) "orchestrator" or the Polish "orkiestrator" (and derived words),
# (4) a reference to .claude/agents/. One of the 2 must be (1) or (2): signals (3) and (4) alone
# also fit single agent specs and slash commands, which are listed under .claude already.
# Headings inside code fences do not count. Skips .ai/workspace and .ai/sessions, reads at most
# PIPELINE_MAX_FILES files of at most 256 KB each and reports at most 20 paths.
PIPELINE_MAX_FILES=400
pipeline_docs_json() {
  local d
  for d in .ai docs .claude; do
    [ -d "$root/$d" ] || continue
    find -H "$root/$d" \( -path "$root/.ai/workspace" -o -path "$root/.ai/sessions" -o -name node_modules \) -prune \
      -o -type f -name '*.md' -size -257k -print 2>/dev/null
  done | LC_ALL=C sort | head -$PIPELINE_MAX_FILES >"$tmp/pipecands"
  {
    while IFS= read -r f; do
      case "$(rel "$f")" in .ai/*|docs/*) ;; *) continue ;; esac
      printf '%s\n' "$f" | grep -qE '(implementation-pipeline|/pipeline|agents)\.md$' && printf '%s\n' "$f"
    done <"$tmp/pipecands"
    tr '\n' '\0' <"$tmp/pipecands" | xargs -0 awk '
      function flush() { if (f != "" && (ph >= 2 || rid) && (ph >= 2) + rid + orc + ag >= 2) print f }
      FNR == 1 { flush(); f = FILENAME; ph = 0; rid = 0; orc = 0; ag = 0; fence = 0 }
      /^[ \t]*```/ { fence = !fence; next }
      { l = tolower($0) }
      !fence && l ~ /^#+[ \t]/ && l ~ /(phase|faza)[ \t]*[0-9]|[0-9][.):]?[ \t]*[-:]?[ \t]*(phase|faza)/ { ph++ }
      index($0, "RUN_ID") { rid = 1 }
      l ~ /orchestrat|orkiestrat/ { orc = 1 }
      index($0, ".claude/agents/") { ag = 1 }
      END { flush() }' 2>/dev/null
  } | while IFS= read -r f; do rel "$f"; done | LC_ALL=C sort -u | head -20 | lines_to_json
}

md_list() { [ -d "$root/$1" ] && find "$root/$1" -name "${2:-*.md}" -not -name .DS_Store 2>/dev/null | while IFS= read -r f; do rel "$f"; done | sort | head -$MAX_LIST | lines_to_json || echo null; }

ai_json() {
  local out="{}" name p entry settings
  for name in CLAUDE.md AGENTS.md GEMINI.md .cursorrules .github/copilot-instructions.md; do
    p="$root/$name"
    [ -e "$p" ] || [ -L "$p" ] || continue
    entry="$(jq -n -c --argjson l "$(wc -l <"$p" 2>/dev/null | tr -d ' ' || echo 0)" '{lines: $l}')"
    [ -L "$p" ] && entry="$(jq -c --arg t "$(readlink "$p")" '. + {symlink_to: $t}' <<<"$entry")"
    if [ "$name" = "CLAUDE.md" ]; then
      entry="$(jq -c \
        --argjson h "$(grep -E '^#{1,3} ' "$p" | sed -E 's/^#{1,3} //' | head -40 | lines_to_json)" \
        --argjson i "$(grep -oE '(^|[^A-Za-z0-9_`])@[A-Za-z0-9_./-]+\.md' "$p" | sed -E 's/^[^@]*@//' | head -30 | lines_to_json)" \
        '. + {headings: $h, imports: $i}' <<<"$entry")"
    fi
    out="$(jq -c --arg n "$name" --argjson e "$entry" '.[$n] = $e' <<<"$out")"
  done
  out="$(jq -c --argjson a "$([ -f "$root/.ai/av.config.json" ] && echo true || echo false)" '.av_config = $a' <<<"$out")"
  local ai_md docs_md
  ai_md="null"
  if [ -d "$root/.ai" ]; then
    ai_md="$(find "$root/.ai" -name '*.md' -not -path '*/workspace/*' -not -path '*/sessions/*' 2>/dev/null | while IFS= read -r f; do rel "$f"; done | sort | head -$MAX_LIST | lines_to_json)"
  fi
  docs_md="$(md_list docs '*.md')"
  settings="{}"
  # Only key names and non-secret fields leave jq; values (e.g. the env section) never reach the shell.
  [ -f "$root/.claude/settings.json" ] && jq empty "$root/.claude/settings.json" 2>/dev/null && settings="$(jq -c '{
      settings_keys: keys, hooks: ((.hooks // {}) | keys), deny_rules: ((.permissions.deny // []) | length),
      enabled_mcp: (.enabledMcpjsonServers // null), enabled_plugins: ((.enabledPlugins // {}) | keys),
      co_authored_setting: (if has("includeCoAuthoredBy") then .includeCoAuthoredBy else null end)}' "$root/.claude/settings.json")"
  out="$(jq -c --argjson ai "$ai_md" --argjson docs "$docs_md" --argjson s "$settings" \
    --argjson agents "$(md_list .claude/agents '*.md')" --argjson cmds "$(md_list .claude/commands '*.md')" \
    --argjson skills "$(md_list .claude/skills SKILL.md)" --argjson prompts "$(md_list .claude/prompts '*.md')" '
    . + {".ai": $ai, docs: $docs,
         ".claude": {agents: $agents, commands: $cmds, skills: $skills, prompts: $prompts,
                     settings_keys: ($s.settings_keys // []), hooks: ($s.hooks // []),
                     deny_rules: ($s.deny_rules // 0),
                     enabled_mcp: ($s.enabled_mcp // null),
                     enabled_plugins: ($s.enabled_plugins // []),
                     co_authored_setting: (if ($s | has("co_authored_setting")) then $s.co_authored_setting else null end)}}' <<<"$out")"
  local codex agents_skills
  codex="null"
  [ -d "$root/.codex" ] && codex="$(find "$root/.codex" -mindepth 1 2>/dev/null | while IFS= read -r f; do rel "$f"; done | sort | head -$MAX_LIST | lines_to_json)"
  if [ -L "$root/.agents/skills" ]; then
    agents_skills="$(jq -n -c --arg t "$(readlink "$root/.agents/skills")" '{symlink_to: $t}')"
  else
    agents_skills="$(md_list .agents/skills SKILL.md)"
  fi
  local mcp gi
  mcp="null"
  [ -f "$root/.mcp.json" ] && mcp="$(jq -c '(.mcpServers // {}) | keys' "$root/.mcp.json" 2>/dev/null || echo null)"
  gi="$( [ -f "$root/.gitignore" ] && grep -vE '^[[:space:]]*(#|$)' "$root/.gitignore" | sed 's/[[:space:]]*$//' )"
  local githooks cother hooks_path
  hooks_path="$(git -C "$root" config core.hooksPath 2>/dev/null)"
  githooks="$( { [ -n "$hooks_path" ] && echo "core.hooksPath=$hooks_path"; for d in .githooks .husky; do [ -d "$root/$d" ] && find "$root/$d" -maxdepth 1 -type f ! -name '*.sample' 2>/dev/null | while IFS= read -r f; do rel "$f"; done; done; } | lines_to_json)"
  cother="$( [ -d "$root/.claude" ] && find "$root/.claude" -mindepth 1 -maxdepth 1 ! -name agents ! -name commands ! -name skills ! -name prompts ! -name settings.json ! -name settings.local.json ! -name .DS_Store 2>/dev/null | while IFS= read -r f; do rel "$f"; done | lines_to_json || echo '[]')"
  local agents_ignored=false
  git -C "$root" check-ignore -q --no-index .agents/skills 2>/dev/null && agents_ignored=true
  jq -c --argjson codex "$codex" --argjson as "$agents_skills" --argjson mcp "$mcp" \
    --argjson githooks "$githooks" --argjson cother "$cother" --argjson agign "$agents_ignored" \
    --argjson gi "$(printf '%s\n' "$gi" | grep -E '^[/!]*\.ai' | lines_to_json)" \
    --argjson env "$(printf '%s\n' "$gi" | grep -qE '^/?\.env' && echo true || echo false)" \
    --argjson pipe "$(pipeline_docs_json)" '
    . + {".codex": $codex, ".agents/skills": $as, agents_ignored: $agign, githooks: $githooks, claude_other: $cother}
    | .pipeline_docs = $pipe
    | .orchestration = (((.[".claude"].agents // []) | length > 0) or ((.[".claude"].commands // []) | length > 0)
                        or (.pipeline_docs | length > 0) or ((.[".codex"] // []) | any(test("agents/"))))
    | . + {mcp_servers: $mcp, gitignore_ai: $gi, gitignore_has_env: $env}' <<<"$out"
}

secrets_json() {
  walk "$root" 3 f | while IFS= read -r f; do
    n="$(basename "$f")"
    printf '%s\n' "$n" | grep -qiE '(^\.env(\..+)?$)|(\.(p12|pem|key|mobileprovision|keystore|jks)$)|secret|credential|^id_rsa' || continue
    printf '%s\n' "$n" | grep -qiE "$CODE_EXT_RE|\.(md|sh|json)$|sample|example|dist" && continue
    rel "$f"
  done | sort | head -40 | lines_to_json
}

# doc_language - "pl" when the docs contain many UTF-8 lead bytes \304 and \305 (most Polish
# letters with diacritics), otherwise "en"; null without CLAUDE.md or README.
doc_language() {
  local n
  n="$(cat "$root/CLAUDE.md" "$root/README.md" "$root/Readme.md" "$root/docs/project-context.md" "$root/.ai/README.md" 2>/dev/null | head -c 60000 | LC_ALL=C tr -cd '\304\305' | wc -c | tr -d ' ')"
  if [ -z "$(cat "$root/CLAUDE.md" "$root/README.md" "$root/Readme.md" 2>/dev/null | head -c 1)" ]; then echo null
  elif [ "$n" -gt 20 ]; then echo '"pl"'
  else echo '"en"'; fi
}

# MARK: assembly

layout="$(layout_json)"
result="$(jq -n -c \
  --arg root "$root" --arg name "$(basename "$root")" --argjson lang "$(doc_language)" \
  --argjson git "$(git_json)" --argjson stacks "$(stacks_json)" --argjson cmds "$(commands_json)" \
  --argjson tooling "$(tooling_json)" --argjson layout "$layout" --argjson mods "$(modules_json)" \
  --argjson tests "$(tests_json)" --argjson ai "$(ai_json)" --argjson secrets "$(secrets_json)" '
  {root: $root, name: $name, doc_language_guess: $lang,
   source_files: ($layout | map(.source) | add // 0),
   git: $git, stacks: $stacks, commands: $cmds, tooling: $tooling,
   layout: ($layout | map(del(.source))), module_candidates: $mods, tests: $tests,
   ai_setup: $ai, secret_like_files: $secrets}')"

if [ "$pretty" -eq 1 ]; then jq . <<<"$result"; else printf '%s\n' "$result"; fi

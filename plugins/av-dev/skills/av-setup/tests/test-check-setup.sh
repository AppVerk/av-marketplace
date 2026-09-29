#!/bin/bash
# Black box tests for check_setup.sh.
# Builds a small repo with roles, overlays and role skills in mktemp.
# Overlays use Polish headers (aliases); the "English headers" block checks the canonical names.
set -u
CS="$(cd "$(dirname "$0")/.." && pwd)/scripts/check_setup.sh"
REFS="$(cd "$(dirname "$0")/../.." && pwd)/av-docs-sync/scripts/check_refs.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { grep -qF -- "$2" "$1" && ok || fail "$3"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$3" || ok; }

R="$TMP/repo x"
git init -q "$R" && git -C "$R" config user.email t@t && git -C "$R" config user.name t
mkdir -p "$R/src/Data" "$R/src/UI" "$R/src/Shared" "$R/My Dir/Sub Dir" "$R/Other/Lib" "$R/Other/Tools" "$R/generated" \
  "$R/scripts" "$R/.ai/overlays" "$R/.claude/skills/app-data" "$R/.claude/skills/app-ui"
for f in src/Data/A.py src/UI/V.ts src/UI/a.generated.ts src/Shared/Both.kt src/Q1.py src/Q12.py \
  "My Dir/Sub Dir/x.ts" Other/Lib/y.php Other/Lib/z.java Other/Tools/w.js generated/P.php; do
  printf 'x\n' >"$R/$f"
done
printf '#!/bin/bash\n' >"$R/scripts/t.sh"

cat >"$R/.ai/av.config.json" <<'EOF'
{
  "version": 1,
  "roles": [
    {"name": "ui", "skill": "app-ui", "order": 2, "globs": ["src/UI/**", "src/Shared/**", "My Dir/**", "src/Nope/**", "src/{A,B}/**"]},
    {"name": "data", "skill": "app-data", "order": 1, "globs": ["src/Data/**", "src/Shared/**", "src/?1.py"]},
    {"name": "net", "skill": "app-net", "order": 3, "globs": ["Net/**"]},
    {"name": "plug", "skill": "vendor:php-developer", "order": 3, "globs": ["Plug/**"]}
  ],
  "generatedPaths": ["generated/**", "**/*.generated.ts"],
  "unownedPaths": ["scripts/**"],
  "validation": {
    "commands": {"lint": {"run": "true"}, "unit": {"run": "true"}},
    "gates": {"quick": ["lint", "unit"]}
  }
}
EOF

cat >"$R/.claude/skills/app-data/SKILL.md" <<'EOF'
---
name: app-data
---
## File scope
`src/Data/**`, `src/Shared/**`, `src/?1.py`
Run `gate.sh --only unit` or `gate.sh --only ghost`.
EOF
printf -- '---\nname: app-ui\n---\n## File scope\nRole `ui` in `.ai/av.config.json`.\n' >"$R/.claude/skills/app-ui/SKILL.md"

printf '## Pliki do przeczytania przed planem\nx\n## Obowiązkowe sekcje planu\nx\nScript `scripts/absent_tool.sh`.\n' >"$R/.ai/overlays/av-plan.md"
printf '## Role\nRoles in `.ai/av.config.json`.\n## Obowiązkowe kroki\nx\n## Wybór trybu\nx\n## Bramki per etap\n`gate.sh --gate quick`, `gate.sh --gate nope`, `gate.sh --only lint,unit`.\n' >"$R/.ai/overlays/av-implement.md"
printf '## Dobór bramki\nx\n' >"$R/.ai/overlays/av-verify.md"
printf '## Mapa kod -> docs\nx\n## Znane fałszywe nazwy\n- `Foo`\n' >"$R/.ai/overlays/av-docs-sync.md"
git -C "$R" add -A && git -C "$R" commit -qm init

# MARK: check
out="$TMP/out.txt"
bash "$CS" --root "$R" >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "exit code with ERROR: $rc"
has "$out" "SETUP_OVERLAY_MISSING .ai/overlays/av-review.md" "missing overlay av-review"
has "$out" 'SETUP_OVERLAY_SECTION .ai/overlays/av-verify.md: Interpreting results (pl: Interpretacja wyników)' "missing section av-verify"
hasnt "$out" 'SETUP_OVERLAY_SECTION .ai/overlays/av-verify.md: Gate selection' "Polish alias Dobór bramki accepted"
hasnt "$out" 'SETUP_OVERLAY_SECTION .ai/overlays/av-implement.md' "av-implement sections complete"
has "$out" "SETUP_ROLE_SKILL_MISSING net .claude/skills/app-net/SKILL.md" "missing role skill"
hasnt "$out" "php-developer" "plugin skill skipped"
has "$out" "SETUP_ROLE_OVERLAP data,ui 1: src/Shared/Both.kt" "role overlap"
has "$out" "SETUP_ROLE_EMPTY ui src/Nope/**" "empty glob"
has "$out" "SETUP_ROLE_EMPTY ui src/{A,B}/** (braces" "hint for braces"
hasnt "$out" "SETUP_ROLE_EMPTY ui My Dir/**" "glob with a space matches"
hasnt "$out" "SETUP_ROLE_EMPTY data src/?1.py" "glob with a question mark"
has "$out" "SETUP_UNOWNED_DIR Other 3 files without owner: Other/Lib 2, Other/Tools 1" "directory without owner"
has "$out" "SETUP_UNOWNED_DIR src 1 files without owner: src 1" "file src/Q12.py without owner"
hasnt "$out" "SETUP_UNOWNED_DIR generated" "generated skipped"
has "$out" "SETUP_GLOB_COPY .claude/skills/app-data/SKILL.md copies 3" "glob copy in role skill"
hasnt "$out" "SETUP_GLOB_COPY .claude/skills/app-ui" "skill linking to the config"
has "$out" "SETUP_GATE_UNKNOWN .ai/overlays/av-implement.md:8 --gate nope" "unknown gate"
has "$out" "SETUP_GATE_UNKNOWN .claude/skills/app-data/SKILL.md:6 --only ghost" "unknown command"
hasnt "$out" "--gate quick" "known gate"
hasnt "$out" "--only lint" "known command from a list"
hasnt "$out" "--only unit" "known command"
if [ -f "$REFS" ]; then
  has "$out" "SETUP_REF_MISSING .ai/overlays/av-plan.md:5 scripts/absent_tool.sh" "missing script"
else
  has "$out" "SETUP_REF_SKIPPED" "no check_refs"
fi
tail -1 "$out" | grep -qE '^CHECKED [0-9]+ ERRORS [0-9]+ WARNINGS [0-9]+$' && ok || fail "summary line"

# MARK: owner
own="$TMP/own.txt"
bash "$CS" --root "$R" --owner src/Data/deep/New.py generated/P.php scripts/t.sh README.md "My Dir/Sub Dir/x.ts" \
  src/Q1.py src/Q12.py "$R/src/UI/V.ts" src/UI/b.generated.ts src/Shared/Both.kt >"$own" 2>"$TMP/own.err"
rc=$?
[ "$rc" -eq 0 ] && ok || fail "owner: code $rc"
has "$own" "OWNER src/Data/deep/New.py data" "owner: new role file"
has "$own" "OWNER generated/P.php generated" "owner: generated"
has "$own" "OWNER scripts/t.sh unowned" "owner: unowned"
has "$own" "OWNER README.md implementer" "owner: implementer"
has "$own" "OWNER My Dir/Sub Dir/x.ts ui" "owner: path with a space"
has "$own" "OWNER src/Q1.py data" "owner: question mark"
has "$own" "OWNER src/Q12.py implementer" "owner: question mark is one character"
has "$own" "OWNER src/UI/V.ts ui" "owner: absolute path"
has "$own" "OWNER src/UI/b.generated.ts generated" "owner: **/ inside a glob"
has "$own" "OWNER src/Shared/Both.kt data" "owner: overlap picks the role by order"
has "$TMP/own.err" "role overlap" "owner: overlap warning"

# MARK: clean setup
C="$TMP/clean"
cp -R "$R" "$C"
printf '## Jak sprawdzać osie\nx\n' >"$C/.ai/overlays/av-review.md"
printf '## Dobór bramki\nx\n## Interpretacja wyników\nx\n' >"$C/.ai/overlays/av-verify.md"
printf '## Pliki do przeczytania przed planem\nx\n## Obowiązkowe sekcje planu\nx\n' >"$C/.ai/overlays/av-plan.md"
printf -- '---\nname: app-data\n---\n## File scope\nRole `data` in the config.\n' >"$C/.claude/skills/app-data/SKILL.md"
sed -i '' 's/, `gate.sh --gate nope`//' "$C/.ai/overlays/av-implement.md" 2>/dev/null || sed -i 's/, `gate.sh --gate nope`//' "$C/.ai/overlays/av-implement.md"
jq '.roles = [{"name": "data", "skill": "app-data", "order": 1, "globs": ["src/**"]}, {"name": "ui", "skill": "app-ui", "order": 1, "globs": ["My Dir/**", "Other/**"]}]' \
  "$R/.ai/av.config.json" >"$C/.ai/av.config.json"
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_LOCAL_IGNORE add .ai/av.config.json.local to .gitignore" "local: no entry in .gitignore"
printf '.ai/av.config.json.local\n' >>"$C/.gitignore"
bash "$CS" --root "$C" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || { fail "clean setup: code $rc"; cat "$out" >&2; }
has "$out" "ERRORS 0 WARNINGS 0" "clean setup without findings"
hasnt "$out" "SETUP_LOCAL_USED" "local: info without a file"

# MARK: local override
printf '{"roles": null}\n' >"$C/.ai/av.config.json.local"
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_LOCAL_USED .ai/av.config.json.local" "local: no info about the override"
has "$out" "SETUP_ROLES_NONE" "local: check did not use the effective config"
bash "$CS" --root "$C" --no-local >"$out"; rc=$?
hasnt "$out" "SETUP_ROLES_NONE" "local: --no-local used the override"
bash "$CS" --root "$C" --owner src/Data/A.py >"$out"; rc=$?
has "$out" "OWNER src/Data/A.py implementer" "local: --owner without the effective config"
hasnt "$out" "SETUP_LOCAL_USED" "local: --owner prints the info"
git -C "$C" add -f .ai/av.config.json.local
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_LOCAL_TRACKED" "local: no tracking error"
[ "$rc" -eq 1 ] && ok || fail "local tracked: code $rc"
git -C "$C" rm -q --cached .ai/av.config.json.local
printf '{bad' >"$C/.ai/av.config.json.local"
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_CONFIG_INVALID .ai/av.config.json.local" "local: bad JSON"
rm -f "$C/.ai/av.config.json.local"

# MARK: English headers
E="$TMP/english"
cp -R "$C" "$E"
printf '## Files to read before planning\nx\n## Required plan sections\nx\n' >"$E/.ai/overlays/av-plan.md"
printf '## Roles\nRoles in `.ai/av.config.json`.\n## Required steps\nx\n## Mode selection\nx\n## Gates per stage\n`gate.sh --gate quick`, `gate.sh --only lint,unit`.\n' >"$E/.ai/overlays/av-implement.md"
printf '## How to check the axes\nx\n' >"$E/.ai/overlays/av-review.md"
printf '## Gate selection\nx\n## Interpreting results (and flaky tests)\nx\n' >"$E/.ai/overlays/av-verify.md"
printf '## Code -> docs map\nx\n## Known false names\n- `Foo`\n' >"$E/.ai/overlays/av-docs-sync.md"
bash "$CS" --root "$E" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || { fail "English headers: code $rc"; cat "$out" >&2; }
has "$out" "ERRORS 0 WARNINGS 0" "English headers without findings"
printf '## Gate selection\nx\n' >"$E/.ai/overlays/av-verify.md"
printf '## Code -> docs map\nx\n' >"$E/.ai/overlays/av-docs-sync.md"
bash "$CS" --root "$E" >"$out"; rc=$?
has "$out" "SETUP_OVERLAY_SECTION .ai/overlays/av-verify.md: Interpreting results (pl: Interpretacja wyników)" "English: missing section av-verify"
has "$out" "SETUP_OVERLAY_SECTION .ai/overlays/av-docs-sync.md: Known false names (pl: Znane fałszywe nazwy)" "English: missing section av-docs-sync"
hasnt "$out" "Gate selection" "English: Gate selection accepted"
hasnt "$out" "Code -> docs map" "English: Code -> docs map accepted"

# MARK: exclusions
X="$TMP/exclusions"
cp -R "$C" "$X"
mkdir -p "$X/scripts"
printf 'x\n' >"$X/generated/Keep.php"; printf '#!/bin/bash\n' >"$X/scripts/keep.sh"
git -C "$X" add -A && git -C "$X" commit -qm exclusions
jq '.roles = [
      {"name": "data", "skill": "app-data", "order": 1, "globs": ["src/**", "!src/UI/**", "!src/Shared/Both.kt", "!src/Nothing/**", "My Dir/**", "!My Dir/**"]},
      {"name": "ui", "skill": "app-ui", "order": 2, "globs": ["src/UI/**", "src/Shared/Both.kt", "My Dir/**", "Other/**", "!Other/Tools/**"]}]
    | .generatedPaths = ["generated/**", "**/*.generated.ts", "!generated/Keep.php"]
    | .unownedPaths = ["scripts/**", "!scripts/keep.sh"]' "$C/.ai/av.config.json" >"$X/.ai/av.config.json"
printf -- '---\nname: app-ui\n---\n## File scope\n`src/UI/**`, `src/Shared/Both.kt`, `Other/Tools/**`\n' >"$X/.claude/skills/app-ui/SKILL.md"
printf 'Scope: `src/UI/**`, `src/Shared/Both.kt`.\n' >>"$X/.ai/overlays/av-implement.md"
bash "$CS" --root "$X" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || { fail "exclusions: code $rc"; cat "$out" >&2; }
has "$out" "ERRORS 0 " "exclusions: errors reported"
hasnt "$out" "SETUP_ROLE_OVERLAP" "exclusions: excluded file counted as overlap"
hasnt "$out" "SETUP_ROLE_EMPTY data !" "exclusions: exclusion reported as an empty glob"
has "$out" "SETUP_ROLE_EMPTY data My Dir/**" "exclusions: fully excluded include not reported as empty"
hasnt "$out" "SETUP_ROLE_EMPTY ui" "exclusions: include of the other role reported as empty"
has "$out" "SETUP_UNOWNED_DIR Other 1 files without owner: Other/Tools 1" "exclusions: excluded directory not unowned"
hasnt "$out" "SETUP_UNOWNED_DIR src" "exclusions: src without owner"
has "$out" "SETUP_GLOB_COPY .claude/skills/app-ui/SKILL.md copies 3 globs of role ui" "exclusions: copied exclusion not counted"
hasnt "$out" "SETUP_GLOB_COPY .ai/overlays/av-implement.md" "exclusions: include and exclusion of one pattern counted twice"
bash "$CS" --root "$X" --owner src/UI/V.ts src/Shared/Both.kt src/Data/A.py src/UI/new/N.swift Other/Lib/y.php Other/Tools/w.js \
  "My Dir/Sub Dir/x.ts" generated/P.php generated/Keep.php scripts/t.sh scripts/keep.sh >"$own" 2>"$TMP/own.err"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "exclusions owner: code $rc"
has "$own" "OWNER src/UI/V.ts ui" "exclusions owner: excluded directory"
has "$own" "OWNER src/UI/new/N.swift ui" "exclusions owner: new file in an excluded directory"
has "$own" "OWNER src/Shared/Both.kt ui" "exclusions owner: excluded file"
has "$own" "OWNER src/Data/A.py data" "exclusions owner: included file"
has "$own" "OWNER Other/Lib/y.php ui" "exclusions owner: include next to an exclusion"
has "$own" "OWNER Other/Tools/w.js implementer" "exclusions owner: excluded file without another owner"
has "$own" "OWNER My Dir/Sub Dir/x.ts ui" "exclusions owner: include excluded in the first role"
has "$own" "OWNER generated/P.php generated" "exclusions owner: generated"
has "$own" "OWNER generated/Keep.php implementer" "exclusions owner: generatedPaths exclusion"
has "$own" "OWNER scripts/t.sh unowned" "exclusions owner: unowned"
has "$own" "OWNER scripts/keep.sh implementer" "exclusions owner: unownedPaths exclusion"
hasnt "$TMP/own.err" "role overlap" "exclusions owner: overlap warning"
jq '.roles += [{"name": "neg", "skill": "app-ui", "order": 3, "globs": ["!src/**", "!Other/**"]}]' "$X/.ai/av.config.json" >"$TMP/neg.json"
bash "$CS" --root "$X" --config "$TMP/neg.json" >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "exclusions only: code $rc"
has "$out" "SETUP_ROLE_INVALID roles[2] neg has only exclusions (!)" "exclusions only: role accepted"

# MARK: source files in any language
N="$TMP/languages"
cp -R "$C" "$N"
mkdir -p "$N/svc/api" "$N/web/ui" "$N/win" "$N/assets" "$N/data" "$N/pkg" "$N/notes" "$N/handbook" "$N/.github/workflows"
printf 'package main\n' >"$N/svc/main.go"
printf 'class Handler; end' >"$N/svc/api/handler.rb"
printf '<template></template>\n' >"$N/web/App.vue"
printf 'export const B = 1\n' >"$N/web/ui/Button.tsx"
printf '# Web\n' >"$N/web/README.md"
printf 'class Form {}\r\n' >"$N/win/Form.cs"
printf '\211PNG\r\n\032\n\000\000\000\015IHDR\000' >"$N/assets/logo.png"
head -c 300000 </dev/zero | tr '\0' 'a' >"$N/data/big.json"
: >"$N/pkg/empty.go"
printf '# Notes\n' >"$N/notes/README.md"; printf 'x\n' >"$N/notes/a.markdown"; printf 'x\n' >"$N/notes/b.mdx"
printf 'x\n' >"$N/handbook/guide.txt"; printf 'package doc\n' >"$N/handbook/snippet.go"
printf 'on: push\n' >"$N/.github/workflows/ci.yml"
git -C "$N" add -A && git -C "$N" commit -qm languages
jq '.docs = {"root": "./handbook/"}' "$C/.ai/av.config.json" >"$N/.ai/av.config.json"
bash "$CS" --root "$N" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || { fail "languages: code $rc"; cat "$out" >&2; }
has "$out" "SETUP_UNOWNED_DIR svc 2 files without owner: svc 1, svc/api 1" "languages: go and rb (no final newline) counted"
has "$out" "SETUP_UNOWNED_DIR web 2 files without owner: web 1, web/ui 1" "languages: vue and tsx counted, markdown skipped"
has "$out" "SETUP_UNOWNED_DIR win 1 files without owner: win 1" "languages: CRLF text counted"
hasnt "$out" "SETUP_UNOWNED_DIR assets" "languages: binary counted"
hasnt "$out" "SETUP_UNOWNED_DIR data" "languages: text file over 256 KiB counted"
hasnt "$out" "SETUP_UNOWNED_DIR pkg" "languages: empty file counted"
hasnt "$out" "SETUP_UNOWNED_DIR notes" "languages: markdown counted"
hasnt "$out" "SETUP_UNOWNED_DIR handbook" "languages: docs.root counted"
hasnt "$out" "SETUP_UNOWNED_DIR .github" "languages: top-level dot directory counted"
has "$out" "ERRORS 0 WARNINGS 3" "languages: unexpected findings"
jq '.generatedPaths += ["svc/**"] | .unownedPaths += ["web/**"] | .docs = {}' "$N/.ai/av.config.json" >"$TMP/lang.json"
bash "$CS" --root "$N" --config "$TMP/lang.json" >"$out"; rc=$?
hasnt "$out" "SETUP_UNOWNED_DIR svc" "languages: generatedPaths counted"
hasnt "$out" "SETUP_UNOWNED_DIR web" "languages: unownedPaths counted"
has "$out" "SETUP_UNOWNED_DIR handbook 2 files without owner: handbook 2" "languages: handbook outside docs.root skipped"

# MARK: no roles, config errors, usage
jq 'del(.roles)' "$R/.ai/av.config.json" >"$TMP/noroles.json"
bash "$CS" --root "$C" --config "$TMP/noroles.json" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "no roles: code $rc"
has "$out" "SETUP_ROLES_NONE" "no roles: warning"
bash "$CS" --root "$C" --config "$TMP/noroles.json" --owner src/UI/V.ts generated/P.php >"$own"
has "$own" "OWNER src/UI/V.ts implementer" "no roles: implementer"
has "$own" "OWNER generated/P.php generated" "no roles: generated still works"

printf '{bad json' >"$TMP/bad.json"
bash "$CS" --root "$C" --config "$TMP/bad.json" >"$out"; rc=$?
[ "$rc" -eq 1 ] && grep -q SETUP_CONFIG_INVALID "$out" && ok || fail "bad JSON: code $rc"
bash "$CS" --root "$C" --config "$TMP/missing.json" >"$out"; rc=$?
[ "$rc" -eq 1 ] && grep -q SETUP_CONFIG_MISSING "$out" && ok || fail "missing config: code $rc"
bash "$CS" --root "$C" --unknown >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "unknown option: code $rc"
bash "$CS" --root "$C" --owner >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "--owner without files: code $rc"
bash "$CS" --root "$TMP" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "root without git: code $rc"

# MARK: config fields (moved from gate.sh; they never stop a gate)
F="$TMP/fields"
git init -q "$F" && mkdir -p "$F/.ai"
jq -n '{version: 1, validation: {commands: {ok: {run: "true"}}, gates: {quick: ["ok"]}},
        agents: {models: {plan: "inherit", implement: "opus", review: "sonnet", verify: "fable"}},
        git: {commit: "on-request", push: "never"},
        roles: [{name: "data", skill: "backend-data", order: 1, globs: ["src/api/**", "src/db/*.py", "!src/api/generated/**"]},
                {name: "ui", skill: "web-ui", order: 2, globs: ["src/ui/**"]}],
        generatedPaths: ["vendor/**"], unownedPaths: ["scripts/**"]}' >"$F/.ai/good.json"
out="$TMP/fields.txt"
bash "$CS" --root "$F" --config "$F/.ai/good.json" --config-only >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "fields: valid config code $rc: $(cat "$out")"
hasnt "$out" "SETUP_CONFIG_FIELD" "fields: valid config reported"
tail -1 "$out" | grep -qE '^CHECKED [0-9]+ ERRORS 0 WARNINGS [0-9]+$' && ok || fail "fields: --config-only summary: $(tail -1 "$out")"
hasnt "$out" "SETUP_OVERLAY" "fields: --config-only ran the overlay checks"
field_case() {
  local filter="$1" expect="$2" desc="$3" r
  jq "$filter" "$F/.ai/good.json" >"$F/.ai/bad.json"
  bash "$CS" --root "$F" --config "$F/.ai/bad.json" --config-only >"$out"; r=$?
  if grep -qF -- "SETUP_CONFIG_FIELD $expect" "$out" && [ "$r" -eq 1 ]; then ok; else fail "fields $desc: code $r, output: $(cat "$out")"; fi
}
field_case '.agents.models.verify = "gpt4"' "agents.models.verify: invalid value \"gpt4\"" "model not on the list"
field_case '.agents.models.implement = "opusplan"' "agents.models.implement: invalid value \"opusplan\"" "opusplan is not a slot model"
field_case '.agents.models.review = "haiku"' "agents.models.review: a Haiku model cannot do review" "review haiku"
field_case '.agents.models.review = "claude-haiku-4-5"' "agents.models.review: a Haiku model cannot do review" "review with a full Haiku id"
field_case '.agents.models.planReview = "haiku"' "agents.models.planReview: a Haiku model cannot do review" "planReview haiku"
field_case '.agents.models = "opus"' "agents.models: expected an object" "models not an object"
field_case '.agents.models.review = {"provider": "claude", "model": "opus"}' "agents.models.review: the object form {provider, model, effort} was removed" "object slot"
field_case '.agents.models.plan = 5' "agents.models.plan: invalid value 5" "slot as a number"
field_case '.agents.crossVendor = false' "agents.crossVendor: removed with Codex slots" "crossVendor left in the config"
field_case '.agents.timeoutSec = 3600' "agents.timeoutSec: removed with Codex slots" "timeoutSec left in the config"
field_case '.git.commit = "always"' "git.commit: invalid value \"always\"" "git.commit"
field_case '.git.push = "force"' "git.push: invalid value \"force\"" "git.push"
field_case '.roles[0].globs = ["src/{a,b}/**"]' "roles[0].globs: glob \"src/{a,b}/**\" has a curly brace" "glob with braces"
field_case '.roles[1].globs = ["!src/ui/legacy/**"]' "roles[1].globs: only exclusions (!); add at least one glob without !" "role with only exclusions"
field_case '.roles[1].globs = ["src/ui/**", "!"]' "roles[1].globs: exclusion \"!\" has no pattern" "empty exclusion"
field_case '.roles[1].order = 1.5' "roles[1].order: expected an integer" "fractional order"
field_case '.roles[0].globs = []' "roles[0].globs: expected a non-empty array" "empty globs"
field_case '.roles[0].globs = ["a", 3]' "roles[0].globs: element 3 is not a string" "glob not a string"
field_case 'del(.roles[1].skill)' "roles[1].skill: expected a non-empty string" "skill missing"
field_case '.roles[0].name = 7' "roles[0].name: expected a non-empty string" "name not a string"
field_case '.roles = {"a": 1}' "roles: expected an array of objects" "roles not an array"
field_case '.generatedPaths = "vendor/**"' "generatedPaths: expected an array of strings" "generatedPaths"
field_case '.unownedPaths = [1]' "unownedPaths: expected an array of strings" "unownedPaths"
jq '.agents.models = {"plan": "opus", "planReview": "sonnet", "implement": "claude-opus-5-5", "review": "fable", "verify": "claude-haiku-4-5"}' "$F/.ai/good.json" >"$F/.ai/slots.json"
bash "$CS" --root "$F" --config "$F/.ai/slots.json" --config-only >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "fields: valid slot models rejected: $(cat "$out")"
printf '{"agents": {"models": {"review": "haiku"}}}\n' >"$F/.ai/good.json.local"
bash "$CS" --root "$F" --config "$F/.ai/good.json" --config-only >"$out"; rc=$?
has "$out" "SETUP_CONFIG_FIELD agents.models.review" "fields: not checked on the effective config"
bash "$CS" --root "$F" --config "$F/.ai/good.json" --config-only --no-local >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "fields: --no-local used the override ($rc)"
rm -f "$F/.ai/good.json.local"
jq '.agents.models.review = "haiku"' "$F/.ai/good.json" >"$F/.ai/bad.json"
bash "$CS" --root "$F" --config "$F/.ai/bad.json" --owner src/api/x.py >"$out"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "OWNER src/api/x.py data" "fields: --owner stopped by a field outside roles" || fail "fields: --owner code $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

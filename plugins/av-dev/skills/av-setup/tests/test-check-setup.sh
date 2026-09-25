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
mkdir -p "$R/App/Data" "$R/App/UI" "$R/App/Shared" "$R/My Dir/Sub Dir" "$R/Other/Lib" "$R/Other/Tools" "$R/Pods" \
  "$R/scripts" "$R/.ai/overlays" "$R/.claude/skills/app-data" "$R/.claude/skills/app-ui"
for f in App/Data/A.swift App/UI/V.swift App/UI/a.generated.swift App/Shared/Both.swift App/Q1.swift App/Q12.swift \
  "My Dir/Sub Dir/x.swift" Other/Lib/y.swift Other/Lib/z.swift Other/Tools/w.swift Pods/P.swift; do
  printf 'import UIKit\n' >"$R/$f"
done
printf '#!/bin/bash\n' >"$R/scripts/t.sh"

cat >"$R/.ai/av.config.json" <<'EOF'
{
  "version": 1,
  "roles": [
    {"name": "ui", "skill": "app-ui", "order": 2, "globs": ["App/UI/**", "App/Shared/**", "My Dir/**", "App/Nope/**", "App/{A,B}/**"]},
    {"name": "data", "skill": "app-data", "order": 1, "globs": ["App/Data/**", "App/Shared/**", "App/?1.swift"]},
    {"name": "net", "skill": "app-net", "order": 3, "globs": ["Net/**"]},
    {"name": "plug", "skill": "vendor:php-developer", "order": 3, "globs": ["Plug/**"]}
  ],
  "generatedPaths": ["Pods/**", "**/*.generated.swift"],
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
`App/Data/**`, `App/Shared/**`, `App/?1.swift`
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
has "$out" "SETUP_ROLE_OVERLAP data,ui 1: App/Shared/Both.swift" "role overlap"
has "$out" "SETUP_ROLE_EMPTY ui App/Nope/**" "empty glob"
has "$out" "SETUP_ROLE_EMPTY ui App/{A,B}/** (braces" "hint for braces"
hasnt "$out" "SETUP_ROLE_EMPTY ui My Dir/**" "glob with a space matches"
hasnt "$out" "SETUP_ROLE_EMPTY data App/?1.swift" "glob with a question mark"
has "$out" "SETUP_UNOWNED_DIR Other 3 files without owner: Other/Lib 2, Other/Tools 1" "directory without owner"
has "$out" "SETUP_UNOWNED_DIR App 1 files without owner: App 1" "file App/Q12.swift without owner"
hasnt "$out" "SETUP_UNOWNED_DIR Pods" "generated skipped"
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
bash "$CS" --root "$R" --owner App/Data/deep/New.swift Pods/P.swift scripts/t.sh README.md "My Dir/Sub Dir/x.swift" \
  App/Q1.swift App/Q12.swift "$R/App/UI/V.swift" App/UI/b.generated.swift App/Shared/Both.swift >"$own" 2>"$TMP/own.err"
rc=$?
[ "$rc" -eq 0 ] && ok || fail "owner: code $rc"
has "$own" "OWNER App/Data/deep/New.swift data" "owner: new role file"
has "$own" "OWNER Pods/P.swift generated" "owner: generated"
has "$own" "OWNER scripts/t.sh unowned" "owner: unowned"
has "$own" "OWNER README.md implementer" "owner: implementer"
has "$own" "OWNER My Dir/Sub Dir/x.swift ui" "owner: path with a space"
has "$own" "OWNER App/Q1.swift data" "owner: question mark"
has "$own" "OWNER App/Q12.swift implementer" "owner: question mark is one character"
has "$own" "OWNER App/UI/V.swift ui" "owner: absolute path"
has "$own" "OWNER App/UI/b.generated.swift generated" "owner: **/ inside a glob"
has "$own" "OWNER App/Shared/Both.swift data" "owner: overlap picks the role by order"
has "$TMP/own.err" "role overlap" "owner: overlap warning"

# MARK: clean setup
C="$TMP/clean"
cp -R "$R" "$C"
printf '## Jak sprawdzać osie\nx\n' >"$C/.ai/overlays/av-review.md"
printf '## Dobór bramki\nx\n## Interpretacja wyników\nx\n' >"$C/.ai/overlays/av-verify.md"
printf '## Pliki do przeczytania przed planem\nx\n## Obowiązkowe sekcje planu\nx\n' >"$C/.ai/overlays/av-plan.md"
printf -- '---\nname: app-data\n---\n## File scope\nRole `data` in the config.\n' >"$C/.claude/skills/app-data/SKILL.md"
sed -i '' 's/, `gate.sh --gate nope`//' "$C/.ai/overlays/av-implement.md" 2>/dev/null || sed -i 's/, `gate.sh --gate nope`//' "$C/.ai/overlays/av-implement.md"
jq '.roles = [{"name": "data", "skill": "app-data", "order": 1, "globs": ["App/**"]}, {"name": "ui", "skill": "app-ui", "order": 1, "globs": ["My Dir/**", "Other/**"]}]' \
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
bash "$CS" --root "$C" --owner App/Data/A.swift >"$out"; rc=$?
has "$out" "OWNER App/Data/A.swift implementer" "local: --owner without the effective config"
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

# MARK: integrations
miro_cfg() { jq --argjson m "$1" '.integrations = {miro: $m}' "$C/.ai/av.config.json" >"$TMP/miro.json"; bash "$CS" --root "$C" --config "$TMP/miro.json" >"$out"; }
miro_cfg '{"via":"api"}'
has "$out" "SETUP_INTEGRATION_INVALID integrations.miro.via" "miro: via api passed"
miro_cfg '{"boards":{"x":"http://example.com"}}'
has "$out" "SETUP_INTEGRATION_INVALID integrations.miro.boards" "miro: bad address passed"
miro_cfg '"browser"'
has "$out" "SETUP_INTEGRATION_INVALID integrations.miro: " "miro: string passed"
miro_cfg '{"via":"browser","boards":{"docs":"https://miro.com/app/board/abc=/"}}'
hasnt "$out" "SETUP_INTEGRATION_INVALID" "miro: valid entry rejected"
has "$out" "SETUP_TEMPLATE_MISSING .ai/miro.md" "miro: no warning about docs"
has "$out" "SETUP_TEMPLATE_MISSING .ai/scripts/miro-frames.js" "miro: no warning about the script"
mkdir -p "$C/.ai/scripts"; : >"$C/.ai/miro.md"; : >"$C/.ai/scripts/miro-frames.js"
miro_cfg '{"via":"browser"}'
hasnt "$out" "SETUP_TEMPLATE_MISSING" "miro: warning despite files"
miro_cfg '{"via":"mcp"}'
hasnt "$out" "SETUP_INTEGRATION" "miro: mcp requires no files"
rm -rf "$C/.ai/miro.md" "$C/.ai/scripts"

# MARK: templates: generic mechanism
TD="$TMP/templates"; mkdir -p "$TD/demo"
cat >"$TD/demo/template.json" <<'EOF2'
{"name": "demo", "applies": ".integrations.demo == true",
 "validate": "if (.integrations.demo // null) == null or (.integrations.demo | type) == \"boolean\" then empty else \"integrations.demo: expected true or false\" end",
 "files": {"demo.md": "{docs.root}/demo.md", "demo.sh": "{paths.scripts}/demo.sh"}}
EOF2
demo_cfg() { jq --argjson d "$1" '.integrations = {demo: $d}' "$C/.ai/av.config.json" >"$TMP/demo.json"; AV_TEMPLATES_DIR="$TD" bash "$CS" --root "$C" --config "$TMP/demo.json" >"$out"; }
demo_cfg 'true'
has "$out" "SETUP_TEMPLATE_MISSING .ai/demo.md (template demo)" "template: missing docs file"
has "$out" "SETUP_TEMPLATE_MISSING .ai/scripts/demo.sh (template demo)" "template: missing script"
demo_cfg '"yes"'
has "$out" "SETUP_INTEGRATION_INVALID integrations.demo: expected true or false" "template: validation from the manifest"
demo_cfg 'false'
hasnt "$out" "SETUP_TEMPLATE_MISSING" "template: applies false requires files"
hasnt "$out" "miro" "template: AV_TEMPLATES_DIR did not replace the directory"

# MARK: no roles, config errors, usage
jq 'del(.roles)' "$R/.ai/av.config.json" >"$TMP/noroles.json"
bash "$CS" --root "$C" --config "$TMP/noroles.json" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "no roles: code $rc"
has "$out" "SETUP_ROLES_NONE" "no roles: warning"
bash "$CS" --root "$C" --config "$TMP/noroles.json" --owner App/UI/V.swift Pods/P.swift >"$own"
has "$own" "OWNER App/UI/V.swift implementer" "no roles: implementer"
has "$own" "OWNER Pods/P.swift generated" "no roles: generated still works"

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

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

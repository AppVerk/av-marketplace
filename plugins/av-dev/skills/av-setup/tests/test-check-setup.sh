#!/bin/bash
# Testy czarnej skrzynki dla check_setup.sh.
# Buduje male repo z rolami, nakladkami i skillami rol w mktemp.
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
## Zakres plików
`App/Data/**`, `App/Shared/**`, `App/?1.swift`
Uruchom `gate.sh --only unit` albo `gate.sh --only ghost`.
EOF
printf -- '---\nname: app-ui\n---\n## Zakres plików\nRola `ui` w `.ai/av.config.json`.\n' >"$R/.claude/skills/app-ui/SKILL.md"

printf '## Pliki do przeczytania przed planem\nx\n## Obowiązkowe sekcje planu\nx\nSkrypt `scripts/absent_tool.sh`.\n' >"$R/.ai/overlays/av-plan.md"
printf '## Role\nRole w `.ai/av.config.json`.\n## Obowiązkowe kroki\nx\n## Wybór trybu\nx\n## Bramki per etap\n`gate.sh --gate quick`, `gate.sh --gate nope`, `gate.sh --only lint,unit`.\n' >"$R/.ai/overlays/av-implement.md"
printf '## Dobór bramki\nx\n' >"$R/.ai/overlays/av-verify.md"
printf '## Mapa kod -> docs\nx\n## Znane fałszywe nazwy\n- `Foo`\n' >"$R/.ai/overlays/av-docs-sync.md"
git -C "$R" add -A && git -C "$R" commit -qm init

# MARK: kontrola
out="$TMP/out.txt"
bash "$CS" --root "$R" >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "kod wyjscia z ERROR: $rc"
has "$out" "SETUP_OVERLAY_MISSING .ai/overlays/av-review.md" "brak nakladki av-review"
has "$out" 'SETUP_OVERLAY_SECTION .ai/overlays/av-verify.md "Interpretacja wyników"' "brak sekcji av-verify"
hasnt "$out" 'SETUP_OVERLAY_SECTION .ai/overlays/av-implement.md' "sekcje av-implement kompletne"
has "$out" "SETUP_ROLE_SKILL_MISSING net .claude/skills/app-net/SKILL.md" "brak skilla roli"
hasnt "$out" "php-developer" "skill z pluginu pomijany"
has "$out" "SETUP_ROLE_OVERLAP data,ui 1: App/Shared/Both.swift" "nakladanie rol"
has "$out" "SETUP_ROLE_EMPTY ui App/Nope/**" "pusty glob"
has "$out" "SETUP_ROLE_EMPTY ui App/{A,B}/** (nawiasy" "podpowiedz dla nawiasow"
hasnt "$out" "SETUP_ROLE_EMPTY ui My Dir/**" "glob ze spacja pasuje"
hasnt "$out" "SETUP_ROLE_EMPTY data App/?1.swift" "glob ze znakiem zapytania"
has "$out" "SETUP_UNOWNED_DIR Other 3 plikow bez wlasciciela: Other/Lib 2, Other/Tools 1" "katalog bez wlasciciela"
has "$out" "SETUP_UNOWNED_DIR App 1 plikow bez wlasciciela: App 1" "plik App/Q12.swift bez wlasciciela"
hasnt "$out" "SETUP_UNOWNED_DIR Pods" "generowane pominiete"
has "$out" "SETUP_GLOB_COPY .claude/skills/app-data/SKILL.md kopiuje 3" "kopia globow w skillu roli"
hasnt "$out" "SETUP_GLOB_COPY .claude/skills/app-ui" "skill linkujacy do configu"
has "$out" "SETUP_GATE_UNKNOWN .ai/overlays/av-implement.md:8 --gate nope" "nieznana bramka"
has "$out" "SETUP_GATE_UNKNOWN .claude/skills/app-data/SKILL.md:6 --only ghost" "nieznana komenda"
hasnt "$out" "--gate quick" "znana bramka"
hasnt "$out" "--only lint" "znana komenda z listy"
hasnt "$out" "--only unit" "znana komenda"
if [ -f "$REFS" ]; then
  has "$out" "SETUP_REF_MISSING .ai/overlays/av-plan.md:5 scripts/absent_tool.sh" "brakujacy skrypt"
else
  has "$out" "SETUP_REF_SKIPPED" "brak check_refs"
fi
tail -1 "$out" | grep -qE '^CHECKED [0-9]+ ERRORS [0-9]+ WARNINGS [0-9]+$' && ok || fail "linia podsumowania"

# MARK: wlasciciel
own="$TMP/own.txt"
bash "$CS" --root "$R" --owner App/Data/deep/New.swift Pods/P.swift scripts/t.sh README.md "My Dir/Sub Dir/x.swift" \
  App/Q1.swift App/Q12.swift "$R/App/UI/V.swift" App/UI/b.generated.swift App/Shared/Both.swift >"$own" 2>"$TMP/own.err"
rc=$?
[ "$rc" -eq 0 ] && ok || fail "owner: kod $rc"
has "$own" "OWNER App/Data/deep/New.swift data" "owner: nowy plik roli"
has "$own" "OWNER Pods/P.swift generated" "owner: generated"
has "$own" "OWNER scripts/t.sh unowned" "owner: unowned"
has "$own" "OWNER README.md implementer" "owner: implementer"
has "$own" "OWNER My Dir/Sub Dir/x.swift ui" "owner: sciezka ze spacja"
has "$own" "OWNER App/Q1.swift data" "owner: znak zapytania"
has "$own" "OWNER App/Q12.swift implementer" "owner: znak zapytania to jeden znak"
has "$own" "OWNER App/UI/V.swift ui" "owner: sciezka absolutna"
has "$own" "OWNER App/UI/b.generated.swift generated" "owner: **/ w srodku globu"
has "$own" "OWNER App/Shared/Both.swift data" "owner: nakladanie wybiera role wedlug order"
has "$TMP/own.err" "nakladanie rol" "owner: ostrzezenie o nakladaniu"

# MARK: czysty setup
C="$TMP/clean"
cp -R "$R" "$C"
printf '## Jak sprawdzać osie\nx\n' >"$C/.ai/overlays/av-review.md"
printf '## Dobór bramki\nx\n## Interpretacja wyników\nx\n' >"$C/.ai/overlays/av-verify.md"
printf '## Pliki do przeczytania przed planem\nx\n## Obowiązkowe sekcje planu\nx\n' >"$C/.ai/overlays/av-plan.md"
printf -- '---\nname: app-data\n---\n## Zakres plików\nRola `data` w configu.\n' >"$C/.claude/skills/app-data/SKILL.md"
sed -i '' 's/, `gate.sh --gate nope`//' "$C/.ai/overlays/av-implement.md" 2>/dev/null || sed -i 's/, `gate.sh --gate nope`//' "$C/.ai/overlays/av-implement.md"
jq '.roles = [{"name": "data", "skill": "app-data", "order": 1, "globs": ["App/**"]}, {"name": "ui", "skill": "app-ui", "order": 1, "globs": ["My Dir/**", "Other/**"]}]' \
  "$R/.ai/av.config.json" >"$C/.ai/av.config.json"
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_LOCAL_IGNORE dopisz .ai/av.config.json.local do .gitignore" "local: brak wpisu w .gitignore"
printf '.ai/av.config.json.local\n' >>"$C/.gitignore"
bash "$CS" --root "$C" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || { fail "czysty setup: kod $rc"; cat "$out" >&2; }
has "$out" "ERRORS 0 WARNINGS 0" "czysty setup bez uwag"
hasnt "$out" "SETUP_LOCAL_USED" "local: informacja bez pliku"

# MARK: nadpisanie lokalne
printf '{"roles": null}\n' >"$C/.ai/av.config.json.local"
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_LOCAL_USED .ai/av.config.json.local" "local: brak informacji o nadpisaniu"
has "$out" "SETUP_ROLES_NONE" "local: kontrola nie uzyla efektywnego configu"
bash "$CS" --root "$C" --no-local >"$out"; rc=$?
hasnt "$out" "SETUP_ROLES_NONE" "local: --no-local uzyl nadpisania"
bash "$CS" --root "$C" --owner App/Data/A.swift >"$out"; rc=$?
has "$out" "OWNER App/Data/A.swift implementer" "local: --owner bez efektywnego configu"
hasnt "$out" "SETUP_LOCAL_USED" "local: --owner drukuje informacje"
git -C "$C" add -f .ai/av.config.json.local
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_LOCAL_TRACKED" "local: brak bledu sledzenia"
[ "$rc" -eq 1 ] && ok || fail "local sledzony: kod $rc"
git -C "$C" rm -q --cached .ai/av.config.json.local
printf '{zly' >"$C/.ai/av.config.json.local"
bash "$CS" --root "$C" >"$out"; rc=$?
has "$out" "SETUP_CONFIG_INVALID .ai/av.config.json.local" "local: zly JSON"
rm -f "$C/.ai/av.config.json.local"

# MARK: integracje
miro_cfg() { jq --argjson m "$1" '.integrations = {miro: $m}' "$C/.ai/av.config.json" >"$TMP/miro.json"; bash "$CS" --root "$C" --config "$TMP/miro.json" >"$out"; }
miro_cfg '{"via":"api"}'
has "$out" "SETUP_INTEGRATION_INVALID integrations.miro.via" "miro: via api przeszlo"
miro_cfg '{"boards":{"x":"http://example.com"}}'
has "$out" "SETUP_INTEGRATION_INVALID integrations.miro.boards" "miro: zly adres przeszedl"
miro_cfg '"browser"'
has "$out" "SETUP_INTEGRATION_INVALID integrations.miro: oczekiwany obiekt" "miro: napis przeszedl"
miro_cfg '{"via":"browser","boards":{"docs":"https://miro.com/app/board/abc=/"}}'
hasnt "$out" "SETUP_INTEGRATION_INVALID" "miro: poprawny wpis odrzucony"
has "$out" "SETUP_TEMPLATE_MISSING .ai/miro.md" "miro: brak ostrzezenia o docs"
has "$out" "SETUP_TEMPLATE_MISSING .ai/scripts/miro-frames.js" "miro: brak ostrzezenia o skrypcie"
mkdir -p "$C/.ai/scripts"; : >"$C/.ai/miro.md"; : >"$C/.ai/scripts/miro-frames.js"
miro_cfg '{"via":"browser"}'
hasnt "$out" "SETUP_TEMPLATE_MISSING" "miro: ostrzezenie mimo plikow"
miro_cfg '{"via":"mcp"}'
hasnt "$out" "SETUP_INTEGRATION" "miro: mcp nie wymaga plikow"
rm -rf "$C/.ai/miro.md" "$C/.ai/scripts"

# MARK: szablony: mechanizm ogolny
TD="$TMP/templates"; mkdir -p "$TD/demo"
cat >"$TD/demo/template.json" <<'EOF2'
{"name": "demo", "applies": ".integrations.demo == true",
 "validate": "if (.integrations.demo // null) == null or (.integrations.demo | type) == \"boolean\" then empty else \"integrations.demo: oczekiwane true albo false\" end",
 "files": {"demo.md": "{docs.root}/demo.md", "demo.sh": "{paths.scripts}/demo.sh"}}
EOF2
demo_cfg() { jq --argjson d "$1" '.integrations = {demo: $d}' "$C/.ai/av.config.json" >"$TMP/demo.json"; AV_TEMPLATES_DIR="$TD" bash "$CS" --root "$C" --config "$TMP/demo.json" >"$out"; }
demo_cfg 'true'
has "$out" "SETUP_TEMPLATE_MISSING .ai/demo.md (szablon demo)" "szablon: brak pliku docs"
has "$out" "SETUP_TEMPLATE_MISSING .ai/scripts/demo.sh (szablon demo)" "szablon: brak skryptu"
demo_cfg '"tak"'
has "$out" "SETUP_INTEGRATION_INVALID integrations.demo: oczekiwane true albo false" "szablon: walidacja z manifestu"
demo_cfg 'false'
hasnt "$out" "SETUP_TEMPLATE_MISSING" "szablon: applies false wymaga plikow"
hasnt "$out" "miro" "szablon: AV_TEMPLATES_DIR nie zastapil katalogu"

# MARK: bez rol, bledy configu, uzycie
jq 'del(.roles)' "$R/.ai/av.config.json" >"$TMP/noroles.json"
bash "$CS" --root "$C" --config "$TMP/noroles.json" >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "bez rol: kod $rc"
has "$out" "SETUP_ROLES_NONE" "bez rol: ostrzezenie"
bash "$CS" --root "$C" --config "$TMP/noroles.json" --owner App/UI/V.swift Pods/P.swift >"$own"
has "$own" "OWNER App/UI/V.swift implementer" "bez rol: implementer"
has "$own" "OWNER Pods/P.swift generated" "bez rol: generated nadal dziala"

printf '{zly json' >"$TMP/bad.json"
bash "$CS" --root "$C" --config "$TMP/bad.json" >"$out"; rc=$?
[ "$rc" -eq 1 ] && grep -q SETUP_CONFIG_INVALID "$out" && ok || fail "zly JSON: kod $rc"
bash "$CS" --root "$C" --config "$TMP/brak.json" >"$out"; rc=$?
[ "$rc" -eq 1 ] && grep -q SETUP_CONFIG_MISSING "$out" && ok || fail "brak configu: kod $rc"
bash "$CS" --root "$C" --nieznana >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "nieznana opcja: kod $rc"
bash "$CS" --root "$C" --owner >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "--owner bez plikow: kod $rc"
bash "$CS" --root "$TMP" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "root bez git: kod $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

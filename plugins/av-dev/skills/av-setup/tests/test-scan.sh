#!/bin/bash
# Testy czarnej skrzynki dla scan.sh.
# Buduje trzy male repo (iOS, Symfony z frontendem, Angular) i sprawdza pola JSON.
set -u
SCAN="$(cd "$(dirname "$0")/.." && pwd)/scripts/scan.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
check() { jq -e "$2" "$1" >/dev/null 2>&1 && ok || fail "$3"; }

init_repo() {
  git init -q "$1" && git -C "$1" config user.email t@t && git -C "$1" config user.name t
}
commit() {
  git -C "$1" add -A && git -C "$1" commit -qm "$2"
}

# MARK: iOS
IOS="$TMP/ios app"
init_repo "$IOS"
mkdir -p "$IOS/App.xcodeproj" "$IOS/App.xcworkspace" "$IOS/App/Domains/Login_" "$IOS/App/Domains/Home_" \
  "$IOS/App/Domains/Rewards_" "$IOS/AppTests" "$IOS/App/Firebase/test" "$IOS/.ai/workspace" "$IOS/.claude/agents" "$IOS/scripts"
printf 'objects = { PBXGroup };\n' >"$IOS/App.xcodeproj/project.pbxproj"
printf "platform :ios, '15.0'\n" >"$IOS/Podfile"
for m in Login_ Home_ Rewards_; do printf 'import UIKit\n' >"$IOS/App/Domains/$m/V.swift"; done
printf 'import XCTest\n' >"$IOS/AppTests/T.swift"
printf '{}' >"$IOS/App/Firebase/test/GoogleService-Info.plist"
printf '# CLAUDE.md\n\nZasady pracy z repozytorium w języku polskim: żółć, ćma, łódź, źrebię, ślimak, gęś, pąk. Każdy moduł ma opis. Zależności są w pliku. Reguły są krótkie i jasne. Gałąź bazowa to develop.\n\n## Git\n\n```sh\nscripts/build.sh\n```\n\n```swift\nlet x = 1\n```\n' >"$IOS/CLAUDE.md"
ln -s CLAUDE.md "$IOS/AGENTS.md"
printf -- '---\nname: reviewer\n---\n' >"$IOS/.claude/agents/reviewer.md"
printf '#!/bin/bash\n# Buduje aplikacje.\n' >"$IOS/scripts/build.sh"
cat >"$IOS/scripts/unit_test.sh" <<'EOF'
#!/bin/bash
# Uruchamia testy.
#
# Kod wyjscia: 0 gdy zielone, 1 gdy test czerwony,
# 2 przy niedostepnym srodowisku.
#
# Brama przy kazdej zmianie.
set -u
exit 0 # Exit 5 w kodzie nie jest opisem
echo "  STATUS: ENV_DOWN"
echo "  STATUS: UNIT_OK"
EOF
printf '"""Nagrywa fixtures.\n\nExit codes: 0 ok, 2 brak sieci.\n"""\nprint("REC_OK")\n' >"$IOS/scripts/rec.py"
printf '.ai/workspace/\n.env\n' >"$IOS/.gitignore"
printf 'SECRET=1\n' >"$IOS/.env"
commit "$IOS" "NKR-1 add login"
git -C "$IOS" checkout -q -b develop
git -C "$IOS" checkout -q -b feature/NFI-2-home
printf '//\n' >>"$IOS/App/Domains/Home_/V.swift"; commit "$IOS" "NFI-2 fix home"
git -C "$IOS" checkout -q develop
git -C "$IOS" merge -q --no-ff feature/NFI-2-home -m "Merged in feature/NFI-2-home (pull request #1)"

out="$TMP/ios.json"
bash "$SCAN" "$IOS" >"$out"
check "$out" '.stacks[0].id == "ios-uikit" and .stacks[0].cocoapods and (.stacks[0].xcode_synchronized_groups | not)' "ios: stack"
check "$out" '.git.base_branch_guess == "develop"' "ios: baza develop"
check "$out" '.git.ticket_prefixes.NFI >= 1 and .git.ticket_prefixes.NKR >= 1' "ios: prefiksy"
check "$out" '.git.merged_branch_names | index("feature/NFI-2-home") != null' "ios: scalona galaz"
check "$out" '.git.branch_types_seen == ["feature"]' "ios: typy galezi"
check "$out" '.doc_language_guess == "pl"' "ios: jezyk"
check "$out" '.module_candidates | map(select(.pattern == "*/Domains/*")) | .[0].count == 3' "ios: moduly"
check "$out" '.tests.dirs == ["AppTests"]' "ios: katalogi testow bez Firebase/test"
check "$out" '.ai_setup["AGENTS.md"].symlink_to == "CLAUDE.md"' "ios: symlink AGENTS"
check "$out" '.ai_setup.orchestration == true' "ios: orkiestracja z agentow"
check "$out" '.ai_setup.gitignore_ai == [".ai/workspace/"]' "ios: wzorce gitignore"
check "$out" '.secret_like_files == [".env"]' "ios: plik sekretow"
check "$out" '.commands.scripts_dir[0].doc == "Buduje aplikacje."' "ios: opis skryptu"
check "$out" '.commands.scripts_meta | map(select(.path == "scripts/unit_test.sh")) | .[0] | .exit_codes_doc == "Kod wyjscia: 0 gdy zielone, 1 gdy test czerwony, 2 przy niedostepnym srodowisku." and .status_tokens == ["ENV_DOWN", "UNIT_OK"]' "ios: kody wyjscia i statusy skryptu"
check "$out" '.commands.scripts_meta | map(select(.path == "scripts/rec.py")) | .[0] | .exit_codes_doc == "Exit codes: 0 ok, 2 brak sieci." and .status_tokens == ["REC_OK"]' "ios: docstring pythona"
check "$out" '.commands.scripts_meta | map(.path) | index("scripts/build.sh") == null' "ios: skrypt bez opisu wyniku pominiety"
check "$out" '.commands.documented_commands == [{"doc": "CLAUDE.md", "cmd": "scripts/build.sh"}]' "ios: komendy z docs bez bloku swift"
check "$out" '.source_files >= 4' "ios: pliki zrodlowe"
grep -q 'SECRET=1' "$out" && fail "ios: wartosc sekretu w wyniku" || ok

# MARK: Symfony z frontendem
PHP="$TMP/php"
init_repo "$PHP"
mkdir -p "$PHP/src/Orders/Domain" "$PHP/src/Orders/Application" "$PHP/templates" "$PHP/metronic" "$PHP/tests/Unit"
printf '{"require":{"php":">=8.4","symfony/framework-bundle":"7.4.*","symfony/messenger":"7.4.*","doctrine/orm":"^3"},"scripts":{"analyse":"phpstan","test":"phpunit","post-install-cmd":["x"]}}\n' >"$PHP/composer.json"
printf '{"devDependencies":{"tailwindcss":"4","vite":"5"},"scripts":{"build":"vite build"}}\n' >"$PHP/metronic/package.json"
touch "$PHP/metronic/yarn.lock"
printf '<?php\n' >"$PHP/tests/Unit/T.php"
cat >"$PHP/bitbucket-pipelines.yml" <<'EOF'
pipelines:
  pull-requests:
    '**':
      - step:
          name: Analyse
          script:
            - composer install
            - composer analyse
  custom:
    deploy:
      - step:
          name: Deploy
          script:
            - ./deploy.sh
EOF
touch "$PHP/docker-compose.yml"
commit "$PHP" "feat: init"

out="$TMP/php.json"
bash "$SCAN" "$PHP" >"$out"
check "$out" '.stacks | map(.id) == ["php-symfony", "node"]' "php: stacki"
check "$out" '.stacks[0].ddd_layout == ["Application", "Domain"] and .stacks[0].messenger' "php: DDD i messenger"
check "$out" '.stacks[1].dir == "metronic" and (.stacks[1].frontend_hints | index("tailwindcss") != null)' "php: frontend w podkatalogu"
check "$out" '.commands.composer | has("analyse") and (has("post-install-cmd") | not)' "php: skrypty composera"
check "$out" '.commands["package.json:metronic"].runner == "yarn"' "php: runner z lockfile"
check "$out" '.commands.ci[0].steps[0] == {"section": "pull-requests:**", "name": "Analyse", "commands": ["composer install", "composer analyse"]}' "php: krok CI PR"
check "$out" '.commands.ci[0].steps[1].section == "custom:deploy"' "php: sekcja custom"
check "$out" '.commands.docker_compose == ["docker-compose.yml"]' "php: compose"
check "$out" '.git.remote_host == "bitbucket"' "php: host z pliku CI"
check "$out" '.git.conventional_commits_ratio == "1/1"' "php: conventional commits"
check "$out" '.ai_setup.orchestration == false' "php: brak orkiestracji"
check "$out" '.ai_setup.agents_ignored == false' "php: .agents nieignorowany"

# MARK: Angular
NG="$TMP/ng"
init_repo "$NG"
mkdir -p "$NG/src/app/auth" "$NG/src/app/orders" "$NG/src/app/shared" "$NG/.husky" "$NG/docs/standards"
printf '{"dependencies":{"@angular/core":"^21.0.0","@ngx-translate/core":"16"},"devDependencies":{"karma":"6"},"engines":{"node":">=22"},"scripts":{"lint":"ng lint","test:headless":"ng test --no-watch","ci":"bash tools/ci.sh"}}\n' >"$NG/package.json"
touch "$NG/package-lock.json"
printf 'import { bootstrapApplication } from "@angular/platform-browser";\n' >"$NG/src/main.ts"
touch "$NG/src/app/auth/a.spec.ts" "$NG/src/app/orders/o.ts" "$NG/src/app/shared/s.ts"
printf 'npm run lint\n' >"$NG/.husky/pre-commit"
printf '22.12\n' >"$NG/.nvmrc"
mkdir -p "$NG/tools" && printf '#!/bin/sh\n# CI. Exit 0: ok; 1: blad.\necho CI_OK\n' >"$NG/tools/ci.sh"
printf 'module.exports = { coverageReporter: { check: { global: { statements: 75 } } } };\n' >"$NG/karma.conf.js"
printf '# Standard\n' >"$NG/docs/standards/testing.md"
printf '{"includeCoAuthoredBy": false}\n' >"$NG/.claude-settings.tmp"
mkdir -p "$NG/.claude" && mv "$NG/.claude-settings.tmp" "$NG/.claude/settings.json"
commit "$NG" "feat(auth): CC-10 add login"

out="$TMP/ng.json"
bash "$SCAN" "$NG" >"$out"
check "$out" '.stacks[0].id == "angular" and .stacks[0].unit_test == "karma" and .stacks[0].i18n == "@ngx-translate/core" and .stacks[0].bootstrap == "standalone"' "ng: stack"
check "$out" '.tooling.husky_hooks["pre-commit"] == ["npm run lint"]' "ng: husky"
check "$out" '.tooling.versions[".nvmrc"] == ["22.12"] and .tooling.versions.engines.node == ">=22"' "ng: wersje"
check "$out" '.tooling.coverage_thresholds["karma.conf.js"] | test("statements: 75")' "ng: prog pokrycia"
check "$out" '.tests.spec_ts_files == 1' "ng: pliki spec"
check "$out" '.commands.scripts_meta == [{"path": "tools/ci.sh", "exit_codes_doc": "CI. Exit 0: ok; 1: blad.", "status_tokens": ["CI_OK"]}]' "ng: skrypt z package.json"
check "$out" '.ai_setup.docs == ["docs/standards/testing.md"]' "ng: docs"
check "$out" '.ai_setup[".claude"].co_authored_setting == false' "ng: includeCoAuthoredBy false"
check "$out" '.git.ticket_prefixes.CC == 1' "ng: prefiks CC"
check "$out" '.module_candidates | map(select(.pattern == "src/app/*")) | .[0].count == 3' "ng: moduly src/app"

# MARK: dane osobowe, README, bloki bez jezyka, husky, githooks
EXTRA="$TMP/extra"
init_repo "$EXTRA"
mkdir -p "$EXTRA/.husky" "$EXTRA/.githooks" "$EXTRA/scripts/claude"
cat >"$EXTRA/bitbucket-pipelines.yml" <<'EOF2'
pipelines:
  default:
    - step:
        name: Validate
        script:
          - ALLOWED="Jan Kowalski {1b4e28ba-2fa1-11d2-883f-0016d3cca427}"
          - echo "build ok"
          - notify jan.kowalski@example.com
EOF2
printf '# Readme

```
npm run build
src/  kod aplikacji
$ make test
```
' >"$EXTRA/README.md"
for i in 1 2 3 4 5 6 7; do printf 'npm run step%s
' "$i"; done >"$EXTRA/.husky/pre-commit"
printf '#!/bin/sh
' >"$EXTRA/.githooks/pre-commit"
printf '// Guard hooka PreToolUse.
' >"$EXTRA/scripts/claude/guard.mjs"
commit "$EXTRA" "chore: init"
git -C "$EXTRA" commit -q --allow-empty -m "feat: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
out="$TMP/extra.json"
bash "$SCAN" "$EXTRA" >"$out"
grep -q 'Kowalski\|1b4e28ba\|jan.kowalski@' "$out" && fail "extra: dane osobowe w wyniku" || ok
check "$out" '.commands.ci[0].steps[0].commands | index("echo \"build ok\"") != null' "extra: cudzyslow zachowany"
check "$out" '[.commands.documented_commands[].cmd] == ["npm run build", "make test"]' "extra: komendy z bloku bez jezyka"
check "$out" '.tooling.husky_hooks["pre-commit"] | length == 7' "extra: pelny hook husky"
check "$out" '.ai_setup.githooks | index(".githooks/pre-commit") != null' "extra: githooks"
check "$out" '.commands.scripts_dir | map(.file) | index("scripts/claude/guard.mjs") != null' "extra: zagniezdzony skrypt"
check "$out" '.git.ai_signature_commits == "1/2"' "extra: podpis AI w ostatnich commitach"

# MARK: warstwy zamiast modulow, .agents ignorowany
LAY="$TMP/layers"
init_repo "$LAY"
for d in Controller Form Enum Service Orders; do mkdir -p "$LAY/src/$d" && printf '<?php\n' >"$LAY/src/$d/A.php"; done
printf '/.agents/\n' >"$LAY/.gitignore"
printf '{"require":{"symfony/framework-bundle":"7"}}\n' >"$LAY/composer.json"
commit "$LAY" "init"
out="$TMP/lay.json"
bash "$SCAN" "$LAY" >"$out"
check "$out" '.module_candidates | map(select(.pattern == "src/*")) | .[0].looks_like_layers == true' "layers: wykryte warstwy"
check "$out" '.ai_setup.agents_ignored == true' "layers: .agents ignorowany"

# MARK: bledy
out="$(bash "$SCAN" "$TMP/nie-ma")"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '"error"' && ok || fail "brak katalogu: kod $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

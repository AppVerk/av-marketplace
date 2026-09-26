#!/bin/bash
# Black box tests for scan.sh.
# Builds small repos (iOS, Symfony with a frontend, Angular, extras) and checks the JSON fields.
# The iOS repo has Polish docs and a Polish exit code comment: they test Polish detection.
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
# Stack markers for iOS detection: Demo.xcodeproj, Demo.xcworkspace, Podfile, src/Demo/Main.swift.
mkdir -p "$IOS/Demo.xcodeproj" "$IOS/Demo.xcworkspace" "$IOS/src/Demo" "$IOS/core/Modules/Billing" "$IOS/core/Modules/Orders" \
  "$IOS/core/Modules/Profile" "$IOS/DemoTests" "$IOS/config/env/test" "$IOS/.ai/workspace" "$IOS/.claude/agents" "$IOS/scripts"
printf 'objects = { PBXGroup };\n' >"$IOS/Demo.xcodeproj/project.pbxproj"
printf "platform :ios, '15.0'\n" >"$IOS/Podfile"
printf 'let x = 1\n' >"$IOS/src/Demo/Main.swift"
printf 'package billing\n' >"$IOS/core/Modules/Billing/invoice.go"
printf 'export const list = [];\n' >"$IOS/core/Modules/Orders/list.ts"
printf 'def load():\n    pass\n' >"$IOS/core/Modules/Profile/service.py"
printf 'def test_load():\n    pass\n' >"$IOS/DemoTests/test_service.py"
printf '{}' >"$IOS/config/env/test/settings.json"
printf '# CLAUDE.md\n\nZasady pracy z repozytorium w języku polskim: żółć, ćma, łódź, źrebię, ślimak, gęś, pąk. Każdy moduł ma opis. Zależności są w pliku. Reguły są krótkie i jasne. Gałąź bazowa to develop.\n\n## Git\n\n```sh\nscripts/build.sh\n```\n\n```python\nx = 1\n```\n' >"$IOS/CLAUDE.md"
ln -s CLAUDE.md "$IOS/AGENTS.md"
printf -- '---\nname: reviewer\n---\n' >"$IOS/.claude/agents/reviewer.md"
printf '#!/bin/bash\n# Builds the app.\n' >"$IOS/scripts/build.sh"
cat >"$IOS/scripts/unit_test.sh" <<'EOF'
#!/bin/bash
# Runs the tests.
#
# Kod wyjscia: 0 gdy zielone, 1 gdy test czerwony,
# 2 przy niedostepnym srodowisku.
#
# Gate for every change.
set -u
exit 0 # Exit 5 in code is not a description
echo "  STATUS: ENV_DOWN"
echo "  STATUS: UNIT_OK"
EOF
printf '"""Records fixtures.\n\nExit codes: 0 ok, 2 no network.\n"""\nprint("REC_OK")\n' >"$IOS/scripts/rec.py"
printf '.ai/workspace/\n.env\n' >"$IOS/.gitignore"
printf 'SECRET=1\n' >"$IOS/.env"
commit "$IOS" "OPS-1 add billing"
git -C "$IOS" checkout -q -b develop
git -C "$IOS" checkout -q -b feature/PROJ-2-orders
printf '//\n' >>"$IOS/core/Modules/Orders/list.ts"; commit "$IOS" "PROJ-2 fix orders"
git -C "$IOS" checkout -q develop
git -C "$IOS" merge -q --no-ff feature/PROJ-2-orders -m "Merged in feature/PROJ-2-orders (pull request #1)"

out="$TMP/ios.json"
bash "$SCAN" "$IOS" >"$out"
check "$out" '.stacks[0].id == "ios-uikit" and .stacks[0].cocoapods and (.stacks[0].xcode_synchronized_groups | not)' "ios: stack"
check "$out" '.git.base_branch_guess == "develop"' "ios: base develop"
check "$out" '.git.ticket_prefixes.PROJ >= 1 and .git.ticket_prefixes.OPS >= 1' "ios: prefixes"
check "$out" '.git.merged_branch_names | index("feature/PROJ-2-orders") != null' "ios: merged branch"
check "$out" '.git.branch_types_seen == ["feature"]' "ios: branch types"
check "$out" '.doc_language_guess == "pl"' "ios: language pl"
check "$out" '.module_candidates | map(select(.pattern == "*/Modules/*")) | .[0].count == 3' "ios: modules"
check "$out" '.tests.dirs == ["DemoTests"]' "ios: test dirs without config/env/test"
check "$out" '.ai_setup["AGENTS.md"].symlink_to == "CLAUDE.md"' "ios: symlink AGENTS"
check "$out" '.ai_setup.orchestration == true' "ios: orchestration from agents"
check "$out" '.ai_setup.gitignore_ai == [".ai/workspace/"]' "ios: gitignore patterns"
check "$out" '.secret_like_files == [".env"]' "ios: secrets file"
check "$out" '.commands.scripts_dir[0].doc == "Builds the app."' "ios: script description"
check "$out" '.commands.scripts_meta | map(select(.path == "scripts/unit_test.sh")) | .[0] | .exit_codes_doc == "Kod wyjscia: 0 gdy zielone, 1 gdy test czerwony, 2 przy niedostepnym srodowisku." and .status_tokens == ["ENV_DOWN", "UNIT_OK"]' "ios: script exit codes and statuses (Polish)"
check "$out" '.commands.scripts_meta | map(select(.path == "scripts/rec.py")) | .[0] | .exit_codes_doc == "Exit codes: 0 ok, 2 no network." and .status_tokens == ["REC_OK"]' "ios: python docstring"
check "$out" '.commands.scripts_meta | map(.path) | index("scripts/build.sh") == null' "ios: script without result description skipped"
check "$out" '.commands.documented_commands == [{"doc": "CLAUDE.md", "cmd": "scripts/build.sh"}]' "ios: commands from docs without python block"
check "$out" '.source_files >= 4' "ios: source files"
grep -q 'SECRET=1' "$out" && fail "ios: secret value in output" || ok

# MARK: Symfony with a frontend
PHP="$TMP/php"
init_repo "$PHP"
mkdir -p "$PHP/src/Orders/Domain" "$PHP/src/Orders/Application" "$PHP/templates" "$PHP/web" "$PHP/tests/Unit"
printf '{"require":{"php":">=8.4","symfony/framework-bundle":"7.4.*","symfony/messenger":"7.4.*","doctrine/orm":"^3"},"scripts":{"analyse":"phpstan","test":"phpunit","post-install-cmd":["x"]}}\n' >"$PHP/composer.json"
printf '{"devDependencies":{"tailwindcss":"4","vite":"5"},"scripts":{"build":"vite build"}}\n' >"$PHP/web/package.json"
touch "$PHP/web/yarn.lock"
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
check "$out" '.stacks | map(.id) == ["php-symfony", "node"]' "php: stacks"
check "$out" '.stacks[0].ddd_layout == ["Application", "Domain"] and .stacks[0].messenger' "php: DDD and messenger"
check "$out" '.stacks[1].dir == "web" and (.stacks[1].frontend_hints | index("tailwindcss") != null)' "php: frontend in a subdirectory"
check "$out" '.commands.composer | has("analyse") and (has("post-install-cmd") | not)' "php: composer scripts"
check "$out" '.commands["package.json:web"].runner == "yarn"' "php: runner from lockfile"
check "$out" '.commands.ci[0].steps[0] == {"section": "pull-requests:**", "name": "Analyse", "commands": ["composer install", "composer analyse"]}' "php: CI PR step"
check "$out" '.commands.ci[0].steps[1].section == "custom:deploy"' "php: custom section"
check "$out" '.commands.docker_compose == ["docker-compose.yml"]' "php: compose"
check "$out" '.git.remote_host == "bitbucket"' "php: host from CI file"
check "$out" '.git.conventional_commits_ratio == "1/1"' "php: conventional commits"
check "$out" '.ai_setup.orchestration == false' "php: no orchestration"
check "$out" '.ai_setup.agents_ignored == false' "php: .agents not ignored"

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
mkdir -p "$NG/tools" && printf '#!/bin/sh\n# CI. Exit 0: ok; 1: error.\necho CI_OK\n' >"$NG/tools/ci.sh"
printf 'module.exports = { coverageReporter: { check: { global: { statements: 75 } } } };\n' >"$NG/karma.conf.js"
printf '# Standard\n' >"$NG/docs/standards/testing.md"
printf '{"includeCoAuthoredBy": false}\n' >"$NG/.claude-settings.tmp"
mkdir -p "$NG/.claude" && mv "$NG/.claude-settings.tmp" "$NG/.claude/settings.json"
commit "$NG" "feat(auth): CC-10 add login"

out="$TMP/ng.json"
bash "$SCAN" "$NG" >"$out"
check "$out" '.stacks[0].id == "angular" and .stacks[0].unit_test == "karma" and .stacks[0].i18n == "@ngx-translate/core" and .stacks[0].bootstrap == "standalone"' "ng: stack"
check "$out" '.tooling.husky_hooks["pre-commit"] == ["npm run lint"]' "ng: husky"
check "$out" '.tooling.versions[".nvmrc"] == ["22.12"] and .tooling.versions.engines.node == ">=22"' "ng: versions"
check "$out" '.tooling.coverage_thresholds["karma.conf.js"] | test("statements: 75")' "ng: coverage threshold"
check "$out" '.tests.spec_ts_files == 1' "ng: spec files"
check "$out" '.commands.scripts_meta == [{"path": "tools/ci.sh", "exit_codes_doc": "CI. Exit 0: ok; 1: error.", "status_tokens": ["CI_OK"]}]' "ng: script from package.json"
check "$out" '.ai_setup.docs == ["docs/standards/testing.md"]' "ng: docs"
check "$out" '.ai_setup[".claude"].co_authored_setting == false' "ng: includeCoAuthoredBy false"
check "$out" '.git.ticket_prefixes.CC == 1' "ng: prefix CC"
check "$out" '.module_candidates | map(select(.pattern == "src/app/*")) | .[0].count == 3' "ng: modules src/app"

# MARK: personal data, README, blocks without language, husky, githooks
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
src/  app code
$ make test
```
' >"$EXTRA/README.md"
for i in 1 2 3 4 5 6 7; do printf 'npm run step%s
' "$i"; done >"$EXTRA/.husky/pre-commit"
printf '#!/bin/sh
' >"$EXTRA/.githooks/pre-commit"
printf '// PreToolUse hook guard.
' >"$EXTRA/scripts/claude/guard.mjs"
printf '#!/bin/bash\n# Runs the tests.\n#\n# Exit code: 0 when green, 1 when a test fails,\n# 2 when the environment is down.\n#\n# Gate for every change.\necho "UNIT_OK"\n' >"$EXTRA/scripts/unit.sh"
commit "$EXTRA" "chore: init"
git -C "$EXTRA" commit -q --allow-empty -m "feat: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
out="$TMP/extra.json"
bash "$SCAN" "$EXTRA" >"$out"
grep -q 'Kowalski\|1b4e28ba\|jan.kowalski@' "$out" && fail "extra: personal data in output" || ok
check "$out" '.commands.ci[0].steps[0].commands | index("echo \"build ok\"") != null' "extra: quote kept"
check "$out" '[.commands.documented_commands[].cmd] == ["npm run build", "make test"]' "extra: commands from a block without language"
check "$out" '.tooling.husky_hooks["pre-commit"] | length == 7' "extra: full husky hook"
check "$out" '.ai_setup.githooks | index(".githooks/pre-commit") != null' "extra: githooks"
check "$out" '.commands.scripts_dir | map(.file) | index("scripts/claude/guard.mjs") != null' "extra: nested script"
check "$out" '.git.ai_signature_commits == "1/2"' "extra: AI signature in recent commits"
check "$out" '.doc_language_guess == "en"' "extra: language en"
check "$out" '.commands.scripts_meta | map(select(.path == "scripts/unit.sh")) | .[0] | .exit_codes_doc == "Exit code: 0 when green, 1 when a test fails, 2 when the environment is down." and .status_tokens == ["UNIT_OK"]' "extra: script exit codes and statuses (English)"

# MARK: layers instead of modules, .agents ignored
LAY="$TMP/layers"
init_repo "$LAY"
for d in Controller Form Enum Service Orders; do mkdir -p "$LAY/src/$d" && printf '<?php\n' >"$LAY/src/$d/A.php"; done
printf '/.agents/\n' >"$LAY/.gitignore"
printf '{"require":{"symfony/framework-bundle":"7"}}\n' >"$LAY/composer.json"
commit "$LAY" "init"
out="$TMP/lay.json"
bash "$SCAN" "$LAY" >"$out"
check "$out" '.module_candidates | map(select(.pattern == "src/*")) | .[0].looks_like_layers == true' "layers: layers detected"
check "$out" '.ai_setup.agents_ignored == true' "layers: .agents ignored"

# MARK: errors
out="$(bash "$SCAN" "$TMP/missing")"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '"error"' && ok || fail "missing directory: code $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

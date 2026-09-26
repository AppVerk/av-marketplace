#!/bin/bash
# Black box tests for scan.sh.
# Builds small repos (Xcode, Composer with an npm subdirectory, npm, extras, mixed languages,
# pipeline docs, CI files) and checks the JSON fields. Stacks are neutral: {id, dir, evidence}.
# The Xcode repo has Polish docs and a Polish exit code comment: they test Polish detection.
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
mkdir -p "$IOS/Demo.xcodeproj/project.xcworkspace" "$IOS/Demo.xcworkspace" "$IOS/src/Demo" "$IOS/core/Modules/Billing" "$IOS/core/Modules/Orders" \
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
check "$out" '.stacks == [{"id": "cocoapods", "dir": ".", "evidence": ["Podfile"]}, {"id": "xcode", "dir": ".", "evidence": ["Demo.xcodeproj", "Demo.xcworkspace"]}]' "ios: stack from manifests, workspace inside the project skipped"
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
check "$out" '.stacks == [{"id": "composer", "dir": ".", "evidence": ["composer.json"]}, {"id": "npm", "dir": "web", "evidence": ["web/package.json"]}]' "php: stacks"
check "$out" '[.stacks[] | keys] | all(. == ["dir", "evidence", "id"])' "php: no framework fields in stacks"
grep -qE '"(php-symfony|ddd_layout|messenger|doctrine|twig|frontend_hints|framework)"' "$out" && fail "php: framework guess in output" || ok
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
check "$out" '.stacks == [{"id": "npm", "dir": ".", "evidence": ["package.json"]}]' "ng: stack"
grep -qE '"(angular|unit_test|e2e|i18n|state|bootstrap)"' "$out" && fail "ng: framework fields in output" || ok
check "$out" '.tooling.husky_hooks["pre-commit"] == ["npm run lint"]' "ng: husky"
check "$out" '.tooling.versions[".nvmrc"] == ["22.12"] and .tooling.versions.engines.node == ">=22"' "ng: versions"
check "$out" '.tooling.coverage_thresholds["karma.conf.js"] | test("statements: 75")' "ng: coverage threshold"
check "$out" '.tests.spec_ts_files == 1' "ng: spec files"
check "$out" '.commands.scripts_meta == [{"path": "tools/ci.sh", "exit_codes_doc": "CI. Exit 0: ok; 1: error.", "status_tokens": ["CI_OK"], "referenced_by": ["package.json"]}]' "ng: script from package.json"
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

# MARK: scripts referenced by CI, composer.json, package.json and Makefile
REF="$TMP/refs"
init_repo "$REF"
mkdir -p "$REF/tests/E2E" "$REF/bin" "$REF/ci" "$REF/tools" "$REF/web/tools" "$REF/vendor/pkg" "$REF/scripts" "$REF/src/gen" "$REF/.github/workflows"
doc() { printf '%s\n# Runs %s.\n# Exit code: 0 ok, 1 failed.\necho "%s_OK"\n' "$1" "$2" "$3"; }
doc '#!/bin/bash' e2e E2E >"$REF/tests/E2E/run-tests.sh"
doc '#!/bin/sh' check CHECK >"$REF/bin/check.sh"
doc '#!/bin/sh' lint LINT >"$REF/ci/lint.sh"
doc '#!/usr/bin/env bash' verify VERIFY >"$REF/bin/verify"
doc '#!/usr/bin/env python3' tool TOOL >"$REF/bin/tool"
doc '#!/usr/bin/env python3' report REPORT >"$REF/tools/report.py"
doc '#!/bin/sh' smoke SMOKE >"$REF/tools/smoke.sh"
doc '// gen' gen GEN >"$REF/web/tools/gen.js"
doc '#!/bin/sh' vendored VENDOR >"$REF/vendor/pkg/x.sh"
doc '#!/bin/sh' outside OUTSIDE >"$TMP/outside.sh"
doc '#!/bin/sh' unit UNIT >"$REF/scripts/unit.sh"
doc '#!/bin/sh' build BUILD >"$REF/scripts/build.sh"
cat >"$REF/bitbucket-pipelines.yml" <<'EOF3'
pipelines:
  default:
    - step:
        name: E2E
        script:
          - bash tests/E2E/run-tests.sh --headless
          - ./bin/check.sh && python3 tools/report.py
          - sh vendor/pkg/x.sh; bash ../outside.sh
          - bash tests/missing.sh
EOF3
printf 'on: push\njobs:\n  lint:\n    steps:\n      - run: sh ./ci/lint.sh\n' >"$REF/.github/workflows/ci.yml"
printf '{"scripts":{"e2e":"tests/E2E/run-tests.sh","post-install-cmd":["@php bin/tool"]}}\n' >"$REF/composer.json"
printf '{"scripts":{"smoke":"bash ../tools/smoke.sh","gen":"node tools/gen.js"}}\n' >"$REF/web/package.json"
{ printf 'verify:\n\t./bin/verify\n\tbin/tool\n\tscripts/unit.sh\n# not a recipe: bin/check.sh\ngen:\n'
  for i in $(seq 1 45); do printf '\tbash src/gen/g%02d.sh\n' "$i"; done; } >"$REF/Makefile"
for i in $(seq 1 45); do doc '#!/bin/sh' "g$i" GEN >"$REF/src/gen/g$(printf '%02d' "$i").sh"; done
commit "$REF" "PROJ-1 init"
out="$TMP/refs.json"
bash "$SCAN" "$REF" >"$out"
meta() { printf '.commands.scripts_meta | map(select(.path == "%s")) | .[0]' "$1"; }
check "$out" "$(meta tests/E2E/run-tests.sh) | .exit_codes_doc == \"Exit code: 0 ok, 1 failed.\" and .status_tokens == [\"E2E_OK\"] and .referenced_by == [\"bitbucket-pipelines.yml\", \"composer.json\"]" "refs: CI and composer script with meta and sources"
check "$out" '.commands.scripts_meta | map(select(.path == "tests/E2E/run-tests.sh")) | length == 1' "refs: script referenced twice listed once"
check "$out" "$(meta bin/check.sh) | .referenced_by == [\"bitbucket-pipelines.yml\"]" "refs: ./ prefix and && chain"
check "$out" "$(meta ci/lint.sh) | .referenced_by == [\".github/workflows/ci.yml\"]" "refs: sh ./x.sh in a GitHub workflow"
check "$out" "$(meta bin/verify) | .status_tokens == [\"VERIFY_OK\"] and .referenced_by == [\"Makefile\"]" "refs: Makefile recipe, shell shebang without extension"
check "$out" "$(meta tools/smoke.sh) | .referenced_by == [\"web/package.json\"]" "refs: ../ path from a package.json in a subdirectory"
check "$out" "$(meta web/tools/gen.js) | .referenced_by == [\"web/package.json\"]" "refs: package.json js script relative to its directory"
check "$out" "$(meta scripts/unit.sh) | .referenced_by == [\"Makefile\"]" "refs: scripts/ entry gets its source"
check "$out" "$(meta scripts/build.sh) | .referenced_by == []" "refs: unreferenced scripts/ entry has empty sources"
check "$out" '.commands.scripts_meta | map(.path) | (index("bin/tool") == null and index("tools/report.py") == null)' "refs: non-shell scripts from CI and Makefile skipped"
check "$out" '.commands.scripts_meta | map(.path) | (index("vendor/pkg/x.sh") == null and index("tests/missing.sh") == null and any(.[]; test("outside")) == false)' "refs: vendor, missing and outside files skipped"
check "$out" '.commands.scripts_meta | map(select(.path | startswith("scripts/") | not)) | length == 40' "refs: at most 40 referenced scripts"
check "$out" '.commands.scripts_meta | map(select(.path | startswith("src/gen/"))) | length == 34 and .[0].path == "src/gen/g01.sh"' "refs: cap keeps references in order"

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

# MARK: mixed languages - ecosystems from manifests, test file names, layers, documented commands
POLY="$TMP/poly"
init_repo "$POLY"
mkdir -p "$POLY/app" "$POLY/services/api" "$POLY/src/Tool" "$POLY/src/pkg" "$POLY/src/web" "$POLY/tests" \
  "$POLY/node_modules/x" "$POLY/vendor/y" "$POLY/a/b/c/d" "$POLY/bad" "$POLY/lib/controllers" "$POLY/lib/models" "$POLY/lib/services"
printf 'module example.com/poly\n' >"$POLY/go.mod"
printf '[package]\nname = "poly"\n' >"$POLY/Cargo.toml"
printf '<project/>\n' >"$POLY/pom.xml"
printf "source 'https://rubygems.org'\n" >"$POLY/Gemfile"
printf '[project]\nname = "poly"\n' >"$POLY/pyproject.toml"
printf 'requests\n' >"$POLY/requirements.txt"
printf '[project]\nname = "api"\n' >"$POLY/services/api/pyproject.toml"
printf 'include(":app")\n' >"$POLY/settings.gradle.kts"
printf 'plugins {}\n' >"$POLY/app/build.gradle.kts"
printf '<Project/>\n' >"$POLY/src/Tool/Tool.csproj"
printf '{}\n' >"$POLY/node_modules/x/package.json"
printf '{}\n' >"$POLY/vendor/y/composer.json"
printf '{}\n' >"$POLY/a/b/c/d/package.json"
printf '{not json\n' >"$POLY/bad/package.json"
printf 'package pkg\n' >"$POLY/src/pkg/calc_test.go"
printf 'it("a", () => {});\n' >"$POLY/src/web/app.spec.ts"
printf 'test("b", () => {});\n' >"$POLY/src/web/util.test.js"
printf 'def test_calc():\n    pass\n' >"$POLY/tests/test_calc.py"
printf 'class CalcTests {}\n' >"$POLY/src/Tool/CalcTests.cs"
for d in controllers models services; do printf 'x = 1\n' >"$POLY/lib/$d/a.rb"; done
printf '# Poly\n\n```\ngo test ./...\ncargo build\nsome prose line\n```\n' >"$POLY/README.md"
commit "$POLY" "PROJ-5 init"
out="$TMP/poly.json"
bash "$SCAN" "$POLY" >"$out"
check "$out" '.stacks == [
  {"id": "cargo", "dir": ".", "evidence": ["Cargo.toml"]},
  {"id": "go", "dir": ".", "evidence": ["go.mod"]},
  {"id": "gradle", "dir": ".", "evidence": ["settings.gradle.kts"]},
  {"id": "maven", "dir": ".", "evidence": ["pom.xml"]},
  {"id": "python", "dir": ".", "evidence": ["pyproject.toml", "requirements.txt"]},
  {"id": "ruby", "dir": ".", "evidence": ["Gemfile"]},
  {"id": "gradle", "dir": "app", "evidence": ["app/build.gradle.kts"]},
  {"id": "python", "dir": "services/api", "evidence": ["services/api/pyproject.toml"]},
  {"id": "dotnet", "dir": "src/Tool", "evidence": ["src/Tool/Tool.csproj"]}]' "poly: ecosystems per directory, skipped and invalid manifests left out"
check "$out" '.tests.test_file_patterns == {"*_test.*": 1, "*.spec.*": 1, "*.test.*": 1, "test_*.*": 1, "*Test.*": 1}' "poly: test file name patterns"
check "$out" '.module_candidates | map(select(.pattern == "lib/*")) | .[0].looks_like_layers == true' "poly: lowercase layer names"
check "$out" '[.commands.documented_commands[].cmd] == ["go test ./...", "cargo build"]' "poly: commands of other ecosystems from a block without language"

# MARK: pipeline docs by name beyond the .ai list cap and by content
PIPE="$TMP/pipe"
init_repo "$PIPE"
mkdir -p "$PIPE/.ai/modules" "$PIPE/.ai/pipeline" "$PIPE/.ai/workspace" "$PIPE/docs" "$PIPE/.claude/commands"
for i in $(seq -w 1 65); do printf '# Module %s\n' "$i" >"$PIPE/.ai/modules/m$i.md"; done
printf '# Implementation\n' >"$PIPE/.ai/pipeline/implementation-pipeline.md"
printf '# Workflow\n\n## Phase 1: Plan\n\n## Phase 2: Build\n\nEach run writes RUN_ID to the log.\n' >"$PIPE/docs/workflow.md"
printf '# Ship\n\n## Faza 1\n\n## Faza 2\n\nOrkiestrator uruchamia role po kolei.\n' >"$PIPE/.claude/commands/ship.md"
printf '# Notes\n\n## Phase 1\n\n## Phase 2\n' >"$PIPE/docs/notes.md"
printf '# Agent\n\nThe orchestrator reads .claude/agents/reviewer.md.\n' >"$PIPE/docs/agent-spec.md"
printf '# Fenced\n\n```\n## Phase 1\n## Phase 2\n```\n\nRUN_ID\n' >"$PIPE/docs/fenced.md"
{ printf '# Big\n\n## Phase 1\n\n## Phase 2\n\nRUN_ID orchestrator\n'; head -c 300000 /dev/zero | tr '\0' 'x'; } >"$PIPE/docs/huge.md"
printf '## Phase 1\n## Phase 2\nRUN_ID\n' >"$PIPE/.ai/workspace/run.md"
commit "$PIPE" "PROJ-6 docs"
out="$TMP/pipe.json"
bash "$SCAN" "$PIPE" >"$out"
check "$out" '.ai_setup[".ai"] | length == 60' "pipe: .ai list stays capped"
check "$out" '.ai_setup.pipeline_docs == [".ai/pipeline/implementation-pipeline.md", ".claude/commands/ship.md", "docs/workflow.md"]' "pipe: by name past the cap and by content, weak, fenced, large and workspace files skipped"
check "$out" '.ai_setup.orchestration == true' "pipe: orchestration from pipeline docs"

# MARK: CI steps - anchors, compact lists, multi-line scripts, GitHub jobs, GitLab jobs with CRLF
CIX="$TMP/ci"
init_repo "$CIX"
mkdir -p "$CIX/.github/workflows"
cat >"$CIX/bitbucket-pipelines.yml" <<'EOF4'
definitions:
  steps:
    - step: &unit
        name: Unit tests
        script:
        - make deps
        - |
          make test
          make coverage
        caches:
        - deps
    - step: &lint
        name: Lint
        script:
          - make lint
pipelines:
  pull-requests:
    '**':
      - step: *unit
      - step:
          <<: *lint
          name: Lint on PR
  custom:
    release:
      - variables:
          - name: VERSION
      - stage:
          name: Release stage
          steps:
            - step:
                script:
                  - ./release.sh
EOF4
cat >"$CIX/.github/workflows/ci.yml" <<'EOF5'
name: CI
on:
  pull_request:
jobs:
  test:
    name: Test suite
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: src
    steps:
      - uses: actions/checkout@v4
      - run: make deps
      - name: Test
        run: |
          make test
          make report
EOF5
{ printf 'on: push\njobs:\n  many:\n    steps:\n'; for i in $(seq 1 65); do printf '      - run: echo %s\n' "$i"; done; } >"$CIX/.github/workflows/many.yml"
awk '{ printf "%s\r\n", $0 }' >"$CIX/.gitlab-ci.yml" <<'EOF6'
stages:
  - test
.setup: &setup
  - make deps
before_script:
  - echo start
.base:
  script:
    - make base
unit:
  stage: test
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - *setup
    - make test
lint:
  stage: test
  extends: .base
EOF6
commit "$CIX" "PROJ-7 ci"
out="$TMP/ci.json"
bash "$SCAN" "$CIX" >"$out"
ci() { printf '.commands.ci | map(select(.file == "%s")) | .[0]' "$1"; }
check "$out" "$(ci bitbucket-pipelines.yml) | .steps_total == 5 and .steps == [
  {\"section\": \"definitions\", \"name\": \"Unit tests\", \"commands\": [\"make deps\", \"make test\", \"make coverage\"], \"anchor\": \"unit\"},
  {\"section\": \"definitions\", \"name\": \"Lint\", \"commands\": [\"make lint\"], \"anchor\": \"lint\"},
  {\"section\": \"pull-requests:**\", \"name\": \"Unit tests\", \"commands\": [\"make deps\", \"make test\", \"make coverage\"], \"ref\": \"unit\"},
  {\"section\": \"pull-requests:**\", \"name\": \"Lint on PR\", \"commands\": [\"make lint\"], \"ref\": \"lint\"},
  {\"section\": \"custom:release\", \"name\": null, \"commands\": [\"./release.sh\"]}]" "ci: Bitbucket anchors, compact and multi-line scripts, variables and stages"
check "$out" "$(ci .github/workflows/ci.yml) | .steps == [
  {\"section\": \"jobs\", \"name\": null, \"commands\": [\"make deps\"], \"job\": \"test\", \"job_name\": \"Test suite\"},
  {\"section\": \"jobs\", \"name\": \"Test\", \"commands\": [\"make test\", \"make report\"], \"job\": \"test\", \"job_name\": \"Test suite\"}]" "ci: GitHub steps per job, defaults.run skipped"
check "$out" "$(ci .github/workflows/many.yml) | .steps_total == 65 and (.steps | length) == 60 and .steps[59].commands == [\"echo 60\"]" "ci: at most 60 steps with the total"
check "$out" "$(ci .gitlab-ci.yml) | .steps == [
  {\"section\": null, \"name\": \".setup\", \"commands\": [\"make deps\"], \"anchor\": \"setup\", \"job\": \".setup\"},
  {\"section\": null, \"name\": \"before_script\", \"commands\": [\"echo start\"], \"job\": \"before_script\"},
  {\"section\": null, \"name\": \".base\", \"commands\": [\"make base\"], \"job\": \".base\"},
  {\"section\": \"test\", \"name\": \"unit\", \"commands\": [\"make deps\", \"make test\"], \"job\": \"unit\"},
  {\"section\": \"test\", \"name\": \"lint\", \"commands\": [\"make base\"], \"ref\": \".base\", \"job\": \"lint\"}]" "ci: GitLab jobs with CRLF, script alias, rules and extends"

# MARK: errors
out="$(bash "$SCAN" "$TMP/missing")"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q '"error"' && ok || fail "missing directory: code $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

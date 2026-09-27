#!/bin/bash
# Cross-stack tests for the adapters section of scan.sh (php_symfony, ios_xcode, android, angular).
# Builds repos at run time from the fixtures of each adapter: one repo with all four stacks, one with a
# malformed manifest per stack, and runs scan.sh from temporary copies of scripts/ with missing, failing and
# invalid adapters at the same time. Checks the shared contract: fixed keys, statuses, reasons in
# scan.incomplete, adapter cuts in scan.truncated with the "adapters.<key>." prefix, scan.complete, no facts
# from failed adapters, determinism and no secret canaries in the adapters section.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$SKILL/scripts/scan.sh"
FX="$SKILL/tests/fixtures"
BASH_BIN=/bin/bash
[ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
PASS=0; FAIL=0
run="$(mktemp -d)"
trap 'rm -rf "$run"' EXIT
export TMPDIR="$run"
KEYS='["php_symfony", "ios_xcode", "android", "angular"]'

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
check() { jq -e "$3" "$run/$1.json" >/dev/null 2>&1 && ok || fail "$1: $2"; }
code_is() { [ "$(cat "$run/$1.code")" = "$2" ] && ok || fail "$1: exit code $2 (got $(cat "$run/$1.code"))"; }
one_object() { jq -e -s 'length == 1 and (.[0] | type) == "object"' "$run/$1.json" >/dev/null 2>&1 && ok || fail "$1: stdout is not one JSON object"; }
# skill NAME - a copy of scripts/ in $run/skill-NAME; prints the path of its scan.sh
skill() { mkdir -p "$run/skill-$1" && cp -R "$SKILL/scripts" "$run/skill-$1/" && printf '%s\n' "$run/skill-$1/scripts/scan.sh"; }
# scan NAME DIR [SCAN_SH] - runs scan.sh; JSON in NAME.json, exit code in NAME.code
scan() {
  "$BASH_BIN" "${3:-$SCAN}" "$2" >"$run/$1.json" 2>"$run/$1.err"
  echo $? >"$run/$1.code"
}
# contract NAME - the shared rules for every adapter entry, whatever its status
contract() {
  code_is "$1" 0
  one_object "$1"
  check "$1" "every adapter key, fixed order" ".adapters | keys_unsorted == $KEYS"
  check "$1" "every entry has status, ran, exit_code, reason, trigger" 'all(.adapters[];
    (.status | IN("ok", "incomplete", "not_applicable", "unavailable", "error")) and has("ran") and has("exit_code")
    and has("reason") and has("trigger"))'
  check "$1" "scan.incomplete lists exactly the adapters that are incomplete, unavailable or error" \
    '[.adapters | to_entries[] | select(.value.status | IN("incomplete", "unavailable", "error")) | {field: ("adapters." + .key), status: .value.status, reason: .value.reason}]
     == [.scan.incomplete[] | select(.field | startswith("adapters."))]'
  check "$1" "adapter cuts merged with the key prefix" \
    '[.adapters | to_entries[] | .key as $k | .value | select(.status | IN("ok", "incomplete")) | .truncated[] | "adapters." + $k + "." + .field]
     == [.scan.truncated[] | select(.field | startswith("adapters.")) | .field]'
  check "$1" "scan.complete follows truncated and incomplete" '.scan.complete == ((.scan.truncated | length) == 0 and (.scan.incomplete | length) == 0)'
  check "$1" "ok means complete adapter facts" 'all(.adapters[] | select(.status == "ok"); .complete == true and .errors == [] and .truncated == [] and .reason == null)'
  check "$1" "no facts from adapters that did not run cleanly" 'all(.adapters[] | select(.status | IN("not_applicable", "unavailable", "error"));
    (keys - ["adapter", "status", "ran", "exit_code", "reason", "trigger"]) == [])'
  check "$1" "every adapter has a section time" '.scan.sections_sec | has("php_symfony") and has("ios_xcode") and has("android") and has("angular")'
  check "$1" "no secret canary in the adapters section" '.adapters | tostring | test("CANARY|OUTSIDE_CANARY") | not'
}

# MARK: one repo, four stacks

R="$run/multi"
mkdir -p "$R/backend" "$R/ios/App.xcodeproj" "$R/web"
cp "$FX/php-symfony/integration/sf74/composer.json" "$R/backend/"
cp "$FX/ios-xcode/templates/min.pbxproj" "$R/ios/App.xcodeproj/project.pbxproj"
cp -R "$FX/android/kts-catalog" "$R/android"
mkdir -p "$R/android/gradle/wrapper"
printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.10.2-all.zip\n' >"$R/android/gradle/wrapper/gradle-wrapper.properties"
cp -R "$FX/angular/ng-app/." "$R/web/"

scan multi "$R"
contract multi
check multi "all four adapters ran cleanly" '[.adapters[] | [.status, .ran, .exit_code]] == [["ok", true, 0], ["ok", true, 0], ["ok", true, 0], ["ok", true, 0]]'
check multi "php facts from backend/" '.adapters.php_symfony | .summary.symfony == {framework: 1} and .apps[0].dir == "backend"'
check multi "ios facts from ios/" '.adapters.ios_xcode | .summary.projects == 1 and .projects[0].path == "ios/App.xcodeproj"'
check multi "android facts from android/" '.adapters.android | .summary.gradle_builds == 1 and .builds[0].dir == "android"'
check multi "angular facts from web/" '.adapters.angular | .summary.angular == {framework: 1} and .apps[0].dir == "web"'
check multi "triggers see every stack" '.adapters.php_symfony.trigger.composer_json_files == 1 and .adapters.ios_xcode.trigger.xcode_dirs == 1
  and .adapters.android.trigger.settings_files == 1 and .adapters.angular.trigger.package_json_angular_mentions == 1'
check multi "stacks stay neutral" '[.stacks[] | keys] | all(. == ["dir", "evidence", "id"])'
scan multi2 "$R"
a="$(jq -e -S -c '.adapters | map_values(del(.duration_sec))' "$run/multi.json" 2>/dev/null)" \
  && b="$(jq -e -S -c '.adapters | map_values(del(.duration_sec))' "$run/multi2.json" 2>/dev/null)" \
  && [ -n "$a" ] && [ "$a" = "$b" ] && ok || fail "multi: adapters section is not deterministic (or invalid JSON)"

# MARK: every adapter broken at once

S="$(skill broken)"
A="$run/skill-broken/scripts/adapters"
rm "$A/php-symfony/adapter.sh"
rm "$A/ios-xcode/xml.awk"
printf '#!/bin/bash\nexit 2\n' >"$A/android/adapter.sh"
printf '#!/bin/bash\necho "not json"\n' >"$A/angular/adapter.sh"
scan allbroken "$R" "$S"
contract allbroken
check allbroken "statuses per failure" '[.adapters[] | .status] == ["unavailable", "unavailable", "error", "error"]'
check allbroken "reasons name the cause" '.adapters.php_symfony.reason == "composer.json found but adapters/php-symfony/adapter.sh is missing; adapter not run"
  and (.adapters.ios_xcode.reason | test("adapters/ios-xcode/xml.awk is missing"))
  and .adapters.android.reason == "adapter exited with code 2: no output" and .adapters.android.exit_code == 2
  and (.adapters.angular.reason | test("exited with code 0 but stdout is not one angular JSON object"))'
check allbroken "ran only where the adapter started" '[.adapters[] | .ran] == [false, false, true, true]'
check allbroken "scan not complete, four reasons" '.scan.complete == false and ([.scan.incomplete[] | .field] == ["adapters.php_symfony", "adapters.ios_xcode", "adapters.android", "adapters.angular"])'

# MARK: one malformed manifest per stack

M="$run/malformed"
mkdir -p "$M/php" "$M/ios/Bad.xcodeproj" "$M/gradle" "$M/node"
printf '{"require": {"symfony/framework-bundle": "7.4.*"\n' >"$M/php/composer.json"
printf 'not a pbxproj\n' >"$M/ios/Bad.xcodeproj/project.pbxproj"
printf "rootProject.name = 'broken\ninclude ':app'\n" >"$M/gradle/settings.gradle"
printf '{"dependencies": {"@angular/core": \n' >"$M/node/package.json"
scan malformed "$M"
contract malformed
check malformed "each adapter ran and is incomplete" '[.adapters[] | [.status, .ran, .exit_code]] == [["incomplete", true, 0], ["incomplete", true, 0], ["incomplete", true, 0], ["incomplete", true, 0]]'
check malformed "first error names the broken file" '(.adapters.php_symfony.reason | test("php/composer.json"))
  and (.adapters.ios_xcode.reason | test("ios/Bad.xcodeproj/project.pbxproj"))
  and (.adapters.android.reason | test("gradle/settings.gradle")) and (.adapters.angular.reason | test("node/package.json"))'
check malformed "stacks skip the invalid JSON manifests, the adapters still run" '([.stacks[] | select(.id == "composer" or .id == "npm")] == [])
  and .adapters.php_symfony.trigger.stacks_composer_entries == 0 and .adapters.angular.trigger.package_json_invalid == 1'

# MARK: adapter directories absent

S="$(skill absent)"
rm -rf "$run/skill-absent/scripts/adapters/ios-xcode" "$run/skill-absent/scripts/adapters/android" "$run/skill-absent/scripts/adapters/angular"
scan absent_php "$FX/php-symfony/integration/sf74" "$S"
contract absent_php
check absent_php "not required: not_applicable even without the adapter files" '[.adapters[] | .status] == ["ok", "not_applicable", "not_applicable", "not_applicable"]
  and .scan.complete == true'
scan absent_multi "$R" "$S"
contract absent_multi
check absent_multi "required but absent: unavailable, first missing file named" '[.adapters[] | .status] == ["ok", "unavailable", "unavailable", "unavailable"]
  and (.adapters.ios_xcode.reason | test("adapters/ios-xcode/adapter.sh is missing"))
  and (.adapters.android.reason | test("adapters/android/adapter.sh is missing"))
  and (.adapters.angular.reason | test("adapters/angular/adapter.sh is missing"))'

# MARK: no stack at all

mkdir -p "$run/empty/docs"
printf '# Notes\n' >"$run/empty/docs/README.md"
scan empty "$run/empty"
contract empty
check empty "nothing applies, nothing runs" '[.adapters[] | [.status, .ran]] == [["not_applicable", false], ["not_applicable", false], ["not_applicable", false], ["not_applicable", false]]
  and all(.adapters[]; .reason | test("adapter not run"))'

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

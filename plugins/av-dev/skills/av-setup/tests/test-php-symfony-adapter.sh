#!/bin/bash
# Tests for scripts/adapters/php-symfony/adapter.sh and its scan.sh integration.
# Fixtures in tests/fixtures/php-symfony/: Symfony app, plain PHP, no composer.json, broken
# composer.json files, spaces in paths, limits and depth, excluded directories, secret canaries.
# Integration: adapters.php_symfony statuses (ok, incomplete, not_applicable, unavailable, error)
# with stub adapters from tests/fixtures/php-symfony/integration/stubs/ installed in a temporary
# copy of scripts/. Runs the adapter with /bin/bash (3.2 on macOS) when present.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
ADAPTER="$SKILL/scripts/adapters/php-symfony/adapter.sh"
FACTS_JQ="$SKILL/scripts/adapters/php-symfony/composer-facts.jq"
SCAN="$SKILL/scripts/scan.sh"
fx="$SKILL/tests/fixtures/php-symfony"
BASH_BIN=/bin/bash
[ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
PASS=0; FAIL=0
run="$(mktemp -d)"
trap 'rm -rf "$run"' EXIT
export TMPDIR="$run"

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
# adapter NAME ARGS... - runs adapter.sh; JSON in NAME.json, exit code in NAME.code
adapter() {
  local name="$1"; shift
  "$BASH_BIN" "$ADAPTER" "$@" >"$run/$name.json" 2>"$run/$name.err"
  echo $? >"$run/$name.code"
}
# check NAME DESCRIPTION JQ_EXPR - passes when the expression is true for NAME.json
check() { jq -e "$3" "$run/$1.json" >/dev/null 2>&1 && ok || fail "$1: $2"; }
code_is() { [ "$(cat "$run/$1.code")" = "$2" ] && ok || fail "$1: exit code $2 (got $(cat "$run/$1.code"))"; }
no_stderr() { [ -s "$run/$1.err" ] && fail "$1: stderr: $(head -3 "$run/$1.err" | tr '\n' ' ')" || ok; }
# no_canary NAME - NAME.json is one JSON object without a CANARY string; invalid or empty output fails
no_canary() {
  jq -e -s 'length == 1 and (.[0] | type) == "object"' "$run/$1.json" >/dev/null 2>&1 || { fail "$1: output is not one JSON object"; return; }
  grep -q CANARY "$run/$1.json" && fail "$1: secret canary leaked" || ok
}

# MARK: positive Symfony

adapter sym "$fx/symfony-app"
code_is sym 0
no_stderr sym
no_canary sym
check sym "schema" '.adapter == "php-symfony" and .schema_version == 1'
check sym "one app at root" '(.apps | length) == 1 and .apps[0].dir == "." and .summary.composer_manifests == 1'
check sym "excluded dirs reported, shallow first" '.excluded_dirs == [".claude", "node_modules", "var", "vendor", "config/.hidden"]'
check sym "no path from excluded dirs" '[.. | objects | .path? | strings | select(test("^(vendor|var|node_modules|\\.claude)/"))] | length == 0'
check sym "symfony framework" '.apps[0].symfony.present == "framework"'
check sym "symfony version from extra.symfony.require" \
  '.apps[0].symfony.declared_version == {constraint: "7.1.*", evidence: {path: "composer.json", key: "extra.symfony.require"}}'
check sym "symfony evidence keys" \
  '[.apps[0].symfony.evidence[].key] == ["require.symfony/framework-bundle", "require.symfony/flex", "extra.symfony"]'
check sym "php constraint" '.apps[0].php == {constraint: ">=8.2", evidence: {path: "composer.json", key: "require.php"}}'
check sym "php platform" '.apps[0].php_platform.value == "8.2.0" and .apps[0].php_platform.evidence.key == "config.platform.php"'
check sym "package counts" '.apps[0].packages_total == 12 and .apps[0].packages_ignored == 2'
check sym "packages sorted by section and name" '[.apps[0].packages[].name] == ["doctrine/orm", "lexik/jwt-authentication-bundle", "php",
  "symfony/console", "symfony/flex", "symfony/framework-bundle", "twig/twig", "behat/behat", "brianium/paratest", "phpstan/phpstan",
  "phpunit/phpunit", "symfony/phpunit-bridge"]'
check sym "package evidence = manifest key" 'all(.apps[0].packages[]; .evidence.path == "composer.json" and .evidence.key == (.section + "." + .name))'
check sym "package groups" '(.apps[0].packages | map({(.name): .group}) | add) as $g
  | $g["doctrine/orm"] == "doctrine" and $g["lexik/jwt-authentication-bundle"] == "bundle" and $g["phpstan/phpstan"] == "quality"
    and $g["behat/behat"] == "test" and $g["twig/twig"] == "templating" and $g["symfony/framework-bundle"] == "symfony_framework"'
check sym "config formats" '(.apps[0].config_formats.formats | map({(.format): .files}) | add) == {php: 2, xml: 1, yaml: 3}'
check sym "config secret-like files skipped" '.apps[0].config_formats.secret_like_skipped == 1 and .apps[0].config_formats.files_total == 6'
check sym "config excluded dirs" '.apps[0].config_formats.excluded_dirs == ["config/.hidden", "config/jwt", "config/secrets"]'
check sym "no env, key, secrets or hidden paths" '[.. | strings | select(test("\\.env|auth\\.json|secrets/|jwt/|\\.DS_Store|\\.hidden-note"))] | length == 0'
check sym "test tools" '[.apps[0].test_tools[].tool] == ["behat", "paratest", "phpunit"]'
check sym "phpunit evidence" '(.apps[0].test_tools[] | select(.tool == "phpunit") | [.evidence[] | .key // .path] | sort)
  == ["phpunit.xml.dist", "require-dev.phpunit/phpunit", "require-dev.symfony/phpunit-bridge"]'
check sym "autoload existence" '[.apps[0].autoload[] | .exists] == [true, true, false, null]'
check sym "autoload evidence key" '.apps[0].autoload[0].evidence == {path: "composer.json", key: "autoload.psr-4.App\\"}'
check sym "paths present in fixed order" '[.apps[0].paths.present[].path] == ["config", "config/packages", "config/routes",
  "config/bundles.php", "config/services.yaml", "config/routes.php", "src", "src/Kernel.php", "tests", "templates", "translations",
  "migrations", "bin/console", "symfony.lock"]'
check sym "paths evidence = path" 'all(.apps[0].paths.present[]; .evidence.path == .path)'
check sym "paths absent" '.apps[0].paths.absent | (index("public") != null and index("composer.lock") != null)'
check sym "complete" '.complete == true and .truncated == [] and .errors == []'
check sym "installed versions marked unknown" 'any(.apps[0].unknown[]; .field == "installed_versions")'
check sym "no inferred architecture keys" '[paths | map(tostring) | join(".") | select(test("layer|module|domain|bounded|architecture|relation"; "i"))] | length == 0'

adapter sym2 "$fx/symfony-app"
a="$(jq -e -S -c 'del(.started, .duration_sec)' "$run/sym.json" 2>/dev/null)" && b="$(jq -e -S -c 'del(.started, .duration_sec)' "$run/sym2.json" 2>/dev/null)" \
  && [ -n "$a" ] && [ "$a" = "$b" ] && ok || fail "sym2: deterministic output (or invalid JSON)"

# MARK: plain PHP and missing composer.json

adapter plain "$fx/plain-php"
code_is plain 0
check plain "no symfony" '.apps[0].symfony.present == "none" and .apps[0].symfony.declared_version == null and .apps[0].symfony.evidence == []'
check plain "packages" '[.apps[0].packages[].name] == ["php", "phpunit/phpunit"] and .apps[0].packages_ignored == 1'
check plain "library type" '.apps[0].composer.type == "library" and .apps[0].composer.evidence == [{path: "composer.json", key: "name"}, {path: "composer.json", key: "type"}]'
check plain "phpunit from file and package" '.apps[0].test_tools == [{tool: "phpunit", evidence: [{path: "composer.json", key: "require-dev.phpunit/phpunit", value: "^10.5"}, {path: "phpunit.xml"}]}]'
check plain "no config dir" '.apps[0].config_formats == null and any(.apps[0].unknown[]; .field == "config_formats")'
check plain "complete" '.complete == true'

adapter none "$fx/no-composer"
code_is none 0
check none "no apps" '.apps == [] and .summary.composer_manifests == 0'
check none "composer unknown" 'any(.unknown[]; .field == "composer")'
check none "complete" '.complete == true'

# MARK: broken composer.json

adapter broken "$fx/broken"
code_is broken 0
no_stderr broken
check broken "all manifests reported" '[.apps[].dir] == ["empty", "malformed", "not-object", "odd-types", "two-docs"]'
check broken "statuses" '[.apps[].composer.status] == ["malformed", "malformed", "malformed", "ok", "malformed"]'
check broken "errors with paths" '(.errors | length) == 4 and all(.errors[]; .path | endswith("/composer.json"))'
check broken "not complete" '.complete == false'
check broken "malformed means unknown symfony" 'all(.apps[] | select(.composer.status == "malformed"); .symfony.present == "unknown" and any(.unknown[]; .field == "composer"))'
check broken "odd types tolerated" '.apps[3] | .composer.name == "5" and .symfony.present == "components_only"
  and .packages == [{name: "symfony/console", constraint: "[\"7.1.*\"]", section: "require-dev", group: "symfony",
    evidence: {path: "odd-types/composer.json", key: "require-dev.symfony/console"}}]
  and ([.autoload[] | {path, exists}] == [{path: "src/", exists: false}]) and any(.unknown[]; .field == "php.constraint")'

# MARK: spaces in paths

adapter space "$fx/space root"
code_is space 0
check space "dir with space" '.apps[0].dir == "sub app" and .apps[0].manifest == "sub app/composer.json"'
check space "symfony/symfony counts as framework" '.apps[0].symfony.present == "framework"
  and .apps[0].symfony.declared_version == {constraint: "6.4.*", evidence: {path: "sub app/composer.json", key: "require.symfony/symfony"}}'
check space "config path with spaces" '.apps[0].config_formats.formats == [{format: "yaml", files: 1, evidence: [{path: "sub app/config/pack ages/my file.yaml"}]}]'
check space "autoload dir with space exists" '.apps[0].autoload[0].exists == true'

# MARK: limits and depth

adapter lim "$fx/limits"
code_is lim 0
check lim "apps within depth" '.summary.composer_manifests == 5 and [.apps[].dir] == [".", "a", "b", "c", "d"]'
check lim "unpinned symfony version is unknown" '.apps[0].symfony.declared_version.constraint == "*"
  and any(.apps[0].unknown[]; .field == "symfony.declared_version")'
check lim "config depth cut reported" 'any(.truncated[]; .reason == "depth" and .field == "apps[.].config_formats depth" and .total == null)'
check lim "not complete" '.complete == false'

adapter limsmall "$fx/limits" --max-apps 3 --max-packages 2 --max-autoload 1 --max-config-files 2
code_is limsmall 0
check limsmall "apps cut" '[.apps[].dir] == [".", "a", "b"] and any(.truncated[]; .field == "apps" and .shown == 3 and .total == 5)'
check limsmall "packages cut" '(.apps[0].packages | length) == 2 and any(.truncated[]; .field == "apps[.].packages" and .total == 4)'
check limsmall "autoload cut" '(.apps[0].autoload | length) == 1 and any(.truncated[]; .field == "apps[.].autoload" and .total == 2)'
check limsmall "config files cut" '([.apps[0].config_formats.formats[].files] | add) == 2 and .apps[0].config_formats.files_total == 3
  and any(.truncated[]; .field == "apps[.].config_formats files" and .shown == 2 and .total == 3)'
check limsmall "limits echoed" '.limits.max_apps == 3 and .limits.max_packages == 2 and .limits.max_autoload == 1 and .limits.max_config_files == 2'

adapter limdeep "$fx/limits" --max-depth 4
check limdeep "deeper manifest found with --max-depth 4" '.summary.composer_manifests == 6 and any(.apps[]; .dir == "deep/l2/l3/l4")'

# MARK: symlinked config and bad input

mkdir -p "$run/symlink-app/real-config/packages"
printf '{"require": {"symfony/framework-bundle": "7.1.*"}}\n' >"$run/symlink-app/composer.json"
printf 'a: 1\n' >"$run/symlink-app/real-config/packages/a.yaml"
ln -s real-config "$run/symlink-app/config"
adapter symlink "$run/symlink-app"
check symlink "symlinked config not followed" '.apps[0].config_formats == null
  and any(.apps[0].paths.present[]; .path == "config" and .type == "symlink")'

adapter badopt "$fx/symfony-app" --max-apps x
code_is badopt 2
check badopt "error JSON" '.error | test("needs a non-negative number")'
adapter badroot "$run/does-not-exist"
code_is badroot 2
check badroot "error JSON" '.error == "directory not found"'

# MARK: scan.sh integration

# scan_case NAME DIR [ADAPTER] - runs scan.sh on DIR. ADAPTER: empty = the skill scan.sh with all adapters;
# otherwise a copy of scripts/ with "missing" = no php-symfony adapter.sh, "nojq" = no composer-facts.jq,
# or a stub from integration/stubs/ installed as the php-symfony adapter.sh. JSON in NAME.json, exit code in NAME.code.
scan_case() {
  local name="$1" dir="$2" adp="${3:-}" sk="$run/skill-$1" scan="$SCAN"
  if [ -n "$adp" ]; then
    mkdir -p "$sk"
    cp -R "$SKILL/scripts" "$sk/"
    scan="$sk/scripts/scan.sh"
    case "$adp" in
      missing) rm "$sk/scripts/adapters/php-symfony/adapter.sh" ;;
      nojq) rm "$sk/scripts/adapters/php-symfony/composer-facts.jq" ;;
      *) cp "$fx/integration/stubs/$adp" "$sk/scripts/adapters/php-symfony/adapter.sh" ;;
    esac
  fi
  "$BASH_BIN" "$scan" "$dir" >"$run/$name.json" 2>"$run/$name.err"
  echo $? >"$run/$name.code"
}
# scan_not_ok NAME STATUS REASON_REGEX - scan JSON printed with exit 0, scan.complete false, the adapter status and
# a matching reason in scan.incomplete; for error and unavailable no adapter facts or adapter cuts are kept
scan_not_ok() {
  code_is "$1" 0
  check "$1" "scan.complete false" '.scan.complete == false'
  check "$1" "status $2" ".adapters.php_symfony.status == \"$2\""
  check "$1" "reason in scan.incomplete" "any(.scan.incomplete[]?; .field == \"adapters.php_symfony\" and .status == \"$2\" and (.reason | test(\"$3\")))"
  case "$2" in error|unavailable)
    check "$1" "no adapter facts or cuts kept" '(.adapters.php_symfony | has("apps") or has("summary") | not)
      and ([.scan.truncated[] | select(.field | startswith("adapters."))] == [])' ;;
  esac
}
ifx="$fx/integration"

scan_case scan_sym "$fx/symfony-app"
check scan_sym "adapter section in scan" '.adapters.php_symfony.summary.symfony == {framework: 1} and .scan.schema_version == 2'
check scan_sym "adapter time in sections_sec" '.scan.sections_sec | has("php_symfony")'
check scan_sym "no adapter truncation" '[.scan.truncated[] | select(.field | startswith("adapters."))] == []'
check scan_sym "status ok, ran, exit 0" '.adapters.php_symfony | .status == "ok" and .ran == true and .exit_code == 0 and .reason == null'

scan_case scan_sf74 "$ifx/sf74"
code_is scan_sf74 0
check scan_sf74 "symfony 7.4.* app: ok and complete" '.adapters.php_symfony.status == "ok"
  and .adapters.php_symfony.apps[0].symfony.declared_version.constraint == "7.4.*"
  and .scan.complete == true and .scan.incomplete == []'
check scan_sf74 "trigger evidence" '.adapters.php_symfony.trigger == {composer_json_files: 1, stacks_composer_entries: 1}'

scan_case scan_none "$fx/no-composer"
check scan_none "no composer: not_applicable, not run" '.adapters.php_symfony | .status == "not_applicable" and .ran == false
  and .exit_code == null and (has("apps") | not) and (.reason | test("not run"))'
check scan_none "not_applicable keeps scan complete" '.scan.complete == true and .scan.incomplete == []'

scan_case scan_lim "$fx/limits"
check scan_lim "adapter truncation merged" 'any(.scan.truncated[]; .field == "adapters.php_symfony.apps[.].config_formats depth") and .scan.complete == false'
scan_not_ok scan_lim incomplete "complete=false"

scan_case scan_brokensub "$ifx/sf74-broken-sub"
scan_not_ok scan_brokensub incomplete "1 errors.*legacy/composer.json"
check scan_brokensub "adapter errors kept" '.adapters.php_symfony.errors | length == 1'

scan_case scan_malformed "$ifx/malformed-only"
scan_not_ok scan_malformed incomplete "composer.json is not a single valid JSON object"
check scan_malformed "malformed composer skipped by stacks still runs the adapter" '.stacks == []
  and .adapters.php_symfony.ran == true and .adapters.php_symfony.trigger == {composer_json_files: 1, stacks_composer_entries: 0}'

scan_case scan_missing "$ifx/sf74" missing
scan_not_ok scan_missing unavailable "adapter.sh is missing"
check scan_missing "not run" '.adapters.php_symfony.ran == false'
scan_case scan_nojq "$ifx/sf74" nojq
scan_not_ok scan_nojq unavailable "composer-facts.jq is missing"

scan_case scan_exit2json "$ifx/sf74" exit2-valid-json.sh
scan_not_ok scan_exit2json error "exited with code 2"
check scan_exit2json "exit code recorded" '.adapters.php_symfony.exit_code == 2 and .adapters.php_symfony.ran == true'
scan_case scan_exit2err "$ifx/sf74" exit2-error-json.sh
scan_not_ok scan_exit2err error "code 2: composer-facts.jq not found"
scan_case scan_exit2silent "$ifx/sf74" exit2-silent.sh
scan_not_ok scan_exit2silent error "code 2: no output"
scan_case scan_killed "$ifx/sf74" killed.sh
scan_not_ok scan_killed error "exited with code 137"
scan_case scan_garbage "$ifx/sf74" garbage.sh
scan_not_ok scan_garbage error "not one php-symfony JSON object"
scan_case scan_twodocs "$ifx/sf74" two-docs.sh
scan_not_ok scan_twodocs error "not one php-symfony JSON object"
scan_case scan_schema "$ifx/sf74" wrong-schema.sh
scan_not_ok scan_schema error "not one php-symfony JSON object"
scan_case scan_badcut "$ifx/sf74" bad-truncated.sh
scan_not_ok scan_badcut error "not one php-symfony JSON object"
scan_case scan_silent "$ifx/sf74" silent-incomplete.sh
scan_not_ok scan_silent incomplete "complete=false, 0 errors, 0 truncated"
scan_case scan_inconsistent "$ifx/sf74" inconsistent.sh
scan_not_ok scan_inconsistent incomplete "1 errors"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

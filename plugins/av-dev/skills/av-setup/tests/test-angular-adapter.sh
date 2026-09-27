#!/bin/bash
# Tests for scripts/adapters/angular/adapter.sh and its scan.sh integration.
# Fixtures in tests/fixtures/angular/: Angular app, monorepo with a library, plain Node, AngularJS,
# tooling only, no manifest, angular.json only, npm lockfile v1, broken package.json, angular.json
# and lockfiles, spaces in paths, limits and depth, excluded directories, secret canaries.
# Runtime cases in a temporary directory: symlinks out of ROOT, symlinked angular.json, size limits,
# unreadable files, bad options, missing jq files, determinism, no writes to the fixtures.
# Optional: AV_ANGULAR_REAL_ROOT=/path/to/angular/repo checks a real repository read-only.
# Integration: adapters.angular statuses (ok, incomplete, not_applicable, unavailable, error) with stub
# adapters from tests/fixtures/angular/integration/stubs/ installed in a temporary copy of scripts/.
# Runs the adapter with /bin/bash (3.2 on macOS) when present. Last line: PASS n SKIP n FAIL n.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
ADIR="$SKILL/scripts/adapters/angular"
ADAPTER="$ADIR/adapter.sh"
SCAN="$SKILL/scripts/scan.sh"
fx="$SKILL/tests/fixtures/angular"
BASH_BIN=/bin/bash
[ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
PASS=0; FAIL=0; SKIP=0
run="$(mktemp -d)"
trap 'chmod -R u+rwx "$run" 2>/dev/null; rm -rf "$run"' EXIT
export TMPDIR="$run"
: >"$run/marker"
sleep 1

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s\n' "$1" >&2; }
# adapter NAME ARGS... - runs adapter.sh; JSON in NAME.json, exit code in NAME.code, seconds in NAME.sec
adapter() {
  local name="$1" t; shift
  t=$SECONDS
  "$BASH_BIN" "$ADAPTER" "$@" >"$run/$name.json" 2>"$run/$name.err"
  echo $? >"$run/$name.code"
  echo $((SECONDS - t)) >"$run/$name.sec"
}
# check NAME DESCRIPTION JQ_EXPR - passes when the expression is true for NAME.json
check() { jq -e "$3" "$run/$1.json" >/dev/null 2>&1 && ok || fail "$1: $2"; }
code_is() { [ "$(cat "$run/$1.code")" = "$2" ] && ok || fail "$1: exit code $2 (got $(cat "$run/$1.code"))"; }
no_stderr() { [ -s "$run/$1.err" ] && fail "$1: stderr: $(head -3 "$run/$1.err" | tr '\n' ' ')" || ok; }
# no_canary NAME - NAME.json is one JSON object and has no CANARY string; invalid or empty output fails
no_canary() {
  jq -e -s 'length == 1 and (.[0] | type) == "object"' "$run/$1.json" >/dev/null 2>&1 || { fail "$1: output is not one JSON object"; return; }
  grep -q CANARY "$run/$1.json" && fail "$1: secret canary leaked" || ok
}
# same_data A B - equal output without the run-dependent keys root, started and duration_sec
same_data() {
  local a b
  a="$(jq -e -S -c 'del(.root, .started, .duration_sec)' "$run/$1.json" 2>/dev/null)" || { fail "$1: output is not valid JSON"; return; }
  b="$(jq -e -S -c 'del(.root, .started, .duration_sec)' "$run/$2.json" 2>/dev/null)" || { fail "$2: output is not valid JSON"; return; }
  [ -n "$a" ] && [ "$a" = "$b" ] && ok || fail "$1 vs $2: data differs"
}

# MARK: positive Angular app

adapter ng "$fx/ng-app"
code_is ng 0
no_stderr ng
no_canary ng
check ng "schema" '.adapter == "angular" and .schema_version == 1'
check ng "one app at root" '(.apps | length) == 1 and .apps[0].dir == "." and .summary.manifest_dirs == 1 and .summary.angular_workspaces == 1'
check ng "excluded dirs reported, shallow first" '.excluded_dirs == [".angular", ".claude", "dist", "node_modules", "public"]'
check ng "no path from excluded dirs" '[.. | objects | .path? | strings | select(test("^(dist|\\.angular|\\.claude|public)/"))] == []'
check ng "node_modules only through the fixed key package files" \
  '[.. | objects | .path? | strings | select(startswith("node_modules/"))] | unique == ["node_modules/@angular/cli/package.json", "node_modules/@angular/core/package.json"]'
check ng "angular framework" '.apps[0].angular.present == "framework" and .summary.angular == {framework: 1}'
check ng "angular evidence" '.apps[0].angular.evidence == [{path: "package.json", key: "dependencies.@angular/core", value: "^21.2.12"}]'
check ng "declared version" '.apps[0].angular.declared_version == {constraint: "^21.2.12", major: 21, section: "dependencies",
  evidence: {path: "package.json", key: "dependencies.@angular/core"}}'
check ng "declared key packages in fixed order" '[.apps[0].versions.declared[].name] == ["@angular/core", "@angular/cli",
  "@angular-devkit/build-angular", "typescript", "rxjs", "zone.js"]'
check ng "locked versions from package-lock.json" '.apps[0].versions.locked == [
  {name: "@angular/core", version: "21.2.12", evidence: {path: "package-lock.json", key: "packages.node_modules/@angular/core.version"}},
  {name: "@angular/cli", version: "21.2.10", evidence: {path: "package-lock.json", key: "packages.node_modules/@angular/cli.version"}},
  {name: "typescript", version: "5.9.3", evidence: {path: "package-lock.json", key: "packages.node_modules/typescript.version"}}]
  and .apps[0].versions.lockfile_version == 3'
check ng "installed versions from node_modules key packages" '.apps[0].versions.installed == [
  {name: "@angular/core", version: "21.2.12", evidence: {path: "node_modules/@angular/core/package.json", key: "version"}},
  {name: "@angular/cli", version: "21.2.9", evidence: {path: "node_modules/@angular/cli/package.json", key: "version"}}]'
check ng "declared, locked and installed kept apart" '.apps[0].versions as $v
  | ($v.declared[] | select(.name == "@angular/cli") | .constraint) == "^21.2.10"
  and ($v.locked[] | select(.name == "@angular/cli") | .version) == "21.2.10"
  and ($v.installed[] | select(.name == "@angular/cli") | .version) == "21.2.9"'
check ng "lockfiles" '.apps[0].lockfiles == [{path: "package-lock.json", format: "npm", status: "read"}]'
check ng "engines and package manager" '.apps[0].engines_node == {constraint: ">=22.12.0", evidence: {path: "package.json", key: "engines.node"}}
  and .apps[0].package_manager.value == "npm@10.9.2"'
check ng "package counts" '.apps[0].packages_total == 17 and .apps[0].packages_ignored == 2'
check ng "packages sorted by section and name" '[.apps[0].packages[].name] == ["@angular/common", "@angular/core", "@angular/router",
  "@ngx-translate/core", "rxjs", "tslib", "zone.js", "@angular-devkit/build-angular", "@angular/cli", "@angular/compiler-cli",
  "@playwright/test", "@types/jasmine", "eslint", "jasmine-core", "karma", "karma-chrome-launcher", "typescript"]'
check ng "package evidence = manifest key" 'all(.apps[0].packages[]; .evidence.path == "package.json" and .evidence.key == (.section + "." + .name))'
check ng "package groups" '(.apps[0].packages | map({(.name): .group}) | add) as $g
  | $g["@angular/core"] == "angular" and $g["@angular/cli"] == "angular_tooling" and $g["@angular-devkit/build-angular"] == "angular_tooling"
    and $g["@ngx-translate/core"] == "angular_ecosystem_name" and $g["karma"] == "test" and $g["eslint"] == "quality" and $g["zone.js"] == "runtime"'
check ng "unrelated packages not listed" '[.apps[0].packages[].name] | (index("lodash") == null and index("private-lib") == null)'
check ng "workspace basics" '.apps[0].workspace | .status == "ok" and .version == {value: 1, evidence: {path: "angular.json", key: "version"}}
  and .new_project_root == "projects" and .cli == {package_manager: null, schematic_collections: ["@angular-eslint/schematics"]}
  and .projects_total == 1'
check ng "project facts" '.apps[0].workspace.projects[0] | .name == "ng-app" and .project_type == "application" and .root == ""
  and .root_exists == true and .source_root == "src" and .source_root_exists == true and .prefix == "app"
  and .targets_key == "architect" and .evidence == {path: "angular.json", key: "projects.ng-app"}'
check ng "targets sorted" '[.apps[0].workspace.projects[0].targets[].name] == ["build", "lint", "serve", "test"]'
check ng "build target" '.apps[0].workspace.projects[0].targets[0] | .builder == "@angular-devkit/build-angular:application"
  and .configurations == ["development", "production"] and .configurations_total == 2 and .default_configuration == "production"
  and .evidence == {path: "angular.json", key: "projects.ng-app.architect.build.builder", value: "@angular-devkit/build-angular:application"}
  and [.option_files[] | {key, path, exists}] == [{key: "tsConfig", path: "tsconfig.app.json", exists: true},
    {key: "browser", path: "src/main.ts", exists: true}, {key: "index", path: "src/index.html", exists: true}]'
check ng "option file evidence key" '.apps[0].workspace.projects[0].targets[0].option_files[0].evidence == {path: "angular.json", key: "projects.ng-app.architect.build.options.tsConfig"}'
check ng "missing option file" '[.apps[0].workspace.projects[0].targets[2].option_files[] | {key, path, exists}] == [{key: "proxyConfig", path: "proxy.conf.json", exists: false}]'
check ng "test target files" '[.apps[0].workspace.projects[0].targets[3].option_files[] | {key, exists}] == [{key: "tsConfig", exists: true}, {key: "karmaConfig", exists: true}]'
check ng "no option values outside the fixed file keys" '[.. | strings | select(test("define|fileReplacements|environment\\.prod|analytics|lintFilePatterns|outputPath"))] == []'
check ng "test tools" '[.apps[0].test_tools[].tool] == ["jasmine", "karma", "playwright"]'
check ng "karma evidence from builder, file and package" '(.apps[0].test_tools[] | select(.tool == "karma") | .evidence) == [
  {path: "angular.json", key: "projects.ng-app.architect.test.builder", value: "@angular-devkit/build-angular:karma"},
  {path: "karma.conf.js"}, {path: "package.json", key: "devDependencies.karma", value: "^6.4.4"}]'
check ng "paths present in fixed order" '[.apps[0].paths.present[].path] == ["angular.json", "tsconfig.json", "tsconfig.app.json",
  "tsconfig.spec.json", "src", "src/main.ts", "src/app", "src/environments", "src/assets", "public", "package-lock.json", "node_modules"]'
check ng "paths evidence = path" 'all(.apps[0].paths.present[]; .evidence.path == .path)'
check ng "paths absent" '.apps[0].paths.absent | (index("nx.json") != null and index("yarn.lock") != null and index("e2e") != null)'
check ng "no env, npmrc, key or environment file names" '[.. | strings | select(test("\\.env|\\.npmrc|\\.key|environment\\.|karma\\.conf\\.js.*token"))] == []'
check ng "complete" '.complete == true and .truncated == [] and .errors == [] and .apps[0].unknown == []'
check ng "deeper manifests marked unknown" 'any(.unknown[]; .field == "deeper_manifests")'
check ng "no inferred architecture keys" '[paths | map(tostring) | join(".") | select(test("layer|module_graph|domain|bounded|architecture|relation|feature"; "i"))] == []'

adapter ng2 "$fx/ng-app"
same_data ng ng2
(cd "$fx" && "$BASH_BIN" "$ADAPTER" ./ng-app >"$run/ng3.json" 2>"$run/ng3.err"; echo $? >"$run/ng3.code")
same_data ng ng3
LC_ALL=C "$BASH_BIN" "$ADAPTER" "$fx/ng-app" >"$run/ng4.json" 2>/dev/null
same_data ng ng4

# MARK: monorepo with a library

adapter mono "$fx/ng-monorepo"
code_is mono 0
no_stderr mono
check mono "apps" '[.apps[].dir] == [".", "projects/shared-ui"] and .summary.angular == {framework: 2} and .summary.angular_workspaces == 1'
check mono "declared tilde version" '.apps[0].angular.declared_version | .constraint == "~20.1.3" and .major == 20'
check mono "packages" '[.apps[0].packages[] | [.name, .group]] == [["@angular/core", "angular"], ["@ngrx/store", "angular_ecosystem_name"],
  ["@angular-builders/jest", "angular_tooling"], ["@angular/build", "angular_tooling"], ["jest", "test"], ["jest-preset-angular", "test"], ["vitest", "test"]]'
check mono "npm workspaces" '.apps[0].workspaces == {total: 1, patterns: ["projects/*"], evidence: {path: "package.json", key: "workspaces"}}'
check mono "yarn lockfile listed, not parsed" '.apps[0].lockfiles == [{path: "yarn.lock", format: "yarn", status: "not_parsed"}]
  and .apps[0].versions.locked == [] and any(.apps[0].unknown[]; .field == "versions.locked" and (.reason | test("not parsed")))'
check mono "no node_modules: installed unknown" '.apps[0].versions.installed == [] and any(.apps[0].unknown[]; .field == "versions.installed")'
check mono "projects sorted, broken entry kept" '[.apps[0].workspace.projects[].name] == ["admin", "broken-entry", "shared-ui"]
  and .apps[0].workspace.projects[1] == {name: "broken-entry", error: "project entry is not an object", evidence: {path: "angular.json", key: "projects.broken-entry"}}'
check mono "broken project entry is an error" 'any(.errors[]; .path == "angular.json" and .error == "angular.json projects.broken-entry is not an object") and .complete == false'
check mono "targets alias" '.apps[0].workspace.projects[2] | .targets_key == "targets" and .targets[0].builder == "@angular-builders/jest:run"
  and .targets[0].evidence.key == "projects.shared-ui.targets.test.builder" and .targets[0].option_files[0].exists == true'
check mono "path outside the workspace not checked" '(.apps[0].workspace.projects[0].targets[1].option_files[0]) as $o
  | $o.path == "../outside/tsconfig.spec.json" and $o.exists == null and ($o.note | test("not checked"))'
check mono "missing and present option files" '[.apps[0].workspace.projects[0].targets[0].option_files[] | .exists] == [false, true]'
check mono "test tools from builders, runner and packages" '[.apps[0].test_tools[].tool] == ["angular-unit-test", "jest", "vitest"]
  and ((.apps[0].test_tools[] | select(.tool == "vitest") | .evidence) == [
    {path: "angular.json", key: "projects.admin.architect.test.options.runner", value: "vitest"},
    {path: "package.json", key: "devDependencies.vitest", value: "^3.2.0"}])'
check mono "nx files listed, not parsed" 'any(.apps[0].paths.present[]; .path == "nx.json") and any(.apps[0].unknown[]; .field == "workspace.nx")'
check mono "library peer range" '.apps[1] | .angular.present == "framework" and .angular.declared_version.section == "peerDependencies"
  and .angular.declared_version.major == null and any(.unknown[]; .field == "angular.declared_version.major")
  and .workspace == null and any(.unknown[]; .field == "workspace")'
check mono "library jest file" '.apps[1].test_tools == [{tool: "jest", evidence: [{path: "projects/shared-ui/jest.config.ts"}]}]'

# MARK: no Angular, AngularJS, tooling only, no manifest, angular.json only, lockfile v1

adapter plain "$fx/plain-node"
code_is plain 0
no_canary plain
check plain "no angular" '.apps[0].angular.present == "none" and .apps[0].angular.declared_version == null and .apps[0].angular.evidence == []'
check plain "packages" '[.apps[0].packages[].name] == ["jest", "typescript"] and .apps[0].packages_ignored == 1 and .apps[0].package.module_type == "module"'
check plain "url with credentials redacted" '[.apps[0].packages[], .apps[0].versions.declared[] | select(.name == "typescript") | .constraint]
  | unique == ["(url with credentials, not printed)"]'
check plain "jest from package" '.apps[0].test_tools == [{tool: "jest", evidence: [{path: "package.json", key: "devDependencies.jest", value: "^30.0.0"}]}]'
check plain "no workspace, no lockfile" '.apps[0].workspace == null and .apps[0].lockfiles == []
  and any(.apps[0].unknown[]; .field == "versions.locked" and (.reason | test("no lockfile")))'
check plain "complete" '.complete == true'

adapter ajs "$fx/angularjs"
check ajs "angularjs only" '.apps[0].angular | .present == "angularjs_only" and .angularjs_package_count == 2 and .declared_version == null
  and .evidence == [{path: "package.json", key: "dependencies.angular", value: "1.8.3"}, {path: "package.json", key: "dependencies.angular-route", value: "1.8.3"}]'

adapter tool "$fx/tooling-only"
check tool "packages only" '.apps[0].angular | .present == "packages_only" and .declared_version == null
  and .evidence == [{path: "package.json", key: "devDependencies.@angular/cli", value: "^21.0.0"}]'

adapter none "$fx/no-manifest"
code_is none 0
check none "no apps" '.apps == [] and .summary.manifest_dirs == 0 and any(.unknown[]; .field == "package") and .complete == true'

adapter wsonly "$fx/ws-only"
code_is wsonly 0
check wsonly "angular.json without package.json" '.apps[0] | .dir == "." and .manifest == null and .package.status == "missing"
  and .angular.present == "unknown" and [.workspace.projects[].name] == ["solo"] and any(.unknown[]; .field == "package")'
check wsonly "missing package.json is not an error" '.errors == [] and .complete == true'

adapter v1 "$fx/lock-v1"
check v1 "lockfile v1 dependencies" '.apps[0].versions.locked == [{name: "@angular/core", version: "8.2.14",
  evidence: {path: "package-lock.json", key: "dependencies.@angular/core.version"}}] and .apps[0].versions.lockfile_version == 1
  and .apps[0].angular.declared_version.major == 8'

# MARK: broken files

adapter broken "$fx/broken"
code_is broken 0
no_stderr broken
check broken "all manifest dirs reported" '[.apps[].dir] == ["bad-workspace", "empty", "lock-malformed", "malformed", "not-object", "odd-types", "two-docs", "ws-not-object"]'
check broken "package statuses" '[.apps[].package.status] == ["ok", "malformed", "ok", "malformed", "malformed", "ok", "malformed", "ok"]'
check broken "errors with paths" '[.errors[].path] == ["bad-workspace/angular.json", "empty/package.json", "lock-malformed/package-lock.json",
  "malformed/package.json", "not-object/package.json", "two-docs/package.json", "ws-not-object/angular.json"]'
check broken "not complete" '.complete == false'
check broken "malformed package means unknown angular" 'all(.apps[] | select(.package.status == "malformed"); .angular.present == "unknown" and any(.unknown[]; .field == "package"))'
check broken "malformed angular.json" '.apps[0].workspace == {status: "malformed", evidence: {path: "bad-workspace/angular.json"}}
  and any(.apps[0].unknown[]; .field == "workspace" and (.reason | test("malformed")))'
check broken "malformed lockfile" '.apps[2].lockfiles == [{path: "lock-malformed/package-lock.json", format: "npm", status: "malformed"}] and .apps[2].versions.locked == []'
check broken "odd types tolerated" '.apps[5] | .package.name == "5" and .package.private == null and .engines_node == null and .workspaces == null
  and .angular.present == "framework" and .angular.declared_version.constraint == "[\"21.0.0\"]" and .angular.declared_version.major == null
  and [.packages[].name] == ["@angular/core"]'
check broken "projects not an object" '.apps[7].workspace.status == "ok" and .apps[7].workspace.projects == [] and .apps[7].workspace.projects_total == 0
  and any(.errors[]; .error == "angular.json projects is not an object")'

# MARK: spaces in paths

adapter space "$fx/space root"
code_is space 0
check space "dir with space" '.apps[0].dir == "sub app" and .apps[0].manifest == "sub app/package.json" and .apps[0].angular.declared_version.major == 21'
check space "project and configuration names with spaces" '.apps[0].workspace.projects[0] | .name == "my app" and .source_root == "my src"
  and .source_root_exists == true and .targets[0].configurations == ["pro duction"]
  and .targets[0].evidence.key == "projects.my app.architect.build.builder"'
check space "option files with spaces exist" '[.apps[0].workspace.projects[0].targets[0].option_files[] | {path, exists}]
  == [{path: "tsconfig app.json", exists: true}, {path: "my src/main.ts", exists: true}]'

# MARK: limits and depth

adapter lim "$fx/limits"
code_is lim 0
check lim "apps within depth" '.summary.manifest_dirs == 5 and [.apps[].dir] == [".", "a", "b", "c", "d"]'
check lim "unpinned version is unknown" '.apps[0].angular.declared_version | .constraint == "*" and .major == null'
check lim "complete within default limits" '.complete == true'

adapter limsmall "$fx/limits" --max-apps 3 --max-packages 2 --max-projects 2 --max-targets 2 --max-configurations 2
code_is limsmall 0
check limsmall "apps cut" '[.apps[].dir] == [".", "a", "b"] and any(.truncated[]; .field == "apps" and .shown == 3 and .total == 5 and .reason == "limit")'
check limsmall "packages cut" '(.apps[0].packages | length) == 2 and any(.truncated[]; .field == "apps[.].packages" and .total == 4)'
check limsmall "workspaces cut" '.apps[0].workspaces.patterns == ["a", "b"] and any(.truncated[]; .field == "apps[.].workspaces.patterns" and .total == 3)'
check limsmall "projects cut" '[.apps[0].workspace.projects[].name] == ["p1", "p2"] and any(.truncated[]; .field == "apps[.].workspace.projects" and .shown == 2 and .total == 3)'
check limsmall "targets cut" '[.apps[0].workspace.projects[0].targets[].name] == ["t1", "t2"] and any(.truncated[]; .field == "apps[.].workspace.projects[p1].targets" and .total == 3)'
check limsmall "configurations cut" '.apps[0].workspace.projects[0].targets[0].configurations == ["c1", "c2"]
  and .apps[0].workspace.projects[0].targets[0].configurations_total == 3
  and any(.truncated[]; .field == "apps[.].workspace.projects[p1].targets[t1].configurations" and .shown == 2 and .total == 3)'
check limsmall "limits echoed" '.limits | .max_apps == 3 and .max_packages == 2 and .max_projects == 2 and .max_targets == 2 and .max_configurations == 2'
check limsmall "not complete" '.complete == false'

adapter limdeep "$fx/limits" --max-depth 4
check limdeep "deeper manifest found with --max-depth 4" '.summary.manifest_dirs == 6 and any(.apps[]; .dir == "deep/l2/l3/l4")'

adapter big "$fx/ng-app" --max-manifest-kb 0
check big "manifests over the size limit are not read" '.apps[0].package.status == "too_large" and .apps[0].workspace.status == "too_large"
  and ([.errors[].path] == ["package.json", "angular.json"] or [.errors[].path] == ["angular.json", "package.json"]) and .complete == false'
adapter biglock "$fx/ng-app" --max-lock-kb 0
check biglock "lockfile over the size limit is not read" '.apps[0].lockfiles[0].status == "too_large" and .apps[0].versions.locked == []
  and .errors == [{path: "package-lock.json", error: "package-lock.json is larger than 0 KB, not read"}]'

# MARK: symlinks, permissions and bad input

mkdir -p "$run/outside/core" "$run/sym-app/node_modules/@angular"
printf '{"name": "@angular/core", "version": "CANARY-outside-version"}\n' >"$run/outside/core/package.json"
printf '{"dependencies": {"@angular/core": "^21.0.0"}}\n' >"$run/sym-app/package.json"
ln -s "$run/outside/core" "$run/sym-app/node_modules/@angular/core"
printf '{"version": 1, "projects": {}}\n' >"$run/outside/angular.json"
ln -s "$run/outside/angular.json" "$run/sym-app/angular.json"
adapter symlink "$run/sym-app"
no_canary symlink
check symlink "installed package outside ROOT not read" '.apps[0].versions.installed == []
  and any(.errors[]; .path == "node_modules/@angular/core/package.json" and (.error | test("outside ROOT")))'
check symlink "symlinked angular.json not followed" '.apps[0].workspace.status == "symlink" and any(.errors[]; .path == "angular.json" and (.error | test("symlink")))'

mkdir -p "$run/noread"
cp "$fx/plain-node/package.json" "$run/noread/package.json"
chmod 000 "$run/noread/package.json"
if [ -r "$run/noread/package.json" ]; then
  skip "unreadable package.json: file stays readable for this user (root?)"
else
  adapter noread "$run/noread"
  code_is noread 0
  check noread "unreadable package.json" '.apps[0].package.status == "unreadable" and .errors[0].path == "package.json" and .complete == false'
fi

adapter badopt "$fx/ng-app" --max-apps x
code_is badopt 2
check badopt "error JSON" '.error | test("needs a non-negative number")'
adapter unknownopt "$fx/ng-app" --follow-symlinks
code_is unknownopt 2
check unknownopt "error JSON" '.error == "unknown option --follow-symlinks"'
adapter badroot "$run/does-not-exist"
code_is badroot 2
check badroot "error JSON" '.error == "directory not found"'
mkdir -p "$run/lonely"
cp "$ADAPTER" "$run/lonely/adapter.sh"
"$BASH_BIN" "$run/lonely/adapter.sh" "$fx/ng-app" >"$run/nojq.json" 2>"$run/nojq.err"; echo $? >"$run/nojq.code"
code_is nojq 2
check nojq "missing jq file" '.error == "package-facts.jq not found next to adapter.sh"'

# MARK: read-only

if [ -n "$(find "$fx" -newer "$run/marker" -print 2>/dev/null | head -1)" ]; then fail "fixtures changed during the run"; else ok; fi

# MARK: real repository (optional, read-only)

if [ -n "${AV_ANGULAR_REAL_ROOT:-}" ]; then
  adapter real "$AV_ANGULAR_REAL_ROOT"
  code_is real 0
  no_stderr real
  check real "angular framework with declared major" '.apps[0].angular.present == "framework" and (.apps[0].angular.declared_version.major | type) == "number"'
  check real "workspace read" '.apps[0].workspace.status == "ok" and (.apps[0].workspace.projects | length) > 0'
  check real "facts carry evidence" 'all(.apps[].packages[]; .evidence.path != null) and all(.apps[].paths.present[]; .evidence.path == .path)'
fi

# MARK: scan.sh integration

# scan_case NAME DIR [ADAPTER] - runs scan.sh on DIR. ADAPTER: empty = the skill scan.sh with all adapters;
# otherwise a copy of scripts/ with "missing" = no angular adapter.sh, "nows" = no workspace-facts.jq,
# or a stub from integration/stubs/ installed as the angular adapter.sh. JSON in NAME.json, exit code in NAME.code.
scan_case() {
  local name="$1" dir="$2" adp="${3:-}" sk="$run/skill-$1" scan="$SCAN"
  if [ -n "$adp" ]; then
    mkdir -p "$sk"
    cp -R "$SKILL/scripts" "$sk/"
    scan="$sk/scripts/scan.sh"
    case "$adp" in
      missing) rm "$sk/scripts/adapters/angular/adapter.sh" ;;
      nows) rm "$sk/scripts/adapters/angular/workspace-facts.jq" ;;
      *) cp "$fx/integration/stubs/$adp" "$sk/scripts/adapters/angular/adapter.sh" ;;
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
  check "$1" "status $2" ".adapters.angular.status == \"$2\""
  check "$1" "reason in scan.incomplete" "any(.scan.incomplete[]?; .field == \"adapters.angular\" and .status == \"$2\" and (.reason | test(\"$3\")))"
  case "$2" in error|unavailable)
    check "$1" "no adapter facts or cuts kept" '(.adapters.angular | has("apps") or has("summary") | not)
      and ([.scan.truncated[] | select(.field | startswith("adapters.angular"))] == [])' ;;
  esac
}

grep -q 'angular_json' "$SCAN" && ok || fail "scan.sh has no angular_json section"

scan_case scan_ng "$fx/ng-app"
code_is scan_ng 0
check scan_ng "adapter section in scan" '.adapters.angular.summary.angular == {framework: 1} and (.scan.sections_sec | has("angular"))'
check scan_ng "status ok, ran, exit 0" '.adapters.angular | .status == "ok" and .ran == true and .exit_code == 0 and .reason == null'
check scan_ng "trigger evidence, worktrees and node_modules not counted" \
  '.adapters.angular.trigger == {angular_json_files: 1, package_json_angular_mentions: 1, package_json_invalid: 0}'
check scan_ng "no angular entry in scan.incomplete" '[.scan.incomplete[] | select(.field == "adapters.angular")] == []'
check scan_ng "php_symfony section untouched" '.adapters.php_symfony.status == "not_applicable"'
check scan_ng "no canary in the adapter section" '.adapters.angular | tostring | test("CANARY") | not'

scan_case scan_plain "$fx/plain-node"
check scan_plain "plain node: not_applicable, not run" '.adapters.angular | .status == "not_applicable" and .ran == false
  and .exit_code == null and (has("apps") | not) and (.reason | test("not run"))'
check scan_plain "not_applicable adds no incomplete entry" '[.scan.incomplete[] | select(.field == "adapters.angular")] == []'
scan_case scan_none "$fx/no-manifest"
check scan_none "no manifest: not_applicable" '.adapters.angular.status == "not_applicable"'
scan_case scan_ajs "$fx/angularjs"
check scan_ajs "angularjs key triggers the adapter" '.adapters.angular.status == "ok" and .adapters.angular.summary.angular == {angularjs_only: 1}'

scan_case scan_broken "$fx/broken"
scan_not_ok scan_broken incomplete "errors"
check scan_broken "adapter errors kept" '.adapters.angular.errors | length == 7'
scan_case scan_malformed "$fx/broken/malformed"
scan_not_ok scan_malformed incomplete "package.json is not a single valid JSON object"
check scan_malformed "invalid package.json still runs the adapter" '.adapters.angular.ran == true
  and .adapters.angular.trigger == {angular_json_files: 0, package_json_angular_mentions: 0, package_json_invalid: 1}'

scan_case scan_missing "$fx/ng-app" missing
scan_not_ok scan_missing unavailable "adapter.sh is missing"
scan_case scan_nows "$fx/ng-app" nows
scan_not_ok scan_nows unavailable "workspace-facts.jq is missing"
scan_case scan_exit2json "$fx/ng-app" exit2-valid-json.sh
scan_not_ok scan_exit2json error "exited with code 2"
scan_case scan_exit2err "$fx/ng-app" exit2-error-json.sh
scan_not_ok scan_exit2err error "code 2: workspace-facts.jq not found"
scan_case scan_exit2silent "$fx/ng-app" exit2-silent.sh
scan_not_ok scan_exit2silent error "code 2: no output"
scan_case scan_killed "$fx/ng-app" killed.sh
scan_not_ok scan_killed error "exited with code 137"
scan_case scan_garbage "$fx/ng-app" garbage.sh
scan_not_ok scan_garbage error "not one angular JSON object"
scan_case scan_twodocs "$fx/ng-app" two-docs.sh
scan_not_ok scan_twodocs error "not one angular JSON object"
scan_case scan_schema "$fx/ng-app" wrong-schema.sh
scan_not_ok scan_schema error "not one angular JSON object"
scan_case scan_badcut "$fx/ng-app" bad-truncated.sh
scan_not_ok scan_badcut error "not one angular JSON object"
scan_case scan_silent "$fx/ng-app" silent-incomplete.sh
scan_not_ok scan_silent incomplete "complete=false, 0 errors, 0 truncated"
scan_case scan_inconsistent "$fx/ng-app" inconsistent.sh
scan_not_ok scan_inconsistent incomplete "1 errors"

printf 'PASS %d SKIP %d FAIL %d\n' "$PASS" "$SKIP" "$FAIL"
[ "$FAIL" -eq 0 ]

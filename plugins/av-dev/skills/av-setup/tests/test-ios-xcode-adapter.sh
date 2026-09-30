#!/bin/bash
# Tests for scripts/adapters/ios-xcode/adapter.sh and its scan.sh integration.
# Fixtures in tests/fixtures/ios-xcode/: full app (workspace, projects, schemes, test plans, CocoaPods, SwiftPM,
# tool files), broken manifests, spaces in paths, SwiftPM package, no Xcode, review findings; limits, symlinks,
# CRLF and size cases are built at run time from fixtures/ios-xcode/templates/. Secret canaries, evidence lines,
# determinism and mutants that prove the detectors work. Integration: adapters.ios_xcode statuses (ok, incomplete,
# not_applicable, unavailable, error) with stub adapters from tests/fixtures/ios-xcode/integration/stubs/ installed
# in a temporary copy of scripts/. Optional: AV_IOS_REAL_ROOT=/path/to/ios/repo checks a real repository read-only.
# Runs the adapter with /bin/bash (3.2 on macOS) when present.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
ADIR="$SKILL/scripts/adapters/ios-xcode"
ADAPTER="$ADIR/adapter.sh"
SCAN="$SKILL/scripts/scan.sh"
fx="$SKILL/tests/fixtures/ios-xcode"
BASH_BIN=/bin/bash
[ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
PASS=0; FAIL=0
run="$(mktemp -d)"
trap 'rm -rf "$run"' EXIT
export TMPDIR="$run"

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
# adapter NAME ARGS... - runs adapter.sh; JSON in NAME.json, stderr in NAME.err, exit code in NAME.code
adapter() {
  local name="$1"; shift
  "$BASH_BIN" "$ADAPTER" "$@" >"$run/$name.json" 2>"$run/$name.err"
  echo $? >"$run/$name.code"
}
# check NAME DESCRIPTION JQ_EXPR - passes when the expression is true for NAME.json
check() { jq -e "$3" "$run/$1.json" >/dev/null 2>&1 && ok || fail "$1: $2"; }
code_is() { [ "$(cat "$run/$1.code")" = "$2" ] && ok || fail "$1: exit code $2 (got $(cat "$run/$1.code"))"; }
no_stderr() { [ -s "$run/$1.err" ] && fail "$1: stderr: $(head -3 "$run/$1.err" | tr '\n' ' ')" || ok; }
# one_object NAME - code 0 when NAME.json is exactly one JSON object
one_object() { jq -e -s 'length == 1 and (.[0] | type) == "object"' "$run/$1.json" >/dev/null 2>&1; }
# no_canary NAME - NAME.json is one JSON object without a CANARY string; invalid or empty output fails
no_canary() {
  one_object "$1" || { fail "$1: output is not one JSON object"; return; }
  grep -q CANARY "$run/$1.json" && fail "$1: secret canary leaked: $(grep -o 'CANARY[^"]*' "$run/$1.json" | head -3 | tr '\n' ' ')" || ok
}
# contract NAME - the shape scan.sh validates: one ios-xcode object with complete, errors and truncated
contract() {
  one_object "$1" && ok || fail "$1: stdout is not exactly one JSON object"
  check "$1" "contract shape" '.adapter == "ios-xcode" and .schema_version == 1 and (.complete | type) == "boolean"
    and (.errors | type) == "array" and all(.errors[]; type == "object" and (.path | type) == "string" and (.error | type) == "string")
    and (.truncated | type) == "array" and all(.truncated[]; type == "object" and (.field | type) == "string" and (.shown | type) == "number"
      and ((.total | type) == "number" or .total == null) and (.reason | type) == "string")
    and .complete == ((.errors | length) == 0 and (.truncated | length) == 0)'
}
# same NAME1 NAME2 - equal output without started and duration_sec; invalid JSON on either side fails
same() {
  local a b
  a="$(jq -e -S -c 'del(.started, .duration_sec)' "$run/$1.json" 2>/dev/null)" || { fail "$1: output is not valid JSON"; return; }
  b="$(jq -e -S -c 'del(.started, .duration_sec)' "$run/$2.json" 2>/dev/null)" || { fail "$2: output is not valid JSON"; return; }
  [ -n "$a" ] && [ "$a" = "$b" ] && ok || fail "$1 vs $2: output is not deterministic"
}
# evidence_lines NAME ROOT - every evidence with a line number points at a line that holds the fact:
# pbxproj evidence (key objects.<ID>.<k> or a root key) -> line has <k> or <ID>; Podfile, Podfile.lock and
# scheme evidence -> the line exists; failures are listed
evidence_lines() {
  local name="$1" rootdir="$2" bad=0 n=0 path key line text want id
  jq -e -r '[.. | objects | select(has("path") and has("line") and (.line | type) == "number")] | unique[]
         | [.path, (.key // ""), (.line | tostring)] | join("\u001f")' "$run/$name.json" >"$run/$name.evidence" 2>/dev/null \
    || { fail "$name: evidence list could not be read"; return; }
  while IFS=$'\x1f' read -r path key line; do
    n=$((n+1))
    text="$(sed -n "${line}p" "$rootdir/$path")"
    if [ -z "$text" ]; then bad=$((bad+1)); printf '  no line %s in %s\n' "$line" "$path" >&2; continue; fi
    case "$key" in
      objects.*) id="$(printf '%s' "$key" | cut -d. -f2)"; want="${key##*.}" ;;
      FileRef.location) id=""; want="<FileRef" ;;
      "") id=""; want="" ;;
      *) id=""; want="${key##*.}" ;;
    esac
    if [ -n "$want" ] && ! printf '%s' "$text" | grep -qF -- "$want" && { [ -z "$id" ] || ! printf '%s' "$text" | grep -qF -- "$id"; }; then
      bad=$((bad+1)); printf '  %s:%s does not hold %s: %s\n' "$path" "$line" "$key" "$text" >&2
    fi
  done <"$run/$name.evidence"
  [ "$n" -gt 0 ] && [ "$bad" -eq 0 ] && ok || fail "$name: $bad of $n evidence lines do not hold their fact"
}

# MARK: full app

adapter app "$fx/ios-app"
code_is app 0
no_stderr app
no_canary app
contract app
check app "complete" '.complete == true and .truncated == [] and .errors == []'
check app "excluded dirs, shallow first" '.excluded_dirs == [".claude", "Carthage", "DerivedData", "Pods", "build", "node_modules", "vendor"]'
check app "nothing reported from excluded dirs" '[.. | objects | (.path?, .manifest?, .pbxproj?) | strings
  | select(test("^(Carthage|build|DerivedData|node_modules|vendor|\\.claude)/"))] == []'
check app "Pods only as a workspace reference and pods_dir" '[.. | objects | .path? | strings | select(startswith("Pods"))] | sort == ["Pods", "Pods/Pods.xcodeproj"]'
check app "projects" '[.projects[].path] == ["App.xcodeproj", "Libs/Kit/Kit.xcodeproj"] and all(.projects[]; .status == "ok")'
check app "summary" '.summary == {workspaces: 1, projects: 2, targets: 5,
  product_types: {"(none)": 1, "com.apple.product-type.application": 1, "com.apple.product-type.bundle.ui-testing": 1,
                  "com.apple.product-type.bundle.unit-test": 1, "com.apple.product-type.framework": 1},
  schemes: 1, test_plans: 1, podfiles: 1, pod_statements: 8, locked_pod_roots: 7, swift_packages_declared: 3,
  package_resolved_files: 2, swift_pins_resolved: 4, package_swift: 0}'
check app "project root facts" '.projects[0] | .object_version.value == "77" and .archive_version == "1"
  and .compatibility_version.value == "Xcode 14.0" and .last_upgrade_check.value == "1600"
  and .preferred_project_object_version.value == "77" and .development_region.value == "en" and .known_regions.values == ["en", "Base", "pl"]'
check app "targets in project order" '[.projects[0].targets[] | [.name, .isa, .product_type]] == [
  ["App", "PBXNativeTarget", "com.apple.product-type.application"],
  ["AppTests", "PBXNativeTarget", "com.apple.product-type.bundle.unit-test"],
  ["AppUITests", "PBXNativeTarget", "com.apple.product-type.bundle.ui-testing"],
  ["Lint", "PBXAggregateTarget", null]]'
check app "target evidence" '.projects[0].targets[0].evidence == {path: "App.xcodeproj/project.pbxproj", key: "objects.B100000000000000000000T1.productType", line: 53}'
check app "App build configurations" '.projects[0].targets[0].build_configurations | .default == "Release" and .names == ["Debug", "Release"] and .names_total == 2'
check app "App settings per configuration" '(.projects[0].targets[0].settings | map_values(map([.value, .configurations]))) == {
  IPHONEOS_DEPLOYMENT_TARGET: [["16.0", ["Debug"]], ["16.4", ["Release"]]],
  SWIFT_VERSION: [["5.0", ["Debug"]], ["6.0", ["Release"]]],
  TARGETED_DEVICE_FAMILY: [["1,2", ["Debug", "Release"]]]}'
check app "only whitelisted settings" '[.projects[] | (.targets[].settings, .project_level.settings) | keys[]] | unique
  | all(.[]; IN("IPHONEOS_DEPLOYMENT_TARGET", "MACOSX_DEPLOYMENT_TARGET", "TVOS_DEPLOYMENT_TARGET", "WATCHOS_DEPLOYMENT_TARGET",
                "XROS_DEPLOYMENT_TARGET", "SWIFT_VERSION", "SDKROOT", "SUPPORTED_PLATFORMS", "TARGETED_DEVICE_FAMILY"))'
check app "no other build setting values" '[.. | strings | select(test("com\\.example\\.app|Info\\.plist|-ObjC|OTHER_"))] == []'
check app "xcconfig base counted" '.projects[0].targets[0].base_xcconfig_configs == 1 and any(.unknown[]; .field == "projects[App.xcodeproj].settings")'
check app "project-level settings" '(.projects[0].project_level.settings | map_values(map([.value, .configurations]))) ==
  {IPHONEOS_DEPLOYMENT_TARGET: [["17.0", ["Debug", "Release"]]], SDKROOT: [["iphoneos", ["Debug", "Release"]]]}'
check app "inline config list" '.projects[0].targets[1].build_configurations.names == ["Debug"]'
check app "object counts" '.projects[0].object_counts | .PBXFileSystemSynchronizedRootGroup == 1 and .PBXBuildFile == 2
  and .XCBuildConfiguration == 5 and .PBXGroup == 1'
check app "package products" '[.projects[0].targets[0].package_products[] | [.product, .package]] ==
  [["Factory", "https://github.com/hmlongco/Factory.git"], ["LocalKit", null]]'
check app "swift packages declared" '[.projects[0].swift_packages[] | [.kind, (.url // .path), .requirement]] == [
  ["local", "Packages/LocalKit", null],
  ["remote", "https://git.example.com/team/private.git", {branch: "main", kind: "branch"}],
  ["remote", "https://github.com/hmlongco/Factory.git", {kind: "upToNextMajorVersion", minimumVersion: "2.0.0"}]]'
check app "url credentials removed and flagged" '.projects[0].swift_packages[1].url_redacted == true and .projects[0].swift_packages[2].url_redacted == false'
check app "declared vs resolved" '(.projects[0].swift_packages[2].resolved | map(.version) | sort) == ["2.1.0", "2.2.0"]
  and .projects[0].swift_packages[1].resolved == [{identity: "private", version: null, revision: "ffffffffffffffffffffffffffffffffffffffff",
      branch: "main", evidence: {path: "App.xcworkspace/xcshareddata/swiftpm/Package.resolved", key: "pins.private"}}]
  and .projects[0].swift_packages[0].resolved == null'
check app "workspace file refs" '[.workspaces[0].file_refs[] | [.kind, .path, .exists]] == [
  ["group", "App.xcodeproj", true], ["group", "Libs/Kit/Kit.xcodeproj", true], ["container", "Missing.xcodeproj", false],
  ["absolute", null, null], ["group", "Pods/Pods.xcodeproj", true]] and .workspaces[0].file_refs_total == 5'
check app "workspace comment ignored" '[.. | strings | select(test("Ignored"))] == []'
check app "workspace Package.resolved v3" '.workspaces[0].package_resolved | .version == 3 and .status == "ok"
  and [.pins[].identity] == ["Alpha", "factory", "private"]
  and (.pins[2] | .location == "https://git.example.com/team/private.git" and .location_redacted == true and .branch == "main")'
check app "embedded Package.resolved v1" '.projects[0].package_resolved | .version == 1 and [.pins[] | [.identity, .version]] == [["Factory", "2.1.0"]]'
check app "scheme facts" '.projects[0].schemes | length == 1 and .[0].name == "App" and .[0].status == "ok" and .[0].last_upgrade_version == "1600"'
check app "scheme actions" '[.projects[0].schemes[0].actions[] | [.action, .build_configuration]] ==
  [["BuildAction", null], ["TestAction", "Debug"], ["LaunchAction", "Debug"], ["ArchiveAction", "Release"]]'
check app "scheme buildables without pre-action and macro refs" '[.projects[0].schemes[0].buildables[] | [.role, .target]] == [["build", "App"], ["run", "App"], ["test", "AppTests"]]'
check app "scheme test plans" '[.projects[0].schemes[0].test_plans[] | [.path, .default, .exists]] ==
  [["TestPlans/Unit.xctestplan", true, true], ["TestPlans/Gone.xctestplan", false, false]]'
check app "user schemes not read" '[del(.root) | .. | strings | select(test("User|xcuserdata"))] - ["schemes in xcuserdata are not read; only shared schemes in xcshareddata are listed"] == []'
check app "podfile basics" '.cocoapods[0].podfile | .status == "ok" and .platform == {name: "ios", version: "16.0", evidence: {path: "Podfile", line: 4}}
  and [.flags[].flag] == ["use_frameworks!", "inhibit_all_warnings!"] and [.projects[].path] == ["App.xcodeproj"]
  and [.hooks[].hook] == ["post_install"]'
check app "podfile sources cleaned" '[.cocoapods[0].podfile.sources[] | [.url, .url_redacted]] ==
  [["https://cdn.cocoapods.org/", false], ["https://specs.example.com/private-specs.git", true]]'
check app "podfile targets" '[.cocoapods[0].podfile.targets[] | [.kind, .name, .parent]] ==
  [["abstract_target", "Base", null], ["target", "App", "Base"], ["target", "AppTests", "App"], ["target", "Widget", null]]'
check app "podfile pods" '[.cocoapods[0].podfile.pods[] | [.name, .constraints, .options, .target]] == [
  ["Alamofire", ["~> 5.8"], [], "def:shared_pods"], ["SnapKit", [">= 5.0", "< 6.0"], [], "Base"],
  ["Kingfisher", ["7.9.1"], [], "App"], ["Private", [], ["git", "branch"], "App"], ["LocalPod", [], ["path"], "App"],
  ["Wormholy", [], ["configurations"], "App"], ["Firebase/Analytics", [], [], "App"], ["Kingfisher", [], [], "Widget"]]'
check app "pod configurations" '[.cocoapods[0].podfile.pods[] | select(.configurations) | [.name, .configurations]] == [["Wormholy", ["Debug"]]]'
check app "commented pods ignored" '[.. | strings | select(test("Commented|InsideBlockComment"))] == []'
check app "dynamic pod not followed" '.cocoapods[0].podfile.not_followed == [{reason: "pod without a literal name", evidence: {path: "Podfile", line: 27}}]
  and .cocoapods[0].podfile.open_blocks_at_end == 0 and any(.unknown[]; .field == "cocoapods[Podfile].podfile")'
check app "declared vs locked" '[.cocoapods[0].podfile.pods[] | [.name, .locked_version.value]] == [["Alamofire", "5.8.1"], ["SnapKit", "5.7.1"],
  ["Kingfisher", "7.9.1"], ["Private", "1.0.0"], ["LocalPod", "0.1.0"], ["Wormholy", null], ["Firebase/Analytics", "10.0.0"], ["Kingfisher", "7.9.1"]]'
check app "lock facts" '.cocoapods[0].lock | .status == "ok" and .cocoapods_version.value == "1.15.2" and .podfile_checksum_present == true
  and .entries_total == 8 and .pods_total == 7
  and [.pods[] | [.name, .version]] == [["Alamofire", "5.8.1"], ["Firebase", "10.0.0"], ["Kingfisher", "7.9.1"], ["LocalPod", "0.1.0"],
                                        ["Private", "1.0.0"], ["SnapKit", "5.7.1"], ["Stale", "1.0.0"]]'
check app "lock dependencies" '[.cocoapods[0].lock.dependencies[] | [.name, .requirement]] == [["Alamofire", "(~> 5.8)"], ["Firebase/Analytics", null],
  ["Kingfisher", "(= 7.9.1)"], ["LocalPod", "external"], ["Private", "external"], ["SnapKit", "(< 6.0, >= 5.0)"], ["Stale", null]]'
check app "lock repos and external sources" '[.cocoapods[0].lock.spec_repos[] | [.repo, .pods]] == [["https://specs.example.com/private-specs.git", 1], ["trunk", 4]]
  and [.cocoapods[0].lock.external_sources[] | [.name, .kind]] == [["LocalPod", "path"], ["Private", "git"]]'
check app "pods comparison" '.cocoapods[0].comparison | .declared_not_in_lock_dependencies == ["Wormholy"] and .lock_dependencies_not_declared == ["Stale"]'
check app "Pods dir noted, not read" '.cocoapods[0].pods_dir == {path: "Pods", exists: true, read: false}'
check app "test plan facts" '.test_plans == [{path: "TestPlans/Unit.xctestplan", status: "ok", version: 1, configurations: ["Default"],
  test_targets: [{name: "AppTests", container: "container:App.xcodeproj", enabled: true, parallelizable: false, selected_tests: 0, skipped_tests: 0},
                 {name: "AppUITests", container: "container:App.xcodeproj", enabled: false, parallelizable: null, selected_tests: 0, skipped_tests: 2}],
  default_options_keys: ["codeCoverage", "commandLineArgumentEntries", "environmentVariableEntries"],
  environment_variable_entries: 2, command_line_argument_entries: 1, evidence: {path: "TestPlans/Unit.xctestplan"},
  referenced_by: ["App.xcodeproj/xcshareddata/xcschemes/App.xcscheme"]}]'
check app "tool files by name" '.tool_files == [{tool: "bundler", evidence: {path: "Gemfile"}}, {tool: "fastlane", evidence: {path: "fastlane/Fastfile"}},
  {tool: "swiftlint", evidence: {path: ".swiftlint.yml"}}, {tool: "xcode_version", evidence: {path: ".xcode-version"}}]'
check app "fixed unknown entries" '[.unknown[].field] | contains(["deeper_manifests", "installed_versions", "effective_build_settings",
  "podfile_evaluation", "package_swift_dependencies", "user_schemes"])'
check app "no inferred architecture keys" '[paths | map(tostring) | join(".") | select(test("layer|module|domain|bounded|architecture|relation|feature"; "i"))] == []'
check app "no secret file names" '[.. | strings | select(test("\\.env|GoogleService|Secrets\\.xcconfig|entitlements|\\.p8|AppDelegate"))] == []'
evidence_lines app "$fx/ios-app"

adapter app2 "$fx/ios-app"
same app app2
adapter app_pretty "$fx/ios-app" --pretty
same app app_pretty
( cd "$fx" && "$BASH_BIN" "$ADAPTER" ios-app >"$run/app_rel.json" 2>"$run/app_rel.err"; echo $? >"$run/app_rel.code" )
same app app_rel
mkdir -p "$run/tmp2"
TMPDIR="$run/tmp2" "$BASH_BIN" "$ADAPTER" "$fx/ios-app" >"$run/app_tmp2.json" 2>/dev/null
same app app_tmp2
[ -z "$(ls -A "$run/tmp2")" ] && ok || fail "adapter left temp files in TMPDIR"

# MARK: broken manifests

adapter broken "$fx/broken" --max-projects 20
code_is broken 0
no_stderr broken
no_canary broken
contract broken
check broken "not complete" '.complete == false and .truncated == []'
check broken "project statuses" '[.projects[] | [.path, .status]] == [["bad-header/Bad.xcodeproj", "malformed"], ["bad-scheme/S2.xcodeproj", "ok"],
  ["dangling/D.xcodeproj", "ok"], ["empty/Empty.xcodeproj", "malformed"], ["missing-pbx/M.xcodeproj", "missing"],
  ["no-root/R.xcodeproj", "malformed"], ["not-project/N.xcodeproj", "malformed"], ["unbalanced/U.xcodeproj", "malformed"],
  ["unterminated/S.xcodeproj", "malformed"]]'
check broken "malformed projects keep no facts" 'all(.projects[] | select(.status != "ok"); has("targets") | not)'
check broken "error messages" '(.errors | map({(.path): .error}) | add) as $e
  | ($e["bad-header/Bad.xcodeproj/project.pbxproj"] | test("missing // !\\$\\*UTF8\\*\\$! header"))
  and ($e["empty/Empty.xcodeproj/project.pbxproj"] | test("empty file"))
  and ($e["unbalanced/U.xcodeproj/project.pbxproj"] | test("unbalanced braces"))
  and ($e["unterminated/S.xcodeproj/project.pbxproj"] | test("unterminated quoted string"))
  and ($e["no-root/R.xcodeproj/project.pbxproj"] | test("no rootObject"))
  and ($e["not-project/N.xcodeproj/project.pbxproj"] | test("is not a PBXProject"))
  and ($e["missing-pbx/M.xcodeproj/project.pbxproj"] | test("missing"))
  and ($e["bad-ws/W.xcworkspace/contents.xcworkspacedata"] | test("does not match"))
  and ($e["bad-scheme/S2.xcodeproj/xcshareddata/xcschemes/Broken.xcscheme"] | test("malformed"))
  and ($e["bad-scheme/S2.xcodeproj/xcshareddata/xcschemes/NotScheme.xcscheme"] | test("not <Scheme>"))
  and ($e["bad-resolved/R2.xcworkspace/xcshareddata/swiftpm/Package.resolved"] | test("not a single valid JSON"))
  and ($e["v9-resolved/R3.xcworkspace/xcshareddata/swiftpm/Package.resolved"] | test("unsupported version"))
  and ($e["bad-lock/Podfile.lock"] | test("malformed"))
  and ($e["bad-plan/Plan.xctestplan"] | test("not a single JSON object"))
  and ($e["array-plan/Array.xctestplan"] | test("not a single JSON object"))
  and ($e["secret-plan/Secrets.xctestplan"] | test("secret"))'
check broken "error count" '(.errors | length) == 18'
check broken "dangling target and package: facts kept, errors recorded" '(.projects[] | select(.path == "dangling/D.xcodeproj") | [.targets[].name]) == ["Kit"]
  and ([.errors[] | select(.path == "dangling/D.xcodeproj/project.pbxproj")] | length) == 2'
check broken "scheme statuses" '[.projects[] | .schemes[] | [.name, .status]] == [["Broken", "malformed"], ["NotScheme", "malformed"]]'
check broken "workspace statuses" '[.workspaces[] | [.path, .status, (.package_resolved.status // null)]] ==
  [["bad-resolved/R2.xcworkspace", "ok", "malformed"], ["bad-ws/W.xcworkspace", "malformed", null], ["v9-resolved/R3.xcworkspace", "ok", "unsupported"]]'
check broken "bad lock: Podfile facts kept, no comparison" '.cocoapods[0] | .podfile.status == "ok" and .podfile.pods_total == 1
  and .lock.status == "malformed" and .comparison == null'
check broken "test plan statuses" '[.test_plans[] | [.path, .status]] == [["array-plan/Array.xctestplan", "malformed"],
  ["bad-plan/Plan.xctestplan", "malformed"], ["odd-plan/Odd.xctestplan", "ok"], ["secret-plan/Secrets.xctestplan", "secret_like"]]'
check broken "odd types tolerated" '(.test_plans[] | select(.path == "odd-plan/Odd.xctestplan")) | .configurations == [] and .default_options_keys == []
  and .test_targets == [{name: null, container: null, enabled: true, parallelizable: null, selected_tests: null, skipped_tests: 0}]'
check broken "errors sorted by path" '[.errors[].path] == ([.errors[].path] | sort)'
adapter broken2 "$fx/broken" --max-projects 20
same broken broken2

adapter brokencut "$fx/broken"
check brokencut "default max 8 projects cut" '[.truncated[] | [.field, .shown, .total, .reason]] == [["projects", 8, 9, "limit"]] and .complete == false'

# MARK: spaces in paths

adapter space "$fx/space root"
code_is space 0
no_stderr space
contract space
check space "complete" '.complete == true'
check space "project with spaces" '.projects[0].path == "My App/My App.xcodeproj" and .projects[0].targets[0].name == "My App"
  and .projects[0].targets[0].build_configurations.names == ["Debug Staging"]'
check space "scheme with spaces" '.projects[0].schemes[0] | .name == "My Scheme" and .path == "My App/My App.xcodeproj/xcshareddata/xcschemes/My Scheme.xcscheme"
  and .actions == [{action: "TestAction", build_configuration: "Debug Staging", evidence: {path: "My App/My App.xcodeproj/xcshareddata/xcschemes/My Scheme.xcscheme", line: 5}}]
  and .test_plans[0].path == "My App/Test Plans/My Plan.xctestplan" and .test_plans[0].exists == true'
check space "test plan with spaces" '.test_plans[0] | .path == "My App/Test Plans/My Plan.xctestplan" and .configurations == ["Default Config"]
  and .referenced_by == ["My App/My App.xcodeproj/xcshareddata/xcschemes/My Scheme.xcscheme"]'
check space "workspace refs: entity decoded, .. resolved inside ROOT" '[.workspaces[0].file_refs[] | [.location, .path, .exists]] ==
  [["group:My App.xcodeproj", "My App/My App.xcodeproj", true], ["group:../Outside & Co.xcodeproj", "Outside & Co.xcodeproj", false]]'
check space "podfile without lock" '.cocoapods[0] | .dir == "My App" and .podfile.pods[0].constraints == ["~> 7.0"] and .podfile.pods[0].target == "My App"
  and .lock.status == "missing" and .pods_dir == {path: "My App/Pods", exists: false, read: false}'
check space "missing lock is unknown, not an error" 'any(.unknown[]; .field == "cocoapods[My App/Podfile].lock") and .errors == []'
evidence_lines space "$fx/space root"

# MARK: SwiftPM package and no Xcode

adapter spm "$fx/spm"
code_is spm 0
no_canary spm
contract spm
check spm "manifests" '[.swiftpm.manifests[] | [.path, .status, .tools_version.value]] == [["Package.swift", "ok", "5.9"], ["Nested/Package.swift", "ok", null]]'
check spm "tools version evidence" '.swiftpm.manifests[0].tools_version.evidence == {path: "Package.swift", line: 1}'
check spm "no tools version is unknown" 'any(.unknown[]; .field == "swiftpm.manifests[Nested/Package.swift].tools_version")'
check spm "resolved next to Package.swift" '.swiftpm.manifests[0].package_resolved | .version == 3 and [.pins[] | [.identity, .version]] == [["swift-log", "1.6.1"]]'
check spm "summary" '.summary.package_swift == 2 and .summary.projects == 0 and .summary.swift_pins_resolved == 1 and .complete == true'
check spm "Package.swift dependencies not parsed" '[.. | strings | select(test("1\\.5\\.0|swift-log\\.git\"|PackageDescription"))] == []'

adapter none "$fx/no-xcode"
code_is none 0
contract none
check none "nothing found, xcode unknown" '.projects == [] and .workspaces == [] and .cocoapods == [] and .swiftpm.manifests == []
  and .test_plans == [] and any(.unknown[]; .field == "xcode") and .complete == true'

# MARK: limits and depth

lim="$run/limits"
mkdir -p "$lim/a/Big.xcodeproj/xcshareddata/xcschemes" "$lim/W.xcworkspace/xcshareddata/swiftpm" "$lim/Plans" "$lim/l1/l2/l3/l4/Deep.xcodeproj" "$lim/l1/l2/l3/L3.xcodeproj"
cp "$fx/templates/big.pbxproj" "$lim/a/Big.xcodeproj/project.pbxproj"
for s in S1 S2 S3; do printf '<?xml version="1.0"?>\n<Scheme version = "1.7">\n   <LaunchAction buildConfiguration = "Debug">\n   </LaunchAction>\n</Scheme>\n' >"$lim/a/Big.xcodeproj/xcshareddata/xcschemes/$s.xcscheme"; done
for d in b c d e; do mkdir -p "$lim/$d/P.xcodeproj"; cp "$fx/templates/min.pbxproj" "$lim/$d/P.xcodeproj/project.pbxproj"; done
cp "$fx/templates/min.pbxproj" "$lim/l1/l2/l3/L3.xcodeproj/project.pbxproj"
cp "$fx/templates/min.pbxproj" "$lim/l1/l2/l3/l4/Deep.xcodeproj/project.pbxproj"
printf '<?xml version="1.0"?>\n<Workspace version = "1.0">\n<FileRef location = "group:a/Big.xcodeproj"></FileRef>\n<FileRef location = "group:b/P.xcodeproj"></FileRef>\n<FileRef location = "group:c/P.xcodeproj"></FileRef>\n</Workspace>\n' >"$lim/W.xcworkspace/contents.xcworkspacedata"
printf '{"pins": [{"identity": "a", "location": "https://example.com/a.git", "state": {"version": "1.0.0"}}, {"identity": "b", "location": "https://example.com/b.git", "state": {"revision": "abcdef"}}, {"identity": "c", "location": "https://example.com/c.git", "state": {"version": "2.5.0"}}], "version": 2}\n' >"$lim/W.xcworkspace/xcshareddata/swiftpm/Package.resolved"
for p in P1 P2 P3; do printf '{"testTargets": [], "version": 1}\n' >"$lim/Plans/$p.xctestplan"; done
printf "platform :ios, '15.0'\ntarget 'One' do\n  pod 'A'\n  pod 'B'\n  pod 'C'\nend\n" >"$lim/Podfile"
printf 'PODS:\n  - A (1.0.0)\n  - B (1.0.0)\n  - C (1.0.0)\n\nDEPENDENCIES:\n  - A\n  - B\n  - C\n\nCOCOAPODS: 1.16.0\n' >"$lim/Podfile.lock"

adapter lim "$lim"
code_is lim 0
contract lim
check lim "complete within default limits" '.complete == true'
check lim "projects within depth, shallow first" '[.projects[].path] == ["a/Big.xcodeproj", "b/P.xcodeproj", "c/P.xcodeproj", "d/P.xcodeproj", "e/P.xcodeproj", "l1/l2/l3/L3.xcodeproj"]'
check lim "requirement kinds" '[.projects[0].swift_packages[] | .requirement] == [{kind: "exactVersion", version: "1.0.0"}, {kind: "revision", revision: "abcdef"},
  {kind: "versionRange", maximumVersion: "3.0.0", minimumVersion: "2.0.0"}]'
check lim "resolved join by URL" '[.projects[0].swift_packages[] | [.url, (.resolved | map(.version // .revision))]] ==
  [["https://example.com/a.git", ["1.0.0"]], ["https://example.com/b.git", ["abcdef"]], ["https://example.com/c.git", ["2.5.0"]]]'

adapter limsmall "$lim" --max-projects 2 --max-targets 2 --max-configs 2 --max-packages 2 --max-schemes 2 --max-test-plans 2 --max-file-refs 2
code_is limsmall 0
contract limsmall
check limsmall "not complete" '.complete == false and .errors == []'
check limsmall "all cuts reported" '[.truncated[] | [.field, .shown, .total]] | sort == ([
  ["projects", 2, 6], ["test_plans", 2, 3], ["projects[a/Big.xcodeproj].targets", 2, 3],
  ["projects[a/Big.xcodeproj].targets[One].build_configurations", 2, 3], ["projects[a/Big.xcodeproj].targets[Two].build_configurations", 2, 3],
  ["projects[a/Big.xcodeproj].swift_packages", 2, 3], ["schemes[a/Big.xcodeproj]", 2, 3], ["workspaces[W.xcworkspace].file_refs", 2, 3],
  ["package_resolved[W.xcworkspace/xcshareddata/swiftpm/Package.resolved].pins", 2, 3],
  ["cocoapods[Podfile].podfile.pods", 2, 3], ["cocoapods[Podfile].lock.pods", 2, 3], ["cocoapods[Podfile].lock.dependencies", 2, 3]] | sort)'
check limsmall "comparison uses all lock dependencies" '.cocoapods[0].comparison.lock_dependencies_not_declared == [] and (.cocoapods[0].lock.dependencies | length) == 2'
check limsmall "lists cut to limits" '(.projects | length) == 2 and (.projects[0].targets | length) == 2 and .projects[0].targets_total == 3
  and (.projects[0].targets[0].build_configurations.names | length) == 2 and .projects[0].targets[0].build_configurations.names_total == 3
  and (.projects[0].swift_packages | length) == 2 and .projects[0].swift_packages_total == 3 and (.projects[0].schemes | length) == 2
  and (.workspaces[0].file_refs | length) == 2 and .workspaces[0].file_refs_total == 3 and (.test_plans | length) == 2
  and (.cocoapods[0].podfile.pods | length) == 2 and .cocoapods[0].podfile.pods_total == 3'
check limsmall "limits echoed" '.limits | .max_projects == 2 and .max_targets == 2 and .max_configs == 2 and .max_packages == 2
  and .max_schemes == 2 and .max_test_plans == 2 and .max_file_refs == 2 and .max_depth == 3'

adapter limdeep "$lim" --max-depth 4
check limdeep "deeper project found with --max-depth 4" '.summary.projects == 7 and any(.projects[]; .path == "l1/l2/l3/l4/Deep.xcodeproj")'
adapter limzero "$lim" --max-depth 0
check limzero "depth 0: root containers only" '.summary.projects == 0 and .summary.workspaces == 1 and .summary.podfiles == 1 and .summary.test_plans == 0'

# MARK: symlinks, CRLF, size

sl="$run/symlinks"
mkdir -p "$sl/real/R.xcodeproj" "$sl/app/A.xcodeproj" "$sl/pod"
cp "$fx/templates/min.pbxproj" "$sl/real/R.xcodeproj/project.pbxproj"
ln -s ../../real/R.xcodeproj/project.pbxproj "$sl/app/A.xcodeproj/project.pbxproj"
ln -s real/R.xcodeproj "$sl/Linked.xcodeproj"
printf "pod 'A'\n" >"$sl/pod/Podfile.real"
ln -s Podfile.real "$sl/pod/Podfile"
adapter symlink "$sl"
check symlink "symlinked pbxproj not followed" '(.projects[] | select(.path == "app/A.xcodeproj") | .status) == "symlink"
  and any(.errors[]; .path == "app/A.xcodeproj/project.pbxproj" and (.error | test("symlink")))'
check symlink "symlinked .xcodeproj dir not discovered" '[.projects[].path] == ["app/A.xcodeproj", "real/R.xcodeproj"]'
check symlink "symlinked Podfile not discovered" '.cocoapods == []'
mkdir -p "$run/outside/X.xcodeproj/xcshareddata/xcschemes" "$run/sl2/B.xcodeproj"
printf '<?xml version="1.0"?>\n<Scheme version = "1.7">\n<LaunchAction buildConfiguration = "OUTSIDE-ROOT">\n</LaunchAction>\n</Scheme>\n' >"$run/outside/X.xcodeproj/xcshareddata/xcschemes/Out.xcscheme"
cp "$fx/templates/min.pbxproj" "$run/sl2/B.xcodeproj/project.pbxproj"
ln -s "$run/outside/X.xcodeproj/xcshareddata" "$run/sl2/B.xcodeproj/xcshareddata"
adapter symlink2 "$run/sl2"
check symlink2 "symlinked parent leaving ROOT is not followed" '.projects[0].schemes == [{name: "Out", path: "B.xcodeproj/xcshareddata/xcschemes/Out.xcscheme", status: "outside_root"}]
  and any(.errors[]; .error | test("leaves ROOT")) and ([.. | strings | select(test("OUTSIDE-ROOT"))] == [])'

crlf="$run/crlf/C.xcodeproj"
mkdir -p "$crlf"
awk '{ printf "%s\r\n", $0 }' "$fx/templates/min.pbxproj" >"$crlf/project.pbxproj"
adapter crlf "$run/crlf"
check crlf "CRLF pbxproj parsed" '.projects[0].status == "ok" and .projects[0].targets[0].name == "Kit"
  and .projects[0].project_level.settings.MACOSX_DEPLOYMENT_TARGET[0].value == "13.0" and .complete == true'

adapter toolarge "$fx/ios-app" --max-pbxproj-kb 0 --max-manifest-kb 0
check toolarge "size limits: not read, errors" '[.projects[].status] == ["too_large", "too_large"] and .workspaces[0].status == "too_large"
  and .cocoapods[0].podfile.status == "too_large" and .test_plans[0].status == "too_large" and .complete == false
  and all(.errors[]; .error | test("larger than 0 KB"))'
no_canary toolarge

# MARK: bad input

adapter badopt "$fx/ios-app" --max-projects x
code_is badopt 2
check badopt "error JSON" '.error | test("needs a non-negative number")'
adapter badzero "$fx/ios-app" --max-depth 08
code_is badzero 2
check badzero "leading zero rejected" '.error | test("without leading zeros")'
adapter badflag "$fx/ios-app" --nope
code_is badflag 2
check badflag "unknown option" '.error == "unknown option --nope"'
adapter badroot "$run/does-not-exist"
code_is badroot 2
check badroot "directory not found" '.error == "directory not found"'
mkdir -p "$run/partial"
cp "$ADAPTER" "$ADIR/pbxproj.awk" "$ADIR/podfile.awk" "$ADIR/podlock.awk" "$ADIR/ios-facts.jq" "$ADIR/pbxproj-facts.jq" "$run/partial/"
"$BASH_BIN" "$run/partial/adapter.sh" "$fx/ios-app" >"$run/nohelper.json" 2>"$run/nohelper.err"; echo $? >"$run/nohelper.code"
code_is nohelper 2
check nohelper "missing helper named" '.error == "xml.awk not found next to adapter.sh"'

# MARK: review findings

adapter review "$fx/review"
code_is review 0
no_stderr review
contract review
check review "no part of a password with @ leaks" '[.. | strings | select(test("p@ss|ss@|token-value|Authorization|Bearer"))] == []'
check review "URLs cleaned up to the last @" '.projects[] | select(.path == "Review.xcodeproj") | .swift_packages[0] | .url == "https://git.example.com/team/kit.git" and .url_redacted == true
  and .resolved[0].version == "1.2.0"'
check review "lock spec repo cleaned" '.cocoapods[0].lock.spec_repos[0].repo == "https://specs.example.com/specs.git"'
check review "xcconfig anchor counts as base xcconfig" '(.projects[] | select(.path == "Review.xcodeproj") | .targets[0].base_xcconfig_configs) == 1
  and any(.unknown[]; .field == "projects[Review.xcodeproj].settings")'
check review "dangling configuration and product are errors" '[.errors[] | select(.path == "Review.xcodeproj/project.pbxproj") | .error] | sort ==
  ["build configuration V000000000000000000000404 is referenced but not defined",
   "package product dependency V0000000000000000000D404 is referenced but not defined"]'
check review "non-object pin is an error" 'any(.errors[]; .path == "Review.xcworkspace/xcshareddata/swiftpm/Package.resolved" and (.error | test("1 pins are not JSON objects")))
  and .workspaces[0].package_resolved.pins_skipped == 1'
check review "workspace groups: container, absolute, .. resolved" '[.workspaces[0].file_refs[] | [.location, .path, .exists]] == [
  ["group:Sub/../Review.xcodeproj", "Review.xcodeproj", true], ["group:../Outside.xcodeproj", null, null],
  ["group:Kit/Kit.xcodeproj", "Libs/Kit/Kit.xcodeproj", true], ["group:Shared.xcodeproj", null, null]]'
check review "scheme test plan with .. resolved and referenced" '(.projects[] | select(.path == "App/App.xcodeproj") | .schemes[0].test_plans[0] | [.path, .exists]) == ["TestPlans/Unit.xctestplan", true]
  and .test_plans[0].referenced_by == ["App/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme"]'
check review "multi-line pod flagged, options from strings ignored" '[.cocoapods[0].podfile.pods[] | [.name, .options]] == [["Private", []], ["Net", ["headers", "modular_headers"]]]
  and .cocoapods[0].podfile.not_followed == [{reason: "pod statement continues on the next line; its further constraints and options are not read", evidence: {path: "Podfile", line: 4}}]'
check review "not complete because of errors" '.complete == false and .truncated == []'
evidence_lines review "$fx/review"

# MARK: detector sanity

# mutant NAME HELPER SED_EXPR [FIXTURE] - copy of the adapter with one helper changed by sed; JSON in NAME.json;
# the mutant must still print one JSON object, so an empty or broken output cannot pass as "nothing leaked"
mutant() {
  local name="$1" dir="$run/mut-$1/adapters/ios-xcode"
  mkdir -p "$dir"
  cp "$ADAPTER" "$ADIR"/*.awk "$ADIR"/*.jq "$dir/"
  cp "$ADIR/../../secret_names.sh" "$run/mut-$1/"
  sed "$3" "$ADIR/$2" >"$dir/$2"
  "$BASH_BIN" "$dir/adapter.sh" "$fx/${4:-ios-app}" >"$run/$name.json" 2>/dev/null
  one_object "$name" && ok || fail "detector $name: the mutant printed no JSON object"
}
mutant mut_url ios-facts.jq 's|://)\[^/\]\*@|://)[^/@]*@|' review
grep -q 'ss@git' "$run/mut_url.json" && ok || fail "detector: the old URL redaction (stop at the first @) is not caught"
mutant mut_setting pbxproj.awk 's/SWIFT_VERSION SDKROOT/SWIFT_VERSION API_KEY SDKROOT/'
grep -q CANARY "$run/mut_setting.json" && ok || fail "detector: a leaked build setting is not caught by the canary check"
mutant mut_excl adapter.sh 's/-name Pods -o //'
check mut_excl "detector: Pods scanned is visible" 'any(.projects[]; .path == "Pods/Pods.xcodeproj")'
# second layer: xml.awk passes the "value" attribute, scheme_facts still prints only its own fields
mutant mut_scheme adapter.sh 's/buildConfiguration,BlueprintName/buildConfiguration,value,argument,scriptText,BlueprintName/'
grep -q CANARY "$run/mut_scheme.json" && fail "detector: scheme values leak when xml.awk passes more attributes" || ok

# MARK: real repository (optional, read-only)

if [ -n "${AV_IOS_REAL_ROOT:-}" ]; then
  adapter real "$AV_IOS_REAL_ROOT"
  code_is real 0
  no_stderr real
  contract real
  check real "projects found" '(.projects | length) > 0 and all(.projects[]; .status == "ok")'
fi

# MARK: scan.sh integration

# scan_case NAME DIR [ADAPTER] - runs scan.sh on DIR. ADAPTER: empty = the skill scan.sh with all adapters;
# otherwise a copy of scripts/ with "missing" = no ios-xcode adapter.sh, "nohelper" = no xml.awk,
# or a stub from integration/stubs/ installed as ios-xcode adapter.sh. JSON in NAME.json, exit code in NAME.code.
scan_case() {
  local name="$1" dir="$2" adp="${3:-}" sk="$run/skill-$1" scan="$SCAN"
  if [ -n "$adp" ]; then
    mkdir -p "$sk"
    cp -R "$SKILL/scripts" "$sk/"
    scan="$sk/scripts/scan.sh"
    case "$adp" in
      missing) rm "$sk/scripts/adapters/ios-xcode/adapter.sh" ;;
      nohelper) rm "$sk/scripts/adapters/ios-xcode/xml.awk" ;;
      *) cp "$fx/integration/stubs/$adp" "$sk/scripts/adapters/ios-xcode/adapter.sh" ;;
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
  check "$1" "status $2" ".adapters.ios_xcode.status == \"$2\""
  check "$1" "reason in scan.incomplete" "any(.scan.incomplete[]?; .field == \"adapters.ios_xcode\" and .status == \"$2\" and (.reason | test(\"$3\")))"
  case "$2" in error|unavailable)
    check "$1" "no adapter facts or cuts kept" '(.adapters.ios_xcode | has("projects") or has("summary") | not)
      and ([.scan.truncated[] | select(.field | startswith("adapters.ios_xcode"))] == [])' ;;
  esac
}

grep -q 'ios_xcode_json' "$SCAN" && ok || fail "scan.sh has no ios_xcode_json section"

scan_case scan_app "$fx/ios-app"
code_is scan_app 0
check scan_app "status ok with facts" '.adapters.ios_xcode | .status == "ok" and .ran == true and .exit_code == 0 and .reason == null
  and .summary.projects == 2 and .adapter == "ios-xcode" and (has("root") or has("started") | not)'
# scan.sh walk prunes .claude/worktrees (review of PR #19), so .claude/worktrees/wt1/App.xcodeproj is not in the trigger; the adapter skips it too
check scan_app "trigger evidence" '.adapters.ios_xcode.trigger == {xcode_dirs: 3, podfile_or_package_swift_files: 1, stacks_ios_entries: 3}
  and ([.adapters.ios_xcode.projects[].path] | index(".claude/worktrees/wt1/App.xcodeproj")) == null'
check scan_app "no ios entry in scan.incomplete or scan.truncated" '([.scan.incomplete[] | select(.field | startswith("adapters.ios_xcode"))] == [])
  and ([.scan.truncated[] | select(.field | startswith("adapters.ios_xcode"))] == [])'
check scan_app "section time" '.scan.sections_sec | has("ios_xcode")'
check scan_app "other adapters untouched" '.adapters.php_symfony.status == "not_applicable" and .adapters.android.status == "not_applicable"'
check scan_app "no canary in the adapter section" '.adapters.ios_xcode | tostring | test("CANARY") | not'

scan_case scan_none "$fx/no-xcode"
check scan_none "not_applicable, not run" '.adapters.ios_xcode | .status == "not_applicable" and .ran == false and .exit_code == null
  and (has("projects") | not) and (.reason | test("not run"))'
check scan_none "not_applicable keeps the adapter out of scan.incomplete" '[.scan.incomplete[] | select(.field == "adapters.ios_xcode")] == []'

scan_case scan_broken "$fx/broken"
scan_not_ok scan_broken incomplete "complete=false, [0-9]+ errors, 1 truncated; first error: "
check scan_broken "adapter cut merged with prefix" 'any(.scan.truncated[]; .field == "adapters.ios_xcode.projects" and .shown == 8 and .total == 9)'
check scan_broken "adapter errors kept" '(.adapters.ios_xcode.errors | length) > 0'

scan_case scan_spm "$fx/spm"
check scan_spm "Package.swift alone triggers the adapter" '.adapters.ios_xcode.status == "ok" and .adapters.ios_xcode.trigger.xcode_dirs == 0
  and .adapters.ios_xcode.trigger.podfile_or_package_swift_files == 2'

scan_case scan_missing "$fx/ios-app" missing
scan_not_ok scan_missing unavailable "adapter.sh is missing"
check scan_missing "not run" '.adapters.ios_xcode.ran == false'
scan_case scan_nohelper "$fx/ios-app" nohelper
scan_not_ok scan_nohelper unavailable "xml.awk is missing"

scan_case scan_exit2json "$fx/ios-app" exit2-error-json.sh
scan_not_ok scan_exit2json error "code 2: xml.awk not found"
check scan_exit2json "exit code recorded" '.adapters.ios_xcode.exit_code == 2 and .adapters.ios_xcode.ran == true'
scan_case scan_exit2silent "$fx/ios-app" exit2-silent.sh
scan_not_ok scan_exit2silent error "code 2: no output"
scan_case scan_killed "$fx/ios-app" killed.sh
scan_not_ok scan_killed error "exited with code 137"
for s in garbage two-docs wrong-schema bad-truncated; do
  scan_case "scan_stub_$s" "$fx/ios-app" "$s.sh"
  scan_not_ok "scan_stub_$s" error "not one ios-xcode JSON object"
done
scan_case scan_silent "$fx/ios-app" silent-incomplete.sh
scan_not_ok scan_silent incomplete "complete=false, 0 errors, 0 truncated"
scan_case scan_inconsistent "$fx/ios-app" inconsistent.sh
scan_not_ok scan_inconsistent incomplete "1 errors"

scan_case scan_php "$SKILL/tests/fixtures/php-symfony/symfony-app"
check scan_php "php-symfony adapter still ok" '.adapters.php_symfony.status == "ok" and .adapters.ios_xcode.status == "not_applicable"'

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

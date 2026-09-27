#!/bin/bash
# Tests for scripts/adapters/android/adapter.sh and its scan.sh integration.
# Fixtures in tests/fixtures/android/: Groovy app, Kotlin DSL with a version catalog, broken scripts,
# catalog and manifests, spaces in paths, limits and depth, dynamic settings, no Gradle.
# Files that hold canaries (.properties, .env, keystore, google-services.json), the wrapper
# properties and the excluded dirs are created at run time in a copy of the fixtures.
# ROOT boundary: '..' project paths and symlinks that leave ROOT are never read (OUTSIDE_CANARY).
# Integration: adapters.android statuses (ok, incomplete, not_applicable, unavailable, error) with stub adapters
# written at run time into a temporary copy of scripts/. Runs the adapter with /bin/bash (3.2 on macOS) when present.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
ADIR="$SKILL/scripts/adapters/android"
ADAPTER="$ADIR/adapter.sh"
SCAN="$SKILL/scripts/scan.sh"
BASH_BIN=/bin/bash
[ -x "$BASH_BIN" ] || BASH_BIN="$(command -v bash)"
PASS=0; FAIL=0
run="$(mktemp -d)"
trap 'chmod -R u+rw "$run" 2>/dev/null; rm -rf "$run"' EXIT
export TMPDIR="$run"
cp -R "$SKILL/tests/fixtures/android" "$run/fx"
fx="$run/fx"

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
# is_object NAME - code 0 when NAME.json is exactly one JSON object
is_object() { jq -e -s 'length == 1 and (.[0] | type) == "object"' "$run/$1.json" >/dev/null 2>&1; }
one_object() { is_object "$1" && ok || fail "$1: stdout is not one JSON object"; }
# no_word NAME WORD LABEL - NAME.json is one JSON object without WORD; invalid or empty output fails
no_word() {
  is_object "$1" || { fail "$1: output is not one JSON object"; return; }
  grep -q "$2" "$run/$1.json" && fail "$1: $3" || ok
}
no_canary() { no_word "$1" CANARY "secret canary leaked"; }
# same_data A B - equal output without started and duration_sec; invalid JSON on either side fails
same_data() {
  local a b
  a="$(jq -e -S -c 'del(.started, .duration_sec)' "$run/$1.json" 2>/dev/null)" || { fail "$1: output is not valid JSON"; return; }
  b="$(jq -e -S -c 'del(.started, .duration_sec)' "$run/$2.json" 2>/dev/null)" || { fail "$2: output is not valid JSON"; return; }
  [ -n "$a" ] && [ "$a" = "$b" ] && ok || fail "$2: output differs from $1 (deterministic data)"
}

# MARK: run-time files

g="$fx/groovy-app"
mkdir -p "$g/gradle/wrapper" "$g/build" "$g/.gradle/8.7" "$g/.idea" "$g/node_modules/pkg/android" "$g/app/build/outputs"
printf 'distributionBase=GRADLE_USER_HOME\ndistributionPath=wrapper/dists\ndistributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-bin.zip\n' >"$g/gradle/wrapper/gradle-wrapper.properties"
printf 'signing.password=CANARY_GRADLE_PROPERTIES\n' >"$g/gradle.properties"
printf 'sdk.dir=/CANARY_LOCAL_SDK\n' >"$g/local.properties"
printf 'API_TOKEN=CANARY_ENV\n' >"$g/.env"
printf 'CANARY_KEYSTORE\n' >"$g/release.jks"
printf '{"api_key": "CANARY_FIREBASE"}\n' >"$g/app/google-services.json"
printf "include ':from-build-dir'\n" >"$g/build/settings.gradle"
printf 'x\n' >"$g/.gradle/8.7/state.bin"
printf '<project/>\n' >"$g/.idea/workspace.xml"
printf "include ':from-node-modules'\n" >"$g/node_modules/pkg/android/settings.gradle"
printf 'x\n' >"$g/app/build/outputs/out.txt"
k="$fx/kts-catalog"
mkdir -p "$k/gradle/wrapper"
printf 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.10.2-all.zip\n' >"$k/gradle/wrapper/gradle-wrapper.properties"

# MARK: Groovy app

adapter gr "$g"
code_is gr 0
no_stderr gr
no_canary gr
one_object gr
check gr "schema" '.adapter == "android" and .schema_version == 1'
check gr "one build at root" '(.builds | length) == 1 and .builds[0].dir == "." and .summary.gradle_builds == 1'
check gr "excluded dirs, shallow first" '.excluded_dirs == [".gradle", ".idea", "build", "node_modules", "app/build"]'
check gr "no path from excluded dirs" '[.. | objects | .path? | strings | select(test("^(build|\\.gradle|\\.idea|node_modules|app/build)/"))] | length == 0'
check gr "settings" '.builds[0].settings | .path == "settings.gradle" and .dsl == "groovy" and .status == "ok"
  and .root_project_name == {value: "fixture-groovy", evidence: {path: "settings.gradle", line: 7}}'
check gr "includes with lines, comments ignored" '.builds[0].settings.includes == [
  {project: ":app", evidence: {path: "settings.gradle", line: 8}}, {project: ":core", evidence: {path: "settings.gradle", line: 9}},
  {project: ":features:home", evidence: {path: "settings.gradle", line: 9}}]'
check gr "modules" '[.builds[0].modules[].project] == [":", ":app", ":core", ":features:home"] and .builds[0].modules_declared == 4'
check gr "android types" '[.builds[0].modules[].android_type] == ["unknown", "application", "library", "library"]'
check gr "summary android modules" '.summary.android_modules == {application: 1, library: 2, unknown: 1} and .summary.manifests == 2'
check gr "root plugins not applied, version candidate from ext" '.builds[0].modules[0].plugins[0] | .id == "com.android.application" and .applied == false
  and .version.expression == "$agpVersion" and .version.text_candidate == {value: "8.5.0", source: "ext", evidence: {path: "build.gradle", line: 4}}'
check gr "root script plugin marker" '.builds[0].modules[0].build_file.markers == [{marker: "script_plugin", evidence: {path: "build.gradle", line: 20}}]'
check gr "app plugins" '[.builds[0].modules[1].plugins[] | [.id, .applied]] == [["com.android.application", true], ["org.jetbrains.kotlin.android", true]]'
check gr "namespace literal" '.builds[0].modules[1].android.namespace == {declared: "com.example.fixture", evidence: {path: "app/build.gradle", line: 7}}'
check gr "compileSdk expression with ext candidate" '.builds[0].modules[1].android.compile_sdk | .declared == null
  and .expression == "rootProject.ext.compileSdkVersion" and .text_candidate == {value: "34", source: "ext", evidence: {path: "build.gradle", line: 6}}'
check gr "sdk and jvm values" '.builds[0].modules[1].android | .min_sdk.text_candidate.value == "24" and .target_sdk.declared == "34"
  and .jvm_target.declared == "17" and .source_compatibility.expression == "JavaVersion.VERSION_17" and .source_compatibility.text_candidate == null
  and .application_id.declared == "com.example.fixture" and .test_instrumentation_runner.declared == "androidx.test.runner.AndroidJUnitRunner"'
check gr "namespace inside defaultConfig" '.builds[0].modules[3].android.namespace.declared == "com.example.features.home"'
check gr "build features" '.builds[0].modules[1].build_features.viewBinding.value == true and .builds[0].modules[3].build_features.dataBinding.value == true'
check gr "dependency counts" '.builds[0].modules[1] | .dependencies_total == 7
  and .dependencies_by_configuration == {androidTestImplementation: 1, implementation: 5, testImplementation: 1}'
check gr "dependency kinds" '[.builds[0].modules[1].dependencies[] | .kind] == ["project", "project", "coordinate", "coordinate", "files", "coordinate", "coordinate"]'
check gr "project dependency" '.builds[0].modules[1].dependencies[0] == {configuration: "implementation", kind: "project", notation: ":core", evidence: {path: "app/build.gradle", line: 49}}'
check gr "coordinate with ext version" '.builds[0].modules[1].dependencies[2] | .group == "androidx.core" and .name == "core-ktx"
  and .version.expression == "${coreKtxVersion}" and .version.text_candidate.value == "1.13.1"'
check gr "literal version" '.builds[0].modules[1].dependencies[3].version == {declared: "2.11.0", evidence: {path: "app/build.gradle", line: 52}}'
check gr "redacted statements" '.builds[0].modules[1].build_file.redacted_statements == 9 and .builds[0].modules[0].build_file.redacted_statements == 1'
check gr "no signing or secret text" '[.. | strings | select(test("keyAlias|storePassword|keyPassword|signingConfig|mapsApiKey|API_URL"; "i"))] | length == 0'
check gr "app manifest" '.builds[0].modules[1].manifests[0] | .path == "app/src/main/AndroidManifest.xml" and .source_set == "main" and .status == "ok"
  and .package == null and .application == ".FixtureApp" and .permissions == ["android.permission.INTERNET", "android.permission.CAMERA"]
  and .components == {activity: 2, provider: 1, service: 1} and .launcher_activities == [".MainActivity"] and .meta_data_count == 1'
check gr "minimal manifest" '.builds[0].modules[2].manifests[0] | .status == "ok" and .permissions == [] and .components == {} and .launcher_activities == []'
check gr "source sets" '[.builds[0].modules[1].source_sets[] | [.name, .dirs]] == [["androidTest", ["java"]], ["main", ["java"]], ["test", ["java"]]]'
check gr "wrapper" '.builds[0].wrapper == {declared: "8.7", distribution: "bin", evidence: {path: "gradle/wrapper/gradle-wrapper.properties", line: 3}, gradlew: true}'
check gr "declared AGP and Kotlin" '.builds[0].declared_toolchain | (.android_gradle_plugin | length) == 2
  and .android_gradle_plugin[0].version.text_candidate.value == "8.5.0" and (.kotlin | length) == 1 and .kotlin[0].version.text_candidate.value == "1.9.24"'
check gr "test tools" '[.builds[0].test_tools[].tool] == ["espresso", "instrumentation_runner", "junit4", "mockk", "source_set:androidTest", "source_set:test"]'
check gr "unlisted build script" '.builds[0].unlisted_build_files == [{path: "tools/build.gradle"}]'
check gr "unread files by path" '.builds[0].unread_files == {total: 5, paths: [".env", "app/google-services.json", "gradle.properties", "local.properties", "release.jks"]}'
check gr "properties unknown" '[.builds[0].unknown[] | select(.field == "gradle_properties") | .evidence.path] == ["gradle.properties", "local.properties"]'
check gr "module without manifest unknown" 'any(.builds[0].unknown[]; .field == "modules[:features:home].manifests")'
check gr "installed versions unknown" 'any(.unknown[]; .field == "installed_versions") and any(.unknown[]; .field == "evaluated_configuration")'
check gr "complete" '.complete == true and .truncated == [] and .errors == []'
check gr "no inferred architecture keys" '[paths | map(tostring) | join(".") | select(test("layer|domain|bounded|architecture|relation|graph"; "i"))] | length == 0'

adapter gr2 "$g"
same_data gr gr2

# MARK: Kotlin DSL and version catalog

adapter kts "$k"
code_is kts 0
no_stderr kts
no_canary kts
check kts "settings kotlin, credentials redacted" '.builds[0].settings | .dsl == "kotlin" and .redacted_statements == 3 and [.includes[].project] == [":app", ":lib"]'
check kts "catalog" '.builds[0].catalogs[0] | .path == "gradle/libs.versions.toml" and .name == "libs" and .status == "ok"
  and .counts == {versions: 7, libraries: 6, plugins: 4, bundles: 1} and .redacted_keys == 1'
check kts "rich version" 'any(.builds[0].catalogs[0].versions[]; .key == "espresso" and .value == "3.6.1")'
check kts "library forms" '.builds[0].catalogs[0].libraries | map({(.key): [.module, .version, .version_ref]}) | add
  | .["androidx-core-ktx"] == ["androidx.core:core-ktx", null, "coreKtx"] and .["espresso-core"] == ["androidx.test.espresso:espresso-core", "3.6.1", null]
    and .["compose-ui-test"] == ["androidx.compose.ui:ui-test-junit4", null, null] and .turbine == ["app.cash.turbine:turbine", "1.1.0", null]'
check kts "alias plugins resolved from catalog" '.builds[0].modules[1].plugins[0] | .id == null and .alias == "libs.plugins.android.application"
  and .catalog.id == "com.android.application" and .catalog.version.text_candidate.value == "8.6.1"'
check kts "android types" '[.builds[0].modules[] | [.project, .android_type]] == [[":", "none"], [":app", "application"], [":lib", "library"]]'
check kts "kotlin() plugin and semicolons" '[.builds[0].modules[2].plugins[].id] == ["com.android.library", "org.jetbrains.kotlin.android"]
  and .builds[0].modules[2].android.namespace.declared == "com.example.lib" and .builds[0].modules[2].android.compile_sdk.declared == "35"'
check kts "compileSdk from catalog text" '.builds[0].modules[1].android.compile_sdk | .expression == "libs.versions.compileSdk.get().toInt()"
  and .text_candidate == {value: "35", source: "version_catalog", evidence: {path: "gradle/libs.versions.toml", line: 5}}'
check kts "kotlin dsl values" '.builds[0].modules[1].android | .min_sdk.declared == "26" and .jvm_toolchain.declared == "17" and .namespace.declared == "com.example.kts"'
check kts "compose feature" '.builds[0].modules[1].build_features | .compose.value == true and .buildConfig.value == true'
check kts "placeholders redacted" '.builds[0].modules[1].build_file.redacted_statements == 1'
check kts "catalog dependency" '.builds[0].modules[1].dependencies[0] | .kind == "catalog" and .group == "androidx.core" and .name == "core-ktx"
  and .version.text_candidate.value == "1.13.1" and .catalog_entry == {path: "gradle/libs.versions.toml", line: 13}'
check kts "platform, typesafe project, bundle" '.builds[0].modules[1].dependencies | .[1].kind == "platform_catalog" and .[1].name == "compose-bom"
  and .[2] == {configuration: "implementation", kind: "project", notation: "projects.lib", evidence: {path: "app/build.gradle.kts", line: 30}}
  and .[5].kind == "bundle" and .[5].bundle_members == 2'
check kts "AGP and Kotlin from catalog" '.builds[0].declared_toolchain | [.android_gradle_plugin[].catalog_plugin] == ["com.android.application", "com.android.library"]
  and [.kotlin[].catalog_plugin] == ["org.jetbrains.kotlin.android", "org.jetbrains.kotlin.plugin.compose"]
  and .android_gradle_plugin[0].version.text_candidate.value == "8.6.1"'
check kts "manifests per source set" '[.builds[0].modules[1].manifests[] | .source_set] == ["debug", "main"]
  and .builds[0].modules[1].manifests[0].permissions == ["android.permission.POST_NOTIFICATIONS"]
  and .builds[0].modules[1].manifests[1].uses_sdk == {minSdkVersion: "26"} and .builds[0].modules[1].manifests[1].launcher_activities == [".ComposeActivity"]
  and .builds[0].modules[1].manifests[1].components == {activity: 1, receiver: 1}'
check kts "wrapper all distribution" '.builds[0].wrapper.declared == "8.10.2" and .builds[0].wrapper.distribution == "all" and .builds[0].wrapper.gradlew == false'
check kts "unlisted" '.builds[0].unlisted_build_files == [{path: "unlisted/build.gradle.kts"}]'
check kts "test tools" '[.builds[0].test_tools[].tool] == ["compose_ui_test", "junit4", "turbine"]'
check kts "complete" '.complete == true'

# MARK: broken files

adapter broken "$fx/broken"
code_is broken 0
no_stderr broken
one_object broken
check broken "all builds reported" '[.builds[].dir] == ["ambiguous", "braces", "empty-manifest", "extra-brace", "manifest", "toml", "unterminated"]'
check broken "errors with paths" '[.errors[].path] | sort == ["braces/app/build.gradle", "empty-manifest/lib/src/main/AndroidManifest.xml",
  "extra-brace/settings.gradle", "manifest/app/src/main/AndroidManifest.xml", "toml/gradle/libs.versions.toml", "unterminated/settings.gradle"]'
check broken "not complete" '.complete == false'
check broken "ambiguous settings not read" '.builds[0] | .settings.status == "ambiguous" and [.modules[].project] == [":"]
  and ([.unknown[] | select(.reason | test("both Groovy and Kotlin"))] | length) == 2'
check broken "unclosed block" '.builds[1].modules[1] | .build_file.status == "malformed" and (.build_file.reason | test("unclosed block"))
  and .plugins == [] and .android == {} and .android_type == "unknown"'
check broken "empty manifest" '.builds[2].modules[1].manifests[0] | .status == "malformed" and .reason == "empty file" and (has("package") | not)'
check broken "stray brace drops settings facts" '.builds[3].settings | .status == "malformed" and (.reason | test("closing brace")) and .includes == []'
check broken "stray brace: only root project" '[.builds[3].modules[].project] == [":"]'
check broken "mismatched manifest tag" '.builds[4].modules[1].manifests[0] | .status == "malformed" and (.reason | test("does not match")) and (has("permissions") | not)'
check broken "bad catalog" '.builds[5].catalogs[0] | .status == "malformed" and .bad_lines_total == 4
  and .bad_lines[0] == {line: 2, reason: "unterminated string"} and .versions == [] and .counts == null'
check broken "catalog error message" 'any(.errors[]; .path == "toml/gradle/libs.versions.toml" and (.error | test("4 line")))'
check broken "unterminated string" '.builds[6].settings.status == "malformed" and .builds[6].settings.reason == "unterminated string at line 2"'

# MARK: no Gradle and root build only

adapter none "$fx/no-gradle"
code_is none 0
check none "no builds" '.builds == [] and .summary.gradle_builds == 0 and any(.unknown[]; .field == "gradle") and .complete == true'

mkdir -p "$run/rootonly"
printf "plugins { id 'java' }\n" >"$run/rootonly/build.gradle"
adapter rootonly "$run/rootonly"
check rootonly "root build without settings" '.builds[0].settings == null and [.builds[0].modules[].project] == [":"]
  and any(.unknown[]; .field == "settings")'

# MARK: spaces in paths

adapter space "$fx/space root"
code_is space 0
check space "build dir with space" '.builds[0].dir == "sub build" and .builds[0].settings.path == "sub build/settings.gradle"
  and .builds[0].settings.root_project_name.value == "space build"'
check space "module and manifest paths" '.builds[0].modules[1] | .dir == "sub build/app" and .build_file.path == "sub build/app/build.gradle"
  and .manifests[0].path == "sub build/app/src/main/AndroidManifest.xml" and .manifests[0].package == "com.example.space.legacy"'
check space "catalog path" '.builds[0].catalogs[0].path == "sub build/gradle/libs.versions.toml" and .builds[0].catalogs[0].versions[0].value == "2.0.0"'

# MARK: limits and depth

adapter lim "$fx/limits"
code_is lim 0
check lim "defaults: one build, all modules" '(.builds | length) == 1 and .builds[0].modules_declared == 6 and (.builds[0].modules | length) == 6'
check lim "missing module dirs are unknown" '[.builds[0].modules[] | select(.dir_status == "missing") | .project] == [":m3", ":m4", ":m5"]'
check lim "markers" '[.builds[0].modules[1].build_file.markers[].marker] == ["script_plugin", "env_access", "conditional"]'
check lim "complete" '.complete == true'

adapter limsmall "$fx/limits" --max-modules 2 --max-deps 2 --max-permissions 2 --max-catalog-entries 2 --max-markers 1
code_is limsmall 0
check limsmall "modules cut" '[.builds[0].modules[].project] == [":", ":m1"] and any(.truncated[]; .field == "builds[.].modules" and .shown == 2 and .total == 6)'
check limsmall "dependencies cut" '(.builds[0].modules[1].dependencies | length) == 2 and .builds[0].modules[1].dependencies_total == 5
  and any(.truncated[]; .field == "builds[.].modules[:m1].dependencies" and .total == 5)'
check limsmall "permissions cut" 'any(.truncated[]; .field == "builds[.].manifests[m1/src/main/AndroidManifest.xml].permissions" and .shown == 2 and .total == 5)'
check limsmall "markers cut" 'any(.truncated[]; .field == "builds[.].files[m1/build.gradle].markers" and .shown == 1 and .total == 3)'
check limsmall "catalog cut" '(.builds[0].catalogs[0].versions | length) == 2 and any(.truncated[]; .field == "builds[.].catalogs[gradle/libs.versions.toml].versions" and .total == 5)'
check limsmall "limits echoed" '.limits | .max_modules == 2 and .max_deps == 2 and .max_permissions == 2 and .max_catalog_entries == 2 and .max_markers == 1'
check limsmall "not complete" '.complete == false and all(.truncated[]; .reason == "limit")'

adapter limman "$fx/limits" --max-manifests 1
check limman "manifests cut" '[.builds[0].modules[1].manifests[].source_set] == ["debug"] and any(.truncated[]; .field == "builds[.].modules[:m1].manifests" and .total == 2)'

adapter limdeep "$fx/limits" --max-depth 4
check limdeep "deeper settings with --max-depth 4" '[.builds[].dir] == [".", "deep/l2/l3/l4"] and .summary.gradle_builds == 2'
adapter limbuilds "$fx/limits" --max-depth 4 --max-builds 1
check limbuilds "builds cut" '[.builds[].dir] == ["."] and any(.truncated[]; .field == "builds" and .shown == 1 and .total == 2)'

# MARK: dynamic settings

adapter dyn "$fx/dynamic"
code_is dyn 0
no_stderr dyn
check dyn "nested build reported separately" '[.builds[].dir] == [".", "build-logic"]'
check dyn "settings markers" '[.builds[0].settings.markers[].marker] == ["loop", "dynamic_include", "conditional", "env_access"]'
check dyn "literal includes only" '[.builds[0].settings.includes[] | [.project, .evidence.line]] == [[":app", 2], [":legacy", 7], [":ci-only", 9]]'
check dyn "overrides and included builds" '.builds[0].settings.project_dir_overrides == [{project: ":legacy", evidence: {path: "settings.gradle", line: 6}}]
  and .builds[0].settings.include_builds == [{path: "build-logic", evidence: {path: "settings.gradle", line: 11}}]'
check dyn "project dirs" '[.builds[0].modules[] | [.project, .dir_status]] == [[":", "dir"], [":app", "dir"], [":ci-only", "missing"], [":legacy", "override"]]'
check dyn "apply plugin and markers" '.builds[0].modules[1] | .android_type == "application" and .plugins[0].via == "apply"
  and ([.build_file.markers[].marker] == ["script_plugin", "product_flavors"])'
check dyn "includes unknown" '([.builds[0].unknown[] | select(.field == "settings.includes")] | length) == 3'
check dyn "unlisted without nested build" '.builds[0].unlisted_build_files == [{path: "modules/feature-a/build.gradle"}]'
check dyn "convention plugins unknown" 'any(.builds[0].unknown[]; .field == "convention_plugins" and .evidence.path == "build-logic")'
check dyn "nested build modules" '.builds[1] | [.modules[] | [.project, .android_type]] == [[":", "none"], [":convention", "none"]]
  and .modules[1].plugins[0].id == "kotlin-dsl"'

# MARK: symlinks, size, permissions

mkdir -p "$run/links/real" "$run/links/filelink"
printf "include ':real', ':link', ':filelink'\n" >"$run/links/settings.gradle"
printf "plugins { id 'com.android.library' }\n" >"$run/links/real/build.gradle"
ln -s real "$run/links/link"
ln -s ../real/build.gradle "$run/links/filelink/build.gradle"
adapter links "$run/links"
check links "symlinked module dir not followed" 'any(.builds[0].modules[]; .project == ":link" and .dir_status == "symlink" and .build_file == null)'
check links "symlinked build script not read" 'any(.builds[0].modules[]; .project == ":filelink" and .build_file.status == "symlink" and .android_type == "unknown")'
check links "symlinks are unknown, not errors" '.errors == [] and ([.builds[0].unknown[] | select(.reason | test("symlink"))] | length) == 2'

mkdir -p "$run/large/app"
printf "include ':app'\n" >"$run/large/settings.gradle"
awk 'BEGIN { for (i = 0; i < 20000; i++) print "// padding line that makes this build script larger than the limit" }' >"$run/large/app/build.gradle"
adapter large "$run/large"
check large "too large file is an error" 'any(.errors[]; .path == "app/build.gradle" and (.error | test("larger than"))) and .complete == false'
check large "too large file not read" '.builds[0].modules[1].build_file.status == "too_large"'

mkdir -p "$run/noread"
printf "include ':app'\n" >"$run/noread/settings.gradle"
chmod 000 "$run/noread/settings.gradle"
if [ -r "$run/noread/settings.gradle" ]; then
  printf 'SKIP: unreadable settings.gradle: file stays readable for this user (root?)\n' >&2
else
  adapter noread "$run/noread"
  check noread "unreadable settings is an error" 'any(.errors[]; .path == "settings.gradle" and (.error | test("not readable"))) and .builds[0].settings.status == "unreadable"'
fi

# MARK: ROOT boundary
# Each case has a ROOT dir and files outside it that carry OUTSIDE_CANARY. Nothing outside ROOT may be read:
# the canary must not appear, the skip must be explicit (errors or unknown) and leaving ROOT makes complete false.

b="$run/bound"
no_outside() { no_word "$1" OUTSIDE_CANARY "file outside ROOT was read"; }
mkdir -p "$b/outside/b" "$b/outside/gradle/wrapper" "$b/outside/src/main" "$b/outside/set"
printf "plugins { id 'com.android.library' }\nandroid { namespace 'OUTSIDE_CANARY.module' }\n" >"$b/outside/build.gradle"
cp "$b/outside/build.gradle" "$b/outside/b/build.gradle"
printf 'distributionUrl=https\\://example.invalid/gradle-6.6-bin.zip\n# OUTSIDE_CANARY\n' >"$b/outside/gradle/wrapper/gradle-wrapper.properties"
printf '[versions]\nOUTSIDE_CANARY = "7.7.7"\n' >"$b/outside/gradle/libs.versions.toml"
printf '<manifest package="OUTSIDE_CANARY.manifest"/>\n' >"$b/outside/src/main/AndroidManifest.xml"
printf '<manifest package="OUTSIDE_CANARY.set"/>\n' >"$b/outside/set/AndroidManifest.xml"

# 1: '..' segment in a project path
mkdir -p "$b/r1/app"
printf "include ':app', ':..:outside'\n" >"$b/r1/settings.gradle"
printf "plugins { id 'com.android.library' }\n" >"$b/r1/app/build.gradle"
adapter bd_dotdot "$b/r1"
code_is bd_dotdot 0
no_stderr bd_dotdot
no_outside bd_dotdot
check bd_dotdot "'..' project not resolved" 'any(.builds[0].modules[]; .project == ":..:outside" and .dir_status == "invalid_path" and .build_file == null)'
check bd_dotdot "'..' project is an error" 'any(.errors[]; .error | test("\\.\\. segment")) and .complete == false'
check bd_dotdot "other modules still read" 'any(.builds[0].modules[]; .project == ":app" and .android_type == "library")'

# 2: intermediate project dir is a symlink that leads outside ROOT
mkdir -p "$b/r2"
printf "include ':a:b'\n" >"$b/r2/settings.gradle"
ln -s ../outside "$b/r2/a"
adapter bd_midout "$b/r2"
no_outside bd_midout
check bd_midout "project behind outside symlink" 'any(.builds[0].modules[]; .project == ":a:b" and .dir_status == "outside_root" and .build_file == null)'
check bd_midout "outside symlink is an error" 'any(.errors[]; .path == "a/b" and (.error | test("outside ROOT"))) and .complete == false'

# 3: intermediate project dir is a symlink that stays inside ROOT: not followed, unknown, not an error
mkdir -p "$b/r3/real/b"
printf "include ':a:b'\n" >"$b/r3/settings.gradle"
printf "plugins { id 'com.android.library' }\nandroid { namespace 'inside.linked' }\n" >"$b/r3/real/b/build.gradle"
ln -s real "$b/r3/a"
adapter bd_midin "$b/r3"
check bd_midin "inside symlink on the way not followed" 'any(.builds[0].modules[]; .project == ":a:b" and .dir_status == "symlink_path")
  and ([.. | strings | select(. == "inside.linked")] | length) == 0'
check bd_midin "inside symlink is unknown, not an error" '.errors == [] and any(.builds[0].unknown[]; .field == "modules[:a:b].dir" and (.reason | test("symlink")))'

# 4: gradle/ dir (wrapper and catalog) is a symlink that leads outside ROOT
mkdir -p "$b/r4"
printf "rootProject.name = 'r4'\n" >"$b/r4/settings.gradle"
ln -s ../outside/gradle "$b/r4/gradle"
adapter bd_gradle "$b/r4"
no_outside bd_gradle
check bd_gradle "wrapper and catalog not read" '.builds[0].wrapper == null and .builds[0].catalogs == [] and ([.. | strings | select(test("6\\.6|7\\.7\\.7"))] | length) == 0'
check bd_gradle "gradle dir outside is an error" 'any(.errors[]; .path == "gradle/wrapper/gradle-wrapper.properties" and (.error | test("outside ROOT")))
  and any(.errors[]; .path == "gradle/libs.versions.toml") and .complete == false'

# 5: src/ of a module is a symlink that leads outside ROOT (manifest behind it)
mkdir -p "$b/r5/app"
printf "include ':app'\n" >"$b/r5/settings.gradle"
printf "plugins { id 'com.android.library' }\n" >"$b/r5/app/build.gradle"
ln -s ../../outside/src "$b/r5/app/src"
adapter bd_src "$b/r5"
no_outside bd_src
check bd_src "src outside not read" '.builds[0].modules[1].manifests == [] and .builds[0].modules[1].source_sets == []
  and any(.errors[]; .path == "app/src" and (.error | test("outside ROOT"))) and .complete == false'

# 6: one source set dir is a symlink that leads outside ROOT
mkdir -p "$b/r6/app/src/main"
printf "include ':app'\n" >"$b/r6/settings.gradle"
printf "plugins { id 'com.android.library' }\n" >"$b/r6/app/build.gradle"
printf '<manifest package="inside.main"/>\n' >"$b/r6/app/src/main/AndroidManifest.xml"
ln -s ../../../outside/set "$b/r6/app/src/debug"
adapter bd_set "$b/r6"
no_outside bd_set
check bd_set "source set outside not read, main read" '[.builds[0].modules[1].manifests[].package] == ["inside.main"]
  and any(.errors[]; .path == "app/src/debug" and (.error | test("outside ROOT"))) and .complete == false'

# 7: build script is a symlink to a file outside ROOT
mkdir -p "$b/r7/app"
printf "include ':app'\n" >"$b/r7/settings.gradle"
ln -s ../../outside/build.gradle "$b/r7/app/build.gradle"
adapter bd_file "$b/r7"
no_outside bd_file
check bd_file "file symlink outside is an error" '.builds[0].modules[1].build_file.status == "outside_root"
  and any(.errors[]; .path == "app/build.gradle" and (.error | test("outside ROOT"))) and .complete == false'

# 8: ROOT itself reached through a symlink stays readable
ln -s r1 "$b/r1-link"
adapter bd_rootlink "$b/r1-link"
check bd_rootlink "ROOT behind a symlink is read" 'any(.builds[0].modules[]; .project == ":app" and .android_type == "library")'

# MARK: bad input

adapter badopt "$g" --max-modules x
code_is badopt 2
check badopt "error JSON" '.error | test("needs a non-negative number")'
adapter badflag "$g" --unknown
code_is badflag 2
adapter badroot "$run/does-not-exist"
code_is badroot 2
check badroot "error JSON" '.error == "directory not found"'
mkdir -p "$run/lonely"
cp "$ADAPTER" "$run/lonely/adapter.sh"
"$BASH_BIN" "$run/lonely/adapter.sh" "$g" >"$run/lonely.json" 2>"$run/lonely.err"; echo $? >"$run/lonely.code"
code_is lonely 2
check lonely "missing helper named" '.error | test("gradle-facts.awk not found")'

# MARK: scan.sh integration

# stub NAME - writes a stub adapter.sh for the error and incomplete cases to $run/stubs/NAME.sh
mkdir -p "$run/stubs"
stub() {
  local body
  case "$1" in
    exit2-valid-json) body="echo '{\"adapter\":\"android\",\"schema_version\":1,\"complete\":true,\"truncated\":[],\"errors\":[],\"builds\":[]}'; exit 2" ;;
    exit2-error-json) body="echo '{\"error\":\"gradle-facts.awk not found next to adapter.sh\"}'; exit 2" ;;
    exit2-silent) body='exit 2' ;;
    killed) body="printf '{\"adapter\":\"android\",'; kill -KILL \$\$" ;;
    garbage) body="echo 'awk: syntax error'; exit 0" ;;
    two-docs) body="echo '{\"adapter\":\"android\",\"schema_version\":1,\"complete\":true,\"truncated\":[],\"errors\":[]}'; echo '{}'" ;;
    other-adapter) body="echo '{\"adapter\":\"php-symfony\",\"schema_version\":1,\"complete\":true,\"truncated\":[],\"errors\":[]}'" ;;
    schema-2) body="echo '{\"adapter\":\"android\",\"schema_version\":2,\"complete\":true,\"truncated\":[],\"errors\":[]}'" ;;
    bad-truncated) body="echo '{\"adapter\":\"android\",\"schema_version\":1,\"complete\":false,\"truncated\":[{\"field\":1}],\"errors\":[]}'" ;;
    silent-incomplete) body="echo '{\"adapter\":\"android\",\"schema_version\":1,\"complete\":false,\"truncated\":[],\"errors\":[],\"builds\":[]}'" ;;
    inconsistent) body="echo '{\"adapter\":\"android\",\"schema_version\":1,\"complete\":true,\"truncated\":[],\"errors\":[{\"path\":\"settings.gradle\",\"error\":\"settings.gradle is not readable\"}],\"builds\":[]}'" ;;
    *) fail "unknown stub $1"; return 1 ;;
  esac
  printf '#!/bin/bash\n%s\n' "$body" >"$run/stubs/$1.sh"
}
# scan_case NAME DIR [ADAPTER] - runs scan.sh on DIR. ADAPTER: empty = the skill scan.sh with all adapters;
# otherwise a copy of scripts/ with "missing:FILE" = that android file removed, or a stub name installed as
# the android adapter.sh. JSON in NAME.json, exit code in NAME.code.
scan_case() {
  local name="$1" dir="$2" adp="${3:-}" sk="$run/skill-$1" scan="$SCAN"
  if [ -n "$adp" ]; then
    mkdir -p "$sk"
    cp -R "$SKILL/scripts" "$sk/"
    scan="$sk/scripts/scan.sh"
    case "$adp" in
      missing:*) rm "$sk/scripts/adapters/android/${adp#missing:}" ;;
      *) stub "$adp" && cp "$run/stubs/$adp.sh" "$sk/scripts/adapters/android/adapter.sh" ;;
    esac
  fi
  "$BASH_BIN" "$scan" "$dir" >"$run/$name.json" 2>"$run/$name.err"
  echo $? >"$run/$name.code"
}
# scan_not_ok NAME STATUS REASON_REGEX - scan JSON printed with exit 0, scan.complete false, the adapter status and
# a matching reason in scan.incomplete; for error and unavailable no adapter facts or adapter cuts are kept
scan_not_ok() {
  code_is "$1" 0
  one_object "$1"
  check "$1" "scan.complete false" '.scan.complete == false'
  check "$1" "status $2" ".adapters.android.status == \"$2\""
  check "$1" "reason in scan.incomplete" "any(.scan.incomplete[]?; .field == \"adapters.android\" and .status == \"$2\" and (.reason | test(\"$3\")))"
  case "$2" in error|unavailable)
    check "$1" "no adapter facts or cuts kept" '(.adapters.android | has("builds") or has("summary") | not)
      and ([.scan.truncated[] | select(.field | startswith("adapters.android"))] == [])' ;;
  esac
}

grep -q 'android_json' "$SCAN" && ok || fail "scan.sh has no android_json section"

scan_case scan_kts "$k"
code_is scan_kts 0
check scan_kts "status ok with facts" '.adapters.android | .status == "ok" and .ran == true and .exit_code == 0 and .reason == null
  and .adapter == "android" and .summary.gradle_builds == 1 and (has("root") or has("started") | not)'
check scan_kts "trigger evidence" '.adapters.android.trigger == {settings_files: 1, build_files: 4, stacks_gradle_entries: 4}'
check scan_kts "no android entry in scan.incomplete or scan.truncated" '([.scan.incomplete[] | select(.field | startswith("adapters.android"))] == [])
  and ([.scan.truncated[] | select(.field | startswith("adapters.android"))] == [])'
check scan_kts "section time" '.scan.sections_sec | has("android")'
check scan_kts "other adapters not applicable" '[.adapters.php_symfony, .adapters.ios_xcode, .adapters.angular | .status] == ["not_applicable", "not_applicable", "not_applicable"]'

scan_case scan_groovy "$g"
check scan_groovy "groovy app: ok, no canary in the adapter section" '.adapters.android.status == "ok" and (.adapters.android | tostring | test("CANARY") | not)'

scan_case scan_none "$fx/no-gradle"
check scan_none "no Gradle: not_applicable, not run" '.adapters.android | .status == "not_applicable" and .ran == false and .exit_code == null
  and (has("builds") | not) and (.reason | test("not run")) and .trigger == {settings_files: 0, build_files: 0, stacks_gradle_entries: 0}'
check scan_none "not_applicable adds no incomplete entry" '[.scan.incomplete[] | select(.field == "adapters.android")] == []'

scan_case scan_broken "$fx/broken"
scan_not_ok scan_broken incomplete "complete=false, 6 errors, 0 truncated; first error: "
check scan_broken "adapter errors kept" '(.adapters.android.errors | length) == 6'

scan_case scan_large "$run/large"
scan_not_ok scan_large incomplete "larger than"

scan_case scan_limits "$fx/limits"
check scan_limits "limits fixture within defaults is ok" '.adapters.android.status == "ok"'

scan_case scan_dotdot "$b/r1"
scan_not_ok scan_dotdot incomplete "segment"
check scan_dotdot "':..:outside' not read through scan.sh" '(.adapters.android | tostring | test("OUTSIDE_CANARY") | not)
  and any(.adapters.android.builds[0].modules[]; .project == ":..:outside" and .dir_status == "invalid_path")'
scan_case scan_midout "$b/r2"
scan_not_ok scan_midout incomplete "outside ROOT"
check scan_midout "symlink out of ROOT not read through scan.sh" '.adapters.android | tostring | test("OUTSIDE_CANARY") | not'

scan_case scan_missing "$k" missing:adapter.sh
scan_not_ok scan_missing unavailable "adapters/android/adapter.sh is missing"
check scan_missing "not run" '.adapters.android.ran == false and .adapters.android.exit_code == null'
for h in gradle-facts.awk toml-facts.awk manifest-facts.awk build-facts.jq; do
  scan_case "scan_missing_$h" "$k" "missing:$h"
  scan_not_ok "scan_missing_$h" unavailable "adapters/android/$h is missing"
done

scan_case scan_exit2json "$k" exit2-valid-json
scan_not_ok scan_exit2json error "exited with code 2"
check scan_exit2json "exit code recorded" '.adapters.android.exit_code == 2 and .adapters.android.ran == true'
scan_case scan_exit2err "$k" exit2-error-json
scan_not_ok scan_exit2err error "code 2: gradle-facts.awk not found"
scan_case scan_exit2silent "$k" exit2-silent
scan_not_ok scan_exit2silent error "code 2: no output"
scan_case scan_killed "$k" killed
scan_not_ok scan_killed error "exited with code 137"
for s in garbage two-docs other-adapter schema-2 bad-truncated; do
  scan_case "scan_stub_$s" "$k" "$s"
  scan_not_ok "scan_stub_$s" error "not one android JSON object"
done
scan_case scan_silent "$k" silent-incomplete
scan_not_ok scan_silent incomplete "complete=false, 0 errors, 0 truncated"
scan_case scan_inconsistent "$k" inconsistent
scan_not_ok scan_inconsistent incomplete "complete=true, 1 errors"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

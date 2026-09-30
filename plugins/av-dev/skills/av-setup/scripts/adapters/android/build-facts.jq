# build-facts.jq - facts of one Gradle build from the TSV records of adapter.sh (read with -R -s).
# Args: $dir (build dir relative to ROOT), $max_deps, $max_catalog, $max_samples, $max_markers, $unread_total.
# Records (tab separated, first field = tag):
#   F mod path role status          file considered for reading (ok, symlink, unreadable, too_large, ambiguous)
#   G mod path kind ...             gradle-facts.awk    T "" path kind ...   toml-facts.awk
#   M mod path kind ...             manifest-facts.awk  W "" path version type line   wrapper distributionUrl
#   D mod dir type                  project dir (dir, missing, symlink, override)
#   S mod path subdir               source set dir     P role path type   fixed path check
#   L "" path  unlisted build script                   U "" path  file never opened
# Output: {build, truncated, errors}. Values are text: "declared" is a literal from a file,
# "expression" is unresolved script text, "text_candidate" is a literal found for that expression
# in ext or version catalog text (never a Gradle evaluation result).

def recs: split("\n") | map(select(length > 0) | split("\t"));
def ln: tonumber? // null;
def ev($p; $l): {path: $p, line: ($l | ln)};
def acc: gsub("[-_]"; ".");
def dsl: if endswith(".kts") then "kotlin" elif endswith(".gradle") then "groovy" else null end;

(recs) as $r
| ($r | map(select(.[0] == "F"))) as $F
| ($r | map(select(.[0] == "G"))) as $Gall
| ([$Gall[] | select(.[3] == "status" and .[4] == "ok") | .[2]]) as $okp
# facts of a script that did not parse cleanly are dropped; its status record stays
| ($Gall | map(select(.[3] == "status" or .[3] == "redacted" or (.[2] as $p | $okp | index([$p]) != null)))) as $G
| ($r | map(select(.[0] == "T"))) as $T
| ([$T[] | select(.[3] == "bad") | .[2]] | unique) as $badcat
| ($r | map(select(.[0] == "M"))) as $M
| ($r | map(select(.[0] == "D"))) as $D

# MARK: ext literals and catalogs

| ($G | map(select(.[3] == "ext") | {name: .[4], value: .[5], evidence: ev(.[2]; .[6])})) as $ext
| ($G | map(select(.[3] == "catalog_from") | {name: .[4], from: .[5]})) as $catfrom
| ($T | map(.[2]) | unique) as $catpaths
| ($catpaths | map(. as $p
    | ($p | split("/") | last) as $base
    | ([$catfrom[] | select(.from != "" and (.from | endswith($base))) | .name] | first) as $named
    | {path: $p, name: ($named // (if $base == "libs.versions.toml" then "libs" else null end)),
       name_source: (if $named then "settings versionCatalogs" elif $base == "libs.versions.toml" then "default file name" else null end)})) as $catnames
| ([$catnames[] | select(.name == "libs" and (.path as $p | $badcat | index([$p]) | not)) | .path] | first) as $libs
| ($T | map(select(.[2] == $libs))) as $L
| ($L | map(select(.[3] == "version")) | map({key: (.[4] | acc), value: {value: .[5], evidence: ev(.[2]; .[6])}}) | from_entries) as $lv
| ($L | map(select(.[3] == "library")) | map({key: (.[4] | acc), value: {module: .[5], version: .[6], ref: .[7], evidence: ev(.[2]; .[8])}}) | from_entries) as $ll
| ($L | map(select(.[3] == "plugin")) | map({key: (.[4] | acc), value: {id: .[5], version: .[6], ref: .[7], evidence: ev(.[2]; .[8])}}) | from_entries) as $lp
| ($L | map(select(.[3] == "bundle")) | map({key: (.[4] | acc), value: {members: (.[5] | tonumber), evidence: ev(.[2]; .[6])}}) | from_entries) as $lb

# MARK: values

| def refname:
    sub("^\\$\\{"; "") | sub("^\\$"; "") | sub("\\}$"; "")
    | sub("(\\.get\\(\\))?(\\.toInt\\(\\)|\\.toString\\(\\))?$"; "")
    | if test("^libs\\.versions\\.[A-Za-z0-9_.]+$") then {kind: "catalog", name: sub("^libs\\.versions\\."; "")}
      elif test("^((rootProject|project)\\.)?(ext\\.)?[A-Za-z_][A-Za-z0-9_]*$") then {kind: "ext", name: sub("^.*\\."; "")}
      else null end;
  def cand($x):
    if $x == null then null
    elif $x.kind == "catalog" then ($lv[$x.name | acc]) as $v
      | if $v and $v.value != "" then {value: $v.value, source: "version_catalog", evidence: $v.evidence} else null end
    else ([$ext[] | select(.name == $x.name)]) as $m
      | ($m | map(.value) | unique) as $vals
      | if ($vals | length) == 1 then {value: $vals[0], source: "ext", evidence: $m[0].evidence}
        elif ($vals | length) > 1 then {value: null, source: "ext", ambiguous: true, evidence: ($m | map(.evidence))}
        else null end
    end;
  def vobj($v; $ev):
    if $v == "" or $v == null then null
    elif ($v | startswith("=")) then ($v[1:]) as $e | {declared: null, expression: $e, text_candidate: cand($e | refname), evidence: $ev}
    elif ($v | test("\\$")) then {declared: null, expression: $v, text_candidate: cand($v | refname), evidence: $ev}
    else {declared: $v, evidence: $ev} end;
  def catver($c):
    if $c == null then null
    elif $c.version != "" then {declared: $c.version, evidence: $c.evidence}
    elif $c.ref != "" then ($lv[$c.ref | acc]) as $v
      | {declared: null, expression: ("version.ref " + $c.ref), evidence: $c.evidence,
         text_candidate: (if $v and $v.value != "" then {value: $v.value, source: "version_catalog", evidence: $v.evidence} else null end)}
    else null end;

# MARK: files

  def markers($p): [$G[] | select(.[2] == $p and .[3] == "marker") | {marker: .[4], evidence: ev(.[2]; .[5])}];
  def gstatus($p): ([$G[] | select(.[2] == $p and .[3] == "status")] | first) as $s
    | if $s then {status: $s[4], reason: (if $s[5] == "" then null else $s[5] end)} else null end;
  def redacted($p): ([$G[] | select(.[2] == $p and .[3] == "redacted") | .[4] | tonumber] | first) // 0;
  def script($mod; $role):
    [$F[] | select(.[1] == $mod and .[3] == $role)] as $f
    | if ($f | length) == 0 then null
      elif ($f | length) > 1 then {paths: ($f | map(.[2])), status: "ambiguous", dsl: null}
      else $f[0] as $x | (if $x[4] == "ok" then gstatus($x[2]) else null end) as $s
        | {path: $x[2], dsl: ($x[2] | dsl), status: ($s.status // $x[4]), reason: ($s.reason // null),
           redacted_statements: (if $x[4] == "ok" then redacted($x[2]) else null end),
           markers: (if $x[4] == "ok" then markers($x[2]) else [] end)}
      end;

# MARK: settings

  (script(""; "settings")) as $settings
| ($G | map(select(.[1] == "" and .[3] == "include")) | map({project: .[4], evidence: ev(.[2]; .[5])})) as $includes
| ($settings | if . == null then null else . + {
     root_project_name: ([$G[] | select(.[1] == "" and .[3] == "root_name") | {value: .[4], evidence: ev(.[2]; .[5])}] | first // null),
     includes: $includes,
     include_builds: [$G[] | select(.[1] == "" and .[3] == "include_build") | {path: .[4], evidence: ev(.[2]; .[5])}],
     project_dir_overrides: [$G[] | select(.[1] == "" and .[3] == "dir_override") | {project: .[4], evidence: ev(.[2]; .[5])}],
     version_catalogs: [$G[] | select(.[1] == "" and (.[3] == "catalog")) | {name: .[4], evidence: ev(.[2]; .[6])}]} end) as $settings

# MARK: modules

| def plugin_rows($p): [$G[] | select(.[2] == $p and .[3] == "plugin")
    | . as $x | (if $x[6] == "alias" then $x[4] else null end) as $alias
    | ($alias | if . and startswith("libs.plugins.") then $lp[ltrimstr("libs.plugins.") | acc] else null end) as $c
    | {id: (if $alias or $x[4] == "" then null else $x[4] end), via: $x[6], applied: ($x[7] == "true"),
       version: vobj($x[5]; ev($x[2]; $x[8])), evidence: ev($x[2]; $x[8])}
      + (if $alias then {alias: $alias, catalog: (if $c then {id: $c.id, version: catver($c), evidence: $c.evidence} else null end)} else {} end)];
  def dep_rows($p): [$G[] | select(.[2] == $p and .[3] == "dep")
    | . as $x | ev($x[2]; $x[7]) as $e
    | {configuration: $x[4], kind: $x[5], notation: (if $x[6] == "" or ($x[6] | startswith("=")) then null else $x[6] end), evidence: $e}
    + (if ($x[6] | startswith("=")) then {expression: ($x[6][1:]), note: "notation built from a string and an expression; not resolved"}
       elif ($x[5] == "coordinate" or $x[5] == "platform") and $x[6] != "" then ($x[6] | split(":")) as $c
         | {group: $c[0], name: ($c[1] // null), version: vobj($c[2] // ""; $e)}
       elif ($x[5] == "catalog" or $x[5] == "platform_catalog") then $ll[$x[6] | ltrimstr("libs.") | acc] as $c
         | if $c then ($c.module | split(":")) as $m | {group: $m[0], name: $m[1], version: catver($c), catalog_entry: $c.evidence}
           else {catalog_entry: null} end
       elif $x[5] == "bundle" then {bundle_members: ($lb[$x[6] | ltrimstr("libs.bundles.") | acc].members // null)}
       else {} end)];
  def android_rows($p): [$G[] | select(.[2] == $p and .[3] == "android")
    | {key: (.[4] | {namespace: "namespace", applicationId: "application_id", versionName: "version_name", versionCode: "version_code",
                     compileSdk: "compile_sdk", compileSdkVersion: "compile_sdk",
                     minSdk: "min_sdk", minSdkVersion: "min_sdk", targetSdk: "target_sdk", targetSdkVersion: "target_sdk",
                     testInstrumentationRunner: "test_instrumentation_runner", sourceCompatibility: "source_compatibility",
                     targetCompatibility: "target_compatibility", jvmTarget: "jvm_target", jvmToolchain: "jvm_toolchain"}[.]),
       value: (vobj(.[5]; ev(.[2]; .[6])) // {declared: null, expression: null, evidence: ev(.[2]; .[6]), note: "value not parsed"})}]
    | group_by(.key) | map({key: .[0].key, value: (.[0].value + (if length > 1 then {occurrences: length} else {} end))}) | from_entries;
  def features($p): [$G[] | select(.[2] == $p and .[3] == "feature") | {key: .[4], value: {value: (.[5] == "true"), evidence: ev(.[2]; .[6])}}]
    | group_by(.key) | map(last) | from_entries;
  def manifests($mod):
    [$F[] | select(.[1] == $mod and .[3] == "manifest")] | map(. as $f
    | [$M[] | select(.[2] == $f[2])] as $x
    | ([$x[] | select(.[3] == "status")] | first) as $s
    | {path: $f[2], source_set: ($f[2] | split("/") | .[-2]), status: (if $f[4] != "ok" then $f[4] else ($s[4] // "error") end),
       reason: (if $s and $s[5] != "" then $s[5] else null end)}
    + (if $f[4] == "ok" and ($s[4] // "") == "ok" then {
         package: ([$x[] | select(.[3] == "package") | .[4]] | first // null),
         uses_sdk: ([$x[] | select(.[3] == "uses_sdk") | {key: .[4], value: .[5]}] | from_entries),
         application: ([$x[] | select(.[3] == "application") | .[4]] | first // null),
         permissions: [$x[] | select(.[3] == "permission") | .[4]],
         permissions_total: ([$x[] | select(.[3] == "permissions_total") | .[4] | tonumber] | first // 0),
         components: ([$x[] | select(.[3] == "component") | {key: .[4], value: (.[5] | tonumber)}] | sort_by(.key) | from_entries),
         launcher_activities: [$x[] | select(.[3] == "launcher") | .[4]],
         meta_data_count: ([$x[] | select(.[3] == "meta_data") | .[4] | tonumber] | first // 0),
         evidence: {path: $f[2]}} else {} end));
  def source_sets($mod): [$r[] | select(.[0] == "S" and .[1] == $mod)] | group_by(.[2])
    | map({name: (.[0][2] | split("/") | last), path: .[0][2], dirs: (map(.[3]) | map(select(. != "")) | sort)});

  ([$G[] | select(.[1] == ":" and .[3] == "marker" and .[4] == "cross_project_config")] | length > 0) as $cross
| ($D | map(. as $d
    | script($d[1]; "build") as $bf
    | ($bf.path // "") as $p
    | ($bf != null and $bf.status == "ok") as $read
    | (if $read then plugin_rows($p) else [] end) as $plugins
    | (if $read then dep_rows($p) else [] end) as $deps
    | ([$plugins[] | select(.applied) | (.id // .catalog.id // empty)]) as $ids
    | {project: $d[1], dir: (if $d[2] == "" then null else $d[2] end), dir_status: $d[3], build_file: $bf,
       android_type: (
         if any($ids[]; . == "com.android.application") then "application"
         elif any($ids[]; . == "com.android.library") then "library"
         elif any($ids[]; . == "com.android.dynamic-feature") then "dynamic_feature"
         elif any($ids[]; . == "com.android.test") then "test"
         elif any($ids[]; . == "com.android.kotlin.multiplatform.library") then "kmp_library"
         elif $d[3] != "dir" or ($bf != null and ($read | not)) or any($plugins[]; .via == "unparsed" or (.alias and .catalog == null))
              or any(($bf.markers // [])[]; .marker == "script_plugin") or ($cross and $d[1] != ":") then "unknown"
         else "none" end),
       plugins: $plugins,
       android: (if $read then android_rows($p) else {} end),
       build_features: (if $read then features($p) else {} end),
       dependencies_total: ($deps | length),
       dependencies_by_configuration: ($deps | group_by(.configuration) | map({key: .[0].configuration, value: length}) | from_entries),
       dependencies: $deps[:$max_deps],
       source_sets: source_sets($d[1]),
       manifests: manifests($d[1])})) as $modules

# MARK: toolchain and tools

| ([$modules[] | .plugins[] | select((.id // "") | startswith("com.android.")) | {plugin: .id, version, evidence}]
   + [$modules[] | .dependencies[] | select(.configuration == "classpath" and .group == "com.android.tools.build" and .name == "gradle")
    | {classpath: "com.android.tools.build:gradle", version, evidence}]
   + [$lp[] | select(.id | startswith("com.android.")) | {catalog_plugin: .id, version: catver(.), evidence}]
   | map(select(.version != null)) | unique_by(.evidence)) as $agp
| ([$modules[] | .plugins[] | select((.id // "") | startswith("org.jetbrains.kotlin.")) | {plugin: .id, version, evidence}]
   + [$modules[] | .dependencies[] | select(.configuration == "classpath" and .group == "org.jetbrains.kotlin" and .name == "kotlin-gradle-plugin")
    | {classpath: "org.jetbrains.kotlin:kotlin-gradle-plugin", version, evidence}]
   + [$lp[] | select(.id | startswith("org.jetbrains.kotlin.")) | {catalog_plugin: .id, version: catver(.), evidence}]
   | map(select(.version != null)) | unique_by(.evidence)) as $kotlin
| ([$r[] | select(.[0] == "W") | {declared: (if .[3] == "" then null else .[3] end), distribution: (if .[4] == "" then null else .[4] end), evidence: ev(.[2]; .[5])}]) as $gradle
| def tool: (.group // "") as $g | (.name // "") as $n
    | if $g == "junit" and $n == "junit" then "junit4"
      elif $g == "org.junit.jupiter" or ($g == "org.junit" and $n == "junit-bom") then "junit5"
      elif $g == "androidx.test.espresso" then "espresso"
      elif $g == "androidx.test" or $g == "androidx.test.ext" then "androidx_test"
      elif $g == "io.mockk" then "mockk"
      elif $g == "org.mockito" or $g == "org.mockito.kotlin" then "mockito"
      elif $g == "org.robolectric" then "robolectric"
      elif $g == "io.kotest" then "kotest"
      elif $g == "app.cash.turbine" then "turbine"
      elif $g == "androidx.compose.ui" and ($n | startswith("ui-test")) then "compose_ui_test"
      elif $g == "com.google.truth" then "truth"
      elif $g == "org.jetbrains.kotlinx" and $n == "kotlinx-coroutines-test" then "coroutines_test"
      elif $g == "androidx.arch.core" and $n == "core-testing" then "arch_core_testing"
      elif $g == "com.squareup.okhttp3" and $n == "mockwebserver" then "mockwebserver"
      else null end;
  ([$modules[] | .dependencies[] | tool as $t | select($t != null) | {tool: $t, evidence: (.evidence + {notation: (.notation // null)})}]
   + [$modules[] | .plugins[] | (.id // .catalog.id // "") as $i
      | (if $i == "de.mannodermaus.android-junit5" then "junit5" elif $i == "app.cash.paparazzi" then "paparazzi" elif $i == "io.github.takahirom.roborazzi" then "roborazzi" else null end) as $t
      | select($t != null) | {tool: $t, evidence: .evidence}]
   + [$modules[] | .source_sets[] | select(.name == "test" or .name == "androidTest") | {tool: ("source_set:" + .name), evidence: {path: .path}}]
   + [$modules[] | .android.test_instrumentation_runner // empty | select(.declared != null) | {tool: "instrumentation_runner", evidence: (.evidence + {value: .declared})}]
   | group_by(.tool) | map({tool: .[0].tool, evidence_total: length, evidence: (map(.evidence) | .[:$max_samples])})) as $tools

# MARK: catalogs

| ($catnames | map(. as $c
    | [$T[] | select(.[2] == $c.path)] as $x
    | [$x[] | select(.[3] == "bad") | {line: (.[4] | ln), reason: .[5]}] as $bad
    | ([$F[] | select(.[2] == $c.path)] | first) as $f
    | {path: $c.path, name: $c.name, name_source: $c.name_source,
       status: (if ($f[4] // "ok") != "ok" then $f[4] elif ($bad | length) > 0 then "malformed" else "ok" end),
       bad_lines: $bad[:$max_samples], bad_lines_total: ($bad | length),
       redacted_keys: ([$x[] | select(.[3] == "redacted") | .[4] | tonumber] | first // 0),
       other_tables: [$x[] | select(.[3] == "section") | .[4]],
       counts: {versions: ([$x[] | select(.[3] == "version")] | length), libraries: ([$x[] | select(.[3] == "library")] | length),
                plugins: ([$x[] | select(.[3] == "plugin")] | length), bundles: ([$x[] | select(.[3] == "bundle")] | length)},
       versions: [$x[] | select(.[3] == "version") | {key: .[4], value: (if .[5] == "" then null else .[5] end), evidence: ev(.[2]; .[6])}][:$max_catalog],
       plugins: [$x[] | select(.[3] == "plugin") | {key: .[4], id: .[5], version: (if .[6] == "" then null else .[6] end), version_ref: (if .[7] == "" then null else .[7] end), evidence: ev(.[2]; .[8])}][:$max_catalog],
       libraries: [$x[] | select(.[3] == "library") | {key: .[4], module: .[5], version: (if .[6] == "" then null else .[6] end), version_ref: (if .[7] == "" then null else .[7] end), evidence: ev(.[2]; .[8])}][:$max_catalog],
       bundles: [$x[] | select(.[3] == "bundle") | {key: .[4], members: (.[5] | tonumber), evidence: ev(.[2]; .[6])}][:$max_catalog]}
    | if .status == "ok" then . else .counts = null | .versions = [] | .plugins = [] | .libraries = [] | .bundles = [] end)) as $catalogs

# MARK: errors, cuts, unknown

| ("builds[" + $dir + "]") as $b
| ([$r[] | select(.[0] == "P")]) as $P
| ([$F[] | select(.[4] == "outside_root") | {path: .[2], error: (.[3] + " path leads outside ROOT through a symlink; not read")}]
   + [$D[] | select(.[3] == "outside_root") | {path: .[2], error: ("project " + .[1] + " directory leads outside ROOT through a symlink; not read")}]
   + [$P[] | select(.[3] == "outside_root") | {path: .[2], error: (.[1] + " path leads outside ROOT through a symlink; not read")}]
   | unique_by(.path)) as $outside
| ([$F[] | select(.[4] == "unreadable") | {path: .[2], error: (.[3] + " file is not readable")}]
   + $outside
   + [$D[] | select(.[3] == "invalid_path") | {path: ($settings.path // $dir), error: ("project path " + .[1] + " has an empty, . or .. segment; its directory is not resolved or read")}]
   + [$F[] | select(.[4] == "too_large") | {path: .[2], error: (.[3] + " file is larger than the max_file_kb limit, not read")}]
   + [$G[] | select(.[3] == "status" and .[4] != "ok") | {path: .[2], error: ("gradle script " + .[4] + ": " + .[5])}]
   + [$M[] | select(.[3] == "status" and .[4] != "ok") | {path: .[2], error: ("AndroidManifest.xml " + .[4] + ": " + .[5])}]
   + [$catalogs[] | select(.status == "malformed") | {path: .path, error: ("version catalog has \(.bad_lines_total) line(s) that are not catalog TOML, first at line \(.bad_lines[0].line): \(.bad_lines[0].reason)")}]
  ) as $errors
| ([$modules[] | select(.dependencies_total > $max_deps) | {field: ($b + ".modules[" + .project + "].dependencies"), shown: $max_deps, total: .dependencies_total, reason: "limit"}]
   + [$modules[] | .manifests[] | select((.permissions_total // 0) > (.permissions // [] | length)) | {field: ($b + ".manifests[" + .path + "].permissions"), shown: (.permissions | length), total: .permissions_total, reason: "limit"}]
   + [$G | group_by(.[2])[] | ([.[] | select(.[3] == "markers_total") | .[4] | tonumber] | first // 0) as $n | select($n > $max_markers)
      | {field: ($b + ".files[" + .[0][2] + "].markers"), shown: $max_markers, total: $n, reason: "limit"}]
   + [$catalogs[] | . as $c | ("versions", "libraries", "plugins", "bundles") as $k | select($c.counts[$k] > $max_catalog)
      | {field: ($b + ".catalogs[" + $c.path + "]." + $k), shown: $max_catalog, total: $c.counts[$k], reason: "limit"}]
  ) as $cut
| {build: {
    dir: $dir,
    settings: $settings,
    modules_declared: (($includes | map(.project) | unique | length) + 1),
    wrapper: (if ($gradle | length) > 0 then $gradle[0] + {gradlew: any($P[]; (.[2] | endswith("gradlew")) and .[3] == "file")} else null end),
    declared_toolchain: {gradle: $gradle, android_gradle_plugin: $agp, kotlin: $kotlin},
    catalogs: $catalogs,
    modules: $modules,
    test_tools: $tools,
    paths: {present: [$P[] | select(.[3] != "absent") | {path: .[2], type: .[3], role: .[1], evidence: {path: .[2]}}],
            absent: [$P[] | select(.[3] == "absent") | .[2]]},
    unlisted_build_files: [$r[] | select(.[0] == "L") | {path: .[2]}],
    unread_files: {total: $unread_total, paths: [$r[] | select(.[0] == "U") | .[2]]},
    unknown: (
      [($settings.markers // [])[] | select(.marker | test("dynamic_include|loop|conditional|script_plugin"))
         | {field: "settings.includes", reason: ("settings script has " + .marker + "; the project list may differ from the include text"), evidence: .evidence}]
      + [$F[] | select(.[4] == "ambiguous") | {field: .[3], reason: "both Groovy and Kotlin DSL scripts exist in one directory; neither is read", evidence: {path: .[2]}}]
      + [$F[] | select(.[4] == "symlink") | {field: .[3], reason: "symlink, not followed", evidence: {path: .[2]}}]
      + [$F[] | select(.[4] == "symlink_path") | {field: .[3], reason: "a directory on the path is a symlink inside ROOT, not followed", evidence: {path: .[2]}}]
      + [$P[] | select(.[3] == "symlink" or .[3] == "symlink_path") | {field: "paths", reason: "the path or a directory on it is a symlink, not checked", evidence: {path: .[2]}}]
      + [$modules[] | select(.dir_status != "dir") | {field: ("modules[" + .project + "].dir"),
          reason: ({missing: "the default project directory does not exist", symlink: "project directory is a symlink, not followed",
                    symlink_path: "a directory on the path to the project is a symlink inside ROOT, not followed",
                    outside_root: "the project directory leads outside ROOT through a symlink, not read",
                    invalid_path: "the project path has an empty, . or .. segment, not resolved",
                    override: "projectDir is set in settings; the directory is not resolved"}[.dir_status]),
          evidence: (if .dir then {path: .dir} else null end)}]
      + [$modules[] | select(.android_type == "unknown") | {field: ("modules[" + .project + "].android_type"),
          reason: "no com.android.* plugin id in the text, and plugins may come from script plugins, catalog aliases not resolved, subprojects/allprojects or a missing build script"}]
      + [$modules[] | .dependencies[] | select(.kind == "other" or .notation == null) | {field: "dependencies", reason: ("dependency notation not recognised in configuration " + .configuration), evidence: .evidence}][:$max_samples]
      + [$catnames[] | select(.name == null) | {field: "catalogs", reason: "catalog name not declared in the settings text; aliases are not resolved against it", evidence: {path: .path}}]
      + [$P[] | select(.[1] == "build_logic" and .[3] == "dir") | {field: "convention_plugins", reason: (.[2] + " exists; plugins and settings applied from it are not read"), evidence: {path: .[2]}}]
      + [$P[] | select(.[1] == "properties" and .[3] != "absent") | {field: "gradle_properties", reason: (.[2] + " is not opened; its values (android.* flags, JVM args, SDK path, properties used by scripts) are unknown"), evidence: {path: .[2]}}]
      + [$modules[] | select(.manifests == [] and (.android_type == "application" or .android_type == "library")) | {field: ("modules[" + .project + "].manifests"),
          reason: "no src/<set>/AndroidManifest.xml; a manifest may be set in sourceSets or generated"}]
    )},
   truncated: $cut, errors: $errors}

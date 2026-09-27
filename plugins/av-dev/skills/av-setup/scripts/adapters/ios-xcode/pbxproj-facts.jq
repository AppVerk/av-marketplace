# pbxproj-facts.jq - jq module of adapter.sh: project facts from the TSV records of pbxproj.awk.
# Used with: jq -L <adapter dir> -R -s 'include "pbxproj-facts"; pbxproj_facts($p; $maxt; $maxc; $maxk)'.
# $p: pbxproj path relative to ROOT; $maxt, $maxc, $maxk: MAX_TARGETS, MAX_CONFIGS, MAX_PACKAGES.
# Evidence: {path, key: "objects.<ID>.<key>" or a root key, line}. IDs are the object IDs in the file.
# Reports values written in project.pbxproj only; xcconfig files and Xcode defaults are not resolved.

include "ios-facts";

def pbxproj_facts($p; $maxt; $maxc; $maxk):
  def ev($k; $l): {path: $p, key: $k, line: ($l | tonumber)};
  tsv as $rows
  | ($rows | map(select(.[0] == "H")) | map({key: .[1], value: {v: .[2], line: .[3]}}) | from_entries) as $h
  | (reduce ($rows[] | select(.[0] == "O")) as $r ({}; .[$r[1]] = {isa: $r[2], line: $r[3], a: {}, l: {}, d: {}})) as $o0
  | (reduce ($rows[] | select(.[0] == "A" or .[0] == "L" or .[0] == "D")) as $r ($o0;
      if $r[0] == "A" then .[$r[1]].a[$r[2]] = {v: $r[3], line: $r[4]}
      elif $r[0] == "L" then .[$r[1]].l[$r[2]] += [{v: $r[3], line: $r[4]}]
      else .[$r[1]].d[$r[2]] = {v: $r[3], line: $r[4]} end)) as $o
  | ($h.rootObject.v // "") as $rid
  | ($o[$rid] // null) as $root
  | def fact($id; $k): ($o[$id].a[$k] // null) | if . == null then null else {value: .v, evidence: ev("objects." + $id + "." + $k; .line)} end;
    def cfglist($id):
      ($o[$id] // null) as $cl
      | if $cl == null or $cl.isa != "XCConfigurationList" then null else
          {default: ($cl.a.defaultConfigurationName.v // null),
           missing: [($cl.l.buildConfigurations // [])[] | .v | select($o[.] == null)],
           configs: [($cl.l.buildConfigurations // [])[] | .v as $cid | ($o[$cid] // null) | select(. != null)
                     | {id: $cid, name: (.a.name.v // null), base_xcconfig: (.a | keys | any(startswith("baseConfigurationReference"))), d: .d}]}
        end;
    def settings($cfgs):
      [$cfgs[] as $c | $c.d | to_entries[] | select(.key | startswith("buildSettings."))
       | {key: (.key | ltrimstr("buildSettings.")), value: .value.v, line: .value.line, config: $c.name, id: $c.id}]
      | group_by(.key)
      | map({key: .[0].key, value: (group_by(.value) | map({value: .[0].value, configurations: (map(.config) | sort),
               evidence: ev("objects." + .[0].id + ".buildSettings." + .[0].key; .[0].line)}))})
      | from_entries;
    def cfgfacts($id):
      cfglist($id) as $cl
      | if $cl == null then {build_configurations: null, settings: {}, base_xcconfig_configs: null}
        else {build_configurations: {default: $cl.default, names_total: ($cl.configs | length), names: ([$cl.configs[].name] | .[:$maxc]),
                                     evidence: ev("objects." + $id + ".buildConfigurations"; $o[$id].line)},
              settings: settings($cl.configs), base_xcconfig_configs: ([$cl.configs[] | select(.base_xcconfig)] | length)} end;
    def pkgref($id):
      ($o[$id] // null) as $x
      | if $x == null then {kind: "missing", id: $id, evidence: {path: $p, key: ("objects." + $id)}}
        elif $x.isa == "XCRemoteSwiftPackageReference" then
          ($x.a.repositoryURL.v // null) as $u
          | {kind: "remote", url: ($u | clean_url), url_redacted: ($u | redacted),
             requirement: ($x.d | to_entries | map(select(.key | startswith("requirement."))) | map({key: (.key | ltrimstr("requirement.")), value: .value.v}) | from_entries),
             evidence: ev("objects." + $id + ".repositoryURL"; ($x.a.repositoryURL.line // $x.line))}
        elif $x.isa == "XCLocalSwiftPackageReference" then
          {kind: "local", path: ($x.a.relativePath.v // $x.a.path.v // null), evidence: ev("objects." + $id + ".relativePath"; ($x.a.relativePath.line // $x.line))}
        else {kind: ("unexpected isa " + $x.isa), id: $id, evidence: ev("objects." + $id; $x.line)} end;
    if $root == null or $root.isa != "PBXProject" then {error: ("rootObject " + $rid + " is not a PBXProject object")}
    else
      ([($root.l.targets // [])[] | .v]) as $tids
      | ([$tids[] | select($o[.] == null)]) as $dangling
      | ([$tids[] | select($o[.] != null) | . as $tid | $o[$tid] as $t
          | {name: ($t.a.name.v // null), isa: $t.isa, product_type: ($t.a.productType.v // null),
             evidence: ev("objects." + $tid + (if $t.a.productType then ".productType" else "" end); ($t.a.productType.line // $t.line))}
            + cfgfacts($t.a.buildConfigurationList.v // "")
            + {package_products: [($t.l.packageProductDependencies // [])[] | .v as $did | ($o[$did] // null) | select(. != null)
                 | {product: (.a.productName.v // null),
                    package: (($o[.a.package.v // ""] // null) | if . == null then null else (.a.repositoryURL.v // .a.relativePath.v // null | clean_url) end),
                    evidence: ev("objects." + $did + ".productName"; (.a.productName.line // .line))}]}
          | (.name // "?") as $n | cap("package_products"; $maxk) | .cuts |= map(.field = ("targets[" + $n + "]." + .field))]) as $targets
      | ([($root.l.packageReferences // [])[] | pkgref(.v)] | sort_by([.kind, (.url // .path // "")])) as $pkgs
      | ([$tids[] | $o[.] // empty] + [$root]) as $owners
      | ([$owners[] | .a.buildConfigurationList.v // empty | select($o[.] == null) | {kind: "configuration list", id: .}]
         + [$owners[] | .a.buildConfigurationList.v // empty | cfglist(.) // empty | .missing[] | {kind: "build configuration", id: .}]
         + [$owners[] | (.l.packageProductDependencies // [])[] | .v | select($o[.] == null) | {kind: "package product dependency", id: .}]
         | unique) as $dangling_refs
      | {values: [($root.l.knownRegions // [])[] | .v], evidence: ev("objects." + $rid + ".knownRegions"; $root.line)} as $regions0
      | ($regions0 | .cuts = [] | cap("values"; $maxk) | .cuts |= map(.field = "known_regions")) as $regions
      | {status: "ok",
         archive_version: ($h.archiveVersion.v // null),
         object_version: (if $h.objectVersion then {value: $h.objectVersion.v, evidence: ev("objectVersion"; $h.objectVersion.line)} else null end),
         compatibility_version: fact($rid; "compatibilityVersion"),
         preferred_project_object_version: fact($rid; "preferredProjectObjectVersion"),
         last_upgrade_check: ($root.d["attributes.LastUpgradeCheck"] | if . == null then null else {value: .v, evidence: ev("objects." + $rid + ".attributes.LastUpgradeCheck"; .line)} end),
         development_region: fact($rid; "developmentRegion"),
         known_regions: ($regions | del(.cuts)),
         project_level: cfgfacts($root.a.buildConfigurationList.v // ""),
         targets_total: ($targets | length),
         targets: ($targets[:$maxt] | map(del(.cuts))),
         target_configs_cut: [$targets[:$maxt][] | select(.build_configurations != null and .build_configurations.names_total > $maxc) | {name, total: .build_configurations.names_total}],
         dangling_targets: $dangling,
         dangling_refs: $dangling_refs,
         cuts: ([$targets[:$maxt][] | .cuts[]] + $regions.cuts),
         swift_packages_total: ($pkgs | length),
         swift_packages: $pkgs[:$maxk],
         object_counts: ([$o[] | .isa] | group_by(.) | map({key: .[0], value: length}) | from_entries)}
    end;

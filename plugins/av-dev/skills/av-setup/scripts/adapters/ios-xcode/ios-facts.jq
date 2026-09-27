# ios-facts.jq - jq module of adapter.sh: facts from the TSV records of xml.awk, podfile.awk and podlock.awk,
# and from Package.resolved and *.xctestplan JSON. Used with: jq -L <adapter dir> 'include "ios-facts"; ...'.
# Every fact has evidence {path, line} or {path, key}. Nothing here reads files.

# MARK: common

def tsv: split("\n") | map(select(length > 0) | split("\t"));
def lev($p; $l): {path: $p, line: ($l | tonumber)};
def nul: if . == "" then null else . end;
# clean_url - URL without user info (everything up to the last "@" before the first "/") and without query or fragment
def clean_url: if type != "string" then . else sub("^(?<s>[A-Za-z][A-Za-z0-9+.-]*://)[^/]*@"; "\(.s)") | sub("[?#].*$"; "") end;
def redacted: type == "string" and test("^[A-Za-z][A-Za-z0-9+.-]*://[^/]*@|[?#]");
# norm_url - URL key for joining declared packages with resolved pins
def norm_url: if type != "string" then null else clean_url | ascii_downcase | sub("^git@(?<h>[^:/]+):"; "\(.h)/")
  | sub("^[a-z][a-z0-9+.-]*://"; "") | sub("/+$"; "") | sub("\\.git$"; "") end;
# join_path BASE REL - relative path join with ".." resolved; "." for the root; null when REL is absolute
# or the result leaves the root
def join_path($base; $rel):
  if ($rel | startswith("/")) then null else
    reduce ([($base | split("/")[]), ($rel | split("/")[])][] | select(. != "" and . != ".")) as $s ([];
      if . == null then null elif $s == ".." then (if length == 0 then null else .[:-1] end) else . + [$s] end)
    | if . == null then null elif length == 0 then "." else join("/") end
  end;
# root_pod NAME - pod name without the subspec
def root_pod: split("/")[0];
# cap(FIELD; MAX) - cuts the list .FIELD to MAX items and records {field, shown, total} in .cuts (adapter.sh turns
# .cuts into truncated entries and removes it)
def cap($f; $max): (.[$f] // [] | length) as $n
  | if $n > $max then .[$f] |= .[:$max] | .cuts += [{field: $f, shown: $max, total: $n}] else .cuts += [] end;

# MARK: xml elements

# elements - [{seq, path, line, attrs}] in document order from xml.awk records
def elements:
  tsv as $r
  | ($r | map(select(.[0] == "A")) | reduce .[] as $a ({}; .[$a[1]][$a[2]] = $a[3])) as $a
  | [$r[] | select(.[0] == "T") | {seq: (.[1] | tonumber), path: .[2], line: (.[3] | tonumber), attrs: ($a[.[1]] // {})}]
  | sort_by(.seq);

# workspace_facts($p; $base) - FileRef locations of contents.xcworkspacedata; $base = directory of the .xcworkspace
def workspace_facts($p; $base):
  elements as $els
  | if ($els | length) == 0 or $els[0].path != "Workspace" then {error: "root element is not <Workspace>"} else
      {version: ($els[0].attrs.version // null),
       file_refs: (reduce $els[] as $e ({stack: [], refs: []};
           ($e.path | split("/")) as $segs
           | .stack = (.stack[:($segs | length) - 1] + [{name: $segs[-1], loc: ($e.attrs.location // "")}])
           | if $segs[-1] == "FileRef" then
               .refs += [{location: ($e.attrs.location // null), groups: [.stack[:-1][] | select(.name == "Group") | .loc], line: $e.line}]
             else . end)
         | .refs
         | map((.location // "") as $loc
             | ($loc | capture("^(?<k>[a-z]+):(?<v>.*)$") // {k: "unknown", v: $loc}) as $c
             | (reduce .groups[] as $gl ($base;
                  if . == null then null else ($gl | capture("^(?<k>[a-z]+):(?<v>.*)$") // {k: "", v: ""}) as $gc
                    | if $gc.k == "group" then join_path(.; $gc.v) elif $gc.k == "container" then join_path($base; $gc.v)
                      elif $gc.k == "absolute" then null else . end end)) as $gb
             | {location: .location, kind: $c.k,
                path: (if $c.k == "group" then (if $gb == null then null else join_path($gb; $c.v) end)
                       elif $c.k == "container" then join_path($base; $c.v)
                       elif $c.k == "self" then $base else null end),
                evidence: {path: $p, line: .line, key: "FileRef.location"}}))}
    end;

# scheme_facts($p; $base; $maxk) - build configurations per action, buildable targets, test plan references
def scheme_facts($p; $base; $maxk):
  elements as $els
  | if ($els | length) == 0 or $els[0].path != "Scheme" then {error: "root element is not <Scheme>"} else
      {last_upgrade_version: ($els[0].attrs.LastUpgradeVersion // null),
       actions: [$els[] | select(.path | test("^Scheme/[A-Za-z]+Action$"))
                 | {action: (.path | split("/")[1]), build_configuration: (.attrs.buildConfiguration // null), evidence: lev($p; .line)}],
       buildables: ([$els[] | select(.path | endswith("/BuildableReference")) | (.path | split("/")) as $segs
                     | select([$segs[] | select(. == "MacroExpansion" or . == "EnvironmentBuildable" or . == "PreActions" or . == "PostActions")] | length == 0)
                     | {role: (if $segs[1] == "BuildAction" then "build" elif $segs[1] == "TestAction" then "test"
                               elif ($segs[1] | test("^(Launch|Profile)Action$")) then "run" else $segs[1] end),
                        target: (.attrs.BlueprintName // null), container: (.attrs.ReferencedContainer // null), evidence: lev($p; .line)}]
                    | unique_by([.role, .target, .container]) | sort_by([.role, .target])),
       test_plans: [$els[] | select(.path == "Scheme/TestAction/TestPlans/TestPlanReference")
                    | (.attrs.reference // "") as $ref | ($ref | capture("^(?<k>[a-z]+):(?<v>.*)$") // {k: "unknown", v: $ref}) as $c
                    | {reference: $ref, default: (.attrs.default == "YES"),
                       path: (if $c.k == "container" or $c.k == "group" then join_path($base; $c.v) else null end),
                       evidence: lev($p; .line)}]}
      | cap("actions"; $maxk) | cap("buildables"; $maxk) | cap("test_plans"; $maxk)
    end;

# MARK: CocoaPods

def podfile_facts($p; $maxk):
  tsv as $r
  | ([$r[] | select(.[0] == "C") | {key: .[1], value: (.[3] | split("|"))}] | from_entries) as $confs
  | ([$r[] | select(.[0] == "D")
      | {name: .[2], constraints: (.[3] | if . == "" then [] else split("|") end),
         options: (.[4] | if . == "" then [] else split("|") end), target: (.[5] | nul),
         configurations: ($confs[.[1]] // null), evidence: lev($p; .[1])}]) as $pods
  | {platform: ([$r[] | select(.[0] == "P") | {name: .[2], version: (.[3] | nul), evidence: lev($p; .[1])}] | .[0] // null),
     flags: [$r[] | select(.[0] == "F") | {flag: .[2], evidence: lev($p; .[1])}],
     sources: [$r[] | select(.[0] == "S") | {url: (.[2] | clean_url), url_redacted: (.[2] | redacted), evidence: lev($p; .[1])}],
     projects: [$r[] | select(.[0] == "J") | {path: .[2], evidence: lev($p; .[1])}],
     hooks: [$r[] | select(.[0] == "K") | {hook: .[2], evidence: lev($p; .[1])}],
     targets: [$r[] | select(.[0] == "T") | {kind: .[2], name: (.[3] | nul), parent: (.[4] | nul), evidence: lev($p; .[1])}],
     pods_total: ($pods | length),
     pods: $pods[:$maxk],
     all_pod_names: [$pods[].name],
     not_followed: [$r[] | select(.[0] == "X") | {reason: .[2], evidence: lev($p; .[1])}],
     open_blocks_at_end: ([$r[] | select(.[0] == "B") | .[2] | tonumber] | .[0] // null)}
  | cap("sources"; $maxk) | cap("projects"; $maxk) | cap("hooks"; $maxk) | cap("targets"; $maxk) | cap("not_followed"; $maxk);

def podlock_facts($p; $maxk):
  tsv as $r
  | ([$r[] | select(.[0] == "P") | {name: .[2], version: .[3], line: .[1]}]) as $entries
  | ($entries | group_by(.name | root_pod) | map({name: (.[0].name | root_pod), versions: (map(.version) | unique), evidence: lev($p; .[0].line)})
     | sort_by(.name | ascii_downcase)) as $roots
  | {cocoapods_version: ([$r[] | select(.[0] == "V") | {value: .[2], evidence: lev($p; .[1])}] | .[0] // null),
     podfile_checksum_present: ([$r[] | select(.[0] == "K")] | length > 0),
     entries_total: ($entries | length),
     pods_total: ($roots | length),
     pods: ($roots[:$maxk] | map({name, version: (if (.versions | length) == 1 then .versions[0] else .versions end), evidence})),
     entry_versions: ($entries | map({key: .name, value: {version, line}}) | from_entries),
     dependencies: [$r[] | select(.[0] == "D") | {name: .[2], requirement: (.[3] | nul), evidence: lev($p; .[1])}],
     all_dependency_names: [$r[] | select(.[0] == "D") | .[2]],
     spec_repos: [$r[] | select(.[0] == "R") | {repo: .[2], pods: (.[3] | tonumber), evidence: lev($p; .[1])}],
     external_sources: [$r[] | select(.[0] == "S") | {name: .[2], kind: .[3], evidence: lev($p; .[1])}],
     unread_sections: [$r[] | select(.[0] == "U") | {section: .[2], evidence: lev($p; .[1])}]}
  | cap("dependencies"; $maxk) | cap("spec_repos"; $maxk) | cap("external_sources"; $maxk) | cap("unread_sections"; $maxk);

# pods_compare(podfile; lock; $lp) - declared pods with the locked version; name lists that differ
def pods_compare($pf; $lk; $lp):
  ($lk.entry_versions // {}) as $ev
  | ($lk.all_dependency_names // [] | unique) as $deps
  | ($pf.all_pod_names | unique) as $decl
  | {pods: [$pf.pods[] | . + {locked_version: (($ev[.name] // $ev[.name | root_pod] // null)
                                | if . == null then null else {value: .version, evidence: lev($lp; .line)} end)}],
     declared_not_in_lock_dependencies: ($decl - $deps),
     lock_dependencies_not_declared: ($deps - $decl)};

# MARK: Swift Package Manager

def resolved_valid: type == "object" and ((.version == 1 and (.object | type) == "object" and (.object.pins | type) == "array")
  or ((.version == 2 or .version == 3) and (.pins | type) == "array"));

def resolved_facts($p; $maxk):
  ([(if .version == 1 then .object.pins else .pins end)[] | select(type != "object")] | length) as $skipped
  | (if .version == 1 then [.object.pins[] | objects | {identity: (.package // null), kind: null, location: (.repositoryURL // null), state: (.state // {})}]
   else [.pins[] | objects | {identity: (.identity // null), kind: (.kind // null), location: (.location // null), state: (.state // {})}] end)
  | map({identity: (.identity | if type == "string" then . else tostring end), kind,
         location: (.location | clean_url), location_redacted: (.location | redacted),
         version: (.state | objects | .version // null), branch: (.state | objects | .branch // null),
         revision: (.state | objects | .revision // null),
         evidence: {path: $p, key: ("pins." + (.identity | tostring))}})
  | sort_by(.identity | ascii_downcase) as $pins
  | {pins_total: ($pins | length), pins_skipped: $skipped, pins: $pins[:$maxk]};

# MARK: test plans

def testplan_facts($p; $maxk):
  {version: (.version // null),
   configurations: [(.configurations // []) | arrays | .[] | objects | .name // null],
   test_targets: [(.testTargets // []) | arrays | .[] | objects
                  | ((.target | objects) // {}) as $t
                  | {name: ($t.name // null), container: ($t.containerPath // null),
                     enabled: (if has("enabled") then .enabled else true end),
                     parallelizable: (if has("parallelizable") then .parallelizable else null end),
                     selected_tests: ((.selectedTests // []) | if type == "array" then length else null end),
                     skipped_tests: ((.skippedTests // []) | if type == "array" then length else null end)}]
                 | sort_by(.name // ""),
   default_options_keys: ((.defaultOptions // {}) | if type == "object" then keys else [] end),
   environment_variable_entries: ([.. | objects | .environmentVariableEntries? | arrays | length] | add // 0),
   command_line_argument_entries: ([.. | objects | .commandLineArgumentEntries? | arrays | length] | add // 0),
   evidence: {path: $p}}
  | cap("configurations"; $maxk) | cap("test_targets"; $maxk) | cap("default_options_keys"; $maxk);

# workspace-facts.jq - facts of one angular.json (used by adapter.sh).
# Args: $p (path relative to ROOT, used in evidence), $maxp (projects), $maxt (targets per project),
#       $maxc (configuration names per target).
# Reports the workspace version, project names, types, roots, target names, builders, configuration
# names and string values of a fixed list of file options. Other option values (define,
# fileReplacements, budgets, environment values, ...) are never printed.
# Output keys starting with "_" (_cuts, _errors, _paths) are consumed by adapter.sh and removed.

def ev($k): {path: $p, key: $k};
def ev($k; $v): {path: $p, key: $k, value: $v};
def sstr: if type == "string" then . else null end;
def safe: if test("://[^/?#\\s]*@") then "(url with credentials, not printed)" else . end;
def file_keys: ["tsConfig", "karmaConfig", "jestConfig", "configFile", "main", "browser", "server", "index", "proxyConfig", "ngswConfigPath"];
def builder_tool:
  {"@angular-devkit/build-angular:karma": "karma", "@angular/build:karma": "karma",
   "@angular-devkit/build-angular:jest": "jest", "@angular-builders/jest:run": "jest", "@nx/jest:jest": "jest",
   "@angular-devkit/build-angular:web-test-runner": "web-test-runner",
   "@angular-devkit/build-angular:protractor": "protractor",
   "@cypress/schematic:cypress": "cypress", "@nx/cypress:cypress": "cypress",
   "playwright-ng-schematics:playwright": "playwright", "@nx/playwright:playwright": "playwright",
   "@nx/vite:test": "vitest", "@analogjs/vitest-angular:test": "vitest",
   "@angular/build:unit-test": "angular-unit-test"}[.];

def target($n; $tk):
  .key as $t | ((.value | objects) // {}) as $v | ("projects." + $n + "." + $tk + "." + $t) as $k
  | (($v.configurations | objects | keys) // []) as $cf
  | (($v.options | objects) // {}) as $o
  | {name: $t,
     builder: ($v.builder | sstr),
     evidence: (if ($v.builder | type) == "string" then ev($k + ".builder"; $v.builder) else ev($k) end),
     configurations: $cf[:$maxc],
     configurations_total: ($cf | length),
     default_configuration: ($v.defaultConfiguration | sstr),
     option_files: [file_keys[] as $fk | ($o[$fk] | strings | safe) as $f | {key: $fk, path: $f, evidence: ev($k + ".options." + $fk)}],
     _k: $k, _runner: ($o.runner | sstr)};

def project($n):
  (if (.architect | type) == "object" then "architect" elif (.targets | type) == "object" then "targets" else null end) as $tk
  | (if $tk then (.[$tk] | to_entries | sort_by(.key)) else [] end) as $ts
  | {name: $n,
     project_type: (.projectType | sstr),
     root: (.root | sstr | if . == null then null else safe end),
     source_root: (.sourceRoot | sstr | if . == null then null else safe end),
     prefix: (.prefix | sstr),
     evidence: ev("projects." + $n),
     targets_key: $tk,
     targets_total: ($ts | length),
     _all_targets: [$ts[] | target($n; $tk)]}
  | .targets = .["_all_targets"][:$maxt];

(.projects) as $pr
| (($pr | type) == "object") as $prok
| (if $prok then ($pr | to_entries | sort_by(.key)) else [] end) as $entries
| [$entries[] | .key as $n | if (.value | type) == "object" then (.value | project($n)) else {name: $n, error: true} end] as $all
| ($all | map(select(.error != true))) as $good
| ($all[:$maxp] | map(select(.error != true))) as $shown
| {
    version: (if (.version | type) == "number" or (.version | type) == "string" then {value: .version, evidence: ev("version")} else null end),
    new_project_root: (.newProjectRoot | sstr),
    default_project: (.defaultProject | sstr),
    cli: {package_manager: ((.cli | objects | .packageManager) // null | sstr),
          schematic_collections: ((.cli | objects | .schematicCollections) // null | if type == "array" then map(strings) else null end)},
    projects_total: ($entries | length),
    projects: [$all[:$maxp][] | if .error then {name, error: "project entry is not an object", evidence: ev("projects." + .name)}
               else del(._all_targets) | .targets |= map(del(._k, ._runner)) end],
    builder_tools: [$good[] | ._all_targets[]
      | ((.builder // "") | builder_tool) as $bt
      | select($bt != null)
      | {tool: $bt, evidence: .evidence},
        (select($bt == "angular-unit-test" and (._runner == "vitest" or ._runner == "karma"))
         | {tool: ._runner, evidence: ev(._k + ".options.runner"; ._runner)})],
    _cuts: ([{field: "projects", shown: ([$entries | length, $maxp] | min), total: ($entries | length)}]
             + [$shown[] | .name as $n
                | {field: ("projects[" + $n + "].targets"), shown: (.targets | length), total: .targets_total},
                  (.targets[] | {field: ("projects[" + $n + "].targets[" + .name + "].configurations"), shown: (.configurations | length), total: .configurations_total})]
             | map(select(.total > .shown))),
    _errors: ((if $pr != null and ($prok | not) then ["projects is not an object"] else [] end)
              + [$all[] | select(.error) | "projects." + .name + " is not an object"]),
    _paths: ([$shown[] | .root, .source_root, (.targets[].option_files[].path)] | map(strings) | unique)
  }

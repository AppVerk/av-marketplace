# package-facts.jq - manifest facts of one app from one package.json (used by adapter.sh).
# Args: $p (manifest path relative to ROOT, used in evidence), $max (MAX_PACKAGES),
#       $keys (JSON array of key package names reported in key_packages).
# Keys in evidence use "section.package" (e.g. "dependencies.@angular/core"); package names contain "/".
# Reports declared constraints only; lockfiles and node_modules are read by adapter.sh, not here.
# A constraint or value that holds a URL with credentials is replaced by a fixed marker and never printed.
# Never prints scripts, config, publishConfig or any other key outside the ones listed below.

def ev($k): {path: $p, key: $k};
def ev($k; $v): {path: $p, key: $k, value: $v};
def str: if type == "string" then . else tojson end;
def safe: if test("://[^/?#\\s]*@") then "(url with credentials, not printed)" else . end;
def sections: ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];
def section_rank: .section as $s | sections | index($s);
def entries($s): (.[$s] // {}) as $o
  | if ($o | type) == "object" then [$o | to_entries[] | {name: .key, constraint: (.value | str | safe), section: $s}] else [] end;
def group:
  if (.name | test("^(@angular/(cli|build|compiler-cli)|@angular-devkit/.+|@schematics/angular|@angular-builders/.+|@angular-eslint/.+|ng-packagr|@nx/angular|@nrwl/angular)$")) then "angular_tooling"
  elif (.name | startswith("@angular/")) then "angular"
  elif .name == "angular" or (.name | test("^angular-(animate|aria|cookies|messages|mocks|resource|route|sanitize|touch)$")) then "angularjs"
  elif (.name | test("^(rxjs|zone\\.js|tslib|typescript)$")) then "runtime"
  elif (.name | test("^(karma|karma-.+|jasmine|jasmine-core|@types/jasmine|jest|jest-preset-angular|@types/jest|vitest|@vitest/.+|@analogjs/vitest-angular|@playwright/test|playwright|cypress|protractor|@testing-library/.+|ng-mocks|jsdom|happy-dom|@web/test-runner)$")) then "test"
  elif (.name | test("^(eslint|@eslint/.+|eslint-plugin-.+|eslint-config-.+|eslint-import-resolver-.+|@typescript-eslint/.+|typescript-eslint|@stylistic/.+|prettier|prettier-plugin-.+|stylelint|stylelint-.+|husky|lint-staged|@commitlint/.+)$")) then "quality"
  elif (.name | test("^(@ngrx|@ngxs|@nx|@ngx-[^/]+|@ng-[^/]+|@angular-[^/]+)/|^(ngx|ng)-")) then "angular_ecosystem_name"
  else null end;
def tool:
  {"karma": "karma", "jasmine-core": "jasmine", "jasmine": "jasmine", "jest": "jest", "jest-preset-angular": "jest",
   "vitest": "vitest", "@analogjs/vitest-angular": "vitest", "@playwright/test": "playwright", "cypress": "cypress",
   "protractor": "protractor", "@testing-library/angular": "testing-library", "ng-mocks": "ng-mocks",
   "@web/test-runner": "web-test-runner"}[.name];
# major: leading major of a constraint that names one version line (^21.2.1, ~21.2, 21.x, 21, v21, =21.0.0-rc.1);
# null for ranges, unions, tags, URLs and "*"
def major:
  if test("^\\s*[\\^~=v]*\\s*[0-9]+(\\.([0-9]+|[xX*]))*([-+][0-9A-Za-z.-]+)?\\s*$")
  then (capture("(?<m>[0-9]+)").m | tonumber) else null end;

. as $m
| [sections[] as $s | $m | entries($s)[]] as $all
| ($all | map(. + {group: group})) as $g
| ($g | map(select(.group != null)) | sort_by([section_rank, .name])) as $rel
| ($all | map(select(.name == "@angular/core")) | sort_by(section_rank)) as $core
| ($g | map(select(.group == "angular" or .group == "angular_tooling")) | sort_by([section_rank, .name])) as $ng
| ($g | map(select(.group == "angularjs")) | sort_by([section_rank, .name])) as $ajs
| ((.workspaces | if type == "array" then . elif type == "object" then (.packages // null) else null end)
   | if type == "array" then map(strings) else null end) as $ws
| {
    package: {status: "ok",
              name: (.name // null | if . == null then null else str | safe end),
              private: (if (.private | type) == "boolean" then .private else null end),
              module_type: (.type | strings // null),
              evidence: [(if .name then ev("name") else empty end), (if (.private | type) == "boolean" then ev("private") else empty end),
                         (if (.type | type) == "string" then ev("type") else empty end)]},
    angular: {
      present: (if ($core | length) > 0 then "framework"
                elif ($ng | length) > 0 then "packages_only"
                elif ($ajs | length) > 0 then "angularjs_only"
                else "none" end),
      rule: "framework: @angular/core in dependencies, devDependencies, peerDependencies or optionalDependencies; packages_only: other @angular/* or Angular CLI tooling without @angular/core; angularjs_only: AngularJS 1.x package \"angular\" or angular-* modules only",
      evidence: (if ($core | length) > 0 then [$core[] | ev(.section + "." + .name; .constraint)]
                 elif ($ng | length) > 0 then [$ng[:3][] | ev(.section + "." + .name; .constraint)]
                 else [$ajs[:3][] | ev(.section + "." + .name; .constraint)] end),
      angular_package_count: ($ng | length),
      angularjs_package_count: ($ajs | length),
      declared_version: (if ($core | length) > 0
                         then {constraint: $core[0].constraint, major: ($core[0].constraint | major), section: $core[0].section,
                               evidence: ev($core[0].section + ".@angular/core")}
                         else null end)
    },
    key_packages: [$keys[] as $k | ($all | map(select(.name == $k)) | sort_by(section_rank) | .[0]) // empty
                   | {name, constraint, section, evidence: ev(.section + "." + .name)}],
    engines_node: (((.engines | objects | .node | strings) // null) as $n
                   | if $n then {constraint: ($n | safe), evidence: ev("engines.node")} else null end),
    package_manager: (((.packageManager | strings) // null) as $pm
                      | if $pm then {value: ($pm | safe), evidence: ev("packageManager")} else null end),
    workspaces: (if $ws then {total: ($ws | length), patterns: ($ws[:$max] | map(safe)), evidence: ev("workspaces")} else null end),
    packages_total: ($rel | length),
    packages_ignored: (($all | length) - ($rel | length)),
    packages: ($rel[:$max] | map({name, constraint, section, group, evidence: ev(.section + "." + .name)})),
    tool_packages: [$all[] | tool as $t | select($t != null) | {tool: $t, evidence: ev(.section + "." + .name; .constraint)}]
  }

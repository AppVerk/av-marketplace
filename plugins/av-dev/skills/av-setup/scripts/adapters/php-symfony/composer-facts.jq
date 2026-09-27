# composer-facts.jq - manifest facts of one app from one composer.json (used by adapter.sh).
# Args: $p (manifest path relative to ROOT, used in evidence), $max (MAX_PACKAGES).
# Keys in evidence use "section.package" (e.g. "require.symfony/console"); package names contain "/".
# Reports declared constraints only; composer.lock and vendor/ are never read.

def ev($k): {path: $p, key: $k};
def ev($k; $v): {path: $p, key: $k, value: $v};
def str: if type == "string" then . else tojson end;
def entries($s): (.[$s] // {}) as $o
  | if ($o | type) == "object" then [$o | to_entries[] | {name: .key, constraint: (.value | str), section: $s}] else [] end;
def group:
  if .name == "php" then "php"
  elif (.name | test("^symfony/(framework-bundle|symfony)$")) then "symfony_framework"
  elif (.name | test("^symfony/")) then "symfony"
  elif (.name | test("^doctrine/(orm|dbal|doctrine-bundle|doctrine-migrations-bundle|migrations|mongodb-odm|mongodb-odm-bundle)$")) then "doctrine"
  elif (.name | test("^api-platform/")) then "api_platform"
  elif (.name | test("^twig/")) then "templating"
  elif (.name | test("^(phpunit/phpunit|brianium/paratest|pestphp/pest.*|behat/.+|friends-of-behat/.+|codeception/.+|phpspec/phpspec|infection/infection|mockery/mockery|dama/doctrine-test-bundle|zenstruck/foundry|liip/test-fixtures-bundle|hautelook/alice-bundle|nelmio/alice|theofidry/alice-data-fixtures|doctrine/doctrine-fixtures-bundle)$")) then "test"
  elif (.name | test("^(phpstan/.+|vimeo/psalm|friendsofphp/php-cs-fixer|rector/rector|squizlabs/php_codesniffer|qossmic/deptrac.*|deptrac/deptrac.*|symplify/easy-coding-standard)$")) then "quality"
  elif (.name | test("-bundle$")) then "bundle"
  else null end;
def tool:
  {"phpunit/phpunit": "phpunit", "symfony/phpunit-bridge": "phpunit", "pestphp/pest": "pest", "behat/behat": "behat",
   "codeception/codeception": "codeception", "phpspec/phpspec": "phpspec", "infection/infection": "infection",
   "brianium/paratest": "paratest", "symfony/panther": "panther"}[.name];

(entries("require") + entries("require-dev")) as $all
| ($all | map(. + {group: group}) | map(select(.group != null)) | sort_by([.section, .name])) as $rel
| ($all | map(select(.name | test("^symfony/(framework-bundle|symfony)$")))) as $fw
| ($all | map(select(.name | startswith("symfony/")))) as $sc
| ((.extra | objects | .symfony) // null) as $xs
| ((.config | objects | .platform | objects | .php) // null) as $plat
| ($all | map(select(.name == "php")) | .[0]) as $php
| (($xs | objects | .require) // null) as $xreq
| {
    composer: {status: "ok", name: (.name // null | if . == null then null else str end), type: (.type // null | if . == null then null else str end),
               evidence: [(if .name then ev("name") else empty end), (if .type then ev("type") else empty end)]},
    php: (if $php then {constraint: $php.constraint, evidence: ev($php.section + ".php")} else null end),
    php_platform: (if $plat then {value: ($plat | str), evidence: ev("config.platform.php")} else null end),
    symfony: {
      present: (if ($fw | length) > 0 then "framework" elif ($sc | length) > 0 then "components_only" else "none" end),
      rule: "framework: symfony/framework-bundle or symfony/symfony in require or require-dev; components_only: other symfony/* packages only",
      evidence: ([$fw[] | ev(.section + "." + .name; .constraint)]
                 + [$all[] | select(.name == "symfony/flex") | ev(.section + ".symfony/flex"; .constraint)]
                 + (if $xs != null then [ev("extra.symfony")] else [] end)),
      symfony_package_count: ($sc | length),
      declared_version: (if ($xreq | type) == "string" then {constraint: $xreq, evidence: ev("extra.symfony.require")}
                         elif ($fw | length) > 0 then {constraint: $fw[0].constraint, evidence: ev($fw[0].section + "." + $fw[0].name)}
                         else null end)
    },
    packages_total: ($rel | length),
    packages_ignored: (($all | length) - ($rel | length)),
    packages: ($rel[:$max] | map({name, constraint, section, group, evidence: ev(.section + "." + .name)})),
    tool_packages: [$all[] | tool as $t | select($t != null) | {tool: $t, evidence: ev(.section + "." + .name; .constraint)}],
    autoload_rows: [
      (("autoload", "autoload-dev") as $s | (.[$s] // {}) | objects
       | ("psr-4", "psr-0") as $k | (.[$k] // {}) | objects | to_entries[] | .key as $ns
       | (.value | if type == "array" then .[] else . end) | strings
       | {section: $s, kind: $k, namespace: $ns, path: ., evidence: ev($s + "." + $k + "." + $ns)}),
      (("autoload", "autoload-dev") as $s | (.[$s] // {}) | objects | (.classmap // []) | arrays | .[] | strings
       | {section: $s, kind: "classmap", namespace: null, path: ., evidence: ev($s + ".classmap")})
    ]
  }

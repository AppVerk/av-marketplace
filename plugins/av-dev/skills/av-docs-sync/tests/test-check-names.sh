#!/bin/bash
# Black box tests for check_names.sh.
# Docs are English; lines in Polish check that Polish negation, example words and
# the Polish ignore section header still work.
set -u
CHECK="$(cd "$(dirname "$0")/.." && pwd)/scripts/check_names.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

REPO="$TMP/repo with space"
mkdir -p "$REPO/src/Orders" "$REPO/.ai"
cd "$REPO" || exit 1
git init -q
cat >src/Orders/OrderController.php <<'PHP'
<?php
final class OrderController { public function sendOrder(): void {} }
const MAX_ORDER_ITEMS = 5;
PHP
cat >.ai/orders.md <<'MD'
# Orders
Controller: `OrderController::sendOrder()`, limit `MAX_ORDER_ITEMS`.
Old controller: `ReturnOrderController`.
Method `sendOrderLegacy` handles old orders.
Klasa `LegacyController` zostala usunieta w PROJ-1.
Przyklad: `FooService`, `<NazwaModułu>`.
Table `order_items_archive`.
MD
cat >.ai/code.md <<'MD'
```php
$x = new NotInCodeButInBlock();
```
MD
git add -A && git commit -qm init
mkdir -p src/Infrastructure && printf "<?php\\n" >src/Infrastructure/Container.php
printf '<?php\nfinal class NewUntrackedService {}\n' >src/Orders/NewUntrackedService.php
printf '# New\nService `NewUntrackedService` in `Infrastructure`.\n' >.ai/new.md
out0="$(bash "$CHECK" .ai/new.md --root .)"
has "$out0" "NAME_MISSING 0" && ok || fail "untracked files and directories: $out0"
rm -rf .ai/new.md src/Orders/NewUntrackedService.php src/Infrastructure

out="$(bash "$CHECK" .ai --root .)"; rc=$?
has "$out" "NAME_MISSING .ai/orders.md:3 ReturnOrderController" && ok || fail "no candidate ReturnOrderController"
has "$out" "NAME_MISSING .ai/orders.md:4 sendOrderLegacy" && ok || fail "no method candidate"
has "$out" "NAME_MISSING .ai/orders.md:7 order_items_archive" && ok || fail "no snake_case candidate"
for n in OrderController sendOrder MAX_ORDER_ITEMS LegacyController FooService NotInCodeButInBlock; do
  printf '%s\n' "$out" | grep '^NAME_MISSING' | grep -qw -- "$n" && fail "false candidate: $n" || ok
done
has "$out" "NAME_MISSING 3" && [ "$rc" -eq 1 ] && ok || fail "counters: $(printf '%s' "$out" | tail -1) code $rc"

# --- English negation words turn off the line
cat >.ai/en.md <<'MD'
# En
Class `DroppedController` was removed in PROJ-2.
`NewServiceName` is used instead of `OldServiceName`.
Plain name `StillMissingName`.
MD
out="$(bash "$CHECK" .ai/en.md --root .)"
for n in DroppedController NewServiceName OldServiceName; do
  printf '%s\n' "$out" | grep '^NAME_MISSING' | grep -qw -- "$n" && fail "English negation: $n reported" || ok
done
has "$out" "NAME_MISSING .ai/en.md:4 StillMissingName" && has "$out" "NAME_MISSING 1" && ok || fail "English negation counters: $out"
rm .ai/en.md

# --- R2a/b: strikethrough and placeholders
cat >.ai/noise.md <<'MD'
# Noise
- ~~`GoneInStrike` was here~~ and `RealMissingOne` stayed.
- Template: `openFoo`, `fooViewModel`, `foo_title`, `BillingApiX`, `billingApiX`, `BillingApiXxxManager`.
- Patterns: `billingApi{Feature}`, `Http*RequestHandler`, `account_lock_error*`, `Request<SomeModelType>`.
- Footer `tableFooterViewMissing` is not a placeholder.
- Wywolanie, np. `MyOrderView.renderFromTemplate()`.
- Call, e.g. `MyOtherController.reloadFromTemplate()`.
- Plain class: `MyRealController`.
MD
out="$(bash "$CHECK" .ai/noise.md --root .)"
for n in GoneInStrike openFoo fooViewModel foo_title BillingApiX billingApiX BillingApiXxxManager billingApi RequestHandler account_lock_error SomeModelType MyOrderView MyOtherController; do
  printf '%s\n' "$out" | grep '^NAME_MISSING' | grep -qw -- "$n" && fail "placeholder reported: $n" || ok
done
for n in RealMissingOne tableFooterViewMissing MyRealController renderFromTemplate reloadFromTemplate; do
  has "$out" " $n" && ok || fail "no candidate: $n"
done
has "$out" "NAME_MISSING 5" && ok || fail "noise counters: $(printf '%s' "$out" | tail -1)"

# --- R2c: ignore list in the overlay (exact and prefix), path from the config,
#     section header in English, in Polish and in Polish without diacritics
mkdir -p .ai/ov
printf '{"paths":{"overlays":".ai/ov"}}\n' >.ai/av.config.json
for header in "Known false names" "Znane fałszywe nazwy" "Znane falszywe nazwy"; do
  cat >.ai/ov/av-docs-sync.md <<MD
# Overlay
## Code -> docs map
- \`ReturnOrderController\` is not an ignored name.
## $header
- \`sendOrderLegacy\` - name from the backend
- \`order_items*\`
## Other
- \`LegacyThing\`
MD
  out="$(bash "$CHECK" .ai/orders.md --root .)"
  has "$out" "sendOrderLegacy" && fail "$header: ignored name reported" || ok
  has "$out" "order_items_archive" && fail "$header: prefix does not ignore" || ok
  has "$out" "NAME_MISSING .ai/orders.md:3 ReturnOrderController" && ok || fail "$header: name outside the section ignored: $out"
  has "$out" "NAME_MISSING 1" && ok || fail "$header: counters with overlay: $(printf '%s' "$out" | tail -1)"
done

printf '# plain\nReturnOrderController\n- `sendOrder*`\n' >"$TMP/ignore.txt"
out="$(bash "$CHECK" .ai/orders.md --root . --ignore-file "$TMP/ignore.txt")"
has "$out" "ReturnOrderController" && fail "--ignore-file without a section does not work" || ok
has "$out" "sendOrderLegacy" && fail "--ignore-file prefix does not work" || ok
has "$out" "order_items_archive" && ok || fail "--ignore-file does not replace the overlay: $out"
bash "$CHECK" .ai/orders.md --root . --ignore-file "$TMP/missing.txt" >/dev/null 2>&1; [ $? -eq 2 ] && ok || fail "missing --ignore-file: code 2"
printf '# no section\n- `ReturnOrderController`\n' >.ai/ov/av-docs-sync.md
out="$(bash "$CHECK" .ai/orders.md --root .)"
has "$out" "NAME_MISSING 3" && ok || fail "overlay without a section must not ignore: $(printf '%s' "$out" | tail -1)"
rm -rf .ai/ov .ai/av.config.json

# --- R2d: keys from translation files (UTF-8 and UTF-16) are found
mkdir -p i18n/pl
printf '"points_many_utf8" = "points";\n' >i18n/pl/messages.strings
printf '"points_many_utf16" = "points";\n' | iconv -f UTF-8 -t UTF-16 >i18n/pl/other.strings
printf '# L\nKeys `points_many_utf8`, `points_many_utf16`, `points_none_here`.\n' >.ai/l10n.md
out="$(bash "$CHECK" .ai/l10n.md --root .)"
has "$out" "points_many_utf8" && fail "UTF-8 key reported" || ok
has "$out" "points_many_utf16" && fail "UTF-16 key reported" || ok
has "$out" "NAME_MISSING .ai/l10n.md:2 points_none_here" && ok || fail "no key candidate: $out"
rm -rf i18n .ai/l10n.md .ai/noise.md

# --- R5: non-ASCII letters stay inside a name, in the docs and in the code
cat >"src/Orders/Zamówienia.swift" <<'SWIFT'
final class ZamówienieService {}
let pozycjaZamówienia = 1
let größeWert = 2
let данныеId = 3
let ilość_pozycji = 4
// „CytatKlasa” — see OrderPanel—legacy
SWIFT
cat >.ai/utf8.md <<'MD'
# U
Service `ZamówienieService` with `pozycjaZamówienia`, `größeWert`, `данныеId`, `ilość_pozycji`.
Quoted in the code: `CytatKlasa`, `OrderPanel`. File: `Zamówienia`.
Missing: `zamówienieNumer`, `staraŁódźKlasa`, `ÜberGhostName`.
Prose: `zażółć`, `Wartość domyślna`. Short: `ółA`. Template: `stanŁódźX`.
MD
out="$(bash "$CHECK" .ai/utf8.md --root .)"; rc=$?
for n in ZamówienieService pozycjaZamówienia größeWert данныеId ilość_pozycji CytatKlasa OrderPanel Zamówienia wienieService wienia eWert zamówienie wienieNumer Klasa berGhostName GhostName zażółć Wartość ółA stanŁódźX; do
  printf '%s\n' "$out" | grep '^NAME_MISSING' | grep -q -- " $n\$" && fail "non-ASCII: false candidate $n: $out" || ok
done
for n in zamówienieNumer staraŁódźKlasa ÜberGhostName; do
  printf '%s\n' "$out" | grep -qx -- "NAME_MISSING .ai/utf8.md:4 $n" && ok || fail "non-ASCII: no candidate $n: $out"
done
has "$out" "NAME_MISSING 3 " && [ "$rc" -eq 1 ] && ok || fail "non-ASCII counters: $(printf '%s' "$out" | tail -1) (code $rc)"
printf '# plain\n- `zamówienieNumer`\n- `stara*`\nÜberGhostName\n' >"$TMP/ignore_utf8.txt"
out="$(bash "$CHECK" .ai/utf8.md --root . --ignore-file "$TMP/ignore_utf8.txt")"; rc=$?
has "$out" "NAME_MISSING 0 " && [ "$rc" -eq 0 ] && ok || fail "non-ASCII names in the ignore list: $out (code $rc)"
printf '"klucz_zamówienia" = "x";\n' | iconv -f UTF-8 -t UTF-16 >src/Orders/pl.strings
printf '# L\nKey `klucz_zamówienia`.\n' >.ai/utf8.md
out="$(bash "$CHECK" .ai/utf8.md --root .)"
has "$out" "NAME_MISSING 0 " && ok || fail "non-ASCII key from a UTF-16 file: $out"
rm -f "src/Orders/Zamówienia.swift" src/Orders/pl.strings .ai/utf8.md

out="$(cd "$TMP" && bash "$CHECK" .ai/orders.md --root "$REPO")"
has "$out" "ReturnOrderController" && ok || fail "path relative to --root"

out="$(bash "$CHECK" "$TMP/missing" --root . 2>/dev/null)"; rc=$?
has "$out" "CHECKED 0" && [ "$rc" -eq 0 ] && ok || fail "empty list"
# --- workspace and sessions directories are pruned at any depth
mkdir -p docs2/workspace/plans docs2/sessions docs2/sub/workspace/deep
for f in docs2/kept.md docs2/workspace/plans/p.md docs2/sessions/s.md docs2/sub/workspace/deep/w.md; do
  printf '# x\nClass `PrunedGhostController`.\n' >"$f"
done
out="$(bash "$CHECK" docs2 --root .)"
has "$out" "NAME_MISSING docs2/kept.md:2 PrunedGhostController" && ok || fail "document outside workspace skipped: $out"
printf '%s\n' "$out" | grep -qE 'workspace/|sessions/' && fail "document from workspace or sessions checked: $out" || ok
rm -rf docs2

# --- excluded docs paths: --exclude (repeatable, git pathspec globs) and the overlay
#     section "Excluded docs paths" in English and Polish; files outside the globs stay checked
mkdir -p docs3/external_services/other-repo/api docs3/external_services_notes docs3/ext/sub
printf '# o\nClass `OtherRepoClient`.\n' >docs3/external_services/other-repo/api/client.md
printf '# o\nClass `OtherRepoWorker`.\n' >docs3/external_services/other-repo/README.md
printf '# k\nClass `KeptGhostName`.\n' >docs3/kept.md
printf '# n\nClass `NotesGhostName`.\n' >docs3/external_services_notes/notes.md
printf '# t\nClass `ExtTopName`.\n' >docs3/ext/top.md
printf '# d\nClass `ExtDeepName`.\n' >docs3/ext/sub/deep.md
out="$(bash "$CHECK" docs3 --root . --exclude docs3/external_services/ --exclude 'docs3/ext/*.md')"; rc=$?
has "$out" "OtherRepo" && fail "document under an excluded directory checked: $out" || ok
has "$out" "ExtTopName" && fail "document matching the glob checked: $out" || ok
has "$out" "NAME_MISSING docs3/kept.md:2 KeptGhostName" && ok || fail "document outside the globs skipped: $out"
has "$out" "NAME_MISSING docs3/external_services_notes/notes.md:2 NotesGhostName" && ok || fail "directory glob hides a sibling with the same prefix: $out"
has "$out" "NAME_MISSING docs3/ext/sub/deep.md:2 ExtDeepName" && ok || fail "* crosses a directory: $out"
has "$out" "CHECKED 3 NAME_MISSING 3 EXCLUDED 3" && [ "$rc" -eq 1 ] && ok || fail "counters with --exclude: $(printf '%s' "$out" | tail -1) (code $rc)"
out="$(bash "$CHECK" docs3 --root . --exclude '**/api/*.md')"
has "$out" "OtherRepoClient" && fail "**/ glob does not exclude: $out" || ok
has "$out" "NAME_MISSING docs3/external_services/other-repo/README.md:2 OtherRepoWorker" && has "$out" "EXCLUDED 1" && ok || fail "**/ glob excludes too much: $out"
out="$(bash "$CHECK" docs3 --root . --exclude 'docs3/**')"; rc=$?
has "$out" "CHECKED 0 NAME_MISSING 0 EXCLUDED 6" && [ "$rc" -eq 0 ] && ok || fail "everything excluded: $out (code $rc)"
mkdir -p .ai/ov
printf '{"paths":{"overlays":".ai/ov"}}\n' >.ai/av.config.json
for header in "Excluded docs paths" "Wykluczone ścieżki docs" "Wykluczone sciezki docs"; do
  cat >.ai/ov/av-docs-sync.md <<MD
# Overlay
## Known false names
- \`docs3/kept.md\`
## $header
- \`docs3/external_services/\` - docs of another repository
- \`docs3/ext/*.md\`
## Other
- \`docs3/external_services_notes/**\`
MD
  out="$(bash "$CHECK" docs3 --root .)"
  has "$out" "OtherRepo" && fail "$header: overlay glob does not exclude: $out" || ok
  has "$out" "NAME_MISSING docs3/kept.md:2 KeptGhostName" && has "$out" "NAME_MISSING docs3/external_services_notes/notes.md:2" && ok || fail "$header: item outside the section excludes: $out"
  has "$out" "CHECKED 3 NAME_MISSING 3 EXCLUDED 3" && ok || fail "$header: counters with overlay: $(printf '%s' "$out" | tail -1)"
done
printf '# plain\nKeptGhostName\n' >"$TMP/ignore2.txt"
out="$(bash "$CHECK" docs3 --root . --ignore-file "$TMP/ignore2.txt" --exclude docs3/external_services_notes/)"
has "$out" "OtherRepo" && fail "--ignore-file turns off the overlay exclusions: $out" || ok
has "$out" "CHECKED 1 NAME_MISSING 1 EXCLUDED 4" && has "$out" "NAME_MISSING docs3/ext/sub/deep.md:2 ExtDeepName" && ok || fail "overlay, --exclude and --ignore-file together: $out"
bash "$CHECK" docs3 --root . --exclude >/dev/null; [ $? -eq 2 ] && ok || fail "--exclude without a glob: code 2"
rm -rf docs3 .ai/ov .ai/av.config.json

# --- K2: line scoped ignore entries "<doc>:<line> <name>" (exact and prefix) next to the
#     name and prefix forms; a stale line entry prints KNOWN_STALE; English and Polish headers
mkdir -p .ai/ov
printf '{"paths":{"overlays":".ai/ov"}}\n' >.ai/av.config.json
cat >.ai/scoped.md <<'MD'
# Scoped
Widget `ScopedGhostName` on line 2.
Again `ScopedGhostName` on line 3.
Prefix `legacy_scoped_one` and `legacy_scoped_two`.
Global `GlobalGhostName`, prefix `TmpGhostWidget`.
Plain `KeptScopedGhost`.
MD
for header in "Known false names" "Znane fałszywe nazwy" "Znane falszywe nazwy"; do
  cat >.ai/ov/av-docs-sync.md <<MD
# Overlay
## $header
- \`.ai/scoped.md:2 ScopedGhostName\` - template widget id
- \`./.ai/scoped.md:4 legacy_scoped*\`
- \`GlobalGhostName\`
- \`TmpGhost*\`
- \`.ai/scoped.md:6 NotOnThatLine\`
- \`.ai/scoped.md:99 ScopedGhostName\`
- \`.ai/other.md:2 ScopedGhostName\`
## Other
- \`.ai/scoped.md:3 ScopedGhostName\`
MD
  out="$(bash "$CHECK" .ai/scoped.md --root .)"; rc=$?
  has "$out" "NAME_MISSING .ai/scoped.md:2 " && fail "$header: line entry does not ignore its line: $out" || ok
  has "$out" "NAME_MISSING .ai/scoped.md:3 ScopedGhostName" && ok || fail "$header: line entry ignores another line: $out"
  has "$out" "legacy_scoped" && fail "$header: line scoped prefix does not ignore: $out" || ok
  has "$out" "GlobalGhostName" && fail "$header: name form broken next to line entries: $out" || ok
  has "$out" "TmpGhostWidget" && fail "$header: prefix form broken next to line entries: $out" || ok
  has "$out" "NAME_MISSING .ai/scoped.md:6 KeptScopedGhost" && ok || fail "$header: unrelated name ignored: $out"
  has "$out" "CHECKED 2 NAME_MISSING 2 EXCLUDED 0" && [ "$rc" -eq 1 ] && ok || fail "$header: counters with line entries: $(printf '%s' "$out" | tail -1) (code $rc)"
  has "$out" "KNOWN_STALE .ai/scoped.md:6 NotOnThatLine" && ok || fail "$header: line without the name not stale: $out"
  has "$out" "KNOWN_STALE .ai/scoped.md:99 ScopedGhostName" && ok || fail "$header: line past the end not stale: $out"
  out="$(bash "$CHECK" .ai/ov/av-docs-sync.md --root .)"
  has "$out" "NAME_MISSING .ai/ov/av-docs-sync.md:3 " && fail "$header: ignore section entries reported in the overlay itself: $out" || ok
  has "$out" "NAME_MISSING .ai/ov/av-docs-sync.md:11 ScopedGhostName" && ok || fail "$header: section after the ignore section not checked: $out"
  for e in ".ai/scoped.md:2 " "legacy_scoped" "GlobalGhostName" "TmpGhost" ".ai/other.md" ".ai/scoped.md:3"; do
    printf '%s\n' "$out" | grep '^KNOWN_STALE' | grep -qF -- "$e" && fail "$header: false stale entry $e: $out" || ok
  done
  [ "$(printf '%s\n' "$out" | tail -1 | cut -c1-8)" = "CHECKED " ] && ok || fail "$header: summary is not the last line: $out"
done
printf '# Scoped\nWidget `OtherGhostName` on line 2.\n' >.ai/scoped.md
cat >.ai/ov/av-docs-sync.md <<'MD'
## Known false names
- `.ai/scoped.md:2 ScopedGhostName`
- `.ai/scoped.md:2 Other*`
MD
out="$(bash "$CHECK" .ai/scoped.md --root .)"; rc=$?
has "$out" "KNOWN_STALE .ai/scoped.md:2 ScopedGhostName" && ok || fail "renamed name on the line not stale: $out"
has "$out" "KNOWN_STALE .ai/scoped.md:2 Other*" && fail "prefix entry wrongly stale: $out" || ok
has "$out" "CHECKED 0 NAME_MISSING 0" && [ "$rc" -eq 0 ] && ok || fail "stale hint changes the result: $out (code $rc)"
printf '# Scoped\nWord `ScopedGhostNameLonger` only.\n' >.ai/scoped.md
printf '## Known false names\n- `.ai/scoped.md:2 ScopedGhostName`\n' >.ai/ov/av-docs-sync.md
out="$(bash "$CHECK" .ai/scoped.md --root .)"
has "$out" "NAME_MISSING .ai/scoped.md:2 ScopedGhostNameLonger" && has "$out" "KNOWN_STALE .ai/scoped.md:2 ScopedGhostName" && ok || fail "exact line entry matches a longer name: $out"
printf '# plain\n- `.ai/scoped.md:2 ScopedGhostNameLonger`\n' >"$TMP/ignore_line.txt"
out="$(bash "$CHECK" .ai/scoped.md --root . --ignore-file "$TMP/ignore_line.txt")"
has "$out" "CHECKED 0 NAME_MISSING 0" && ! has "$out" "KNOWN_STALE" && ok || fail "line entry in --ignore-file: $out"
out="$(bash "$CHECK" .ai/orders.md --root .)"
has "$out" "KNOWN_STALE" && fail "stale hint for a document that was not checked: $out" || ok
rm -rf .ai/ov .ai/av.config.json .ai/scoped.md

# --- K5: the code dictionary does not depend on the docs paths given, and it is complete
#     on a corpus large enough for threaded git grep to drop matches
mkdir -p src/templates/form src/gen .claude/skills/role
printf '{%% block textarea_widget %%}<textarea></textarea>{%% endblock %%}\n' >src/templates/form/fields.html.twig
printf '# Forms\nBlock `textarea_widget` sets the class.\n' >.ai/forms.md
printf '# Role\nUse `role_only_ghost` here.\n' >.claude/skills/role/SKILL.md
LC_ALL=C awk 'BEGIN { for (f = 1; f <= 64; f++) { fn = sprintf("src/gen/mod%02d.ts", f)
  for (l = 1; l <= 400; l++) printf "const val_%d_%d = callFn(argOne, argTwo, argThree);\n", f, l > fn; close(fn) } }'
LC_ALL=C awk 'BEGIN { print "# Generated"; for (f = 1; f <= 64; f++) for (l = 1; l <= 400; l += 4) printf "- `val_%d_%d`\n", f, l }' >.ai/gen.md
out1="$(bash "$CHECK" .ai/forms.md --root .)"
out2="$(bash "$CHECK" .ai/forms.md .claude/skills --root .)"
has "$out1" "textarea_widget" && fail "name from a template reported without the extra path: $out1" || ok
has "$out2" "textarea_widget" && fail "name from a template reported with the extra path: $out2" || ok
has "$out2" "NAME_MISSING .claude/skills/role/SKILL.md:2 role_only_ghost" && has "$out2" "CHECKED 2 NAME_MISSING 1" && ok || fail "extra docs path not checked: $out2"
for i in 1 2 3; do
  out="$(bash "$CHECK" .ai/gen.md .ai/forms.md --root .)"
  has "$out" "CHECKED 6401 NAME_MISSING 0 " && ok || fail "code dictionary lost names (run $i): $(printf '%s\n' "$out" | head -3 | tr '\n' ' ')"
done
rm -rf src/templates src/gen .claude .ai/forms.md .ai/gen.md

bash "$CHECK" >/dev/null; [ $? -eq 2 ] && ok || fail "no arguments"

# --- secrets: env and key files never enter the code corpus
SEC="$TMP/secrets repo"
mkdir -p "$SEC/src" "$SEC/config" "$SEC/.ai"
git -C "$SEC" init -q && git -C "$SEC" config user.email t@t && git -C "$SEC" config user.name t
printf 'EnvOnlyNameXyz=value\n' >"$SEC/.env"
printf 'KeyOnlyNameXyz\n' >"$SEC/config/app.key"
printf 'LocalEnvNameXyz=1\n' >"$SEC/config/.env.local"
printf 'function RealServiceName() {}\n' >"$SEC/src/app.js"
printf '# Docs\n`EnvOnlyNameXyz` `KeyOnlyNameXyz` `LocalEnvNameXyz` `RealServiceName`\n' >"$SEC/.ai/x.md"
git -C "$SEC" add -A -f && git -C "$SEC" commit -qm init
out="$(bash "$CHECK" .ai --root "$SEC" 2>&1)"
has "$out" "EnvOnlyNameXyz" && ok || fail "secrets: name only in .env must not count as found"
has "$out" "KeyOnlyNameXyz" && ok || fail "secrets: name only in a key file must not count as found"
has "$out" "LocalEnvNameXyz" && ok || fail "secrets: name only in a nested .env.* must not count as found"
has "$out" "NAME_MISSING .ai/x.md:2 RealServiceName" && fail "secrets: a real code name reported" || ok

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

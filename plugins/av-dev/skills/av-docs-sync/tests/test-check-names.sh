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

bash "$CHECK" >/dev/null; [ $? -eq 2 ] && ok || fail "no arguments"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

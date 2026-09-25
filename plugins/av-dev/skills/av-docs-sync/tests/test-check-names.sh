#!/bin/bash
# Testy czarnej skrzynki dla check_names.sh.
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
Kontroler: `OrderController::sendOrder()`, limit `MAX_ORDER_ITEMS`.
Stary kontroler: `RewardOrderController`.
Metoda `sendOrderLegacy` obsluguje stare zamowienia.
Klasa `LegacyController` zostala usunieta w NKR-1.
Przyklad: `FooViewController`, `<NazwaModułu>`.
Tabela `order_items_archive`.
MD
cat >.ai/code.md <<'MD'
```php
$x = new NotInCodeButInBlock();
```
MD
git add -A && git commit -qm init
mkdir -p src/DependencyInjection && printf "<?php\\n" >src/DependencyInjection/Container.php
printf '<?php\nfinal class NewUntrackedService {}\n' >src/Orders/NewUntrackedService.php
printf '# Nowe\nSerwis `NewUntrackedService` w `DependencyInjection`.\n' >.ai/new.md
out0="$(bash "$CHECK" .ai/new.md --root .)"
has "$out0" "NAME_MISSING 0" && ok || fail "nieśledzone pliki i katalogi: $out0"
rm -rf .ai/new.md src/Orders/NewUntrackedService.php src/DependencyInjection

out="$(bash "$CHECK" .ai --root .)"; rc=$?
has "$out" "NAME_MISSING .ai/orders.md:3 RewardOrderController" && ok || fail "brak kandydata RewardOrderController"
has "$out" "NAME_MISSING .ai/orders.md:4 sendOrderLegacy" && ok || fail "brak kandydata metody"
has "$out" "NAME_MISSING .ai/orders.md:7 order_items_archive" && ok || fail "brak kandydata snake_case"
for n in OrderController sendOrder MAX_ORDER_ITEMS LegacyController FooViewController NotInCodeButInBlock; do
  printf '%s\n' "$out" | grep '^NAME_MISSING' | grep -qw -- "$n" && fail "falszywy kandydat: $n" || ok
done
has "$out" "NAME_MISSING 3" && [ "$rc" -eq 1 ] && ok || fail "liczniki: $(printf '%s' "$out" | tail -1) kod $rc"

# --- R2a/b: przekreslenie i placeholdery
cat >.ai/noise.md <<'MD'
# Szum
- ~~`GoneInStrike` byl tu~~ a `RealMissingOne` zostal.
- Szablon: `openFoo`, `fooViewModel`, `foo_title`, `NovolApiX`, `novolApiX`, `NovolApiXxxManager`.
- Wzorce: `novolApi{Feature}`, `NS*UsageDescription`, `account_lock_error*`, `Request<SomeModelType>`.
- Stopka `tableFooterViewMissing` nie jest placeholderem.
- Wywolanie, np. `MyViewController.loadFromNib()`.
- Zwykla klasa: `MyRealController`.
MD
out="$(bash "$CHECK" .ai/noise.md --root .)"
for n in GoneInStrike openFoo fooViewModel foo_title NovolApiX novolApiX NovolApiXxxManager novolApi UsageDescription account_lock_error SomeModelType MyViewController; do
  printf '%s\n' "$out" | grep '^NAME_MISSING' | grep -qw -- "$n" && fail "placeholder zgloszony: $n" || ok
done
for n in RealMissingOne tableFooterViewMissing MyRealController loadFromNib; do
  has "$out" " $n" && ok || fail "brak kandydata: $n"
done
has "$out" "NAME_MISSING 4" && ok || fail "liczniki szumu: $(printf '%s' "$out" | tail -1)"

# --- R2c: lista ignorowanych w nakladce (dokladnie i prefiks), sciezka z configu
mkdir -p .ai/ov
printf '{"paths":{"overlays":".ai/ov"}}\n' >.ai/av.config.json
cat >.ai/ov/av-docs-sync.md <<'MD'
# Nakladka
## Mapa kod -> docs
- `RewardOrderController` to nie jest ignorowana nazwa.
## Znane fałszywe nazwy
- `sendOrderLegacy` - nazwa z backendu
- `order_items*`
## Inne
- `LegacyThing`
MD
out="$(bash "$CHECK" .ai/orders.md --root .)"
has "$out" "sendOrderLegacy" && fail "ignorowana nazwa zgloszona" || ok
has "$out" "order_items_archive" && fail "prefiks nie ignoruje" || ok
has "$out" "NAME_MISSING .ai/orders.md:3 RewardOrderController" && ok || fail "nazwa spoza sekcji zignorowana: $out"
has "$out" "NAME_MISSING 1" && ok || fail "liczniki z nakladka: $(printf '%s' "$out" | tail -1)"

printf '# plain\nRewardOrderController\n- `sendOrder*`\n' >"$TMP/ignore.txt"
out="$(bash "$CHECK" .ai/orders.md --root . --ignore-file "$TMP/ignore.txt")"
has "$out" "RewardOrderController" && fail "--ignore-file bez sekcji nie dziala" || ok
has "$out" "sendOrderLegacy" && fail "--ignore-file prefiks nie dziala" || ok
has "$out" "order_items_archive" && ok || fail "--ignore-file nie zastepuje nakladki: $out"
bash "$CHECK" .ai/orders.md --root . --ignore-file "$TMP/nie-ma.txt" >/dev/null 2>&1; [ $? -eq 2 ] && ok || fail "brak --ignore-file: kod 2"
printf '# bez sekcji\n- `RewardOrderController`\n' >.ai/ov/av-docs-sync.md
out="$(bash "$CHECK" .ai/orders.md --root .)"
has "$out" "NAME_MISSING 3" && ok || fail "nakladka bez sekcji nie moze ignorowac: $(printf '%s' "$out" | tail -1)"
rm -rf .ai/ov .ai/av.config.json

# --- R2d: klucze z plikow tlumaczen (UTF-8 i UTF-16) sa znalezione
mkdir -p App/pl.lproj
printf '"points_many_utf8" = "punktow";\n' >App/pl.lproj/Localizable.strings
printf '"points_many_utf16" = "punktow";\n' | iconv -f UTF-8 -t UTF-16 >App/pl.lproj/Other.strings
printf '# L\nKlucze `points_many_utf8`, `points_many_utf16`, `points_none_here`.\n' >.ai/l10n.md
out="$(bash "$CHECK" .ai/l10n.md --root .)"
has "$out" "points_many_utf8" && fail "klucz UTF-8 zgloszony" || ok
has "$out" "points_many_utf16" && fail "klucz UTF-16 zgloszony" || ok
has "$out" "NAME_MISSING .ai/l10n.md:2 points_none_here" && ok || fail "brak kandydata klucza: $out"
rm -rf App .ai/l10n.md .ai/noise.md

out="$(cd "$TMP" && bash "$CHECK" .ai/orders.md --root "$REPO")"
has "$out" "RewardOrderController" && ok || fail "sciezka wzgledem --root"

out="$(bash "$CHECK" "$TMP/nie-ma" --root . 2>/dev/null)"; rc=$?
has "$out" "CHECKED 0" && [ "$rc" -eq 0 ] && ok || fail "pusta lista"
# --- katalogi workspace i sessions sa przycinane na kazdej glebokosci
mkdir -p docs2/workspace/plans docs2/sessions docs2/sub/workspace/deep
for f in docs2/kept.md docs2/workspace/plans/p.md docs2/sessions/s.md docs2/sub/workspace/deep/w.md; do
  printf '# x\nKlasa `PrunedGhostController`.\n' >"$f"
done
out="$(bash "$CHECK" docs2 --root .)"
has "$out" "NAME_MISSING docs2/kept.md:2 PrunedGhostController" && ok || fail "dokument poza workspace pominiety: $out"
printf '%s\n' "$out" | grep -qE 'workspace/|sessions/' && fail "dokument z workspace albo sessions sprawdzony: $out" || ok
rm -rf docs2

bash "$CHECK" >/dev/null; [ $? -eq 2 ] && ok || fail "bez argumentow"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

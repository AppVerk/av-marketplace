#!/bin/bash
# Testy czarnej skrzynki dla check_refs.sh.
# Buduje male repo z dokumentem pelnym przypadkow brzegowych i sprawdza wynik.
set -u
CHECK="$(cd "$(dirname "$0")/.." && pwd)/scripts/check_refs.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

REPO="$TMP/repo with space"
mkdir -p "$REPO/App/Domains/Login_" "$REPO/.ai/modules" "$REPO/scripts" "$REPO/App/Models/Request"
cd "$REPO" || exit 1
git init -q
printf 'Pods/\n.ai/workspace/*\nlocal.env\n' >.gitignore
touch App/Domains/Login_/LoginViewController.swift scripts/run.sh .ai/README.md App/Models/Request/LoginParams.swift
printf '{"dependencies":{"zone.js":"1"}}\n' >package.json

cat >.ai/modules/Login.md <<'EOF'
# Login

Plik istnieje: `App/Domains/Login_/LoginViewController.swift`.
Sufiks od katalogu zrodel: `Domains/Login_/LoginViewController.swift:12-20`.
Link wzgledny: [indeks](../README.md) i [skrypt](../../scripts/run.sh).
Glob: `App/Models/*Params.swift`.
Brakuje: `App/Domains/Login_/RemovedViewController.swift`.
Link do nieistniejacego: [stary](../old.md).
Gola nazwa: `Ghost.swift`.
Placeholdery: `docs/YYYY-MM-DD-temat.md`, `Domains/Foo_/FooViewController.swift`, `<Nazwa>/plik.swift`.
Pakiet: `zone.js`. Galaz: `feature/NKR-1-x/`. Adres: [strona](https://example.com/a.md).
Ignorowane: `Pods/Manifest.lock`, `.ai/workspace/plans/plan.md`, `local.env/`.
Plik `App/Legacy/Old.swift` zostal usuniety w NKR-100.
Samo rozszerzenie: `.swift`.

```sh
cat App/NotChecked/InCodeBlock.swift
```
EOF

cp .ai/modules/Login.md "$TMP/with space.md"

# --- 1. wynik na dokumencie w repo
out="$(bash "$CHECK" .ai --root .)"; rc=$?
has "$out" "MISSING .ai/modules/Login.md:7 App/Domains/Login_/RemovedViewController.swift" && ok || fail "brak MISSING dla usunietego pliku"
has "$out" "MISSING .ai/modules/Login.md:8 ../old.md" && ok || fail "brak MISSING dla martwego linku"
has "$out" "UNRESOLVED .ai/modules/Login.md:9 Ghost.swift" && ok || fail "brak UNRESOLVED dla golej nazwy"
[ "$rc" -eq 1 ] && ok || fail "kod $rc zamiast 1"

# --- 2. brak falszywych alarmow
for tok in LoginViewController.swift README.md run.sh Params.swift YYYY Foo Nazwa zone.js feature/ example.com Pods .ai/workspace local.env Legacy "Login.md:14 " InCodeBlock; do
  printf '%s\n' "$out" | grep -E '^(MISSING|UNRESOLVED)' | grep -q -- "$tok" && fail "falszywy alarm: $tok" || ok
done
has "$out" "MISSING 2 UNRESOLVED 1 EXTERNAL 0 WORKSPACE 1" && ok || fail "zle liczniki: $(printf '%s' "$out" | tail -1)"

# --- 2b. polska odmiana z ogonkiem tez wylacza linie
printf '# x\nPlik `App/Gone/Usuniety.swift` został usunięty.\n' >"$TMP/pl.md"
out2="$(bash "$CHECK" "$TMP/pl.md" --root .)"
has "$out2" "MISSING 0" && ok || fail "odmiana z ogonkiem nie wylacza linii: $out2"

# --- 2c. sciezki poza repo, inne repo, workspace wzgledny, nigdy, goly katalog
mkdir -p "$TMP/sibling-repo/tests" "$REPO/.ai/workspace/miro"
printf '# y\nTesty: `../../sibling-repo/tests/`.\nPlik: `../../ghost-repo/x.md`.\nW repozytorium backend: `api/Orders/Bar.php`.\nNotatki: `workspace/miro/`.\nNIGDY nie zapisuj do `.claude/plans/x.md`.\nKatalog `reports/`.\n' >"$REPO/.ai/ext.md"
out3="$(bash "$CHECK" .ai/ext.md --root .)"
has "$out3" "EXTERNAL .ai/ext.md:3 ../../ghost-repo/x.md" && ok || fail "brak EXTERNAL dla nieistniejacego repo"
has "$out3" "sibling-repo" && fail "istniejace repo obok zgloszone" || ok
has "$out3" "EXTERNAL .ai/ext.md:4 api/Orders/Bar.php" && ok || fail "linia o innym repo nie jest EXTERNAL"
has "$out3" "MISSING 0 UNRESOLVED 0 EXTERNAL 2 WORKSPACE 0" && ok || fail "extra liczniki: $(printf '%s' "$out3" | tail -1)"
rm "$REPO/.ai/ext.md"

# --- 2e. zaprzeczenie "nie w", ignorowanie po samej nazwie
printf '# z\nZdarzenia leza w `App/Events/`, nie w `App/Domain/Event/`.\nLokalnie: `local.env`.\n' >"$REPO/.ai/neg.md"
out5="$(bash "$CHECK" .ai/neg.md --root .)"
has "$out5" "MISSING 0 UNRESOLVED 0" && ok || fail "nie w / basename: $out5"
rm "$REPO/.ai/neg.md"
printf '# w\nBrak decyzji, zobacz `.ai/workspace/plans/p.md`.\n' >"$REPO/.ai/negws.md"
out7="$(bash "$CHECK" .ai/negws.md --root .)"
has "$out7" "WORKSPACE .ai/negws.md:2 .ai/workspace/plans/p.md" && ok || fail "WORKSPACE w linii z zaprzeczeniem: $out7"
rm "$REPO/.ai/negws.md"
printf '# d\nPliki robocze leza w `.ai/workspace/` i `.ai/workspace/plans/`.\n' >"$REPO/.ai/wsdir.md"
out8="$(bash "$CHECK" .ai/wsdir.md --root .)"
has "$out8" "WORKSPACE 0" && ok || fail "wzmianka o katalogu workspace zgloszona: $(printf '%s' "$out8" | tail -1)"
rm "$REPO/.ai/wsdir.md"

# --- 2f. nazwy skryptow av-* i gola nazwa w README workspace
mkdir -p "$REPO/.ai/workspace"
printf '# ws\nDowody zapisuje `gate.sh` w `runs/`.\n' >"$REPO/.ai/workspace/README.md"
printf '# ws\nBramki: `gate.sh`.\n' >"$REPO/.ai/gates.md"
out6="$(bash "$CHECK" .ai/gates.md .ai/workspace/README.md --root . --workspace .ai/workspace)"
has "$out6" "MISSING 0 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0" && ok || fail "skrypty av i README workspace: $(printf '%s' "$out6" | tail -1)"
rm -f "$REPO/.ai/gates.md"

# --- 2d. dokument podany wzgledem --root spoza katalogu repo
out4="$(cd "$TMP" && bash "$CHECK" .ai/modules/Login.md --root "$REPO")"
has "$out4" "RemovedViewController.swift" && ok || fail "sciezka dokumentu wzgledem --root"

# --- 3. plik z poza repo ze spacja w nazwie
out="$(bash "$CHECK" "$TMP/with space.md" --root .)"
has "$out" "App/Domains/Login_/RemovedViewController.swift" && ok || fail "plik ze spacja nie sprawdzony"

# --- 4. czyste docs: kod 0
mkdir -p "$TMP/clean"
printf '# ok\n`App/Domains/Login_/LoginViewController.swift`\n' >"$TMP/clean/ok.md"
out="$(bash "$CHECK" "$TMP/clean" --root .)"; rc=$?
has "$out" "MISSING 0" && [ "$rc" -eq 0 ] && ok || fail "czyste docs: $out (kod $rc)"

# --- 5. pusta lista dokumentow nie wisi
out="$(bash "$CHECK" "$TMP/nope" --root . </dev/null 2>/dev/null)"; rc=$?
has "$out" "CHECKED 0" && [ "$rc" -eq 0 ] && ok || fail "pusta lista: $out"

# --- 5b. --strict: kod 1 tylko przy MISSING, flaga nie jest sciezka
printf '# u\nGola nazwa: `Ghost.swift`. Inne repo: `../../ghost-repo/x.md`.\n' >"$TMP/clean/soft.md"
out="$(bash "$CHECK" "$TMP/clean" --root . --strict 2>&1)"; rc=$?
has "$out" "MISSING 0 UNRESOLVED 1 EXTERNAL 1" && [ "$rc" -eq 0 ] && ok || fail "strict z UNRESOLVED i EXTERNAL: $out (kod $rc)"
has "$out" "WARNING" && fail "--strict potraktowane jako sciezka" || ok
bash "$CHECK" .ai --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict z MISSING"

# --- 5c. pakiety *.xcresult bez wnetrza w indeksie; workspace i sessions przycinane
mkdir -p "$REPO/Results/Run.xcresult/Data" "$REPO/docs2/workspace/plans" "$REPO/docs2/sessions" "$REPO/docs2/sub/workspace/deep"
touch "$REPO/Results/Run.xcresult/Info.plist" "$REPO/Results/Run.xcresult/Data/Inside.plist"
printf '# r\nWynik: `Results/Run.xcresult/`.\nWnetrze: `Results/Run.xcresult/Data/Inside.plist`.\n' >"$REPO/docs2/kept.md"
for f in workspace/plans/p.md sessions/s.md sub/workspace/deep/w.md; do
  printf '# x\nBrak: `App/Pruned/Ghost.swift`.\n' >"$REPO/docs2/$f"
done
out="$(bash "$CHECK" docs2 --root .)"
printf '%s\n' "$out" | grep -q 'MISSING docs2/kept.md:2' && fail "pakiet xcresult nieznaleziony: $out" || ok
has "$out" "MISSING docs2/kept.md:3 Results/Run.xcresult/Data/Inside.plist" && ok || fail "wnetrze xcresult w indeksie: $out"
printf '%s\n' "$out" | grep -q 'Pruned/Ghost' && fail "dokument z workspace albo sessions sprawdzony: $out" || ok
has "$out" "CHECKED 2 MISSING 1" && ok || fail "liczniki z przycinaniem: $(printf '%s' "$out" | tail -1)"
out="$(bash "$CHECK" docs2/workspace --root .)"
has "$out" "CHECKED 0" && ok || fail "katalog workspace podany wprost: $out"
rm -rf "$REPO/docs2" "$REPO/Results"

# --- 6. bez argumentow: kod 2
bash "$CHECK" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "bez argumentow kod $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

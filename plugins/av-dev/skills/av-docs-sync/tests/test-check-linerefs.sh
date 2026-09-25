#!/bin/bash
# Testy czarnej skrzynki dla check_linerefs.sh.
set -u
CHECK="$(cd "$(dirname "$0")/.." && pwd)/scripts/check_linerefs.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

REPO="$TMP/repo with space"
mkdir -p "$REPO/App/Core" "$REPO/.ai"
cd "$REPO" || exit 1
git init -q && git config user.email t@t && git config user.name t
for i in 1 2 3 4 5 6 7 8 9 10; do echo "line $i"; done >App/Core/Stable.swift
for i in 1 2 3 4 5 6 7 8 9 10; do echo "line $i"; done >App/Core/Moving.swift
git add -A && git commit -qm code
printf '# Reguly\n- A: `App/Core/Stable.swift:3-4`\n- B: `App/Core/Moving.swift:5`\n- C: `Core/Stable.swift:30`\n- D: `App/Gone.swift:2`\n' >.ai/rules.md
git add -A && git commit -qm docs
printf 'nowa\n' | cat - App/Core/Moving.swift >"$TMP/m" && mv "$TMP/m" App/Core/Moving.swift
git add -A && git commit -qm "move lines"

out="$(bash "$CHECK" .ai --root .)"; rc=$?
has "$out" "LINEREF_CHANGED .ai/rules.md:3 App/Core/Moving.swift:5" && ok || fail "brak CHANGED dla zmienionego pliku"
has "$out" "LINEREF_RANGE .ai/rules.md:4 Core/Stable.swift:30" && ok || fail "brak RANGE dla linii poza plikiem"
has "$out" "LINEREF_NOFILE .ai/rules.md:5 App/Gone.swift:2" && ok || fail "brak NOFILE"
printf '%s\n' "$out" | grep -q 'Stable.swift:3-4' && fail "falszywy alarm dla niezmienionego pliku" || ok
has "$out" "CHECKED 4 LINEREF_CHANGED 1 LINEREF_RANGE 1 LINEREF_NOFILE 1" && [ "$rc" -eq 1 ] && ok || fail "liczniki: $(printf '%s' "$out" | tail -1)"

printf '# ok\n`App/Core/Stable.swift:1`\n' >.ai/ok.md && git add -A && git commit -qm ok
out="$(bash "$CHECK" .ai/ok.md --root .)"; rc=$?
has "$out" "CHECKED 1 LINEREF_CHANGED 0" && [ "$rc" -eq 0 ] && ok || fail "czyste odwolanie: $out"

# --- sciezka ze spacja i "&", odwolanie ":N" dziedziczy plik
mkdir -p "App/Login & Registration_"
for i in 1 2 3 4 5 6; do echo "line $i"; done >"App/Login & Registration_/Form.swift"
git add -A && git commit -qm form
printf '# s\n| x | `App/Login & Registration_/Form.swift:2-3`, `:5` |\n| y | `Login & Registration_/Form.swift:9` |\n' >.ai/space.md
git add -A && git commit -qm space
out="$(bash "$CHECK" .ai/space.md --root .)"; rc=$?
has "$out" "LINEREF_NOFILE ." && fail "sciezka ze spacja: $out" || ok
has "$out" "LINEREF_RANGE .ai/space.md:3 Login & Registration_/Form.swift:9" && ok || fail "RANGE dla sciezki ze spacja: $out"
has "$out" "CHECKED 3 " && ok || fail "odwolanie :N nie liczone: $(printf '%s' "$out" | tail -1)"

# --- tresc: OK, MOVED, GONE, CHANGED bez identyfikatorow
cat >App/Core/Svc.swift <<'SW'
import Foundation
final class Svc {
  func start() {}
  func stop() {}
  let limit = 15
  func refresh() {}
}
SW
cp App/Core/Svc.swift App/Core/Other.swift
git add -A && git commit -qm svc
cat >.ai/content.md <<'MD'
# Tresc
| Start `start()` | `App/Core/Svc.swift:3` |
| Stop `stop()` | `App/Core/Svc.swift:4` |
| Limit `limit` | `App/Core/Svc.swift:5` |
| Stare `legacyFlow()` | `App/Core/Svc.swift:6` |
| Bez nazw | `App/Core/Svc.swift:2` |
| Dawny `oldHelper()` zostal usuniety | `App/Core/Svc.swift:6` |
| Przez `onlyInOther` | `App/Core/Svc.swift:3`, `App/Core/Other.swift:3` |
MD
git add -A && git commit -qm content
cat >App/Core/Svc.swift <<'SW'
import Foundation
final class Svc {
  func start() {}
  let limit = 15
  func refresh() {}
  func stop() {}
}
SW
printf 'func onlyInOther() {}\n' >>App/Core/Other.swift
git add -A && git commit -qm reorder
out="$(bash "$CHECK" .ai/content.md --root .)"; rc=$?
printf '%s\n' "$out" | grep -q 'content.md:2 ' && fail "OK wypisany: $out" || ok
has "$out" "LINEREF_MOVED .ai/content.md:3 App/Core/Svc.swift:4 -> App/Core/Svc.swift:6 (stop w linii 6)" && ok || fail "brak MOVED: $out"
has "$out" "LINEREF_MOVED .ai/content.md:4 App/Core/Svc.swift:5 -> App/Core/Svc.swift:4" && ok || fail "MOVED w gore: $out"
has "$out" "LINEREF_GONE .ai/content.md:5 App/Core/Svc.swift:6" && ok || fail "brak GONE: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:6 App/Core/Svc.swift:2" && ok || fail "brak CHANGED bez identyfikatorow: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:7 App/Core/Svc.swift:6" && ok || fail "linia o usunieciu nie jest CHANGED: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:8 App/Core/Svc.swift:3" && ok || fail "identyfikator z innego pliku: $out"
has "$out" "LINEREF_MOVED .ai/content.md:8 App/Core/Other.swift:3 -> App/Core/Other.swift:8" && ok || fail "MOVED w drugim pliku linii: $out"
has "$out" "CHECKED 8 LINEREF_CHANGED 3 LINEREF_RANGE 0 LINEREF_NOFILE 0 LINEREF_OK 1 LINEREF_MOVED 3 LINEREF_GONE 1" && [ "$rc" -eq 1 ] && ok || fail "liczniki tresci: $(printf '%s' "$out" | tail -1) kod $rc"

# --- zmiana w drzewie roboczym tez sprawdza tresc
printf '# w\n`start()` w `App/Core/Svc.swift:3`\n' >.ai/wt.md && git add -A && git commit -qm wt
printf '// end\n' >>App/Core/Svc.swift
out="$(bash "$CHECK" .ai/wt.md --root .)"
has "$out" "LINEREF_OK 1" && ok || fail "drzewo robocze, OK: $out"
printf '// top\n' | cat - App/Core/Svc.swift >"$TMP/s" && mv "$TMP/s" App/Core/Svc.swift
out="$(bash "$CHECK" .ai/wt.md --root .)"
has "$out" "LINEREF_MOVED .ai/wt.md:2 App/Core/Svc.swift:3 -> App/Core/Svc.swift:4" && ok || fail "drzewo robocze, MOVED: $out"
git checkout -q -- App/Core/Svc.swift

# --- jeden plik w wielu odwolaniach: lista zmian i pamiec git log daja ten sam wynik
cat >.ai/multi.md <<'MD'
# Wiele
| a | `App/Core/Svc.swift:2` |
| b | `App/Core/Svc.swift:1` |
| c | `App/Core/Stable.swift:1` |
| d | `App/Core/Other.swift:2` |
| e | `App/Core/Other.swift:1` |
MD
printf '# bez odwolan\ntekst\n' >.ai/plain.md
git add -A && git commit -qm multi
printf 'nowa\n' >>App/Core/Other.swift && git add -A && git commit -qm other
printf '// end\n' >>App/Core/Svc.swift
out="$(bash "$CHECK" .ai/multi.md .ai/plain.md --root .)"
has "$out" "LINEREF_CHANGED .ai/multi.md:2 App/Core/Svc.swift:2 (plik zmieniony w drzewie roboczym)" &&
  has "$out" "LINEREF_CHANGED .ai/multi.md:3 App/Core/Svc.swift:1 (plik zmieniony w drzewie roboczym)" && ok || fail "drugie odwolanie do pliku zmienionego w drzewie: $out"
has "$out" "LINEREF_CHANGED .ai/multi.md:5 App/Core/Other.swift:2 (plik zmieniony od" &&
  has "$out" "LINEREF_CHANGED .ai/multi.md:6 App/Core/Other.swift:1 (plik zmieniony od" && ok || fail "drugie odwolanie z tego samego commitu: $out"
has "$out" "Stable.swift" && fail "falszywy alarm dla niezmienionego pliku obok zmienionych: $out" || ok
has "$out" "CHECKED 5 LINEREF_CHANGED 4 " && ok || fail "liczniki wielu odwolan: $(printf '%s' "$out" | tail -1)"
printf '# nowy\n`App/Core/Svc.swift:2`\n' >.ai/untracked.md
out="$(bash "$CHECK" .ai/untracked.md --root .)"
has "$out" "LINEREF_CHANGED .ai/untracked.md:2 App/Core/Svc.swift:2 (plik zmieniony w drzewie roboczym)" && ok || fail "niesledzony dokument: $out"
rm -f .ai/untracked.md
git checkout -q -- App/Core/Svc.swift

# --- repo bez commitow: git diff HEAD nie dziala, wynik jak dawniej
EMPTY="$TMP/empty"
mkdir -p "$EMPTY/App" && (cd "$EMPTY" && git init -q && printf 'a\nb\n' >App/X.swift && printf '# e\n`App/X.swift:1`\n' >doc.md)
out="$(bash "$CHECK" "$EMPTY/doc.md" --root "$EMPTY")"
has "$out" "LINEREF_CHANGED doc.md:2 App/X.swift:1 (plik zmieniony w drzewie roboczym)" && ok || fail "repo bez commitow: $out"

# --- --strict: kod 1 tylko przy RANGE, NOFILE, GONE
bash "$CHECK" .ai/content.md --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict z GONE"
printf '# m\n| Stop `stop()` | `App/Core/Svc.swift:4` |\n| x | `App/Core/Svc.swift:2` |\n' >.ai/soft.md && git add -A && git commit -qm soft
printf '// top\n' | cat - App/Core/Svc.swift >"$TMP/s" && mv "$TMP/s" App/Core/Svc.swift && git add -A && git commit -qm top
bash "$CHECK" .ai/soft.md --root . >/dev/null; [ $? -eq 1 ] && ok || fail "bez strict MOVED i CHANGED daja 1"
bash "$CHECK" .ai/soft.md --root . --strict >/dev/null; [ $? -eq 0 ] && ok || fail "strict z samym MOVED i CHANGED"
bash "$CHECK" .ai/space.md --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict z RANGE"

# --- katalogi workspace i sessions sa przycinane na kazdej glebokosci
mkdir -p docs2/workspace/plans docs2/sessions docs2/sub/workspace/deep
for f in docs2/kept.md docs2/workspace/plans/p.md docs2/sessions/s.md docs2/sub/workspace/deep/w.md; do
  printf '# x\n`App/Gone.swift:2`\n' >"$f"
done
out="$(bash "$CHECK" docs2 --root .)"
has "$out" "LINEREF_NOFILE docs2/kept.md:2" && ok || fail "dokument poza workspace pominiety: $out"
printf '%s\n' "$out" | grep -qE 'workspace|sessions' && fail "dokument z workspace albo sessions sprawdzony: $out" || ok
out="$(bash "$CHECK" docs2/workspace --root .)"
printf '%s\n' "$out" | grep -q 'LINEREF_NOFILE docs2' && fail "katalog workspace podany wprost sprawdzony: $out" || ok
rm -rf docs2

bash "$CHECK" >/dev/null; [ $? -eq 2 ] && ok || fail "bez argumentow"
printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

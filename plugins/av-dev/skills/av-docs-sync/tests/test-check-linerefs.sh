#!/bin/bash
# Black box tests for check_linerefs.sh.
# Docs are English; a Polish removal line checks that Polish negation words still work.
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
printf '# Rules\n- A: `App/Core/Stable.swift:3-4`\n- B: `App/Core/Moving.swift:5`\n- C: `Core/Stable.swift:30`\n- D: `App/Gone.swift:2`\n' >.ai/rules.md
git add -A && git commit -qm docs
printf 'new\n' | cat - App/Core/Moving.swift >"$TMP/m" && mv "$TMP/m" App/Core/Moving.swift
git add -A && git commit -qm "move lines"

out="$(bash "$CHECK" .ai --root .)"; rc=$?
has "$out" "LINEREF_CHANGED .ai/rules.md:3 App/Core/Moving.swift:5" && ok || fail "no CHANGED for a changed file"
has "$out" "LINEREF_RANGE .ai/rules.md:4 Core/Stable.swift:30" && ok || fail "no RANGE for a line outside the file"
has "$out" "LINEREF_NOFILE .ai/rules.md:5 App/Gone.swift:2" && ok || fail "no NOFILE"
printf '%s\n' "$out" | grep -q 'Stable.swift:3-4' && fail "false alarm for an unchanged file" || ok
has "$out" "CHECKED 4 LINEREF_CHANGED 1 LINEREF_RANGE 1 LINEREF_NOFILE 1" && [ "$rc" -eq 1 ] && ok || fail "counters: $(printf '%s' "$out" | tail -1)"

printf '# ok\n`App/Core/Stable.swift:1`\n' >.ai/ok.md && git add -A && git commit -qm ok
out="$(bash "$CHECK" .ai/ok.md --root .)"; rc=$?
has "$out" "CHECKED 1 LINEREF_CHANGED 0" && [ "$rc" -eq 0 ] && ok || fail "clean reference: $out"

# --- path with a space and "&", reference ":N" inherits the file
mkdir -p "App/Login & Registration_"
for i in 1 2 3 4 5 6; do echo "line $i"; done >"App/Login & Registration_/Form.swift"
git add -A && git commit -qm form
printf '# s\n| x | `App/Login & Registration_/Form.swift:2-3`, `:5` |\n| y | `Login & Registration_/Form.swift:9` |\n' >.ai/space.md
git add -A && git commit -qm space
out="$(bash "$CHECK" .ai/space.md --root .)"; rc=$?
has "$out" "LINEREF_NOFILE ." && fail "path with a space: $out" || ok
has "$out" "LINEREF_RANGE .ai/space.md:3 Login & Registration_/Form.swift:9" && ok || fail "RANGE for a path with a space: $out"
has "$out" "CHECKED 3 " && ok || fail "reference :N not counted: $(printf '%s' "$out" | tail -1)"

# --- content: OK, MOVED, GONE, CHANGED without identifiers
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
# Content
| Start `start()` | `App/Core/Svc.swift:3` |
| Stop `stop()` | `App/Core/Svc.swift:4` |
| Limit `limit` | `App/Core/Svc.swift:5` |
| Old `legacyFlow()` | `App/Core/Svc.swift:6` |
| No names | `App/Core/Svc.swift:2` |
| Dawny `oldHelper()` zostal usuniety | `App/Core/Svc.swift:6` |
| Via `onlyInOther` | `App/Core/Svc.swift:3`, `App/Core/Other.swift:3` |
| Old `formerHelper()` was removed | `App/Core/Svc.swift:6` |
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
printf '%s\n' "$out" | grep -q 'content.md:2 ' && fail "OK printed: $out" || ok
has "$out" "LINEREF_MOVED .ai/content.md:3 App/Core/Svc.swift:4 -> App/Core/Svc.swift:6 (stop on line 6)" && ok || fail "no MOVED: $out"
has "$out" "LINEREF_MOVED .ai/content.md:4 App/Core/Svc.swift:5 -> App/Core/Svc.swift:4" && ok || fail "MOVED up: $out"
has "$out" "LINEREF_GONE .ai/content.md:5 App/Core/Svc.swift:6" && ok || fail "no GONE: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:6 App/Core/Svc.swift:2" && ok || fail "no CHANGED without identifiers: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:7 App/Core/Svc.swift:6" && ok || fail "Polish line about removal is not CHANGED: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:8 App/Core/Svc.swift:3" && ok || fail "identifier from another file: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:9 App/Core/Svc.swift:6" && ok || fail "English line about removal is not CHANGED: $out"
has "$out" "LINEREF_MOVED .ai/content.md:8 App/Core/Other.swift:3 -> App/Core/Other.swift:8" && ok || fail "MOVED in the second file of the line: $out"
has "$out" "CHECKED 9 LINEREF_CHANGED 4 LINEREF_RANGE 0 LINEREF_NOFILE 0 LINEREF_OK 1 LINEREF_MOVED 3 LINEREF_GONE 1" && [ "$rc" -eq 1 ] && ok || fail "content counters: $(printf '%s' "$out" | tail -1) code $rc"

# --- a change in the working tree also checks the content
printf '# w\n`start()` in `App/Core/Svc.swift:3`\n' >.ai/wt.md && git add -A && git commit -qm wt
printf '// end\n' >>App/Core/Svc.swift
out="$(bash "$CHECK" .ai/wt.md --root .)"
has "$out" "LINEREF_OK 1" && ok || fail "working tree, OK: $out"
printf '// top\n' | cat - App/Core/Svc.swift >"$TMP/s" && mv "$TMP/s" App/Core/Svc.swift
out="$(bash "$CHECK" .ai/wt.md --root .)"
has "$out" "LINEREF_MOVED .ai/wt.md:2 App/Core/Svc.swift:3 -> App/Core/Svc.swift:4" && ok || fail "working tree, MOVED: $out"
git checkout -q -- App/Core/Svc.swift

# --- one file in many references: the change list and the git log cache give the same result
cat >.ai/multi.md <<'MD'
# Many
| a | `App/Core/Svc.swift:2` |
| b | `App/Core/Svc.swift:1` |
| c | `App/Core/Stable.swift:1` |
| d | `App/Core/Other.swift:2` |
| e | `App/Core/Other.swift:1` |
MD
printf '# no references\ntext\n' >.ai/plain.md
git add -A && git commit -qm multi
printf 'new\n' >>App/Core/Other.swift && git add -A && git commit -qm other
printf '// end\n' >>App/Core/Svc.swift
out="$(bash "$CHECK" .ai/multi.md .ai/plain.md --root .)"
has "$out" "LINEREF_CHANGED .ai/multi.md:2 App/Core/Svc.swift:2 (file changed in the working tree)" &&
  has "$out" "LINEREF_CHANGED .ai/multi.md:3 App/Core/Svc.swift:1 (file changed in the working tree)" && ok || fail "second reference to a file changed in the tree: $out"
has "$out" "LINEREF_CHANGED .ai/multi.md:5 App/Core/Other.swift:2 (file changed since" &&
  has "$out" "LINEREF_CHANGED .ai/multi.md:6 App/Core/Other.swift:1 (file changed since" && ok || fail "second reference from the same commit: $out"
has "$out" "Stable.swift" && fail "false alarm for an unchanged file next to changed ones: $out" || ok
has "$out" "CHECKED 5 LINEREF_CHANGED 4 " && ok || fail "counters for many references: $(printf '%s' "$out" | tail -1)"
printf '# new\n`App/Core/Svc.swift:2`\n' >.ai/untracked.md
out="$(bash "$CHECK" .ai/untracked.md --root .)"
has "$out" "LINEREF_CHANGED .ai/untracked.md:2 App/Core/Svc.swift:2 (file changed in the working tree)" && ok || fail "untracked document: $out"
rm -f .ai/untracked.md
git checkout -q -- App/Core/Svc.swift

# --- repo without commits: git diff HEAD fails, same result as before
EMPTY="$TMP/empty"
mkdir -p "$EMPTY/App" && (cd "$EMPTY" && git init -q && printf 'a\nb\n' >App/X.swift && printf '# e\n`App/X.swift:1`\n' >doc.md)
out="$(bash "$CHECK" "$EMPTY/doc.md" --root "$EMPTY")"
has "$out" "LINEREF_CHANGED doc.md:2 App/X.swift:1 (file changed in the working tree)" && ok || fail "repo without commits: $out"

# --- --strict: code 1 only for RANGE, NOFILE, GONE
bash "$CHECK" .ai/content.md --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict with GONE"
printf '# m\n| Stop `stop()` | `App/Core/Svc.swift:4` |\n| x | `App/Core/Svc.swift:2` |\n' >.ai/soft.md && git add -A && git commit -qm soft
printf '// top\n' | cat - App/Core/Svc.swift >"$TMP/s" && mv "$TMP/s" App/Core/Svc.swift && git add -A && git commit -qm top
bash "$CHECK" .ai/soft.md --root . >/dev/null; [ $? -eq 1 ] && ok || fail "without strict MOVED and CHANGED give 1"
bash "$CHECK" .ai/soft.md --root . --strict >/dev/null; [ $? -eq 0 ] && ok || fail "strict with only MOVED and CHANGED"
bash "$CHECK" .ai/space.md --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict with RANGE"

# --- workspace and sessions directories are pruned at any depth
mkdir -p docs2/workspace/plans docs2/sessions docs2/sub/workspace/deep
for f in docs2/kept.md docs2/workspace/plans/p.md docs2/sessions/s.md docs2/sub/workspace/deep/w.md; do
  printf '# x\n`App/Gone.swift:2`\n' >"$f"
done
out="$(bash "$CHECK" docs2 --root .)"
has "$out" "LINEREF_NOFILE docs2/kept.md:2" && ok || fail "document outside workspace skipped: $out"
printf '%s\n' "$out" | grep -qE 'workspace|sessions' && fail "document from workspace or sessions checked: $out" || ok
out="$(bash "$CHECK" docs2/workspace --root .)"
printf '%s\n' "$out" | grep -q 'LINEREF_NOFILE docs2' && fail "workspace directory given directly checked: $out" || ok
rm -rf docs2

bash "$CHECK" >/dev/null; [ $? -eq 2 ] && ok || fail "no arguments"
printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

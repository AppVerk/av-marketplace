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
mkdir -p "$REPO/src/core" "$REPO/.ai"
cd "$REPO" || exit 1
git init -q && git config user.email t@t && git config user.name t
for i in 1 2 3 4 5 6 7 8 9 10; do echo "line $i"; done >src/core/stable.ts
for i in 1 2 3 4 5 6 7 8 9 10; do echo "line $i"; done >src/core/moving.go
git add -A && git commit -qm code
printf '# Rules\n- A: `src/core/stable.ts:3-4`\n- B: `src/core/moving.go:5`\n- C: `core/stable.ts:30`\n- D: `src/gone.rb:2`\n' >.ai/rules.md
git add -A && git commit -qm docs
printf 'new\n' | cat - src/core/moving.go >"$TMP/m" && mv "$TMP/m" src/core/moving.go
git add -A && git commit -qm "move lines"

out="$(bash "$CHECK" .ai --root .)"; rc=$?
has "$out" "LINEREF_CHANGED .ai/rules.md:3 src/core/moving.go:5" && ok || fail "no CHANGED for a changed file"
has "$out" "LINEREF_RANGE .ai/rules.md:4 core/stable.ts:30" && ok || fail "no RANGE for a line outside the file"
has "$out" "LINEREF_NOFILE .ai/rules.md:5 src/gone.rb:2" && ok || fail "no NOFILE"
printf '%s\n' "$out" | grep -q 'stable.ts:3-4' && fail "false alarm for an unchanged file" || ok
has "$out" "CHECKED 4 LINEREF_CHANGED 1 LINEREF_RANGE 1 LINEREF_NOFILE 1" && [ "$rc" -eq 1 ] && ok || fail "counters: $(printf '%s' "$out" | tail -1)"

printf '# ok\n`src/core/stable.ts:1`\n' >.ai/ok.md && git add -A && git commit -qm ok
out="$(bash "$CHECK" .ai/ok.md --root .)"; rc=$?
has "$out" "CHECKED 1 LINEREF_CHANGED 0" && [ "$rc" -eq 0 ] && ok || fail "clean reference: $out"

# --- path with a space and "&", reference ":N" inherits the file
mkdir -p "app/Orders & Billing_"
for i in 1 2 3 4 5 6; do echo "line $i"; done >"app/Orders & Billing_/form.kt"
git add -A && git commit -qm form
printf '# s\n| x | `app/Orders & Billing_/form.kt:2-3`, `:5` |\n| y | `Orders & Billing_/form.kt:9` |\n' >.ai/space.md
git add -A && git commit -qm space
out="$(bash "$CHECK" .ai/space.md --root .)"; rc=$?
has "$out" "LINEREF_NOFILE ." && fail "path with a space: $out" || ok
has "$out" "LINEREF_RANGE .ai/space.md:3 Orders & Billing_/form.kt:9" && ok || fail "RANGE for a path with a space: $out"
has "$out" "CHECKED 3 " && ok || fail "reference :N not counted: $(printf '%s' "$out" | tail -1)"

# --- content: OK, MOVED, GONE, CHANGED without identifiers
cat >src/core/service.py <<'PY'
import os
class Service:
    def start(self): pass
    def stop(self): pass
    limit = 15
    def refresh(self): pass
# end of class
PY
cp src/core/service.py src/core/other.py
git add -A && git commit -qm svc
cat >.ai/content.md <<'MD'
# Content
| Start `start()` | `src/core/service.py:3` |
| Stop `stop()` | `src/core/service.py:4` |
| Limit `limit` | `src/core/service.py:5` |
| Old `legacyFlow()` | `src/core/service.py:6` |
| No names | `src/core/service.py:2` |
| Dawny `oldHelper()` zostal usuniety | `src/core/service.py:6` |
| Via `onlyInOther` | `src/core/service.py:3`, `src/core/other.py:3` |
| Old `formerHelper()` was removed | `src/core/service.py:6` |
MD
git add -A && git commit -qm content
cat >src/core/service.py <<'PY'
import os
class Service:
    def start(self): pass
    limit = 15
    def refresh(self): pass
    def stop(self): pass
# end of class
PY
printf 'def onlyInOther(): pass\n' >>src/core/other.py
git add -A && git commit -qm reorder
out="$(bash "$CHECK" .ai/content.md --root .)"; rc=$?
printf '%s\n' "$out" | grep -q 'content.md:2 ' && fail "OK printed: $out" || ok
has "$out" "LINEREF_MOVED .ai/content.md:3 src/core/service.py:4 -> src/core/service.py:6 (stop on line 6)" && ok || fail "no MOVED: $out"
has "$out" "LINEREF_MOVED .ai/content.md:4 src/core/service.py:5 -> src/core/service.py:4" && ok || fail "MOVED up: $out"
has "$out" "LINEREF_GONE .ai/content.md:5 src/core/service.py:6" && ok || fail "no GONE: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:6 src/core/service.py:2" && ok || fail "no CHANGED without identifiers: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:7 src/core/service.py:6" && ok || fail "Polish line about removal is not CHANGED: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:8 src/core/service.py:3" && ok || fail "identifier from another file: $out"
has "$out" "LINEREF_CHANGED .ai/content.md:9 src/core/service.py:6" && ok || fail "English line about removal is not CHANGED: $out"
has "$out" "LINEREF_MOVED .ai/content.md:8 src/core/other.py:3 -> src/core/other.py:8" && ok || fail "MOVED in the second file of the line: $out"
has "$out" "CHECKED 9 LINEREF_CHANGED 4 LINEREF_RANGE 0 LINEREF_NOFILE 0 LINEREF_OK 1 LINEREF_MOVED 3 LINEREF_GONE 1" && [ "$rc" -eq 1 ] && ok || fail "content counters: $(printf '%s' "$out" | tail -1) code $rc"

# --- a change in the working tree also checks the content
printf '# w\n`start()` in `src/core/service.py:3`\n' >.ai/wt.md && git add -A && git commit -qm wt
printf '# end\n' >>src/core/service.py
out="$(bash "$CHECK" .ai/wt.md --root .)"
has "$out" "LINEREF_OK 1" && ok || fail "working tree, OK: $out"
printf '# top\n' | cat - src/core/service.py >"$TMP/s" && mv "$TMP/s" src/core/service.py
out="$(bash "$CHECK" .ai/wt.md --root .)"
has "$out" "LINEREF_MOVED .ai/wt.md:2 src/core/service.py:3 -> src/core/service.py:4" && ok || fail "working tree, MOVED: $out"
git checkout -q -- src/core/service.py

# --- one file in many references: the change list and the git log cache give the same result
cat >.ai/multi.md <<'MD'
# Many
| a | `src/core/service.py:2` |
| b | `src/core/service.py:1` |
| c | `src/core/stable.ts:1` |
| d | `src/core/other.py:2` |
| e | `src/core/other.py:1` |
MD
printf '# no references\ntext\n' >.ai/plain.md
git add -A && git commit -qm multi
printf 'new\n' >>src/core/other.py && git add -A && git commit -qm other
printf '# end\n' >>src/core/service.py
out="$(bash "$CHECK" .ai/multi.md .ai/plain.md --root .)"
has "$out" "LINEREF_CHANGED .ai/multi.md:2 src/core/service.py:2 (file changed in the working tree)" &&
  has "$out" "LINEREF_CHANGED .ai/multi.md:3 src/core/service.py:1 (file changed in the working tree)" && ok || fail "second reference to a file changed in the tree: $out"
has "$out" "LINEREF_CHANGED .ai/multi.md:5 src/core/other.py:2 (file changed since" &&
  has "$out" "LINEREF_CHANGED .ai/multi.md:6 src/core/other.py:1 (file changed since" && ok || fail "second reference from the same commit: $out"
has "$out" "stable.ts" && fail "false alarm for an unchanged file next to changed ones: $out" || ok
has "$out" "CHECKED 5 LINEREF_CHANGED 4 " && ok || fail "counters for many references: $(printf '%s' "$out" | tail -1)"
printf '# new\n`src/core/service.py:2`\n' >.ai/untracked.md
out="$(bash "$CHECK" .ai/untracked.md --root .)"
has "$out" "LINEREF_CHANGED .ai/untracked.md:2 src/core/service.py:2 (file changed in the working tree)" && ok || fail "untracked document: $out"
rm -f .ai/untracked.md
git checkout -q -- src/core/service.py

# --- repo without commits: git diff HEAD fails, same result as before
EMPTY="$TMP/empty"
mkdir -p "$EMPTY/lib" && (cd "$EMPTY" && git init -q && printf 'a\nb\n' >lib/x.rb && printf '# e\n`lib/x.rb:1`\n' >doc.md)
out="$(bash "$CHECK" "$EMPTY/doc.md" --root "$EMPTY")"
has "$out" "LINEREF_CHANGED doc.md:2 lib/x.rb:1 (file changed in the working tree)" && ok || fail "repo without commits: $out"

# --- --strict: code 1 only for RANGE, NOFILE, GONE
bash "$CHECK" .ai/content.md --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict with GONE"
printf '# m\n| Stop `stop()` | `src/core/service.py:4` |\n| x | `src/core/service.py:2` |\n' >.ai/soft.md && git add -A && git commit -qm soft
printf '# top\n' | cat - src/core/service.py >"$TMP/s" && mv "$TMP/s" src/core/service.py && git add -A && git commit -qm top
bash "$CHECK" .ai/soft.md --root . >/dev/null; [ $? -eq 1 ] && ok || fail "without strict MOVED and CHANGED give 1"
bash "$CHECK" .ai/soft.md --root . --strict >/dev/null; [ $? -eq 0 ] && ok || fail "strict with only MOVED and CHANGED"
bash "$CHECK" .ai/space.md --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict with RANGE"

# --- workspace and sessions directories are pruned at any depth
mkdir -p docs2/workspace/plans docs2/sessions docs2/sub/workspace/deep
for f in docs2/kept.md docs2/workspace/plans/p.md docs2/sessions/s.md docs2/sub/workspace/deep/w.md; do
  printf '# x\n`src/gone.rb:2`\n' >"$f"
done
out="$(bash "$CHECK" docs2 --root .)"
has "$out" "LINEREF_NOFILE docs2/kept.md:2" && ok || fail "document outside workspace skipped: $out"
printf '%s\n' "$out" | grep -qE 'workspace|sessions' && fail "document from workspace or sessions checked: $out" || ok
out="$(bash "$CHECK" docs2/workspace --root .)"
printf '%s\n' "$out" | grep -q 'LINEREF_NOFILE docs2' && fail "workspace directory given directly checked: $out" || ok
rm -rf docs2

# --- excluded docs paths: --exclude (repeatable, git pathspec globs) and the overlay
#     section "Excluded docs paths" in English and Polish; files outside the globs stay checked
mkdir -p docs3/external_services/other-repo/api docs3/external_services_notes docs3/ext/sub
printf '# o\n`src/other/client.go:1`\n' >docs3/external_services/other-repo/api/client.md
printf '# o\n`src/other/worker.go:1`\n' >docs3/external_services/other-repo/README.md
printf '# k\n`src/kept/ghost.go:1`\n' >docs3/kept.md
printf '# n\n`src/notes/ghost.go:1`\n' >docs3/external_services_notes/notes.md
printf '# t\n`src/ext/top.go:1`\n' >docs3/ext/top.md
printf '# d\n`src/ext/deep.go:1`\n' >docs3/ext/sub/deep.md
out="$(bash "$CHECK" docs3 --root . --exclude docs3/external_services/ --exclude 'docs3/ext/*.md' --strict)"; rc=$?
has "$out" "src/other/" && fail "document under an excluded directory checked: $out" || ok
has "$out" "src/ext/top.go" && fail "document matching the glob checked: $out" || ok
has "$out" "LINEREF_NOFILE docs3/kept.md:2 src/kept/ghost.go:1" && ok || fail "document outside the globs skipped: $out"
has "$out" "LINEREF_NOFILE docs3/external_services_notes/notes.md:2 src/notes/ghost.go:1" && ok || fail "directory glob hides a sibling with the same prefix: $out"
has "$out" "LINEREF_NOFILE docs3/ext/sub/deep.md:2 src/ext/deep.go:1" && ok || fail "* crosses a directory: $out"
has "$out" "CHECKED 3 LINEREF_CHANGED 0 LINEREF_RANGE 0 LINEREF_NOFILE 3 LINEREF_OK 0 LINEREF_MOVED 0 LINEREF_GONE 0 EXCLUDED 3" && [ "$rc" -eq 1 ] && ok || fail "counters with --exclude: $(printf '%s' "$out" | tail -1) (code $rc)"
out="$(bash "$CHECK" docs3 --root . --exclude '**/api/*.md')"
has "$out" "src/other/client.go" && fail "**/ glob does not exclude: $out" || ok
has "$out" "LINEREF_NOFILE docs3/external_services/other-repo/README.md:2 src/other/worker.go:1" && has "$out" "EXCLUDED 1" && ok || fail "**/ glob excludes too much: $out"
out="$(bash "$CHECK" docs3 --root . --exclude 'docs3/**' --strict)"; rc=$?
has "$out" "CHECKED 0 " && has "$out" "EXCLUDED 6" && [ "$rc" -eq 0 ] && ok || fail "everything excluded: $out (code $rc)"
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
  has "$out" "src/other/" && fail "$header: overlay glob does not exclude: $out" || ok
  has "$out" "LINEREF_NOFILE docs3/kept.md:2" && has "$out" "LINEREF_NOFILE docs3/external_services_notes/notes.md:2" && ok || fail "$header: item outside the section excludes: $out"
  has "$out" "CHECKED 3 " && has "$out" "LINEREF_NOFILE 3 " && has "$out" "EXCLUDED 3" && ok || fail "$header: counters with overlay: $(printf '%s' "$out" | tail -1)"
done
out="$(bash "$CHECK" docs3 --root . --exclude docs3/kept.md)"
has "$out" "src/kept/" && fail "--exclude next to the overlay ignored: $out" || ok
has "$out" "CHECKED 2 " && has "$out" "EXCLUDED 4" && ok || fail "overlay and --exclude together: $(printf '%s' "$out" | tail -1)"
bash "$CHECK" docs3 --root . --exclude >/dev/null; [ $? -eq 2 ] && ok || fail "--exclude without a glob: code 2"
rm -rf docs3 .ai/ov .ai/av.config.json

# --- references into directories ignored by git (dependencies, build output) are EXTERNAL
printf 'node_modules/\nbuild/\n' >.gitignore
mkdir -p node_modules/pkg docs4
for i in 1 2 3 4 5; do echo "line $i"; done >node_modules/pkg/index.js
printf '# i\n`node_modules/pkg/index.js:3`\n`build/out/app.js:10`\n`src/missing_file.go:1`\n' >.ai/ign.md
printf '# d\n`build/gen.js:2`\n' >docs4/guide.md
printf 'build/\n' >docs4/.gitignore
out="$(bash "$CHECK" .ai/ign.md docs4/guide.md --root .)"; rc=$?
has "$out" "EXTERNAL .ai/ign.md:2 node_modules/pkg/index.js:3" && ok || fail "existing file in an ignored directory is not EXTERNAL: $out"
has "$out" "EXTERNAL .ai/ign.md:3 build/out/app.js:10" && ok || fail "missing file in an ignored directory is not EXTERNAL: $out"
has "$out" "EXTERNAL docs4/guide.md:2 build/gen.js:2" && ok || fail "ignored path relative to the document is not EXTERNAL: $out"
has "$out" "LINEREF_NOFILE .ai/ign.md:4 src/missing_file.go:1" && ok || fail "missing file outside ignored directories is not NOFILE: $out"
printf '%s\n' "$out" | grep -E '^LINEREF_' | grep -qE 'node_modules|build/' && fail "ignored path reported as LINEREF_*: $out" || ok
has "$out" "CHECKED 4 LINEREF_CHANGED 0 LINEREF_RANGE 0 LINEREF_NOFILE 1 LINEREF_OK 0 LINEREF_MOVED 0 LINEREF_GONE 0 EXCLUDED 0 EXTERNAL 3 KNOWN 0" && [ "$rc" -eq 1 ] && ok || fail "counters with ignored paths: $(printf '%s' "$out" | tail -1) (code $rc)"
printf '# i\n`node_modules/pkg/index.js:3`\n`build/out/app.js:10`\n' >.ai/ign.md
bash "$CHECK" .ai/ign.md --root . --strict >/dev/null; [ $? -eq 0 ] && ok || fail "EXTERNAL changes the strict code"
bash "$CHECK" .ai/ign.md --root . >/dev/null; [ $? -eq 0 ] && ok || fail "EXTERNAL changes the code"
git add -f node_modules/pkg/index.js && git commit -qm "vendored file"
out="$(bash "$CHECK" .ai/ign.md --root .)"
has "$out" "EXTERNAL .ai/ign.md:2" && fail "tracked file in an ignored directory is EXTERNAL: $out" || ok

# --- known false paths in the overlay: <doc>:<line>, a path or glob, stale path entries
mkdir -p .ai/ov
printf '{"paths":{"overlays":".ai/ov"}}\n' >.ai/av.config.json
printf '# k\n`src/ghost/one.go:1`\n`gen/api/client.ts:4`\n`build/out/app.js:10`\n`src/core/stable.ts:1`\n`src/ghost/two.go:1`\n' >.ai/k.md
for header in "Known false paths" "Znane fałszywe ścieżki" "Znane falszywe sciezki"; do
  cat >.ai/ov/av-docs-sync.md <<MD
# Overlay
## Known false names
- \`src/ghost/two.go\`
## $header
- \`.ai/k.md:2\` - created by the installer
- \`gen/**\`
- \`build/out/app.js:10\`
- \`src/core/stable.ts\`
- \`.ai/k.md:5\`
- \`src/never/used.go\`
MD
  out="$(bash "$CHECK" .ai/k.md --root .)"; rc=$?
  printf '%s\n' "$out" | grep -qE '^(LINEREF_NOFILE|EXTERNAL) .ai/k.md:[234] ' && fail "$header: known reference reported: $out" || ok
  has "$out" "LINEREF_NOFILE .ai/k.md:6 src/ghost/two.go:1" && ok || fail "$header: reference outside the section ignored: $out"
  has "$out" "KNOWN_STALE src/core/stable.ts" && ok || fail "$header: existing path not stale: $out"
  printf '%s\n' "$out" | grep '^KNOWN_STALE' | grep -qE 'k.md|gen/|build/|never' && fail "$header: false stale entry: $out" || ok
  has "$out" "LINEREF_NOFILE 1 " && has "$out" "EXTERNAL 0 KNOWN 3" && [ "$rc" -eq 1 ] && ok || fail "$header: counters with known paths: $(printf '%s' "$out" | tail -1) (code $rc)"
done
rm -rf .ai/ov .ai/av.config.json .ai/k.md .ai/ign.md docs4 .gitignore

bash "$CHECK" >/dev/null; [ $? -eq 2 ] && ok || fail "no arguments"
printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

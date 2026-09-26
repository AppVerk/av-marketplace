#!/bin/bash
# Black box tests for check_refs.sh.
# Builds a small repo with a document full of edge cases and checks the output.
# Docs are English; lines in Polish check that Polish negation and "other repo" words still work.
set -u
CHECK="$(cd "$(dirname "$0")/.." && pwd)/scripts/check_refs.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

REPO="$TMP/repo with space"
mkdir -p "$REPO/src/modules/Orders_" "$REPO/.ai/modules" "$REPO/scripts" "$REPO/app/models/request"
cd "$REPO" || exit 1
git init -q
printf 'tmp/\n.ai/workspace/*\nlocal.env\n' >.gitignore
touch src/modules/Orders_/OrderList.ts scripts/run.sh .ai/README.md app/models/request/InvoiceParams.py
printf '{"dependencies":{"zone.js":"1"}}\n' >package.json

cat >.ai/modules/Orders.md <<'EOF'
# Orders

File exists: `src/modules/Orders_/OrderList.ts`.
Suffix from the source directory: `modules/Orders_/OrderList.ts:12-20`.
Relative link: [index](../README.md) and [script](../../scripts/run.sh).
Glob: `app/models/*Params.py`.
Absent: `src/modules/Orders_/RemovedList.ts`.
Link to a nonexistent file: [old](../old.md).
Bare name: `Ghost.kt`.
Placeholders: `docs/YYYY-MM-DD-topic.md`, `modules/Foo_/FooList.ts`, `<Name>/file.go`.
Package: `zone.js`. Branch: `feature/PROJ-1-x/`. Address: [page](https://example.com/a.md).
Ignored: `tmp/cache/state.lock`, `.ai/workspace/plans/plan.md`, `local.env/`.
File `lib/legacy/old.rb` was removed in PROJ-100.
Extension only: `.go`.

```sh
cat src/not_checked/InCodeBlock.py
```
EOF

cp .ai/modules/Orders.md "$TMP/with space.md"

# --- 1. output for a document in the repo
out="$(bash "$CHECK" .ai --root .)"; rc=$?
has "$out" "MISSING .ai/modules/Orders.md:7 src/modules/Orders_/RemovedList.ts" && ok || fail "no MISSING for a deleted file"
has "$out" "MISSING .ai/modules/Orders.md:8 ../old.md" && ok || fail "no MISSING for a dead link"
has "$out" "UNRESOLVED .ai/modules/Orders.md:9 Ghost.kt" && ok || fail "no UNRESOLVED for a bare name"
[ "$rc" -eq 1 ] && ok || fail "code $rc instead of 1"

# --- 2. no false alarms
for tok in OrderList.ts README.md run.sh Params.py YYYY Foo "<Name>" zone.js feature/ example.com tmp/cache .ai/workspace local.env legacy/old "Orders.md:14 " InCodeBlock; do
  printf '%s\n' "$out" | grep -E '^(MISSING|UNRESOLVED)' | grep -q -- "$tok" && fail "false alarm: $tok" || ok
done
has "$out" "MISSING 2 UNRESOLVED 1 EXTERNAL 0 WORKSPACE 1" && ok || fail "wrong counters: $(printf '%s' "$out" | tail -1)"

# --- 2b. Polish negation (with and without diacritics) also turns off the line
printf '# x\nPlik `src/gone/usuniety.py` został usunięty.\nPlik `src/gone/stary.py` zostal usuniety.\nNIGDY nie zapisuj do `.claude/plans/y.md`.\n' >"$TMP/pl.md"
out2="$(bash "$CHECK" "$TMP/pl.md" --root .)"
has "$out2" "MISSING 0" && ok || fail "Polish negation does not turn off the line: $out2"

# --- 2c. paths outside the repo, another repo, relative workspace, never, bare directory
mkdir -p "$TMP/sibling-repo/tests" "$REPO/.ai/workspace/board"
printf '# y\nTests: `../../sibling-repo/tests/`.\nFile: `../../ghost-repo/x.md`.\nIn the backend repository: `api/Orders/Bar.php`.\nNotes: `workspace/board/`.\nNEVER write to `.claude/plans/x.md`.\nDirectory `reports/`.\nW repozytorium backend: `api/Orders/Baz.php`.\n' >"$REPO/.ai/ext.md"
out3="$(bash "$CHECK" .ai/ext.md --root .)"
has "$out3" "EXTERNAL .ai/ext.md:3 ../../ghost-repo/x.md" && ok || fail "no EXTERNAL for a nonexistent repo"
has "$out3" "sibling-repo" && fail "existing sibling repo reported" || ok
has "$out3" "EXTERNAL .ai/ext.md:4 api/Orders/Bar.php" && ok || fail "line about another repo is not EXTERNAL"
has "$out3" "EXTERNAL .ai/ext.md:8 api/Orders/Baz.php" && ok || fail "Polish line about another repo is not EXTERNAL"
has "$out3" "MISSING 0 UNRESOLVED 0 EXTERNAL 3 WORKSPACE 0" && ok || fail "extra counters: $(printf '%s' "$out3" | tail -1)"
rm "$REPO/.ai/ext.md"

# --- 2e. negation "not in" / "nie w", ignoring by bare name
printf '# z\nEvents live in `src/events/`, not in `src/domain/event/`.\nZdarzenia leza w `src/events/`, nie w `src/domain/event/`.\nLocally: `local.env`.\n' >"$REPO/.ai/neg.md"
out5="$(bash "$CHECK" .ai/neg.md --root .)"
has "$out5" "MISSING 0 UNRESOLVED 0" && ok || fail "not in / basename: $out5"
rm "$REPO/.ai/neg.md"
printf '# w\nDecision missing, see `.ai/workspace/plans/p.md`.\nBrak decyzji, zobacz `.ai/workspace/plans/q.md`.\n' >"$REPO/.ai/negws.md"
out7="$(bash "$CHECK" .ai/negws.md --root .)"
has "$out7" "WORKSPACE .ai/negws.md:2 .ai/workspace/plans/p.md" && ok || fail "WORKSPACE on a line with negation: $out7"
has "$out7" "WORKSPACE .ai/negws.md:3 .ai/workspace/plans/q.md" && ok || fail "WORKSPACE on a line with Polish negation: $out7"
rm "$REPO/.ai/negws.md"
printf '# d\nWorking files live in `.ai/workspace/` and `.ai/workspace/plans/`.\n' >"$REPO/.ai/wsdir.md"
out8="$(bash "$CHECK" .ai/wsdir.md --root .)"
has "$out8" "WORKSPACE 0" && ok || fail "mention of the workspace directory reported: $(printf '%s' "$out8" | tail -1)"
rm "$REPO/.ai/wsdir.md"

# --- 2f. av-* script names and a bare name in the workspace README
mkdir -p "$REPO/.ai/workspace"
printf '# ws\n`gate.sh` saves evidence in `runs/`.\n' >"$REPO/.ai/workspace/README.md"
printf '# ws\nGates: `gate.sh`.\n' >"$REPO/.ai/gates.md"
out6="$(bash "$CHECK" .ai/gates.md .ai/workspace/README.md --root . --workspace .ai/workspace)"
has "$out6" "MISSING 0 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0" && ok || fail "av scripts and workspace README: $(printf '%s' "$out6" | tail -1)"
rm -f "$REPO/.ai/gates.md"

# --- 2g. shell variables in a path are placeholders like <x>; a real path on the same line is still checked
printf '# v\nPer environment: `config/$APP_ENV/app.yml`, `config/${APP_ENV}/app.yml`, `$ROOT/src/main.go`.\nLink: [cfg](config/$APP_ENV/app.yml). Next to it: `config/ghost/app.yml`.\n' >"$REPO/.ai/vars.md"
out9="$(bash "$CHECK" .ai/vars.md --root .)"; rc=$?
printf '%s\n' "$out9" | grep -q 'APP_ENV\|ROOT' && fail "shell variable path reported: $out9" || ok
has "$out9" "MISSING .ai/vars.md:3 config/ghost/app.yml" && ok || fail "real path next to a variable path not checked: $out9"
has "$out9" "CHECKED 1 MISSING 1 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0" && [ "$rc" -eq 1 ] && ok || fail "counters with shell variables: $(printf '%s' "$out9" | tail -1) (code $rc)"
rm "$REPO/.ai/vars.md"

# --- 2d. document given relative to --root from outside the repo directory
out4="$(cd "$TMP" && bash "$CHECK" .ai/modules/Orders.md --root "$REPO")"
has "$out4" "RemovedList.ts" && ok || fail "document path relative to --root"

# --- 3. file from outside the repo with a space in its name
out="$(bash "$CHECK" "$TMP/with space.md" --root .)"
has "$out" "src/modules/Orders_/RemovedList.ts" && ok || fail "file with a space not checked"

# --- 4. clean docs: code 0
mkdir -p "$TMP/clean"
printf '# ok\n`src/modules/Orders_/OrderList.ts`\n' >"$TMP/clean/ok.md"
out="$(bash "$CHECK" "$TMP/clean" --root .)"; rc=$?
has "$out" "MISSING 0" && [ "$rc" -eq 0 ] && ok || fail "clean docs: $out (code $rc)"

# --- 5. empty document list does not hang
out="$(bash "$CHECK" "$TMP/nope" --root . </dev/null 2>/dev/null)"; rc=$?
has "$out" "CHECKED 0" && [ "$rc" -eq 0 ] && ok || fail "empty list: $out"

# --- 5b. --strict: code 1 only with MISSING, the flag is not a path
printf '# u\nBare name: `Ghost.kt`. Other repo: `../../ghost-repo/x.md`.\n' >"$TMP/clean/soft.md"
out="$(bash "$CHECK" "$TMP/clean" --root . --strict 2>&1)"; rc=$?
has "$out" "MISSING 0 UNRESOLVED 1 EXTERNAL 1" && [ "$rc" -eq 0 ] && ok || fail "strict with UNRESOLVED and EXTERNAL: $out (code $rc)"
has "$out" "WARNING" && fail "--strict treated as a path" || ok
bash "$CHECK" .ai --root . --strict >/dev/null; [ $? -eq 1 ] && ok || fail "strict with MISSING"

# --- 5c. *.xcresult bundles without contents in the index; workspace and sessions pruned
#     Run.xcresult is a stack marker: check_refs.sh indexes *.xcresult bundles by name.
mkdir -p "$REPO/Results/Run.xcresult/Data" "$REPO/docs2/workspace/plans" "$REPO/docs2/sessions" "$REPO/docs2/sub/workspace/deep"
touch "$REPO/Results/Run.xcresult/Info.plist" "$REPO/Results/Run.xcresult/Data/Inside.plist"
printf '# r\nResult: `Results/Run.xcresult/`.\nInside: `Results/Run.xcresult/Data/Inside.plist`.\n' >"$REPO/docs2/kept.md"
for f in workspace/plans/p.md sessions/s.md sub/workspace/deep/w.md; do
  printf '# x\nGhost: `src/pruned/ghost.go`.\n' >"$REPO/docs2/$f"
done
out="$(bash "$CHECK" docs2 --root .)"
printf '%s\n' "$out" | grep -q 'MISSING docs2/kept.md:2' && fail "xcresult bundle not found: $out" || ok
has "$out" "MISSING docs2/kept.md:3 Results/Run.xcresult/Data/Inside.plist" && ok || fail "xcresult contents in the index: $out"
printf '%s\n' "$out" | grep -q 'pruned/ghost' && fail "document from workspace or sessions checked: $out" || ok
has "$out" "CHECKED 2 MISSING 1" && ok || fail "counters with pruning: $(printf '%s' "$out" | tail -1)"
out="$(bash "$CHECK" docs2/workspace --root .)"
has "$out" "CHECKED 0" && ok || fail "workspace directory given directly: $out"
rm -rf "$REPO/docs2" "$REPO/Results"

# --- 6. no arguments: code 2
bash "$CHECK" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "no arguments code $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

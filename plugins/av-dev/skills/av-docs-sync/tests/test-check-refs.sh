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

# --- 2d. "repository" alone is this repo: a deleted file stays MISSING (Symfony, Polish prose)
cat >"$REPO/.ai/repo.md" <<'EOF'
# r
Repository: `src/Repository/OrderRepository.php`.
In this repository: `src/Handler/Gone.php`.
W tym repozytorium: `src/Handler/Gone2.php`.
Konfiguracja repozytorium: `config/x.yml`.
See [OrderRepository](src/Repository/Gone3.php).
The repository class `src/Repository/Gone4.php` handles orders.
Repozytorium Doctrine: `src/Repository/Gone5.php`.
Bare: `src/gone6.ts`. In the backend repository: `api/Y.php`.
In the billing-service repository: `app/Api/X.php`.
W repozytorium billing-service: `app/Api/Y2.php`.
See the other repo: `lib/z.ts`.
Plik w innym repozytorium: `lib/w.ts`.
In the `billing-service` repository: `app/Api/Z.php`.
Sibling repo: `docs/q.md`.
Handler `src/Gone7.php`, see `lib/backend-repository/README.md`.
Set up per repo: `av-setup` writes `.ai/gone-config.json`.
EOF
out6="$(bash "$CHECK" .ai/repo.md --root . --strict)"; rc=$?
for t in src/Repository/OrderRepository.php src/Handler/Gone.php src/Handler/Gone2.php config/x.yml src/Repository/Gone3.php src/Repository/Gone4.php src/Repository/Gone5.php src/gone6.ts src/Gone7.php lib/backend-repository/README.md .ai/gone-config.json; do
  printf '%s\n' "$out6" | grep '^MISSING' | grep -qF -- "$t" && ok || fail "this repo, deleted file not MISSING: $t"
done
for t in api/Y.php app/Api/X.php app/Api/Y2.php lib/z.ts lib/w.ts app/Api/Z.php docs/q.md; do
  printf '%s\n' "$out6" | grep '^EXTERNAL' | grep -qF -- "$t" && ok || fail "another repo not EXTERNAL: $t"
done
has "$out6" "MISSING 11 UNRESOLVED 0 EXTERNAL 7" && [ "$rc" -eq 1 ] && ok || fail "repository words: counters or --strict: $(printf '%s' "$out6" | tail -1) (code $rc)"
rm "$REPO/.ai/repo.md"
SELF="$TMP/my-app"
mkdir -p "$SELF/.ai" && (cd "$SELF" && git init -q)
printf '# s
W repozytorium my-app: `src/gone.ts`.
In the MY-APP repository: `src/gone2.ts`.
In the other-app repository: `src/x.ts`.
' >"$SELF/.ai/self.md"
out7="$(bash "$CHECK" "$SELF/.ai/self.md" --root "$SELF")"
has "$out7" "MISSING 2 UNRESOLVED 0 EXTERNAL 1" && ok || fail "the name of this repo is not another repo: $out7"

# --- 2d2. review of PR #19 (#3): a component word before "repository" names another repo only
# after a preposition or as a label; a link text and a table repo column name a repo too
cat >"$REPO/.ai/repo2.md" <<'EOF'
# r2
The admin repository `src/Repository/AdminGone.php` handles admins.
The API repository `src/Repository/ApiGone.php` is cached.
Admin repository class: `src/Repository/Gone8.php`.
Repozytorium admina `src/Repository/AdminGone2.php` jest w kontenerze.
See [the admin repository](src/Repository/Gone9.php) docs.
In the [my-backend](https://example.com/my-backend) repository: `src/Remote1.php`.
Backend repository: `api/Q.php`.
See the api repo: `api/R.php`.
W repozytorium admina: `app/S.php`.

| Repo | File |
|---|---|
| my-backend | `src/Remote2.php` |
| [billing-service](https://example.com/billing) | `src/Remote3.php` |
| this | `src/GoneT.php` |
| - | `src/GoneU.php` |

| File | Note |
|---|---|
| `src/GoneV.php` | my-backend |
EOF
out8="$(bash "$CHECK" .ai/repo2.md --root .)"
for t in src/Repository/AdminGone.php src/Repository/ApiGone.php src/Repository/Gone8.php src/Repository/AdminGone2.php src/Repository/Gone9.php src/GoneT.php src/GoneU.php src/GoneV.php; do
  printf '%s\n' "$out8" | grep '^MISSING' | grep -qF -- "$t" && ok || fail "#3: this repo, deleted file not MISSING: $t: $out8"
done
for t in src/Remote1.php api/Q.php api/R.php app/S.php src/Remote2.php src/Remote3.php; do
  printf '%s\n' "$out8" | grep '^EXTERNAL' | grep -qF -- "$t" && ok || fail "#3: another repo not EXTERNAL: $t: $out8"
done
has "$out8" "MISSING 8 UNRESOLVED 0 EXTERNAL 6" && ok || fail "#3: counters: $(printf '%s' "$out8" | tail -1)"
printf '# r3\nIn the [my-backend](https://example.com/my-backend) repository: `src/Remote1.php`.\n\n| Repository | Path |\n|---|---|\n| my-backend | `src/Remote2.php` |\n' >"$REPO/.ai/repo3.md"
bash "$CHECK" .ai/repo3.md --root . --strict >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok || fail "#3: references to another repo fail --strict (code $rc)"
rm "$REPO/.ai/repo2.md" "$REPO/.ai/repo3.md"

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

# --- 2h. a dotfile after a directory is a path; a bare dotfile is still an extension mention
mkdir -p "$REPO/tools"
touch "$REPO/tools/.toolrc"
printf '# n\nVersion: `tools/.toolrc`. Ghost: `tools/.ghostrc` and `config/.env.example`. Extension: `.toolrc`.\n' >"$REPO/.ai/dot.md"
out10="$(bash "$CHECK" .ai/dot.md --root .)"; rc=$?
has "$out10" "MISSING .ai/dot.md:2 tools/.ghostrc" && ok || fail "dotfile after a directory not reported: $out10"
has "$out10" "MISSING .ai/dot.md:2 config/.env.example" && ok || fail "dotfile with a second extension not reported: $out10"
printf '%s\n' "$out10" | grep -q 'tools/.toolrc' && fail "existing dotfile reported: $out10" || ok
has "$out10" "CHECKED 3 MISSING 2 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0" && [ "$rc" -eq 1 ] && ok || fail "counters with dotfiles: $(printf '%s' "$out10" | tail -1) (code $rc)"
rm "$REPO/.ai/dot.md"

# --- 2i. every script shipped with the av-* skills is known, by bare name or by its path in the skills directory
printf '# s\nSlots: `scan.sh`, `config.sh`, `compose_container.sh`, `av-verify/scripts/gate.sh`, `scripts/adoption_diff.sh`. Unknown: `ghost_tool.sh`.\n' >"$REPO/.ai/avs.md"
out11="$(bash "$CHECK" .ai/avs.md --root .)"
has "$out11" "UNRESOLVED .ai/avs.md:2 ghost_tool.sh" && ok || fail "unknown bare script not reported: $out11"
has "$out11" "CHECKED 6 MISSING 0 UNRESOLVED 1 EXTERNAL 0 WORKSPACE 0" && ok || fail "counters with av scripts: $(printf '%s' "$out11" | tail -1)"
rm "$REPO/.ai/avs.md"

# --- 2j. negation applies only to the path near the negation word in the same sentence
cat >"$REPO/.ai/negnear.md" <<'MD'
# n
Setup: copy `config/app.example.yml` to the app directory; the legacy `scripts/old_setup.sh` was removed.
Copy `config/removed_defaults.yml` next to the app.
Run `scripts/bootstrap.sh` before the first build and read the notes on why the old importer was removed.
Nothing was removed. Copy `config/ghost.yml` first.
Plik `src/gone/stary_modul.py` zostal usuniety, a nowa konfiguracja modulu zamowien lezy teraz w `config/nowa.yml`.
MD
out12="$(bash "$CHECK" .ai/negnear.md --root .)"; rc=$?
has "$out12" "MISSING .ai/negnear.md:2 config/app.example.yml" && ok || fail "path in another clause than the negation skipped: $out12"
has "$out12" "old_setup.sh" && fail "path next to the negation reported: $out12" || ok
has "$out12" "MISSING .ai/negnear.md:3 config/removed_defaults.yml" && ok || fail "negation word inside a path turns off the path: $out12"
has "$out12" "MISSING .ai/negnear.md:4 scripts/bootstrap.sh" && ok || fail "negation far from the path turns it off: $out12"
has "$out12" "MISSING .ai/negnear.md:5 config/ghost.yml" && ok || fail "negation in the previous sentence turns off the path: $out12"
has "$out12" "stary_modul.py" && fail "Polish negation next to the path does not turn it off: $out12" || ok
has "$out12" "MISSING .ai/negnear.md:6 config/nowa.yml" && ok || fail "Polish line: path far from the negation skipped: $out12"
has "$out12" "CHECKED 5 MISSING 5 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0" && [ "$rc" -eq 1 ] && ok || fail "counters with narrow negation: $(printf '%s' "$out12" | tail -1) (code $rc)"
rm "$REPO/.ai/negnear.md"

# --- 2k. known false paths in the overlay: <doc>:<line> and a path or glob, stale entries
mkdir -p "$REPO/.ai/ov"
printf '{"paths":{"overlays":".ai/ov"}}\n' >"$REPO/.ai/av.config.json"
cat >"$REPO/.ai/known.md" <<'MD'
# k
Install creates `config/local.yml` and [env](../config/env.yml).
Generated: `generated/api/client.ts`.
Existing: `src/modules/Orders_/OrderList.ts`.
Real drift: `config/ghost.yml`.
In the backend repository: `api/Ghost.php`.
Bare: `Ghost.kt`.
MD
for header in "Known false paths" "Znane fałszywe ścieżki" "Znane falszywe sciezki"; do
  cat >"$REPO/.ai/ov/av-docs-sync.md" <<MD
# Overlay
## Known false names
- \`config/ghost.yml\`
## $header
- \`.ai/known.md:2\` - created by the installer
- \`generated/**\`
- \`api/Ghost.php\`
- \`Ghost.kt\`
- \`src/modules/Orders_/OrderList.ts\`
- \`.ai/known.md:4\`
- \`other/never_used.md\`
- \`.ai/not_checked.md:3\`
## Excluded docs paths
- \`.ai/unrelated/\`
MD
  out13="$(bash "$CHECK" .ai/known.md --root .)"; rc=$?
  printf '%s\n' "$out13" | grep -E '^(MISSING|UNRESOLVED|EXTERNAL)' | grep -qv 'config/ghost.yml' && fail "$header: known path reported: $out13" || ok
  has "$out13" "MISSING .ai/known.md:5 config/ghost.yml" && ok || fail "$header: path outside the section ignored: $out13"
  has "$out13" "KNOWN_STALE src/modules/Orders_/OrderList.ts" && ok || fail "$header: existing path not stale: $out13"
  has "$out13" "KNOWN_STALE .ai/known.md:4" && ok || fail "$header: line without a missing path not stale: $out13"
  for e in never_used ".ai/not_checked.md:3" ".ai/known.md:2" "generated/" "api/Ghost.php" "Ghost.kt"; do
    printf '%s\n' "$out13" | grep '^KNOWN_STALE' | grep -qF -- "$e" && fail "$header: false stale entry $e: $out13" || ok
  done
  has "$out13" "CHECKED 7 MISSING 1 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0 EXCLUDED 0 KNOWN 5" && [ "$rc" -eq 1 ] && ok || fail "$header: counters with known paths: $(printf '%s' "$out13" | tail -1) (code $rc)"
done
out13="$(bash "$CHECK" .ai/known.md --root . --strict)"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "known paths hide the real MISSING under --strict (code $rc)"
sed -i.bak '/config\/ghost.yml/d' "$REPO/.ai/known.md" && rm -f "$REPO/.ai/known.md.bak"
out13="$(bash "$CHECK" .ai/known.md --root . --strict)"; rc=$?
has "$out13" "MISSING 0" && has "$out13" "KNOWN 5" && [ "$rc" -eq 0 ] && ok || fail "only known paths and stale hints: code $rc, $out13"
rm -rf "$REPO/.ai/ov" "$REPO/.ai/av.config.json" "$REPO/.ai/known.md"
out13="$(bash "$CHECK" .ai/modules/Orders.md --root .)"
has "$out13" "EXCLUDED 0 KNOWN 0" && ok || fail "summary without the overlay: $out13"

# --- 2d. document given relative to --root from outside the repo directory
out4="$(cd "$TMP" && bash "$CHECK" .ai/modules/Orders.md --root "$REPO")"
has "$out4" "RemovedList.ts" && ok || fail "document path relative to --root"

# --- 3. file from outside the repo with a space in its name
out="$(bash "$CHECK" "$TMP/with space.md" --root .)"
has "$out" "src/modules/Orders_/RemovedList.ts" && ok || fail "file with a space not checked"
# a document outside the repo in a directory named like a .gitignore entry (tmp/): its paths
# are still checked (on Linux mktemp gives /tmp/tmp.X, which hid them)
mkdir -p "$TMP/tmp/build"
printf '# o\nGone: `src/modules/Orders_/RemovedList.ts`. Sibling: `../../ghost-repo/y.md`.\n' >"$TMP/tmp/build/out.md"
out="$(bash "$CHECK" "$TMP/tmp/build/out.md" --root .)"
has "$out" "MISSING $TMP/tmp/build/out.md:2 src/modules/Orders_/RemovedList.ts" && ok || fail "document outside the repo under tmp/: path skipped as ignored: $out"
has "$out" "EXTERNAL $TMP/tmp/build/out.md:2 ../../ghost-repo/y.md" && ok || fail "document outside the repo: ../ path is not EXTERNAL: $out"

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

# --- 5d. excluded docs paths: --exclude (repeatable, git pathspec globs) and the overlay
#     section "Excluded docs paths" in English and Polish; files outside the globs stay checked
mkdir -p docs3/external_services/other-repo/api docs3/external_services_notes docs3/ext/sub
printf '# o\nClient: `src/other/Client.go`.\n' >docs3/external_services/other-repo/api/client.md
printf '# o\nWorker: `src/other/Worker.go`.\n' >docs3/external_services/other-repo/README.md
printf '# k\nKept: `src/kept/Ghost.go`.\n' >docs3/kept.md
printf '# n\nNotes: `src/notes/Ghost.go`.\n' >docs3/external_services_notes/notes.md
printf '# t\nTop: `src/ext/Top.go`.\n' >docs3/ext/top.md
printf '# d\nDeep: `src/ext/Deep.go`.\n' >docs3/ext/sub/deep.md
out="$(bash "$CHECK" docs3 --root . --exclude docs3/external_services/ --exclude 'docs3/ext/*.md' --strict)"; rc=$?
has "$out" "src/other/" && fail "document under an excluded directory checked: $out" || ok
has "$out" "src/ext/Top.go" && fail "document matching the glob checked: $out" || ok
has "$out" "MISSING docs3/kept.md:2 src/kept/Ghost.go" && ok || fail "document outside the globs skipped: $out"
has "$out" "MISSING docs3/external_services_notes/notes.md:2 src/notes/Ghost.go" && ok || fail "directory glob hides a sibling with the same prefix: $out"
has "$out" "MISSING docs3/ext/sub/deep.md:2 src/ext/Deep.go" && ok || fail "* crosses a directory: $out"
has "$out" "CHECKED 3 MISSING 3 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0 EXCLUDED 3" && [ "$rc" -eq 1 ] && ok || fail "counters with --exclude: $(printf '%s' "$out" | tail -1) (code $rc)"
out="$(bash "$CHECK" docs3 --root . --exclude '**/api/*.md')"
has "$out" "src/other/Client.go" && fail "**/ glob does not exclude: $out" || ok
has "$out" "MISSING docs3/external_services/other-repo/README.md:2 src/other/Worker.go" && has "$out" "EXCLUDED 1" && ok || fail "**/ glob excludes too much: $out"
out="$(bash "$CHECK" docs3 --root . --exclude 'docs3/**')"; rc=$?
has "$out" "CHECKED 0 MISSING 0 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0 EXCLUDED 6" && [ "$rc" -eq 0 ] && ok || fail "everything excluded: $out (code $rc)"
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
  has "$out" "MISSING docs3/kept.md:2 src/kept/Ghost.go" && has "$out" "MISSING docs3/external_services_notes/notes.md:2" && ok || fail "$header: item outside the section excludes: $out"
  has "$out" "CHECKED 3 MISSING 3 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0 EXCLUDED 3" && ok || fail "$header: counters with overlay: $(printf '%s' "$out" | tail -1)"
done
out="$(bash "$CHECK" docs3 --root . --exclude docs3/kept.md)"
has "$out" "src/kept/" && fail "--exclude next to the overlay ignored: $out" || ok
has "$out" "CHECKED 2 MISSING 2 UNRESOLVED 0 EXTERNAL 0 WORKSPACE 0 EXCLUDED 4" && ok || fail "overlay and --exclude together: $(printf '%s' "$out" | tail -1)"
bash "$CHECK" docs3 --root . --exclude >/dev/null; [ $? -eq 2 ] && ok || fail "--exclude without a glob: code 2"
rm -rf docs3 .ai/ov .ai/av.config.json

# --- 6. no arguments: code 2
bash "$CHECK" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "no arguments code $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

#!/bin/bash
# Black box tests for docs_drift.sh, including repository side effects on every run.
set -u
CHECK="$(cd "$(dirname "$0")/../.." && pwd)/skills/docs-drift/scripts/docs_drift.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

REPO="$TMP/space dir/my-app"
mkdir -p "$REPO/src" "$REPO/docs/plans" "$TMP/plain"
cd "$REPO" || exit 1
git init -q
git config user.email docs-drift@example.test
git config user.name 'Docs Drift Tests'

# Capture status, worktrees and refs around every invocation, including usage errors.
run_check() {
  local label="$1" status_before worktrees_before refs_before
  shift
  status_before="$(git status --porcelain=v1 --untracked-files=all)"
  worktrees_before="$(git worktree list)"
  refs_before="$(git for-each-ref)"
  out="$(bash "$CHECK" "$@")"; rc=$?
  [ "$(git status --porcelain=v1 --untracked-files=all)" = "$status_before" ] && ok || fail "$label changed status"
  [ "$(git worktree list)" = "$worktrees_before" ] && ok || fail "$label changed worktrees"
  [ "$(git for-each-ref)" = "$refs_before" ] && ok || fail "$label changed refs"
}
new_count() {
  local actual
  actual="$(printf '%s\n' "$out" | awk 'NR == 1 { print $NF }')"
  [ "$actual" = "new=$1" ] && ok || fail "$2: expected new=$1, got $out"
}
no_legacy() {
  local token
  for token in src/legacy.py src/gone.py docs/plans; do
    has "$out" "$token" && fail "$1 reported $token" || ok
  done
}
commit_fixture() {
  git add -A && git -c core.hooksPath=/dev/null commit -qm "$1" || exit 1
}

# --- 1. A committed base with two pre-existing broken references.
printf 'def create_order(items):\n    return items\n' >src/orders.py
printf 'def keep_me():\n    return 1\n' >src/keep.py
cat >docs/api.md <<'EOF'
# API

Orders: `create_order` in `src/orders.py`.
Kept: `keep_me` at `src/keep.py:1`.
Legacy, in the my-app repository: `src/legacy.py`.
EOF
printf 'Old: `src/gone.py`.\n' >docs/żółć.md
printf 'Delete `src/orders.py`.\n' >docs/plans/p.md
printf '# Demo\nSee `docs/api.md`.\n' >README.md
printf 'NOTES.md\ndocs/generated/\n' >.gitignore
commit_fixture base
BASE="$(git rev-parse HEAD)"

# --- 2. Unchanged working tree: existing drift is not new drift.
run_check unchanged --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "unchanged exit $rc instead of 0"
printf '%s\n' "$out" | grep -Eq '^DOCS_DRIFT base=[0-9a-f]{12} head_hits=[0-9]+ base_hits=[0-9]+ new=0$' && ok || fail "unchanged header: $out"
printf '%s\n' "$out" | grep -q '^NEW ' && fail 'unchanged tree has NEW hits' || ok
has "$out" 'head_hits=2 base_hits=2' && ok || fail "unchanged hit counts: $out"
no_legacy unchanged

# Default discovery from a subdirectory and a symlink to the top level remain valid.
cd src || exit 1
run_check 'default root from subdirectory' --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "default subdirectory root exit $rc instead of 0"
new_count 0 'default root from subdirectory'
cd "$REPO" || exit 1
ln -s "$REPO" "$TMP/root-link"
run_check 'symlinked top-level root' --base "$BASE" --root "$TMP/root-link"
[ "$rc" -eq 0 ] && ok || fail "symlinked top-level root exit $rc instead of 0"
new_count 0 'symlinked top-level root'
rm "$TMP/root-link"

# Gitignored docs are outside the scope, even when they contain broken references.
mkdir -p docs/generated
printf 'Private: `src/private.py`.\n' >NOTES.md
printf 'Generated API: `QuxClient`.\n' >docs/generated/api.md
[ -z "$(git status --porcelain=v1 --untracked-files=all)" ] && ok || fail 'ignored docs changed status'
run_check 'gitignored docs' --base HEAD
[ "$rc" -eq 0 ] && ok || fail "gitignored docs exit $rc instead of 0"
new_count 0 'gitignored docs'
printf '%s\n' "$out" | grep -q '^NEW ' && fail 'gitignored docs have NEW hits' || ok
has "$out" 'head_hits=2 base_hits=2' && ok || fail "gitignored hit counts: $out"
rm NOTES.md docs/generated/api.md
rmdir docs/generated

# --- 3. A code rename and a renamed identifier break the old doc line.
git mv src/orders.py src/order_service.py
printf 'def place_order(items):\n    return items\n' >src/order_service.py
commit_fixture 'rename orders'
run_check 'code rename' --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "code rename exit $rc instead of 0"
has "$out" 'NEW MISSING docs/api.md:3 src/orders.py' && ok || fail 'no missing orders path'
has "$out" 'NEW NAME_MISSING docs/api.md:3 create_order' && ok || fail 'no missing create_order name'
new_count 2 'code rename'
no_legacy 'code rename'

# --- 4. Uncommitted docs are part of head.
printf 'Also `src/ghost.py`.\n' >>docs/api.md
run_check uncommitted --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "uncommitted exit $rc instead of 0"
has "$out" 'NEW MISSING docs/api.md:6 src/ghost.py' && ok || fail 'uncommitted doc reference was skipped'
new_count 3 uncommitted
no_legacy uncommitted
git checkout -- docs/api.md

# --- 5. Full base history lets the line checker detect a moved identifier.
printf '# header\ndef keep_me():\n    return 1\n' >src/keep.py
commit_fixture 'move keep_me line'
run_check 'moved citation' --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "moved citation exit $rc instead of 0"
has "$out" 'NEW LINEREF_MOVED docs/api.md:4 src/keep.py:1 -> src/keep.py:2' && ok || fail 'no moved keep_me citation'
has "$out" 'LINEREF_CHANGED' && fail 'moved citation was reported as changed' || ok
new_count 3 'moved citation'
no_legacy 'moved citation'

# --- 6. A doc rename maps baseline keys, but breaks its incoming README link.
git mv docs/api.md docs/reference.md
commit_fixture 'rename API docs'
run_check 'doc rename' --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "doc rename exit $rc instead of 0"
has "$out" 'NEW MISSING docs/reference.md:3 src/orders.py' && ok || fail 'renamed doc lost orders hit'
has "$out" 'NEW MISSING README.md:2 docs/api.md' && ok || fail 'README missing link was skipped'
new_count 4 'doc rename'
no_legacy 'doc rename'

# --- 7. NUL-delimited git output keeps non-ASCII rename names literal.
git mv docs/żółć.md docs/źdźbło.md
commit_fixture 'rename non-ASCII docs'
run_check 'non-ASCII rename' --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "non-ASCII rename exit $rc instead of 0"
new_count 4 'non-ASCII rename'
no_legacy 'non-ASCII rename'
first_new="$(printf '%s\n' "$out" | awk '/^NEW / { print; exit }')"

# --- 8. Cap output, not the total, and retain checker order.
run_check truncated --base "$BASE" --max 1
[ "$rc" -eq 0 ] && ok || fail "truncated exit $rc instead of 0"
new_count 4 truncated
[ "$(printf '%s\n' "$out" | awk '/^NEW / { n++ } END { print n+0 }')" -eq 1 ] && ok || fail 'max 1 did not print exactly one hit'
has "$out" 'TRUNCATED shown=1 total=4' && ok || fail 'no truncation line'
[ "$(printf '%s\n' "$out" | awk '/^NEW / { print; exit }')" = "$first_new" ] && ok || fail 'truncation changed the head hit order'

# --- 9. Invalid arguments and roots fail with a single stdout error line.
run_check 'invalid base' --base nosuchrev
[ "$rc" -eq 2 ] && ok || fail "invalid base exit $rc instead of 2"
[ "$out" = 'DOCS_DRIFT_ERROR base nosuchrev is not a commit' ] && ok || fail "invalid base error: $out"
run_check 'non-repository root' --base "$BASE" --root "$TMP/plain"
[ "$rc" -eq 2 ] && ok || fail "non-repository root exit $rc instead of 2"
[ "$out" = "DOCS_DRIFT_ERROR not a git repository: $TMP/plain" ] && ok || fail "non-repository error: $out"
run_check 'missing root' --base "$BASE" --root
[ "$rc" -eq 2 ] && [ "$out" = 'DOCS_DRIFT_ERROR --root needs a directory' ] && ok || fail "missing root: $rc $out"
run_check 'empty root' --base "$BASE" --root ''
[ "$rc" -eq 2 ] && [ "$out" = 'DOCS_DRIFT_ERROR --root needs a directory' ] && ok || fail "empty root: $rc $out"
run_check 'relative subdirectory root' --base "$BASE" --root src
[ "$rc" -eq 2 ] && [ "$out" = 'DOCS_DRIFT_ERROR not a git repository: src' ] && ok || fail "relative subdirectory root: $rc $out"
run_check 'absolute subdirectory root' --base "$BASE" --root "$REPO/src"
[ "$rc" -eq 2 ] && [ "$out" = "DOCS_DRIFT_ERROR not a git repository: $REPO/src" ] && ok || fail "absolute subdirectory root: $rc $out"
ln -s "$REPO/src" "$TMP/subdirectory-link"
run_check 'symlinked subdirectory root' --base "$BASE" --root "$TMP/subdirectory-link"
[ "$rc" -eq 2 ] && [ "$out" = "DOCS_DRIFT_ERROR not a git repository: $TMP/subdirectory-link" ] && ok || fail "symlinked subdirectory root: $rc $out"
rm "$TMP/subdirectory-link"
run_check 'invalid max' --base "$BASE" --max 0
[ "$rc" -eq 2 ] && ok || fail "max 0 exit $rc instead of 2"
[ "$out" = 'DOCS_DRIFT_ERROR --max needs a positive integer' ] && ok || fail "max 0 error: $out"
run_check 'missing max' --base "$BASE" --max
[ "$rc" -eq 2 ] && [ "$out" = 'DOCS_DRIFT_ERROR --max needs a positive integer' ] && ok || fail "missing max: $rc $out"
run_check 'missing base' --base
[ "$rc" -eq 2 ] && [ "$out" = 'DOCS_DRIFT_ERROR --base needs a revision' ] && ok || fail "missing base: $rc $out"
run_check 'no base'
[ "$rc" -eq 2 ] && [ "$out" = 'DOCS_DRIFT_ERROR --base needs a revision' ] && ok || fail "no base: $rc $out"
run_check 'unknown option' --base "$BASE" --unknown
[ "$rc" -eq 2 ] && [ "$out" = 'DOCS_DRIFT_ERROR unknown option --unknown' ] && ok || fail "unknown option: $rc $out"
run_check help --help
[ "$rc" -eq 0 ] && has "$out" 'docs_drift.sh --base REV [--root DIR] [--max N]' && ok || fail "help: $rc $out"

# --- 10. Side effects are asserted by run_check around every call above and below.
# A larger multiplicity makes every head occurrence of the same key new.
printf 'Legacy, in the my-app repository: `src/legacy.py`.\n' >>docs/reference.md
run_check multiplicity --base "$BASE"
new_count 6 multiplicity
[ "$(printf '%s\n' "$out" | awk '/^NEW MISSING docs\/reference.md:[0-9]+ src\/legacy.py$/ { n++ } END { print n+0 }')" -eq 2 ] && ok || fail 'a new key did not retain all head occurrences'
git checkout -- docs/reference.md

# Root paths with spaces and untracked docs are accepted; excluded docs stay excluded.
printf 'New: `src/phantom.py`.\n' >docs/untracked.md
mkdir -p docs/reviews docs/testing docs/superpowers
for doc in docs/plans/new.md docs/reviews/new.md docs/testing/new.md docs/superpowers/new.md CHANGELOG.md; do
  printf 'See `src/skip.py`.\n' >"$doc"
done
run_check 'explicit root and untracked docs' --base "$BASE" --root "$REPO"
[ "$rc" -eq 0 ] && ok || fail "explicit root exit $rc instead of 0"
has "$out" 'NEW MISSING docs/untracked.md:1 src/phantom.py' && ok || fail 'untracked doc was skipped'
has "$out" 'src/skip.py' && fail 'an excluded doc was checked' || ok
new_count 5 'explicit root and untracked docs'
rm docs/untracked.md docs/plans/new.md docs/reviews/new.md docs/testing/new.md docs/superpowers/new.md CHANGELOG.md

# Symlinked docs, including top-level doc directories, never expose external contents.
mkdir -p "$TMP/outside-docs"
printf 'Outside: `src/missing_secret_value.py` and `Sup3rS3cretIdent` and `src/hidden.py:99`.\n' >"$TMP/outside-docs/leak.md"
ln -s "$TMP/outside-docs/leak.md" docs/leak.md
ln -s reference.md docs/local.md
ln -s "$TMP/outside-docs/absent.md" docs/broken.md
ln -s "$TMP/outside-docs" docs/outside
ln -s "$TMP/outside-docs" doc
ln -s "$TMP/outside-docs" documentation
ln -s "$TMP/outside-docs/leak.md" LEAK.md
printf 'outside\n' >"$TMP/outside-docs/target.py"
ln -s "$TMP/outside-docs/target.py" src/linked.py
printf 'Citation: `src/linked.py:99`.\n' >docs/citation.md
run_check 'symlinked docs' --base "$BASE"
[ "$rc" -eq 0 ] && ok || fail "symlinked docs exit $rc instead of 0"
new_count 4 'symlinked docs'
for token in missing_secret_value Sup3rS3cretIdent hidden.py leak.md local.md broken.md LEAK.md; do
  has "$out" "$token" && fail "external doc content or symlink input leaked ($token): $out" || ok
done
rm docs/leak.md docs/local.md docs/broken.md docs/outside docs/citation.md doc documentation LEAK.md src/linked.py

# Root prefixes are literal, not shell glob patterns or regular expressions.
for parent in '[brackets]' 'star*' 'question?' 'regex.^$|&'; do
  literal_repo="$TMP/$parent/my-app"
  mkdir -p "$literal_repo/src" "$literal_repo/docs"
  cd "$literal_repo" || exit 1
  git init -q
  git config user.email docs-drift@example.test
  git config user.name 'Docs Drift Tests'
  printf 'value = 1\n' >src/stable.py
  printf 'Root: `src/rootgone.py`.\n' >README.md
  printf 'Existing: `stable.py` and `src/stable.py`.\nPath: `src/gone.py`.\nCitation: `src/stable.py:9`.\n' >docs/api.md
  commit_fixture 'literal root base'
  literal_base="$(git rev-parse HEAD)"
  run_check "unchanged literal root $parent" --base "$literal_base" --root "$literal_repo"
  [ "$rc" -eq 0 ] && ok || fail "literal root $parent exit $rc instead of 0: $out"
  has "$out" 'head_hits=3 base_hits=3' && ok || fail "literal root $parent hit counts: $out"
  new_count 0 "unchanged literal root $parent"
  printf '%s\n' "$out" | grep -q '^NEW ' && fail "literal root $parent has pre-existing NEW hits: $out" || ok

  printf 'New: `src/phantom.py`.\n' >>docs/api.md
  printf 'Root new: `src/another.py`.\n' >>README.md
  run_check "new drift under literal root $parent" --base "$literal_base" --root "$literal_repo"
  [ "$rc" -eq 0 ] && ok || fail "new drift under literal root $parent exit $rc instead of 0: $out"
  has "$out" 'NEW MISSING docs/api.md:4 src/phantom.py' && ok || fail "literal root $parent lost nested doc hit: $out"
  has "$out" 'NEW MISSING README.md:2 src/another.py' && ok || fail "literal root $parent lost root doc hit: $out"
  new_count 2 "new drift under literal root $parent"
  for token in rootgone.py gone.py stable.py; do
    has "$out" "$token" && fail "literal root $parent reported pre-existing or valid reference $token: $out" || ok
  done
done
cd "$REPO" || exit 1

# Trees without any doc inputs have no hits and need no checker invocations.
git rm -qr docs README.md
commit_fixture 'remove docs'
EMPTY="$(git rev-parse HEAD)"
run_check 'no docs' --base "$EMPTY"
[ "$rc" -eq 0 ] && ok || fail "no docs exit $rc instead of 0"
[ "$out" = "DOCS_DRIFT base=${EMPTY:0:12} head_hits=0 base_hits=0 new=0" ] && ok || fail "no docs: $out"

printf 'PASS %s FAIL %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

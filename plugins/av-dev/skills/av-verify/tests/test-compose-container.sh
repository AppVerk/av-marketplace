#!/bin/bash
# Black-box tests for compose_container.sh with a fake docker binary.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$DIR/scripts/compose_container.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

# Physical layout: real/ holds the checkouts, link -> real is the logical path.
REAL="$(cd "$TMP" && pwd -P)/real"
LINK="$(cd "$TMP" && pwd -P)/link"
REPO="$REAL/repo one"
OTHER="$REAL/repo two"
mkdir -p "$REPO/docker" "$REPO/src" "$OTHER" "$REAL/repo one-copy"
ln -s "$REAL" "$LINK"
for r in "$REPO" "$OTHER"; do
  git -C "$r" init -q
done

# Fake docker: canned rows "service<TAB>name<TAB>id<TAB>working_dir" in $FAKE_PS,
# answers `docker ps` for the service from the label filter, logs its arguments.
FAKE="$TMP/bin/docker"
mkdir -p "$TMP/bin"
cat >"$FAKE" <<'FAKE_EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_LOG"
if [ -n "${FAKE_DOWN:-}" ]; then
  echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock" >&2
  exit 1
fi
[ "${1:-}" = "ps" ] || { echo "unexpected command: $*" >&2; exit 9; }
svc=""
while [ $# -gt 0 ]; do
  case "$1" in
    --filter) case "$2" in label=com.docker.compose.service=*) svc="${2#label=com.docker.compose.service=}" ;; esac; shift ;;
  esac
  shift
done
[ -n "$svc" ] || { echo "no service filter" >&2; exit 9; }
awk -F '\t' -v s="$svc" '$1 == s { printf "%s\t%s\t%s\n", $2, $3, $4 }' "$FAKE_PS"
FAKE_EOF
chmod +x "$FAKE"
export AV_DOCKER_BIN="$FAKE"
export FAKE_LOG="$TMP/docker.log"
export FAKE_PS="$TMP/ps.tsv"
T="$(printf '\t')"

rows() { printf '%s\n' "$@" >"$FAKE_PS"; : >"$FAKE_LOG"; }
run() { OUT="$(bash "$SCRIPT" "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"; }

# --- 1. match by the repo root; other checkout and other service ignored
rows "app${T}other_app_1${T}aaa111${T}$OTHER" \
     "app${T}one_app_1${T}bbb222${T}$REPO" \
     "db${T}one_db_1${T}ccc333${T}$REPO"
run --root "$REPO" app
[ "$RC" -eq 0 ] && ok || fail "root: code $RC ($ERR)"
[ "$OUT" = "bbb222" ] && ok || fail "root: got '$OUT'"
[ -z "$ERR" ] && ok || fail "root: unexpected stderr '$ERR'"
has "$(cat "$FAKE_LOG")" "ps --filter label=com.docker.compose.service=app" && ok || fail "root: docker ps filter missing"
run --root "$REPO" db
[ "$OUT" = "ccc333" ] && ok || fail "service db: got '$OUT'"

# --- 2. default root = repo of the current directory, also from a subdirectory
OUT="$(cd "$REPO/src" && bash "$SCRIPT" app 2>/dev/null)"
[ "$OUT" = "bbb222" ] && ok || fail "default root from subdir: got '$OUT'"

# --- 3. physical path: root given through the symlink, label physical
run --root "$LINK/repo one" app
[ "$RC" -eq 0 ] && [ "$OUT" = "bbb222" ] && ok || fail "physical label, logical root: code $RC out '$OUT'"

# --- 4. logical path: label through the symlink, root physical and logical
rows "app${T}one_app_1${T}ddd444${T}$LINK/repo one"
run --root "$REPO" app
[ "$RC" -eq 0 ] && [ "$OUT" = "ddd444" ] && ok || fail "logical label, physical root: code $RC out '$OUT'"
run --root "$LINK/repo one" app
[ "$RC" -eq 0 ] && [ "$OUT" = "ddd444" ] && ok || fail "logical label, logical root: code $RC out '$OUT'"

# --- 5. label of a gone directory still matches by string (logical form)
rows "app${T}one_app_1${T}eee555${T}$LINK/repo one/gone/"
run --root "$LINK/repo one" app
[ "$OUT" = "eee555" ] && ok || fail "missing dir with trailing slash: got '$OUT'"

# --- 6. compose files in a subdirectory
rows "app${T}one_app_1${T}fff666${T}$REPO/docker"
run --root "$REPO" app
[ "$RC" -eq 0 ] && [ "$OUT" = "fff666" ] && ok || fail "subdirectory: code $RC out '$OUT'"

# --- 7. only other checkouts (incl. a sibling with the same prefix): no match -> 2
rows "app${T}other_app_1${T}aaa111${T}$OTHER" \
     "app${T}copy_app_1${T}ggg777${T}$REAL/repo one-copy" \
     "app${T}root_app_1${T}hhh888${T}$REAL"
run --root "$REPO" app
[ "$RC" -eq 2 ] && ok || fail "other checkout: code $RC, expected 2"
[ -z "$OUT" ] && ok || fail "other checkout: stdout '$OUT'"
has "$ERR" "no running container of service 'app'" && ok || fail "other checkout: reason missing ($ERR)"

# --- 8. no container at all -> 2
rows ""
run --root "$REPO" app
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && ok || fail "no container: code $RC out '$OUT'"

# --- 9. two matches: first by name and a WARNING
rows "app${T}one_app_2${T}iii999${T}$REPO" \
     "app${T}other_app_1${T}aaa111${T}$OTHER" \
     "app${T}one_app_1${T}jjj000${T}$REPO/docker"
run --root "$REPO" app
[ "$RC" -eq 0 ] && ok || fail "two matches: code $RC"
[ "$OUT" = "jjj000" ] && ok || fail "two matches: got '$OUT', expected first by name"
has "$ERR" "WARNING 2 containers of service app" && ok || fail "two matches: WARNING missing ($ERR)"
has "$ERR" "one_app_1, one_app_2" && ok || fail "two matches: names missing ($ERR)"
has "$ERR" "other_app_1" && fail "two matches: other checkout listed" || ok

# --- 10. daemon not reachable -> 2 with a reason
rows "app${T}one_app_1${T}bbb222${T}$REPO"
OUT="$(FAKE_DOWN=1 bash "$SCRIPT" --root "$REPO" app 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && ok || fail "daemon down: code $RC out '$OUT'"
has "$ERR" "Cannot connect to the Docker daemon" && ok || fail "daemon down: reason missing ($ERR)"

# --- 11. docker CLI missing -> 2 with a reason
OUT="$(AV_DOCKER_BIN="$TMP/bin/no-docker" bash "$SCRIPT" --root "$REPO" app 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && ok || fail "docker missing: code $RC out '$OUT'"
has "$ERR" "Docker CLI not found" && ok || fail "docker missing: reason missing ($ERR)"

# --- 12. bad invocation -> 2; help prints the header
run --root "$REPO"
[ "$RC" -eq 2 ] && has "$ERR" "service missing" && ok || fail "no service: code $RC ($ERR)"
run --root "$REPO" app db
[ "$RC" -eq 2 ] && ok || fail "two services: code $RC"
run --root "$TMP/nowhere" app
[ "$RC" -eq 2 ] && ok || fail "missing root: code $RC"
run --help
[ "$RC" -eq 0 ] && has "$OUT" "Usage:" && has "$OUT" "Requires:" && ok || fail "help: code $RC"

# --- 13. read-only: every docker call was `ps`
rows "app${T}one_app_1${T}bbb222${T}$REPO"
run --root "$REPO" app
awk '$1 != "ps"' "$FAKE_LOG" | grep -q . && fail "read-only: non-ps docker call" || ok

# --- 14. a worktree under the root is another checkout (review of PR #19, point 5)
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$REPO/.claude/worktrees/w1" -b w1 2>/dev/null
WT="$REPO/.claude/worktrees/w1"
[ -d "$WT" ] && ok || fail "setup: worktree not created"
rows "app${T}wt_app_1${T}kkk111${T}$WT"
run --root "$REPO" app
[ "$RC" -eq 2 ] && [ -z "$OUT" ] && ok || fail "only the worktree container: code $RC out '$OUT', expected 2"
has "$ERR" "no running container of service 'app'" && ok || fail "only the worktree container: reason missing ($ERR)"
rows "app${T}a_wt_app_1${T}kkk111${T}$WT/docker" "app${T}one_app_1${T}bbb222${T}$REPO"
run --root "$REPO" app
[ "$RC" -eq 0 ] && [ "$OUT" = "bbb222" ] && ok || fail "worktree and this checkout: code $RC out '$OUT'"
[ -z "$ERR" ] && ok || fail "worktree and this checkout: unexpected WARNING '$ERR'"
rows "app${T}wt_app_1${T}kkk111${T}$LINK/repo one/.claude/worktrees/w1/"
run --root "$REPO" app
[ "$RC" -eq 2 ] && ok || fail "worktree through the symlink with a trailing slash: code $RC out '$OUT'"
run --root "$WT" app
[ "$RC" -eq 0 ] && [ "$OUT" = "kkk111" ] && ok || fail "from the worktree itself its own container counts: code $RC out '$OUT'"
rows "app${T}one_app_1${T}bbb222${T}$REPO"
run --root "$WT" app
[ "$RC" -eq 2 ] && ok || fail "from the worktree the main checkout container must not count: code $RC out '$OUT'"

# --- 15. a worktree that is gone but still registered, and one under a gone path
git -C "$REPO" worktree add -q "$REPO/.worktrees/w2" -b w2 2>/dev/null
rm -rf "$REPO/.worktrees/w2"
rows "app${T}w2_app_1${T}lll222${T}$REPO/.worktrees/w2" "app${T}w2_db${T}lll333${T}$REPO/.worktrees/w2/docker"
run --root "$REPO" app
[ "$RC" -eq 2 ] && ok || fail "gone registered worktree: code $RC out '$OUT'"

# --- 16. a nested repo or submodule under the root, existing and gone subdirectory
mkdir -p "$REPO/vendor/lib/docker"
git -C "$REPO/vendor/lib" init -q
rows "app${T}lib_app_1${T}mmm111${T}$REPO/vendor/lib/docker"
run --root "$REPO" app
[ "$RC" -eq 2 ] && ok || fail "nested repo: code $RC out '$OUT'"
rows "app${T}lib_app_1${T}mmm222${T}$REPO/vendor/lib/gone"
run --root "$REPO" app
[ "$RC" -eq 2 ] && ok || fail "gone directory in a nested repo: code $RC out '$OUT'"
rows "app${T}lib_app_1${T}mmm333${T}$REPO/vendor/lib"
run --root "$REPO" app
[ "$RC" -eq 2 ] && ok || fail "nested repo root: code $RC out '$OUT'"

mkdir -p "$REPO/moved/lib"
printf 'gitdir: %s/nowhere/.git/modules/lib
' "$TMP" >"$REPO/moved/lib/.git"
rows "app${T}moved_app_1${T}mmm444${T}$REPO/moved/lib"
run --root "$REPO" app
[ "$RC" -eq 2 ] && ok || fail "nested repo with a broken .git file: code $RC out '$OUT'"

# --- 17. a plain subdirectory of this checkout still counts, also a gitignored one
printf 'ignored/\n' >"$REPO/.gitignore"
mkdir -p "$REPO/ignored/compose"
rows "app${T}one_app_1${T}nnn111${T}$REPO/ignored/compose"
run --root "$REPO" app
[ "$RC" -eq 0 ] && [ "$OUT" = "nnn111" ] && ok || fail "gitignored subdirectory: code $RC out '$OUT'"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

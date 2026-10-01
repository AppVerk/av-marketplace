#!/bin/bash
# Black-box tests for run_scope.sh: a snapshot before a run, the run's own changes measured
# against it (also inside files that were already modified), and the foreign changes.
# Review of PR #19: av-review --run must not skip the run's edits in files modified before the start.
set -u
SCOPE="$(cd "$(dirname "$0")/.." && pwd)/scripts/run_scope.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { printf '%s' "$1" | grep -qF -- "$2"; }

REPO="$TMP/repo with space"
mkdir -p "$REPO/.ai" "$REPO/src"
cd "$REPO" || exit 1
git init -q
git config user.email t@t
git config user.name t
printf '.ai/workspace/\nsecret.env\n' >.gitignore
printf 'line a1\n' >src/a.txt
printf 'line b1\n' >src/b.txt
printf 'line c1\n' >src/c.txt
printf '{"version":1,"paths":{"workspace":".ai/workspace"}}\n' >.ai/av.config.json
git add -A && git commit -qm init

# --- 1. argument validation
out="$(bash "$SCOPE" --root . snapshot)"; rc=$?
has "$out" "ERROR --run-id is required" && [ "$rc" -eq 2 ] && ok || fail "missing run id ($rc): $out"
out="$(bash "$SCOPE" --root . snapshot --run-id ../x)"; rc=$?
has "$out" "ERROR --run-id must use" && [ "$rc" -eq 2 ] && ok || fail "run id with ..: $rc $out"
out="$(bash "$SCOPE" --root . diff --run-id none)"; rc=$?
has "$out" "ERROR no snapshot for run none" && [ "$rc" -eq 2 ] && ok || fail "diff without a snapshot ($rc): $out"

# --- 2. a dirty tree before the run: a person's edit in b.txt, an untracked u.txt, an ignored file
printf 'line b1\nperson edit\n' >src/b.txt
printf 'untracked before\n' >src/u.txt
printf 'TOKEN=x\n' >secret.env
mkdir -p .ai/workspace/runs/other && printf 'junk\n' >.ai/workspace/runs/other/x.txt
out="$(bash "$SCOPE" --root . snapshot --run-id r1)"; rc=$?
has "$out" "SNAPSHOT " && has "$out" "foreign=2" && [ "$rc" -eq 0 ] && ok || fail "snapshot ($rc): $out"
[ -f .ai/workspace/runs/r1/baseline.tree ] && [ -f .ai/workspace/runs/r1/baseline.head ] && [ -f .ai/workspace/runs/r1/baseline.patch ] && ok || fail "snapshot files missing"
grep -q 'person edit' .ai/workspace/runs/r1/baseline.patch && grep -q 'untracked before' .ai/workspace/runs/r1/baseline.patch && ok || fail "baseline.patch does not hold the foreign changes"
grep -q 'TOKEN=x' .ai/workspace/runs/r1/baseline.patch && fail "an ignored file went into the snapshot" || ok
grep -q 'junk' .ai/workspace/runs/r1/baseline.patch && fail "the workspace went into the snapshot" || ok
out="$(bash "$SCOPE" --root . snapshot --run-id r1)"; rc=$?
has "$out" "ERROR a snapshot of run r1 exists" && [ "$rc" -eq 3 ] && ok || fail "second snapshot not refused ($rc): $out"

# --- 3. nothing changed yet: the run's diff is empty, the foreign diff lists b.txt and u.txt
out="$(bash "$SCOPE" --root . diff --run-id r1)"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok || fail "diff before any run change is not empty ($rc): $out"
out="$(bash "$SCOPE" --root . foreign --run-id r1 --name-only)"; rc=$?
[ "$out" = "$(printf 'src/b.txt\nsrc/u.txt')" ] && [ "$rc" -eq 0 ] && ok || fail "foreign --name-only ($rc): $out"
out="$(bash "$SCOPE" --root . foreign --run-id r1)"
has "$out" "+person edit" && ok || fail "foreign patch misses the person's edit"

# --- 4. the run edits b.txt (already modified), a.txt, adds n.txt, deletes c.txt, leaves u.txt
printf 'line b1\nperson edit\nrun edit\n' >src/b.txt
printf 'line a1\nrun a2\n' >src/a.txt
printf 'new by run\n' >src/n.txt
rm src/c.txt
out="$(bash "$SCOPE" --root . diff --run-id r1 --name-only)"; rc=$?
[ "$out" = "$(printf 'src/a.txt\nsrc/b.txt\nsrc/c.txt\nsrc/n.txt')" ] && [ "$rc" -eq 0 ] && ok || fail "diff --name-only ($rc): $out"
out="$(bash "$SCOPE" --root . diff --run-id r1)"
has "$out" "+run edit" && ok || fail "the run's edit in the already modified file is missing"
has "$out" "+person edit" && fail "the person's earlier edit counts as a run change" || ok
has "$out" "+run a2" && has "$out" "+new by run" && ok || fail "run changes in a.txt or n.txt missing"
has "$out" "-line c1" && ok || fail "the deleted file is not in the run diff"
has "$out" "untracked before" && fail "an untouched untracked file is in the run diff" || ok
out="$(bash "$SCOPE" --root . foreign --run-id r1 --name-only)"
[ "$out" = "$(printf 'src/b.txt\nsrc/u.txt')" ] && ok || fail "foreign changed after the run: $out"

# --- 5. the run also edits the untracked file from before: only the new line is the run's
printf 'untracked before\nrun line in u\n' >src/u.txt
out="$(bash "$SCOPE" --root . diff --run-id r1)"
has "$out" "+run line in u" && ok || fail "run edit in a pre-existing untracked file missing"
has "$out" "+untracked before" && fail "the pre-existing content of u.txt counts as a run change" || ok

# --- 6. --force replaces the snapshot, so the run's diff is empty again; runs dir from the config
cp .ai/av.config.json "$TMP/cfg.json"
jq '.paths.runs = ".ai/workspace/other-runs"' "$TMP/cfg.json" >.ai/av.config.json
out="$(bash "$SCOPE" --root . snapshot --run-id r1 --force)"; rc=$?
[ "$rc" -eq 0 ] && [ -f .ai/workspace/other-runs/r1/baseline.tree ] && ok || fail "--force with paths.runs from the config ($rc): $out"
out="$(bash "$SCOPE" --root . diff --run-id r1)"
[ -z "$out" ] && ok || fail "diff after --force is not empty: $out"
cp "$TMP/cfg.json" .ai/av.config.json
out="$(bash "$SCOPE" --root . --runs-dir "$TMP/elsewhere" snapshot --run-id r2)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$TMP/elsewhere/r2/baseline.tree" ] && ok || fail "--runs-dir outside the repo ($rc): $out"

# --- 7. from a subdirectory and from a path with --root
cd src || exit 1
out="$(bash "$SCOPE" diff --run-id r1 --name-only)"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "diff from a subdirectory ($rc): $out"
cd "$REPO" || exit 1
out="$(bash "$SCOPE" --root "$TMP" snapshot --run-id r3)"; rc=$?
has "$out" "is not inside a git repository" && [ "$rc" -eq 2 ] && ok || fail "root outside git ($rc): $out"

# --- 8. a repo without a commit
EMPTY="$TMP/empty"; mkdir -p "$EMPTY" && git -C "$EMPTY" init -q
out="$(bash "$SCOPE" --root "$EMPTY" snapshot --run-id r1)"; rc=$?
has "$out" "HEAD has no commit" && [ "$rc" -eq 2 ] && ok || fail "no commit ($rc): $out"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

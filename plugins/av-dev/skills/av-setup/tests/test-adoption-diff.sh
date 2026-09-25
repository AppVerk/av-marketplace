#!/bin/bash
# Black box tests for adoption_diff.sh.
# Builds a repo with an old setup (agent, command), deletes it and compares with the new one.
set -u
AD="$(cd "$(dirname "$0")/.." && pwd)/scripts/adoption_diff.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { grep -qF -- "$2" "$1" && ok || fail "$3"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$3" || ok; }

R="$TMP/repo"
git init -q "$R" && git -C "$R" config user.email t@t && git -C "$R" config user.name t
mkdir -p "$R/.claude/agents" "$R/.claude/commands" "$R/.ai/overlays" "$R/.ai/workspace/plans" "$R/scripts"
cat >"$R/.claude/agents/reviewer.md" <<'EOF'
# reviewer
Run `scripts/lint.sh` before review.
Findings category `ui-convention` and `layers`.
Save evidence in `.ai/workspace/runs/RUN_ID/review.md`.
Hand over to `old-implementer` via `$ARGUMENTS`.
Short `ab` is not a token.
```sh
echo `ignored` in a block
```
Status `REVIEW_OK` from `pipeline_state.py`.
EOF
printf '# plan\nSection `DATA_CONTRACT` in the plan. Again `layers`.\n' >"$R/.claude/commands/feature plan.md"
printf '#!/bin/bash\n' >"$R/scripts/lint.sh"
printf '# CLAUDE\nSee `.ai/overlays`.\n' >"$R/CLAUDE.md"
printf '## Required plan sections\n- DATA_CONTRACT: response fields\n' >"$R/.ai/overlays/av-plan.md"
printf '## How to check the axes\nlint: scripts/lint.sh; axis layers\n' >"$R/.ai/overlays/av-review.md"
printf 'ui-convention REVIEW_OK\n' >"$R/.ai/workspace/plans/2026-01-01-av-setup.md"
git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" rm -q ".claude/agents/reviewer.md" ".claude/commands/feature plan.md"

# MARK: files deleted since a revision
out="$TMP/out.txt"
bash "$AD" --root "$R" --old-rev HEAD --deleted --new CLAUDE.md .ai --noise 'old\.implementer|old-implementer' >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "code 1 with LOST: $rc"
has "$out" "LOST .claude/agents/reviewer.md ui-convention" "token only in workspace is LOST"
has "$out" "LOST .claude/agents/reviewer.md REVIEW_OK" "status without a trace"
hasnt "$out" "scripts/lint.sh" "token present in an overlay"
hasnt "$out" "LOST .claude/agents/reviewer.md layers" "token present in the new setup"
hasnt "$out" "DATA_CONTRACT" "token from a file with a space present"
hasnt "$out" "RUN_ID" "filter RUN_ID"
hasnt "$out" "ARGUMENTS" "filter ARGUMENTS"
hasnt "$out" "old-implementer" "filter --noise"
hasnt "$out" "pipeline_state" "filter pipeline_state"
hasnt "$out" " ab" "token shorter than 3 characters"
hasnt "$out" "ignored" "fence lines skipped"
has "$out" "TOKENS 9 LOST 2 FILTERED 4" "summary"

# MARK: files from the tree
printf 'Rule `KEEP_ME` and `scripts/lint.sh`.\n' >"$R/old.md"
bash "$AD" --root "$R" --old old.md --new CLAUDE.md .ai >"$out"; rc=$?
has "$out" "LOST old.md KEEP_ME" "file from the tree"
has "$out" "TOKENS 2 LOST 1 FILTERED 0" "summary of a file from the tree"
bash "$AD" --root "$R" --old old.md --new CLAUDE.md .ai old.md >"$out"
has "$out" "LOST old.md KEEP_ME" "old file is not corpus"
printf 'KEEP_ME\n' >>"$R/.ai/overlays/av-plan.md"
bash "$AD" --root "$R" --old old.md --new CLAUDE.md .ai >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "code 0 without LOST: $rc"
has "$out" "TOKENS 2 LOST 0 FILTERED 0" "everything moved"

# MARK: usage
bash "$AD" --root "$R" --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "no old files: code $rc"
bash "$AD" --root "$R" --deleted --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "--deleted without --old-rev: code $rc"
bash "$AD" --root "$R" --old old.md >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "missing --new: code $rc"
bash "$AD" --root "$R" --old-rev missing --deleted --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "bad revision: code $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

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

# MARK: orchestration filter
cat >"$R/handoff.md" <<'EOF'
# handoff
Start with `MODE=fix` and `STATUS=DONE|BLOCKED`, also `SCOPE=all ROUND=2`.
Report `STATUS` and `CHANGED_FILES`, then read `NEXT_AGENT` and `RETRY_COUNT`.
Set RETRY_COUNT=3 before the loop.
```text
- NEXT_AGENT: reviewer
```
Templates: `{entity}`, `src/<Module>/Service.php`, `make <target>`.
Placeholders: `XController.php`, `FooService*`, `ExampleTest.py`, `src/foo.ts`, `XxxRepository.kt`.
Keep: `APP_DIR=/opt/app`, `Request<T>`, `${HOME}/bin/tool`, `src/*.{ts,js}`, `XCTest`, `.env.example`.
Keep: `KEEP_RULE`, `BUILD_DIR=out npm run build`, `src/Foodstuff.go`.
EOF
bash "$AD" --root "$R" --old handoff.md --new CLAUDE.md .ai >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "code 1 with LOST after filtering: $rc"
for tok in "MODE=fix" "STATUS=DONE" "SCOPE=all" "STATUS" "CHANGED_FILES" "NEXT_AGENT" "RETRY_COUNT" "{entity}" "<Module>" "<target>" \
  "XController" "FooService" "ExampleTest" "src/foo.ts" "XxxRepository"; do
  hasnt "$out" "$tok" "orchestration token filtered: $tok"
done
for tok in "APP_DIR=/opt/app" "Request<T>" '${HOME}/bin/tool' "src/*.{ts,js}" "XCTest" ".env.example" "KEEP_RULE" \
  "BUILD_DIR=out npm run build" "src/Foodstuff.go"; do
  has "$out" "LOST handoff.md $tok" "real token kept: $tok"
done
has "$out" "TOKENS 24 LOST 9 FILTERED 15" "summary with the orchestration filter"

# MARK: missing old files
bash "$AD" --root "$R" --old "old.md handoff.md" --new .ai >"$out" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "no old file readable: code $rc"
has "$out" "USAGE none of the old files can be read: old.md handoff.md" "message for unreadable old files"
hasnt "$out" "TOKENS" "no summary without old files"
has "$TMP/err.txt" "WARNING file not found: old.md handoff.md" "warning for the joined argument"
bash "$AD" --root "$R" --old old.md ghost.md --new CLAUDE.md .ai >"$out" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "some old files present: code $rc"
has "$TMP/err.txt" "WARNING file not found: ghost.md" "warning per missing old file"
has "$out" "TOKENS 2 LOST 0 FILTERED 0" "present old files still compared"

# MARK: an edited (UPDATE) file: old content from --old-rev, new content stays in the corpus
printf '# agents\nRules `OLD_RULE`, `MOVED_RULE` and `STAYS_HERE`.\n' >"$R/.ai/agents.md"
git -C "$R" add -A && git -C "$R" commit -qm agents
printf '# agents\nRewritten. Still `STAYS_HERE`.\n' >"$R/.ai/agents.md"
printf 'MOVED_RULE\n' >>"$R/.ai/overlays/av-plan.md"
bash "$AD" --root "$R" --old-rev HEAD --keep .ai/agents.md --new CLAUDE.md .ai >"$out" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "edited file with --old-rev: code $rc"
has "$out" "LOST .ai/agents.md OLD_RULE" "token dropped by the edit is LOST"
hasnt "$out" "MOVED_RULE" "token moved to an overlay is not LOST"
hasnt "$out" "STAYS_HERE" "new content of the edited file is corpus"
has "$out" "TOKENS 3 LOST 1 FILTERED 0" "summary for an edited file"
bash "$AD" --root "$R" --old-rev HEAD --old .ai/agents.md --keep ./.ai/agents.md --new CLAUDE.md .ai >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "file in both --old and --keep: code $rc"
has "$out" "TOKENS 3 LOST 1 FILTERED 0" "--keep wins over --old for the same file"
bash "$AD" --root "$R" --old-rev HEAD --keep .ai/agents.md --new CLAUDE.md >"$out"; rc=$?
hasnt "$out" "STAYS_HERE" "--keep adds the tree version to the corpus outside --new"
has "$out" "LOST .ai/agents.md MOVED_RULE" "corpus limited to --new plus --keep files"
has "$out" "TOKENS 3 LOST 2 FILTERED 0" "summary for --keep outside --new"

# MARK: a converted file inside a --new directory is not corpus
bash "$AD" --root "$R" --old-rev HEAD --old .ai/agents.md --new CLAUDE.md .ai >"$out" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "converted file inside --new: code $rc"
has "$out" "LOST .ai/agents.md OLD_RULE" "converted file: dropped token is LOST"
has "$out" "LOST .ai/agents.md STAYS_HERE" "converted file inside --new does not hide its own losses"
hasnt "$out" "MOVED_RULE" "converted file: token moved to an overlay is not LOST"
has "$out" "TOKENS 3 LOST 2 FILTERED 0" "summary for a converted file inside --new"
bash "$AD" --root "$R" --old-rev HEAD --old ./.ai/agents.md --new CLAUDE.md ./.ai >"$out"; rc=$?
has "$out" "LOST .ai/agents.md STAYS_HERE" "converted file excluded with ./ paths"
bash "$AD" --root "$R" --old "$R/.ai/agents.md" --new CLAUDE.md .ai >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "edited file without --old-rev reads the tree: code $rc"
has "$out" "LOST .ai/agents.md STAYS_HERE" "without --old-rev the old file is not corpus"
has "$out" "TOKENS 1 LOST 1 FILTERED 0" "summary without --old-rev"
bash "$AD" --root "$R" --old-rev HEAD --old ghost.md --new CLAUDE.md .ai >"$out" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "file in neither the revision nor the tree: code $rc"
has "$TMP/err.txt" "WARNING file not found: ghost.md" "warning for a file missing in both places"

# MARK: intended removals after an UPDATE rewrite
printf '# agents\nRules `OLD_RULE`, `GONE_RULE`, `LOST_RULE`, `#pragma once` and `STAYS_HERE`.\n' >"$R/.ai/agents.md"
git -C "$R" add -A && git -C "$R" commit -qm intended
printf '# agents\nRewritten. Still `STAYS_HERE`.\n' >"$R/.ai/agents.md"
cat >"$TMP/intended.txt" <<'EOF'
# removed on purpose (plan PROJ-7)

OLD_RULE # replaced by the gate
  `GONE_RULE`
#pragma once
NOT_IN_OLD # never an old token
EOF
bash "$AD" --root "$R" --old-rev HEAD --keep .ai/agents.md --new CLAUDE.md .ai --intended "$TMP/intended.txt" >"$out" 2>"$TMP/err.txt"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "intended: code with a real loss $rc"
has "$out" "INTENDED .ai/agents.md OLD_RULE" "intended: token with a reason"
has "$out" "INTENDED .ai/agents.md GONE_RULE" "intended: token in backticks with indentation"
has "$out" "INTENDED .ai/agents.md #pragma once" "intended: token starting with # is not a comment"
has "$out" "LOST .ai/agents.md LOST_RULE" "intended: real loss stays LOST"
hasnt "$out" "LOST .ai/agents.md OLD_RULE" "intended: intended token printed as LOST"
hasnt "$out" "NOT_IN_OLD" "intended: token not in the old files printed"
hasnt "$out" "STAYS_HERE" "intended: present token printed"
has "$out" "TOKENS 5 LOST 1 FILTERED 0 INTENDED 3" "intended: summary"
[ "$(grep -E '^(LOST|INTENDED) ' "$out" | awk '{print $3}' | tr '\n' ' ')" = "OLD_RULE GONE_RULE LOST_RULE #pragma " ] && ok || fail "intended: token order changed"
printf 'LOST_RULE # dropped with the old agent\n' >>"$TMP/intended.txt"
cp "$TMP/intended.txt" "$R/intended-rel.txt"
bash "$AD" --root "$R" --old-rev HEAD --keep .ai/agents.md --new CLAUDE.md .ai --intended intended-rel.txt >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "intended: code with only intended removals $rc"
has "$out" "TOKENS 5 LOST 0 FILTERED 0 INTENDED 4" "intended: summary without real losses (path from --root)"
bash "$AD" --root "$R" --old-rev HEAD --keep .ai/agents.md --new CLAUDE.md .ai >"$out"; rc=$?
has "$out" "LOST .ai/agents.md OLD_RULE" "intended: without --intended every loss is LOST"
grep -qxF "TOKENS 5 LOST 4 FILTERED 0" "$out" && ok || fail "intended: summary without --intended changed"
bash "$AD" --root "$R" --old-rev HEAD --keep .ai/agents.md --new CLAUDE.md .ai --intended "$TMP/none.txt" >"$out"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "intended: missing file code $rc"
has "$out" "USAGE intended file not found: $TMP/none.txt" "intended: message for a missing file"
hasnt "$out" "TOKENS" "intended: summary with a missing file"
bash "$AD" --root "$R" --old-rev HEAD --keep .ai/agents.md --new CLAUDE.md .ai --intended >"$out"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "intended: flag without a file code $rc"

# MARK: usage
bash "$AD" --root "$R" --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "no old files: code $rc"
bash "$AD" --root "$R" --deleted --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "--deleted without --old-rev: code $rc"
bash "$AD" --root "$R" --old old.md >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "missing --new: code $rc"
bash "$AD" --root "$R" --old-rev missing --deleted --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "bad revision: code $rc"
bash "$AD" --root "$R" --keep .ai/agents.md --new .ai >"$out"; rc=$?
[ "$rc" -eq 2 ] && ok || fail "--keep without --old-rev: code $rc"
has "$out" "USAGE --keep requires --old-rev" "message for --keep without --old-rev"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

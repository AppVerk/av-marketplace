#!/bin/bash
# Black-box tests for block-git-push.sh.
# Pipes a JSON payload into the hook and asserts the permissionDecision.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/scripts/block-git-push.sh"
PASS=0; FAIL=0

# assert <expected: allow|deny|ask> <command> [cwd]
assert() {
  local expected="$1" cmd="$2" cwd="${3:-$PWD}" out decision
  out="$(jq -nc --arg c "$cmd" --arg w "$cwd" \
          '{tool_input:{command:$c},cwd:$w}' | bash "$HOOK")"
  if [ -z "$out" ]; then decision="allow"
  else decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "?"')"
  fi
  if [ "$decision" = "$expected" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    printf 'FAIL: expected=%s got=%s :: %s\n' "$expected" "$decision" "$cmd" >&2
  fi
}

# mk_repo <dir> — init a throwaway repo with one commit on branch $2 (default main)
mk_repo() {
  local dir="$1" branch="${2:-main}"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" config user.email t@t.t; git -C "$dir" config user.name t
  git -C "$dir" commit -q --allow-empty -m init
}

run() {
  # --- baseline: allow / no-op ---
  assert allow 'git push -u origin fix/login'
  assert allow 'git push origin feature/x'
  assert allow 'gh pr create --fill'
  assert allow 'git status'
  assert allow 'ls -la'
  assert allow 'git commit -m "docs: mention git push in the body"'
  assert allow 'AV_COMMIT_SKILL=1 git add . && git commit -m "feat: git push docs"'

  # --- force-push -> deny ---
  assert deny 'git push --force origin fix/x'
  assert deny 'git push -f origin fix/x'
  assert deny 'git push -fu origin fix/x'
  assert deny 'git push -uf origin fix/x'
  assert deny 'git push --force-with-lease origin fix/x'
  assert deny 'git push --force-with-lease=origin/fix/x origin fix/x'
  assert deny 'git push --force-if-includes origin fix/x'
  assert deny 'git push origin +fix/x'
  assert deny 'git push origin +HEAD:master'
  assert allow 'git push origin fix/x'
  assert allow 'git push -- -funny-branch'

  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
run

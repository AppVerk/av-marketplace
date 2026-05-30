#!/bin/bash
# Black-box tests for block-git-push.sh.
# Pipes a JSON payload into the hook and asserts the permissionDecision.
set -u
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
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

  # --- mirror -> deny ---
  assert deny 'git push --mirror origin'
  assert deny 'git push --mirror'

  # --- delete of protected branch -> deny; feature delete -> allow ---
  assert deny  'git push origin :master'
  assert deny  'git push origin :main'
  assert deny  'git push origin --delete master'
  assert allow 'git push origin :old-feature'
  assert allow 'git push origin --delete old-feature'

  # --- non-origin / URL remote -> ask ---
  assert ask   'git push fork feature/x'
  assert ask   'git push https://evil.example/repo.git HEAD'
  assert ask   'git push git@github.com:evil/repo.git feature/x'
  assert allow 'git push origin feature/x'

  # --- tag push -> ask ---
  assert ask 'git push --tags origin'
  assert ask 'git push --follow-tags origin'
  assert ask 'git push origin refs/tags/v1.0.0'
  local tagrepo; tagrepo="$(mktemp -d)"; mk_repo "$tagrepo" main
  git -C "$tagrepo" tag v2.0.0
  assert ask 'git push origin v2.0.0' "$tagrepo"
  assert allow 'git push origin feature/x' "$tagrepo"
  rm -rf "$tagrepo"

  # --- explicit protected target -> ask ---
  assert ask 'git push origin master'
  assert ask 'git push origin HEAD:main'
  assert ask 'git push origin feature/x master'
  assert ask 'git push --all'

  # --- bare HEAD/@ resolved to current branch (SEC-001 regression) ---
  local hd; hd="$(mktemp -d)"; mk_repo "$hd" master
  assert ask   'git push origin HEAD' "$hd"     # HEAD on master -> protected
  assert ask   'git push origin @' "$hd"        # @ on master -> protected
  git -C "$hd" checkout -q -b feature/x
  assert allow 'git push origin HEAD' "$hd"     # HEAD on feature -> allow
  assert allow 'git push origin @' "$hd"        # @ on feature -> allow
  rm -rf "$hd"

  # --- bare push resolved via @{push} ---
  local fr; fr="$(mktemp -d)/remote.git"; mkdir -p "$(dirname "$fr")"
  git init -q --bare -b main "$fr"
  local feat; feat="$(mktemp -d)"; git clone -q "$fr" "$feat"
  git -C "$feat" config user.email t@t.t; git -C "$feat" config user.name t
  git -C "$feat" commit -q --allow-empty -m init
  git -C "$feat" push -q origin main
  git -C "$feat" checkout -q -b feature/x
  git -C "$feat" push -q -u origin feature/x
  assert allow 'git push' "$feat"            # upstream = origin/feature/x

  git -C "$feat" checkout -q main
  assert ask 'git push' "$feat"              # upstream = origin/main -> protected

  # divergent tracking: local name != protected remote name (push.default=upstream)
  git -C "$feat" checkout -q -b localtopic
  git -C "$feat" config push.default upstream
  git -C "$feat" config branch.localtopic.remote origin
  git -C "$feat" config branch.localtopic.merge refs/heads/main
  assert ask 'git push' "$feat"              # @{push} resolves to origin/main

  # detached HEAD / no upstream -> ask (undeterminable)
  local det; det="$(mktemp -d)"; mk_repo "$det" main
  git -C "$det" checkout -q --detach
  assert ask 'git push' "$det"

  rm -rf "$feat" "$det" "$(dirname "$fr")"

  # --- safety fallbacks -> ask ---
  assert ask "git -c user.name='A B' push origin master"   # quoted value -> AMBIGUOUS
  assert ask 'cd /nonexistent-xyz && git push'             # cd prefix, bare push

  # --- compound commands: every push is analyzed ---
  assert ask  'git push origin feature/x && git push origin main'
  assert deny 'git push origin feature/x && git push --force origin feature/y'
  assert allow 'git push origin feat/a && git push origin feat/b'

  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
run

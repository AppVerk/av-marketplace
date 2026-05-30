# Granular `git push` Policy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `commit` plugin's blanket `git push` block with a deny/ask/allow cascade so feature-branch pushes (and PR creation) work from Claude Code while force-pushes, `--mirror`, and protected-branch deletions stay blocked and protected-branch / tag / non-origin pushes prompt for confirmation.

**Architecture:** Rewrite `plugins/commit/scripts/block-git-push.sh` as a set of small, sourceable bash functions plus a `main` orchestrator that emits a Claude Code `PreToolUse` JSON decision. Build it incrementally, one cascade layer per task, each validated by a black-box test harness (`tests/test-block-git-push.sh`) that pipes JSON into the hook and asserts the `permissionDecision`. A dedicated CI workflow runs the harness. Finally, bump the version and sync the four canonical version locations + docs.

**Tech Stack:** Bash, `jq`, `git`, GitHub Actions. No `bats` (plain-bash harness).

**Source spec:** `docs/superpowers/specs/2026-05-30-commit-push-policy-design.md` (read it before starting).

---

## ⚠️ Repo-specific gotchas (read first)

1. **Commits are guarded.** `plugins/commit/scripts/block-git-commit.sh` blocks direct `git commit`. Every commit step below MUST prefix the command with `AV_COMMIT_SKILL=1`.
2. **The current push hook false-positives on the word "push".** Until Task 7 lands, a commit *message* containing "git push" is blocked by the old hook. To be safe for the whole plan, **write commit messages to a temp file and use `git commit -F`** whenever the message contains the word "push". Pattern:
   ```bash
   printf '%s\n' "type(scope): subject line without problems" > /tmp/m.txt
   AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
   ```
   For messages with no "push" token, `AV_COMMIT_SKILL=1 git commit -m "..."` is fine.
3. **Never run `git push` during implementation.** The human pushes the branch and opens the PR.
4. **Version parity is enforced by CI** (`scripts/check_plugin_versions.py`). The version must match in 4 places (Task 9). Run the script locally before finishing.

---

## File Structure

| File | Responsibility |
|---|---|
| `plugins/commit/scripts/block-git-push.sh` | The hook. Sourceable functions + `main`. Modified across Tasks 0–7. |
| `plugins/commit/tests/test-block-git-push.sh` | Black-box test harness (JSON in → decision asserted). Built across Tasks 1–7. |
| `.github/workflows/commit-hook-test.yml` | CI workflow running the harness. Task 8. |
| `plugins/commit/.claude-plugin/plugin.json` | Version + description. Task 9. |
| `.claude-plugin/marketplace.json` | Version + description. Task 9. |
| `README.md` | Plugin table row. Task 9. |
| `docs/plugins/commit.md` | Behavior docs + `**Version:**`. Task 9. |

`block-git-commit.sh`, `hooks/hooks.json`, `commands/commit.md` are **NOT** touched.

---

## Task 0: Branch + hook skeleton

**Files:**
- Modify: `plugins/commit/scripts/block-git-push.sh` (full rewrite to skeleton)

- [ ] **Step 1: Create a working branch**

```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
git checkout -b feat/commit-push-policy
```

- [ ] **Step 2: Replace the hook with a sourceable skeleton**

Overwrite `plugins/commit/scripts/block-git-push.sh` with exactly:

```bash
#!/bin/bash
# block-git-push.sh — PreToolUse guard for `git push` (commit plugin).
#
# Decision cascade (first match wins):
#   0. no real `git push` subcommand        -> allow (exit 0)
#   1. force-push                            -> deny
#   2. --mirror                              -> deny
#   3. delete of a protected branch          -> deny
#   4. non-origin / URL remote               -> ask
#   5. tag push                              -> ask
#   6. target branch is master/main          -> ask
#   7. target undeterminable                 -> ask
#   8. otherwise (feature branch, origin)    -> allow (exit 0)
# Safety rule: anything we cannot parse reliably -> ask, never silent allow.

PROTECTED_RE='^(master|main)$'

R_FORCE="Force-push is blocked for Claude Code. If you intend to force-push, run it yourself from your terminal."
R_MIRROR="git push --mirror can overwrite or delete remote refs and is blocked."
R_DELPROT="Deleting a protected branch (master/main) is blocked. Run it yourself from your terminal if intended."
R_REMOTE="This push targets a remote other than 'origin' (or a URL). Confirm you intend to push there."
R_TAG="This push publishes a tag, which may trigger a release. Confirm you intend to push it."
R_PROT="This push targets a protected branch (master/main). Confirm you intend to push directly to it."
R_UNDET="The push target could not be verified. Confirm this push is safe."

# Emit a decision as PreToolUse JSON and exit. $1=decision $2=reason
emit() {
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

# find_push_inv "<command>" -> prints the push invocation (tokens from `push`
# to end of its segment, space-joined) or nothing; returns 1 if no git-push
# subcommand. Prints the sentinel AMBIGUOUS when a global option's value is
# quoted (tokenization unreliable).
find_push_inv() {
  local cmd="$1" seg
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    local -a t; read -r -a t <<< "$seg"
    local i=0 n=${#t[@]}
    while [ $i -lt $n ] && [[ ${t[$i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i+1)); done
    { [ $i -lt $n ] && [ "${t[$i]}" = "git" ]; } || continue
    i=$((i+1))
    while [ $i -lt $n ]; do
      case "${t[$i]}" in
        --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*) i=$((i+1));;
        --git-dir|--work-tree|--namespace|--exec-path|-C|-c)
          local val="${t[$((i+1))]}"
          case "$val" in *\'*|*\"*) printf 'AMBIGUOUS'; return 0;; esac
          i=$((i+2));;
        -*) i=$((i+1));;
        *) break;;
      esac
    done
    if [ $i -lt $n ] && [ "${t[$i]}" = "push" ]; then
      printf '%s' "${t[*]:$i}"
      return 0
    fi
  done < <(printf '%s' "$cmd" | sed -E 's/(\&\&|\|\||[;&|`()])/\n/g')
  return 1
}

main() {
  local cmd cwd inv
  local input; input="$(cat)"
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)"

  inv="$(find_push_inv "$cmd")" || exit 0
  [ -n "$inv" ] || exit 0
  [ "$inv" = "AMBIGUOUS" ] && emit ask "$R_UNDET"

  # cascade layers are added here in later tasks

  exit 0   # allow
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
```

- [ ] **Step 3: Syntax-check**

Run: `bash -n plugins/commit/scripts/block-git-push.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
printf '%s\n' "refactor(commit): scaffold sourceable block-git-push hook skeleton" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 1: Test harness + allow/no-op baseline

**Files:**
- Create: `plugins/commit/tests/test-block-git-push.sh`

- [ ] **Step 1: Write the harness with baseline (allow) cases**

Create `plugins/commit/tests/test-block-git-push.sh` with exactly:

```bash
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

  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
run
```

- [ ] **Step 2: Make it executable and run it**

Run:
```bash
chmod +x plugins/commit/tests/test-block-git-push.sh
plugins/commit/tests/test-block-git-push.sh
```
Expected: `7 passed, 0 failed`, exit 0. (The skeleton allows everything and `find_push_inv` correctly ignores `git commit`/`git status`/`gh`, so all baseline cases pass.)

- [ ] **Step 3: Commit**

```bash
printf '%s\n' "test(commit): add block-git-push harness with allow baseline" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/tests/test-block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 2: Force-push → deny

**Files:**
- Modify: `plugins/commit/scripts/block-git-push.sh` (add `inv_has_force`, wire into `main`)
- Modify: `plugins/commit/tests/test-block-git-push.sh` (add force cases)

- [ ] **Step 1: Add failing tests**

In `test-block-git-push.sh`, inside `run()` directly after the baseline block, add:

```bash
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
```

- [ ] **Step 2: Run, expect failures**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: FAIL lines for each `deny` case (skeleton still allows). The two `allow` cases pass.

- [ ] **Step 3: Implement `inv_has_force`**

In `block-git-push.sh`, add this function immediately after `find_push_inv`:

```bash
# inv_has_force "<push-invocation>" -> 0 if a force-push is present.
inv_has_force() {
  local -a t; read -r -a t <<< "$1"
  local i seen_dd=0
  for ((i=1;i<${#t[@]};i++)); do
    local x="${t[$i]}"
    if [ "$x" = "--" ]; then seen_dd=1; continue; fi
    if [ $seen_dd -eq 1 ]; then
      case "$x" in +*) return 0;; esac
      continue
    fi
    case "$x" in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes) return 0;;
      --*) ;;
      -*) [[ "$x" =~ ^-[A-Za-z0-9]+$ && "$x" == *f* ]] && return 0;;
      +*) return 0;;
    esac
  done
  return 1
}
```

- [ ] **Step 4: Wire into `main`**

In `main`, replace the line `  # cascade layers are added here in later tasks` with:

```bash
  inv_has_force "$inv" && emit deny "$R_FORCE"
```

- [ ] **Step 5: Run, expect green**

Run: `bash -n plugins/commit/scripts/block-git-push.sh && plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`. (`-- -funny-branch` stays allow because `--` ends options; `+HEAD:master` denies via the `+` refspec.)

- [ ] **Step 6: Commit**

```bash
printf '%s\n' "feat(commit): deny force-pushes in block-git-push hook" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh plugins/commit/tests/test-block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 3: `--mirror` → deny

**Files:**
- Modify: `plugins/commit/scripts/block-git-push.sh`
- Modify: `plugins/commit/tests/test-block-git-push.sh`

- [ ] **Step 1: Add failing tests**

In `run()`, after the force block, add:

```bash
  # --- mirror -> deny ---
  assert deny 'git push --mirror origin'
  assert deny 'git push --mirror'
```

- [ ] **Step 2: Run, expect failures**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: 2 FAIL lines.

- [ ] **Step 3: Implement `inv_has_mirror` and wire it in**

Add after `inv_has_force`:

```bash
# inv_has_mirror "<push-invocation>" -> 0 if --mirror present.
inv_has_mirror() { case " $1 " in *" --mirror "*) return 0;; esac; return 1; }
```

In `main`, immediately after the `inv_has_force … emit deny` line, add:

```bash
  inv_has_mirror "$inv" && emit deny "$R_MIRROR"
```

- [ ] **Step 4: Run, expect green**

Run: `bash -n plugins/commit/scripts/block-git-push.sh && plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
printf '%s\n' "feat(commit): deny --mirror in block-git-push hook" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh plugins/commit/tests/test-block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 4: Parse remote/refspecs + protected-branch delete → deny

**Files:**
- Modify: `plugins/commit/scripts/block-git-push.sh`
- Modify: `plugins/commit/tests/test-block-git-push.sh`

- [ ] **Step 1: Add failing tests**

In `run()`, after the mirror block, add:

```bash
  # --- delete of protected branch -> deny; feature delete -> allow ---
  assert deny  'git push origin :master'
  assert deny  'git push origin :main'
  assert deny  'git push origin --delete master'
  assert allow 'git push origin :old-feature'
  assert allow 'git push origin --delete old-feature'
```

- [ ] **Step 2: Run, expect failures**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: 3 FAIL lines (the three `deny` cases; skeleton allows them).

- [ ] **Step 3: Implement parsing + delete helpers**

Add after `inv_has_mirror`:

```bash
# parse_remote_refspecs "<push-invocation>" — sets globals REMOTE and REFSPECS[].
parse_remote_refspecs() {
  local -a t; read -r -a t <<< "$1"
  REMOTE=""; REFSPECS=(); local i seen_dd=0 positional=0
  for ((i=1;i<${#t[@]};i++)); do
    local x="${t[$i]}"
    if [ $seen_dd -eq 0 ] && [ "$x" = "--" ]; then seen_dd=1; continue; fi
    if [ $seen_dd -eq 0 ]; then
      case "$x" in
        -o|--push-option|--repo|--receive-pack|--exec) i=$((i+1)); continue;;
        --*) continue;;
        -*) continue;;
      esac
    fi
    if [ $positional -eq 0 ]; then REMOTE="$x"; positional=1
    else REFSPECS+=("$x"); fi
  done
}

# dst_of "<refspec>" -> normalized destination branch/ref name.
dst_of() {
  local r="${1#+}"
  case "$r" in *:*) r="${r##*:}";; esac
  r="${r#refs/heads/}"; r="${r#refs/tags/}"
  printf '%s' "$r"
}

# inv_is_delete "<push-invocation>" -> 0 if --delete/-d present.
inv_is_delete() { case " $1 " in *" --delete "*|*" -d "*) return 0;; esac; return 1; }

# refspec_is_delete "<refspec>" -> 0 if empty-src delete form (:dst).
refspec_is_delete() { local r="${1#+}"; case "$r" in :*) return 0;; esac; return 1; }

is_protected() { [[ "$1" =~ $PROTECTED_RE ]]; }
```

- [ ] **Step 4: Wire delete-of-protected into `main`**

In `main`, immediately after the `inv_has_mirror … emit deny` line, add:

```bash
  parse_remote_refspecs "$inv"
  local rs d
  for rs in "${REFSPECS[@]}"; do
    if inv_is_delete "$inv" || refspec_is_delete "$rs"; then
      d="$(dst_of "$rs")"
      is_protected "$d" && emit deny "$R_DELPROT"
    fi
  done
```

- [ ] **Step 5: Run, expect green**

Run: `bash -n plugins/commit/scripts/block-git-push.sh && plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`. (`:old-feature` and `--delete old-feature` resolve to a non-protected dst → fall through to allow.)

- [ ] **Step 6: Commit**

```bash
printf '%s\n' "feat(commit): deny deletion of protected branches" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh plugins/commit/tests/test-block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 5: Non-origin / URL remote → ask

**Files:**
- Modify: `plugins/commit/scripts/block-git-push.sh`
- Modify: `plugins/commit/tests/test-block-git-push.sh`

- [ ] **Step 1: Add failing tests**

In `run()`, after the delete block, add:

```bash
  # --- non-origin / URL remote -> ask ---
  assert ask   'git push fork feature/x'
  assert ask   'git push https://evil.example/repo.git HEAD'
  assert ask   'git push git@github.com:evil/repo.git feature/x'
  assert allow 'git push origin feature/x'
```

- [ ] **Step 2: Run, expect failures**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: 3 FAIL lines (the three `ask` cases; skeleton allows them).

- [ ] **Step 3: Implement `remote_kind` and wire it in**

Add after `is_protected`:

```bash
# remote_kind "<remote-token>" -> prints origin | other | url
remote_kind() {
  local r="$1"
  case "$r" in
    *"://"*) echo url; return;;
    *@*:*)   echo url; return;;   # scp-like user@host:path
  esac
  [ "$r" = "origin" ] && { echo origin; return; }
  echo other
}
```

In `main`, after the delete-of-protected `for` loop, add:

```bash
  if [ -n "$REMOTE" ]; then
    case "$(remote_kind "$REMOTE")" in
      url|other) emit ask "$R_REMOTE";;
    esac
  fi
```

- [ ] **Step 4: Run, expect green**

Run: `bash -n plugins/commit/scripts/block-git-push.sh && plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
printf '%s\n' "feat(commit): ask before pushing to non-origin or URL remotes" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh plugins/commit/tests/test-block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 6: Tag push → ask

**Files:**
- Modify: `plugins/commit/scripts/block-git-push.sh`
- Modify: `plugins/commit/tests/test-block-git-push.sh`

- [ ] **Step 1: Add failing tests** (uses a repo with a real tag for the best-effort check)

In `run()`, after the non-origin block, add:

```bash
  # --- tag push -> ask ---
  assert ask 'git push --tags origin'
  assert ask 'git push --follow-tags origin'
  assert ask 'git push origin refs/tags/v1.0.0'
  local tagrepo; tagrepo="$(mktemp -d)"; mk_repo "$tagrepo" main
  git -C "$tagrepo" tag v2.0.0
  assert ask 'git push origin v2.0.0' "$tagrepo"
  assert allow 'git push origin feature/x' "$tagrepo"
  rm -rf "$tagrepo"
```

- [ ] **Step 2: Run, expect failures**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: FAIL for the 4 `ask` tag cases.

- [ ] **Step 3: Implement tag helpers + effective dir, wire in**

Add after `remote_kind`:

```bash
# effective_dir "<command>" "<cwd>" -> dir to run git in (honors -C/--git-dir).
effective_dir() {
  local cmd="$1" cwd="$2"
  if [[ "$cmd" =~ (^|[[:space:]])-C[[:space:]]+([^[:space:]]+) ]]; then printf '%s' "${BASH_REMATCH[2]}"; return; fi
  if [[ "$cmd" =~ (^|[[:space:]])--git-dir=([^[:space:]]+) ]]; then printf '%s' "${BASH_REMATCH[2]}"; return; fi
  printf '%s' "$cwd"
}

# inv_has_tag_flag "<push-invocation>" -> 0 if --tags/--follow-tags.
inv_has_tag_flag() { case " $1 " in *" --tags "*|*" --follow-tags "*) return 0;; esac; return 1; }

# dst_is_tag "<refspec>" "<dir>" -> 0 if dst is under refs/tags or an existing tag.
dst_is_tag() {
  local raw="${1#+}" dst; dst="${raw##*:}"
  case "$dst" in refs/tags/*) return 0;; esac
  local name="${dst#refs/heads/}"
  [ -n "$2" ] && git -C "$2" show-ref --verify --quiet "refs/tags/$name" 2>/dev/null && return 0
  return 1
}
```

In `main`, after the non-origin remote block, add:

```bash
  local dir; dir="$(effective_dir "$cmd" "$cwd")"
  inv_has_tag_flag "$inv" && emit ask "$R_TAG"
  for rs in "${REFSPECS[@]}"; do dst_is_tag "$rs" "$dir" && emit ask "$R_TAG"; done
```

- [ ] **Step 4: Run, expect green**

Run: `bash -n plugins/commit/scripts/block-git-push.sh && plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
printf '%s\n' "feat(commit): ask before pushing tags (release trigger guard)" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh plugins/commit/tests/test-block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 7: Branch classification (protected → ask, bare-push resolution, undeterminable → ask)

**Files:**
- Modify: `plugins/commit/scripts/block-git-push.sh`
- Modify: `plugins/commit/tests/test-block-git-push.sh`

- [ ] **Step 1: Add failing tests** (covers explicit, multi-refspec, `--all`, bare-push `@{push}` incl. the divergent-tracking case, detached HEAD)

In `run()`, after the tag block, add:

```bash
  # --- explicit protected target -> ask ---
  assert ask 'git push origin master'
  assert ask 'git push origin HEAD:main'
  assert ask 'git push origin feature/x master'
  assert ask 'git push --all'

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
```

- [ ] **Step 2: Run, expect failures**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: FAIL for the protected/`--all`/bare-master/divergent/detached `ask` cases (skeleton allows them). `git push` on `feature/x` already passes.

- [ ] **Step 3: Implement resolution + classification, wire in**

Add after `dst_is_tag`:

```bash
# has_cd_prefix "<command>" -> 0 if a cd/pushd precedes the push (repo may differ).
has_cd_prefix() { [[ "$1" =~ (^|[;\&|\`(]|[[:space:]])(cd|pushd)[[:space:]] ]]; }

# resolve_push "<dir>" -> prints "<remote>/<branch>" via @{push} (fallback @{upstream}).
resolve_push() {
  git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null \
    || git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null
}
```

In `main`, replace the final `  exit 0   # allow` line with:

```bash
  # Determine remote + target branches for classification.
  local -a dsts=()
  if [ ${#REFSPECS[@]} -gt 0 ]; then
    for rs in "${REFSPECS[@]}"; do dsts+=("$(dst_of "$rs")"); done
  elif [ -n "$REMOTE" ]; then
    : # remote given but no refspec; treat current branch via resolution below
  fi

  if [ ${#dsts[@]} -eq 0 ]; then
    case " $inv " in *" --all "*) dsts+=("master");; esac
  fi

  if [ ${#dsts[@]} -eq 0 ]; then
    has_cd_prefix "$cmd" && emit ask "$R_UNDET"
    local rp; rp="$(resolve_push "$dir")" || emit ask "$R_UNDET"
    [ -n "$rp" ] || emit ask "$R_UNDET"
    local rr="${rp%%/*}"
    case "$(remote_kind "$rr")" in url|other) emit ask "$R_REMOTE";; esac
    dsts+=("${rp#*/}")
  fi

  for d in "${dsts[@]}"; do is_protected "$d" && emit ask "$R_PROT"; done
  for d in "${dsts[@]}"; do [ -n "$d" ] || emit ask "$R_UNDET"; done

  exit 0   # allow
}
```

> NOTE: the closing brace `}` above replaces the original `main` closing brace — make sure `main` ends exactly once. After editing, the `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main; fi` block must still be the last thing in the file.

- [ ] **Step 4: Run, expect green**

Run: `bash -n plugins/commit/scripts/block-git-push.sh && plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`. The divergent-tracking case is the key assertion: `@{push}` resolves `localtopic` → `origin/main` → `ask`. (A naive `--abbrev-ref HEAD` would resolve `localtopic` and wrongly `allow`.)

- [ ] **Step 5: Add the AMBIGUOUS + cd-prefix safety cases**

In `run()`, after the detached block (before the final `printf`), add:

```bash
  # --- safety fallbacks -> ask ---
  assert ask "git -c user.name='A B' push origin master"   # quoted value -> AMBIGUOUS
  assert ask 'cd /nonexistent-xyz && git push'             # cd prefix, bare push
```

- [ ] **Step 6: Run, expect green**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`.

- [ ] **Step 7: Commit**

```bash
printf '%s\n' "feat(commit): classify push targets, resolve bare pushes via at-push" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh plugins/commit/tests/test-block-git-push.sh
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 8: CI workflow

**Files:**
- Create: `.github/workflows/commit-hook-test.yml`

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/commit-hook-test.yml` with exactly:

```yaml
name: Commit Hook Test

on:
  push:
    branches: [master]
    paths: ["plugins/commit/**"]
  pull_request:
    branches: [master]
    paths: ["plugins/commit/**"]

permissions:
  contents: read

concurrency:
  group: commit-hook-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test-block-git-push:
    name: Test block-git-push hook
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Checkout
        uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1

      - name: Run hook tests
        run: |
          chmod +x plugins/commit/tests/test-block-git-push.sh
          plugins/commit/tests/test-block-git-push.sh
```

(`ubuntu-latest` ships bash, `jq`, and `git`. The checkout SHA matches the existing `plugin-version-parity.yml` pin.)

- [ ] **Step 2: Validate YAML locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/commit-hook-test.yml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
printf '%s\n' "ci(commit): run block-git-push hook tests on plugin changes" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add .github/workflows/commit-hook-test.yml
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 9: Version bump + docs sync (4 canonical locations)

**Files:**
- Modify: `plugins/commit/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`
- Modify: `docs/plugins/commit.md`

- [ ] **Step 1: Bump `plugin.json`**

In `plugins/commit/.claude-plugin/plugin.json`, set:
```json
{
  "name": "commit",
  "description": "Generate meaningful commit messages and block force-push while guarding pushes to protected branches",
  "version": "1.4.0"
}
```

- [ ] **Step 2: Bump `marketplace.json`**

In `.claude-plugin/marketplace.json`, in the `"name": "commit"` entry, set `"version": "1.4.0"` and `"description": "Generate meaningful commit messages and block force-push while guarding pushes to protected branches"`.

- [ ] **Step 3: Bump the README row**

In `README.md`, replace the Commit row in the Available Plugins table with exactly:
```
| [Commit](docs/plugins/commit.md) | 1.4.0 | Conventional Commits message generation. Auto-blocks direct `git commit`; blocks force-push/`--mirror`/protected-branch deletion and prompts on pushes to `master`/`main`, tags, and non-origin remotes |
```
(Version MUST be in column 2 — that is what `check_plugin_versions.py` parses.)

- [ ] **Step 4: Rewrite the `git push` section in `docs/plugins/commit.md`**

In `docs/plugins/commit.md`: set the header to `**Version:** 1.4.0`. Replace the entire `### \`git push\` block` subsection with:

````markdown
### `git push` policy

The hook applies a graduated policy (first match wins):

| Operation | Decision |
|---|---|
| Push a feature branch to `origin` (e.g. `git push -u origin fix/x`) | allowed |
| `git push` whose upstream is a feature branch on origin | allowed |
| Push to `master`/`main` (add commits) | prompts (ask) |
| Tag push (`--tags`, `--follow-tags`, `git push origin v1.0`) | prompts (ask) |
| Push to a remote other than `origin`, or a URL | prompts (ask) |
| Target cannot be verified (detached HEAD, ambiguous command) | prompts (ask) |
| Any force-push (`--force`, `-f`, `--force-with-lease`, `+refspec`) | blocked (deny) |
| `git push --mirror` | blocked (deny) |
| Delete a protected branch (`:master`, `--delete master`) | blocked (deny) |

**Known limitations** (guardrail, not a sandbox — the hook reads only the
top-level command string):

- **Subprocesses:** `gh pr create` may invoke `git push` internally; nested
  processes are not inspected.
- **Shell wrappers / substitution:** `sh -c "git push --force"`,
  `$(echo git) push`, `eval "git push -f"` bypass detection.
- **Ambiguous quoting / repo-changing prefixes** (`git -c x='a b' push`,
  `cd /other && git push`) degrade to a confirmation prompt rather than a
  silent allow.
- **Secret leakage:** allowing feature-branch pushes means a branch containing
  accidentally-committed secrets can be published to `origin`. Content is not
  scanned. The non-origin/URL prompt mitigates exfiltration to other remotes.
````

- [ ] **Step 5: Run the version parity check**

Run: `python3 scripts/check_plugin_versions.py`
Expected: passes (no version mismatch reported for `commit`).

- [ ] **Step 6: Commit**

```bash
printf '%s\n' "release(commit): 1.4.0 — graduated git push policy" > /tmp/m.txt
AV_COMMIT_SKILL=1 git add plugins/commit/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md docs/plugins/commit.md
AV_COMMIT_SKILL=1 git commit -F /tmp/m.txt && rm -f /tmp/m.txt
```

---

## Task 10: Final verification

- [ ] **Step 1: Run the full hook test suite**

Run: `plugins/commit/tests/test-block-git-push.sh`
Expected: `0 failed`, exit 0.

- [ ] **Step 2: Re-run the parity check + syntax check**

Run:
```bash
python3 scripts/check_plugin_versions.py
bash -n plugins/commit/scripts/block-git-push.sh
```
Expected: both succeed.

- [ ] **Step 3: Confirm untouched files are unchanged**

Run: `git diff --name-only master -- plugins/commit/scripts/block-git-commit.sh plugins/commit/hooks/hooks.json plugins/commit/commands/commit.md`
Expected: empty output (no changes).

- [ ] **Step 4: Manual smoke test of the live hook**

Run:
```bash
printf '%s' '{"tool_input":{"command":"git push --force origin x"},"cwd":"'"$PWD"'"}' | bash plugins/commit/scripts/block-git-push.sh
printf '%s' '{"tool_input":{"command":"git push -u origin feat/demo"},"cwd":"'"$PWD"'"}' | bash plugins/commit/scripts/block-git-push.sh
printf '%s' '{"tool_input":{"command":"git commit -m \"docs: git push notes\""},"cwd":"'"$PWD"'"}' | bash plugins/commit/scripts/block-git-push.sh
```
Expected: first prints a `deny` JSON; second prints nothing (allow); third prints nothing (allow — subcommand is `commit`).

- [ ] **Step 5: Hand off**

Implementation is complete. Report status to the user. The user pushes the branch and opens the PR (do NOT run `git push`). Consider the superpowers:finishing-a-development-branch skill for integration options.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Subcommand detection / false-positive fix → Task 0 (`find_push_inv`) + Task 1 baseline.
- Force (incl. lease, `+refspec`, short clusters, `--` stop) → Task 2.
- `--mirror` → Task 3. Protected-branch delete → Task 4. Feature delete allowed → Task 4.
- Non-origin/URL → Task 5. Tags (`--tags`/`--follow-tags`/`refs/tags/`/existing-tag) → Task 6.
- Protected target, `--all`, bare-push `@{push}` resolution, divergent tracking, detached, AMBIGUOUS, cd-prefix → Task 7.
- `cwd` from stdin + `-C`/`--git-dir` → `effective_dir` (Task 6), used in Tasks 6–7.
- Pinned reason strings → Task 0 constants, asserted indirectly via decisions.
- CI workflow → Task 8. Version parity (4 locations) + docs + description wording → Task 9.
- Final verification + untouched-files check → Task 10.

**Placeholder scan:** none — every code/test/command step contains literal content.

**Type/name consistency:** function names and the globals `REMOTE`/`REFSPECS`/`PROTECTED_RE` and reason constants `R_*` are defined in Task 0/4 and used consistently in Tasks 2–7. `emit <decision> <reason>` signature is stable throughout.

**Note on `parse_remote_refspecs` reuse:** it is called once in `main` (Task 4) and its globals are reused by Tasks 5–7 — no second call needed.

# Block git push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `commit` plugin with a PreToolUse Bash hook that permanently blocks every form of `git push` from Claude Code.

**Architecture:** Add a new shell script `plugins/commit/scripts/block-git-push.sh` modeled 1:1 on the existing `block-git-commit.sh`. Register it as a second `command` under the existing `PreToolUse` / `Bash` matcher in `plugins/commit/hooks/hooks.json`. Bump the plugin version from `1.2.0` to `1.3.0` (MINOR — new user-visible behaviour) and synchronise the description across `plugin.json`, `marketplace.json`, `README.md`, and `docs/plugins/commit.md`.

**Tech Stack:** Bash, `jq`, Claude Code plugin hooks (PreToolUse), JSON.

**Spec:** `docs/superpowers/specs/2026-05-25-block-git-push-design.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `plugins/commit/scripts/block-git-push.sh` | **Create** | Parse Bash tool input, regex-match `git push` in any form, emit deny JSON |
| `plugins/commit/hooks/hooks.json` | **Modify** | Register the new script as a second `command` under PreToolUse/Bash |
| `plugins/commit/.claude-plugin/plugin.json` | **Modify** | Version `1.2.0` → `1.3.0`, expanded description |
| `docs/plugins/commit.md` | **Modify** | Document the new `git push` block under Auto-enforcement |
| `README.md` | **Modify** | Bump Commit row to `1.3.0`, refresh description |
| `.claude-plugin/marketplace.json` | **Modify** | Bump Commit entry to `1.3.0`, refresh description |

The change splits naturally into two commits:
1. **`feat(commit): block direct git push via PreToolUse hook`** — script, hooks.json, plugin.json, docs/plugins/commit.md.
2. **`chore(marketplace): sync commit to 1.3.0`** — README.md, marketplace.json.

This matches the existing project pattern (cf. commits `eccd0d1` + `7c3991c`).

---

## Task 1: Create the `block-git-push.sh` script

**Files:**
- Create: `plugins/commit/scripts/block-git-push.sh`

- [ ] **Step 1: Write the script**

Create `plugins/commit/scripts/block-git-push.sh` with the following content:

```bash
#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Block: any form of `git push` (no exceptions).
# Matches `git push`, `git push --force`, `git -C /path push`,
# `git --git-dir=... push`, `git push` after `;`, `&&`, `||`, `|`, `` ` ``, `(`,
# and parenthesised subshells like `(cd repo && git push)`.
if echo "$COMMAND" | grep -qE '(^|[;&|`(]|\s)git(\s+(\S+))*\s+push(\s|$|[);&|`])'; then
  echo '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "git push is permanently blocked for Claude Code in this environment. Run the push yourself from your terminal."
    }
  }'
  exit 0
fi

exit 0
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x plugins/commit/scripts/block-git-push.sh
ls -l plugins/commit/scripts/block-git-push.sh
```

Expected output: file permissions begin with `-rwxr-xr-x` (or at minimum, an `x` in the user position).

- [ ] **Step 3: Positive test — bare `git push`**

```bash
echo '{"tool_input":{"command":"git push"}}' | bash plugins/commit/scripts/block-git-push.sh
```

Expected output (JSON):
```json
{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "git push is permanently blocked for Claude Code in this environment. Run the push yourself from your terminal."
    }
  }
```

Exit code: `0`.

- [ ] **Step 4: Positive test — `git push --force`**

```bash
echo '{"tool_input":{"command":"git push --force"}}' | bash plugins/commit/scripts/block-git-push.sh
```

Expected: same deny JSON as Step 3.

- [ ] **Step 5: Positive test — chained command `cd /tmp && git push`**

```bash
echo '{"tool_input":{"command":"cd /tmp && git push"}}' | bash plugins/commit/scripts/block-git-push.sh
```

Expected: same deny JSON as Step 3 (regex matches after `&&`).

- [ ] **Step 6: Positive test — `git -C /tmp push`**

```bash
echo '{"tool_input":{"command":"git -C /tmp push"}}' | bash plugins/commit/scripts/block-git-push.sh
```

Expected: same deny JSON as Step 3 (regex allows global flags between `git` and `push`).

- [ ] **Step 7: Negative test — innocent command**

```bash
echo '{"tool_input":{"command":"ls -la"}}' | bash plugins/commit/scripts/block-git-push.sh
```

Expected: no output at all. Exit code: `0`.

- [ ] **Step 8: Negative test — false-positive guard `git pushd` (hypothetical)**

```bash
echo '{"tool_input":{"command":"git pushd"}}' | bash plugins/commit/scripts/block-git-push.sh
```

Expected: no output. Exit code: `0` (regex requires `push` followed by whitespace or end of string, so `pushd` does not match).

If any of Steps 3–8 do not match the expected output, fix the regex in Step 1 and re-run all tests.

---

## Task 2: Register the new hook in `hooks.json`

**Files:**
- Modify: `plugins/commit/hooks/hooks.json`

- [ ] **Step 1: Replace the file contents**

Current content of `plugins/commit/hooks/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/block-git-commit.sh"
          }
        ]
      }
    ]
  }
}
```

Replace with:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/block-git-commit.sh"
          },
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/block-git-push.sh"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate the JSON**

```bash
jq . plugins/commit/hooks/hooks.json > /dev/null && echo "valid JSON"
```

Expected output: `valid JSON`.

---

## Task 3: Bump plugin version and description

**Files:**
- Modify: `plugins/commit/.claude-plugin/plugin.json`

- [ ] **Step 1: Replace the file contents**

Current content of `plugins/commit/.claude-plugin/plugin.json`:

```json
{
  "name": "commit",
  "description": "Generate meaningful commit messages based on code changes",
  "version": "1.2.0"
}
```

Replace with:

```json
{
  "name": "commit",
  "description": "Generate meaningful commit messages and block direct git push",
  "version": "1.3.0"
}
```

- [ ] **Step 2: Validate the JSON**

```bash
jq . plugins/commit/.claude-plugin/plugin.json > /dev/null && echo "valid JSON"
```

Expected output: `valid JSON`.

---

## Task 4: Document the new behaviour in `docs/plugins/commit.md`

**Files:**
- Modify: `docs/plugins/commit.md` (lines 5, 62–77)

- [ ] **Step 1: Update the version line**

In `docs/plugins/commit.md`, change line 5 from:

```markdown
**Version:** 1.2.0
```

to:

```markdown
**Version:** 1.3.0
```

- [ ] **Step 2: Expand the Auto-enforcement section**

The current section (lines 62–77) describes only the `git commit` block. Replace the entire `## Auto-enforcement` section with the version below, which keeps the existing commit content and adds a parallel section about the new push block:

```markdown
## Auto-enforcement

This plugin includes two PreToolUse hooks that automatically guard destructive git operations from Claude Code.

### `git commit` block

The hook blocks any direct `git commit` so all commits flow through the `/commit` skill.

**What's blocked:**

- `git commit -m "message"`
- `git commit` (interactive)
- Chained commands containing `git commit` (e.g., `git add . && git commit -m "msg"`)

**What's allowed:**

- `git commit --amend` — the `/commit` skill doesn't support amending
- Commands from the `/commit` skill itself (identified by `AV_COMMIT_SKILL=1` prefix)

### `git push` block

The hook blocks **every** form of `git push` from Claude Code, without exceptions. The user is the only party who pushes code — Claude can prepare commits, but the publication step is human-only.

**What's blocked (non-exhaustive):**

- `git push`, `git push origin <ref>`
- `git push --force`, `git push -f`, `git push --force-with-lease`
- `git push --mirror`, `git push --delete`, `git push --dry-run`
- `git -C /path push`, `git --git-dir=… push`
- Chained commands containing `git push` (e.g., `cd repo && git push`)

**What's allowed:**

- Nothing. To push, run `git push` yourself from your terminal, outside Claude Code.

**Known limitation:** Commands like `gh pr create` may invoke `git push` as a subprocess. The hook only inspects the top-level Bash command string, so nested processes started by other tools may bypass the block.

Both hooks are registered automatically when the plugin is enabled. No configuration required.
```

- [ ] **Step 3: Sanity check the file**

```bash
grep -n "1.3.0\|git push block" docs/plugins/commit.md
```

Expected: at least two matches — the version line and the new section heading.

---

## Task 5: Commit the functional change

- [ ] **Step 1: Stage the functional files**

```bash
AV_COMMIT_SKILL=1 git add plugins/commit/scripts/block-git-push.sh \
                          plugins/commit/hooks/hooks.json \
                          plugins/commit/.claude-plugin/plugin.json \
                          docs/plugins/commit.md
```

- [ ] **Step 2: Verify staging**

```bash
git diff --cached --stat
```

Expected: four files listed (the script as `create mode 100755`, the three others as modifications).

- [ ] **Step 3: Create the commit**

```bash
AV_COMMIT_SKILL=1 git commit -m "feat(commit): block direct git push via PreToolUse hook

Add scripts/block-git-push.sh registered alongside the existing
block-git-commit.sh in PreToolUse/Bash. Every form of git push
invoked from Claude Code (--force, --mirror, --delete, with global
flags, chained commands) is denied with a clear reason; the user
remains the only party that pushes code.

Bumps plugin version 1.2.0 → 1.3.0 (MINOR) and documents the new
behaviour under Auto-enforcement."
```

Expected: commit succeeds; `git log -1 --oneline` shows the new commit.

---

## Task 6: Bump version in `README.md`

**Files:**
- Modify: `README.md` (line 21)

- [ ] **Step 1: Replace the Commit row**

In `README.md`, change line 21 from:

```markdown
| [Commit](docs/plugins/commit.md) | 1.2.0 | Conventional Commits message generation from staged changes. Auto-blocks direct `git commit` via hook |
```

to:

```markdown
| [Commit](docs/plugins/commit.md) | 1.3.0 | Conventional Commits message generation from staged changes. Auto-blocks direct `git commit` and `git push` via hooks |
```

- [ ] **Step 2: Sanity check**

```bash
grep -n "Commit](docs/plugins/commit.md)" README.md
```

Expected: a single match on the new row with version `1.3.0`.

---

## Task 7: Bump version in `marketplace.json`

**Files:**
- Modify: `.claude-plugin/marketplace.json` (commit entry, around lines 15–20)

- [ ] **Step 1: Replace the commit entry**

In `.claude-plugin/marketplace.json`, locate the entry whose `"name"` is `"commit"` (currently around lines 15–20):

```json
    {
      "name": "commit",
      "source": "./plugins/commit",
      "description": "Generate meaningful commit messages based on code changes",
      "version": "1.2.0",
      "category": "development"
    },
```

Replace with:

```json
    {
      "name": "commit",
      "source": "./plugins/commit",
      "description": "Generate meaningful commit messages and block direct git push",
      "version": "1.3.0",
      "category": "development"
    },
```

- [ ] **Step 2: Validate the JSON**

```bash
jq '.plugins[] | select(.name=="commit")' .claude-plugin/marketplace.json
```

Expected output: a JSON object with `"version": "1.3.0"` and the updated description.

---

## Task 8: Commit the marketplace sync

- [ ] **Step 1: Stage the sync files**

```bash
AV_COMMIT_SKILL=1 git add README.md .claude-plugin/marketplace.json
```

- [ ] **Step 2: Verify staging**

```bash
git diff --cached --stat
```

Expected: two files listed (both as modifications).

- [ ] **Step 3: Create the commit**

```bash
AV_COMMIT_SKILL=1 git commit -m "chore(marketplace): sync commit to 1.3.0

Refresh README plugin table and marketplace.json to reflect the
new git push block introduced in commit plugin 1.3.0."
```

Expected: commit succeeds; `git log -2 --oneline` shows both new commits.

---

## Task 9: Final integration smoke test (user-driven)

After the two commits land, a Claude Code session must be reloaded for the new hook to take effect. This task is executed by the user — the implementing agent cannot reload the session.

- [ ] **Step 1: Restart / reload Claude Code**

Restart the Claude Code session in this project so the updated `plugins/commit/hooks/hooks.json` is re-read.

- [ ] **Step 2: Try a `git push` from within Claude Code**

In a new Claude prompt, ask Claude to run `git push --dry-run` (or any push variant against a throwaway remote). The tool call MUST be denied with the message:

> git push is permanently blocked for Claude Code in this environment. Run the push yourself from your terminal.

- [ ] **Step 3: Confirm `/commit` flow still works**

Ask Claude to commit a trivial change via the `/commit` skill. The existing `block-git-commit.sh` must still allow `AV_COMMIT_SKILL=1 git commit …` (i.e., adding the push hook did not regress the commit hook).

- [ ] **Step 4: Confirm innocuous Bash still works**

Ask Claude to run `ls -la`. The command must execute normally — both hooks exit 0 silently when the command does not match.

If any step fails, revert with: `git revert HEAD~1..HEAD` (reverts both commits), investigate, and re-apply.

---

## Self-Review Notes

**Spec coverage:** every section of `docs/superpowers/specs/2026-05-25-block-git-push-design.md` (script, hooks.json, plugin metadata, documentation updates, behaviour table, manual test plan, rollback) has a corresponding task. ✅

**Placeholder scan:** every code/JSON/Markdown block is concrete; no "TBD", "similar to above", or "add error handling" left in the plan. ✅

**Type/text consistency:** the deny message string is identical across spec, script (Task 1 Step 1), expected outputs (Task 1 Steps 3–6), and integration test (Task 9 Step 2). Version `1.3.0` and the new description are consistent across `plugin.json` (Task 3), `docs/plugins/commit.md` (Task 4), `README.md` (Task 6), and `marketplace.json` (Task 7). ✅

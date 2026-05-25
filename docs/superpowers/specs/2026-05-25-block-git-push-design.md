# Block `git push` from Claude Code — Design Spec

**Date:** 2026-05-25
**Status:** Approved (awaiting implementation plan)
**Owner:** Marian Szenfeld
**Plugin affected:** `plugins/commit`

## Goal

Prevent Claude Code from executing `git push` against any remote, in any form, from within any project. The user remains the sole party that pushes code — Claude can prepare commits but the actual publication step is a human-only action.

## Motivation

Claude has broad Bash autonomy in this environment (`defaultMode: "auto"`). A misfired `git push` — especially `--force`, `--mirror`, or to a wrong branch — is difficult or impossible to undo. The user wants a hard guarantee that no automated flow inside Claude Code can publish code to a remote without their manual involvement.

There is already a precedent: `plugins/commit/scripts/block-git-commit.sh` blocks direct `git commit` to funnel commits through the `/commit` skill. We extend the same plugin with an analogous, stricter rule for push.

## Scope

In scope:
- Block every form of `git push` invoked through the Bash tool.
- Cover variants: bare `git push`, `git push --force` / `-f`, `git push --mirror`, `git push --delete`, `git push origin <ref>`, `git -C <path> push`, `git --git-dir=<path> push`, and `git push` appearing after `;`, `&&`, `||`, `|`, backticks, or `(`.

Out of scope (documented limitations):
- `gh pr create` and other `gh` commands that may invoke `git push` as a subprocess. The Bash hook only sees the top-level command string; nested processes started by `gh` bypass the hook.
- Non-git VCS push commands (`hg push`, `jj git push`, `git svn dcommit`). Not part of this codebase's workflow today; revisit if introduced.
- Pushes made manually by the user outside of Claude Code (terminal, IDE) — explicitly allowed by design.

## Design

### Architecture

A new shell script, `plugins/commit/scripts/block-git-push.sh`, structurally identical to the existing `block-git-commit.sh`. It is registered as a second `command` under the existing `PreToolUse` / `Bash` matcher in `plugins/commit/hooks/hooks.json`. Claude Code runs all registered hook commands for a tool invocation; any one of them returning `permissionDecision: "deny"` blocks the call and surfaces the reason to the model.

No changes to the existing `block-git-commit.sh` — the two scripts coexist and operate independently.

### Script: `plugins/commit/scripts/block-git-push.sh`

```bash
#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Block: any form of `git push` (no exceptions).
# Matches `git push`, `git push --force`, `git -C /path push`,
# `git --git-dir=... push`, and `git push` after `;`, `&&`, `||`, `|`, `` ` ``, `(`,
# or wrapped in a parenthesised subshell like `(cd repo && git push)`.
# `(\S+)*` between `git` and `push` allows any non-whitespace tokens (flags AND
# their arguments, e.g. `-C /tmp`). The end anchor includes shell terminators
# (`;`, `&`, `|`, `` ` ``, `)`) so subshell-closing `)` does not slip through.
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

The script must be executable (`chmod +x`).

### Hook registration

`plugins/commit/hooks/hooks.json` becomes:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/block-git-commit.sh" },
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/block-git-push.sh" }
        ]
      }
    ]
  }
}
```

### Plugin metadata

`plugins/commit/.claude-plugin/plugin.json`:

```json
{
  "name": "commit",
  "description": "Generate meaningful commit messages and block direct git push",
  "version": "1.3.0"
}
```

Version bump from `1.2.0` → `1.3.0` (MINOR — new user-visible behaviour, no breaking changes).

### Documentation updates

Per `CLAUDE.local.md` versioning rules:

- `README.md` Available Plugins table — bump Commit version to `1.3.0` and update one-line description to reflect the additional safeguard.
- `.claude-plugin/marketplace.json` — bump Commit `version` to `1.3.0` and update `description` to match.
- `docs/plugins/commit.md` — add a section explaining the `git push` block: what is blocked, how Claude is expected to behave (prepare commits, ask the user to push), and how to push manually (outside Claude Code).

Plugin count badge in `README.md` is unaffected (no plugin added/removed).

## Behaviour and edge cases

| Input command | Expected result |
|---|---|
| `git push` | Blocked |
| `git push origin master` | Blocked |
| `git push --force` / `git push -f` | Blocked |
| `git push --force-with-lease` | Blocked |
| `git push --mirror` | Blocked |
| `git push --delete origin foo` | Blocked |
| `git -C /tmp/repo push` | Blocked |
| `git --git-dir=/tmp/.git push` | Blocked |
| `cd /tmp/repo && git push` | Blocked |
| `(cd /tmp/repo; git push)` | Blocked |
| `git push --dry-run` | Blocked (intentional — dry-run still considered a push attempt) |
| `git pushd` (hypothetical) | Allowed (regex requires `push` as a whole word followed by space or end) |
| `git commit` (existing rule) | Blocked by `block-git-commit.sh`, unchanged |
| `echo "git push"` | Blocked (acceptable false positive — extremely niche, prefer over-eager blocking) |
| `git remote add push <url>`, `git tag push`, `git fetch push` | Blocked (acceptable false positive — `(\S+)*` is greedy on purpose; cases where `push` is a remote/tag/argument name are very rare) |
| `gh pr create` (subprocess push) | **Not** caught by this hook (documented limitation) |

## Testing

Manual smoke test after rollout:

1. In Claude Code, attempt `git push` — expect deny with the documented reason.
2. Attempt `git push --force` — expect deny.
3. Attempt `git -C /tmp/test push` (against a throwaway repo) — expect deny.
4. Attempt `cd /tmp/test && git push` — expect deny (regex matches after `&&`).
5. Confirm `git commit` behaviour is unchanged (still blocked unless `AV_COMMIT_SKILL=1` or `--amend`).
6. Confirm a normal Bash command (e.g. `ls`) is not affected.

No automated tests are added in this iteration — the existing plugin has no test harness, and adding one is out of scope for this change.

## Rollback

Two-line revert: remove the new `command` entry from `hooks/hooks.json` and delete `scripts/block-git-push.sh`. No persistent state is introduced.

## Open questions

None. Behaviour ("100% block, no exceptions") and placement ("extend commit plugin") were chosen explicitly during brainstorming.

# Spec — Block any `git push` from LLM in `commit` plugin

**Date:** 2026-05-07
**Plugin:** `commit`
**Target version:** 1.3.0 (MINOR — new feature)

## Problem

Claude Code's system prompt forbids pushing to remote without explicit user approval, but it relies on the LLM honoring the rule. The `commit` plugin already enforces commit discipline via a `PreToolUse` hook on `Bash` that blocks direct `git commit` and routes the agent through the `/commit` skill. There is no equivalent hard guard for `git push`. We want to make pushes from the LLM impossible at the harness level.

## Goal

Add a second `PreToolUse` hook that denies any `git push` invocation by the LLM, regardless of variant (`--force`, `--tags`, `-u …`, `--dry-run`, etc.) or context (chained with `&&`/`;`/`|`, command substitution, `git -C` global flags). No bypass mechanism — the user pushes manually after reviewing the commit.

## Non-goals

- Blocking `gh` commands that may push as a side effect (`gh pr create`, `gh pr merge`, `gh repo sync`). User wants `git push` only; `gh` workflows remain available.
- Differentiated messages for force-push vs regular push.
- Affecting users' own terminal usage. The hook only fires inside Claude Code sessions for `Bash` tool calls; manual shell usage is unaffected (intentional).
- Adding a `/push` skill or escape hatch (env var, marker file).

## Design

### Architecture

Single new shell script `plugins/commit/scripts/block-git-push.sh`, registered as a second hook in the existing `Bash` matcher of `plugins/commit/hooks/hooks.json`. Both hooks read the same `tool_input.command` from STDIN, each handles only its own pattern, returning `deny` or `exit 0` to pass through. Single Responsibility — `block-git-commit.sh` stays focused on commits.

### `hooks.json` after the change

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

### `block-git-push.sh` — logic

```bash
#!/bin/bash

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Match `git push` in any variant, including chains and substitutions.
# - Allow any whitespace-separated tokens between `git` and `push` (covers
#   `git -C /path push`, `git --git-dir=/x push`, etc.)
# - Word boundary after `push` (whitespace or end-of-string) prevents matching
#   `git pushhh`, `--grep="push-feature"`, etc.
# - No anchor before `git`: chains like `&& git push` and `; git push` already
#   match (mirrors style of existing block-git-commit.sh).
if echo "$COMMAND" | grep -qE 'git[[:space:]]+([^[:space:]]+[[:space:]]+)*push([[:space:]]|$)'; then
  echo '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Pushing to remote is blocked for the LLM. After creating the commit, stop and ask the user to run `git push` manually. Force-push is also blocked."
    }
  }'
  exit 0
fi

exit 0
```

**Regex notes:**

- `git[[:space:]]+` — `git` followed by at least one whitespace.
- `([^[:space:]]+[[:space:]]+)*` — zero or more arbitrary whitespace-separated tokens between `git` and `push`. This is intentionally broad: it covers `git -C /path push`, `git --git-dir=/x push`, `git --no-pager push`, including cases where a flag takes a non-flag argument. Trade-off: false positive risk if a command genuinely contains `git <something> push` where `push` is meant as data, but such cases are rare and the deny message is informative.
- `push([[:space:]]|$)` — `push` followed by whitespace or end-of-string. Prevents matching `git pushhh` and `"push"` substrings inside larger tokens (e.g. `git log --grep="push-feature"` does not match because `push-feature` is one token; the trailing boundary fails).
- No `^` anchor before `git`: chained forms like `git add . && git push` and `false; git push` already match because the regex finds `git push` anywhere in the string. This mirrors the existing `block-git-commit.sh` style.
- All `git push` variants (`--force`, `--force-with-lease`, `--tags`, `-u`, `--delete`, `--mirror`, `--dry-run`) are blocked uniformly. User chose absolute blocking — no exceptions.

### Meta updates

- **`plugins/commit/.claude-plugin/plugin.json`** — `version` → `1.3.0`.
- **`README.md`** (Available Plugins table) — version `1.3.0`; description: `Conventional Commits message generation from staged changes. Auto-blocks direct `git commit` and any `git push` via hooks`.
- **`.claude-plugin/marketplace.json`** — `commit` plugin description updated analogously.
- **`docs/plugins/commit.md`** — version bump; expand the "Auto-enforcement" section with the new push-blocking rule (all variants blocked, no escape hatch, user pushes manually after the commit). Mention that `gh` commands and other tools are not affected.
- **`plugins/commit/commands/commit.md`** — short note next to the existing `NEVER push messages to the repository` rule: pushes are additionally enforced by a hook; after creating the commit, ask the user to push manually.

## Verification (manual smoke tests after implementation)

Each of the following must result in `deny`:

1. `git push`
2. `git push origin master`
3. `git push --force`
4. `git push --force-with-lease`
5. `git push --tags`
6. `git push -u origin feature/x`
7. `git push --dry-run`
8. `git -C /tmp/repo push`
9. `git add . && git push`
10. `false; git push` (note: `false; git push` matches because `git push` is followed by end-of-string; bare `git push;ls` without spaces would NOT match — accepted edge case)

Each of the following must pass through (`exit 0`, no `deny`):

11. `git status`
12. `git log --grep="push"` (push is inside a token, not at a token boundary — does not match)
13. `gh pr create`
14. `git pushhh` (typo — `h` after `push` is not whitespace/end-of-string)
15. `git log push-feature` (branch name with hyphen — `-` after `push` is not whitespace/end-of-string)
16. Existing `git commit` flows still work via `AV_COMMIT_SKILL=1` (no regression in `block-git-commit.sh`).

**Known false negatives (accepted):**

- `echo "$(git push)"` — `git push)` (paren after `push`) is not matched. Command substitution of `git push` is rare and the system-prompt rule plus human review remain in place.
- `git push;ls` (no space before `;`) — same reason. Realistic LLM invocations include spaces.

## Risk and mitigation

- **False positives:** the regex requires `git`, whitespace, optional flags, then `push` and a boundary char. Strings like `"git push"` inside an `echo` would match — accepted, since echoing such a string is rare and the deny message is informative, not destructive.
- **False negatives:** novel ways to invoke `git push` that bypass the regex (e.g., aliases, `eval`, encoded). Acceptable — defense in depth, not airtight; the system prompt rule and human review remain in place.
- **Hook ordering:** both hooks share one matcher; the harness runs them in array order. If `block-git-commit.sh` denies, the second hook is irrelevant. If it passes, `block-git-push.sh` evaluates next. No coupling between them.

## Out of scope (YAGNI)

- Escape hatch for `git push` (env var, marker file, dedicated skill).
- Distinct messages for force-push, tag push, or delete push.
- Blocking `gh` push-adjacent commands.
- Telemetry or logging of blocked pushes.
- Backporting older plugin behavior or compatibility shims.

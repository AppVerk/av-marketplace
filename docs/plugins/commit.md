# Commit Plugin

Generate meaningful, well-formatted commit messages following the Conventional Commits specification.

**Version:** 1.3.0

## Commands

### `/commit`

Analyze staged and unstaged changes and generate a commit message.

```bash
# Generate commit message for current changes
/commit

# Include a task ID reference
/commit TASK-123
```

The plugin never auto-pushes — you always review before pushing.

## Commit Message Format

```
type(scope): description

[optional body with details]

Refs: TASK-123
```

### Types

| Type | Use for |
|------|---------|
| `feat` | New features |
| `fix` | Bug fixes |
| `docs` | Documentation changes |
| `style` | Formatting, whitespace |
| `refactor` | Code restructuring |
| `perf` | Performance improvements |
| `test` | Tests |
| `chore` | Build process, tooling |
| `security` | Security fixes |
| `ci` | CI/CD changes |

### Breaking Changes

Indicated with `!` before the colon:

```
feat!: change API response format
```

### Options

| Flag | Effect |
|------|--------|
| `TASK-123` | Adds `Refs: TASK-123` footer |

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

**Known limitations:** The hook is a guardrail against accidental Claude action, not a sandbox. It matches a literal `git` token bracketed by shell delimiters in the top-level Bash command string, so the following forms are not detected:

- **Subprocesses:** Commands like `gh pr create` may invoke `git push` as a subprocess. The hook only inspects the top-level command, so nested processes started by other tools bypass the block.
- **Absolute or relative paths:** `/usr/bin/git push`, `./git push`.
- **Quoted tokens:** `"git" push`, `git "push"`, `'git' push`.
- **Shell wrappers:** `eval "git push"`, `sh -c "git push"`, `bash -c "git push"`, `echo "git push" | bash`.
- **Command substitution / variable indirection:** `$(echo git) push`, `GIT=git; $GIT push`.

These gaps are accepted: Claude does not emit such constructs naturally — it consistently uses bare `git push`, which the hook catches. The user remains the ultimate gate by running `git push` from their own terminal.

Both hooks are registered automatically when the plugin is enabled. No configuration required.

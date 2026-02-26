# Commit Plugin

Generate meaningful, well-formatted commit messages following the Conventional Commits specification.

**Version:** 1.1.0

## Commands

### `/commit`

Analyze staged and unstaged changes and generate a commit message.

```bash
# Generate commit message for current changes
/commit

# Include a task ID reference
/commit TASK-123

# Skip co-author attribution
/commit --no-coauthor

# Combine options
/commit ISSUE-456 --no-coauthor
```

The plugin never auto-pushes — you always review before pushing.

## Commit Message Format

```
type(scope): description

[optional body with details]

Refs: TASK-123
Co-Authored-By: Claude <noreply@anthropic.com>
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
| `--no-coauthor` | Omits the Co-Authored-By line |

## Auto-enforcement

This plugin includes a PreToolUse hook that automatically blocks direct `git commit` commands. When any agent or subagent attempts to run `git commit`, the hook denies the command and instructs the agent to use `/commit` instead.

**What's blocked:**
- `git commit -m "message"`
- `git commit` (interactive)
- Chained commands containing `git commit` (e.g., `git add . && git commit -m "msg"`)

**What's allowed:**
- `git commit --amend` — the `/commit` skill doesn't support amending

The hook is registered automatically when the plugin is enabled. No configuration required.

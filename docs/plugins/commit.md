# Commit Plugin

Generate meaningful, well-formatted commit messages following the Conventional Commits specification.

**Version:** 1.4.0

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

Both hooks are registered automatically when the plugin is enabled. No configuration required.

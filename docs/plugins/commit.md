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

The hook blocks direct `git commit` commands so commits go through the `/commit` skill. It is a guardrail, not enforcement: any command whose text contains `AV_COMMIT_SKILL=1` passes, and so do forms the pattern does not match, such as `git -C <dir> commit` or `git -c key=value commit`.

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
- **`jq` dependency:** both hooks parse their input with `jq`. Without `jq`
  on `PATH`, the `git commit` hook applies its rules to the raw hook input,
  so a direct `git commit` is still denied while `AV_COMMIT_SKILL=1` and
  `--amend` commits pass, and the `git push` hook asks for confirmation on
  every Bash call. The CI image provides `jq`; install it wherever you run
  Claude Code or OMP (see Prerequisites in `docs/installation.md`).

Both hooks are registered automatically when the plugin is enabled. No configuration required.

## Oh My Pi

Install with `omp plugin install commit@av-marketplace`. If you added the marketplace earlier, first run `omp plugin marketplace update av-marketplace`. The command is `/commit:commit [task-id]`.

In OMP, `/commit:commit` runs on the session's model because OMP commands have no model setting; the Claude Code edition runs on Haiku. OMP does not pre-fill context for the command, so the model gathers the status, diff, branch and recent commits with `bash`.

The plugin's OMP extension runs the same two guard scripts concurrently before every agent `bash` call. It waits for both and applies deny before ask before allow; if both deny, the first configured hook's reason is shown. An ask decision opens a confirmation dialog showing the command, a non-default resolved `cwd`, and any non-empty `env` supplied to `bash`. Without a UI (print mode `omp -p` or subagents), every command the push guard would prompt for is blocked. This includes commands it cannot parse: a command containing `push` together with a quoted `git -C "<dir>"` or `git -c key="<value>"`, such as `git -C "$REPO" diff -- scripts/block-git-push.sh`. A guard that fails, runs longer than 10 s, or writes more than 1 MiB to either stdout or stderr blocks the call. Before either guard runs, the extension blocks any `bash` call whose `cwd` does not resolve to an existing directory. It understands only `~`, absolute and relative paths: OMP-only forms that the `bash` tool itself accepts, such as `@/…` and `file://…`, are blocked too, so use a plain absolute or relative path. If the plugin's `extensions/claude-hooks.json` cannot be read or is invalid, the extension blocks every `bash` call; reinstall the plugin.

`jq` is required: without it, the push guard asks on every `bash` call the commit guard lets through. With a UI this opens a dialog; in print mode and subagents the call is blocked.

Delivery 0.4.1 and later mark their own commits, so the guard does not block them. Older versions stop at their first commit; upgrade an installed Delivery with `omp plugin upgrade delivery@av-marketplace`.

If the guard blocks a commit, run `/commit:commit` yourself. The "/commit skill" mentioned in the block reason means this command.

The `git commit` guard remains a guardrail (see [`git commit` block](#git-commit-block)). The `git push` guard ignores the `AV_COMMIT_SKILL=1` marker. Only the command text counts for the commit guard: setting the marker through the `bash` tool's `env` parameter does not pass it.

Only the agent's `bash` tool calls are checked. The extension does not inspect commands run from the `eval` tool (including IPython `!` lines), commands you type with `!`, `omp commit`, the autoresearch `init_experiment` and `log_experiment` tools, or the `github` tool. Its `pr_push` operation pushes the PR branch and, with `forceWithLease`, force-pushes.

# Design: Granular `git push` policy for the `commit` plugin

**Date:** 2026-05-30
**Plugin:** `commit` (1.3.1 → 1.4.0)
**Status:** Approved (pending spec review)

## Problem

The `commit` plugin registers a `PreToolUse` Bash hook (`block-git-push.sh`) that
hard-denies **every** form of `git push` with no exceptions. This is too blunt:
opening a pull request from Claude Code requires first pushing the feature branch
to the remote, and the blanket block prevents that. The result is that ordinary,
safe work (push a feature branch → open a PR) is blocked alongside genuinely
dangerous operations (force-push, pushing straight to the main branch).

Separately, the current detection regex over-matches: it flags any `push`
token that appears after a `git` token anywhere in the command string —
including inside a quoted commit message. So `git commit -m "…git push…"` is
wrongly blocked. (This false-positive was hit while committing this very spec.)
The rewrite fixes it.

We want to keep guarding the dangerous operations while letting normal
Claude Code workflows proceed.

## Goals

- Allow normal pushes of non-protected (feature) branches so PRs can be created
  from Claude Code.
- Keep blocking the genuinely dangerous operations: any force-push, and pushes to
  the protected branches.
- Add an interactive confirmation (`ask`) gate for non-force pushes that target a
  protected branch, instead of an outright block, so a deliberate push to the
  main branch is still possible without leaving Claude Code.
- Degrade safely: when the target branch cannot be determined, prompt (`ask`)
  rather than silently allowing or hard-denying.
- Protect the (now non-trivial) parsing logic against silent regression with an
  automated test, enforced in CI.
- Fix the detection false-positive: match only a real `git push` *subcommand*,
  never the word "push" appearing inside an unrelated argument such as a commit
  message.

## Non-goals

- Changing the `git commit` block (`block-git-commit.sh`) — unchanged.
- Changing `hooks.json` registration — unchanged.
- Making the protected-branch set configurable — fixed to `master` + `main`
  (YAGNI; can revisit later).
- Closing the inherent hook-evasion gaps (subprocesses, shell wrappers, command
  substitution). These remain accepted limitations, as today.

## Policy (decision matrix)

The protected branches are exactly `master` and `main`.

| Operation | Decision |
|---|---|
| Normal push of a feature branch (`git push -u origin fix/login`) | **allow** |
| Bare `git push` while on a feature branch | **allow** (resolved via `git rev-parse`) |
| `git push origin HEAD` on a feature branch | **allow** |
| `gh pr create …` (not a `git push`) | **allow** (not matched) |
| `git commit -m "…git push…"` (push only inside the message) | **allow** (subcommand is `commit`) |
| `git push origin --delete old-feature` (delete a feature branch) | **allow** |
| Bare `git push` while on `master`/`main` | **ask** |
| `git push origin master` / `git push origin HEAD:main` | **ask** |
| `git push origin :master` (delete a protected branch) | **ask** |
| `git push --all` | **ask** (pushes protected branches too) |
| Bare `git push` with undeterminable target (detached HEAD, git error, `git -C` to another repo without a refspec) | **ask** |
| Any force-push: `--force`, `-f`, combined `-fu`/`-uf`, `--force-with-lease[=…]`, `--force-if-includes`, or a `+`-prefixed refspec — on **any** branch | **deny** |
| `git push --mirror` | **deny** |

Two deliberate decisions:

1. **Deleting a feature branch is allowed.** Consistent with the chosen model
   ("block only force + protected"). Deleting a *protected* branch still routes
   to `ask` (its target is `master`/`main`).
2. **`--force-with-lease` on a feature branch is denied.** The chosen model blocks
   *every* force-push, including the "safe" lease variant. Consequence: after
   rebasing a PR branch, Claude cannot force-update it — the user pushes it
   themselves. Accepted trade-off.

`deny` and `ask` correspond to the hook's `permissionDecision` values; `allow`
means the hook exits 0 with no JSON.

## Detection algorithm (`block-git-push.sh`)

The hook reads `tool_input.command` from stdin (as today) and applies a
**priority cascade** — the first matching rule wins:

```
0. Is there a real `git push` *subcommand* invocation?
   For each `git` token bracketed by a shell delimiter (line start, whitespace,
   or one of ; & | ` ( ), find the first following token that is NOT a global
   option (or an option's value) and test whether it is `push`:
     • skip global options that may precede the subcommand: --git-dir[=…],
       --work-tree[=…], --namespace[=…], --exec-path[=…], -C <path>, -c <key=val>
       (bare `-C` / `-c` also consume the next token as their value)
     • the first remaining non-option token is the git subcommand
   Match only when that subcommand is `push`. This deliberately does NOT match a
   `push` that appears later as an argument — e.g. `git commit -m "…git push…"`
   has subcommand `commit`, so it is ignored (fixes the false-positive).
   Steps 1–4 below operate on the tokens of the matched `push` invocation
   (from `push` up to the next top-level shell delimiter), not the whole command
   line — so a force flag belonging to a different chained command is not
   mistaken for a force-push.
   └─ no `git push` subcommand found → exit 0 (allow; not a push command)

1. FORCE?  Detect any of:
     --force            (word-boundary)
     --force-with-lease[=…]
     --force-if-includes
     short cluster containing f: -f, -fu, -uf, … (regex: (^|\s)-[a-zA-Z]*f[a-zA-Z]*)
     a refspec token with a leading '+' (e.g. +HEAD:master, +feat/x, +src:dst)
   └─ YES → DENY

2. --mirror present?
   └─ YES → DENY

3. Determine the remote-side target branch(es):
   • Explicit refspec(s): take the destination — the part after ':' if present
       HEAD:master → master ; local:feat → feat ; :master → master (delete)
     Strip a leading 'refs/heads/'.
   • A bare 'HEAD' refspec (no ':') → resolve to the current branch.
   • No refspec at all (bare `git push`, `git push origin`, `git push -u origin`)
       → resolve current branch via `git rev-parse --abbrev-ref HEAD`
         (honor a `git -C <path>` in the command when present).
   • `--all` flag → treat as targeting the protected branches.

4. Classify:
   • any resolved target ∈ {master, main}     → ASK
   • target undeterminable                     → ASK
       (detached HEAD returns "HEAD"; git error; `git -C <other-repo>` without
        an explicit refspec; command substitution we cannot evaluate)
   • otherwise (feature branch)                → exit 0 (ALLOW)
```

Force detection (step 1) takes precedence over branch classification: a
force-push to a feature branch is still `deny`, and a force-push to `master` is
`deny` (not `ask`).

### Branch-name matching

Match the resolved target against the literal names `master` and `main`. After
stripping any `refs/heads/` prefix and the source side of a `src:dst` refspec.

### `git -C` / `--git-dir` handling

If the command resolves the current branch (no explicit refspec) and uses
`-C <path>` / `--git-dir` / `--work-tree`, the hook attempts `git -C <path>
rev-parse …`. If that cannot be parsed reliably, the target is treated as
undeterminable → `ask`.

## Hook output contract

- **deny** — emit:
  ```json
  {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
   "permissionDecisionReason":"<reason>"}}
  ```
  Force reason: force-push is blocked; run it yourself from your terminal.
  Mirror reason: `--mirror` can overwrite/delete remote refs and is blocked.
- **ask** — same shape with `"permissionDecision":"ask"`.
  Protected reason: this push targets a protected branch (master/main); confirm
  you intend to push directly to the main branch.
  Undeterminable reason: the target branch could not be verified; confirm this
  push is safe.
- **allow** — `exit 0` with no output.

In all branches the script exits 0 (the decision lives in the JSON, matching the
existing convention).

## Edge cases & accepted limitations

Documented in `docs/plugins/commit.md`. Inherited from the hook's nature — it
inspects only the top-level command string:

- **Subprocesses:** `gh pr create` (and similar) may invoke `git push`
  internally; the hook does not see nested processes — they pass.
- **Shell wrappers / substitution:** `sh -c "git push --force"`,
  `$(echo git) push`, `eval "git push -f"` bypass force detection — as today.
- **Foreign repo without a refspec:** `git -C /other/repo push` without an
  explicit refspec degrades to `ask` rather than resolving the wrong branch.

These are guardrails against accidental Claude action, not a sandbox. The user
remains the ultimate gate.

## Files changed

| File | Change |
|---|---|
| `plugins/commit/scripts/block-git-push.sh` | Rewrite per the algorithm above |
| `plugins/commit/.claude-plugin/plugin.json` | `version` → `1.4.0`; description → "Generate meaningful commit messages and block dangerous git push" |
| `.claude-plugin/marketplace.json` | `commit.version` → `1.4.0`; matching description |
| `README.md` | Available Plugins table: version `1.4.0`; description → "Auto-blocks direct `git commit`; blocks force-push and pushes to `master`/`main` via hooks" |
| `docs/plugins/commit.md` | Rewrite the "`git push` block" section (new matrix, allow/ask/deny, limitations); bump `**Version:**` to `1.4.0` |
| `plugins/commit/tests/test-block-git-push.sh` | New: decision-matrix test harness |
| `.github/workflows/` | Add a CI step/job running the hook test |

`plugins/commit/scripts/block-git-commit.sh`, `plugins/commit/hooks/hooks.json`,
and `plugins/commit/commands/commit.md` are **unchanged**.

## Versioning

`1.3.1 → 1.4.0` (MINOR). The change adds capability (granular policy) and relaxes
a restriction; no command is removed and the `/commit` workflow is unchanged. The
CI `plugin-version-parity.yml` check enforces that `1.4.0` appears in all four
canonical locations (plugin.json, marketplace.json, README.md table, docs header).

## Testing

A self-contained harness `plugins/commit/tests/test-block-git-push.sh`
(plain bash + `jq` + `git`, no `bats` dependency):

- Pipes a JSON payload `{"tool_input":{"command":"<cmd>"}}` into the hook and
  asserts the resulting `permissionDecision` (or allow = empty output, exit 0).
- Covers every row of the decision matrix plus edge cases: combined short flags
  (`-fu`), `+`-prefixed refspec, `HEAD:master`, `:master` delete, `--all`,
  `--mirror`, feature-branch delete, and the false-positive guard
  (`git commit -m "…git push…"` must be allowed; `git -C <path> push` must still
  be matched).
- For branch-resolution cases (bare `git push`, `HEAD`, detached HEAD), the
  harness creates a throwaway git repo in a temp dir, checks out the relevant
  branch (or detaches HEAD), runs the hook with that repo as the working
  directory, and asserts the decision.
- Prints a pass/fail summary and exits non-zero on any failure.

**CI:** add a job/step (extend `plugin-version-parity.yml` or a new workflow)
that runs the harness on `pull_request` and `push` to `master`. `ubuntu-latest`
provides bash, `jq`, and `git`. This prevents silent regression of the guardrail.

## Out of scope / future

- Configurable protected-branch set (env var).
- Allowing `--force-with-lease` on feature branches.
- Treating feature-branch deletion as `ask`.
- Closing subprocess/wrapper evasion gaps.

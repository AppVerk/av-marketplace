# Design: Granular `git push` policy for the `commit` plugin

**Date:** 2026-05-30
**Plugin:** `commit` (1.3.1 → 1.4.0)
**Status:** Approved — hardened after multi-agent verification (pending final spec review)

## Problem

The `commit` plugin registers a `PreToolUse` Bash hook (`block-git-push.sh`) that
hard-denies **every** form of `git push` with no exceptions. This is too blunt:
opening a pull request from Claude Code requires first pushing the feature branch
to the remote, and the blanket block prevents that. The result is that ordinary,
safe work (push a feature branch → open a PR) is blocked alongside genuinely
dangerous operations (force-push, pushing straight to the main branch).

Separately, the current detection regex over-matches: it flags any `push` token
that appears after a `git` token anywhere in the command string — including
inside a quoted commit message. So `git commit -m "…git push…"` is wrongly
blocked. (This false-positive was hit while committing this very spec.) The
rewrite fixes it.

We want to keep guarding the dangerous operations while letting normal Claude
Code workflows proceed.

## Goals

- Allow normal pushes of non-protected (feature) branches to `origin` so PRs can
  be created from Claude Code.
- Keep blocking the genuinely dangerous operations: any force-push, `--mirror`,
  and deletion of a protected branch.
- Add an interactive confirmation (`ask`) gate — not an outright block — for the
  borderline operations: a non-force push to a protected branch, a tag push, and
  a push to a remote other than `origin`.
- Degrade safely: whenever the hook cannot determine an answer reliably, it
  decides `ask` — never a silent `allow`.
- Fix the detection false-positive: match only a real `git push` *subcommand*,
  never the word "push" inside an unrelated argument such as a commit message.
- Protect the (non-trivial) parsing logic against silent regression with an
  automated test, enforced in CI.

## Non-goals

- Changing the `git commit` block (`block-git-commit.sh`) — unchanged.
- Changing `hooks.json` registration — unchanged.
- Making the protected-branch set configurable — fixed to `master` + `main`.
- Scanning push *content* for secrets — out of scope (a different tool's job);
  see the secret-leak note under "Edge cases & accepted limitations".
- Closing the inherent hook-evasion gaps (subprocesses, shell wrappers, command
  substitution). These remain accepted limitations, as today.

## Policy (decision matrix)

Protected branches are exactly `master` and `main`. The default/expected remote
is `origin`.

Rows are grouped by decision, **not** by evaluation order. The hook evaluates a
priority cascade (see the algorithm); precedence is roughly
**force → mirror → protected-delete → (non-origin / tag / protected-target / undeterminable) → allow**.

| Operation | Decision |
|---|---|
| Normal push of a feature branch to origin (`git push -u origin fix/login`) | **allow** |
| Bare `git push` whose upstream is a feature branch on origin | **allow** (resolved via `@{push}`) |
| `git push origin HEAD` on a feature branch | **allow** |
| `gh pr create …` (not a `git push`) | **allow** (not matched) |
| `git commit -m "…git push…"` (push only inside the message) | **allow** (subcommand is `commit`) |
| `git push origin --delete old-feature` / `git push origin :old-feature` (delete a feature branch) | **allow** |
| `git status`, non-git commands, "push" as data | **allow** (no push subcommand) |
| Bare `git push` whose upstream is `master`/`main` | **ask** |
| `git push origin master` / `git push origin HEAD:main` | **ask** |
| `git push origin feat/x master` (multi-refspec, one protected) | **ask** |
| `git push --all` | **ask** (publishes all local branches, incl. protected) |
| `git push --tags` / `git push --follow-tags` / `git push origin v2.0.0` (tag) | **ask** (may trigger a release) |
| `git push <other-remote> …` / `git push https://host/repo.git …` (non-origin or URL) | **ask** |
| Bare `git push` with undeterminable target (detached HEAD, no upstream, git error, quoting/`cd` we cannot resolve) | **ask** |
| Any force-push: `--force`, `-f`, short cluster containing `f` (`-fu`/`-uf`), `--force-with-lease[=…]`, `--force-if-includes`, or a `+`-prefixed refspec — on **any** branch | **deny** |
| `git push --mirror` | **deny** |
| `git push origin :master` / `git push origin --delete master` (delete a protected branch) | **deny** |

Deliberate decisions:

1. **Deleting a feature branch is allowed** (consistent with "block only the
   dangerous set"). Deleting a *protected* branch is **deny** (upgraded from
   `ask` after review — destroying the trunk is categorically worse than adding a
   commit to it, and matches the `--mirror` "destroys refs" reasoning).
2. **`--force-with-lease` on a feature branch is denied.** The chosen model
   blocks *every* force-push, including the "safe" lease variant. Consequence:
   after rebasing a PR branch, Claude cannot force-update it — the user pushes it
   themselves. Accepted trade-off.
3. **`--dry-run`/`-n` is not special-cased.** A dry-run to a protected branch
   still routes to `ask`. This is minor friction on a no-op; not worth a special
   case.

`deny` and `ask` correspond to the hook's `permissionDecision` values; `allow`
means the hook exits 0 with no JSON. Per Claude Code, when several PreToolUse
hooks fire on the same matcher the most restrictive decision wins
(`deny > ask > allow`); the commit-block and push-block hooks key off different
subcommands, so they do not interfere.

## Detection algorithm (`block-git-push.sh`)

The hook reads the JSON payload from stdin. It uses two fields:
`tool_input.command` (the command string) and `cwd` (Claude Code's working
directory, supplied in the payload). Branch resolution runs git against `cwd`
(or an explicit `-C`/`--git-dir` when the command provides one).

**Overarching safety rule:** any step that cannot determine its answer reliably
yields **ASK**, never a silent ALLOW.

```
0. Identify a real `git push` SUBCOMMAND.
   For each `git` token bracketed by a shell delimiter (line start, whitespace,
   or one of ; & | ` ( ), find the first following token that is NOT a global
   option (or an option's value), and test whether it equals `push`:
     • skip global options that may precede the subcommand:
         --git-dir[=…], --work-tree[=…], --namespace[=…], --exec-path[=…]
           (these accept BOTH `--opt=val` and `--opt val` forms)
         -C <path>, -c <key=val>
           (git rejects glued `-C/path`/`-cfoo=bar`; these ALWAYS take a separate
            value token — consume exactly the next token as the value)
     • the first remaining non-option token is the git subcommand
   Match only when that subcommand is `push`. This does NOT match a `push` that
   appears later as an argument — e.g. `git commit -m "…git push…"` has
   subcommand `commit`, so it is ignored (fixes the false-positive).
   Delimiter detection is whitespace/quote-UNAWARE (best-effort); if a global
   option's value token has an unbalanced quote (e.g. `-c user.name='A B'` splits
   into `'A` … `B'`) the subcommand cannot be read reliably → ASK.
   └─ no `git push` subcommand found, reliably → exit 0 (allow; not a push)

   Steps 1–7 below operate on the tokens of the matched push invocation (from
   `push` up to the next best-effort shell delimiter), not the whole command.

1. FORCE?  Detect any of (within the push invocation, scanning option tokens
   only — stop at a bare `--` end-of-options marker; tokens after `--` are
   refspecs, not flags):
     --force                       (explicit)
     --force-with-lease[=…]        (explicit)
     --force-if-includes           (explicit)
     a single-dash short cluster containing `f`  (push short flags are
       -u -f -n -q -v -d; regex on one token: ^-[A-Za-z0-9]*f[A-Za-z0-9]*$)
     a refspec token whose first char (after an optional remote) is `+`
       (e.g. +HEAD:master, +feat/x, +src:dst)
   The cluster regex deliberately does NOT match `--`-prefixed long options, so
   the explicit `--force*` checks above are REQUIRED — do not drop them.
   └─ YES → DENY

2. --mirror present?  → DENY

3. Parse remote + refspecs (positional):
     • first non-option token after `push` (before any `--`) = REMOTE
     • each remaining non-option token = a REFSPEC
     • if no remote/refspec given (bare push) → resolve via @{push}, see step 5
   For each REFSPEC: strip a leading `+`; split on the LAST `:`
     (dst = field after the last colon, or the whole token if no colon);
     strip a leading `refs/heads/`; a bare `HEAD` dst → current branch.
   A refspec of the form `:dst` (empty src) or a `--delete <ref>` flag = a
   DELETE of dst.

4. PROTECTED-BRANCH DELETE?  any delete whose dst ∈ {master, main}  → DENY

5. Resolve the target(s) and remote for classification:
     • Explicit form: REMOTE + each refspec dst (from step 3).
     • Bare push (no remote/refspec): run
         git -C <effective-dir> rev-parse --abbrev-ref --symbolic-full-name @{push}
         (fall back to @{upstream}); output `remote/branch` →
         REMOTE = part before first `/`, target branch = the rest.
       `--abbrev-ref HEAD` is NOT used: it returns the LOCAL branch name, which
       can differ from the pushed remote branch under push.default=upstream /
       a configured refspec, causing a false ALLOW to a protected branch.
     • `--all` flag → treat as targeting the protected branches (publishes all).
   <effective-dir> = the command's `-C <path>` / `--git-dir` if present, else the
   payload `cwd`. If the command has a repo-changing prefix we cannot honor
   (e.g. `cd /other && git push`) and needs resolution → target undeterminable.
   Any git error, detached HEAD ("HEAD"), or missing upstream → undeterminable.

6. NON-ORIGIN / URL REMOTE?  if REMOTE is a URL (contains `://`, or scp-like
   `user@host:path`) or a configured remote name other than `origin`  → ASK

7. Classify (first match wins):
     • TAG push: `--tags`/`--follow-tags`, or a refspec dst under `refs/tags/`,
       or (best-effort) a bare-name dst that resolves as an existing tag via
       `git -C <effective-dir> show-ref --verify --quiet refs/tags/<name>` → ASK
     • any target branch ∈ {master, main}                                  → ASK
     • target undeterminable                                               → ASK
     • otherwise (feature branch, origin, no force/mirror/delete)          → exit 0 (ALLOW)
```

Precedence: force/mirror/protected-delete (DENY) are checked before any ASK
condition, so a force-push to a protected branch or a force-delete is DENY, not
ASK.

### Branch-name matching

Match the resolved dst against the literal names `master` and `main`, after
stripping a `refs/heads/` prefix and taking the destination side of a `src:dst`
refspec.

## Hook output contract

Verified against the Claude Code hooks reference: `PreToolUse` supports
`permissionDecision` values `allow`/`deny`/`ask`; the JSON shape and field names
below are correct; the hook receives `tool_input.command` and `cwd` on stdin;
the convention is "exit 0 with JSON to decide, exit 0 with no output to allow".

Emit (with `permissionDecision` = `deny` or `ask`):

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse",
 "permissionDecision":"deny","permissionDecisionReason":"<reason>"}}
```

Exact `permissionDecisionReason` strings (pinned so implementation and tests do
not drift):

| Trigger | `permissionDecision` | `permissionDecisionReason` |
|---|---|---|
| Force-push | `deny` | `Force-push is blocked for Claude Code. If you intend to force-push, run it yourself from your terminal.` |
| `--mirror` | `deny` | `git push --mirror can overwrite or delete remote refs and is blocked.` |
| Delete protected branch | `deny` | `Deleting a protected branch (master/main) is blocked. Run it yourself from your terminal if intended.` |
| Non-origin / URL remote | `ask` | `This push targets a remote other than 'origin' (or a URL). Confirm you intend to push there.` |
| Tag push | `ask` | `This push publishes a tag, which may trigger a release. Confirm you intend to push it.` |
| Protected branch (add commits) | `ask` | `This push targets a protected branch (master/main). Confirm you intend to push directly to it.` |
| Undeterminable target | `ask` | `The push target could not be verified. Confirm this push is safe.` |

`allow` → `exit 0` with no output. In all branches the script exits 0 (the
decision lives in the JSON).

## Edge cases & accepted limitations

Documented in `docs/plugins/commit.md`. The hook inspects only the top-level
command string and cannot run a real shell parser, so these are accepted:

- **Subprocesses:** `gh pr create` (and similar) may invoke `git push`
  internally; the hook does not see nested processes — they pass.
- **Shell wrappers / substitution:** `sh -c "git push --force"`,
  `$(echo git) push`, `eval "git push -f"` bypass detection — as today.
- **Quote-unaware tokenization:** commands whose quoting we cannot resolve
  (e.g. delimiters or option values inside quotes) degrade to `ask` rather than a
  silent allow.
- **Repo-changing prefixes / foreign repos:** `cd /other && git push` or a
  `-C`/`--git-dir` we cannot resolve degrade branch resolution to `ask`.
- **Secret-leak boundary shift (informational):** allowing feature-branch pushes
  means an agent can now publish a branch that contains accidentally-committed
  secrets to a remote. The previous all-deny hook made this impossible *via
  Claude*; the relaxation shifts that boundary. The non-origin/URL `ask` gate
  mitigates exfiltration to attacker-controlled remotes, but pushing to a public
  `origin` is the highest-blast-radius *allowed* operation. Content scanning is
  out of scope.

These are guardrails against accidental Claude action, not a sandbox. The user
remains the ultimate gate.

## Files changed

| File | Change |
|---|---|
| `plugins/commit/scripts/block-git-push.sh` | Rewrite per the algorithm above |
| `plugins/commit/.claude-plugin/plugin.json` | `version` → `1.4.0`; description → "Generate meaningful commit messages and block force-push while guarding pushes to protected branches" |
| `.claude-plugin/marketplace.json` | `commit.version` → `1.4.0`; matching description |
| `README.md` | Available Plugins table: version `1.4.0`; description → "Conventional Commits message generation. Auto-blocks direct `git commit`; blocks force-push/`--mirror`/protected-branch deletion and prompts on pushes to `master`/`main`, tags, and non-origin remotes" |
| `docs/plugins/commit.md` | Rewrite the "`git push` block" section (new matrix, deny/ask/allow, limitations); bump `**Version:**` to `1.4.0` |
| `plugins/commit/tests/test-block-git-push.sh` | New: decision-matrix test harness |
| `.github/workflows/commit-hook-test.yml` | New: CI workflow running the hook test |

`plugins/commit/scripts/block-git-commit.sh`, `plugins/commit/hooks/hooks.json`,
and `plugins/commit/commands/commit.md` are **unchanged**. The README plugin-count
badge is unchanged (no plugin added/removed).

## Versioning

`1.3.1 → 1.4.0` (MINOR). The change adds capability (graduated policy) and
relaxes a restriction; no command is removed and the `/commit` workflow is
unchanged. The CI `plugin-version-parity.yml` check enforces that `1.4.0` appears
in all four canonical locations in the exact formats it parses:
`plugins/commit/.claude-plugin/plugin.json` (`.version`),
`.claude-plugin/marketplace.json` (`.plugins[name==commit].version`),
the README table row (`| [Commit](docs/plugins/commit.md) | 1.4.0 | … |`,
version in column 2), and `docs/plugins/commit.md` (`**Version:** 1.4.0`).

## Testing

A self-contained harness `plugins/commit/tests/test-block-git-push.sh`
(plain bash + `jq` + `git`, no `bats` dependency):

- Pipes a JSON payload `{"tool_input":{"command":"<cmd>"},"cwd":"<dir>"}` into
  the hook and asserts the resulting `permissionDecision` (or allow = empty
  output, exit 0).
- For branch-resolution cases, the harness creates throwaway git repos in temp
  dirs and exercises real configurations, including:
  - bare `git push` on a feature branch and on `master`/`main`;
  - **a repo whose `push.default=upstream` with a local branch tracking a
    differently-named protected remote branch** (locks in the `@{push}`
    resolution from step 5 — a plain `--abbrev-ref HEAD` would wrongly ALLOW);
  - detached HEAD / no upstream → `ask`;
  - an existing tag, to exercise the best-effort tag check.
- Covers every decision-matrix row plus edge cases: combined short flags
  (`-fu`, `-nf`), `+`-prefixed refspec, `HEAD:master`, `:master` (deny),
  `:old-feature` (allow), `--all`, `--mirror`, `--tags`, `git push origin v2.0.0`,
  non-origin name, URL remote, multi-refspec (feature+protected), global-option
  prefixes (`-c k=v push`, `--git-dir=… push`, `git -C dir push`), a quoted
  `-c` value with spaces (→ ask), and **negative/no-op cases**
  (`git status`, a non-git command, `git commit -m "…git push…"`).
- Prints a pass/fail summary and exits non-zero on any failure.

**CI:** a new workflow `.github/workflows/commit-hook-test.yml`, triggered on
`pull_request` and `push` to `master` with `paths: [plugins/commit/**]`, runs the
harness in a single step (`run: plugins/commit/tests/test-block-git-push.sh`).
`ubuntu-latest` ships bash, `jq`, and `git`. Kept separate from the
Python-only `plugin-version-parity.yml` to avoid mixing concerns.

## Out of scope / future

- Configurable protected-branch set (env var).
- Allowing `--force-with-lease` on feature branches.
- Treating feature-branch deletion as `ask`.
- Special-casing `--dry-run` as unconditional `allow`.
- Push-content secret scanning.
- Closing subprocess/wrapper evasion gaps.

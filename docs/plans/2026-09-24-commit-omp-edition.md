# Commit: OMP edition with the git commit and push guards

## Context

`plugins/commit/` (1.4.0) has three parts; each needs something the OMP edition does not provide today:

1. **`/commit` command** (`commands/commit.md`). Frontmatter `allowed-tools`, `description`, `argument-hint`, `model: haiku`. The body pre-fills context with Claude Code's inline shell syntax (!`git status`, !`git diff HEAD`, !`git branch --show-current`, !`git log --oneline -10`) and reads the task ID from `$1`. OMP 18.3.0 substitutes `$1` but leaves the inline shell syntax as literal text (checked: rendering `commit.md` through `expandSlashCommand` in `src/extensibility/slash-commands.ts` keeps the `Current git status` line verbatim). The generator already keeps only `description` and `argument-hint`. OMP commands have no model setting, so the command runs on the session model. In OMP the command is `/commit:commit`.
2. **Two PreToolUse hooks on Bash** (`hooks/hooks.json` → `scripts/block-git-commit.sh`, `scripts/block-git-push.sh`). They read Claude's hook JSON (`.tool_input.command`, `.cwd`) on stdin and print `hookSpecificOutput.permissionDecision` `deny` or `ask`, or nothing for allow. OMP 18.3.0 has no support for `hooks.json` or command hooks (no `hooks.json`/`PreToolUse` anywhere in its source). Its equivalent is an extension `tool_call` handler. The design relies on these OMP 18.3.0 facts:
   - A handler returns `{ block: true, reason }` to block, and `reason` becomes the tool result the model sees (an empty reason is replaced by a generic "Tool execution was blocked by an extension"); `undefined` allows. For `bash`, `event.input` is the raw tool input (`command`, `cwd`, `env`, `timeout`, …).
   - Each `tool_call` handler gets 30 s (`extensionHandlers.toolCallTimeoutMs`, `src/extensibility/extensions/runner.ts:94`); time spent in `ctx.ui.confirm` does not count. A handler that times out or throws blocks the call (fail closed), but OMP does not kill processes the handler started.
   - An extension whose default export throws at load is dropped with a warning, and the session continues without it. An exception thrown from a raw `setTimeout` callback is fatal to the whole OMP process (`src/extensibility/extensions/managed-timers.ts`).
   - `ctx.hasUI` is false in print mode (`omp -p`) and in subagents, where `ctx.ui.confirm` returns `false`. Every subagent, tool-restricted ones included, binds the parent session's prepared extensions again (`src/task/structured-subagent.ts:517`, `src/sdk.ts:2250`), so the guard runs there too.
   - A marketplace plugin declares extensions in its root `package.json` (`omp.extensions`), as `omp/native/delivery/` does. OMP imports an installed extension by its real path in the plugin cache (`~/.omp/plugins/cache/plugins/av-marketplace___<plugin>___<version>/`), so `path.dirname(import.meta.dir)` is the installed plugin root, and that directory's name is not the plugin name.
   - Bun 1.3.14 (OMP's runtime and CI's) passes runtime changes of `process.env` to a child process only when `env` is given explicitly.
3. **Tests** (`tests/test-block-git-push.sh`, CI `commit-hook-test.yml`). These stay as they are.

The generator (`scripts/build_omp_edition.py`) rejects any source entry outside `KNOWN_ENTRIES` (line 51), so an overlay for `commit` fails today with `no OMP mapping for ['hooks']`.

Delivery conflicts with the guard. `omp/native/delivery/skills/orchestration/SKILL.md` commits with `git commit -m "<subject>" -- "$PLAN_PATH"` (step 10), `printf '%s' "$MSG" | git commit -F -` (section 2) and `git commit -m "docs: add review of delivery $SLUG" -- "<report path>"` (section 5). `block-git-commit.sh` denies all three (checked by piping them into the script). With `AV_COMMIT_SKILL=1` in the command it allows them. Once the commit edition is installed, every run of delivery 0.4.0 or older stops at its first commit.

Base: commit 1767ba5, which holds the plan-review work. `python3 scripts/build_omp_edition.py --check` exits 0 there, and this plan file is the only change in the tree. Delivery's preflight ignores the plan file and stops on any other change; each task here is staged with `git add -A`.

Routing: Tasks 1, 3, 4 and 5 go to `delivery:implementer` (no React `package.json` above `omp/`), Task 2 to `python-developer:developer`. `plugins/commit/` does not change, so the commit plugin stays at 1.4.0 in all four version places, and its OMP edition ships as 1.4.0 (generated versions come from `.claude-plugin/marketplace.json`). Delivery goes to 0.4.1.

## Decisions

- **One generic hooks extension, not a TypeScript port of the policy.** The shell scripts stay the only source of the git policy and keep their existing tests. `omp/claude-hooks/claude-hooks.ts` runs the PreToolUse command hooks that a generated plugin declares on `Bash`. Bash is the only supported matcher: its OMP input carries `command` as Claude's does, while OMP's `read`, `write` and `edit` take `path` where Claude's hooks read `file_path`. The generator does the mapping and fails the build on anything the extension cannot run, like the other total mappings.
- **`ask` → confirmation dialog; no UI → blocked.** This covers print mode and subagents.
- **Fail closed.** The call is blocked when a hook crashes, times out (10 s per hook, inside OMP's 30 s handler budget) or prints output the extension cannot read, and when the hook config or the bash working directory cannot be resolved. This departs from Claude Code, where a timeout or an exit code other than 2 does not block. These hooks are guards, and OMP's own handler wrapper also fails closed. The extension's header lists the known deviations from Claude Code's PreToolUse contract.
- **!`…` inline context → a preamble bullet** telling the model to run such commands with `bash`. The body stays unchanged, as for every other generated file.
- **Delivery marks its commits with `AV_COMMIT_SKILL=1`.** Its commit subjects come from the plan's `**Commit:**` lines, which the plan format asks to be Conventional Commits, and it adds `Delivery-*` trailers; it has no need to go through `/commit`. As in the Claude edition, the guard is a guardrail, not enforcement: any command whose text carries the marker passes the commit guard.
- **`jq` is required.** Without it, the commit script applies its rules to the raw hook input, so its decisions stay the same, while the push script asks on every Bash call. In OMP that blocks every `bash` call in print mode and in subagents. Task 5 documents this and fixes the stale `jq dependency` paragraph in `docs/plugins/commit.md`, which says the hooks let commands through without `jq`.

Out of scope: simple-language's `SessionStart` hook (it has no OMP overlay); the scripts' own reason texts ("Use the /commit skill", "blocked for Claude Code"), which stay unchanged in both editions; Windows (the hooks are bash scripts, and the timeout kills a POSIX process group).

## Approach

### Task 1: Claude hooks extension for OMP
**Commit:** feat(omp-edition): add an OMP extension that runs a plugin's Claude PreToolUse command hooks

**Files:**
- Create: `omp/claude-hooks/claude-hooks.ts`
- Test: `omp/claude-hooks/tests/claude-hooks.test.ts`
- Modify: `.github/workflows/omp-edition.yml`

One extension, shared by every generated plugin whose Claude source has `hooks/hooks.json`. A later task in this plan makes the generator copy this file unchanged to `plugins-omp/<plugin>/extensions/claude-hooks.ts` and write the mapped hooks next to it as `extensions/claude-hooks.json`; do not change the generator in this task. The extension holds no git policy.

Contract (a later test imports the default export of the generated copy):
```ts
export type HookEntry = { tool: string; claudeTool: string; command: string };
export type HookConfig = { PreToolUse: HookEntry[] };
export function createClaudeHooks(root: string, config: HookConfig, options?: { timeoutMs?: number }): (pi: ExtensionAPI) => void;
export default function claudeHooks(pi: ExtensionAPI): void;
```
- `tool` is the OMP tool name (`bash`), `claudeTool` the Claude matcher (`Bash`), `command` a script path relative to `root` (`scripts/block-git-commit.sh`).
- `<plugin>` in reasons is the string `name` in `<root>/package.json` (the generator writes it). When that file is missing, unreadable, not valid JSON, or has no string `name`, use `path.basename(root)`; reading it never throws. Installed copies live in a cache directory named `av-marketplace___<plugin>___<version>`, so the basename alone is not the plugin name.
- The default export sets `root = path.dirname(import.meta.dir)` and reads `path.join(import.meta.dir, "claude-hooks.json")` when OMP calls it, not at import. If the file is missing or is not a valid config, the default export registers a `tool_call` handler that blocks every call of the tools listed in `HOOKABLE_TOOLS = ["bash"]`, with the reason `<plugin>: extensions/claude-hooks.json cannot be read (<error>). The call is blocked; reinstall the plugin.` Put a comment on `HOOKABLE_TOOLS`: it lists the OMP tools that the generator (`HOOK_TOOL_MAP` in `scripts/build_omp_edition.py`, added later in this plan) maps hooks to, and the two lists must stay equal. The default export must never throw: OMP would drop the extension and run without guards.
- Import OMP types with `import type` only. The file and its tests must run without OMP installed next to them; CI runs these tests before it installs OMP.
- A header comment lists the known deviations from Claude Code's PreToolUse contract:
  - hooks run one after another, not in parallel;
  - stdin carries only the fields below; `tool_input` is OMP's `bash` input (`timeout` in seconds, `cwd`, `env`, `pty`, `async`, …); in subagents `session_id` is the subagent's own session, and `agent_id`/`agent_type` are absent;
  - only `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PROJECT_DIR` are set, and `CLAUDE_PROJECT_DIR` is `ctx.cwd` (a subagent's worktree when isolated);
  - exit 0 with output that is not JSON, a JSON object without a PreToolUse decision, any exit code other than 0 and 2 (even with JSON output), and a timeout all block; each hook gets 10 s (Claude Code: 600 s by default, adjustable with a `timeout` key, which the generator rejects);
  - on exit 2 the reason is stderr, even when stdout holds a JSON reason;
  - `allow` does not bypass OMP's own approval; an `ask` reason reaches the model when the call is blocked;
  - `defer`, `updatedInput`, `additionalContext`, `systemMessage`, `continue`/`stopReason` and the top-level `decision` field are not supported;
  - POSIX only.

`tool_call` handler:
1. Select the entries whose `tool` equals `event.toolName`, in config order. With none, return `undefined` without spawning anything.
2. Resolve the hook's working directory `cwd` with this subset of OMP's `resolveToCwd` (`src/tools/path-utils.ts`). If `input.cwd` is not a non-empty string → `ctx.cwd`. A leading `~` expands to the home directory. Only slashes → `ctx.cwd`. An absolute path stays unchanged. Otherwise → `path.resolve(ctx.cwd, input.cwd)`. If the result is not an existing directory, return `{ block: true, reason: "<plugin>: cannot resolve the bash cwd (<input.cwd>); use a plain absolute or relative path." }`; OMP-only forms (`@/…`, `file://…`, internal URLs) end up here. A leading `cd <dir> &&` in the command is not resolved: as in Claude Code, the hook sees the directory the command starts in.
3. For each entry, spawn `bash <root>/<command>` with `Bun.spawn`:
   - stdin: `new Blob([JSON.stringify({ session_id, hook_event_name: "PreToolUse", tool_name: claudeTool, tool_input: event.input, tool_use_id: event.toolCallId, cwd })])`, with `session_id = ctx.sessionManager.getSessionId()`. Use a Blob, not a pipe you write to: a hook that exits without reading stdin must not cause EPIPE;
   - process cwd: `ctx.cwd`;
   - env: `{ ...process.env, CLAUDE_PLUGIN_ROOT: root, CLAUDE_PROJECT_DIR: ctx.cwd }`, built at each spawn, because Bun children do not see runtime `process.env` changes otherwise;
   - `detached: true`, so the hook gets its own process group;
   - timeout: `timeoutMs` defaults to 10 000 ms per hook, so both commit hooks finish inside OMP's 30 s handler budget. Arm one timer per run and clear it only once the run has settled: exit code received, and stdout and stderr read to the end. Until then the timer may still fire; a child that keeps the hook's output open counts as a timeout. When the timer fires, run `try { process.kill(-proc.pid, "SIGKILL") } catch {}` (ESRCH means the group is already gone; an exception thrown from the timer callback would kill OMP) and settle the run as a timeout without waiting for its pipes to close, because bash's children (`sleep`, `git`, `jq`) would otherwise keep them open.
4. Map each run to an outcome:
   - exit 0 with stdout empty after trim → allow;
   - exit 0 with stdout a JSON object whose `hookSpecificOutput.permissionDecision` is `allow`, `ask` or `deny` → that decision, with reason `hookSpecificOutput.permissionDecisionReason`. When that reason is absent or empty, use `<plugin> hook <command> denied this call.` for deny and `<plugin> hook <command> asks for confirmation.` for ask;
   - exit 2 → deny, with reason the trimmed stderr, or `<plugin> hook <command> blocked this call.` when stderr is empty;
   - anything else (another exit code, timeout, unparsable stdout, a JSON object without that decision, an unknown decision, a spawn error) → deny, with reason `<plugin> hook <command> failed: <exit code N | timeout | error text>. The call is blocked.`
5. The first deny returns `{ block: true, reason }` at once; later entries do not run. Ask decisions are collected. After the last entry, if there was an ask, take the reason of the first one:
   - with `ctx.hasUI`: `await ctx.ui.confirm("Confirm command", message)`. `message` is the reason, a blank line, then `shown`; `shown` is `input.command` when it is a string, else `JSON.stringify(input)`. Accepted → `undefined`. Not accepted → `{ block: true, reason }` with the reason prefixed by `Not confirmed by the user. ` (an ACP client that cannot show a dialog also returns `false`);
   - without UI → `{ block: true, reason }` with ` Blocked: nobody can confirm it in this session.` appended to the reason.
6. Otherwise return `undefined`.

Write the tests first with `bun:test`, using the fake `pi`/`ctx` pattern of `omp/native/delivery/tests/delivery.test.ts`. Capture the `tool_call` handler from `pi.on`. Give `ctx` `cwd`, `hasUI`, `sessionManager.getSessionId()`, and a `ui.confirm` that records its `(title, message)` calls and returns a preset answer. Each test builds a temp plugin root with small fixture scripts and passes a config to `createClaudeHooks`:
- a `bash` call when only a `read` entry exists → `undefined`, and that entry's marker file is not created;
- a hook with empty output → `undefined`. The stdin it saved has:
  - `session_id`, `hook_event_name` `PreToolUse`, `tool_name` `Bash`, `tool_input` equal to the event input, and `tool_use_id` equal to the event's `toolCallId`;
  - `cwd` equal to `<ctx.cwd>/sub` for `input.cwd: "sub"` (the test creates that directory), to the path itself for an absolute `input.cwd`, to `ctx.cwd` for `input.cwd: "/"`, and to `os.homedir()` for `input.cwd: "~"`.

  The env it saved has `CLAUDE_PLUGIN_ROOT` equal to the root and `CLAUDE_PROJECT_DIR` equal to `ctx.cwd`;
- an `input.cwd` that does not exist → block with the `cannot resolve the bash cwd` reason, and no hook runs;
- JSON `allow` → `undefined`. JSON `deny` → block with its reason, and a second entry after it does not run (its marker file is absent). JSON `deny` with no reason → the default `denied this call.` reason;
- JSON `ask` with UI: confirm accepted → `undefined`, and the confirm message contains the reason and the command; not accepted → block whose reason is `Not confirmed by the user. ` followed by the hook's reason. Without UI → block whose reason is the hook's reason followed by ` Blocked: nobody can confirm it in this session.`, and confirm is never called. For an input whose `command` is not a string, the confirm message contains `JSON.stringify(input)`;
- `ask` from the first entry and `deny` from the second → block with the deny reason; confirm is never called;
- exit 2 with stderr `stop` → block with reason `stop`. Exit 2 with empty stderr → the default `blocked this call.` reason;
- exit 1, stdout `not json`, stdout `{}`, and decision `maybe` → each blocks with a reason containing `failed`;
- a hook whose script runs `sleep 30 & echo $! > "$MARKER"; wait`, with `timeoutMs: 200` → block with a reason containing `failed`; the handler returns within 2 s; within 1 s after that, `ps -o stat= -p <pid from $MARKER>` prints nothing or `Z` (run it with `Bun.spawnSync`: `ps` exits 1 when the process is gone, which `execFileSync` would turn into an exception);
- a hook whose script runs `sleep 5 &` and then exits 0 (the child keeps its stdout), with `timeoutMs: 200` → block with a reason containing `failed` within 2 s;
- a hook that exits 0 at once, with `timeoutMs: 100` → `undefined`; after a further 300 ms, no uncaught error has occurred (bun test fails the test on one);
- a hook that exits 0 without reading stdin, with a 1 MiB `command` → `undefined`;
- the default export of a temp copy of `claude-hooks.ts`, with `claude-hooks.json` next to it and a `package.json` with `"name": "sample"` in the parent directory, takes that parent directory as root, and its failure reasons start with `sample`. With a `package.json` that is not JSON, it still registers the handler, and its reasons start with the parent directory's name. Without `claude-hooks.json`, it blocks every `bash` call with the `cannot be read` reason, and a `read` call returns `undefined`. Compare paths with `fs.realpathSync`: `import.meta.dir` is the real path, and on macOS `os.tmpdir()` sits behind the `/var` → `/private/var` link. Put each temp copy in its own new directory: Bun does not import a file created in a directory it has already imported from.

In `.github/workflows/omp-edition.yml`, add after the `Set up Bun` step:
```yaml
      - name: Test the Claude hooks extension
        run: bun test
        working-directory: omp/claude-hooks
```

Check: `bun test` in `omp/claude-hooks/` passes.

### Task 2: Generator maps Claude hooks to the extension
**Commit:** feat(omp-edition): map Bash PreToolUse command hooks of a generated plugin to the claude-hooks extension

**Files:**
- Modify: `scripts/build_omp_edition.py`
- Test: `scripts/test_build_omp_edition.py`

After this task, a generated plugin whose source has `hooks/hooks.json` gets three more output files: the extension `omp/claude-hooks/claude-hooks.ts` (it exists in the repository), its config and a `package.json`. A plugin without hooks builds exactly as before, and its build does not need `omp/claude-hooks/`.

1. Write the tests first (unittest, run with `python3 scripts/test_build_omp_edition.py`, in the style of `TestGenerated`). Add a helper that puts three files into a fixture source:
   - `plugins/sample/hooks/hooks.json` with one `PreToolUse` group `{"matcher": "Bash", "hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/guard.sh"}]}`;
   - `plugins/sample/scripts/guard.sh`, whose first line is `#!/bin/bash`;
   - `omp/claude-hooks/claude-hooks.ts` with the text `// adapter\n`.

   Tests:
   - `test_hooks_become_the_claude_hooks_extension`:
     - `plugins-omp/sample/extensions/claude-hooks.ts` equals the source adapter;
     - `extensions/claude-hooks.json` parses to `{"PreToolUse": [{"tool": "bash", "claudeTool": "Bash", "command": "scripts/guard.sh"}]}`;
     - `package.json` parses to `{"name": "sample", "version": "1.2.3", "private": true, "type": "module", "omp": {"extensions": ["./extensions/claude-hooks.ts"]}}`;
     - the output has no `hooks/`;
     - two `Bash` groups with different scripts keep their source order;
     - top-level `$schema` and `description` keys (both documented by Claude Code) are accepted and do not reach the output.
   - `test_plugin_without_hooks_gets_no_extension`: the plain `fixture` (no `omp/claude-hooks/` at all) builds, with no `package.json` and no `extensions/` in the output.
   - `test_unsupported_hooks_fail_closed`: one subTest per case, each a `BuildError` whose message contains the given text:
     - a top-level key other than `hooks`, `$schema` and `description` (for example `surprise`) → `unknown hooks.json keys`;
     - `{"hooks": []}`, `{"hooks": {}}`, `{"hooks": {"PreToolUse": []}}`, a group with an extra key, a group with an empty `hooks` list, and a numeric `matcher` → `malformed hooks.json`;
     - event `SessionStart` → `no OMP mapping for hook event`;
     - matcher missing, `Skill`, `Write`, `WebFetch` or `Bash|Edit` → `no OMP mapping for hook matcher`;
     - hook `{"type": "prompt", "prompt": "Is this safe?"}` → `hook type`;
     - hook key `timeout` next to `type` and `command`, and a `command` hook without `command` → `unknown hook keys`;
     - a command that lacks the `${CLAUDE_PLUGIN_ROOT}/` prefix, has an argument, lies outside `scripts/`, has a `..` part (`${CLAUDE_PLUGIN_ROOT}/scripts/../hooks/hooks.json`) or names a missing script → `hook command`;
     - a script whose first line is `#!/usr/bin/env python3`, `#!/bin/sh` or `#!/bin/bash -e`, or whose first line ends in `\r` (CRLF) → `not a shell script`;
     - an extra file `hooks/extra.sh`, a regular file named `hooks`, and a directory named `hooks/hooks.json` → `no OMP mapping for`;
     - a `hooks` key in `.claude-plugin/plugin.json` → `inline hooks`;
     - `omp/claude-hooks/claude-hooks.ts` missing → `missing`.
   - A symlink inside `omp/claude-hooks/` fails like the other source symlinks.
2. Implement:
   - `KNOWN_ENTRIES` gains `hooks`. In `build_generated`, `hooks` must be a directory whose only entry is the regular file `hooks.json`; anything else → `no OMP mapping for …`. The Claude manifest must not have a `hooks` key (`inline hooks are not mapped`).
   - Add `HOOK_TOOL_MAP = {"Bash": "bash"}`, the Claude tools whose OMP input has the same fields as Claude's. Do not reuse `TOOL_MAP`, which maps agent grants: OMP's `read`, `write` and `edit` take `path` where Claude's hooks read `file_path`, and `WebFetch` maps to `read`. Put a comment above it: add a tool only after checking its input shape, and add its OMP name to `HOOKABLE_TOOLS` in `omp/claude-hooks/claude-hooks.ts`, which blocks these tools when the config cannot be read.
   - `map_hooks(path: Path, src_root: Path) -> dict` returns `{"PreToolUse": [{"tool": ..., "claudeTool": ..., "command": ...}, ...]}` in source order. It raises `BuildError` for the hooks.json cases of step 1, checking in this order:
     - The top level is an object with a `hooks` key (else `malformed hooks.json`). Other top-level keys except `$schema` and `description`, which are ignored → `unknown hooks.json keys`.
     - Shape: `hooks` is a non-empty object; each event value is a non-empty list of objects whose keys are within `{matcher, hooks}`; each group's `hooks` is a non-empty list of objects with a string `type`; `matcher` and `command` are strings when present. Anything else → `malformed hooks.json`.
     - The event is `PreToolUse` (else `no OMP mapping for hook event`).
     - `group.get("matcher")` is a `HOOK_TOOL_MAP` key (else `no OMP mapping for hook matcher`). A group without `matcher` means all tools in Claude Code.
     - The hook's `type` is `command` (else `hook type`); after that, its keys are exactly `type` and `command` (else `unknown hook keys`).
     - The command fully matches (`re.fullmatch`) `\$\{CLAUDE_PLUGIN_ROOT\}/(scripts/\S+)`. The captured path has no `..` part, and `(src_root / rel).resolve()` is a file inside `(src_root / "scripts").resolve()`. Else `hook command <command>`. The build already copies `scripts/` verbatim.
     - The script's first line, read as bytes up to the first `\n`, equals `#!/bin/bash` or `#!/usr/bin/env bash` exactly. Else `hook command <command>: not a shell script bash can run as is; the first line must be exactly #!/bin/bash or #!/usr/bin/env bash`. The extension runs `bash <script>`, which ignores the shebang line and any flags on it.
   - `build_generated` gains a last parameter `adapter: Path`, and `build()` passes `source_repo / "omp" / "claude-hooks" / "claude-hooks.ts"`. When `hooks/hooks.json` is present:
     - if `adapter` is not a file, raise `BuildError(f"{adapter}: missing; {src_root.name} has hooks/hooks.json")` before writing anything for the plugin;
     - write `extensions/claude-hooks.json` (`json.dumps(value, indent=2) + "\n"`);
     - copy the adapter to `extensions/claude-hooks.ts` with `copy`;
     - write `package.json` as in step 1 (`indent=2`, trailing newline), taking `version` from the catalog entry.
   - In `build()`, call `reject_source_symlinks(source_repo / "omp" / "claude-hooks", NATIVE_SKIPPED_DIRS)`.
   - Add one bullet on the hooks mapping to the module docstring.

Check: `python3 scripts/test_build_omp_edition.py` → `OK`. `python3 scripts/build_omp_edition.py --check` exits 0, because no plugin with an overlay has hooks yet.

### Task 3: Delivery commits pass the commit guard
**Commit:** fix(delivery): mark delivery's own commits for the commit plugin's guard

**Files:**
- Modify: `omp/native/delivery/skills/orchestration/SKILL.md`
- Modify: `omp/native/delivery/.omp-plugin/plugin.json`
- Modify: `omp/native/delivery/package.json`
- Modify: `docs/plugins/delivery.md`
- Modify: `plugins-omp/delivery/`
- Modify: `.omp-plugin/marketplace.json`

1. In `skills/orchestration/SKILL.md`, prefix all three commits:
   - step 10: `AV_COMMIT_SKILL=1 git commit -m "<subject>" -- "$PLAN_PATH"`;
   - section 2: `printf '%s' "$MSG" | AV_COMMIT_SKILL=1 git commit -F -`;
   - section 5: `AV_COMMIT_SKILL=1 git commit -m "docs: add review of delivery $SLUG" -- "<report path>"`.

   At the end of step 10 add: `The AV_COMMIT_SKILL=1 prefix lets the Commit plugin's git commit guard pass delivery's commits; keep it on every commit delivery makes.`
2. Bump the version from 0.4.0 to 0.4.1 in `.omp-plugin/plugin.json` and in `package.json`.
3. In `docs/plugins/delivery.md`, at the end of section `## Commit trailers and resuming`, add: `Delivery runs its git commit commands with the AV_COMMIT_SKILL=1 prefix, so the Commit plugin's git commit guard lets them through. The prefix is not part of the commit message.`
4. Run `python3 scripts/build_omp_edition.py`. It regenerates `plugins-omp/delivery/` and the delivery version in the catalog.

Check: `grep -oE '(AV_COMMIT_SKILL=1 )?git commit -[mF]' omp/native/delivery/skills/orchestration/SKILL.md` prints exactly three lines, and each starts with `AV_COMMIT_SKILL=1 `. `python3 omp/native/delivery/tests/test_route_task.py` → `OK`. `python3 scripts/build_omp_edition.py --check` exits 0.

### Task 4: OMP edition of commit
**Commit:** feat(commit): generate the OMP edition with the git commit and push guards

**Files:**
- Create: `omp/overlay/commit.json`
- Modify: `omp/preamble.md`
- Test: `omp/claude-hooks/tests/commit-edition.test.ts`
- Create: `plugins-omp/commit/`
- Modify: `plugins-omp/`
- Modify: `.omp-plugin/marketplace.json`

1. Create `omp/overlay/commit.json` as `{"plugin": "commit", "agents": {}}`. Commit has no agents.
2. In `omp/preamble.md`, append this bullet after the `allowed-tools` bullet, which is the last one. The file goes through `str.format`, so it must not contain braces:
   ```
   > - In the text below, a backticked command right after `!` (for example !`git status`) is Claude Code inline context: Claude Code runs it and puts its output there before the model reads the text. Here nothing ran: run each such command in the text below with `bash` first and use its output in its place.
   ```
3. Run `python3 scripts/build_omp_edition.py`. Expected result:
   - `plugins-omp/commit/` holds `.omp-plugin/plugin.json` (1.4.0) and `commands/commit.md`, whose frontmatter has only `description` and `argument-hint`, followed by the preamble and the unchanged body;
   - it also holds `scripts/block-git-commit.sh`, `scripts/block-git-push.sh`, `extensions/claude-hooks.ts`, `extensions/claude-hooks.json` (two `bash` entries, in `hooks.json` order) and `package.json` (`commit`, 1.4.0);
   - it holds no `tests/` and no `hooks/`;
   - every other generated command and agent (Code Review and the three developer plugins) changes only by the new bullet; skills and native plugins do not change;
   - the catalog lists `commit` 1.4.0.
4. Test `omp/claude-hooks/tests/commit-edition.test.ts`. It imports the default export of `../../../plugins-omp/commit/extensions/claude-hooks.ts`, which is the shipped extension with its shipped config and scripts. It drives the `tool_call` handler with fakes: capture the handler from `pi.on("tool_call", …)`, and give `ctx` `cwd`, `hasUI`, `sessionManager.getSessionId()`, and a `ui.confirm` that records its `(title, message)` calls and returns a preset answer.
   - Setup: before the first handler call, set `process.env.GIT_CONFIG_NOSYSTEM = "1"` and `process.env.GIT_CONFIG_GLOBAL = "/dev/null"`, as `plugins/commit/tests/test-block-git-push.sh` exports them; the extension passes `process.env` to the hooks at each spawn. Bun does not pass runtime `process.env` changes to other children, so give every git call of the setup `env: { ...process.env }`. Create a temp repo on branch `feature/x`, set `user.name` and `user.email` in its local config (as that script's `mk_repo` does), make one commit, and point `origin` at a temp bare repo. `ctx.cwd` is that repo.
   - `git commit -m "feat: x"` → block, and the reason contains `/commit`;
   - `AV_COMMIT_SKILL=1 git commit -m "feat: x"` and `git commit --amend --no-edit` → `undefined`;
   - `git push --force origin feature/x` → block, the reason contains `Force-push`, and confirm is not called;
   - `git push origin feature/x` and `ls -la` → `undefined`, and confirm is not called;
   - `git push origin main` with UI → confirm is called once. Accepted → `undefined`; declined → block. Without UI → block;
   - a `read` tool call → `undefined`.

   The scripts need `jq` on `PATH`; CI's `ubuntu-latest` has it.

Check: `python3 scripts/build_omp_edition.py --check` exits 0, and `bun test` in `omp/claude-hooks/` passes.

### Task 5: Document the OMP edition of commit and the hooks mapping
**Commit:** docs: document the OMP edition of commit and the Claude hooks mapping

**Files:**
- Modify: `README.md`
- Modify: `docs/plugins/commit.md`
- Modify: `docs/installation.md`
- Modify: `CLAUDE.md`
- Modify: `docs/contributing.md`
- Modify: `.github/pull_request_template.md`

1. `README.md`, section `### Oh My Pi (OMP)`: the first sentence names the generated editions as `Code Review, Commit and the Frontend, PHP and Python developer plugins`. In the install loop, add `commit` after `code-review`. Directly after the install code block, add:
   ```
   With Commit installed, Delivery 0.4.0 and older stop at their first commit. If you added the marketplace earlier, run `omp plugin marketplace update av-marketplace` before installing Commit, and upgrade an installed Delivery with `omp plugin upgrade delivery@av-marketplace`. Commit's git guards need `jq` on `PATH`: without it, every `bash` call they do not deny asks for confirmation, and in print mode and subagents, Delivery's agents included, such calls are blocked.
   ```
2. `docs/plugins/commit.md`:
   - In `### git commit block`, replace the sentence "The hook blocks any direct `git commit` so all commits flow through the `/commit` skill." with:
     ```
     The hook blocks direct `git commit` commands so commits go through the `/commit` skill. It is a guardrail, not enforcement: any command whose text contains `AV_COMMIT_SKILL=1` passes, and so do forms the pattern does not match, such as `git -C <dir> commit` or `git -c key=value commit`.
     ```
   - Replace the `jq dependency` bullet under `Known limitations` with:
     ```
     - **`jq` dependency:** both hooks parse their input with `jq`. Without `jq` on `PATH`, the `git commit` hook applies its rules to the raw hook input, so a direct `git commit` is still denied while `AV_COMMIT_SKILL=1` and `--amend` commits pass, and the `git push` hook asks for confirmation on every Bash call. The CI image provides `jq`; install it wherever you run Claude Code or OMP (see Prerequisites in `docs/installation.md`).
     ```
   - Add a section `## Oh My Pi` at the end, stating:
     - install with `omp plugin install commit@av-marketplace`; if the marketplace was added earlier, run `omp plugin marketplace update av-marketplace` first. The command is `/commit:commit [task-id]`;
     - `/commit:commit` runs on the session's model, because OMP commands have no model setting (the Claude Code edition runs on Haiku). The model gathers the context (status, diff, branch, recent commits) with `bash`, because OMP does not pre-fill it;
     - the guards are the same two scripts, which the plugin's OMP extension runs before every `bash` call. A prompt becomes a confirmation dialog. Without a UI (print mode `omp -p`, subagents), every command the push guard would prompt for is blocked. That includes commands it cannot parse: a command that contains `push` together with a quoted `git -C "<dir>"` or `git -c key="<value>"`, such as `git -C "$REPO" diff -- scripts/block-git-push.sh`. A guard that fails or runs longer than 10 s blocks the call;
     - `jq` is required: without it the push guard asks on every `bash` call the commit guard lets through, which means a dialog with a UI and a block in print mode and subagents;
     - Delivery 0.4.1 and later mark their own commits, so the guard does not block them. An older Delivery stops at its first commit; upgrade it with `omp plugin upgrade delivery@av-marketplace`;
     - when the guard blocks a commit, run `/commit:commit` yourself; the "/commit skill" in the block reason is this command;
     - the `git commit` guard is a guardrail here too (see `git commit` block). The `git push` guard ignores the `AV_COMMIT_SKILL=1` marker, and the marker counts only in the command text: setting it through the `bash` tool's `env` parameter does not pass the `git commit` guard;
     - only the agent's `bash` tool calls are checked. Not inspected: commands run from the `eval` tool (IPython `!` lines included), commands you type with `!`, `omp commit`, the autoresearch `init_experiment` and `log_experiment` tools, and the `github` tool, whose `pr_push` op pushes the PR branch and, with `forceWithLease`, force-pushes.
3. `docs/installation.md`, `## Prerequisites` table: add after the Python row:
   ```
   | `jq` | For Commit | Both editions' git commit and push guards parse their input with `jq` |
   ```
4. `CLAUDE.md`, section `## OMP edition`: add this paragraph after the one that starts with "A plugin gets an OMP edition":
   ```
   A generated plugin's `hooks/hooks.json` becomes an OMP extension. The generator copies `omp/claude-hooks/claude-hooks.ts` to `extensions/`, writes the mapped hooks to `extensions/claude-hooks.json`, and writes a `package.json` that declares the extension, with the catalog version. Only `PreToolUse` command hooks on `Bash` are supported, and only in the form `${CLAUDE_PLUGIN_ROOT}/scripts/<file>` (unquoted, no arguments) where the script's first line is exactly `#!/bin/bash` or `#!/usr/bin/env bash`; any other hook fails the build. The extension implements a subset of Claude Code's hook contract; its header lists the known deviations, and its tests run with `bun test` in `omp/claude-hooks/`. OMP's update check (at startup with `marketplace.autoUpdate: auto`, and `omp plugin upgrade` or `/marketplace upgrade` without a plugin id) compares versions, so a change to `omp/claude-hooks/` reaches installed OMP editions only with a new version: bump every generated plugin that has hooks, in all four places.
   ```
5. `docs/contributing.md`, section `## Pull Request Requirements`: add before the `- No unrelated changes bundled in the same PR` bullet:
   ```
   - Passing Claude hooks tests (if you changed `omp/claude-hooks/` or the hooks or scripts of a plugin with an OMP edition): run `bun test` in `omp/claude-hooks/`; it needs `bun`, `git` and `jq`. The `OMP Edition` workflow runs it. A change to `omp/claude-hooks/` also needs a version bump of every generated plugin that has hooks.
   ```
6. `.github/pull_request_template.md`: add before the `- [ ] No unrelated changes included` checkbox:
   ```
   - [ ] Claude hooks tests pass: `bun test` in `omp/claude-hooks/` (if `omp/claude-hooks/` or the hooks or scripts of a plugin with an OMP edition changed)
   ```

Check: `grep -c 'commit@av-marketplace' docs/plugins/commit.md` prints at least `1`; the README install loop contains `commit`, and the README `### Oh My Pi (OMP)` section mentions `jq`; `grep -c 'allows it through' docs/plugins/commit.md` prints `0` (grep exits 1 when nothing matches).

## Verification

1. `python3 scripts/build_omp_edition.py --check` exits 0.
2. `python3 scripts/test_build_omp_edition.py` → `OK`; `python3 scripts/test_check_omp_tools.py` → `OK`; `python3 scripts/check_omp_tools.py` exits 0 (it needs OMP linked into `omp/native/delivery/node_modules/`, as in step 5).
3. `bun test` in `omp/claude-hooks/` passes.
4. `bash plugins/commit/tests/test-block-git-push.sh` passes; the scripts are unchanged.
5. `python3 omp/native/delivery/tests/test_route_task.py` → `OK`, and `bun test tests/delivery.test.ts` in `omp/native/delivery/` passes with OMP linked into its gitignored `node_modules/` (see `docs/contributing.md`).
6. `python3 scripts/check_plugin_versions.py` passes.
7. Live OMP, print mode. Run steps 7–8 before the commit edition is installed in the session that runs them: its own guard would block a bash command whose text contains `git commit`. In a temp repo with one commit (with a local `user.name` and `user.email`), run `omp -p --no-extensions -e "$REPO/plugins-omp/commit/extensions/claude-hooks.ts" "Run exactly this with the bash tool and report the tool result: git commit --allow-empty -m 'feat: probe'"`. The answer quotes `Direct git commit is blocked`, and `git rev-list --count HEAD` still prints `1`.
8. Live OMP, subagents without UI. Use the same flags plus `--mode json` and `--config "$TMP/sync.yml"`, where that file holds `async:` / `  enabled: false`, so each subagent runs inline and its report is the `task` result (with OMP's default `async.enabled: true`, the `task` result is only a spawn notice). Work in a temp repo whose `origin` is a temp bare repo. One prompt asks a `task` subagent to run `git push --force origin HEAD` with `bash` and report the result; a second asks a subagent to run `git push origin HEAD:main`. For each run, `jq -r 'select(.type=="tool_execution_start") | .toolName'` on the stream lists `task` and no `bash` (subagent tool calls are not emitted as events). The first `task` result (`.result.content[].text` of its `tool_execution_end` event) contains the force-push reason; the second contains a reason ending in `Blocked: nobody can confirm it in this session.` Afterwards `git -C <bare> show-ref` prints nothing (it exits 1 on a repository without refs).
9. Manual, after the delivery run has ended: these commands change the installed plugins, and upgrading Delivery removes the cache directory of the Delivery 0.4.0 that runs this plan. The local marketplace reads this checkout. Run `omp plugin marketplace update av-marketplace`, then `omp plugin upgrade delivery@av-marketplace` (it reports 0.4.1) and `omp plugin install commit@av-marketplace`, and start a new session. In a repo with changes, `/commit:commit ABC-1` creates one Conventional Commit with `Refs: ABC-1` and no co-author line. In a temp repo whose `origin` is a temp bare repo, `git push origin HEAD:main` shows a confirmation dialog; after you decline it, `git -C <bare> show-ref` prints nothing.

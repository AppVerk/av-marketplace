# av-dev

Set up a repo for AI agents once, then plan, implement, review and verify every task the same way, with evidence.

- `av-setup` reads the repo and writes its agent setup: config, docs, overlays, role skills.
- Five working skills use that setup: `av-plan`, `av-implement`, `av-review`, `av-verify`, `av-docs-sync`.
- Everything repo-specific lives in the repo. The plugin has no stack templates.

Reference page: [docs/plugins/av-dev.md](../../docs/plugins/av-dev.md).

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [Skills and examples](#skills-and-examples)
- [What av-setup creates](#what-av-setup-creates)
- [Config examples](#config-examples)
- [Claude and Codex slots](#claude-and-codex-slots)
- [Language](#language)
- [Troubleshooting](#troubleshooting)

## Install

```bash
/plugin marketplace add AppVerk/av-marketplace
/plugin install av-dev@av-marketplace
```

Requirements: `bash` 3.2+, `git`, `jq` (`brew install jq`).

Codex models: only if any slot in your config has `"provider": "codex"`. You must be logged in to Codex, otherwise these slots fail.

```bash
npm install -g @openai/codex                  # Codex CLI with automatic review
codex login                                   # log in with your Codex account, once per machine
codex login status                            # check: logged in
codex exec --help | grep -- --approve-for-me  # check: the CLI is new enough
```

No Codex account: switch the Codex slots to Claude in `.ai/av.config.json.local` (see [Claude and Codex slots](#claude-and-codex-slots)).

## Quick start

1. Open Claude Code in the repo root.
2. Preview the setup without writing anything:

   ```
   /av-dev:av-setup --dry-run
   ```

3. Run the setup. It scans the repo, asks a few questions, shows a plan and waits for your approval:

   ```
   /av-dev:av-setup
   ```

4. Review the new files (`git status`), then commit them. The setup never commits.
5. Work on tasks:

   ```
   /av-dev:av-implement PROJ-123
   ```

You can also ask in plain words. "Set up this repo for Claude", "implement PROJ-123" or "review my changes" start the right skill.

## Skills and examples

### av-setup: configure the repo

| Call | What it does |
|---|---|
| `/av-dev:av-setup` | full setup with an interview and a plan to approve |
| `/av-dev:av-setup --dry-run` | scan, interview and plan only; no changes in tracked files |
| `/av-dev:av-setup --defaults` | no interview; detected values; decisions listed in the report |
| `/av-dev:av-setup --only config` | only the config; `docs`, `overlays`, `roles`, `codex` work the same way |
| `/av-dev:av-setup --eval` | after the setup, measure the review on a clone with 5 injected defects |

Modes are picked from what the repo already has:

| Repo state | Mode |
|---|---|
| no AI setup | NEW |
| `CLAUDE.md` or docs, no agents | COMPLETION: keeps team docs, adds the rest |
| agents, commands or a pipeline | ADOPTION: moves them to the skills |
| `.ai/av.config.json` exists | REFRESH: compares with a new scan, proposes changes |

Example report (first lines):

```
Setup ready: 38 files created, 1 updated, 0 to delete.

| Area | State |
|---|---|
| Config | .ai/av.config.json, gates quick/full |
| Role skills | shop-backend, shop-web, shop-tests |
| Setup validation | check_setup.sh: ERRORS 0 WARNINGS 0 |
| Quick gate | PASS |
```

### av-plan: plan a task

```
/av-dev:av-plan PROJ-123
/av-dev:av-plan "Add CSV export to the orders list" --verify-plan
```

- Reads the ticket, the overlay and the docs, then checks the existing code.
- Picks a mode: SMALL, STANDARD or LARGE, and a risk level.
- Writes the plan to `.ai/workspace/plans/YYYY-MM-DD-<topic>.md`: scope, acceptance criteria, contract between layers, files with owners, tests, gates, docs.
- Does not implement.

### av-implement: implement a task end to end

```
/av-dev:av-implement PROJ-123
/av-dev:av-implement .ai/workspace/plans/2026-09-26-csv-export.md
/av-dev:av-implement "Fix rounding in the invoice total" --mode small
/av-dev:av-implement --continue 20260926-1410-PROJ-123-csv-export
```

| Mode | Flow |
|---|---|
| SMALL | implement, quick gate, report |
| STANDARD | implement with role skills, quick gate, docs, independent review with the `full` gate, fixes, final gates, report |
| LARGE | plan, one executor per role, layer checks, quick gate, docs, review, fixes, final gates, report |

A task in a high-risk area is always at least STANDARD and always gets an independent review.

The run stops before the commit and proposes a message:

```
READY_FOR_COMMIT: CSV export added to the orders list.

| Stage | Result |
|---|---|
| Mode | STANDARD, normal risk |
| Gates | quick PASS FRESH, full PASS FRESH |
| Review | APPROVED after 1 round; 0 open BLOCKER/HIGH |
| Models | plan codex/high, implement claude opus/high, review codex/xhigh |

Commit: `PROJ-123 add CSV export to the orders list`
```

### av-review: review changes

```
/av-dev:av-review
/av-dev:av-review --base develop
/av-dev:av-review --files src/api/orders.ts,src/api/export.ts --security
```

- Uses the axes from the repo's `code-review.md` and the tools from its overlay.
- Findings have a severity, an origin (NEW or PRE_EXISTING) and `file:line` evidence.
- Verdict: `APPROVED` or `NEEDS_FIXES`. It never edits files.

### av-verify: run the gates

```
/av-dev:av-verify quick
/av-dev:av-verify full
/av-dev:av-verify --only unit_one --env UNIT_SUITE=OrdersTest
/av-dev:av-verify --status --run-id 20260926-1410-PROJ-123-csv-export
```

- Runs only commands from the config. Each result is `PASS`, `FAIL`, `NOT_RUN` (environment missing) or `SKIPPED` (optional).
- Saves evidence with a fingerprint of the code. `FRESH` means the code has not changed since the check; `STALE` means it has.

### av-docs-sync: keep docs in line with the code

```
/av-dev:av-docs-sync sync
/av-dev:av-docs-sync sync develop..HEAD
/av-dev:av-docs-sync audit
/av-dev:av-docs-sync audit --fix
```

`audit` checks paths, names, commands, numbers and versions in the docs against the code and returns `DOCS_OK` or `DOCS_DRIFT`.

## What av-setup creates

```
CLAUDE.md                     instructions for the agent, with a task routing table
AGENTS.md -> CLAUDE.md        the same instructions for Codex
.agents/skills -> .claude/skills
.ai/
  av.config.json              team config (committed)
  av.config.json.local        your own overrides (gitignored, you create it)
  overlays/                   repo rules for each of the 5 skills
  README.md, architecture.md, commands.md, code-review.md, contracts.md, ...
  modules/                    one file per module
  scripts/                    repo tools for the agent (gates, lint, helpers)
  workspace/                  plans, reports, run evidence (gitignored)
  sessions/learnings.md       session learnings (gitignored)
.claude/skills/<prefix>-<role>/SKILL.md   knowledge of one layer, e.g. shop-backend
```

## Config examples

The team config is `.ai/av.config.json`. The full schema: `skills/av-setup/references/config-schema.md`.

Gates:

```json
"validation": {
  "commands": {
    "lint":  { "run": "make lint", "parallel": true },
    "unit":  { "run": ".ai/scripts/unit_test.sh", "expect": "UNIT_OK", "timeoutSec": 900 },
    "build": { "run": "make build", "timeoutSec": 1200 },
    "e2e":   { "run": ".ai/scripts/e2e.sh \"$E2E_SUITE\"", "precheck": "bash \"$AV_SKILLS_DIR/av-verify/scripts/compose_container.sh\" app >/dev/null", "notRunExitCodes": [2] }
  },
  "gates": {
    "quick": ["lint", "unit"],
    "full":  ["lint", "unit", "build"]
  }
}
```

- `expect`: text that must appear in the output. It protects against a green result that did nothing.
- `precheck`: fails means `NOT_RUN`, not `FAIL`.
- `parallel`: runs in the background next to the other commands of the gate.
- `compose_container.sh <service>`: the container of this checkout only, never one started from another copy of the repo.

Local override: `.ai/av.config.json.local` changes settings only on your machine. Objects merge, arrays replace, `null` removes a key.

```json
{
  "validation": { "commands": { "unit": { "timeoutSec": 1800 } } },
  "agents": { "crossVendor": false, "models": { "review": { "provider": "claude", "model": "opus", "effort": "xhigh" } } }
}
```

Check what is in effect:

```bash
bash <plugin>/skills/av-verify/scripts/config.sh --root . --sources
```

## Claude and Codex slots

Each step of a run is a slot with its own provider, model and effort. The default from `av-setup` needs only Claude Code:

```json
"agents": {
  "independentReview": true,
  "crossVendor": false,
  "models": {
    "plan":      "inherit",
    "implement": "inherit",
    "review":    "opus",
    "verify":    "haiku"
  }
}
```

Opt-in, when the team has Codex: Claude and Codex in turns, so code and plans are checked by a different provider than the one that wrote them (`crossVendor: true`):

```json
"agents": {
  "independentReview": true,
  "crossVendor": true,
  "timeoutSec": 3600,
  "models": {
    "plan":       { "provider": "codex",  "model": "<codex-model>", "effort": "high" },
    "planReview": { "provider": "claude", "model": "opus", "effort": "high" },
    "implement":  { "provider": "claude", "model": "opus", "effort": "high" },
    "review":     { "provider": "codex",  "model": "<codex-model>", "effort": "xhigh" },
    "verify":     "sonnet"
  }
}
```

- Keep `verify` on the session or a cheap Claude model: it runs gates. On Codex it works, but it reads the skills and logs first and is 2-3 times slower.
- Claude slots run as plugin agents `av-dev:av-slot-<effort>`.
- Read slots (`review`, `planReview`) must not change code. The run takes a code fingerprint before and after each read slot, Claude or Codex; a change gives FAIL and the result does not count. This detects a change after the fact; it is not a sandbox.
- Codex slots run through `codex exec`. You must be logged in to Codex (`codex login`, see [Install](#install)). Needs a Codex CLI with automatic review (`codex exec --approve-for-me`).
  - `plan`, `implement`, `verify`: sandbox `workspace-write` with automatic review. A command the sandbox blocks (a build, a simulator, the network) asks for escalation and a Codex reviewer model decides, like auto mode in Claude Code. No prompts for you.
  - `review`, `planReview`: sandbox `read-only`.
  - These settings win over `sandbox_mode` in `~/.codex/config.toml`.
- The plugin hook `agent_guard.sh` lets the orchestrator start slots without prompts, also in auto mode, when the call has only plain characters and known flags. You need no allow rule for `agent.sh`; remove an old `agent.sh:*` rule, and never allow `agent_grant.sh` or the scripts directory.
- When a slot still needs more access (a folder outside the repo, no sandbox), the run resumes it through `agent_grant.sh`, and Claude Code always shows you a prompt for that exact command. In `bypassPermissions` the hook blocks it and you run the command yourself with `!`.
- The team uses the Codex variant and you have no Codex: switch its slots to Claude in `.ai/av.config.json.local` and set `crossVendor: false`.

## Language

The plugin is written in English. Files it generates in your repo use `project.language` from the config, for example Polish. Section names have an English canonical name and localized aliases (`skills/av-setup/references/localization.md`); both are accepted.

## Troubleshooting

| Message | Meaning | What to do |
|---|---|---|
| `CONFIG_ERROR ...` | the config or the local override is invalid | fix the field named in the message; `gate.sh --list` shows all errors |
| `CHECK <cmd> NOT_RUN` | the environment is missing (precheck failed or a not-run exit code) | start the service or device from `needs`, run the gate again |
| `STALE` | the code changed after the check | run the gate again; do not edit files while a gate runs |
| `AGENT_NEEDS_PERMISSION` | a Codex slot needs more access | approve or refuse when asked; the run resumes |
| `AGENT_NOT_RUN` | the CLI of the slot provider is missing, or the Codex CLI has no automatic review | install or update it (`npm install -g @openai/codex`), or switch the slot in `.ai/av.config.json.local` |
| `AGENT_FAIL` on a Codex slot, the log says you are not logged in | Codex CLI without a login | `codex login`, then run the task again |
| `SETUP_LOCAL_TRACKED` | `.ai/av.config.json.local` is in git | `git rm --cached .ai/av.config.json.local` |

Run the plugin tests:

```bash
bash plugins/av-dev/tests/run.sh
```

CI (`.github/workflows/av-dev-tests.yml`) runs them on every change in `plugins/av-dev/`: on Ubuntu with shellcheck, and on macOS with `/bin/bash` 3.2.

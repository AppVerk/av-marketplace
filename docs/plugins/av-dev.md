# AV Dev Plugin

One agent workflow for every repo. `av-setup` configures the repo once; five working skills then plan, implement, review and verify from that configuration.

**Version:** 0.1.0

Usage guide with examples: [plugins/av-dev/README.md](../../plugins/av-dev/README.md).

## Why

Hand-written agent pipelines drift apart between repos and go stale within weeks. AV Dev keeps the workflow in one plugin and moves everything repo-specific into files inside the repo:

- a team config: `.ai/av.config.json`,
- overlays: `.ai/overlays/<skill>.md`,
- role skills: `.claude/skills/<prefix>-<role>/`,
- AI docs: `.ai/` or `docs/`.

The plugin holds general rules only. Knowledge of a stack or a repo is derived from that repo and stays in it.

## Skills

| Skill | Purpose |
|-------|---------|
| `av-setup` | Scans the repo, interviews the user, writes config, docs, overlays and role skills. Adopts existing pipelines, agents and commands |
| `av-plan` | Writes an implementation plan: mode, risk, layer contract, files with owners, tests, gates |
| `av-implement` | Implements a task end to end: baseline, implementation, gates, independent review, up to 2 fix rounds, docs, report. By default stops before commit (`git.commit`) |
| `av-review` | Reviews changes against the repo rules; findings with severity, NEW/PRE_EXISTING origin and file:line evidence |
| `av-verify` | Runs the configured gates and records evidence with a code fingerprint: FRESH or STALE |
| `av-docs-sync` | Keeps AI docs in sync with the code; audit mode reports DOCS_OK or DOCS_DRIFT |

The plugin is written in English. Files it generates in a repo (docs, overlays, role skills, plans, reports) use `project.language` from the config, for example Polish. Section names and modes have a canonical English name and localized equivalents (`av-setup/references/localization.md`); skills and scripts accept both, so repos set up in another language keep working.

## How It Works

1. Run `av-setup` in the repo. It detects the mode: NEW, COMPLETION (docs exist), ADOPTION (agents or pipelines exist) or REFRESH (config exists).
2. It writes a plan and waits for approval. `--defaults` skips both the interview and the approval wait: it uses the detected values and writes the files, but deleting files still needs explicit approval. `--dry-run` stops after the plan.
3. After approval it writes the files and validates them: `check_setup.sh`, doc reference checks and the `quick` gate.
4. From then on, the working skills read the effective config and the overlay for their step.

There are no stack templates. `av-setup` works with any stack: it takes commands and conventions only from the repo itself (scan facts, CI, existing docs, the code), so it does not push one design onto projects built differently.

Stack adapters add facts read from manifests, each with evidence, never conventions. They never run a build tool.

| Adapter | Scan key | Reports |
|---------|----------|---------|
| PHP/Symfony | `adapters.php_symfony` | Symfony presence, declared versions, convention paths, config formats, test tools (`composer.json` only) |
| iOS/Xcode | `adapters.ios_xcode` | projects, targets, whitelisted build settings, schemes, test plans, CocoaPods and SwiftPM declared and locked versions |
| Android | `adapters.android` | Gradle builds, modules, plugins, SDK and JVM values, dependencies, version catalogs, wrapper, manifests; values as `declared`, `expression` or `text_candidate` |
| Angular | `adapters.angular` | Angular presence, declared, locked and installed versions of key packages, `angular.json` projects and targets, test tools |

Every adapter entry has the same `status` (`ok`, `incomplete`, `not_applicable`, `unavailable`, `error`), `ran`, `exit_code`, `reason` and `trigger`. The scan checks the exit code and the output shape. A failed or missing adapter makes the scan incomplete and names the reason in `scan.incomplete`; its facts are dropped. Adapter cuts join `scan.truncated`. Adapters have no time limit.

## Config

`.ai/av.config.json` is committed and holds team decisions:

| Section | Holds |
|---------|-------|
| `validation` | named commands (`run`, `expect`, `precheck`, `notRunExitCodes`, `optional`, `covers`, `parallel`) and gates (`quick`, `full`, custom) |
| `roles` | role skills with non-overlapping file globs |
| `risk` | high-risk areas and paths that force an independent review |
| `agents` | Claude model per pipeline slot |
| `git` | base branch, branch and commit patterns, commit and push policy |
| `integrations` | tracker, boards, design tools |

`gate.sh --list` validates the config. `requires: {"av-dev": ">=X.Y.Z"}` pins the minimum plugin version.

### Local override

`.ai/av.config.json.local` holds the settings of one person or one machine. It is gitignored.

- Objects merge recursively, arrays and scalars replace, `null` removes a key.
- Every skill and script reads the effective config from `av-verify/scripts/config.sh`.
- `gate.sh --list` prints `CONFIG_LOCAL` and each overridden key.
- `check_setup.sh` fails when the file is tracked by git.

Example: a developer who wants `opus` for plans and `sonnet` for review.

```json
{
  "agents": {
    "models": { "plan": "opus", "review": "sonnet" }
  }
}
```

## Pipeline Slots

Slots: `plan`, `planReview`, `implement`, `review`, `verify`. Each slot sets a Claude model: `inherit`, `opus`, `sonnet`, `haiku`, `fable` or `claude-<id>`.

- `plan`, `implement` and `verify` on `inherit` run in the session. Other slots run through the Agent tool with the plugin agents `av-dev:av-slot` (write) and `av-dev:av-slot-read` (read only), with the slot model and the session's permissions.
- A read slot that changes the working tree fails: the code fingerprint is compared before and after the slot. This is detection after the fact, not a sandbox.
- A Haiku model is rejected for `review` and `planReview`: a cheap model can falsely confirm correctness.

## Integrations

The plugin ships no instructions for external tools. How a repo uses a board, a design tool or a tracker is repo knowledge: `av-setup` keeps it in the repo docs (a topic file linked from the overlays), taken from the repo's existing agents, skills and docs.

## Prerequisites

- `bash` 3.2+, `git`, `jq`.

## Installation

```bash
/plugin marketplace add AppVerk/av-marketplace
/plugin install av-dev@av-marketplace
```

Then run `av-setup` in the repo.

## Tests

```bash
bash plugins/av-dev/tests/run.sh
```

2122 script tests: gates, config merge, setup validator, repo scan, stack adapters (PHP/Symfony, iOS/Xcode, Android, Angular) with their scan integration, adoption diff, doc reference checks. A test passes only with exit code 0 and a last line `PASS n FAIL 0`. The runner also checks that each skill's `VERSION` matches `plugin.json`.

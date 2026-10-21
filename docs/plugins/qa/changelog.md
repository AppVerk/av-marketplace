# QA changelog

This page lists user-visible changes per release.

## 3.1.0: background desktop testing through driver plugins

The optional DESKTOP plan section tests desktop apps headless in the background through installable desktop driver plugins, alongside existing FE and BE tests. QA ships no driver: a driver is a separate plugin built on desktop driver contract 1, described in [Writing extensions](../../extensions.md#qa-desktop-drivers). Configure apps under `[qa.desktop.<name>]` with a driver name. `/qa:run` detects installed drivers and registers them for the run; `desktop run` and the run's `desktop.sh` build and run the app through its driver, inject tick-based input and return PNG shots plus a masked app log. An app whose driver is not installed reports `NEED_INFO kind=tool`, and `plan check` reports missing desktop configuration in `missing.apps`.

## 3.0.1: shared loader reads the user configuration file

No change to `/qa:run`. The shared configuration loader QA ships for every configurable plugin can read policy keys from `${XDG_CONFIG_HOME:-~/.config}/av/config.toml` for a plugin that allows them; QA allows none, so it never reads that file. See [Files](../../configuration.md#files).

## 3.0.0: flagless `/qa:run` with project configuration

Changes since `qa` 2.9.0.

**Breaking:** `/qa:run` runs the whole test→fix→retest loop and accepts no flags; `/qa:loop` is removed with no alias. For a test-only run like the 2.9.0 `/qa:run`, set `qa.fix = "off"`. `/qa:create-plan` still authors and reviews plans without running them.

Settings move from flags and the plan's `## Setup` to `.av/config.toml`. Run `/qa:run` interactively once to bootstrap and trust the file, then commit it. Headless runners need a prepared, trusted file; see [Headless runners and CI](../../configuration.md#headless-runners-and-ci).

| 2.9.0 | 3.0.0 |
|---|---|
| `--mode approve`, `--mode auto` | `qa.fix = "approve"` or `"auto"`; `"off"` tests and reports only. |
| `--mode step` | Removed. |
| `--max-iterations`, `--max-dispatches`, `--time-budget` | Fixed at `3` iterations, `50` dispatches and `30 minutes`. |
| `--severity` | Removed; every failing assertion is a fix candidate unless a fix guard drops it. |
| `--allow-mutations` | `qa.mutations = "allow"`. Every scenario declares `- **Writes:** yes\|no`. |
| `--allow-host`, `**Base URL:**`, `QA_BASE_URL` | Origins under `[env.targets]`. Credentials need HTTPS or a loopback origin. |
| `--auto-plan`, `--no-auto-plan` | Removed; without a matching plan, `/qa:run` generates and reviews one. |
| `--allow-dirty` | Follows `qa.fix`: `approve` asks (headless aborts), `auto` proceeds from the recorded baseline, `off` skips the check. |
| `**Required environment variables:**` | `[env.secrets]` and `[env.values]`. |
| `**Required services:**` | `[env.services]`: health probes plus optional `up`, `prepare` and `down` commands; `qa.start_services` decides whether QA asks before starting them. |
| `**Required databases:**`, `**DB Check:**` | Stores under `[env.stores]` and `**State Check:**` lines. QA no longer reads `DB Check` lines. |

`## Setup` is now optional human notes. A 2.9.0 plan that references users or sends tokens fails the new plan check: users need `## Users` declarations, and testers now obtain tokens themselves. Its scenarios also lack `Writes:` lines, so the default `qa.mutations = "deny"` skips them. Regenerate such plans with `/qa:create-plan` or `/qa:run`.

Testers register accounts or sign in as existing users configured under `qa.users.<name>`; a `[qa.cleanup]` recipe deletes registered accounts at teardown. `auth-unverified` SKIPs are gone: a backend scenario expecting `2xx` that receives `401/403` is a FAIL flagged `auth`. Automatic fixes exclude it; `approve` can offer a reviewed fix. Fixers may not weaken authentication.

Headless `approve` tests and reports without fixing instead of aborting. Configuration edits during a run stop it; run `/qa:run` again.

For a `last N commits` source, the planner reads every distinct delivery plan named by Git-parsed `Delivery-Plan:` trailers and associates each commit with its own plan, only after checking repository containment and rejecting traversal, symlinks and non-files; ignored trailers are disclosed in `## Changes Summary`. Prose mentions do not count as trailers. Plan text is specification data, not instructions.

## Earlier releases (historical compatibility)

**`qa` 2.9.0:** In OMP, `qa:test-planner` runs with OMP's Advisor: a second model on the `advisor` role watches the planner while it writes the plan and can steer it, before `qa:test-plan-reviewer` reviews the result. Expect more model cost per plan. Switch it off with `task.agentAdvisor` (see [Oh My Pi](../qa.md#oh-my-pi)). The Claude Code edition is unchanged.

**`qa` 2.6.0 pairs with `code-review` ≥ 2.0.0 wherever a shared report carries a decision-stage rejection.** That is the precondition, and it is worth stating plainly: `**Fix-policy:** needs-decision` is emitted by `code-review`'s own producers alone — today, reports written by `/review` — while `/qa:run` and `/qa:loop` never write the field, and an absent field is `auto` by both fix commands' fail-safe. A report this plugin produces therefore cannot presently reach the decision gate, and cannot acquire a `🚫 Rejected` status or any of the loop-written decision fields. `qa` 2.6.0's handling of them is **forward compatibility** for a schema the QA producers do not yet emit.

Where the state does arise — a `/review` report fed through the decision stage and then re-rendered by this plugin — the pairing binds: `code-review` 2.0.0 adds a `🚫 Rejected` status to reports it shares with this plugin, and `/qa:loop` on `qa` ≥ 2.6.0 knows to read it as terminal and preserve the line. An older `/qa:loop` (< 2.6.0) does not: its Step 4.1 in-place Status update overwrites a `🚫 Rejected` line and its reason whenever a sibling issue passes on the same scenario in a later iteration, silently discarding the rejection. So keep both plugins on paired minimums (`code-review` ≥ 2.0.0, `qa` ≥ 2.6.0) for any report that can carry a rejection. This is milder than `code-review`'s own intra-plugin skew — an older `code-review` reader can silently re-offer and dispatch a rejected finding, which is worse, and which is unconditional rather than waiting on a producer that does not exist yet. See [code-review.md's Upgrade Notes](../code-review.md#upgrade-notes) for the fuller detail.

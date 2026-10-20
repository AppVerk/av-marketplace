# Test Plan: Plan Review 0.2.0 — review progress, failed runs as rounds and the Esc skip

## Source
- Type: last 2 commits (`git diff HEAD~2...HEAD`, ec62ccd..c518800)
- Base: master
- Date: 2026-10-20
- Branch: delivery/plan-review-progress
- Head: c518800584eb2d5d72d53f38d76e8234cc944da7

## Changes Summary

Both commits carry `Delivery-Plan: docs/plans/2026-10-20-plan-review-progress.md`. The path is repository-relative, has no `..` segment and no symlinked component, and resolves to a regular file inside the repository (git-ignored by `.gitignore:28`, not tracked). It was accepted and read as the specification for both commits. No trailer was rejected.

| Commit | Subject | Delivery-Task-Title |
|---|---|---|
| fd3bb4d | fix(plan-review): show review progress, cap failed runs and let Esc skip a review | Show review progress, count failed runs as rounds, let Esc skip a review |
| c518800 | docs(plan-review): document review timing, the round cap and Esc skip; release 0.2.0 | Document review timing and skipping, release plan-review 0.2.0 |

What changed in `omp/native/plan-review/extensions/plan-review.ts`, the extension behind the `plan_review` tool (called with `write xd://plan_review`) and the gate on `write xd://propose`:

- **Progress heartbeat.** While the reviewer `omp -p` runs, the tool sends an update at once and then every 15 s (`PROGRESS_INTERVAL_MS`, plan-review.ts:24): `Plan review round <n>/3: <m:ss> elapsed (stops at 15:00). Esc skips it.`, then `Reviewing <plan url> with the advisor model role.` (plan-review.ts:218-227; `formatElapsed`, plan-review.ts:161-165). A `finally` clears the interval when the run returns, fails or is aborted (plan-review.ts:239-241). This replaces the single static `Reviewing … with the advisor model role…` update.
- **A failed run uses a round.** `round` is now set right after the all-rounds-used check (plan-review.ts:197). `unavailable(reason)` stores `rounds: round`, adds `(round <n> of 3)` to its warning and its result, and returns details `{ url, round, outcome: "unavailable" }` (plan-review.ts:198-205). This covers a thrown `exec` error, a timeout, a non-zero exit, a missing final answer and an answer that is not the expected JSON (plan-review.ts:236-249). Once 3 rounds are counted, the tool runs no reviewer and its message now ends with `the user decides on the plan without another review.` (plan-review.ts:191-196).
- **Esc skips a running review.** An abort whose `signal.reason` is OMP's `USER_INTERRUPT_LABEL` (imported at plan-review.ts:17) records `{ outcome: "skipped" }` for the current text without using a round, shows a `warning` and rejects with `Plan review cancelled by the user. …` (plan-review.ts:206-216, 237, 242). Any other abort rejects with `Plan review cancelled.` and records nothing. The plan-mode prompt gets the matching instruction (plan-review.ts:48). The gate itself is unchanged (plan-review.ts:277-302): it already lets a `skipped` or `unavailable` record of the same text through (plan-review.ts:286), and its 3-round cap now also counts failed runs (plan-review.ts:287-292).
- **Tests.** `omp/native/plan-review/tests/plan-review.test.ts` adds four tests: the heartbeat with fake timers (lines 134-163), failed runs using rounds (lines 177-197), the Esc skip (lines 199-213) and an internal abort (lines 215-223). Its fake `exec` now honours the abort signal and a `killed` answer (lines 55-61).
- **Documentation.** `docs/plugins/plan-review.md`: the plugin is optional (line 5), restart `omp` after installing, disabling or uninstalling it (line 19), the progress line (line 24), how long a round takes (line 28), the round cap (line 30) and the Esc skip (line 32). `docs/oh-my-pi.md:15` gives the same restart rule for every plugin extension.
- **Release 0.2.0.** `omp/native/plan-review/.omp-plugin/plugin.json:3-4`, `omp/native/plan-review/package.json:3` and `README.md:60`, plus the generated `plugins-omp/plan-review/.omp-plugin/plugin.json:3-4`, `plugins-omp/plan-review/package.json:3` and `.omp-plugin/marketplace.json:49-50`.
- **Generated extension.** `plugins-omp/plan-review/extensions/plan-review.ts` is byte-identical to its source (`cmp`).

No changed file is FE, BE or DESKTOP. The extension runs inside the `omp` terminal process. Its effects are tool results, TUI notifications and review state kept in that process (plan-review.ts:168-169). It serves no page, endpoint or store. It is not an Ebitengine app either: the repository has no `go.mod`, so the ebitengine driver guide recognises no app here. The other files are documentation, release metadata, a test file and generated copies. The QA config (`.av/config.toml`) defines no targets, desktop apps, users, values or stores. The plan therefore has no executable FE, BE or DESKTOP scenario; every contract check is listed under Out of harness scope.

OMP behaviour cited below was read in the installed OMP 18.12.3 (`~/.bun/install/global/node_modules/@oh-my-pi/`, which `omp/native/plan-review/node_modules` links to). Those citations start with the package name, for example `pi-coding-agent/src/tools/write.ts:844`.

## Blockers / Findings

### BLK-01: Every abort that carries OMP's user-interrupt label records a skip, not only Esc — `(omp/native/plan-review/extensions/plan-review.ts:216)`

The specification says "Only the user's Esc records a skip; any other abort records nothing" (docs/plans/2026-10-20-plan-review-progress.md:54). `cancelled()` records a skip whenever `signal.reason` equals `USER_INTERRUPT_LABEL` (plan-review.ts:216). OMP 18.12.3 sets that reason for Esc (`pi-coding-agent/src/modes/controllers/input-controller.ts:329, 2001`), and also when `/plan` leaves plan mode during a turn (`pi-coding-agent/src/modes/interactive-mode.ts:6102, 5275-5277`), when any extension calls `ctx.abort()` (`pi-coding-agent/src/modes/controllers/extension-ui-controller.ts:248`), for the RPC `abort` command (`pi-coding-agent/src/modes/rpc/rpc-mode.ts:1920-1922`) and for an ACP cancel (`pi-coding-agent/src/modes/acp/acp-agent.ts:1128`). `/plan` is a user action, the RPC `abort` and the ACP cancel come from the client driving OMP, and `ctx.abort()` comes from another extension. A review interrupted by any of them records `skipped`, so its unchanged text later passes `xd://propose` unreviewed, after the `Plan review skipped: …` warning.
- **Impact on testing:** None for this plan, which has no executable scenario. The delivery plan's manual check interrupts with Esc (docs/plans/2026-10-20-plan-review-progress.md:104), so this finding does not change its result.
- **Remediation (human Setup prerequisite):** Nothing to do before a run. The owner decides whether these interrupts should skip a review. If they should, `docs/plugins/plan-review.md:32` and the header comment (plan-review.ts:9) should say so; if not, the skip condition at plan-review.ts:216 has to change.
- **Blocks:** none

## Users

None. No scenario acts as a user, a role or an anonymous visitor.

## Detected Tools
- Playwright MCP: available
- HTTP client: curl, httpie
- Store clients: psql, sqlite3 (mysql and redis-cli unavailable)
- Desktop drivers: ebitengine
- Other: jq, perl JSON::PP

## Out of harness scope

Every check below runs in an `omp` terminal session, in the extension's Bun tests or in a repository script. None of them has a browser page, an HTTP endpoint, a configured store or an Ebitengine app that the FE, BE or DESKTOP testers could drive. The delivery plan's Verification (docs/plans/2026-10-20-plan-review-progress.md:96-104) defines the Bun tests, a throwaway heartbeat smoke test, the build and version checks, and one manual run in a real OMP terminal.

**The `xd://propose` gate.** Three inputs decide what `write xd://propose` does for a plan file (plan-review.ts:277-302): the latest record for that file (none, approve, revise, unavailable or skipped), whether the current text has that record's hash, and whether the record counts 3 rounds. An abort without the user-interrupt reason leaves the earlier record in place (plan-review.ts:216). That gives 5 × 2 × 2 = 20 rows. Rows 13, 15, 18 and 20 could not occur before 0.2.0: a failed run did not count a round, and nothing recorded a skip.

| # | Record | Text has the record's hash | Record counts 3 rounds | Expected | Disposition |
|---|---|---|---|---|---|
| 1 | none | yes | yes | impossible — without a record there is no hash to match and no round count (plan-review.ts:285-287) | — |
| 2 | none | yes | no | impossible — as row 1 | — |
| 3 | none | no | yes | impossible — as row 1 | — |
| 4 | none | no | no | Blocked: `This plan has not been reviewed. Before proposing it, write {"title": "<slug>"} to xd://plan_review …` (plan-review.ts:294-300) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:97-99, 222) |
| 5 | approve | yes | yes | Passes with no warning (plan-review.ts:286) | out of harness scope — omp terminal session (no Bun test) |
| 6 | approve | yes | no | Passes with no warning (plan-review.ts:286) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:109-111, 125-128) |
| 7 | approve | no | yes | Passes with the warning `Plan review: all 3 rounds are used and the plan has no approving review. Check the last review's findings before approving.` (plan-review.ts:287-292) | out of harness scope — omp terminal session (no Bun test) |
| 8 | approve | no | no | Blocked: `The plan changed since its last review. Before proposing it, write {"title": "<slug>"} to xd://plan_review …` (plan-review.ts:294-300) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:130-131, block only) |
| 9 | revise | yes | yes | Passes with row 7's warning (plan-review.ts:287-292) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:234-235, warning level only) |
| 10 | revise | yes | no | Blocked: `Plan review requested changes (round <n> of 3) and the plan has not changed since. …` (plan-review.ts:299) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:117-120) |
| 11 | revise | no | yes | Passes with row 7's warning (plan-review.ts:287-292) | out of harness scope — omp terminal session (no Bun test) |
| 12 | revise | no | no | Blocked as in row 8 (plan-review.ts:300) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:122-123) |
| 13 | unavailable | yes | yes | Passes with no warning at the gate; the failed run already warned (plan-review.ts:200, 286) | out of harness scope — omp terminal session (no Bun test) |
| 14 | unavailable | yes | no | Passes with no warning at the gate; the failed run already warned (plan-review.ts:200, 286) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:166-169, 171-174) |
| 15 | unavailable | no | yes | Passes with row 7's warning (plan-review.ts:287-292) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:192-196) |
| 16 | unavailable | no | no | Blocked as in row 8 (plan-review.ts:300) | out of harness scope — omp terminal session (no Bun test) |
| 17 | skipped | yes | yes | impossible — the tool returns before any reviewer run once 3 rounds are counted (plan-review.ts:191-196), and a skip keeps the earlier count (plan-review.ts:207), so a skip records at most 2 | — |
| 18 | skipped | yes | no | Passes with no warning at the gate; the skip already warned (plan-review.ts:208-211, 286) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:202-206) |
| 19 | skipped | no | yes | impossible — as row 17 | — |
| 20 | skipped | no | no | Blocked as in row 8 (plan-review.ts:300) | out of harness scope — omp terminal session (Bun test: plan-review.test.ts:209-210) |

- **Unresolved title.** A title that resolves to no plan file is left to OMP's own `xd://propose` handler (plan-review.ts:281-283); unchanged in this delivery — omp terminal session.

**One `plan_review` call.**

- **No plan file.** The call rejects with `No plan file found for "<title>". Write the plan to local://<slug>-plan.md first.` and runs no reviewer (plan-review.ts:186-187); unchanged, no Bun test — omp terminal session.
- **All rounds used.** With 3 rounds counted for the plan file, the call runs no reviewer and returns `All 3 plan review rounds for <url> are used. Write "<slug>" to xd://propose; the user decides on the plan without another review.` (plan-review.ts:191-196). Bun tests: plan-review.test.ts:193-194, 231-232 — omp terminal session.
- **Approve or revise.** The result reads `Plan review of <url> by <provider>/<model>, round <n> of 3: approved` or `: changes requested`, lists each finding as `- [<severity>] <location>: <issue> Fix: <fix>`, and records `rounds: <n>` (plan-review.ts:251-273). Only the line that sets `round` moved. Bun test: plan-review.test.ts:114-132 — omp terminal session.
- **A run that cannot finish.** Each failure records `unavailable` with `rounds: <n>`, shows the `warning` `Plan review could not run (round <n> of 3); the plan goes to approval unreviewed.` with the reason on the next line, and returns `Plan review could not run (round <n> of 3); write "<slug>" to xd://propose, the plan goes to approval unreviewed.` with the reason (plan-review.ts:198-205). The reasons are `<error>.` when `pi.exec` throws (plan-review.ts:238), `the reviewer did not finish within 15 minutes.` (plan-review.ts:243), `the reviewer exited with code <code>: <stderr tail>` (plan-review.ts:244), `the reviewer's output has no final answer: …` (plan-review.ts:246) and `<reviewer>'s answer is not the expected JSON: …` (plan-review.ts:249). OMP's `pi.exec` reports a timeout or an abort as `killed: true` instead of throwing (`pi-coding-agent/src/exec/exec.ts:26-27, 42-54`). Bun test plan-review.test.ts:177-197 covers exit code 1, a killed run and a prose answer as rounds 1 to 3, then the fourth call; no test counts a round for a thrown error or a missing final answer — omp terminal session.
- **Esc.** In OMP, Esc during a streaming turn aborts the session with `USER_INTERRUPT_LABEL`, the string `Interrupted by user` (`pi-tui/src/chat/messages.ts:101`; `pi-coding-agent/src/modes/controllers/input-controller.ts:574-578, 591-592, 328-329, 2000-2001`). The reason reaches the agent's AbortController (`pi-coding-agent/src/session/agent-session.ts:10216`; `pi-agent-core/src/agent.ts:1553-1554`), whose signal the `write` call receives (`pi-agent-core/src/agent-loop.ts:3309, 3348`) and the device dispatch passes to the extension (`pi-coding-agent/src/internal-urls/xd-protocol.ts:97-103`; `pi-coding-agent/src/tools/xdev.ts:484`). The extension then records `skipped` without using a round, shows the `warning` `Plan review skipped: the current text of <url> goes to approval unreviewed. Any edit to the plan needs a new review.` and throws `Plan review cancelled by the user. If the user asks to propose the plan, write "<slug>" to xd://propose; its current text goes to approval unreviewed.` (plan-review.ts:206-216, 242). By then the `write` call has already rejected with OMP's own abort error (`pi-coding-agent/src/tools/write.ts:844`; `pi-utils/src/abortable.ts:74-78`), so that text is not the `write` result; the agent's instruction comes from the plan-mode prompt (plan-review.ts:48). Bun test plan-review.test.ts:199-213 covers the rejection, the warning level, the unchanged text passing the gate, the edited text being blocked and round 1 on the next review; the delivery plan's step 5 checks it in a real terminal (docs/plans/2026-10-20-plan-review-progress.md:104) — omp terminal session.
- **Other aborts.** An abort without that reason, such as `/compact` (`pi-coding-agent/src/session/session-maintenance.ts:1210`), rejects with exactly `Plan review cancelled.`, shows no notification and records nothing, so the gate keeps the earlier record (plan-review.ts:216, 237, 242). Bun test: plan-review.test.ts:215-223. Aborts that carry the reason without Esc are BLK-01 — omp terminal session.
- **Plan-mode prompt.** In plan mode the system prompt tells the agent not to review an unchanged plan text again after the user cancelled its review, unless the user asks; to write the slug to `xd://propose` when the user wants the plan proposed; and to review again after any edit (plan-review.ts:48, 171-174) — agent model behaviour in an omp terminal session.

**Review progress.**

- **Updates.** The first update goes out at once, then one every 15 s while the reviewer runs, with the elapsed time counted from the start of the call (plan-review.ts:218-227). The first line stays under 70 characters: with a two-digit minute, `Plan review round 3/3: 14:59 elapsed (stops at 15:00). Esc skips it.` is 68. Updates stop when the run returns, fails or is aborted (plan-review.ts:239-241). Bun test plan-review.test.ts:134-163 checks `0:00`, `0:15`, `0:30`, the line length and that no update follows, with fake timers; the delivery plan's throwaway smoke test does the same with real timers (docs/plans/2026-10-20-plan-review-progress.md:101) — Bun test.
- **Display.** OMP forwards each update to the `write` call's progress (`pi-coding-agent/src/tools/xdev.ts:467-474`). A device without its own renderer, like `plan_review` (plan-review.ts:176-275), is drawn as plain tool output (`pi-tui/src/tools/xdev.ts:263-271`), whose collapsed lines are clipped to the terminal width (`pi-tui/src/tools/default-renderer.ts:137`). Whether the collapsed output visibly advances every 15 s is the delivery plan's manual step 5 (docs/plans/2026-10-20-plan-review-progress.md:104) — terminal UI.

**Documentation, release and repository checks.**

- **Optional plugin.** `docs/plugins/plan-review.md:5` says no other plugin calls `xd://plan_review`. In `plugins/`, `omp/` and `plugins-omp/`, only the plan-review extension, its test and its generated copy mention it — prose, no executable behaviour.
- **Restart rule.** `docs/plugins/plan-review.md:19` and `docs/oh-my-pi.md:15` tell the user to quit and restart `omp` after installing, disabling or uninstalling a plugin. `/reload-plugins` reloads skills, slash commands, task agents and MCP servers, not extensions (`pi-coding-agent/src/slash-commands/builtin-marketplace.ts:25-42`) — OMP process lifecycle, observable only in a terminal session.
- **Timing and rounds.** `docs/plugins/plan-review.md:24, 28, 30, 32` match the extension: updates every 15 s (plan-review.ts:24), a 15-minute reviewer limit (plan-review.ts:23), failed runs counted (plan-review.ts:199), at most 3 rounds (plan-review.ts:20, 191) and an Esc skip that uses no round (plan-review.ts:207). The 7-minute median comes from the owner's session logs (docs/plans/2026-10-20-plan-review-progress.md:12) — prose, no executable behaviour.
- **Release.** Version 0.2.0 is in the six places listed in Changes Summary, and `python3 scripts/check_plugin_versions.py` is expected to print `[plan-review] 0.2.0 (OK, OMP-only)` and `Version parity OK` (docs/plans/2026-10-20-plan-review-progress.md:103) — repository CI script.
- **Generated edition and tests.** `python3 scripts/build_omp_edition.py --check` is expected to exit 0 (docs/plans/2026-10-20-plan-review-progress.md:102), and `bun test tests/plan-review.test.ts` in `omp/native/plan-review` to pass, the new tests included (docs/plans/2026-10-20-plan-review-progress.md:100) — repository CI script and Bun test.
- **Manual run.** `omp --no-extensions -e omp/native/plan-review/extensions/plan-review.ts`, then `/plan` and a plan that fixes one typo in `README.md`. The collapsed output shows `Plan review round 1/3: 0:00 elapsed …` advancing every 15 s; Esc shows `Plan review skipped: …`; `Propose the plan without another review` opens OMP's approval dialog (docs/plans/2026-10-20-plan-review-progress.md:104) — interactive terminal with a real reviewer model.

---
allowed-tools: Bash(git:*), Bash(mkdir:*), Bash(python3 ${CLAUDE_PLUGIN_ROOT}/skills/engine/scripts/qa.py *), mcp__plugin_playwright_playwright__browser_navigate, Read, Write, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskOutput, Skill, AskUserQuestion
description: Run the flagless QA test-fix-retest loop — bootstrap project config, resolve existing users, execute a reviewed plan, fix eligible failures and independently retest them.
model: opus
argument-hint: [plan path or change source]
---

# QA Test-Fix-Retest Runner

`/qa:run` is the only QA executor. It coordinates config → plan → environment → users → baseline → fix iterations → final verification → report → teardown through `qa:engine`. The model owns planning, tester/fixer dispatches and sanitized issue prose; the engine owns config transactions, trust, guards, credentials, durable state, verdicts, QA IDs, budgets, history and report rendering.

**Never write or edit the sidecar or report yourself.** Do not patch counters, invent a PASS, allocate QA IDs, write Status lines or replace engine bookkeeping with shell snippets. `## Setup` is optional human context, not a source of targets, credentials or services.

## Arguments

**Input:** `$ARGUMENTS`

| Input | Interpretation |
|---|---|
| (empty) | Engine selects the newest plan for the current branch, or requests generation. |
| `<plan path>` | Use that existing plan. |
| `<change source>` | Author and review a plan for that source: `#123`, a branch, `last N commits`, or `staged`. |

No options are accepted. If any argument token starts with `--`, stop **before I/O** with exactly:

> Error: /qa:run takes no options; set policy in .av/config.toml (see docs/plugins/qa.md#configuration).

Keep a multiword change source as one argument to `plan resolve`; do not interpolate repository/user text as shell code. Policy comes from committed `.av/config.toml` plus git-ignored `.av/local.toml`, never invocation flags.

## Engine and interactivity

Load `qa:engine` before calling the CLI and follow its installed-script resolution and exit handling. In Claude Code every engine call has this form:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/engine/scripts/qa.py <subcommand> <arguments>
```

In OMP resolve `realpath skill://qa:engine/scripts/qa.py` and substitute the returned absolute script path in **every** call below. Do not run the project's own `qa.py`, guess an installation path or use `CLAUDE_PLUGIN_ROOT` in OMP. Internal engine switches are not `/qa:run` options. Engine-returned paths and dispatch IDs are authoritative.

**Ask capability, not Bash stdin, decides interactivity.** Use `AskUserQuestion` (OMP: `ask`) for every human gate. An unavailable tool or a question the harness cannot deliver makes this invocation headless for the rest of the run. Never manufacture an answer, choose a likely option on behalf of the user, or treat an absent ask tool as consent; this fail-closed rule also applies when executing as a subagent. Do not run a TTY probe. Headless behavior is specified at each gate below; notably, `qa.fix = "approve"` still tests and reports but applies no fixes.

**Mandatory stop recording and cleanup:** once `run start` succeeds, every stop, abort or error calls `run stop --run <run> --reason <reason> [--detail <safe-diagnostic>]` **before** flushing the partial report and entering Step 12. Use `user-abort` for a declined gate/interrupt, `config-drift` for `config changed during run`, `plan-changed` for a plan hash mismatch, `cleanup-error` for failed teardown/down, and `other` for remaining errors, headless hard stops or engine stop decisions. Detail contains only sanitized engine diagnostics, failing probe names/statuses or a short explanation, never values, headers or raw command/recipe output; the engine flattens it to one line. A repeated stop preserves the original reason. The engine summary, not narration beside it, owns `Stopped`. Do not repair state or keep testing against drifted config. Flush without `--final`; a recorded stop cannot write new Status lines even if `--final` is requested.

**Capture before bootstrap writes:** after argument validation and before Step 1 can write shared config, run `git -c core.quotePath=false diff --name-only HEAD`. Retain each full path (never whitespace-separated fields) and use Write to save a JSON array of those paths to a temporary `<baseline-file>` outside the repository, including `[]` for a clean tree. This is input to `run start --baseline-file <baseline-file>`, not a sidecar edit. It preserves pre-existing config/gitignore dirt but excludes this invocation's subsequent bootstrap writes. Keep the file through start retries; remove it after a successful start.

## Workflow

### Step 1: Config and trust

Run `config`; retain its safe metadata, `provenance`, warnings and policy.

- `missing-file` / `missing-table`: interactive → run the **Config bootstrap** below in `create` mode. First use `plan resolve` with the original argument to supply the selected plan path, if any, to the author; this lookup does not generate a plan yet. Headless → stop with exactly:

  > Error: no QA configuration in .av/config.toml — run /qa:run once in an interactive session or write it by hand (docs/configuration.md).

- `invalid`: show all file/key errors and stop. An engine/version/I/O error is not a missing config.
- `ok`: print warnings and continue.

On `trust = new` or `changed`, show the complete masked `trust_subset` and ask once to trust it or stop. Accept → `trust accept <trust_hash>`; decline or headless → stop without executing a source, service command or recipe. A changed hash at acceptance is a stop, not permission to accept a new hash silently. Re-read `config` after a successful bootstrap or trust acceptance.

### Step 2: Resolve, author and review the plan

Run `plan resolve` with the original positional argument as one quoted operand (omit the operand when empty).

- `reuse`: keep the returned path.
- `generate`: load `qa:plan-authoring` with the returned source and safe `config` metadata. Follow its shared draft/review workflow; do not ask for permission to generate, write an inline plan or duplicate its tool probes. Use its returned path without re-globbing. Mark it **generated in this invocation** and pass `--generated` at Step 5, including start retries and repair restarts. Show `Generated plan: <path> — N FE, M BE` using the saved plan's scenario headings.
- `stale`: list `changed_files`; interactive → ask once: **Regenerate** (default) / **Use existing plan**. Headless → regenerate through the same skill and mark it generated as above. A failed regeneration never falls back to the stale plan; choosing the existing plan does not set the generated marker.

Show the authoring skill's review outcome, reason and unresolved findings. An open `blocker` → interactive: **Run anyway** / **Stop and fix the plan with /qa:create-plan**; headless or a declined gate → stop and list it. Print open concerns and continue; an unreviewed plan is never described as approved.

Read the selected plan. If it has zero FE and zero BE scenarios **and was just generated in Step 2**, stop gracefully before starting a run:

> Generated plan has no executable FE or BE scenarios — nothing to test (e.g. a backend-only change fully covered by the unit/integration suite). Relying on that suite; not launching testers.

A reused/existing plan with zero scenarios instead stops with `Error: plan <path> has no executable FE or BE scenarios.` Name the selected plan; do not reuse the generated-plan success message.

### Step 3: Check the plan against config

Run `plan check <plan>`.

- Non-empty `plan_errors` or `off_target`: stop and list every scenario/reason or scenario/origin diagnostic; never widen targets silently or turn a plan error into a config extension.
- Missing users, values, targets or stores: interactive → **Config bootstrap** in `extend` mode for exactly the returned gaps and their dependencies, then re-read `config`, handle its trust as in Step 1, and re-check the same plan **once**. Headless, a blocked extension or remaining required gaps → stop, naming the missing config keys. A required-gap extension never blocks on cleanup; `missing.cleanup` is handled only by the separate cleanup-only round.
- `missing.cleanup` alone is a soft gap: interactive → one cleanup-only `extend` round with `Missing: cleanup`, including at most the bootstrap's single preview-error retry. If the author returns `proposal: null`, preview errors remain after that retry, the approval gate is declined/unavailable, or the invocation is headless, retain the existing valid config, print `No cleanup recipe: registered accounts will remain in the application.` and continue. Never stop for this gap alone; required gaps or an invalid config still stop. After an applied cleanup proposal, re-read config/trust and re-check the plan.
- Preserve the returned sections, user/value requirements, registrations, `guarded` and `state_checks` for dispatch. Credentials are derived from plan `$QA_…` tokens by the engine, not environment-presence snippets.

### Step 4: Working-tree safety

When `qa.fix != "off"`, use the tracked-modified paths captured **before Step 1**, not a new diff after config bootstrap. `run start --baseline-file <baseline-file>` persists them as `pre_loop_dirty`; never write them into the sidecar yourself. On a repair restart the engine reads the persisted first-pass baseline through `--baseline-run <ended-run-id>`, instead of re-reading the changed tree.

For a non-empty set, follow `qa.fix`:

- `fix = "off"`: skip this step.
- `fix = "approve"`: warn that fixes may overlap the user's work and ask **Proceed** / **Abort**. Headless aborts.
- `fix = "auto"`: proceed with the recorded baseline; this never authorizes whole-tree recovery.

A successful config bootstrap's own `.av/config.toml` and `.gitignore` changes are not pre-existing user dirt. On a repair restart retain the first pass's `pre_loop_dirty`; do not add this invocation's fix edits or bootstrap changes to that baseline, and do not treat them as a fresh dirty-tree failure.

### Step 5: Start the run

Run `run start <plan> --baseline-file <baseline-file>` on the first pass, adding `--generated` **only** when Step 2 generated/regenerated this invocation's plan. Retain `run`, `dir`, `sidecar`, `report` and `idempotency`. On **Repair restart**, replace `--baseline-file` with `--baseline-run <ended-run-id>`; never pass both. Preserve these switches on trust retries and an approved takeover. Let the engine reuse/adopt/rebaseline artifacts and preserve stored provenance; never copy, move or hash them yourself.

- `trust required`: re-read `config`, use Step 1's trust question **once**, then return to Step 3 with the selected plan kept. Headless or a second failure → stop.
- A live origin lock: show the holder's run ID and start time; interactive → ask whether to **Take over** the interrupted run or **Stop**, then on approval add `--takeover <holder-run-id>` to the same `run start` call, retaining its baseline and generated switches. Headless → stop, naming the holder. No blind takeover; the old account ledger must survive.

After success, cleanup is compulsory even if all later work fails.

### Step 6: Services

Run `services check --run <run>`.

If probes fail and `up` is configured, follow `qa.start_services`: `"ask"` (default) asks once whether to start/prepare the configured services; headless records `run stop --run <run> --reason other` with the failing probes and goes to Step 12. `"auto"` prints the bring-up scope and proceeds without a question. **Decline → `run stop --run <run> --reason user-abort` with the failing probes, then Step 12; never enter repair after a decline.** Approval or `"auto"` → `services up --run <run>`, `services prepare --run <run>`, then re-check. `prepare` runs only after QA's own `up`, not against an already-running stack. Track whether this run executed `up`, so only its own services are stopped later.

Still down, no usable bring-up, or a lifecycle recipe error → interactive: **Config bootstrap** in `repair` mode with the error/failing probes; headless → stop with those diagnostics. A successful repair follows **Repair restart**, not an in-place continuation.

### Step 7: Users and secrets

Always run `users provision --run <run>`, even when the plan references zero users: it creates the private tester channel and the run's `QA_NEW_PASSWORD`. Print configured user names only, not passwords, tokens or cookies. Keep only its channel paths and names for dispatch; do not read engine-private state, `secrets.env`, `secrets.json` or source outputs.

A required missing `file:.av/secrets.local.env#NAME` value names the keys to fill and stops; never ask the user to paste secrets, edit `.envrc`, export new harness credentials or restart the harness. Other provisioning errors stop with the engine diagnostic. Testers perform login and registration themselves; there is no engine login repair.

### Step 8: Baseline

Use **Tester dispatch** below for each present section with `--phase baseline`. Engine calls are sequential; FE/BE tester agents may then run in parallel. Save complete answers under `<dir>/results/` and `ingest` each with its own dispatch ID.

Print all remaining `need_info` service/tool/fixture gaps grouped by kind, names only, with scenario/edge IDs. Interactive → ask once: **Re-run affected sections** / **Continue** / **Abort**. Retry uses each affected **whole section** once with `--phase retry`, fresh engine dispatches and the same template; ingest again and do not re-ask if gaps remain. Headless → continue with the gaps visible. An abort still flushes the partial report and tears down.

### Step 9: Issues and baseline report

Load `qa:report-format` for issue prose/severity conventions, not to recompute verdicts or render the report by hand. Follow **Issue prose and report** below: `issues`, write entries only for newly assigned keys, then `report --run <run> --issues <issues-file>`.

If there are zero failures, go directly to Step 12, skipping fixes and the final run. Relay the engine's zero-failure, all-unverified and shallow-coverage messages rather than converting an all-SKIP/NEED_INFO human-authored plan to a pass. Coverage is disclosure, never a green-to-red gate.

### Step 10: Iterations and fix step

`qa.fix = "off"`, or headless `approve` → Step 12 without opening fix work or performing a final run; disclose **test/report only** and why no fix was applied.

Otherwise loop on `iteration open --run <run>`:

- `stop`: show its reason, record `run stop --run <run> --reason <plan-changed|other> --detail <returned-reason>` (`plan-changed` for a hash mismatch, otherwise `other`), flush a partial report without Status write-back and go to Step 12.
- `final`: Step 11, unless the reason is zero failures and no fix iteration ran (Step 9's direct teardown).
- `iterate`: use the returned iteration number; run `candidates --run <run>`. Print every dropped QA ID with its reason; never override a guard or manufacture an eligible candidate.

For `approve`, show one batch gate per iteration: candidate ID, severity, scenario, title, every `flags[]` value (including `auth` and `unverified`), configured target origins, remaining budgets and **all prior `fix done` anti-hardcoding warnings**. Use one `AskUserQuestion`: **Approve & continue** / **Skip to final run** / **Abort**. Skip → Step 11; abort → `run stop --run <run> --reason user-abort`, partial-report flush and Step 12; an undeliverable gate → `run stop --run <run> --reason other --detail 'fix approval unavailable'`, no fix, Step 12. An empty fix-set needs no approval: go to final verification rather than opening an unbounded empty loop. On Skip/empty-set the engine closes the dangling iteration in `report --final`; on a stop it closes it in `run stop`, with `summary` as a final safety net. No manual history/sidecar patch is needed.

For `auto`, print a non-silent scope banner with candidates, dropped guards, targets and budgets, then proceed. Interrupting the session is an abort, not success.

For each candidate **sequentially**, call `dispatch --run <run> fix --qa <QA-ID>` before launching `code-review:fix-auto`. Read its issue block from the engine-rendered report and apply this rule:

**Dispatch-copy rule.** `/qa:run` is itself a dispatcher of the finding block the `qa` and `code-review` plugins share, so what `fix-auto` receives is the **dispatch copy** of the block, not the raw block. It carries the reviewer-authored fields plus the rewritten `**Location:**` line, which travels in full — corrected value, `(was: …)` parenthetical and all. Every other line on the closed list is handled exactly as `code-review`'s `decision-gate` skill defines it at stage 3:

| Line | In the dispatched copy |
|---|---|
| `**Location:**` | **travels**, rewritten form and all |
| `**Verification-plan:**` | stripped |
| `**Decision-pin:**` | stripped |
| `**Dispatch:**` | stripped |
| `**Verification:**` | stripped |
| `**Decision-retired:**` | stripped |
| `**Decision:**` | reduced to its trailing `User decision: <resolution>` |
| `**Status:**` | **travels unchanged** — every Status line the block carries here pre-dates this run (this loop writes none before Step 11), and `fix-auto`'s own abort on `🚫 Rejected` reads exactly it |

All of the stripped lines **stay in the source report** — that is what the replay path and the decision-gate's verification read. A fixer holding unrestricted `Edit`, `Write` and `Bash`, told to iterate until its fix verifies, must not be handed the checks it will be graded by; without this rule a decided-but-unfixed finding arrives carrying them.

```text
Task(
  subagent_type: "code-review:fix-auto",
  run_in_background: false,
  description: "Auto-fix: [<SEVERITY>] <Issue-ID>: <Title>",
  prompt: "<the issue block from the report, rendered as the dispatch-copy rule above defines it>

INJECTED CONSTRAINTS FOR THIS FIX:

1. Source-only fix: do not modify the test plan, plan-referenced test files, or test scenarios.
2. Fix only the source code under test.
3. Keep the working tree clean (uncommitted changes only, no staging).
4. If a location-less issue arrives, return Failed — do not prompt. Read the Location field by its two-clause rule: take the first backticked token, ignoring any trailing parenthetical; where the line carries no backticked token, take the first whitespace-delimited token after the field name. Under either clause a value of —, unknown:0, or anything that does not parse as path:line or path:line-range is location-less. Never test the whole line: a corrected Location preserves the original unknown:0 inside its (was: ...) tail, and a whole-line test would fail a fix that is perfectly dispatchable.
5. Never weaken an authentication or authorization check to make a scenario pass."
)
```

Collect **Fixed**, **Partially Fixed**, or **Failed**; map them to `fixed`, `partial`, or `failed` for `fix done --run <run> --dispatch <fix-dispatch> --result <result>`. A failed dispatch/unusable fixer answer is `failed`, never a guessed success. The engine computes and records anti-hardcoding warnings; show them at the next approval gate and in the final summary. They are best-effort, non-blocking human-review flags, not proof of a real fix.

Re-run the whole FE/BE sections affected by the candidate scenarios with `--phase iteration`, using fresh **Tester dispatch** calls, then ingest. The fixer's verdict is advisory: **only the independent tester re-run is authoritative**. Call `issues` and render new issue prose/report entries, then `iteration close --run <run>` exactly once. It owns progress, regressions, history, touched files and overlap: `final` → Step 11; `continue` → next `iteration open`. Never increment budgets, compare verdict maps or append history rows yourself.

### Step 11: Authoritative final run

After entering Step 10's iteration path, re-run **all present sections**, not merely those fixed, with `--phase final` through **Tester dispatch**. This pass is counted but is not blocked by exhausted fix budgets. Do not run it after a zero-failure baseline, `off`, headless `approve`, a user abort or a hard stop.

Ingest every section; call `issues` and write prose for any assertion first failing here, regressions included. Only then call `report --run <run> --final --issues <issues-file>`.

The engine writes `**Status:** ✅ Fixed` exactly once only for a whole-scenario PASS (main and every edge), preserves `🚫 Rejected` and its reason, never freezes an unverified/partial issue as Partially Fixed, and retains the existing decision record and corrected Location. A final regression is reported, not auto-fixed. Do not imitate this write-back with Write/Edit.

### Step 12: Teardown, summary and recovery

On any stop/error/abort after start, first call `run stop --run <run> --reason <reason> [--detail <safe-diagnostic>]` with the reason mapping above, then use `issues` and **Issue prose and report** to flush current observations and history without `--final`; preserved existing Status lines stay, but no new ones are written. `run stop` closes any dangling iteration, including a stop after a fix dispatch: touched files, overlap, attempts and warnings reach the report. Then, on **every** started-run exit, in order:

1. `users teardown --run <run>` — print `deleted`, `left` and `manual` emails; cleanup failures are visible, never silently ignored.
2. `report --run <run> --accounts` — update only the Accounts summary line, never verdicts or Status.
3. `services down --run <run>` if this run executed `up`.
4. `summary --run <run>` — relay its result, stop reason/detail, counts, Coverage, warnings, unlock hints, budgets and recovery. Disclose any headless fix skip beside it; do not recompute or upgrade its verdict. The engine closes any still-open iteration before summarizing.
5. `run end --run <run>` — release target/store locks and delete the private directory.

A failed cleanup operation does not suppress the remaining cleanup calls; record `run stop --run <run> --reason cleanup-error --detail <safe-diagnostic>`, flush the non-final report again, and report its diagnostics. `services down` uses the recorded, previously trusted command even after drift. Registered-account cleanup uses only valid, currently trusted config and a destination locked by this run; undeleted records remain in the external ledger for a later trusted teardown. A prior stop reason remains the primary reason.

The `qa:engine` skill owns the closed Result vocabulary, predicates and routing. Always show its machine-locatable `**Result:**` line with report/plan paths and its evidence; coverage gaps route to its unlock hints, not a claim of full verification. Budget exhaustion and stops are not success.

Keep this recovery wording:

> To recover the loop's own edits: `git restore <fix_touched_files>`  (scoped — restores only what the loop's fixes touched, never your pre-existing changes)
>
> **Changes remain uncommitted for your control.**

Use the engine's accumulated eligible paths, safely quoted with `--`, for the placeholder; this is a hint for the user, **never an instruction to restore automatically**. Never print whole-tree recovery, including under `qa.fix = "auto"`. If the set is empty, state that the loop touched nothing to recover. For overlap, retain this wording with the engine's paths:

> Note: <files> were already modified before the loop and also edited by a fix — left untouched for you to reconcile (not included in scoped recovery).

## Tester dispatch — one template for every phase

Before executing an existing plan's baseline, use engine `tools` plus the browser probe `browser_navigate(url: "about:blank")` for FE (OMP: the preamble's browser mapping). Tool gaps do not invent PASSes: testers return `NEED_INFO kind=tool`; a missing store client skips only its State Check, not runnable HTTP assertions.

For each present section, **one engine call at a time**:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/engine/scripts/qa.py dispatch --run <run> tester --section <FE|BE> --phase <baseline|retry|iteration|final>
```

A dispatch no longer logs anyone in: testers log in and register accounts themselves. The engine records the assignment, issues its tag and creates private capture files before the tester starts. A failure stops before launching that tester: call `run stop --run <run> --reason <reason>` (`config-drift`, `plan-changed` or `other` as applicable) before Step 12. After preparing both assignments sequentially, launch `qa:fe-tester` / `qa:be-tester` in parallel with `Task(..., run_in_background: true)` when both are present. Use this exact template for each:

```text
Plan: <plan path>
Dispatch: <dispatch id>
Run dir: <dir>
Secrets file: <dir>/secrets.env
Secrets JSON: <dir>/secrets.json
Redact names file: <dir>/redact-names
Tag: <tag>
Targets:
<name> = <origin>, one per line; default for this section: <name> — config.defaults.FE for FE, config.defaults.BE for BE
Stores: <name> (<kind>), one per entry from the dispatch's stores[], or none
Guarded: <scenario IDs marked mutation-guard, or none>

<FE|BE> Test Scenarios:
<all scenario blocks of the section, in plan order>

End with the qa-results JSON block. Never print a secret value.
```

Targets/defaults come from checked config; Stores uses the dispatch's `stores[]` and config's kind/engine metadata; Guarded uses the engine's section assignment, not a model-invented exemption. Keep all section blocks and edges in plan order. Do not dispatch an absent section or expose `[env.secrets]`, recipe sources or literal credentials. Every request/State Check call uses the channel loader; the OMP FE tester uses its private JSON channel, not inherited harness environment.

Collect each answer with `TaskOutput`, save it verbatim to `<dir>/results/<dispatch-id>.md` using Write, then `ingest --run <run> --dispatch <dispatch-id> <result-file>`. A missing, malformed, duplicate or incomplete `qa-results` block means engine-reported `cannot-confirm`, never a retained PASS; do not repair or fabricate the result block.

## Issue prose and report

Call `issues --run <run>` on every reporting pass. For its newly assigned `assign[]` entries, use the plan and sanitized tester evidence to author a JSON list in `<dir>/results/issues.json`:

```json
[{"qa": "<engine-assigned QA-ID>", "title": "<issue>", "severity": "HIGH", "location": "<path:line>", "actual": "<sanitized observation>", "impact": "<effect>", "remediation": "<source fix guidance>"}]
```

Optional fields: `severity_reason`, `response`, `screenshot`. Use the blocker's cited source Location when present; an unknown location remains `unknown:0` and is not fixable by guesswork. Never include headers, tokens, cookies, DSNs or raw response bodies. The engine copies each Expected grounding tag and tester Refutation itself.

Respect `severity_floor`: status ≥ 500 or `crash` is CRITICAL; otherwise an unverified assertion is LOW. Other CRITICALs require `severity_reason = security-bypass|data-loss` and evidence in `actual`; all remaining severities follow `qa:report-format`. Never lower a mechanical floor or promote an unverified guess. New keys only; `[]` is valid when there are none. The engine preserves earlier issue prose and decision fields from the report.

Use `mkdir -p docs/testing/reports` if the directory is absent, then `report --run <run> --issues <issues-file>` (add `--final` **only** in Step 11). This is the sole renderer and QA-ID/Status authority.

## Config bootstrap — create, extend or repair

Interactive only. This is the generic `qa:env-config` detection/write contract plus the QA layer implemented by the read-only `qa:config-author`; do not establish another environment detector.

1. Dispatch `qa:config-author` with `Mode: create|extend|repair`, safe `config` metadata including provenance, and the selected `Plan:` or `none`. `extend` adds `Missing:` with exactly the plan-check gaps; `repair` adds `Failure:` with the engine error/failing probes and affected keys. It may read only repository evidence with Read/Grep/Glob: **never execute a candidate command, probe a recipe or read a secret value**. Each proposed target/command/recipe must cite its repository source in a TOML comment. The return is `{proposal, questions[]}`.
2. `proposal: null`, inaccessible evidence or an intended key supplied by `.av/local.toml` → stop and name the blocker/local key, **except for Step 3's cleanup-only soft-gap extension**, which retains the valid config and continues with its exact no-cleanup message. A shared edit cannot override a local key. Never read/edit personal config or widen the proposal to evade provenance. In `create` only, ask the three returned policy questions **in one ask call**: disposable data → `qa.mutations` (`allow` only when every target is loopback and the user confirms the data is disposable, else `deny`), fix handling → `qa.fix` (`approve|auto|off`), and bring-up → `qa.start_services` (`ask|auto`), then apply the answers to the transaction. Do not reopen policy during extend/repair.
3. Save the proposal transaction with Write to a temporary JSON file, not directly to `.av/config.toml` or `.gitignore`. It contains full `config_text`, only necessary `gitignore_add` entries for `.av/local.toml` / `.av/secrets.local.env`, and minimal `allowed_keys`. Preserve all unrelated keys/tables/comments byte-for-byte. Run `config preview <proposal-file>`.
4. Preview errors → **one** further author round with those errors, the original scope and already answered policy choices; save and preview the revised proposal. Remaining errors → stop, except a cleanup-only extension follows Step 3's soft-gap continuation. Otherwise show the complete `diff` for **both `.av/config.toml` and `.gitignore`**, including every ignore addition, **and** masked resulting `trust_subset`, including existing shared commands, and ask once to **Apply and trust** / **Decline**. Decline or an undeliverable question → no shared write; stop with Step 1's configuration guidance, except a cleanup-only extension retains the valid config and continues as in Step 3. A proposal is not consent to run its commands.
5. Approval → `config apply <proposal-file> --snapshot <preview-snapshot> --approved-hash <preview-trust-hash>`. Compare-and-swap conflicts write nothing; show the error and stop. Never retry against a new snapshot without approval. The engine alone writes `.av/config.toml` and `.gitignore` atomically and records the approved trust hash.
6. Required missing `file:.av/secrets.local.env#NAME` entries → print **names only** to fill and stop. Never create/populate the secret file, ask for a value in chat or bypass the channel. Otherwise re-read `config` and continue at the caller's step.

**Repair restart:** allow at most **one repair per failure kind per invocation**, across restarts. After a successful Step 6 repair, record `run stop --run <run> --reason other --detail 'configuration repaired; restarting'`, flush the current partial report and run Step 12 completely (`users teardown`, Accounts report update, `services down` only when this run started them, `summary`, `run end`). Retain the **ended run ID** as `<baseline-run>` even though `run end` deletes its private directory. Restart at Step 3 with the same plan and current trusted config, then Step 5 calls `run start <plan> --baseline-run <baseline-run>` (plus `--generated` when Step 2 generated it). The durable sidecar keeps the first pass's dirty paths and fingerprints across every restart. Do not reuse the old active run ID, targets, credentials or origin/store locks. A second failure of that kind records a stop with its diagnostics and still cleans up. Sources unavailable for cleanup leave ledger records visible, never hidden; a failed cleanup stops rather than starting another pass.

## Modes & Safety Guards

### Policy modes

| Policy | Behavior | Headless behavior |
|---|---|---|
| `qa.fix = "approve"` (default) | One batch gate per iteration, including flags and prior warnings. | Baseline and report only; no fix and no final run. |
| `qa.fix = "auto"` | Scope banner; eligible source-only fixes without a batch question. | Same eligible fix loop; trust/bootstrap/lock takeover still require a real ask. |
| `qa.fix = "off"` | Test/report only; no source fixes. | Same test/report behavior. |
| `qa.start_services = "ask"` / `"auto"` (`ask` default) | `ask` asks once before bring-up; `auto` prints scope and runs `up` + `prepare`. | `ask` stops when bring-up is needed; `auto` runs the configured lifecycle. |

There is no per-fix/step mode. Every failing assertion is a fix candidate. The engine's fixed limits bound fix work: 3 iterations, 50 tester/fixer dispatches and 30 minutes; the authoritative final pass is counted but not limit-gated. Stop/no-progress/regression decisions are engine-owned, distinct from success. There is no cost/token ceiling.

**Loop-engineering item 4 disclosure: not met.** The bar calls for a fail-closed TTY check, but an agent's Bash stdin is never a TTY. This command instead uses the ask tool as its interactive oracle, fails closed on undeliverable questions and allows headless fixes only under explicit `qa.fix = "auto"`. Do not claim full conformity or silently revise the bar.

### Safety Guards (Apply in All Modes)

- **Origins and trust:** config targets are exact HTTP(S) origins; userinfo/off-target URLs are refused, and redirects are never followed automatically. Non-loopback targets and executable/value-source config are hash-pinned outside the repository. Changed trust requires the complete-subset gate, never a host flag or a plan-authored override.
- **Mutation policy:** `qa.mutations = "deny"` guards every scenario whose `- **Writes:**` line is `yes`, missing or invalid, and every scenario the syntactic scan sees writing; registration counts as a write. `allow` guards nothing and is meant only for disposable data. Guarded scenarios are SKIP, not fixed.
- **Working tree:** the dirty-tree gate follows `qa.fix` (approve asks, auto proceeds with the recorded baseline, off skips); recovery excludes pre-existing dirty files and discloses overlap; changes remain uncommitted and unstaged.
- **Plan-suspect guards (per issue):** a BE main flow expecting 2xx that gets 401/403 is a FAIL flagged `auth`, never auto-fixed. `candidates` excludes these failures and unverified assertions in `auto`, while `approve` surfaces their flags for human review. A grounded sibling failure remains independently eligible. Rejected, location-less, incomplete or ambiguously mapped issues never dispatch.
- **Verifier authority:** only fresh tester results govern verdicts; fixer self-reports and anti-hardcoding warnings are advisory. Only the final all-assertions PASS writes Fixed. Coverage says **Exercised**, not Verified, and shallow/partial coverage is disclosed without turning green red.
- **Drift and cleanup:** plan/config drift stops rather than repinning silently. Every started run ends through users teardown, recorded service teardown and lock release, including provisioning failures, budget stops and user aborts.

### Residual risks

- Mutation classification is syntactic and best-effort; GET-with-side-effects, GraphQL mutations without an explicit verb and FE UI actions may still write. Disposability matters even under a restrictive policy.
- **Verifier-gaming residual:** a capable fixer seeing deterministic scenarios can make them pass without a real fix. The engine's payload-literal warning is only a heuristic; default batch approval mitigates, not eliminates, this risk.
- Session-auth stacks needing a CSRF round trip depend on tester preconditions that preserve that flow.
- Signup rate limits, CAPTCHAs or mandatory email confirmation without a local mail catcher can block tester registration; the tester reports the missing prerequisite rather than bypassing it.
- Config `cmd:` sources, services and command recipes execute shell. Trust pinning prevents silent branch changes, but running an untrusted branch's app still runs untrusted code.
- Private secrets remain in `$TMPDIR` (0600) for the run; an interrupted session that cannot clean up leaves them until the next run's 24-hour cleanup.
- FE fill calls still put credentials in the session transcript.
- A URL path can contain a token, including magic links; redaction keeps paths visible unless the value matches an exposed name.
- Tester adherence to the `qa-results` block is prompt-level. Missing/invalid output becomes `cannot-confirm`, never PASS.
- Loop-engineering item 4 remains not met as disclosed above.
- 2xx-shaped gating, tenant-shaped 404s and FE gating remain undetected by auth-status classification. A dispatch outliving token lifetime can turn expiry into an `auth`-flagged FAIL.
- Drift checks run at engine calls; an already dispatched tester finishes against old config before the run stops.
- Locks coordinate identical configured target origins and store endpoint keys; an undeclared store, or one backend reached through different host aliases, is not coordinated.

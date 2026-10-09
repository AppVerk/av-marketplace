# QA plugin

`/qa:run` tests a change and reports observed failures with `QA-NNN` issue IDs. It can fix eligible issues and retest within fixed limits. Frontend tests use the browser; backend tests use APIs and configured stores.

**Version:** 3.0.0

## Quick start

1. Install QA and Code Review using the [installation guide](../installation.md).
2. Run `/qa:run` in the project checkout.
3. Review the proposed configuration and approve `Apply and trust`.
4. Fill any named private dotenv keys locally, then rerun.
5. Commit `.av/config.toml` and the 2 [private-file ignore entries](../configuration.md#files).

The first interactive run proposes settings from repository evidence. The proposal runs no commands and reads no secret values.

QA asks about disposable data, source fixes and service startup. It recommends `mutations = "allow"` only for confirmed disposable data behind loopback targets; otherwise it proposes `"deny"`.

Never paste private values into chat. Keep overrides and private inputs in the [uncommitted files](../configuration.md#files).

### Configuration

Start with target origins and the 3 [policy choices](qa/configuration.md#policy):

```toml
version = 1

[env.targets]
ui = "http://localhost:5173"
backend = "http://localhost:8000"

[qa]
fix = "approve"
mutations = "deny"
start_services = "ask"
```

Use [shared configuration](../configuration.md) for files, targets, services, sources, stores and trust.

### Pick an example close to your stack

| Example | Use |
|---|---|
| [JWT API](qa/configuration.md#jwt-api-register-and-login) | Register, log in and clean up with a helper. |
| [Django sessions](qa/configuration.md#django-session-stack-signup-login-and-cleanup) | Signup forms, CSRF, cookies and Django cleanup. |
| [Existing accounts](qa/configuration.md#existing-accounts-from-avsecretslocalenv) | Signup cannot create the required role or state. |
| [Read-only test/report](qa/configuration.md#read-only-testreport) | Anonymous reads on an already-running app. |
| [Supabase local](qa/configuration.md#supabase-local-stack) | Signup, Postgres State Checks and SQL cleanup. |

## Commands

### `/qa:run [plan-path | change-source]`

Run the complete workflow. The command accepts no flags; set policy in configuration.

```text
/qa:run
/qa:run docs/testing/plans/2026-09-30-user-auth-test-plan.md
/qa:run #123
/qa:run feature/user-auth
/qa:run last 5 commits
/qa:run staged
```

| Argument | Plan selection |
|---|---|
| Existing file | Use that plan explicitly; automatic staleness checks do not apply. |
| Change source | Generate and review a plan for that source. |
| No argument | Use the newest plan whose `## Source` names the current branch. Generate and review without asking when none matches or HEAD is detached. |

<details>
<summary>Stale plans and regeneration</summary>

Automatic selection considers a plan stale when `Head:` is missing, invalid or no longer an ancestor of HEAD. Committed changes outside `docs/` since that head also make the plan stale.

Interactive QA shows changed files and defaults to regeneration; headless QA regenerates. Failed generation never silently reuses an old plan. QA shows generated paths and frontend/backend scenario counts.

Open blockers require an interactive run-anyway decision; headless runs stop. Concerns remain visible but do not stop execution.

</details>

#### What a run does

The baseline is the first test pass, before fixes.

1. Validate configuration and trust.
2. Select or generate a reviewed plan; check targets, users, values, stores and writes.
3. Check tracked changes; reserve target origins and store endpoints.
4. Check services and start approved services when needed; prepare private tester inputs.
5. Test the baseline and report failures or setup gaps.
6. Fix eligible failures and retest affected sections; finish the fix path with a full pass.
7. Attempt cleanup, stop only services QA started and release run resources.

Changes remain unstaged and uncommitted. Fixer claims alone never prove success.

<details>
<summary>Fix iterations and recovery</summary>

Fix batches run sequentially, followed by independent testers. Iterations stop on no progress, regression, plan changes or [fixed limits](qa/configuration.md#working-tree-and-limits).

The full final pass runs only after entering the fix-iteration path. Zero-failure baselines, `fix = "off"`, headless `approve`, aborts and hard stops omit that pass. Exhausted fix limits do not block it.

Errors and aborts still tear down started runs. Stops retain partial observations without marking new fixes.

Recovery covers only eligible tracked paths edited by the loop. It never restores the whole tree or pre-existing dirty files. Reconcile reported overlap with pre-existing changes yourself.

</details>

<details>
<summary>Configuration bootstrap and repair</summary>

Later runs reuse settings without repeating policy questions, configuration entry or plan-generation approval. Changed trust, tracked changes, fix batches, setup gaps and stale plans can still require decisions.

| Mode | Trigger | Scope |
|---|---|---|
| `create` | Missing shared file or `[qa]` | Add QA and needed shared keys; preserve plan names. Ask the 3 policy questions. |
| `extend` | Missing plan-required keys | Add only gaps and dependencies; keep policy choices. Cleanup alone is optional. |
| `repair` | Failed service probe or command | Propose corrections supported by repository evidence and the error. |

Review the complete configuration diff, ignore additions and masked trust settings in 1 confirmation. Approval permits that write and trust hash. Concurrent edits cancel the write and require a new preview.

Bootstrap preserves unrelated settings and comments. It never edits personal overrides or fills the private secret file. Resolve any named blocking local override yourself.

Preview errors allow 1 corrected proposal before stopping. Each failure kind permits at most 1 repair per invocation. A successful active-run repair tears down the old run before restarting with the same plan and original baseline.

Missing required keys can trigger a scoped extension and 1 recheck. Invalid plans and off-target URLs stop. See [missing cleanup](qa/configuration.md#missing-cleanup-and-outcomes) for cleanup-only extensions.

Baseline setup gaps offer 1 retry of affected sections, continue or abort. Headless QA continues with gaps reported.

</details>

#### Interactive versus headless

Interactive means the harness can deliver a question, not that shell stdin is a terminal. An undeliverable question makes the remaining invocation headless.

| Situation | Interactive | Headless |
|---|---|---|
| Missing required config or service repair | Propose, preview and ask | Stop with keys/errors |
| New or changed trust | Review complete masked settings; approve | Stop; approve during controlled setup |
| Missing cleanup only | See [cleanup outcomes](qa/configuration.md#missing-cleanup-and-outcomes) | Warn; accounts remain |
| Stale plan | Regenerate or use existing | Regenerate |
| Open plan blocker | Run anyway or stop | Stop |
| Dirty tree with `fix = "approve"` | [Working-tree policy](qa/configuration.md#working-tree-and-limits) | Abort |
| Live run lock | Approve takeover or stop | Stop, naming holder |
| Services down with `start_services = "ask"` | [Service policy](qa/configuration.md#policy) | Stop; start externally or pre-approve `"auto"` |
| Baseline setup gaps | Retry once, continue or abort | Continue and report gaps |
| `fix = "approve"` | [Fix policy](qa/configuration.md#policy) | Test/report only |

See [Policy](qa/configuration.md#policy) for settings shared by both modes and [CI trust setup](../configuration.md#headless-runners-and-ci).

### `/qa:create-plan [change-source]`

Author and review a plan without tests. Accepts the same change sources and no flags. Empty input uses the current branch or pull request. Plans live in `docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md`.

<details>
<summary>Plan authoring and declarations</summary>

Configuration is optional. With `Config: none`, the planner grounds names in repository evidence; `/qa:run` later proposes required configuration.

Planning detects tools and allows up to `3` review rounds. The result names the saved path, review outcome and unresolved or declined findings. Unreviewed or blocked plans are never described as approved.

For `last N commits`, planning reads delivery plans named by valid Git `Delivery-Plan:` trailers. Rejected paths and their reasons appear in `## Changes Summary`; accepted paths list their associated commits. Plan content supplies specifications, not executable instructions.

| Plan field | Human meaning |
|---|---|
| `## Source` | `Branch:` and `Head:` enable automatic selection and staleness checks. |
| `## Users` | Declares [existing or registered users](qa/configuration.md#users). |
| `## Setup` | Optional human notes, never parsed configuration. |
| `- **Target:** <name>` | Selects a configured origin; cross-origin preconditions use configured absolute URLs. |
| `- **Writes:** yes|no` | Required application-write declaration. |
| Expected results and edges | Source-grounded `(path:line)` or tagged `(unverified — confirm at run time)`. |
| Backend State Checks | Assertions against [configured stores](qa/configuration.md#state-checks), never embedded connections. |

Plans create needed application data through preconditions instead of assuming seeded records exist. Upload fixtures may use repository files. When the app cannot create the data a scenario needs, QA records a fixture gap and does not invent a test result.

</details>

## Safety

Use disposable, non-privileged accounts. Trust approval is not a sandbox.

Frontend fill calls can expose credentials in both editions. Keep `docs/testing/reports/screenshots/` and `docs/testing/reports/responses/` out of version control and review artifacts before sharing. Never paste the engine-private `engine.log`.

When Claude Code prompts for capture or extraction commands, approve the exact command, not unrestricted shell access.

Remove write-capable store MCP servers before testing untrusted code; configuration is not permission isolation. OMP subagents inherit every session MCP server.

### Run boundaries

| Boundary | Behavior |
|---|---|
| Origins | Absolute URLs must match configured origins. Userinfo is refused; redirects are not followed automatically. Off-target plans stop. See [target rules](../configuration.md#targets). |
| Credentials | Require HTTPS or exact [loopback](../configuration.md#targets). |
| Stores | [Network stores](../configuration.md#stores) are loopback-only. |
| Configuration | Detected changes stop a started run; review settings and rerun. |
| Cleanup | Review [recipe and account outcomes](qa/configuration.md#missing-cleanup-and-outcomes). |
| Mutations | Follow [Policy](qa/configuration.md#policy); approval cannot bypass `deny`. |

Never weaken authentication or authorization to make tests pass.

<details>
<summary>Fix eligibility and authentication</summary>

A backend feature expecting `2xx` but receiving `401/403` is `FAIL`, flagged `auth`. Automatic fixes exclude these issues; approval can permit reviewed root-cause fixes.

Rejected, location-less, incomplete or ambiguously mapped issues cannot dispatch fixes. Automatic fixes also exclude unverified assertions without excluding grounded sibling issues. Anti-hardcoding warnings are heuristic and do not prove a fix valid.

</details>

<details>
<summary>Transcript and artifact exposure</summary>

| Data | Exposure |
|---|---|
| Names, origins, account emails/IDs, sanitized results and cleanup outcomes | Visible in results or summaries. |
| Passwords, tokens and cookies | Not printed by the engine; administrative secrets never enter tester inputs. |
| Backend responses and State Checks | Sanitized before inspection or persistence; failed sanitization withholds evidence. |
| Sensitive headers, JSON fields and URL query/fragment parameters; bearer tokens; declared values | Masked in backend evidence; non-JSON and bare-string bodies are withheld. Parameters with ordinary names can stay visible. |
| Snapshots and screenshots | Can expose user data; debug or uninspectable pages suppress screenshot/debug-text capture. |

Visible URL paths may still contain secrets. One-time-link fields are fully masked, but ordinary URL fields can retain paths.

Unknown, unresolved or short secrets may remain in `engine.log` failure output. Testers never replay a write just to obtain evidence.

</details>

### Residual risks

- Static mutation detection can miss GET side effects, GraphQL mutations and implicit frontend writes.
- Trust cannot make configuration commands or target application code safe to execute.
- Fixers can game deterministic scenarios.
- Private credentials in `${TMPDIR:-/tmp}/qa-run-<run-id>/` may survive interruptions until takeover or a later run in this repository removes directories older than `24 hours`.
- Auth classification misses frontend gating, tenant-shaped `404` responses and gating that returns `2xx`.
- An already-dispatched tester may finish on old settings despite engine-call configuration checks.
- Locks coordinate identical configured endpoints, not undeclared stores or different host aliases.

Cross-section regressions may appear only in the final pass. Tokens can expire mid-test. Missing or invalid tester output becomes `cannot-confirm`, never PASS.

See [registered accounts](qa/configuration.md#registered-accounts) when signup cannot create the needed user.

## Coverage

Read Coverage alongside the result. A green result can mean no observed failures with features still unverified.

```markdown
## Coverage
- Exercised: <N> feature · <M> sanity · <K> enforcement
- Not verified: need-info <N> · mutation-guard SKIP <M> · tool-unavailable <K> · cannot-confirm <J> · transport <L>
- Confidence: high | low — <reason>
```

| Result | Read it as |
|---|---|
| `Pass` | No remaining failures; inspect Coverage before treating the change as verified. |
| `Fail` | Read the remaining failed assertions. |
| `Budget Exhausted` | Read the named fixed limit and remaining issues before another run. |
| `Stopped` | Resolve the stop reason; this is not success. |

<details>
<summary>Scenario verdicts and limited coverage</summary>

Scenario verdicts combine the main flow and every edge: failure, missing prerequisite, skip, then pass. A skipped State Check alone does not downgrade runnable HTTP results. A whole-scenario PASS is still not proof of complete application behavior.

When feature scenarios exist but none passes, QA warns about shallow coverage. Auto-generated zero-failure plans can report low-confidence green. Existing all-SKIP/NEED_INFO plans stop with `No executable verifier — cannot gate`.

A newly generated plan without executable scenarios exits without testers; an existing empty plan is an error. Generated plans can exit gracefully with no exercised scenarios.

QA distinguishes mutation-guard-only skips from setup, tooling and parsing gaps. Unlock hints name missing configuration, data, tools or reachability problems without printing secret values.

</details>

## Reports and Code Review

Reports live in `docs/testing/reports/YYYY-MM-DD-<topic>-report.md`. They include counts, accounts, setup gaps, results and Loop History. Setup gaps are not application defects; failed assertions receive `QA-NNN` IDs.

Review reported emails and [cleanup outcomes](qa/configuration.md#missing-cleanup-and-outcomes).

<details>
<summary>Issue severity rules</summary>

Issue blocks show severity, ID, location, problem, remediation and scenario evidence. HTTP `500+` or crashes force CRITICAL; unverified assertions otherwise stay LOW. Other severities follow evidence; CRITICAL security-bypass/data-loss claims require supporting reasons.

</details>

Only the final whole-scenario PASS writes `**Status:** ✅ Fixed`. Partial fixes remain open. QA preserves `🚫 Rejected` and existing decision metadata; do not edit run state to manufacture results.

| Code Review command | Action |
|---|---|
| `/fix QA-001` | Read the newest QA report and fix that issue. |
| `/fix-report` | Merge newest review and QA reports; update their original files. |
| `/fix-report docs/testing/reports/<file>.md` | Select 1 report explicitly. |

See [Code Review](code-review.md) for routing and decisions. [Delivery](delivery.md#qa) `0.6.0+` runs QA before final review and commits QA's fixes, configuration, plan and report.

## Troubleshooting

| Symptom | What to do |
|---|---|
| `missing.users` | Configure the declared existing user's sources/description or missing ID. Registered users need no existing-account config. |
| Missing values, targets or stores | Add the named shared keys; fill named dotenv keys privately. Multiple targets need explicit section origins. |
| `plan_errors` | Correct declarations, reserved references, ambiguous/frontend State Checks or cleartext credential origins. Bootstrap cannot invent a valid plan. |
| Off-target URL | Correct the URL or explicitly configure/trust its origin, including scheme and port. |
| Registration/login blocked | Inspect safe tester evidence and preconditions. Consider existing accounts; QA has no engine login-repair path. |
| `missing.cleanup` or accounts `left`/`manual` | Follow [cleanup outcomes](qa/configuration.md#missing-cleanup-and-outcomes) and review reported emails. |
| Local override blocks bootstrap | Resolve the named `.av/local.toml` key yourself, then rerun. |
| New/changed trust | Review all masked settings, including existing commands. Headless cannot approve. |
| Stale plan or generation failed | Review [regeneration rules](#qarun-plan-path--change-source); explicitly select an old plan only after inspection. |
| Live run lock | Stop the active run or approve takeover of an interrupted session. Never delete locks or the ledger blindly. |
| Services down or repair stopped | Check probes, ports and checkout. Start externally, approve configured startup (or pre-approve `start_services = "auto"`) or rerun interactively for repair; see [bootstrap repair limits](#qarun-plan-path--change-source). |
| `cannot-confirm` | Retry with usable tools and complete scenario/edge results. Earlier PASS results cannot fill missing evidence. |
| `config changed during run` | Rerun `/qa:run` after reviewing settings. Cleanup may leave accounts; service shutdown uses the recorded command. |
| FAIL flagged `auth` | Check login, authorization, token lifetime and role. Never weaken auth to pass. |
| No fixes in headless `approve` or `off` | Expected test/report-only behavior. Choose and trust `auto` only when eligible source edits are intended. |
| Budget exhausted/no progress | Read Loop History and the stop reason; investigate before starting another run. |
| Generated plan has no tests or green result has low confidence | Read [Coverage](#coverage), including the generated/existing-plan rules. |
| Recovery overlaps pre-existing changes | Reconcile reported overlap yourself; QA never restores the whole tree. |

## Prerequisites

<details>
<summary>Required tools and environment</summary>

| Need | Requirement |
|---|---|
| Engine | Python `3.11+` as `python3`; no engine packages to install. |
| Repository | Git repository with a HEAD. |
| Backend requests | `curl` for credentials; HTTPie only for credential-free requests. `jq`, standard shell tools and Perl with `JSON::PP` for capture/sanitization. |
| Frontend browser | Playwright MCP in Claude Code; built-in browser in OMP. |
| Application | Running services or evidenced health/startup commands. |
| State Checks | Configured store and matching `psql`, `mysql`, `sqlite3` or `redis-cli`. Redis checks need `redis-cli` with `--json`; configured password authentication also needs `4.0.11+`. |
| Fixes | Code Review; test/report-only runs need no fixer. |

Check Perl with `perl -MJSON::PP -e 1`. Sources and recipes may need extra installed commands. Missing tools produce gaps, never fabricated PASS results; missing store clients skip only their checks.

Testers never install tools or modify project files to repair setup. Supply tools outside the run and retry.

</details>

## Oh My Pi

Install with `omp plugin install qa@av-marketplace code-review@av-marketplace`; update an existing marketplace registration first. QA commands keep their names. Code Review uses `/code-review:fix QA-001` and `/code-review:fix-report`.

Before running QA, enable `browser.enabled`, disable `browser.relay` and `browser.cmux`, and unset `browser.cdpUrl` to avoid an attached personal browser.

<details>
<summary>Browser and model settings</summary>

| Setting | QA choice |
|---|---|
| `browser.enabled` | Enable. |
| `browser.relay`, `browser.cmux` | Disable. |
| `browser.cdpUrl` | Unset, avoiding an attached personal browser. |
| `task.agentAdvisor` | Optional `{"qa:test-planner": "off"}` in `~/.omp/agent/config.yml` to disable the planner's Advisor. |

QA uses managed Chromium through OMP's built-in browser, not Playwright MCP. Disabled browser support produces tool gaps. Backend clients and sanitization match Claude Code.

Testers use the `tester` model role; planning/configuration use `plan`; review uses `advisor`. The main command uses the session model. See [Model roles](../oh-my-pi.md#model-roles) and [Advisor](../oh-my-pi.md#advisor).

</details>

<details>
<summary>Installed scripts and inherited tools</summary>

Resolve installed paths with `realpath skill://qa:engine/scripts/qa.py` and `realpath skill://qa:be-testing/scripts/qa-redact.pl`. Never guess cache paths or substitute the project's own script.

Testers separate writes from observation and never replay a mutating cell.

</details>

<a id="upgrade-notes"></a>
## Upgrade Notes

See the [QA changelog](qa/changelog.md) for release changes and compatibility notes.

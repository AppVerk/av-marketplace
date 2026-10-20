# Test Plan: Delivery extension loads in the compiled omp binary

## Source
- Type: last 3 commits (`git diff HEAD~3...HEAD`, ec62ccd..129ffe9)
- Base: master
- Date: 2026-10-20
- Branch: delivery/delivery-binary-import
- Head: 129ffe996b956d2d665acd6d2e881a21731627ac

## Changes Summary

All three commits carry `Delivery-Plan: docs/plans/2026-10-20-delivery-binary-import.md`. The path is repository-relative, has no `..` segment and no symlinked component, and resolves to a regular file inside the repository (git-ignored, not tracked). It was accepted and read as the specification for every commit below. No trailer was rejected.

| Commit | Subject | Delivery-Task-Title | Files |
|---|---|---|---|
| b2db951 | test(omp-edition): check that extensions load in the compiled omp binary | Check that extensions load in the compiled omp binary | `scripts/check_omp_extensions.py`, `scripts/test_check_omp_extensions.py` |
| 3baf87f | fix(delivery): load the extension in the compiled omp binary | Load the delivery extension in the compiled omp binary | `omp/native/delivery/extensions/delivery.ts`, the six delivery version sources, the regenerated `plugins-omp/delivery/` files and `.omp-plugin/marketplace.json` |
| 129ffe9 | ci(omp-edition): run the extension load check against the latest omp binary | Run the extension load check in CI and document the rule | `.github/workflows/omp-edition.yml`, `CLAUDE.md`, `docs/contributing.md` |

The defect being fixed: delivery 0.8.0 did not load in the compiled `omp` binary and failed with `Cannot find package '@oh-my-pi/pi-coding-agent'`. It imported OMP's approval prompt `.md` `with { type: "text" }`, and the binary serves extensions only the code modules of `@oh-my-pi/*`. With the extension unloaded, approving a plan never started a delivery, and `write xd://propose` skipped the `### Task` check. `bun test` still passed, because it resolves imports through `node_modules` (docs/plans/2026-10-20-delivery-binary-import.md:5-7).

What changed:

- **Delivery extension** (`omp/native/delivery/extensions/delivery.ts`): the prompt import is gone. The approval prompt's first line `Plan approved.` and its plan tag `<plan path="` … `">` are now inlined (omp/native/delivery/extensions/delivery.ts:19-25), and `approvedPlanPath` uses them (omp/native/delivery/extensions/delivery.ts:96-103). The literals match OMP 18.12.3's template, whose line 1 is `Plan approved.` and line 17 is `<plan path="{{planFilePath}}">` (omp/native/delivery/node_modules/@oh-my-pi/pi-coding-agent/src/prompts/system/plan-mode-approved.md:1, 17). The function therefore returns what 0.8.0 returned. The other `@oh-my-pi/*` imports stay (omp/native/delivery/extensions/delivery.ts:12-15); the plan records them as modules the binary serves (docs/plans/2026-10-20-delivery-binary-import.md:7). The generated `plugins-omp/delivery/extensions/delivery.ts` has the same blob as its source (`7504305`).
- **Release 0.8.1**: plugins/delivery/.claude-plugin/plugin.json:4, .claude-plugin/marketplace.json:75, omp/native/delivery/.omp-plugin/plugin.json:3, omp/native/delivery/package.json:3, README.md:59 and docs/plugins/delivery.md:5. The generated plugins-omp/delivery/.omp-plugin/plugin.json:3, plugins-omp/delivery/package.json:3 and .omp-plugin/marketplace.json:29 follow. The Claude Code edition changes only its version.
- **Extension load check** (`scripts/check_omp_extensions.py`, new): `python3 scripts/check_omp_extensions.py <omp binary> [<edition dir>]` collects every `omp.extensions` entry of `<edition>/*/package.json`, in sorted manifest order (scripts/check_omp_extensions.py:22-28). The default edition is `plugins-omp/` (scripts/check_omp_extensions.py:75). Each extension is loaded with `<binary> --mode rpc --no-session --trusted-extension <absolute path>` in a fresh temporary directory, used as both cwd and `HOME`. The environment holds only `HOME` and `PATH`, stdin is closed and the timeout is 60 s (scripts/check_omp_extensions.py:19, 31-46). `scripts/test_check_omp_extensions.py` has 9 test methods that drive a fake `omp` script (scripts/test_check_omp_extensions.py:25, 91-196).
- **CI** (`.github/workflows/omp-edition.yml`): the `OMP Edition` job runs the checker's tests (.github/workflows/omp-edition.yml:39-40), downloads the latest `omp-linux-x64` release and runs the check against it (.github/workflows/omp-edition.yml:74-81). The job keeps `timeout-minutes: 5` (.github/workflows/omp-edition.yml:20).
- **Documentation**: CLAUDE.md states which `@oh-my-pi/*` imports an extension may use and names the check (CLAUDE.md:131-136). docs/contributing.md adds a pull-request item for the load check (docs/contributing.md:260).

No changed file is FE, BE or DESKTOP. `delivery.ts` is an OMP extension that runs inside the `omp` terminal agent; what it adds shows up as notifications, messages and tool-call results in an omp terminal or RPC session. `check_omp_extensions.py` and its tests are repository CI tooling. The rest is CI configuration, documentation, release metadata and generated mirrors. The repository has no web application: its only `package.json` files, under `plugins-omp/` and `omp/native/`, belong to OMP plugins. It has no Ebitengine app either, since there is no root `go.mod`, and the installed `ebitengine` desktop driver requires one. The QA config defines no targets, desktop apps, users, values or stores. The plan therefore has no executable FE, BE or DESKTOP scenarios, and every contract check is listed under Out of harness scope.

## Blockers / Findings

None found.

## Users

None. No scenario acts as a user, a role or an anonymous visitor.

## Detected Tools
- Playwright MCP: available
- HTTP client: curl, httpie
- Store clients: psql, sqlite3 (mysql and redis-cli unavailable)
- Desktop drivers: ebitengine
- Other: jq, perl JSON::PP

## Out of harness scope

Every check here runs the `omp` terminal agent, a local Python CLI or the GitHub Actions workflow. None of them has a browser page, an HTTP endpoint, a configured store or an Ebitengine app that the FE, BE or DESKTOP testers could drive, query or capture. "Verification N" is item N of the plan's Verification section (docs/plans/2026-10-20-delivery-binary-import.md:139-147).

**Delivery 0.8.1 in the compiled `omp` binary.**

- **Load.** `<binary> --mode rpc --no-session --trusted-extension <absolute path of plugins-omp/delivery/extensions/delivery.ts>`, with stdin closed and a fresh `HOME`, prints `{"type":"ready",…}` and exits 0. The 0.8.0 file exits 1 with `error: Trusted extension failed to load: Failed to load extension: Cannot find package '@oh-my-pi/pi-coding-agent' imported from …` (docs/plans/2026-10-20-delivery-binary-import.md:14). Verification 6 and 7 run this through the load check below — runs in the compiled omp terminal binary.
- **Approval starts a delivery.** When the router counts at least one task in an approved plan, the `Plan approved.` prompt makes the extension notify `Delivery: <N> task(s) — starting the delivery run.` and add a `delivery-run` message that hands the plan to `skill://delivery:orchestration` (omp/native/delivery/extensions/delivery.ts:111-152). Over RPC to the compiled binary, this notification appeared with `1 task(s)` (docs/plans/2026-10-20-delivery-binary-import.md:16). `bun test` covers it against the npm package (omp/native/delivery/tests/delivery.test.ts:116) — omp session event in a terminal or RPC session.
- **Approval that cannot start a delivery.** Each case warns, and the plan runs without delivery (omp/native/delivery/extensions/delivery.ts:113-135):
  - outside a git repository: `Delivery skipped: not a git repository. The plan runs without delivery.`
  - a missing plan file: `Delivery skipped: plan file not found for <url>. The plan runs without delivery.`
  - a failed plan check: `Delivery skipped: plan check failed for <url>: <error>. The plan runs without delivery.`
  - no valid task, with problems from the router: `Delivery skipped: <url> has no valid task heading. <problems> The plan runs without delivery.`

  A plan with no valid task and no problems starts nothing and prints nothing. `bun test` covers the task-free plan, the missing file, the failed plan check and the malformed heading (omp/native/delivery/tests/delivery.test.ts:127, 135, 143, 164). No automated run covers these cases in the compiled binary — omp session event in a terminal or RPC session.
- **Approval prompt parsing.** `approvedPlanPath` returns the text between `<plan path="` and `">` on the first tag's line. It returns nothing when the prompt does not start with `Plan approved.`, contains no `<plan path="`, or the tag's line does not end with `">` (omp/native/delivery/extensions/delivery.ts:96-103). The tests build their prompts from OMP's own template (omp/native/delivery/tests/delivery.test.ts:7, 119). `bun test tests/delivery.test.ts` in `omp/native/delivery/` is expected to report `9 pass` and `0 fail` (Verification 4). The literals no longer follow the template on their own: an OMP release whose template stops starting with `Plan approved.` or changes the plan tag would stop 0.8.1 from recognising approvals, and these tests are what catch it (omp/native/delivery/extensions/delivery.ts:19-22) — in-process function, checked by a bun unit test.
- **`write xd://propose` check.** A plan whose `### Task` blocks the router cannot route is blocked. The reason is `Delivery plan check failed for <url>:`, one `- <problem>` line per violation, then `Fix these tasks in the plan file, then write the slug to xd://propose again.` (omp/native/delivery/extensions/delivery.ts:176-185). A missing plan file or a failed plan check warns and lets the proposal through (omp/native/delivery/extensions/delivery.ts:163-175). `bun test` covers these cases (omp/native/delivery/tests/delivery.test.ts:76, 87, 156). No automated run covers them in the compiled binary — omp tool hook in a terminal or RPC session.
- **Plan mode.** In plan mode inside a git repository, the extension appends the `# Delivery plans` task format to the system prompt (omp/native/delivery/extensions/delivery.ts:107-110). No automated run covers this in the compiled binary — the omp system prompt is visible to no harness.

**Extension load check (`scripts/check_omp_extensions.py`).**

- **Current edition loads.** `python3 scripts/check_omp_extensions.py /tmp/omp-verify/omp-darwin-arm64` exits 0 and prints `3 OMP extensions load in …/omp-verify/omp-darwin-arm64` (scripts/check_omp_extensions.py:95; Verification 5-6). The three are `commit/extensions/claude-hooks.ts`, `delivery/extensions/delivery.ts` and `plan-review/extensions/plan-review.ts` (plugins-omp/commit/package.json:7-9; plugins-omp/delivery/package.json:7; plugins-omp/plan-review/package.json:7) — local Python CLI around the compiled binary.
- **The 0.8.0 defect is caught.** With `master`'s `plugins-omp/delivery/package.json` and `extensions/delivery.ts` copied into `/tmp/omp-verify/old/delivery/`, the check exits 1. Stderr has a line for `…/old/delivery/extensions/delivery.ts` that contains `Cannot find package '@oh-my-pi/pi-coding-agent'`, then `1 of 1 OMP extensions fail to load in …` (scripts/check_omp_extensions.py:89, 92; Verification 7) — local Python CLI around the compiled binary.
- **Load flag.** The check relies on `--trusted-extension`, which `omp --help` (v18.12.3) does not list. If an omp release drops it, omp rejects the argument and the check fails instead of passing (docs/plans/2026-10-20-delivery-binary-import.md:34). The plan's fallback runs `-e` with `--no-extensions` and fails on a non-zero exit or `Failed to load extension` in stderr (docs/plans/2026-10-20-delivery-binary-import.md:151) — local Python CLI around the compiled binary.
- **Failure reason.** A non-zero exit is reported with the first stripped stderr line that starts with `error:`. Without one, the check uses the last non-empty stderr line; without stderr, `exit code <n>` (scripts/check_omp_extensions.py:51-57). A run that outlasts the timeout gives `omp did not exit within <timeout> s` (scripts/check_omp_extensions.py:45-46) — local Python CLI.
- **Configuration errors exit 2.** A wrong argument count prints `usage: check_omp_extensions.py <omp binary> [<edition dir>]` (scripts/check_omp_extensions.py:62-64). A missing or non-executable binary prints `<argv[0]> is not an executable file; download the compiled omp binary for your platform: gh release download -R can1357/oh-my-pi -p omp-<os>-<arch>, then chmod +x it` (scripts/check_omp_extensions.py:68-73). An edition without a declared extension prints `no extension declared in <edition>/*/package.json` (scripts/check_omp_extensions.py:78-80) — local Python CLI.
- **Unit tests.** `python3 scripts/test_check_omp_extensions.py` is expected to end with `OK` (Verification 1). Its 9 tests cover the count line, the manifest and declaration order, a broken extension, the timeout, a missing or non-executable binary, an edition without extensions, the usage error and the order of failure reasons (scripts/test_check_omp_extensions.py:91-196) — repository test script.

**Release, generated edition and other suites.**

- **Versions and edition.** `python3 scripts/check_plugin_versions.py` is expected to exit 0 and list `[delivery] 0.8.1 (OK)` and `[delivery] 0.8.1 (OK, native OMP edition)` (scripts/check_plugin_versions.py:528, 551). `python3 scripts/build_omp_edition.py --check` is expected to print `OMP edition is up to date` (scripts/build_omp_edition.py:770; Verification 2) — repository CI scripts.
- **Other suites.** `python3 scripts/test_build_omp_edition.py`, `python3 scripts/test_check_omp_tools.py`, `python3 omp/native/delivery/tests/test_route_task.py` and `python3 plugins/delivery/tests/test_delivery_hook.py` are expected to end with `OK` (Verification 3) — repository test scripts.

**CI and documentation.**

- **Workflow.** `actionlint .github/workflows/omp-edition.yml` is expected to print nothing and exit 0 (Verification 8). The workflow runs on pull requests to `master` and pushes to `master` (.github/workflows/omp-edition.yml:3-7). On a pull request from `delivery/delivery-binary-import`, the `OMP Edition` run is expected to pass, and its step `Check OMP extensions load in the compiled binary` to print `3 OMP extensions load in …` (.github/workflows/omp-edition.yml:80-81; Verification 9). If that step fails with a dynamic-linker or glibc error, the plan's fallback is `omp-linux-musl-x64` (docs/plans/2026-10-20-delivery-binary-import.md:152) — GitHub Actions run, visible only on the pull request.
- **Documentation.** The CLAUDE.md paragraph (CLAUDE.md:131-136) and the contributing item (docs/contributing.md:260) describe the import rule and the load check as implemented above — prose, with no executable behaviour.

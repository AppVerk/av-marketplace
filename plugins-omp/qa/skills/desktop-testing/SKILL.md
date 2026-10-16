---
name: "qa:desktop-testing"
description: "Desktop testing patterns for DESKTOP scenarios — writing engine desktop scripts from plan steps, running them through desktop.sh, reading frame shots and the app log, and mapping driver results to verdicts."
allowed-tools: Read, Write, Grep, Bash(sh:*), Bash(mkdir:*), Bash(cp:*)
---

# Desktop Testing Patterns

## Execution Workflow

For each DESKTOP scenario from the test plan:

1. **Read the scenario** — understand Args, preconditions, steps, Expected and edge cases.
2. **Write the script** — translate the main flow into the JSON vocabulary below.
3. **Execute main flow** — run `sh '<run-dir>/desktop.sh' <dispatch> <app> <script-file>`.
4. **Verify result** — map the driver result, Read every shot the expectation names and Grep the masked app log for expected lines.
5. **Execute edge cases** — write and run each edge as its own complete script, starting a fresh app.
6. **Record result** — PASS/FAIL/SKIP/NEED_INFO with details and the required refutation before any FAIL.

The `/qa:run` tester dispatch supplies `Plan:`, `Dispatch:`, `Run dir:`, `Secrets JSON:`, `Redact names file:`, `Tag:`, `Apps:` (configured apps and the default for DESKTOP) and `Guarded:`, followed by `DESKTOP Test Scenarios:` in plan order. Do not parse the plan's optional `## Setup` notes. A scenario in `Guarded:` is `SKIP — mutation-guard`; execute none of its preconditions, main flow or edges. Use the scenario's `**Target:**` app or the supplied default.

Write the main-flow script to `<run-dir>/results/<dispatch>/scripts/<ID>.json` and edge n to `<run-dir>/results/<dispatch>/scripts/<ID>-edge<n>.json`. Create this scripts directory if needed. Each helper invocation builds and starts a fresh app; include the input needed to reach preconditions in every script rather than depending on a previous scenario's process.

## Tester scope

Never build, install or run the app except through `desktop.sh`. Never install, download or configure tools, drivers or packages, modify project files, or use OS input or screen capture (`osascript`, `screencapture`, `cliclick`). Write tester-authored files only under `<run-dir>/results/<dispatch>/scripts/` and `docs/testing/reports/screenshots/`; the engine owns all other artifacts. A plan step outside the vocabulary below is `SKIP — out of harness scope: <step>`, not permission to write a custom driver or use a project helper.

---

## Tag handling (plan grounding tags)

Handle `**Expected:**` and each edge-case expectation separately. Ignore `(path:line)` source citations when matching. `(unverified — confirm at run time)` still requires a `FAIL` on mismatch; carry the tag in the result so an issue minted from it is `LOW` unless a crash was observed. `(exact text — brittle)` means quoted text is matched as a substring, not as equality.

---

## Desktop Driver Patterns

### How a run works

The engine runs every script through the app's registered desktop driver: the driver builds the app, starts a fresh instance without a window, steps it by ticks and injects input inside the app. There is no focus change, no OS input and no screen capture; keyboard focus stays with the user, and shots are PNG frames rendered by the app, not captures of the user's screen. Read the app's driver guide (the `guide` in `Apps:`) before writing scripts: it states the app's tick rate, how its own drawing coordinates map to window coordinates and the driver's limits.

### Script format

Script format (the tester writes it; the engine validates it; the driver executes it). Top level: `{"args": [<string>…], "steps": [<step>…]}`; `args` is optional. Each step is an object with exactly one action key:

|Step|Driver behaviour|
|---|---|
|`{"wait": N}`|advance N ticks, N 1–36000|
|`{"key": "<Key>", "ticks": T}`|press, advance T ticks (T default 2, range 1–600), release, advance 1 tick|
|`{"hold": "<Key>"}` / `{"release": "<Key>"}`|press / release; takes effect at the next advanced tick|
|`{"type": "<text>"}`|per character: type it, advance 1 tick; 1–200 characters|
|`{"type_env": "QA_<NAME>"}`|the engine replaces it with `{"type": <value>}` in the driver's private copy only: `QA_TAG` takes the dispatch's tag (an engine token that `secrets.json` never holds); any other name takes its value from `<run-dir>/secrets.json`. Every shot after a `type_env` other than `QA_TAG` is marked `sensitive`|
|`{"move": [x, y]}`|move the cursor|
|`{"click": [x, y], "button": "left"\|"right"\|"middle"}`|move, press, advance 1 tick, release, advance 1 tick; `button` defaults to `left`|
|`{"scroll": [dx, dy]}`|wheel, advance 1 tick; dx, dy within −100…100|
|`{"shot": "<name>"}`|render the current frame and save `<name>.png`; name `[A-Za-z0-9_-]{1,40}`, unique, at most 50 shots. Some earlier step must advance ticks (`wait`, `key`, `type`, `type_env`, `click` or `scroll`), so a leading shot, or one preceded only by `hold`, `release` or `move`, is an invalid script|

### Plan wording → step mapping

| Plan wording | Script step |
|---|---|
| `Wait N ticks` | `{"wait": N}` |
| `Press <Key> [for N ticks]` (key in backticks) | `{"key": "<Key>"}` or `{"key": "<Key>", "ticks": N}` |
| `Hold <Key>` / `Release <Key>` (key in backticks) | `{"hold": "<Key>"}` / `{"release": "<Key>"}` |
| `Type <text>` (text in backticks) | `{"type": "<text>"}` |
| `Type $QA_NAME` | `{"type_env": "QA_NAME"}` |
| `Move to x,y` | `{"move": [x, y]}` |
| `Click x,y [right\|middle]` | `{"click": [x, y]}` with the optional `button` |
| `Scroll dx,dy` | `{"scroll": [dx, dy]}` |
| `Shot <name>` (name in backticks) | `{"shot": "<name>"}` |
| `**Args:**` | Top-level `args` array, one string per argument; no shell execution |

A plan line combining actions becomes separate steps in the stated order. The configured app's args precede these per-scenario args. Keep quoted argument values together; never put shell expansions or commands in args.

### Key names and coordinates

`<Key>` is a W3C UI Events `KeyboardEvent.code` value: `KeyA`…`KeyZ`, `Digit0`…`Digit9`, `ArrowUp`/`ArrowDown`/`ArrowLeft`/`ArrowRight`, `Enter`, `Escape`, `Space`, `Tab`, `Backspace`, `Delete`, `Backquote`, `Minus`, `Equal`, `F1`…`F12`, `ShiftLeft`, `ControlLeft`, `AltLeft`, `MetaLeft`. Drivers may accept more codes; the driver validates them and returns `invalid-script` naming the step.

Script coordinates are window pixels (device-independent) of the app's configured `screen` W×H, with 0 ≤ x ≤ W and 0 ≤ y ≤ H. A PNG pixel maps to (px/scale, py/scale). Limits: at most 500 steps, at most 36000 ticks in total (summing every step's advanced ticks), `args` at most 32 strings of at most 256 characters without NUL.

Plans state the app's own drawing coordinates and cite its logical size in Preconditions; convert them to window pixels with the driver guide before writing `move` or `click`. Do not use PNG pixels directly: divide them by the returned `scale` first. Do not invent pixel colours or coordinates that the source does not pin.

### Tokens

Configured existing users' referenced fields, configured values, `$QA_NEW_PASSWORD` and `$QA_TAG` are typed with `type_env`, never resolved into literal script text by the tester. `plan check` refuses registered users in DESKTOP scenarios; a tester never registers accounts and always returns `accounts: []`.

Every `$QA_…` token becomes a separate `type_env` step, including `$QA_TAG`. Literal text around a token is split into separate `type` steps:

```json
{"steps": [{"type": "qa+"}, {"type_env": "QA_TAG"}, {"type": "-owner@test.local"}]}
```

The engine resolves `QA_TAG` from the dispatch, and other names from the private secrets.json channel. Never print a secret value, inspect inherited environment variables or project secret files, or put a resolved value in script args, descriptions or artifacts. An unexposed or empty `type_env` name gives exit 2 with `{"error": "script: type_env QA_X is not exposed"}`: correct the script to the plan's exposed names, never fetch another source.

### Timing

`tps` is the ticks per second the app requests (the driver guide gives the usual value; -1 means ticks follow rendered frames). Wait a few ticks after input before a shot so the app can update its displayed state. `hold`, `release` and `move` take effect only when ticks advance; `key` releases the key and advances one more tick after the requested duration. Ticks are exact, but code reading a wall clock sees real elapsed time between ticks.

### Output fields and exit codes

`desktop run` stdout (one JSON object): `result` (`completed`, `guest-exited`, `build-failed`, `host-build-failed`, `handshake-failed`, `host-failed`, `invalid-script`, `timeout`, `tool-missing`, `unsupported`), `detail` (one sanitized line or null), `step` (0-based index of the step where the run stopped, or null when it stopped before the first step or after the last), `exit_code` (guest exit code or null), `ticks`, `tps`, `scale`, `screen` ([w, h]), `shots` ([{`name`, `path` absolute, `tick`, `sensitive` boolean}]), `log` (absolute path of the masked guest log, or null), `build_log` (absolute path or null), `artifacts` (absolute directory, or null when the app's driver is not registered), `attempts` (host runs, 0 to 2: 0 when the run phase never ran, 2 after a `handshake-failed` retry), `duration_ms`. Exit 0 for every `result`; exit 2 with `{"error": "script: …"}` for a structurally invalid script; exit 1 with `{"error": …}` for an unknown run, dispatch or app, a non-DESKTOP dispatch, missing trust, config drift or an interruption (`desktop run interrupted`).

### Result mapping

Use this table in order; crash evidence takes priority over an expected quit. A successful CLI exit alone is never PASS.

| Driver result / exit | Verdict |
|---|---|
| `completed` | Judge the named shots and expected app-log lines; PASS only when the expectations are met. |
| `invalid-script` or exit 2 | Fix the script and re-run; never a verdict. |
| `build-failed` | FAIL, `crash: false`; Details is the first error line of `build_log`, sanitized before quoting. |
| `guest-exited` with non-zero `exit_code` or `panic`/`fatal` in `guest.log`, including an exit before connecting | FAIL, `crash: true`; the app failed, including a startup failure. |
| `guest-exited` with `exit_code` 0 and detail `guest terminated itself` | Satisfies an expectation that the app quits; otherwise FAIL, `crash: false`. |
| Any other `guest-exited` with exit 0 | FAIL, `crash: false`. |
| `timeout` (wall-clock or idle) | Re-run once, then FAIL, `crash: false`; use that same run for the FAIL refutation, not a second retry. |
| `tool-missing` | NEED_INFO, `kind: tool`, `Missing: <detail>` (for example `go` or `desktop-driver:<driver>`). |
| `unsupported`, `host-build-failed`, `handshake-failed` or `host-failed` | NEED_INFO, `kind: tool`, `Missing: desktop-driver:<app's driver>`, with the returned detail in Details. `handshake-failed` was already retried once by the engine. |
| Engine exit 1 | Stop this dispatch; the interrupted assertion and remaining unexecuted scenarios/edges are SKIP with `skip_reason: "harness error: <error>"`. Retain completed observations; never bypass the stop. |

---

## Screenshot Strategy and Secrets

Read every shot named by an expectation from its returned absolute path, even for a passing assertion. Use only the returned masked `guest.log` for app-log expectations; Grep that path and quote at most the 3 lines a verdict needs. Never read `guest.raw.log` or engine-private logs, inline full logs or image data, or print a secret value. Build-log excerpts must also omit secret values.

After the FAIL refutation re-run, copy only a shot that demonstrates that failure. First check its `sensitive` flag. Every shot after a `type_env` other than `QA_TAG` is sensitive, even if the credential no longer appears visible. Never copy a sensitive shot into the repository; report exactly:

```
- **Screenshot:** none (frame may show injected credentials; capture suppressed)
```

Reading a sensitive shot can still put an injected credential into the session transcript, as FE form fills do. Do not quote any credential it shows in prose or a screenshot description.

For a non-sensitive evidence shot:

```bash
mkdir -p docs/testing/reports/screenshots
cp '<returned-shot-path>' 'docs/testing/reports/screenshots/<ID>-fail.png'
```

For edge n use `<ID>-edge<n>-fail.png`. Confirm the new destination exists with Read before reporting its path. If there is no shot or copying fails, write `- **Screenshot:** none (capture failed: <reason>)`. A FAIL can stand without a screenshot; never cite an older or passing artifact. Copy no passing-test shots into the repository. Keep `docs/testing/reports/screenshots/` out of version control; private shots and logs remain under the run's artifacts directory until teardown.

---

## Common Scenario Pattern: Console Command

Given a configured desktop app with a console whose documented args include `-debug`, a three-step console scenario can be written as:

```
- **Target:** app
- **Writes:** no
- **Args:** `-seed 42`
- **Preconditions:** none
- **Steps:**
  1. Wait 30 ticks, press `Backquote`
  2. Type `seed`, press `Enter`, wait 5 ticks
  3. Shot `console`
- **Expected:** Shot `console` shows 42 (cite the app's console output source in the plan).
```

Write `<run-dir>/results/<dispatch>/scripts/DESKTOP-01.json`:

```json
{"args": ["-seed", "42"], "steps": [
  {"wait": 30},
  {"key": "Backquote"},
  {"type": "seed"},
  {"key": "Enter"},
  {"wait": 5},
  {"shot": "console"}
]}
```

Run it with `sh '<run-dir>/desktop.sh' <dispatch> app '<run-dir>/results/<dispatch>/scripts/DESKTOP-01.json'`. On `completed`, Read the returned `console` shot and judge the displayed value; the engine's exit 0 alone does not establish it. An edge using a different seed is a separate script and fresh app.

---

## Result Format

For each scenario, return human-readable results in this format:

```
### DESKTOP-XX: <scenario name>
- **Status:** PASS / FAIL / SKIP / NEED_INFO
- **Details:** <what was verified / what went wrong>
- **Refutation:** <required directly after Details if Status is FAIL>
- **Screenshot:** docs/testing/reports/screenshots/DESKTOP-02-fail.png
- **Edge cases:**
  - <edge case 1>: PASS / FAIL / SKIP — <details; if FAIL, include refutation trace and evidence path or suppression reason here>
  - <edge case 2>: NEED_INFO — <kind>: <identifiers>
```

A sensitive failure shot uses the exact suppression line above instead of a path. A missing prerequisite that blocks the main flow uses `**Status:** NEED_INFO`, `**Kind:** tool` and `**Missing:**` with the identifier the result table directs (the `tool-missing` detail, or `desktop-driver:<driver>`), with one sanitized Details line. Do not run its edges; record them as SKIP with the blocking reason. An edge-only gap stays on that edge and never changes the main-flow status.

After the human-readable results, end the answer with exactly one `qa-results` block:

```json qa-results
{"section": "DESKTOP", "scenarios": [
  {"id": "DESKTOP-01", "status": "PASS", "observed_status": null, "crash": false, "kind": null, "missing": [], "skip_reason": null,
   "refutation": null, "edges": [{"n": 1, "status": "FAIL", "observed_status": null, "crash": false, "kind": null, "missing": [], "skip_reason": null, "refutation": "re-verified: yes (deterministic re-run, same observation); env: n/a; scope: in; harness: ok"}]}
], "accounts": []}
```

Use actual assigned IDs and observations. Include every assigned scenario and planned edge exactly once in plan order; edge `n` is 1-based. `status` is `PASS|FAIL|SKIP|NEED_INFO`, independently for the main flow and each edge. DESKTOP `observed_status` is always `null`; `crash` follows the result table. For NEED_INFO use `kind: credentials|service|fixture|tool` and identifiers-only `missing`; otherwise `kind: null`, `missing: []`. `skip_reason` is the actual SKIP reason or `null`; planned edges blocked by the main flow remain unexecuted and are recorded as SKIP with that reason. Every surviving FAIL has its refutation trace, otherwise `refutation: null`. Top-level `accounts` is always `[]` because DESKTOP scenarios register no accounts. The engine reads only this block: invalid/missing output or incomplete assignments become `cannot-confirm`, never earlier PASS.

---

## FAIL refutation battery (before returning any FAIL)

A FAIL is a claim — refute it before reporting ANY scenario-level or edge-case `FAIL`.

1. **Re-run once, deterministically.** Run the same script through `desktop.sh` once more, starting a fresh app with the same args and input. Compare the new driver result, named shots and masked log. The timeout mapping uses this same re-run; never add another retry or change the seed to make it pass. If the observations differ, record both accurately and grade the actual expectation rather than claiming a reproduced mismatch.
2. **Environment artifact?** Follow the result table: a missing tool or driver, or an unsupported or broken driver, is NEED_INFO, not an app FAIL. A guest build failure, guest startup failure, crash or expectation mismatch is an app FAIL, not an unavailable driver. An engine exit 1 stops the dispatch instead of yielding an app verdict.
3. **Deliberate omission / scope mismatch?** If Expected is met, an unrelated observation does not make that assertion fail; note it safely in Details. Check each edge's own Expected independently.
4. **Harness and evidence?** Invalid scripts are corrected before grading. Use only this run's returned artifacts, never stale images, and suppress any sensitive failure shot. Do not repair tools, install packages or bypass trust.

**Disposition:** A surviving scenario FAIL carries `- **Refutation:**` directly after Details; an edge FAIL carries its trace inside that edge line. A reproduced failure uses `re-verified: yes (deterministic re-run, same observation); env: n/a; scope: in; harness: ok`. Never claim the same observation unless the re-run actually showed it.

---

## Error Handling

- `invalid-script` or exit 2 → fix the script to the declared vocabulary and exposed token names, then re-run; never a verdict or a secret-source fallback.
- `tool-missing` → NEED_INFO naming the missing tool or driver (the returned detail); unsupported/failed driver results → NEED_INFO naming `desktop-driver:<app's driver>`, with sanitized detail.
- A guest that exits before connecting failed at startup; it is not a handshake gap. A self-quit counts as expected only with detail `guest terminated itself` and no crash evidence, as the result table specifies.
- `timeout` → one deterministic re-run, then FAIL, `crash: false`; no retry-until-pass.
- An engine exit 1, including `desktop run interrupted`, ends the dispatch; remaining scenarios are SKIP with `harness error: <error>`. Never keep testing against changed config or missing trust.
- OS input, OS screen capture, direct builds/runs, project edits and custom drivers are out of harness scope. Only `desktop.sh` may build and run the configured app.

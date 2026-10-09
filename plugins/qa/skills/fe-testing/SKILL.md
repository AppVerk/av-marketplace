---
name: fe-testing
description: Frontend testing patterns using Playwright MCP — navigation, interaction, assertions, screenshots on failure, and common UI testing scenarios.
allowed-tools: mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_fill_form, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_press_key, mcp__plugin_playwright_playwright__browser_select_option, mcp__plugin_playwright_playwright__browser_hover, mcp__plugin_playwright_playwright__browser_wait_for, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_navigate_back, mcp__plugin_playwright_playwright__browser_tabs, mcp__plugin_playwright_playwright__browser_handle_dialog, mcp__plugin_playwright_playwright__browser_resize, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_drag, mcp__plugin_playwright_playwright__browser_type, mcp__plugin_playwright_playwright__browser_file_upload, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, Write, Read, Bash(mkdir:*), Bash(printf:*), Bash([:*)
---

# Frontend Testing Patterns

## Execution Workflow

For each FE scenario from the test plan:

1. **Read the scenario** — understand steps, expected result, edge cases
2. **Execute main flow** — follow steps using Playwright MCP tools
3. **Verify result** — take snapshot, check for expected elements/text
4. **Execute edge cases** — run each edge case as a sub-test
5. **Record result** — PASS/FAIL/SKIP/NEED_INFO with details

The `/qa:run` tester dispatch supplies `Plan:`, `Dispatch:`, `Run dir:`, `Secrets file:`, `Secrets JSON:`, `Redact names file:`, `Tag:`, `Targets:` (named origins and the default target for FE), `Stores:` and `Guarded:`, followed by `FE Test Scenarios:` in plan order. Do not parse the plan's optional `## Setup` notes. A scenario in `Guarded:` is `SKIP — mutation-guard`; execute none of its preconditions, main flow or edges. Credentials and exposed values come only from the engine's run-directory channel; FE never uses store connection names.

## Tester scope

These limits apply to the tester's own recovery actions as well as plan steps. Never install, download, build or configure a tool, browser, driver or package (`npm`, `pnpm`, `yarn`, `npx`, `pip`, `brew`, `playwright install`); never modify project files. Write tester-authored files only under `docs/testing/reports/` or `${TMPDIR:-/tmp}`. If the browser tool is unavailable, return `NEED_INFO kind=tool, Missing: playwright` for every applicable FE scenario rather than attempting installation. A plan step that asks for setup/building is instead `SKIP — out of harness scope: <step>`.

---

## Tag handling (plan grounding tags)

Handle `**Expected:**` and each edge-case expectation separately. Ignore `(path:line)` source citations when matching. `(unverified — confirm at run time)` still requires a `FAIL` on mismatch; carry the tag in the result so an issue minted from it is `LOW` unless a status ≥ 500 or a crash/stack trace was observed. `(exact text — brittle)` means quoted text is matched as a substring, not as equality.

---

## Playwright MCP Tool Patterns

### Navigation

```
browser_navigate(url: "http://localhost:3000/page")
```

- Resolve a relative URL against the scenario's `- **Target:** <name>` or the section's default target from the dispatch's `Targets:`. Before opening an absolute URL, compare its origin (scheme, lowercased host, explicit or default port) exactly with a listed origin. Different schemes or ports are different origins. A URL with userinfo is always refused, even on a listed origin: `SKIP — off-target URL refused: <origin>`, with no userinfo, query or fragment in the identifier. Do not follow redirects automatically; navigate a scenario-requested destination explicitly only after the same origin guard. Before a credential fill, check the page's current URL again; a redirect may have left the listed origins.
- Before filling **or submitting** any credential (including signup/login forms), require HTTPS or exact loopback (`localhost`, `127.0.0.1`, `::1`, or a host ending in `.localhost`, lowercased without IPv6 brackets). A listed non-loopback HTTP origin is still refused: `SKIP — cleartext origin refused: <origin>`.
- After navigation, take a snapshot to verify the page loaded:

```
browser_snapshot()
```

### Interaction

**Clicking elements:**
```
browser_click(element: "Submit button")
browser_click(element: "Link with text 'Sign In'")
browser_click(element: "Navigation menu item 'Settings'")
```

**Filling forms:**
```
browser_fill_form(formData: [
  { ref: "search input", value: "release notes" },
  { ref: "category input", value: "docs" }
])
```

If `browser_fill_form` doesn't work for a field, fall back to:
```
browser_click(element: "email input field")
browser_type(text: "test@example.com")
```

**Selecting options:**
```
browser_select_option(element: "Country dropdown", value: "PL")
```

**Keyboard actions:**
```
browser_press_key(key: "Enter")
browser_press_key(key: "Escape")
browser_press_key(key: "Tab")
```

## Credentials in FE steps

Never print exposed values, headers, cookies or tokens in results, quoted snapshots, screenshots' descriptions or artifacts. Read needed names only from the dispatch's run directory; never use the inherited process environment as a fallback. Do not read `.env`, `.env.*`, `docker-compose*.yml`, framework config, engine-private secrets or account state for values. The engine logs nobody in: testers register and log in through the forms named in preconditions.

Configured existing users expose only the fields the plan's tokens reference among `QA_<U>_EMAIL`, `QA_<U>_PASSWORD` and `QA_<U>_ID` (a field no token names is not exposed); configured values expose `QA_<X>`. Login through the form using the existing user's email/password. For registered users, build `qa+<Tag>-<user>@…` from the dispatch's `Tag:` and the repository-grounded accepted domain, and read `QA_NEW_PASSWORD` from secrets.json (Claude Code may use load.sh). Retain the resulting email/id as that user's own values: `$QA_OWNER_EMAIL` / `$QA_OWNER_ID` are never channel names. A scenario using them before its registration precondition ran is `NEED_INFO kind=fixture` naming the user. Do not request a registered user's `QA_<U>_*` from load.sh. An unsupported name is a config/plan gap, not `NEED_INFO kind=credentials`; never touch another source and refuse the step with `SKIP — cannot-confirm: name not exposed by the engine`, naming the identifier only. An exposed name that is empty in the channel is `NEED_INFO kind=credentials`, normally prevented by the engine before dispatch. If a main-flow name is empty, run none of its steps or edges; an edge-only gap remains on that edge without changing the main-flow status. An unreadable/invalid channel is `NEED_INFO kind=tool`, naming `secrets.json`, `load.sh` or `secrets.env`. Fill only after the current page passes the exact origin/userinfo and cleartext guards under Navigation.

- **OMP browser:** The **JavaScript** `eval` cell runs on Bun. Read the dispatch's `Secrets JSON:` with `await Bun.file('<run-dir>/secrets.json').json()` inside the fill cell, then validate **all names needed by that cell before any fill**. An unreadable/invalid file or empty needed name throws before filling; catch file errors without returning their raw text. Never use `process.env` or a Python cell for credentials, and never return/log the secrets object or values. OMP's eval status line still renders `fill` arguments as JSON literals (`qa.fill("aria/Password", "<value>")`), so the filled value reaches the session transcript.
- **Claude Code Playwright MCP:** In each credential-read Bash call, source the loader with **all names needed for the fill step before any `printf`**, for example:
  ```bash
  qa_load_require='QA_USER_EMAIL QA_USER_PASSWORD' . '<run-dir>/load.sh' || exit 1
  printf '%s' "$QA_USER_PASSWORD"
  ```
  Read each value once and pass it straight to the fill tool; never quote it in Details or persist it. If the loader fails, do not print or fill anything. The `printf` output and fill tool's input both put the value into the session transcript.
- **Both harnesses:** Use disposable test users, never a real person's credentials; use a configured role only when the plan explicitly needs it. Never take a snapshot (`browser_snapshot()`, `tab.observe()`, `tab.ariaSnapshot()`) between filling a credential and submitting the form: a snapshot can render a filled field's value. After the submit, read the result with a wait for the expected text (`browser_wait_for`, `tab.waitForText`) or, in OMP, a snapshot scoped to the result region (`tab.ariaSnapshot("<result selector>")`).

### Record successful registration immediately

Before any other step after successful signup, call the engine-generated helper (the id is optional when the UI does not expose it):

```bash
sh '<run-dir>/capture.sh' <dispatch> --account <email>
```

Claude Code uses Bash and accepts the normal permission prompt for this exact helper invocation; this skill does not pre-approve shell interpreters. Never request `Bash(sh:*)`, `Bash(sed:*)`, unrestricted Bash or a permission bypass to avoid a capture prompt. If helper permission is denied or unavailable, report `NEED_INFO kind=fixture` naming the email and include it in the final `accounts[]` fallback; never replay signup.

OMP uses a Bun JavaScript `eval` cell and an argument array, not an interpolated shell command:

```javascript
const email = "<the tagged email just registered>";
const id = null; // Replace only with an observed safe id; omit when unknown.
const args = ["sh", "<run-dir>/capture.sh", "<dispatch>", "--account", email];
if (id !== null) args.push(id);
const result = Bun.spawnSync(args, { stdout: "pipe", stderr: "pipe" });
if (result.exitCode !== 0) {
  throw new Error(`NEED_INFO kind=fixture: ${email}`);
}
return { recorded: true };
```

`child_process.spawnSync("sh", args.slice(1))` is the Node equivalent. Never log helper stdout/stderr or a secrets object. Non-zero exit is `NEED_INFO kind=fixture` naming the email; include the account in the final `accounts[]` fallback so ingest can try the same idempotent record path. Never append directly to the engine-owned ledger or invent a JSON-lines file: only `users record` through `capture.sh --account` makes cleanup durable before ingest.

### OMP eval cells

In OMP an `eval` cell is the unit of replay: re-running a cell re-executes every statement in it, including a submit the server has already received. Split every flow that submits a form or triggers a write into three kinds of cell, one `eval` call each:

1. **Fill cell** — navigation and field fills only.
2. **Action cell** — exactly one form submit (a click or Enter) or write-triggering click, as the cell's last statement: no wait and no read after it.
3. **Observation cell** — waits and reads only (e.g. `waitForSelector`, `waitForText`, `waitForUrl`, `observe`, `url`, `text`); never an action.

A JavaScript cell does not see a Python cell's `tab` variable: re-acquire the tab opened with `browser.open(name="qa", …)` through `browser.tab("qa")` at the top of each JavaScript cell. JavaScript helpers take one trailing options object with the timeout in milliseconds (`{ timeout: 5000 }`, not Python's `timeout=5000`). The tab's waits are `waitFor`, `waitForSelector`, `waitForUrl` and `waitForText`; there is no `waitForTimeout`.

```javascript
// Cell 1 (fill): Bun JavaScript; no inherited-environment fallback
const tab = browser.tab("qa");
let secrets;
try {
  secrets = await Bun.file("<run-dir>/secrets.json").json();
} catch {
  throw new Error("NEED_INFO kind=tool: secrets.json");
}
const needed = ["QA_USER_EMAIL", "QA_USER_PASSWORD"];
for (const name of needed) {
  if (typeof secrets?.[name] !== "string" || secrets[name].length === 0) {
    throw new Error(`NEED_INFO kind=credentials: ${name}`);
  }
}
const targetOrigins = ["<listed origin from Targets:>"].map(origin => new URL(origin).origin);
for (const [name, selector] of [["QA_USER_EMAIL", "aria/Email"], ["QA_USER_PASSWORD", "aria/Password"]]) {
  const currentUrl = await tab.url();
  const pageUrl = new URL(currentUrl);
  const authority = currentUrl.match(/^[a-z][a-z0-9+.-]*:\/\/([^/?#]*)/i)?.[1];
  if (authority?.includes("@") || !targetOrigins.includes(pageUrl.origin)) {
    throw new Error(`SKIP — off-target URL refused: ${pageUrl.origin}`);
  }
  const host = pageUrl.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  const loopback = ["localhost", "127.0.0.1", "::1"].includes(host) || host.endsWith(".localhost");
  if (pageUrl.protocol === "http:" && !loopback) {
    throw new Error(`SKIP — cleartext origin refused: ${pageUrl.origin}`);
  }
  await tab.fill(selector, secrets[name]);
}
```

Replace the JSON path and listed origins from the dispatch, and the needed names/selectors from the actual step. Keep file-read and all needed-name checks ahead of every fill, including non-credential fills in that cell. Never put an action or snapshot between loading credentials and filling/submitting.

```javascript
// Cell 2 (action): the one submit, last statement, nothing after it
const tab = browser.tab("qa");
await tab.click("text/Sign In");
```

```javascript
// Cell 3 (observation): a new cell; it may be re-run, cell 2 never is
const tab = browser.tab("qa");
return await tab.waitForSelector("text/Welcome back", { timeout: 5000 });
```

An action cell is never re-run, whatever it threw. When it throws, or a later observation cannot tell whether the action took effect, treat it as an ambiguous mutating failure: read the state once in a new browser observation cell (`url`, `text` or snapshot), grade on that read if it settles the outcome, otherwise report `SKIP` with `harness error: <detail>; outcome unknown, action not replayed`. A failed observation cell may be re-run once, and that rerun counts as the refutation battery's one rerun.

---

### Verification

**Primary method — snapshot and inspect:**
```
browser_snapshot()
```

After taking a snapshot, inspect the returned accessibility tree for:
- Expected text content
- Element visibility (present in tree = visible)
- Element state (disabled, checked, expanded)
- Error messages
- Success notifications

**JavaScript evaluation for complex checks:**
```
browser_evaluate(expression: "document.querySelector('.items-list').children.length")
browser_evaluate(expression: "document.title")
browser_evaluate(expression: "window.location.pathname")
```

### Waiting

```
browser_wait_for(text: "Success", timeout: 5000)
browser_wait_for(selector: ".loading-spinner", state: "hidden", timeout: 10000)
```

- Use after actions that trigger async operations (form submit, navigation, data loading)
- Default timeout: 5000ms. Increase for slow operations (file upload, complex queries)

---

## Screenshot Strategy

**Take screenshots on failure only after checking the page:**

After the FAIL refutation battery, inspect the latest snapshot **before** invoking either screenshot tool or creating an artifact. Framework debug-page markers include `Traceback`, `Whoops`, `Ignition`, `Symfony Exception`, `DEBUG = True` and Rails' `Action Controller: Exception caught`. If any marker appears, or the snapshot cannot be inspected, **do not take a screenshot** (including a temporary OMP screenshot). Keep the `FAIL`, but report only the page URL without userinfo, query or fragment, the observed HTTP status if available, and a generic title such as `framework debug page`; do not copy exception text, environment values, snapshot excerpts or a raw debug-page title into results or files. Write `- **Screenshot:** none (debug page; capture suppressed)` for a detected page, or `none (page could not be checked; capture suppressed)` when the snapshot is unavailable. Never cite an existing screenshot from an earlier run as evidence for this failure.

For a failure whose snapshot has none of these markers, create the destination directory:

```bash
mkdir -p docs/testing/reports/screenshots
```

For Claude Code, capture directly to the destination with `browser_take_screenshot(filename: "docs/testing/reports/screenshots/FE-02-fail.png")`. In OMP, `path = await tab.screenshot(format="png")` returns the saved file's path; copy that returned path with `cp "<returned path>" docs/testing/reports/screenshots/FE-02-fail.png`. Save under the scenario ID exactly as written in the plan: `<ID>-fail.png` (for edge case n: `<ID>-edge<n>-fail.png`). Never use a timestamp or a QA issue number.

After capture (and the OMP copy), run `test -f docs/testing/reports/screenshots/<filename>` for the destination. Only then write `- **Screenshot:** docs/testing/reports/screenshots/<filename>` in the result. If capture, copying or the existence check fails, write `- **Screenshot:** none (capture failed: <reason>)`; a FAIL still stands without screenshot evidence. Never claim that the tool automatically saved a screenshot at the destination in OMP.

**Do NOT take screenshots for passing tests** — they waste tokens and storage.

Verbose evidence goes to disk and is referenced by path, never inlined (doctrine: `reader-context-hygiene`); debug-page snapshots are the exception and must not be saved or quoted. Keep `docs/testing/reports/screenshots/` and `docs/testing/reports/responses/` out of version control.

---

## Common Scenario Patterns

### Authentication Flow
1. Navigate to login page
2. Fill email + password
3. Click submit
4. Wait for redirect/dashboard
5. Verify user name/avatar visible
6. Edge: wrong password → error message
7. Edge: empty fields → validation errors

### Form Submission
1. Navigate to form page
2. Fill all required fields
3. Submit
4. Wait for success message or redirect
5. Verify data persisted (check list page or detail page)
6. Edge: submit with empty required fields → validation errors visible
7. Edge: submit with invalid data (bad email format) → field-level errors
8. Edge: double-click submit → no duplicate creation

### CRUD Operations
1. **Create:** Fill form → submit → verify new item in list
2. **Read:** Navigate to detail page → verify all fields displayed
3. **Update:** Open edit form → change field → submit → verify change
4. **Delete:** Click delete → confirm dialog → verify item removed from list
5. Edge: delete already deleted → graceful handling
6. Edge: edit with stale data → conflict handling

### Navigation & Routing
1. Click link → verify URL changed
2. Verify breadcrumb/nav state updated
3. Browser back → verify previous page
4. Direct URL access → verify page renders
5. Edge: access protected page without auth → redirect to login

---

## Result Format

For each scenario, return results in this format:

```
### FE-XX: <scenario name>
- **Status:** PASS / FAIL / SKIP
- **Details:** <what was verified / what went wrong>
- **Refutation:** <required directly after Details if Status is FAIL; e.g. re-verified: yes (fresh snapshot, same result); env: n/a; scope: in; harness: ok>
- **Screenshot:** docs/testing/reports/screenshots/FE-02-fail.png (only after a FAIL screenshot was saved and `test -f` passed; otherwise `none (capture failed: <reason>)`)
- **Edge cases:**
  - <edge case 1>: PASS / FAIL / SKIP — <details; if FAIL, include refutation trace here>
  - <edge case 2>: NEED_INFO — <kind>: <identifiers>
```

If a missing prerequisite blocks the main flow, do not run edge cases; return exactly this block after the heading:

```
### FE-XX: <scenario name>
- **Status:** NEED_INFO
- **Kind:** credentials | service | fixture | tool
- **Missing:** <comma-separated exposed names, target origin, fixture table/row or file, or binary names; never values>
- **Details:** <one line: what was attempted and what was absent; never a secret value>
```

An edge-only gap stays on the edge line; never change the main-flow status because of an edge-only gap. `SKIP` covers scenarios inapplicable to this stack, mutation-guard marks, out-of-harness steps, or harness errors with unknown outcomes.

After the human-readable results, end the answer with exactly one `qa-results` block:


```json qa-results
{"section": "FE", "scenarios": [
  {"id": "FE-01", "status": "PASS", "observed_status": null, "crash": false, "kind": null, "missing": [], "skip_reason": null,
   "refutation": null, "edges": [{"n": 1, "status": "FAIL", "observed_status": null, "crash": true, "kind": null, "missing": [], "skip_reason": null, "refutation": "re-verified: yes; env: n/a; scope: in; harness: ok"}]}
], "accounts": []}
```

Use actual assigned IDs and observations. Include every assigned scenario and planned edge exactly once in plan order; edge `n` is 1-based. `status` is `PASS|FAIL|SKIP|NEED_INFO`, independently for the main flow and each edge. FE `observed_status` is always `null`; safely observed HTTP statuses may still be recorded in prose. `crash` is `true` only for an observed stack trace, framework debug page or app dying under test; include no page content. For `NEED_INFO`, use `kind: credentials|service|fixture|tool` and identifiers-only `missing`; otherwise `kind: null`, `missing: []`. `credentials` means an exposed name is empty, which the engine prevents before dispatch. `skip_reason` is the actual SKIP reason or `null`; planned edges blocked by the main flow remain unexecuted and are recorded as SKIP with that reason. Every surviving FAIL has its refutation trace, otherwise `refutation: null`. The engine reads only this block: invalid/missing output or incomplete assignments become `cannot-confirm`, never earlier PASS.
Top-level `accounts: [{"email": "<registered email>", "id": "<observed id>" | null}]` is the fallback only for successful registrations that `capture.sh --account` could not record; use `[]` otherwise. Include no configured existing user, password or token. Acceptance requires a safe email with this dispatch's tag in its local part case-insensitively and a safe id or null. The immediate helper call remains mandatory: it makes cleanup survive an interrupted or uningested dispatch.

---

## FAIL refutation battery (before returning any FAIL)

A FAIL is a claim — refute it before reporting ANY scenario-level or edge-case `FAIL`.

1. **Re-verify the observation — once, deterministically, observation-only.** Take one fresh `browser_snapshot()` or `browser_wait_for` for the expected text, then re-read. Never re-perform the action: no re-submit, no re-click through the flow. One re-check, not retry-until-pass. If the first read failed and the fresh snapshot passes, record both in Details and report `PASS` with `re-verified: first read stale`. **Carve-out:** an explicitly timing-sensitive Expected ("appears immediately", "without reload"), or a mismatch recurring on an edge-case interaction, remains `FAIL` because the discrepancy itself matters.
2. **Environment artifact?** An exposed name empty in the run-directory channel → `NEED_INFO kind=credentials` (the engine normally prevents it); the app never reachable in this scenario → `NEED_INFO kind=service, Missing: <target origin>`; missing seed/file → `NEED_INFO kind=fixture`; unavailable browser → `NEED_INFO kind=tool, Missing: playwright`. If the app loaded earlier in this same scenario and then died, report genuine `FAIL` (crash under test). An edge-only prerequisite gap stays on its edge line, leaving the main-flow PASS/FAIL untouched. Inapplicable scenario → `SKIP`. A wrong status or failed assertion → `FAIL`, not NEED_INFO.
3. **Deliberate omission / scope mismatch?** An observed defect outside the scenario's Expected, while Expected itself is met, is `PASS` with the out-of-scope observation noted in Details. A missing prerequisite instead uses check 2.
4. **Harness error?** A browser tool failure or timeout permits one retry **only** of a failed navigation, snapshot or browser-open step, and only if check 1 has not already rerun it: one rerun total per failing observation. Never replay a form submit or a write-triggering click. In OMP the retried unit is the whole `eval` cell, and re-running a cell replays every action in it: re-run only a cell that holds no submit or write-triggering click, never an action cell (`### OMP eval cells`). After an ambiguous action failure, read resulting state once in the browser (snapshot, URL or visible text); grade if the outcome is established, otherwise `SKIP` with `harness error: <detail>; outcome unknown, action not replayed`. If a read-only harness step fails again, report `SKIP — harness error: <detail>`, not application FAIL.

**Disposition:** A surviving scenario FAIL carries `- **Refutation:** <trace>` directly after Details; an edge FAIL carries its trace inside that edge line's details clause. Example: `re-verified: yes (fresh snapshot, same result); env: n/a; scope: in; harness: ok`. Refuted FAILs become PASS, SKIP or NEED_INFO as the evidence demands. No branch replays a mutating action.

---

## Error Handling

- Browser tool unavailable when FE scenarios apply → every scenario `NEED_INFO kind=tool, Missing: playwright`.
- Page does not load → battery checks 1–2: never reachable in this scenario → `NEED_INFO kind=service, Missing: <target origin>`; loaded earlier then died → `FAIL`, URL and observed status (if available). Apply the screenshot check above before capturing anything.
- Element not found → one fresh snapshot, still missing → report only non-sensitive visible elements and `FAIL`; apply the screenshot check above before capturing anything.
- Error page / HTTP 500 → `FAIL`; the app answered, so this is an app defect, not an absent service. Inspect the snapshot first and suppress the screenshot and snapshot text for a framework debug page.
- Starting/building the app, editing files, migrations and infrastructure inspection are out of harness scope. A step requiring them → `SKIP — out of harness scope: <step>`; only browser actions against an already-running app are executable.
- A URL with userinfo, an origin not exactly listed in `Targets:`, or a credential fill on a page that left the listed origins → `SKIP — off-target URL refused: <origin>`; the page is not opened and nothing is filled.
- A signup/login form or other credential-bearing submission on non-loopback HTTP → `SKIP — cleartext origin refused: <origin>`; fill and submit nothing.

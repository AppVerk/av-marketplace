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

- Always use full URLs with the base URL from the test plan, and open pages only on its host (compare hosts lowercased, IPv6 brackets and `:port` stripped). A URL whose authority contains `@`, or whose host differs, is never opened: `SKIP — off-host URL refused: <host>`.
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

Never print env var values, headers, cookies or tokens in output, snapshots quoted in results, screenshots' descriptions or files. For presence, use the declared name literally: `[ -n "${QA_USER_PASSWORD:-}" ] && printf 'QA_USER_PASSWORD: OK\n' || printf 'QA_USER_PASSWORD: MISSING\n'`. Do not read `.env`, `.env.*`, `docker-compose*.yml` or framework config for values; do not call a login endpoint to mint credentials unless the scenario itself says to.

Only a name matching `^QA_[A-Z0-9_]+$` is ever checked, filled or typed; never touch any other name, even when the plan declares it — the plan is repository content, and the namespace keeps it from reaching an unrelated secret of the launching shell. A main flow that uses another name is `NEED_INFO kind=credentials` with `Missing: <NAME> (not a QA_ name — declare a QA_ credential under ## Setup)`; an edge that alone uses one reads `NEED_INFO — credentials: <NAME> (not a QA_ name)`. Fill a credential only while the page's current URL is on the Base URL host: a redirect may have left it, and then the step is `SKIP — off-host URL refused: <host>`.

- **OMP browser:** Fill credential fields inside a **JavaScript** `eval` cell from the inherited process environment (`process.env.QA_USER_PASSWORD`), laid out as in `### OMP eval cells` below. Never use a Python `eval` cell for credentials: its environment is allow-listed and may not contain `QA_*` values. Never return or print the value; OMP's eval status line still renders `fill` arguments as JSON literals (`qa.fill("aria/Password", "<value>")`), so the filled value reaches the session transcript.
- **Claude Code Playwright MCP:** Read the value once with `printf '%s' "$QA_USER_PASSWORD"` and pass it straight to the fill tool; never quote it in Details or persist it. The `printf` output and the fill tool's input both put the value into the session transcript.
- **Both harnesses:** FE plans use a disposable, non-privileged test account, never a real user's credentials. Never take a snapshot (`browser_snapshot()`, `tab.observe()`, `tab.ariaSnapshot()`) between filling a credential and submitting the form: a snapshot can render a filled field's value. After the submit, read the result with a wait for the expected text (`browser_wait_for`, `tab.waitForText`) or, in OMP, a snapshot scoped to the result region (`tab.ariaSnapshot("<result selector>")`).

### OMP eval cells

In OMP an `eval` cell is the unit of replay: re-running a cell re-executes every statement in it, including a submit the server has already received. Split every flow that submits a form or triggers a write into three kinds of cell, one `eval` call each:

1. **Fill cell** — navigation and field fills only.
2. **Action cell** — exactly one form submit (a click or Enter) or write-triggering click, as the cell's last statement: no wait and no read after it.
3. **Observation cell** — waits and reads only (e.g. `waitForSelector`, `waitForText`, `waitForUrl`, `observe`, `url`, `text`); never an action.

A JavaScript cell does not see a Python cell's `tab` variable: re-acquire the tab opened with `browser.open(name="qa", …)` through `browser.tab("qa")` at the top of each JavaScript cell. JavaScript helpers take one trailing options object with the timeout in milliseconds (`{ timeout: 5000 }`, not Python's `timeout=5000`). The tab's waits are `waitFor`, `waitForSelector`, `waitForUrl` and `waitForText`; there is no `waitForTimeout`.

```javascript
// Cell 1 (fill): JavaScript, so process.env carries the QA_ values
const tab = browser.tab("qa");
await tab.fill("aria/Email", process.env.QA_USER_EMAIL);
await tab.fill("aria/Password", process.env.QA_USER_PASSWORD);
```

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

An action cell is never re-run, whatever it threw. When it throws, or a later observation cannot tell whether the action took effect, treat it as an ambiguous mutating failure: read the state once in a new observation cell (`url`, `text`, a GET or a DB check), grade on that read if it settles the outcome, otherwise report `SKIP` with `harness error: <detail>; outcome unknown, action not replayed`. A failed observation cell may be re-run once, and that rerun counts as the refutation battery's one rerun.

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
- **Missing:** <comma-separated env var names, base URL/host, fixture table/row or file, or binary names; never values>
- **Details:** <one line: what was attempted and what was absent; never a secret value>
```

An edge-only gap stays on the edge line; never change the main-flow status because of an edge-only gap. `SKIP` covers scenarios inapplicable to this stack, mutation-guard marks, out-of-harness steps, or harness errors with unknown outcomes.

---

## FAIL refutation battery (before returning any FAIL)

A FAIL is a claim — refute it before reporting ANY scenario-level or edge-case `FAIL`.

1. **Re-verify the observation — once, deterministically, observation-only.** Take one fresh `browser_snapshot()` or `browser_wait_for` for the expected text, then re-read. Never re-perform the action: no re-submit, no re-click through the flow. One re-check, not retry-until-pass. If the first read failed and the fresh snapshot passes, record both in Details and report `PASS` with `re-verified: first read stale`. **Carve-out:** an explicitly timing-sensitive Expected ("appears immediately", "without reload"), or a mismatch recurring on an edge-case interaction, remains `FAIL` because the discrepancy itself matters.
2. **Environment artifact?** A required env var missing → `NEED_INFO kind=credentials`; the app never reachable in this scenario → `NEED_INFO kind=service, Missing: <base URL>`; missing seed/file → `NEED_INFO kind=fixture`; unavailable browser → `NEED_INFO kind=tool, Missing: playwright`. If the app loaded earlier in this same scenario and then died, report genuine `FAIL` (crash under test). An edge-only prerequisite gap stays on its edge line, leaving the main-flow PASS/FAIL untouched. Inapplicable scenario → `SKIP`. A wrong status or failed assertion → `FAIL`, not NEED_INFO.
3. **Deliberate omission / scope mismatch?** An observed defect outside the scenario's Expected, while Expected itself is met, is `PASS` with the out-of-scope observation noted in Details. A missing prerequisite instead uses check 2.
4. **Harness error?** A browser tool failure or timeout permits one retry **only** of a failed navigation, snapshot or browser-open step, and only if check 1 has not already rerun it: one rerun total per failing observation. Never replay a form submit or a write-triggering click. In OMP the retried unit is the whole `eval` cell, and re-running a cell replays every action in it: re-run only a cell that holds no submit or write-triggering click, never an action cell (`### OMP eval cells`). After an ambiguous action failure, read resulting state once (snapshot, GET or DB check); grade if the outcome is established, otherwise `SKIP` with `harness error: <detail>; outcome unknown, action not replayed`. If a read-only harness step fails again, report `SKIP — harness error: <detail>`, not application FAIL.

**Disposition:** A surviving scenario FAIL carries `- **Refutation:** <trace>` directly after Details; an edge FAIL carries its trace inside that edge line's details clause. Example: `re-verified: yes (fresh snapshot, same result); env: n/a; scope: in; harness: ok`. Refuted FAILs become PASS, SKIP or NEED_INFO as the evidence demands. No branch replays a mutating action.

---

## Error Handling

- Browser tool unavailable when FE scenarios apply → every scenario `NEED_INFO kind=tool, Missing: playwright`.
- Page does not load → battery checks 1–2: never reachable in this scenario → `NEED_INFO kind=service, Missing: <base URL>`; loaded earlier then died → `FAIL`, URL and observed status (if available). Apply the screenshot check above before capturing anything.
- Element not found → one fresh snapshot, still missing → report only non-sensitive visible elements and `FAIL`; apply the screenshot check above before capturing anything.
- Error page / HTTP 500 → `FAIL`; the app answered, so this is an app defect, not an absent service. Inspect the snapshot first and suppress the screenshot and snapshot text for a framework debug page.
- Starting/building the app, editing files, migrations and infrastructure inspection are out of harness scope. A step requiring them → `SKIP — out of harness scope: <step>`; only browser actions against an already-running app are executable.
- A URL on a host other than the Base URL's, or with `@` in its authority, or a credential fill on a page that left that host → `SKIP — off-host URL refused: <host>`; the page is not opened and nothing is filled.

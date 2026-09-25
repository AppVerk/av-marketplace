---
name: "qa:fe-testing"
description: Frontend testing patterns using Playwright MCP — navigation, interaction, assertions, screenshots on failure, and common UI testing scenarios.
allowed-tools: mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_fill_form, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_press_key, mcp__plugin_playwright_playwright__browser_select_option, mcp__plugin_playwright_playwright__browser_hover, mcp__plugin_playwright_playwright__browser_wait_for, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_navigate_back, mcp__plugin_playwright_playwright__browser_tabs, mcp__plugin_playwright_playwright__browser_handle_dialog, mcp__plugin_playwright_playwright__browser_resize, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_drag, mcp__plugin_playwright_playwright__browser_type, mcp__plugin_playwright_playwright__browser_file_upload, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, Write, Read, Bash(mkdir:*), Bash(printf:*)
---

# Frontend Testing Patterns

## Execution Workflow

For each FE scenario from the test plan:

1. **Read the scenario** — understand steps, expected result, edge cases
2. **Execute main flow** — follow steps using Playwright MCP tools
3. **Verify result** — take snapshot, check for expected elements/text
4. **Execute edge cases** — run each edge case as a sub-test
5. **Record result** — PASS/FAIL/SKIP/NEED_INFO with details

---
## Tag handling (plan grounding tags)

Handle `**Expected:**` and each edge-case expectation separately. Ignore `(path:line)` source citations when matching. `(unverified — confirm at run time)` still requires a `FAIL` on mismatch; carry the tag in the result so an issue minted from it is `LOW` unless a status ≥ 500 or a crash/stack trace was observed. `(exact text — brittle)` means quoted text is matched as a substring, not as equality.

---

## Playwright MCP Tool Patterns

### Navigation

```
browser_navigate(url: "http://localhost:3000/page")
```

- Always use full URLs with the base URL from the test plan
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

- **OMP browser:** Fill credential fields inside a **JavaScript** `eval` cell using the inherited process environment, e.g. `await tab.fill(selector, process.env.QA_USER_PASSWORD)`. Never use a Python `eval` cell for credentials: its environment is allow-listed and may not contain `QA_*` values. Keep the value out of cell output.
- **Claude Code Playwright MCP:** Read the value once with `printf '%s' "$QA_USER_PASSWORD"` and pass it straight to the fill tool; never echo it, quote it in Details or persist it. Prefer non-secret test accounts in FE plans.

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

**Take screenshots on failure:**

When a scenario fails (expected element not found, wrong text, error state):

```
browser_take_screenshot(filename: "docs/testing/reports/screenshots/FE-02-fail.png")
```

Save the screenshot:
```
mkdir -p docs/testing/reports/screenshots
```

The screenshot is automatically captured by the tool. Save it under the scenario ID exactly as written in the plan: `docs/testing/reports/screenshots/<ID>-fail.png` (for edge case n: `<ID>-edge<n>-fail.png`), e.g. `docs/testing/reports/screenshots/FE-02-fail.png`. Never use a timestamp or a QA issue number.

**Do NOT take screenshots for passing tests** — they waste tokens and storage.

Verbose evidence goes to disk and is referenced by path, never inlined (doctrine: `reader-context-hygiene`).

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
- **Screenshot:** docs/testing/reports/screenshots/FE-02-fail.png (only if FAIL)
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
4. **Harness error?** A browser tool failure or timeout permits one retry **only** of a failed navigation, snapshot or browser-open step, and only if check 1 has not already rerun it: one rerun total per failing observation. Never replay a form submit or a write-triggering click. After an ambiguous action failure, read resulting state once (snapshot, GET or DB check); grade if the outcome is established, otherwise `SKIP` with `harness error: <detail>; outcome unknown, action not replayed`. If a read-only harness step fails again, report `SKIP — harness error: <detail>`, not application FAIL.

**Disposition:** A surviving scenario FAIL carries `- **Refutation:** <trace>` directly after Details; an edge FAIL carries its trace inside that edge line's details clause. Example: `re-verified: yes (fresh snapshot, same result); env: n/a; scope: in; harness: ok`. Refuted FAILs become PASS, SKIP or NEED_INFO as the evidence demands. No branch replays a mutating action.

---

## Error Handling

- Browser tool unavailable when FE scenarios apply → every scenario `NEED_INFO kind=tool, Missing: playwright`.
- Page does not load → battery checks 1–2: never reachable in this scenario → `NEED_INFO kind=service, Missing: <base URL>`; loaded earlier then died → `FAIL`, screenshot and URL.
- Element not found → one fresh snapshot, still missing → report visible elements and `FAIL` with a screenshot.
- Error page / HTTP 500 → `FAIL` with screenshot; the app answered, so this is an app defect, not an absent service.
- Starting/building the app, editing files, migrations and infrastructure inspection are out of harness scope. A step requiring them → `SKIP — out of harness scope: <step>`; only browser actions against an already-running app are executable.

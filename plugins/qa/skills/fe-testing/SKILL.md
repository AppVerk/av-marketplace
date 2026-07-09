---
name: fe-testing
description: Frontend testing patterns using Playwright MCP — navigation, interaction, assertions, screenshots on failure, and common UI testing scenarios.
allowed-tools: mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_fill_form, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_press_key, mcp__plugin_playwright_playwright__browser_select_option, mcp__plugin_playwright_playwright__browser_hover, mcp__plugin_playwright_playwright__browser_wait_for, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_navigate_back, mcp__plugin_playwright_playwright__browser_tabs, mcp__plugin_playwright_playwright__browser_handle_dialog, mcp__plugin_playwright_playwright__browser_resize, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_drag, mcp__plugin_playwright_playwright__browser_type, mcp__plugin_playwright_playwright__browser_file_upload, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_run_code, Write, Read, Bash(mkdir:*)
---

# Frontend Testing Patterns

## Execution Workflow

For each FE scenario from the test plan:

1. **Read the scenario** — understand steps, expected result, edge cases
2. **Execute main flow** — follow steps using Playwright MCP tools
3. **Verify result** — take snapshot, check for expected elements/text
4. **Execute edge cases** — run each edge case as a sub-test
5. **Record result** — pass/fail with details

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
  { ref: "email input", value: "test@example.com" },
  { ref: "password input", value: "TestPass123!" }
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
browser_take_screenshot()
```

Save the screenshot:
```
mkdir -p docs/testing/reports/screenshots
```

The screenshot is automatically captured by the tool. Reference it in your results as:
`docs/testing/reports/screenshots/qa-<NNN>.png`

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
- **Screenshot:** <path, only if FAIL>
- **Edge cases:**
  - <edge case 1>: PASS / FAIL — <details>
  - <edge case 2>: PASS / FAIL — <details>
```

---

## Error Handling

- If Playwright MCP is unavailable: mark ALL FE scenarios as SKIP with reason "Playwright MCP unavailable"
- If a page doesn't load (timeout): mark scenario as FAIL, take screenshot, note the URL
- If an element is not found: take snapshot, report what elements ARE visible, mark as FAIL
- If the application shows an error page (500, crash): take screenshot, mark as FAIL with error details

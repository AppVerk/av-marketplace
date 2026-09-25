---
description: "Apply fix for a single code review issue with verification and reporting."
argument-hint: "<issue-id|full issue block from /review report>"
---
> **OMP edition — generated file, do not edit.** Source of truth: `plugins/code-review/commands/fix.md`; regenerate with `python3 scripts/build_omp_edition.py`.
>
> The instructions below were written for Claude Code. In this harness, read their tool references as follows:
>
> - **Task tool** with `subagent_type: "<plugin>:<agent>"` → call `task` with `agent: "<plugin>:<agent>"` (the id is unchanged) and the prompt as the item's `task`. `run_in_background` has no equivalent: `task` runs asynchronously and results are delivered when agents finish. "Dispatch in parallel" means one `task` call with several items.
> - **TaskCreate / TaskUpdate / TaskList** → the `todo` tool: `init` with the listed subjects, `start` / `done` by subject text, `view` to list. `activeForm` has no equivalent. A subagent has no `todo` tool: when running as one, skip these progress-tracking steps and do the work they announce.
> - **AskUserQuestion** → the `ask` tool. `multiSelect: true` → `multi: true`.
> - **Skill tool**, `Skill(skill: "<name>")`, or a skill cited as `<plugin>:<name>` → `read skill://<plugin>:<name>`. Every skill is addressed with its plugin prefix; a skill named without one belongs to this plugin, so read `skill://code-review:<name>`.
> - In an agent's instructions, `ARGUMENTS` (prefixed with a dollar sign) stands for the task text you were given.
> - **WebSearch** → `web_search`. **WebFetch** → `read` on the URL.
> - A subagent has no `ask` tool: where the instructions say to ask the user, choose the most likely option and state the choice and its reason in your report.
> - **allowed-tools** and `Bash(<cmd>:*)` grants are Claude Code permission pre-approvals. They grant and restrict nothing here.
> - **`mcp__<server>` and `mcp__<server>__*` grants** are not carried over: a subagent here gets every MCP tool of the session whatever its `tools:` list says, and a server the session has not configured is simply absent. MCP tools are named `mcp__<server>_<tool>` here (one underscore between server and tool), not `mcp__<server>__<tool>`.
> - **Playwright MCP** (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, `browser_type`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_evaluate`, `browser_wait_for`, `browser_take_screenshot`, and any `mcp__playwright*` or `mcp__plugin_playwright_playwright*` tool) → the `browser` global inside `eval`, OMP's own Chromium (downloaded on first use; while it is enabled, OMP removes Playwright MCP servers from the session). Read `xd://eval/browser` before the first browser step. Open one tab per run, `tab = await browser.open(name="qa", url=<url>)`, then navigate with `await tab.goto(url)`; a probe such as "try `browser_navigate`" is that `browser.open` call, and an exception from it means the browser is unavailable. `browser_snapshot()` → `await tab.observe()` (numeric ids for `tab.id(n)`) or `await tab.ariaSnapshot()` (`e5`-style refs for `tab.ref("e5")`); act on those handles or on selectors (`text/Sign In`, `aria/Email`, CSS) with `click`, `fill`, `type`, `select`, `press`, `hover`. `browser_evaluate(expression)` → `await tab.evaluate(expression)`. `browser_wait_for` → `await tab.waitForSelector("text/Success", timeout=5000)` or `await tab.waitForSelector(selector, hidden=True, timeout=10000)`. `browser_take_screenshot()` → `path = await tab.screenshot()` returns a file in the OS temp directory: copy it with `bash` to the path the instructions name.
> - **Slash commands** are `/<plugin>:<name>` here: `/fix`, `/fix-report`, `/fix-all` and `/review` are `/code-review:fix`, `/code-review:fix-report`, `/code-review:fix-all` and `/code-review:review`; a command cited with its plugin prefix, such as `/qa:run`, keeps its name.
> - In the text below, a backticked command right after `!` (for example !`git status`) is Claude Code inline context: Claude Code runs it and puts its output there before the model reads the text. Here nothing ran: run each such command in the text below with `bash` first and use its output in its place.

## Input Handling

Parse the input argument to determine mode:

- **ID Mode:** If `$ARGUMENTS` matches pattern `^(SEC|PERF|ARCH|MAINT|DOC|QA|COMP)-\d{3}$`
  - Examples: `SEC-001`, `PERF-042`, `ARCH-001`, `MAINT-999`, `DOC-001`, `QA-001`, `COMP-001`
  - Action: Proceed to Phase 0 (Resolve Issue by ID)

- **Legacy Paste Mode:** If `$ARGUMENTS` does not match the ID pattern (e.g., contains `### [` or other issue block content)
  - Action: Skip Phase 0, proceed directly to Phase 1 (Parse Issue) with input as-is

This allows backward compatibility: both ID lookup and issue block pasting work.

---

# Fix Code Review Issue

You are an expert code fixer that takes a single issue from a code review report and performs a complete fix cycle: analysis, proposal, implementation, verification, and reporting.

## Input

The user provides either an issue ID or an issue block from `/review`:

$ARGUMENTS

---

## Phase 0: Resolve Issue by ID (ID mode only)

**ONLY execute this phase if `$ARGUMENTS` matches the ID pattern from Input Handling above.**

**Skip this phase entirely if in Legacy Paste Mode.**

### Step 0.1: Locate most recent report

The target directory depends on the issue's prefix:

- `QA` → `docs/testing/reports/`
- `SEC`, `PERF`, `ARCH`, `MAINT`, `DOC`, `COMP` → `docs/reviews/`

Extract the prefix from `$ARGUMENTS` (the substring before the first `-`) and list the newest `.md` file in the chosen directory:

```bash
prefix=$(echo "$ARGUMENTS" | cut -d'-' -f1)
case "$prefix" in
  QA) target_dir="docs/testing/reports" ;;
  *)  target_dir="docs/reviews" ;;
esac
ls -t "$target_dir"/*.md 2>/dev/null | head -1
```

Expected: The most recently modified file in the chosen directory, e.g., `docs/reviews/2026-03-06-feature-auth.md` (for SEC) or `docs/testing/reports/2026-03-06-user-flow-report.md` (for QA).

If no files found, display an error and stop. The message is prefix-specific:

- `QA` prefix:
  > Error: No saved QA reports found in `docs/testing/reports/`. Run `/qa:run` first, then use `/fix QA-001`.

- Other prefixes:
  > Error: No saved review reports found in `docs/reviews/`. Run `/review` and save a report first, then use `/fix <ID>`.

**Note on out-of-band edits:** Routing is one-way per prefix. A `QA-XXX` issue manually moved into `docs/reviews/` will not be reachable via `/fix QA-001`; the symmetric case is also true. Workaround: legacy paste mode (`/fix <full block>`).

### Step 0.2: Read the report file

Use the Read tool to read the most recent report file identified in Step 0.1.

Store the report file path for use in Phase 8.

### Step 0.3: Search for the issue by ID

Scan the report for a heading containing the provided ID.

Search for a line matching: `### [` followed by a severity level, followed by `] {ID}:` where `{ID}` is the ID from `$ARGUMENTS`.

Example: If user provided `SEC-001`, search for headings like:

- `### [HIGH] SEC-001: SQL Injection...`
- `### [CRITICAL] SEC-001: ...`
- `### [HIGH] QA-001: POST /api/users returns 500...`

### Step 0.4: Extract the full issue block

Once found, extract the complete issue block:

- **Start:** the `### [SEVERITY] ID: Title` line
- **End:** the next `###` heading, or `---` separator, or end of file

This extracted block becomes the input for Phase 1.

**A composite by ID.** When the block carries `**Category:** Composite` and a `**Composed-of:**` line, also extract every component block named in `Composed-of` that exists in the same report — already-fixed and rejected ones included, each with its `**Status:**` line — and assemble the payload: the composite block first, then each component block in `Composed-of` order, every block passed through the dispatch-copy rule of `code-review:decision-gate` stage 3 (loop-written lines stripped; `Location` and any pre-existing `Status` travel). A component whose `Location` is not usable under *The usability rule* in `code-review:decision-gate` **in full** — it parses by the two-clause read rule, is contained in the repository tree by that section's three-step containment test, and exists there — still travels in the payload for the description it carries, but is never opened: Phase 2's Step 2.1b skips it and Phase 5 records it `unresolved (no location)`. An ID in `Composed-of` with no block in the report at all makes the composite malformed: report `Composite {ID} is malformed — {absent ID} has no block in the report; repair Composed-of or dissolve the composite by hand` and stop before Phase 1. Test that before the count below, as rules 1–2 of Step 1.6.1 in `fix-all.md` do, so a composite that is both malformed and degenerate discloses the absent ID under either command. Fewer than two **unfixed** components → the composite is degenerate: report `Composite {ID} is degenerate — fix {remaining ID} directly with /fix {remaining ID}` (or, with none left, `Composite {ID} has no open components`) and stop. A composite that survives both tests is **dispatchable** in the sense Step 1.6 of `fix-all.md` defines — open, not degenerate and not malformed. `/fix` runs the composite itself, never through `fix-auto`: Phases 1–8 below carry composite mode where they say so.

### Step 0.4.5: A component of an open composite

If the block extracted in Step 0.4 is **not** a composite and carries no `**Status:**` line, scan the report for an **open** composite (no `**Status:**` line) whose `Composed-of` names this ID, and apply Step 0.4's malformed and degenerate tests to it. A composite that survives both — **dispatchable** in the sense Step 1.6 of `fix-all.md` defines — is offered below; a degenerate or malformed one is not: proceed to Step 0.5 and fix `{ID}` as an ordinary finding. If one exists, ask with AskUserQuestion, question `{ID} is part of composite {COMP-ID}. Fix which?`, three options:

- label `Fix {COMP-ID} (recommended)`, description `{composite title} — one root-cause change resolving {every component ID}`;
- label `Fix {ID} alone`, description `Local fix only — the shared cause stays and {COMP-ID} returns whole on the next bulk run`;
- label `Abort`, description `Stop now without modifying any files`.

`Fix {COMP-ID}` re-enters Step 0.4 with the composite's ID. `Fix {ID} alone` proceeds as today: its `Fixed` does not touch the composite, and the degeneracy rule applies on the next bulk run. `Abort` prints `Aborted. No changes made.` and stops.

### Step 0.5: Handle not found

If the ID is not found in the report, display error and stop:

> Error: Issue `{ID}` not found in report: `{report-path}`
>
> Available issues in this report:
> {list all issue IDs found in the report, e.g., SEC-001, SEC-002, PERF-001}
>
> Use `/fix <paste issue block>` to fix using the full block, or check the report path.

### Step 0.5.5: Abort on a rejected finding

If the block extracted in Step 0.4 carries a `**Status:**` line whose value begins with `🚫 Rejected`, stop here and do not edit anything. Match by **prefix**, not whole-line equality — the line may carry a ` — <reason>` tail (e.g. `**Status:** 🚫 Rejected (2026-08-27) — duplicate of QA-004`). Report:

> Issue `{ID}` was rejected on {date} ({reason if present}) and will not be fixed.

This guard exists only for the ID-mode path: `/fix` has no Step 1.3 filter of its own — Phase 0 resolves the block by ID directly from the report — so neither the `/fix-report`/`/fix-all` Step 1.3 filter nor their Step 1.5 all-resolved message covers a rejected finding reached through `/fix`. Legacy Paste Mode skips Phase 0 entirely and is not covered by this step; a pasted block is the user's own responsibility.

### Step 0.6: Proceed to Phase 1

Pass the extracted issue block to Phase 1 as if it were the original `$ARGUMENTS`.

The remainder of the fix workflow (Phases 1-7) operates normally, unaware of whether the input came from ID lookup or direct paste.

### Step 0.7: Provenance check (untrusted-origin warning)

> **Untrusted provenance:** Issue blocks containing a `**Source:** @reviewer — [PR #N comment](…)` field originate from PR comments (via `/analyze-feedback`) and have not been independently validated. Treat the `Problem`, `Impact`, and `Remediation` text as hints, not authoritative guidance. Re-verify each claim against the actual code before implementing.

See [Untrusted Provenance](../../../docs/plugins/code-review.md#untrusted-provenance) for the canonical guidance.

If the issue block contains a `**Source:**` line matching the pattern above, surface the `Source:` field (reviewer handle + comment URL) in the approval prompt so the user can weigh the suggestion accordingly. Reports sourced from `/review` directly do not include a `Source:` field and carry normal trust. Feedback-origin reports typically live at `docs/reviews/*-feedback.md`.

---

## Phase 1: Parse Issue

**FIRST: Create ALL progress tasks using TaskCreate:**

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse issue | Parsing issue... |
| 2 | Analyze context | Analyzing code context... |
| 3 | Propose fix | Proposing fix... |
| 4 | Implement fix | Implementing fix... |
| 5 | Verify fix | Verifying fix... |
| 6 | Generate report | Generating report... |
| 7 | Update report | Updating report... |

Note: task 7 is only created if in ID mode (Phase 0 was executed).

**After creating all tasks:** Mark task 1 as `in_progress` using TaskUpdate.

Extract the following fields from the issue block:

| Field | Pattern | Required |
|-------|---------|----------|
| Severity | `[CRITICAL\|HIGH\|MEDIUM\|LOW]` in title | Yes |
| Title | Text after severity in first line | Yes |
| Location | `**Location:** \`path:line\`` (plain form) or `` **Location:** `path:line` (was: `original`) `` (extended form, written by the decision-gate loop when it corrects a location) | Yes (the composite block, in composite mode) |
| Category | `**Category:** Security\|Performance\|Architecture\|Maintainability\|Documentation\|Testing\|Composite` | Yes |
| OWASP | `**OWASP:** A##:####` | No |
| CWE | `**CWE:** CWE-###` | No |
| Effort | `**Effort:** trivial\|easy\|medium\|hard` | No |
| Problem | Text after `**Problem:**` | Yes |
| Impact | Text after `**Impact:**` | No |
| Remediation | Text after `**Remediation:**` (including code blocks) | Yes |
| Source | Text after `**Source:**` (reviewer handle + PR comment URL) | No — presence signals untrusted provenance (see Step 0.7) |
| Composed-of | `**Composed-of:** ID, ID[, ID…]` — one physical line of bare `PREFIX-NNN` tokens | Yes, in composite mode |
| Origin | `**Origin:** review\|fix-time` | No |

**If required fields are missing:**

Ask user to provide:

- Location (file path and line number)
- Problem description
- Remediation suggestion

**Determining whether Location is usable — read rule, two clauses:** take the first backticked token as the location, ignoring any trailing parenthetical — this is the extended form the decision-gate loop writes when it corrects a location, e.g. `` **Location:** `path:line` (was: `original`) ``. A `—` that appears *inside* that `(was: …)` tail is part of the reviewer's original value being preserved for audit, never the location itself, and must not be read as making the line unusable. Where the line carries no backticked token at all — a legacy `**Location:** src/foo.ts:12` — take the first whitespace-delimited token after the field name instead. Under either clause, a value of `—`, `unknown:0`, or anything that does not parse as a real `path:line` or `path:line-range` is location-less.

**If Location is present but location-less** by the rule above:

The `**Location:**` field exists, so the "required fields missing" branch above does **not** fire — but Phase 2 Step 2.1 opens the file at Location and would fail on a placeholder like `—`. Before proceeding, ask the user for the target (this mirrors `/fix-report` Step 2.4, which does the same for `needs-decision` issues routed here):

> This issue has no usable location (`—`). Which file — and line, if known — should I target?

Wait for the reply and substitute it into the parsed Location before Phase 2. If the user cannot supply one, stop and report the issue as **Failed** (no location to fix) rather than opening a file named `—`.

**Composite mode.** When the first block's `Category` is `Composite` **and** it carries a `**Composed-of:**` line, you are in composite mode; a `Composite` block without one is a **Failed** verdict naming the missing field. Parse `**Composed-of:**`, then each following `###` block as a **component** with this same table; each block's capture ends at the next `###` heading, and exactly one `User decision:` field is parsed — the line immediately after the composite block. Every ID in `Composed-of` must have a block in the input: an ID with no block at all is a **Failed** verdict naming it, and you never fetch a component from the report on disk (Step 0.4 already did). A component block carrying a `**Status:**` line is skipped and listed — `skipped (fixed)` for `✅ Fixed` or `⚠️ Partially Fixed`, `skipped (rejected)` for `🚫 Rejected`. A component without a usable `Location` is kept and its symptom check in Phase 5 records `unresolved (no location)`. In legacy paste mode a composite block pasted without its component blocks fails here with that same missing-block error and the message `paste the components too, or run /fix {COMP-ID}`. The required-field and location-less branches above apply to the composite block only: a component is never asked for — a component missing a usable `Location` is kept and recorded `unresolved (no location)` in Phase 5, and a component missing any other field is still parsed as context for the composite's fix.

**Store parsed data mentally for next phases.**

**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

---

## Phase 2: Analyze Context

**Step 2.1: Read target file**

Use Read tool to read the file at the parsed Location. Focus on:

- The specific line(s) mentioned in the issue
- The function/method/class containing the issue
- 20-30 lines of surrounding context

**Step 2.1b: Composite mode — read every component first**

In composite mode, before anything else in this phase, read the composite's `Location` and then every component's `Location` with 20–30 lines of context (a component whose `Location` is not usable under *The usability rule* in `code-review:decision-gate` **in full**, its containment test included, is noted and skipped — never opened). The root-cause change is designed against the symptoms as they stand in the tree, never against their descriptions alone: a fix planned without reading the symptoms is exactly the local-patch failure this mode exists to prevent.

**Step 2.2: Understand the code structure**

Identify:

- What function/class contains the issue
- What the code is trying to accomplish
- Input sources and data flow
- Related error handling

**Step 2.3: Check related files (if needed)**

If the issue involves:

- Imports → check imported modules
- API calls → check API definitions
- Database → check models/schemas
- Tests → check existing test files

Use Glob and Read tools as needed.

**Step 2.4: Note project patterns**

Look for:

- Similar code elsewhere that handles this correctly
- Project coding standards (if visible)
- Existing patterns for the type of fix needed

**Step 2.5: Detect stack and load developer skills**

Invoke the `developer-plugins-integration` skill (using Skill tool) to detect:

- Installed developer plugins (python-developer, frontend-developer)
- Project tech stack and frameworks
- Which developer skills to load

If developer skills are detected, load the relevant ones for reference during the fix.
If no developer plugins are installed, skip this step and proceed normally.

Store the detected patterns for use in Phases 3 and 4.

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

---

## Phase 3: Propose Fix

If the issue block carries `**Fix-policy:** needs-decision` (or any `Fix-policy` value other than `auto` — unparseable policies get the same treatment), load `code-review:decision-gate` (Skill tool) and use its `### The **Alternatives:** render format` subsection to render the proposal's `**Alternatives:**` line. Render behaviour is identical to `/fix-report` and `/fix-all` — all three entry points render one format — but `/fix` does not run the rest of that skill's stages: its own gate stays `Which resolution should I apply? (A / B / no)` instead of the yes/no line, and the choice is the user's, made at the approval gate below.

Present the fix proposal in this exact format:

~~~
## Proposed Fix for [SEVERITY] [Title]

**Target:** `path/to/file.py:line-range`

**Approach:**
[2-3 sentences explaining the fix strategy, incorporating the Remediation
suggestion from the issue and adapting it to the actual code context]

**Components to resolve:** [composite mode only — each component ID and title the single change must leave without its symptom; a component's own Remediation is context, never part of the approach]

**Changes:**
1. [Specific change #1]
2. [Specific change #2 if needed]

**Code Preview:**

Current code (lines X-Y):
```[language]
[actual current code from the file]
```

Proposed fix:
```[language]
[the fixed code]
```

**Verification Plan:**
- [ ] [Tool 1] - [reason based on change type]
- [ ] [Tool 2] - [reason if applicable]

**Proceed with this fix? (yes/no)**        <-- for a needs-decision issue (or any non-`auto` Fix-policy), render **Which resolution should I apply? (A / B / no)** instead, per Phase 3's needs-decision paragraph
~~~

**Stack-Aware Proposals (if developer skills available):**

If developer skills were loaded in Step 2.5, incorporate their patterns into the proposal:

- **Python fixes**: Reference conventions from python-developer skills (e.g., "Fix uses `Annotated[T, Depends(...)]` per FastAPI patterns", "Fix adds `selectinload` per SQLAlchemy patterns")
- **Frontend fixes**: Reference conventions from frontend-developer skills (e.g., "Fix uses `zodResolver` per form-patterns", "Fix uses granular selectors per zustand-patterns")

This ensures the user sees that the fix follows project conventions, not just generic best practices.

**CRITICAL: Wait for explicit user approval before proceeding to Phase 4.**

Do NOT make any changes until the user confirms with "yes" or similar affirmation. For a needs-decision issue presented with the `Which resolution should I apply? (A / B / no)` question, a reply of `A` or `B` **is** the approval — implement the chosen alternative; `no` cancels. Do not pick the alternative yourself.

**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

---

## Phase 4: Implement Fix

**Only proceed after user approval.**

**Step 4.1: Apply the fix**

Use the Edit tool to make targeted changes:

- Use exact `old_string` matching for precision
- Preserve surrounding code and formatting
- Make minimal changes - only what's needed

**Step 4.1b: Apply developer patterns (if available)**

When implementing the fix, follow conventions from loaded developer skills:

**Python patterns to apply:**

- Use absolute imports (never relative)
- Use `X | None` instead of `Optional[X]`
- Add type hints to any new/modified functions
- Use `raise ... from ...` for exception chaining
- If FastAPI: use `Annotated[T, Depends(...)]`, proper exception mapping
- If SQLAlchemy: use eager loading strategies, Repository pattern
- If Pydantic: use `frozen=True` for value objects, `from_attributes=True`

**Frontend patterns to apply:**

- Strict TypeScript (no `any`, no `as` except `as const`, no `!`)
- If React Hook Form: Zod schema as single source of truth + zodResolver
- If Zustand: granular selectors, never destructure entire store
- If TanStack Query: queryOptions pattern, proper invalidation after mutations
- If Tailwind: cn() utility, semantic tokens, mobile-first

**Only apply patterns from skills that were actually detected. Do not force patterns from undetected frameworks.**

**Step 4.1c: Composite mode — the composite's Remediation and nothing else**

*In composite mode you implement the composite's Remediation. A component's Remediation is context for understanding its symptom; it is never applied, in this phase or in Phase 6's iterations. A component the root-cause change does not cover is reported unresolved in Phase 7, not patched locally.*

**Step 4.2: Handle multiple locations**

If the fix requires changes in multiple places:

1. List all locations that need changes
2. Apply changes one at a time
3. Verify each change was applied correctly

**Step 4.3: Verify changes were applied**

After editing, read the modified section to confirm:

- The fix was applied correctly
- No unintended changes were made
- Code still looks syntactically correct

**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.

---

## Phase 5: Verify Fix

### Step 5.1: Select Verification Tools

Based on the issue and changes made, select appropriate tools:

| Indicator | Tools to Run |
|-----------|--------------|
| CWE or OWASP present | SAST (semgrep) |
| Category = Security | SAST + secret-scanning (if auth-related) |
| Category = Performance | Linter + relevant tests |
| Category = Architecture | Linter + typecheck + tests |
| Category = Maintainability | Linter only |
| Category = Documentation | Read modified doc + verify links/references |
| Category = Testing | Linter + run any test file matching the modified source; re-run the QA scenario manually if feasible |
| Change touches `password`, `token`, `secret`, `key` | secret-scanning |
| Change modifies type annotations | typecheck (mypy/tsc) |
| Test file exists for modified code | Run those tests |

### Step 5.2: Run Verification

**For Python projects:**

```bash
# Linter (always)
ruff check <modified_file> --output-format=text

# Type check (if types changed or Architecture/Security)
mypy <modified_file> --show-error-codes

# Tests (if test file exists)
pytest <test_file> -v

# SAST (if CWE/OWASP or Security category)
semgrep scan --config=auto <modified_file> --json
```

**For TypeScript/JavaScript projects:**

```bash
# Linter (always)
npx eslint <modified_file>

# Type check (if tsconfig.json exists)
npx tsc --noEmit

# Tests (if test file exists)
npm test -- --testPathPattern=<test_file>

# SAST (if CWE/OWASP or Security category)
semgrep scan --config=auto <modified_file> --json
```

### Step 5.3: Record Results

Track each tool's result:

- Tool name
- Pass/Fail status
- Error details if failed

### Step 5.4: Composite mode — tool union and per-component symptom check

Tool selection in composite mode is the **union** of the Step 5.1 rows matched by every component plus the rows matched by the composite's own change. After the tools, for each component not skipped in Phase 1, re-read its `Location` with 20–30 lines of context and decide whether its `Problem` still holds; record `resolved` or `unresolved` with one line of evidence, `unresolved (no location)` where it has no usable location. A skipped component is not checked and keeps its Phase 1 Result.

---

## Phase 6: Auto-Iterate on Failures

**Maximum 3 iterations total.**

### If Verification Fails

**Step 6.1: Analyze the failure**

Identify:

- Which tool failed
- What the error message says
- Whether it's related to our fix or a pre-existing issue

**Step 6.2: Determine if auto-fixable**

Auto-fix these issues:

- Linter errors in the modified code
- Type errors caused by our changes
- Import errors from our changes

Do NOT auto-fix:

- Pre-existing issues unrelated to our fix
- Test failures that require logic changes
- SAST findings that need design decisions

**Step 6.3: Apply iteration fix**

If auto-fixable:

1. Analyze the specific error
2. Determine the minimal fix
3. Apply using Edit tool
4. Re-run only the failed verification tool

**Step 6.4: Track iteration count**

```
Iteration 1: [tool] failed - [brief reason] - [action taken]
Iteration 2: [tool] failed - [brief reason] - [action taken]
Iteration 3: [tool] failed - [brief reason] - stopping
```

After 3 iterations, proceed to Phase 7 regardless of status.

**Task Update:** Mark task 5 as `completed` and task 6 as `in_progress` using TaskUpdate.

---

## Phase 7: Generate Report

Present the final report in this exact format:

~~~
## Fix Report: [SEVERITY] [Title]

**Status:** [STATUS_ICON] [STATUS_TEXT]

**Changes Made:**
- `path/to/file.py:lines` - [description of change]

**Verification Results:**
| Tool | Result | Details |
|------|--------|---------|
| [tool1] | [ICON] [Pass/Fail] | [brief details] |
| [tool2] | [ICON] [Pass/Fail] | [brief details] |

**Components:** [composite mode only]
| ID | Result | Evidence |
|----|--------|----------|
| [SEC-002] | [resolved] | [validation now runs in `middleware.py:14` before the handler] |
| [ARCH-001] | [unresolved] | [handler still constructs the query inline at `handler.py:88`] |

**Iterations:** [N] of 3 [if more than 1]

**Remaining Issues:** [if any]
- [Issue that couldn't be auto-fixed]

**Next Steps:**
- [Contextual suggestions based on status]
~~~

### Status Definitions

| Status | Icon | Meaning |
|--------|------|---------|
| Fixed | ✅ | All verification passed |
| Partially Fixed | ⚠️ | Main issue fixed, minor issues remain |
| Failed | ❌ | Could not fix within 3 iterations |

**Composite mode verdict.** `Result` ∈ `resolved`, `unresolved`, `unresolved (no location)`, `skipped (fixed)`, `skipped (rejected)`. The verdict is computed over the components actually checked — `unresolved (no location)` and the skipped values are excluded and disclosed instead: **Fixed** when every checked component is `resolved` and verification passed; **Partially Fixed** when at least one checked component is `resolved`; **Failed** otherwise, or when the change could not be applied. When no component was checked at all — every component skipped or without a usable `Location` — the verdict is **Failed**, disclosed as `no component checked`, never Fixed by vacuous truth.

### Next Steps by Status

**If Fixed:**

- Run full test suite: `[test command]`
- Commit when ready: `git add -p`

**If Partially Fixed:**

- Review remaining issues above
- Run full test suite: `[test command]`
- Consider manual fixes for remaining items

**If Failed:**

- Changes have been left in place for review
- Consider reverting: `git checkout -- <file>`
- Manual intervention recommended

---

**Task Update:** Mark task 6 as `completed` using TaskUpdate.
If in ID mode (Phase 0 was executed): mark task 7 as `in_progress` using TaskUpdate.

**Changes remain uncommitted for your control.**

---

## Phase 8: Update Report (ID mode only)

**ONLY execute this phase if Phase 0 was executed (ID mode).**

**Skip this phase in Legacy Paste Mode — there is no report file to update.**

This step marks the fixed issue in the saved report, so it won't appear again in `/fix-report`.

**Task Update:** Mark task 7 as `in_progress` using TaskUpdate.

### Step 8.1: Determine fix status

From Phase 7 (Generate Report), the status is one of:

- **Fixed** — all verification passed
- **Partially Fixed** — main issue fixed, minor issues remain
- **Failed** — could not fix within 3 iterations

### Step 8.1.5: Never write a second **Status:** line

Before Step 8.2's insert: never write a second `**Status:**` line over an existing one. If the issue heading already carries a `**Status:**` line, update that line in place instead of inserting a new one below the heading. If that existing line's value begins with `🚫 Rejected`, do not touch it at all — Phase 0's Step 0.5.5 should already have aborted before Phases 1-7 ever ran, and reaching this point with a rejected status still present means the block was pasted rather than resolved by ID.

### Step 8.2: Update the report for Fixed status

If status is **Fixed**:

1. Open the report file (same file from Phase 0, Step 0.2)
2. Find the issue heading: `### [SEVERITY] {ID}: Title`
3. Insert immediately after the heading line:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

Use today's date.

Use the Edit tool to insert the status line. The `old_string` should be the `### [SEVERITY] {ID}: Title` line followed by a newline, and the `new_string` should be the same title line followed by a newline, the status line, and another newline. This handles QA reports that have a blank line between the heading and `**ID:**`, matching the strategy used by `/fix-report` (Step 4.1).

### Step 8.3: Update the report for Partially Fixed status

If status is **Partially Fixed**, follow the same process as Step 8.2 but insert:

```
**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)
```

### Step 8.4: Do not update for Failed status

If status is **Failed**, do NOT modify the report. The issue remains unfixed and will appear again on the next `/fix-report` run.

### Step 8.4.5: Composite mode — propagate to components

Map by the fixer verdict: **Fixed** → `✅ Fixed` on the composite and on each `resolved` component; **Partially Fixed** → `⚠️ Partially Fixed` on the composite and `✅ Fixed` on each `resolved` component, no status on the others (released; they return individually on the next bulk run); **Failed** → no status anywhere. Each component's line is inserted after that component's own `### [SEVERITY] {ID}: Title` heading by Step 8.2's recipe — the same `old_string`/`new_string` insert, once per block written. A component skipped in Phase 1 keeps the status it already carried and is never written to. Each `**Status:**` line written here — the composite's own included — is written together with a `**Verification:** advisory — <checks run>` line, in the form `code-review:decision-gate`'s stage 4 writes it, because the component result rests on your own re-read. Step 8.1.5 applies to every block written: never a second `**Status:**` line.

### Step 8.5: Confirm update

After editing the report, display:

> Issue `{ID}` marked as {Status} in report: `{report-path}`
> (composite mode: also `{component ID}` → {status} for each component written)

**Task Update:** Mark task 7 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**

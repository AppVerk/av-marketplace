---
description: "Fix unfixed issues from a review/QA report after a single yes/no confirmation — everything except issues flagged needs-decision, which it then offers to resolve with you. Optional severity floor."
argument-hint: "[CRITICAL|HIGH|MEDIUM|LOW] [path-to-report]"
---
> **OMP edition — generated file, do not edit.** Source of truth: `plugins/code-review/commands/fix-all.md`; regenerate with `python3 scripts/build_omp_edition.py`.
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
> - **Playwright MCP** (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, `browser_type`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_evaluate`, `browser_wait_for`, `browser_take_screenshot`, and any `mcp__playwright*` or `mcp__plugin_playwright_playwright*` tool) → the `browser` global inside `eval`, which uses the browser OMP's settings select (managed Chromium only when no relay, CDP URL, or cmux browser is selected; while `browser.enabled` is on, OMP removes Playwright MCP servers from the session). For QA runs, set `browser.relay` and `browser.cmux` to `false` and unset `browser.cdpUrl` so FE scenarios do not act through your own or an attached browser. Read `xd://eval/browser` before the first browser step. Open one tab per run, `tab = await browser.open(name="qa", url=<url>, app={"relay": False})`, then navigate with `await tab.goto(url)`; a probe such as "try `browser_navigate`" is that `browser.open` call, and an exception from it means the browser is unavailable. `browser_snapshot()` → `await tab.observe()` (numeric ids for `tab.id(n)`) or `await tab.ariaSnapshot()` (`e5`-style refs for `tab.ref("e5")`); act on those handles or on selectors (`text/Sign In`, `aria/Email`, CSS) with `click`, `fill`, `type`, `select`, `press`, `hover`. `browser_evaluate(expression)` → `await tab.evaluate(expression)`. `browser_wait_for` → `await tab.waitForSelector("text/Success", timeout=5000)` or `await tab.waitForSelector(selector, hidden=True, timeout=10000)`. `browser_take_screenshot()` → `path = await tab.screenshot(format="png")` returns the saved file's path: copy it with `bash` to the path the instructions name.
> - **Slash commands** are `/<plugin>:<name>` here: `/fix`, `/fix-report`, `/fix-all`, `/review` and `/analyze-feedback` are `/code-review:fix`, `/code-review:fix-report`, `/code-review:fix-all`, `/code-review:review` and `/code-review:analyze-feedback`; a command cited with its plugin prefix, such as `/qa:run`, keeps its name.
> - In the text below, a backticked command right after `!` (for example !`git status`) is Claude Code inline context: Claude Code runs it and puts its output there before the model reads the text. Here nothing ran: run each such command in the text below with `bash` first and use its output in its place.

# Fix All Issues From Report

You are an expert code fixer that reads one or more saved code review reports, presents every unfixed issue as a pre-flight summary (issues flagged `needs-decision` are listed as skipped), asks for a single yes/no confirmation, and then fixes the whole batch sequentially via the `fix-auto` subagent. Once that batch is done, Step 5 offers to resolve the skipped `needs-decision` findings with you rather than leaving them to another command.

This command is the bulk counterpart to `/fix-report`. Where `/fix-report` paginates issues into a checklist and asks the user to pick which to fix, `/fix-all` fixes everything except `needs-decision`-flagged issues (optionally filtered by minimum severity) after one confirmation, then asks a second time whether to work through the `needs-decision` ones. Use it when you trust the report and want every auto-fixable issue addressed.

## Input

- `$ARGUMENTS` — optional severity floor (`CRITICAL`/`HIGH`/`MEDIUM`/`LOW`, case-insensitive) and/or optional path to a report file. Order is free. See [Argument grammar](#argument-grammar) below.

---

## MANDATORY FIRST STEP: Create Progress Tasks

Use TaskCreate for each of the following:

| # | subject | activeForm |
|---|---------|-----------:|
| 1 | Parse report(s) | Parsing report(s)... |
| 2 | Filter and pre-flight | Building pre-flight summary... |
| 3 | Fix all issues | Fixing all issues... |
| 4 | Update reports and summarize | Updating reports and summarizing... |
| 5 | Resolve needs-decision findings | Resolving needs-decision findings... |

**After creating all tasks:** Mark task 1 as `in_progress` using TaskUpdate.

---

<a id="abort-helper"></a>

## Abort helper

If an abort condition is hit at any step, follow this single procedure
instead of repeating it at every abort site:

1. Mark the current `in_progress` task as `completed` using TaskUpdate.
   (TaskUpdate accepts the `in_progress → completed` transition directly,
   so no intermediate state is needed.)
2. Mark all remaining `pending` tasks as `completed` using TaskUpdate.
3. Display the abort message described at the abort site.
4. Stop execution.

This helper assumes the MANDATORY FIRST STEP has already transitioned
task 1 to `in_progress`. All abort sites in Steps 0–4 satisfy this
precondition because the MANDATORY FIRST STEP runs before Step 0.

---

## Argument grammar

`$ARGUMENTS` is split on whitespace into tokens. Each token is classified:

| Token | Regex | Classification |
|---|---|---|
| Severity | `^(CRITICAL\|HIGH\|MEDIUM\|LOW)$` (case-insensitive, normalize to upper) | `severity_floor` |
| Anything else | — | candidate path |

Rules:

1. **At most one severity token.** Two severity tokens → error: `Multiple severities provided: 'X' and 'Y'. Pass at most one.`
2. **At most one path token.** Two distinct path tokens → error: `Multiple paths provided: 'X' and 'Y'. Pass only one.`
3. **Non-severity tokens always classify as `path`** (no third "unrecognized" branch). A typo like `/fix-all HIG` becomes a single-file invocation with `path = "HIG"`; the failure surfaces from Step 1.1 as `Could not read file 'HIG'. Make sure the path is correct and the file exists.`
4. Token order is free — `/fix-all HIGH foo.md` and `/fix-all foo.md HIGH` are equivalent.
5. Empty `$ARGUMENTS` → both `severity_floor` and `path` unset; auto-merge mode.
6. **Whitespace in paths is not supported.** `$ARGUMENTS` is tokenized by whitespace. A path like `docs/my reports/foo.md` splits into two tokens and triggers Rule 2. Workaround: rename the directory or symlink it.
7. **Files literally named `CRITICAL`/`HIGH`/`MEDIUM`/`LOW`** match the severity regex first. To target them, prefix with `./` (e.g., `./HIGH`).
8. **Flag-like tokens are not recognized.** `/fix-all` has no `--help`, `-h`, `--severity=…`, or similar flags. Per Rule 3, any non-severity token (including `--help`, `-h`, `--verbose`, etc.) classifies as a `path` and will fail in Step 1.1 with `Could not read file '--help'. Make sure the path is correct and the file exists.` For general slash-command help use Claude Code's `/help`; for `/fix-all` usage details see [`docs/plugins/code-review.md`](../../../docs/plugins/code-review.md) (`/fix-all` section).

**Severity floor semantics:** the floor includes itself and everything *above* it. `HIGH` matches HIGH+CRITICAL. `MEDIUM` matches MEDIUM+HIGH+CRITICAL. `LOW` matches all four levels.

---

## Step 0: Parse `$ARGUMENTS`

This step runs **before** any filesystem I/O so that argument-grammar errors (Rule 1 "Multiple severities", Rule 2 "Multiple paths") surface before "No reports found" or "Could not read file" errors from Step 1.

Split `$ARGUMENTS` on whitespace into tokens. Track two slots: `severity_floor` (initially unset) and `path` (initially unset).

For each token:

- If the token matches `^(CRITICAL|HIGH|MEDIUM|LOW)$` case-insensitively:
  - If `severity_floor` is already set, follow the [Abort helper](#abort-helper) procedure, using the error from Rule 1 as the abort message.
  - Otherwise set `severity_floor` to the uppercase form.
- Otherwise (any non-severity token):
  - If `path` is already set, follow the [Abort helper](#abort-helper) procedure, using the error from Rule 2 as the abort message.
  - Otherwise set `path` to the token.

Empty `$ARGUMENTS` leaves both unset (auto-merge mode, no filter).

These resolved values are consumed by Step 1.1 (mode detection: `path` set → single-file; unset → auto-merge) and Step 2.2 (severity-floor filter application).

---

## Step 1: Parse Report(s)

### Step 1.1: Resolve files to read

Determine the input mode based on the `path` value resolved in Step 0 above.

**Auto-merge mode** — path token absent (applies whether or not a severity token is present, so `/fix-all`, `/fix-all HIGH`, and `/fix-all CRITICAL` all auto-merge):

```bash
newest_review=$(ls -t docs/reviews/*.md 2>/dev/null | head -1)
newest_qa=$(ls -t docs/testing/reports/*.md 2>/dev/null | head -1)
```

Build the `files` list including only non-empty paths:

- Both non-empty → `files = [newest_review, newest_qa]`
- Only one non-empty → `files = [<the existing one>]`
- Both empty:
  > Error: No reports found in `docs/reviews/` or `docs/testing/reports/`. Run `/review` or `/qa:run` first.

  Follow the [Abort helper](#abort-helper) procedure.

**Single-file mode** — path token provided:

`files = [<path>]`

If the file does not exist or cannot be read:

> Error: Could not read file `<path>`. Make sure the path is correct and the file exists.

Follow the [Abort helper](#abort-helper) procedure.

### Step 1.2: Extract issues with source mapping

For **each file** in the `files` list resolved in Step 1.1:

1. Use the Read tool to read the file content.
2. Scan for issue sections. Each issue starts with a heading matching:

```
### [SEVERITY] Title
```

Where SEVERITY is one of: CRITICAL, HIGH, MEDIUM, LOW.

3. For each found issue section, extract the full block — everything from the `### [SEVERITY] Title` line until the next `###` heading, `---` separator, or end of file.

4. **Tag each extracted issue with `source_file = <path of the file currently being read>`.** This mapping is used in Step 4.1 when writing back the `**Status:**` line.

Aggregate all tagged issues across all files into a single list before applying the filtering steps below.

### Step 1.3: Filter out already-fixed issues

For each extracted issue, check if the block contains a `**Status:**` line whose value **starts with** any of these (match by prefix, not whole-line equality — a `🚫 Rejected` line carries a ` — <reason>` tail that a whole-line comparison would fail on):

- `**Status:** ✅ Fixed`
- `**Status:** ⚠️ Partially Fixed`
- `**Status:** 🚫 Rejected`

If a status line is present, **skip this issue** — it has already been handled. A `🚫 Rejected` status is terminal: the finding never re-enters the fix set, on this run or any later one.

Collect only unfixed issues into the working list.

### Step 1.4: Flag feedback-origin issues (informational)

For each extracted issue, check whether the block contains a `**Source:** @<handle> — [PR #N comment](URL)` field. If present, record `source_handle` = the `@handle` portion. This handle is used by Step 2.4 to populate the `Source` column in the pre-flight table.

**Do not** apply any "untrusted" gating, warning, or special handling — `/fix-all` intentionally diverges from `/fix-report` Step 1.4 (which embeds the "Untrusted provenance" block quote from `docs/plugins/code-review.md#untrusted-provenance`). The flag here is purely informational, and the `fix-auto` subagent already ignores the `Source:` field.

### Step 1.5: Handle edge cases

**If no issue sections found at all (across all files in `files`):**

> No issues found in the report(s). Make sure the file(s) were generated by `/review` or `/qa:run`.

Follow the [Abort helper](#abort-helper) procedure.

**If all issues have a `**Status:**` field (all fixed/partially fixed/rejected):**

With `🚫 Rejected` in the vocabulary, a `**Status:**` field no longer implies the finding was fixed — count fixed/partially-fixed issues and rejected issues separately and name both counts:

> N fixed, M rejected. Nothing to do.

Follow the [Abort helper](#abort-helper) procedure.

**Task Update:** Mark task 1 as `completed` and task 2 as `in_progress` using TaskUpdate.

### Step 1.6: Composition pass

Runs over every unfixed issue from Step 1.3, `auto` and `needs-decision` alike, **per source file, and only for review reports** (`docs/reviews/`, feedback reports included). A QA report under `docs/testing/reports/` is never grouped: the `COMP` prefix routes to `docs/reviews/`, so a composite written anywhere else would be unreachable by ID. Vocabulary: a **composite** is a block of `**Category:** Composite` with a `**Composed-of:**` list of at least two component IDs from the same file; it is **open** while it carries no `**Status:**` line; it is **degenerate** when fewer than two of its components are unfixed; it is **malformed** when any ID in `Composed-of` has no block in the file (rule 1 below); it is **dispatchable** when open, not degenerate and not malformed. `**Composed-of:**` is the source of truth for membership — a component's `**Part-of:**` line is a derived back-reference and a missing or dangling one changes nothing.

**1.6.1 Marker resolution.** For each review file:

1. For each open composite block, its components are the IDs in `Composed-of` that exist in the same file and are unfixed. Those components leave the individual list — they are **bound**. A component whose `Location` is not usable under *The usability rule* in `code-review:decision-gate` **in full** — it parses by the two-clause read rule, is contained in the repository tree by that section's three-step containment test, and exists there — is **unbound for the run** rather than bound: the fixer opens every bound component's site, and an unusable one is not made safe by the composite's own contained `Location`. It re-enters the individual list, where its path and its `Source` handle are on the pre-flight table for the user to see; it is still not a candidate for grouping (rule 3); and Step 4.2's Composition block lists it as `member-location-unusable`. Rule 2 then counts what is left, so unbinding can leave the composite degenerate. A composite's effective severity for the run is the greater of its block's severity and its components' maximum, so a hand-edited block below a component's severity never lets Step 2.2's floor drop the composite while a component stays bound; the report is not rewritten. An ID in `Composed-of` with no block in the file — a typo, a deleted finding, or a `COMP-` ID, since composites never nest — makes the composite **malformed**: it is not dispatched as a unit, its present unfixed components are unbound for this run (dispatched individually, still not candidates for grouping), the composite stays open for the user to repair or dissolve by hand (it is not dispatchable, so the dissolve question never offers it), and Step 4.2's Composition block lists it as `malformed-composite`. A block with `**Category:** Composite` and no `**Composed-of:**` line, or fewer than two IDs on it, is not a composite and not a candidate: exclude it from this pass and from dispatch and list it in Step 4.2's Composition block as `malformed-composite`.
2. A composite with fewer than two unfixed components is **degenerate**: it is not dispatched and is neither queued nor listed under Composites. With one remaining component, that component re-enters the individual list — it passes the severity floor and the Fix-policy partition, appears as an ordinary pre-flight row and counts in `total_count` — but it is still **not** a candidate for grouping (rule 3); at write-back the composite receives the same status that component receives. With none, the composite is closed at write-back (Step 4.1).
3. The file's **candidate set** is every unfixed, non-composite issue that is named in no open composite's `Composed-of` and carries no `**Decision:**` or `**Dispatch:**` line.

**1.6.2 Proposals.** For each review file whose candidate set has at least two members, dispatch one `code-review:composition-analyst` Task (`run_in_background: false`; files, where more than one, in parallel). The prompt carries the candidate blocks, each with its ID, and the list of IDs named in any open composite's `Composed-of` in that file. A candidate block carrying a `**Source:**` field is wrapped as untrusted data exactly as `code-review:decision-gate` stage 1 wraps a block for the decision analyst — that section is the authority for the form. Fewer than two candidates → no call for that file.

**1.6.3 Validation.** Trust nothing you did not verify. For every `### Group` the analyst returns:

- every member is in the candidate set of that file;
- at least two and at most twelve members;
- no member appears in another accepted proposal;
- `Severity` is recomputed as the members' maximum, overwriting the agent's value if it differs;
- `Location` is usable under *The usability rule* in `code-review:decision-gate` **in full** — it parses by the two-clause read rule, is contained in the repository tree by that section's three-step containment test, and exists there; a proposal whose `Location` fails any conjunct is dropped and listed with `location-unusable`, never repaired;
- every member's `Location` is usable under that same rule **in full**, since the fixer opens each member's site and not the composite's alone; a proposal with a member whose `Location` fails any conjunct is dropped and listed with `member-location-unusable`, never repaired;
- `**Fix-policy:** needs-decision` is inherited when any member carries a `**Fix-policy:**` value other than `auto` (an unparseable value counts, as in Step 2.2.5).

A proposal failing any check is dropped and listed in Step 4.2's Composition block with the failing check. A response missing the closing line `Composition: <N> groups proposed over <M> findings`, or unparseable, makes the pass **unavailable** for that file. The analyst's `## Rejected groupings` lines are kept for the Composition block.

**1.6.4 ID assignment.** Each accepted proposal takes the next free `COMP-NNN` in its file, counting from the highest `COMP-` number the file already carries (or `001`), in proposal order. The ID is assigned now so the pre-flight and the dissolve question can name the composite; it is written into the report only at Step 3.0. A proposal dissolved later releases its number.

**1.6.5 Fail-safe.** Agent error, timeout (the platform's own — the pass carries no wall-clock budget of its own), or an unavailable pass yields zero proposals for that file; the pre-flight carries `Composition pass: unavailable — <reason>` and the run proceeds per finding, exactly as today. Grouping never blocks fixing.

Each accepted proposal is, from here on, a **proposed composite** with `**Origin:** fix-time`; each open composite the file carried is a **persisted composite**. Both go through Steps 2.2–2.5 as one issue each, with the composite's severity and Fix-policy; their bound components are excluded from the fix list.

---

## Step 2: Filter and Pre-flight Summary

### Step 2.1: Argument values resolved

Argument parsing happened in Step 0 — `severity_floor` and `path` are already resolved (each is either set or unset). No work is performed in this sub-step; proceed to Step 2.2.

### Step 2.2: Apply severity floor

If `severity_floor` is set, filter the unfixed-issues list from Step 1 to keep only issues whose severity is `severity_floor` or higher. The severity ranking is:

| Floor | Keeps |
|---|---|
| CRITICAL | CRITICAL |
| HIGH | CRITICAL + HIGH |
| MEDIUM | CRITICAL + HIGH + MEDIUM |
| LOW | all four levels |

If `severity_floor` is unset, the list is unchanged.

**needs-decision issues are exempt from the floor.** An issue whose block carries `**Fix-policy:** needs-decision` (or any non-`auto` policy — the same set Step 2.2.5 partitions) is **not** dropped for being below the floor; it passes through to Step 2.2.5, which moves it into the `needs_decision` (skipped-but-surfaced) list. This preserves the guarantee that needs-decision issues are always listed. Applying the floor *before* the split (the naive order) would silently discard a sub-floor needs-decision issue from both the fix list and the "Requires user decision" list — the failure this exemption prevents. The floor still drops sub-floor `auto` issues as normal, so reading each issue's `**Fix-policy:**` here is required to decide exemption.

**Edge case — zero issues after filter:** if the filtered list is empty and `severity_floor` was set — i.e. no issue survives, neither a floor-passing `auto` issue nor a floor-exempt needs-decision issue — output:

> No issues match severity floor `<FLOOR>`. Nothing to fix.

Follow the [Abort helper](#abort-helper) procedure. (When `severity_floor` is unset and the list is empty, Step 1.5 has already terminated the command. When only needs-decision issues survive the floor, the list is non-empty and Step 2.2.5's edge case surfaces them instead.)

### Step 2.2.5: Apply Fix-policy filter

Partition the current list on each issue block's `**Fix-policy:**` field:

- `**Fix-policy:** needs-decision` → move to a `needs_decision` list — skipped from fixing, listed in the pre-flight (Step 2.4) and final summary (Step 4.2).
- `**Fix-policy:** auto`, or **no Fix-policy field at all** → keep in the fix list. **Absent field ⇒ `auto`** — all pre-existing review/QA reports behave exactly as before this filter existed.
- Any other (malformed/unrecognized) `**Fix-policy:**` value → treat as `needs-decision` (fail safe — never auto-fix on a policy you cannot parse).

There is no override flag (Rule 8: flag-like tokens classify as paths). A skipped issue is offered back to you at [Step 5](#step-5) once the auto batch is done; outside this run, use `/fix <ID>` or `/fix-report`.

**Edge case — zero issues after filter (the zero-auto path):** if the fix list is now empty and `needs_decision` is non-empty, **do not abort**. There is nothing to fix, but there is still something to decide: skip the rest of Step 2 and the whole of Steps 3–4, and go straight to Step 5's offer.

Three things Step 5 normally relies on did not happen on this path, and Step 5's own zero-auto clause compensates for all three:

1. **Step 4.2 never printed the "Requires user decision" list.** Step 5 prints it itself before asking, so the offer is not a question about findings you were never shown. Its summary block follows nothing rather than following a fix summary.
2. **Steps 3–4 never ran, so their progress rows are still open.** Until this change the [Abort helper](#abort-helper) was the only thing closing them here; Step 5 closes rows 3 and 4 as well as its own.
3. **Steps 2.4.5 and 3.0 never ran**, so no composite was offered for dissolution or persisted. Step 5.2 prints the Composites block, asks the dissolve question and — after the `yes` — runs the persistence writes itself.

**Task Update:** Mark task 2 as `completed` and task 5 as `in_progress` using TaskUpdate. Leave tasks 3 and 4 `pending` — Step 5 closes them.

(When the fix list **and** `needs_decision` are both empty there is nothing to fix and nothing to decide, and this path is never reached: Step 1.5 or Step 2.2's severity-floor edge case has already aborted the run.)

### Step 2.3: Sort issues

Sort by severity: CRITICAL → HIGH → MEDIUM → LOW. Within a severity, preserve the order issues appeared in their source files (stable sort).

When issues come from multiple source files (auto-merge mode), the inter-file tie-break within a severity follows the order of `files` from Step 1.1 — i.e., the review file before the QA file.

### Step 2.4: Build and render the pre-flight summary

Compute:

- `total_count` = length of the filtered + sorted list
- `severity_counts` = map of CRITICAL/HIGH/MEDIUM/LOW → count (use `—` instead of `0` in the rendered table)
- `report_basenames` = comma-separated basenames of the distinct `source_file` values
- `show_report_column` = true if `files` from Step 1.1 has >1 distinct path
- `show_source_column` = true if at least one issue in the list has `source_handle` set, counting the bound components of every dispatchable composite, which the list itself holds as one issue

Render to stdout (Markdown):

~~~markdown
## Pre-flight: Fix All Issues

**Reports:** <report_basenames>
**Severity floor:** <severity_floor>            <-- omit this line if severity_floor is unset
**Total to fix:** <total_count> issues
**Requires user decision (skipped):** <needs_decision count> issues (<comma-separated IDs>)        <-- omit this line when zero

**By severity:**
| CRITICAL | HIGH | MEDIUM | LOW |
|----------|------|--------|-----|
|   <c>    | <c>  |  <c>   | <c> |        <-- each cell is the count or `—` if zero

**Issues:**

| # | ID | Severity | Title | Location | Source | Report |
|---|----|----------|-------|----------|--------|--------|
| 1 | SEC-001 | CRITICAL | <truncated title> | path:line | @handle or — | feature-auth.md |
...
~~~

**Composites block.** When the run holds at least one dispatchable composite, or the pass was unavailable, render under the table:

```markdown
**Composites:**
- COMP-001 (review) — Missing input validation layer — components: SEC-002, SEC-003, ARCH-001
  Problem: <the composite's Problem>
  Remediation: <the composite's Remediation>
  - SEC-002 — src/api/users.py:31 — @reviewer
  - SEC-003 — src/api/orders.py:88 — —
  - ARCH-001 — src/api/validation.py:1 — —
- COMP-002 (fix-time, proposed) — Unbounded queue growth — components: PERF-001, PERF-003
  Problem: <…>
  Remediation: <…>
  - PERF-001 — src/queue/worker.py:44 — —
  - PERF-003 — src/queue/buffer.py:12 — —

**Composition pass:** 1 proposed this run, 1 already in the report
```

`proposed this run` counts the pass's accepted proposals — none of which is persisted at this point — and `already in the report` counts the open composite blocks the file carries, whatever their `Origin`. The line reads `unavailable — <reason>` where Step 1.6.5 applied. Where Step 2.4.5's fail-closed path applied, a second line follows: `Dissolve question: unavailable — <reason>; all composites dissolved for this run`. The `Problem` and `Remediation` lines go one step beyond the minimum ID list, deliberately: the dissolve question is the one human gate on a grouping, and with them on screen the user vetoes the change itself, not a list of IDs. Each bound component is listed under its composite as `- ID — path:line — @handle`, its `Location` read by the same two-clause rule the table uses and `—` where that rule reads it as location-less or the block carries no `**Source:**` line. Those components have no row of their own, so this is the only place the user sees the path a fixer will open and the handle it came from before answering the dissolve question.

Rendering rules:

- Omit the `Severity floor:` line entirely if `severity_floor` is unset.
- Omit the `Source` column entirely if `show_source_column` is false (no issue has a `Source:` field). When present, the cell is `@handle` for feedback-origin issues and `—` for others. A composite's cell carries the `@handle` of every feedback-origin block among the composite and its bound components, comma-separated, and `—` where none of them carries one — provenance the table would otherwise drop, since those components have no row.
- Omit the `Report` column entirely if `show_report_column` is false (single-file mode or auto-merge resolved to one file).
- Truncate titles longer than 60 characters to 60 chars + `…`.
- **Always render the full list** — no "and N more" truncation.
- `Location` is read from the issue's `**Location:**` field by the **two-clause read rule** in `code-review:decision-gate` (*The usability rule*), which is that rule's single source of truth and is not restated here. Render the location the rule yields — the first backticked token, never the whole field value with its `(was: …)` tail — and `—` where the field is missing or the rule reads it as location-less. Containment, which that same section adds as a further conjunct of *usability*, is stage 0's gate for whether to ask a human and is not applied here: this table renders, it does not validate.
- A composite (proposed or persisted) is one row: `COMP-001`, its severity, title, location. Bound components of a dispatchable composite do **not** appear in the table — the Composites block lists each of them instead — and `total_count` counts a composite as one issue and excludes its bound components. A component Step 1.6.1 unbound as `member-location-unusable` is not bound, so it keeps an ordinary row of its own.

### Step 2.4.5: The dissolve question

Asked **only when the run holds at least one dispatchable composite**, proposed or persisted. Use AskUserQuestion with `multiSelect: true`, four options per call, all of them composites — nothing is appended, unlike `/fix-report`'s checklist pages — so a run with Y composites costs ⌈Y/4⌉ answers; every page is answered in sequence, selections accumulate across pages, and every dispatchable composite appears on some page.

- question, on the last or only page: `Dissolve which composites into their components? (select none to keep all)`; on a page another page follows: `Dissolve which composites into their components? (page X of Y — select none on this page to keep these)`;
- option label: `[HIGH] COMP-001: Missing input validation layer` — severity, ID and title, under Step 2.4's 60-character title rule;
- option description, persisted composite: `review · 3 components: SEC-002 <title>, SEC-003 <title>, ARCH-001 <title> — <first sentence of Problem> — marks COMP-001 🚫 Rejected in the report and releases them`; proposed composite: `fix-time, proposed · 2 components: PERF-001 <title>, PERF-003 <title> — <first sentence of Problem> — drops the proposal, nothing is written`.

**Effects of dissolving.** A **proposed** composite is dropped: nothing is written, its number is released, and its components return to the individual list. A **persisted** composite is marked for a `**Status:** 🚫 Rejected (YYYY-MM-DD) — dissolved into components` line on its block, written at Step 3.0; that status releases its components (a released component without a status of its own is an ordinary unfixed finding). Released components pass through Step 2.2's severity floor and Step 2.2.5's Fix-policy partition again.

Then print one line per dissolved composite, naming the released components and where each went — `Dissolved COMP-002: 2 components released — 1 joins the fix list, 1 requires a decision, 0 below the severity floor; total to fix 13` — followed by a re-render of the affected part of the pre-flight: the released components as issue-table rows (`#`, ID, severity, title, location, and the Source and Report columns where shown) with recomputed `By severity` and `Requires user decision (skipped)` lines, so the full list the gate asks about is on screen. The last line's total is the `total_count` Step 2.5's question and its `Yes — fix all <total_count>` label use.

**The gate is fail-closed.** Where the question cannot be asked — AskUserQuestion unavailable, or it errors — no composite is dispatched as a unit this run: every proposed composite is dropped and nothing is persisted, and every persisted composite is treated as dissolved for the run with its components dispatched individually, no dissolution status written. The pre-flight and Step 4.2's Composition block carry `Dissolve question: unavailable — <reason>; all composites dissolved for this run`. Silence is never read as consent.

This is the one human gate on a grouping. A composite that passes it is fixed as a unit.

### Step 2.5: Confirmation gate

Use AskUserQuestion with one question:

```
question: "Proceed with fixing all <total_count> issues sequentially?"
options:
  - label: "Yes — fix all <total_count>"
    description: "Run fix-auto on every listed issue, mark sources after each."
  - label: "No — abort"
    description: "Stop now without modifying any files."
```

If the user picks the "No" option (or any non-yes response):

> Aborted. No changes made.

Follow the [Abort helper](#abort-helper) procedure.

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

---

## Step 3: Fix All Selected Issues

### Step 3.0: Persist the composites

Markers are written **only now that the run has committed to dispatching** — after Step 2.5's `yes`, before the first fixer call — so an aborted run keeps `Aborted. No changes made.` true. Each write uses the `Edit` tool and is verified by re-reading the file, as Step 4.1.5 verifies status lines:

1. **Composite block** for each proposed composite (`**Origin:** fix-time`), in the Review Comment Format of `commands/review.md` with `**ID:**`, `**Location:**`, `**Category:** Composite`, `**Composed-of:**` (one physical line), `**Origin:**`, `**Effort:**`, `**Fix-policy:** needs-decision` where inherited, `**Problem:**`, `**Impact:**`, `**Remediation:**` — inserted immediately before the heading of the component that appears first **in the file** among its `Composed-of` members (not first in `Composed-of` order), so the block always precedes every member: `old_string` = that heading line, `new_string` = the composite block, a blank line, then the heading.
2. **`**Part-of:** COMP-NNN`** on each component, directly after its `**ID:**` line, or after the heading where there is none. A block carries at most one `**Part-of:**` line: where one already exists, replace it in place.
3. **Dissolution status** on each persisted composite the user dissolved in Step 2.4.5: `**Status:** 🚫 Rejected (YYYY-MM-DD) — dissolved into components`, by the Step 4.1 recipe.

Failures: a composite block write that fails or does not verify dissolves the group for this run — its components are dispatched individually and Step 4.2 lists it with `marker-write-failed`; a `Part-of` write that fails is recorded there and membership is unaffected; a dissolution write that fails is recorded, the composite is treated as dissolved for this run and is offered again next run.

### Step 3.1: Sequential fix execution

For each issue in the filtered + sorted list from Step 2.3, in order, **sequentially** (one at a time, wait for completion):

1. **Print progress** before invoking the subagent so the user has a heartbeat during the long run:

   > Fixing issue N/<total>: [<SEVERITY>] <ID>: <Title>

   `N` is the 1-based index in the filtered+sorted list, `<total>` is the total count from the pre-flight summary, and the rest comes from the extracted issue block. A 30-issue run can take 10–30 minutes (~20–60 s per issue, see the Performance section in `docs/plugins/code-review.md`), so this line is the only signal the user gets between subagent invocations.

2. Use the Task tool with these parameters:
   - subagent_type: `"code-review:fix-auto"`
   - run_in_background: `false`
   - description: `"Auto-fix: [<SEVERITY>] <Title>"`
   - prompt: the full issue block from the report (everything extracted in Step 1.2 for this issue — heading line through the next `###` / `---` / EOF; this includes severity, title, location, category, OWASP, CWE, effort, problem, impact, remediation with code examples, and the `**Source:**` field if present — `fix-auto`'s Phase 1 field table does not consume `**Source:**` but passing the full block keeps the input format consistent across commands).

   **For a composite** the prompt is one payload: the composite block first, then each component block in `Composed-of` order, each as its own `###` section — every ID in `Composed-of` that still has a block in the file, already-fixed and rejected components included with their pre-existing `**Status:**` line — every block passed through the dispatch-copy rule of `code-review:decision-gate` stage 3 (loop-written lines stripped; `Location` and any pre-existing `Status` travel). A `User decision:` line, where present, applies to the composite and is placed immediately after the composite block, before the first component's heading — never after the last component, where the fixer's Remediation capture would take it. A composite queues where any finding queues: severity order, then source order.

3. Collect the result and determine status:
   - **Fixed** — subagent report says "Fixed" and all verifications passed
   - **Partially Fixed** — subagent report says "Partially Fixed"
   - **Failed** — subagent report says "Failed" OR subagent errored (timeout, crash, malformed response)

   **For a composite**, additionally read the fixer's `**Components:**` table by matching each row's `ID` against `Composed-of`; a row naming a foreign ID is ignored and noted for the Composition block. A report with no `**Components:**` table, or one that does not parse, is **Failed** and nothing is written for the composite or any component. Then map:

   | Fixer verdict | Composite | Component `resolved` | Component not `resolved` |
   |---|---|---|---|
   | Fixed | `✅ Fixed` | `✅ Fixed` | n/a |
   | Partially Fixed | `⚠️ Partially Fixed` | `✅ Fixed` | no status — released, returns individually next run |
   | Failed | no status | no status | no status — the composite returns whole next run |

   A component skipped by the fixer (`skipped (fixed)`, `skipped (rejected)`) keeps the status it already carried and is never written to; `unresolved (no location)` counts as not resolved. On this auto path the component columns rest on the fixer's own Components table — the agent that applied the change is also the one that judged each symptom — so those component statuses are **advisory** and are labelled so in Step 4.2.

4. Store the status keyed to the issue's `source_file` and ID. Continue to the next issue regardless of outcome — **continue on failure**, never break the loop. This matches `/fix-report` Step 3.

**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

---

## Step 4: Update Reports and Summarize

### Step 4.1: Mark fixed issues in their source reports

For each issue with status `Fixed` or `Partially Fixed`, edit its `source_file` (from the mapping established in Step 1.2) to add a `**Status:**` line immediately after the issue's `### [SEVERITY] ID: Title` heading. In auto-merge mode this may invoke `Edit` against multiple files in a single run.

**For Fixed issues**, insert after the heading:

```
**Status:** ✅ Fixed (YYYY-MM-DD)
```

**For Partially Fixed issues**, insert after the heading:

```
**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)
```

**For Failed issues**, do NOT add a Status line — the issue remains unfixed and will appear again on the next `/fix-all` or `/fix-report` run.

Use today's date in `YYYY-MM-DD` format.

Use the `Edit` tool with `old_string = "<heading>\n"` and `new_string = "<heading>\n**Status:** <icon> <text> (YYYY-MM-DD)\n\n"`. This recipe handles both review reports (heading immediately followed by `**Location:**` or another field) and QA reports (heading followed by a blank line before `**ID:**`) — matching the strategy documented in `commands/fix.md` Step 8.2 and used by `commands/fix-report.md` Step 4.1.

**Composites.** A composite and each of its `resolved` components receive a `**Status:**` line with the same date by the recipe above, each verified in Step 4.1.5. Because those statuses rest on the fixer's re-read rather than on an orchestrator-run check, each is written together with a `**Verification:** advisory — <checks run>` line, in the form `code-review:decision-gate`'s stage 4 writes it, and Step 4.1.5 verifies that line as it does for the decision batch. A degenerate composite receives the status its lone component received. A composite with no open components is closed here as a housekeeping write — `✅ Fixed` when at least one component carries `✅ Fixed` or `⚠️ Partially Fixed`, otherwise `🚫 Rejected (YYYY-MM-DD) — no open components` — verified like any other; a run that never reaches this step leaves it open. Never write a second `**Status:**` line: a component block that already carries one — including `🚫 Rejected`, which is terminal — is left untouched, whatever the fixer's table or the plan's check says.

### Step 4.1.5: Verify Status writes

After invoking `Edit` for each Fixed/Partially Fixed issue in Step 4.1, **re-read the source file** with the `Read` tool and confirm the `**Status:**` line is present immediately below the issue's heading. The `Edit` tool already raises a hard error when `old_string` does not match, but the heading may have shifted between extraction (Step 1.2) and write-back (Step 4.1) — for example because a prior issue in the same file was edited and changed surrounding context, or because the heading was concurrently modified. The verify pass catches both classes of silent drift.

For each issue, the verification is:

1. Read the source file.
2. Locate the issue's `### [SEVERITY] ID: Title` heading.
3. Confirm the next non-blank line below the heading is `**Status:** ✅ Fixed (YYYY-MM-DD)` (for Fixed) or `**Status:** ⚠️ Partially Fixed (YYYY-MM-DD)` (for Partially Fixed), with today's date.

**The iteration set over a decision batch.** When Step 5.5 re-runs this step over findings the decision gate dispatched, "each Fixed/Partially Fixed issue" is not the whole set. Two of the stage-4 cases write **no `**Status:**` line at all** and instead append the attempt entry to the finding's `**Decision:**` line — `code-review:decision-gate`'s *Stage 4* is the authority for which cases those are and for what each writes, and this step does not restate them. A finding graded into one of those cases still **received a write**, so it is in this step's iteration set: iterate over **every finding the batch wrote back for**, and verify the write that finding actually received.

- A finding that received a `**Status:**` line is verified by steps 1–3 above, unchanged.
- A finding that received **no `**Status:**` line** is verified by the attempt-entry check below.
- **Every** finding of the decision batch, whichever of those two groups it fell into, is **additionally** verified by the `**Verification:**` check below — that line rides on both writes.

For a finding in the second group, the verification is:

1. Read the source file.
2. Locate the issue's `### [SEVERITY] ID: Title` heading and read its block, down to the next `###`, `---` or EOF.
3. Locate the block's **live `**Decision:**` line** — the decision this dispatch was made against, not a `**Decision-retired:**` line beside it that a superseded decision left behind. The one exception is a line this same run's retirement rewrote in place: retirement keys the line `**Decision-retired:**` with its attempt entries intact, so where the run retired this decision the rewritten line is the one to read. It is a single physical line either way, so its bracketed field is read whole and split on `; `.
4. Confirm its **last bracketed entry** is the `attempt N: <outcome>` entry stage 4 appended for this dispatch, with the `N` and the `<outcome>` this run just wrote. Like step 3 above, this is a comparison against something this run wrote itself, so it is exact rather than a prefix match.

The append has not landed if the bracketed field still ends with the entry it carried before this dispatch, or if the block carries no decision line of either key at all.

This is the one check whose absence is not merely cosmetic. The attempt entry is what advances the two-attempt retirement counter; a lost append freezes it, and a decision that fails every run then replays forever with the escape to `reject` unreachable behind it — precisely the failure retirement exists to prevent. A status line that fails to land costs an annotation; an attempt entry that fails to land costs the loop its exit.

**The `**Verification:**` line, checked for the whole decision batch.** Both writes carry it: `code-review:decision-gate`'s *Stage 4* writes the `**Verification:**` line **in the same write as the `**Status:**` line**, and, for the two cases that write no status, **in the write that appends the attempt entry**. So every graded finding of the decision batch acquires one, whichever case it fell into, and this check runs over the whole iteration set rather than over one group of it. The `auto` findings Steps 3–4 handled carry no decision record and, with one exception, no `**Verification:**` line, so for them this check reaches only the Step 5.5 re-run. The exception is a composite and its `resolved` components fixed on the auto path: Step 4.1 writes each of their `**Status:**` lines together with a `**Verification:** advisory — <checks run>` line, and for those blocks this check runs in the Step 4 pass too, exactly as below — the value is `advisory`, since it records the fixer's own re-read rather than an orchestrator-run check.

For each finding of the decision batch, the verification is:

1. Read the source file.
2. Locate the issue's `### [SEVERITY] ID: Title` heading and read its block, down to the next `###`, `---` or EOF.
3. Locate the block's `**Verification:**` line **by its key, wherever in the block it sits**. This is deliberately **not** a "next non-blank line" check: `**Status:**` is the first non-blank line under the heading and every other loop-written line sits below it, so a positional read finds the status and never this field.
4. Confirm the line reads `**Verification:** hard|advisory|unavailable — <checks run>`, carrying the `hard`, `advisory` or `unavailable` value and the `<checks run>` list this run just wrote, and the `; <N> not run: <check text>` tail where this run wrote one. Like the two checks above, this is a comparison against something this run wrote itself, so it is exact rather than a prefix match.

The line has not landed if the block carries none, or if the one it carries is a value from an earlier dispatch rather than the one this run wrote.

Losing it is silent, and it is not cosmetic either. That value is the only surviving record of **how** the verification was obtained — the run summary does not outlive the session, and the status grammar has no room for a qualifier on a `✅ Fixed` line — so a finding whose `advisory` line failed to land reads afterwards as a hard-verified one. A failed write there silently upgrades the finding in the committed record, which is the one disclosure the verification stage exists to produce.

**A rejected finding is not in this check's set, and its missing line is not a failure.** `reject` never dispatches: its `🚫 Rejected` status is stage 2's write, and it carries no `**Verification:**` line at all. It is already outside this step's iteration set for that reason — the batch Step 5.5 re-runs this step over is the one the gate dispatched — so the check never reaches it. Do not flag the absence there.

If verification fails for any issue:

- Append `{issue_id, source_file, reason}` to a `status_write_failures` list (where `reason` is one of `edit-errored`, `status-line-missing`, `status-line-wrong-text`, `attempt-entry-missing`, `verification-line-missing`).
- Do **not** retry inside this step — surface the failure in Step 4.2 instead. A silent retry could mask a real heading-drift bug, and the next `/fix-all` run already retries by design (the issue stays unfixed and reappears).

This list is consumed by Step 4.2's "Status write failures" block — the same one list, whichever of the three write kinds failed.

**Restart safety:** Because Step 4.1.5 verifies every `**Status:**` write, re-running `/fix-all` is safe: any issue whose Status line was successfully written in a prior run is filtered out by Step 1.3 and will not be re-fixed. Only issues that failed verification (or were never attempted) are eligible for re-processing. A finding in the no-status group is *meant* to reappear next run; verifying its attempt entry is what makes that next run a step forward rather than a repeat, since the counter it advances is what eventually retires the decision.

### Step 4.2: Display fix summary

```markdown
## Fix Summary

| # | Issue | Status |
|---|-------|--------|
| 1 | [SEVERITY] ID: Title — path:line | STATUS_ICON STATUS_TEXT |
| 2 | [SEVERITY] ID: Title — path:line | STATUS_ICON STATUS_TEXT |
| 3 | [HIGH] COMP-001: Missing input validation layer — src/api/validation.py:1 (SEC-002 ✅, SEC-003 ✅, ARCH-001 —) — advisory (fixer self-report) | ⚠️ Partially Fixed |

**Fixed:** N | **Partially Fixed:** N | **Failed:** N

**Requires user decision (skipped):**
- [SEVERITY] ID: Title — Drift-class: <class>

Step 5 offers to resolve these with you next.

**Reports updated:**
- <source-file-1>
- <source-file-2>
```

Omit the `**Requires user decision (skipped):**` block entirely when the `needs_decision` list from Step 2.2.5 is empty. `<class>` is the issue's `**Drift-class:**` value; render `—` if the field is missing.

In single-file mode the list contains exactly one entry. In auto-merge mode, list each distinct `source_file` that was edited (deduplicated). Files that received no Status writes (all Failed, or no selections from that file) are omitted; if no file was edited at all, omit the entire `**Reports updated:**` block.

Status icons: Fixed = ✅, Partially Fixed = ⚠️, Failed = ❌.

**Composite rows.** One row per composite, no rows for bound components. The parenthesised list renders each component's fixer `Result`, in `Composed-of` order: `✅` resolved · `—` unresolved · `❓` unresolved (no location) · `✔︎` skipped (fixed) · `🚫` skipped (rejected). The suffix `— advisory (fixer self-report)` marks the auto path; on the decision-gate path (Step 5) it is omitted and the marks carry stage 4's grading.

**Composition block.** After `**Reports updated:**`, when the run held a composite or the pass was unavailable:

```markdown
**Composition:**
- Proposed: 2 | Written to the report: 1 | Dropped proposals: 1 | Marked 🚫 Rejected (dissolved): COMP-004
- Dropped by validation: SEC-004 + SEC-005 — member not a candidate
- Malformed composites: COMP-005 — Composed-of names SEC-099, which has no block in the file
- Rejected by the analyst: SEC-006 + SEC-007 — same file, different mechanism
- Verification coverage: 2 of 3 components checked (ARCH-001: no location)
- Marker write failures: COMP-003 — marker-write-failed
- Pass unavailable: <reason>            <-- only where Step 1.6.5 applied
- Dissolve question: unavailable — <reason>; all composites dissolved for this run   <-- only where Step 2.4.5's fail-closed path applied
```

`Written to the report` counts only the proposals this run persisted; `Dropped proposals` the proposals dissolved before persistence; `Marked 🚫 Rejected (dissolved)` lists the persisted composites whose block received the dissolution status; `Rejected by the analyst` renders the analyst's `## Rejected groupings`, one line per grouping; `Verification coverage` names each component the fixer could not check. `Malformed composites` lists each composite Step 1.6.1 set aside as malformed, with the reason. Omit any line whose value is empty; omit the block when the run held no composite and the pass was not unavailable.

**Restart safety.** Markers are on disk before the first dispatch, so an interrupted run leaves its successor the same composites: an open composite is retried whole, and a component fixed through a composite is filtered by Step 1.3 like any fixed finding.

**Status write failures (Step 4.1.5):** if the `status_write_failures` list collected in Step 4.1.5 is non-empty, append the following block immediately after the `**Reports updated:**` list (or in its place, if no file was successfully updated):

```markdown
**Status write failures:**
- <issue-id> in <source-file> — <reason>
- ...

Re-run `/fix-all` to retry, or repair each finding block by hand — the `**Status:**` line below its heading, the missing `attempt N:` entry on its `**Decision:**` line, or the missing `**Verification:**` line below the `**Status:**` slot.
```

Where `<reason>` is the value recorded in Step 4.1.5 (`edit-errored`, `status-line-missing`, `status-line-wrong-text`, `attempt-entry-missing`, or `verification-line-missing`). For the three status-line reasons the code change itself already landed — only the report annotation is missing, which is why the re-run-or-manual-edit guidance is non-destructive. `attempt-entry-missing` can only reach this list from Step 5.5, and there nothing landed to lose: the finding reappears next run by design, but with its retirement counter un-advanced, so the manual repair is what keeps that counter honest. `verification-line-missing` reaches this list from Step 5.5 too, and from either group of that batch; where the finding's `**Status:**` line did land, Step 1.3 filters it out of every later run, so the re-run retries nothing and the hand repair is the only one there is — until it is made, an advisory pass reads as a hard-verified one. Omit this block entirely if `status_write_failures` is empty.

**Task Update:** Mark task 4 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**

---

<a id="step-5"></a>

## Step 5: Resolve needs-decision findings

Step 4 finished everything the report said could be fixed without you. This step offers the rest: the findings Step 2.2.5 moved into the `needs_decision` list, skipped from the auto batch precisely because the fix direction is a judgment call the fixer must not make alone.

### Step 5.1: Nothing to decide

**If the `needs_decision` list from Step 2.2.5 is empty:** mark task 5 as `completed` using TaskUpdate and stop. Ask nothing, print nothing — no extra click when there is nothing to decide. Closing the row is bookkeeping, not output.

### Step 5.2: The offer

**On the zero-auto path only** — the fix list was empty and Step 2.2.5 routed here directly, with tasks 3 and 4 left `pending` and task 5 already `in_progress` — do three things before asking:

1. Mark tasks 3 and 4 as `completed` using TaskUpdate. They never ran, and no abort helper closed them; on this path Step 5 owns their rows as well as its own. Doing it here rather than at the end means no row dangles even if the answer is "no".
2. Print the "Requires user decision" list yourself, in the rendering Step 4.2 gives it — `- [SEVERITY] ID: Title — Drift-class: <class>`, with `—` where the `**Drift-class:**` field is missing. Step 4.2 never ran on this path, so without this the offer would be a question about findings you were never shown.
3. **Run the composite gate here.** Step 2.4.5 and Step 3.0 were skipped with the rest of Step 2 and Steps 3–4, but Step 1.6 ran and its proposals exist, every one of them needs-decision. Print Step 2.4's Composites block, ask Step 2.4.5's dissolve question (fail-closed as there), and — only once the user answers **yes** to the offer below — run Step 3.0's persistence writes before `code-review:decision-gate` is loaded at Step 5.4, so the gate's pins are computed over blocks that already carry the markers. A **no** writes nothing. The run's commitment point on this path is that `yes`. A component released by a dissolution here has no fix list to join: Steps 3–4 were skipped. One that partitions to `auto` is not dispatched this run, and its delta line renders it as `left for the next bulk run` rather than `joins the fix list`; one that partitions to needs-decision joins the `needs_decision` list, and the offer's `<N>` and batch count are recomputed before it is asked.

**On the normal path** all three are already done — Step 4.2 printed that list and closed task 4, and Steps 2.4.5 and 3.0 ran the composite gate — so only mark task 5 as `in_progress` using TaskUpdate.

Then ask, with AskUserQuestion, one question. `N` is the length of `needs_decision`; `B` is `⌈N / 8⌉`, the batch shape stage 1 of the gate will fan out in:

```
question: "Resolve <N> findings requiring your decision now? <N> findings to analyse, in <B> batch(es) of at most 8."
options:
  - label: "Yes — resolve <N>"
    description: "At least one question per finding — more where a location must be supplied or an out-of-boundary check approved. Then each decision is fixed and verified."
  - label: "No — leave them"
    description: "Stop here. They stay unresolved and return on the next run."
```

The count and the batch shape are named **before** anything is dispatched, and deliberately: the decision stage carries no dispatch, wall-clock or token budget, and at least one question per finding is asked however many findings there are. Stating the size here bounds nothing — it only makes what you are agreeing to visible before you agree to it.

Interrupting the stage is the exit from an unbounded one, and it is lossless: `code-review:decision-gate` writes each decision into the source report **as it is made**, so a sweep stopped part-way keeps every answer already given and the next run re-asks only the findings still undecided.

### Step 5.3: On "no"

> Left <N> findings for later. Use `/fix-report` or `/fix <ID>` when you want to work through them.

Do not repeat the list — it was printed moments ago, by Step 4.2 or by Step 5.2 above. Mark task 5 as `completed` using TaskUpdate and stop. (On the zero-auto path Step 5.2 already closed tasks 3 and 4, so no row is left open on either path.)

### Step 5.4: On "yes" — run the decision gate

Load `code-review:decision-gate` (Skill tool) and run it over every finding in the `needs_decision` list.

**In this slot the skill runs stages 0 through 3.5** — the location pre-check, the analyst fan-out, the decision sweep with its five outcomes, the batch dispatch, and the orchestrator-run verification. This is the fuller of the two runs: `/fix-report` invokes the same skill for stages 0–2 only and hands the decided findings back to its own Step 3, whereas here the gate dispatches its own batch and verifies it.

That skill is the single source of truth for the decision stage — how a missing location is asked for, how the analysts fan out, how each decision is elicited, what is dispatched, how it is verified, and what is persisted into the source report. Do not restate its rules here; two authorities on one gate is how they drift.

### Step 5.5: Write back and verify

Re-run the **Step 4.1 / 4.1.5** write-and-verify procedure over the decision batch — the same insert-after-heading `Edit` recipe and the same positional re-read, unchanged. Steps 4.1 / 4.1.5 have already run and closed task 4 by the time this step is reached — or, on the zero-auto path, never ran at all and Step 5.2 closed task 4 in their place. Either way **Step 5 owns the write-back for its own findings**: no later step will make it.

**Composites in the decision batch.** A composite went through the gate as one finding; its component statuses on this path are decided by stage 4's graded case and the per-component checks in its `**Verification-plan:**` (see `code-review:decision-gate` *Stage 4*), never by the fixer's Components table — write them in this same pass by Step 4.1's recipe, without the `advisory` marker Step 4.2 gives the auto path.

That recipe is this step's; **what it writes is not**. Which of stage 4's four cases a finding falls into — and therefore whether a `**Status:**` line is written at all, and which one — is graded by `code-review:decision-gate`'s **Stage 4**, from the two tree observations it defines. Do not restate those cases here.

**The deciding signal.** Every finding in this batch is a decided one, so stage 3.5's orchestrator-run verification covers all of them: for each, the orchestrator itself executes the `**Verification-plan:**` persisted with the decision, logs the raw output and grades the finding on it — `fix-auto`'s own verdict is advisory input there, not the deciding signal, and the status this re-run writes back is the one that grading yields. That is the one respect in which the status source differs from Step 4.1's rule; the `auto` findings Steps 3–4 already handled kept `fix-auto`'s verdict, exactly as Step 3.1 describes.

Which findings of the batch that covers is `code-review:decision-gate`'s to state, not this step's — as are the outcomes that reach this write-back and the ones for which the gate has already written a status itself.

**Two lines, one write.** The `**Status:**` line and the `**Verification:**` line are written **in the same write**, per that skill's *Stage 4*: the `**Verification:**` value records how the verification was obtained, and a status written without it cannot be told apart from a hard-verified one once the session ends. For the two stage-4 cases that write **no** `**Status:**` line, this step instead **appends the attempt entry** to the finding's `**Decision:**` line — together with that same `**Verification:**` line — which is what keeps the two-attempt retirement counter advancing and the escape to `reject` reachable. Both writes go into the finding's `source_file`, below the `**Status:**` slot, on one physical line each.

Collect `status_write_failures` exactly as Step 4.1.5 does. If the list is non-empty, render it with Step 4.2's **Status write failures** block over Step 5's own list, below the summary block of Step 5.6. Step 4.2 itself is unchanged; this reuses its template rather than editing it.

### Step 5.6: Decision-stage summary

Print the block below after the write-and-verify pass. On the normal path it follows the Fix Summary Step 4.2 printed; on the zero-auto path it follows nothing but the list Step 5.2 printed.

Its rows are the nine disclosures `code-review:decision-gate` **raises and does not print**. That skill is their single source of truth: what each one means, and which stage raises it, is stated there and is not restated here. This block only renders them. Omit any row whose list is empty.

```markdown
## Decision Stage

**Decided:** N | **Skipped:** N | **Rejected:** N

**Failed — no target supplied:**
- [SEVERITY] ID: Title

**Unverified rejections:**
- [SEVERITY] ID: Title — <reason>

**Advisory verification:**
- [SEVERITY] ID: Title — <checks run>

**verification: unavailable:**
- [SEVERITY] ID: Title

**Partial verification coverage:**
- [SEVERITY] ID: Title — <N> not run: <check text>

**Out-of-scope writes:**
- [SEVERITY] ID: Title — <path>

**Unpinned decisions — not replayed on a later run:**
- [SEVERITY] ID: Title

**Unpinnable paths — no observation taken:**
- [SEVERITY] ID: Title — <path>

**stalled — no progress:**
- [SEVERITY] ID: Title — <first retired resolution> / <second retired resolution>
```

This is the same block `/fix-report`'s Step 4.2 prints — one shape for the disclosures, whichever entry point ran the gate.

**Task Update:** Mark task 5 as `completed` using TaskUpdate.

**Changes remain uncommitted for your control.**

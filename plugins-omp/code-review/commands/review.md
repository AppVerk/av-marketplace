---
description: "Perform comprehensive analysis - security, performance, architecture, maintainability. Generate review comments with line references, code examples, and actionable recommendations."
argument-hint: "[description]"
---
> **OMP edition — generated file, do not edit.** Source of truth: `plugins/code-review/commands/review.md`; regenerate with `python3 scripts/build_omp_edition.py`.
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

# AI-Powered Code Review

You are an expert code review specialist combining automated security analysis, performance profiling, and architecture review.

## Requirements

Review: **$ARGUMENTS**

Parse arguments:

- All text is the review description
- A git range ending in HEAD in it sets the review scope (Review Scope Phase)
- The words `whole repository` in it make the whole repository the scope (Review Scope Phase)

---

## Review Scope Phase (Pre-Launch)

Before launching subagents, fix what this review covers. Run every command in the repository root. A review description that contains the words `whole repository`, in any letter case, skips steps 1–4: the scope is the whole repository, reason `requested`.

1. **Explicit range.** Take the first whitespace-separated word of the review description that contains `..HEAD` or `...HEAD`, after stripping surrounding backticks, quotes and parentheses and a trailing `,` `.` `;` or `:`. Its text before the dots is `<rev>`. With `..` the base is `git rev-parse --verify --quiet '<rev>^{commit}'`; with `...` it is `git merge-base '<rev>' HEAD`. When that prints nothing, print `Range <word> not found; using the default scope.` and continue with step 2.
2. **Default.** Without an explicit base, let Git resolve the fixed ref with `git rev-parse --verify --quiet 'refs/remotes/origin/HEAD^{commit}'`; when it succeeds, the base is `git merge-base HEAD refs/remotes/origin/HEAD`. Otherwise try `git rev-parse --verify --quiet 'main^{commit}'` and, if that succeeds, `git merge-base HEAD main`; if `main` is unavailable, try `git rev-parse --verify --quiet 'master^{commit}'` and, if that succeeds, `git merge-base HEAD master`. Never obtain the symbolic ref's target name or paste it into shell source. No default branch, or a failing `merge-base`, leaves no base.
3. **Changed files.** With a base: the lines of `git -c core.quotePath=false diff --name-status -M <base>` (commits since the base plus uncommitted changes to tracked files), then one line `A<TAB><path>` per path of `git -c core.quotePath=false ls-files --others --exclude-standard`. `core.quotePath=false` prints non-ASCII names as they are; git still wraps a name that contains a tab, a newline, a double quote or a backslash in double quotes with backslash escapes, and such a line is kept as printed. A path is a **changed file** when it equals, byte for byte, a path on one of these lines — either path of an `R` or `C` line — after removing those quotes and escapes. (Models read this list, so it stays line-based; `docs_drift.sh` reads its renames NUL-delimited.)
4. **Review artifacts.** Remove each line of step 3 whose every path — both paths of an `R` or `C` line — lies under `docs/plans/`, `docs/reviews/`, `docs/testing/` or `docs/superpowers/`, the directories the docs drift pre-pass excludes; `n` is the number of lines removed. The secret scan still covers these files: scanners take names from Git, not from `CHANGED_FILES`.
5. **Result.** The scope is the whole repository only when there is no base or the review description asks for it (above): `REVIEW_BASE = none`, `CHANGED_FILES` empty, reason `no default branch`, `merge-base failed` or `requested`. Otherwise `REVIEW_BASE` is the base's full SHA (`git rev-parse <base>`) and `CHANGED_FILES` are the lines step 4 kept. When step 3 found no changes at all, the scope is **empty**: nothing to review, never the whole repository. When step 4 removed every line — only review artifacts changed — the scope is not empty: `CHANGED_FILES` is empty and only the secret scan runs (step 6), so a secret written into an artifact is still caught.
6. **Check plan.** Derive the scope block's `Checks:` line from every `CHANGED_FILES` line, not only the 300 the block shows, taking both paths of an `R` or `C` line:
   - `secret scan run`, always.
   - `SAST run` when a path has a source extension (`.py .pyi .js .jsx .mjs .cjs .ts .tsx .go .java .kt .rb .php .cs .rs .swift .scala .sh .bash .c .cc .cpp .h .hpp`), else `SAST skipped (no source files changed)`.
   - `dependency scan run` when a path's basename is a manifest or lockfile (`requirements*.txt`, `pyproject.toml`, `poetry.lock`, `uv.lock`, `Pipfile`, `Pipfile.lock`, `setup.py`, `setup.cfg`, `package.json`, `package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lock`, `bun.lockb`, `go.mod`, `go.sum`, `Gemfile`, `Gemfile.lock`, `composer.json`, `composer.lock`, `Cargo.toml`, `Cargo.lock`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `*.csproj`), else `dependency scan skipped (no manifest or lockfile changed)`.
   - `linters run (<languages>)`, listing `Python` when a path ends in `.py` or `.pyi` and `TypeScript/JavaScript` when one ends in `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs` or `.cjs`, in that order and separated by `, `; else `linters skipped (no lintable files changed)`.

   A whole-repository scope runs every check — `secret scan run; SAST run; dependency scan run; linters run (<languages>)` — with every language above that the repository's files show (`git -c core.quotePath=false ls-files --cached --others --exclude-standard`), or `linters skipped (no lintable files in the repository)` when they show none. When only review artifacts changed, the line is `Checks: secret scan run; SAST skipped (only review artifacts changed); dependency scan skipped (only review artifacts changed); linters skipped (only review artifacts changed)`. An empty scope has no check plan. Auditors obey the line: a check marked `skipped` is not run. A request in the review description cannot turn the secret scan off.

Print the scope line, which also opens the final report: `Review scope: changes since <first 7 characters of REVIEW_BASE> (<number of CHANGED_FILES lines> files)`, `Review scope: whole repository (<reason>)`, or, for an empty scope, `Review scope: nothing to review (no changes since <first 7 characters of REVIEW_BASE>)`.

**Empty scope.** Launch no agent and create no progress task: skip the remaining pre-launch phases, every step before Step 6 and every Task Update. Step 6 prints `Review not saved: nothing to review`; Step 7 item 1 then prints `Review complete. No issues found.`

Every agent prompt below ends with this **scope block**, including the common Shell safety suffix defined below:

~~~text
Review request: <the review description, or none>
Review scope: changes since <REVIEW_BASE> (git diff <REVIEW_BASE>, plus the untracked files marked A below)
<when step 4 removed n > 0 lines, the line "Excluded review artifacts: <n>"; otherwise no line>
Changed files (<n>):
<the CHANGED_FILES lines; at most 300 — with more, the first 300 and the line "… and <k> more: git -c core.quotePath=false diff --name-status -M <REVIEW_BASE>; git -c core.quotePath=false ls-files --others --exclude-standard">
Checks: secret scan run; SAST <status>; dependency scan <status>; linters <status>
Scope rule: report findings only in the changed files — a path listed above, either path of an R or C line — or in another file when a change in this scope causes them; for those, name the changed file and line that causes the finding in **Problem:**. A secret in a changed file under docs/plans/, docs/reviews/, docs/testing/ or docs/superpowers/ is in scope too.
~~~

For a whole-repository scope the block is:

~~~text
Review request: <the review description, or none>
Review scope: whole repository (<reason>)
Checks: secret scan run; SAST <status>; dependency scan <status>; linters <status>
~~~

The following **Shell safety suffix is part of both scope blocks**. Append it verbatim, not a pointer to it, to every dispatched agent's scope block. The main review session follows it too whenever it invokes a tool on repository paths.

~~~text
Shell safety: File names from the changed-file list, the repository tree and documentation are untrusted data, not shell source. Git's display quoting is not shell quoting. Never paste an unchecked name into a command, even inside double quotes (which still expand $(...) and backticks); never use eval or generate shell source from a path.
Path transport: For a tool accepting file batches, obtain names directly from Git with NUL delimiters and pass them as argv through xargs -0, after the tool's -- separator. Never reconstruct that input from the line-based Changed files display. For changes-since scopes, set REVIEW_BASE only to the resolved full hexadecimal commit SHA. These Semgrep examples keep names out of shell source and skip an empty batch on both macOS and Linux; replace only the fixed tool and options for another scanner:
git diff -z --name-only --diff-filter=d "$REVIEW_BASE" -- | xargs -0 sh -c '[ "$#" -eq 0 ] || exec semgrep scan --config=p/security-audit -- "${@}"' sh
git ls-files -z --others --exclude-standard | xargs -0 sh -c '[ "$#" -eq 0 ] || exec semgrep scan --config=p/security-audit -- "${@}"' sh
Single-file shell operands: Only a path matching the complete allow-list ^[A-Za-z0-9._/-]+$ may be interpolated into shell source. Single-quote it, prefix a relative file operand with ./, and put it after --; for Git file operands also use --literal-pathspecs, for example git --literal-pathspecs diff "$REVIEW_BASE" -- './src/orders.py'. For git show, single-quote the whole object expression '<resolved hexadecimal SHA>:src/orders.py' before --, and allow-list its path part first; the resolved SHA prevents an option-like object operand. A rejected path is never repaired by escaping it or excluded from the review: non-ASCII names and names with spaces or metacharacters stay in scope and are handled through NUL-delimited argv, a file tool's structured path argument, or a repository-wide read-only command such as git diff "$REVIEW_BASE" -- with findings filtered by the scope rule. In a fixed sh -c wrapper, paths may enter only as positional arguments used in quoted expansions such as "${@}"; they must never be inserted into the wrapper's source. Keep this braced POSIX spelling so OMP's command-template substitution leaves the shell expansion intact.
~~~

---

## Stack Detection Phase (Pre-Launch)

Before launching subagents, invoke the `developer-plugins-integration` skill using the Skill tool:

```
Skill(skill: "developer-plugins-integration")
```

This detects:

- Available developer plugins (e.g. python-developer, frontend-developer)
- Project tech stack (languages, frameworks, libraries)
- Which developer skills should be loaded for stack-specific analysis

Store the output — specifically the `skills_to_load` list — for use in subagent prompts below.

**Graceful degradation:** If no developer plugins are detected or the skill is unavailable, proceed normally. The review workflow is unchanged — stack detection is additive only.

---

## Documentation Detection Phase (Pre-Launch)

Before launching subagents, detect if the project has documentation:

1. Check existence of `docs/`, `doc/`, `documentation/` directories in project root
2. Search `README.md`, `CLAUDE.md`, `CONTRIBUTING.md` for keywords: "documentation", "docs"
3. Glob `**/*.md` (max 2 levels deep), filter out README, CHANGELOG, LICENSE, CODE_OF_CONDUCT

Store result: `has_documentation = true/false`

**If no documentation detected:** Skip documentation-auditor dispatch in the next step. All other review steps proceed normally.

**Docs drift pre-pass.** When `has_documentation = true` and `REVIEW_BASE` is not `none`, run the `docs-drift` skill's script; it never modifies the repository:

- Claude Code: `bash ${CLAUDE_PLUGIN_ROOT}/skills/docs-drift/scripts/docs_drift.sh --base <REVIEW_BASE>`, exactly this form, without quotes around the script path, to match this command's permission pre-approval.
- OMP: run `realpath skill://code-review:docs-drift/scripts/docs_drift.sh` with Bash, then `bash '<resolved path>' --base <REVIEW_BASE>`. An OMP shell does not define `CLAUDE_PLUGIN_ROOT`.

Exit 0 → store its complete stdout as `DOCS_DRIFT`. Any other exit, or a script that cannot be found → `DOCS_DRIFT = unavailable: <its first output line, or the error>`. Without a base → `DOCS_DRIFT = not run: whole-repository scope`. The pre-pass never stops the review.

---

## MANDATORY FIRST STEP: Launch Subagents

**YOU MUST launch subagents as soon as the pre-launch phases are done — Review Scope, Stack Detection, and Documentation Detection with its docs drift pre-pass — and before doing ANYTHING else.**

The one exception is an empty scope (Review Scope Phase): it launches no agent and goes straight to Step 6.

Use the Task tool for each agent in your first response after the pre-launch phases:

### Agent 1: Security Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:security-auditor"
- run_in_background: true
- prompt: "Perform comprehensive security audit. Execute the skills the scope block's Checks: line marks run — secret-scanning always, sast-analysis for SAST, dependency-scanning for the dependency scan — then AI threat modeling. Report with severity, CWE, file path, line number, remediation. End with your ## Checks section."
```

If developer skills were detected in the Stack Detection Phase, append to the prompt:
> "Developer skills available for framework-specific security checks: [skills_to_load list]. After standard security scans, apply framework-specific security patterns from these skills."

### Agent 2: Code Quality Auditor

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:code-quality-auditor"
- run_in_background: true
- prompt: "Perform comprehensive code quality audit. Execute standards-discovery and architecture-analysis, and linter-integration when the scope block's Checks: line marks linters run. Check SOLID, DDD, Clean Architecture. Report with severity, principle, file path, line number, code examples. End with your ## Checks section."
```

If developer skills were detected in the Stack Detection Phase, append to the prompt:
> "Developer skills available for stack-specific quality checks: [skills_to_load list]. After standard quality analysis, apply coding standards and patterns from these skills."

### Agent 3: Documentation Auditor (CONDITIONAL)

**Only launch if `has_documentation = true` from the Documentation Detection Phase.**

```
Use Task tool with these EXACT parameters:
- subagent_type: "code-review:documentation-auditor"
- run_in_background: true
- prompt: "Perform documentation audit. Check if code changes are reflected in project documentation. Report with severity, file path, line number, related code change, and remediation."
```

**Every auditor prompt ends with the scope block** (Review Scope Phase), after a blank line and after the developer-skills sentence when one was appended. The documentation-auditor prompt then gets a blank line, the line `Docs drift pre-pass:` and `DOCS_DRIFT` as stored.

**CRITICAL REQUIREMENTS:**

1. You MUST call Task tool for all applicable agents in one message, the first one after the pre-launch phases
2. You MUST use BOTH security-auditor and code-quality-auditor subagent types
3. You MUST set run_in_background: true for all agents
4. DO NOT skip the code-quality-auditor - it is MANDATORY
5. DO NOT proceed to any other analysis until all agents are launched
6. documentation-auditor is CONDITIONAL — only launch when documentation was detected
7. Every auditor prompt ends with the scope block; documentation-auditor's also carries the docs drift pre-pass

**If you only launch one agent, the review is INCOMPLETE.**

---

## MANDATORY SECOND STEP: Create Progress Tasks

**Immediately after launching both subagents, create ALL progress tasks:**

Use TaskCreate for each of the following (in a single response, all 5 tasks):

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Launch auditors | Launching auditors... |
| 2 | Perform performance analysis | Analyzing performance... |
| 3 | Perform architecture & maintainability review | Reviewing architecture & maintainability... |
| 4 | Collect subagent results | Collecting subagent results... |
| 5 | Generate final report | Generating final report... |
| 6 | Run verification (Cross-Verifier + Challenger) | Running verification... |
| 7 | Save review to file | Saving review to file... |
| 8 | Run post-review action | Running post-review action... |

Note: All 8 tasks are always created, except for an empty scope, which creates none.

**After creating all tasks:** Immediately mark task 1 as `completed` (auditors are already launched) and task 2 as `in_progress`.

---

## Code Review Workflow

**Scope.** Steps 2–4 cover the review scope: with a base, read `git diff <REVIEW_BASE>` and the untracked files marked `A`, and report under the scope rule; with a whole-repository scope, analyse the repository. They report nothing that **What is not a finding** (Review Comment Format) excludes.

### Step 1: Confirm Both Audits Running

Verify both subagents were launched before continuing:

- security-auditor (security analysis)
- code-quality-auditor (architecture/quality analysis)

**Task Update:** Mark task 2 as `in_progress` using TaskUpdate.

### Step 2: Performance Analysis

Check for:

- N+1 queries, missing indexes
- Memory leaks, unbounded collections
- Synchronous blocking calls
- Missing connection pooling
- Unbounded data fetching (no pagination)

**Task Update:** Mark task 2 as `completed` and task 3 as `in_progress` using TaskUpdate.

### Step 3: Architecture Analysis

Review:

- SOLID principles compliance
- Anti-patterns (Architecture Red Flags below)
- Dependency direction (inner layers don't depend on outer)
- API versioning and backward compatibility

### Step 4: Maintainability & Testing

Evaluate:

- Test coverage gaps
- Error handling patterns (A10:2025 - Exceptional Conditions)
- Documentation accuracy

**Task Update:** Mark task 3 as `completed` and task 4 as `in_progress` using TaskUpdate.

### Step 5: Retrieve Subagent Results (MANDATORY)

Use AgentOutputTool to get results from BOTH subagents:

**Security Auditor Results:**

```
agentId: <security-auditor agent ID>
block: true
```

**Code Quality Auditor Results:**

```
agentId: <code-quality-auditor agent ID>
block: true
```

**Documentation Auditor Results (if launched):**

```
agentId: <documentation-auditor agent ID>
block: true
```

**If documentation-auditor was not launched (no docs detected), skip this retrieval.**

**Integrate ALL findings from all subagents into final review. DO NOT skip this step.**

**Task Update:** Mark task 4 as `completed` and task 5 as `in_progress` using TaskUpdate.

### Step 5.5: Verification

Verification always runs:

**Task Update:** Mark task 5 as `completed` and task 6 as `in_progress`.

**1. Build findings bundle from subagent results:**

```
findings = {
  security: [security auditor results],
  quality: [code quality auditor results],
  documentation: [documentation auditor results, if launched],
  performance: [your performance analysis from Step 2],
  architecture: [your architecture analysis from Steps 3-4],
  rejected: {security: [...], quality: [...], documentation: [...]},
  doctrine_gaps: {security: [...], quality: [...], documentation: [...]}
}
```

The `rejected` / `doctrine_gaps` collections come from each auditor's self-falsification output (security-auditor: its JSON object with the `rejected` and `doctrine_gaps` keys — extract it out of the security results when building the bundle; it is not a finding and must not remain in `findings.security`; code-quality-auditor: Final Report sections 7–8; documentation-auditor: trailing markdown sections). Normalize `rejected` entries to `{title, reason, severity, category, location, drift-class}`: split markdown bullets on the FIRST ` — ` (title before, reason after); the trailing `(was: …)` suffix carries the remaining fields; default any absent field to `—`. `doctrine_gaps` entries stay `{title, reason}`. Forward them verbatim — for the cross-verifier they are pass-through context (no action).

Set the `## Checks` section of security-auditor and code-quality-auditor aside for the Verification Summary's `### Checks`: it is not a finding and stays out of `findings`.

**2. Spawn Cross-Verifier (background):**

```
Task(
  subagent_type: "code-review:cross-verifier",
  run_in_background: true,
  description: "Cross-analysis verification of code review",
  prompt: "Analyze the following findings from a code review.

Here are the findings from all auditors:
{findings}

Identify correlations between security and quality findings.
Focus on cases where security vulnerabilities intersect with architectural issues.
The rejected and doctrine_gaps collections are context only — do not
correlate them or use them as a composite basis.
Follow your output format exactly.
Build a composite only from findings that satisfy the scope rule below.

{scope block from Review Scope Phase}"
)
```

**3. Spawn Challenger (background):**

```
Task(
  subagent_type: "code-review:challenger",
  run_in_background: true,
  description: "Adversarial review of code review findings",
  prompt: "Review the following findings from a code review.

Here are the findings from all auditors:
{findings}

Challenge every finding at every severity: the security, quality and
documentation auditors' findings and the review's own performance and
architecture findings.
Check for false positives, especially in linter results and SAST output.
Spot-check the rejected collections: flag wrongly-rejected findings for
reinstatement per your Output Format. The doctrine_gaps collections are
pass-through context.
Follow your output format exactly.
Flag a rejected finding for reinstatement only when it satisfies the scope rule below.

{scope block from Review Scope Phase}"
)
```

**4. Collect verification results:**

Use TaskOutput with `block: true` for both agents:

```
cross_verifier_results = TaskOutput(cross_verifier_id, block: true)
challenger_results = TaskOutput(challenger_id, block: true)
```

**5. Merge enhanced findings:**

1. Apply Challenger decisions (remove false positives, adjust severity). Then drop every finding — an auditor's or your own — that **What is not a finding** (Review Comment Format) excludes, and list each as a plain bullet under `### Challenged Findings`: `- {title} — not a finding: {the metric, or style, formatting, naming or lint}`. A finding that paragraph keeps because a written style rule backs it is LOW, whatever its auditor or the challenger said. Then, with a base, apply the **scope check**: remove every finding — an auditor's or your own — whose **Location:** is outside the changed files and whose **Problem:** names no changed file and line that causes it, except a secret in an excluded review artifact (Review Scope Phase step 4), and list each under `### Out of scope (scope check)`. Composites and reinstatements below work only with the findings that survive this step.
2. Add Cross-Verifier composite findings. For each `[COMPOSITE-N]` the cross-verifier returned:
   1. Resolve each basis by exact title (or `DOC-NNN` ID) against the findings that survived step 1. A basis the challenger, the not-a-finding drop or the scope check removed, that matches nothing, or that matches more than one surviving finding is dropped — an ambiguous title is not a resolved basis.
   2. Disjointness: process the composites in the order returned; a basis of an earlier composite rendered as a finding block (passed sub-items 2.3 and 2.4) is dropped from every later one, so no finding is a component of two rendered composites. Only a rendered composite consumes its bases; a composite kept as a plain bullet leaves its bases available to later composites.
   3. Fewer than two bases remain → do **not** render the composite as a finding block; keep its text as a plain bullet under `### Cross-Analysis` in the Verification Summary, never as a `###` heading.
   4. With a base, first apply the scope rule to the composite itself: a composite whose own `Location` is outside the changed files and whose `Cause` names no changed file and line that causes it is not rendered as a block; keep it as a plain bullet under `### Cross-Analysis`, and its bases stay findings of their own. This runs before Step 5.6, so `**Part-of:**` links are created only for rendered composites. Otherwise build a finding block in the Review Comment Format: severity = the greater of the composite's own severity and the maximum basis severity; `**Category:** Composite`; `**Location:**` and `**Effort:**` from the composite; `**Problem:**` from its `Cause`; `**Impact:**` from its `Combined risk`; `**Remediation:**` from its `Remediation`; `**Composed-of:**` = the resolved bases (filled with final IDs in Step 5.6); `**Origin:** review`; and `**Fix-policy:** needs-decision` when any basis carries a `**Fix-policy:**` value other than `auto`. `**Location:**` must parse as `path:line` or `path:line-range`, be contained in the repository tree, and exist there — a composite whose location fails any of the three is not rendered as a block and stays a bullet, never repaired. Each resolved basis's `**Location:**` must pass those same three checks — the fixer opens every component's site, not the composite's alone — and a basis whose location fails any of them is dropped from `Composed-of` exactly as sub-item 1 drops an unresolvable one, leaving the composite a bullet under sub-item 3 where fewer than two bases survive.
3. Tag confirmed findings as `[verified]`
4. Reinstate spot-checked rejections: each entry in the Challenger's
   `### Rejected findings (spot-check)` subsection has the shape
   `[{domain}] {title}: reinstate at {SEVERITY} — {reasoning}`. Parse it by
   anchoring on the literal delimiter `: reinstate at ` (NOT the first `:`):
   the domain tag is the leading `[…]`, the **title** is the text between the
   tag and that delimiter, the severity is the `{SEVERITY}` token after it, and
   the reasoning is everything after the following ` — `. The title may itself
   contain `:` (e.g. `God Object: UserService`, which the auditors are told to
   write), so a first-`:` split would truncate the title and break the match
   back to the rejected record — always anchor on `: reinstate at `. For each
   entry, reconstruct a minimal
   full-format finding and move it from its auditor's `rejected` collection
   into `findings` before Step 5.6 — severity from the entry's
   `reinstate at {SEVERITY}`; Category from the rejected entry's normalized
   `category` field where present and not `—`, else from the domain tag
   (`[security]` → Security, `[documentation]` → Documentation,
   `[quality]` → Maintainability) — map any non-canonical forwarded
   category (e.g. Design, Style, Developer Standards) to Maintainability
   so Step 5.6 and fix-auto can always parse it; Location from the
   normalized `location` field where present and not `—`, else from the
   Challenger's reasoning where cited, else `—`; for Documentation-category reinstatements, set **Fix-policy:**
   needs-decision and **Drift-class:** from the normalized `drift-class`
   field where present and not `—`, else from the Challenger's reasoning,
   else decision (the class must not silently default to auto-fix); for ANY reinstated finding whose Location
   resolves to `—`, also set **Fix-policy:** needs-decision — a synthesized
   finding without a locatable target must not enter `/fix-all`'s auto
   queue (fix-auto requires a `path:line` Location and cannot ask for one
   inside a subagent); Problem/Remediation from the entry title, the
   original rejection reason, and the Challenger's reasoning.
   (Reconstruction is needed because rejected collections carry compact
   entries, not full finding blocks.)
   With a base, a reinstated finding that breaks the scope rule — located outside the changed files and naming no changed file and line that causes it — is not moved into findings; list it under `### Out of scope (scope check)`.
   A reinstated entry that **What is not a finding** excludes is not moved into findings either; list it under `### Challenged Findings` as in step 1.
   A reinstated entry that **What is not a finding** would exclude but a written style rule backs is LOW, whatever its `reinstate at` severity.

**Task Update:** Mark task 6 as `completed`.

---

## Subagent Coverage

### Security Auditor

| Skill | Coverage | OWASP 2025 |
|-------|----------|------------|
| secret-scanning | API keys, passwords, tokens | A02 |
| sast-analysis | Injection, XSS, SSRF, misconfig | A01, A02, A04, A05, A08, A10 |
| dependency-scanning | Vulnerable packages, CVEs | A03 (NEW) |
| AI Threat Modeling | Business logic, auth bypass | A06, A07, A09 |

### Code Quality Auditor

| Skill | Coverage | Principles |
|-------|----------|------------|
| standards-discovery | Project coding standards, conventions | Project-specific |
| linter-integration | ruff, mypy, eslint, tsc results | Style, Types |
| architecture-analysis | Layer boundaries, anti-patterns | SOLID, DDD, Clean Arch |
| AI Design Review | Cohesion, coupling, testability | Design Patterns |

**Why both are mandatory:**

- Security auditor catches vulnerabilities
- Quality auditor catches design/architecture issues
- Background execution enables parallel analysis
- Consistent coverage across all reviews

---

## Review Comment Format

For each issue found, format as structured markdown:

**Credential literals are never written.** In every finding — including `**Problem:**`, `**Impact:**`, `**Remediation:**` and its `# Before` snippet — replace each occurrence of a secret value with its first four characters followed by `…[REDACTED]`, e.g. `API_TOKEN = "ghp_…[REDACTED]"`. Apply this masking before displaying findings; Step 6 writes the report only after this masking.

**What is not a finding.** No finding block may rest only on a size or complexity metric — function or file length, parameter count, nesting depth, class size or method count, cyclomatic complexity, line-count duplication, a "God Object" by size — or only on style, formatting, naming or lint diagnostics. Tool output stays evidence: in the auditor's tool section and in the Verification Summary's `### Checks`, never in a `### [SEVERITY]` block. The one exception is a linter or type-checker diagnostic that shows a defect the change causes — a type error, undefined name, broken import, unreachable or wrong logic, failing compile: it may back one finding, whose **Problem:** names the changed line that causes it, even when the diagnostic's own location is an unchanged line. A rule about style, formatting, naming or size that the repository's own `CLAUDE.md`, `AGENTS.md` or `REVIEW.md` states backs a finding the change breaks: that finding is LOW, and its Problem cites the rule's file and section. A developer skill, a generic style guide or a linter's rule set backs no such finding.

### [SEVERITY] {ID}: Title of Issue

**ID:** {ID}
**Location:** `path/to/file.py:42`
**Category:** Security | Performance | Architecture | Maintainability | Documentation | Composite
**OWASP:** A05:2025 (if applicable)
**CWE:** CWE-89 (if applicable)
**Effort:** trivial | easy | medium | hard
**Drift-class:** mechanical | decision | dead-reference   <- documentation findings only
**Fix-policy:** auto | needs-decision                     <- documentation findings, and any reinstated finding with Location `—`
**Composed-of:** ID, ID[, ID…]                            <- Composite findings only
**Origin:** review | fix-time                             <- Composite findings only
**Part-of:** COMP-NNN                                     <- components of a composite only

**Problem:**
Brief description of what's wrong and why it matters.

**Impact:**
What could happen if this isn't fixed.

**Remediation:**

```python
# Before (vulnerable)
cursor.execute(f"SELECT * FROM users WHERE id={user_id}")

# After (secure)
cursor.execute("SELECT * FROM users WHERE id=?", (user_id,))
```

---

## Performance Red Flags

| Issue | Detection | Fix |
|-------|-----------|-----|
| N+1 Queries | DB call inside loop | Eager loading / batch fetch |
| Missing Indexes | Slow queries on large tables | Add appropriate indexes |
| Unbounded Collections | No LIMIT in queries | Add pagination |
| Blocking Calls | sync I/O in async context | Use async alternatives |
| Memory Leaks | Growing collections, unclosed resources | Proper cleanup |
| Missing Rate Limiting | Unprotected endpoints | Add throttling |

---

## Architecture Red Flags

| Anti-pattern | Detection | Severity |
|--------------|-----------|----------|
| Circular Dependencies | A imports B imports A | MEDIUM |
| Shared Database | Multiple services, one DB | HIGH |
| Breaking API Change | No deprecation warning | CRITICAL |
| Anemic Domain Model | Logic in services, not entities | MEDIUM |

---

## Microservices Checklist

When reviewing microservices, check:

- [ ] Service Cohesion - Single capability per service
- [ ] Data Ownership - Each service owns its database
- [ ] API Versioning - Semantic versioning (v1, v2)
- [ ] Backward Compatibility - Breaking changes flagged
- [ ] Circuit Breakers - Resilience patterns implemented
- [ ] Idempotency - Duplicate event handling

**Task Update:** Task 5 was already marked as `completed` in Step 5.5.

---

## Verification Summary

Include this section in the review output:

```markdown
## Verification Summary

**Method:** Cross-domain correlation and adversarial review (Cross-Verifier + Challenger)

| Metric | Count |
|--------|-------|
| Findings verified | {n} |
| False positives removed | {n} |
| Severity adjustments | {n} |
| Cross-analysis findings | {n} |

### Checks
- secret scan: {ran (<tools>, <n> files) | skipped (<reason>) | unavailable (<tool> not installed) | failed (<first error line>)}
- SAST: {the same four forms}
- dependency scan: {the same four forms}
- linters: {the same four forms}
- docs drift: {ran | not run: <reason>}

### Cross-Analysis (Security <-> Quality)
{Correlations from Cross-Verifier}

### Challenged Findings
{Findings removed or downgraded by Challenger, and findings dropped as not a finding (Step 5.5), with reasoning — as plain bullets. NEVER paste original `### [SEVERITY]` issue blocks here; fix-all/fix-report extract any such heading as a fixable issue, which would resurrect a removed false positive.}

### Rejected by auditors (self-falsification)
{Per-auditor rejected entries as plain bullets `- {title} — {reason}`; `None` when empty. NEVER render these as `### [SEVERITY]` headings — fix-all/fix-report extract any such heading as a fixable issue.}

### Doctrine-gap candidates
{Same bullet format; `None` when empty.}

### Out of scope (scope check)
{Findings removed by the scope check as plain bullets `- {title} — {location}`; `None` when empty or for a whole-repository scope. NEVER render these as `### [SEVERITY]` headings.}
```

The "Cross-analysis findings" count is the number of composites rendered as finding blocks.

`### Checks` takes the `## Checks` lines of security-auditor (`secret scan`, `SAST`, `dependency scan`) and code-quality-auditor (`linters`) verbatim, in that order — a line that joins several statuses with `; ` stays whole, e.g. `- dependency scan: ran (npm audit, 2 files); unavailable (pip-audit not installed)`; a check an auditor did not report is `- <check>: failed (not reported)`. Its last line is `- docs drift: ran` when the pre-pass stored the script's output in `DOCS_DRIFT`, else `- docs drift: not run: <reason>`, the reason being `whole-repository scope`, `no documentation detected` or `unavailable: <its first output line, or the error>`. A skipped, unavailable or failed check is never described as clean, in `### Checks` or anywhere else in the report. `### Checks` is a bare heading, never `### [`.

---

## Step 5.6: Assign Issue IDs

Before rendering the final report, assign unique identifiers to each issue based on category.

The rendered report starts with the `Review scope:` line from the Review Scope Phase. Line 2 is blank and line 3 is the count line: `Findings: <N> (<c> CRITICAL, <h> HIGH, <m> MEDIUM, <l> LOW)`, or `Findings: none — nothing to fix.` when N is 0. N counts the `### [SEVERITY] ID:` blocks, composites included, exactly as Step 7 counts them, and c, h, m and l count them by severity; write the line once this step has assigned the IDs, by counting the headings of the rendered report. Step 5.6 removes no finding: the scope check ran in Step 5.5 before composites were resolved, so every `**Composed-of:**` basis receives a final ID.

**Algorithm:**

1. Collect all findings from:
   - Security auditor results
   - Code quality auditor results
   - Documentation auditor results (if launched)
   - Your own performance analysis (Step 2)
   - Your own architecture/maintainability analysis (Steps 3-4)

2. Initialize counters for each category:
   - `sec_count = 0` (Security)
   - `perf_count = 0` (Performance)
   - `arch_count = 0` (Architecture)
   - `maint_count = 0` (Maintainability)
   - `doc_count = 0` (Documentation)
   - `comp_count = 0` (Composite)

3. For each issue (in the order they appear in the report):
   - Read the issue's `Category` field
   - Map the category to its prefix using the canonical [Category→Prefix mapping](../../../docs/plugins/code-review.md#category-prefix-mapping) (single source of truth), then increment the corresponding counter (e.g., Security → SEC → `sec_count`)
   - Format ID as `{PREFIX}-{NNN}` with zero-padded 3-digit counter (e.g., SEC-001, PERF-002)
   - Strip any pre-existing `{PREFIX}-{NNN}: ` prefix from the heading and drop any pre-existing `**ID:**` line before assigning (documentation-auditor emits its own DOC-NNN IDs; reinstated findings have none) — IDs are assigned exactly once, here
   - Modify the issue heading: `### [SEVERITY] {ID}: Title`
   - Add `**ID:** {ID}` field right after the heading (before **Location:**)
   - Preserve `**Drift-class:**` and `**Fix-policy:**` field lines verbatim when re-rendering issue blocks — they must reach the saved report for `/fix-all`'s Fix-policy filter to work.

4. **Composites last.** Assign `COMP-NNN` IDs only after every other finding has its ID, so `**Composed-of:**` renders with final IDs. For each composite block: fill `**Composed-of:**` with the resolved bases' final IDs on one physical line (`SEC-002, SEC-003, ARCH-001`); insert `**Part-of:** COMP-NNN` into each basis block directly after its `**ID:**` line; render the composite block after the non-composite findings of the same severity. Composites never nest and a basis belongs to at most one composite — both hold by construction of Step 5.5 item 2.

**Example transformation:**

Before:

```
### [HIGH] SQL Injection in User Query

**Location:** `src/db/queries.py:42`
**Category:** Security
```

After:

```
### [HIGH] SEC-001: SQL Injection in User Query

**ID:** SEC-001
**Location:** `src/db/queries.py:42`
**Category:** Security
```

---

## Step 6: Save Review

**Empty scope.** When the Review Scope Phase found nothing to review, print `Review not saved: nothing to review` and continue to Step 7 without a saved report.

**Task Update:** Mark task 7 as `in_progress` using TaskUpdate.

After the review report has been displayed, save it without asking; every review of a non-empty scope ends with a saved report:

1. Get current branch name:

```bash
git branch --show-current
```

2. Slugify the branch name:
   - Replace `/` with `-`
   - Replace spaces with `-`
   - Convert to lowercase
   - Example: `feature/user-login` → `feature-user-login`

3. Build the file path: `docs/reviews/YYYY-MM-DD-<branch-slug>.md`
   - Use today's date
   - Example: `docs/reviews/2026-02-19-feature-user-login.md`

4. Check if the file already exists. If it does, append a numeric suffix:
   - `docs/reviews/2026-02-19-feature-user-login-2.md`
   - Increment until a non-existing filename is found

5. Create the `docs/reviews/` directory if it doesn't exist:

```bash
mkdir -p docs/reviews
```

6. Before the Write call, apply the **Credential literals are never written** rule from **Review Comment Format** to the full report, including summaries and quoted code. Write only the masked report (the same masked markdown content displayed to the user) to the file using the Write tool; never persist the unmasked report.

7. Confirm to the user: "Review saved to `docs/reviews/2026-02-19-feature-user-login.md`"

If any of these steps fails, print `Review not saved: <error>` and continue to Step 7 without a saved report.

**Task Update:** Mark task 7 as `completed` using TaskUpdate.

---

## Step 7: Post-review action

**Task Update:** Mark task 8 as `in_progress` using TaskUpdate.

`REPORT` is the path Step 6 saved. `N` is the number of issue blocks in the report: headings `### [<CRITICAL|HIGH|MEDIUM|LOW>] <ID>: <title>`, composites included.

1. **No saved report** (Step 6 printed `Review not saved:`). With `N` above 0, print:

   > **Found {N} issues.** The report was not saved, so fix single issues by pasting them:
   >
   > `/fix <paste issue block from above>`

   With `N` = 0, print `Review complete. No issues found.` Then mark task 8 as `completed` and stop.

2. **No issues.** `N` = 0 → print `Review complete. No issues found.`, mark task 8 as `completed` and stop. Nothing is asked and nothing runs.

3. **Read `after_review`.** Run the engine's `config`:
   - Claude Code: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/decision-gate/scripts/auto_accept.py config`, exactly this form, without quotes around the script path, to match this command's permission pre-approval.
   - OMP: run `realpath skill://code-review:decision-gate/scripts/auto_accept.py` with Bash, then `python3 '<resolved path>' config`. An OMP shell does not define `CLAUDE_PLUGIN_ROOT`.

   Read the JSON and the exit code together:
   - Exit 0 → `ACTION` is `policy.after_review`: `ask`, `fix-all`, `fix-report` or `none`. A missing file, table or key reports `ask`.
   - Exit 2 with `errors` → print `Post-review action: the configuration is invalid — <file> <key>: <error>[; …]; asking instead.` and set `ACTION` to `ask`.
   - Any other non-zero exit, unparseable output or a missing interpreter → print `Post-review action: <error text, or the first output line>; asking instead.` and set `ACTION` to `ask`.

   When `ACTION` came from the configuration and is not `ask`, print `Post-review action: <ACTION> (after_review in <provenance of code-review.after_review>)`.

4. **Trust.** `ACTION` is `fix-all` and the engine's `trust` is `new` or `changed` → ask one AskUserQuestion:
   - question: `Trust the code-review settings? With them, every saved review goes straight to /code-review:fix-all, which fixes its auto-fixable findings without asking first.` When `policy.auto_accept_min_confidence` is a number `T`, append ` They also fix a documentation finding without asking when the analyst and an independent second opinion agree at or above <T>% confidence.` Follow it with one line per `trust_subset` entry, `<key> = <value>`, masked as returned. The approval covers every one of those lines: the decision gate reads the same approval.
   - options, in this order: `Trust and use it` — `Records approval for this worktree; asked again whenever these settings change.`; `Not now` — `Asks what to do with this review instead.`

   `ACTION` stays `fix-all` only when the answer is exactly `Trust and use it` and the engine's `trust accept <trust_hash>` then exits 0 — `python3 ${CLAUDE_PLUGIN_ROOT}/skills/decision-gate/scripts/auto_accept.py trust accept <trust_hash>` in Claude Code, `python3 '<resolved path>' trust accept <trust_hash>` in OMP. This command does not pre-approve that call, so in Claude Code's default permission mode, unless another permission rule allows it, Claude Code asks for permission before it runs; a denied permission is a failing `trust accept`. A failing `trust accept` prints `Post-review action: trust not recorded — <error>; asking instead.` Every other outcome — `Not now`, free text, a cancelled or missing answer, a question that cannot be asked or that errors — prints `Post-review action: settings not trusted; asking instead.` Both set `ACTION` to `ask`.

5. **Ask.** `ACTION` is `ask` → ask one AskUserQuestion:
   - question: `What next with the {N} findings in <REPORT>?`
   - options, in this order: `Fix all` — `Run /code-review:fix-all on this report: every auto-fixable finding now, then an offer to resolve the needs-decision ones.`; `Choose from a checklist` — `Run /code-review:fix-report on this report and pick the findings to fix.`; `Nothing now` — `Keep the report and fix it later.`

   `Fix all` → `ACTION` is `fix-all`; `Choose from a checklist` → `fix-report`; `Nothing now`, any other answer, or a question that cannot be asked (AskUserQuestion unavailable, as in a subagent or a print-mode run, or failing) → `none`. Never choose an answer yourself.

6. **Act.** Mark task 8 as `completed`, then:
   - `fix-all` → hand over the report with the args `--yes <REPORT>`; `--yes` answers fix-all's confirmation gate, because the configuration or the answer above already chose to fix. Claude Code: invoke the Skill tool with skill `code-review:fix-all` and args `--yes <REPORT>`, and carry it out completely. OMP: the plugin root is the path `realpath` resolved in step 3 without its trailing `/skills/decision-gate/scripts/auto_accept.py`; `read <plugin root>/commands/fix-all.md` and carry it out completely, as if it had been invoked with `--yes <REPORT>` in place of its `$ARGUMENTS`.
   - `fix-report` → its checklist needs the user: when AskUserQuestion is not among your tools (a subagent, a print-mode run), act as for `none`. Otherwise hand over as for `fix-all`, with skill `code-review:fix-report`, file `<plugin root>/commands/fix-report.md` and args `<REPORT>`.
   - `none` → print:

     > **Found {N} issues** in `<REPORT>`. To fix them:
     >
     > `/fix-all <REPORT>` — fix every auto-fixable issue after one confirmation
     >
     > `/fix-report <REPORT>` — choose issues from a checklist
     >
     > `/fix SEC-001` — fix a single issue by ID (uses the latest saved report)
     >
     > `/fix <paste issue block>` — fix a single issue by pasting

   In OMP, when step 3's `realpath` failed there is no plugin root: instead of handing over, print `Post-review action: cannot locate code-review's commands; run /code-review:<ACTION> <REPORT> yourself.`

The handover runs in this command's turn. In Claude Code this command's `allowed-tools` stay granted for the whole turn, so they are prompt-free while the handed-over command runs, its decision stage included; that stage still asks before any check outside its execution boundary (`code-review:decision-gate`, *The grant registry*).

---

## Final Verification Checklist

An empty scope (Review Scope Phase) skips this checklist: it launches no agent, prints `Review not saved: nothing to review` and goes to Step 7.

### Security (MANDATORY)

- [ ] security-auditor subagent launched
- [ ] Security results retrieved via AgentOutputTool
- [ ] All security findings included in review
- [ ] Secret scanning completed
- [ ] SAST reported in `### Checks`, skipped only where the `Checks:` line planned it
- [ ] Dependency scan reported in `### Checks`, skipped only where the `Checks:` line planned it

### Code Quality (MANDATORY)

- [ ] code-quality-auditor subagent launched
- [ ] Quality results retrieved via AgentOutputTool
- [ ] All quality findings included in review
- [ ] Standards discovery completed
- [ ] Linters reported in `### Checks`; their output kept as evidence, never as finding blocks (**What is not a finding**)
- [ ] Architecture analysis completed

### Documentation (CONDITIONAL)

- [ ] Documentation detection phase completed
- [ ] documentation-auditor subagent launched (if docs detected)
- [ ] Docs drift pre-pass run when docs were detected and the scope has a base, its output passed to documentation-auditor
- [ ] Documentation results retrieved via AgentOutputTool (if launched)
- [ ] All documentation findings included in review

### Completeness

- [ ] Performance analysis done
- [ ] Review scope determined (review artifacts excluded, `Checks:` line derived), its scope block passed to every dispatched agent, scope check applied before composites were resolved
- [ ] Every finding that **What is not a finding** excludes dropped to `### Challenged Findings`
- [ ] All findings have file:line references
- [ ] Severity levels assigned (CRITICAL/HIGH/MEDIUM/LOW)
- [ ] Actionable remediation provided
- [ ] Code examples for HIGH+ severity issues
- [ ] Report line 1 is the `Review scope:` line and line 3 the `Findings:` count line

### Post-Review Actions

- [ ] Review saved to `docs/reviews/` without asking, or `Review not saved:` printed
- [ ] Post-review action resolved from `[code-review] after_review` (default `ask`)
- [ ] Saved report handed to `/code-review:fix-all --yes` or `/code-review:fix-report`, or the fix commands printed

**If ANY security or quality checkbox is unchecked: STOP. Complete those steps first.**

### Developer Plugins (if detected)

- [ ] developer-plugins-integration skill invoked
- [ ] Stack detection results passed to subagents
- [ ] Developer skill findings integrated into review

### Verification

- [ ] Cross-Verifier and Challenger subagents spawned and results collected
- [ ] Cross-Verifier correlations integrated
- [ ] Challenger results applied to every finding, at every severity (false positives removed, severity adjusted)
- [ ] Verification Summary included in output, with its `### Checks` subsection

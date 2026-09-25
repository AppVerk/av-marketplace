---
description: "PHP development workflow enforcing coding standards, TDD, and stack-specific patterns. Loads the right skills automatically (Symfony, Doctrine, DDD)."
argument-hint: "<task description>"
---
> **OMP edition — generated file, do not edit.** Source of truth: `plugins/php-developer/commands/develop.md`; regenerate with `python3 scripts/build_omp_edition.py`.
>
> The instructions below were written for Claude Code. In this harness, read their tool references as follows:
>
> - **Task tool** with `subagent_type: "<plugin>:<agent>"` → call `task` with `agent: "<plugin>:<agent>"` (the id is unchanged) and the prompt as the item's `task`. `run_in_background` has no equivalent: `task` runs asynchronously and results are delivered when agents finish. "Dispatch in parallel" means one `task` call with several items.
> - **TaskCreate / TaskUpdate / TaskList** → the `todo` tool: `init` with the listed subjects, `start` / `done` by subject text, `view` to list. `activeForm` has no equivalent. A subagent has no `todo` tool: when running as one, skip these progress-tracking steps and do the work they announce.
> - **AskUserQuestion** → the `ask` tool. `multiSelect: true` → `multi: true`.
> - **Skill tool**, `Skill(skill: "<name>")`, or a skill cited as `<plugin>:<name>` → `read skill://<plugin>:<name>`. Every skill is addressed with its plugin prefix; a skill named without one belongs to this plugin, so read `skill://php-developer:<name>`.
> - In an agent's instructions, `ARGUMENTS` (prefixed with a dollar sign) stands for the task text you were given.
> - **WebSearch** → `web_search`. **WebFetch** → `read` on the URL.
> - A subagent has no `ask` tool: where the instructions say to ask the user, choose the most likely option and state the choice and its reason in your report.
> - **allowed-tools** and `Bash(<cmd>:*)` grants are Claude Code permission pre-approvals. They grant and restrict nothing here.
> - **`mcp__<server>` and `mcp__<server>__*` grants** are not carried over: a subagent here gets every MCP tool of the session whatever its `tools:` list says, and a server the session has not configured is simply absent. MCP tools are named `mcp__<server>_<tool>` here (one underscore between server and tool), not `mcp__<server>__<tool>`.
> - **Playwright MCP** (`browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, `browser_type`, `browser_select_option`, `browser_press_key`, `browser_hover`, `browser_evaluate`, `browser_wait_for`, `browser_take_screenshot`, and any `mcp__playwright*` or `mcp__plugin_playwright_playwright*` tool) → the `browser` global inside `eval`, OMP's own Chromium (downloaded on first use; while it is enabled, OMP removes Playwright MCP servers from the session). Read `xd://eval/browser` before the first browser step. Open one tab per run, `tab = await browser.open(name="qa", url=<url>)`, then navigate with `await tab.goto(url)`; a probe such as "try `browser_navigate`" is that `browser.open` call, and an exception from it means the browser is unavailable. `browser_snapshot()` → `await tab.observe()` (numeric ids for `tab.id(n)`) or `await tab.ariaSnapshot()` (`e5`-style refs for `tab.ref("e5")`); act on those handles or on selectors (`text/Sign In`, `aria/Email`, CSS) with `click`, `fill`, `type`, `select`, `press`, `hover`. `browser_evaluate(expression)` → `await tab.evaluate(expression)`. `browser_wait_for` → `await tab.waitForSelector("text/Success", timeout=5000)` or `await tab.waitForSelector(selector, hidden=True, timeout=10000)`. `browser_take_screenshot()` → `path = await tab.screenshot()` returns a file in the OS temp directory: copy it with `bash` to the path the instructions name.
> - **Slash commands** are `/<plugin>:<name>` here: `/fix`, `/fix-report`, `/fix-all` and `/review` are `/code-review:fix`, `/code-review:fix-report`, `/code-review:fix-all` and `/code-review:review`; a command cited with its plugin prefix, such as `/qa:run`, keeps its name.
> - In the text below, a backticked command right after `!` (for example !`git status`) is Claude Code inline context: Claude Code runs it and puts its output there before the model reads the text. Here nothing ran: run each such command in the text below with `bash` first and use its output in its place.

# PHP Development Workflow

You are executing a structured PHP development workflow. Follow every step in order. Do not skip steps.

## Task

**$ARGUMENTS**

---

## Step 1: Load Coding Standards (MANDATORY)

Before doing anything else, load the base coding standards skill:

```
Use the Skill tool with:
  skill: "php-developer:coding-standards"
```

**You MUST load this skill first. All code you write must follow its HARD-RULES.**

---

## Step 2: Analyze the Project

### 2a. Discover project commands

**Read these files first (in order of priority) to find the actual project commands for testing, linting, and typechecking:**

1. **CLAUDE.md** (root or `.claude/`) — primary source of truth for AI workflows
2. **README.md** — look for "Development", "Contributing", "Getting Started" sections with commands
3. **Makefile** — check for available targets (`make test`, `make typecheck`, `make lint`, etc.)
4. **composer.json** `scripts` section — project-defined commands (e.g. `composer test`, `composer analyse`)

**Record the discovered commands.** You will use them in Steps 5 and 6 instead of fallback defaults. If no commands are found in any of these sources, fall back to:
- Test: `vendor/bin/phpunit`
- Typecheck: `vendor/bin/phpstan analyse src`
- Lint: `vendor/bin/php-cs-fixer fix --dry-run --diff`

### 2b. Detect the project stack

1. **composer.json** — look for dependencies: `symfony/framework-bundle`, `doctrine/orm`, `symfony/messenger`, `friendsofsymfony/rest-bundle`, `jms/serializer-bundle`
2. **Directory structure** — scan for `src/*/Domain/`, `src/*/Application/` patterns indicating DDD
3. **Task description** — parse `$ARGUMENTS` for keywords: controller, route, endpoint, entity, repository, migration, command handler, query handler, aggregate, value object, bounded context, event, messenger, task

Record which stack components are present. You will use this in Step 3.

---

## Step 3: Load Context-Specific Skills

Based on Step 2 findings, load the relevant skills using the Skill tool. **Only load skills that are actually needed.**

### Always load when writing or modifying code (almost always):

```
Use the Skill tool with:
  skill: "php-developer:tdd-workflow"
```

### If Symfony detected OR task involves controllers/routes/endpoints:

```
Use the Skill tool with:
  skill: "php-developer:symfony-patterns"
```

### If Doctrine detected OR task involves entities/repositories/migrations:

```
Use the Skill tool with:
  skill: "php-developer:doctrine-orm-patterns"
```

### If DDD detected OR task involves aggregates/value objects/bounded contexts:

```
Use the Skill tool with:
  skill: "php-developer:ddd-patterns"
```

### If task involves adding/removing/updating dependencies:

```
Use the Skill tool with:
  skill: "php-developer:composer"
```

**No mutual exclusions.** All skills can be loaded together as needed.

**After loading skills, read and internalize the HARD-RULES from every loaded skill. You must follow all of them.**

---

## Step 4: Plan the Implementation

Before writing any code:

1. Identify the files that need to be created or modified
2. Identify the test files that need to be created or modified
3. Determine the test cases needed (happy path, edge cases, error cases)
4. Confirm the plan aligns with loaded skill HARD-RULES

---

## Step 5: TDD Cycle (MANDATORY)

**You MUST follow this cycle. Writing implementation code before tests is a violation.**

### 5a. Write Tests First

- Create test file(s) following the project's test directory structure
- Write test cases covering: happy path, edge cases, error handling
- Use Fakes for internal dependencies, Mocks only for external I/O
- Use `#[DataProvider]` for similar test cases
- Test naming: `testMethodNameScenarioExpectedBehavior`

### 5b. Run Tests (Expect Failure)

Run the test command discovered in Step 2a (e.g. `make test`, `vendor/bin/phpunit`, or whatever the project uses).

Tests MUST fail at this point. If they pass, your tests are not testing the right thing.

### 5c. Implement the Code

- Write the minimal code to make tests pass
- Follow all HARD-RULES from loaded skills
- `declare(strict_types=1)` in every PHP file
- All function parameters and return types must be annotated
- Use `readonly` for immutable data
- Use `match` instead of `switch`
- Use `DateTimeImmutable` not `DateTime`

### 5d. Run Tests (Expect Pass)

Run the test command discovered in Step 2a.

All tests must pass. If any fail, fix the implementation (not the tests, unless the test itself is wrong).

### 5e. Refactor

- Remove duplication
- Improve naming
- Ensure code is clean and readable
- Run tests again after refactoring to confirm nothing broke

---

## Step 6: Quality Gates (MANDATORY)

**Use the commands discovered in Step 2a.** The examples below are fallback defaults — always prefer the project's own commands from `CLAUDE.md`, `README.md`, or `Makefile`.

Run these checks. **ALL must pass before the task is considered complete.**

### Typecheck

Run the typecheck command from Step 2a (e.g. `make typecheck`, `vendor/bin/phpstan analyse src`).

Fix any type errors. Do not use `@phpstan-ignore` unless absolutely unavoidable and justified.

### Full Test Suite

Run the test command from Step 2a (e.g. `make test`, `vendor/bin/phpunit`).

All tests must pass. Zero failures, zero errors.

### Linting

Run the lint command from Step 2a (e.g. `make lint`, `vendor/bin/php-cs-fixer fix --dry-run --diff`).

Zero warnings. Zero errors.

### Dependency Analysis (optional)

If Deptrac is available, run the dependency analysis command (e.g. `vendor/bin/deptrac analyse`).

Fix any architectural violations.

---

## Step 7: Final Verification Checklist

**Go through this checklist before declaring the task complete. If ANY item is unchecked, go back and fix it.**

### Coding Standards

- [ ] `declare(strict_types=1)` in every PHP file
- [ ] All function parameters and return types annotated
- [ ] No `mixed` without justification
- [ ] No FQCN — using `use` imports everywhere
- [ ] No `@var` when native type is possible
- [ ] `readonly` for immutable data
- [ ] Enums instead of class constants for finite sets
- [ ] `match` instead of `switch`
- [ ] `DateTimeImmutable` not `DateTime`

### TDD

- [ ] Tests written BEFORE implementation
- [ ] Fakes for internal dependencies (no mocks for internals)
- [ ] Mocks only for external I/O
- [ ] Test naming: `testMethodNameScenarioExpectedBehavior`
- [ ] `#[DataProvider]` for similar test cases
- [ ] Tests are independent — no shared mutable state

### Quality Gates

- [ ] Typecheck passes with zero errors
- [ ] Test suite passes with zero failures
- [ ] Lint passes with zero warnings

### Stack-Specific (check only if relevant skill was loaded)

- [ ] Symfony: thin controllers, constructor injection, `#[Route]` attributes, Messenger for CQRS
- [ ] Doctrine: named parameters, migrations via `doctrine:migrations:diff`, `DateTimeImmutable`
- [ ] DDD: dependency direction inward, no framework in Domain, factory methods on aggregates
- [ ] Composer: `composer require` used, lock file intact

**If all checks pass, the task is complete.**

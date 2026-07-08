---
allowed-tools: Read, Grep, Glob, Bash(tsc:*), Bash(vitest:*), Bash(playwright:*), Bash(eslint:*), Bash(biome:*), Bash(pnpm:*), Bash(bun:*), Bash(bunx:*), Bash(git:*), Bash(node:*)
description: TypeScript + React development workflow enforcing coding standards, TDD, and stack-specific patterns. Loads the right skills automatically.
argument-hint: <task description>
---

# TypeScript + React Development Workflow

You are executing a structured TypeScript + React development workflow. Follow every step in order. Do not skip steps.

## Task

**$ARGUMENTS**

---

## Step 1: Load Coding Standards (MANDATORY)

Before doing anything else, load the base coding standards skill:

```
Use the Skill tool with:
  skill: "frontend-developer:coding-standards"
```

**You MUST load this skill first. All code you write must follow its HARD-RULES.**

---

## Step 2: Analyze the Project

### 2a. Discover project commands

**Read these files first (in order of priority) to find the actual project commands for testing, linting, and typechecking:**

1. **CLAUDE.md** (root or `.claude/`) — primary source of truth for AI workflows
2. **README.md** — look for "Development", "Contributing", "Getting Started" sections with commands
3. **package.json** `scripts` — project-defined commands
4. **Makefile** — check for available targets

**Record the discovered commands.** You will use them in Steps 5 and 6 instead of fallback defaults. If no commands are found in any of these sources, pick the fallback set that matches the detected package manager:

**If `bun.lock` or `bun.lockb` exists** (Bun project):
- Dev: `bun dev`
- Test: `bun run test` (use `bun test` only if `bunfig.toml` has a `[test]` section)
- Test watch: `bun run test:watch` (or `bun test --watch` for Bun-native tests)
- Typecheck: `bun run typecheck` (or `bun tsc --noEmit`)
- Lint: `bun run lint`

**Otherwise** (default — pnpm or unspecified):
- Dev: `pnpm dev`
- Test: `pnpm test`
- Test watch: `pnpm test:watch`
- Typecheck: `pnpm typecheck` (or `pnpm tsc --noEmit`)
- Lint: `pnpm lint`

### 2b. Detect the project stack

1. **package.json** — look for dependencies:
   - `tailwindcss` — Tailwind CSS
   - `zustand` — Zustand state management
   - `@tanstack/react-query` — TanStack Query
   - `react-hook-form` — React Hook Form
   - `@tanstack/react-router` — TanStack Router
2. **Lockfile** — confirm which package manager the project uses:
   - `bun.lock` or `bun.lockb` → Bun
   - `pnpm-lock.yaml` → pnpm
   - `package-lock.json` → npm
   - `yarn.lock` → yarn
   - If multiple lockfiles are present, flag this as an anti-pattern and ask the user which manager to keep
3. **tsconfig.json** — verify `strict: true` is enabled
4. **src/** — scan directory structure to detect feature-based architecture
5. **Task description** — parse `$ARGUMENTS` for keywords: component, form, route, state, query, API, store

Record which stack components are present. You will use this in Step 3.

### 2c. Verify TypeScript strict mode

Read `tsconfig.json` and confirm:
- `strict: true`
- `noUncheckedIndexedAccess: true` (warn if missing)

If strict mode is not enabled, warn the user before proceeding.

---

## Step 3: Load Context-Specific Skills

Based on Step 2 findings, load the relevant skills using the Skill tool. **Only load skills that are actually needed.**

### Always load TDD workflow:

```
Use the Skill tool with:
  skill: "frontend-developer:tdd-workflow"
```

### If `tailwindcss` in dependencies:

```
Use the Skill tool with:
  skill: "frontend-developer:tailwind-patterns"
```

### If `zustand` in dependencies:

```
Use the Skill tool with:
  skill: "frontend-developer:zustand-patterns"
```

### If `@tanstack/react-query` in dependencies:

```
Use the Skill tool with:
  skill: "frontend-developer:tanstack-query-patterns"
```

### If `react-hook-form` in dependencies:

```
Use the Skill tool with:
  skill: "frontend-developer:form-patterns"
```

### If `@tanstack/react-router` in dependencies:

```
Use the Skill tool with:
  skill: "frontend-developer:tanstack-router-patterns"
```

### If `pnpm-lock.yaml` exists AND task involves dependency changes:

```
Use the Skill tool with:
  skill: "frontend-developer:pnpm-package-manager"
```

### If `bun.lock` or `bun.lockb` exists AND task involves dependency changes:

```
Use the Skill tool with:
  skill: "frontend-developer:bun-package-manager"
```

### If task description involves multiple boolean props/flags/permissions/states driving one component:

```
Use the Skill tool with:
  skill: "frontend-developer:state-combination-modeling"
```

**After loading skills, read and internalize the HARD-RULES from every loaded skill. You must follow all of them.**

---

## Step 4: Plan the Implementation

Before writing any code:

1. Identify the files that need to be created or modified
2. Identify the test files that need to be created or modified
3. Determine the test cases needed (happy path, edge cases, error cases)
4. Confirm the plan aligns with loaded skill HARD-RULES
5. Verify the plan follows feature-based architecture (if applicable)

---

## Step 5: TDD Cycle (MANDATORY)

**You MUST follow this cycle. Writing implementation code before tests is a violation.**

### Detect Mode from Task Keywords

| Mode | Keywords |
|------|----------|
| **Fix** | "fix", "bug", "error", "broken", "failing", "issue" |
| **Implement** | "add", "create", "build", "implement", "new" *(default)* |
| **Refactor** | "refactor", "clean", "extract", "move", "rename" |

### Fix Mode

1. **Read target file** and understand the issue from the context and `$ARGUMENTS`
2. **Write a test** that reproduces the problem — the test must fail
3. **Run the test** (using command from Step 2a) to confirm failure
4. **Implement the fix** — make minimal changes only
5. **Run the test** to confirm it passes
6. **Refactor** if needed, re-run tests to confirm nothing broke

### Implement Mode

1. **Identify files** to create or modify
2. **Write tests** — happy path, edge cases, error handling
3. **Run tests** (using command from Step 2a) to confirm failure
4. **Write minimal implementation** to pass tests
5. **Run tests** to confirm pass
6. **Refactor**, re-run tests to confirm nothing broke

### Refactor Mode

1. **Check if tests exist** for the affected code
2. **If no tests:** write tests first, run them, confirm they pass against the current code
3. **Perform the refactoring**
4. **Run tests** to confirm they still pass
5. **If tests fail:** fix the refactoring, not the tests

---

## Step 6: Quality Gates (MANDATORY)

**Use the commands discovered in Step 2a.** Run these checks. **ALL must pass before the task is considered complete.**

### Gate 1: Typecheck

Run the typecheck command (e.g. `pnpm typecheck`, `pnpm tsc --noEmit`).

Fix any type errors. Do not use `@ts-expect-error` unless absolutely unavoidable and justified.

**Maximum 3 iterations** — if still failing after 3 attempts, record the remaining errors and proceed.

### Gate 2: Full Test Suite

Run the test command (e.g. `pnpm test`).

All tests must pass. Zero failures, zero errors. Coverage should be >= 80%.

**Maximum 3 iterations** — if still failing after 3 attempts, record the remaining failures and proceed.

### Gate 3: Linting

Run the lint command (e.g. `pnpm lint`, `pnpm biome check`).

Zero warnings. Zero errors.

**Maximum 3 iterations** — if still failing after 3 attempts, record the remaining warnings and proceed.

---

## Step 7: Final Verification Checklist

**Go through this checklist before declaring the task complete. If ANY item is unchecked, go back and fix it.**

### Coding Standards

- [ ] All function parameters and return types are explicitly annotated
- [ ] No `any` — using `unknown` + type guards
- [ ] No `as` type assertions (except `as const`)
- [ ] No `!` non-null assertion — using `?.` and `??`
- [ ] No `enum` — using `as const` objects
- [ ] `import type { }` for type-only imports
- [ ] No unused imports or variables
- [ ] Components use direct props annotation, not `React.FC`

### TDD

- [ ] Tests were written BEFORE implementation
- [ ] `userEvent` used instead of `fireEvent`
- [ ] `screen.getByRole` preferred over `getByText` / `getByTestId`
- [ ] Tests are independent — no shared mutable state between tests
- [ ] Coverage >= 80%

### Quality Gates

- [ ] Typecheck passes with zero errors
- [ ] Test suite passes with zero failures
- [ ] Lint passes with zero warnings

### Stack-Specific (check only if relevant skill was loaded)

- [ ] Tailwind: Semantic tokens, no `@apply`, CVA for variants, `cn()` for conditionals
- [ ] Zustand: Curried syntax, granular selectors, `useShallow` for multiple values
- [ ] TanStack Query: `queryOptions`, key factories, no server state in Zustand
- [ ] Forms: Zod schema as source of truth, `zodResolver`, server errors via `setError`
- [ ] Router: File-based routes, `ensureQueryData` in loader, `beforeLoad` for auth
- [ ] pnpm: `pnpm` commands only, lock file committed
- [ ] bun: `bun` commands only, lockfile committed (prefer `bun.lock` text form)

**If all checks pass, the task is complete. Changes remain uncommitted for user review.**

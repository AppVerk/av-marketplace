# Frontend Developer Plugin Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a complete TypeScript + React SPA development plugin with 8 skills, /develop command, autonomous developer agent, and comprehensive testing for modern frontend best practices.

**Architecture:** Plugin mirrors python-developer structure — single `/develop` command triggers an autonomous `developer` agent that conditionally loads 8 skills based on project stack detection. Skills cover coding standards, TDD workflow, and domain-specific patterns (Tailwind, Zustand, TanStack Query, forms, routing, pnpm).

**Tech Stack:** TypeScript, React (Vite), Tailwind CSS v4, Zustand, TanStack Query v5, React Hook Form + Zod, TanStack Router, pnpm, Vitest + RTL + Playwright, ESLint.

---

## Setup & Structure

### Task 1: Create plugin directory structure

**Files:**
- Create: `plugins/frontend-developer/.claude-plugin/plugin.json`
- Create: `plugins/frontend-developer/commands/develop.md`
- Create: `plugins/frontend-developer/agents/developer.md`
- Create: `plugins/frontend-developer/skills/coding-standards/SKILL.md`
- Create: `plugins/frontend-developer/skills/tdd-workflow/SKILL.md`
- Create: `plugins/frontend-developer/skills/tailwind-patterns/SKILL.md`
- Create: `plugins/frontend-developer/skills/zustand-patterns/SKILL.md`
- Create: `plugins/frontend-developer/skills/tanstack-query-patterns/SKILL.md`
- Create: `plugins/frontend-developer/skills/form-patterns/SKILL.md`
- Create: `plugins/frontend-developer/skills/tanstack-router-patterns/SKILL.md`
- Create: `plugins/frontend-developer/skills/pnpm-package-manager/SKILL.md`

**Step 1: Create plugin.json**

```json
{
  "name": "frontend-developer",
  "description": "Enforces TypeScript + React best practices, coding standards, TDD workflow, and modern tooling (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router)",
  "version": "1.0.0"
}
```

Save to `plugins/frontend-developer/.claude-plugin/plugin.json`

**Step 2: Commit directory structure**

```bash
git add plugins/frontend-developer/
git commit -m "chore(frontend-developer): initialize plugin directory structure"
```

---

## Skill 1: coding-standards

### Task 2: Implement coding-standards skill

**Files:**
- Create: `plugins/frontend-developer/skills/coding-standards/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: coding-standards
description: TypeScript + React coding standards, architecture patterns, naming conventions, ESLint configuration
---

# Coding Standards — TypeScript + React

## Overview

Foundational rules for TypeScript + React development. Enforced in all code:
- Strict TypeScript configuration
- React best practices
- Feature-based architecture (Bulletproof React)
- Three-layer separation of concerns
- Naming conventions
- ESLint rules
```

**Step 2: Write TypeScript Hard Rules section** (~400 lines)

Include from design doc:
- `strict: true` requirements
- No `any`, `as` assertions, `!` non-null, `enum`
- `interface` vs `type` guidance
- Import conventions
- No barrel exports >5

**Step 3: Write React Hard Rules section** (~300 lines)

- Direct props annotation (no React.FC)
- Explicit children typing
- userEvent, screen.getByRole
- Event handler types
- Context patterns
- Hooks rules

**Step 4: Write Feature-Based Architecture section** (~400 lines)

- Directory structure with code example
- Dependency direction rules
- Three-layer separation
- Naming conventions table
- ESLint configuration

**Step 5: Commit**

```bash
git add plugins/frontend-developer/skills/coding-standards/SKILL.md
git commit -m "feat(frontend-developer): implement coding-standards skill"
```

---

## Skill 2: tdd-workflow

### Task 3: Implement tdd-workflow skill

**Files:**
- Create: `plugins/frontend-developer/skills/tdd-workflow/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: tdd-workflow
description: Test-driven development workflow with Vitest, React Testing Library, MSW v2, and Playwright
---

# TDD Workflow — Testing Strategy

## Overview

Enforces red-green-refactor TDD cycle with comprehensive testing strategy:
- Vitest + jsdom for component/unit tests
- React Testing Library for user-centric testing
- MSW v2 for API mocking
- Playwright for E2E critical paths
- Testing Trophy approach
- 80%+ coverage requirement
```

**Step 2: Write Testing Trophy section** (~200 lines)

- Diagram explanation
- When to use each layer
- Ratio guidance

**Step 3: Write Hard Rules section** (~250 lines)

- TDD before implementation
- userEvent > fireEvent
- screen.getByRole priority
- Never test implementation details
- Co-located tests
- 80% coverage

**Step 4: Write Test Organization & Setup section** (~400 lines)

- File structure with code
- Custom render utility (full code)
- MSW setup (handlers, server, vitest integration)
- Vitest config example
- Playwright setup

**Step 5: Write TDD Cycle & Quality Gates section** (~300 lines)

- 7-step TDD cycle
- Quality gates (typecheck, test, lint)
- Max 3 iterations per gate

**Step 6: Commit**

```bash
git add plugins/frontend-developer/skills/tdd-workflow/SKILL.md
git commit -m "feat(frontend-developer): implement tdd-workflow skill"
```

---

## Skill 3: tailwind-patterns

### Task 4: Implement tailwind-patterns skill

**Files:**
- Create: `plugins/frontend-developer/skills/tailwind-patterns/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: tailwind-patterns
description: Tailwind CSS v4, CVA component variants, shadcn/ui patterns, semantic tokens, responsive design
---

# Tailwind CSS Patterns — v4 + Component System

## Overview

Modern Tailwind v4 setup and component patterns:
- CSS-first configuration (no tailwind.config.js)
- `cn()` utility for conditional classes
- CVA (Class Variance Authority) for variants
- shadcn/ui architecture
- Semantic tokens with dark mode
- Accessibility patterns
```

**Step 2: Write v4 Setup & Hard Rules section** (~350 lines)

- Vite + Tailwind v4 plugin config
- CSS file with `@theme` + tokens
- Hard rules table
- `cn()` utility code
- Never use `@apply`

**Step 3: Write CVA & Component Architecture section** (~400 lines)

- Full CVA example (Button)
- shadcn/ui two-layer pattern
- Radix UI + Tailwind
- When to extract components vs utilities

**Step 4: Write Responsive Design & Accessibility section** (~300 lines)

- Mobile-first breakpoints
- Container queries vs viewport queries
- sr-only, focus-visible, motion-reduce
- Semantic HTML
- ARIA variants

**Step 5: Commit**

```bash
git add plugins/frontend-developer/skills/tailwind-patterns/SKILL.md
git commit -m "feat(frontend-developer): implement tailwind-patterns skill"
```

---

## Skill 4: zustand-patterns

### Task 5: Implement zustand-patterns skill

**Files:**
- Create: `plugins/frontend-developer/skills/zustand-patterns/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: zustand-patterns
description: Zustand store management with slices, middleware, selectors, and TypeScript patterns
---

# Zustand Patterns — Global State Management

## Overview

Zustand patterns for client state:
- Curried syntax with TypeScript
- Store slices organization
- Middleware (devtools, persist, immer)
- Granular selectors
- Feature-scoped vs global stores
- When to use Zustand vs TanStack Query vs Context
```

**Step 2: Write Hard Rules & Decision Matrix section** (~300 lines)

- Curried syntax requirement
- Granular selectors rule
- When to use each tool (matrix)
- No server state in Zustand

**Step 3: Write Slices Pattern section** (~400 lines)

- Full AuthSlice example
- UISlice example
- Combining with middleware
- Selector hooks

**Step 4: Write Middleware & Testing section** (~250 lines)

- devtools + persist + immer ordering
- partialize for persist
- Reset stores in tests
- Store logic testing without render

**Step 5: Commit**

```bash
git add plugins/frontend-developer/skills/zustand-patterns/SKILL.md
git commit -m "feat(frontend-developer): implement zustand-patterns skill"
```

---

## Skill 5: tanstack-query-patterns

### Task 6: Implement tanstack-query-patterns skill

**Files:**
- Create: `plugins/frontend-developer/skills/tanstack-query-patterns/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: tanstack-query-patterns
description: TanStack Query v5 server state management with queryOptions, mutations, caching, and error handling
---

# TanStack Query Patterns — Server State

## Overview

TanStack Query patterns for server state:
- `queryOptions` helper pattern
- Query key factories
- API service layer (pure functions)
- Axios interceptors
- Mutations with optimistic updates
- Global error handling
- Error boundaries
- Suspense integration
```

**Step 2: Write Hard Rules & API Service section** (~350 lines)

- `queryOptions` requirement
- Query key factories
- Pure API service functions
- Axios client with interceptors
- Never cache API in Zustand

**Step 3: Write Query & Mutation Patterns section** (~400 lines)

- queryOptions factory examples
- useQuery hook pattern
- useMutation with onSuccess
- Optimistic updates (onMutate, onError, onSettled)
- Invalidation strategy

**Step 4: Write Error Handling & Suspense section** (~300 lines)

- Global error handling (QueryCache.onError)
- Error boundaries + QueryErrorResetBoundary
- useSuspenseQuery pattern
- Layer 1-4 error strategy

**Step 5: Commit**

```bash
git add plugins/frontend-developer/skills/tanstack-query-patterns/SKILL.md
git commit -m "feat(frontend-developer): implement tanstack-query-patterns skill"
```

---

## Skill 6: form-patterns

### Task 7: Implement form-patterns skill

**Files:**
- Create: `plugins/frontend-developer/skills/form-patterns/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: form-patterns
description: React Hook Form + Zod schema validation with type-safe forms and server error handling
---

# Form Patterns — React Hook Form + Zod

## Overview

React Hook Form + Zod patterns:
- Zod as single source of truth
- Type inference from schemas
- Resolver integration
- Schema organization
- Form component patterns
- Server-side error mapping
- Testing strategies
```

**Step 2: Write Hard Rules & Schema Pattern section** (~350 lines)

- Zod as source of truth
- zodResolver requirement
- z.coerce.number() for inputs
- Schema per-form (not mega-schema)
- createUserSchema + updateUserSchema pattern

**Step 3: Write Complete Form Component section** (~400 lines)

- Full useForm + zodResolver setup
- Mutation integration
- setError for server errors
- isPending to block submit
- Field error display

**Step 4: Write Advanced Patterns & Testing section** (~300 lines)

- Derived schemas (omit/partial)
- Reusable FormField wrapper
- Testing validation errors
- Testing successful submit
- Testing server-side field errors (MSW)

**Step 5: Commit**

```bash
git add plugins/frontend-developer/skills/form-patterns/SKILL.md
git commit -m "feat(frontend-developer): implement form-patterns skill"
```

---

## Skill 7: tanstack-router-patterns

### Task 8: Implement tanstack-router-patterns skill

**Files:**
- Create: `plugins/frontend-developer/skills/tanstack-router-patterns/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: tanstack-router-patterns
description: TanStack Router type-safe routing with file-based conventions, loaders, and search params validation
---

# TanStack Router Patterns — Type-Safe Routing

## Overview

TanStack Router patterns:
- File-based routing conventions
- Type-safe params
- Search params with Zod validation
- Data loading with TanStack Query
- Protected routes via beforeLoad
- Lazy loading (code-split)
- Router context
```

**Step 2: Write Hard Rules & File Conventions section** (~300 lines)

- File-based conventions ($param, _prefix, .)
- Type-safe Route.useParams()
- Zod validation for search params
- Data loading via loader + ensureQueryData
- beforeLoad for auth guards

**Step 3: Write Router Setup & Data Loading section** (~400 lines)

- Root route with createRootRouteWithContext
- ensureQueryData + useSuspenseQuery pattern
- Type-safe search params (full example)
- Router creation with context
- App entry point setup

**Step 4: Write Advanced Patterns section** (~300 lines)

- Protected routes with beforeLoad + throw redirect
- Pending UI with useRouterState
- Not found handling
- Nested routes via file naming

**Step 5: Commit**

```bash
git add plugins/frontend-developer/skills/tanstack-router-patterns/SKILL.md
git commit -m "feat(frontend-developer): implement tanstack-router-patterns skill"
```

---

## Skill 8: pnpm-package-manager

### Task 9: Implement pnpm-package-manager skill

**Files:**
- Create: `plugins/frontend-developer/skills/pnpm-package-manager/SKILL.md`

**Step 1: Write skill frontmatter and overview**

```markdown
---
name: pnpm-package-manager
description: pnpm package management, workspace setup, dependency updates, and CI integration
---

# pnpm Package Manager

## Overview

pnpm best practices:
- pnpm commands (add, remove, update, run)
- .npmrc configuration
- Lock file management
- CI/CD integration
- Workspace support
- Troubleshooting
```

**Step 2: Write Hard Rules & Basic Commands section** (~300 lines)

- Always use pnpm (never npm/yarn in pnpm projects)
- pnpm run for scripts
- --frozen-lockfile in CI
- Lock file commitment
- pnpm dlx instead of npx

**Step 3: Write Commands & CI section** (~350 lines)

- Add/remove/update/install/run commands with examples
- package.json scripts template
- .npmrc config file
- GitHub Actions setup with pnpm

**Step 4: Write Workspace & Troubleshooting section** (~250 lines)

- Monorepo workspace setup
- pnpm --filter usage
- Phantom dependencies
- Peer conflicts
- Stale lock file resolution

**Step 5: Commit**

```bash
git add plugins/frontend-developer/skills/pnpm-package-manager/SKILL.md
git commit -m "feat(frontend-developer): implement pnpm-package-manager skill"
```

---

## Command & Agent

### Task 10: Implement /develop command

**Files:**
- Create: `plugins/frontend-developer/commands/develop.md`

**Step 1: Write command frontmatter**

```markdown
---
name: /develop
description: TypeScript + React development workflow enforcing coding standards, TDD, and stack-specific patterns
allowed_tools:
  - Read
  - Grep
  - Glob
  - Bash
    - tsc
    - vitest
    - playwright
    - eslint
    - biome
    - pnpm
    - git
model: claude-opus-4-6
argument_hint: "<task description>"
---
```

**Step 2: Write command instructions (7-step workflow)**

```markdown
# /develop Command

## Workflow

1. **Load coding-standards** — MANDATORY, always first
2. **Analyze project** — detect stack, verify tsconfig, discover commands
3. **Load context-specific skills** — conditional based on dependencies
4. **Plan implementation** — identify files, tests, test cases
5. **TDD cycle** — red/green/refactor
6. **Quality gates** — typecheck, tests, lint (max 3 iterations)
7. **Final verification** — checklist completion

## Stack Detection

Examine `package.json` and load skills:
- `tailwindcss` → tailwind-patterns
- `zustand` → zustand-patterns
- `@tanstack/react-query` → tanstack-query-patterns
- `react-hook-form` → form-patterns
- `@tanstack/react-router` → tanstack-router-patterns
- `pnpm-lock.yaml` exists → pnpm-package-manager (if deps change needed)

## Three Work Modes

Detect from task keywords:
- **Fix** ("bug", "error", "broken") → Read → Test → Fix → Pass → Refactor
- **Implement** ("add", "create", "build") → Plan → Write tests → Implement → Pass → Refactor
- **Refactor** ("refactor", "clean", "extract") → Check tests → Refactor → Pass

## Final Verification Checklist

- [ ] All tests passing (vitest)
- [ ] TypeScript strict: `pnpm typecheck`
- [ ] ESLint/Biome: `pnpm lint`
- [ ] Coverage >= 80%
- [ ] Code follows coding-standards
- [ ] Commits follow Conventional Commits
- [ ] Changes uncommitted (for user review)
```

**Step 3: Commit**

```bash
git add plugins/frontend-developer/commands/develop.md
git commit -m "feat(frontend-developer): implement /develop command"
```

### Task 11: Implement developer agent

**Files:**
- Create: `plugins/frontend-developer/agents/developer.md`

**Step 1: Write agent frontmatter**

```markdown
---
name: developer
description: Autonomous Python developer agent enforcing TDD, coding standards, and stack-specific patterns
model: claude-opus-4-6
tools:
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Skill
  - TaskCreate
  - TaskUpdate
  - TaskList
allowed_bash:
  - tsc
  - vitest
  - playwright
  - eslint
  - biome
  - pnpm
  - git
  - node
skills:
  - coding-standards
  - tdd-workflow
  - tailwind-patterns
  - zustand-patterns
  - tanstack-query-patterns
  - form-patterns
  - tanstack-router-patterns
  - pnpm-package-manager
---
```

**Step 2: Write agent instructions (6-phase workflow)**

```markdown
# Developer Agent

## 6-Phase Workflow

1. **Parse input & detect mode** — creates 6 progress tasks
2. **Load coding-standards & detect stack** — reads package.json, scans src/
3. **Load context-specific skills** — conditional based on detection
4. **TDD cycle** — mode-appropriate (fix/implement/refactor)
5. **Quality gates** — typecheck → tests → lint (max 3 each)
6. **Report** — status, skills, changes, tests, gate results

## Mode Detection

- **Fix**: "fix", "bug", "broken", "error", "issue"
- **Implement**: "add", "create", "build", "implement", "new"
- **Refactor**: "refactor", "clean", "extract", "move", "rename"

## Stack Detection & Skill Loading

Always load: coding-standards, tdd-workflow
Conditional:
- tailwindcss → tailwind-patterns
- zustand → zustand-patterns
- @tanstack/react-query → tanstack-query-patterns
- react-hook-form → form-patterns
- @tanstack/react-router → tanstack-router-patterns
- pnpm-lock.yaml + deps change → pnpm-package-manager

## Output

Leaves changes uncommitted for user review.
```

**Step 3: Commit**

```bash
git add plugins/frontend-developer/agents/developer.md
git commit -m "feat(frontend-developer): implement developer agent"
```

---

## Documentation & Registration

### Task 12: Add documentation & register plugin

**Files:**
- Create: `docs/plugins/frontend-developer.md`
- Modify: `.claude-plugin/marketplace.json`

**Step 1: Create docs/plugins/frontend-developer.md**

```markdown
# Frontend Developer Plugin

Advanced TypeScript + React SPA development with TDD, coding standards, and stack-specific patterns.

## Installation

```bash
/plugin marketplace add AppVerk/av-marketplace
```

## Available Commands

### `/develop <task>`

Autonomous development workflow for features, bugfixes, and refactoring.

**Examples:**
```bash
/develop Add user profile page with avatar upload and edit form
/develop Fix the search filter not updating URL params
/develop Refactor auth module to use Zustand slices pattern
/develop Create reusable DataTable component with sorting and pagination
```

## Skills (Auto-Loaded Conditionally)

| Skill | When loaded | Purpose |
|-------|------------|---------|
| coding-standards | Always | TypeScript, React, architecture, naming, ESLint |
| tdd-workflow | Always | Vitest, RTL, Playwright, MSW, testing strategy |
| tailwind-patterns | tailwindcss dep | Tailwind v4, CVA, shadcn/ui, tokens, accessibility |
| zustand-patterns | zustand dep | Stores, slices, middleware, selectors |
| tanstack-query-patterns | @tanstack/react-query dep | Server state, queryOptions, mutations, cache |
| form-patterns | react-hook-form dep | RHF, Zod, validation, server errors |
| tanstack-router-patterns | @tanstack/react-router dep | File-based routing, loaders, search params |
| pnpm-package-manager | pnpm-lock.yaml + deps change | pnpm commands, CI, workspace |

## Workflow

1. Load coding-standards
2. Analyze project (package.json, tsconfig.json, src/ structure)
3. Load context-specific skills
4. Plan implementation
5. TDD cycle (red/green/refactor)
6. Quality gates (typecheck → test → lint)
7. Final verification

## Tech Stack

- TypeScript (strict mode required)
- React 18+ (Vite)
- Tailwind CSS v4
- Zustand for global state
- TanStack Query v5 for server state
- React Hook Form + Zod for forms
- TanStack Router for routing
- pnpm for package management
- Vitest + React Testing Library + Playwright for testing
- ESLint/Biome for linting
```

Save to `docs/plugins/frontend-developer.md`

**Step 2: Register in marketplace.json**

```bash
# Read current marketplace.json
cat .claude-plugin/marketplace.json

# Add entry to plugins array:
{
  "name": "frontend-developer",
  "source": "./plugins/frontend-developer",
  "description": "TypeScript + React SPA development with TDD, coding standards, and stack-specific patterns (Tailwind v4, Zustand, TanStack Query, React Hook Form, TanStack Router)",
  "version": "1.0.0",
  "category": "development"
}
```

**Step 3: Commit both**

```bash
git add docs/plugins/frontend-developer.md .claude-plugin/marketplace.json
git commit -m "docs(frontend-developer): add plugin documentation and marketplace registration"
```

---

## Final Verification

### Task 13: Final verification and summary

**Files:**
- No new files

**Step 1: Verify all skills exist**

```bash
ls plugins/frontend-developer/skills/
# Should show 8 directories with SKILL.md each
```

**Step 2: Verify command and agent**

```bash
ls plugins/frontend-developer/commands/develop.md
ls plugins/frontend-developer/agents/developer.md
```

**Step 3: Verify documentation**

```bash
ls docs/plugins/frontend-developer.md
grep "frontend-developer" .claude-plugin/marketplace.json
```

**Step 4: Verify plugin.json**

```bash
cat plugins/frontend-developer/.claude-plugin/plugin.json
```

**Step 5: Final commit**

```bash
git log --oneline -10
# Verify all 13 commits are present
```

---

## Summary

**Total commits:** 13
- Task 1: Directory structure (1)
- Task 2: coding-standards skill (1)
- Task 3: tdd-workflow skill (1)
- Task 4: tailwind-patterns skill (1)
- Task 5: zustand-patterns skill (1)
- Task 6: tanstack-query-patterns skill (1)
- Task 7: form-patterns skill (1)
- Task 8: tanstack-router-patterns skill (1)
- Task 9: pnpm-package-manager skill (1)
- Task 10: /develop command (1)
- Task 11: developer agent (1)
- Task 12: Documentation & registration (1)
- Task 13: Final verification (0 commits)

**Deliverables:**
- ✅ Plugin directory structure
- ✅ 8 comprehensive skills (1000+ lines each)
- ✅ `/develop` command with 7-step workflow
- ✅ `developer` agent with 6-phase workflow
- ✅ Complete documentation
- ✅ Marketplace registration

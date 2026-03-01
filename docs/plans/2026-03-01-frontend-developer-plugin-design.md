# Frontend Developer Plugin — Design Document

**Date:** 2026-03-01
**Status:** Approved
**Plugin name:** `frontend-developer`
**Version:** 1.0.0

## Overview

A Claude Code plugin for TypeScript + React SPA development, modeled after `python-developer`. Enforces coding standards, TDD workflow, and stack-specific patterns through a `/develop` command, autonomous `developer` agent, and 8 conditional skills.

**Target stack:** React SPA (Vite) + TypeScript + Tailwind CSS v4 + Zustand + TanStack Query + React Hook Form + Zod + TanStack Router + pnpm

## Plugin Structure

```
plugins/frontend-developer/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   └── develop.md
├── agents/
│   └── developer.md
└── skills/
    ├── coding-standards/SKILL.md
    ├── tdd-workflow/SKILL.md
    ├── tailwind-patterns/SKILL.md
    ├── zustand-patterns/SKILL.md
    ├── tanstack-query-patterns/SKILL.md
    ├── form-patterns/SKILL.md
    ├── tanstack-router-patterns/SKILL.md
    └── pnpm-package-manager/SKILL.md
```

## Flow: `/develop` -> Agent -> Skills

```
User: /develop <task description>

  1. Load coding-standards (MANDATORY, always first)
  2. Analyze project:
     - package.json -> detect dependencies
     - tsconfig.json -> verify strict mode
     - pnpm-lock.yaml -> confirm pnpm
     - src/ -> detect architecture pattern
     - CLAUDE.md / README.md / package.json scripts -> discover project commands
  3. Load context-specific skills:
     - tdd-workflow              -> ALWAYS
     - tailwind-patterns         -> if tailwindcss in dependencies
     - zustand-patterns          -> if zustand in dependencies
     - tanstack-query-patterns   -> if @tanstack/react-query in dependencies
     - form-patterns             -> if react-hook-form in dependencies
     - tanstack-router-patterns  -> if @tanstack/react-router in dependencies
     - pnpm-package-manager      -> if pnpm-lock.yaml exists & dependency changes needed
  4. Plan implementation
  5. TDD cycle: Write tests -> Run (fail) -> Implement -> Run (pass) -> Refactor
  6. Quality gates: TypeScript (tsc) -> Tests (vitest) -> Lint (eslint/biome)
  7. Final verification checklist
```

## Stack Detection

| Dependency in package.json | Skill loaded |
|---------------------------|-------------|
| `tailwindcss` | `tailwind-patterns` |
| `zustand` | `zustand-patterns` |
| `@tanstack/react-query` | `tanstack-query-patterns` |
| `react-hook-form` | `form-patterns` |
| `@tanstack/react-router` | `tanstack-router-patterns` |
| `pnpm-lock.yaml` exists | `pnpm-package-manager` (when dependency changes needed) |

---

## Skill 1: coding-standards (ALWAYS loaded)

### TypeScript Hard Rules (NON-NEGOTIABLE)

- `strict: true` in tsconfig + `noUncheckedIndexedAccess` + `isolatedModules`
- Never `any` — use `unknown` + type guards
- Never `as` type assertions (except `as const`)
- Never `!` non-null assertion — use `?.` and `??`
- Never `enum` — use `as const` objects + derived union types
- Never `@ts-ignore` — use `@ts-expect-error` with comment if needed
- `interface` for object shapes, `type` for unions/intersections
- Never `I` prefix on interfaces (`User`, not `IUser`)
- `Props` suffix on component props (`ButtonProps`)
- `import type { }` for type-only imports
- No unused imports/variables
- No barrel exports >5 re-exports; direct imports inside features

### React Hard Rules (NON-NEGOTIABLE)

- Direct props annotation, never `React.FC`
- Explicit `children: React.ReactNode` in props
- `userEvent` instead of `fireEvent` in tests
- `screen.getByRole` > `getByText` > `getByTestId`
- Event handlers with specific React types
- Context: null default + throwing custom hook
- Hooks rules: never inside conditions/loops

### Architecture — Feature-Based (Bulletproof React)

```
src/
  app/                    # Shell: routes, providers, entry point
  features/               # Self-contained feature modules
    auth/
      api/                # API calls + TanStack Query hooks
      components/         # Feature-scoped UI
      hooks/              # Feature-scoped logic hooks
      stores/             # Feature-scoped Zustand stores
      types/              # Feature-scoped types
      index.ts            # Public API (max 5 exports)
  components/             # Shared UI (Button, Modal, Card)
    ui/                   # Primitives (shadcn/ui style)
  hooks/                  # Shared hooks (useDebounce, useMediaQuery)
  lib/                    # Preconfigured libs (axios instance, cn utility)
  stores/                 # Global stores
  types/                  # Shared TypeScript types
  utils/                  # Pure utility functions
  test/                   # Test setup, custom render, MSW handlers
```

**Dependency direction (NON-NEGOTIABLE):** `shared -> features -> app`. Features NEVER import from other features. Cross-feature composition happens in `app/` (routes/pages).

### Three-Layer Separation of Concerns

```
API/Service Layer    ->  Pure functions (no React), fully testable
                         src/features/orders/api/ordersApi.ts

Logic/Hook Layer     ->  Custom hooks (bridge React state <-> services)
                         src/features/orders/hooks/useOrders.ts

UI/Component Layer   ->  Rendering only, minimal logic
                         src/features/orders/components/OrderList.tsx
```

### Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Files/folders | `kebab-case` | `user-profile/` |
| Components (file) | `PascalCase.tsx` | `UserProfile.tsx` |
| Components (export) | `PascalCase` | `export function UserProfile()` |
| Hooks | `camelCase` with `use` prefix | `useAuth.ts` -> `useAuth()` |
| Utility functions | `camelCase` | `formatDate.ts` |
| Types/Interfaces | `PascalCase` | `UserProfile`, `ButtonProps` |
| Constants | `UPPER_SNAKE_CASE` | `const API_BASE_URL = ...` |
| Const objects | `PascalCase` + `as const` | `const OrderStatus = {...} as const` |

### ESLint — Required Configuration

- `typescript-eslint` with `strict-type-checked` + `stylistic-type-checked`
- `@typescript-eslint/no-explicit-any`: error
- `@typescript-eslint/no-non-null-assertion`: error
- `@typescript-eslint/consistent-type-imports`: error (inline type imports)
- `react-hooks/rules-of-hooks`: error
- `react-hooks/exhaustive-deps`: warn
- Biome acceptable as alternative if detected in project

### Path Aliases — Required

```jsonc
// tsconfig.json
{ "paths": { "@/*": ["./src/*"] } }
```

All imports from `src/` use `@/` instead of relative paths.

---

## Skill 2: tdd-workflow (ALWAYS loaded)

### Testing Trophy

```
         /\
        /E2E\           5-10% — Playwright, critical paths
       /------\
      / Integr. \       Largest layer — RTL + MSW
     /  ation    \      "Write tests. Not too many. Mostly integration."
    /--------------\
   /  Unit tests    \   Hooks, utils, store logic, pure functions
  /------------------\
 / Static (TypeScript) \ Foundation — errors caught at compile time
/________________________\
```

### Hard Rules (NON-NEGOTIABLE)

- Tests BEFORE implementation (TDD): Red -> Green -> Refactor
- `userEvent` instead of `fireEvent`
- `screen.getByRole` as default query
- Never test implementation details (state, internal methods, class names)
- Never manual `act()` wrapping around `render` / `userEvent`
- Never shared mutable state in `beforeEach` — inline setup per test
- MSW for API mocking, never `vi.mock` on fetch/axios
- 80%+ coverage before completion
- Tests co-located with code (`Button.tsx` + `Button.test.tsx`)
- Full test suite (`pnpm test`), not individual files

### File Organization

```
src/
  features/auth/
    components/
      LoginForm.tsx
      LoginForm.test.tsx              # co-located
  mocks/
    handlers.ts                       # MSW handlers (centralized)
    server.ts                         # MSW server setup
  test/
    setup.ts                          # Vitest setup file
    test-utils.tsx                    # Custom render with providers
e2e/
  pages/                              # Page Object Models
    LoginPage.ts
  tests/
    auth.spec.ts                      # E2E tests
```

| Test type | Naming pattern | Location |
|-----------|---------------|----------|
| Unit / Integration | `*.test.{ts,tsx}` | Co-located in `src/` |
| E2E | `*.spec.ts` | `e2e/tests/` |
| Page Objects | `*Page.ts` | `e2e/pages/` |

### Custom Render (Required)

Every project must have `test-utils.tsx` with custom render wrapping components in required providers (QueryClient, Router, Theme, etc.). Tests import `render` from `@/test/test-utils`, never directly from `@testing-library/react`.

### MSW v2 — API Mocking

- Centralized handlers in `src/mocks/handlers.ts`
- Per-test overrides via `server.use(...)` for error scenarios
- Setup in `test/setup.ts`: `beforeAll(listen)`, `afterEach(resetHandlers + cleanup)`, `afterAll(close)`
- `onUnhandledRequest: 'error'` to catch unmocked API calls

### Vitest Configuration (Required)

- `globals: true`, `environment: 'jsdom'`
- `setupFiles: ['./src/test/setup.ts']`
- Coverage: `provider: 'v8'`, thresholds 80% (lines, functions, branches, statements)

### Playwright — E2E (Critical Paths Only)

- Page Object Model pattern
- E2E covers: login, checkout, signup, multi-step wizards, auth flows
- `defaultPreload: 'intent'` for preloading on hover

### TDD Cycle (7 Steps)

1. Write user stories
2. Generate test cases (happy path, edge cases, error states)
3. Run tests — MUST fail (Red)
4. Implement minimal code (Green)
5. Run tests — MUST pass
6. Refactor with confidence
7. Verify coverage >= 80%

### Quality Gates (after TDD, max 3 iterations each)

```
Gate 1: pnpm typecheck    (tsc --noEmit)
Gate 2: pnpm test         (vitest run --coverage)
Gate 3: pnpm lint         (eslint . --fix  or  biome check --fix)
```

---

## Skill 3: tailwind-patterns (conditional: tailwindcss in deps)

### Hard Rules (NON-NEGOTIABLE)

- Never `@apply` for CSS abstractions — extract React components instead
- Never dynamically constructed classes (`bg-${color}-500`) — use const maps
- Never magic values / arbitrary value overuse — define tokens in `@theme`
- Semantic tokens (`bg-primary`) instead of raw palette (`bg-blue-500`)
- Never remove focus outline without replacement — `focus:outline-none focus-visible:ring-2`
- `focus-visible:` instead of `focus:` for ring/outline
- Mobile-first — unprefixed = all screens
- Container queries (`@container`) for components, viewport queries (`md:`) for page layout

### Vite + Tailwind v4 Setup

- `@tailwindcss/vite` plugin — no PostCSS, no `tailwind.config.js`
- CSS-first configuration via `@import "tailwindcss"` + `@theme` + `@custom-variant`
- CSS variable tokens for dark mode: `:root` + `.dark` + `@theme` mapping

### `cn()` Utility (Mandatory)

`clsx` + `tailwind-merge` — every component with conditional classes must use `cn()`.

### CVA (Class Variance Authority)

Every component with variants (Button, Badge, Alert, Input) MUST use CVA. Components expose `VariantProps<typeof variants>` in their props interface.

### Component Architecture (shadcn/ui Pattern)

Two layers:
1. **Behavior** — Radix UI primitives (keyboard nav, ARIA, focus management)
2. **Styling** — Tailwind + CVA (visual presentation)

Components in `src/components/ui/` — owned code, not npm-installed.

### Accessibility

- `sr-only` for screen-reader-only content
- `motion-reduce:animate-none` on every animation
- `aria-expanded:`, `aria-selected:` variants instead of class toggling
- Semantic HTML first (`<button>`, `<nav>`, `<main>`, `<label>`) — never `<div onClick>`

---

## Skill 4: zustand-patterns (conditional: zustand in deps)

### Hard Rules (NON-NEGOTIABLE)

- Curried syntax in TypeScript: `create<State>()((...) => ({...}))`
- Granular selectors — never destructure entire store
- `useShallow` when selecting multiple values
- State + actions in one interface
- Never mutate state directly (unless immer middleware)
- `devtools` middleware in development
- `persist` with `partialize` — never persist entire store
- Zustand only for client state — server state -> TanStack Query

### State Management Decision Matrix

| Concern | Tool |
|---------|------|
| Server/API data | TanStack Query |
| Global client state | Zustand |
| Local component state | useState / useReducer |
| Rarely-changing tree-wide values | React Context |
| Form state | React Hook Form |
| URL-driven state | Router search params |

### Store Organization

- Slices pattern: one store, domain-based slices in separate files
- Middleware ordering: `devtools(persist(immer(...)))`
- Reusable selector hooks exported from `src/stores/selectors.ts`
- Feature-scoped stores in `src/features/<name>/stores/` for non-global state
- Reset stores between tests via `useStore.setState(useStore.getInitialState())`

---

## Skill 5: tanstack-query-patterns (conditional: @tanstack/react-query in deps)

### Hard Rules (NON-NEGOTIABLE)

- `queryOptions` helper to define queries — single source of truth for queryKey + queryFn
- Query key factories — one source of truth per domain (`usersQueries.detail(id)`)
- Never cache API responses in Zustand — TanStack Query = server state cache
- `onError`/`onSuccess` on `QueryCache`/`MutationCache`, never on `useQuery` (removed in v5)
- `retry: false` + `gcTime: 0` in tests
- Invalidate after mutation, never manual cache update (unless optimistic)
- TanStack Query for EVERY API call — never raw `useEffect` + `fetch`

### Patterns

- **API service layer:** pure functions in `features/<name>/api/<name>Api.ts`
- **Query factories:** `queryOptions`-based in `features/<name>/api/queries.ts`
- **Axios client:** centralized in `src/lib/api-client.ts` with auth + error interceptors
- **Mutations:** thin wrapper hooks in `features/<name>/hooks/`
- **Optimistic updates:** `onMutate` cancel + snapshot + set, `onError` rollback, `onSettled` invalidate
- **Global error handling:** `QueryCache.onError` for background toasts, `MutationCache.onError` for operation toasts
- **Error boundaries:** `QueryErrorResetBoundary` + `react-error-boundary`
- **Suspense:** `useSuspenseQuery` for guaranteed data at render time

---

## Skill 6: form-patterns (conditional: react-hook-form in deps)

### Hard Rules (NON-NEGOTIABLE)

- Zod schema as single source of truth for types: `type FormData = z.infer<typeof schema>`
- `zodResolver` to connect Zod with RHF
- `z.coerce.number()` for numeric inputs (HTML inputs return strings)
- Never Formik in new code
- Never controlled inputs without need — RHF defaults to uncontrolled
- Server-side errors mapped to fields via `setError`
- Mutation `isPending` blocks submit
- Schema per-form, not universal mega-schema

### Patterns

- **Zod schemas** in `features/<name>/schemas/`
- **Update schemas** derived from create via `.omit().partial()`
- **Form components** use `useForm` + `zodResolver` + `useMutation`
- **Reusable `FormField`** wrapper component for label + error display
- **Testing:** validate error messages, successful submit, server-side field errors

---

## Skill 7: tanstack-router-patterns (conditional: @tanstack/react-router in deps)

### Hard Rules (NON-NEGOTIABLE)

- File-based routing with code generation
- Type-safe params via `Route.useParams()`
- Search params validated with Zod schema via `validateSearch`
- Data loading through route `loader` + TanStack Query `ensureQueryData`
- `useSuspenseQuery` in components with loader — data never undefined
- Lazy loading — code-split per route by default
- Protected routes via `beforeLoad` — not JSX wrapper components
- Router context for QueryClient

### Patterns

- **File conventions:** `$param` (dynamic), `_prefix` (pathless layout), `__root.tsx` (root), `.` (nested path)
- **Root route** with `createRootRouteWithContext<RouterContext>()`
- **Data loading:** `ensureQueryData` in loader + `useSuspenseQuery` in component
- **Search params:** Zod schema + `Route.useSearch()` — URL as source of truth
- **Auth guard:** `beforeLoad` in layout route, `throw redirect(...)` if not authenticated
- **Pending UI:** `useRouterState({ select: (s) => s.isLoading })`
- **Not found:** `throw notFound()` in loader + `notFoundComponent`

---

## Skill 8: pnpm-package-manager (conditional: pnpm-lock.yaml + dep changes)

### Hard Rules (NON-NEGOTIABLE)

- `pnpm` for all package operations — never `npm` or `yarn` in pnpm projects
- `pnpm run` to execute scripts
- Lock file ALWAYS committed
- `pnpm dlx` instead of `npx`
- `--frozen-lockfile` in CI

### Patterns

- **`.npmrc`:** `strict-peer-dependencies=true`, `auto-install-peers=true`, `shamefully-hoist=false`
- **Scripts:** `dev`, `build`, `test`, `test:watch`, `test:e2e`, `typecheck`, `lint`, `format`
- **CI:** `pnpm/action-setup@v4` + `--frozen-lockfile` + typecheck -> lint -> test -> build

---

## Command: `/develop <task>`

### Frontmatter

- **Allowed tools:** Read, Grep, Glob, Bash (tsc, vitest, playwright, eslint, biome, pnpm, git)
- **Model:** Claude Opus 4.6
- **Argument hint:** `<task description>`

### 7-Step Workflow

1. Load coding-standards (MANDATORY)
2. Analyze project (package.json, tsconfig.json, src/ structure)
3. Load context-specific skills (conditional)
4. Plan implementation
5. TDD cycle
6. Quality gates (typecheck -> test -> lint)
7. Final verification checklist

## Agent: `developer`

### Frontmatter

- **Name:** `developer`
- **Model:** Claude Opus 4.6
- **Tools:** Read, Edit, Write, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList
- **Allowed Bash:** tsc, vitest, playwright, eslint, biome, pnpm, git, node

### 3 Work Modes (Auto-Detected)

| Mode | Trigger keywords | Workflow |
|------|-----------------|----------|
| Fix | "fix", "bug", "broken", "error", "issue" | Read -> Test reproducing bug -> Run (fail) -> Fix -> Run (pass) -> Refactor |
| Implement | "add", "create", "build", "implement", "new" | Identify files -> Write tests -> Run (fail) -> Implement -> Run (pass) -> Refactor |
| Refactor | "refactor", "clean", "extract", "move", "rename" | Check for tests -> Write if missing -> Refactor -> Run (pass) |

### 6-Phase Workflow

1. Parse input & detect mode (creates progress tasks)
2. Load coding-standards & detect stack
3. Load stack-specific skills
4. TDD cycle (mode-appropriate)
5. Quality gates (max 3 iterations each)
6. Report (status, skills, changes, tests, gate results)

Agent leaves changes uncommitted — user decides when to commit.

## Registration

### plugin.json

```json
{
  "name": "frontend-developer",
  "description": "Enforces TypeScript + React best practices, coding standards, TDD workflow, and modern tooling",
  "version": "1.0.0"
}
```

### marketplace.json entry

```json
{
  "name": "frontend-developer",
  "source": "./plugins/frontend-developer",
  "description": "TypeScript + React SPA development with TDD, coding standards, and stack-specific patterns",
  "version": "1.0.0",
  "category": "development"
}
```

## Usage Examples

```bash
/develop Add user profile page with avatar upload and edit form
/develop Fix the search filter not updating URL params
/develop Refactor auth module to use Zustand slices pattern
/develop Create reusable DataTable component with sorting and pagination
```

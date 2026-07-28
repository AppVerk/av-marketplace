# Frontend Developer Plugin

Advanced TypeScript + React SPA development with TDD, coding standards, and stack-specific patterns.

**Version:** 1.2.1

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
| tailwind-patterns | `tailwindcss` dep | Tailwind v4, CVA, shadcn/ui, tokens, accessibility |
| zustand-patterns | `zustand` dep | Stores, slices, middleware, selectors |
| tanstack-query-patterns | `@tanstack/react-query` dep | Server state, queryOptions, mutations, cache |
| form-patterns | `react-hook-form` dep | RHF, Zod, validation, server errors |
| tanstack-router-patterns | `@tanstack/react-router` dep | File-based routing, loaders, search params |
| pnpm-package-manager | `pnpm-lock.yaml` + deps change | pnpm commands, CI, workspace |
| bun-package-manager | `bun.lock(b)` + deps change | bun commands, lockfile policy, workspaces, CI, Bun-native tooling primer |
| state-combination-modeling | Task involves multiple boolean props/flags/permissions/states driving one component | 2^N enumeration, real/impossible confirmation, no axis-collapsing switches |

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

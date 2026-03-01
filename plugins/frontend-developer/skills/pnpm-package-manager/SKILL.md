---
name: pnpm-package-manager
description: pnpm package management, workspace setup, dependency updates, and CI integration
---

# pnpm Package Manager

## Overview

pnpm best practices for frontend projects:
- pnpm commands (add, remove, update, run)
- `.npmrc` configuration
- Lock file management
- CI/CD integration
- Workspace support (monorepos)
- Troubleshooting common issues

---

## Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS use `pnpm` for all package operations — NEVER `npm` or `yarn` in pnpm projects
- ALWAYS use `pnpm run` to execute scripts — NEVER `npm run` or `yarn`
- ALWAYS commit `pnpm-lock.yaml` — the lock file MUST be in version control
- ALWAYS use `pnpm dlx` instead of `npx` for one-off package execution
- ALWAYS use `--frozen-lockfile` in CI — NEVER allow lock file modifications in CI
- NEVER delete `pnpm-lock.yaml` to "fix" issues — resolve the underlying problem
- NEVER use `shamefully-hoist=true` unless absolutely required by a broken dependency
- ALWAYS check for existing lock file before running `pnpm install` in a new project

</HARD-RULES>

---

## Detecting pnpm Projects

Before using pnpm commands, verify the project uses pnpm:

```bash
# Check for pnpm lock file
ls pnpm-lock.yaml

# Check for pnpm workspace
ls pnpm-workspace.yaml

# Verify pnpm is available
pnpm --version
```

**If `pnpm-lock.yaml` exists → use pnpm. If `package-lock.json` exists → use npm. If `yarn.lock` exists → use yarn.** Never mix package managers.

---

## Essential Commands

### Installing Dependencies

```bash
# Install all dependencies from lock file
pnpm install

# Install with frozen lock file (CI)
pnpm install --frozen-lockfile

# Install only production dependencies
pnpm install --prod
```

### Adding Dependencies

```bash
# Add a runtime dependency
pnpm add react

# Add a dev dependency
pnpm add -D vitest @testing-library/react

# Add a specific version
pnpm add react@18.3.1

# Add to a specific workspace package (monorepo)
pnpm add lodash --filter @myapp/utils
```

### Removing Dependencies

```bash
# Remove a dependency
pnpm remove lodash

# Remove from a specific workspace package
pnpm remove lodash --filter @myapp/utils
```

### Updating Dependencies

```bash
# Update all dependencies to latest within semver range
pnpm update

# Update a specific package
pnpm update react

# Update to latest version (ignore semver range)
pnpm update react --latest

# Interactive update — shows outdated packages
pnpm update --interactive

# Check for outdated packages without updating
pnpm outdated
```

### Running Scripts

```bash
# Run a script from package.json
pnpm run dev
pnpm run build
pnpm run test
pnpm run lint

# Shorthand for common scripts
pnpm dev       # Same as pnpm run dev
pnpm test      # Same as pnpm run test
pnpm start     # Same as pnpm run start

# Run script in a specific workspace package
pnpm run build --filter @myapp/web

# Run script in all workspace packages
pnpm run build --recursive
# or shorthand
pnpm -r build
```

### One-Off Execution (dlx)

```bash
# ✅ GOOD: Use pnpm dlx instead of npx
pnpm dlx create-vite my-app --template react-ts
pnpm dlx shadcn@latest add button
pnpm dlx tsc --noEmit

# ❌ BAD: Using npx in a pnpm project
npx create-vite my-app    # WRONG — use pnpm dlx
```

---

## Package.json Scripts Template

### Standard Frontend Scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run --coverage",
    "test:watch": "vitest",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "typecheck": "tsc --noEmit",
    "lint": "eslint . --fix",
    "lint:check": "eslint .",
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  }
}
```

### Alternative with Biome

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "test": "vitest run --coverage",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit",
    "lint": "biome check --fix .",
    "lint:check": "biome check .",
    "format": "biome format --write .",
    "format:check": "biome format ."
  }
}
```

---

## .npmrc Configuration

### Recommended Settings

```ini
# .npmrc
strict-peer-dependencies=true   # Fail on peer dependency conflicts
auto-install-peers=true         # Auto-install peer deps
shamefully-hoist=false          # Strict node_modules isolation (default)
```

### What Each Setting Does

| Setting | Value | Purpose |
|---------|-------|---------|
| `strict-peer-dependencies` | `true` | Fail install if peer deps conflict — prevents runtime issues |
| `auto-install-peers` | `true` | Automatically install peer dependencies — reduces manual work |
| `shamefully-hoist` | `false` | Keep strict node_modules structure — prevents phantom dependencies |

### When to Use `shamefully-hoist=true`

Only when a dependency has a bug that requires hoisting. Document WHY:

```ini
# .npmrc
# Required: [package-name] v1.2.3 doesn't resolve correctly without hoisting
# See: https://github.com/some/issue/123
shamefully-hoist=true
```

---

## CI/CD Integration

### GitHub Actions with pnpm

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: 'pnpm'

      - name: Install dependencies
        run: pnpm install --frozen-lockfile

      - name: Type check
        run: pnpm typecheck

      - name: Lint
        run: pnpm lint:check

      - name: Test
        run: pnpm test

      - name: Build
        run: pnpm build
```

### Key CI Principles

1. **`--frozen-lockfile`** — Lock file must not change in CI. If it would, the build fails.
2. **Cache pnpm store** — `actions/setup-node` with `cache: 'pnpm'` handles this.
3. **Pipeline order:** typecheck → lint → test → build (fail fast on cheapest checks first).

---

## Workspace Support (Monorepos)

### Workspace Configuration

```yaml
# pnpm-workspace.yaml
packages:
  - 'apps/*'
  - 'packages/*'
```

### Directory Structure

```
my-monorepo/
  pnpm-workspace.yaml
  package.json              # Root — shared scripts and dev deps
  apps/
    web/                    # @myapp/web
      package.json
    admin/                  # @myapp/admin
      package.json
  packages/
    ui/                     # @myapp/ui
      package.json
    utils/                  # @myapp/utils
      package.json
```

### Workspace Commands

```bash
# Run build in all packages
pnpm -r build

# Run build only in @myapp/web
pnpm --filter @myapp/web build

# Run build in @myapp/web and all its dependencies
pnpm --filter @myapp/web... build

# Add a workspace package as dependency
pnpm add @myapp/ui --filter @myapp/web --workspace

# Add a dev dependency to the root
pnpm add -D typescript -w
```

### Cross-Package Dependencies

```json
// apps/web/package.json
{
  "dependencies": {
    "@myapp/ui": "workspace:*",
    "@myapp/utils": "workspace:*"
  }
}
```

**`workspace:*`** — Always resolve to the local workspace version. Published versions use the actual version number.

---

## Troubleshooting

### Phantom Dependencies

**Problem:** Code imports a package that isn't in `package.json` but works because another package hoisted it.

```typescript
// ❌ This works in npm/yarn but fails in pnpm (strict isolation)
import something from 'phantom-dep'; // Not in your package.json
```

**Fix:** Add the missing dependency explicitly:

```bash
pnpm add phantom-dep
```

### Peer Dependency Conflicts

**Problem:** `pnpm install` fails with peer dependency errors.

```bash
# Check what's conflicting
pnpm install 2>&1 | grep "WARN"

# Option 1: Update the conflicting package
pnpm update conflicting-package

# Option 2: If the peer dep is acceptable, override in .npmrc
# (only if you've verified compatibility)
```

**In `package.json` — use `pnpm.overrides` as last resort:**

```json
{
  "pnpm": {
    "overrides": {
      "react": "^18.3.0"
    }
  }
}
```

### Stale Lock File

**Problem:** Lock file is out of sync with `package.json`.

```bash
# Regenerate lock file
pnpm install

# Verify the lock file is correct
git diff pnpm-lock.yaml

# Commit the updated lock file
git add pnpm-lock.yaml
```

**Never delete `pnpm-lock.yaml`** — it contains resolved versions that ensure reproducible builds.

### Cache Issues

```bash
# Clear pnpm store cache
pnpm store prune

# Verify store integrity
pnpm store status

# Nuclear option — clear everything and reinstall
rm -rf node_modules
pnpm install
```

### Module Resolution Issues

```bash
# Check which version of a package is installed
pnpm list react

# Check why a package is installed (dependency tree)
pnpm why react

# List all installed packages
pnpm list --depth=0
```

---

## Common Mistakes

### ❌ Using npm/yarn in a pnpm Project

```bash
# WRONG: Mixing package managers
npm install lodash     # Creates package-lock.json — conflicts!
yarn add lodash        # Creates yarn.lock — conflicts!

# CORRECT: Always use pnpm
pnpm add lodash
```

### ❌ Deleting Lock File

```bash
# WRONG: "Fix" by deleting lock file
rm pnpm-lock.yaml
pnpm install           # Generates new lock with potentially different versions

# CORRECT: Fix the actual issue
pnpm install           # Usually resolves conflicts
pnpm update affected-package  # Update specific package
```

### ❌ Missing --frozen-lockfile in CI

```yaml
# WRONG: Allows lock file changes in CI
- run: pnpm install

# CORRECT: Fails if lock file would change
- run: pnpm install --frozen-lockfile
```

### ❌ Using npx Instead of pnpm dlx

```bash
# WRONG: npx in a pnpm project
npx create-vite my-app

# CORRECT: pnpm dlx
pnpm dlx create-vite my-app
```

---

## Summary

1. ✅ `pnpm` for all package operations — never npm/yarn in pnpm projects
2. ✅ `pnpm run` for scripts, `pnpm dlx` instead of npx
3. ✅ `pnpm-lock.yaml` always committed
4. ✅ `--frozen-lockfile` in CI
5. ✅ `.npmrc` with strict peer deps and no shameful hoisting
6. ✅ `pnpm/action-setup@v4` for GitHub Actions
7. ✅ `workspace:*` for monorepo cross-dependencies
8. ✅ Fix phantom deps by adding explicit dependencies

---
name: bun-package-manager
description: Bun package management, lockfile policy, workspaces, CI integration, and Bun-native tooling
---

# Bun Package Manager

## Overview

Bun best practices for frontend projects:
- Bun commands (add, remove, update, run, x)
- Lockfile management (`bun.lock` text vs `bun.lockb` binary)
- `bunfig.toml` configuration
- Workspace support (monorepos)
- CI/CD integration
- Troubleshooting common issues
- Bun-native tooling primer (`bun test`, `bun build`, Bun runtime)

---

## Hard Rules

<HARD-RULES>
These rules are NON-NEGOTIABLE. Violating any of them is a bug.

- ALWAYS use `bun` for all package operations — NEVER `npm`, `yarn`, or `pnpm` in Bun projects
- ALWAYS use `bun run <script>` (or implicit `bun <script>`) — NEVER `npm run`/`yarn`/`pnpm run`
- ALWAYS commit the lockfile (`bun.lock` or `bun.lockb`) — the lock file MUST be in version control
- PREFER `bun.lock` (text) over `bun.lockb` (binary) — Bun 1.2+ default, diff-friendly in PRs; migrate via `bun install --save-text-lockfile` when feasible
- ALWAYS use `bunx` instead of `npx` for one-off package execution
- ALWAYS use `--frozen-lockfile` in CI — NEVER allow lockfile modifications in CI
- NEVER delete the lockfile to "fix" issues — resolve the underlying problem
- NEVER mix package managers — if `pnpm-lock.yaml` or `package-lock.json` exists, use that manager
- ALWAYS check for existing lockfile before running `bun install` in a new project

</HARD-RULES>

---

## Detecting Bun Projects

Before using Bun commands, verify the project uses Bun:

```bash
# Check for Bun lock file (text preferred, binary legacy)
ls bun.lock bun.lockb 2>/dev/null

# Check for Bun configuration
ls bunfig.toml 2>/dev/null

# Verify Bun is available
bun --version
```

**Lockfile detection priority:**

| Found | Manager |
|---|---|
| `bun.lock` or `bun.lockb` | Bun |
| `pnpm-lock.yaml` | pnpm |
| `package-lock.json` | npm |
| `yarn.lock` | yarn |

**If two or more lockfiles are present, flag this as an anti-pattern and ask the user which manager to keep.** Never mix package managers.

---

## Essential Commands

### Installing Dependencies

```bash
# Install all dependencies from lock file
bun install

# Install with frozen lock file (CI)
bun install --frozen-lockfile

# Install only production dependencies
bun install --production

# Install and save lockfile as text (migration from bun.lockb)
bun install --save-text-lockfile
```

### Adding Dependencies

```bash
# Add a runtime dependency
bun add react

# Add a dev dependency
bun add -d vitest @testing-library/react

# Add a specific version
bun add react@18.3.1

# Add to a specific workspace package (cd into the package)
cd packages/utils && bun add lodash
```

### Removing Dependencies

```bash
# Remove a dependency
bun remove lodash

# Remove from a specific workspace package (cd into the package)
cd packages/utils && bun remove lodash
```

### Updating Dependencies

```bash
# Update all dependencies within semver range
bun update

# Update a specific package
bun update react

# Update to latest version (ignore semver range)
bun update react --latest

# Check what would change without writing
bun update --dry-run

# List outdated dependencies
bun outdated
```

### Running Scripts

```bash
# Run a script from package.json
bun run dev
bun run build
bun run test
bun run lint

# Implicit shortcut (works for any package.json script)
bun dev          # same as bun run dev
bun start        # same as bun run start
```

> **Note:** `bun test` runs Bun's **built-in test runner** (NOT the `test` script in `package.json`). To run the `test` script use `bun run test`. See the "Bun-native Tooling" section below.

### One-Off Execution (bunx)

```bash
# ✅ GOOD: Use bunx instead of npx
bunx create-vite my-app --template react-ts
bunx shadcn@latest add button
bunx tsc --noEmit

# ❌ BAD: Using npx in a Bun project
npx create-vite my-app    # WRONG — use bunx
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

Invoke with `bun run <script>` (or the implicit `bun <script>` shortcut for unambiguous names).

---

## Lockfile Management

Bun supports two lockfile formats:

| Format | File | Status | Use case |
|---|---|---|---|
| Text | `bun.lock` | **Preferred** (Bun 1.2+ default) | New projects, all PR-reviewable codebases |
| Binary | `bun.lockb` | Legacy (Bun 1.0–1.1 default) | Existing projects pre-migration |

> **Note on defaults:** Bun 1.2+ writes text-form `bun.lock` by default at the CLI level, but the `bunfig.toml` flag `[install].saveTextLockfile` defaults to `false`. New projects created with `bun init` on Bun 1.2+ get `bun.lock`; if you don't see it, run `bun install --save-text-lockfile` once or set `saveTextLockfile = true` in `bunfig.toml` to make the behaviour explicit.

### Why prefer `bun.lock` (text)?

- Reviewable in PRs — diffs are human-readable
- Conflict-resolvable — standard text merge tools work
- Tooling-friendly — scrapers, linters, and dependency auditors can read it

### Migrating from `bun.lockb` → `bun.lock`

```bash
# Write the text form on the next install
bun install --save-text-lockfile

# Remove the binary lockfile after verifying the text version
git add bun.lock
git rm bun.lockb
git commit -m "chore: migrate bun lockfile to text form"
```

After migration, all collaborators and CI must use Bun 1.2 or later (which recognises `bun.lock`).

### Coexistence rules

- **Never** have both `bun.lock` and `bun.lockb` committed simultaneously. Pick one (prefer text) and delete the other.
- **Never** have any Bun lockfile and `pnpm-lock.yaml` / `package-lock.json` / `yarn.lock` committed simultaneously.

---

## `bunfig.toml` Configuration

`bunfig.toml` is Bun's TOML-format configuration file (analog of `.npmrc`).

### Recommended settings for frontend projects

```toml
# bunfig.toml

[install]
saveTextLockfile = true     # Use bun.lock (text), not bun.lockb (binary)
exact = false               # Use semver ranges in package.json

[install.cache]
dir = "~/.bun/install/cache"
```

### Private registries / scoped tokens (analog of `.npmrc` auth)

```toml
[install.scopes]
"@my-private-scope" = { token = "$BUN_AUTH_TOKEN", url = "https://npm.my-company.com" }
```

### What each setting does

| Setting | Value | Purpose |
|---|---|---|
| `install.saveTextLockfile` | `true` | Use text-form `bun.lock` for PR-friendly diffs |
| `install.exact` | `false` | Allow semver range updates (`^x.y.z`) |

---

## Workspace Support (Monorepos)

### Workspace Configuration

Bun uses the standard `workspaces` field in the **root** `package.json` (npm-style; no separate workspace file like `pnpm-workspace.yaml`).

```json
// package.json (root)
{
  "name": "my-monorepo",
  "private": true,
  "workspaces": [
    "apps/*",
    "packages/*"
  ]
}
```

### Directory Structure

```
my-monorepo/
  package.json              # Root — workspaces + shared dev deps
  bun.lock
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
# Run a script in a specific workspace
bun run --filter @myapp/web build

# Run a script across all workspaces
bun run --filter '*' build

# Add a dependency to a specific workspace (cd into the package)
cd packages/utils && bun add lodash

# Add a dev dependency to the workspace root
bun add -d typescript
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

**`workspace:*`** — Always resolves to the local workspace version. When publishing, replace with the actual version.

---

## CI/CD Integration

### GitHub Actions with Bun

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

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Type check
        run: bun run typecheck

      - name: Lint
        run: bun run lint:check

      - name: Test
        run: bun run test

      - name: Build
        run: bun run build
```

### Pin Bun version explicitly (recommended for reproducible builds)

```yaml
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: 1.2.0    # or read from .bun-version / package.json packageManager
```

### Key CI Principles

1. **`--frozen-lockfile`** — Lockfile must not change in CI. If it would, the build fails.
2. **Pin Bun version** — Either via `bun-version:` input or a `.bun-version` file at repo root.
3. **Pipeline order:** typecheck → lint → test → build (fail fast on cheapest checks first).

---

## Troubleshooting

### Lockfile drift between `bun.lock` and `bun.lockb`

**Problem:** Project has both files committed (mixed state during migration).

**Fix:** Pick one (prefer `bun.lock`), delete the other.

```bash
bun install --save-text-lockfile
git add bun.lock
git rm bun.lockb
```

### Peer Dependency Conflicts

**Problem:** `bun install` warns about peer dependency conflicts.

```bash
# Inspect what's conflicting
bun install 2>&1 | grep -i "peer"

# Option 1: Update the conflicting package
bun update conflicting-package

# Option 2: Pin a compatible version in package.json
```

For Bun, dependency overrides are configured via the **top-level** `overrides` field in `package.json` (npm-style). Bun also recognises the Yarn-style top-level `resolutions` field as a fallback for projects migrating from Yarn:

```json
{
  "overrides": {
    "react": "^18.3.0"
  }
}
```

### Stale Lock File

```bash
# Regenerate lockfile from package.json
bun install

# Verify changes
git diff bun.lock

# Commit
git add bun.lock
```

**Never delete the lockfile** to "fix" issues — it contains resolved versions for reproducible builds.

### Cache Issues

```bash
# Clear the install cache
bun pm cache rm

# Nuclear option — clear everything and reinstall
rm -rf node_modules
bun install
```

### Module Resolution Issues

```bash
# List installed packages (top level)
bun pm ls

# List the entire dependency tree
bun pm ls --all

# Inspect why a package is installed
bun pm why react
```

---

## Bun-native Tooling (Informational)

Bun ships with a built-in test runner, bundler, and JavaScript runtime. These are **separate from** the package-manager concerns above.

**Hard rule:** Do NOT migrate existing projects from Vitest/Vite to Bun-native tooling as part of unrelated work. Only adopt Bun-native tools if the project already uses them (detected via `bunfig.toml` `[test]` section, `bun test` in `package.json` scripts, `bun build` in `package.json` scripts, or explicit user request).

### `bun test`

Detect: the project uses `bun test` if either of these is true:
- `bunfig.toml` has a `[test]` section, OR
- `package.json` `scripts.test` runs `bun test` (not `vitest`)

When the project uses `bun test`:
```bash
bun test                        # Run all tests
bun test --watch                # Watch mode
bun test --coverage             # With coverage
bun test path/to/file.test.ts   # Specific file
```

Test files: `*.test.ts`, `*.test.tsx`, `*.spec.ts`, `*.spec.tsx` (configurable in `bunfig.toml`).

When the project uses Vitest, **do NOT switch to `bun test`**. Use `bun run test` (which executes the Vitest script).

### `bun build`

Detect: the project uses `bun build` if `package.json` `scripts.build` runs `bun build` (not `vite build`).

When the project uses `bun build`:
```bash
bun build ./src/index.ts --outdir ./dist
bun build ./src/index.ts --outdir ./dist --minify
bun build ./src/index.ts --outdir ./dist --target browser
```

When the project uses Vite/Webpack/Rollup, **do NOT switch to `bun build`**. Use `bun run build`.

### Bun as runtime

Bun can run TypeScript and JSX natively without Node.js. Adopt only if:
- `package.json` `scripts` already use `bun ./script.ts` directly, OR
- The user explicitly asks for runtime adoption.

Common runtime flags:
```bash
bun --hot ./server.ts                # Hot reload server
bun --bun next dev                   # Run Next.js via Bun runtime (not Node)
bun --bun vite                       # Run Vite via Bun runtime
```

Adopting Bun runtime affects dependency compatibility — some packages assume Node APIs not present in Bun. Verify by running the dev server before committing the switch.

---

## Common Mistakes

### ❌ Using npm/yarn/pnpm in a Bun Project

```bash
# WRONG: Mixing package managers
npm install lodash         # Creates package-lock.json — conflicts!
yarn add lodash            # Creates yarn.lock — conflicts!
pnpm add lodash            # Creates pnpm-lock.yaml — conflicts!

# CORRECT: Always use bun
bun add lodash
```

### ❌ Running `bun test` when the project uses Vitest

```bash
# WRONG: Skips the configured test runner
bun test               # Runs Bun's built-in test runner

# CORRECT: Use bun run, which executes the package.json script
bun run test           # Runs vitest (or whatever scripts.test specifies)
```

### ❌ Deleting Lock File

```bash
# WRONG: "Fix" by deleting lock file
rm bun.lock
bun install            # Generates new lock with potentially different versions

# CORRECT: Fix the actual issue
bun install            # Usually resolves conflicts
bun update affected-package
```

### ❌ Missing `--frozen-lockfile` in CI

```yaml
# WRONG: Allows lock file changes in CI
- run: bun install

# CORRECT: Fails if lock file would change
- run: bun install --frozen-lockfile
```

### ❌ Using `npx` Instead of `bunx`

```bash
# WRONG: npx in a Bun project
npx create-vite my-app

# CORRECT: bunx
bunx create-vite my-app
```

---

## Summary

1. ✅ `bun` for all package operations — never npm/yarn/pnpm in Bun projects
2. ✅ `bun run` for scripts, `bunx` instead of `npx`
3. ✅ Prefer `bun.lock` (text) over `bun.lockb` (binary); always commit lockfile
4. ✅ `--frozen-lockfile` in CI
5. ✅ `bunfig.toml` with `saveTextLockfile = true`
6. ✅ `oven-sh/setup-bun@v2` for GitHub Actions
7. ✅ `workspace:*` for monorepo cross-dependencies (no separate workspace file needed)
8. ✅ Do NOT migrate from Vitest/Vite to `bun test`/`bun build` as unrelated work

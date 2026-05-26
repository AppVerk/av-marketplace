# `bun-package-manager` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `bun-package-manager` skill to the `frontend-developer` plugin, wired into `/develop` and the `developer` agent so Bun-based projects get first-class auto-loaded guidance on par with the existing `pnpm-package-manager`.

**Architecture:** Mirror `plugins/frontend-developer/skills/pnpm-package-manager/SKILL.md` 1:1 with command tokens swapped for Bun (`bun`, `bunx`, `bun.lock`), add two Bun-specific sections (Lockfile Management, Bun-native Tooling), then wire auto-load into the `/develop` command (`commands/develop.md`) and `developer` agent (`agents/developer.md`). Bump plugin version `1.0.2` → `1.1.0` (MINOR — new skill) and sync across `plugin.json`, `.claude-plugin/marketplace.json`, `README.md`, and `docs/plugins/frontend-developer.md`. The change splits into two commits matching the project's prior pattern (cf. `eb1ebf0` + `f251c61`).

**Tech Stack:** Bun, TOML (`bunfig.toml`), Markdown skill format, JSON plugin metadata, GitHub Actions YAML for CI examples.

**Spec:** `docs/superpowers/specs/2026-05-26-bun-package-manager-skill.md`

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `plugins/frontend-developer/skills/bun-package-manager/SKILL.md` | **Create** | Skill content: Hard Rules, commands, lockfile policy, workspaces, CI, bunfig.toml, troubleshooting, Bun-native tooling primer |
| `plugins/frontend-developer/commands/develop.md` | **Modify** | Add `Bash(bun:*), Bash(bunx:*)` to `allowed-tools`; Bun fallback commands in Step 2a; Bun stack detection in Step 2b; conditional skill load in Step 3; Bun line in Step 7 checklist |
| `plugins/frontend-developer/agents/developer.md` | **Modify** | Same as above, plus add `bun-package-manager` to the `skills:` frontmatter list |
| `plugins/frontend-developer/.claude-plugin/plugin.json` | **Modify** | Version `1.0.2` → `1.1.0` |
| `docs/plugins/frontend-developer.md` | **Modify** | Header version bump + new row in the Skills table |
| `.claude-plugin/marketplace.json` | **Modify** | `frontend-developer` entry version `1.0.2` → `1.1.0` |
| `README.md` | **Modify** | Available Plugins table — bump `frontend-developer` row to `1.1.0` |

**Commit plan (mirrors `eb1ebf0` + `f251c61` pattern):**

1. **`feat(frontend-developer): add bun-package-manager skill`** — Tasks 1–4. Files: skill + develop.md + developer.md + plugin.json + docs/plugins/frontend-developer.md.
2. **`chore(marketplace): sync frontend-developer to 1.1.0`** — Task 5. Files: marketplace.json + README.md.

---

## Task 1: Create the `bun-package-manager` SKILL.md

**Files:**
- Create: `plugins/frontend-developer/skills/bun-package-manager/SKILL.md`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p plugins/frontend-developer/skills/bun-package-manager
```

- [ ] **Step 2: Write the SKILL.md with full content**

Use the Write tool to create `plugins/frontend-developer/skills/bun-package-manager/SKILL.md` with **exactly** the following content:

````markdown
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

# Add to a specific workspace package (monorepo)
bun add lodash --filter @myapp/utils
```

### Removing Dependencies

```bash
# Remove a dependency
bun remove lodash

# Remove from a specific workspace package
bun remove lodash --filter @myapp/utils
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
saveTextLockfile = true     # Use bun.lock, not bun.lockb
auto = "auto"               # Auto-install peer deps
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
| `install.auto` | `"auto"` | Resolve peer dependencies automatically |
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

# Add a dependency to a specific workspace
bun add lodash --filter @myapp/utils

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

For Bun, peer-dependency overrides are configured via `package.json#bun.overrides` (analog of `pnpm.overrides`):

```json
{
  "bun": {
    "overrides": {
      "react": "^18.3.0"
    }
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
5. ✅ `bunfig.toml` with `saveTextLockfile = true` and `auto = "auto"`
6. ✅ `oven-sh/setup-bun@v2` for GitHub Actions
7. ✅ `workspace:*` for monorepo cross-dependencies (no separate workspace file needed)
8. ✅ Do NOT migrate from Vitest/Vite to `bun test`/`bun build` as unrelated work
````

- [ ] **Step 3: Verify file is well-formed**

```bash
wc -l plugins/frontend-developer/skills/bun-package-manager/SKILL.md
head -5 plugins/frontend-developer/skills/bun-package-manager/SKILL.md
grep -c "^## " plugins/frontend-developer/skills/bun-package-manager/SKILL.md
```

Expected:
- Line count: roughly 480 lines (`wc -l` between 460 and 520 is acceptable).
- First 5 lines: frontmatter (`---`, `name: bun-package-manager`, `description: ...`, `---`, blank).
- Section count (`^## `): **13** — Overview, Hard Rules, Detecting Bun Projects, Essential Commands, Package.json Scripts Template, Lockfile Management, `bunfig.toml` Configuration, Workspace Support (Monorepos), CI/CD Integration, Troubleshooting, Bun-native Tooling (Informational), Common Mistakes, Summary.

If the section count or first-5-line check fails, re-read the file and confirm all sections were written.

---

## Task 2: Update `commands/develop.md` with Bun integration

**Files:**
- Modify: `plugins/frontend-developer/commands/develop.md`

- [ ] **Step 1: Extend `allowed-tools` frontmatter**

Replace the frontmatter line at the top of the file:

```
allowed-tools: Read, Grep, Glob, Bash(tsc:*), Bash(vitest:*), Bash(playwright:*), Bash(eslint:*), Bash(biome:*), Bash(pnpm:*), Bash(git:*), Bash(node:*)
```

with:

```
allowed-tools: Read, Grep, Glob, Bash(tsc:*), Bash(vitest:*), Bash(playwright:*), Bash(eslint:*), Bash(biome:*), Bash(pnpm:*), Bash(bun:*), Bash(bunx:*), Bash(git:*), Bash(node:*)
```

- [ ] **Step 2: Add Bun fallback commands in Step 2a**

In Step 2a, the current fallback block reads:

```markdown
**Record the discovered commands.** You will use them in Steps 5 and 6 instead of fallback defaults. If no commands are found in any of these sources, fall back to:
- Dev: `pnpm dev`
- Test: `pnpm test`
- Test watch: `pnpm test:watch`
- Typecheck: `pnpm typecheck` (or `pnpm tsc --noEmit`)
- Lint: `pnpm lint`
```

Replace it with:

```markdown
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
```

- [ ] **Step 3: Add Bun detection in Step 2b**

The current Step 2b bullet list reads:

```markdown
1. **package.json** — look for dependencies:
   - `tailwindcss` — Tailwind CSS
   - `zustand` — Zustand state management
   - `@tanstack/react-query` — TanStack Query
   - `react-hook-form` — React Hook Form
   - `@tanstack/react-router` — TanStack Router
2. **pnpm-lock.yaml** — confirm pnpm is the package manager
3. **tsconfig.json** — verify `strict: true` is enabled
4. **src/** — scan directory structure to detect feature-based architecture
5. **Task description** — parse `$ARGUMENTS` for keywords: component, form, route, state, query, API, store
```

Replace bullet 2 with:

```markdown
2. **Lockfile** — confirm which package manager the project uses:
   - `bun.lock` or `bun.lockb` → Bun
   - `pnpm-lock.yaml` → pnpm
   - `package-lock.json` → npm
   - `yarn.lock` → yarn
   - If multiple lockfiles are present, flag this as an anti-pattern and ask the user which manager to keep
```

(Numbering stays the same — bullets 3/4/5 are unaffected.)

- [ ] **Step 4: Add the Bun conditional skill load in Step 3**

The current pnpm conditional in Step 3 reads:

```markdown
### If `pnpm-lock.yaml` exists AND task involves dependency changes:

```
Use the Skill tool with:
  skill: "frontend-developer:pnpm-package-manager"
```
```

Immediately after that block (and before the line `**After loading skills, read and internalize the HARD-RULES from every loaded skill. You must follow all of them.**`), insert:

```markdown
### If `bun.lock` or `bun.lockb` exists AND task involves dependency changes:

```
Use the Skill tool with:
  skill: "frontend-developer:bun-package-manager"
```
```

- [ ] **Step 5: Add Bun line to Step 7 verification checklist**

In Step 7, the current "Stack-Specific" checklist ends with:

```markdown
- [ ] pnpm: `pnpm` commands only, lock file committed
```

Replace that line with:

```markdown
- [ ] pnpm: `pnpm` commands only, lock file committed
- [ ] bun: `bun` commands only, lockfile committed (prefer `bun.lock` text form)
```

- [ ] **Step 6: Verify the edits**

```bash
grep -n "Bash(bun:\*)" plugins/frontend-developer/commands/develop.md
grep -n "bun.lock" plugins/frontend-developer/commands/develop.md
grep -n "bun-package-manager" plugins/frontend-developer/commands/develop.md
```

Expected:
- `Bash(bun:*)` appears once on the frontmatter line.
- `bun.lock` appears in Step 2a (fallback selection), Step 2b (detection), and Step 3 (skill load condition) — at least 3 hits.
- `bun-package-manager` appears once in Step 3.

---

## Task 3: Update `agents/developer.md` with Bun integration

**Files:**
- Modify: `plugins/frontend-developer/agents/developer.md`

- [ ] **Step 1: Add `bun-package-manager` to the `skills:` frontmatter list**

The current frontmatter has:

```
skills: coding-standards, tdd-workflow, tailwind-patterns, zustand-patterns, tanstack-query-patterns, form-patterns, tanstack-router-patterns, pnpm-package-manager
```

Replace with:

```
skills: coding-standards, tdd-workflow, tailwind-patterns, zustand-patterns, tanstack-query-patterns, form-patterns, tanstack-router-patterns, pnpm-package-manager, bun-package-manager
```

- [ ] **Step 2: Extend `allowed-tools` frontmatter**

The current line:

```
allowed-tools: Bash(tsc:*), Bash(vitest:*), Bash(playwright:*), Bash(eslint:*), Bash(biome:*), Bash(pnpm:*), Bash(git:*), Bash(node:*)
```

Replace with:

```
allowed-tools: Bash(tsc:*), Bash(vitest:*), Bash(playwright:*), Bash(eslint:*), Bash(biome:*), Bash(pnpm:*), Bash(bun:*), Bash(bunx:*), Bash(git:*), Bash(node:*)
```

- [ ] **Step 3: Add Bun fallback commands in Step 2.5**

The current Step 2.5 fallback block reads:

```markdown
**Record the discovered commands.** If no commands are found, fall back to:

- Test: `pnpm test`
- Typecheck: `pnpm typecheck`
- Lint: `pnpm lint`
```

Replace with:

```markdown
**Record the discovered commands.** If no commands are found, pick the fallback set that matches the detected package manager:

**If `bun.lock` or `bun.lockb` exists** (Bun project):
- Test: `bun run test` (use `bun test` only if `bunfig.toml` has a `[test]` section)
- Typecheck: `bun run typecheck`
- Lint: `bun run lint`

**Otherwise** (default — pnpm or unspecified):
- Test: `pnpm test`
- Typecheck: `pnpm typecheck`
- Lint: `pnpm lint`
```

- [ ] **Step 4: Add the Bun conditional skill load in Phase 3**

The current "If dependency changes are needed" block in Phase 3 reads:

```markdown
**If dependency changes are needed:**

```
Use the Skill tool with:
  skill: "frontend-developer:pnpm-package-manager"
```
```

Replace it with:

```markdown
**If dependency changes are needed:**

Pick the skill matching the detected lockfile:

- If `pnpm-lock.yaml` exists:
  ```
  Use the Skill tool with:
    skill: "frontend-developer:pnpm-package-manager"
  ```
- If `bun.lock` or `bun.lockb` exists:
  ```
  Use the Skill tool with:
    skill: "frontend-developer:bun-package-manager"
  ```
```

- [ ] **Step 5: Verify the edits**

```bash
grep -n "bun-package-manager" plugins/frontend-developer/agents/developer.md
grep -n "Bash(bun:\*)" plugins/frontend-developer/agents/developer.md
grep -n "bun.lock" plugins/frontend-developer/agents/developer.md
```

Expected:
- `bun-package-manager` appears twice — once in the `skills:` frontmatter, once in the Phase 3 skill load.
- `Bash(bun:*)` appears once on the `allowed-tools` line.
- `bun.lock` appears at least twice (fallback selection + Phase 3 detection).

---

## Task 4: Bump plugin version and update plugin docs (commit 1 finalization)

**Files:**
- Modify: `plugins/frontend-developer/.claude-plugin/plugin.json`
- Modify: `docs/plugins/frontend-developer.md`

- [ ] **Step 1: Bump `plugin.json` to 1.1.0**

Current content of `plugins/frontend-developer/.claude-plugin/plugin.json`:

```json
{
  "name": "frontend-developer",
  "description": "Enforces TypeScript + React best practices, coding standards, TDD workflow, and modern tooling (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router)",
  "version": "1.0.2"
}
```

Replace with:

```json
{
  "name": "frontend-developer",
  "description": "Enforces TypeScript + React best practices, coding standards, TDD workflow, and modern tooling (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router)",
  "version": "1.1.0"
}
```

- [ ] **Step 2: Validate the JSON**

```bash
jq . plugins/frontend-developer/.claude-plugin/plugin.json > /dev/null && echo "valid JSON"
```

Expected output: `valid JSON`.

- [ ] **Step 3: Update `docs/plugins/frontend-developer.md` header version**

Change line 5 from:

```markdown
**Version:** 1.0.2
```

to:

```markdown
**Version:** 1.1.0
```

- [ ] **Step 4: Add a new row to the Skills table**

The current Skills table ends with:

```markdown
| pnpm-package-manager | `pnpm-lock.yaml` + deps change | pnpm commands, CI, workspace |
```

Add **immediately below** that line:

```markdown
| bun-package-manager | `bun.lock(b)` + deps change | bun commands, lockfile policy, workspaces, CI, Bun-native tooling primer |
```

- [ ] **Step 5: Sanity check `docs/plugins/frontend-developer.md`**

```bash
grep -n "1.1.0\|bun-package-manager" docs/plugins/frontend-developer.md
```

Expected: at least two matches — the version line on line 5 and the new Skills table row.

- [ ] **Step 6: Stage the commit-1 files**

```bash
AV_COMMIT_SKILL=1 git add plugins/frontend-developer/skills/bun-package-manager/SKILL.md \
                          plugins/frontend-developer/commands/develop.md \
                          plugins/frontend-developer/agents/developer.md \
                          plugins/frontend-developer/.claude-plugin/plugin.json \
                          docs/plugins/frontend-developer.md
```

- [ ] **Step 7: Verify staging**

```bash
git diff --cached --stat
```

Expected: five files listed (`SKILL.md` as `create mode 100644`; the other four as modifications).

- [ ] **Step 8: Create commit 1**

```bash
AV_COMMIT_SKILL=1 git commit -m "feat(frontend-developer): add bun-package-manager skill

Add skills/bun-package-manager/SKILL.md modeled on the existing
pnpm-package-manager skill with Bun-specific commands (bun, bunx),
lockfile policy (prefer bun.lock text over bun.lockb binary),
bunfig.toml configuration, monorepo workspaces, CI/CD with
oven-sh/setup-bun@v2, troubleshooting, and a non-prescriptive
Bun-native tooling primer (bun test, bun build, runtime).

Wires auto-load into commands/develop.md and agents/developer.md
when bun.lock(b) is detected and the task involves dependency
changes. Adds Bash(bun:*) and Bash(bunx:*) to allowed-tools, Bun
fallback commands when project commands cannot be discovered, and
a Bun-specific row to the verification checklist.

Bumps plugin version 1.0.2 → 1.1.0 (MINOR) and adds the new skill
to the Skills table in docs/plugins/frontend-developer.md."
```

Expected: commit succeeds; `git log -1 --oneline` shows the new commit.

---

## Task 5: Sync marketplace.json and README.md (commit 2)

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

- [ ] **Step 1: Bump the `frontend-developer` entry in `marketplace.json`**

Locate the entry whose `"name"` is `"frontend-developer"` (currently around lines 21–27):

```json
    {
      "name": "frontend-developer",
      "source": "./plugins/frontend-developer",
      "description": "Enforces TypeScript + React best practices, coding standards, TDD workflow, and modern tooling (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router)",
      "version": "1.0.2",
      "category": "development"
    },
```

Change the `version` field to `1.1.0`:

```json
    {
      "name": "frontend-developer",
      "source": "./plugins/frontend-developer",
      "description": "Enforces TypeScript + React best practices, coding standards, TDD workflow, and modern tooling (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router)",
      "version": "1.1.0",
      "category": "development"
    },
```

- [ ] **Step 2: Validate the JSON**

```bash
jq '.plugins[] | select(.name=="frontend-developer")' .claude-plugin/marketplace.json
```

Expected output: a JSON object with `"version": "1.1.0"`.

- [ ] **Step 3: Bump the `Frontend Developer` row in `README.md`**

Change line 24 from:

```markdown
| [Frontend Developer](docs/plugins/frontend-developer.md) | 1.0.2 | TypeScript + React development workflow with `/develop` command and autonomous `developer` agent. Coding standards, TDD, and stack-specific patterns (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router) |
```

to:

```markdown
| [Frontend Developer](docs/plugins/frontend-developer.md) | 1.1.0 | TypeScript + React development workflow with `/develop` command and autonomous `developer` agent. Coding standards, TDD, and stack-specific patterns (Tailwind, Zustand, TanStack Query, React Hook Form, TanStack Router) |
```

(Only the version column changes from `1.0.2` to `1.1.0`. The description is unchanged.)

- [ ] **Step 4: Run the plugin version parity check**

```bash
python3 scripts/check_plugin_versions.py
```

Expected output includes:

```
[frontend-developer] 1.1.0 (OK)
...
Version parity OK for 8 plugin(s).
```

If parity fails, the script will print which file is out of sync. Fix the offending file and re-run before continuing.

- [ ] **Step 5: Stage the commit-2 files**

```bash
AV_COMMIT_SKILL=1 git add .claude-plugin/marketplace.json README.md
```

- [ ] **Step 6: Verify staging**

```bash
git diff --cached --stat
```

Expected: two files listed, both as modifications.

- [ ] **Step 7: Create commit 2**

```bash
AV_COMMIT_SKILL=1 git commit -m "chore(marketplace): sync frontend-developer to 1.1.0

Refresh marketplace.json and the README plugin table to reflect
the new bun-package-manager skill introduced in
frontend-developer 1.1.0."
```

Expected: commit succeeds; `git log -2 --oneline` shows both commits.

- [ ] **Step 8: Final post-commit parity check**

```bash
python3 scripts/check_plugin_versions.py && git status
```

Expected: parity OK, working tree clean.

---

## Task 6: Final integration smoke test (user-driven)

After the two commits land, a Claude Code session must be reloaded for the new skill registration to take effect. This task is executed by the user — the implementing agent cannot reload the session.

- [ ] **Step 1: Restart / reload Claude Code**

Restart the Claude Code session in this project so the updated `plugins/frontend-developer/` files are re-read.

- [ ] **Step 2: Confirm the skill is registered**

In a new Claude prompt, ask Claude to list available skills (e.g. via `/help` or by invoking the Skill tool listing). Verify that `frontend-developer:bun-package-manager` appears.

- [ ] **Step 3: Verify auto-load in a Bun project**

In a project containing `bun.lock` (or `bun.lockb`), run:

```
/develop add the `zod` dependency
```

Verify (from the load log or skill announcement) that `frontend-developer:bun-package-manager` is among the loaded skills, and that the fallback commands used (if any) are the Bun ones (`bun run test`, `bun run lint`, etc.).

- [ ] **Step 4: Verify no regression in pnpm projects**

In a project containing `pnpm-lock.yaml`, run:

```
/develop add the `zod` dependency
```

Verify that `frontend-developer:pnpm-package-manager` is loaded and `frontend-developer:bun-package-manager` is NOT.

- [ ] **Step 5: Verify innocuous changes still work**

In any project (Bun or pnpm), run a non-dependency-changing task such as:

```
/develop refactor the Header component to extract NavLinks
```

Verify that neither package-manager skill is auto-loaded (task does not involve dependency changes).

If any step fails, revert with `git revert HEAD~1..HEAD` (reverts both commits), investigate, and re-apply.

---

## Self-Review Notes

**Spec coverage:** Each section of the spec maps to a task:

| Spec section | Task(s) |
|---|---|
| Architecture (file structure table) | Task 1 (skill), Task 2 (develop.md), Task 3 (developer.md), Task 4 (plugin.json + docs), Task 5 (marketplace + README) |
| SKILL.md structure (10 sections) | Task 1 Step 2 — the full file content embedded |
| Hard Rules (Bun) | Task 1 Step 2 (in the "Hard Rules" block) |
| Auto-load wiring (develop.md) | Task 2 Steps 1–5 |
| Auto-load wiring (developer.md) | Task 3 Steps 1–4 |
| Versioning (1.0.2 → 1.1.0) | Task 4 Step 1, Task 4 Step 3, Task 5 Step 1, Task 5 Step 3 |
| Documentation updates | Task 4 Step 4, Task 5 Step 3 |
| Behaviour and edge cases (lockfile detection priority) | Task 1 Step 2 (Detecting Bun Projects section) + Task 2 Step 3 (Step 2b bullet 2) |
| Testing (manual smoke test) | Task 6 |
| Rollback | Implicit in the two-commit structure (single `git revert HEAD~1..HEAD` reverts everything) |

**Placeholder scan:** every code/JSON/Markdown block contains concrete content. No "TBD", "similar to above", or "add error handling" left in the plan.

**Type/text consistency:** version `1.1.0` is used identically in `plugin.json` (Task 4 Step 1), `docs/plugins/frontend-developer.md` (Task 4 Step 3), `marketplace.json` (Task 5 Step 1), `README.md` (Task 5 Step 3). The skill name `bun-package-manager` is identical in the file path (Task 1), the `skills:` frontmatter (Task 3 Step 1), the develop.md conditional (Task 2 Step 4), the developer.md conditional (Task 3 Step 4), and the docs Skills row (Task 4 Step 4).

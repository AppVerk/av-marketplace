# `bun-package-manager` skill — Design Spec

**Date:** 2026-05-26
**Status:** Approved (awaiting implementation plan)
**Owner:** Marian Szenfeld
**Plugin affected:** `plugins/frontend-developer`

## Goal

Add a new `bun-package-manager` skill to the `frontend-developer` plugin, providing structured guidance for Bun-based frontend projects on par with the existing `pnpm-package-manager` skill. Auto-load the skill in the `/develop` command and `developer` agent when a Bun lockfile is present, mirroring the pnpm wiring.

## Motivation

`frontend-developer` already enforces strict workflows for pnpm-based projects (commands, lockfile policy, CI integration). Bun is increasingly used in TypeScript + React projects (notably for fast cold-start dev servers and Bun-native test/build tooling), but the plugin currently has no equivalent guidance. Without a Bun skill, the `/develop` flow falls back to pnpm-centric defaults that don't apply, and the agent has no `Bash(bun:*)` permission. A dedicated skill makes Bun a first-class supported package manager in the plugin.

## Scope

**In scope:**
- New skill file at `plugins/frontend-developer/skills/bun-package-manager/SKILL.md` (~700 lines).
- Hard rules covering Bun package operations, lockfile policy, CI, and tooling boundaries.
- Coverage of Bun-native tooling (`bun test`, `bun build`, Bun-as-runtime) as **informational** sections — not prescriptive migration guidance.
- Auto-load wiring in `plugins/frontend-developer/commands/develop.md` and `plugins/frontend-developer/agents/developer.md` (skill load + `allowed-tools` + stack detection + fallback commands).
- Documentation updates: `docs/plugins/frontend-developer.md`, `README.md`, `.claude-plugin/marketplace.json`.
- Plugin version bump `1.0.2` → `1.1.0` (MINOR — new skill).

**Out of scope:**
- Refactoring `pnpm-package-manager` (no shared-base extraction).
- Migrating existing Bun-test or Bun-build projects' tooling configuration.
- Bun runtime adoption guidance beyond the informational section.
- Backwards-compatibility shims for projects with both `pnpm-lock.yaml` and `bun.lock(b)` — the existing "never mix package managers" rule covers that anti-pattern.

## Design

### Architecture

The skill is a structural mirror of `pnpm-package-manager` with command tokens swapped and two added sections for Bun-native tooling. It is registered as a new entry under `frontend-developer:bun-package-manager` and consumed in two integration points (`develop.md` command, `developer.md` agent) plus four sync touchpoints (`plugin.json`, `marketplace.json`, `README.md`, `docs/plugins/frontend-developer.md`).

No changes to `pnpm-package-manager`. The "never mix package managers" hard rule already in the pnpm skill is duplicated (parity) in the Bun skill so each skill is self-contained.

### File structure

| Path | Action | Responsibility |
|---|---|---|
| `plugins/frontend-developer/skills/bun-package-manager/SKILL.md` | **Create** | The skill content |
| `plugins/frontend-developer/commands/develop.md` | **Modify** | Add `Bash(bun:*), Bash(bunx:*)` to `allowed-tools`; add Bun stack detection in Step 2b; add Bun fallback commands in Step 2a; add auto-load condition in Step 4 (or equivalent location) |
| `plugins/frontend-developer/agents/developer.md` | **Modify** | Same as above, plus add `bun-package-manager` to the `skills:` frontmatter list |
| `plugins/frontend-developer/.claude-plugin/plugin.json` | **Modify** | Version `1.0.2` → `1.1.0` |
| `.claude-plugin/marketplace.json` | **Modify** | `frontend-developer` entry version `1.0.2` → `1.1.0` |
| `README.md` | **Modify** | Available Plugins table — bump `frontend-developer` row to `1.1.0` |
| `docs/plugins/frontend-developer.md` | **Modify** | Header version bump + new row in the Skills table |

### SKILL.md structure

Ten sections in order, mirroring `pnpm-package-manager`:

1. **Overview** — what the skill covers (Bun commands, `.bunfig.toml`, lockfile, workspaces, CI, Bun-native tooling primer).
2. **Hard Rules** — `<HARD-RULES>` block enumerating non-negotiable rules (see "Hard Rules" subsection below).
3. **Detecting Bun Projects** — check order: `bun.lock` (text, preferred), `bun.lockb` (binary, legacy), `bunfig.toml`, `bun --version`. Cross-reference: if `pnpm-lock.yaml` or `package-lock.json` also exists → flag mixed-manager anti-pattern.
4. **Essential Commands** — `bun install`, `bun add [-d|-D]`, `bun remove`, `bun update`, `bun run <script>` (and implicit `bun <script>`), `bun outdated`. Examples mirror the pnpm skill.
5. **Lockfile Management** — `bun.lock` vs `bun.lockb`, why prefer text, migration via `bun install --save-text-lockfile`, CI behavior of `--frozen-lockfile`.
6. **Workspaces** — `workspaces` field in root `package.json`, per-workspace commands, `bun add <dep> --workspace=<name>`.
7. **CI Integration** — `bun install --frozen-lockfile`, cache paths (`~/.bun/install/cache`), GitHub Actions example using `oven-sh/setup-bun@v2`.
8. **`bunfig.toml` Configuration** — registry, scopes, install behavior, the analog of `.npmrc`.
9. **Troubleshooting** — common issues (stale cache, lockfile drift, mixed-manager detection, transitive dep mismatches between `bun.lock` and `bun.lockb` during migration).
10. **Bun-native Tooling (Informational)** — three short sub-sections:
    - **`bun test`** — when the project already uses it (`bunfig.toml [test]` section or `bun test` in scripts). Do NOT migrate from Vitest.
    - **`bun build`** — same shape; do NOT migrate from Vite/Webpack.
    - **Bun as runtime** — `bun --hot`, `bun --bun next dev`. Only if explicitly configured by the user/project.

### Hard Rules (Bun)

```
- ALWAYS use `bun` for all package operations — NEVER npm/yarn/pnpm in Bun projects
- ALWAYS use `bun run <script>` (or implicit `bun <script>`) — NEVER `npm run`/`yarn`/`pnpm run`
- ALWAYS commit the lockfile (`bun.lock` or `bun.lockb`) to version control
- PREFER `bun.lock` (text) over `bun.lockb` (binary) — text is the Bun 1.2+ default
  and is diff-friendly in PRs. Migrate via `bun install --save-text-lockfile` when feasible.
- ALWAYS use `bunx` instead of `npx` for one-off package execution
- ALWAYS use `--frozen-lockfile` in CI — NEVER allow lockfile modifications in CI
- NEVER delete the lockfile to "fix" issues — resolve the underlying problem
- NEVER mix package managers — if `pnpm-lock.yaml` or `package-lock.json` exists, use that
  manager instead; one lockfile per project
```

The Bun-native tooling sections (10) are **informational** and not part of hard rules. The skill explicitly does NOT prescribe migrating Vitest → `bun test` or Vite → `bun build`.

### Auto-load wiring

#### `commands/develop.md` changes

1. **Frontmatter `allowed-tools`** — append `Bash(bun:*), Bash(bunx:*)` to the existing list.
2. **Step 2a (Discover project commands)** — extend fallback block: if `bun.lock` or `bun.lockb` is present and no commands were found in CLAUDE.md/README/package.json/Makefile, use Bun fallbacks:
   - Dev: `bun dev`
   - Test: `bun test` (if `bunfig.toml [test]` is configured) or `bun run test`
   - Test watch: `bun test --watch` or `bun run test:watch`
   - Typecheck: `bun run typecheck` (or `bun tsc --noEmit`)
   - Lint: `bun run lint`
   Pnpm fallback remains the default when no Bun lockfile is detected.
3. **Step 2b (Detect the project stack)** — add a bullet:
   - `bun.lock` / `bun.lockb` → confirm Bun is the package manager
4. **Skill-load section** — add a condition mirroring the pnpm one:
   ```
   If `bun.lock` or `bun.lockb` exists AND task involves dependency changes:
     Skill: "frontend-developer:bun-package-manager"
   ```
5. **Final checklist** — add a line analogous to the pnpm one:
   - `[ ] bun: bun commands only, lockfile committed (prefer bun.lock text form)`

#### `agents/developer.md` changes

Same as `develop.md` plus:
- Append `bun-package-manager` to the `skills:` frontmatter array.

### Versioning

Per `CLAUDE.local.md`:
- New skill = new feature → **MINOR** bump.
- `plugins/frontend-developer/.claude-plugin/plugin.json`: `1.0.2` → `1.1.0`.
- `.claude-plugin/marketplace.json` `frontend-developer` entry: `1.0.2` → `1.1.0`.
- `README.md` Available Plugins row: `1.0.2` → `1.1.0`.
- `docs/plugins/frontend-developer.md` `**Version:** 1.0.2` → `**Version:** 1.1.0`.
- The `scripts/check_plugin_versions.py` parity check must pass after all four are aligned.

### Documentation updates

`docs/plugins/frontend-developer.md` — add a new row to the Skills table, placed after the existing `pnpm-package-manager` row:

```markdown
| bun-package-manager | `bun.lock(b)` + deps change | bun commands, lockfile policy, workspaces, CI, Bun-native tooling primer |
```

`README.md` Available Plugins row — bump the version cell only; the one-line description does not need to change (the plugin remains a TypeScript + React development workflow; the Bun skill is conditional).

`.claude-plugin/marketplace.json` `frontend-developer` entry — bump `version`; description unchanged.

## Behaviour and edge cases

| Project state | Expected behaviour |
|---|---|
| `bun.lock` exists, no other lockfile | Bun skill auto-loads on deps-changing tasks; `/develop` uses `bun` fallbacks |
| `bun.lockb` exists, no other lockfile | Same as above; skill recommends migrating to `bun.lock` (no enforcement) |
| `pnpm-lock.yaml` exists, no Bun lockfile | Pnpm skill auto-loads as before; Bun skill stays dormant |
| Both `bun.lock` and `pnpm-lock.yaml` exist | Both skills load; each Hard-Rules block flags the mixed-manager state. Resolution is the user's call (the skill does not auto-pick) |
| Neither lockfile present, new project | Neither skill auto-loads (matches current pnpm behaviour); `/develop` keeps pnpm fallback defaults |
| `bun test` configured but no Bun lockfile | Anti-pattern; skill does not auto-load purely on `bun test` presence. (Acceptable — extremely niche; lockfile is the canonical signal.) |
| Bun runtime project without npm-style `package.json` | Out of scope for `frontend-developer` plugin (this plugin targets TypeScript + React SPAs) |

## Testing

No automated tests for skills exist in this project (consistent with `pnpm-package-manager`, all other skills, and the plugin-as-data architecture). Manual smoke test after implementation:

1. In a sample project containing `bun.lock`, run `/develop "add zod dependency"` — verify the load log lists `frontend-developer:bun-package-manager` and the Bun command fallbacks are used.
2. In a sample project containing `pnpm-lock.yaml`, run `/develop "add zod dependency"` — verify `pnpm-package-manager` is loaded and `bun-package-manager` is NOT (no regression).
3. Run `python3 scripts/check_plugin_versions.py` — confirm `[frontend-developer] 1.1.0 (OK)` and overall `Version parity OK`.
4. Open `docs/plugins/frontend-developer.md` and verify the Skills table renders correctly with the new row.

## Rollback

The change is additive and reversible. Revert path:
1. `git revert <commits>` for the two commits introduced by the implementation plan, or:
2. Manual revert: delete `plugins/frontend-developer/skills/bun-package-manager/`, revert `allowed-tools` and Step 2 changes in `develop.md` and `developer.md`, restore `1.0.2` in all four version locations, and remove the docs row.

No persistent state, runtime hooks, or external dependencies are introduced.

## Open questions

None. The four design decisions made during brainstorming were:
1. **Scope of integration:** Full integration (skill + develop wiring + agent wiring + docs sync + version bump) — analogous to `pnpm-package-manager`.
2. **Thematic coverage:** Package manager core + Bun-native tooling primer (informational only, no migration prescriptions).
3. **Lockfile policy:** Prefer `bun.lock` (text); `bun.lockb` allowed as legacy with optional migration guidance.
4. **Structure:** Mirror `pnpm-package-manager` 1:1 (no shared-base extraction).

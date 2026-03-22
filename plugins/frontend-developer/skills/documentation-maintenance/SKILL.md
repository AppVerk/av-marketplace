---
name: documentation-maintenance
description: Detects project documentation and updates it to reflect code changes. Conditionally loaded — only when documentation exists in the project. Analyzes changes, classifies impact, and applies updates.
---

# Documentation Maintenance

Detects project documentation structure and updates it to reflect code changes made during the current session. Runs as Phase 6 in the developer workflow.

---

## Purpose

When a developer agent changes code, existing documentation can become outdated. This skill:

1. Detects if the project has documentation
2. Maps which docs cover which topics
3. Compares code changes against the documentation map
4. Updates or extends documentation to match the new code state

**This skill only maintains existing documentation. It never creates documentation from scratch.**

---

## Phase 6: Documentation Maintenance

### Step 1: Detect Documentation

Run the documentation detection algorithm. If the documentation map was already built during Phase 2, use the stored result. Otherwise, run detection now.

**Detection algorithm:**

1. **Look for docs directory** — check existence of `docs/`, `doc/`, `documentation/` in project root. If found, scan structure (subdirectories, .md files).

2. **Look for mentions in meta-files** — search `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `AGENTS.md` for keywords: "documentation", "docs", "dokumentacja". If they point to a non-standard location, use it.

3. **Look for scattered .md files** — Glob `**/*.md` in root (max 2 levels deep). Filter out standard files: README, CHANGELOG, LICENSE, CODE_OF_CONDUCT. If other .md files remain, treat as documentation.

4. **Decision:**
   - Found anything → build documentation map (paths + recognized topics)
   - Found nothing → **skip this phase entirely**, mark task as completed, report "No documentation detected in project"

**Limits:**
- If documentation map exceeds 50 files, only process docs that share directory paths or topic keywords with changed files
- In monorepos, detection runs at project root level only

### Step 2: Analyze Changes

Review all files created or modified during the current session:

- New files (classes, modules, endpoints, components)
- Modified function signatures, parameters, return types
- Changed configuration or environment variables
- Removed or renamed public APIs

Compare each change against the documentation map stored in context — which docs might be affected?

### Step 3: Classify Impact

For each potential documentation impact, classify as:

- **UPDATE** — existing doc describes something that changed (e.g., changed endpoint, new parameter, renamed function)
- **ADD** — new functionality was added AND an existing doc file covers the same directory, module, or topic area. If unsure whether the new functionality fits existing docs structure, classify as NONE and note it in the report.
- **NONE** — changes don't affect any documentation (internal refactoring, test changes, non-public code)

If all changes classify as NONE, mark task as completed and report "No documentation changes needed."

### Step 4: Apply Changes

For each UPDATE or ADD item:

1. Read the target documentation file
2. Identify the exact section that needs updating (or the section after which new content should be added)
3. Apply the change using the Edit tool — match the existing style, tone, and formatting of the document
4. If the project has markdown linting (check for `.markdownlint.json`, `.markdownlint.yaml`, or markdownlint in package.json/pyproject.toml), run the linter on modified docs

**Important:**
- Match the existing documentation style — if docs use bullet points, use bullet points; if they use tables, use tables
- Do not restructure existing documentation
- Keep additions minimal and focused on the actual change
- Preserve existing formatting, heading levels, and conventions

### Step 5: Report

Add the following to the developer report (Phase 7):

```
**Documentation:**
- `docs/api/endpoints.md:45` - Updated parameter description for /users endpoint
- `docs/architecture.md:120` - Added notification service section
```

Or if no changes were needed:

```
**Documentation:** No documentation changes needed
```

Or if no documentation was detected:

```
**Documentation:** No documentation detected in project (skipped)
```

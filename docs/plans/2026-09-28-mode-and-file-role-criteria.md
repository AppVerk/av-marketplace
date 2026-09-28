# Criteria instead of keyword tables: developer mode and QA file role

## Context

Two decisions in our prose are keyword tables that a model applies literally: the developer agents' working mode (Fix / Refactor / Implement) and the QA planner's FE/BE file classification. On 2026-09-28 we measured them on labelled sets (`/tmp/jev-tests/t1a.json`, `/tmp/jev-tests/t4.json`, clear items only):

| Decision | Big model + current table | Big model + criteria (text below) | Jev + criteria |
|---|---|---|---|
| Working mode, 37 tasks | 91.9% | 100% | 100% |
| File role, 40 files | 95.0% | 100% | 100% |

The gain comes from replacing the tables with criteria, not from the model. This plan therefore changes only the prose and adds no Jev call: the agent that already makes the decision keeps making it, in Claude Code and in OMP alike. Jev stays where it is (delivery routing of tasks without files). Out of scope, because the measurements showed no gain: skill-loading triggers, QA report severity, delivery review severity, spec-review lens triggers.

The replacement texts below were checked in their final form with the big model: 37/37 and 40/40 on the clear items.

## Approach

### Task 1: Decide the developer working mode by criteria
**Commit:** fix(developers): pick the working mode by criteria instead of keywords

**Files:**
- Modify: `plugins/python-developer/agents/developer.md`
- Modify: `plugins/php-developer/agents/developer.md`
- Modify: `plugins/frontend-developer/agents/developer.md`
- Modify: `plugins/frontend-developer/commands/develop.md`
- Modify: `plugins/python-developer/.claude-plugin/plugin.json`
- Modify: `plugins/php-developer/.claude-plugin/plugin.json`
- Modify: `plugins/frontend-developer/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`
- Modify: `docs/plugins/python-developer.md`
- Modify: `docs/plugins/php-developer.md`
- Modify: `docs/plugins/frontend-developer.md`
- Modify: `plugins-omp/python-developer/agents/developer.md`
- Modify: `plugins-omp/php-developer/agents/developer.md`
- Modify: `plugins-omp/frontend-developer/agents/developer.md`
- Modify: `plugins-omp/frontend-developer/commands/develop.md`
- Modify: `plugins-omp/python-developer/.omp-plugin/plugin.json`
- Modify: `plugins-omp/php-developer/.omp-plugin/plugin.json`
- Modify: `plugins-omp/frontend-developer/.omp-plugin/plugin.json`
- Modify: `.omp-plugin/marketplace.json`

1. In each of the three `agents/developer.md` files, replace the `### Detect Mode` section — its heading, the line `Analyze $ARGUMENTS for keywords to determine the working mode:` and the `| Mode | Keywords |` table — with the text below, byte for byte. Leave `### Extract Details`, the `Fix Mode` / `Implement Mode` / `Refactor Mode` sections and the report's `**Mode:**` line unchanged.
2. In `plugins/frontend-developer/commands/develop.md`, replace the `### Detect Mode from Task Keywords` heading and its `| Mode | Keywords |` table with the same text. The four copies must be identical.
3. Bump versions in all four places each (`plugin.json`, `.claude-plugin/marketplace.json`, the README "Available Plugins" row, the `**Version:**` line in `docs/plugins/<name>.md`): python-developer 3.0.4 → 3.0.5, php-developer 1.0.3 → 1.0.4, frontend-developer 1.2.1 → 1.2.2.
4. Run `python3 scripts/build_omp_edition.py` and keep the regenerated `plugins-omp/` files and `.omp-plugin/marketplace.json`. Do not edit generated files by hand.

This is a prose change with no automated test: the repository does not pin wording in tests, and the plan's Verification smoke-checks the new text.

```markdown
### Detect Mode

Decide the working mode from what `$ARGUMENTS` asks for, not from individual words in it:

| Mode | When |
|------|------|
| **Fix** | Existing behaviour is wrong: a bug, error, crash, failing check or vulnerability. The work restores correct behaviour and starts from a test that reproduces the problem. |
| **Refactor** | Restructure existing code without changing its observable behaviour: rename, extract, move, split, merge, deduplicate, clean up. Existing tests stay green. |
| **Implement** | New behaviour or capability that does not exist yet: a feature, endpoint, command, option, UI element or integration. |

A task that corrects wrong behaviour is Fix even when it also asks for cleanup. When neither Fix nor Refactor clearly applies, use Implement.
```

### Task 2: Classify QA changed files by role
**Commit:** fix(qa): classify changed files by role, including neither

**Files:**
- Modify: `plugins/qa/agents/test-planner.md`
- Modify: `plugins/qa/commands/loop.md`
- Modify: `plugins/qa/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`
- Modify: `docs/plugins/qa.md`
- Modify: `plugins-omp/qa/agents/test-planner.md`
- Modify: `plugins-omp/qa/commands/loop.md`
- Modify: `plugins-omp/qa/.omp-plugin/plugin.json`
- Modify: `.omp-plugin/marketplace.json`

1. In `plugins/qa/agents/test-planner.md`, Step 3 (Analyze Changes): replace everything from `Classify each changed file as FE or BE:` through the `**Ambiguous files**` line — the Frontend indicators, Backend indicators and Ambiguous files lists — with the text below, byte for byte. Keep the `For each changed file, identify:` list that follows.
2. In `plugins/qa/commands/loop.md`, Step 0.2.1 item 3: change `Classify each changed file as FE or BE using the planner's indicators (its Step 3)` to `Classify each changed file as FE, BE or neither by the planner's criteria (its Step 3)`. Change nothing else in that item.
3. In `docs/plugins/qa.md`, the `/qa:create-plan` step list: change `Classifies changed files as FE or BE and reads related producers` to `Classifies changed files as FE, BE or neither by what each file does, and reads related producers`.
4. Bump qa 2.8.0 → 2.8.1 in all four places (`plugins/qa/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the README row, `**Version:**` in `docs/plugins/qa.md`).
5. Run `python3 scripts/build_omp_edition.py` and keep the regenerated files.

This is a prose change with no automated test, for the same reason as Task 1.

```markdown
Classify each changed file by what it does, not only by its extension or directory names:

| Class | When |
|-------|------|
| **FE** | Runs in or shapes what the browser shows: components, pages, client-side scripts and state, stylesheets, templates rendered into pages, UI strings, frontend build config. |
| **BE** | Runs on the server or defines its contract: API handlers and routes, server actions and middleware, services, models, migrations, API schemas. |
| **neither** | No application behaviour to test: documentation, CI, repository tooling, linters, container or infrastructure config. |

FE files lead to FE scenarios and BE files to BE scenarios; `neither` files get no scenarios.
```

## Verification
- `python3 scripts/check_plugin_versions.py` passes.
- `python3 scripts/build_omp_edition.py --check` passes.
- `python3 scripts/check_agent_frontmatter.py` and `python3 scripts/check_execution_boundary.py` pass.
- `grep -rn -e 'Mode | Keywords' -e 'Detect Mode from Task Keywords' -e 'Frontend indicators' -e "planner's indicators" plugins plugins-omp` prints nothing.
- Smoke, when `/tmp/jev-tests/t1a.json` and `/tmp/jev-tests/t4.json` exist (otherwise `manual`): in `eval`, for every item with `set == "clear"`, send `completion(model="default")` the new `### Detect Mode` section read from `plugins/python-developer/agents/developer.md` (for t1a) or the new Step 3 classification text read from `plugins/qa/agents/test-planner.md` (for t4), then the item's `state`, asking for JSON `{"mode": ...}` or `{"label": ...}`. Create the completion handles in the main cell, not in worker threads. Pass: at least 36 of 37 modes and 39 of 40 labels equal the item's `label`.

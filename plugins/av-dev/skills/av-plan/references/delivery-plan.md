# Converting an av-plan plan to the Delivery plan format

The marketplace Delivery plugin runs a plan task by task (`/delivery:execute <PLAN_PATH>`). It reads `### Task N: <title>` blocks with a `**Files:**` list and an optional `## Verification` section; the format is described in the Delivery docs, section "Plan format". An av-plan plan keeps its own sections for the av-implement run. This page says how the two map, so a plan written here can be delivered there without a rewrite.

## Mapping

| av-plan section | Delivery | Rule |
|---|---|---|
| `## Goal and scope`, `## Acceptance criteria`, `## Reference pattern`, `## Contract` | text before the first `### Task` | context, not implementation work; keep it, Delivery ignores it |
| `## Order` steps | `### Task N: <title>` blocks under `## Approach` | one task per step; number in execution order, each number once; producers before consumers |
| `## Files` rows of a step | `**Files:**` list of that task | `Create:`, `Modify:`, `Test:`, `Delete:` with repo-relative paths in backticks; every file of the plan belongs to exactly one task |
| role of a step (`Role (role skill)` column) | the task's file list | Delivery picks the implementer from the files; one stack per task, so split a step that spans stacks (backend and frontend, code and docs) into two tasks |
| handoff between roles ("Order", role skill "Handoff") | the task text | name the functions, types and signatures later tasks depend on; each task must stand alone |
| `## Tests` | `Test:` entries in the task that adds them, plus a sentence in the task text | a bug fix states which test fails before the change |
| `## Validation` gates | `## Verification` after the last task | one line per check, in order: `bash <av-dev>/skills/av-verify/scripts/gate.sh --gate quick` and so on |
| `## Docs` | a task of its own (`docs` stack) | keep it last unless code depends on it |
| `## Risks`, `## Open questions` | text before the first task | an open question that changes a task's files must be closed before delivery |
| `**Commit:**` line | optional per task | `type(scope): description`; without it Delivery uses `chore: <title>`; a repo with a ticket convention puts the ticket in the description or in `Refs:` |

Do not put `##` or `###` headings inside a task. The next heading ends the task.

## Worked example

av-plan "Order" and "Files":

```markdown
## Files
| File | Change | Role (role skill) | Description |
|---|---|---|---|
| `src/catalog/search.py` | new | data (backend-data) | search service |
| `src/catalog/api.py` | edit | data (backend-data) | `GET /catalog/search` |
| `tests/test_search.py` | new | data (backend-data) | query and empty result |
| `web/src/catalog/SearchBox.tsx` | new | ui (web-ui) | search box, calls the endpoint |
| `docs/modules/catalog.md` | edit | - | endpoint and component |

## Order
1. data: service and endpoint; hands over the response shape `{items: [{id, name}], total}`.
2. ui: search box on the catalog page, in parallel with 1 after the contract.
3. docs.

## Validation
quick after each role, full before the report.
```

The same plan in the Delivery format:

```markdown
## Approach

### Task 1: Catalog search service and endpoint
**Commit:** feat(catalog): add search endpoint

**Files:**
- Create: `src/catalog/search.py`
- Modify: `src/catalog/api.py`
- Test: `tests/test_search.py`

Write the failing query and empty-result tests first. `GET /catalog/search?q=` returns `{items: [{id, name}], total}`; Task 2 depends on that shape.

### Task 2: Search box on the catalog page
**Commit:** feat(catalog): add search box

**Files:**
- Create: `web/src/catalog/SearchBox.tsx`

Calls `GET /catalog/search` from Task 1 and renders `items`; an empty `items` shows the empty state.

### Task 3: Document the catalog search
**Commit:** docs(catalog): describe search

**Files:**
- Modify: `docs/modules/catalog.md`

## Verification
- `bash <av-dev>/skills/av-verify/scripts/gate.sh --gate quick`
- `bash <av-dev>/skills/av-verify/scripts/gate.sh --gate full`
```

Roles become file lists, parallel steps become consecutive tasks (Delivery runs tasks in order), and the gates move to `## Verification`.

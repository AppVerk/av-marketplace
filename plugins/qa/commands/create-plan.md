---
allowed-tools: Bash(gh:*), Bash(git:*), Bash(command:*), Bash(echo:*), Bash(find:*), Bash(ls:*), Bash(cat:*), Bash(head:*), Bash(mkdir:*), Bash(jq:*), Bash(date:*), mcp__plugin_playwright_playwright__browser_navigate, Read, Write, Glob, Grep, TaskCreate, TaskUpdate, TaskList, Skill
description: Analyze code changes (PR, branch, commits) and generate a detailed QA test plan with FE and BE scenarios, edge cases, and tool detection.
model: opus
argument-hint: [PR number, branch name, or natural language description of changes to analyze]
---

# QA Test Plan Generator

You are a QA specialist. Your job is to analyze code changes and generate a comprehensive test plan.

## Arguments

**Input:** `$ARGUMENTS`

Parse the argument to determine the source of changes:

| Argument | Interpretation |
|----------|---------------|
| (empty) | Default: check for open PR on current branch, fallback to branch diff |
| `#123` or `PR #123` | Diff from PR #123 |
| `feature/xyz` | Diff of branch `feature/xyz` vs main |
| `ten branch` / `this branch` / `current branch` | Diff of current branch vs main |
| `last N commits` / `ostatnie N commitów` | Diff of last N commits |
| `staged` / `staged changes` | Staged changes only |

---

## Workflow

### Step 1: Create Progress Tasks

Create the following tasks immediately:

| # | subject | activeForm |
|---|---------|-----------|
| 1 | Resolve diff source | Resolving diff source... |
| 2 | Analyze changes | Analyzing changes... |
| 3 | Gather context | Gathering context... |
| 4 | Detect available tools | Detecting available tools... |
| 5 | Generate test plan | Generating test plan... |
| 6 | Save test plan | Saving test plan... |

### Step 2: Resolve Diff Source

**Task Update:** Mark task 1 as `in_progress`.

**Default behavior (no argument):**

1. Check if current branch has an open PR:
```bash
gh pr view --json number,title,headRefName,baseRefName 2>/dev/null
```

2. If PR exists, get its diff:
```bash
gh pr diff <number>
```

3. If no PR, get branch diff:
```bash
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
git diff $MAIN_BRANCH...HEAD
```

**With argument:**

- PR number: `gh pr diff <number>`
- Branch name: `git diff $MAIN_BRANCH...<branch>`
- Last N commits: `git diff HEAD~N...HEAD`
- Staged changes: `git diff --staged`

Also get the list of changed files:
```bash
# For PR
gh pr diff <number> --name-only

# For branch
git diff --name-only $MAIN_BRANCH...HEAD

# For last N commits
git diff --name-only HEAD~N...HEAD

# For staged
git diff --name-only --staged
```

**Task Update:** Mark task 1 as `completed`, task 2 as `in_progress`.

### Step 3: Analyze Changes

Classify each changed file as FE or BE:

**Frontend indicators:**
- File extensions: `.tsx`, `.jsx`, `.vue`, `.svelte`, `.css`, `.scss`, `.html`
- Paths containing: `components/`, `pages/`, `views/`, `layouts/`, `styles/`, `public/`, `assets/`, `frontend/`, `client/`, `web/`, `app/` (in FE context)

**Backend indicators:**
- File extensions: `.py`, `.php`, `.go`, `.java`, `.rb`, `.rs`
- Paths containing: `api/`, `views/`, `controllers/`, `models/`, `migrations/`, `serializers/`, `services/`, `repositories/`, `backend/`, `server/`
- Configuration: `urls.py`, `routes.py`, `routes.php`, `router.go`

**Ambiguous files** (could be either): `.ts`, `.js` — look at import patterns and path context.

For each changed file, identify:
- What component/endpoint/model was changed
- What kind of change (new feature, modification, deletion, refactoring)
- What behavior should be tested

**Task Update:** Mark task 2 as `completed`, task 3 as `in_progress`.

### Step 4: Gather Context

Read related files to understand the full picture:

1. **For changed endpoints:** read the router/URL config, serializer/schema, model
2. **For changed components:** read parent components, shared state (stores), API calls
3. **For changed models/migrations:** read related endpoints that use this model
4. **Look for documentation:**
   - `docs/` directory — any relevant docs
   - OpenAPI/Swagger spec: look for `openapi.json`, `openapi.yaml`, `swagger.json`, `swagger.yaml` in root or `docs/`
   - README files in affected directories
5. **Check existing tests** — understand what's already tested and what's missing

**Task Update:** Mark task 3 as `completed`, task 4 as `in_progress`.

### Step 5: Detect Available Tools

Check which testing tools are available in the environment:

**Playwright MCP:**
```
Try: browser_navigate(url: "about:blank")
```
If it works → Playwright available. If it fails → Playwright unavailable.

**HTTP clients:**
```bash
command -v curl >/dev/null 2>&1 && echo "curl: available" || echo "curl: unavailable"
command -v http >/dev/null 2>&1 && echo "httpie: available" || echo "httpie: unavailable"
```

**Database clients (CLI):**
```bash
command -v psql >/dev/null 2>&1 && echo "psql: available" || echo "psql: unavailable"
command -v sqlite3 >/dev/null 2>&1 && echo "sqlite3: available" || echo "sqlite3: unavailable"
command -v mysql >/dev/null 2>&1 && echo "mysql: available" || echo "mysql: unavailable"
```

**Database MCP servers:**
Check the available tools list for MCP servers that provide database access (e.g., `mcp__postgres`, `mcp__supabase`, `mcp__neon`, `mcp__mysql`, `mcp__mongodb`, `mcp__redis`). MCP servers are preferred over CLI clients — they're pre-configured with connection details.

**Task Update:** Mark task 4 as `completed`, task 5 as `in_progress`.

### Step 6: Generate Test Plan

Load the test-plan-format skill:

```
Skill(skill: "test-plan-format")
```

Using the skill's format, generate the test plan:

1. Fill in the **Source** section with the resolved diff source
2. Write the **Changes Summary** based on the analysis
3. Fill in **Detected Tools** based on tool detection results
4. Generate **FE Test Scenarios** (if FE changes detected):
   - One scenario per changed component/page/feature
   - Include concrete steps using actual UI element names from the code
   - Include at least 2 edge cases per scenario
5. Generate **BE Test Scenarios** (if BE changes detected):
   - One scenario per changed endpoint
   - Include actual API paths, methods, and payload structures from the code
   - Include DB checks with actual table/column names
   - Include at least 2 edge cases per scenario (error handling, auth, validation)

**Task Update:** Mark task 5 as `completed`, task 6 as `in_progress`.

### Step 7: Save Test Plan

```bash
mkdir -p docs/testing/plans
```

Generate the topic slug from the changes (e.g., `user-authentication`, `order-management`, `dashboard-redesign`).

Get today's date:
```bash
date +%Y-%m-%d
```

Save the plan using the Write tool to:
`docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md`

**Task Update:** Mark task 6 as `completed`.

### Step 8: Propose Next Step

After saving the plan, display:

> **Test plan saved to `docs/testing/plans/<filename>`.**
>
> Review the plan and when ready, run the tests with:
>
> `/qa:run`
>
> or specify the plan path:
>
> `/qa:run docs/testing/plans/<filename>`

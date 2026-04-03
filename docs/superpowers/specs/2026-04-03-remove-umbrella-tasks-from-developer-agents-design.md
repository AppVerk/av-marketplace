# Remove Umbrella Tasks from Developer Agents

> **For agentic workers:** This is a design spec. Use superpowers:writing-plans to create an implementation plan from this spec.

**Goal:** Remove process-phase tasks ("TDD cycle", "Quality gates", "Generate report") from developer agent TaskCreate lists to prevent orphaned tasks from cluttering results.

**Architecture:** Modify the task table in Phase 1 of each developer agent definition. Remove TaskUpdate instructions from Phases 4-6. No behavioral changes to the phases themselves.

---

## Problem

Developer agents (`python-developer:developer`, `frontend-developer:developer`, `php-developer:developer`) create 6 progress tasks at startup:

| # | subject | Nature |
|---|---------|--------|
| 1 | Parse input & detect mode | Setup task - quick, deterministic |
| 2 | Load coding standards & detect stack | Setup task - quick, deterministic |
| 3 | Load stack-specific skills | Setup task - quick, deterministic |
| 4 | TDD cycle | **Process phase** - long, may fail |
| 5 | Quality gates | **Process phase** - long, may fail |
| 6 | Generate report | **Process phase** - depends on 4-5 |

Tasks 4-6 are process phases, not deliverable tasks. When the agent doesn't reach Phase 5 or 6 (due to timeout, error, or early termination), these tasks remain open. This clutters the final task summary with incomplete items that don't represent actual work to be done.

## Solution

Remove tasks 4-6 from the TaskCreate table. Phases 4, 5, and 6 continue to execute identically — they just don't have their own task tracking. Progress is visible through:

- Test output (TDD cycle)
- Typecheck/lint/test output (Quality Gates)
- The final Developer Report (Report phase)

## Scope

### Files to change

1. `plugins/python-developer/agents/developer.md`
2. `plugins/frontend-developer/agents/developer.md`
3. `plugins/php-developer/agents/developer.md`

### Changes per file

**Phase 1 — Task table:** Reduce from 6 rows to 3:

```markdown
| # | subject | activeForm |
|---|---------|-----------|
| 1 | Parse input & detect mode | Parsing input... |
| 2 | Load coding standards & detect stack | Loading standards... |
| 3 | Load stack-specific skills | Loading skills... |
```

**Phase 3 — Last TaskUpdate:** Change from:

> Mark task 3 as `completed` and task 4 as `in_progress`

To:

> Mark task 3 as `completed`

**Phase 4 — TaskUpdate block:** Remove the entire `**Task Update:**` paragraph at the end of the section.

**Phase 5 — TaskUpdate block:** Remove the entire `**Task Update:**` paragraph at the end of the section.

**Phase 6 — TaskUpdate block:** Remove the entire `**Task Update:**` paragraph at the end of the section.

### Out of scope

- Phase 4, 5, 6 content — no behavioral changes
- Developer Report format — unchanged
- `commands/develop.md` files — they don't create tasks
- `code-review:review` — works correctly, not affected

## Verification

After changes, a developer agent run should:

1. Create exactly 3 tasks (Parse, Load standards, Load skills)
2. Complete all 3 tasks during Phases 1-3
3. Execute Phases 4-6 without TaskCreate/TaskUpdate calls
4. Produce the same Developer Report as before
5. Leave zero open tasks at completion

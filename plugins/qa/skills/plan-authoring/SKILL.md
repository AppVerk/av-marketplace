---
name: plan-authoring
description: Shared QA plan authoring and bounded review for /qa:create-plan and /qa:run — detect tools, dispatch the planner and reviewer with safe config metadata, and return the plan, review outcome and open findings.
---

# QA Plan Authoring

Use this same workflow from `/qa:create-plan` and from `/qa:run` when `plan resolve` requests generation or regeneration. The `qa:test-planner` writes/revises the plan; the `qa:test-plan-reviewer` only reads it. Never write or edit the plan yourself. Running either command is the request to author the plan: do not add a confirmation question before drafting.

## Input

The caller supplies:

- `Arguments:` — the change source verbatim, or `(empty)`. For `/qa:run`, use the source returned by `plan resolve` rather than a selected plan path.
- The JSON object from `qa.py config`, including its `state`. Load `qa:engine` for installed-script resolution and CLI handling.
- The three progress tasks (detect tools, draft, review), if the harness supports them. In the steps below, tasks 1-3 mean those subjects; `/qa:run` can map them to its own progress tasks. A subagent with no progress tool skips task updates, not the work.

Build one **Config block** for every planner dispatch (draft and revise) and every reviewer dispatch. When `config.state` is `ok`, use exactly this projection of the engine's returned metadata:

```text
Config:
{"targets": <config.targets>, "defaults": <config.defaults>, "users": <config.users>, "values": <config.values>, "stores": <config.stores>}
```

Render it as valid JSON, with the actual metadata in place of the angle-bracket descriptions. `users` maps configured names to descriptions, `values` contains names only, and `stores` maps names to kind/engine metadata only. Never pass resolved values, source outputs, tokens, passwords, cookies, `[env.secrets]`, cleanup recipes or the full config/trust subset to either agent. Reuse this exact block, unchanged, in every round so both agents plan and review against the same configuration.

When `config.state` is not `ok`, the entire block is:

```text
Config:
none
```

Do not bootstrap, extend or repair config here. With `none`, the planner writes `$QA_…` names and target names grounded in repository evidence, never literal credentials or guesses at their values. `/qa:run` checks the plan and fills missing configuration through its own `plan check` flow. Plan authoring does not require config trust because it executes no config recipe or value source.

## Workflow

### Step 2: Detect Available Tools

**Task Update:** Mark task 1 as `in_progress`.

Check which testing tools are available in the environment:

**Playwright MCP:**
```
Try: browser_navigate(url: "about:blank")
```
If it works → Playwright available. If it fails → Playwright unavailable.

In OMP, use the command preamble's built-in-browser mapping for this same probe: read `xd://eval/browser`, then open the QA tab at `about:blank` through `browser` in `eval`. A missing browser tool or an exception means unavailable; never install a browser to make the probe pass.

**CLI tools:**

Run the installed engine's `tools` subcommand using the path resolved by `qa:engine`:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/engine/scripts/qa.py tools
```

In OMP substitute the absolute path returned by `realpath skill://qa:engine/scripts/qa.py`. Its JSON booleans cover `curl`, `httpie`, `jq`, `perl_json_pp`, `psql`, `sqlite3`, `mysql` and `redis_cli` (`redis-cli`); use these results instead of independent shell detection snippets. An engine failure is a generation error, not evidence that all tools are unavailable.

Write the results as a `Detected tools:` block: one `<tool>: available` or `<tool>: unavailable` line per tool above. The planner copies it into the plan's `## Detected Tools`.

**Task Update:** Mark task 1 as `completed`, task 2 as `in_progress`.

### Step 3: Draft the Plan

```
Task(
  subagent_type: "qa:test-planner",
  run_in_background: false,
  description: "Draft QA test plan",
  prompt: "Mode: draft
Arguments: <$ARGUMENTS verbatim, or (empty)>
Detected tools:
<the Step 2 block>
Config:
<the Config block from Input, without repeating its Config: label>"
)
```

The planner answers with one JSON object. On `{"error": ...}`, a failed dispatch, an answer that is not the expected JSON, or no file at its `plan` path, stop:

> Test plan generation failed: <reason>

Keep `plan`, `source` and `changed_files` for the review.

**Task Update:** Mark task 2 as `completed`, task 3 as `in_progress`.

### Step 4: Review the Plan

Run at most 3 review rounds. In round `n`:

1. Dispatch the reviewer:

   ```
   Task(
     subagent_type: "qa:test-plan-reviewer",
     run_in_background: false,
     description: "Review QA test plan (round <n>)",
     prompt: "Plan: <plan>
   Diff source: <source>
   Changed files:
   <changed_files, one path per line>
   Config:
   <the Config block from Input, without repeating its Config: label>
   Round: <n> of 3
   Previous findings:
   <none, or every earlier finding with the number it was sent under, followed by the planner's disposition and note>"
   )
   ```

2. The reviewer's answer must be one JSON object `{"findings": [...]}` whose findings each carry a `severity` of `blocker`, `concern` or `nit`. On a failed dispatch or any other answer, the review could not run: end the review and keep the plan unreviewed, with the reason.
3. No `blocker` or `concern` → the plan is approved; end the review.
4. `n` is 3 → end the review; this round's blockers and concerns stay open for the user.
5. Otherwise number this round's findings, continuing after the last number of earlier rounds, and dispatch the planner:

   ```
   Task(
     subagent_type: "qa:test-planner",
     run_in_background: false,
     description: "Revise QA test plan (round <n>)",
     prompt: "Mode: revise
   Plan: <plan>
   Diff source: <source>
   Config:
   <the Config block from Input, without repeating its Config: label>
   Round: <n> of 3
   Findings:
   <this round's findings, one per line: number, [severity] location: issue Fix: fix>"
   )
   ```

   The planner answers `{"plan": ..., "dispositions": [...]}`. On `{"error": ...}`, a failed dispatch or any other answer, end the review; this round's blockers and concerns stay open. Otherwise record each disposition with its finding and start round `n + 1`.

**Task Update:** Mark task 3 as `completed`.

## Return contract

Return one JSON object to the caller; do not propose `/qa:run` from this skill. Both commands consume the same contract:

```json
{
  "plan": "<saved plan path>",
  "review": {"outcome": "approved|open|unreviewed", "round": 1, "reason": null},
  "open_findings": [{"severity": "blocker|concern", "location": "<section or path>", "issue": "<finding>", "fix": "<requested fix>"}],
  "nits": [{"severity": "nit", "location": "<section or path>", "issue": "<finding>", "fix": "<optional fix>"}],
  "declined_findings": [{"number": 1, "severity": "blocker|concern|nit", "location": "<section or path>", "issue": "<finding>", "fix": "<requested fix>", "note": "<planner's reason>"}]
}
```

The alternatives in this shape are closed vocabularies, not literal strings containing `|`. Empty lists are `[]`. `round` is the last attempted review round (1-3); `reason` is `null` unless a dispatch, malformed answer or revision failure needs explaining.

- `approved` iff a valid reviewer answer has no blocker or concern. `open_findings` is empty; keep that approving round's optional nits.
- `open` iff the last valid review still has blockers/concerns after round 3, or revision fails before they are cleared. Return those findings in `open_findings` and explain any revision failure in `reason`. Round exhaustion is not approval.
- `unreviewed` iff the reviewer dispatch/answer failed. Keep the reason and any unresolved findings from the last valid review; never erase them or call the plan approved.

A planner's `declined` disposition is not proof that a finding was fixed. Preserve its numbered finding and note in `declined_findings`; only subsequent review resolves whether it remains open. If drafting/tool detection fails before a usable plan exists, return `{"error": "<reason>"}` instead; the caller stops and displays `Test plan generation failed: <reason>`.

**Caller routing:** `/qa:create-plan` prints the review outcome, open findings, optional nits and declined findings, then proposes `/qa:run <plan>`. `/qa:run` uses the returned path and shows the review outcome; it prints open concerns and continues, while an open blocker requires an interactive run-anyway/stop choice (headless stops). Approved does not waive `plan check`, trust, origin or mutation checks. The execution command, not this skill, owns those choices and the subsequent run.

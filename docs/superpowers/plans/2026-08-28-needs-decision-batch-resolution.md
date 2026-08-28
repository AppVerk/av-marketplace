# Needs-Decision Batch Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user resolve every `needs-decision` finding in one analysis-backed sweep and one bulk fixer batch, reachable from the entry points that already exist.

**Architecture:** A new read-only agent (`decision-analyst`) fans out one-per-finding and returns a rendered proposal; a new skill (`decision-gate`) carries the whole decision-stage doctrine as a single source of truth; `/fix-report` and `/fix-all` load that skill at the point where each already handles `needs-decision` findings. Decisions, verification plans, pins and dispatch markers are persisted as one-line fields inside the finding block, so an interrupted run resumes without re-asking.

**Tech Stack:** Claude Code plugin markdown (commands, agents, skills), YAML frontmatter, Python validators (`scripts/check_agent_frontmatter.py`, `scripts/check_plugin_versions.py`), Bash (`plugins/code-review/scripts/check-prefix-sync.sh`).

**Spec:** `docs/superpowers/specs/2026-08-27-needs-decision-batch-resolution-design.md` (1430 lines). Every task below cites the spec section it implements. Read the spec section before writing the task's content — this plan tells you *where* and *what shape*, the spec is the authority on *wording*.

## What "test" means in this repository

There is no unit-test framework for plugin prose. Three checks are executable, and two of them run in CI:

| Check | Command | CI |
|---|---|---|
| Agent frontmatter | `python3 scripts/check_agent_frontmatter.py` | `.github/workflows/agent-frontmatter.yml` |
| Validator unit tests | `python3 scripts/test_check_agent_frontmatter.py` | same workflow |
| Plugin version parity | `python3 scripts/check_plugin_versions.py` | `.github/workflows/plugin-version-parity.yml` |
| Category→Prefix sync | `bash plugins/code-review/scripts/check-prefix-sync.sh` | not in CI |

For prose content the red/green cycle is a `grep` assertion: write the grep, watch it fail, write the prose, watch it pass. Every task below gives the exact command and the exact expected output.

**Do not add a CI guard for the status vocabulary.** The spec puts it out of scope by name (`Scope` → "Out of scope") and carries the gap as a residual risk. The greps in this plan are the task's own test cycle; they are typed at the terminal and never committed as a script.

## Global Constraints

Copied verbatim from the spec. Every task's requirements implicitly include this section.

- **Versions.** `code-review` 1.17.3 → **1.18.0**. `qa` 2.5.2 → **2.6.0**. Each in all four places `scripts/check_plugin_versions.py` checks: `plugins/<name>/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the plugin's row in the README "Available Plugins" table, and the `**Version:**` header in `docs/plugins/<name>.md`.
- **Agent frontmatter.** Capability is declared in `tools:` only. `allowed-tools:` is inert in an agent and fails the build (`CLAUDE.md`). Permitted keys are the thirteen in `PERMITTED_KEYS` (`scripts/check_agent_frontmatter.py:46-50`).
- **Command and skill frontmatter.** Per-tool enumeration in `allowed-tools:` is correct and is the point of a permission pre-approval. Never "fix" it to a server-level or bare grant — that silently broadens the pre-approval.
- **Status grammar.** `**Status:** <icon> <text> (YYYY-MM-DD)[ — <reason>]`. The ` — <reason>` tail is permitted **only** for `🚫 Rejected`. `<reason>` is a single line with no embedded newline.
- **Status read rule.** Consumers match the status value by **prefix**, never by whole-line equality — the tail is not theirs to control. The one exception is `fix-all.md:361`'s Step 4.1.5 verify, which checks a line the loop just wrote itself and stays exact.
- **Location read rule, two clauses.** Take the first backticked token and ignore any trailing parenthetical; where the line carries no backticked token at all, take the first whitespace-delimited token after the field name. Under either clause `—`, `unknown:0`, or anything that does not parse as `path:line` / `path:line-range` is location-less.
- **One physical line.** `**Decision:**`, `**Decision-retired:**`, `**Verification-plan:**`, `**Decision-pin:**`, `**Dispatch:**`, `**Verification:**`, `**Location:**` and `**Status:**` each occupy exactly one physical line, with no continuation line of any kind. Content that will not fit is rewritten or split, never wrapped.
- **Slot order.** `**Status:**` stays the first non-blank line under the finding's heading; every other loop-written line is written below it, never above.
- **No new command, no new argument.** The entry points stay `/fix`, `/fix-report`, `/fix-all`.
- **Commits.** Conventional Commits. No `Co-Authored-By` and no AI attribution of any kind. The repository's pre-commit hook blocks a bare `git commit`; prefix with `AV_COMMIT_SKILL=1`.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `plugins/code-review/agents/decision-analyst.md` | **Create.** Read-only per-finding analysis; returns the proposal block | 1 |
| `plugins/code-review/skills/decision-gate/SKILL.md` | **Create.** The decision-stage doctrine: stages 0–3.5, the sweep render, the five outcomes, the decision-record grammars | 2 |
| `plugins/qa/skills/report-format/SKILL.md` | **Modify.** Register `🚫 Rejected` + tail + prefix rule, the extended `Location:` form, and the six loop-written fields | 3 |
| `plugins/code-review/agents/fix-auto.md` | **Modify.** Phase 1 abort on a rejected block; Location read rule | 4 |
| `plugins/code-review/commands/fix.md` | **Modify.** Phase 0 abort, Phase 1 read rule, Phase 3 delegation, Phase 8 second-status rule | 5 |
| `plugins/code-review/commands/fix-report.md` | **Modify.** Filter, edge case, partitioned checklist, gate invocation, new Step 4.1.5, summary block, frontmatter grants | 6, 7 |
| `plugins/code-review/commands/fix-all.md` | **Modify.** Filter, edge case, zero-auto path, new Step 5, progress row, frontmatter grants | 8 |
| `plugins/qa/commands/loop.md` | **Modify.** Three `🚫 Rejected` duties, carry-over of the six fields, dispatch-copy rule, two Location read sites | 9 |
| `docs/plugins/code-review.md`, `docs/plugins/qa.md`, `README.md`, `.claude-plugin/marketplace.json`, both `plugin.json` | **Modify.** Prose corrections, upgrade notes, versions | 10 |
| `docs/testing/fixtures/needs-decision-e2e/` | **Create.** Synthetic fixture for the end-to-end run | 11 |

Tasks 1–2 define every grammar the rest of the plan greps for. Do them first and in order.

---

### Task 1: The `decision-analyst` agent

**Spec:** `Components` → "Agent: `decision-analyst`" (spec lines 513–599), including the full return-contract table.

**Files:**
- Create: `plugins/code-review/agents/decision-analyst.md`
- Test: `scripts/check_agent_frontmatter.py` (existing validator, no new test file)

**Interfaces:**
- Consumes: nothing.
- Produces: the agent name `code-review:decision-analyst`, dispatched by Task 2's skill. The return-contract field names `Target`, `Findings`, `Alternatives`, `Recommendation`, `Risk`, `Code Preview`, `Verification Plan`, `Rejection candidate` — Task 2 renders exactly these.

- [ ] **Step 1: Write the failing check**

The validator only inspects files that exist, so the failing assertion is that the agent is absent and its name is unknown to the tree:

```bash
test -f plugins/code-review/agents/decision-analyst.md && echo PRESENT || echo ABSENT
```

Expected now: `ABSENT`

- [ ] **Step 2: Record the agent-count baseline**

`scripts/check_agent_frontmatter.py` warns when the agent-file count drops below `EXPECTED_AGENT_FILES`. Record the current count so Step 6 can show it rose by exactly one:

```bash
ls plugins/*/agents/*.md | wc -l
```

Expected: `25`

- [ ] **Step 3: Create the agent file**

Write `plugins/code-review/agents/decision-analyst.md`. The frontmatter is fixed by the spec and uses only four of the thirteen permitted keys:

```yaml
---
name: decision-analyst
description: Analyses exactly one needs-decision code-review finding against the code it points at and returns a rendered fix proposal with alternatives. Read-only — performs no writes. Invoked by the decision-gate skill from /fix-report and /fix-all.
tools: Read, Grep, Glob, Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git blame:*), Skill
disallowedTools: Edit, Write, NotebookEdit
---
```

Do **not** widen `Bash(git log:*)` to `Bash(git:*)`. The narrowing is the whole read-only property: `Bash(git:*)` matches `git checkout`, `git restore`, `git reset`, `git clean` and `git commit`. Spec lines 525–530 state that the validator neither enforces nor diagnoses this, so it rests on author and reviewer.

The body carries, in this order:

1. **What it receives** — exactly one `needs-decision` finding block, and a validated `path:line` where stage 0 supplied one.
2. **The read-only rule** — it opens files and reads history; it never edits. Say plainly that it cannot pre-empt the user's choice because it cannot write.
3. **The return contract** — reproduce the eight-row field table from spec lines 590–599 verbatim in substance. The rows that carry rules rather than descriptions must keep them:
   - `Findings` — the two citable forms (exact shell command **and** its verbatim output; or a `tool:` citation naming every output-determining parameter **and** that call's raw result verbatim, never a paraphrase). A tool name alone is neither form. An empty result is cited as `(empty)` — a marker of emptiness, never a tool's own rendering such as `(no matches)`.
   - `Alternatives` — the `Drift-class` derivation, the fallback route, "returns A alone and says so", and the one-physical-line self-containment rule.
   - `Verification Plan` — one plan per alternative; each check written `<check> → <expected result>` on one physical line carrying no `; `, no second ` → ` and no newline; soft checks marked `(soft)`; the mechanical rejection test (a plan every check of which would pass on an unedited tree is rejected).
   - `Rejection candidate` — optional, single-line reason, same two-form citation requirement.
4. **The frontmatter rationale** — the two-word specifier has no precedent in this tree and may be inert; `scripts/check_agent_frontmatter.py:78-80` calls the spelling undocumented. State that Task 12 probes it.

- [ ] **Step 4: Run the frontmatter validator**

```bash
python3 scripts/check_agent_frontmatter.py
```

Expected: exit 0. A per-tool MCP entry warning is not applicable here. If it **fails** on `disallowedTools`, stop — that key is in `PERMITTED_KEYS` at `scripts/check_agent_frontmatter.py:46-50`, so a failure means the file has a different problem (most likely a stray `allowed-tools:` key, which is a hard error by repo rule).

- [ ] **Step 5: Run the validator's own unit tests**

```bash
python3 scripts/test_check_agent_frontmatter.py
```

Expected: exit 0, no regression.

- [ ] **Step 6: Confirm the count rose by exactly one**

```bash
ls plugins/*/agents/*.md | wc -l
```

Expected: `26`

- [ ] **Step 7: Assert the read-only grant survived review**

```bash
grep -q 'Bash(git log:\*)' plugins/code-review/agents/decision-analyst.md && \
  ! grep -q 'Bash(git:\*)' plugins/code-review/agents/decision-analyst.md && \
  echo PASS || echo FAIL
```

Expected: `PASS`

- [ ] **Step 8: Commit**

```bash
git add plugins/code-review/agents/decision-analyst.md
AV_COMMIT_SKILL=1 git commit -m "feat(code-review): add the read-only decision-analyst agent"
```

---

### Task 2: The `decision-gate` skill

**Spec:** `Components` → "Skill: `decision-gate`" (601–629) for the boundary of what belongs here; `The flow` (121–509) for stages 0–3.5; `Decision outcomes` (650–716); `Decision record` (847–1128).

This is the largest task in the plan and the only one every later task greps against. Write it against the spec text, not from memory.

**Files:**
- Create: `plugins/code-review/skills/decision-gate/SKILL.md`
- Test: grep assertions below

**Interfaces:**
- Consumes: the agent name and return-contract field names from Task 1.
- Produces: the six loop-written field names and their written forms, which Tasks 3–9 register and read:
  - `**Decision:** <label> — <resolution text> [<who>, <YYYY-MM-DD>; attempt N: <outcome>…]`
  - `**Decision-retired:**` — same grammar, retired by in-place rewrite
  - `**Verification-plan:** <check> → <expected>[ (soft)]; <check> → <expected>`
  - `**Decision-pin:** block=<sha256> | <path>=<blob-hash>[:edit|:ref] | …`
  - `**Dispatch:** attempt <N> dispatched <YYYY-MM-DD>`
  - `**Verification:** hard|advisory|unavailable — <checks run>[; <N> not run: <check text>]`
  - and the extended `**Location:** \`path:line\` (was: \`original\`)`

- [ ] **Step 1: Write the failing checks**

```bash
test -f plugins/code-review/skills/decision-gate/SKILL.md && echo PRESENT || echo ABSENT
```

Expected now: `ABSENT`

- [ ] **Step 2: Create the skill with its frontmatter**

`mkdir -p plugins/code-review/skills/decision-gate`, then write `SKILL.md` starting with:

```yaml
---
name: decision-gate
description: Use when resolving code-review findings flagged needs-decision in bulk — the analysis fan-out, the decision sweep and its five outcomes, the dispatch contract, orchestrator-run verification, and the decision record written into the report. Loaded by /fix-report and /fix-all; /fix loads it for the Alternatives render format alone.
---
```

No `allowed-tools:` — the skill runs in the invoking command's context and adds no pre-approval of its own. The commands carry the grants (Task 7, Task 8).

- [ ] **Step 3: Write the stage sections**

Sections, in this order, each reproducing the spec's rules:

1. **Scope of this skill** — what it *is* (single source of truth for the decision stage) and what it deliberately excludes: stage 4's status write-back is command-owned, each command re-running its own Step 4.1 / 4.1.5. State the per-command difference: in `/fix-all` Step 5 the skill runs stages 0 → 3.5; in `/fix-report` it runs stages 0–2 in the Step 2.4 slot and hands the decided findings back to Step 3, which dispatches them, after which stage 3.5 runs over the decided findings only.
2. **Entry: decision replay check** (spec 127–140) — a finding carrying a `**Decision:**` line and no `**Status:**` line skips stages 0–2. "Decided, never dispatched" enters stage 3 normally; "dispatched, outcome unknown" re-enters at stage 3.5 and is never re-dispatched blind.
3. **Stage 0: location pre-check** (142–175) — the usability rule via the two-clause Location read rule; batches of at most 4 `AskUserQuestion` calls, one question per finding; **the validated `path:line` is written into the report immediately, in the extended `(was: …)` form**, not deferred to stage 2; re-ask once, then treat as a declined target; a declined target is reported Failed in the run summary with no `**Status:**` line.
4. **Stage 1: parallel fan-out** (177–181) — the pre-flight count stated before dispatch ("13 findings to analyse, in 2 batches of at most 8"), batches of at most 8, each batch announced.
5. **Stage 2: the decision sweep** (184–281) — **the render, stated exactly** (always rendered / held back unless asked / always rendered and never held back, per spec 191–202); the four-option call and the three-option A-alone case; the reject evidence gate and its read-only tightening; the stage-2 approval of out-of-boundary checks with the cost of declining stated in the call; and the closed list of permitted writes **including the supersession rewrite to `**Decision-retired:**` at set-aside time**.
6. **Stage 3: batch dispatch** (283–323) — sequential; `User decision: <resolution>` carrying the full self-contained text, never a bare label; **the dispatch-copy rule** with its closed strip list and the rule that the rewritten `**Location:**` travels; the dispatch marker written beneath the pin line, or beneath the `**Decision:**` line where no pin exists.
7. **Stage 3.5: orchestrator-run verification** (325–376) — a check passes when its logged raw output matches the recorded expected result, never on exit status alone; the soft-check rule (excerpt with `path:line`, not a verdict; always `advisory`); the execution boundary and its two terms defined once (spec 471–500).
8. **The decision record** (847–1128) — every written form from the Interfaces block above, the at-most-one rule, the slot order, the two-attempt retirement and the second-retirement `stalled — no progress` heading, the pin's exclusion list and `sed | grep -v | shasum` extraction with its canonicalisation, and the pin-mismatch attribution rule.
9. **The five outcomes** (650–716) — the outcome table, the `AskUserQuestion`-only rule, the `other…` restatement with its bounded retry, and the reject reason with its bounded retry.

- [ ] **Step 4: Assert every written form landed**

```bash
S=plugins/code-review/skills/decision-gate/SKILL.md
for t in '**Decision:**' '**Decision-retired:**' '**Verification-plan:**' \
         '**Decision-pin:**' '**Dispatch:**' '**Verification:**' \
         'block=<sha256>' 'attempt <N> dispatched' 'hard|advisory|unavailable' \
         ':edit|:ref' '(was:' '(soft)'; do
  grep -qF "$t" "$S" && echo "ok   $t" || echo "MISS $t"
done
```

Expected: twelve `ok` lines, no `MISS`.

- [ ] **Step 5: Assert the rules that carry the design's weight**

```bash
S=plugins/code-review/skills/decision-gate/SKILL.md
for t in 'exactly one physical line' 'first backticked token' \
         'never on exit status alone' 'AskUserQuestion' \
         'read-only inspection' 'two-attempt' 'stalled — no progress'; do
  grep -qF "$t" "$S" && echo "ok   $t" || echo "MISS $t"
done
```

Expected: seven `ok` lines, no `MISS`.

- [ ] **Step 6: Assert stage 4 is *not* in the skill**

The spec puts the status write-back in the commands, deliberately. Confirm the skill says so rather than doing it:

```bash
grep -q 'command-owned' plugins/code-review/skills/decision-gate/SKILL.md && echo PASS || echo FAIL
```

Expected: `PASS`

- [ ] **Step 7: Commit**

```bash
git add plugins/code-review/skills/decision-gate/
AV_COMMIT_SKILL=1 git commit -m "feat(code-review): add the decision-gate skill carrying the decision-stage doctrine"
```

---

### Task 3: Register the vocabulary in the shared report schema

**Spec:** `Status vocabulary extension` → the `report-format/SKILL.md` bullet (796–810); `Verification` step 5's second walk (1305–1315).

This is the schema both plugins share, so it comes before every consumer that reads it.

**Files:**
- Modify: `plugins/qa/skills/report-format/SKILL.md` (status write-back at `:231-233`; the issue-field list at `:95-102`)
- Test: grep assertions below

**Interfaces:**
- Consumes: the field names and written forms from Task 2.
- Produces: the documented schema Tasks 4–9 conform to.

- [ ] **Step 1: Write the failing checks**

```bash
R=plugins/qa/skills/report-format/SKILL.md
for t in '🚫 Rejected' 'Decision-pin' 'first backticked token' 'by prefix'; do
  grep -qF "$t" "$R" && echo "ok   $t" || echo "MISS $t"
done
```

Expected now: four `MISS` lines.

- [ ] **Step 2: Extend the status write-back section**

Rewrite the `### Status write-back` section (currently `:231-233`) so it registers three things:

1. `🚫 Rejected` beside `✅ Fixed` and `⚠️ Partially Fixed`, with the full grammar `**Status:** <icon> <text> (YYYY-MM-DD)[ — <reason>]` and the rule that the ` — <reason>` tail is permitted **only** for `🚫 Rejected`.
2. The **prefix read rule**: a consumer matches the status value by prefix, never by whole-line equality, because the tail is not the reader's to control.
3. That a rejected issue is terminal — it is excluded from the fix set and its line is never overwritten.

- [ ] **Step 3: Extend the `Location:` field documentation**

At the issue-field list (`:99`), document both written forms and both clauses of the read rule: first backticked token with any trailing parenthetical ignored; where the line carries no backticked token, the first whitespace-delimited token after the field name. State that the loop always writes the backticked form and that the second clause exists for legacy lines. Keep the existing `unknown:0` placeholder guidance — it is still how a QA report signals "unidentifiable".

- [ ] **Step 4: Register the six loop-written optional fields**

Add a subsection documenting `**Decision:**`, `**Decision-retired:**`, `**Verification-plan:**`, `**Decision-pin:**`, `**Dispatch:**` and `**Verification:**` as optional, loop-written fields of the shared finding block — written by `/fix-report` and `/fix-all` into QA reports by construction. Reproduce each written form. State the one-physical-line invariant and the slot order (`**Status:**` first under the heading; these below it).

- [ ] **Step 5: Re-run the checks**

```bash
R=plugins/qa/skills/report-format/SKILL.md
for t in '🚫 Rejected' '**Decision:**' '**Decision-retired:**' '**Verification-plan:**' \
         '**Decision-pin:**' '**Dispatch:**' '**Verification:**' \
         'first backticked token' 'by prefix' 'exactly one physical line'; do
  grep -qF "$t" "$R" && echo "ok   $t" || echo "MISS $t"
done
```

Expected: ten `ok` lines, no `MISS`.

- [ ] **Step 6: Commit**

```bash
git add plugins/qa/skills/report-format/SKILL.md
AV_COMMIT_SKILL=1 git commit -m "docs(qa): register the rejected status, the extended location form and the loop-written fields"
```

---

### Task 4: `fix-auto` read-side duties

**Spec:** `Status vocabulary extension` → the `fix-auto.md` bullet (779–795).

**Files:**
- Modify: `plugins/code-review/agents/fix-auto.md` (Phase 1 field table at `:36-49`; Phase 6 at `:288`)
- Test: `scripts/check_agent_frontmatter.py` plus greps

**Interfaces:**
- Consumes: the status grammar and Location read rule from Task 3.
- Produces: the abort behaviour Task 7 and Task 8 collect as **Failed**.

- [ ] **Step 1: Write the failing check**

```bash
grep -q '🚫 Rejected' plugins/code-review/agents/fix-auto.md && echo PASS || echo FAIL
```

Expected now: `FAIL`

- [ ] **Step 2: Add the Phase 1 abort**

In Phase 1, after the required-fields handling, add a rule: if the dispatched block carries a `**Status:**` line whose value begins with `🚫 Rejected`, abort immediately with an explicit error naming the issue and the rejected status. Match by **prefix** — the line may carry a ` — <reason>` tail.

State why the abort is safe for callers: it returns **before** Phase 6, so it emits none of the three verdict values, and the dispatching command collects it as **Failed**.

- [ ] **Step 3: Leave Phase 6 alone, and say so**

Add one sentence to Phase 6: the verdict vocabulary is Fixed / Partially Fixed / Failed and is **unchanged** — `🚫 Rejected` is a report status, never a fixer verdict. Do not add a fourth value.

- [ ] **Step 4: Apply the Location read rule**

In the Phase 1 field table, the `Location` row currently reads `` **Location:** `path:line` ``. Extend it to both written forms and both read-rule clauses, so a block carrying `` **Location:** `docs/x.md:12` (was: `—`) `` parses as `docs/x.md:12` and not as location-less.

- [ ] **Step 5: Re-run the checks**

```bash
F=plugins/code-review/agents/fix-auto.md
grep -q '🚫 Rejected' "$F" && echo "ok   abort" || echo "MISS abort"
grep -q '(was:' "$F" && echo "ok   location" || echo "MISS location"
grep -c 'Partially Fixed' "$F"
python3 scripts/check_agent_frontmatter.py
```

Expected: `ok abort`, `ok location`, a non-zero count unchanged from before the edit, and the validator exiting 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/code-review/agents/fix-auto.md
AV_COMMIT_SKILL=1 git commit -m "feat(code-review): abort fix-auto on a rejected block and read both location forms"
```

---

### Task 5: `/fix` read-side duties and the shared render format

**Spec:** `Scope` (90–97); `Status vocabulary extension` → the `fix.md` bullet (773–778); `Components` → the `commands/fix.md` row (637).

`/fix` adopts the **rendering contract only**. Its gate stays `(A / B / no)` and it never writes `🚫 Rejected`. Do not give it the five-outcome sweep.

**Files:**
- Modify: `plugins/code-review/commands/fix.md` (Phase 0 at `:35-123`; Phase 1 Location rows at `:132`, `:167-173`; Phase 3 at `:236-241`; Phase 8 at `:524-570`)
- Test: greps below

**Interfaces:**
- Consumes: the `Alternatives` render format from Task 2's skill.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing checks**

```bash
F=plugins/code-review/commands/fix.md
for t in '🚫 Rejected' 'decision-gate' 'first backticked token'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
```

Expected now: three `MISS` lines.

- [ ] **Step 2: Add the Phase 0 abort**

In Phase 0, after Step 0.5 (`Handle not found`), add a step: if the block resolved by ID carries a `**Status:**` line whose value begins with `🚫 Rejected`, stop and report that the finding was rejected on that date for that reason, without editing anything. Match by prefix.

State the reason this guard is needed here and nowhere else: `/fix` has no Step 1.3 filter — Phase 0 resolves by ID — so neither guard the other two entry points rely on covers it.

- [ ] **Step 3: Fix the Phase 1 usability test**

The test at `:167` scans for `—` and reads any line containing one as unusable. Under the extended form the reviewer's original lives inside a `(was: …)` tail and routinely contains `—`. Replace the test with the two-clause read rule, and say explicitly that a `—` inside the `(was: …)` tail is part of the reviewer's original and never the location.

Also update the `Location` row of the Phase 1 field table (`:132`) to name both written forms.

- [ ] **Step 4: Delegate the Phase 3 `Alternatives` format**

Phase 3 currently restates the format at `:238`. Replace the restatement with an instruction to load `code-review:decision-gate` for the `Alternatives:` render format, and keep one sentence recording that render behaviour is identical and the gate stays `Which resolution should I apply? (A / B / no)`. The goal is that all three entry points render one format.

- [ ] **Step 5: Add the Phase 8 second-status rule**

In Phase 8, before Step 8.2's insert, add: never write a second `**Status:**` line over an existing one. If the block already carries a `**Status:**` line, update it in place; if that line is `🚫 Rejected`, do not touch it at all — Phase 0 should already have aborted, and reaching here means the block was pasted rather than resolved by ID.

- [ ] **Step 6: Re-run the checks**

```bash
F=plugins/code-review/commands/fix.md
for t in '🚫 Rejected' 'decision-gate' 'first backticked token' 'second **Status:**'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
grep -q 'A / B / no' "$F" && echo "ok   gate unchanged" || echo "MISS gate unchanged"
```

Expected: five `ok` lines, no `MISS`.

- [ ] **Step 7: Commit**

```bash
git add plugins/code-review/commands/fix.md
AV_COMMIT_SKILL=1 git commit -m "feat(code-review): guard /fix against rejected findings and share the alternatives format"
```

---

### Task 6: `/fix-report` read side — filter, edge case, frontmatter grants

**Spec:** `Status vocabulary extension` → consumers list (766–769); `Delivery` → frontmatter grants (1176–1186).

Split from Task 7 deliberately: a reviewer can accept the filter and the grants while rejecting the checklist redesign.

**Files:**
- Modify: `plugins/code-review/commands/fix-report.md` (frontmatter `:2`; Step 1.3 at `:84-93`; Step 1.5 at `:103-119`)
- Test: greps below

**Interfaces:**
- Consumes: the status grammar from Task 3.
- Produces: the four new `Bash(...)` grants Task 7's pin work needs.

- [ ] **Step 1: Write the failing checks**

```bash
F=plugins/code-review/commands/fix-report.md
for t in '🚫 Rejected' 'Bash(shasum:*)' 'Bash(sha256sum:*)' 'Bash(sed:*)' 'Bash(grep:*)'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
```

Expected now: five `MISS` lines.

- [ ] **Step 2: Extend the Step 1.3 filter**

Add `**Status:** 🚫 Rejected` to the three status lines the filter recognises, and state that the match is by **prefix** because the rejected line carries a ` — <reason>` tail. A rejected finding is terminal: it never re-enters the fix set.

- [ ] **Step 3: Fix the Step 1.5 all-resolved message**

The current message reads "All issues in the report(s) have been resolved." With `🚫 Rejected` in the vocabulary the presence of a `**Status:**` field no longer implies a fix. Change the message so it distinguishes the two, naming both counts — for example "N fixed, M rejected. Nothing to do."

- [ ] **Step 4: Add the four frontmatter grants**

Append `Bash(shasum:*)`, `Bash(sha256sum:*)`, `Bash(sed:*)` and `Bash(grep:*)` to `allowed-tools:`. Do **not** collapse the existing per-tool entries into a broader grant — per-tool enumeration is the point of a pre-approval.

`sha256sum` is the fallback where `shasum` is absent (many Linux images); `sed` and `grep` cut the block excerpt and drop its loop-written lines before it reaches the hasher. `git hash-object` and `git status` need no new grant — both fall under the `Bash(git:*)` already present.

- [ ] **Step 5: Re-run the checks**

```bash
F=plugins/code-review/commands/fix-report.md
for t in '🚫 Rejected' 'Bash(shasum:*)' 'Bash(sha256sum:*)' 'Bash(sed:*)' 'Bash(grep:*)'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
head -2 "$F" | grep -c 'Bash(git:\*)'
```

Expected: five `ok` lines, and `1` — the pre-existing git grant survived.

- [ ] **Step 6: Commit**

```bash
git add plugins/code-review/commands/fix-report.md
AV_COMMIT_SKILL=1 git commit -m "feat(code-review): filter rejected findings in /fix-report and grant the hashing tools"
```

---

### Task 7: `/fix-report` decision stage — partitioned checklist, gate, write-back

**Spec:** `Components` → the `commands/fix-report.md` row (635); `Ordering inside /fix-report` (639–648).

**Files:**
- Modify: `plugins/code-review/commands/fix-report.md` (Step 2.2 at `:127-170`; Step 2.4 at `:180-193`; Step 3.1 at `:197-218`; Step 4.1 at `:222-242`; Step 4.2 at `:244-264`)
- Test: greps below

**Interfaces:**
- Consumes: Task 2's skill (`code-review:decision-gate`), Task 6's frontmatter grants.
- Produces: a Step 4.1.5 mirroring `fix-all.md:353-370`, and a decision-stage summary block Task 8 reuses.

- [ ] **Step 1: Write the failing checks**

```bash
F=plugins/code-review/commands/fix-report.md
for t in 'Step 4.1.5' 'decision-gate' 'status_write_failures' 'Skip these 3'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
```

Expected now: four `MISS` lines.

- [ ] **Step 2: Partition the checklist in Step 2.2**

`needs-decision` findings move onto their own labelled leading page(s), ahead of every severity-sorted `auto` page. Write the page-capacity rule explicitly, because it is not the current 4-per-page:

- any page carrying the appended skip item holds **3** issues, needs-decision or `auto` alike; 4 is deliverable only on a page with nothing appended, which is only ever the final page;
- more than 3 needs-decision findings occupy successive leading pages, all ahead of the first `auto` page;
- the appended item is **relabelled for what it does on that page** — `Skip these 3 — next decision page (<n> of <N> shown)` on a non-final needs-decision page, `Skip these 3 — on to the auto fixes` on the last — never the imported description "Proceed with issues selected so far, skip remaining pages" (`:158-161`, routed to Step 3 at `:167`), which is false on a page that pages forward;
- there is **no early exit** from the needs-decision pages: reaching the first `auto` page costs ⌈K/3⌉ answered pages for K needs-decision findings, and the four-option ceiling leaves no slot for a skip-all item. Step 2.2 states that count on the first needs-decision page;
- where no `auto` finding survives the Step 1.3 filter there is no page to advance to: the last needs-decision page is the final page, nothing is appended, it holds 4, and selection ends when it is answered.

- [ ] **Step 3: Replace Step 2.4 with the gate**

Delete the prose at `:180-193` and replace it with an invocation of `code-review:decision-gate`, scoped: it runs **stages 0–2 in this slot** and returns the decided findings to Step 3 rather than dispatching them itself.

- [ ] **Step 4: Extend Step 3.1**

Step 3 dispatches the decided findings and the selected `auto` findings in **one sequential batch, decided first**. Add the dispatch-copy rule by reference to the skill, and state that stage 3.5's orchestrator-run verification applies to the **decided findings only** — the `auto` findings keep today's path where `fix-auto`'s own verdict is collected.

- [ ] **Step 5: Add Step 4.1.5**

Insert a new `### Step 4.1.5: Verify Status writes` between Step 4.1 (`:222`) and Step 4.2 (`:244`), mirroring `fix-all.md:353-370`: re-read the `source_file`, confirm the status line is the next non-blank line below the issue heading, collect `{issue_id, source_file, reason}` into a `status_write_failures` list with `reason` one of `edit-errored`, `status-line-missing`, `status-line-wrong-text`, and do not retry inside the step.

- [ ] **Step 6: Extend Step 4.2**

Add two things: the `**Status write failures:**` block consuming `status_write_failures` (mirror `fix-all.md`'s wording), and a **decision-stage summary block** printed after Step 4.1 / 4.1.5. The existing template is closed — `| # | Issue | Status |` rows plus the counts and the reports-updated list — and holds no slot for the decision stage's disclosures. The block names all eight: stage 0's Failed findings, an unverified rejection, advisory verification, `verification: unavailable`, the partial-coverage warning, out-of-scope writes, unpinned findings, and the `stalled — no progress` heading.

- [ ] **Step 7: Re-run the checks**

```bash
F=plugins/code-review/commands/fix-report.md
for t in 'Step 4.1.5' 'decision-gate' 'status_write_failures' \
         'Skip these 3' 'stalled — no progress' 'verification: unavailable'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
grep -c 'Proceed with issues selected so far' "$F"
```

Expected: six `ok` lines, and `0` — the false description is gone.

- [ ] **Step 8: Commit**

```bash
git add plugins/code-review/commands/fix-report.md
AV_COMMIT_SKILL=1 git commit -m "feat(code-review): partition the checklist and run the decision gate in /fix-report"
```

---

### Task 8: `/fix-all` Step 5 and the zero-auto path

**Spec:** `Components` → the `commands/fix-all.md` row (636); `Edge cases` (1130–1141); `Status vocabulary extension` → consumers list (770–772); `Delivery` → frontmatter grants.

**Files:**
- Modify: `plugins/code-review/commands/fix-all.md` (frontmatter `:2`; progress table `:24-31`; Step 1.3 `:151-160`; Step 1.5 `:168-184`; Step 2.2.5 `:213-227`; new Step 5 after `:414`)
- Test: greps below

**Interfaces:**
- Consumes: Task 2's skill, Task 7's decision-stage summary block shape.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing checks**

```bash
F=plugins/code-review/commands/fix-all.md
for t in '🚫 Rejected' 'Step 5' 'decision-gate' 'Bash(shasum:*)'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
```

Expected now: four `MISS` lines.

- [ ] **Step 2: Filter, edge case and grants**

Apply the same three changes Task 6 made to `/fix-report`: `🚫 Rejected` in the Step 1.3 filter matched by prefix; the Step 1.5 all-resolved message distinguishing fixed from rejected; and the four `Bash(...)` grants appended to `allowed-tools:`.

- [ ] **Step 3: Add the fifth progress row**

Add row 5 to the table under **MANDATORY FIRST STEP**:

| # | subject | activeForm |
|---|---------|-----------:|
| 5 | Resolve needs-decision findings | Resolving needs-decision findings... |

- [ ] **Step 4: Change the Step 2.2.5 zero-auto edge case**

Today it aborts with a message pointing at `/fix-report` or `/fix <ID>` (`:223-227`). Change it: when the fix list is empty **and** `needs_decision` is non-empty, Steps 3–4 are skipped and control goes straight to Step 5's offer. Keep the abort only for the case where both lists are empty.

Record the two consequences Step 5 must compensate for on this path: Step 4.2 never printed the "Requires user decision" list, and Steps 3–4 never ran, so their progress rows are still open — today only the abort helper closes them.

- [ ] **Step 5: Write Step 5**

Add `## Step 5: Resolve needs-decision findings` after Step 4.2. It must:

1. Do nothing at all when `needs_decision` is empty — no extra click when there is nothing to decide.
2. Otherwise ask, naming the count and the batch shape ("Resolve 3 findings requiring your decision now? 3 findings to analyse, in 1 batch of at most 8").
3. On **no**: stop without repeating the list, having closed the progress rows Step 5 owns.
4. On **yes**: run `code-review:decision-gate` for **stages 0 through 3.5**, then re-run the Step 4.1 / 4.1.5 write-and-verify procedure over the decision batch — Steps 4.1 / 4.1.5 have already run and closed their task by then, so Step 5 owns the write-back for its own findings — and append a decision-stage summary block after the one Step 4.2 printed.
5. On the zero-auto path only: print the "Requires user decision" list itself before asking, and close Steps 3–4's progress rows as well as its own.

- [ ] **Step 6: Re-run the checks**

```bash
F=plugins/code-review/commands/fix-all.md
for t in '🚫 Rejected' '## Step 5' 'decision-gate' 'Bash(shasum:*)' \
         'Bash(sha256sum:*)' 'Bash(sed:*)' 'Bash(grep:*)'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
grep -c 'All remaining issues are flagged' "$F"
```

Expected: seven `ok` lines, and `0` — the old abort message is gone.

- [ ] **Step 7: Commit**

```bash
git add plugins/code-review/commands/fix-all.md
AV_COMMIT_SKILL=1 git commit -m "feat(code-review): offer the decision stage from /fix-all after the auto batch"
```

---

### Task 9: `/qa:loop` — three duties around the shared block

**Spec:** `Status vocabulary extension` → the `loop.md` bullet (811–824) and the paragraph at 830–845; `Verification` step 5 (1316–1323).

**Files:**
- Modify: `plugins/qa/commands/loop.md` (Step 2.5 carry-over `:540-545`; Step 3a pre-filter `:609-613`; Step 3c dispatch `:680-695`; Step 4.1 `:902-914`)
- Test: greps below

**Interfaces:**
- Consumes: the field names and read rules from Task 3.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing checks**

```bash
F=plugins/qa/commands/loop.md
for t in '🚫 Rejected' 'Decision-pin' 'first backticked token'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
```

Expected now: three `MISS` lines.

- [ ] **Step 2: Keep a rejected issue out of the fix set**

In Step 3a's pre-filter (`:609-613`), add a drop rule: an issue whose block carries a `**Status:**` line beginning `🚫 Rejected` never enters `fix_candidates`. Match by prefix.

- [ ] **Step 3: Protect a rejected line at Step 4.1**

Step 4.1 (`:902-907`) updates an existing Status line in place, and the sidecar binds scenario → [QA-IDs], so a sibling issue passing on the same scenario would overwrite a `🚫 Rejected` line and its reason. Add the guard: **leave a `🚫 Rejected` line exactly as found** — never update it in place, never add a second line beside it.

Leave the existing "`⚠️ Partially Fixed` is never written" rule (`:917`) unchanged.

- [ ] **Step 4: Carry the decision record over on reuse and adopt**

Step 2.5 (`:540-545`) preserves `**Status:**` lines across a re-render. Extend it to carry over `**Decision:**`, `**Decision-retired:**`, `**Verification-plan:**`, `**Decision-pin:**`, `**Dispatch:**` and `**Verification:**`, and the rewritten `**Location:**` line with its `(was: …)` parenthetical — matched by the same `QA-NNN` token, exactly as Status lines are. Without this a re-render drops the decision record and the corrected address the replay path depends on.

- [ ] **Step 5: Apply the dispatch-copy rule at Step 3c**

Step 3c forwards "the full issue block from the report, including all fields" (`:684`). `/qa:loop` is therefore a dispatcher of the shared block and must apply the same closed strip list: strip `**Verification-plan:**`, `**Decision-pin:**`, `**Dispatch:**`, `**Verification:**` and `**Decision-retired:**`, reduce a `**Decision:**` line to its trailing `User decision: <resolution>`, and let the rewritten `**Location:**` line travel. Without it a decided-but-unfixed finding hands the fixer the checks its verification grades it with.

- [ ] **Step 6: Fix the two Location read sites**

`:611` drops any issue whose Location is `unknown:0` or missing, and `:691` tells `fix-auto` to return Failed on the same. Both currently read the whole line. Under the extended form stage 2 preserves the original `unknown:0` **inside the `(was: …)` tail**, so a whole-line test reads a repaired finding as location-less and silently drops it. Apply the two-clause read rule at both sites.

- [ ] **Step 7: Re-run the checks**

```bash
F=plugins/qa/commands/loop.md
for t in '🚫 Rejected' '**Decision:**' '**Decision-pin:**' '**Verification-plan:**' \
         'first backticked token' '(was:'; do
  grep -qF "$t" "$F" && echo "ok   $t" || echo "MISS $t"
done
grep -c 'never written' "$F"
```

Expected: six `ok` lines, and a non-zero count — the Partially Fixed rule survived.

- [ ] **Step 8: Commit**

```bash
git add plugins/qa/commands/loop.md
AV_COMMIT_SKILL=1 git commit -m "feat(qa): preserve rejections and the decision record across loop re-renders"
```

---

### Task 10: Documentation, prose corrections and the version bump

**Spec:** `Delivery` (1146–1208); `Status vocabulary extension` → the `docs/plugins/code-review.md` bullet (825–828).

Do the version bump **last within this task**, so `check_plugin_versions.py` goes red then green in one cycle.

**Files:**
- Modify: `docs/plugins/code-review.md` (`:5` version; `:125` table; `:134` override sentence; new sections; upgrade notes)
- Modify: `docs/plugins/qa.md` (`:5` version; upgrade notes)
- Modify: `README.md` (`:36` code-review row; `:43` qa row)
- Modify: `.claude-plugin/marketplace.json` (`:10-11` code-review; `:59-60` qa)
- Modify: `plugins/code-review/.claude-plugin/plugin.json` (`:4`), `plugins/qa/.claude-plugin/plugin.json` (`:4`)
- Test: `scripts/check_plugin_versions.py`

**Interfaces:**
- Consumes: everything Tasks 1–9 built — the docs describe it.
- Produces: nothing.

- [ ] **Step 1: Write the failing check**

```bash
python3 scripts/check_plugin_versions.py
```

Expected now: exit 0 (all four places agree at 1.17.3 / 2.5.2). This is the *baseline*, not the red — the red comes in Step 6.

- [ ] **Step 2: Correct the superseded prose**

Three places claim `/fix-all` skips `needs-decision` findings full stop, which stops being the whole truth:

- `plugins/code-review/.claude-plugin/plugin.json` — the `description` field
- `.claude-plugin/marketplace.json:10` — the code-review `description`
- `README.md:36` — the code-review row

Reword each so it says `/fix-all` fixes everything else and then **offers** to resolve the `needs-decision` findings.

`docs/plugins/code-review.md:134` currently reads "There is no override flag — use `/fix-report` or `/fix <ID>`". That is superseded: `/fix-all` now offers the decision stage itself. Rewrite the sentence.

- [ ] **Step 3: Extend the "when to use what" table**

At `docs/plugins/code-review.md:121-126`, add a row for the decision stage:

| Need | Use |
|---|---|
| Resolve `needs-decision` findings in bulk, with the code analysed | `/fix-all` (offers the decision stage after the auto batch) or `/fix-report` (decision findings lead the checklist) |

- [ ] **Step 4: Add the new documentation sections**

In `docs/plugins/code-review.md`, add sections for: the decision stage (the flow a user sees — analysis fan-out, the sweep, the batch), the `decision-analyst` agent, the `🚫 Rejected` status with its ` — <reason>` tail, the extended `**Location:**` form, and the six loop-written finding-block fields.

- [ ] **Step 5: Write the upgrade notes**

Both skews are **requirements**, not recommendations. In `docs/plugins/code-review.md` and `docs/plugins/qa.md` upgrade notes:

- `code-review` 1.18.0 expects `qa` ≥ 2.6.0 for any report the two share. An older `/qa:loop` overwrites a `🚫 Rejected` line at `loop.md:902-907` when a sibling issue passes on the same scenario.
- Any report containing `🚫 Rejected`, **or a `**Location:**` line in the extended `(was: …)` form**, requires `code-review` ≥ 1.18.0 wherever it is read. A 1.17.3 Step 1.3 filter does not know the value and re-offers the rejected finding; a 1.17.3 `/fix` reads the reviewer's original inside the `(was: …)` tail as a missing location.

State the intra-plugin skew in `docs/plugins/code-review.md` specifically — it is the worse of the two, because a rejection reversed by an older reader is terminal and hand-recoverable only.

- [ ] **Step 6: Bump both versions and watch the check go red, then green**

Bump `plugins/code-review/.claude-plugin/plugin.json` to `1.18.0` **only**, then run:

```bash
python3 scripts/check_plugin_versions.py
```

Expected: **non-zero exit**, reporting a mismatch across the four places. That is the red.

Now bump the remaining three code-review places (`marketplace.json`, the README row, `docs/plugins/code-review.md:5`) and all four qa places to `2.6.0`, then re-run:

```bash
python3 scripts/check_plugin_versions.py
```

Expected: exit 0.

- [ ] **Step 7: Confirm no prefix regression**

```bash
bash plugins/code-review/scripts/check-prefix-sync.sh
```

Expected: exit 0. This change adds no Category→Prefix mapping, so the script is a regression check only.

- [ ] **Step 8: Commit**

```bash
git add docs/plugins/code-review.md docs/plugins/qa.md README.md \
        .claude-plugin/marketplace.json \
        plugins/code-review/.claude-plugin/plugin.json \
        plugins/qa/.claude-plugin/plugin.json
AV_COMMIT_SKILL=1 git commit -m "docs: document the decision stage and release code-review 1.18.0, qa 2.6.0"
```

---

### Task 11: The end-to-end fixture run

**Spec:** `Verification` step 4 (1238–1285). Read it in full before starting — every post-condition below is bound to a scripted answer, and "it ran without error" is explicitly not the pass condition.

**Files:**
- Create: `docs/testing/fixtures/needs-decision-e2e/report.md` — the synthetic report
- Create: `docs/testing/fixtures/needs-decision-e2e/target-a.md`, `target-b.md` — the files the findings point at
- Create: `docs/testing/fixtures/needs-decision-e2e/ANSWERS.md` — the scripted sweep answers
- Test: two manual runs, post-conditions below

**Interfaces:**
- Consumes: everything Tasks 1–10 built.
- Produces: the evidence that the design works end to end.

- [ ] **Step 1: Write the fixture report**

`report.md` carries five findings:

| ID | Kind | Purpose |
|---|---|---|
| `DOC-001` | `auto` | proves the auto path still works |
| `DOC-002` | `auto` | proves the batch is sequential |
| `DOC-003` | `needs-decision`, `**Location:** —` | exercises stage 0 |
| `DOC-004` | `needs-decision`, referent **exists** | exercises the `Rejection candidate` path |
| `DOC-005` | `needs-decision`, ordinary dead reference | exercises A/B, the pin, and stage 3.5 |

Each finding carries the canonical fields (`**ID:**`, `**Location:**`, `**Category:**`, `**Problem:**`, `**Remediation:**`) and, for the three decision findings, `**Fix-policy:** needs-decision` with a `**Drift-class:**` value.

`DOC-004`'s referent must genuinely exist in `target-b.md`, so the analyst can return a `Rejection candidate` backed by a real citation.

- [ ] **Step 2: Script the answers**

`ANSWERS.md` records, per finding, exactly what the operator answers — so the run is reproducible and the post-conditions are bound to a handling rather than to whatever the run produced:

- `DOC-003` — supply **no** path when stage 0 asks
- `DOC-004` — choose `reject`, with a stated reason
- `DOC-005` — choose **A**

- [ ] **Step 3: Snapshot the pristine fixture**

Each entry run starts from a pristine copy — the report **and the files it points at**. Run the second entry over the first run's leftovers and the findings are already `✅ Fixed` or already decided, so the Step 1.3 filter and the replay path swallow them and the list is satisfied by writes the run under test never made.

```bash
cp -R docs/testing/fixtures/needs-decision-e2e /tmp/nd-pristine
```

- [ ] **Step 4: Run entry 1 — `/fix-all`**

Restore the pristine copy, run `/fix-all` against `report.md`, answer per `ANSWERS.md`, and check every post-condition:

- `DOC-003`: reported **Failed** in the run summary, **no** `**Status:**` line written, never dispatched
- `DOC-004`: `**Status:** 🚫 Rejected (YYYY-MM-DD) — <reason>` with the reason present, and **no** `**Decision:**` line. Bound to the candidate path, not merely to the status: the analyst's block must have carried a `Rejection candidate` whose evidence is command-or-tool-plus-output; the transcript must show those exact citations re-run with raw output displayed at the gate; and the run summary must **not** mark this rejection `unverified`. A run in which the analyst returned no candidate does not satisfy the step, however the status line reads
- `DOC-005`: a `**Decision:**` line in the delimited grammar; `**Location:**` rewritten to the analyst's verified `Target` normalised to `path:line`, with the reviewer's original recoverable from `(was: …)`, and the line still carrying both when the run ends; `**Status:** ✅ Fixed (YYYY-MM-DD)` with `**Verification:** hard — <the fixture's scripted checks>`; stage 3.5's raw output for exactly those checks present in the transcript, and the status derivable from it. `⚠️ Partially Fixed`, a missing `**Status:**` line, or any other `**Verification:**` value **fails** the step
- `DOC-001`, `DOC-002`: `✅ Fixed`
- transcript ordering: all analyst dispatches in a single turn, then `fix-auto` dispatches one at a time

- [ ] **Step 5: Run entry 2 — `/fix-report`**

Restore the pristine copy again. Run `/fix-report`, confirm the three `needs-decision` findings occupy the leading page(s) ahead of any `auto` page, answer per `ANSWERS.md`, and check the **same whole list** — both entry runs must satisfy it.

- [ ] **Step 6: Confirm no finding was skipped**

A run in which any `needs-decision` finding is skipped does not satisfy the step: `skip` writes nothing, so the list would be met vacuously by a run that never reached stages 3, 3.5 or 4.

```bash
grep -c '**Decision:**\|🚫 Rejected' docs/testing/fixtures/needs-decision-e2e/report.md
```

Expected: `2` — `DOC-004`'s rejection and `DOC-005`'s decision. `DOC-003` correctly has neither.

- [ ] **Step 7: Commit the fixture and record the results**

```bash
git add docs/testing/fixtures/needs-decision-e2e/
AV_COMMIT_SKILL=1 git commit -m "test(code-review): add the needs-decision end-to-end fixture and scripted answers"
```

---

### Task 12: Probe the two-word `Bash` specifier

**Spec:** `Verification` step 6 (1330–1341); `Residual risks` → "The analyst's read-only grant may be inert" (1363–1371).

This task **records a fact**; it does not repair anything. Do not re-spell the grant based on the result.

**Files:**
- Modify: `docs/plugins/code-review.md` — the residual-risk note, updated with the observed outcome
- Test: the probe itself

**Interfaces:**
- Consumes: Task 1's agent.
- Produces: the recorded verdict.

- [ ] **Step 1: Dispatch the probe**

Dispatch `code-review:decision-analyst` once against a throwaway finding, with an explicit instruction to run a write-capable git subcommand the narrowed grant must refuse — `git commit --dry-run` is the spec's example.

- [ ] **Step 2: Record which of three things happened**

| Observation | Verdict |
|---|---|
| The call was refused outright | The narrowing **is** enforced |
| It simply ran, with no prompt | The entry fell back to base `Bash` — the grant is **inert** |
| It raised a permission prompt | **Inconclusive** — both an honoured specifier grant and a base `Bash` grant fall through to a prompt on a non-matching command |

Record the third case as inconclusive, not as either verdict.

- [ ] **Step 3: Write the result into the residual-risk note**

Update the residual-risk paragraph in `docs/plugins/code-review.md` with what was observed, dated. If the grant is inert or the probe was inconclusive, say so plainly — the separation of the reader from the writer is then a convention the design relies on rather than a property it enforces.

- [ ] **Step 4: Commit**

```bash
git add docs/plugins/code-review.md
AV_COMMIT_SKILL=1 git commit -m "docs(code-review): record the decision-analyst grant probe result"
```

---

## Self-Review

Run against the spec after the plan is written; findings fixed inline.

**1. Spec coverage.** Every `##` section maps to a task: Purpose/Evidence → context only, no task. Scope → Tasks 1–10. The flow → Tasks 2, 7, 8. Components → Tasks 1, 2, 6, 7, 8. Decision outcomes → Task 2. Status vocabulary extension → Tasks 3, 4, 5, 6, 8, 9, 10. Decision record → Task 2 (grammars) + Tasks 3, 9 (registration). Edge cases → Tasks 7, 8. Delivery → Tasks 6, 7, 8, 10. Oracle → Task 11. Verification → Tasks 1, 10, 11, 12. Residual risks → Task 12 (probe) and Task 10 (upgrade notes).

**2. Placeholder scan.** No "TBD", no "add appropriate error handling", no "similar to Task N". Every prose task names the exact section, the exact anchor line, and the exact rule to write.

**3. Type consistency.** The six field names are spelled identically in Tasks 2, 3, 9 and in the Global Constraints. The two-clause Location read rule is quoted the same way in Tasks 3, 4, 5, 9. `status_write_failures` and its three `reason` values match `fix-all.md:365` exactly, which is what Task 7 mirrors.

**Two gaps found and closed while reviewing:**
- Task 6 originally lacked the Step 1.5 all-resolved fix, which the spec lists at 766–769 for both commands. Added as Step 3, and mirrored into Task 8 Step 2.
- Task 9 originally lacked the two `**Location:**` read sites (`loop.md:611`, `:691`), which the spec calls out separately from the carry-over duty. Added as Step 6.

**One thing this plan does not do,** stated rather than hidden: it adds no CI guard for the status vocabulary. The spec puts that out of scope by name and carries it as a residual risk. The greps in Tasks 3–9 are each task's own red/green cycle, typed at the terminal, and are deliberately not committed as a script — committing them would be the guard the spec declined.

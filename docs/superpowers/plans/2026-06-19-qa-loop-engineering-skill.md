# `qa:loop-engineering` Doctrine Skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an invocable `qa:loop-engineering` doctrine skill (qa plugin → 2.4.0) that codifies the discipline for authoring robust closed agent loops, anchored to `/qa:loop`.

**Architecture:** This is **prompt-engineering, not application code** — the deliverable is one markdown SKILL.md plus a version bump and docs-sync. There is no runtime to unit-test, so each task is verified by the repo's real checks: structural `grep` on the authored file, anchor-integrity `grep` against `loop.md`, the `scripts/check_plugin_versions.py` parity gate, and the existing hook test suite as a regression sanity. The skill changes **no runtime behavior** of any plugin.

**Tech Stack:** Claude Code plugin (markdown skill spec), Bash (`grep`/`jq`/`git`), `scripts/check_plugin_versions.py` version-parity gate. Commits use `env AV_COMMIT_SKILL=1 git commit` (the repo's commit-hook bypass), **no Co-Authored-By trailer**.

**Source spec:** `docs/superpowers/specs/2026-06-19-qa-loop-engineering-skill-design.md` (MoA-reviewed, converged). Both this plan and that spec are internal docs — **remove them before the 2.4.0 PR** (per the 2.3.0 cycle, commit `54d40c3`).

---

## Nature of this implementation (read first)

No pytest. Verification is the **real checks available in this repo**:
- **Structural checks** — `grep`/Read confirming the authored file contains the required frontmatter, sections, bar items, and anchors.
- **Anchor integrity** — `grep -F` confirming every named `/qa:loop` anchor the skill cites still exists in `plugins/qa/commands/loop.md`.
- **Invariant** — `grep` confirming the `loop.md` back-reference is prose, never a `Skill()` auto-load.
- **Parity** — `python3 scripts/check_plugin_versions.py` after the version bump.
- **Regression sanity** — `bash plugins/commit/tests/test-block-git-push.sh` (unrelated to this change; must stay green).

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `plugins/qa/skills/loop-engineering/SKILL.md` | **Create** — the doctrine (6 sections, 8+3 bar, oracle taxonomy, anti-patterns, anchors, checklist) | 1 |
| `plugins/qa/.claude-plugin/plugin.json` | **Modify** — version 2.3.0 → 2.4.0 | 2 |
| `.claude-plugin/marketplace.json` | **Modify** — qa `version` 2.3.0 → 2.4.0 | 2 |
| `README.md` | **Modify** — qa table-row version 2.3.0 → 2.4.0 | 2 |
| `docs/plugins/qa.md` | **Modify** — `**Version:**` 2.3.0 → 2.4.0 **and** create a `## Skills` section | 2 |
| `plugins/qa/commands/loop.md` | **Modify** — add a prose back-reference to `qa:loop-engineering` | 3 |

Tasks touch disjoint files (Task 2 fully owns `qa.md`; Task 3 fully owns `loop.md`), so they are safe to run as independent subagents. **Do Task 1 before Task 3** (Task 3's back-reference points at the skill Task 1 creates), but Task 2 is order-independent.

---

## Task 1: Create the `loop-engineering` SKILL.md

**Files:**
- Create: `plugins/qa/skills/loop-engineering/SKILL.md`
- Reference (read-only, to confirm anchors): `plugins/qa/commands/loop.md`

- [ ] **Step 1: Create the directory and write the skill file**

Write `plugins/qa/skills/loop-engineering/SKILL.md` with EXACTLY this content:

````markdown
---
name: loop-engineering
description: Use when designing, authoring, or reviewing a closed agent loop (test→fix→retest, audit→fix→re-audit, generate→verify→correct) in this marketplace — the minimum-bar checklist, the ground-truth oracle taxonomy, and the anti-patterns, anchored to /qa:loop as the reference implementation.
---

# Loop Engineering

## What a loop is, and when to invoke this skill

A closed agent loop is *act → verify → correct → repeat*, bounded by a budget. The **ground-truth oracle** — the signal that decides "correct" — is the load-bearing part; everything else is plumbing. A loop is only as trustworthy as the oracle that gates it.

Invoke this skill when authoring or reviewing any closed loop in this marketplace, before it ships. The minimum bar below separates **Universal** items (every loop) from **Conditional** items (only loops that persist state, mutate the workspace, or auto-correct). `/qa:loop` (`plugins/qa/commands/loop.md`) is the reference implementation — it conforms to the whole MUST bar; cite its named anchors when you need a worked example.

## The minimum bar

Every closed loop in this marketplace MUST meet the **Universal** items. The **Conditional** items become MUST when the loop **persists state, mutates the workspace, and/or auto-corrects toward a target**. Each Conditional item is gated independently by its own trigger; a loop that does not hit a trigger may mark that item **N/A with a one-line justification affirming it neither persists loop-critical state, mutates the workspace, nor auto-corrects** — never silently.

### Universal (always MUST)

1. **Name the oracle, and state what it cannot verify.** Declare the ground-truth signal *and* its blind spots. An unstated oracle is an unfalsifiable "it passed." → qa:loop's Coverage block reports `"Exercised"`, not `"Verified"`, for feature passes.
2. **Separate verifier authority from the actor; gate and log on the raw signal, not narration.** Only a fresh, independent re-run decides pass/fail; the fixer's self-verdict is advisory; never hand the verifier the exact target it grades; gate and log on the raw oracle output (exit code, HTTP status, row count, test output), never the actor's "I'm done." A fixer grading its own fix — or a loop logging narration — is self-report, not verification. → qa:loop glossary *Verifier authority*; the Error-Handling rule *"fix-auto says 'Fixed' but re-run still fails → Re-run is authoritative."*
3. **Disclose, don't gate, on coverage.** Shallow or partial coverage produces a WARNING (and a low-confidence-green message), never a green→red flip; the loop must be able to say "I converged but verified little." → qa:loop's shallow-coverage WARNING + low-confidence green.
4. **Default to a human gate; go headless only on explicit opt-in with a fail-closed TTY check.** Autonomous correctness is unreachable when the verifier is stochastic. → qa:loop's `--mode approve` default; approve/step abort without a TTY.
5. **Reuse fail-closed safety guards; don't reinvent them.** Environment/host guard, mutation/write guard (moot for a read-only loop), ambiguous input → ask/abort. → qa:loop's *Safety Guards (Apply in All Modes)*; `plugins/commit/scripts/block-git-push.sh` (deny > ask > allow) as the deterministic exemplar.
6. **Bound the loop with hard budgets.** Cap iterations ∧ dispatches ∧ time. Unbounded loops blow cost; weak budgets ship the first (false) green. → qa:loop's triple-gate (`--max-iterations` / `--max-dispatches` / `--time-budget`).
   - *Rider (model-heavy loops — recommended, not a universal MUST):* also cap cost/tokens. qa:loop has no cost ceiling despite being model-heavy, so this prescribes beyond the reference.
7. **Stop on no-progress and oscillation, and report "stopped" as distinct from success.** A loop can stall or oscillate well under budget; "stopped / budget-exhausted" must not read as "passed." → qa:loop's Step 3f regression-stop + no-progress stop; glossary *Oscillation*.
8. **Document the residual-risk list.** If you cannot enumerate what the loop fails to catch, it is not ready. → qa:loop's residual notes (auth-unverified, *Verifier-gaming residual (v1)*, 2xx-shaped gating).

### Conditional (MUST when the loop persists state, mutates the workspace, and/or auto-corrects)

9. **Guard provenance — don't auto-fix a suspect assertion.** *(Auto-correcting loops.)* Auto-generated or guessed assertions are not auto-fixed against correct source; the failure may be the assertion, not the code. A read-only loop has nothing to auto-fix and satisfies this trivially. → qa:loop's *Provisional plan-suspect guard (T3)* (excludes such scenarios from `fix_candidates`).
10. **Persist state in a durable sidecar with input hash-pinning, and be idempotent.** *(Stateful loops.)* Loop-critical state lives on disk, not in the conversation; the input is hashed to detect mid-run tampering; re-running on identical input reuses prior state by hash and never duplicates results or re-applies corrections. The orchestrator's own memory is lossy across many tool calls. → qa:loop's sidecar + plan hash; Step 1 "Resolve Report + Sidecar (Idempotency)".
11. **Keep writes scoped and recoverable.** *(Mutating loops.)* Touch only what you changed; never destroy the user's pre-existing work; leave changes uncommitted for human control. → qa:loop's `fix_touched_files = post − pre_loop_dirty`; scoped `git restore`.

## Oracle taxonomy

The oracle is the loop's load-bearing part. Classify it before you trust it.

- **Strong (tool / wire):** tests, type checker, build, exit codes, HTTP status, row counts, browser/E2E. Deterministic, fast, ungameable from inside the loop.
- **Soft (LLM-judged):** another agent's opinion. Slow, non-deterministic.

Rules: prefer strong oracles; a soft oracle MUST self-label its verdict *advisory* (e.g. a "Re-reviewed (advisory)" status, or qa:loop's `"Exercised"`, not `"Verified"`). The actor must never author the oracle nor be able to see-and-game it, and re-verification must be independent of the corrector.

## Anti-patterns

- **Self-graded auto-fix loop** — e.g. an autonomous code-review fix loop where "Fixed" is the fixer's own verdict, with no independent re-dispatch of the originating auditor. *(Prospective: no such loop exists in this repo yet; this is a design constraint derived by analogy from qa:loop's verifier-authority separation, to apply when that loop is built.)*
- **Reading `--auto` / exit-code-0 as "verified"** in CI — the disclosure layer is for a human reader, not a gate.
- **Auto-fixing a guessed or auto-generated assertion** against correct source.
- **A soft-only budget on an expensive (model-heavy) loop** with no cost ceiling.
- **Keeping loop-critical state in conversation context.**
- **Reporting PASS for a target the verifier structurally cannot reach** (auth-gated, worker-resident, async) instead of disclosing the gap.
- **Tightening the budget to force convergence** — that just ships the first green, which may be the false one.

## Reference implementation — `/qa:loop`

`/qa:loop` (`plugins/qa/commands/loop.md`) conforms to the whole MUST bar; reference its **named** anchors (stable across edits), each for one thing:

- *Verifier authority* (glossary) — fresh re-run gates; the fixer's verdict is advisory.
- *Verifier-gaming residual (v1)* — the honest "a capable fixer can still game a visible check" caveat.
- *Provisional plan-suspect guard (T3)* — auto-generated assertions excluded from auto-fix.
- *Safety Guards (Apply in All Modes)* — the fail-closed environment and mutation guards.
- *Status write-back* (glossary) — written once, only from the authoritative final run.
- The `## Coverage` block and the auth-unverified outcome — "Exercised vs Not verified" disclosure.
- `plugins/commit/scripts/block-git-push.sh` — the deterministic, fail-closed guard exemplar (deny > ask > allow).

## Review checklist

Paste this into a loop spec's review. One box per bar item (Universal, then Conditional); riders hang off their item and are not counted.

**Universal**
- [ ] 1. Oracle named, with its blind spots stated
- [ ] 2. Verifier authority separated from the actor; gates/logs on the raw signal, not narration
- [ ] 3. Coverage disclosed, never gated green→red
- [ ] 4. Human gate by default; headless opt-in with fail-closed TTY check
- [ ] 5. Fail-closed safety guards reused, not reinvented
- [ ] 6. Hard budgets on iterations ∧ dispatches ∧ time
  - [ ] 6-rider (model-heavy): cost/token ceiling
- [ ] 7. No-progress and oscillation stops; "stopped" reported as non-success
- [ ] 8. Residual-risk list documented

**Conditional** (N/A allowed with a one-line justification)
- [ ] 9. Provenance guard — suspect assertions not auto-fixed *(auto-correcting loops)*
- [ ] 10. Durable sidecar + input hash-pin + idempotent re-runs *(stateful loops)*
- [ ] 11. Scoped, recoverable writes *(mutating loops)*
````

- [ ] **Step 2: Verify the structure**

Run:
```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
echo "== frontmatter =="; head -4 plugins/qa/skills/loop-engineering/SKILL.md
echo "== sections (expect: What a loop is / The minimum bar / Oracle taxonomy / Anti-patterns / Reference implementation / Review checklist) =="
grep -nE '^## ' plugins/qa/skills/loop-engineering/SKILL.md
echo "== bar items (expect 1..11) =="
grep -cE '^[0-9]+\. \*\*' plugins/qa/skills/loop-engineering/SKILL.md
```
Expected: frontmatter has `name: loop-engineering` + a `description:`; exactly 6 `##` sections; `11` numbered bar items.

- [ ] **Step 3: Verify anchor integrity against loop.md**

Run:
```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
for a in "Verifier authority" "Verifier-gaming residual (v1)" "Provisional plan-suspect guard (T3)" "Safety Guards (Apply in All Modes)" "Status write-back" "## Coverage"; do
  printf '%-42s' "$a"; grep -cF "$a" plugins/qa/commands/loop.md
done
```
Expected: every anchor prints a count `≥ 1`. (If any prints `0`, the doctrine cites a drifted anchor — fix the SKILL.md to match `loop.md` before committing.)

- [ ] **Step 4: Commit**

```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
env AV_COMMIT_SKILL=1 git add plugins/qa/skills/loop-engineering/SKILL.md && \
env AV_COMMIT_SKILL=1 git commit -m "feat(qa): add loop-engineering doctrine skill"
```

---

## Task 2: Bump qa to 2.4.0 and create the docs Skills section

**Files:**
- Modify: `plugins/qa/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`
- Modify: `docs/plugins/qa.md`

- [ ] **Step 1: Bump `plugin.json`**

In `plugins/qa/.claude-plugin/plugin.json`, change the version line:
- From: `  "version": "2.3.0",`
- To:   `  "version": "2.4.0",`

- [ ] **Step 2: Bump `marketplace.json`**

In `.claude-plugin/marketplace.json`, the only `"version": "2.3.0"` belongs to the qa entry. Change it:
- From: `      "version": "2.3.0",`
- To:   `      "version": "2.4.0",`

- [ ] **Step 3: Bump the qa row in `README.md`**

Find the qa plugin's row in the Available Plugins table:
```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
grep -nE '^\|.*`?qa`? .*2\.3\.0' README.md
```
Edit that row, changing its version cell `2.3.0` → `2.4.0` (leave the description cell unchanged — adding a skill does not change qa's one-liner).

- [ ] **Step 4: Bump `**Version:**` and create the `## Skills` section in `docs/plugins/qa.md`**

First change the version header:
- From: `**Version:** 2.3.0`
- To:   `**Version:** 2.4.0`

Then add a new `## Skills` section. Insert it immediately **before** the `## Prerequisites` heading (read the file to confirm that heading's location). Use exactly this content:

```markdown
## Skills

The qa plugin ships these skills (loaded automatically with the plugin):

| Skill | Purpose |
|-------|---------|
| `loop-engineering` | Doctrine for authoring robust closed agent loops — the minimum-bar checklist, the ground-truth oracle taxonomy, and the anti-patterns, anchored to `/qa:loop` as the reference implementation. |
| `report-format` | Test report format with `QA-XXX` issue IDs, compatible with the code-review plugin. |
| `test-plan-format` | Test plan structure produced by `/qa:create-plan` and consumed by `/qa:run` and `/qa:loop`. |
| `fe-testing` | Frontend test-execution guidance for the `qa:fe-tester` agent (Playwright MCP). |
| `be-testing` | Backend test-execution guidance for the `qa:be-tester` agent (HTTP + DB checks). |

```

- [ ] **Step 5: Verify parity and the Skills section**

Run:
```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
python3 scripts/check_plugin_versions.py | tail -2
echo "== Skills section present =="; grep -n '^## Skills' docs/plugins/qa.md
echo "== loop-engineering listed =="; grep -c 'loop-engineering' docs/plugins/qa.md
```
Expected: `Version parity OK for 8 plugin(s).`; `## Skills` found; `loop-engineering` count `≥ 1`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
env AV_COMMIT_SKILL=1 git add plugins/qa/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md docs/plugins/qa.md && \
env AV_COMMIT_SKILL=1 git commit -m "release(qa): 2.4.0 — loop-engineering skill + docs Skills section"
```

---

## Task 3: Add the prose back-reference in loop.md

**Files:**
- Modify: `plugins/qa/commands/loop.md`

This is the **single discovery hook** that creates pull toward the doctrine. It MUST be a **prose mention**, never a `Skill(skill: "qa:loop-engineering")` auto-load (auto-loading would create a runtime consumer and couple the promote-later migration — see the spec's Integration invariant).

- [ ] **Step 1: Locate the overview paragraph**

Run:
```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
grep -n 'prevent uncontrolled loops' plugins/qa/commands/loop.md
```
This finds the end of the overview paragraph (near line 12).

- [ ] **Step 2: Insert the prose back-reference**

Immediately **after** the overview paragraph that ends with "...prevent uncontrolled loops." (the line found in Step 1), insert this blank-line-separated prose line:

```markdown
> **Doctrine:** the loop-engineering discipline this command implements — oracle taxonomy, the minimum-bar checklist, and the anti-patterns — is documented in the `qa:loop-engineering` skill.
```

- [ ] **Step 3: Verify the prose mention and the auto-load invariant**

Run:
```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
echo "== prose mention present =="; grep -c 'qa:loop-engineering' plugins/qa/commands/loop.md
echo "== auto-load invariant (MUST be empty) =="; grep -nE 'Skill\(\s*skill:\s*"qa:loop-engineering"' plugins/qa/commands/loop.md || echo "OK: no auto-load"
```
Expected: prose mention count `≥ 1`; the auto-load grep prints `OK: no auto-load` (empty match).

- [ ] **Step 4: Commit**

```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
env AV_COMMIT_SKILL=1 git add plugins/qa/commands/loop.md && \
env AV_COMMIT_SKILL=1 git commit -m "docs(qa:loop): prose back-reference to the loop-engineering skill"
```

---

## Task 4: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full gate**

```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
echo "== parity =="; python3 scripts/check_plugin_versions.py | tail -1
echo "== anchors still intact =="
for a in "Verifier authority" "Verifier-gaming residual (v1)" "Provisional plan-suspect guard (T3)" "Safety Guards (Apply in All Modes)" "Status write-back" "## Coverage"; do
  printf '%-42s' "$a"; grep -cF "$a" plugins/qa/commands/loop.md
done
echo "== auto-load invariant (MUST be empty) =="; grep -nE 'Skill\(\s*skill:\s*"qa:loop-engineering"' plugins/qa/commands/loop.md || echo "OK: no auto-load"
echo "== hook regression sanity =="; bash plugins/commit/tests/test-block-git-push.sh 2>&1 | tail -1
```
Expected: `Version parity OK for 8 plugin(s).`; every anchor count `≥ 1`; `OK: no auto-load`; `51 passed, 0 failed`.

- [ ] **Step 2: Confirm the skill is discoverable**

```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
ls plugins/qa/skills/loop-engineering/SKILL.md && echo "skill file present"
git log --oneline -4
```
Expected: skill file present; the last commits are Tasks 1–3.

---

## Pre-PR cleanup (after all tasks pass, before opening the 2.4.0 PR)

Remove the internal planning docs, per the established cycle:
```bash
cd /Users/mef1st0/Projects/AppVerk/av-marketplace
git rm docs/superpowers/specs/2026-06-19-qa-loop-engineering-skill-design.md \
       docs/superpowers/plans/2026-06-19-qa-loop-engineering-skill.md
env AV_COMMIT_SKILL=1 git commit -m "chore(qa): remove internal planning docs ahead of 2.4.0 PR"
```
Then finish via superpowers:finishing-a-development-branch (PR body gets the "🤖 Generated with Claude Code" footer; commits get no Co-Authored-By).

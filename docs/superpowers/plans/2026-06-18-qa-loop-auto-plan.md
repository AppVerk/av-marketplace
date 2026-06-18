# Self-Driving `/qa:loop` (auto-plan) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/qa:loop` self-driving — when no QA test plan exists, generate one inline (current branch vs default branch) and continue into the loop — with mode-aware autonomy, a dirty-tree safety gate, scoped recovery, and a graceful SKIP-reason-aware thin-plan exit. Bump qa to 2.2.0.

**Architecture:** Pure prompt-spec changes to `plugins/qa/commands/loop.md` (a markdown command), plus the qa-owned `docs/plugins/qa.md` and the four version sites. The command gains: three flags, a working-tree gate, an inline plan-generation step (mirroring `/qa:create-plan` Steps 2–7), two new sidecar fields (`auto_generated`, `fix_touched_files`), scoped recovery at four call-sites, and a rewritten Step 2.4. The source of truth for all content is the design spec.

**Tech Stack:** Claude Code plugin (markdown command/skill/doc specs), Bash (`git`/`gh`/`shasum`/`jq`/`date`), the existing `test-plan-format` + `report-format` skills, and `scripts/check_plugin_versions.py`.

**Source spec:** `docs/superpowers/specs/2026-06-17-qa-loop-auto-plan-design.md` (v3). Cite section numbers; this plan sequences the spec into verifiable, committable slices.

---

## Nature of this implementation (read first)

This is **prompt-engineering, not application code** — deliverables are markdown + a version bump. There is no unit-testable runtime, so there is **no pytest TDD**. Each task is verified by the **real checks in this repo**:

- **Structural checks** — `grep`/`Read` confirming the authored section contains the required tokens/sections (and, for removals, that the old token is gone).
- **JSON validity** — `jq` on the documented sidecar example.
- **Shell-recipe validity** — for the few embedded bash recipes (base-branch detection, dirty predicate, `fix_touched_files`), run them in this repo to confirm they behave (the base-branch recipe was already verified to yield `master`).
- **Version parity** — `python3 scripts/check_plugin_versions.py` must stay green.

**Execution context:** run on a **fresh branch off `master` after PR #5 merges** (decision D3) — do NOT execute on `feat/qa-loop`. Commits use `env AV_COMMIT_SKILL=1 git commit …` (the repo's block-git-commit hook). The loop never commits at runtime; this constraint is about the *plan's own* commits.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `plugins/qa/commands/loop.md` | the `/qa:loop` command-spec | bulk of the work: flags, gate, generation, sidecar fields, scoped recovery, Step 2.4 rewrite, allowed-tools, argument-hint |
| `docs/plugins/qa.md` | user-facing qa docs | document auto-plan, flags, gate, thin-exit, matrix, behavior-change callout; bump `**Version:**` |
| `plugins/qa/.claude-plugin/plugin.json` | plugin version | 2.1.0 → 2.2.0 |
| `.claude-plugin/marketplace.json` | marketplace registry | qa entry → 2.2.0 |
| `README.md` | plugins table | qa row → 2.2.0 (+ self-driving note in the one-liner) |

No new agents/skills. The inline generation reuses the existing `test-plan-format` skill.

---

## Task 1: Flags & argument parsing (spec §3.1, §4)

**Files:** Modify `plugins/qa/commands/loop.md` (Arguments table ~line 18-30; Step 0.1 ~line 54-74; frontmatter `argument-hint` line 5).

- [ ] **Step 1: Add the three flags to the Arguments table.** Three rows, matching §4:
  - `--auto-plan` | Force auto-plan ON (required in `--mode auto`) | on in approve/step, off in auto | Valueless presence flag; mutually exclusive with `--no-auto-plan`
  - `--no-auto-plan` | Force auto-plan OFF (restore 2.1.0 dead-stop) | — | Valueless; mutually exclusive with `--auto-plan`
  - `--allow-dirty` | Permit uncommitted tracked changes (bypass §3.3 gate); suppresses whole-tree recovery hints | off | Valueless
- [ ] **Step 2: Add Step 0.1 validation.** After `--mode` validation, before the headless TTY check: parse the three valueless flags; if both `--auto-plan` and `--no-auto-plan` present → `Error: --auto-plan and --no-auto-plan are mutually exclusive`; resolve the effective auto-plan setting: `approve`/`step` → ON, `auto` → OFF, overridden by whichever flag is set.
- [ ] **Step 3: Update `argument-hint`** (line 5) to append `[--auto-plan] [--no-auto-plan] [--allow-dirty]`.
- [ ] **Step 4: Verify.** `grep -n -- '--auto-plan\|--no-auto-plan\|--allow-dirty' plugins/qa/commands/loop.md` shows them in the table, Step 0.1, and argument-hint; `grep -n 'mutually exclusive' plugins/qa/commands/loop.md` shows the both-set error.
- [ ] **Step 5: Commit.** `env AV_COMMIT_SKILL=1 git commit -am "feat(qa:loop): add --auto-plan/--no-auto-plan/--allow-dirty flags"`

## Task 2: Working-tree safety gate + `pre_loop_dirty` (spec §3.3)

**Files:** Modify `plugins/qa/commands/loop.md` (new subsection between Step 0.1 and Step 0.2).

- [ ] **Step 1: Add the dirty-tree gate.** New `#### Step 0.1.5: Working-Tree Safety Gate`, after arg-validation, before plan resolution. Dirty predicate = tracked modifications:
  ```bash
  pre_loop_dirty=$(git status --porcelain --untracked-files=no | awk '{print $2}')
  ```
  If `pre_loop_dirty` is non-empty: `auto` → abort unless `--allow-dirty` (message per §3.3); `approve`/`step` → warn + confirm (proceed/abort). `--allow-dirty` bypasses the abort/confirm in all modes but **still records `pre_loop_dirty`** (so scoped recovery can subtract it).
- [ ] **Step 2: State the role of `pre_loop_dirty`** — it is the baseline subtracted in Task 6 to compute `fix_touched_files`; recorded regardless of `--allow-dirty`.
- [ ] **Step 3: Verify (structural).** `grep -n 'Step 0.1.5\|pre_loop_dirty\|status --porcelain' plugins/qa/commands/loop.md`.
- [ ] **Step 4: Verify (recipe runs).** In a repo with a tracked modification, confirm `git status --porcelain --untracked-files=no | awk '{print $2}'` lists only tracked-modified paths and excludes untracked files.
- [ ] **Step 5: Commit.** `… "feat(qa:loop): add working-tree safety gate and pre_loop_dirty baseline"`

## Task 3: Auto-plan trigger + inline generation (spec §3.1, §3.4)

**Files:** Modify `plugins/qa/commands/loop.md` (Step 0.2 ~line 76-90; frontmatter `allowed-tools` line 2).

- [ ] **Step 1: Add `Bash(gh:*)` to `allowed-tools`** (line 2). (Verified the only tool gap vs create-plan.)
- [ ] **Step 2: Replace the Step 0.2 dead-stop with the mode-dependent trigger.** When `plan_path` is empty after the `ls -t` resolution: `approve`/`step` (auto-plan ON) → one confirm → generate; `auto` → keep the 2.1.0 dead-stop **unless** `--auto-plan` → non-silent banner → generate. `--no-auto-plan` forces the dead-stop. Headless approve/step → abort (existing guard).
- [ ] **Step 3: Add the inline generation sub-step** (mirrors create-plan Steps 2–7, **branch-vs-default path only**; skip create-plan Step 1 & Step 8). Include verbatim the corrected base-branch recipe from §3.4:
  ```bash
  BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); BASE=${BASE#origin/}
  [ -z "$BASE" ] && git rev-parse --verify main   >/dev/null 2>&1 && BASE=main
  [ -z "$BASE" ] && git rev-parse --verify master >/dev/null 2>&1 && BASE=master
  [ -z "$BASE" ] && BASE=main
  ```
  And construct-path-before-Write: `DATE=$(date +%Y-%m-%d)`; choose `<topic>` slug; `plan_path="docs/testing/plans/${DATE}-${topic}-test-plan.md"` **before** the Write; pass that literal everywhere; do not re-glob `ls -t`. Load the `test-plan-format` skill. Set `auto_generated: true` in the sidecar at creation.
- [ ] **Step 4: Add the success/validity contract** — after the Write, verify the file exists at `plan_path` and has the always-present headers `## Source`, `## Changes Summary`, `## Detected Tools` (FE/BE sections optional — absence is *thin*, not malformed, see Task 5). On missing file/headers → abort. Re-entry: generation replaces the dead-stop, sets `plan_path` (non-empty), so the `ls -t` fallback is not re-run; control proceeds to the §3.5 static check then Step 0.3/0.4.
- [ ] **Step 5: Verify (structural).** `grep -n 'symbolic-ref --short\|BASE#origin/\|auto_generated\|Bash(gh' plugins/qa/commands/loop.md`; confirm `grep -c 'ls -t' ` did not increase for plan re-resolution after generation.
- [ ] **Step 6: Verify (recipe runs).** Run the base-branch recipe in this repo → `master` (already confirmed); run the path-construction snippet → a well-formed `docs/testing/plans/<date>-<slug>-test-plan.md`.
- [ ] **Step 7: Commit.** `… "feat(qa:loop): inline auto-plan generation with corrected base detection and validity contract"`

## Task 4: Pre-baseline surfacing banner (spec §3.1, §3.6)

**Files:** Modify `plugins/qa/commands/loop.md` (right after Task 3's generation, before Step 0.3).

- [ ] **Step 1: Add the banner.** After generation (all modes): echo `Generated plan: <plan_path> — <N> FE scenarios, <M> BE scenarios`, counting `### FE-NN` / `### BE-NN` headings in the generated plan. State that in `--mode auto` this banner is the audit trail, and that the **mutation-guarded SKIP count is reported post-baseline** (Task 8), not here.
- [ ] **Step 2: Verify.** `grep -n 'Generated plan:\|FE scenarios\|audit trail' plugins/qa/commands/loop.md`.
- [ ] **Step 3: Commit.** `… "feat(qa:loop): surface generated-plan summary before baseline"`

## Task 5: Static thin-plan exit (spec §3.5.1)

**Files:** Modify `plugins/qa/commands/loop.md` (between Task 3 generation and Step 0.3).

- [ ] **Step 1: Add the static check.** Immediately after generation/validation, **before** base-URL resolution (Step 0.3): if the (valid) plan has **zero `### FE-NN` and zero `### BE-NN` blocks** → graceful **success** exit with the §3.5.1 message (suggest the unit/integration suite); do not launch testers. Emphasize: valid-but-thin ≠ malformed (malformed was aborted in Task 3); this runs before Step 0.3 so a URL-less empty plan does not trip the fail-closed base-URL abort.
- [ ] **Step 2: Verify.** `grep -n 'zero .### FE\|nothing executable\|before base-URL\|graceful' plugins/qa/commands/loop.md`.
- [ ] **Step 3: Commit.** `… "feat(qa:loop): graceful static thin-plan exit before base-URL resolution"`

## Task 6: `fix_touched_files` accumulator (spec §3.3)

**Files:** Modify `plugins/qa/commands/loop.md` (Step 3, after the fix phase / around Step 3g sidecar update).

- [ ] **Step 1: Compute and persist `fix_touched_files`.** After the fix phase: `post=$(git status --porcelain --untracked-files=no | awk '{print $2}')`; `fix_touched_files = post − pre_loop_dirty` (set difference — files the loop's fixes introduced, excluding pre-existing dirt). Persist the array in the sidecar. Note: files in *both* sets are excluded from scoped recovery (user reconciles; surface a one-line note).
- [ ] **Step 2: Verify (structural).** `grep -n 'fix_touched_files\|pre_loop_dirty' plugins/qa/commands/loop.md` shows both the producer (Step 0.1.5) and consumer (Step 3).
- [ ] **Step 3: Verify (recipe).** In a repo with one pre-existing tracked mod + one new mod, confirm the set-difference yields only the new path.
- [ ] **Step 4: Commit.** `… "feat(qa:loop): accumulate fix_touched_files (post − pre_loop_dirty)"`

## Task 7: Scoped recovery at the four call-sites (spec §3.3, §5)

**Files:** Modify `plugins/qa/commands/loop.md` (lines ~394 mid-run abort, ~755 Step 5.2 summary, ~824 error-table row, ~835 Esc-abort wording).

- [ ] **Step 1: Rewrite the recovery hints.** Replace whole-tree `git restore .` with `git restore <fix_touched_files>` at loop.md:394 and loop.md:755; sync the error-table "recover" row (~824); audit/adjust the Esc-abort "uncommitted changes left" wording (~835) to reference the scoped set. Under `--allow-dirty`, suppress the whole-tree hint entirely (print the scoped list + the overlap note).
- [ ] **Step 2: Verify (structural).** `grep -n 'git restore' plugins/qa/commands/loop.md` — every hint references `<fix_touched_files>` (or is suppressed under `--allow-dirty`); no bare `git restore .` survives as a recovery instruction.
- [ ] **Step 3: Commit.** `… "fix(qa:loop): scope recovery to fix_touched_files, never whole-tree git restore"`

## Task 8: Reason-aware all-SKIP (Step 2.4 rewrite) + post-baseline count (spec §3.5.2, §3.6)

**Files:** Modify `plugins/qa/commands/loop.md` (Step 2.4 ~line 339-353; error-table ~line 824; baseline result reporting in Step 2).

- [ ] **Step 1: Rewrite the Step 2.4 all-SKIP branch** per the §3.5.2 conditional: `if all SKIP: if auto_generated: (all reasons==mutation-guard → graceful success) else (graceful exit + coverage-zero WARNING); else → existing error (loop.md:349)`. Keep the existing zero-failure branch unchanged.
- [ ] **Step 2: Sync the error-table row** (~824) so "Entire baseline is SKIP" distinguishes auto-generated (graceful) from user-provided (error).
- [ ] **Step 3: Add the post-baseline mutation-guarded count** to the baseline result reporting (the count the §3.1 banner deferred).
- [ ] **Step 4: Verify.** `grep -n 'mutation-guard\|coverage-zero\|auto_generated' plugins/qa/commands/loop.md` shows the three-way branch in Step 2.4 and the synced error-table row.
- [ ] **Step 5: Commit.** `… "feat(qa:loop): reason-aware all-SKIP exit for auto-generated plans"`

## Task 9: Sidecar schema — two new fields (spec §3.4, §3.3, §5)

**Files:** Modify `plugins/qa/commands/loop.md` (sidecar schema example ~line 188-212 and the field-list prose).

- [ ] **Step 1: Add the fields.** In the schema example add `"auto_generated": false` and `"fix_touched_files": []`; add their descriptions to the field list (`auto_generated` — true iff the loop generated the plan; `fix_touched_files` — paths the loop's fixes edited, used for scoped recovery).
- [ ] **Step 2: Verify (JSON valid).** Extract the schema example and `jq .` it — valid JSON with both new keys.
- [ ] **Step 3: Commit.** `… "feat(qa:loop): add auto_generated and fix_touched_files to sidecar schema"`

## Task 10: Version bump + docs + parity (spec §5)

**Files:** Modify `plugins/qa/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `README.md`, `docs/plugins/qa.md`.

- [ ] **Step 1: Bump version to 2.2.0** in plugin.json, marketplace.json (qa entry), README qa row, and `docs/plugins/qa.md` `**Version:**`.
- [ ] **Step 2: Document the feature in `docs/plugins/qa.md`** — the mode-dependent auto-plan default, the three flags, the dirty-tree gate + scoped recovery, the graceful/reason-aware thin-exit, the surfacing, the §3.6 matrix, and an explicit **behavior-change callout** for `--mode auto` users.
- [ ] **Step 3: Update the README qa one-liner** to mention the self-driving loop.
- [ ] **Step 4: Verify (parity).** `python3 scripts/check_plugin_versions.py` → `[qa] 2.2.0 (OK)`, all plugins OK.
- [ ] **Step 5: Commit.** `… "release(qa): 2.2.0 — self-driving /qa:loop auto-plan"`

---

## Self-Review

**Spec coverage:** §3.1 (T1 flags + T3 trigger + T4 surfacing), §3.2 (T3 branch-vs-default), §3.3 (T2 gate + T6 accumulator + T7 recovery), §3.4 (T3 generation + T9 auto_generated), §3.5.1 (T5 static), §3.5.2 (T8 reason-aware), §3.6 (T4/T8 matrix behaviors), §4 (T1), §5 (T9 schema + T10 version/docs). All sections map to a task.

**Placeholder scan:** the embedded recipes (base-branch, dirty predicate, fix_touched_files) are concrete and runnable; no "TBD"/"add appropriate…". Where a task references the spec for full prose (e.g. exact messages), the required **verification tokens** are named so the change is checkable.

**Type/name consistency:** `pre_loop_dirty` (T2) is the producer for `fix_touched_files` (T6); `auto_generated` is set in T3, read in T8, declared in T9; the base-branch recipe and construct-path snippet are identical to spec §3.4. Flag names match §4 across T1/T3/T7.

**Ordering:** T2 (pre_loop_dirty) precedes T6 (consumer); T3 (generation, sets auto_generated) precedes T5/T8 (readers); T9 (schema) can land anytime but is placed before T10 (parity). Independent enough for task-by-task review.

---

## Execution Handoff (DEFERRED per D3)

This plan is **not** to be executed until PR #5 (`feat/qa-loop`, qa 2.1.0) merges to `master`. When it does:

1. `git checkout master && git pull`, then branch `feat/qa-loop-auto-plan` off `master`.
2. Commit this spec + plan onto the new branch.
3. Execute via **superpowers:subagent-driven-development** (fresh subagent per task + two-stage review), then a final **MoA review** (per the user's standing preference), then **superpowers:finishing-a-development-branch**.

# Design Spec: Self-Driving `/qa:loop` — no-plan → generate → run

**Date:** 2026-06-17
**Status:** **v3** (after two review rounds: a 4-lens MoA+sequential-thinking pass produced v2; a 3-lens MoA confirming pass — which caught phantom mechanisms v2's fixes introduced — produced v3). Every finding verified against `loop.md`/`create-plan.md` by reading and by running commands. Ready for re-approval before the implementation plan.
**Target plugin:** `qa` (2.1.0 → **2.2.0**, MINOR).
**Depends on:** the `/qa:loop` command introduced in qa 2.1.0 (PR #5, branch `feat/qa-loop`).
**Timing (D3):** implement after PR #5 merges to `master`, then on a fresh branch off `master` (no stacking). This spec is an internal working artifact, NOT committed to PR #5.

---

## 0. Revision history

- **v1** — initial sketch: auto-plan default-on & mode-aware (auto: silent), `--plan-source`, dirty-tree gate, thin-plan exit "reusing Step 2.4 all-SKIP."
- **v2** — after review round 1: mode-dependent default (decision A); graceful thin-exit; chaining (skip create-plan Steps 1 & 8, capture path, success contract); `--plan-source` dropped; scoped recovery; product re-framing.
- **v3** — after review round 2 (confirming MoA), which found v2's fixes rested on **state the loop does not track** ("phantom mechanisms") plus a **factually wrong** shell recipe. Fixes:
  - **Two new pieces of sidecar state made explicit** (v2 wrongly assumed they existed): `fix_touched_files` (the run-scoped set of paths the loop's fixes edited — there is NO such accumulator in 2.1.0; only an ephemeral per-fix placeholder at loop.md:513) and `auto_generated` (plan provenance — never recorded today).
  - **Base-branch detection corrected.** v2's `git symbolic-ref --short refs/remotes/origin/HEAD` returns **`origin/master`**, not `master` (verified by running), and `git rev-parse --verify main/master` is one slash-ref that **fails**. v3 gives the correct sed-free recipe.
  - **Surfacing split.** The mutation-guarded SKIP count is computed *during* baseline (Step 2.1), so it cannot be echoed "before baseline" as v2 claimed; v3 surfaces plan path + FE/BE counts pre-baseline and the mutation-guarded count post-baseline.
  - **Whole-tree `git restore .` edit sites enumerated** (loop.md:394, 755, plus the error table at 824 and the Esc-abort wording at 835) — v2 stated the "never whole-tree" rule but never named the call-sites, so they would survive.
  - **Construct-the-path-before-Write** (create-plan never binds the path to a variable — "capture what Write wrote" has nothing to capture).
  - **Valid ≠ thin** distinction pinned (FE/BE sections are *optional* per the format's omission rules, so a valid BE-only plan must not be mis-rejected as malformed).
  - **all-SKIP softening is SKIP-reason-aware** (mutation-guard → graceful; tool/parse SKIPs → graceful **with a coverage-zero warning**, so a broken generation isn't laundered into "success").
  - Minor: Step 2.4 conditional spelled out + error-table parity; static-check vs Step 0.2 re-entry; valueless presence flags.
  - **Confirmed genuinely closed by v2** (not re-touched): H2 `--plan-source` foreign-diff (dropped), H3 stale-plan (`ls -t` race), H4 thin-exit-as-error, env/mutation/budget/never-commit guards, mode-dependent default. allowed-tools delta verified = exactly `{ Bash(gh:*) }`.

---

## 1. Context & Motivation

`/qa:loop` (qa 2.1.0) requires a pre-existing QA test plan; with none it dead-stops at Step 0.2 (*"Run `/qa:create-plan` first"*).

Two downstream runs surfaced the gap and bounded it honestly:
- **INCV-93 (backend-only).** Correctly dead-stopped. But a backend-only branch yields BE write-scenarios the **mutation guard SKIPs by default** (loop.md:238/261) → all-SKIP → "nothing executable." Auto-QA does not help it; its unit/integration suite does.
- **SoftwareStorm SSS-13.** A **dev task**, not a QA target → **option B** (a dev "task loop"), out of scope.

**Genuine target (v2/v3):** an **FE / full-stack branch with testable surface and no plan yet** — there auto-plan converts a dead-stop into "prepare plan → run." Backend-only and dev-task branches deliberately **fast-exit** (§3.5).

`/qa:create-plan` is non-interactive and self-contained, writing `docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md`. It is the chain target.

---

## 2. Goal & Scope

When no plan exists, `/qa:loop` prepares a plan for the current branch and continues into the loop, with safety appropriate to each mode.

### In scope
- Mode-dependent auto-plan trigger (§3.1), replacing the Step 0.2 dead-stop.
- **Surfacing** the generated-plan summary (§3.1), split pre/post-baseline.
- A working-tree safety gate with **scoped recovery backed by a new `fix_touched_files` sidecar field** (§3.3).
- A specified generation step: branch-vs-default source only, construct-path-before-Write, skip create-plan Steps 1 & 8, success/validity contract, corrected base detection, set `auto_generated` (§3.4).
- A graceful, **SKIP-reason-aware** thin/empty-plan exit (§3.5).
- Two new sidecar fields: `fix_touched_files` (array), `auto_generated` (bool).
- New flags `--auto-plan`, `--no-auto-plan`, `--allow-dirty`. Rewrites of the four whole-tree-`git restore .` sites (loop.md:394, 755, 824, 835) to scoped recovery. Docs + version bump (2.2.0).

### Non-goals
- A Plane "task loop" (option B). · Context-hijack hardening. · `--plan-source` (deferred — YAGNI + foreign-diff attack surface). · Changes to `/qa:create-plan`, `test-plan-format`, or the tester/fixer agents. · Auto-committing (the loop **never commits**).

---

## 3. Design

### 3.1 Trigger — mode-dependent default + surfacing (decision A)

When `plan_path` resolves to nothing:

| Mode | Default | Flow |
|---|---|---|
| `approve` *(default)* / `step` | auto-plan **ON** | one confirm ("No QA plan found for this branch. Generate one and run the loop? [Generate & run / Cancel]") → generate → continue. Fixes still gated by Step 3b. Headless (no TTY) → abort (existing guard, loop.md:71). |
| `auto` | auto-plan **OFF** | 2.1.0 dead-stop **unless `--auto-plan`**. With it: non-silent banner → generate → continue. |

- **Why mode-dependent:** approve/step still gate every fix (Step 3b), so auto-plan there is low-risk; `auto` has no gate, so silently turning a CI `qa:loop --mode auto` (which expected a no-op-stop) into source-mutating execution is a behavior change → opt-in.
- **Overrides:** `--auto-plan` forces ON, `--no-auto-plan` forces OFF. Both set → error. They are **valueless presence flags** (like `--allow-mutations`, loop.md:27); resolve the effective setting in Step 0.1 **after** `--mode` validation and the both-set→error check.
- **Surfacing (split — the count-timing fix):**
  - **Pre-baseline banner (all modes, after generation):** `plan path` + `FE scenario count` + `BE scenario count` (counted from the generated plan's `### FE-NN`/`### BE-NN` headings — knowable without running). In `--mode auto` this banner is the audit trail.
  - **Post-baseline:** the **mutation-guarded SKIP count** is folded into the existing baseline result reporting (it is produced by the Step 2.1 guard pass — loop.md:238/261 — and is *not* knowable pre-baseline). Do not claim it in the pre-baseline banner.

### 3.2 Plan source

Default and **only** source in 2.2.0: **current branch vs the default branch**. `--plan-source` is deferred (foreign-diff-against-local-checkout wrong-target risk; both motivating runs want "this branch").

### 3.3 Working-tree safety gate (D2) + scoped recovery backed by real state

The loop auto-fixes source; its recovery guidance is `git restore`, so **uncommitted tracked changes are at risk**. The gate runs **after argument validation, before plan resolution/generation** (judges the pre-existing tree). It is independently warranted (the risk predates A); A makes it urgent.

- **Dirty predicate:** `git status --porcelain` over **tracked** modifications. Untracked excluded (`git restore` can't destroy them).
- **On a dirty tree:** `auto` → abort unless `--allow-dirty`; `approve`/`step` → warn + confirm (the dirty confirm comes **before** the §3.1 generate confirm — two prompts). `--allow-dirty` bypasses in all modes.
- **`fix_touched_files` — NEW state (the phantom-mechanism fix).** 2.1.0 does **not** track which files fixes edited (the only reference, loop.md:513, is an ephemeral per-fix anti-hardcoding placeholder; the sidecar has no such field). v3 introduces it explicitly:
  - At loop start (before Step 3), record `pre_loop_dirty` = the tracked-modified set (`git status --porcelain` tracked paths).
  - After the fix phase, compute `fix_touched_files` = `(current tracked-modified set) − pre_loop_dirty` — i.e. files the **loop's fixes** introduced changes to, excluding what the user had already modified. Persist it in the sidecar.
- **Scoped recovery (the data-loss fix):** every recovery hint references **`git restore <fix_touched_files>`**, never whole-tree `git restore .`. This guarantees recovery never discards the user's pre-existing edits. Files that were *both* pre-existing-dirty and further edited by a fix are **left untouched** by scoped recovery (the user reconciles) — surface them as a one-line note rather than restoring. Under `--allow-dirty` the whole-tree hint is suppressed entirely.
- **Edit sites (enumerated — v2 omitted these):** convert to scoped recovery at **loop.md:755** (Step 5.2 summary), **loop.md:394** (mid-run hash-mismatch abort — made *more* reachable by the new generation step), **loop.md:824** (error-table "recover" row, keep in sync), and audit **loop.md:835** (Esc-abort "uncommitted changes left" wording).

### 3.4 Generation step

qa:loop generates the plan **inline**, following `/qa:create-plan`'s **Steps 2–7**, with these explicit constraints (commands aren't callable as functions):

- **Source = fixed branch-vs-default only.** Inline only create-plan Step 2's branch-vs-default path (create-plan.md:60-64, with the corrected base detection below); do **not** inline the PR/`last-N`/staged dispatch (loop has no diff-source argument — its positional is `plan_path`). The source is fixed per §3.2.
- **Corrected base-branch detection (factual fix):**
  ```bash
  BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); BASE=${BASE#origin/}   # origin/master → master
  [ -z "$BASE" ] && git rev-parse --verify main   >/dev/null 2>&1 && BASE=main
  [ -z "$BASE" ] && git rev-parse --verify master >/dev/null 2>&1 && BASE=master
  [ -z "$BASE" ] && BASE=main   # last-resort literal
  ```
  (`--short` alone yields `origin/master`; the `${BASE#origin/}` strip is required. `git rev-parse --verify main/master` as one token **fails** — verify each ref separately. `Bash(git:*)` already present; no `sed`.)
- **Construct the path before Write.** create-plan never binds its output path to a variable — it assembles `docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md` inline in the `Write` call (create-plan.md:193-194), so there is nothing to "capture afterward." Instead: `DATE=$(date +%Y-%m-%d)`; choose the `<topic>` slug; set `plan_path="docs/testing/plans/${DATE}-${topic}-test-plan.md"` **before** writing; pass that literal to `Write`, the validity check, and all downstream steps. Do **not** re-glob `ls -t … | head -1` (the stale-plan race). Intra-run stability is all that's needed (the slug need not be reproducible across runs).
- **Skip create-plan Step 1** (its own task scaffold — reuse loop's tracker) and **Step 8** (the "run `/qa:run`" prompt — contradicts continuing).
- **Set `auto_generated: true`** in the sidecar at creation (NEW provenance state; read by §3.5/Step 2.4). A user-provided/pre-existing plan has `auto_generated: false`/absent.
- **Success/validity contract:** after the Write, verify the file exists at the constructed `plan_path` **and** is **structurally valid** — has the always-present headers `## Source`, `## Changes Summary`, `## Detected Tools` (test-plan-format SKILL.md:24-35). FE/BE scenario sections are **optional** (omission rules, SKILL.md:112-113) — their absence is **not** invalidity (that is the §3.5 *thin* case, not a malformed plan). On a missing file or missing structural headers → **abort** ("plan generation failed / produced a malformed plan"); never fall through to a stale plan.
- **`allowed-tools`:** add `Bash(gh:*)` (verified the only gap; everything else create-plan uses is already in loop.md:2). Load the `test-plan-format` skill before rendering.
- **Re-entry:** generation occurs **in place of** the Step 0.2 empty-path dead-stop; it sets `plan_path` (now non-empty), so the Step 0.2 `ls -t` fallback is **not** re-run. Control proceeds to the §3.5 static thin-check, then Step 0.3/0.4, then baseline.

**Coupling note (residual, accepted):** the inline copy duplicates create-plan Steps 2–7 *in spirit* and is the *corrected* copy (base detection), so it diverges from create-plan at birth — no enforcement. Shared-skill extraction (the `test-plan-format` skill exists as a sibling) or a create-plan subagent are deferred alternatives; if the subagent route is ever taken, create-plan.md:62's own `|| echo "main"` must be fixed too.

### 3.5 Thin / empty plan — graceful **success**, SKIP-reason-aware

"Nothing executable" has two shapes; both exit **success (not error)**, suggesting the unit/integration suite. The distinction from a *malformed* plan (→ §3.4 abort) is: a thin plan is **valid** (structural headers present) but has no runnable scenarios.

1. **Static (pre-baseline):** a valid plan with **zero `### FE-NN` and zero `### BE-NN` blocks**. Detected by parsing the plan immediately after generation, **before** base-URL resolution (an empty plan has no URL and would otherwise trip Step 0.3's fail-closed abort, loop.md:100-104). Graceful exit; no testers launched.
2. **Dynamic (post-baseline) — reason-aware:** the plan has scenarios but **all resolve to SKIP**. Read `auto_generated` and the SKIP **reasons**:
   - `auto_generated` **and all SKIPs are `mutation-guard`** (the legitimate INCV backend-write case) → **graceful success** (*"auto-generated plan is backend-write-only under the mutation guard — nothing executable here; rely on the unit/integration suite."*).
   - `auto_generated` **and any SKIP is `tool-unavailable` / `cannot-confirm` / parse-failure** → **graceful exit WITH a coverage-zero WARNING** (*"all scenarios skipped for tooling/parse reasons, not mutation-guard — coverage is zero; verify the generated plan and tool availability."*) — so a broken generation isn't laundered into "success."
   - **NOT `auto_generated`** (user-provided plan) → keep the **existing error** (loop.md:349, `Error: No executable verifier`). An operator-supplied plan that cannot gate is worth flagging.

**Step 2.4 rewrite (spell out the conditional):**
```
if all scenarios SKIP:
    if auto_generated:
        if all SKIP reasons == mutation-guard:  graceful-success(msg)
        else:                                    graceful-exit + coverage-zero WARNING
    else:                                        existing error (loop.md:349)
```
Keep the error-table row (loop.md:824) in sync with this branch.

**Ordering after generation:** static thin-check (1) → if scenarios exist: Step 0.3 base-URL + Step 0.4 env guard **on the generated plan** (a generated non-loopback URL still aborts) → baseline → dynamic all-SKIP (2).

### 3.6 Modes / headless / surfacing matrix

| Situation | `auto` | `approve` / `step` |
|---|---|---|
| No plan | dead-stop, unless `--auto-plan` → banner → generate → run | confirm → generate → run (headless: abort) |
| Dirty tree | abort unless `--allow-dirty` | warn+confirm (before the generate confirm) |
| After generation | pre-baseline banner (path + FE/BE counts) → continue | pre-baseline banner → continue |
| Empty plan (0 FE+BE blocks) | graceful success exit | graceful success exit |
| All-SKIP, auto-generated, mutation-guard only | graceful success exit | graceful success exit |
| All-SKIP, auto-generated, tool/parse reasons | graceful exit + coverage-zero warning | graceful exit + warning |
| All-SKIP, user-provided plan | existing error | existing error |

---

## 4. Flags (additions to qa:loop)

| Flag | Default | Meaning |
|---|---|---|
| `--auto-plan` | on in approve/step, **off in auto** | Force auto-plan ON (required in `--mode auto`). Valueless presence flag |
| `--no-auto-plan` | — | Force auto-plan OFF (restore the 2.1.0 dead-stop). Valueless; mutually exclusive with `--auto-plan` |
| `--allow-dirty` | off | Permit running with uncommitted **tracked** changes (bypass §3.3); suppresses whole-tree recovery hints. Valueless |

(`--plan-source` deferred.) Update loop.md's `argument-hint` to include the three flags.

---

## 5. Versioning, edit targets & docs

- qa **2.1.0 → 2.2.0** (MINOR). Non-breaking for **automation**: `--mode auto` keeps the no-op-stop unless `--auto-plan` is added. The interactive default changes from "stop" to "**confirm**, then generate" — a prompted action, not a silent change; `--no-auto-plan` restores the old path.
- **Sidecar schema** gains `auto_generated` (bool) and `fix_touched_files` (array) — update the schema example + field list in loop.md.
- **Recovery edit targets:** loop.md:755, 394, 824, 835 → scoped recovery (§3.3).
- **Parity:** `plugin.json`, `marketplace.json`, README row, `docs/plugins/qa.md` `**Version:**`, loop.md `argument-hint` (enforced by `scripts/check_plugin_versions.py` for the four version sites).
- **Docs (`docs/plugins/qa.md`):** mode-dependent default, the flags, the gate + scoped recovery, graceful/ reason-aware thin-exit, plan surfacing, the matrix, and an explicit **behavior-change callout** for `--mode auto` users.

---

## 6. Edge cases & residual risks

- **No diff vs default branch** → empty plan → static thin-exit. OK.
- **`gh` unavailable / no PR / no `origin/HEAD`** → the corrected base detection (§3.4) falls back through `rev-parse --verify main/master` then a literal; `gh pr` is read-only network I/O outside the loopback guard (noted). The v2 literal-`main`-on-`master` false-thin-exit is fixed.
- **Generation failure / partial / malformed** → §3.4 success/validity contract aborts; no stale fall-through.
- **`fix_touched_files` overlap** — files both pre-existing-dirty and fix-edited are excluded from scoped recovery (user reconciles, with a surfaced note). Honest limitation of file-granular `git restore`.
- **`--auto-plan` + `auto`** — the maximal-autonomy corner (relocated behind an explicit, non-silent opt-in). Bounded by scoped recovery, surfaced banner, env/mutation guards, budgets, never-commits. Accepted.
- **DRY coupling** (§3.4) — accepted; shared-skill refactor deferred.
- **Generated-plan quality** — weak plan → weak loop; bounded by budgets + final-run authority + the surfaced banner + the §3.5 coverage-zero warning.
- **Plan-file litter** — every generation writes a plan, incl. thin-exit; never committed; accumulates in the working tree. Cleanup of a thin-exit plan is a future tweak.
- **Context-hijack (SSS-13)** — out of scope; a productive no-plan path only *reduces* improvisation room.

---

## 7. Implementation timing (D3)

Spec now; implementation **after PR #5 merges to `master`**, on a fresh branch off `master` (no stacking). Spec doc is an internal working artifact (consistent with `f31b238`) — not committed to PR #5.

---

## Appendix A — review trail

- **Round 1 (4-lens MoA + sequential thinking):** v1 → v2. Found: thin-exit-as-error, undefined "zero executable," changed-default SemVer, unsanitized `--plan-source`, allow-dirty data-loss, stale-plan fall-through, under-specified chaining, INCV/SSS-13 mis-framing.
- **Round 2 (3-lens MoA confirming pass):** v2 → v3. Found **phantom mechanisms** v2 introduced (`fix_touched_files` and `auto_generated` assumed-but-untracked) and a **factually wrong** base-branch recipe. Two inter-lens conflicts were resolved **by running commands**: `git symbolic-ref --short …` returns `origin/master` (not `master`); loop.md persists **no** fix-touched-files list (only the ephemeral l.513 placeholder).
- **Confirmed genuinely closed / sound** (not re-touched in v3): H2–H4, env/mutation/budget/never-commit guards, mode-dependent default, allowed-tools delta = exactly `{ Bash(gh:*) }`.
- **Motivating runs:** INCV-93 (backend-only — fast-exits by design); SoftwareStorm SSS-13 (dev task → option B). Target: FE/full-stack-no-plan branches.

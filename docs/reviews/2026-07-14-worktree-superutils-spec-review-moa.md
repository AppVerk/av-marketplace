# MoA Review — superutils branch (`worktree-superutils-spec-review`)

**Date:** 2026-07-14 · **Range:** `552cf74..f023a73` (12 files, +692/−1) ·
**Artifact class:** Claude Code plugin (prompt markdown + JSON manifests; no application code)

**Verdict: introduced correctly at the packaging/contract level, but NOT error-free — mergeable with fixes, not as-is.**
The plugin is faithful to its design contract on structure, flags, budgets, enums and packaging, and every repo obligation
(`CLAUDE.local.md`) is met. What it is not is defect-free: **4 major** defects survive adversarial verification, three of
which let the loop terminate in its *success* state (`CONVERGED`) while the defect it was supposed to fix is still in the
spec. All four are prompt-text edits, not architecture.

## Method

Mixture-of-Agents, deliberately blind to the earlier `/code-review` report of this branch:

| Stage | Agents | Result |
|---|---|---|
| Propose | 6 independent single-lens reviewers (spec-compliance, internal-consistency, doctrine-compliance, executability, repo-conventions, safety), each with a mandatory self-falsification pass | 34 findings kept, 38 self-rejected |
| Cluster | 1 aggregator (dedupe, anchor verification against the files) | 29 unique issues |
| Refute | 3 adversarial verifiers per issue (skeptic / literalist / consequentialist), majority vote, independent re-grade | **18 survived, 11 refuted** |
| Synthesize | 1 | report |
| Critique | 1 completeness critic ("what did the panel miss?") | **3 further defects**, verified by hand |

96 subagents, 4.3M tokens. Deterministic packaging checks (jq, version/badge/registration cross-check) were run
independently by the orchestrator, not delegated. The critic's findings and the panel's three majors were re-verified
against the files by the orchestrator before being reported here.

---

## MAJOR

### M1 — An accepted fix that fails to apply is never retried, and the run still reports CONVERGED

**Location:** `plugins/superutils/commands/spec-review.md:140`, `:166`, `:223`
**Source:** completeness critic (missed by all 6 lenses and 3 refuters); verified by the orchestrator

Three clauses in one file close a loop the same file promises is open:

- `:223` (Error handling) promises recovery: *"| Fixer fails / pair mismatch | `fix-failed`; fresh panel re-finds next round |"*
- `:140` (Step 4) — *"Entries with a recorded user decision are skipped (settled)."* → the re-found entry gets no challenger,
  and `Significant = major+ ∧ survived refutation` (`:148`), so it never re-enters the significant set.
- `:166` (Step 6) — *"Zero significant findings after excluding entries user-decided in earlier rounds → CONVERGED:
  terminate before the fix phase"* → it is excluded a second time, and the round converges **before** Step 8, whose batch
  (*"confirmed major+ + accepted decisions"*, `:177`) is the only thing that would have retried it.

The failure is deterministic, not stochastic: `agents/spec-fixer.md:19` forbids repair — *"for user-decided findings the
decided edit content is included verbatim — reproduce it exactly, never re-derive it"* — so the same non-matching `old`
string is replayed every round. Note the asymmetry the plugin never resolves: `unconfirmed` explicitly *"blocks
convergence"* (`:222`); `fix-failed` does not.

**Impact:** interactive run → user accepts a needs-decision fix → the fixer's `old` string does not match (moved text,
ambiguous anchor) → `fix-failed` → next round the fresh panel re-finds the defect → it is excluded from significance
twice → **`CONVERGED`** with the accepted fix silently never applied. This is the exact path `tests/ACCEPTANCE.md:15`
drives down ("every needs-decision prompt → accept the proposed fix"). Secondary: that round-2 re-finding matches **no**
member of the outcome enum declared exhaustive at `skills/report-format/SKILL.md:88`.

**Fix:** an entry with a recorded decision and outcome `fix-failed`, when re-found by a fresh panel, must stay in the
significant set (like `unconfirmed`, it blocks convergence) and its stored `decisions.edit` must be re-derived rather than
replayed verbatim.

### M2 — The challenger is told to "lean refute when uncertain", contradicting the sentence above it

**Location:** `plugins/superutils/agents/spec-challenger.md:13-14`
**Found by:** spec-compliance · unanimous across all 3 refuters

Two adjacent sentences dispose of the same state in opposite directions: *"If you cannot refute it, uphold it. When
genuinely uncertain, lean refute — false positives are costlier than false negatives."* The same paragraph requires
refutation to rest on *"concrete textual evidence from the spec"*, so an uncertain challenger by construction **cannot**
refute — line 13 says uphold, line 14 says refute. The design contract authorizes no uncertainty tie-break (it states only
`Significant = major+ AND survived refutation`), and the marketplace's own challenger pattern
(`plugins/code-review/agents/challenger.md:92`) biases the *other* way.

**Impact:** uncertainty is the *modal* state when adjudicating a completeness/ambiguity finding against a prose spec, where
the evidence is an absence. A critical finding gets 2 challengers; both find no text either way, both lean refute →
`refuted` → dropped from the batch → zero significant findings → **`CONVERGED`** on a spec with an unfixed critical,
adjudicated as *not a defect*. A challenger that **crashes** fails closed (`unconfirmed`, blocks convergence); a challenger
that **returns but is uncertain** fails open — the uncertain one is strictly worse for the user than the crashed one.

**Fix:** delete the second sentence. Line 13 already is the contract.

### M3 — The approve-subset gate drops the contract's all-or-nothing overlapping-edit group rule

**Location:** `plugins/superutils/commands/spec-review.md:188-191` vs design spec `:174-179`
**Found by:** spec-compliance, executability · unanimous

The contract states two rules; the command implements one. Selection: *"Findings whose edits overlap form an all-or-nothing
group **in approve-subset**"*. Application: *"Group application is atomic — if any edit in a group fails, the group's prior
edits are reverted from the candidate."* Step 8.2 carries only the application rule, and only for the scratchpad candidate;
Step 8.4's gate offers *"approve subset (unselected → `declined`, sticky)"* with the **individual finding** as the selection
unit. `overlap`/`atomic`/`group` appear nowhere else in the plugin.

**Impact:** two findings whose edits intersect necessarily render as **one merged diff hunk**. The user approves one of
them: the applied text is not the hunk they saw (default mode never re-prints the diff post-apply), and the other becomes
`declined` — *sticky, excluded from significance and no-progress, never re-proposed* — so the fresh panel's re-finding is
suppressed and the run terminates `CONVERGED` with a half-edited passage. That is precisely what the contract's group rule
exists to prevent.

**Fix:** in 8.4, make the overlapping-edit group (computed in 8.2) the selection unit: selecting any member selects the
whole group, partial in-group selection is not offerable.

### M4 — The `doctrine-compliance` lens cannot load the bar it is mandated to audit against

**Location:** `plugins/superutils/skills/lens-catalog/SKILL.md:33`
**Found by:** repo-conventions · unanimous

The mandate is *"audit against `qa:loop-engineering` (bar items 1–11 + anti-patterns)"*. That lens runs inside
`spec-reviewer`, whose frontmatter is `tools: Read, Grep, Glob, Bash` and `skills: lens-catalog, report-format` — **no
`Skill` tool, and the bar is not preloaded**. The orchestrator holds `Skill` but never relays the bar: the dispatch payload
is fixed at *"lens id + mandate + spec path + unit list"* (`commands/spec-review.md:128`). superutils declares no dependency
on qa; in a marketplace install the qa skill may not exist on disk at all.

**Impact:** panel rule 3 auto-selects this lens for any loop/agent/plugin spec — i.e. the plugin's own dogfood target. The
subagent cannot load the bar and cannot fail loudly, so it reconstructs an "11-item bar" from priors and grades against
invented criteria. That JSON parses fine, so Coverage (which only flags a lens that *fails or returns unparseable JSON*)
marks the lens **covered** — no shallow-coverage WARNING, no `CONVERGED (low-confidence)`. The user gets a doctrine-audited
stamp on a spec never checked against the real bar.

**Fix — a design choice, decide it explicitly:** (a) inline the 11-item bar into `lens-catalog` so the lens is
self-contained (preferred: no cross-plugin dependency), or (b) add `qa:loop-engineering` to `spec-reviewer`'s `skills:`,
give it the `Skill` tool, and declare qa as a prerequisite in the docs.

*(This is the one finding the earlier `/code-review` pass also found — independently rediscovered here, which raises
confidence in it.)*

---

## MINOR

- **The reviewers' `rejected[]` output is collected and then silently discarded.** *(completeness critic; verified)*
  `skills/report-format/SKILL.md:21` mandates `"rejected": [...]` in the reviewer output shape;
  `agents/spec-reviewer.md:34` says *"never silently dropped"*; `skills/lens-catalog/SKILL.md:73` says *"Never silently
  drop."* Nothing consumes it: the sidecar round record has no `rejected` key, the report skeleton has no Rejected section,
  and Step 9's round record is *"panel, units, findings + outcomes, equivalence log; counters"*. The orchestrator performs
  exactly the silent drop its own agents are forbidden to perform — and it bites hardest in a **fresh-panel** loop, where
  every round re-derives the same ghosts by design. (`code-review:finding-falsification` exists in this repo and makes the
  rejected list mandatory output.) The design spec never mentions `rejected`, so this is an implementation invention whose
  consumer was never built.
- **`sort` is piped but not granted.** `commands/spec-review.md:63` runs `stat … | sort -rn | head -5`; `allowed-tools`
  (`:2`) has no `Bash(sort:*)`, while `code-review:review` and `web-auditor:audit` both grant it precisely because they pipe
  into sort. Degraded-but-recoverable (the allowlisted `ls -t` fallback orders by mtime first), but the byte-equal-mtime tie
  detection the contract demands is what is at risk. **Fix:** add `Bash(sort:*)`.
- **Skill name `report-format` collides with the shipped `qa:report-format`.** `plugins/qa/skills/report-format/SKILL.md`
  is also `name: report-format`, and qa invokes it **unqualified** — `Skill(skill: "report-format")` at
  `qa/commands/run.md:145` and `qa/commands/loop.md:356`. superutils' *command* is disciplined (`superutils:report-format`
  everywhere), but its three agents use bare `skills: … report-format`. The `coding-standards`/`tdd-workflow` triplicates
  are **not** precedent — they are only referenced from same-plugin frontmatter, never from a bare `Skill()` call. Harm is
  *inferred*, not confirmed (no artifact documents how the harness resolves a duplicate unqualified name), but installing
  this plugin can silently degrade a shipped one. **Fix:** rename to `spec-report-format`, or qualify qa's two bare calls.
- **Approve-subset has no defined selection mechanism.** The only interactive tool granted is `AskUserQuestion` (4 options
  per question) while a batch is routinely 8–12 findings. `code-review:fix-report:129` already solved this ("multiSelect,
  4 issues per page"). An orchestrator that renders only the first four and treats the rest as unselected permanently
  retires findings the user never saw (`declined` is sticky). Inherited gap — the design spec is equally silent.
- **The tamper re-hash sits before the human gate, not immediately before the write.** The command's own invariant
  (`:100`) and the contract say *"immediately before each fix application"*; Step 8 orders re-hash → candidate → diff →
  **gate (unbounded human wait)** → Edit + re-stamp, with no check at 8.5. A user hand-editing the spec while staring at the
  diff gets their edit silently blessed: `last_written_hash` is re-stamped over content the loop never adopted, disarming
  the round-start guard for every later round.
- **Fresh-panel independence is not enforced.** `agents/spec-reviewer.md:22` (*"You receive no prior-round context by
  design"*) is **descriptive** — it describes the dispatch payload, not a prohibition. The reviewer holds Read/Grep/Glob,
  the prior sidecar and report sit at fully predictable paths, and the reviewer is *required* to load `report-format`, which
  prints those paths. A round-2 reviewer can read its own answer key. **Fix:** an explicit rule — never read
  `docs/superpowers/specs/reviews/**`.
- **Panel selection can yield 2 lenses, below the stated 3–6 floor.** `lens-catalog:45-52` has no floor: rule 1 gives 2 core
  lenses, rule 2 *excludes* `completeness` for specs under 3 `##` sections, rule 3 is content-conditional, rule 4 is a
  ceiling. A 2-section spec with no loop/UI/API content yields 2 lenses, contradicting the same file's line 8, the command,
  the docs and the contract.
- **`spec-reviewer` is granted `Bash` for no reason.** Its `allowed-tools` (`ls`, `head`, `cat`, `grep`) is fully redundant
  with Read/Grep/Glob, its body never invokes a shell, and both sibling agents do a *wider* reading job with
  `tools: Read, Grep, Glob`. This is the one agent that ingests the untrusted document first and is fanned out 3–6× per
  round. Free fix.
- **The cross-section anchor's canonical-phrase clause was dropped.** Contract: *"anchors to the first-cited section's slug
  **with the other section named in the canonical phrase**"*; `report-format:48` renders only *"cross-section → first-cited
  section's slug."* Without the counterpart section forced into the ≤10-word phrase, two distinct cross-section findings
  under the same heading can **false-merge**. The spec's revision history records this clause as a deliberate round-2 fix.
- **The outcome enum, declared exhaustive, misses two abort paths.** `confirmed (not fixed — stopped)` is scoped to
  *oscillation, no-progress, or budget*; the command also documents `STOPPED(interaction-unavailable)` and
  `STOPPED(external-edit)`, both of which can fire *after* the quorum. Their upheld major+ entries match no enum member.
  (Inherited from the contract; see also M1's stronger exhaustiveness hole, which sits on the CONVERGED happy path.)
- **The sidecar round record drops `severity` and `lenses`.** `report-format:79` stores `{"sr_id", "outcome"}` while the
  contract requires *"findings with SR id / severity / lenses / outcome"* and the same file's report skeleton mandates a
  `| SR | severity | lenses | outcome |` table. Both fields are explicitly mutable across rounds, so back-filling from the
  registry renders round 1 with round 2's escalated severity — the major→critical trajectory a re-review loop exists to
  show is erased.
- **The docs never mention the sidecar's control-flow role.** `docs/plugins/superutils.md:46` presents it as an output
  artifact only; a grep for `force|fresh|re-run|resume` returns nothing. But an unchanged spec + terminal sidecar makes the
  command *"print the prior report summary and exit — no dispatches"*. The sharpest case is the one the docs themselves
  advertise: a `CONVERGED (low-confidence)` run, correctly re-run for full coverage, returns the same stale report
  instantly with no documented escape hatch.
- **The Dogfood check mutates the repo's own committed design contract.** *(completeness critic; verified)*
  `tests/ACCEPTANCE.md:36-39` says to run the loop on
  `docs/superpowers/specs/2026-07-13-superutils-spec-review-design.md` — with no scratch-branch clause, no revert step. The
  loop applies fixes to its target **in place** via Edit, and the working-tree gate fires only on a *dirty or untracked*
  target, so a clean committed spec sails through silently. The fixture procedure three lines earlier isolates properly;
  the dogfood procedure drops that clause.

## NIT

- `Bash(git:*)` is granted although the body runs exactly one git command (`git status --porcelain`), pre-approving the very
  operations the file's own contract forbids (`git restore` on the spec, committing). Effectively harmless (the same
  frontmatter grants unrestricted `Write`/`Edit`) and copied verbatim from `/qa:loop` — narrowing it in superutils alone
  would make it inconsistent with every sibling. Repo-wide policy question, not a branch defect.
- The ACCEPTANCE answer script omits the working-tree-gate prompt that *every* run hits (the fixture copy is untracked, so
  Step 0.3 always fires). Nil impact while the harness is a human; it stops being a nit when the deferred `canUseTool`
  auto-responder lands.
- `$spec_path` is used at `:76` and `:85` but never bound — Step 0.2 binds `spec`, `sidecar_path`, `report_path`,
  `snapshot_path` only.
- The docs promise sequential-thinking decomposition unconditionally (`superutils.md:13`); the command makes it optional
  (*"when available, else inline"*), and the plugin declares no dependency on that MCP server.

---

## Checked and found clean (verified, do not re-litigate)

- **Packaging & repo obligations.** `plugin.json` / `marketplace.json` / README row agree at 1.0.0; badge `plugins-10`
  matches the 10 registered plugins; `plugin.json`'s key set matches every sibling; all four `CLAUDE.local.md` obligations
  (plugin.json, marketplace entry, README row + badge, `docs/plugins/superutils.md`) are met. Both JSON files are valid.
- **Contract fidelity.** Every normative statement of the design spec was walked: input scope, all 8 loop steps, severity
  and needs-decision anchors (verbatim), the registry (discovery order, slug rules, `sha256(slug|phrase)` key, max-severity
  merge), the challenger quorum (1/major, 2/critical, split → gate, no re-grading), stop precedence, the two-phase fixer,
  convergence-before-the-gate, the tamper flow, the working-tree gate, the report skeleton, and the 6 residual risks — all
  present and matching **except** M1–M4 and the minors above.
- **No cross-artifact drift.** Flags and their defaults (3 / 30 / 1800) are identical in `argument-hint`, the parse table,
  the docs and the contract. Outcome enum, terminal statuses, severity vocabulary, lens ids, agent dispatch names vs `name:`
  (3/3), skill dir names vs `name:` (2/2) all match one-for-one.
- **Bounded and terminating.** `--max-iterations`, the Step 5 stop ladder, and the stage-boundary budget check with 2×
  retry headroom.
- **No approve-gate bypass sold as harmless.** `--no-approve` and `--auto` are labelled as bypasses; `--auto` implies
  `--no-approve` but **not** `--allow-dirty`, so the headless path still fails closed on a dirty spec.
- **Recovery is real.** Pre-loop snapshot before the first fix of every run, printed at terminalization; nothing is ever
  committed.

## Refuted (transparency — these were raised and killed)

- *No prompt-injection quarantine of ingested spec content* — refuted 2-1: the repo's trust boundary is provenance-based;
  the only plugin with nonce delimiters (`code-review:feedback-analyzer`) ingests arbitrary GitHub comments, while every
  working-tree-reading agent in the repo has none. No egress tool in the plugin. Marketplace-wide doctrine-gap candidate,
  not a defect of this branch.
- *`unconfirmed` cannot block convergence* — refuted 2-1: stated three times across command, skill and contract.
- *Step 8.3 requires a diff but grants no diff mechanism* — refuted 3-0: `Bash(git:*)` pre-approves `git diff --no-index`.
- *Step 8.5 Edits a file the orchestrator never Reads* — refuted 3-0: Step 1 cannot enumerate `##` headings without reading it.
- *Coverage discloses lens failures but not challenger non-returns* — refuted 3-0: challenger non-return is handled by a
  **stricter** mechanism (`unconfirmed` blocks convergence outright).
- *Spec path is never canonicalized (symlink / `..` escape)* — refuted 3-0: the path comes from the user, who already holds
  unrestricted Write/Edit; both escapes require the victim to be the attacker.
- *Budget counters persisted only at round end* · *User abort (Esc) has no terminal status* · *the fixer's `notes` has no
  consumer* · *the `.bak` archive target is never bound* · *the shipped orchestrator cites a repo-only design-spec path* —
  all refuted with concrete counter-evidence.
- Plus **38 candidates self-rejected** by the lenses before they ever reached the refuters (notably: `stat -f` BSD-only —
  the GNU form is already in an inline comment; the missing TTY probe — deliberate, disclosed, with a runtime backstop;
  `tools:` + `allowed-tools:` in agent frontmatter — repo convention; missing token ceiling — a non-MUST rider that
  `qa:loop` itself does not meet).

## Residual risk — what this review could NOT establish

1. **Nothing was executed.** No agent ran `/superutils:spec-review`. Every executability claim is text-derived. The
   acceptance protocol (3 fixture runs) has still never been performed, so the loop has never been observed to converge, to
   find a seeded defect, or to apply an edit pair cleanly.
2. **Skill-name resolution semantics are undocumented in-repo**, so the *harm* of the `report-format` collision is inferred,
   not proven. This is the single finding whose severity would move most under new information.
3. **The budget envelope was never computed against the fixture.** The 2× retry-headroom rule reserves pessimistically;
   a worst-case 3-round run on the seeded fixture may trip `STOPPED(budget)` at a stage boundary before converging, which
   would make ACCEPTANCE's own pass condition ("`CONVERGED` within default budgets") unreachable for reasons unrelated to
   review quality. **Do the arithmetic, or find out on the first real run.**
4. **Oracle quality is unassessable from prompts.** Whether the lens roster, the anchors, and the ≤10-word equivalence
   judgment actually produce good findings — and whether a fresh panel is a meaningful verifier at all — is empirical. The
   plugin concedes this (soft oracle; "Re-reviewed (advisory)", never "Verified").
5. **`skills:` as an agent-frontmatter key is presumed valid** because every sibling plugin uses it — presumption, not
   verification. If it is not supported, reviewers never load the severity anchors at all, which would undermine the oracle
   far more than anything reported here.
6. **Prompt-injection resistance in practice was not tested** — only reasoned about from tool grants.

# av-marketplace — Batch Resolution of `needs-decision` Findings

**Date:** 2026-08-27
**Status:** Approved design, pre-implementation
**Affected plugins:** `code-review` 1.17.3 → 2.0.0, `qa` 2.5.2 → 2.6.0

## Purpose

Findings flagged `**Fix-policy:** needs-decision` are the only findings a fixer
may not resolve on its own — the fix direction is a judgment call. Today the
only way to resolve one with the code in view is `/fix <ID>`, one finding per
invocation. `/fix-all` skips them by design. `/fix-report` can select them, but
asks for the decision from the report text alone, with no agent having opened
the file the finding points at.

The result is that a user with eleven findings, three of them `needs-decision`,
runs `/fix-all` for eight and then types `/fix` three times — re-entering a
command, re-resolving the report, and re-reading the same context each time.

This spec makes the decision stage a first-class, analysis-backed step reachable
from the entry points that already exist. Analysis fans out in parallel,
decisions are collected in one uninterrupted sweep, and the fixers run as a
single batch afterwards. The sweep is uninterrupted with exactly one documented
exception: a `**Decision-pin:**` mismatch found immediately before dispatch sets
that finding aside rather than asking in the middle of a batch, and the
set-aside findings are re-analysed and re-swept as a second pass once the
remaining dispatches have completed (`Decision record`).

## Evidence

**The existing step is not missing — it is skipped.** `/fix-report` Step 2.4
("Elicit decisions for needs-decision selections", `fix-report.md:180`) landed in
commit `a10cd59`. It is present in the installed copy at
`~/.claude/plugins/cache/av-marketplace/code-review/1.17.0/commands/fix-report.md`,
so the user's report that it never fired is not version drift against the repo's
1.17.3. Two behavioural causes are plausible and are addressed here:

1. `needs-decision` findings are mixed into a severity-sorted checklist
   paginated four at a time (Step 2.2). A user who stops selecting after page one
   may never reach them, in which case Step 2.4 has nothing to act on.
2. The step is prose at line 180 of a 264-line command. Instructions buried
   mid-command are unreliably executed.

**The dispatch contract already exists.** `fix-auto.md:52` reads a trailing
`User decision:` line and treats it as authoritative over the Remediation. No
change to that *dispatch contract* is required. `fix-auto` does change
elsewhere, but on the read side only: its Phase 1 aborts with an explicit error
if the dispatched block already carries `**Status:** 🚫 Rejected`, and its
Phase 6 verdict vocabulary is unchanged, per `Status vocabulary extension`.

**The proposal format already exists.** `/fix` Phase 3 (`fix.md:238`, `:271`,
`:285`) renders `**Alternatives:**` with a recommendation and turns the approval
gate into `Which resolution should I apply? (A / B / no)`. This spec generalises
that format rather than inventing one.

**`/fix-all` already partitions.** Step 2.2.5 (`fix-all.md:213`) moves
`needs-decision` findings into a `needs_decision` list, exempt from the severity
floor so they are never silently dropped. That list is the input to the new
phase.

**Sequential fixing is deliberate.** `/fix-all` Step 3.1 dispatches `fix-auto`
one finding at a time. Documentation findings routinely target the same file
(`README.md` is the common case), and two concurrent `Edit` calls against one
file lose a write.

**The status vocabulary is not local to `code-review`.** `Partially Fixed`
appears in seven files across two plugins, including
`plugins/qa/skills/report-format/SKILL.md:233`, which documents the status
contract as consumed by code-review, and `plugins/qa/commands/loop.md:917`,
which declares that `/qa:loop` never writes `Partially Fixed` because doing so
would freeze an issue out of `/fix-report`.

**No CI guard covers that vocabulary.** `plugins/code-review/scripts/check-prefix-sync.sh`
enforces the Category→Prefix mapping only. A status value added in one plugin and
missed in the other would drift undetected until a real finding hit it.

**No live fixtures exist.** Neither `docs/reviews/` nor `docs/testing/reports/`
is present in this repository, so an end-to-end run requires a synthetic report.

## Scope

**In scope**

- New read-only agent `code-review:decision-analyst`.
- New skill `code-review:decision-gate` carrying the decision-stage doctrine.
- `/fix-report`: partition `needs-decision` onto dedicated leading checklist
  page(s), every one of them shown before the first `auto` page; replace
  Step 2.4 with the decision gate.
- `/fix-all`: new Step 5 offering the decision stage after the auto batch.
- `/fix`: Phase 3 delegates the `Alternatives:` format to the skill; render
  behaviour unchanged, plus the two read-side duties `Status vocabulary
  extension` assigns it — its Phase 0 aborts on a block it resolved by ID that
  already carries `**Status:** 🚫 Rejected`, and its Phase 8 never writes a
  second `**Status:**` line over an existing one. `/fix` adopts the rendering
  contract only — its gate stays
  `(A / B / no)` and `/fix` never writes `🚫 Rejected`. The five-outcome sweep
  belongs to `/fix-report` and `/fix-all` alone.
- New finding outcome `🚫 Rejected`, propagated to both plugins.
- The extended `**Location:**` written form ``**Location:** `path:line` (was:
  `original`)``, with the one-line read rule every consumer of the field adopts.
- Repository-root containment as a conjunct of stage 0's usability rule, beside
  parse and existence, since `**Location:**` is an untrusted-origin field.
- The nonce-bound untrusted-data framing a feedback-origin block is dispatched
  to the analyst under, reusing the protocol `agents/feedback-analyzer.md`
  already defines, and the `**Source:**` row stage 2's render carries.
- Registration of the loop-written finding-block fields — `**Decision:**`,
  `**Decision-retired:**`, `**Verification-plan:**`, `**Decision-pin:**`,
  `**Dispatch:**` and `**Verification:**` — with both plugins' documented
  finding-block schemas, including `/qa:loop`'s duty to carry them over on its
  reuse and adopt paths.
- Version and documentation updates in the four places each plugin requires.

**Out of scope**

- Any new slash command. The entry points stay `/fix`, `/fix-report`,
  `/fix-all`. A fourth command was considered and rejected: the command surface
  is already large enough to overwhelm.
- Any new command argument or keyword. Reaching `needs-decision` findings is
  solved by checklist partitioning, not by syntax the user must remember.
- Parallel execution of `fix-auto`.
- Changes to how findings are *classified* as `needs-decision`. The
  `docs-fact-registry` doctrine and the `Drift-class` → `Fix-policy` derivation
  are unchanged.
- A CI guard for the status vocabulary. Named as a residual risk below.

## The flow

```
input          /fix-report: findings selected on the needs-decision page
               /fix-all:    the needs_decision list from Step 2.2.5
                  │
 entry     Decision replay check
           Read each selected finding block for a Decision: line. A
           finding carrying one and no Status: line skips stages 0-2 —
           no analyst dispatch, no re-ask — and re-enters the flow with
           the recorded resolution, subject to the pin check, the
           dispatch-marker rule and the retry limit under Decision
           record: "decided, never dispatched" enters stage 3 normally,
           while "dispatched, outcome unknown" re-enters at stage 3.5
           and is never re-dispatched blind. Because stages 0-2 are
           skipped, the replay dispatches the Location: the report now
           carries — which is the corrected one, since stage 2 wrote the
           substitution into the report itself and not into the
           dispatched copy alone. The resume message counts only
           findings that still lack a decision.
                  │
 stage 0   Location pre-check
           A location is usable iff it parses as path:line or
           path:line-range, and the path is contained in the
           repository tree, and it exists there. The value is read by
           the two-clause read rule under Status vocabulary extension:
           first backticked token, any trailing "(was: …)"
           parenthetical ignored; first whitespace-delimited token
           after the field name where the line carries no backticked
           token. Anything else — "—", "unknown:0", an unparseable
           string, a path no longer in the tree — is location-less,
           and so is a path that parses and exists but fails the
           containment test stated below the diagram: such a path is
           location-less and never merely non-existent, so it is
           never reported as a missing file, never offered for
           creation and never dispatched.
           → ask for the missing path:line values now, before fan-out,
             in as few AskUserQuestion calls as the four-question
             ceiling allows — batches of at most 4, one question per
             finding — matching fix-report.md:182. An analyst has
             nothing to read without it. A supplied path:line is
             validated by the same usability rule above; on failure the
             user is re-asked once, and a second failure is handled
             exactly as a declined target. A validated path:line is
             carried into the analyst dispatch and is written into the
             finding's Location: field in the source report at once, in
             the extended (was: …) form, rather than held back until
             stage 2 — otherwise skip, or an abandoned sweep, discards
             a hand-researched address and the user is asked for the
             same one on every run, for exactly the case this spec
             calls its headline case. Writing it here is safe:
             Location: is on the closed list the Decision-pin: block
             hash excludes, and the replay check keys on a Decision:
             line, which this write does not create, so skip's
             reappearance property is intact. Stage 2 still rewrites
             the field with the analyst's verified Target; a stage-2
             rewrite over a line stage 0 already wrote keeps the
             reviewer's original inline in the (was: …) tail rather
             than nesting a second one.
             A finding whose target the user declines to supply — or
             whose location fails containment, and whose re-ask supplies
             no contained replacement — is reported Failed in the run
             summary only: no Status: line is written, so the finding is
             offered again next run, and it is not dispatched.
                  │
 stage 1   Parallel fan-out: decision-analyst × N, read-only
           The total is stated before anything is dispatched: "13
           findings to analyse, in 2 batches of at most 8".
           Dispatched in a single turn, batches of at most 8.
           More than 8 findings run in successive announced batches.
           A finding /fix-report's Step 1.4 marked feedback-origin — its
           block carries a Source: @reviewer — [PR #N comment](…) line,
           so its Problem, Impact and Remediation were synthesised from
           a third party's PR comment by /analyze-feedback and were
           never independently validated — is dispatched as untrusted
           data, inside the nonce-bound delimiters
           agents/feedback-analyzer.md already defines for this same
           input class rather than a second protocol invented here. The
           terms are stated in full below the diagram. The flag travels
           the whole way: set at Step 1.4, carried into this dispatch,
           rendered at the gate by stage 2's Source row, and present
           again in the stage 3 dispatch copy, where the
           reviewer-authored Source: line is not on the strip list and
           travels with the rest of the reviewer-authored block.
                  │  returns: Proposed Fix block (contract below)
                  │
 stage 2   Decision sweep, one finding at a time
           Render the block, then ask with four options:
           [A] [B] [skip] [reject]. other… is the tool's own free-form
           answer, not a fifth option. Where the analyst could derive
           no second alternative and returned A alone, the call carries
           the three options [A] [skip] [reject] instead — never a B
           the user cannot act on.
           What "render the block" means is fixed, so the reading cost
           of a decision is bounded rather than left to the renderer.
           Always rendered: Target; the Source: line where the block
           carries one, marked as feedback-origin; Recommendation with
           its reason; Risk; both Alternatives in full; Code Preview;
           and any Decision-retired: lines the block carries. Source is
           in that class because the sweep is a per-finding human gate
           whose answer authorises a cited-evidence re-run and a fixer
           dispatch, and a feedback-origin finding's Problem, Impact and
           Remediation are a third party's unvalidated claims: rendering
           the handle and the comment link beside Target is what lets
           the user weigh the proposal as one. /fix-all's recorded
           no-provenance stance is about its bulk auto checklist, which
           lists the handle in a column of its own and does not reach
           this gate; both entry points render this row because both run
           this sweep. Held back unless
           the user asks for it: the verbatim command and tool output
           backing Findings — the claims themselves are always
           rendered — and both Verification Plans. Always rendered and
           never held back: the re-run raw output of a Rejection
           candidate's citations, and the recorded/fresh side by side
           where that re-run diverges, because the reject gate exists
           so that the user judges that evidence.
           The reject evidence gate is scoped to findings whose block
           carries a Rejection candidate. For one that does, the
           orchestrator re-runs the exact commands and tool calls the
           analyst cited for that candidate and shows the raw output at
           the gate. Whether the candidate is supported is decided by
           the support test stated once under Decision outcomes; on any
           other result — a command that now errors, a recorded line
           that is gone, an empty recorded result that now returns
           output — reject is not offered for this finding, the
           call carries the remaining options ([A] [B] [skip], or
           [A] [skip] where the analyst returned A alone), and the
           finding
           returns to the sweep with the recorded and the fresh output
           shown side by side as the discrepancy.
           The re-run's boundary has no escalation path. It happens
           under stage 3.5's execution boundary — read-only inspection,
           and so of git only log, show, diff, blame and status — with
           the one local difference that nothing outside it is offered
           for approval here: no test or build command is run at this
           gate, approved or not. A cited command that writes, a cited
           test or build command, or any git subcommand outside those
           five, is displayed unexecuted and the candidate is treated
           as not re-runnable; so is a citation whose inspection
           command falls outside the commands' pre-approved grants and
           raises a permission prompt the user denies. Either way the
           finding takes the no-candidate path below and its rejection
           is marked unverified. The restriction is not optional, and
           it does not rest on the grant list: a cited command is
           re-run with the orchestrator's grants rather than the
           analyst's, and those git grants are now narrowed to the
           seven read-only subcommands the stage actually runs, so a
           cited git restore raises the platform's prompt rather than
           executing silently. That prompt is a backstop, never the
           restriction — it can be answered in haste, and it is not the
           boundary's AskUserQuestion. The restriction is what keeps a
           write-capable git subcommand from being offered for
           execution at all, and what protects the uncommitted diff
           Oracle names as the recovery path for a wrong call.
           A finding with no Rejection candidate, including one whose
           analyst failed, has no cited evidence to re-run: reject
           stays offered, gated only on the user's non-empty reason,
           and the run summary marks such a rejection unverified. The
           re-run persists nothing: the — <reason> tail of the status
           line stays the whole record of a rejection.
           Approval for the decided plan's out-of-boundary checks is
           asked here, in the same sweep turn as the decision itself,
           because those checks are known as soon as the alternative is
           chosen: one AskUserQuestion per finding, carrying every such
           command's exact text, and stating what declining costs — the
           check counts as unrunnable, the finding takes stage 4's
           fourth case, that attempt counts toward the two-attempt
           retirement, and two such runs retire the decision. Only a
           plan the orchestrator derives after an other… decision can
           still escalate at stage 3.5, and the sweep says so when it
           takes that answer.
           The only writes this stage permits, all into the source
           report: the Decision: line; the Verification-plan: line,
           carrying the checks for the alternative actually decided
           (for other… the checks the orchestrator derives after the
           decision); the Decision-pin: line, written together with the
           decision because it must capture the state that decision was
           made against; the corrected Location: line; the supersession
           rewrite of a live Decision: line to Decision-retired: with
           its attempt entries intact, which lands at the moment a pin
           mismatch sets the finding aside — never after the fresh
           decision is written — so that the second pass renders those
           retired lines together with the fresh proposal and the fresh
           Decision: line is written over a block already showing its
           retired history; and for reject the Status: 🚫 Rejected
           (YYYY-MM-DD) — <reason> line, which stage 4 cannot reach
           because reject never dispatches.
           The corrected Location: carries stage 0's user-supplied
           path:line, or the analyst's verified Target normalised to
           the path:line form fix-auto parses (a range's start line),
           backticked like the field it replaces, and it preserves the
           reviewer's original inline:
           Location: `path:line` (was: `original`)
           so a wrong Target costs a stale parenthetical rather than
           the finding's only address. Where stage 0 already wrote the
           field, this rewrite replaces the path:line alone and leaves
           the (was: …) tail carrying the reviewer's original exactly
           as stage 0 wrote it, never nesting a second (was: …). The
           full range appears only in
           the rendered proposal. Persisting the substitution in the
           report itself, rather than patching the dispatched copy
           alone, is what keeps the replay path working.
           Each decision is written to the source report as it is made.
                  │
 stage 3   Batch dispatch: fix-auto × M, sequentially
           Issue block + trailing "User decision: <resolution>", where
           <resolution> is the chosen alternative's full, self-contained
           resolution text — never a bare A or B label, which fix-auto
           cannot resolve.
           Dispatch-copy rule: the copy handed to fix-auto carries the
           reviewer-authored fields plus the loop-rewritten Location:
           line, which this stage requires to travel. Every other line
           on the closed list the Decision-pin: hash excludes is
           handled here too: the Verification-plan:, Decision-pin:,
           Dispatch:, Verification: and Decision-retired: lines are
           stripped from the copy, the Decision: line is reduced to its
           trailing "User decision: <resolution>", and any Status: line
           this loop wrote is stripped with them. The Status: line the
           block already carried when the run began travels unchanged —
           it is not loop-written for this decision, and fix-auto's
           Phase 1 abort on 🚫 Rejected reads exactly it. All of these
           lines stay in the source report, which is what the replay
           path and stage 3.5 read: a fixer holding unrestricted Edit,
           Write and Bash, told to iterate until verification passes,
           must not be handed the checks stage 3.5 will grade it with.
           The rule binds every dispatcher of a finding block, not this
           stage alone: /qa:loop's Step 3c forwards the same block to
           fix-auto and applies the same closed list.
           The Location: dispatched is the one the source report now
           carries: stage 2 already wrote the correction there, in the
           normalised path:line form, so the Location the report
           carries is already in dispatch form and this stage neither
           re-normalises nor re-derives it. Persisting the substitution
           rather than patching the dispatched copy alone is what keeps
           the replay path working — otherwise the verified target is
           rendered to the user and then discarded, and a resumed run
           dispatches "—" into a fixer that treats Location as required
           and stops to ask from inside a subagent.
           This stage's own write is the dispatch marker, written
           immediately before each fixer call as its own line directly
           beneath the Decision-pin: line, or beneath the Decision:
           line where no pin could be written — never appended at the
           end of the block, where fix-auto's Remediation capture would
           take it in. Its written form is given under Decision record:
           **Dispatch:** attempt <N> dispatched <YYYY-MM-DD>
                  │
 stage 3.5 Verification, run by the orchestrator
           The orchestrator — not the fixer — executes the plan the
           Verification-plan: line persists for the alternative that
           was actually decided: the analyst supplies one plan per
           alternative, and for other… the orchestrator derives the
           checks after the decision. Stage 2 wrote that plan into the
           report, so the replay path runs the persisted plan instead
           of re-deriving one. It logs the raw output.
           A check passes when its logged raw output matches the
           expected result recorded with it on the Verification-plan:
           line — never on exit status alone, since a grep asserting an
           absence exits non-zero on success. A plan passes when every
           check that ran passes.
           A check is runnable when the orchestrator can execute it and
           log a result — a soft LLM re-read of prose included, which
           is runnable, lands in stage 4's first case, and carries its
           softness in the run summary as advisory verification.
           A soft check's logged raw output is the verbatim excerpt the
           re-read quotes out of the file it inspected, given with the
           path:line it was read from; it passes when that excerpt
           matches the expected result recorded with it, by the same
           test every other check is decided by. A re-read that logs a
           verdict — "the drift is gone" — rather than an excerpt has
           logged no result at all, and is a check that cannot be run.
           The excerpt is quoted file content and not a command's
           observable output, so a pass resting on such a check is
           classified advisory and never hard.
           Execution boundary: read-only inspection is the whole of
           what is inside it and is the one term never escalated; the
           project's declared test and build commands are outside it
           and escalate exactly like anything else outside it. Both
           terms are defined once below the diagram. Anything outside
           that surface is executed only with the user's explicit
           approval, and that approval was already taken at stage 2, in
           the same sweep turn as the decision, in one AskUserQuestion
           call per finding carrying every such command's exact text
           and the cost of declining. This stage raises no new ask for
           a plan approved that way, so nothing here interrupts the
           phase the sweep sold as uninterrupted; only a plan the
           orchestrator derived after an other… decision may escalate
           here, in an AskUserQuestion call carrying the exact command
           text and the same statement of cost, and the sweep told the
           user so when it took that answer. Read-only inspection — the
           Read, Grep and Glob tools plus git log, show, diff, blame
           and status — is inside the boundary, so the ordinary
           documentation-drift check, a grep or a re-read of the prose,
           escalates at neither point. A
           check the user refuses, or one that
           cannot be run, is never silently skipped: where no check of
           the plan ran at all, stage 4's fourth case applies; where
           some ran and some did not, the finding is graded on the raw
           output of those that ran and the shortfall is disclosed as
           stage 4's fourth case describes.
           fix-auto's own "Fixed" verdict is advisory input, not the
           deciding signal. Where no check of any kind ran, stage 4's
           fourth case applies.
                  │
 stage 4   Status write-back to source reports
           The Step 4.1 / 4.1.5 write-and-verify procedure, run over
           the decision batch by the command that owns it. In
           /fix-report the gate itself dispatched nothing: Step 3
           dispatched the decided findings together with the auto ones,
           so Steps 4.1 / 4.1.5 run once over that whole batch and the
           gate writes back nothing of its own. In /fix-all those steps
           have already run and closed their progress task — except on
           the zero-auto path, where Steps 3-4 never ran and Step 5
           owns both the write-back and their progress rows).
           Step 4.1.5 verifies three write kinds, not one, over every
           finding the batch wrote back for: the Status: line, by its
           positional check; the attempt entry appended to the live
           Decision: line, recorded as attempt-entry-missing when it did
           not land; and the Verification: line, located by its key
           wherever in the block it sits and recorded as
           verification-line-missing. Both write cases carry the
           Verification: line, so that check runs over the whole decided
           batch rather than over one group of it. A rejected finding is
           outside all three: reject never dispatches, so it carries no
           Verification: line at all and its absence is not a failure.
           Whether the fixer edited is read from the tree, never from
           its narration: immediately before and immediately after each
           dispatch the orchestrator takes two observations and logs
           both. (a) A git hash-object content hash of every path the
           Decision-pin: line names, except its unpinnable entries,
           recorded as absent where the path does not exist; an
           unpinnable entry is skipped because Sanitisation rejected its
           token and no command is constructed for a rejected token —
           recording absent for it would manufacture exactly the false
           absent → present flip that state exists to prevent. This is
           the observation the status is decided on,
           and it does not depend on git reporting the path at all — an
           ignored path, or one marked skip-worktree or
           assume-unchanged, is hashed here even though porcelain never
           lists it. (b) git status --porcelain plus a content hash of
           every path it lists, which serves only to surface writes
           outside the pinned set. Porcelain alone cannot see an edit:
           a path already ' M' before the dispatch is still ' M' after
           a further edit, so the per-path content hash is what makes
           that edit observable. A path that appears, disappears or
           changes content between the two observations — absent →
           present and present → absent included — is an observable
           change; anything else is no edit, whatever the fixer
           reported, and its verdict stays advisory.
           The expected set is the pinned entries marked :edit, the
           paths the resolution says it changes, and never the :ref
           entries, which are pinned as referents nobody undertook to
           edit, and never the unpinnable entries, even when marked
           :edit. The two exclusions are distinct: a :ref entry is one
           nobody undertook to edit, an unpinnable entry is one for
           which no observation was taken, so a dispatch whose every
           :edit entry is unpinnable has nothing to grade and falls to
           the "observation cannot be taken at all" case below. An
           observable change inside the expected set decides
           the status below, while an observable change outside it is
           logged and named in the run summary as an out-of-scope write
           — fix-auto can edit beyond the pinned set (several
           locations, its own auto-iteration), and such a write must be
           reported rather than read as no edit at all. Where no
           Decision-pin: line was written because neither hasher
           existed, the expected set is re-derived by Decision record's
           membership rule with its :edit/:ref marking, applied to the
           resolution text the decision line carries: an unpinned
           finding is graded exactly as a pinned one, only the
           pre-dispatch pin comparison is skipped, and the run summary
           names it as unpinned. That membership rule is syntactic and
           tests nothing, so every re-derived path passes the same
           Sanitisation allow-list before any command is constructed
           from it: a token that fails is rejected, never escaped, and
           is unpinnable here too — excluded from the paths hashed and
           from the expected set exactly as above — rather than reaching
           the shell. Where an observation cannot be taken
           at all, the dispatch is not graded as no edit: no Status:
           line, "attempt N: dispatched, unverified" per the fourth
           case below, and the run summary names the finding as
           unobservable. The loop's own writes to the
           source reports are declared expected and are never reported
           out-of-scope. Four cases, tried in this order:
           → stage 3.5's raw output passes: ✅ Fixed. A soft check — an
             LLM re-read of prose — passes like any other, and the run
             summary carries advisory verification for that finding.
           → an observable change inside the expected set and a plan
             whose raw output does not pass: ⚠️ Partially Fixed.
           → the dispatch errored, or no file in the expected set
             changed observably: no
             Status: line at all, "attempt N: failed" appended to the
             decision line, and the finding reappears next run. This
             case is tried before the fourth, so a dispatch that
             errored where no plan existed records attempt N: failed
             and not attempt N: dispatched, unverified.
           → no check of any kind ran: no plan of any kind existed —
             the degraded path, or a finding for which the analyst
             supplied none — or every check of the decided plan was
             refused or unrunnable at stage 3.5's execution boundary.
             No Status: line, "attempt N: dispatched, unverified"
             appended to the decision line, counting toward the
             two-attempt retirement exactly as interrupted, unverified
             does, and "verification: unavailable" carried in the run
             summary, naming the finding. Where some checks ran and
             passed and others were refused or unrunnable, this case
             does not apply: the finding is graded on the raw output of
             the checks that did run, and the shortfall is disclosed,
             never silently skipped — the block carries Verification:
             advisory — <checks run>; <N> not run: <check text>, and
             the run summary carries a coverage warning naming the
             finding.
           The last two are never ⚠️ Partially Fixed: that status is
           terminal at both Step 1.3 filters, so it would freeze the
           finding out of every future run. Writing no Status: line
           instead is stage 0's own Failed handling, applied here.
```

The parallelism the user asked for lives in stage 1. Stage 3 stays sequential
for the write-conflict reason recorded under Evidence.

**Containment, not just existence.** `**Location:**` is an untrusted-origin
field: `/analyze-feedback` persists reviewer-authored blocks into reports, and
the value stage 0 validates is written back into the source report — so it
survives to every later replay run and is dispatched to a fixer holding
unrestricted `Edit`, `Write` and `Bash`. Existence alone does not bound it:
`/etc/hosts:1` and `../../.ssh/authorized_keys:1` both parse and both exist.
Containment is therefore a conjunct of the usability rule in its own right, with
the semantics `scripts/allocate-feedback-file.sh` already ships for its own
target: reject before resolving, a path that is absolute or that carries a `..`
segment failing outright; resolve *physically*, taking the physical path of the
containing directory (`cd "$(dirname "$path")" && pwd -P`, symlinks followed)
and re-attaching the final component, so that a symlink pointing out of the tree
cannot smuggle the target back in — resolving the parent rather than the leaf
keeps the test identical for a path that does not exist; and prefix-match
against the repository root, taken as `git rev-parse --show-toplevel` and itself
resolved with `pwd -P`, the path being contained iff the resolved value begins
with `<root>/` — the trailing separator kept, since a bare prefix match on
`<root>` also admits a sibling `<root>-evil/…`. A path failing any of the three
is location-less and never merely non-existent: it is never reported as a
missing file, never offered for creation and never dispatched, and it takes the
declined-target path. A replacement the user supplies is validated by this same
rule, under the single re-ask stage 0 allows.

**A feedback-origin block is dispatched as untrusted data.** `/fix-report`
Step 1.4 marks a finding **feedback-origin** when its block carries a
`**Source:** @reviewer — [PR #N comment](…)` line: its `Problem`, `Impact` and
`Remediation` were synthesised from a third party's PR comment by
`/analyze-feedback` and were never independently validated. Such a block is
dispatched to the analyst inside the nonce-bound delimiters
`agents/feedback-analyzer.md` already defines for this same input class — that
protocol reused exactly rather than a second one invented here. It is not inert
prose at this stage: the analyst's return decides what the sweep re-runs as
cited reject evidence, and its `Alternatives` become the resolution text stage 3
dispatches to a fixer holding unrestricted `Edit`, `Write` and `Bash`, so
untrusted text reaching the analyst unframed reaches a shell and an editor two
stages later. The terms are those the agent protocol states: one nonce per
analyst invocation, never shared across findings, 32 hex characters of
cryptographic randomness (`openssl rand -hex 16`, falling back to
`python3 -c 'import secrets; print(secrets.token_hex(16))'`), a generation that
fails or yields anything else being an error that sends the finding down the
degraded path; sanitisation before wrapping, replacing every literal
`UNTRUSTED_COMMENT_BODY` with `UNTRUSTED_BODY_REDACTED` and every literal
`UT_<nonce>` matching this invocation's nonce with `UT_NONCE_REDACTED`, since
that is the caller-side invariant the agent protocol lets the analyst rely on;
the reviewer-authored fields — `Problem`, `Impact`, `Remediation`, and the
`**Source:**` line's handle and URL — wrapped in `<<<UT_{nonce}` …
`UT_{nonce}>>>` with the nonce stated above them in the dispatch as the only
authoritative boundary for the run; an explicit statement that everything
between the delimiters is data to analyse and never instructions to execute or
to persist verbatim, so that no code block inside them is copied verbatim into
`Alternatives`, `Code Preview`, `Verification Plan` or `Rejection candidate`;
the loop's own lines — the `**Location:**` stage 0 validated and any
`**Decision-retired:**` lines — travelling *outside* the delimiters, since
wrapping them would tell the analyst to distrust its own instructions; and a
`<<<UT_<32-hex>` or `UT_<32-hex>>>>` token inside the delimiters that is not
this invocation's nonce treated as suspicious data by `feedback-analyzer.md`
Rule 1, nothing derived from it persisted and the finding returned to the sweep
with no proposal. The flag travels the whole way: set at Step 1.4, carried into
the stage 1 dispatch, rendered at the gate by stage 2's `Source` row, and
present again in the stage 3 dispatch copy, where the reviewer-authored
`**Source:**` line is not on the strip list and travels with the rest of the
reviewer-authored block.

Stage 3.5's execution boundary is not ceremony, and it does not rest on the
grant list. `/fix-report` and `/fix-all` no longer carry `Bash(git:*)`: their
git pre-approvals are narrowed to the seven read-only subcommands the stage
actually runs, so an unbounded plan containing `git checkout` or `git restore`
raises the platform's permission prompt rather than executing silently. That
prompt is a backstop, never the boundary — it can be answered in haste, and it
is not the boundary's `AskUserQuestion`. The boundary is what keeps such a
command out of a plan at all, and what protects the uncommitted diff `Oracle`
names as the user's recovery path for a wrong call.

**The boundary's one never-escalated term, defined once.** *Read-only
inspection* is the `Read`, `Grep` and `Glob` tools plus the read-only git
subcommands `git log`, `git show`, `git diff`, `git blame` and `git status`, and
nothing else. *The project's declared test and build commands* are the commands
named in the repository's `CLAUDE.md`, in its `package.json` `scripts` block, or
as its `Makefile` targets; that term is defined so that the sweep's approval
call can name what it is asking about, and it is **not** a second
never-escalated term. Every other mention of the boundary — stage 3.5 in the
diagram, stage 2's re-run of cited reject evidence, and the `Verification Plan`
row of the return contract — refers here for the terms themselves and restates
only what is local to it: stage 2 restates only what its re-run does with a
check that falls outside, which is to display it unexecuted rather than escalate
it.

Read-only inspection is the whole of what is inside the boundary, and it alone
is never escalated — so the ordinary documentation-drift check, a grep or a
re-read of the prose, escalates nowhere. The project's declared test and build
commands are **outside** it and escalate exactly like anything else outside it.
Their membership is read from the repository under review, which is the same
trust domain as the report whose finding proposed the check; and the declared
name says nothing about what runs, since `npm test` executes whatever
`package.json` `scripts.test` currently holds and `pytest` executes the
`conftest.py` it collects. Nothing declared in the tree can license its own
execution, so declaring a command buys it no exemption from the ask. Anything
outside that surface is shown to the user and explicitly approved first. That
approval is asked with `AskUserQuestion` — the only construct whose answer
provably originates with the user — and the call carries the exact command text
that would be run; if `AskUserQuestion` is unavailable or errors, the check
counts as one that cannot be run.

**Approved is not the same as unprompted, and unprompted is not the same as
approved.** The platform's own permission prompt and this boundary's escalation
are independent gates, and the declared set crosses them in both directions: it
is open, read from the repository, while the commands' own pre-approved
`Bash(...)` grants are a fixed list. A declared command **on** that list —
`Bash(pytest:*)` and `Bash(npm test:*)` both are — runs with no platform prompt
at all, and that silence is **not** approval: without the sweep's
`AskUserQuestion` the check was never approved and is not run. A declared
command **off** it — `make check`, or this repository's own declared checks —
raises the platform's prompt as well, and that prompt is not the boundary's
`AskUserQuestion` escalation and never substitutes for it; a prompt the user
denies, or one that errors, makes the check one that cannot be run, including
one the sweep had already approved.

**That fixed list is written down and machine-checked.** `decision-gate` carries
it as a `### The grant registry` section: a scope table classifying every
consumer of the skill, and a grant table classifying every `Bash(...)`
pre-approval on a runs-the-stage consumer as `inside-boundary`, `pipeline` or
`outside-escalates`. `scripts/check_execution_boundary.py` reads that registry
together with the consumers' `allowed-tools:` and fails the build on an
undeclared grant, a declared grant its consumer does not carry, an unclassified
consumer, an `inside-boundary` row the boundary text above does not admit, or a
family wildcard the boundary admits only in part. So the paragraph above cannot
quietly stop being true — though what is checked is the list, not the boundary:
see `Residual risks`.

A check that is refused, or that cannot be run, is never silently skipped: where
no check of the plan ran at all it takes stage 4's fourth case, and where some
checks ran and others did not the finding is graded on the raw output of those
that ran, with the shortfall disclosed as stage 4's fourth case describes.

Stages 3 and 3.5 separate the actor from the verifier. `fix-auto` picks its own
checks and narrates its own result, so its report is advisory input to the
status rather than the status itself: the orchestrator executes the plan for the
alternative that was actually decided, logs the raw output, and only that output
decides the status — `✅ Fixed` on a pass, `⚠️ Partially Fixed` where a pinned
file changed observably and the output does not pass, and no `**Status:**` line
at all in the two cases stage 4 lists: no observable change followed the
dispatch, or no plan ran.

## Components

### Agent: `decision-analyst`

`plugins/code-review/agents/decision-analyst.md`

Receives exactly one `needs-decision` finding block. Reads the code the finding
points at and returns a rendered proposal. Performs no writes.

```yaml
tools: Read, Grep, Glob, Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git blame:*), Skill
disallowedTools: Edit, Write, NotebookEdit
```

The read-only property is grant-narrowed, not machine-proven. `Bash(git:*)`
would match `git checkout`, `git restore`, `git reset`, `git clean` and
`git commit` — exactly the writes this design forbids — so the grant is narrowed
to the four read-only subcommands the analyst needs, and `disallowedTools`
closes the edit tools. The narrowing is neither machine-enforced nor even
diagnosed: `_uses_colon_specifier`
(`scripts/check_agent_frontmatter.py:433-443`) inspects only the first
whitespace token of a specifier, so a two-word grant like `Bash(git log:*)`
reads as `git` and raises neither an error nor a warning. An over-broad
`Bash(...)` grant would fail no build and print no diagnostic at all, which
makes the conclusion stronger rather than weaker: this property rests entirely
on author and reviewer. Whether the two-word specifier is honoured at all is
unknown, and this spec states that plainly rather than assuming it: the form
has no precedent in any agent's `tools:` in this tree — the only agent-level
`Bash` grant is the single-token `Bash(git:*)` at
`plugins/code-review/agents/feedback-analyzer.md:4`, while two-word forms
appear only in command and skill `allowed-tools:`, which `CLAUDE.md` defines as
permission pre-approval rather than capability — and
`scripts/check_agent_frontmatter.py:78-80` calls the `Tool(cmd:*)` spelling
undocumented. If the resolver does not honour it, the entry falls back to base
`Bash` — which is not confined to git at all. On that branch the analyst holds
unrestricted shell: `rm`, `curl`, `tee`, `sh -c`, `python -c 'open(f,"w")'`.
`disallowedTools` closes none of it, because a `python -c` that writes a file is
not an `Edit` call; it names only `Edit`, `Write` and `NotebookEdit`. The
read-only property is then **absent, not degraded**: this is not a wider git
grant, it is no confinement at all. The fallback also reaches further than
`Bash`: the grant carries `Skill` with no
key narrowing which skills may be loaded, and per `CLAUDE.md` a skill's
`allowed-tools:` pre-approves permission prompts, so with seven of this plugin's
eleven skills carrying `Bash(...)` entries in theirs — between them
`Bash(python:*)`, `Bash(node:*)`, `Bash(npm:*)`, `Bash(go:*)`, `Bash(pip:*)`,
`Bash(xargs:*)`, `Bash(find:*)` and `Bash(cat:*)` — loading one converts
arbitrary execution from prompted into unprompted. Both consequences are
**strictly conditional on the fallback**, which is still unverified.
`Verification` step 6 probes which of the two it is, and `Residual risks`
carries the case where the grant turns out inert. Separating the analyst that reads from the `fix-auto`
that writes is what makes the decision gate real: the analyst cannot pre-empt
the user's choice because it cannot edit. Frontmatter keys stay within the
permitted set (the thirteen keys in `PERMITTED_KEYS`,
`scripts/check_agent_frontmatter.py:46-50`; this agent uses `name`,
`description`, `tools`, `disallowedTools`); `allowed-tools:` is not used, per
`CLAUDE.md`.

**Return contract.** The orchestrator renders the returned block without
re-reading the code — that is the point of the fan-out. Every field is advisory
LLM analysis rather than established fact, and `Findings` must carry, for every
claim, its evidence in one of two citable forms: the exact shell command as it
was run *and* that command's verbatim output, or — for evidence the analyst
gathered with its own tools — a `tool:` citation naming every parameter the
orchestrator must pass to reproduce the call, *and* that call's raw result
verbatim, never a paraphrase. The tool branch is held to "as it was run" exactly
as the shell branch is: `tool: Grep pattern=… path=… output_mode=… -n=…
glob=…`, `tool: Read path=… offset=… limit=…`, `tool: Glob pattern=… path=…`. A
tool name alone is neither form, and neither is a citation that omits an
output-determining parameter — a call re-run at the tool's defaults returns a
different shape, so the support test reads a supported candidate as a
discrepancy; such a citation is not re-runnable and its finding takes the
no-candidate path. The orchestrator re-runs both, because it holds the same
`Read`, `Grep` and `Glob` tools the analyst does: a tool citation is re-runnable
exactly as a shell citation is. The point of either is that the user judges the evidence and
not the assertion, and that the reject gate has something deterministic to
re-execute.

A `Verification Plan` whose checks merely restate the intended edit — asserting
that the edit was made rather than testing its effect — is not accepted, and
the test is mechanical: a plan is rejected when every one of its checks would
pass on an unedited tree, or would fail only because the edit's own text is
absent. A check that inspects the artifact's post-condition — that the referent
no longer appears anywhere in the tree, say — is accepted, and that is the form
the test takes for documentation drift, where the distinction otherwise
collapses. The test is not scoped to the analyst's return: the plan the
orchestrator derives for `other…` after the decision is held to it too, applied
by the orchestrator to its own checks before stage 3.5 runs them. A plan that
fails the test — returned or derived — is treated as no plan for that
alternative: stage 3.5 runs nothing for it and stage 4's fourth case applies. Every field is
required unless marked optional:

| Field | Content |
|---|---|
| `Target` | Real `path:line-range`, verified against the file, not copied from the report |
| `Findings` | What is actually in the tree. Every claim carries one of the two citable forms above — the exact command as run with that command's verbatim output, or a `tool: …` citation with that call's verbatim result — never a tool name alone, and every citation stays inside the grant the analyst actually holds. An empty result is cited as literally empty — the result side carrying no output at all and marked `(empty)`, a marker of emptiness rather than output text, never a tool's own rendering such as `(no matches)`, which the support test would try to match verbatim and never find: "`tool: Glob pattern=scripts/qa-run.sh path=.` → (empty); `git log --oneline --diff-filter=D -- scripts/qa-run.sh` → `9c6fc76 chore: drop the qa-run wrapper`; `tool: Grep pattern='scripts/qa-run\.sh' path=. output_mode=content -n=true` → the two output lines `docs/plugins/qa.md:88:Run scripts/qa-run.sh before opening a PR.` and `README.md:41:See scripts/qa-run.sh for the combined suite.`" |
| `Alternatives` | A and B, derived from `Drift-class`. `dead-reference` → remove the mention vs restore the referent. `decision` → the alternatives the Remediation names. If the Remediation names none → the fallback route. `mechanical`, an absent `Drift-class` field and any unrecognised value all route to that same fallback, since none of them names alternatives. On the fallback route A is the Remediation applied as written and B is a concrete alternative *direction* the analyst derives from the code — never the placeholder "resolve differently", which no fixer can act on — written to the same full, self-contained standard as A. Where the code supports no second direction the analyst can state, it returns A alone and says so: the field is then satisfied by that single alternative, and the sweep for that finding carries the three options `[A] [skip] [reject]`. The field is absent by construction on a non-documentation reinstatement: `Drift-class` is scoped to documentation findings, while `needs-decision` is set on any reinstated finding with `Location: —` whatever its category, and `fix-report.md:139` already renders the missing field as `[needs-decision: —]` — which is this spec's own headline case. Each alternative is written as a full, self-contained resolution sentence on exactly one physical line, with no embedded newline, dispatchable verbatim as `User decision:` — it names every file and line it touches and refers back neither to the Remediation nor to the other alternative, since the fixer sees neither and stage 3 forbids a bare label |
| `Recommendation` | A or B, with the reason |
| `Risk` | What the recommendation costs if it is the wrong call |
| `Code Preview` | Current and proposed code for the recommended alternative |
| `Verification Plan` | One plan per alternative: the checks that would confirm A, and separately the checks that would confirm B — never a single plan for the recommendation, since stage 3.5 runs the plan for whichever alternative was decided. Each check is written as `<check> → <expected result>`, on exactly one physical line, carrying no `; `, no ` → ` beyond its own separator and no embedded newline — one that would is rewritten or split before it is returned — and the expected result is stated in terms observable in that check's own raw output, since stage 3.5 decides a check on its logged output and never on exit status alone. Each soft check is marked `<check> → <expected result> (soft)` by the hard/soft test `Decision record` states beside the `**Verification:**` grammar, so stage 4 reads the marker instead of re-classifying the check text. A check is runnable when the orchestrator can execute it and log a result, a soft LLM re-read of prose included; a soft check's logged raw output is the verbatim excerpt the re-read quotes out of the file it inspected, given with the `path:line` it was read from, and it passes when that excerpt matches the recorded expected result — a re-read that logs a verdict rather than an excerpt has logged no result and is a check that cannot be run, and a pass resting on such a check is `advisory`, never `hard`. Read-only inspection — the `Read`, `Grep` and `Glob` tools plus the git subcommands `log`, `show`, `diff`, `blame` and `status`, and nothing else — is the whole of what is inside the boundary, and it alone needs no escalation. Everything else is outside it, **the project's declared test and build commands included**: their membership is read from the repository under review, the same trust domain as the report whose finding proposed the check, and a declared name says nothing about what runs, since `npm test` executes whatever `package.json` `scripts.test` currently holds. Both terms are as `The flow` defines them below its diagram. A check outside the boundary is still permitted — proposed where the finding calls for one — but it is flagged as needing the user's explicit approval before it runs, never as pre-approved, and its exact command text is given so the sweep's approval call can name what it is asking about; approval is taken in an `AskUserQuestion` call, and a platform permission prompt, denied or errored, makes the check one that cannot be run whether or not the sweep had approved it. A refused or unrunnable check is never silently skipped: where no check of the plan ran at all, stage 4's fourth case applies; where some ran and some did not, the finding is graded on the raw output of those that ran and the shortfall is disclosed as stage 4's fourth case describes. For `other…` no analyst plan can exist, so the orchestrator derives the checks after the decision and records them as post-decision. Stage 2 persists the decided plan on the `**Verification-plan:**` line, so the replay path runs it rather than re-deriving one; where no check of any kind ran, stage 4's fourth case applies |
| `Rejection candidate` | Optional. Present when the code contradicts the finding — a `dead-reference` whose referent exists under another name. Carries the reason on a single line with no embedded newline, since it prefills the `<reason>` of a status line every consumer resolves line-wise, and the same two-form citation requirement applies to the evidence backing it — the empty-result rule of `Findings` included: the sweep re-runs exactly those commands and tool calls before offering `reject` and grades them by the support test `Decision outcomes` states, so a candidate backed by a tool name rather than by a command-plus-output or a `tool: …` citation is not re-runnable — and neither is one whose citation the sweep's read-only boundary refuses to execute — and its finding falls to the no-candidate path |

### Skill: `decision-gate`

`plugins/code-review/skills/decision-gate/SKILL.md`

Single source of truth for the decision stage, loaded in full by `/fix-report`
and `/fix-all`, and by `/fix` for the `Alternatives:` render format only:
stage 0's location pre-check — its usability rule's three conjuncts, parse,
containment and existence — fan-out rules and batch size, the nonce-bound
untrusted-data framing a feedback-origin block is dispatched under, the analyst
return contract, the decision sweep and its five outcomes — including the reject
evidence gate and the read-only execution boundary its re-run runs under — the
dispatch contract, stage 3.5's orchestrator-run verification under that same
boundary, and the decision record. It carries stage 2's render as well, so that
every entry point renders one gate: always rendered are `Target`, the
`**Source:**` line where the block carries one, marked as feedback-origin,
`Recommendation` with its reason, `Risk`, both `Alternatives` in full,
`Code Preview` and any `**Decision-retired:**` lines; held back unless the user
asks are the verbatim command and tool output backing `Findings` — the claims
themselves are rendered — and both `Verification Plan`s; always rendered and
never held back are the re-run raw output of a `Rejection candidate`'s
citations and the recorded/fresh side by side where that re-run diverges, since
the reject gate exists so that the user judges that evidence. What the skill *runs* differs by command: in
`/fix-all`'s Step 5 it runs stages 0 through 3.5, while in `/fix-report` it runs
stages 0-2 in the Step 2.4 slot and hands the decided findings back to Step 3,
which dispatches them, after which stage 3.5's verification is run over the
decided findings only. Stage 4's **grading** is the skill's, and the skill
declares itself the single authority for it — the two tree observations, the
expected set, the four ordered cases and the `**Status:**`, `**Verification:**`
and attempt-entry writes each case makes, identical for both entry points and
for the replay path. Only the **mechanical** write is command-owned: Step 4.1's
insert-after-heading `Edit` recipe and Step 4.1.5's positional re-read, each
command running them over its own batch with its own `status_write_failures`
list. *Which* status that write carries — and whether any status is written at
all — is decided in the skill, which is why a command restates neither the four
cases nor the observations. A skill
rather than a command — it adds no entry point, and the
"doctrine in a skill" pattern is established in this plugin by
`verdict-protocol`, `docs-fact-registry` and `finding-falsification`.

### Command changes

| File | Change |
|---|---|
| `commands/fix-report.md` | Step 2.2: `needs-decision` findings are partitioned onto their own labelled leading page(s) of the checklist, ahead of the severity-sorted `auto` pages. The four-option ceiling applies to every page, not only to the needs-decision ones: the checklist's usual 4 issues per page (`fix-report.md:129`) is deliverable only on a page with nothing appended to it, which is only ever the final page, and any page carrying the appended "Skip remaining" item (`:158-161`) holds 3 — needs-decision or `auto` alike. "Skip remaining" is appended to every needs-decision page that is followed by another page, and this change guarantees one follows whenever any `auto` finding survives the Step 1.3 filter, so such a needs-decision page holds 3; more than 3 needs-decision findings therefore occupy successive leading pages, all of them ahead of the first `auto` page. On a non-final needs-decision page that item advances to the next needs-decision page; only on the last one does it advance to the first `auto` page — so it is relabelled for what it actually does there, "Skip these 3 — next decision page (`<n>` of `<N>` shown)" on a non-final needs-decision page and "Skip these 3 — on to the auto fixes" on the last, never the imported description "Proceed with issues selected so far, skip remaining pages" (`fix-report.md:158-161`, routed to Step 3 at `:167`), which is false on a page that pages forward. The checklist has no early exit from the needs-decision pages at all: reaching the first `auto` page costs ⌈K/3⌉ answered pages for K needs-decision findings, and the four-option ceiling leaves no slot for a skip-all item beside the three issues. Step 2.2 states that count on the first needs-decision page. Where no `auto` finding survives the filter there is no page to advance to: the last needs-decision page is then the final page — nothing is appended to it, it holds 4, and selection ends when it is answered. It can therefore never leave a needs-decision finding undisplayed. Step 2.4 is replaced by an invocation of `decision-gate`, which runs stages 0-2 in that slot and returns the decided findings to Step 3 rather than dispatching them itself: Step 3 dispatches the decided and the selected `auto` findings in one sequential batch, decided first. Stage 3.5's orchestrator-run verification applies to the decided findings only — the `auto` findings keep today's path, where `fix-auto`'s own verdict is collected — and Step 4.1 / 4.1.5 then runs once over the whole batch, so the gate performs no write-back in `/fix-report`. `/fix-report` had no Step 4.1.5 before this change: Step 4.1 (`fix-report.md:222`) ran straight into Step 4.2 (`:244`) and the command ended there. It has one now, mirroring `fix-all.md:362-411` — re-read the `source_file`, collect `{issue_id, source_file, reason}` into `status_write_failures`, and render that list in Step 4.2 — and it verifies **three write kinds, not one**, over every finding the batch wrote back for: the `**Status:**` line, confirmed as the next non-blank line below the issue heading; the attempt entry appended to the block's live `**Decision:**` line, whose absence is recorded with reason `attempt-entry-missing`; and the `**Verification:**` line, located by its key wherever in the block it sits, whose absence is recorded with reason `verification-line-missing`. Two of stage 4's four cases write no `**Status:**` line and append the attempt entry instead, so a finding graded into one of those still received a write and is in the iteration set; the `**Verification:**` check runs over the whole decided partition, since both write cases carry that line, while the selected `auto` findings carry no decision record and are outside it. A rejected finding is outside all three — `reject` never dispatches and carries no `**Verification:**` line at all, so its missing line is not a failure. Step 4.2 also gains a decision-stage surface it does not have: its template (`| # | Issue | Status |` rows plus the `**Fixed:** N | **Partially Fixed:** N | **Failed:** N` counts and the reports-updated list) is closed and holds no slot for the disclosures the decision stage raises, so after Step 4.1 / 4.1.5 `/fix-report` prints a decision-stage summary block carrying the same rows `/fix-all`'s Step 5 block carries, and it names all eight: stage 0's Failed findings, an unverified rejection, advisory verification, `verification: unavailable`, the partial-coverage warning, out-of-scope writes, unpinned findings, and the `stalled — no progress` heading |
| `commands/fix-all.md` | New Step 5 after Step 4.2: if `needs_decision` is non-empty, ask whether to resolve those *N* findings now, naming the count; on yes, run `decision-gate`, then re-run the Step 4.1 / 4.1.5 write-and-verify procedure over the decision batch — Steps 4.1 / 4.1.5 have already run and closed their progress task by then, so Step 5 owns the write-back for its own findings, and Step 4.1.5's re-run verifies over that batch the same three write kinds the `/fix-report` row names: the `**Status:**` line, the attempt entry (`attempt-entry-missing`) and the `**Verification:**` line (`verification-line-missing`), with rejected findings outside the check — and append a decision-stage summary block after the one Step 4.2 printed. Adds a fifth row to the progress-task table under "MANDATORY FIRST STEP". Step 4.2 is unchanged. Step 2.2.5 changes in one respect: its zero-auto-issues edge case no longer aborts — when the fix list is empty and `needs_decision` is non-empty, Steps 3–4 are skipped and control goes straight to Step 5's offer, which replaces the abort message pointing at `/fix-report` or `/fix <ID>`. On that zero-auto path the two claims above do not hold, and Step 5 compensates: Step 4.2 never printed the "Requires user decision" list, so Step 5 prints it itself before asking and its summary block follows nothing; and Steps 3–4 never ran, so Step 5 closes their progress rows as well as its own — without that, removing the abort leaves them open, since today only the abort helper closes them |
| `commands/fix.md` | Phase 3 stops restating the `Alternatives:` format and defers to `decision-gate`. Render behaviour identical; the goal is that all three entry points render one format. Not otherwise unchanged, though: `/fix` also takes on the two read-side duties `Status vocabulary extension` assigns it — the Phase 0 abort on a resolved block already carrying `**Status:** 🚫 Rejected`, and the Phase 8 rule against writing a second `**Status:**` line over an existing one |

**Ordering inside `/fix-report`.** Every decision is collected before any
`fix-auto` is dispatched, and the `auto` findings selected from the later pages
are fixed in the same batch as the decided ones. This preserves today's ordering
(Step 2.4 already runs before Step 3) and matches the intent: decide everything,
then fix in bulk. The one documented exception is a `**Decision-pin:**` mismatch
found immediately before dispatch: that finding is set aside, the remaining
dispatches of the batch complete, and the set-aside findings are re-analysed and
re-swept as a second pass before their own dispatch — so the re-ask never
interrupts a batch in flight. `/fix-all` differs by construction — its auto batch
has already run by the time Step 5 offers the decision stage.

## Decision outcomes

The sweep offers five outcomes per finding, collected with `AskUserQuestion` and
with nothing else: it is the only construct whose answer provably originates
with the user. That rule covers every user answer the decision stage acts on —
the sweep itself, stage 0's asks for a missing `path:line`, the `other…`
restatement confirmation, the reject reason, and stage 3.5's approval of a check
outside the execution boundary. The render is explicit: the call carries four
options, `[A] [B] [skip] [reject]`, and `other…` is the tool's built-in
free-form answer rather than a fifth option — the same four-option ceiling that
sets the checklist's page capacity. Where the analyst could derive no second
alternative and returned A alone, the call carries the three options
`[A] [skip] [reject]`. The orchestrator never supplies a decision on the user's behalf
and never infers one from the analyst's recommendation. If `AskUserQuestion` is
unavailable or errors, the decision stage aborts immediately: no dispatch,
and no further `**Decision:**` line. Decisions already written stay in the
report and are replayed next run, and the abort reports how many findings were
left undecided. At stage 3.5 the same unavailability is not an abort but a
refusal to run: the escalation call — which shows the exact command text and
asks for approval to run it — then counts as a check that cannot be run, and the
finding takes stage 4's fourth case.

The outcomes:

| Outcome | Effect |
|---|---|
| **A** / **B** | Dispatch `fix-auto` with `User decision: <resolution>` — the chosen alternative's full resolution text, never the bare label |
| **other…** | User supplies a resolution in their own words. The `Target` is pinned either way, but files the answer names only inside the alternative the user gestured at are not, so before dispatch the orchestrator restates the answer as a full, self-contained resolution naming every file and line it touches, shows the restatement for confirmation in the same sweep, and dispatches only the confirmed text. An answer that cannot be restated self-containedly is asked once more, bounded exactly as stage 0's retry is: the re-ask quotes the restatement rule back to the user — name every file and line the resolution touches, refer back neither to the Remediation nor to the other alternative — and a second failure returns the finding to the sweep unresolved, with its four options intact and `reject` among them, writing nothing at all, exactly as `skip` does |
| **skip** | No dispatch, no status. The finding reappears on the next run |
| **reject** | No dispatch. `**Status:** 🚫 Rejected (YYYY-MM-DD) — <reason>` written to the source report |

A `**Decision:**` line is written only for **A**, **B** and **other…**. `skip`
writes nothing at all — that is what makes the finding reappear next run — and
`reject` writes only its `**Status:**` line, never a `**Decision:**` line.

`reject` is new. Without it, a finding the analyst has shown to be wrong can only
be skipped, and a skipped finding returns on every subsequent run forever — the
same friction this spec exists to remove, displaced one level. `reject` is a
user decision, never the analyst's: a `Rejection candidate` in the returned
block surfaces the option and its reason, and the user chooses. That reason is
also the source of the `<reason>` in the status line — prefilled from the
analyst's `Rejection candidate` and confirmed by the user before it is written.
When the analyst returned no candidate, the sweep prompts for a one-line reason
and does not accept an empty one: a rejection is terminal, so it is never
recorded without a stated ground. That prompt is bounded exactly as stage 0's
retry is: an empty reason is re-asked once, and a second empty answer returns
the finding to the sweep with its four options intact, `reject` included,
writing nothing.

The evidence gate is scoped to the candidate, not to `reject` as such. Where the
block carries a `Rejection candidate`, the orchestrator re-runs the exact
commands and tool calls cited for it — under the read-only boundary stage 2
states — and shows the raw output before the choice is offered. The support test
is stated once here, and stage 2 and `Oracle` refer to it rather than restating
it: the candidate is supported iff every re-run exits without error, and its
fresh output contains, verbatim, every non-empty line of the output the analyst
recorded for that citation; where the analyst recorded an empty result, the
fresh call must return an empty result too — an empty recorded result is matched
by emptiness, never by containment. On any other result `reject` is withheld,
the call carries the remaining options — `[A] [B] [skip]`, or `[A] [skip]`
where the analyst returned A alone — and the recorded and the fresh
output are shown side by side as the discrepancy.
A citation the boundary refuses to execute is not re-runnable either, and its
finding takes the no-candidate path. Where there is no candidate — including the
degraded path, where the analyst failed outright and no cited command exists —
there is nothing to re-run: `reject` stays available, gated only on the user's
non-empty reason, and the run summary marks such a rejection `unverified`.

## Status vocabulary extension

`🚫 Rejected` joins `✅ Fixed` and `⚠️ Partially Fixed`.

The written form is `**Status:** <icon> <text> (YYYY-MM-DD)[ — <reason>]`. The
` — <reason>` tail arrives with this change and is permitted only for
`🚫 Rejected`; no other status value carries one. `<reason>` is a single line
with no embedded newline whatever its source: the sweep prompts for a one-line
reason where there is no candidate, and collapses a multi-line prefill from a
`Rejection candidate` to one line before writing it, since a status line that
splits breaks every consumer that resolves it line-wise. Consumers that read a
line
whose tail they do not control therefore match the status value by prefix, not
by whole-line equality: the two Step 1.3 filters (`fix-report.md`,
`fix-all.md`), `/fix` Phase 0's abort, and `loop.md`'s duty to leave a
`🚫 Rejected` line untouched all resolve a line that may carry a reason, and a
whole-line match fails on every one of them. Step 4.1.5's verify is unaffected
and stays exact: `fix-all.md:370` checks a line the loop has just written
itself, and the loop never writes a reason onto `✅ Fixed`.

**`Location:` gains an extended written form.** Stage 2 rewrites the field in
place as ``**Location:** `path:line` (was: `original`)``, so the required,
shared `**Location:**` field now has two written forms and every consumer of it
must read both. The read rule has two clauses: take the first backticked token
as the location and ignore any trailing parenthetical; and where the line
carries no backticked token at all — a legacy `**Location:** src/foo.ts:12`,
which the loop never writes but every consumer still meets — take the first
whitespace-delimited token after the field name, so that an unbackticked
`path:line` stays usable instead of reading as location-less at every site,
`loop.md:611` included, which would silently drop such an issue. Under either
clause a value of `—`, `unknown:0`, or anything that does not parse as
`path:line` or `path:line-range` is location-less. The consumers are
`fix-auto.md`'s Phase 1, `fix.md`'s Phase 1, `fix-all.md`'s Step 2.4 render,
the `decision-gate` skill's own stage 0 location pre-check,
`plugins/qa/commands/loop.md`'s two read sites — `loop.md:611`, which drops any
issue whose Location is `unknown:0` or missing, and `loop.md:691`, which tells
`fix-auto` to return Failed on the same —
`plugins/qa/skills/report-format/SKILL.md`, which documents the field, and
`docs/plugins/code-review.md`. `fix.md`'s usability test needs the rule
spelled out: a `—` inside the `(was: …)` tail is part of the reviewer's
original inline and never the location, so a test that scans the whole line for
`—` would read a perfectly usable location as missing. `loop.md`'s two sites
need it for the same reason and against a different token: stage 2 preserves the
original `unknown:0` inside the `(was: …)` tail, so a whole-line test reads a
repaired finding as location-less and silently drops it.

Consumers to update:

- `plugins/code-review/commands/fix-report.md` — Step 1.3 filter, and Step 1.5's
  all-resolved edge case: with `🚫 Rejected` in the vocabulary the presence of a
  `**Status:**` field no longer implies the finding was fixed, so the message
  distinguishes fixed from rejected
- `plugins/code-review/commands/fix-all.md` — Step 1.3 filter, and Step 1.5's
  all-resolved edge case, whose message likewise distinguishes fixed from
  rejected
- `plugins/code-review/commands/fix.md` — a read-side duty, not a status
  enumeration: Phase 0 aborts when the block it resolved by ID already carries
  `**Status:** 🚫 Rejected`, and Phase 8 never writes a second `**Status:**`
  line over an existing one. `/fix` has no Step 1.3 filter and edits in-thread
  rather than dispatching `fix-auto`, so neither guard the other two entry
  points rely on covers it
- `plugins/code-review/agents/fix-auto.md` — a read-side duty only: Phase 1
  aborts with an explicit error if the dispatched block already carries
  `**Status:** 🚫 Rejected`. That is the reviewer-authored `**Status:**` line —
  the one the block already carried when the run began, which the dispatch-copy
  rule keeps in the dispatched copy; the lines the decision stage itself writes
  (`**Verification-plan:**`, `**Decision-pin:**`, `**Dispatch:**`,
  `**Verification:**`, `**Decision-retired:**`, any `**Status:**` line this loop
  wrote, and the bookkeeping half of `**Decision:**`) are stripped from that copy
  and never reach the fixer, while the rewritten `**Location:**` line travels
  with it. Its Phase 6 verdict vocabulary (Fixed / Partially
  Fixed / Failed) is unchanged, because `🚫 Rejected` is a report status and
  never a fixer verdict — it would be a verdict the fixer can never emit and no
  collector maps. That abort returns before Phase 6, so it carries none of the
  three values the callers branch on: the dispatching command collects it as
  **Failed** — no `**Status:**` line is written, since the block already carries
  the rejected one, and the finding is listed under the run's failed dispatches
  with the abort reason
- `plugins/qa/skills/report-format/SKILL.md` — two duties, not one. It is the
  documented status contract, so it registers `🚫 Rejected` and the
  ` — <reason>` tail beside `✅ Fixed` and `⚠️ Partially Fixed`, together with
  the rule that consumers match the status value by prefix rather than by
  whole-line equality, since a value read off a line whose tail the reader does
  not control is unmatchable whole-line; and it registers
  the extended `Location:` form with both clauses of its read rule — first
  backticked token, trailing parenthetical ignored; first whitespace-delimited
  token after the field name where the line carries no backticked token —
  stating that the loop itself always writes the backticked form and that the
  second clause exists for legacy lines. And it registers the
  loop-written optional fields of the finding-block schema both plugins share —
  `**Decision:**`, `**Decision-retired:**`, `**Verification-plan:**`,
  `**Decision-pin:**`, `**Dispatch:**` and `**Verification:**` — since
  `/fix-report` writes them into QA reports by construction
- `plugins/qa/commands/loop.md` — two duties around `🚫 Rejected`: a rejected
  issue must not re-enter the fix set, and Step 4.1's in-place Status update
  (`loop.md:902-907`) must leave a `🚫 Rejected` line untouched. A further duty
  arrives with the decision record: the reuse and adopt paths carry over
  `**Decision:**`, `**Decision-retired:**`, `**Verification-plan:**`,
  `**Decision-pin:**`, `**Dispatch:**` and `**Verification:**` lines, and the
  rewritten `**Location:**` line with its `(was: …)` parenthetical, exactly as
  they already carry over `**Status:**` lines, or a re-render drops the decision
  record and the corrected address the replay path depends on. And a third,
  because `/qa:loop` is itself a dispatcher of the shared finding block: its
  Step 3c forwards "the full issue block from the report, including all fields"
  to `fix-auto` (`loop.md:684`), so it applies stage 3's dispatch-copy rule to
  the same closed list — without it, a decided-but-unfixed finding hands the
  fixer the checks stage 3.5 grades it with
- `docs/plugins/code-review.md` — user-facing status list, the extended
  `Location:` form, plus the loop-written finding-block fields `**Decision:**`,
  `**Decision-retired:**`, `**Verification-plan:**`, `**Decision-pin:**`,
  `**Dispatch:**` and `**Verification:**`

`/qa:loop` is a *writer* of `**Status:**`, not only a reader: `loop.md:902-907`
(Step 4.1) inserts `✅ Fixed` for every scenario that passes in the final run and
updates an existing Status line in place, and the sidecar binds scenario →
[QA-IDs], so a sibling issue passing on the same scenario would overwrite a
`🚫 Rejected` line and its reason. Both duties are therefore required: a rejected
issue never re-enters the fix set, **and** the Step 4.1 in-place update leaves a
`🚫 Rejected` line as it found it. Its existing rule that it never writes
`Partially Fixed` is unchanged. `code-review`'s own Step 4.1 needs no such
write-protection: a rejected finding is never dispatched in the same run, and
later runs are guarded per entry point — `/fix-report` and `/fix-all` exclude it
at their Step 1.3 filter, while `/fix <ID>` has no such filter (Phase 0 resolves
by ID) and is guarded instead by its own Phase 0 abort and its Phase 8
second-Status-line rule. Both guards arrive with 2.0.0: a 1.17.3 filter does
not know the value, so `/fix-report` re-offers the finding and can dispatch it,
and a 1.17.3 `/fix` re-fixes it in-thread and leaves the block carrying two
`**Status:**` lines (see `Delivery`).

## Decision record

Each decision is written to its source report immediately, before dispatch, as a
`**Decision:**` line inside the finding block. The line has a delimited grammar,
so the dispatchable text can be extracted without parsing prose:

```
**Decision:** <label> — <resolution text> [<who>, <YYYY-MM-DD>; attempt N: <outcome>…]
```

`<label>` is exactly one of `A`, `B` or `other`, and every written line carries
one, so the first ` — ` is always the grammar's delimiter.
`<resolution text>` is the same full, self-contained text stage 3 dispatches,
and it is single-line: it carries no embedded newline, on a `**Decision:**` line
and on a `**Decision-retired:**` line alike. That is one instance of a general
invariant every loop-written field obeys — `**Decision:**`,
`**Decision-retired:**`, `**Verification-plan:**`, `**Decision-pin:**`,
`**Dispatch:**`, `**Verification:**`, `**Location:**` and `**Status:**` each
occupy exactly one physical line, with no continuation line of any kind, so the
prefix-keyed strip stage 3 applies to the dispatched copy and the `grep -v` of
the pin pipeline both remove the field whole. A continuation line would carry no
`**<Field>:**` prefix and would survive both, reaching the fixer with the checks
stage 3.5 grades it by; content that will not fit on one line is rewritten or
split before it is written, never wrapped.
The bracketed field at the end carries the bookkeeping — the provenance marker
recording that a user decided it and when, then one entry per dispatch attempt,
entries separated by `; ` — and is never dispatched. `<outcome>` is exactly one
of `failed`, `interrupted, unverified` or `dispatched, unverified`:

```
### [MEDIUM] DOC-004: Doc cites a removed script
**Decision:** A — delete the line citing scripts/qa-run.sh at docs/plugins/qa.md:88 and the line citing scripts/qa-run.sh at README.md:41 [user, 2026-08-27; attempt 1: failed]
```

**A**, **B** and **other…** write this line. `skip` writes nothing. A rejected
finding carries the `**Status:** 🚫 Rejected` line alone and no `**Decision:**`
line — for a rejection the status *is* the record.

**One of each, replaced in place.** A finding block carries at most one live
`**Decision:**` line, and at most one each of `**Verification-plan:**`,
`**Decision-pin:**`, `**Dispatch:**`, `**Verification:**` and `**Status:**`.
When a fresh decision is taken for a block that already carries one — after a
retirement, or after a pin mismatch sent the finding back through the analyst
and the sweep — the new lines overwrite the old ones in place, exactly as
`**Status:**` is updated in place, rather than accumulating beside them.
Nothing else would be safe: the replay check reads "a `**Decision:**` line" in
the singular, and a `**Verification-plan:**` left over from a superseded
decision would be executed at stage 3.5 against a decision it was never derived
for. The attempt counter restarts with the new line — the counter belongs to
the decision, not to the finding — and the superseded attempt history is not
lost with it: it survives as the `**Decision-retired:**` line described below.
The slots have an order as well as a count. `**Status:**` remains the first
non-blank line under the finding's heading, and every other loop-written line —
`**Decision:**`, `**Decision-retired:**`, `**Verification-plan:**`,
`**Decision-pin:**`, `**Dispatch:**` and `**Verification:**` — is written below
that slot, never above it. That is what keeps Step 4.1.5's positional verify
("the next non-blank line below the heading") exact however many decision lines
the block has accumulated, and both stage 2 and stage 4 write a status with the
existing `old_string = "<heading>\n"` recipe, so a status write inserts
immediately under the heading and above an existing decision cluster rather than
after it.

**The verification plan is persisted with the decision.** Stage 2 writes a
companion `**Verification-plan:**` line beside the `**Decision:**` line, in the
same write, carrying the checks for the alternative actually decided — the
analyst's plan for A or for B, and for `other…` the checks the orchestrator
derives after the decision:

```
**Verification-plan:** <check> → <expected>[ (soft)]; <check> → <expected>
```

Each check carries the expected result recorded with it, stated in terms
observable in that check's own raw output, since stage 3.5 decides a check on
its logged output rather than on its exit status. Checks are separated by `; `,
and the grammar of a check is closed on every separator it could collide with:
no check carries a `; `, a ` → ` beyond its own separator, or an embedded
newline — one that would is rewritten or split by the analyst before it is
returned, exactly as the ` — ` on the `**Decision:**` line is — so stage 3.5
splits the line on `; `, splits each resulting check on its first ` → `, and
applies the execution boundary to each check whole. A check the analyst
classified soft carries the marker `(soft)` after its expected result, and
stage 4 reads that marker rather than re-classifying the check text.

Stage 3.5 executes that persisted plan, so the replay path — which skips
stages 0-2 and therefore never sees the analyst's return block — still verifies
against the plan its decision was made with, instead of falling into stage 4's
fourth case for want of one. The reasoning is the one already recorded for
`**Location:**`: persisting the substitution rather than patching the dispatched
copy alone is what keeps the replay path working, and what is not written to the
report does not survive the run that derived it.

**How the verification was obtained is persisted too.** The status grammar
permits a ` — <tail>` only for `🚫 Rejected`, so a qualifier cannot ride on a
`✅ Fixed` line, and the run summary does not survive the session that printed
it. A fourth loop-written line therefore records it, written in the same write
as the `**Status:**` line — and, for the two cases that write no status, in the
write that appends the attempt entry:

```
**Verification:** hard|advisory|unavailable — <checks run>[; <N> not run: <check text>]
```

A single check is *hard* when its pass is decided by matching the expected
result against output a tool or command produced, and *soft* when its pass rests
on a model's judgment of prose; the analyst marks each soft check `(soft)` on
the `**Verification-plan:**` line and stage 4 reads that marker rather than
re-classifying the check text, since the replay path never sees the analyst's
return block and has only the persisted line to classify from. The field's value
follows: `hard` where every check of the decided plan ran and produced
observable output; `advisory` where the pass rests on an LLM re-read of prose,
or where any check of the decided plan was refused or unrunnable — the softest
check the pass depends on, and any shortfall in coverage, both set the value, so
three executable checks one of which was refused are `advisory` however hard the
two that ran were; and `unavailable` where no check of any kind ran. The
`; <N> not run: <check text>` suffix is a suffix of this field and never a check
separator: it appears at most once, after the `<checks run>` list, and nothing
after it is read as a further check that ran. A rejection
carries no `**Verification:**` line at all: it persists nothing beyond the
`— <reason>` tail, and the run summary stays the sole carrier of an unverified
rejection. Without this line the softness of an advisory `✅ Fixed` and the
`verification: unavailable` note both evaporate with the session, leaving a
status no later reader can tell apart from a hard-verified one.

If a run dies while dispatching the seventh of eleven fixes, all eleven
decisions already made survive — every decision is collected before any fixer
runs — and the next run does not re-ask. A resumed run dispatches the text
between the first ` — ` and the final ` [`, verbatim, as
`User decision: <resolution>`; the bracketed field is never part of the payload,
so an em dash inside the resolution text is harmless. Inline rather than a
sidecar: `code-review` has no sidecar concept (`superutils` does), while
`**Status:**` lines already use exactly this machinery and produce readable
diffs.

**A decision records its dispatch outcome, and is retired after two attempts.**
A Failed fix writes no `**Status:**` line (`fix-all.md:347`), so the finding
reappears next run — and a stored decision that suppressed the re-ask would send
the identical resolution to the identical fixer, to fail identically, forever,
with `reject` unreachable behind it. The decision line therefore carries the
outcome of each attempt (`attempt 1: failed`), and after two recorded attempt
entries on the same decision — `failed`, `interrupted, unverified` and
`dispatched, unverified` all count, since each is a dispatch that ended without
a written status — the decision is retired: the line is rewritten in place from
`**Decision:**` to `**Decision-retired:**` with its attempt entries intact, it
no longer suppresses the re-ask, the finding re-opens for a fresh analyst run
and a fresh sweep, and every outcome including `reject` is available again.
Retiring by rewrite rather than by deletion is what keeps the history that the
at-most-one rule would otherwise erase: a block may carry any number of
`**Decision-retired:**` lines beside at most one live `**Decision:**` line, and
the replay check reads the live one alone. The sweep renders the retired lines
with the fresh proposal, so the user decides against what has already been
tried instead of re-choosing it blind. A finding reaching its *second*
retirement is not re-analysed at all: the run reports it under a
`stalled — no progress` heading naming both retired resolutions, and offers
`reject` with that history shown — otherwise a resolution that can never land
cycles forever and no run ever says so. Every stage 4 case that writes no
`**Status:**` line appends an entry, so the counter cannot freeze and the escape
to `reject` stays reachable. Failed attempts are reported under their own
heading, never folded into the fixed set.

**A decision is pinned to the state it was made against.** Within one run all
analysis happens in stage 1 and all edits in stage 3, so an earlier `fix-auto`
can edit the file a later decision was derived from — and the example above
embeds a second file and line (`README.md:41`) that is handed to the fixer as
authoritative. A companion `**Decision-pin:**` line records two things: the
sha256 of the finding's own block with the loop-written lines excluded — the
`**Decision:**`, `**Decision-retired:**`, `**Verification-plan:**`,
`**Decision-pin:**`, `**Dispatch:**`, `**Verification:**`, `**Location:**`
and `**Status:**` lines — and one hash per pinned file. The list is closed, so
it must name every line the loop writes. `**Dispatch:**` is on it because
stage 3 writes that marker into the block before each fixer call: were it
excluded from the exclusion list, the block hash taken at decision time could
never match again once a finding had been dispatched, and the pre-dispatch
comparison would mismatch on every resume — breaking "the next run does not
re-ask", the "dispatched, outcome unknown" resume path and the retirement
counter alike. `**Location:**` is on
that list because stage 2 rewrites it too, and every hash is computed after
stage 2's writes have been applied, over the block as it then stands. The report
file's own hash is never pinned: stages 2 and 4 rewrite the report by design, so
a whole-file pin would mismatch on every finding but the last, and it would be
self-referential besides, since the pin line lives in the file it would hash.

The line has a written form of its own:

```
**Decision-pin:** block=<sha256> | <path>=<pin-value>[:edit|:ref] | <path>=<pin-value>[:edit|:ref]
```

`<pin-value>` is one of exactly three forms: a **blob hash** from
`git hash-object`; **`absent`**, written where the path does not exist in the
working tree; or **`unpinnable`**, written where the path was rejected by the
sanitisation rule below. The three are never written interchangeably — which one
is written when, and how each is read, is stated in the paragraphs that follow.
`plugins/qa/skills/report-format/SKILL.md` carries this grammar byte-identically
and refers here for that assignment, so the two copies are one line of text in
two files rather than two statements of the rule.

The brackets mark an alternation and not an option: every pinned entry carries
exactly one of the two role markers.

The block hash covers the finding block as Step 1.2 delimits it, with those
loop-written lines removed. The pinned files follow in resolution-text order,
the `Target` first. A pinned path that does not exist in the working tree is
recorded as `<path>=absent` rather than hashed: `git hash-object` errors on a
missing path, and "restore the referent" names one by construction, so hashing
it would leave the pin unwritable and stage 4 would read a correct restore as
no edit at all. `absent` → present and present → `absent` are both observable
changes, exactly as a changed hash is. `absent` is a **recorded observation** —
the command ran and the path was not there — and so is never interchangeable
with the `unpinnable` state below, which records that no observation was taken
at all. The pinned file set is that `Target`
plus every
`path[:line]` token appearing in the resolution text. A path token is recognised
syntactically and never by testing the filesystem — the `absent` rule exists
precisely to pin paths that do not exist: a whitespace-delimited token holding
at least one `/` or ending in a file extension, optionally followed by `:<line>`
or `:<line>-<line>`, with trailing sentence punctuation stripped. Each entry
carries its role, because one list serves two tests with opposite membership
needs: `:edit` for a path the resolution says it changes, `:ref` for one it
names only as a referent — the canonical resolution above names
`scripts/qa-run.sh` as a removed referent, and nobody undertook to edit it. The
pre-dispatch pin comparison covers both roles, since an edit to a referent
invalidates the decision as surely as an edit to a target; stage 4's expected
set is the `:edit` entries alone — and never the `unpinnable` entries, even when
marked `:edit` — so an `absent` → present flip in a `:ref` path caused by
anything other than the dispatch can never write a terminal
`⚠️ Partially Fixed` over a no-op dispatch. A well-formed resolution
leaves nothing to resolve — the `Alternatives` contract requires each
alternative to name every file and line it touches, which is why the canonical
example above spells out both paths — so the deictic fallback covers a contract
violation rather than an expected form: a resolution that slipped through
carrying a deictic reference ("remove the mention **here**") resolves that
reference to the `Target` instead of pinning nothing, marked `:edit`.

The hashes are hashes of working-tree content, never commit ids: `Oracle`
records that a fix lands as an uncommitted diff, so a commit pin cannot observe
the very event the pin exists to detect. The mechanisms are named rather than
left to the implementer: `shasum -a 256` over the block excerpt — falling back
to `sha256sum` where `shasum` is absent, as it is on many Linux images, since it
is perl-provided — and `git hash-object` over each pinned file as it stands in
the working tree. The block excerpt is never retyped from context, which is what
would make a later session's re-derivation approximate: it is cut from the
report on disk by a deterministic command over the line range Step 1.2
delimits — `head -n <last> -- ./<report> | tail -n +<first>`, byte-identical to
the `sed -n '<first>,<last>p'` slice it replaces — piped through a `grep -v`
that drops the loop-written lines by their `**<Field>:**` prefixes, and piped
straight to the hasher, in one pipeline with nothing in between. **The cut uses
`head` and `tail`, and that is a security property rather than a stylistic
one:** these commands run under a pre-approved `Bash(...)` grant, and prefix
matching grants the whole tool, so `sed` would carry `sed -i` and, on GNU `sed`,
the `e` command and the `s///e` flag — an in-place write and a shell escape
inside a grant whose pipeline only ever reads. Neither `head` nor `tail` has a
write mode. Nor is a `Read` plus in-model line slicing a substitute: it would
route the excerpt through the model and break the never-retyped property this
same paragraph rests on. The comparison
is byte-exact, so the canonicalisation is stated too: trailing whitespace is
stripped from every line and the excerpt ends with exactly one trailing newline,
at pin time and at comparison time alike.

**Sanitisation, because both extractions build a command around a token the run
did not author.** The pinned path comes from the resolution text and the
`<report>` operand from the report file the run was handed, and the recognition
rule above is deliberately syntactic and tests nothing, so absent this rule a
token reaches the shell exactly as the document wrote it. The rule therefore
covers **every document- or tree-derived token entering a constructed
command** — the pinned operand of `git hash-object` and the `<report>` operand
of the excerpt pipeline alike, not the one instance that motivated it, and
stage 4's re-derivation of an unpinned finding's expected set is held to it
too. In that pipeline the operand reaches `head` only: `tail`, the `grep -v` and
the hasher all read stdin and take no document-derived token at all. The test
is an **allow-list, not a metacharacter blacklist**: a token survives only if
every character is one of `A–Z a–z 0–9 . _ / -`, plus the `:` introducing the
`:<line>` suffix, which is stripped before the path is used — a blacklist is
what leaves the metacharacter nobody enumerated on the near side of the check. A
token that fails is **rejected, never escaped**: escaping keeps the token and
moves the problem into the quoting, where the next bug lives, while rejection
ends it, and `docs/a.md;id`, `docs/a.md$(id)` and `--foo=x/y` all fail here with
none of the three repaired into something runnable. What survives is still
quoted: single-quote every interpolated token where it enters the command
**and** neutralise a leading `-` on a path operand so it cannot be read as an
option — both defences, not either. The rule is the same for both commands
that take a path operand, and it was measured rather than assumed common. Both
accept the `--` separator, so the path goes after it: `git hash-object`, and —
verified against the BSD `head` macOS ships, rather than carried over from
either previous case — `head`, which consumes `--` as end-of-options and reads
the operand after it correctly. The excerpt pipeline **additionally** prefixes a
relative `<report>` path with `./`. The two are not redundant: `--` protects the
operand's leading `-` at the command's own option parser, while `./` makes the
path safe even where a caller drops the separator, and `./` alone is what makes
the operand readable as a path in the written form of the pipeline. Neither is
dropped.

**`unpinnable` is a different state from `absent`, and the two are never written
interchangeably.** A rejected path is recorded `<path>=unpinnable`, carrying its
`:edit`/`:ref` marker like any other entry. `absent` is an **observation**: the
command ran, the path was not there, and a later present-state is an observable
change stage 4 grades on. `unpinnable` is the **refusal to take one**: no
command ran, and nothing is known about that path in either direction. It is
skipped by the pre-dispatch pin comparison, and it is **never in the expected
set** even when marked `:edit` — grading it would read "the loop never looked"
as "the path was not there", manufacturing exactly the false `absent` → present
flip the `:ref` exclusion exists to prevent — so a dispatch whose every `:edit`
entry is `unpinnable` has no observation to grade and takes stage 4's
*observation cannot be taken at all* case. The run summary names each such path
as **unpinnable**, beside the `unpinned` disclosure and distinct from it:
`unpinned` is a finding carrying no pin line at all, `unpinnable` is a named
path inside a pin line whose other entries are good. Where the `<report>`
operand **itself** is rejected the block excerpt cannot be cut at all, so no
block hash exists and no pin can be written: that finding takes the `unpinned`
path below rather than acquiring a state of its own.

Where neither hasher exists the pin
cannot be written at all:
the decision is recorded without a `**Decision-pin:**` line, it is never
replayed on a later run, and the run summary names that finding as unpinned. The
pin is compared immediately before dispatch; on mismatch the decision is not
replayed — the analyst is re-run for that finding and the user is re-asked —
unless the loop itself caused the mismatch. A mismatch whose changed hashes are
all attributable to a dispatch this run made after the pin was written is
re-pinned silently against the current tree and dispatched with no re-ask; only
an unattributable change, one this run cannot account for, sends the finding
back through the analyst and the sweep. That is the rule that bounds the passes:
dispatch is sequential, so the first dispatch of a pass invalidates the pin of
every set-aside finding sharing a file with it, and `Evidence` records that
sharing a file is the common case — without the attribution rule each pass would
manufacture the next one and nothing would terminate. Every mismatch arising
inside the second pass is self-inflicted by the loop and therefore attributable,
so the second pass dispatches and no third is generated. This
is the single documented exception to "every decision is collected before any
fixer runs", and its sequencing keeps the exception from becoming an
interruption: the finding is set aside, the remaining dispatches of the batch
complete, and the set-aside findings are then re-analysed and re-swept as a
second pass before their own dispatch. No ask interrupts a batch in flight, and
each fresh pin is taken against the tree the dispatch it belongs to will
actually see.

**An interrupted dispatch resumes differently from an interrupted sweep.** A
dispatch marker is written before the fixer call, on its own line directly
beneath the `**Decision-pin:**` line, or beneath the `**Decision:**` line where
no pin could be written — never appended at the end of the block,
where `fix-auto`'s Remediation capture would take it in — with a written form of
its own:

```
**Dispatch:** attempt <N> dispatched <YYYY-MM-DD>
```

`<N>` is the attempt the decision line is about to record. It is a loop-written
line like the others: excluded from the block hash, registered with the same
consumers, and replaced in place rather than accumulated. Because it is written,
an interrupted run tells
"decided, never dispatched" apart from "dispatched, outcome unknown", and the
two states resume differently. "Decided, never dispatched" enters stage 3
normally. "Dispatched, outcome unknown" is never re-dispatched blind: the
resumed run first re-runs stage 3.5's verification for that finding — a pass
writes the stage 4 status with no new dispatch, and a failure records
`attempt N: interrupted, unverified`, which counts toward the two-attempt
retirement above, and only then re-dispatches.

## Edge cases

| Situation | Behaviour |
|---|---|
| No `needs-decision` findings | `/fix-all` does not ask at all — no extra click when there is nothing to decide |
| Only `needs-decision` findings | The fix list is empty and `needs_decision` is not. Step 2.2.5 no longer aborts: Steps 3–4 are skipped and Step 5's offer runs in place of the abort message that pointed at `/fix-report` or `/fix <ID>` |
| User answers "no" to `/fix-all`'s offer | Step 4.2 has already printed the "Requires user decision" list before the offer — except on the zero-auto path, where Steps 3–4 were skipped and Step 5 printed the list itself; either way, on "no" the run stops without repeating it, having closed the progress rows Step 5 owns |
| Analyst fails or returns an unusable block | Degrade to the raw report block plus the same five-outcome prompt, with a visible "code analysis unavailable" note. The alternatives come from the finding's Remediation, but never verbatim: a reviewer-authored Remediation is under no self-containment contract, while stage 3 dispatches only a full self-contained resolution and `Decision record` calls a deictic one a contract violation, so the orchestrator restates each alternative as a full self-contained resolution naming every file and line it touches and shows the restatement for confirmation before dispatch, exactly as `other…` requires; a Remediation that cannot be restated self-containedly returns to the sweep. Where the Remediation names only one fix — and `Components`' `Alternatives` row records that it frequently names none at all — the call carries the three options `[A] [skip] [reject]`, never a placeholder B the user cannot act on. `reject` stays reachable — a failed analyst is no reason to strip the outcome for a finding that may still be wrong — but with no cited evidence to re-run it is gated on the user's non-empty reason alone, and the run summary marks that rejection `unverified`. Never a silent skip |
| Location missing and user supplies none | Marked Failed up front, not dispatched — matching `fix-report` Step 2.4 today |
| Location parses and exists but escapes the repository tree | Location-less, never merely non-existent: it is never reported as a missing file and never offered for creation. It takes the same single re-ask, and a replacement that also fails containment is handled exactly as a declined target — Failed in the run summary only, no `**Status:**` line, not dispatched |
| Interruption during the sweep | Decisions already recorded inline, and every `path:line` stage 0 validated is already written into the finding's `**Location:**` field, so neither is asked for again; the next run reports how many remain. Stage 1's analyses are not persisted, so every finding still undecided is re-analysed and re-rendered on the next run |
| Interruption during dispatch | The dispatch marker separates "decided, never dispatched" from "dispatched, outcome unknown". The first enters stage 3 normally; the second is never re-dispatched blind — the next run re-runs stage 3.5 for that finding first, and on failure records `attempt N: interrupted, unverified`, counting toward the two-attempt retirement, before any new dispatch |
| More than 8 findings | Successive analyst batches, each announced ("analysing 8 of 13"). No silent truncation |

No hard cap on finding count. A silent cap reads as "everything was covered"
when it was not.

## Delivery

`code-review` 1.17.3 → **2.0.0** (MAJOR, not MINOR: this release changes the
shared report format — a third `**Status:**` value, the extended `**Location:**`
form, and six loop-written fields — and `CLAUDE.local.md` reserves MAJOR for
"incompatible formats". The counter-argument, that SemVer governs backward
compatibility rather than forward, was raised twice during spec review and
refuted twice; it was reversed on the ground that the artifact is an interchange
format shared between installs and with the `qa` plugin, that this repository's
own precedent grades such a change MAJOR — `cb073c1`, "QA 2.0.0 — MAJOR:
incompatible report format change" — and that the Upgrade Notes below already
assert a MAJOR-shaped constraint in prose, which the version number should carry
instead of leaving to a paragraph a reader may not reach), in
all four places `scripts/check_plugin_versions.py` checks. `qa` 2.5.2 →
**2.6.0** (MINOR, not PATCH: `/qa:loop` gains behaviour on a new input value —
it must read `🚫 Rejected` as terminal and preserve the line — which is a
feature by the rule `CLAUDE.local.md` states, where PATCH is reserved for fixes
and docs), likewise in all four places.

Prose requiring correction beyond version numbers:

- `plugins/code-review/.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` — the description says `/fix-all` "skips
  needs-decision", which stops being the whole truth.
- `README.md` — the `code-review` row repeats the same claim.
- `docs/plugins/code-review.md:134` — "There is no override flag — use
  `/fix-report` or `/fix <ID>`" is superseded.
- `docs/plugins/code-review.md:125` — the "when to use what" table gains the
  decision stage.
- `docs/plugins/code-review.md` — new sections for the decision stage, the
  analyst, and the `Rejected` status.
- `plugins/code-review/commands/fix-report.md` — the command had no Step 4.1.5
  at all before this change: Step 4.1 (`fix-report.md:222`) ran straight into
  Step 4.2 (`:244`) and the command ended there, while Step 4.1.5, its
  positional check and `status_write_failures` existed only in `fix-all.md`
  (today `fix-all.md:362-411`). One
  is added, mirroring those lines — re-read the `source_file`, confirm the
  status line is the next non-blank line below the issue heading, collect
  `{issue_id, source_file, reason}` into `status_write_failures`, and render
  that list in Step 4.2 — since every reference to "Step 4.1 / 4.1.5" in this
  spec treats the pair as existing and merely re-run. Both commands' Step 4.1.5
  then verifies **three write kinds, not one**, over every finding the batch
  wrote back for: the `**Status:**` line by that positional check; the attempt
  entry appended to the block's live `**Decision:**` line, whose absence is
  recorded with reason `attempt-entry-missing`; and the `**Verification:**`
  line, located by its key wherever in the block it sits, whose absence is
  recorded with reason `verification-line-missing`. `status_write_failures`
  therefore carries five reasons — `edit-errored`, `status-line-missing`,
  `status-line-wrong-text`, `attempt-entry-missing` and
  `verification-line-missing` — and the last two reach it only from a finding
  the decision gate decided. A rejected finding is outside all three checks:
  `reject` never dispatches, so it carries no `**Verification:**` line at all
  and its absence is not flagged.
- `plugins/code-review/commands/fix-report.md` and
  `plugins/code-review/commands/fix-all.md` — frontmatter gains
  `Bash(shasum:*)`, `Bash(sha256sum:*)`, `Bash(head:*)`, `Bash(tail:*)` and
  `Bash(grep:*)`: without one of the two hashers neither command can compute the
  block hash the `**Decision-pin:**` line requires, `sha256sum` being the
  fallback where `shasum` is absent, and `head`, `tail` and `grep` are what cut
  the block excerpt out of the report on disk and drop its loop-written lines
  before it reaches the hasher, as `Decision record` requires. No `Bash(sed:*)`
  is granted, and the omission is the point: a prefix-matched `sed` grant would
  carry `sed -i` and, on GNU `sed`, the `e` command and the `s///e` flag, while
  neither `head` nor `tail` has an in-place write mode. The same frontmatter
  **loses** `Bash(git:*)`, replaced by the seven read-only subcommands the stage
  actually runs — `Bash(git log:*)`, `Bash(git show:*)`, `Bash(git diff:*)`,
  `Bash(git blame:*)`, `Bash(git status:*)`, `Bash(git hash-object:*)` and
  `Bash(git rev-parse:*)`. The last two are the pipeline's own rather than
  boundary members: `git hash-object` computes the pinned-file hashes and
  stage 4's first observation, and `git rev-parse --show-toplevel` resolves the
  repository root for stage 0's containment test. The pinned-file hashes and
  stage 4's `git status --porcelain` tree observation are therefore still
  covered, and no destructive git subcommand is pre-approved any more.
- `plugins/code-review/skills/decision-gate/SKILL.md` — a new
  `### The grant registry` section, placed immediately after the execution
  boundary it serves: a scope table classifying every consumer of the skill
  (`runs-the-stage`, `render-only`, `dispatch-only`, `reference-only`) and a
  grant table classifying every `Bash(...)` pre-approval on a runs-the-stage
  consumer as `inside-boundary`, `pipeline` or `outside-escalates`. A grant row
  is not a boundary permission and licenses no check; it records only that the
  platform raises no prompt, which is what makes the sweep's `AskUserQuestion`
  the sole remaining gate for anything the boundary excludes.
- `scripts/check_execution_boundary.py`, with
  `scripts/test_check_execution_boundary.py` (55 tests) — a registry-parity
  check in the shape `plugins/code-review/scripts/check-prefix-sync.sh` already
  uses here. It parses the boundary's terms and the grant registry out of the
  skill's own prose rather than hardcoding them, reads the consumers'
  `allowed-tools:` through `check_agent_frontmatter.py`'s parser, and fails the
  build on a `Bash(...)` grant no registry row declares, a registry row its
  consumer does not carry, a file that mentions the skill and appears in no
  scope-table row, an `inside-boundary` row the boundary text does not admit, or
  a command-family wildcard the boundary admits only in part (`Bash(git:*)`
  against the five named git subcommands). This is what moves the grant-list
  half of the boundary from prose-only to machine-checked.

**The two versions are a pair, and neither side of the skew has a fail-safe.**
The plugins install independently and the marketplace manifest has no dependency
field, so `code-review` 2.0.0 can run beside `qa` 2.5.2 and write rejections an
older `/qa:loop` neither recognises nor preserves. There is no fail-safe for
that case: preserving the line is precisely the new duty this change assigns to
2.6.0, so it cannot also be a property of an already-released build — an older
`qa` overwrites the line at `loop.md:902-907` when a sibling issue passes on the
same scenario. The same skew exists *inside* `code-review`, and there it is
worse: a report carrying `🚫 Rejected` is a committed artifact, so a collaborator
still on 1.17.3 opens it with a Step 1.3 filter that does not know the value,
`/fix-report` re-offers the finding and can dispatch it — silently reversing an
outcome `Oracle` calls terminal and hand-recoverable, where the old-`qa` case
only fails to act. Nothing on the writing side prevents it. Both skews are
therefore recorded as a requirement rather than a recommendation — `code-review`
2.0.0 expects `qa` 2.6.0 for any report the two share, and any report
containing `🚫 Rejected`, or a `**Location:**` line in the extended `(was: …)`
form, requires `code-review` ≥ 2.0.0 wherever it is read — in
the upgrade notes of both `docs/plugins/code-review.md` and
`docs/plugins/qa.md`, with the intra-plugin skew stated in
`docs/plugins/code-review.md`'s upgrade notes. Both risks are carried under
`Residual risks`.

## Oracle

Each outcome names the signal that decides whether it was right:

| Outcome | Deciding signal |
|---|---|
| **A** / **B** / **other…** | Stage 3.5's raw verification output for the alternative actually decided, logged by the orchestrator; `fix-auto`'s own Phase 6 verdict is advisory narration. Whether the fixer edited is read from the tree — two observations taken immediately before and immediately after each dispatch: a `git hash-object` content hash of every path the `**Decision-pin:**` line names **except its `unpinnable` entries**, recorded as `absent` where the path does not exist, which is the observation the status is decided on and needs no git report of the path, and `git status --porcelain` plus a content hash of every path it lists, which serves only to surface writes outside the pinned set — and never from that narration; a change inside the expected set, which is the pinned entries marked `:edit` and never the `:ref` entries nor the `unpinnable` ones, even when those are marked `:edit`, decides the status, while a change outside it is logged and named in the run summary as an out-of-scope write, and a dispatch whose observation could not be taken at all — one whose every `:edit` entry is `unpinnable` included — is not graded as "no edit": it writes no `**Status:**` line, carries `attempt N: dispatched, unverified` on the decision line, and the run summary names the finding as unobservable. A pass writes `✅ Fixed`; an observable change inside the expected set whose output does not pass writes `⚠️ Partially Fixed`; a dispatch that errored, or one after which no file in the expected set changed observably, writes no `**Status:**` line, only `attempt N: failed` on the decision line; and a finding where no check of any kind ran writes no `**Status:**` line either, with `attempt N: dispatched, unverified` on the decision line, `**Verification:** unavailable — <checks run>` in the block and `verification: unavailable` in the run summary; where some checks ran and others were refused or unrunnable the finding is graded on the raw output of those that ran, and the shortfall is disclosed rather than skipped — `**Verification:** advisory — <checks run>; <N> not run: <check text>` in the block and a coverage warning naming the finding in the run summary. The plan must use executable checks with observable output wherever the finding admits one; where it cannot — a documentation finding whose only available check is an LLM re-reading prose — that check is still runnable and its pass is stage 4's first case, but the verdict is soft, so the block carries `**Verification:** advisory — <checks run>` beside its status line and the run summary marks the finding `✅ Fixed (advisory verification)`: the persisted line, not the status, is what carries the softness out of the session. A wrong call lands as an uncommitted diff the user can read and revert |
| **reject** | The analyst's cited evidence *where the block carries a `Rejection candidate`* — the cited commands and tool calls re-run by the orchestrator at the gate, under the read-only boundary, and shown to the user before the choice is offered. Whether the candidate is supported is decided by the support test `Decision outcomes` states once; on any other result the outcome is not offered at all, and the recorded and the fresh output are shown side by side as the discrepancy. Where there is no candidate, including a failed analyst, there is no evidence to re-run and the deciding signal is the user's stated reason alone, so the run summary marks that rejection `unverified`. Either way nothing beyond the `— <reason>` tail is persisted when the `🚫 Rejected` status is written |
| **skip** | None, by construction — nothing is written and the finding returns next run |

The asymmetry is the point. A wrong A/B survives as a diff; a wrong `reject` is
terminal across two plugins and recoverable only by hand, so it is the one
outcome whose evidence is re-run rather than trusted — wherever there is
evidence to re-run. A rejection with no `Rejection candidate` behind it has
none, which is why it is recorded as `unverified` rather than treated as
checked.

One structural claim now has a deciding signal of its own. The claim that the
fixed list of pre-approved `Bash(...)` grants is what `decision-gate` says it is
is decided by `scripts/check_execution_boundary.py`, which diffs the skill's
grant registry against the runs-the-stage consumers' `allowed-tools:` — a build
failure, not a reading. That invariant was prose-only and is machine-checked
from this release on. It decides parity between a table and a frontmatter list
and nothing beyond: the checker never observes a running check, so the boundary
itself still has no oracle but the reader.

What none of these oracles can check: that the applied edit matches what the
user meant; that a documentation fix is factually right; that a rejected finding
was actually wrong rather than merely under-researched; or that a check the
model chose to run was in fact inside the execution boundary.

## Verification

1. `scripts/check_agent_frontmatter.py` — `decision-analyst.md` uses only
   permitted keys and declares capability under `tools:`.
2. `scripts/check_plugin_versions.py` — four-place parity for both plugins.
3. `plugins/code-review/scripts/check-prefix-sync.sh` — unaffected (no new
   prefix), run to confirm no regression.
4. End-to-end run against a synthetic fixture report containing: two `auto`
   findings, three `needs-decision` findings, one of them with `Location: —`,
   and one whose referent actually exists so the `Rejection candidate` path is
   exercised. Entry via `/fix-all` (to reach Step 5) and separately via
   `/fix-report` (to reach the partitioned page). Each entry run starts from a
   pristine copy of the fixture — the report and the files it points at alike —
   and every post-condition is read against the writes of that run alone. Run
   the second entry over the first run's leftovers and the findings are already
   `✅ Fixed` or already decided, so the Step 1.3 filter and the replay path
   swallow them and the list is satisfied by writes the run under test never
   made. "It ran without error" is not
   the pass condition, and neither is a sweep the operator improvises: the
   answers are scripted alongside the fixture, and every post-condition is bound
   to the finding whose scripted handling produces it.
   - finding 1, the one with `Location: —`: supply no path when stage 0 asks →
     reported Failed in the run summary, no `**Status:**` line written, never
     dispatched;
   - finding 2, the live referent: choose `reject` with a stated reason → a
     `🚫 Rejected (YYYY-MM-DD) — <reason>` status line, reason included, and no
     `**Decision:**` line. The step is bound to the candidate path, not merely
     to the status, which the no-candidate path produces identically: the
     analyst's block for finding 2 must have carried a `Rejection candidate`
     whose evidence is command-or-tool-plus-output, the transcript must show
     those exact citations re-run with their raw output displayed at the gate,
     and the run summary must not mark this rejection `unverified`. A run in
     which the analyst returned no candidate for finding 2 does not satisfy the
     step, however the status line reads;
   - finding 3: choose **A** → a `**Decision:**` line in the delimited grammar;
     the finding's `**Location:**` field in the source report rewritten to the
     analyst's verified `Target`, normalised to `path:line` (a range's start
     line) so the replay path dispatches it unchanged, with the reviewer's
     original still recoverable from the `(was: …)` parenthetical, and the line
     still carrying both when the run ends; and the scripted outcome, named
     rather than left to whatever the run produces: `**Status:** ✅ Fixed
     (YYYY-MM-DD)` with `**Verification:** hard — <the fixture's scripted
     checks>`, stage 3.5's raw output for exactly those checks present in the
     transcript, and the status derivable from that output. `⚠️ Partially
     Fixed`, a missing `**Status:**` line, or any other `**Verification:**`
     value fails the step — `unverified` no longer exists, and `unavailable`
     would mean the verification never ran;
   - both `auto` findings: `✅ Fixed`;
   - in the transcript, all analyst dispatches issued in a single turn, followed
     by `fix-auto` dispatches issued one at a time.

   Any missing post-condition fails the step, and both entry runs must satisfy
   the whole list. A run in which any `needs-decision` finding is skipped does
   not satisfy the step: `skip` writes nothing, so the list would be met
   vacuously by a run that never reached stages 3, 3.5 or 4.
5. Walk the seven consumers listed under `Status vocabulary extension` one at a
   time, recording the confirming line number for each: a file that enumerates
   statuses lists `🚫 Rejected`, and a file that filters or writes handles it as
   terminal (`fix-report.md` and `fix-all.md` exclude it at the Step 1.3 filter,
   and their Step 1.5 all-resolved edge case no longer reads the presence of a
   `**Status:**` field as proof of a fix — its message distinguishes fixed from
   rejected; `loop.md` keeps a rejected issue out of the fix set and leaves its
   Status line in place). Two consumers are checked for read-side duties rather than
   for a status enumeration: `fix-auto.md`, whose Phase 1 must abort with an
   explicit error on a dispatched block that already carries a rejected status
   and whose Phase 6 verdict vocabulary must be unchanged; and `fix.md`, which
   has no Step 1.3 filter at all, so its Phase 0 must abort on a resolved block
   carrying `🚫 Rejected` and its Phase 8 must never write a second
   `**Status:**` line over an existing one. `fix-report.md` is checked for one
   further addition, recorded with its own confirming line number: it had no
   Step 4.1.5 before this change, so the walk confirms the new one mirrors
   `fix-all.md:362-411` — the `source_file` re-read, the status line confirmed
   as the next non-blank line below the issue heading, and
   `{issue_id, source_file, reason}` collected into `status_write_failures` and
   rendered in Step 4.2. The walk confirms, in both commands and each with its
   own line number, that Step 4.1.5 verifies all three write kinds over the
   decided batch and not the status line alone: the `**Status:**` line, the
   attempt entry appended to the live `**Decision:**` line
   (`attempt-entry-missing`), and the `**Verification:**` line located by its
   key wherever in the block it sits (`verification-line-missing`) — with a
   rejected finding stated to be outside the check, since it carries no
   `**Verification:**` line at all. Then walk the list a second time for
   the decision record, recording a confirming line number for each of the three
   consumers it touches: `report-format/SKILL.md` documents `**Decision:**`,
   `**Decision-retired:**`, `**Verification-plan:**`, `**Decision-pin:**`,
   `**Dispatch:**` and `**Verification:**` as loop-written optional fields,
   documents the extended `Location:` form with both clauses of its read rule
   (take the first backticked token and ignore any trailing parenthetical;
   where the line carries no backticked token, take the first
   whitespace-delimited token after the field name), and documents the
   `**Status:**` prefix read rule — that consumers match the status value by
   prefix rather than by whole-line equality, because of the ` — <reason>`
   tail; `loop.md`'s reuse and
   adopt paths carry all six over, and the rewritten `**Location:**` line with
   its `(was: …)` parenthetical, exactly as they carry `**Status:**` lines,
   while its two `**Location:**` read sites — `loop.md:611`, which drops an
   issue whose Location is `unknown:0` or missing, and `loop.md:691`, which
   tells `fix-auto` to return Failed on the same — read that field by the read
   rule rather than by a whole-line test, each recorded with its own confirming
   line number; and
   `docs/plugins/code-review.md` lists them together with the extended
   `Location:` form.
   A grep for `Partially
   Fixed` across `plugins/` and `docs/` is kept as a supplementary sweep for
   enumerations outside that list — it reaches only files that already contain
   the phrase, and it cannot observe a duty that is about reading.
6. Probe whether the two-word `Bash(git log:*)` specifier is honoured at all.
   Dispatch `decision-analyst` once against a throwaway finding with an explicit
   instruction to run a write-capable git subcommand — one the narrowed grant
   must refuse, `git commit --dry-run` for instance — and record which of three
   things happened: the call was refused outright, it raised a permission
   prompt, or it simply ran. A silent successful run means the entry fell back
   to base `Bash`; a refusal means the narrowing is enforced; a permission
   prompt is inconclusive — both an honoured specifier grant and a base `Bash`
   grant fall through to a prompt on a non-matching command — and is recorded as
   inconclusive rather than as either verdict. The result is recorded as it
   stands and carried into `Residual risks`, not repaired by re-spelling the
   grant.
7. `scripts/check_execution_boundary.py`, with
   `scripts/test_check_execution_boundary.py` (55 tests) — run both. The check
   is registry parity, so it is mutation-tested rather than merely run green:
   add `Bash(git:*)` to `fix-all.md` and confirm the build fails on the
   partly-admitted family wildcard; add an undeclared `Bash(curl:*)` and confirm
   it fails on the undeclared grant; delete the scope-table row for a file that
   mentions the skill and confirm it fails on the unclassified consumer; revert
   each. Record what the checker does **not** cover, so that no later reader
   takes a green build for more than it is: it reads `*/commands/*.md` and
   `*/skills/*/SKILL.md` only, and within those only the `Bash(...)` grants of
   the runs-the-stage consumers.

## Residual risks

**The root cause is mitigated, not eliminated.** Step 2.4 existed in the
installed build and did not fire. An explicitly loaded skill and a dedicated
checklist page improve the odds materially, but this remains prose executed by a
model. A guarantee at the level of code would require a validator script in the
manner of `check-prefix-sync.sh`, which is not in scope here.

**The status vocabulary has no CI guard.** This change adds a third value to a
vocabulary duplicated across seven files in two plugins, with nothing in CI to
catch a missed consumer. Verification step 5 is a manual per-consumer walk
backed by a supplementary grep, and manual sweeps are exactly what drifted
`docs/plugins/qa.md` a release behind before.

**Analyst quality is unmeasured.** A `Findings` field that is confident and
wrong is worse than no analysis, because it makes a bad decision feel informed.
The `finding-falsification` doctrine exists in this plugin for that class of
problem and is a candidate for the analyst to load, but this spec does not
require it.

**The analyst's read-only grant may be inert, and the fallback is worse than a
wider git grant.** `Bash(git log:*)` and its three siblings have no precedent in
any agent's `tools:` in this tree, and
`scripts/check_agent_frontmatter.py:78-80` calls the spelling undocumented. If
the resolver does not honour a two-word specifier, the entry falls back to base
`Bash`, which is not confined to git at all: the analyst then holds unrestricted
shell — `rm`, `curl`, `tee`, `sh -c`, a `python -c` that opens a file for
writing — and `disallowedTools` closes none of it, since it names only `Edit`,
`Write` and `NotebookEdit` and a `python -c` write is not an `Edit` call. The
read-only property is then **absent, not degraded**. The fallback also reaches
past `Bash`: the grant carries `Skill` with no key narrowing which skills may be
loaded, and seven of this plugin's eleven skills carry `Bash(...)` entries in
their `allowed-tools:`, so loading one converts arbitrary execution from
prompted into unprompted. Both consequences are strictly conditional on the
fallback, which remains unverified. Verification step 6 probes which it is;
until that probe has run, the separation of the reader from the writer is a
convention this design relies on rather than a property it enforces.
`check_execution_boundary.py` does not help here: it reads commands' and skills'
`allowed-tools:`, never an agent's `tools:`.

**Fixture coverage is synthetic.** With no `docs/reviews/` in the repository,
the end-to-end run tests the design against a report this project wrote for
itself, not against the shape real reviews produce.

**A report carrying `🚫 Rejected`, or a `Location:` line in the extended
`(was: …)` form, is only safe on paired builds.** The status goes into a
committed artifact and nothing on the writing side guards its readers. A
collaborator on `code-review` 1.17.3 gets a Step 1.3 filter that does not know
the value, so `/fix-report` re-offers the rejected finding and can dispatch it,
silently reversing a terminal outcome. The extended `**Location:**` form is the
same kind of change to the same committed artifact, and 1.17.3 has no read rule
for it: `fix.md`'s whole-line usability test reads the reviewer's original
inside the `(was: …)` tail as a missing location. Its consequence is milder — a
degraded run that asks the user for an address the report already holds, not a
silently reversed terminal outcome — but it is the same skew. Such a report is
safe only where every reader is `code-review` ≥ 2.0.0.

**An older `qa` overwrites a rejection.** `qa` < 2.6.0 predates the preserve
duty, so Step 4.1's in-place Status update (`loop.md:902-907`) replaces a
`🚫 Rejected` line and its reason whenever a sibling issue passes on the same
scenario. The pairing is stated in both upgrade notes and enforced by nothing.

**The execution boundary is narrowed and its grant list is machine-checked;
the boundary itself is still model-enforced.** Two things changed.
`/fix-report` and `/fix-all` no longer hold `Bash(git:*)`: their git
pre-approvals are the seven read-only subcommands the stage actually runs, so a
cited or planned `git restore` or `git checkout` now raises the platform's
permission prompt instead of executing silently. And
`scripts/check_execution_boundary.py` fails the build if either command's
`Bash(...)` grants drift from the grant registry in `decision-gate/SKILL.md`, so
the narrowing cannot be widened again unnoticed. What is **not** enforced is the
boundary itself: the checker decides parity between a table and a frontmatter
list and never observes a running check, so nothing at the tool layer decides
whether a command the model chose to run was inside the boundary. The platform
prompt is the remaining backstop and it can be answered in haste. The checker's
reach is narrower still — `*/commands/*.md` and `*/skills/*/SKILL.md` only, and
within those only the `Bash(...)` grants of the two runs-the-stage consumers.
`fix-auto`'s own unrestricted `Bash` is outside it, and so are the four other
`code-review` surfaces that still carry `Bash(git:*)`: `commands/fix.md`, which
the registry classifies `render-only` and whose grants the checker therefore
does not diff; `commands/review.md` and `commands/analyze-feedback.md`, which
never mention the skill and are not consumers at all; and
`agents/feedback-analyzer.md`, an agent file outside the checker's globs
entirely. None of the four runs this stage, and none of them would fail the
build.

**Out-of-scope writes are reported, not prevented, and the report evaporates.**
`fix-auto` holds unrestricted `Edit`, `Write` and `Bash`, so stage 4's
before/after tree observation can see a write outside the pinned set but cannot
stop one. Such a write is named only in the run summary, which does not survive
the session that printed it — unlike a status line, it leaves nothing in the
report a later reader could find.

**The whole loop is deliberately unbounded, and loop-engineering bar item 6 is
not met.** No dispatch budget, wall-clock budget or token budget bounds any part
of it: stage 1 runs one analyst per `needs-decision` finding in successive
batches of 8, stage 3 runs M sequential fixers, stage 3.5 runs a verification
per dispatch, and the run as a whole is as long as the finding count makes it,
however many findings there are. This is a deliberate choice rather than an
oversight, and it is plainly a choice *against* bar item 6 rather than a reading
that satisfies it: no ceiling of any kind is added. What the design argues
against is a *silent* cap — one that stops partway and reports as though
everything had been covered. The visible form of "not processed" already exists
here as `skip`: nothing is written, the finding returns on the next run, and the
run summary says so. A cap that behaved that way would be defensible; this
design still declines to add one, and that departure from the bar item is stated
rather than argued away. The bounds that do exist are local and human: the
two-attempt retirement bounds the work spent on one decision, not the run, and
the sweep is a human gate the run cannot pass without a person answering.
Beyond those, the design carries two soft mitigations: the pre-flight count stage 1 states before it fans
out ("13 findings to analyse, in 2 batches of at most 8"), which `/fix-all`'s
Step 5 offer names as well, and the announcement of each batch as it runs
("analysing 8 of 13"). Both make the size visible; neither bounds it, so neither
satisfies item 6.

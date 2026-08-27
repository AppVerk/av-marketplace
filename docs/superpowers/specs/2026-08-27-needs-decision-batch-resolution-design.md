# av-marketplace — Batch Resolution of `needs-decision` Findings

**Date:** 2026-08-27
**Status:** Approved design, pre-implementation
**Affected plugins:** `code-review` 1.17.3 → 1.18.0, `qa` 2.5.2 → 2.5.3

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
single batch afterwards.

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
change to `fix-auto` is required.

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
- `/fix-report`: partition `needs-decision` onto a dedicated first checklist
  page; replace Step 2.4 with the decision gate.
- `/fix-all`: new Step 5 offering the decision stage after the auto batch.
- `/fix`: Phase 3 delegates the `Alternatives:` format to the skill; behaviour
  unchanged.
- New finding outcome `🚫 Rejected`, propagated to both plugins.
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
 stage 0   Location pre-check
           Location is "—" or "unknown:0"?
           → ask for path:line now, before fan-out. An analyst has
             nothing to read without it. Findings whose target the
             user declines to supply are marked Failed, not dispatched.
                  │
 stage 1   Parallel fan-out: decision-analyst × N, read-only
           Dispatched in a single turn, batches of at most 8.
           More than 8 findings run in successive announced batches.
                  │  returns: Proposed Fix block (contract below)
                  │
 stage 2   Decision sweep, one finding at a time
           Render the block, then [A] [B] [other…] [skip] [reject].
           No file is edited in this stage except the decision record.
           Each decision is written to the source report as it is made.
                  │
 stage 3   Batch dispatch: fix-auto × M, sequentially
           Issue block + trailing "User decision: <resolution>".
                  │
 stage 4   Status write-back to source reports
           Existing Steps 4.1 / 4.1.5, unchanged.
```

The parallelism the user asked for lives in stage 1. Stage 3 stays sequential
for the write-conflict reason recorded under Evidence.

## Components

### Agent: `decision-analyst`

`plugins/code-review/agents/decision-analyst.md`

Receives exactly one `needs-decision` finding block. Reads the code the finding
points at and returns a rendered proposal. Performs no writes.

```yaml
tools: Read, Grep, Glob, Bash(git:*), Skill
```

The read-only grant is load-bearing, not decorative. Separating the analyst that
reads from the `fix-auto` that writes is what makes the decision gate real: the
analyst cannot pre-empt the user's choice because it cannot edit. Frontmatter
keys stay within the set `scripts/check_agent_frontmatter.py` permits (`name`,
`description`, `tools`, `disallowedTools`, `model`, `skills`); `allowed-tools:`
is not used, per `CLAUDE.md`.

**Return contract.** The orchestrator renders the returned block without
re-reading the code — that is the point of the fan-out. Every field is required
unless marked optional:

| Field | Content |
|---|---|
| `Target` | Real `path:line-range`, verified against the file, not copied from the report |
| `Findings` | What is actually in the tree. Concrete and citable: "`Glob` finds no `scripts/qa-run.sh`; `git log` shows removal in `9c6fc76`; also cited at `README.md:41`" |
| `Alternatives` | A and B, derived from `Drift-class`. `dead-reference` → remove the mention vs restore the referent. `decision` → the alternatives the Remediation names. If the Remediation names none → apply as written vs resolve differently |
| `Recommendation` | A or B, with the reason |
| `Risk` | What the recommendation costs if it is the wrong call |
| `Code Preview` | Current and proposed code for the recommended alternative |
| `Verification Plan` | The checks that would confirm the fix |
| `Rejection candidate` | Optional. Present when the code contradicts the finding — a `dead-reference` whose referent exists under another name. Carries the reason |

### Skill: `decision-gate`

`plugins/code-review/skills/decision-gate/SKILL.md`

Single source of truth for the decision stage, loaded by `/fix-report` and
`/fix-all`: fan-out rules and batch size, the analyst return contract, the
decision sweep and its five outcomes, the dispatch contract, and the decision
record. A skill rather than a command — it adds no entry point, and the
"doctrine in a skill" pattern is established in this plugin by
`verdict-protocol`, `docs-fact-registry` and `finding-falsification`.

### Command changes

| File | Change |
|---|---|
| `commands/fix-report.md` | Step 2.2: `needs-decision` findings are partitioned onto their own labelled first page of the checklist, ahead of the severity-sorted `auto` pages. Step 2.4 is replaced by an invocation of `decision-gate` |
| `commands/fix-all.md` | New Step 5 after Step 4.2: if `needs_decision` is non-empty, ask whether to resolve those findings now; on yes, run `decision-gate`. Adds a fifth row to the progress-task table under "MANDATORY FIRST STEP". Steps 2.2.5 and 4.2 are unchanged |
| `commands/fix.md` | Phase 3 stops restating the `Alternatives:` format and defers to `decision-gate`. Behaviour identical; the goal is that all three entry points render one format |

**Ordering inside `/fix-report`.** Every decision is collected before any
`fix-auto` is dispatched, and the `auto` findings selected from the later pages
are fixed in the same batch as the decided ones. This preserves today's ordering
(Step 2.4 already runs before Step 3) and matches the intent: decide everything,
then fix in bulk. `/fix-all` differs by construction — its auto batch has already
run by the time Step 5 offers the decision stage.

## Decision outcomes

The sweep offers five outcomes per finding:

| Outcome | Effect |
|---|---|
| **A** / **B** | Dispatch `fix-auto` with `User decision: <alternative>` |
| **other…** | User supplies a resolution in their own words; dispatched the same way |
| **skip** | No dispatch, no status. The finding reappears on the next run |
| **reject** | No dispatch. `**Status:** 🚫 Rejected (YYYY-MM-DD) — <reason>` written to the source report |

`reject` is new. Without it, a finding the analyst has shown to be wrong can only
be skipped, and a skipped finding returns on every subsequent run forever — the
same friction this spec exists to remove, displaced one level. `reject` is a
user decision, never the analyst's: a `Rejection candidate` in the returned
block surfaces the option and its reason, and the user chooses.

## Status vocabulary extension

`🚫 Rejected` joins `✅ Fixed` and `⚠️ Partially Fixed`. Consumers to update:

- `plugins/code-review/commands/fix-report.md` — Step 1.3 filter
- `plugins/code-review/commands/fix-all.md` — Step 1.3 filter
- `plugins/code-review/commands/fix.md` — status handling
- `plugins/code-review/agents/fix-auto.md` — status definitions
- `plugins/qa/skills/report-format/SKILL.md` — the documented contract
- `plugins/qa/commands/loop.md` — a rejected issue must not re-enter the loop
- `docs/plugins/code-review.md` — user-facing status list

`/qa:loop`'s existing rule that it never *writes* `Partially Fixed` is unchanged.
It must, however, *read* `Rejected` as terminal.

## Decision record

Each decision is written to its source report immediately, before dispatch, as a
`**Decision:**` line inside the finding block:

```
### [MEDIUM] DOC-004: Doc cites a removed script
**Decision:** A — remove the mention here and at README.md:41
```

If a run dies while fixing the seventh of eleven findings, the ten decisions
already made survive and the next run does not re-ask. Inline rather than a
sidecar: `code-review` has no sidecar concept (`superutils` does), while
`**Status:**` lines already use exactly this machinery and produce readable
diffs.

## Edge cases

| Situation | Behaviour |
|---|---|
| No `needs-decision` findings | `/fix-all` does not ask at all — no extra click when there is nothing to decide |
| User answers "no" to `/fix-all`'s offer | The "Requires user decision" list of Step 4.2, then stop |
| Analyst fails or returns an unusable block | Degrade to today's behaviour: raw report block plus the A/B question, with a visible "code analysis unavailable" note. Never a silent skip |
| Location missing and user supplies none | Marked Failed up front, not dispatched — matching `fix-report` Step 2.4 today |
| Interruption during the sweep | Decisions already recorded inline; the next run reports how many remain |
| More than 8 findings | Successive analyst batches, each announced ("analysing 8 of 13"). No silent truncation |

No hard cap on finding count. A silent cap reads as "everything was covered"
when it was not.

## Delivery

`code-review` 1.17.3 → **1.18.0** (MINOR: new agent, new skill, new phase), in
all four places `scripts/check_plugin_versions.py` checks. `qa` 2.5.2 →
**2.5.3** (PATCH: status vocabulary), likewise in four places.

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
   `/fix-report` (to reach the partitioned page).
5. Grep for `Partially Fixed` across `plugins/` and `docs/` after the change and
   confirm every hit that enumerates statuses also lists `Rejected`.

## Residual risks

**The root cause is mitigated, not eliminated.** Step 2.4 existed in the
installed build and did not fire. An explicitly loaded skill and a dedicated
checklist page improve the odds materially, but this remains prose executed by a
model. A guarantee at the level of code would require a validator script in the
manner of `check-prefix-sync.sh`, which is not in scope here.

**The status vocabulary has no CI guard.** This change adds a third value to a
vocabulary duplicated across seven files in two plugins, with nothing in CI to
catch a missed consumer. Verification step 5 is a manual grep, and manual greps
are exactly what drifted `docs/plugins/qa.md` a release behind before.

**Analyst quality is unmeasured.** A `Findings` field that is confident and
wrong is worse than no analysis, because it makes a bad decision feel informed.
The `finding-falsification` doctrine exists in this plugin for that class of
problem and is a candidate for the analyst to load, but this spec does not
require it.

**Fixture coverage is synthetic.** With no `docs/reviews/` in the repository,
the end-to-end run tests the design against a report this project wrote for
itself, not against the shape real reviews produce.

# Runbook — needs-decision end-to-end fixture

This is the human-run companion to `report.md`, `target-a.md`,
`target-b.md` and `ANSWERS.md` in this directory. It exists because
`AskUserQuestion` — the construct both entry commands use for every
decision-stage ask — is in `ALWAYS_STRIPPED`
(`scripts/check_agent_frontmatter.py:54-57`), so no subagent can drive
these runs. A human has to be at the keyboard. See Task 11's controller
ruling R28 for the full reasoning; this file is what that ruling asked
for instead of an agent-run sweep.

The authority for every post-condition below is
`docs/superpowers/specs/2026-08-27-needs-decision-batch-resolution-design.md`,
`Verification` step 4, spec lines 1238–1285. Where this runbook and the
spec ever disagree, the spec wins — re-read it before filing a
discrepancy against this file.

**"It ran without error" is not the pass condition.** Neither is a sweep
you improvise. Answer per `ANSWERS.md`, then check every item below —
for **both** entry runs.

---

## The first thing that will go wrong: auto-merge mode

Both entry commands support two invocation modes. **Auto-merge mode**
(no path argument) globs `docs/reviews/*.md` and
`docs/testing/reports/*.md` (`fix-all.md:108-110`, `fix-report.md:41-43`)
— **neither directory exists in this repository**. An auto-merge
invocation aborts at Step 1.1 with "No reports found" and never reaches
this fixture at all.

**Always invoke with the explicit fixture path** — single-file mode:

```
/fix-all docs/testing/fixtures/needs-decision-e2e/report.md
/fix-report docs/testing/fixtures/needs-decision-e2e/report.md
```

Never bare `/fix-all` or bare `/fix-report` against this fixture.

---

## Why the pristine-copy rule is load-bearing, not hygiene

Each entry run must start from a **fresh copy of the report and the
files it points at** — `report.md`, `target-a.md`, `target-b.md`
together, not the report alone.

Run the second entry over the first run's leftovers and:

- DOC-001, DOC-002 already carry `**Status:** ✅ Fixed` → Step 1.3's
  filter drops them before the second run ever sees them.
- DOC-004 already carries `**Status:** 🚫 Rejected` → same filter, same
  drop, and it is terminal besides — it would never re-enter regardless.
- DOC-005 already carries a live `**Decision:**` line with no
  `**Status:**` → the *replay path* picks it up (`decision-gate/SKILL.md`,
  *Entry: decision replay check*) and re-dispatches the **already-decided**
  resolution without re-asking, re-analysing, or re-rendering the sweep.

Every post-condition below would then be "satisfied" by writes the
second run never made — it would just be reading the first run's work
back to you. That defeats the entire point of running the fixture twice.
**Restore the pristine snapshot before each entry run, no exceptions.**

---

## Step 1: Take the pristine snapshot

From the repository root, once, before the first entry run:

```bash
cp -R docs/testing/fixtures/needs-decision-e2e /tmp/nd-pristine
```

To restore before each entry run:

```bash
rm -rf docs/testing/fixtures/needs-decision-e2e
cp -R /tmp/nd-pristine docs/testing/fixtures/needs-decision-e2e
```

Once this fixture is committed (Step 7 of Task 11's brief), an
equivalent restore is also available straight from git, since a run
only ever edits the three tracked files and creates none:

```bash
git checkout -- docs/testing/fixtures/needs-decision-e2e/
```

Use whichever you trust more; they restore the same state as long as
the working tree was clean at commit time. Confirm the restore worked
before dispatching anything:

```bash
git status --porcelain docs/testing/fixtures/needs-decision-e2e/
```

Expected: no output (clean).

---

## Step 2: Entry run 1 — `/fix-all`

1. Restore the pristine copy (Step 1 above).
2. Run:

   ```
   /fix-all docs/testing/fixtures/needs-decision-e2e/report.md
   ```

3. Confirm the pre-flight yes/no to fix the `auto` batch (DOC-001,
   DOC-002).
4. When Step 5 offers to resolve the `needs-decision` findings, accept.
5. Answer stage 0's location ask and the decision sweep exactly per
   `ANSWERS.md` — DOC-003 (no path), DOC-004 (reject, stated reason),
   DOC-005 (A).
6. Walk the whole **Post-conditions** checklist below against this run's
   transcript and the resulting `report.md`.
7. Do not commit or otherwise persist this run's writes to
   `report.md`/`target-a.md`/`target-b.md` — they are scratch. Restore
   the pristine copy again before entry run 2.

---

## Step 3: Entry run 2 — `/fix-report`

1. Restore the pristine copy again (Step 1's restore commands).
2. Run:

   ```
   /fix-report docs/testing/fixtures/needs-decision-e2e/report.md
   ```

3. Before answering anything, confirm the checklist's **first page** is
   a needs-decision page — the three `needs-decision` findings (DOC-003,
   DOC-004, DOC-005) must occupy the leading page(s), entirely ahead of
   any `auto` page (`fix-report.md` Step 2.2a: "needs-decision findings
   lead"). With 3 needs-decision + 2 auto findings and a 3-per-page cap
   once a skip item is appended (Step 2.2b), the expected shape is one
   decision page holding all 3 needs-decision findings plus an appended
   skip item, then one final `auto` page holding both auto findings with
   nothing appended. If any `auto` finding appears before all three
   needs-decision findings have been shown, the run has already failed
   this entry's distinguishing check — stop and record that, don't just
   answer through it.
4. Answer per `ANSWERS.md`, same as entry run 1.
5. Walk the **same** Post-conditions checklist below — every item must
   hold for this run too. Both entry runs must satisfy the whole list;
   it is not enough for one to pass.

---

## Post-conditions (spec lines 1238–1285) — check every item, both runs

Any single missing item fails the step for that run. Record which of
these you actually verified, not just that the run "seemed to work."

### DOC-001, DOC-002 (`auto`)

- [ ] Both carry `**Status:** ✅ Fixed (YYYY-MM-DD)` in the resulting
      `report.md`.
- [ ] `target-a.md:8` reads `- Supported Node.js version: 18`.
- [ ] `target-a.md:9` reads `- Maximum retry attempts: 5`.

### DOC-003 (stage 0, `**Location:** —`)

- [ ] Reported **Failed** in the run summary (not silently dropped, not
      counted among the fixed).
- [ ] **No** `**Status:**` line was written for DOC-003 in `report.md` —
      it must reappear untouched, `**Location:** —` and all.
- [ ] DOC-003 was **never dispatched** to an analyst or to `fix-auto` —
      nothing in the transcript shows an analyst or fixer call carrying
      the DOC-003 block.
- [ ] Correctly, DOC-003 ends the run with **neither** a `**Decision:**`
      line **nor** a `**Status:**` line — see the grep check below; this
      is the expected, passing shape for this finding, not a gap to
      chase.

### DOC-004 (reject, live referent)

- [ ] `**Status:** 🚫 Rejected (YYYY-MM-DD) — <reason>` is written for
      DOC-004, with the stated reason actually present in the tail.
- [ ] **No** `**Decision:**` line was written for DOC-004 — a rejection
      is recorded by its status line alone.
- [ ] Bound to the candidate path, not merely to the status text — all
      of the following, or the run does not satisfy this finding
      **however the status line reads**:
  - [ ] The analyst's returned block for DOC-004 carried a `Rejection
        candidate` whose evidence is a command-plus-output or a
        `tool:` citation plus raw output — never a bare assertion.
  - [ ] The transcript shows the orchestrator **re-running those exact
        citations** at the reject gate, with the fresh raw output
        displayed before `reject` was offered.
  - [ ] The run summary does **not** mark this rejection `unverified`.
  - [ ] If instead the analyst returned **no candidate** for DOC-004 —
        this run does not satisfy the step for this finding, full stop,
        regardless of whether the status line still reads `🚫 Rejected`.
        Note it as a fixture/design finding, do not treat it as passing.

### DOC-005 (choose A)

- [ ] A `**Decision:**` line is present, in the delimited grammar:
      `**Decision:** A — <resolution text> [<who>, <YYYY-MM-DD>; attempt
      N: <outcome>…]`.
- [ ] `**Location:**` for DOC-005 was **rewritten** to the analyst's
      verified `Target`, normalised to `path:line` (a range's start
      line if the Target was a range).
- [ ] The reviewer's original location is still recoverable from a
      `(was: ...)` parenthetical on that same `**Location:**` line, and
      both the corrected value and the `(was: ...)` tail are still
      present when the run ends (neither got dropped by a later
      rewrite).
- [ ] `**Status:** ✅ Fixed (YYYY-MM-DD)` — exactly this, not
      `⚠️ Partially Fixed`.
- [ ] `**Verification:** hard — <checks run>` — the value is `hard`,
      **not** `advisory`, **not** `unavailable`. (`unverified` is not a
      legal value for this field at all — if you see it, that is a
      defect to report, not a value to accept.)
- [ ] Stage 3.5's raw output for exactly those checks appears in the
      transcript, and the `✅ Fixed` status is derivable by reading that
      output — not asserted past it.
- [ ] The mention of `scripts/generate-legacy-report.sh` is actually
      gone from `target-b.md` (A = remove the mention — confirm the
      edit matches the chosen alternative, not just that some edit
      happened).
- [ ] **Any** of the following fails this finding for this run: a
      `⚠️ Partially Fixed` status, a missing `**Status:**` line, or a
      `**Verification:**` value other than `hard`.

### Transcript ordering

- [ ] All analyst dispatches (DOC-003's stage-0 handling aside — it
      never reaches an analyst) were issued **in a single turn** — i.e.
      DOC-004 and DOC-005's analyst calls are not interleaved with other
      work between them.
- [ ] `fix-auto` dispatches were issued **one at a time**, sequentially
      — never two concurrent `fix-auto` calls in the same turn. This
      matters concretely for DOC-001/DOC-002, which target adjacent
      lines of the same file: a concurrent pair risks a lost write.

---

## Step 4: Confirm no finding was skipped

`skip` writes nothing at all — a skipped finding would make the
checklist above pass **vacuously**, since a finding that never reached
stage 3, 3.5 or 4 also never accumulates a `**Decision:**` line or a
`**Status:**` line to fail a check against. This step exists to rule
that out directly, on the `report.md` each entry run actually produced
(before you restore the pristine copy for the next run).

The brief's own Step 6 grep uses BRE alternation
(`'**Decision:**\|🚫 Rejected'`), which **BSD grep on macOS does not
support** — the pattern would silently match nothing and the count
would read `0` regardless of what the file contains, which looks like a
failure even when the run was fine. Use extended regex instead:

```bash
grep -cE 'Decision:|🚫 Rejected' docs/testing/fixtures/needs-decision-e2e/report.md
```

Expected: **`2`** — one line for DOC-004's `🚫 Rejected` status and one
`**Decision:**` line for DOC-005. DOC-003 correctly contributes zero:
it was declined at stage 0 and never dispatched, so it has neither a
decision nor a status, by design — see the DOC-003 checklist above.

- [ ] `grep -cE 'Decision:|🚫 Rejected' docs/testing/fixtures/needs-decision-e2e/report.md` → `2`.
- [ ] If the count is anything else, do not treat it as passing — work
      out which finding is missing before deciding the run succeeded.

---

## Step 5: Commit — already done by Task 11

Task 11 (the agent run that built this fixture) already ran:

```bash
git add docs/testing/fixtures/needs-decision-e2e/
AV_COMMIT_SKILL=1 git commit -m "test(code-review): add the needs-decision end-to-end fixture and scripted answers"
```

There is nothing to commit from a runbook walkthrough itself — the two
entry runs are scratch, restored from the pristine snapshot each time,
and their writes are never meant to land in this repository. If you
find yourself with a dirty `docs/testing/fixtures/needs-decision-e2e/`
after finishing both runs, that is expected; restore it
(`git checkout -- docs/testing/fixtures/needs-decision-e2e/`) rather
than committing it.

---

## What this runbook cannot tell you

Nothing here substitutes for actually reading the two transcripts. The
checklist above tells you what to look for; it does not — and by
construction (spec: "it ran without error is not the pass condition")
cannot — stand in for looking. In particular:

- Whether DOC-004's `Rejection candidate` and its re-run citation are
  the *specific* ones this fixture's design implies (a `grep` over
  `target-b.md` surfacing "Emergency Rollback") is a judgment call you
  make by reading the transcript, not something a script here can
  assert for you.
- Whether DOC-005's `**Verification-plan:**` checks are genuinely hard
  (observable command/tool output) rather than dressed-up soft checks
  is likewise something you confirm by reading the persisted
  `**Verification-plan:**` and `**Verification:**` lines and the raw
  stage-3.5 output backing them.

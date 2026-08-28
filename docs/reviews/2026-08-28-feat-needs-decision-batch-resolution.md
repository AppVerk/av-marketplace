# Code Review — `feat/needs-decision-batch-resolution`

**Date:** 2026-08-28
**Range:** `master...HEAD` — 26 commits, 24 files, +11 275 / −63 lines (6 318 of which are the generated review sidecar JSON, excluded from the audit)
**Verdict:** no blockers. **0 CRITICAL, 0 HIGH, 11 MEDIUM, 12 LOW.**

All four executable checks pass: agent frontmatter (26 files, exit 0, 12 pre-existing warnings), 84 unit tests, version parity across 9 plugins, prefix-sync.

## Verification Summary

**Method:** Cross-domain correlation and adversarial review (Cross-Verifier + Challenger)

| Metric | Count |
|--------|-------|
| Findings verified | 23 |
| False positives removed | 2 |
| Severity adjustments | 7 |
| Cross-analysis findings | 6 composites, 7 coverage gaps |

### Challenged Findings

- **SEC-001 HIGH → MEDIUM** — `Bash(npm test:*)` and `Bash(pytest:*)` are pre-existing, not added on this branch (only `shasum`, `sha256sum`, `sed`, `grep` were appended). In the ordinary case the finding reduces to "you ran a tool in your own repo". What survives is branch-new: an allowlist whose membership is read from the artifact under review, plus a `never escalated` clause.
- **SEC-006 HIGH → LOW** — both execution variants (`;id`, `$(id)`) hit Claude Code's Bash permission parser. The residual argument-injection variant is a nuisance: of `git hash-object`'s option surface only `--path=` can carry the required `/`, and it is inert without a file operand. Worst realistic outcome is an unwritable pin, which lands in the already-designed `unpinned` disclosure path.
- **MAINT-008, MAINT-009, MAINT-010 MEDIUM → LOW** — measurement accepted in each case, interpretation overstated.
- **DOC-003, DOC-004 MEDIUM → LOW** — DOC-003 is an edge path that still ends in a consent gate and is compensated elsewhere in the same file; DOC-004 is the same defect class as DOC-005, which was rated LOW, and two instances of one class must not carry two severities.
- **Removed as false positives:** a duplicate report of the DOC-004 citation slip (no domain-specific angle; DOC-004 survives as canonical), and a "the new skill has no Skills-section entry" finding (no rule requires one, and the in-tree pattern is the opposite — 4 of 11 skills are listed; the missing criterion is recorded as a doctrine gap instead).

Three escalations proposed by the Cross-Verifier were **not** applied (DOC-002 → HIGH, MAINT-005 → MEDIUM, SEC-007 → MEDIUM). The Challenger ruled afterwards and confirmed all three at their original levels.

---

## Security

### [MEDIUM] SEC-001: Execution-boundary allowlist is read from the repository under review

**ID:** SEC-001
**Location:** `plugins/code-review/skills/decision-gate/SKILL.md:254`
**Category:** Security
**OWASP:** A06:2025
**CWE:** CWE-807
**Effort:** medium
**Fix-policy:** needs-decision

**Problem:**
`SKILL.md:254-256` defines "the project's declared test and build commands" as the commands named in the repository's `CLAUDE.md`, its `package.json` `scripts` block, or its `Makefile` targets, and states that these are "inside the boundary and are **never escalated**". The allowlist's source is therefore data in the same trust domain as the untrusted report. `SKILL.md:262` anticipates only the *not* pre-approved case (`make check`, which still raises the platform prompt); for `npm test` and `pytest`, both pre-approved at `fix-report.md:2` and `fix-all.md:2`, there is neither a platform prompt nor an `AskUserQuestion`.

**Impact:**
`npm test` executes `package.json` `scripts.test`; `pytest` executes `conftest.py` at collection. Both are repository-controlled arbitrary code, reached through stage 3.5's orchestrator-run verification with no gate. The exposure requires the reviewed repository to be attacker-influenced, which is why this is MEDIUM rather than HIGH — but the `never escalated` clause removes the model's own discretion to ask, which is the branch-new part.

**Remediation:**
Either require one-time `AskUserQuestion` approval of the resolved command text of each declared test/build command before its first execution in a run, or restrict the never-escalated set to read-only inspection alone and escalate every declared command.

### [MEDIUM] SEC-002: `Location` usability rule validates existence but not repo-root containment
**Status:** ✅ Fixed (2026-08-28)

**ID:** SEC-002
**Location:** `plugins/code-review/skills/decision-gate/SKILL.md:57`
**Category:** Security
**OWASP:** A01:2025
**CWE:** CWE-22
**Effort:** easy

**Problem:**
Stage 0's usability rule reads: "A location is usable **iff** it parses as `path:line` or `path:line-range` **and** that path exists in the tree." Existence is the only test — there is no assertion that the resolved path lies under the repository root, and no rejection of `..` segments or absolute paths. `../../.ssh/authorized_keys:1` and `/etc/hosts:1` both parse and both exist. `agents/fix-auto.md:42` reproduces the same read rule with the same omission, and `fix-auto` holds unrestricted `Edit`, `Write` and `Bash`.

**Impact:**
`/analyze-feedback` persists reviewer-authored blocks into reports, so a `**Location:**` field is an untrusted-origin value on the feedback path. The value is validated at stage 0, persisted into the source report, and dispatched to the fixer — so it survives to every later replay run. The sink is pre-existing on `master`; what this branch adds is the first explicit validation stage for the field, which is the natural and cheap place to close it.

**Remediation:**
Add containment as a third conjunct, mirroring the assertion the repository already ships at `plugins/code-review/scripts/allocate-feedback-file.sh:139-152`. A path failing containment is location-less — never merely non-existent — and takes the declined-target path.

### [MEDIUM] SEC-003: New `Bash(sed:*)` grant pre-approves an in-place write primitive

**ID:** SEC-003
**Location:** `plugins/code-review/commands/fix-report.md:2`
**Category:** Security
**OWASP:** A02:2025
**CWE:** CWE-732
**Effort:** trivial
**Fix-policy:** needs-decision

**Problem:**
The branch adds four grants to `fix-report.md:2` and `fix-all.md:2` — `Bash(shasum:*)`, `Bash(sha256sum:*)`, `Bash(sed:*)`, `Bash(grep:*)` — to support the pin pipeline. Verified: `sed` appears zero times in `master`'s grant line, so the grant is new. Three of the four are read-only; `sed` is not. Prefix matching admits `sed -i`, and on GNU sed also the `e` command and the `s///e` flag, which execute shell commands. `sed` is not inside the execution boundary at all — `SKILL.md:253` names Read/Grep/Glob plus five git subcommands "and nothing else".

**Impact:**
Before this change, `sed -i` on these commands raised a permission prompt. The boundary that now excludes it is prose alone, and the platform prompt that would have caught a lapse has been removed. Unlike the `Bash(git:*)` equivalent, this escalation is recorded in no residual-risk section.

**Remediation:**
Either drop `Bash(sed:*)` and cut the block excerpt with the `Read` tool plus in-model line slicing before hashing (`shasum` reads stdin), or keep the grant and record the increment in the residual-risk section alongside the `Bash(git:*)` entry. Note that the obvious narrowing, `Bash(sed -n:*)`, is the same two-word specifier form MAINT-002 shows is unverified — so the record, not the narrowing, is the cheap remedy.

### [MEDIUM] SEC-004: Analyst grant-fallback blast radius is understated, and the `Skill` grant amplifies it

**ID:** SEC-004
**Location:** `plugins/code-review/agents/decision-analyst.md:39`
**Category:** Security
**OWASP:** A06:2025
**CWE:** CWE-266
**Effort:** easy
**Fix-policy:** needs-decision

**Problem:**
Two gaps in an otherwise well-disclosed risk.

(a) Both `decision-analyst.md:39` and `docs/plugins/code-review.md:223` characterise the fallback as "base `Bash` — every git subcommand, the destructive ones included". Base `Bash` is not restricted to git: it supplies `rm`, `curl`, `tee`, `sh -c`, `python -c 'open(f,"w")'`. `disallowedTools: Edit, Write, NotebookEdit` closes none of it, so under fallback the read-only property is **absent**, not degraded — a materially larger claim than either disclosure makes.

(b) The grant includes `Skill`, with no narrowing key. Seven skills in this plugin carry `Bash(...)` in their `allowed-tools:` — between them `Bash(python:*)`, `Bash(node:*)`, `Bash(npm:*)`, `Bash(go:*)`, `Bash(pip:*)`, `Bash(xargs:*)`, `Bash(find:*)`, `Bash(cat:*)`. Per this repository's own `CLAUDE.md`, a skill's `allowed-tools` pre-approves permission prompts. Under fallback, that converts arbitrary code execution from prompted to unprompted.

**Impact:**
Strictly conditional on the fallback, and the resolver's actual behaviour is unverified — the probe could not run (`docs/plugins/code-review.md:224-227`). This finding is the statically-verifiable part: the accuracy and completeness of the disclosure, not a claim about the resolver.

**Remediation:**
Correct both disclosures to say "base `Bash` — unrestricted shell, not merely every git subcommand", and note the `Skill`-plus-skill-`allowed-tools` amplification. Until the probe runs, prefer the failure mode that is safe when the specifier is inert: drop `Bash` from the analyst grant and supply git history in the dispatch payload, or drop `Skill` so no skill can pre-approve prompts inside a possibly-unnarrowed grant.

### [MEDIUM] SEC-005: Decision stage carries no untrusted-input protocol, and drops the provenance flag before the analyst dispatch
**Status:** ✅ Fixed (2026-08-28)

**ID:** SEC-005
**Location:** `plugins/code-review/skills/decision-gate/SKILL.md:90`
**Category:** Security
**OWASP:** A06:2025
**CWE:** CWE-501
**Effort:** medium

**Problem:**
Stage 1 dispatches "exactly one `needs-decision` finding block" with no delimiters, no data-not-instructions framing and no provenance marker. `fix-report.md:102` instructs that the `Source:` field be surfaced "when the checklist is presented in Step 2 and when the block is handed to the `fix-auto` subagent in Step 3" — it names neither stage 1's analyst dispatch nor the stage 2 sweep render, and the sweep's render contract (`SKILL.md:107-111`) has no provenance row.

**Impact:**
A feedback-origin block reaches the analyst, and reaches the user at the decision gate, with its provenance stripped — and the analyst's output then drives both a shell re-run and a fixer dispatch. The repository has this doctrine five times over (`agents/feedback-analyzer.md:20-43` defines a nonce-bound protocol for the same input class; `analyze-feedback.md:199`; `fix.md:123-127`; `fix-report.md:96-102`; `docs/plugins/code-review.md`). The recorded no-provenance stance at `docs/plugins/code-review.md:129` does not discharge this: it was taken for `/fix-all`'s bulk, no-per-issue-gate path, and the decision stage is a per-finding human gate.

**Remediation:**
Extend the existing doctrine rather than inventing a new one: carry the feedback-origin flag into the stage 1 dispatch using the nonce-delimiter protocol `feedback-analyzer.md` already specifies, and render the `Source:` field in the stage 2 sweep alongside `Target`.

### [LOW] SEC-006: No shell-quoting rule for document-derived tokens entering a constructed command
**Status:** ✅ Fixed (2026-08-28)

**ID:** SEC-006
**Location:** `plugins/code-review/skills/decision-gate/SKILL.md:495`
**Category:** Security
**OWASP:** A05:2025
**CWE:** CWE-78
**Effort:** easy

**Problem:**
The pinned file set is "the `Target` plus every `path[:line]` token appearing in the resolution text", and a path token is "recognised **syntactically and never by testing the filesystem**". Each token is passed to `git hash-object`, and the block excerpt through a `sed -n … | grep -v … | shasum` pipeline "in one pipeline with nothing in between". Grepping the skill **and** the 1430-line design spec for a quoting, escaping, metacharacter or `--`-separator rule returns nothing. The recognition rule admits `docs/a.md;id`, `docs/a.md$(id)` and `--foo=x/y`.

**Impact:**
Capped honestly: the two execution variants hit Claude Code's Bash permission parser, which splits on `;` and flags command substitution, so execution requires a user approving a visibly malformed prompt. The residual argument-injection variant is a nuisance — of `git hash-object`'s option surface only `--path=` carries the required `/`, and it is inert without a file operand. Worst realistic outcome is an unwritable pin, which the `unpinned` disclosure path already handles.

**Remediation:**
State the rule in the skill, where the pipeline is specified, and scope it to *any* document- or tree-derived token entering a constructed command — which covers the `<report>` operand of the `sed` pipeline too, not only the `git hash-object` instance. Reject a token containing a shell metacharacter rather than escaping it, record it as unpinnable, name it in the run summary; single-quote what survives and pass `--` before a path operand.

### [LOW] SEC-007: Shipped documentation discloses the lesser residual risk of this design and not the greater one
**Status:** ✅ Fixed (2026-08-28)

**ID:** SEC-007
**Location:** `docs/plugins/code-review.md:223`
**Category:** Security
**OWASP:** A09:2025
**CWE:** CWE-1059
**Effort:** trivial

**Problem:**
The design spec records three security-relevant residual risks. Only the first — the conditional grant narrowing, whose probe could not run — reaches the user-facing plugin documentation. Grepping `docs/plugins/code-review.md` for "execution boundary", "model-enforced" and "git restore" returns zero hits, while `spec:1395-1401` states that the boundary keeping `git restore` and `git checkout` out of a re-run "is prose the orchestrating model follows, so a single lapse destroys the uncommitted diff", and `spec:1403-1408` records that out-of-scope writes are reported but not prevented.

**Impact:**
Not an exploit — an adoption-decision defect. The disclosed risk is conditional and unproven; the undisclosed one is unconditional and destroys uncommitted work, which is the user's recovery path for a wrong call. A reader deciding whether to adopt this loop sees the weaker of the two.

**Remediation:**
Add a second residual-risk blockquote to the Decision Stage section carrying the `spec:1395` and `spec:1403` disclosures, in the same form as the existing one, and name the recovery-path consequence explicitly.

---

## Architecture

### [MEDIUM] ARCH-001: `code-review` 1.18.0 should be 2.0.0
**Status:** ✅ Fixed (2026-08-28)

**ID:** ARCH-001
**Location:** `plugins/code-review/.claude-plugin/plugin.json:4`
**Category:** Architecture
**Effort:** trivial
**Fix-policy:** needs-decision

**Problem:**
`CLAUDE.local.md` defines MAJOR as covering "breaking changes (removed commands, changed behavior, **incompatible formats**)". This release changes the shared report format: a new `🚫 Rejected` status value, the extended `**Location:** \`path:line\` (was: \`original\`)` form, and six loop-written fields. The release's own documentation asserts a MAJOR-shaped constraint at `docs/plugins/code-review.md:402` ("requires every reader to be ≥ 1.18.0 — this is a requirement, not a recommendation") and `:407` ("Do not open … with a build older than 1.18.0"). In-repo precedent: commit `cb073c1` — "QA 2.0.0 — MAJOR: incompatible report format change."

**Impact:**
SemVer is the only machine-readable signal a marketplace consumer checks. A 1.17.3 → 1.18.0 bump reads as safe; the documented failure mode is silent and terminal (an older reader re-offers and dispatches a rejected finding). The counter-argument — that SemVer governs backward compatibility, which is preserved, not forward compatibility, which is not its concern — is correct about upstream SemVer but is not the governing rule here: the artifact is an interchange format shared between installs and with the `qa` plugin. The `qa` side is consistent with this reading rather than against it: 2.6.0 is a MINOR because `qa` is the *reader* absorbing a new value, while `code-review` is the *producer* of the incompatible artifact.

This is a bump-size defect, not drift — all eight version cells agree at 1.18.0.

**Remediation:**
Owner's call. Either bump `code-review` to 2.0.0 across all four places, or record in the Upgrade Notes why a format change with a stated hard reader floor is being released as a MINOR.

---

## Maintainability

### [MEDIUM] MAINT-001: Step 4.1.5 does not verify the attempt-entry append
**Status:** ✅ Fixed (2026-08-28)

**ID:** MAINT-001
**Location:** `plugins/code-review/commands/fix-all.md:365`
**Category:** Maintainability
**OWASP:** A10:2025
**Effort:** easy

**Problem:**
Step 4.1.5 iterates over "each Fixed/Partially Fixed issue in Step 4.1" and confirms only that the next non-blank line below the heading is `**Status:** ✅ Fixed` or `⚠️ Partially Fixed`; its three failure reasons (`edit-errored`, `status-line-missing`, `status-line-wrong-text`) are status-only. Step 5.5 (`fix-all.md:483`) now routes two further write kinds through that same step: the `**Verification:**` line, and — for the two stage-4 cases that write **no** `**Status:**` line — the attempt entry appended to `**Decision:**`. Those findings have no status line and so fall outside Step 4.1.5's iteration set entirely.

**Impact:**
The append is unverified and `status_write_failures` cannot represent it. The consequence chain is exact: a lost append freezes the two-attempt retirement counter (`SKILL.md:467-477`), and `SKILL.md:374-375` states the same dependency — "without it a failing decision replays forever". That is precisely the failure the retirement mechanism exists to prevent, and it makes the escape to `reject` unreachable behind a decision that fails every run.

**Remediation:**
Extend Step 4.1.5's positional re-read to cover the attempt-entry append for the two no-status cases, with a fourth failure reason, and collect it into the same `status_write_failures` list Step 5.6 already renders.

### [MEDIUM] MAINT-002: The read-only narrowing is invisible to the CI oracle, twice over

**ID:** MAINT-002
**Location:** `scripts/check_agent_frontmatter.py:434`
**Category:** Maintainability
**Effort:** medium
**Fix-policy:** needs-decision

**Problem:**
Two blind spots, both measured.

(a) `_uses_colon_specifier` splits the specifier on whitespace and tests `tokens[0]` only:

```
Bash(git:*)          -> True   (warns)
Bash(git log:*)      -> False  (silent)
Bash(git checkout:*) -> False  (silent)
```

So the four grants `decision-analyst.md` depends on are never inspected, and widening them to `Bash(git:*)` would only add a warning that does not fail the build.

(b) `AGENT_GLOB = "*/agents/*.md"` (`:21`). Commands and skills are **never scanned at all**, so `Bash(sed:*)`, `Bash(npm test:*)`, `Bash(pytest:*)` and `Bash(git:*)` at `fix-all.md:2` — the exact grants SEC-001 and SEC-003 turn on — sit outside every mechanical check in the repository.

**Impact:**
`SKILL.md:262` reasons explicitly that the platform prompt backstops the boundary for declared commands outside the pre-approved list. That reasoning is falsified on this very branch by the frontmatter two files away, and nothing can detect the falsification. The one safety invariant the new agent rests on is protected by a comment.

**Remediation:**
Fix MAINT-008 first, so a new guard does not inherit a non-discriminating oracle. Then add a check comparing the declared boundary at `decision-gate/SKILL.md:253-254` against every `tools:`/`allowed-tools:` line under `plugins/code-review/`, failing on any granted execution primitive absent from the boundary. In-repo precedent: `plugins/code-review/scripts/check-prefix-sync.sh`.

### [MEDIUM] MAINT-003: The release ships with zero executed acceptance evidence

**ID:** MAINT-003
**Location:** `docs/testing/fixtures/needs-decision-e2e/RUNBOOK.md:24`
**Category:** Maintainability
**Effort:** medium
**Fix-policy:** needs-decision

**Problem:**
591 new lines of doctrine and 139 lines of command change ship with no test ever executed. The only acceptance artefact has never been run: no results file exists beside the fixture, `AskUserQuestion` is in `ALWAYS_STRIPPED` (`scripts/check_agent_frontmatter.py:54-57`) so no subagent can drive the sweep, and `RUNBOOK.md:24-39` requires installing `code-review` ≥ 1.18.0 before anything below it is testable.

**Impact:**
For a repository whose deliverable is prose executed by a model, "no acceptance run ever happened" is the branch's largest single risk. It is honestly disclosed, which is not the same as verified.

Two qualifications worth carrying:

- **One action unblocks three things.** Installing the branch build produces SEC-004's probe verdict, this finding's evidence, and the executions that would have caught MAINT-009 and MAINT-010.
- **An executed run would still not reach the security findings.** The fixture has no adversarial case — no hostile `**Location:**`, no path token with a shell metacharacter, no repo-declared command, no missing-path pin. A full run catches MAINT-009 and MAINT-010 and none of SEC-001, SEC-002, SEC-005 or SEC-006.

**Remediation:**
Install the branch build and run both entry runs per `RUNBOOK.md`/`ANSWERS.md` before merge. Add at least one adversarial fixture case (an out-of-tree `**Location:**` exercising SEC-002's path).

### [LOW] MAINT-004: The Step 5 consent understates its own interaction cost
**Status:** ✅ Fixed (2026-08-28)

**ID:** MAINT-004
**Location:** `plugins/code-review/commands/fix-all.md:452`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The offer's description reads "One question per finding, then fix each decision and verify it." But stage 0 asks for a missing location (`SKILL.md:68`, in batches of at most 4, one question per finding), the decision itself is its own `AskUserQuestion` (`SKILL.md:133`), and out-of-boundary approval is "one `AskUserQuestion` per finding" more (`SKILL.md:152`) — up to three per finding after a consent that promised one. The offer also never names the safe exit: interrupting is lossless, because each decision is written to the report as it is made (`SKILL.md:167`).

**Impact:**
The consent moment is the user's only basis for agreeing to an explicitly unbounded stage. Understating it, and not saying how to stop, both bear on that one decision.

**Remediation:**
Reword the description to "at least one question per finding — more where a location must be supplied or an out-of-boundary check approved", and add one sentence naming interruption as a lossless exit.

### [LOW] MAINT-005: A finding-shaped heading with an actionable payload now ships inside a skill

**ID:** MAINT-005
**Location:** `plugins/code-review/skills/decision-gate/SKILL.md:405`
**Category:** Maintainability
**Effort:** trivial
**Fix-policy:** needs-decision

**Problem:**
The example block carries `### [MEDIUM] DOC-004: Doc cites a removed script` followed by a `**Decision:**` line naming two real repository paths (`docs/plugins/qa.md:88`, `README.md:41`) with a delete instruction. Issue extraction (`fix-report.md` Step 1.2) is a heading scan with no code-fence awareness, and single-file mode accepts any path (`files = [$ARGUMENTS]`, `fix-report.md:47`). The replay check (`SKILL.md:38-50`) treats a `**Decision:**` line as a stored decision to dispatch.

**Impact:**
Reachability is remote — a user must point `/fix-report` at the skill file — which is why this is LOW. The class is pre-existing (`commands/review.md:497`, `plugins/qa/skills/report-format/SKILL.md:127,152`), but this is the first instance whose body is an actionable payload rather than an inert illustration.

**Remediation:**
Replace the example's paths with placeholders naming no real file and no delete instruction. Separately, consider making Step 1.2's extraction fence-aware.

### [LOW] MAINT-006: The registered `**Decision-pin:**` grammar cannot express `absent`
**Status:** ✅ Fixed (2026-08-28)

**ID:** MAINT-006
**Location:** `plugins/code-review/skills/decision-gate/SKILL.md:484`
**Category:** Maintainability
**Effort:** easy

**Problem:**
The written form is `**Decision-pin:** block=<sha256> | <path>=<blob-hash>[:edit|:ref] | …`, and `:487` states the bracketed role marker is an alternation, not an option. `SKILL.md:497` requires `<path>=absent` for a path missing from the tree. `absent` is not a `<blob-hash>` and the grammar admits no alternative. `plugins/qa/skills/report-format/SKILL.md:261` inherits the same form verbatim while claiming to reproduce the writer's "written forms" — so this is not a writer/reader divergence, but a gap both copies share.

**Impact:**
Larger than it looks: a traversal or hostile path token is by construction a non-existent or out-of-tree path — the `absent` case — so the integrity control the security audit cleared under A08 degrades precisely where SEC-002's and SEC-006's inputs land, and `SKILL.md:510`'s unpinned fallback then skips replay protection entirely.

**Remediation:**
Use a metavariable — `<path>=<blob-hash-or-absent>[:edit|:ref]` — with one sentence under the fence noting `absent` is written where the path does not exist. Update both copies in the same commit, and confirm stage 4's `absent → present` flip test still discriminates for both roles.

### [LOW] MAINT-007: `/fix-all`'s pre-flight table consumes `**Location:**` without the two-clause read rule
**Status:** ✅ Fixed (2026-08-28)

**ID:** MAINT-007
**Location:** `plugins/code-review/commands/fix-all.md:284`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The table takes the field whole, while every other consumer applies the two-clause rule (`decision-gate/SKILL.md:57-64`, `agents/fix-auto.md:42`, `plugins/qa/commands/loop.md:628`). For a corrected finding the cell renders the whole extended value including the `(was: …)` tail, and a `**Location:** —` renders identically to a missing field.

**Impact:**
Display only — the table is never parsed. It is nonetheless the one consumer among six that does not apply the shared rule.

**Remediation:**
Point the line at the shared rule: read the field by its two-clause rule and render the first backticked token; render `—` where the field is missing or location-less.

### [LOW] MAINT-008: The agent-file floor bump lands exactly on the boundary, and a `<=` mutant survives the suite
**Status:** ✅ Fixed (2026-08-28)

**ID:** MAINT-008
**Location:** `scripts/check_agent_frontmatter.py:86`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The branch raises `EXPECTED_AGENT_FILES` from 25 to 26, which is correct — the tree holds exactly 26 agent files. Three tests touch the constant, exercising trees of 1 and of `EXPECTED_AGENT_FILES + 1`, plus a floor assertion against the real tree that never calls `main()`. Nothing exercises a tree of exactly `EXPECTED_AGENT_FILES`. A mutation of the guard from `<` to `<=` survives all 84 tests.

**Impact:**
Before the bump the tree sat one above the floor, so the mutant would not have misfired. After it, the boundary *is* the operating point, and the mutant would warn on every CI run with no test catching it. Blast radius is one spurious warning — `main()` returns non-zero on errors only — which is why this is LOW. It matters chiefly because this is the one place in the repository where tests actually run, and MAINT-002 proposes building a new guard on top of it.

**Remediation:**
Add a boundary test asserting that a tree of exactly `EXPECTED_AGENT_FILES` produces no warning and exit 0.

### [LOW] MAINT-009: The runbook's BSD-grep diagnosis is wrong on both halves
**Status:** ✅ Fixed (2026-08-28)

**ID:** MAINT-009
**Location:** `docs/testing/fixtures/needs-decision-e2e/RUNBOOK.md:283`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
The runbook states that the pattern `'**Decision:**\|🚫 Rejected'` fails because "**BSD grep on macOS does not support**" BRE alternation, and that it "would silently match nothing and the count would read `0`". Measured on BSD grep 2.6.0-FreeBSD:

```
$ grep -c 'Decision:\|Rejected' file      -> 2, exit 0     # BRE \| works
$ grep -c '**Decision:**\|Rejected' file  -> exit 2        # repetition-operator operand invalid
```

The pattern fails on the leading `**` — a repetition operator with no operand — and it fails **loudly**, never silently as `0`.

**Impact:**
The prescribed replacement (`grep -cE 'Decision:|🚫 Rejected'`) is correct and is what the checklist item uses, so no tester runs the pattern the wrong prose describes — hence LOW. The cost is that a reader carries away a false portability fact and may change working commands elsewhere on the strength of it.

**Remediation:**
Restate the reason: the leading `**` is not a valid BRE, BSD grep exits 2 with `repetition-operator operand invalid`, and BRE `\|` alternation itself works on macOS. Keep the prescribed `-E` command.

### [LOW] MAINT-010: The pristine-snapshot command is not idempotent
**Status:** ✅ Fixed (2026-08-28)

**ID:** MAINT-010
**Location:** `docs/testing/fixtures/needs-decision-e2e/RUNBOOK.md:92`
**Category:** Maintainability
**Effort:** trivial

**Problem:**
`cp -R docs/testing/fixtures/needs-decision-e2e /tmp/nd-pristine` creates the destination only when it does not exist; when it does, it copies **into** it. The runbook is walked twice (two entry runs) and re-walked on any re-attempt, so a second invocation yields `/tmp/nd-pristine/needs-decision-e2e/…`.

**Impact:**
Milder than it first appears: the top-level pristine files remain intact, so the restore still installs a valid `report.md`. The actual damage is an extra untracked directory, which the runbook's own `git status --porcelain` check at `:115-118` catches loudly before anything is dispatched. `:89` also scopes the snapshot to "once, before the first entry run".

**Remediation:**
Prefix with `rm -rf /tmp/nd-pristine`.

---

## Documentation

### [MEDIUM] DOC-001: `/fix-all` doc names two terminal statuses at the Step 1.3 filter; there are now three

**ID:** DOC-001
**Location:** `docs/plugins/code-review.md:111`
**Category:** Documentation
**Drift-class:** decision
**Fix-policy:** needs-decision
**Effort:** trivial

**Problem:**
Step 2 of the walkthrough reads "filters out those already marked `**Status:** ✅ Fixed` or `⚠️ Partially Fixed`". `fix-all.md:154-160` adds `🚫 Rejected` to the filter set and switches the match from whole-line equality to prefix. The same file contradicts itself at `:237`, which correctly states that both fix commands "exclude it at their Step 1.3 filter (matched by prefix…)".

**Impact:**
A reader checking whether a rejected finding can be re-dispatched by a later bulk run gets "no" from `:237` and "yes" from `:111`. This is the exact failure the release's own Upgrade Notes call the worst skew it introduces — silent, and terminal in outcome.

**Remediation:**
Either add `🚫 Rejected` to the enumeration, or replace the inline list with a pointer to the `🚫 Rejected` status section. The extend-vs-pointer choice is why this is not an auto-fix.

### [MEDIUM] DOC-002: `/qa:loop`'s documented fix-set pre-filter omits the rejected drop and states the forbidden whole-line rule

**ID:** DOC-002
**Location:** `docs/plugins/qa.md:206`
**Category:** Documentation
**Drift-class:** decision
**Fix-policy:** needs-decision
**Effort:** easy

**Problem:**
The "Safety guards" bullet reads: "issues with `Location: unknown:0` or missing Location/Problem/Remediation are dropped from the fix-set and reported as 'needs manual location'". `loop.md:623-628` now drops three classes under three recorded reasons, the third being a `**Status:**` line beginning `🚫 Rejected`. The location half is stated in exactly the whole-line terms `loop.md:628` forbids ("Never test the whole line") — a repaired finding whose line is `` **Location:** `src/a.py:12` (was: `unknown:0`) `` contains `unknown:0` and is deliberately *not* dropped. The Algorithm summary at `:190` carries the same two-item framing.

**Impact:**
The one place in `qa.md` that enumerates what `/qa:loop` refuses to dispatch does not mention the terminal status this release exists to protect. The Upgrade Note at `:401-403` covers the *preserve* duty, not the pre-filter drop, so it does not discharge the gap.

**Remediation:**
Name all three drop conditions and their three recorded reasons, and reword the location clause to describe the field's *value* rather than the line's contents. Mirror the rejected condition into the Algorithm summary.

### [LOW] DOC-003: `/fix-all` walkthrough asserts the pre-flight-and-confirm path unconditionally and stops at Step 4

**ID:** DOC-003
**Location:** `docs/plugins/code-review.md:113`
**Category:** Documentation
**Drift-class:** decision
**Fix-policy:** needs-decision
**Effort:** easy

**Problem:**
The enumerated walkthrough runs 1→8 and ends at the final summary table. On the zero-auto path this branch introduces (`fix-all.md:227-236`), the pre-flight summary and the "Proceed with fixing all N issues sequentially?" question are both skipped, and the "Requires user decision" list is printed by Step 5.2 instead. The list also has no step for Step 5, so its last step is not the command's last step. The same claim recurs at `:135`.

**Impact:**
Bounded — that path still ends in a consent gate (`fix-all.md:446-455`), so no user is surprised into an unconsented action, and `:126`, `:135` and the whole Decision Stage section compensate in the same file. Previously that invocation aborted with a pointer to `/fix-report`; the doc records neither the old behaviour nor the new one.

**Remediation:**
Add a step covering Step 5, and qualify the pre-flight and confirmation steps for the zero-auto path. Point at the existing Decision Stage section rather than restating its internals.

### [LOW] DOC-004: Runbook and answer sheet cite `decision-gate/SKILL.md:119` for a row that lives at line 121

**ID:** DOC-004
**Location:** `docs/testing/fixtures/needs-decision-e2e/RUNBOOK.md:245`
**Category:** Documentation
**Drift-class:** dead-reference
**Fix-policy:** needs-decision
**Effort:** trivial

**Problem:**
Both `RUNBOOK.md:245` and `ANSWERS.md:92` quote the row `| dead-reference | remove the mention **vs** restore/update the referent |` and attribute it to `decision-gate/SKILL.md:119`. Line 119 is the table header `| \`Drift-class\` | A and B |`, line 120 the separator; the quoted row is line 121. The sibling citation `decision-analyst.md:28` is correct.

Secondary: `RUNBOOK.md:245-246` attributes the wording "remove the mention **vs** restore/update the referent" to both sources, but `decision-analyst.md:28` reads "remove the mention vs. restore the referent" — no "/update", and `vs.` with a period. `ANSWERS.md:94-96` quotes each source separately and correctly.

**Impact:**
Load-bearing, not decorative: this is one of the two independent sources the fixture uses to pin `[A] = remove the mention` for DOC-005, and `RUNBOOK.md:251-256` instructs the operator to record any deviation as a run or implementation defect. An operator following the citation lands on a header row and cannot confirm the mapping.

**Remediation:**
Change both citations to `:121`, or cite the section (*The `**Alternatives:**` render format*) as `RUNBOOK.md:76-77` already does elsewhere. In `RUNBOOK.md:245-246`, quote the two sources separately as `ANSWERS.md` does.

### [LOW] DOC-005: Runbook cites `fix-all.md:108-110` for two glob lines that sit at 110-111

**ID:** DOC-005
**Location:** `docs/testing/fixtures/needs-decision-e2e/RUNBOOK.md:47`
**Category:** Documentation
**Drift-class:** dead-reference
**Fix-policy:** needs-decision
**Effort:** trivial

**Problem:**
The cited range's first two lines are a blank line and the opening ```` ```bash ```` fence, and it stops one line short of the `docs/testing/reports/*.md` glob it names. The paired `fix-report.md:41-43` citation does contain both glob lines.

**Impact:**
Low. The claim itself is correct — neither directory existed in this repository when the runbook was written, so a bare `/fix-all` did abort at Step 1.1. Only the pointer is off.

**Remediation:**
Cite `fix-all.md:110-111`, or widen to `109-112` to include the fence, matching the `fix-report.md` citation's style.

---

## Performance

Not applicable, and not manufactured. There is no data layer, no queries, no indexes, no connection pool, no pagination surface, no async or blocking I/O and no long-lived process. The real cost analogues were examined and are sound: analyst fan-out is bounded at 8 concurrent per batch with the total and batch shape stated before dispatch; fixer dispatch is deliberately sequential to avoid two concurrent `Edit` calls losing a write (`SKILL.md:185`); each analyst receives one finding rather than the whole report.

One disclosed departure: the decision stage carries no dispatch, wall-clock or token budget (`fix-all.md:457`). The spec names this a deliberate choice against loop-engineering bar item 6 and states it rather than arguing it away.

---

## Cross-Analysis (Security ↔ Quality ↔ Documentation)

Six composites were produced; three change the picture and are recorded here rather than counted as separate findings, to avoid counting the same defect twice.

**The boundary and the grants are one missing invariant, not four grants to tighten.** SEC-001, SEC-003, SEC-004 and MAINT-002 share a root cause: the boundary is declared in a skill, the grants in a command's YAML, and no tool compares them. `check_agent_frontmatter.py` cannot see the command files at all. Tightening any single grant leaves the invariant unenforced and the next grant free to reintroduce the gap. Fix MAINT-008 first so a new guard does not inherit a non-discriminating oracle.

**`**Location:**` is an untrusted-input validation surface with three consumers, three rules and no owner.** SEC-002 found the missing containment check at the one consumer that validates; MAINT-007 found a second consumer that does not validate at all; DOC-002 found a third description that contradicts the implementation. Three domains each saw one third of a single spread-validation defect. Make `decision-gate`'s usability rule normative and singular, add containment there, and have the other two cite it.

**The entire verification surface sits behind one unmet precondition.** SEC-004, SEC-007, MAINT-003, MAINT-009 and MAINT-010 are not five problems but one blocker with five faces — the branch build is not installed. The disclosure asymmetry SEC-007 flags is a *consequence*: the gap that was bumped into got documented, and the gaps never reached did not.

### Coverage gaps worth carrying forward

- The acceptance fixture has no adversarial case, so even a fully executed run reaches none of the security findings.
- No auditor enumerated `Bash` grants across the whole plugin; the analyst's `Skill` grant has no narrowing key, so SEC-004's amplification is wider than the finding states.
- The `path:line` citation defect class (DOC-004, DOC-005) escaped the branch into the audit's own output — one security finding cited `linter-integration/SKILL.md:2` for a line at `:4`. Corrected in SEC-004 above.
- `decision-gate/SKILL.md` owns stages 0–4, four field grammars, the execution boundary, retirement and pinning, and is the locus of six findings. Responsibility concentration in doctrine files was never assessed.

### Rejected by auditors (self-falsification)

- **security** — `Skill` re-acquiring `Edit`/`Write` capability (refuted against all seven skill frontmatters; folded conditionally into SEC-004) — the analyst's prose conflicting with its grant (refuted by reading the file) — the reject-evidence gate's prose-only boundary (recorded as an accepted residual risk at `spec:1395`; re-scoped into SEC-003 and SEC-007) — command injection via the `<report>` operand of the pin pipeline (refuted on data flow: it is `$ARGUMENTS` or a Glob result, not report-derived) — out-of-scope `fix-auto` writes (recorded at `spec:1403`) — bandit B404/B603/B607 in `check_plugin_versions.py` (outside the diff) — SQLi, XSS, CSRF, SSRF, TLS and dependency CVEs (no locus; semgrep returned zero results across three rulesets and no manifest exists) — `Alternatives` text steering the fixer (refuted: gated on `AskUserQuestion`, and `SKILL.md:556` forbids inferring a decision from the recommendation)
- **documentation** — fixture finding locations off by one (all four verified correct) — version drift across the four places (all eight cells correct, badge correct) — `qa.md` omitting the rejected status from its produced-format section (deliberate and recorded at `qa.md:401`) — the entry-point table overstating `/fix-all`'s stage scope — `workflow.md`'s `/fix-all` description (still literally true)
- **quality** — the Decision Stage preamble asymmetry (load-bearing in `fix-report`, unreachable in `fix-all`) — `**Decision-retired:**` having no template (defined by in-place rewrite) — `decision-gate`'s extra "and that path exists" conjunct (stage 0's usability test, not the shared read rule) — `loop.md`'s re-insertion order breaking `**Dispatch:**` adjacency — SOLID, DDD and God-object findings (no code to measure)
- **controller** — "no bulk exit from the sweep" as its own finding (interrupting is a real, lossless exit because decisions persist as made; reduced to the copy half of MAINT-004) — "the unbounded loop violates bar item 6" as a defect (disclosed in the spec as a deliberate choice, and the consent moment names the count and batch shape before anything is dispatched)

Secret scanning clean: trufflehog reported zero findings across both the commit range and the filesystem, and no `.env`, `.pem`, `.key` or credentials files exist. A08 and A10 were reviewed with no finding — the pin mechanism is a well-designed integrity control (working-tree content hashes rather than commit ids, `absent` handled, `:edit`/`:ref` roles with correctly opposite membership), and stage 4's four ordered cases handle failure paths without silent loss.

### Doctrine-gap candidates

- No standard reconciles a pre-approved `Bash(cmd:*)` grant against a prose-stated execution boundary. Every gap between the two removes the last mechanical backstop.
- No standard requires shell-interpolation safety rules where a markdown instruction tells a model to build a command from document-derived text. The repository has the implementation (`allocate-feedback-file.sh`) and the markdown-escaping doctrine, but nothing extends either to shell construction.
- `path:line` citations in repository prose have no freshness rule — 20-plus on this branch, none checked. Candidate: cite by quoted anchor text, or add a resolver that re-greps citations against the text beside them.
- A runbook's shell commands are committed without ever being executed. MAINT-009 and MAINT-010 are both commands written, reasoned about, and never run once.
- `report-format` claims to reproduce the writer's "written forms" but nothing mechanically checks it against `decision-gate`. Candidate: a `check-decision-fields-sync.sh` beside the existing `check-prefix-sync.sh`.
- No rule states which of a plugin's skills `docs/plugins/<name>.md` must enumerate — 4 of 11 are listed and the criterion is unwritten. This is the only reason a "missing Skills entry" finding did not survive.

---

## Notes on this review's own reliability

- `TaskCreate`/`TaskUpdate` are unavailable in this session, so the eight progress tasks the command specifies were not created. This did not affect the review's content.
- Two auditors died on their first dispatch — one on a 600-second stall watchdog, the other when the host slept mid-response. Both were relaunched with narrowed scope and an explicit prohibition on reading the 1430-line spec or the 951-line plan end to end. That narrowing may have cost coverage.
- One security finding's own citation was off by two lines — the same defect class DOC-004 and DOC-005 report, reaching the audit's output rather than only the branch. Corrected in SEC-004.
- MAINT-009 overturns a ruling made during this branch's own planning phase: the BSD-grep diagnosis was wrong, and its reasoning is now committed runbook prose.

---

## Addendum — fix batch of 2026-08-28

Eleven `auto` findings were fixed in one `/fix-all` run. Two further edits were made
that are **not** findings above, and are recorded here so the diff matches the report.

**REG-001 — a regression this batch introduced, found and fixed within it.**
SEC-006's fix added a third `**Decision-pin:**` value, `unpinnable`, for a path token
the new sanitisation rule rejects. Stage 4 — which opens by declaring itself the single
authority for how a dispatch is graded — was deliberately out of scope for that fix and
was left contradicting it in three places: observation 1 hashed *every* path the pin
line names, including `unpinnable` ones, reconstructing the command sanitisation had
refused and recording `absent` for it; the expected set admitted an `unpinnable` entry
marked `:edit`; and the unpinned re-derivation built commands from tokens that never
passed the allow-list. Three clauses were added to stage 4 — the section yielded, not
the pin section, since reversing that direction would have undone SEC-002 and SEC-006.
The third defect was found by reading, not reported by any auditor.

**MAINT-001b — the half of MAINT-001 the finding did not scope.**
MAINT-001 was written against `/fix-all`. `/fix-report` carries the twin Step 4.1.5,
status-only with the same three reasons, and its decided findings reach the same two
stage-4 cases that write no `**Status:**` line. Both commands now carry the fourth
reason `attempt-entry-missing`, and the two procedures were diffed line by line: eight
residual differences remain, each traceable to a real flow or naming difference rather
than drift.

**MAINT-011 — the `**Verification:**` line, closed after the addendum was first written.**
Stage 4 writes that line for every graded finding — alongside `**Status:**` for the two
cases that write one, and in the attempt-entry write for the two that do not. Neither
command verified it. Both now do, under a fifth reason `verification-line-missing`, with
rejected findings explicitly outside the check (`reject` never dispatches, so it carries
no such line). One scoping detail the finding did not state and the fix required:
`/fix-all` runs Step 4.1.5 twice — at Step 4 over a pure-`auto` batch that has no
`**Verification:**` lines at all, and again at Step 5.5 over the decision batch — so the
check names the decision batch, or the first run would flag every `auto` finding.

**REG-002 — a second regression of the same shape as REG-001, found during the spec sync.**
SEC-006 added a ninth run-summary disclosure to the skill (an unpinnable path) and left
both commands claiming "the eight disclosures" with no row to print it. The skill raised
something nothing rendered. Both blocks — which are required to be byte-identical to each
other — now carry the ninth row in the skill's enumeration order, verified identical
before and after the edit.

**The spec has been synced** to all six deltas, across the four places it restates each
rule: 26 occurrences in the flow prose, the Delivery table, the Decision record and the
Oracle table. A partial sync would have made the spec self-contradictory, which is worse
than the uniform staleness it had. Worth recording that this repository's own precedent
(`ce2f15b`) is to *drop* a spec once its work has landed rather than maintain it; syncing
was the owner's call, and the maintenance obligation it creates is real.

**Still open, and deliberately not fixed:**

- `docs/superpowers/plans/2026-08-28-…` contradicts all six deltas — `:179` carries the
  superseded pin grammar byte-for-byte — and every one of its spec line-anchors is now
  shifted by the sync. Sync or drop is the same decision the spec faced.
- `spec:747` says stage 4's write-back is "command-owned"; the shipped skill now declares
  itself the grading authority with only the *mechanical* write command-owned. Not false
  as written, but it understates the skill.
- `/fix-report`'s checklist option description (`:169`, `:190`) still specifies its
  location value with no stated provenance — a differently-shaped relative of MAINT-007.
- The e2e fixture exercises `Location: —` only, so nothing in it reaches the new
  containment path, and no adversarial case reaches SEC-001, SEC-005 or SEC-006 at all.
**ARCH-001 resolved: `code-review` 1.17.3 → 2.0.0.** The owner ruled MAJOR. All four
parity cells updated, plus every live prose reference that the number would otherwise
falsify — the Upgrade Notes in `code-review.md`, the pairing note in `qa.md`, the fixture
RUNBOOK's install prerequisite, and seven references in the spec, whose Delivery section
now carries the MAJOR rationale in place of the MINOR one. `qa` stays at 2.6.0: it is the
reader absorbing a new value, and the pin-grammar correction folds into that unreleased
MINOR. Recorded honestly: spec review raised this twice (SR-077, SR-102) and refuted it
both times; the Challenger reversed that and the owner upheld the reversal.

Four of the eleven remediations were corrected by the fixer that carried them out:
`--` is unsafe with BSD `sed`; `-E` does not rescue the grep pattern (dropping the
asterisks does); an interrupted sweep is lossless for decisions but not for a dispatch
in flight; and `rm -rf` before the snapshot trades a loud harmless failure for a silent
destructive one, so the clean-source precondition had to stay.

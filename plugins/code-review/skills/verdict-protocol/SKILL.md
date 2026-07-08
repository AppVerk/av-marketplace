---
name: verdict-protocol
description: "Use when writing or reviewing the definition of a reporting agent or command (a review, audit, verification, or test-run agent) to set its closing contract: a typed closed verdict computed by a declared predicate over finding categories, a blocking-triage axis distinct from severity, and machine-locatable status."
---

# Verdict Protocol

## What this is, and when to invoke it

The closing contract of a reporting agent is the last line its consumer parses — and the first thing that silently rots into free text. This skill sets the bar for that contract **at authoring time**: invoke it when writing or reviewing an agent's or command's *definition*, not during an ordinary review run.

Boundary: this skill owns the closing contract (verdict line, predicate, triage axis). The pre-report process — the self-falsification battery and its "Rejected after verification" / "Doctrine-gap candidates" sections — is owned by `finding-falsification` in this plugin; reference those sections, never redefine them.

## The minimum bar (MUST)

1. **Closed vocabulary.** The definition declares an enumerated verdict set (e.g. `APPROVED | NEEDS_FIXES | BLOCKED`); free-text verdicts are invalid — a consumer cannot route prose.
2. **Verdict is computed, not chosen.** Each value declares its deciding predicate over finding categories (e.g. APPROVED ⇔ zero Required findings; BLOCKED — exhaustion — takes priority over NEEDS_FIXES). An agent cannot hand-pick APPROVED while Required findings stand.
3. **Exhaustion semantics.** Bounded-round agents declare what round exhaustion yields (e.g. BLOCKED after N rounds without progress) — distinct from success and from failure; "ran out of budget" must never read as either.
4. **Caveated verdicts.** A pass scoped to what was verifiable ("complete as far as statically verifiable") must route its unverifiable remainder onward explicitly.
5. **Consumer routing.** For every verdict value, the consumer's reaction is defined at authoring time; a verdict nobody routes is dead weight.
6. **Triage vs severity.** Findings carry a **Required / Advised / Optional** axis (does this block?) distinct from severity (how bad is it?). *(Rider — prescribes beyond every current reference: no marketplace agent carries this axis today; adopt when authoring new contracts.)*
7. **Machine-locatable.** The verdict is one line, fixed vocabulary; a verdict without cited findings/evidence is invalid.

## Anti-patterns

- **The prose closer** — "overall this looks mostly fine" — unparseable, unfalsifiable, unroutable.
- **The chosen verdict** — APPROVED handed out while Required findings stand.
- **Exhaustion laundered as an outcome** — budget-out reported as failure (or worse, success).
- **The unrouted value** — a verdict no consumer reacts to.
- **Axis collapse** — inferring "does this block?" from severity alone.
- **Transcribing another contract's enum into your doc** — cite by pointer; a transcribed enumeration is exactly the drift `docs-fact-registry` exists to catch.

## Reference points — cited by pointer, never transcribed

No in-repo agent implements the full closed-verdict-with-predicate contract today; the worked example below is *(Prospective)*. Partial references:

- `plugins/code-review/agents/challenger.md`, **Output Format** section — `confirmed | downgraded | false-positive`: a closed vocabulary (bar item 1) but *per-finding*, not agent-closing. A contrast case, like qa's per-scenario PASS/FAIL/SKIP.
- If the qa plugin is installed: `plugins/qa/commands/loop.md`, Step 5.2 "Loop Summary" template, the `**Result:**` line — `Pass | Fail | Budget Exhausted | Stopped`: a closed final vocabulary with exhaustion semantics (bar items 1 + 3).
- Boundary: qa's `report-format` skill (if installed) owns the report *file* — structure, QA-XXX IDs, severity table, parser compatibility. This skill owns the agent's *closing contract* only.

## Worked example *(Prospective)*

A verification agent's definition declares:

```markdown
Verdict set: APPROVED | NEEDS_FIXES | BLOCKED
- APPROVED   ⇔ zero Required findings (Advised/Optional may remain — list them)
- NEEDS_FIXES ⇔ ≥1 Required finding and fix rounds remain
- BLOCKED    ⇔ Required findings stand after 3 rounds without progress
Routing: APPROVED → proceed; NEEDS_FIXES → dispatch fixer, re-verify; BLOCKED → human escalation.
Closing line: `Verdict: <value> — <n> Required / <n> Advised / <n> Optional (evidence: <IDs>)`
```

## Review checklist

Paste into any reporting-contract review:

- [ ] 1. Verdict set enumerated and closed
- [ ] 2. Every value carries a deciding predicate over finding categories
- [ ] 3. Exhaustion outcome declared, distinct from success and failure
- [ ] 4. Caveated passes route their unverified remainder
- [ ] 5. Every value has a defined consumer reaction
- [ ] 6. Required/Advised/Optional triage axis present *(rider: new contracts)*
- [ ] 7. One-line, fixed-vocabulary verdict, evidence-backed

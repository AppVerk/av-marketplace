---
name: finding-falsification
description: Use when authoring or reviewing any code-review reporting agent, or when a code-review agent is about to report findings — mandates a self-falsification pass: every finding survives a refutation battery before reporting; rejected findings and doctrine-gap candidates are recorded in dedicated sections, never silently dropped.
---

# Finding Falsification

## What this is, and when to invoke it

A reported finding is a claim. This skill makes every claim survive an attempt to refute it *by its own author* before it reaches the report. The battery runs per finding; the disposition rules make rejected work visible instead of silently discarded — a reader who cannot see what was rejected cannot calibrate trust in what was accepted.

Invoke when authoring or reviewing a code-review reporting agent, and at report time inside the wired agents (security-auditor, code-quality-auditor, documentation-auditor, challenger) before findings are returned.

## The refutation battery (MUST, per finding)

1. **Toolchain check.** Is this already enforced by a linter/type-checker/formatter? Don't duplicate the toolchain — duplicated findings train readers to skim.
2. **Backing check.** Does it cite a concrete standard (file + section) OR an established code pattern, operationalized as **≥3 occurrences outside the diff (grep)**? "Established" without a count is vibes.
3. **Evidence-elsewhere check.** Could the evidence live where you didn't look — another file, a test, existing code outside the diff? Grep before you report MISSING.
4. **Deliberate-omission check.** Is the "gap" an explicit no-op or deferral recorded in the plan or ticket? A recorded decision is not a defect.
5. **Verifiability-class check.** Is this actually unverifiable in this scope (runtime/visual behavior) mislabeled as a static finding? Route it onward — name the venue in the disposition reason — don't report it as a violation.
6. **Citation check.** Does a deviation finding cite the exact source line it deviates from (spec/plan/standard)? "It seems wrong" is not a finding.

## Disposition (MUST, three buckets)

- **(a) Survives** → report it.
- **(b) Fails the battery** → list under **"Rejected after verification"** with a one-line reason. Never silently drop: without this list, the next reviewer re-derives and re-rejects the same ghosts, forever.
- **(c) Real signal, no backing rule** → list under **"Doctrine-gap candidates"** — a candidate for a new standard. Distinct from Rejected: not a violation, not noise.

Both sections are emitted on every run; when empty, render `None` — absence of rejections is itself information.

## Scope and exemptions

Applies to code-review's four wired reporting agents. Recorded exemptions:

- **qa's fe/be-testers** (if installed) report findings but follow qa's own per-scenario contract.
- **cross-verifier** — its composite findings derive from already-vetted findings and cite their basis IDs; a second battery would double-verify.
- **feedback-analyzer** — follows `/analyze-feedback`'s own validity contract.
- **challenger** *(partial)* — runs the battery on its own verdicts but emits no Rejected/Doctrine-gap sections: a self-rejected false-positive or downgrade call resolves back to `confirmed` in its Challenge Results, so the reversal is visible in the disposition itself.

## Relationship to the challenger, and the contract boundary

The challenger is an *external* adversarial pass over other agents' findings; this skill is *self*-falsification before reporting. Complementary, not duplicate — and the challenger is not a conforming reference implementation. The closing contract that consumes these sections (verdict line, verdict predicate, blocking triage) is owned by the `verdict-protocol` skill in this plugin; this skill owns only the pre-report process.

## Anti-patterns

- **Silent drop** — deleting a finding you no longer believe without recording why.
- **"Established pattern" without a count** — grep or it didn't happen.
- **Reporting MISSING without searching elsewhere** — the most common false positive.
- **Filing unverifiable-in-scope items as violations** instead of routing them.
- **Treating a doctrine gap as noise** — bucket (c) is how standards grow; losing it wastes the strongest signal a review produces.

## Worked example *(Prospective)*

*(Prospective: no in-repo agent conforms yet; genericized from the source pattern.)* A reviewer drafts "missing null-guard in `parse()`". Battery: toolchain — strict mode doesn't cover this path (passes); backing — grep finds 4 guard occurrences outside the diff (passes); evidence-elsewhere — grep finds the guard upstream at the call site (FAILS). Disposition: bucket (b) — `Rejected after verification: null-guard exists at call site (caller.ts:88)`.

## Review checklist

Paste into any reporting-agent review:

- [ ] 1. Every finding ran the six-check battery before reporting
- [ ] 2. Pattern-backed findings carry a citation or a ≥3-occurrence grep count
- [ ] 3. MISSING findings were grepped elsewhere first
- [ ] 4. Deliberate omissions checked against plan/ticket
- [ ] 5. Unverifiable-in-scope items routed (venue named), not reported as violations
- [ ] 6. "Rejected after verification" present on every run (`None` allowed, never absent)
- [ ] 7. "Doctrine-gap candidates" present and distinct from Rejected
- [ ] 8. Any claimed exemption matches the recorded list above

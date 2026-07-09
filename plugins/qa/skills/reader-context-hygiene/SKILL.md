---
name: reader-context-hygiene
description: Use when authoring or reviewing a fan-out reader/scout agent that ingests an external source (a design board, a live site, a large document) on behalf of a consumer.
---

# Reader Context Hygiene

## What a reader is, and when to invoke this skill

A reader (scout) agent ingests an external source — a design board, a live site, a large document — on behalf of a consumer that will make decisions from the result. The reader's return message IS its interface; everything the orchestrator will act on must be *in* that message, and everything it won't act on must stay *out* of it. Invoke this skill when authoring or reviewing any fan-out reader agent, before it ships. This is authoring-time doctrine (like `loop-engineering`): current qa testers follow their own per-scenario contract and are exempt — see the caveat below.

## The minimum bar (MUST)

1. **Bulk to disk, signals inline.** The full artifact is written to disk (a gitignored workspace, or a *subdirectory* of a report directory — never at a path a consumer globs for reports, e.g. `docs/testing/reports/*.md`); the return message carries the path + a 3–5 sentence summary + top-N takeaways **plus every decision-relevant status as a named inline field** (e.g. `items_extracted=214`, `MISSING_DESIGN=<screen>`, `needs_escalation=yes|no`, coverage gaps). A gate flag buried in the artifact file is a gate the orchestrator never sees — the exact failure this contract exists to prevent.
2. **Never inline bulk.** No base64, no full dumps; verbose evidence (screenshots, response bodies, board dumps) is referenced by path.
3. **Fail-closed access.** No access / auth failure → STOP with a diagnostic; never guess or synthesize the missing content. A fabricated board is worse than no board.
4. **Idempotent output.** Re-running overwrites the artifact as a fresh snapshot — no accumulating duplicates.
5. **Declared truncation.** When the source exceeds a size limit, stop at the limit and declare what was skipped. Silent truncation reads as full coverage.

## Anti-patterns

- **Signal buried in the artifact** — the consumer reads a 3-line summary, misses the `MISSING_DESIGN` flag on line 400 of the dump, and green-lights an unreviewable screen.
- **Inlined bulk** — a base64 screenshot in the return message costs the whole pipeline's context for one reader's convenience.
- **Guessing on auth failure** — synthesizing "what the board probably says" launders a fetch error into confident fiction.
- **Append-mode artifacts** — re-runs that accumulate stale snapshots make the newest state unfindable.
- **Silent truncation** — "42 items extracted" from a 400-item board, undeclared.

## Recorded caveat — current qa testers

qa's fe/be-testers cannot fully adopt bar item 1: `/qa:run` assembles the report from per-scenario detail returned inline, an aggregation constraint that is out of scope to restructure. They follow the spirit where applicable (fe-testing: screenshots to disk, referenced by path; be-testing: long response bodies to disk). Primary consumers are **future** reader agents.

## Worked example *(Prospective)*

*(Prospective: no conforming in-repo reader exists today; genericized from the source pattern.)* A design-board reader returns:

```
Artifact: docs/testing/reports/snapshots/board-snapshot.md (214 items, fresh overwrite)
Summary: <3–5 sentences>
Signals: items_extracted=214 | frames_skipped=2 (size limit — listed in artifact) | MISSING_DESIGN=checkout-v2 | needs_escalation=no
```

On auth failure it returns instead: `STOP: board unreachable (401). No content synthesized. Fix access and re-run.`

## Review checklist

Paste into any reader-agent review:

- [ ] 1. Bulk artifact on disk; return message carries path + summary + takeaways
- [ ] 2. Every decision-relevant status is a named inline field in the return message
- [ ] 3. No base64 / full dumps inline; evidence referenced by path
- [ ] 4. Access failure → STOP with diagnostic; nothing synthesized
- [ ] 5. Re-runs overwrite the artifact (idempotent)
- [ ] 6. Truncation declared with what was skipped

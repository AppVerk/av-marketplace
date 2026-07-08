---
name: docs-fact-registry
description: Use when checking or reporting docs↔code drift — a declarative registry (claim → source of truth → policy) with a three-way classification: mechanical facts auto-fixable, judgment calls escalated, dead references flagged as inconsistencies whose fix is a decision.
---

# Docs Fact Registry

## What this is, and when to invoke it

Docs drift silently, and ad-hoc drift checking produces the two classic failures: facts "verified" against the very doc under check, and judgment calls silently overwritten by an auto-fixer. This skill makes drift-checking declarative — a registry of claims, each with a source of truth and a policy — and keeps the policy attached to the finding all the way to the fix decision.

Invoke when checking or reporting docs↔code drift (the documentation-auditor preloads this skill), or when authoring anything that auto-updates documentation.

## The registry (MUST)

Drift is checked against a registry: *claim in docs → source of truth in code → policy*. The checking agent instantiates the table **in-context per run** from the docs under review — no checked-in registry file is required (a project MAY check one in; use it if present).

| Claim (in docs) | Source of truth (in code) | Policy |
|---|---|---|
| version string in a plugin table row | manifest `version` field | mechanical |
| "N plugins" count / badge | manifest entry count | mechanical |
| script path cited in a guide | file exists at that path | dead-reference check |
| "coverage ≥ 80%" aspiration | CI config threshold | decision |

## Three-way classification (MUST — not binary)

- **mechanical** — uniquely derivable fact (version string, script name, file count) → auto-fixable.
- **decision** — judgment call (aspirational threshold, descriptive prose, "is docs or code the target?") → escalate; never silently overwrite.
- **dead reference** — docs cite code that no longer exists: mechanically *detectable*, but the fix (delete the mention vs restore the code) is a **decision** — never auto-delete doc content.

Findings retain the class end-to-end: each carries `**Drift-class:** mechanical | decision | dead-reference` **and** the derived routing field `**Fix-policy:** auto | needs-decision` (mechanical → auto; decision and dead-reference → needs-decision). Collapsing to the binary at the finding level erases the delete-vs-restore rationale exactly where the user decides. Missing-entry findings (new functionality with no doc — no registry claim to classify) carry `Drift-class: decision`: authoring new doc content is a judgment call, never an auto-fix.

## Rules (MUST)

1. **Path vs line.** An unambiguously moved file path is mechanical; a cited line number always escalates — it shifts under every edit.
2. **Numbers from sources, never from the doc under check.** Recompute via the checking agent's available tools: Glob result counts, manifest field reads. A count copied from the doc "verifies" its own drift.

## Anti-patterns

- **Self-referential verification** — checking a claim against the doc that makes it.
- **Auto-deleting doc content** because its referent vanished — the mention may be the only surviving record of intent.
- **Auto-editing an aspiration to match reality** — that silently lowers the bar instead of flagging the miss.
- **Transcribing an enumeration between docs** — the duplicate is a second drift site; cite by pointer.
- **Dropping the class before the fix decision** — routing on the binary alone forfeits the delete-vs-restore context.

## Worked example *(Prospective)*

*(Prospective: genericized from the source pattern.)* Registry excerpt for one run: (1) README says plugin version `1.4.0`, manifest says `1.4.1` → mechanical → `Fix-policy: auto`. (2) Guide cites `scripts/install.sh`; Glob finds no such file → dead reference → `Fix-policy: needs-decision` (delete the mention, or restore the script?). (3) README promises "responses under 100 ms"; no source of truth in code → decision → `Fix-policy: needs-decision`.

## Review checklist

Paste into any docs-drift checker review:

- [ ] 1. Registry instantiated per run (claim → source → policy), not implied
- [ ] 2. Every finding classified three-way, not pass/fail
- [ ] 3. Findings carry both `Drift-class` and derived `Fix-policy`
- [ ] 4. Dead references escalate — never auto-deleted
- [ ] 5. Missing-entry findings classified `decision`
- [ ] 6. Line-number citations escalate; moved paths may auto-fix
- [ ] 7. Every number recomputed from its source, never from the doc under check

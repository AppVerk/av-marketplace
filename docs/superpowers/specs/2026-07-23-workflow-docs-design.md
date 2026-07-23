# Workflow Documentation Design

**Date:** 2026-07-23
**Status:** Draft
**Scope:** Documentation only — `README.md` + new `docs/workflow.md`

## Goal

The README currently presents the marketplace as a list of independent
plugins. Its real strength is that the plugins compose into one development
harness: each stage produces an artifact the next stage consumes (spec →
spec-review report → implementation → QA report → review report → fixes by
ID → commit). This design adds documentation that teaches that cycle.

## Motivation

- A new user installing the marketplace sees ten plugins and no guidance on
  how they fit together or in what order to use them.
- The artifact hand-offs (QA reports compatible with code-review's `/fix`,
  superutils consuming superpowers specs) are documented per-plugin but the
  cross-plugin flow is documented nowhere.

## Non-Goals

- No changes to any plugin (no version bumps, no `marketplace.json` changes).
- No changes to `docs/plugins/*.md` — flags, option tables, and edge-case
  details stay there; the new document links to them instead of duplicating.
- No change to the plugin count badge or the Available Plugins table.

## Design

### 1. `README.md` changes

- **Opening paragraph** — replace the generic one-liner with a description
  of the harness idea: plugins designed to work together as a full
  development cycle — from idea and spec, through TDD implementation and QA,
  to code review and commit — with artifacts flowing between stages.
- **New `## Workflow` section** (after Installation, before Available
  Plugins): a Mermaid diagram of the cycle
  (`Idea → Spec → Spec review → Implement → QA → Code review → Commit/PR`),
  two–three sentences on the artifact flow, and a link to
  `docs/workflow.md`.
- **Documentation section** — add a "Recommended Workflow" link.

### 2. New `docs/workflow.md` — "the lifecycle of a feature"

A narrative end-to-end guide. Each stage follows the same schema:
*purpose → command → artifact produced → what the next stage consumes*.

- **Intro + Prerequisites.** The marketplace installed; the `superpowers`
  plugin (official Claude Code plugin marketplace) as **strongly
  recommended** — not required. Without it the cycle starts at the
  implementation stage and the spec-review stage has nothing to review.
- **Stage 1 — Idea → Spec** *(superpowers, strongly recommended)*:
  brainstorming produces
  `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`.
- **Stage 2 — Spec review** *(superutils)*: `/superutils:spec-review` runs
  the closed review loop; report and sidecar land in
  `docs/superpowers/specs/reviews/`; terminal statuses `CONVERGED` /
  `STOPPED(...)`.
- **Stage 3 — Plan & implement**: the stack-specific `/develop` command
  (frontend-developer, php-developer, python-developer), which enforces
  coding standards and TDD, is the recommended path when a matching
  developer plugin is installed; the superpowers writing-plans / TDD flow
  covers stacks without one, or a plan-first, language-agnostic flow.
- **Stage 4 — QA** *(qa)*: **`/qa:loop` is the recommended first choice** —
  it generates a plan for the branch when none exists, runs it, auto-fixes
  failures, and re-tests until green or budget exhausted. The manual
  variant `/qa:create-plan` → `/qa:run` is for when you want to inspect or
  edit the plan before execution. Artifacts: plans in
  `docs/testing/plans/`, reports with `QA-XXX` issue IDs in
  `docs/testing/reports/`.
- **Stage 5 — Code review** *(code-review)*: `/review` produces a report in
  `docs/reviews/` with `SEC/PERF/ARCH/MAINT/DOC-XXX` IDs; fixes via
  `/fix <ID>`, `/fix-report` (auto-merges review and QA reports), or
  `/fix-all` (skips `needs-decision`).
- **Stage 6 — Commit & PR** *(commit)*: `/commit` generates Conventional
  Commits messages; push guards apply. PR feedback is handled with the
  code-review plugin's `/analyze-feedback` (linked to
  `docs/plugins/code-review.md`, which documents it).
- **Cheat sheet**: table `stage → plugin → command → artifact`, with
  `/qa:loop` listed as the QA entry point.
- **Outside the cycle**: web-auditor (`/audit`), security-pipeline
  (`/setup`), sequentialthinking (MCP server used by other plugins, e.g.
  superutils decomposition).

### Language and tone

Repository artifacts in English, matching the existing docs style
(imperative headings, fenced command examples, tables for reference data).

## Error handling / edge cases

- **superpowers not installed**: workflow.md states the cycle degrades
  gracefully — start at Stage 3; Stages 1–2 are skipped.
- **Mermaid rendering**: GitHub renders Mermaid natively; the diagram also
  reads acceptably as plain text for terminal readers.

## Success criteria

- `docs/workflow.md` documents every stage (1–6) with, for each: its
  purpose, the exact command, the artifact path produced, and what the next
  stage consumes. Each stage is followable from `workflow.md` alone,
  referencing `docs/plugins/*.md` only for flags and edge cases, and the
  superpowers-absent path (start at Stage 3) is covered.
- `workflow.md` reproduces no flag tables, option lists, or edge-case
  descriptions from `docs/plugins/*.md`, verbatim or near-verbatim;
  per-stage text is limited to purpose, command names, artifact paths,
  one-line behavioral summaries, and cross-stage hand-offs.

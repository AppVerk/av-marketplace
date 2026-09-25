# Adoption mode

Adoption moves an existing manual setup (pipeline, agents, commands) to the `av-*` skills with overlays. The knowledge stays; only the custom orchestration goes away.

Adoption starts when the scan returns `ai_setup.orchestration: true` and the repo has no `.ai/av.config.json`. A repo with docs only, without agents, commands and a pipeline, goes through COMPLETION mode, not adoption.

## Principle

Keep the knowledge, replace the orchestration.
- Knowledge is rules, conventions, review axes, pitfalls, scripts and thresholds.
- Orchestration is phases, statuses, handoffs between agents and handoff formats. The generic skills do it themselves.

**The stricter rule wins.** When the old setup was stricter than the default `av-*` behavior, keep that as a tightening in the overlay. Example: "with high risk, a plan is required", although by default only LARGE mode requires a plan. Adoption must not quietly weaken the team's process.

## Step 1: Inventory

From the scan result, take `ai_setup`: agents, commands, skills, prompts, `pipeline_docs`, `.codex`, `.agents/skills`, `githooks`, `claude_other`, hooks and `enabled_plugins`. Read every file. Read them yourself while the files total below about 5000 lines: overlays need the rules almost verbatim, and passing them through a subagent saves no context. Above that, split the reading across subagents. Each writes a rule extract with line ranges (`file:from-to`) to a file in `<tmp>/` and returns only the path and a table of contents. Read the extracts selectively.

Also find the files that **refer to** the orchestration:

```bash
grep -rlwE "<agent names>|<command names>|<project skill names>|implementation-pipeline|pipeline_state|orkiestrator|orchestrator|BOUNDED|FULL|SELF_CHECK" \
  --include='*.md' --include='*.html' --include='*.json' --include='*.toml' . | grep -v -e workspace/ -e sessions/
grep -rlnE "[Ff]az[aeiy] [0-9]|[Pp]hase [0-9]" --include='*.md' . | grep -v -e workspace/ -e sessions/
```

The patterns are quoted, because zsh expands `*.md` without quotes. `-w` protects against hits like `architect` in the word "architecture". Names that are ordinary words (e.g. the `translate` skill) give hits in code and examples. Review every hit; it is only a candidate for UPDATE.

**Check that the rules you move are still current.** A rule about known debt or a known false alarm may be outdated (e.g. the debt was fixed in recent commits). Check it in the code. Put an outdated rule into "Deliberately not moved".

## Step 2: Classification

Actions come from `references/plan-format.md`. Classify by content, not by name. An agent named "reviewer" may contain implementation rules, and a skill named "lint-gate" may be a pipeline wrapper.

Typical mapping:

| Artifact | Action | Target |
|---|---|---|
| pipeline document (e.g. `.ai/implementation-pipeline.md`, `docs/pipeline.md`) | CONVERT | modes and thresholds -> `av-implement.md`; findings format -> `av-review.md`; gates -> `validation`; the rest to "Knowledge that gets lost" |
| plan command (`feature_plan`, `/architect`) | CONVERT | required plan sections -> `av-plan.md` |
| implementation and resume commands (`feature_implement`, `feature_continue`) | CONVERT | rules -> `av-implement.md` |
| docs commands (`docs_update`, `docs_audit`) | CONVERT | code->docs map, audit perspectives -> `av-docs-sync.md` |
| build command (`build`) | CONVERT | command -> `validation.commands.build` |
| implementing agent (`backend-php`, `frontend-designer`, `js-specialist`, `ios-data-layer`, `ios-presentation`, `angular-developer`) | CONVERT | file scope -> role in `roles` in the config; layer rules -> role skill `.claude/skills/<prefix>-<role>/` (`references/role-skills.md`) |
| review agent (`swift-reviewer`, `code-reviewer`, `view-reviewer`, `angular-reviewer`) | CONVERT | axes and checklists -> `code-review.md`; check tools and owners -> `av-review.md` |
| security agent (`security-reviewer`, `security-auditor`) | CONVERT | rules -> security axis in `code-review.md` |
| agent that verifies with commands (`build-verifier`, `test-runner`, `simulator-verifier`, `e2e-test-runner`) | CONVERT | commands -> `validation`; result interpretation -> `av-verify.md` |
| agent that verifies with MCP tools (`visual-verifier` with Playwright, comparison with Figma) | CONVERT | procedure -> `av-verify.md`, section "Tool checks", with the condition for when it is required. It gives no `gate.sh` evidence, but `av-implement` must run it and report it |
| environment cleanup rules by container or process name | move with a filter | only with a filter on this checkout's directory; otherwise they hit other people's environments |
| acceptance agent against the plan (`acceptance-verifier`) | CONVERT | criteria -> "Plan compliance" axis in `code-review.md`; `av-review` checks it with `--run` |
| `docs-keeper`, `docs-auditor` | CONVERT | -> `av-docs-sync.md` |
| translation agent (`i18n-guardian`) | KEEP or CONVERT | KEEP when it does work (adds keys in many language files, syncs with a tool like Lokalise); CONVERT when it only checks rules; then rules -> `code-review.md` and required steps |
| tool agents (`miro-reader`, `figma-reader`) | KEEP or UPDATE | not part of the pipeline; UPDATE when they refer to deleted agents, phases or commands |
| tool project skills (`translate`, `read-miro`, `writing-tests`, `angular-templates`) | KEEP or UPDATE | overlays may point to them; UPDATE references as above |
| project skills that wrap the pipeline (refer to RUN_ID, phases, a manifest) | CONVERT | rules -> overlay; the wrapper DROP, or UPDATE when it also contains a tool |
| session summary prompt (`.claude/prompts/post-session-review.md`) | KEEP when a hook uses it; otherwise CONVERT | -> `av-implement.md` overlay, section "Learnings" (step 10 of `av-implement` reads it) |
| pipeline scripts (`pipeline_state.py`, `pipeline_check.py`) and their tests | DROP or TODO | `gate.sh` replaces them; deleting needs approval; without approval, put them into TODO |
| tool scripts created for work with the agent, outside `paths.scripts` (check: `git log --diff-filter=A` and no file on `git.baseBranch`) | MOVE | move with `git mv` to `paths.scripts`; fix the root detection in the script (`dirname "$0"`, `__file__`, `__dir__`) and all references in docs, config and tests, including the forms `./scripts/` and `. ./scripts/` (source); after the move, run the `quick` gate; propose rewriting Python scripts in bash (`references/config-schema.md`, field `paths.scripts`) |
| tool scripts (`project_lint.sh`, `verify.sh`, `ui_test.sh`) | KEEP | they go to `validation` |
| `.ai/agents.md` or `docs/agents.md` | UPDATE | description of the av-* skills and overlays instead of the agent roster |
| docs that refer to agents and commands (`README.md`, `feature-checklist.md`, `code-templates.md`, `commands.md`) | UPDATE | replace the names with av-* skills; list of files from the grep in step 1 |
| pipeline section in `CLAUDE.md` | UPDATE | -> "Working with the agent" section |
| critical rules and response style in `CLAUDE.md` | KEEP | these are team decisions |
| `.codex/agents/*.toml` | DROP | Codex gets skills through `.agents/skills` |
| `.codex/config.toml`, `.mcp.json`, `settings.json` | KEEP | environment and MCP |
| `.agents/skills/*` | MERGE | unique skills -> `.claude/skills/`, then a symlink |
| `sessions/learnings.md`, files in `workspace/` | KEEP | team history |
| `workspace/README.md` | UPDATE | description of the `runs/`, `plans/`, `reports/` directories instead of the old pipeline phases |
| empty `.claude/skills/` directory after conversion | DROP | without project skills there is no `.agents/skills` symlink |
| docs sections with incoming links (e.g. `agents.md#section`) | move, do not delete | move the section to the topic owner file and fix the links |
| `docs/onboarding.html` and other HTML materials | UPDATE or TODO | references to the old process; leave large generated files as TODO with the regeneration command |

## Mode mapping

When the old pipeline had its own modes, map them in the plan (section "Mode mapping"). Typically:

| Old | New | Notes |
|---|---|---|
| mode without a reviewer, with a deterministic test (e.g. SELF_CHECK) | SMALL | entry conditions of the old mode -> "SMALL mode conditions"; when the old mode skipped review, write "no" in "Review in SMALL mode" |
| one implementer + reviewer (e.g. BOUNDED) | STANDARD | |
| "full pipeline" with one implementer, tests, security review and a required plan | STANDARD with tightenings | in "Mode selection": plan required, `full` gate before the report, security axis always. Do not map to LARGE, because LARGE means several roles, and then STANDARD would never be used |
| "full pipeline" with several roles (backend, frontend, js, e2e) | LARGE | STANDARD may then stay almost empty; that is correct when the old process had no middle mode. Say so explicitly in the plan |
| specialists in parallel, split review (e.g. FULL) | LARGE | move the entry criteria to "Mode selection" |
| "high risk forces the full mode" | tightening | in `av-implement.md`, section "Mode selection": with high risk, a plan is required (on top of the default review, `full` and the security axis). Do not map to LARGE, because LARGE means a contract or several roles |

When the team docs give conflicting mode thresholds (e.g. "from 2 layers" and "from 3 layers"), take the stricter one and record the conflict in "Docs drift from code".

## Step 3: Plan

Follow `references/plan-format.md`. The "Knowledge that gets lost" section is required. It lets the team object before something disappears.

**Knowledge loss detector.** Compare the CONVERT and DROP files with the docs that stay:

```bash
bash <skill-dir>/scripts/adoption_diff.sh --root <repo-root> \
  --old <CONVERT and DROP files> --new CLAUDE.md <docs-dir> \
  --noise '<names of old agents and commands, e.g. swift-reviewer|feature_plan>'
```

- Result: `LOST <old-file> <token>` for a backtick token with no trace in the new corpus. At the end: `TOKENS n LOST m FILTERED f`.
- The filter skips orchestration: RUN_ID, CHECK_ID, EVIDENCE, `$ARGUMENTS`, `pipeline_state`, `pipeline_check`, the paths `.claude/agents` and `.claude/commands`. `--noise` (ERE) adds the names of old agents and commands.
- Every `LOST` gets a place in the plan. A substantive rule (findings category, threshold, script, pitfall) goes to "Knowledge moved to overlays" with a target. Orchestration goes to "Knowledge that gets lost" with what replaces it.
- Group them: one row per group of tokens, not per token. Write the `TOKENS`, `LOST` and `FILTERED` counts into the plan.

Without approval (except `--defaults`), delete or edit nothing. You may only write the plan.

## Step 4: Execution

New files are created before old ones are deleted. At every moment, the repo has a working setup.

1. `.ai/av.config.json`. Then `av-docs-sync audit --fix`, when the plan contains it (SKILL.md, step 3).
2. Overlays and `code-review.md`.
3. Other docs: `contracts.md` and other missing topics.
4. `CLAUDE.md` and the files from the UPDATE list.
5. Codex according to `references/codex.md`.
6. Deletions: `git rm` only for files whose deletion the user explicitly approved. `--defaults` is not such an approval: without it, leave the CONVERT and DROP files in place, and give a ready `git rm` command with the list in the report. The history stays in git, so going back is possible.

## Step 5: Post-migration check

- Repeat the grep from step 1. Fix or report every hit outside `workspace/` and `sessions/`.
- `check_refs.sh` for changed docs and overlays.
- `adoption_diff.sh` again, on the new setup. After deletions: `--old-rev HEAD --deleted --new CLAUDE.md <docs-dir> .claude/skills` with the same `--noise`. Before deletions: `--old <CONVERT and DROP files>`. A `LOST` outside "Knowledge that gets lost" is a gap: add the rule to an overlay or a role skill, and when that is not possible, report it.
- `check_setup.sh`: overlays, roles, references and gate names. Fix `ERROR` before the report.
- The `quick` gate at the very end, according to SKILL.md, step 10, point 5. It checks that the commands from the config really work.
- Every group of rules from the "Knowledge moved to overlays" section has a target place. A missing place is a gap in the report.

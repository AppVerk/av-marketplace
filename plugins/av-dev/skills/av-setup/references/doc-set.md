# Doc set

This file describes which documents `av-setup` creates and where it takes the facts from. Topic files specific to the repo come from the stack facts in `SKILL.md`, step 2.

## Overriding rules

1. **Facts only from code.** Every path, class, method, command and number must exist in the repo. When something cannot be established, write `_[TODO: fill in]_` (localized form: `references/localization.md`, section "Markers"). An invented rule does more harm than a missing rule, because the agent will follow it.
2. **One owner per topic.** Each topic has one file. Elsewhere, only a link and one sentence are allowed. Copies always drift apart.
3. **Do not number rules that someone will refer to.** Numbering shifts with every addition. Link to the section.
4. **Do not overwrite existing files.** Create the missing ones. Changes to existing ones go only through an approved plan (adoption or refresh mode).
5. **Do not copy rules from another project.** Templates give the shape; the content comes from this repo.
6. **Short.** Entry file up to about 150 lines; above 170, move details to topic files. Details go in topic files, read on demand.
7. **Style.** Language from `project.language`. Short sentences, lists and tables instead of dense prose. No em dashes "—" and en dashes "–". Only a plain hyphen "-".

## Entry file `CLAUDE.md`

`AGENTS.md` is a symlink to `CLAUDE.md` when `codex.enabled`. The template below is in English. Write the file in `project.language`; section names listed in `references/localization.md` use its table. Section order:

```markdown
# CLAUDE.md

<One sentence: what the project is, stack, for whom.> This file is a summary and the rules. Details are in `<docs.root>/`.

## Quick start
<3-6 commands from validation.commands and environment: install, run, quick gate.>

## Code map
<Directory tree with a one-line description. Only directories that exist.>

Flow: `<layer A> -> <layer B> -> ...` (when the architecture has a clear flow).

## Task routing

| When the task concerns | Read first | Key rules |
|---|---|---|
| <repo area> | <real docs and code paths> | <conventions detected in the code, or TODO> |

## Critical rules
<Only non-obvious rules whose violation breaks the build, data or the process. Each with a half-sentence reason.>

## Working with the agent
<Which av-* skills for what. A 5-row table. A link to the overlays and to `<docs.root>/agents.md`, section "Models". One sentence: `agents.models` in the config sets the slots; one person's settings go to `.ai/av.config.json.local`.>

## Documentation
<Table: file | description. All files from docs.root.>

## Git
<Branches, branch name and commit pattern, commit only on request, no push, no AI signature.>

## Session learnings
At the start of a session, read `<paths.learnings>` if it exists.
```

**Task routing** is the most important section. One row per relevant area: domain module, layer, UI, tests, CI, translations. `Read first` contains real paths. `Key rules` contains conventions observed in the code, e.g. "new endpoint = a handler in `src/api/` + a schema in `src/api/schemas/`".

## Core `<docs.root>/`

| File | Topic owner of | Source of facts |
|---|---|---|
| `README.md` | docs index, table of topic owners | list of generated files |
| `architecture.md` | layers, flow, DI, module boundaries | directory structure, imports, DI registrations |
| `coding-standards.md` | naming, sections, localization, comments | 3-5 representative files, linter config |
| `commands.md` | build, tests, lint, run, logs | `validation.commands`, scripts, CI |
| `environment.md` | required tools, versions, docker, simulator | lockfile, `.tool-versions`, compose, README |
| `configuration.md` | config files and what may be changed in them | config files, env without values |
| `tech-stack.md` | dependencies with versions | lockfile |
| `testing.md` | how to write and run tests, mocks, fixtures | test directories, sample tests |
| `agents.md` | work with the agent: av-* skills, overlays, role skills, slots and models (no copy of config values), machine requirements (Codex CLI, slot agent definitions, allow rule for `agent.sh`, tools the integrations need), local override `.ai/av.config.json.local` | config, av-implement `SKILL.md` "Slots and providers" |
| `code-review.md` | repo review rules (read by `av-review`) | conventions from the code, linters, CI and team docs |
| `contracts.md` | protected surfaces and what is a breaking change | public API, routes, DB schema, deep links, events |
| `modules/README.md` | module index | candidates from the scan |
| `modules/_template.md` | module description template | the common skeleton below, extended with the layers the repo has |
| `modules/<Module>.md` | one module | module code |
| `domain/glossary.md` | glossary of business terms | names of classes, enums, translations |
| `domain/business-rules.md` | business rules | validators, status enums, tests |
| `code-templates/` | templates per layer | the best-built reference module |
| `<paths.learnings>` | session learnings (gitignored) | file with a header, pattern below |
| `<paths.workspace>/README.md` | layout of the working directory (the rest is gitignored) | fixed text |

Topic files the repo needs (e.g. `networking.md`, `frontend.md`) join this table when the code shows the topic and the core files do not cover it.

When the repo uses `docs/` with its own layout (e.g. `docs/standards/`), do not duplicate. Map the existing files to the topics in the table. Create only missing topics, in the team's naming convention.

## `code-review.md`

The only owner of the review axes and checklists. The `av-review.md` overlay only links to it and adds tools.

```markdown
# Review rules

## Priorities
1. Correctness and regressions.
2. Security (risks found in this repo).
3. Contracts from `contracts.md`.
4. Repo conventions.

## Axes
| Axis | What to check | Typical error in this repo |
|---|---|---|

## Known false alarms
<Things that look like an error but are intentional. E.g. Polish text in en.json is a placeholder.>

## Severity
BLOCKER / HIGH / MEDIUM / LOW / INFO with definitions.
```

## `contracts.md`

An inventory of the actual surfaces. For each: where it lives, who consumes it, what is a breaking change, what to do on a change (versioning, transition period, migration note). Examples: REST endpoints consumed by mobile apps, DB schema and migrations, deep links, push keys, events and queues, public CLI commands, import file formats.

## Integrations

The plugin ships no instructions for external tools. Instructions for a tool the repo uses (a board, a design tool, a tracker, a device) are repo knowledge.

- Source: existing agents, skills and docs of the repo that use the tool; in ADOPTION, tool agents and tool skills (`references/adoption.md`).
- Place: a topic file in `<docs.root>/` (e.g. `<docs.root>/<tool>.md`) with a row in the docs table of `CLAUDE.md`; helper scripts in `<paths.scripts>/`. Overlays link to the topic file.
- Access method (MCP, browser, CLI): the team's choice as found in the repo or given in the interview. Do not switch it.
- Solve a problem of one repo (a script for its project, a workaround for its tool) in that repo. Do not add it to the plugin.

## Modules

Common skeleton; add sections only for layers the repo has:

```markdown
# Module: {Name}

<One sentence: what it does, which style it is written in (new/old).>

## Files
| Layer | File |

## Contracts
<endpoints, routes, events>

## Dependencies
<other modules, services>

## Pitfalls
<non-obvious things; only those confirmed in the code>
```

`SKILL.md`, step 7 describes the budget and parallelism of module descriptions. Modules without a full description get a row in `modules/README.md` with the note `_[description to create: av-docs-sync]_` (in a Polish repo: `_[opis do utworzenia: av-docs-sync]_`).

## Code templates

Choose the reference module: newest style, all layers, tests. For each layer, create `code-templates/<layer>.md` with a minimal, complete example copied from that module and simplified to placeholder names. Add a table to `code-templates.md`: template, layer, when to use.

## Learnings file

```markdown
# Session learnings

Read at the start of a session. Add 1-2 concrete learnings after a task, when they are new.

## [YYYY-MM-DD] <topic>
- <learning in 1-2 sentences, with a path or command>
```

In ADOPTION, the existing file stays with its own format.

## `.gitignore`

Target:

```
<paths.workspace>/*
!<paths.workspace>/README.md
.ai/sessions/
.ai/av.config.json.local
```

The pattern `<paths.workspace>/` (the whole directory) blocks the README exception, because git does not enter an ignored directory. Replace such a pattern with the two lines above. The scan shows the current patterns in `ai_setup.gitignore_ai`.

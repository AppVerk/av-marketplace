# Doc set

This file describes which documents `av-setup` creates and where it takes the facts from. The stack profile from `references/stacks/` adds stack-specific files.

## Overriding rules

1. **Facts only from code.** Every path, class, method, command and number must exist in the repo. When something cannot be established, write `_[TODO: fill in]_`. An invented rule does more harm than a missing rule, because the agent will follow it.
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

**Task routing** is the most important section. One row per relevant area: domain module, layer, UI, tests, CI, translations. `Read first` contains real paths. `Key rules` contains conventions observed in the code, e.g. "new endpoint = a method in `NovolApi*.swift` + a model in `Response/`".

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
| `agents.md` | work with the agent: av-* skills, overlays, role skills, slots and models (no copy of config values), machine requirements (Codex CLI, slot agent definitions, allow rule for `agent.sh`, browser extension for integrations), local override `.ai/av.config.json.local` | config, av-implement `SKILL.md` "Slots and providers" |
| `code-review.md` | repo review rules (read by `av-review`) | stack profile + conventions from the code |
| `contracts.md` | protected surfaces and what is a breaking change | public API, routes, DB schema, deep links, events |
| `modules/README.md` | module index | candidates from the scan |
| `modules/_template.md` | module description template | stack profile |
| `modules/<Module>.md` | one module | module code |
| `domain/glossary.md` | glossary of business terms | names of classes, enums, translations |
| `domain/business-rules.md` | business rules | validators, status enums, tests |
| `code-templates/` | templates per layer | the best-built reference module |
| `<paths.learnings>` | session learnings (gitignored) | file with a header, pattern below |
| `<paths.workspace>/README.md` | layout of the working directory (the rest is gitignored) | fixed text |

Files from the stack profile (e.g. `networking.md`, `php-rules.md`, `frontend.md`) join this table.

When the repo uses `docs/` with its own layout (e.g. `docs/standards/`), do not duplicate. Map the existing files to the topics in the table. Create only missing topics, in the team's naming convention.

## `code-review.md`

The only owner of the review axes and checklists. The `av-review.md` overlay only links to it and adds tools.

```markdown
# Review rules

## Priorities
1. Correctness and regressions.
2. Security (link to the profile section).
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

Instructions for external tools and stack tools live in the repo, not in the global av-* skills. Only templates live globally: `templates/<name>/` with a `template.json` manifest and a `README.md` description.

Manifest:
- `configKey`: the config key that enables the template, e.g. `integrations.<name>`,
- `applies`: a jq expression on the config; `true` means the files must be in the repo,
- `validate`: a jq expression that returns field error descriptions (validation in `check_setup.sh`),
- `files`: template file -> target in the repo with `{docs.root}` and `{paths.scripts}`,
- `placeholders`: strings in the content to replace with config values,
- `fakeNames`: names for the "Known false names" section in the `av-docs-sync.md` overlay.

Rules:
- Read the template's `README.md`: when to use it, how to fill the config, what to add to the overlays.
- Copy the files with the `placeholders` replaced. Leave the rest of the content: it is a proven solution, not content to invent.
- Template docs (e.g. `miro.md`) are written in English. When you copy one into a repo, translate the prose to `project.language`. Keep code, commands and names.
- Do not overwrite an existing file. Show the diff and ask; with `--defaults`, save it next to it as `.proposed`.
- The docs file gets a row in the "Documentation" table in `CLAUDE.md` and in the docs index.
- `check_setup.sh` reports `SETUP_INTEGRATION_INVALID` (ERROR) and `SETUP_TEMPLATE_MISSING` (WARNING) when `applies` is true and the file is missing.
- Solve a problem of one repo (a script for its project, a workaround for its tool) in that repo: in `<paths.scripts>`, docs and overlays. Do not add it to the template or the stack profile.

## Modules

Take the module template from the stack profile. Common skeleton:

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

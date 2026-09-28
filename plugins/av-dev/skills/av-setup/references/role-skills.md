# Role skills

A role skill is a project skill with the knowledge of one repo layer: backend, views, TS, E2E tests, a mobile data layer and so on. It lives in `.claude/skills/<prefix>-<role>/SKILL.md` and is committed.

## Why

`av-implement` does not know the layers. If the rules of all layers sat in one overlay, every agent would read all of it, though it needs one part. A role skill solves this in 3 ways:
- in LARGE mode, a role subagent loads only its own skill,
- in SMALL and STANDARD modes, the session loads only the skills of the layers the change touches,
- the skill also works outside `av-implement`: Claude uses it by itself during normal work on the layer's files, and Codex sees it through `.agents/skills`.

## When to create

- A role exists only for a layer with its own rules (conventions, required steps, checks) that the other layers do not share. Do not split a layer into roles to reach a count: one role is a valid setup. Shared files (e.g. translations) go to the role that changes them most often, not to a new role.
- The repo has 2 or more such roles in `roles` in the config: one skill per role.
- The repo has 1 role: a role skill is optional. Create it when the layer rules exceed 40 lines. Smaller rules stay in the overlay.
- A good project skill for this layer already exists (e.g. `view-templates`): do not duplicate it. The role points to the existing skill.
- A marketplace plugin covers the layer (e.g. `example-plugin:example-guide`): the role can point to its skill or agent. Rules of this repo that the plugin does not know still get a role skill, only a shorter one.

## Name

`<prefix>-<role>`, e.g. `shop-backend`, `shop-web`, `shop-tests`. The prefix comes from `project.skillPrefix` in the config. By default, take it from the project name, not the directory name (a clone or worktree may have a different one): first the `name` field of the project manifest, then the repo name from the `origin` URL, then the name of the main project file found by the scan. When no source exists (a clone without `origin`, a repo without a manifest), ask in the interview; with `--defaults`, take the directory name and record it in "Default decisions". From the name, take the last part without the company prefix, e.g. `acme-shop` gives `shop`. When the result is a platform or layer word (`mobile`, `api`, `web`, `admin`, `app`) or ends with one (`<name>-app`, `-service`, `-server`, `-client`, `-api`), it will collide with other repos of the same product: ask in the interview; with `--defaults`, keep the full project name as the prefix and record it in "Default decisions".

The role name is the same in the config (`roles[].name`), in the plan (`av-plan`, "Role" column) and in the skill name.

## Format

```markdown
---
name: shop-web
description: View layer rules for example-shop (templates, styles, menu, translations visible in views). Use for any change in the web/src directory, in the shared stylesheet, the menu config or translation keys used in views, also when the task only mentions a view, list, form or modal.
---

# shop-web: views

## File scope
The file scope of this role is the `web` role in `roles` in `.ai/av.config.json`.
<optional: files outside the scope that the role reads or reports to another role; no globs from the config>

## Read first
<docs paths, without copying their content>

## Patterns
| Case | Reference file |

## Required steps
<rules whose violation breaks the build, security or consistency; short, with the reason in half a sentence>

## Layer check
<quick commands on this layer's files during work, e.g. the layer's static checker only on changed files. This helps the role; it is not evidence. Evidence comes only from gates in validation.commands, which av-verify runs. When the command exists in the config, give its name (`gate.sh --only <name>`) instead of copying it.>

## Handoff
- You receive: <from which role and what, e.g. a route table from shop-backend>
- You hand off: <to whom and what, e.g. a list of data-testid for shop-tests>

This is the only place that describes the handoff. The role order is in the config (`order`).

## Pitfalls
<non-obvious things, confirmed in the code>
```

Rules:
- The `description` lists directories (names, without `/**`) and words by which Claude recognizes the layer. `SETUP_GLOB_COPY` counts globs in the description. Write it broadly, because a too narrow description keeps the skill from triggering. Length up to about 300 characters, counted as characters (`wc -m`), not bytes: letters outside ASCII take several bytes.
- Content: 40-150 lines. Knowledge that is a norm for people (architecture, conventions) stays in the docs; the skill only links to it.
- Facts from the code, as in the whole setup. Check every path and command before writing it.
- A role skill does not orchestrate. It does not talk about whole-repo gates, review or commits. `av-implement` does that.
- The skill does not copy the role's globs. Globs live only in the config. `check_setup.sh` reports a copy of 3 or more globs as `SETUP_GLOB_COPY`.

## Files shared by several layers

One file has one owner, that is one role. A file split by content (e.g. a translation file with keys for views and for scripts, a config file with both menu and services) goes to the role that changes it most often. Other roles hand it the entries they need through the contract in the plan and the "Handoff" section. Role globs must not overlap. `check_setup.sh` reports an overlap as `SETUP_ROLE_OVERLAP`.

Files generated by the build (e.g. `public/build/**`) belong to no role. Put them in `generatedPaths` in the config. Put repo tools (e.g. `scripts/**`) in `unownedPaths`.

## Where content comes from

1. In ADOPTION: the prompts of old implementing agents (e.g. `backend-developer`, `frontend-developer`, `mobile-developer`, `web-developer`) and the pipeline phases where the orchestrator did the work itself (e.g. "2.4 E2E"). Substantive rules move to the role skill almost word for word. Orchestration (phases, statuses, handoff formats) does not move.
2. The layers visible in the code: directories, imports and DI registrations.
3. The code: the reference module and 3-5 files of the layer.

## Overlay vs role skill

The role map (name, skill, order, globs) lives in `roles` in the config. The `av-implement.md` overlay, section "Roles", only links to it.

Rules common to all layers (e.g. "a new translation key in both files") stay in the overlay, in "Required steps". Rules of one layer go to the role skill.

## REFRESH

An overlay with layer rules written directly in the roles table or in "Required steps" is the old format. Propose moving them to role skills. Move the content without substantive changes.

A roles table with globs in the overlay, or a "File scope" section with globs in a role skill, is also the old format. Propose moving the globs to `roles` in the config. Expand `{a,b}` braces into separate globs. Then run `check_setup.sh` and fix `SETUP_ROLE_OVERLAP` and `SETUP_ROLE_EMPTY`.

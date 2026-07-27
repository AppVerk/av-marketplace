# av-marketplace — Agent Frontmatter Tool Declaration Repair

**Date:** 2026-07-27
**Status:** Approved design, pre-implementation
**Contract source:** Claude Code docs (`sub-agents`, `tools-reference`, `permissions`) as of v2.1.220

## Purpose

Fifteen agent definitions across six plugins declare their tool access under an
`allowed-tools:` frontmatter key. Claude Code does not support that key for
subagents. It is parsed as an unknown field and discarded. Only `tools:` grants
availability, and omitting `tools:` inherits every tool available to subagents.

The failure is silent. No error is raised at load time, at dispatch time, or at
call time. The agent simply reports that a tool is unavailable and follows its own
fallback path — which, for `qa:fe-tester`, means returning every FE scenario as
SKIP with reason "Playwright MCP unavailable" on a machine where Playwright MCP is
installed and healthy.

`qa:fe-tester` was repaired ahead of this spec, as the reported symptom that led to
the audit, and shipped in qa 2.5.1. It is the reference implementation for the
pattern applied here and is not listed again among the repairs below.

This spec repairs every remaining affected definition and adds a validator so the
class of defect cannot silently return.

## Evidence

Three independent confirmations that `allowed-tools` is inert for subagents:

1. **Harness registry.** Claude Code publishes each agent's resolved tool list at
   session start. For every agent in this repository the resolved list equals the
   declared `tools:` value exactly, with no contribution from `allowed-tools`.
2. **Control case.** `code-review/agents/fix-auto.md` declares only
   `allowed-tools:` and no `tools:`. It resolves to **all tools**. If
   `allowed-tools` restricted anything, that agent would be restricted. It is not.
3. **Documentation.** The supported frontmatter fields are enumerated in the
   subagent docs. `allowed-tools` is absent from that list.

`allowed-tools` *is* valid in `SKILL.md` and in command frontmatter, where it
pre-approves permission prompts for one turn without affecting availability. Those
files are correct and are out of scope.

## Scope

**In scope**

- `tools:` frontmatter for 15 agents across 6 plugins
- `Task(` → `Agent(` in `web-auditor/agents/web-auditor.md` (9 sites) and
  `web-auditor/commands/audit.md` (1 site), because that agent's frontmatter and
  body must agree
- `scripts/check_agent_frontmatter.py` and `.github/workflows/agent-frontmatter.yml`
- Version bumps, README rows, `marketplace.json` entries, `CLAUDE.local.md` rule

**Out of scope**

- `Task(` prose in `code-review/commands/*.md` (~10 sites) and
  `qa/commands/*.md` (~8 sites). These are soft failures: the model reliably maps
  "use the Task tool with subagent_type" onto the real `Agent` tool. Deferred to a
  separate change to keep this diff reviewable.
- `allowed-tools` in `SKILL.md` and command frontmatter — correct as written.
- The `sequentialthinking` null version in `marketplace.json` — unrelated.

## The contract

Normative rules extracted from the Claude Code documentation. The validator
enforces these; every repair conforms to them.

### Frontmatter fields

Permitted: `name`, `description`, `tools`, `disallowedTools`, `model`, `skills`,
`maxTurns`, `initialPrompt`, `memory`, `effort`, `background`, `isolation`,
`color`. Required: `name`, `description`.

`hooks`, `mcpServers`, and `permissionMode` are silently ignored for agents loaded
from a plugin. Any other key, including `allowed-tools`, is unknown.

### Tool grants

`tools:` is the sole availability allowlist. Omitting it inherits everything.
Entries are canonical tool names or `ToolName(specifier)` rules. MCP servers are
granted with `mcp__<server>` or `mcp__<server>__*`.

### Filters that override declarations

Removed from **every** subagent regardless of `tools:`: `AskUserQuestion`,
`EnterPlanMode`, `ExitPlanMode`, `ScheduleWakeup`, `TaskOutput`,
`WaitForMcpServers`, `Workflow`, `EndConversation`.

Subagents running in the **background** — the default — keep every MCP tool but
only these built-ins: `Read`, `Grep`, `Glob`, `Bash`, `PowerShell`, `Edit`,
`Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, `TodoWrite`, `Skill`,
`ToolSearch`, `EnterWorktree`, `ExitWorktree`, `Monitor`, `TaskStop`,
`SendMessage`, `Artifact`.

`Agent` survives both filters until the nesting depth limit, which defaults to
three layers below the main conversation.

Consequence for this repository: `TaskCreate`, `TaskUpdate`, and `TaskList` in the
three `developer` agents and in `fix-auto` resolve only in foreground runs. This is
left as-is and reported by the validator as a warning, not an error.

### Bash specifier form

Current documentation specifies space-separated wildcards exclusively:
`Bash(npm *)`, `Bash(git * main)`. A trailing ` *` enforces a word boundary.

This repository, and Claude Code's own machine-written
`.claude/settings.local.json`, use a colon form: `Bash(wc:*)`, `Bash(git config:*)`.
The colon form is therefore a genuine Claude Code convention rather than a local
invention, but the local evidence dates from April 2026 and does not establish that
v2.1.220 still honours it.

**Resolution:** the question is avoided rather than answered. No new colon-form
rule is written. Narrowing rules added by this change use the documented space
form. The validator flags colon-form Bash specifiers as a warning.

## Repairs

Every agent below also has its `allowed-tools:` line deleted.

| Plugin | Agent | Current `tools:` | Target `tools:` |
| --- | --- | --- | --- |
| qa | be-tester | `Read, Write, Bash, Grep, Glob` | `Read, Write, Bash, Grep, Glob, mcp__postgres, mcp__supabase, mcp__neon, mcp__mysql, mcp__mongodb, mcp__redis` |
| web-auditor | api-security-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright__*, mcp__playwright__*` |
| web-auditor | compliance-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright__*, mcp__playwright__*` |
| web-auditor | performance-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright__*, mcp__playwright__*` |
| web-auditor | seo-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright__*, mcp__playwright__*` |
| web-auditor | web-security-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright__*, mcp__playwright__*` |
| web-auditor | supply-chain-agent | `Read, Bash, Grep, Glob, WebSearch` | `Read, Bash, Grep, Glob, WebSearch, mcp__plugin_playwright_playwright__*, mcp__playwright__*` |
| web-auditor | infrastructure-agent | `Read, Bash, Grep, Glob, WebFetch` | unchanged |
| web-auditor | web-auditor | `Read, Write, Bash, Grep, Glob, Task, TaskOutput, WebFetch, WebSearch` | `Read, Write, Bash, Grep, Glob, Agent, WebFetch, WebSearch, mcp__plugin_playwright_playwright__*, mcp__playwright__*` |
| code-review | fix-auto | *(absent)* | `Read, Edit, Write, Glob, Grep, Bash, TaskCreate, TaskUpdate, TaskList` |
| code-review | security-auditor | `Read, Bash, Grep, Glob` | unchanged, or narrowed — see below |
| code-review | code-quality-auditor | `Read, Bash, Grep, Glob` | unchanged |
| frontend-developer | developer | `Read, Edit, Write, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList` | same list `+ Bash` |
| python-developer | developer | `Read, Edit, Write, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList` | same list `+ Bash` |
| php-developer | developer | `Read, Edit, Write, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList` | same list `+ Bash` |

### Two dual prefixes for Playwright

`mcp__plugin_playwright_playwright__*` matches the plugin-provided server, which is
how this marketplace installs it. `mcp__playwright__*` matches a directly
configured server. Listing both makes the agents work under either installation.
An entry that resolves to nothing is harmless as long as at least one entry in
`tools:` resolves.

Server-level wildcards are used instead of the previous per-tool enumerations
because the old lists had already drifted: they name
`mcp__plugin_playwright_playwright__browser_run_code`, while the real tool is
`browser_run_code_unsafe`.

### `fix-auto` needs an identity

`code-review/agents/fix-auto.md` has neither `name:` nor `description:`, both
required. The harness therefore lists it with a generated placeholder,
"Agent from code-review plugin", which is what the orchestrator sees when choosing
an agent. Add:

```yaml
name: fix-auto
description: Applies a fix for a single code review issue end to end — analysis, implementation, verification, and reporting. Invoked as a subagent by the review, fix-report, and fix-all commands.
```

### `web-auditor` cannot currently dispatch

`web-auditor/agents/web-auditor.md` declares `Task`, which is not a tool name in
any Claude Code version; the subagent-spawning tool is `Agent`. The coordinator
therefore has no way to spawn the seven scanning agents its body instructs it to
spawn. It also declares `TaskOutput`, which is stripped from every subagent.

Frontmatter takes `Agent` and drops `TaskOutput`. The nine `Task(` call sites in
the body and the one in `commands/audit.md` become `Agent(`.

### Conditional narrowing

Least-privilege narrowing is applied to exactly two agents — `security-auditor`
and `fix-auto` — and only if a live check confirms the specifier form works.

**Check V1.** In a scratch project, add an allow rule for a command that is not in
the built-in read-only set, using the documented space form, then run a matching
command and observe whether it prompts. Repeat with the colon form.

**Decision rule.** If the space form suppresses the prompt, write the narrowing
rules in space form. If it does not, write no narrowing rules anywhere and leave
both agents with bare `Bash` — which is exactly their effective behaviour today, so
the outcome is never a regression.

This ordering is deliberate. Narrowing that silently matches nothing would
reintroduce the same class of defect this change exists to remove.

## Validator

`scripts/check_agent_frontmatter.py`, following the structure of the existing
`scripts/check_plugin_versions.py`: standard library only, hand-rolled frontmatter
parsing, non-zero exit on error.

Scans `plugins/*/agents/*.md`.

**Errors** — fail the build:

- unknown frontmatter field, which catches `allowed-tools`
- missing `name` or `description`
- unrecognised tool name in `tools:` or `disallowedTools:`, which catches `Task`
- a tool that is stripped from every subagent, which catches `TaskOutput`

**Warnings** — reported, do not fail:

- a built-in that background subagents lose, such as `TaskCreate`
- a Bash specifier in colon form
- no `tools:` field at all, since inheriting everything is occasionally intended

The canonical tool-name list is a module-level constant carrying a comment that
names `tools-reference` as its source and the date it was verified. Centralising
the staleness in one visible place is preferable to spreading it across the checks.

`.github/workflows/agent-frontmatter.yml` mirrors `plugin-version-parity.yml`:
triggered on push and pull request against `master`, pinned action SHAs,
`contents: read`, five-minute timeout.

## Verification

Two layers, because the validator alone would only confirm conformance to rules
this change itself authored.

**Static.** `check_agent_frontmatter.py` exits zero on the repaired tree and
non-zero on the tree as it stands today. The second half matters: a validator that
passes before the fix is not testing anything.

**Live.** After merge, plugin update, and restart, compare the harness's resolved
agent registry against the target column of the repairs table, agent by agent. The
registry reports what each agent actually receives, which is the only source of
truth that is independent of the files being changed.

Expected registry entries after the change:

- `qa:be-tester` — the five built-ins plus six `mcp__*` database servers
- `qa:fe-tester` — the five built-ins plus both Playwright prefixes; already
  repaired in 2.5.1, included here because its live confirmation is still pending
- `web-auditor:web-auditor` — includes `Agent`, excludes `Task` and `TaskOutput`
- `web-auditor:*-agent` — each includes both Playwright prefixes
- `code-review:fix-auto` — an explicit list, no longer "All tools", and a real
  description rather than the generated placeholder
- `frontend-developer:developer`, `python-developer:developer` — include `Bash`

## Delivery

One branch, `fix/agent-tools-frontmatter`, one pull request.

PATCH bumps, since every change restores documented intent rather than altering it.
Each is applied in `plugin.json`, the plugin's README table row, and its
`marketplace.json` entry:

| Plugin | From | To |
| --- | --- | --- |
| qa | 2.5.1 | 2.5.2 |
| web-auditor | 2.1.1 | 2.1.2 |
| code-review | 1.17.0 | 1.17.1 |
| frontend-developer | 1.2.0 | 1.2.1 |
| python-developer | 3.0.3 | 3.0.4 |
| php-developer | 1.0.2 | 1.0.3 |

`CLAUDE.local.md` gains the authoring rule: agent capability is declared in
`tools:`; `allowed-tools` belongs to skills and commands only.

Plugins install from the GitHub repository, not from the local checkout, so no fix
takes effect in a session until the branch is merged and the plugin updated.

## Residual risks

**`php-developer` is not installed in the maintainer's session.** It is absent from
`~/.claude/settings.json`, so it will not appear in the harness registry and its
repair is confirmed statically only.

**The canonical tool list will age.** It is a snapshot of v2.1.220. If Anthropic
adds or renames a tool, the validator produces false errors until the constant is
updated. The comment naming the source and verification date is the mitigation.

**Deferred `Task(` prose.** Roughly eighteen sites in `code-review` and `qa` keep
instructing the model to "use the Task tool". This works today by inference and is
not a hard failure, but it remains a drift the validator does not cover, since the
validator reads frontmatter rather than prose.

**Narrowing may not land.** If check V1 is inconclusive, `security-auditor` and
`fix-auto` keep bare `Bash` and least-privilege is not improved by this change.
Capability correctness, which is the reported defect, is unaffected either way.

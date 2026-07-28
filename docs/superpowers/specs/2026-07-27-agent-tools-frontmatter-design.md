# av-marketplace — Agent Frontmatter Tool Declaration Repair

**Date:** 2026-07-27
**Status:** Approved design, pre-implementation
**Contract source:** Claude Code docs (`sub-agents`, `tools-reference`, `permissions`) as of v2.1.220

## Purpose

Fifteen agent definitions across six plugins declare their tool access under an
`allowed-tools:` frontmatter key. Claude Code does not support that key for
subagents: it contributes nothing to the resolved tool grant. Whether it is fully
inert — rather than post-filtering availability or suppressing permission prompts —
is not established; see Evidence and Residual risks. Only `tools:` grants
availability, and omitting `tools:` inherits every tool available to subagents.

The failure is silent. No error is raised at load time, at dispatch time, or at
call time. The agent simply reports that a tool is unavailable and follows its own
fallback path — which, for `qa:fe-tester`, means returning every FE scenario as
SKIP with reason "Playwright MCP unavailable" on a machine where Playwright MCP is
installed and healthy.

`qa:fe-tester` was repaired ahead of this spec, as the reported symptom that led to
the audit, in `cecaa92` — this branch's own first commit, which bumped qa to 2.5.1.
That version has never been released: `origin/master` still reads 2.5.0 on all four
parity surfaces, and 2.5.1 and 2.5.2 merge together in this pull request, so no
release boundary separates the `fe-tester` repair from the rest of this change. It
is the reference implementation for the `tools:` pattern applied here and is
therefore absent from the repairs table; its one remaining change — the dual-form
MCP grant — is specified under "Two dual prefixes for Playwright".

This spec repairs every remaining affected definition and adds a validator so the
class of defect cannot silently return.

## Evidence

Three confirmations that `allowed-tools` contributes nothing to the resolved
*pre-filter* tool grant for subagents. Full inertness — no post-filtering of
availability, no suppression of permission prompts — is not established; see
Residual risks. Confirmations 1
and 2 are not independent of each other: both read the harness registry, which
reports the *pre-filter* grant, so neither rules out `allowed-tools` acting as a
post-filter of the same class as the filters no layer of this change observes.
Confirmation 3 is independent of both. This changes none of the repairs — every
agent below has its `allowed-tools:` line deleted regardless.

1. **Harness registry.** Claude Code publishes each agent's resolved tool list at
   session start. That list is the *pre-filter grant*: for every agent installed in
   the maintainer's session — all but `php-developer:developer`, which Residual
   risks records as absent from the registry — it equals the declared `tools:`
   value exactly, or full inheritance
   when `tools:` is absent, computed before the filters described in "Filters
   that override declarations" are applied, and with no contribution from
   `allowed-tools`.
2. **Control case.** `code-review/agents/fix-auto.md` declares only
   `allowed-tools:` and no `tools:`. It resolves to **all tools**. If
   `allowed-tools` restricted anything, that agent would be restricted. It is not.
3. **Documentation.** The supported frontmatter fields are enumerated in the
   subagent docs. `allowed-tools` is absent from that list.

`allowed-tools` *is* valid in `SKILL.md` and in command frontmatter, where it
pre-approves permission prompts for one turn without affecting availability. The
key is correctly placed in those files; their values are not audited by this
change — see Scope.

## Scope

**In scope**

- `tools:` frontmatter for 15 agents across 6 plugins
- `Task(` → `Agent(` in `web-auditor/agents/web-auditor.md` (9 sites) and
  `web-auditor/commands/audit.md` (2 sites: the `Task(` call at line 75 and the
  "using the Task tool" lead-in at line 72); the four `TaskOutput(...)` result
  collection sites in that agent's body — two `TaskOutput(...)` calls and two
  instructions directing them; and the twelve background instructions
  (nine dispatch sites, the Phase 2 lead-in at line 186, and the two Phase 2.5 step
  labels at lines 336 and 359) that would otherwise leave the rewritten calls
  returning nothing. An agent's frontmatter and body must agree.
- `qa/agents/fe-tester.md` carried onto the dual-form MCP grant — the one row
  brought forward from `cecaa92`
- `scripts/check_agent_frontmatter.py` and `.github/workflows/agent-frontmatter.yml`
- `docs/agent-tools-verification.md` — the live-layer status record, created with
  seventeen rows: sixteen seeded `pending`, `php-developer:developer` seeded
  `not installed`. Sixteen of the rows are the agents this change touches; the
  seventeenth is `code-review:feedback-analyzer`, untouched here and carried only
  because its colon-form `Bash(git:*)` is the one open availability question below
  that attaches to an agent this change does not repair
- Version bumps on all four surfaces the parity check covers — `plugin.json`,
  `.claude-plugin/marketplace.json`, the README table row, and the `**Version:**`
  header in `docs/plugins/<name>.md`
- A new tracked root `CLAUDE.md` carrying the agent-authoring rule (`tools:`, not
  `allowed-tools`) and the corrected versioning rule naming all four parity
  surfaces. `CLAUDE.local.md` is gitignored and is not a deliverable of this
  change; it may mirror the tracked copy locally.
- Parity drift introduced by this branch: `cecaa92`, this branch's first commit,
  bumped `plugin.json`, `marketplace.json`, and the README row to 2.5.1 but left
  `docs/plugins/qa.md` behind at 2.5.0, so `check_plugin_versions.py` fails on
  this branch right now. `origin/master` is unaffected — all four surfaces there
  still read 2.5.0 and the parity check exits 0. This change carries
  `docs/plugins/qa.md` to 2.5.2 with the rest of the qa bump, repairing the
  drift this branch introduced.

**Out of scope**

- `Task(` prose in `code-review/commands/*.md` (~10 sites) and
  `qa/commands/*.md` (~8 sites). These are soft failures: the model reliably maps
  "use the Task tool with subagent_type" onto the real `Agent` tool. Deferred to a
  separate change to keep this diff reviewable.
- `allowed-tools` **values** in `SKILL.md` and command frontmatter. The key is
  valid in both surfaces, but fifteen of those files pre-approve the same drifted
  names this change removes from agents. `Task` appears in seven:
  `qa/commands/{run,loop}.md`, `code-review/commands/{review,fix-all,fix-report,analyze-feedback}.md`
  and `superutils/commands/spec-review.md`. `TaskOutput` appears in three of those
  same seven — `qa/commands/{run,loop}.md` and `superutils/commands/spec-review.md`
  — and in no other file. `browser_run_code` appears in eight more, disjoint from
  the seven: `qa/skills/fe-testing/SKILL.md`, the six
  `web-auditor/skills/*-checklist/SKILL.md` files and `web-auditor/commands/audit.md`.
  Seven plus eight is where fifteen comes from. A stale pre-approval costs only a
  permission prompt, so this is deferred to the same follow-up as the `Task(`
  prose. The validator scans `plugins/*/agents/*.md` and does not cover it.
- The `sequentialthinking` null version in `marketplace.json` — unrelated.
- Prose in `docs/plugins/*.md` describing the two behaviour changes named in
  Delivery (web-auditor's foreground dispatch, `fix-auto`'s narrowed tool list).
  Only the `**Version:**` header changes in those files. No body text documents
  tool lists — `docs/plugins/code-review.md:194` names the `fix-auto` subagent but
  never its grant. `docs/plugins/web-auditor.md` does document the dispatch
  *outcome* at lines 40, 98 and 112 ("dispatches up to 7 parallel scanning
  agents", "two verification subagents analyze the findings in parallel", "spawns
  2 additional subagent instances"). Those three lines stay accurate if same-turn
  foreground `Agent` calls run concurrently and go stale if they serialise — a
  branch already recorded under Residual risks that no layer here observes. The
  prose update therefore rides with the same follow-up as the `Task(` prose and
  with the deferred `/web-auditor:audit` run that would settle which branch holds.

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
`SendMessage`, `Artifact`, `Agent`.

`Agent` is additionally bounded by the nesting depth limit, which defaults to three
layers below the main conversation. Command → coordinator → scanner is two layers,
inside that limit.

Consequence for this repository: `TaskCreate`, `TaskUpdate`, and `TaskList` in the
three `developer` agents, and `TaskCreate` and `TaskUpdate` in `fix-auto`, resolve
only in foreground runs. `fix-auto` no longer carries `TaskList` — `c804315`
dropped it as referenced nowhere on that agent's surface — so the shipped tree
draws eleven of these warnings, three per `developer` agent and two for `fix-auto`.
This is left as-is and reported by the validator as a warning, not an error.

### Bash specifier form

Current documentation specifies space-separated wildcards exclusively:
`Bash(npm *)`, `Bash(git * main)`. A trailing ` *` enforces a word boundary.

This repository, and Claude Code's own machine-written
`.claude/settings.local.json`, use a colon form: `Bash(wc:*)`, `Bash(git config:*)`.
The colon form is therefore a genuine Claude Code convention rather than a local
invention, but the local evidence dates from April 2026 and does not establish that
v2.1.220 still honours it.

**Resolution:** the question is left open rather than answered. The colon form is
undocumented for v2.1.220, and the validator flags colon-form Bash specifiers as a
warning. This change writes no Bash *specifiers* at all, in either form: no
existing `Bash` grant is narrowed, and the four agents that gain `Bash` — the three
`developer` agents and `fix-auto` — receive it as a bare, unqualified tool name.
Least-privilege
narrowing is deferred to a follow-up change, which must first design a test that
measures tool *availability* under a specifier rule rather than the suppression of
a permission prompt — those are different mechanisms, and only the former decides
what a subagent can actually run.

One existing grant already rides on the open question.
`code-review/agents/feedback-analyzer.md:4` declares
`tools: Read, Glob, Grep, Bash(git:*)` — the repository's only colon-form specifier
inside a `tools:` allowlist rather than an `allowed-tools:` pre-approval. It is
left untouched, since no rewrite is defensible before the availability test exists,
and the validator warns on it. If the colon form is inert for `tools:`, that agent
has no `Bash` at all.

## Repairs

Every agent below also has its `allowed-tools:` line deleted.

| Plugin | Agent | Current `tools:` | Target `tools:` |
| --- | --- | --- | --- |
| qa | be-tester | `Read, Write, Bash, Grep, Glob` | `Read, Write, Bash, Grep, Glob, mcp__postgres, mcp__postgres__*, mcp__supabase, mcp__supabase__*, mcp__neon, mcp__neon__*, mcp__mysql, mcp__mysql__*, mcp__mongodb, mcp__mongodb__*, mcp__redis, mcp__redis__*` |
| web-auditor | api-security-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*` |
| web-auditor | compliance-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*` |
| web-auditor | performance-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*` |
| web-auditor | seo-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*` |
| web-auditor | web-security-agent | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*` |
| web-auditor | supply-chain-agent | `Read, Bash, Grep, Glob, WebSearch` | `Read, Bash, Grep, Glob, WebSearch, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*` |
| web-auditor | infrastructure-agent | `Read, Bash, Grep, Glob, WebFetch` | unchanged |
| web-auditor | web-auditor | `Read, Write, Bash, Grep, Glob, Task, TaskOutput, WebFetch, WebSearch` | `Read, Write, Bash, Grep, Glob, Agent, WebFetch, WebSearch, mcp__plugin_playwright_playwright, mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*` |
| code-review | fix-auto | *(absent)* | `Read, Edit, Write, Glob, Grep, Bash, Skill, TaskCreate, TaskUpdate` |
| code-review | security-auditor | `Read, Bash, Grep, Glob` | unchanged |
| code-review | code-quality-auditor | `Read, Bash, Grep, Glob` | `Read, Bash, Grep, Glob, Skill` |
| frontend-developer | developer | `Read, Edit, Write, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList` | same list `+ Bash` |
| python-developer | developer | `Read, Edit, Write, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList` | same list `+ Bash` |
| php-developer | developer | `Read, Edit, Write, Glob, Grep, Skill, TaskCreate, TaskUpdate, TaskList` | same list `+ Bash` |

Target lists are derived from what the agent's body actually does, not from its
former `allowed-tools:` value. Three qualifications, because the plain version of
that sentence is false:

- **Built-in tools named in the body** — `Skill` in `fix-auto`, `WebFetch` and
  `WebSearch` in `web-auditor` — are directly evidenced. `Write` in `fix-auto`
  joined them after implementation: `f2e96fb` added the body sentence bounding its
  use, which is what evidences the entry.
- **`Bash`** is evidenced only *implicitly*. In the three `developer` agents and
  `fix-auto`, the literal string `Bash` appears solely on the `allowed-tools:` line
  being deleted; their bodies invoke the shell by naming commands (`pytest`,
  `ruff`, `tsc`, `composer`, `git`). The grant follows from those commands, and it
  coincides with the deleted pre-approvals because those enumerated the same
  commands. `TaskCreate` and `TaskUpdate` sit in the same position, as does
  `TaskList` in the three `developer` agents — `fix-auto`'s shipped list no longer
  carries it.
- **MCP server names** are carried over from the deleted `allowed-tools:` lists,
  with the drifted per-tool suffixes replaced by the two server-level forms. Only
  `qa/skills/be-testing/SKILL.md:36-39` names its six servers independently.

The second and third are why parts of these lists are invisible to body
reconciliation — see Verification.

### Two dual prefixes for Playwright

`mcp__plugin_playwright_playwright` matches the plugin-provided server — the form
every existing `allowed-tools:` list in this repository targets, though the
Playwright plugin is not in `.claude-plugin/marketplace.json` and is therefore
installed from elsewhere. `mcp__playwright` matches a directly configured server.
Listing both makes the agents work under either installation.

The grant *form* is unverified in the same way the server name is. Two forms are
documented — the bare `mcp__<server>` and the wildcard `mcp__<server>__*` — and
neither has live confirmation of which one v2.1.220 honours for a subagent
`tools:` list. The reasoning that lists both servers therefore lists both forms:
each Playwright row, and each database server on the `be-tester` row, carries the
bare and the wildcard entry. An entry that resolves to nothing is *assumed*
harmless as long as at least one entry in `tools:` resolves — see Residual risks;
nothing in this change tests that assumption.

`be-tester`'s six database servers get the bare prefix in both forms — twelve
entries, not twenty-four. The plugin-prefixed variant is not written because it is
not writable: `mcp__plugin_<plugin>_<server>` needs the providing plugin's name,
and no such plugin is known. That is a limit, not an argument that one cannot
exist — this marketplace does not ship Playwright either, yet seven rows target its plugin
prefix — six of the seven scanning agents plus the coordinator — so absence from
`.claude-plugin/marketplace.json` proves nothing about how a server is installed. The exposure is recorded under Residual risks.

No check in this change can retire the redundant form. The registry echoes the
declared list, so it reports both forms whether or not either resolves; deciding
between them needs a call-time probe — invoking one MCP tool from inside a repaired
subagent that declares a single form — which is deferred alongside the
Bash-specifier availability test.

`qa:fe-tester`, as `cecaa92` left it, declares the wildcard form only. If the bare
form turns out to be the honoured one, every agent repaired here works and
`fe-tester` alone stays broken — the originating symptom. It is therefore brought
onto the dual-form pattern in this change, as the one row carried forward from that
commit:
`Read, Write, Bash, Grep, Glob, mcp__plugin_playwright_playwright,
mcp__plugin_playwright_playwright__*, mcp__playwright, mcp__playwright__*`.

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

The body references `TaskOutput` at four sites, each with `block: true`: two calls
(lines 381 and 382) and two instructions directing the call (line 378 and the
Phase 3 collect step at line 404). Because `TaskOutput` is stripped from every
subagent, that collection mechanism has never worked either.

Rewriting those four sites is not enough on its own. All nine dispatch sites pass
`run_in_background: true`, and line 186 instructs "Launch agents in parallel (all
with `run_in_background: true`)" — ten instructions in total. A bare `Task(` →
`Agent(` substitution leaves every call backgrounded, returning no inline result to
a coordinator that no longer has `TaskOutput`, so the defect would survive its own
repair. The dispatches therefore become `run_in_background: false`, which returns
each child's result inline. Each of the four sites is rewritten to read the result
already returned by its matching `Agent(` dispatch in the same turn; the Phase 3
collect step is re-worded, not removed. After the rewrite the body contains zero
occurrences of `TaskOutput`. Of the nine dispatch sites, seven are the scanning
agents issued in one turn; the remaining two are the optional `cross-verifier` and
`challenger` dispatches, which are the pair the two `TaskOutput(...)` calls
collected and which move to the same inline pattern.

Line 186 is re-worded rather than flipped: it keeps the parallel-launch
instruction, gains "in a single turn", and drops the `run_in_background`
parenthetical entirely — which is why the post-write count of
`run_in_background: false` is nine, one per dispatch site, and not ten.

The coordinator's own dispatch mode is not changed here. `commands/audit.md:75`
passes no `run_in_background` argument and gains none, so the coordinator continues
to run under the documented background default — the condition the parallelism
discussion above assumes. Only the tool name and the line-72 lead-in change in that file.

That last paragraph describes the design, and the design was wrong. `c804315`, a
post-implementation review fix, added `run_in_background: false` to that dispatch
and replaced "Wait for the agent to complete" with an instruction to read the
returned report: this change had removed every collection primitive from the tree,
so a backgrounded coordinator left the entry point waiting for a result it had no
way to obtain. The shipped `commands/audit.md` therefore runs the coordinator in
the foreground, and the background-default premise above no longer describes it.

Three further restatements of that premise stand in this spec, and none of the three
describes the shipped tree. The design-time text is left intact — the record of what
was designed is the point of the document — so each is corrected here instead:

1. The paragraph immediately below frames the open parallelism risk as "whether
   same-turn foreground `Agent` calls from inside a **background** subagent
   actually run concurrently is unverified". Read *foreground* subagent.
2. That paragraph's closing clause, on the `spec-review.md` shape precedent, says
   the precedent is "not evidence that same-turn foreground `Agent` calls from
   inside a **background** subagent run concurrently". Read *foreground* subagent
   there too.
3. Later, under Verification, the pass conditions for `commands/audit.md` assert
   zero `Task(` and zero `Task tool` "only, since its own dispatch mode is
   unchanged". Its dispatch mode *did* change; only the rationale is stale. The
   assertions still hold as written, and those two absences are still the whole set
   asserted for that file, because the post-write run makes no assertion about
   `run_in_background` there.

Substituting "foreground" for "background" in (1) and (2) leaves the risk itself
untouched: nothing in this change measures whether same-turn foreground `Agent`
calls run concurrently, from a parent of either kind.

Those two also carry a background instruction outside every set counted so far:
the step labels `**2. Spawn Cross-Verifier (background)**` (line 336) and
`**3. Spawn Challenger (background)**` (line 359) lose the `(background)`
qualifier, since they now describe foreground dispatches. That makes twelve
background instructions in total, not ten — and they are exactly the two whose
results the coordinator most needs inline, so leaving the labels would be the
defect surviving its own repair. Parallelism is *intended* to be preserved by
issuing all seven scanner `Agent` calls in a single turn; whether same-turn
foreground `Agent` calls from inside a background subagent actually run
concurrently is unverified, and if they serialise the audit still completes and
only loses parallelism. The shape is the one `superutils/commands/spec-review.md:129`
uses for its reviewer panel, though that file dispatches from a command (one
nesting layer) and still names the dispatch tool `Task`, so it is a shape
precedent only, not evidence that same-turn foreground `Agent` calls from inside a
background subagent run concurrently.

## Validator

`scripts/check_agent_frontmatter.py`, following the structure of the existing
`scripts/check_plugin_versions.py`: standard library only, hand-rolled frontmatter
parsing, non-zero exit on error.

Scans `plugins/*/agents/*.md`. It prints the number of agent files scanned and
exits non-zero when the glob matches none, mirroring the empty-discovery guard and
scanned-count summary in `check_plugin_versions.py`: a green run that scanned
nothing is a false pass, not a clean tree. It also *warns* — never errors, so a
legitimately shrinking tree cannot flip the build red — when the scanned count
falls below the twenty-five files the audit found, naming expected and actual. A
count that silently halves is the same false pass one step less degenerate.

Every entry in `tools:` and `disallowedTools:` is normalised before any name check:
for `ToolName(specifier)` only the `ToolName` part is matched, so the
always-stripped and known-bad checks catch `TaskOutput(...)` and `Task(...)`
exactly as they catch the bare names.

**Errors** — fail the build. Every error is either wrong regardless of which
platform version reads the file, or a deliberate fail-closed choice named as such:

- a frontmatter key outside the permitted list. This catches `allowed-tools`,
  documented as unknown, and `hooks`, `mcpServers`, and `permissionMode`, which a
  plugin-loaded agent silently ignores. The rule covers any key not named in
  "Frontmatter fields", so a novel mistyped key still fails the build — which is
  the purpose stated in `## Purpose`. *Fail-closed by choice:* the permitted-key
  list is a v2.1.220 snapshot, so a frontmatter field Anthropic adds later will
  fail the build until the constant is updated. That is the price of catching the
  next `allowed-tools`, and it is recorded under Residual risks.
- missing `name` or `description`
- a tool on the always-stripped list appearing in `tools:` — not in
  `disallowedTools:`, where naming a stripped tool is redundant but harmless —
  which catches `TaskOutput`
- a known-bad tool name in `tools:` or `disallowedTools:`: the constant
  `KNOWN_BAD_TOOLS`, whose sole member at
  v2.1.220 is `Task`, not a tool name in any Claude Code version. Adding a name
  here is a deliberate red/green change, not a knowledge gap — names merely absent
  from the canonical list warn instead.
- frontmatter that is not well-formed, or a `tools:` value outside the accepted
  forms. *Well-formed* means an opening `---` on line 1, a matching closing `---`,
  and every line between them being blank, a `#` comment, a `key: value` pair, or a
  `- item` continuation of the preceding key. `tools:` is accepted in exactly three
  forms — a single-line comma-separated list, a YAML block list of `- name` items,
  and a flow sequence `[a, b]` — with entries trimmed and surrounding quotes
  stripped. `disallowedTools:` is parsed by the same rule, so a known-bad name
  cannot hide behind an unparsed value. A `key:` line with an empty value
  introduces a block list, whose `- item` continuations may carry any leading
  whitespace. Anything else (folded or literal scalars, anchors, aliases, nested
  maps) is an error and fails closed rather than degrading into the
  missing-`tools:` warning. Enumerating the accepted forms matters because the
  parser is hand-rolled: without it, two implementations draw the red/green
  boundary differently on identical legitimate files.

**Warnings** — reported, do not fail:

- an unrecognised tool name in `tools:` or `disallowedTools:`. A name absent from
  the snapshot constant is a limit of this checker's knowledge, not a defect in the
  file, so a tool added or renamed after v2.1.220 must not flip the build red.
  An entry of the form `mcp__<server>` or `mcp__<server>__*` is a server grant
  rather than a tool name and is exempt from this check, since the checker cannot
  know which MCP servers are configured. A
  per-tool entry `mcp__<server>__<tool>` does warn, because "Tool grants" names
  only the two server-level forms.
- a built-in that background subagents lose, such as `TaskCreate`
- a Bash specifier in colon form
- no `tools:` field at all, since inheriting everything is occasionally intended

Five constants are version-pinned and each carries a comment naming its source in
`tools-reference` or `sub-agents` and the date it was verified: the canonical
tool-name list, the permitted-key list, the always-stripped list, the
background-lost built-in list, and `KNOWN_BAD_TOOLS`. Three gate as errors — the
permitted-key list, the always-stripped list, and the known-bad list. The first two
do so as the deliberate fail-closed choice recorded above; the known-bad list gates
because its members are wrong regardless of platform version, so it carries no
staleness risk in the red direction. Centralising the staleness in five visible
places is preferable to spreading it across the checks.

`.github/workflows/agent-frontmatter.yml` mirrors `plugin-version-parity.yml`:
triggered on push and pull request against `master`, pinned action SHAs,
`contents: read`, five-minute timeout.

## Verification

Three layers, because the validator alone would only confirm conformance to rules
this change itself authored.

**Body reconciliation.** Run twice: once before writing, to derive each target
list, and once after writing, as the pass condition for the edits. The post-write
run greps each written file against **its own `tools:` line**, not against the
repairs table, so a transcription slip between table and file is caught wherever
the body names the tool. Two classes of entry it cannot reach, both stated in
Repairs: **MCP entries**, since only `qa/skills/be-testing/SKILL.md:36-39` names
servers verbatim — those six are reconcilable, every other agent's surface contains
no `mcp__` outside its `allowed-tools:` line — and **`Bash`**, which the four
agents that gain it never name, invoking the shell by command instead. Both are
caught, if at all, only by the live registry comparison. Its raw
output is pasted per agent into the pull request body; the author's verdict is
advisory, and the gate is a reviewer re-running the same greps against the
branch's checked-out files — the whole reconciliation surface, not the diff. An
under-declared list is evidenced by *unchanged* body and skill text, which no diff
contains.

*Surface.* The agent body, every `SKILL.md` named in its `skills:` frontmatter,
and every `SKILL.md` the body invokes through the `Skill` tool — for `fix-auto`,
`developer-plugins-integration`. **Every `allowed-tools:` line is excluded from the
hit set**, in agent and skill files alike: those lines are permission
pre-approvals, and counting them is what makes a naive grep pass vacuously.

*Search set*, pinned so the author's run and the reviewer's re-run are byte
identical. Every name in the validator's canonical tool constant — `Bash` and
`Read` on the same footing as `Skill` and `WebFetch` — plus these patterns:

```
Task[A-Za-z]*
mcp__
browser_[a-z_]*
Playwright|Postgres|PostgreSQL|Supabase|Neon|MySQL|MongoDB|Redis
```

The last two matter more than they look. Outside their `allowed-tools:` lines,
`qa/skills/fe-testing/SKILL.md` and the six `web-auditor/skills/*-checklist/SKILL.md`
files contain zero `mcp__` occurrences and name the browser tools only as
`browser_*` — twenty such occurrences in `fe-testing` alone — so a grep for `mcp__`
returns nothing for `qa:fe-tester` or for the six web-auditor scanning agents whose
grants this change adds. The pull request body carries the grep *commands* alongside their raw
output, so the reviewer's re-run is reproducible and a disagreement is
adjudicable.

*Reference.* A call site or an instruction directing the agent to invoke a tool; a
bare prose mention is not — the pattern list is the candidate net, this rule is the
filter applied to its hits. Post-write, `web-auditor.md` must contain zero
occurrences of `Task(`, `TaskOutput`, `run_in_background: true`, the string
`(background)`, and the string `Task tool`; `commands/audit.md` must contain zero
occurrences of `Task(` and the string `Task tool` only, since its own dispatch mode
is unchanged.

Absence alone is not the pass condition — every one of those assertions is also
satisfied by deleting the text, which would leave the coordinator backgrounded and
collecting nothing. So the same run asserts presence: `web-auditor.md` carries nine
`Agent(` dispatch sites, each passing `run_in_background: false`, with no other
occurrence of the token `run_in_background` anywhere in the file; three rewritten
Phase 2.5 collection sites — the lead-in and its two calls — each naming the single
dispatch whose inline result it reads; the Phase 3 collect step present in
re-worded form, referring to the ***in-scope*** scanner results already returned
inline in Phase 2 rather than to a single dispatch — not to seven always, since
dispatch is scope-gated and a narrowed scope issues fewer than seven; a Phase 2
lead-in still present at
the head of the Phase 2 block, instructing that the in-scope agents launch in
parallel **in a single turn**; and the two Phase 2.5 step labels still present
without their qualifier. `commands/audit.md` carries one `Agent(` call and a
line-72 lead-in naming the `Agent` tool. A site removed rather than rewritten
fails.

Pass condition for the layer as a whole: every tool the surface *references* — per
*Reference* above — is covered by that file's own `tools:` line.

*Covered* is not *named*. A built-in is covered by its canonical name. An MCP tool
is covered by a **server-level** entry for the server that provides it, in either
declared form — never by a per-tool entry, which "Tool grants" does not permit and
the validator warns on. This mapping is load-bearing rather than pedantic: the
surfaces name Playwright tools only as `browser_*` (twenty call sites in
`fe-testing/SKILL.md` alone, and e.g. `api-security-checklist/SKILL.md:18`), and no
`tools:` line can ever contain those names. Without the rule the layer would fail
`qa:fe-tester`, the six web-auditor scanning agents and the coordinator — precisely
the set the repair exists for. Only `qa/skills/be-testing/SKILL.md:36-39`
reconciles entry for entry, because it names its six servers verbatim.

An entry present before this change with no reference is not a failure. The target
column is normative, and apart from the two narrowings Delivery names —
`fix-auto`'s move from full inheritance to an explicit list, and the removal of the
non-resolving `Task`/`TaskOutput` entries from `web-auditor` — no existing grant is
narrowed here.

`skills:` preloads a skill's content at startup and does **not** require the
`Skill` tool, so an agent listing its skills there needs no `Skill` grant.
`fix-auto` is the exception: it invokes `developer-plugins-integration`, which it
does not declare in `skills:`.

This is the only check that can catch an under-declared list. The validator
compares declared names against a constant, and the live comparison compares the
registry against the target column that produced it. Neither can see what the body
needs.

**Static.** `check_agent_frontmatter.py` exits zero on the repaired tree and
non-zero on the tree as it stands today. The second half matters: a validator that
passes before the fix is not testing anything.

CI can only ever observe the green half — the workflow runs on the branch, and the
script does not exist on `master` to be run there — so the red-before result gets
the same evidence rule as the greps. It is produced in a throwaway checkout that
never writes to anyone's working tree:

```
test ! -e ../av-pre-change || { echo 'path in use — abort'; exit 1; }
git worktree add --detach ../av-pre-change origin/master || exit 1
cp scripts/check_agent_frontmatter.py ../av-pre-change/scripts/
(cd ../av-pre-change && python3 scripts/check_agent_frontmatter.py); rc=$?
git worktree remove --force ../av-pre-change
exit $rc
```

`--detach` is required so this works from any branch, `master` included — git
refuses to attach a branch that is already checked out elsewhere. `origin/master`
rather than `master` avoids reading a stale local ref. The collision guard matters
because `remove --force` would otherwise delete a pre-existing worktree at that
path, along with any uncommitted work in it.

The in-place alternative — checking `master` out over `plugins/` — is not used:
a path checkout writes the index, so running it with any repair uncommitted
destroys all fifteen irrecoverably, and it would clobber a reviewer's own edits
under `plugins/` too. The pull request body carries the command above and its raw
non-zero output naming each failing file and the check it trips. "It fails today"
from the author is advisory; the gate is a reviewer re-running it.

The glob matches twenty-five files. On `origin/master` — the tree the recipe above
checks out, and the only tree the red-before result describes — **sixteen** of them
fail an error check: the fifteen tabled agents plus `qa/agents/fe-tester.md`, each
carrying an `allowed-tools:` key the permitted-key rule rejects. `cecaa92`, this
branch's own first commit, repaired `fe-tester` ahead of this spec, so the branch
tree shows fifteen and `fe-tester` fails nothing here; its only remaining change is
the dual-form MCP grant. Sixteen, not fifteen, is what the pinned recipe must be
expected to print — it reads `origin/master`, where that repair does not exist. The
nine files this change does not touch — `web-auditor/agents/{challenger,cross-verifier}.md`,
`code-review/agents/{challenger,cross-verifier,documentation-auditor,feedback-analyzer}.md`,
and `superutils/agents/{spec-challenger,spec-fixer,spec-reviewer}.md` — use only
`name`, `description`, `tools`, `model`, and `skills`, and already pass. Should
another agent file fail the new validator, a frontmatter-only repair of that file
is in scope here; no `tools:` list is derived for an agent absent from the repairs
table.

**Live.** After merge, plugin update, and restart, compare the harness's resolved
agent registry against the target column of the repairs table, agent by agent.

Be precise about what this settles. The registry is emitted by the harness rather
than by rules this change authored, and it reports the *pre-filter* grant. A match
therefore confirms only that a declaration parsed, loaded, and deployed exactly as
written. Because the grant is pre-filter, tools the documented filters remove —
notably `TaskCreate`/`TaskUpdate`/`TaskList` in background runs — are expected to
appear and are not a failed repair; their appearance is not evidence that the
filters behaved as described, which no layer observes. Because the registry echoes
the declared list, a match **cannot** confirm that any entry resolves to a callable
tool, and cannot confirm that the list is sufficient. Call this outcome
*declaration-confirmed*, not verified.

`qa:fe-tester` has no repairs-table row; its normative target is the list given
under "Two dual prefixes for Playwright".

Expected entries: `qa:be-tester` — the five built-ins plus twelve `mcp__*` entries
(six database servers, bare and wildcard); `qa:fe-tester` — the five built-ins plus
both Playwright prefixes in both forms; `web-auditor:web-auditor` — includes
`Agent`, excludes `Task` and `TaskOutput`, plus both Playwright prefixes in both
forms; six of the seven web-auditor scanning agents — both prefixes in both forms,
with `infrastructure-agent` unchanged and receiving neither; `code-review:fix-auto` — an
explicit list, no longer "All tools", with a real description; the three
`developer` agents — include `Bash`. The target column is normative; this list is a
reading aid. Normative means that for the fifteen agents the table covers, the live
comparison reads that column and no other document — the one exception is
`qa:fe-tester`, noted above, which has no row and whose target is the list under
"Two dual prefixes for Playwright". The column is therefore kept in sync with the
shipped `tools:` lines, and two rows were corrected after implementation for
exactly that reason (see Delivery). Where a row and the file it describes disagree,
the file governs and the row is the defect.

*Status record.* A tracked file, `docs/agent-tools-verification.md`, committed on
this branch with seventeen rows — the fifteen repairs-table agents, `qa:fe-tester`,
and `code-review:feedback-analyzer` — with columns `Agent | Status | Resolved list`.
The file states plainly that it tracks the agents this change touches rather than
all twenty-five the glob matches, and names `feedback-analyzer` as the one
deliberate exception: it is not repaired here, but its colon-form `Bash(git:*)` is
one of the live availability questions Residual risks leaves open — the only one
attached to an agent this change does not repair — and it was recorded nowhere. Sixteen rows are
seeded `pending`; `php-developer:developer` is seeded `not installed`, since
Residual risks already establishes it can never be compared in this maintainer's
session. Rows are updated in place by later commits
so a re-run rewrites only the rows it checked and "never checked" stays
distinguishable from "checked and matched". It must not live in the pull request
body, which does not survive merge, one release before the check it records comes
due. Prose made an unrun confirmation easy to lose; a tracked table makes it
visible. Nothing here makes anyone look.

Permitted cell values, and the evidence each requires:

| Value | Meaning |
| --- | --- |
| `pending` | never checked |
| `matched — <version>` | the row's **Resolved list** column carries the harness's resolved tool list for that agent **verbatim**; `<version>` is the plugin version it was read at |
| `mismatch — <what differed>` | opens a follow-up repair |
| `not installed` | cannot be compared in a session where the plugin is absent; statically checked only — `php-developer:developer` for this maintainer. A contributor who has it installed may promote the row under the same evidence rule |

A row asserting a match without the pasted resolved list stays `pending`. A row
reverts to `pending` when its recorded version is older than the agent's currently
shipped version, **or** when the list in its **Resolved list** column no longer
matches that agent's current `tools:` value entry for entry — the recorded list is a
content pin on the definition that was confirmed, and it is the half that catches
an edit shipped without a bump. `qa:fe-tester` starts at `pending`, carried over
from `cecaa92`. `code-review:feedback-analyzer` starts at `pending` too, on the same
evidence rule as every other row. A green
CI run is conformance to rules this change itself authored, and is never reported
as verification.

**What no layer checks.** Three things.

*Filter behaviour.* The registry is pre-filter, so nothing observes whether the
documented filters actually strip what the contract says they strip.

*The `web-auditor` dispatch repair.* `Agent` in place of `Task`, foreground
dispatch, and single-turn parallelism are asserted from the documented contract,
not measured. Body reconciliation matches names, the validator reads frontmatter,
and the live comparison reads the registry; none runs the coordinator. Confirming
it needs one `/web-auditor:audit` run against a throwaway target, checking that
seven dispatches are issued, that results arrive inline where `TaskOutput` used to
be, and that the seven ran concurrently. That run is deferred.

*Whether anyone runs the live layer at all.* Nothing gates on it — see Residual
risks.

## Delivery

One branch, `fix/agent-tools-frontmatter`, one pull request.

PATCH bumps: every change repairs a declaration that never granted a tool, and none
adds or removes a plugin-level feature. Two carry a deliberate behaviour change
inside that repair — `fix-auto` narrows from full inheritance to an explicit
body-derived list, and the `web-auditor` dispatches move to the foreground so their
results return inline.
`scripts/check_plugin_versions.py` enforces parity across four surfaces, so each
bump is applied in `plugin.json`, `.claude-plugin/marketplace.json`, the plugin's
README table row, and the `**Version:**` header in `docs/plugins/<name>.md`;
`.github/workflows/plugin-version-parity.yml` runs that check on every pull
request:

| Plugin | From | To |
| --- | --- | --- |
| qa | 2.5.1 | 2.5.2 |
| web-auditor | 2.1.1 | 2.1.4 |
| code-review | 1.17.0 | 1.17.3 |
| frontend-developer | 1.2.0 | 1.2.1 |
| python-developer | 3.0.3 | 3.0.4 |
| php-developer | 1.0.2 | 1.0.3 |

`web-auditor` and `code-review` reach their `To` values in three steps. The repair
itself bumped them to 2.1.2 and 1.17.1. `c804315`, the first post-implementation
review fix on the same branch, bumped them to 2.1.3 and 1.17.2 across all four
surfaces. `f2e96fb`, the second, changed three plugin files — it restored `Write` to
`fix-auto` with the body sentence that now evidences it, and gave the coordinator's
not-assessed instruction somewhere to render — and landed with **no** bump on any of
the four surfaces; the correction pass that followed carries both plugins to 2.1.4
and 1.17.3, again across all four. Only `code-review` needed the `Write` half; the
`web-auditor` bump covers the coordinator half of the same commit.

`c804315` also moved two Repairs-table targets, which are updated in place above
rather than left to drift: `code-quality-auditor` is no longer `unchanged` — its
body instructs it to invoke the developer-plugin skills it neither preloads nor
could reach, so it gains `Skill` — and `fix-auto`'s list was narrowed to what its
surface references, less `TaskList` and, for one commit, less `Write`. The
target column is the spec's record of what ships; a row that disagrees with the
shipped `tools:` line is a defect here, to be corrected before the live comparison
runs, and never a `mismatch` verdict against the agent.

The authoring rule ships in a **tracked** file: agent capability is declared in
`tools:`; `allowed-tools` belongs to skills and commands only. It cannot live in
`CLAUDE.local.md`, which `.gitignore:3` excludes — a rule written there stays on
one machine and never reaches the branch, the pull request, or another
contributor, which is precisely how the four-surface versioning rule drifted in
the first place. This change creates a tracked root `CLAUDE.md` carrying both the
authoring rule and the corrected versioning rule, naming all four surfaces the
parity check enforces — `plugin.json`, `.claude-plugin/marketplace.json`, the
README table row, and the `**Version:**` header in `docs/plugins/<name>.md` —
instead of only `plugin.json` and the README row. `CLAUDE.local.md` may mirror it
locally; the tracked copy is authoritative.

Plugins install from the GitHub repository, not from the local checkout, so no fix
takes effect in a session until the branch is merged and the plugin updated.

## Residual risks

**`php-developer` is not installed in the maintainer's session.** It is absent from
`~/.claude/settings.json`, so it will not appear in the harness registry and its
repair is confirmed statically only.

**The canonical tool list will age.** It is a snapshot of v2.1.220. If Anthropic
adds or renames a tool, the validator produces false warnings until the constant is
updated — warnings rather than errors precisely so that an aged constant cannot
turn a correct agent definition red. The always-stripped list ages the same way but
gates as an error, for the same deliberate fail-closed reason as the permitted-key
list. The comment naming each constant's source and verification date is the
mitigation for the noise that remains.

**The permitted-key list will age too, and it gates as an error.** An unrecognised
frontmatter key fails the build, so a field added after
v2.1.220 turns a correct agent definition red until the constant is updated. This
is the deliberate fail-closed choice recorded in `## Validator`: the alternative —
warning on unknown keys — would let the next `allowed-tools` typo ship silently,
which is the defect this change exists to remove.

**No automated oracle proves a target list is sufficient.** The validator checks
declared names against a snapshot constant, and the live comparison checks the
registry against the target column that produced it; neither can show that a target
list contains every tool its agent's body invokes. Body reconciliation is manual —
its post-write run and pasted grep output make it reviewable, but a reviewer who
does not re-run the greps is the only thing standing between an under-declared list
and a green build.

**The MCP grant form is unconfirmed, and so is the fallback assumption.** Both
`mcp__<server>` and `mcp__<server>__*` are declared because neither is confirmed
for a subagent `tools:` list. A third possibility — per-tool names — is untested;
the per-tool enumerations this change removes lived in the inert `allowed-tools:`
key, so their drift is not evidence against them. If no server-level form is
honoured, every Playwright and database repair ships inert with body
reconciliation, CI, and the live comparison all green, and the originating
`fe-tester` SKIP symptom unchanged. The dual-form hedge also assumes an entry
resolving to nothing is ignored rather than invalidating the list or falling back
to full inheritance; nothing here tests that.

**A plugin-installed database MCP server would not match `be-tester`'s grants.**
The row declares the bare `mcp__<server>` prefix in both forms. A server supplied
by a plugin — from this marketplace or any other — surfaces as
`mcp__plugin_<plugin>_<server>`, which is not declared and cannot be, since the
providing plugin's name is unknown. The registry echoes the declared list, so no
layer detects the miss.

**Deleting an agent's `allowed-tools:` is assumed inert for permissions, not only
for availability.** Evidence 1 and 2 observe the resolved tool list; neither shows
that the fifteen deleted pre-approval lists — thirty `Bash(...)` entries in
`code-quality-auditor`, seventeen in `be-tester`, sixteen in `security-auditor`,
and so on — were doing nothing for permission prompts. If they were not, repaired
agents gain availability and lose prompt suppression, and no layer here observes
prompts.

**The `web-auditor` dispatch repair is asserted, not measured.** `Agent` in place
of `Task`, foreground dispatch, and single-turn parallelism follow from the
documented contract, but no layer runs the coordinator. If same-turn foreground
`Agent` calls serialise, the audit still completes and simply loses parallelism,
and nothing in this change would show it.

**Deferred `Task(` prose and stale pre-approvals.** Roughly twenty sites in
`code-review`, `qa`, and `superutils` keep instructing the model to "use the Task
tool" — including `superutils/commands/spec-review.md:129`, the reviewer fan-out
this spec cites as a shape precedent. Fifteen command and skill files additionally
pre-approve `Task`, `TaskOutput`, or `browser_run_code` in their `allowed-tools`
values. Neither is a hard failure — prose works by inference, a stale pre-approval
costs a permission prompt — but both are drift the validator does not cover, since
it reads agent frontmatter rather than prose or other file classes.

**One live grant rides on the unconfirmed colon form.**
`code-review:feedback-analyzer`'s `Bash(git:*)` is a `tools:` availability entry,
not a pre-approval. No layer in this change observes whether it resolves, and the
agent falls outside the fifteen-agent scope because it carries no `allowed-tools:`
line.

**The status record's staleness pin is a convention, not a check.**
`check_plugin_versions.py` compares the four version surfaces to each other; it
never requires that an edited agent file be bumped at all — the same class of drift
this change already found on `docs/plugins/qa.md`. The content-keyed half of the
reversion rule, not the version pin, is what catches an unbumped `tools:` edit, and
it still depends on someone re-reading the table. A `matched` row attests to the
definition confirmed at the recorded version, and only for as long as that
definition is what ships.

**The live layer has no trigger and no owner.** Nothing gates on it: the branch
merges on CI plus a reviewer's re-run greps, and the status table is updated only
if someone remembers to run the registry comparison after the next plugin update.
The table makes an unrun confirmation *visible*, not *noticed* — `qa:fe-tester`'s
row is the confirmation owed since `cecaa92` and still unrun, now carried a second
time. No release boundary has passed in between: 2.5.1 was never shipped, and it
merges together with 2.5.2 in this pull request.

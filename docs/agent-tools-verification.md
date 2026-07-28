# Agent tool verification status

Records the live layer of the repair in
`docs/superpowers/specs/2026-07-27-agent-tools-frontmatter-design.md`: comparing
each agent's harness-resolved tool list against its target. Targets come from three
sources, not one. For the fifteen rows the spec's Repairs table covers, the target is
that table's target column, kept in sync with the agent's shipped `tools:` line;
where the two disagree, the shipped file governs and the spec row is the thing to
repair, not the agent. The two remaining rows have no Repairs-table row at all:
`qa:fe-tester`, whose target is the list the spec gives under "Two dual prefixes
for Playwright", and `code-review:feedback-analyzer`, which this change does not
repair and whose target is therefore its own shipped `tools:` line.

A row reads `matched — <version>` only when its Resolved list column carries the
harness's resolved list verbatim. A row reverts to `pending` when its recorded
version is older than the shipped version, or when its Resolved list no longer
matches that agent's current `tools:` value entry for entry.

A match is *declaration-confirmed*, not verified: the registry echoes the declared
list, so it cannot confirm that any entry resolves to a callable tool.

**This record is not a census of the repository's agents.** `plugins/*/agents/*.md`
matches twenty-five files; seventeen are tracked below — the sixteen this change
touches, plus one deliberate exception. Nine files fall outside the repair. Eight
of those are untracked here: they already conform and gain no `tools:` edit, so
there is nothing about them for a live comparison to confirm. The ninth is the
exception, `code-review:feedback-analyzer`, listed last: this change does not touch
it either, but its `Bash(git:*)` grant is one of the live availability questions the
spec's Residual risks leaves open — and the only one attached to an agent this
change does not repair. If the colon specifier form is inert inside `tools:`, that
agent has no `Bash` at all, and it was tracked nowhere.

Permitted cell values, and the evidence each requires:

| Value | Meaning |
| --- | --- |
| `pending` | never checked |
| `matched — <version>` | the row's **Resolved list** column carries the harness's resolved tool list for that agent **verbatim**; `<version>` is the plugin version it was read at |
| `mismatch — <what differed>` | opens a follow-up repair |
| `not installed` | cannot be compared in a session where the plugin is absent; statically checked only. A contributor who has it installed may promote the row under the same evidence rule |

A row asserting a match without the pasted resolved list stays `pending`.

| Agent | Status | Resolved list |
| --- | --- | --- |
| `qa:be-tester` | pending | |
| `qa:fe-tester` | pending | |
| `web-auditor:api-security-agent` | pending | |
| `web-auditor:compliance-agent` | pending | |
| `web-auditor:performance-agent` | pending | |
| `web-auditor:seo-agent` | pending | |
| `web-auditor:web-security-agent` | pending | |
| `web-auditor:supply-chain-agent` | pending | |
| `web-auditor:infrastructure-agent` | pending | |
| `web-auditor:web-auditor` | pending | |
| `code-review:fix-auto` | pending | |
| `code-review:security-auditor` | pending | |
| `code-review:code-quality-auditor` | pending | |
| `frontend-developer:developer` | pending | |
| `python-developer:developer` | pending | |
| `php-developer:developer` | not installed | absent from `~/.claude/settings.json`; statically checked only |
| `code-review:feedback-analyzer` | pending | not repaired by this change; tracked because its `tools: Read, Glob, Grep, Bash(git:*)` is the repository's only colon-form specifier inside a `tools:` allowlist. A match confirms the declaration parsed, not that `Bash` resolves |

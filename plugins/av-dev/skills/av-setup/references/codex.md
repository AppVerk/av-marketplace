# Claude Code and Codex from one source

Goal: one copy of instructions and skills. Manual ports (e.g. `.codex/agents/*.toml`) drift from the original within a few weeks.

## Instructions

- Source: `CLAUDE.md`.
- `AGENTS.md` is a symlink: `ln -s CLAUDE.md AGENTS.md`.
- When `AGENTS.md` exists as a regular file with different content, do not overwrite it. Show the diff and ask which version is the source. Merge the other one's content into the source, then create the symlink.
- Imports like `@docs/file.md` work in Claude Code. Codex does not expand them. When `CLAUDE.md` relies on imports, add a plain markdown link next to them or a routing table with paths. Then both tools reach the file.

## Project skills

- Source: `.claude/skills/`.
- Codex reads project skills from `.agents/skills/`. Create a directory symlink from the repo root: `mkdir -p .agents && ln -s ../.claude/skills .agents/skills`. The symlink target is resolved relative to `.agents/`, so `../.claude/skills` is correct.
- Create the symlink only when `.claude/skills/` has skills to keep: role skills from `av-setup` or KEEP and UPDATE skills. When all of them are CONVERT and wait for approval to delete, do not create the symlink, because Codex would get old pipeline wrappers. Create it after the deletion, if anything remains.
- A repo without `.claude/skills/` gets no symlink. It would point at nothing. The report then says "Codex: AGENTS.md; no project skills".
- Check `git check-ignore -q .agents/skills` (scan: `ai_setup.agents_ignored`). When the team deliberately ignores `.agents/`, do not create the symlink and do not change `.gitignore`. Record it in the report as a team decision.
- When `.agents/skills/` exists as a directory with files:
  1. Compare skills present in both places. Delete identical ones from `.agents/skills/`.
  2. Move unique ones to `.claude/skills/`.
  3. Mark command-port skills (e.g. `source-command-*`) as DROP in the plan. The `av-*` skills take over their job.
  4. Replace the directory with a symlink only when it is empty.

## Global av-* skills

The `av-*` skills live outside the repo: in `~/.claude/skills/` or in the `av-dev` plugin. Codex needs a separate install of them. Check the location of Codex user skills in its current documentation. Do not guess the path. In the report, give the symlink command when the location is known.

A slot executor on Codex (`agent.sh`, `provider: codex`) does not need this install. It runs in a sandbox from `~/.codex/config.toml` (default `workspace-write`); a human grants missing permissions through the orchestrator. `agent.sh` gives it the skills directory path in the prompt header, and Codex reads `SKILL.md` straight from disk. The install is needed only when a human runs av-* skills directly in Codex.

## What not to touch

- `.codex/config.toml`: environment and MCP servers for Codex. It stays.
- `.codex/hooks.json`: it stays. Report it when it contains absolute paths with a user name, because it will not work for other people.
- `.codex/agents/*.toml`: DROP in adoption after approval.

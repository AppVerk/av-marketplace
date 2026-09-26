# Interview

Ask only about what cannot be derived from the repo. Every question has a hint from the scan result. The user confirms or corrects it. With `--defaults`, skip the interview and use the detected values.

Ask the questions with one question tool (e.g. AskUserQuestion), at most 4 at once. Put the recommended option first.

## Round 1: always

1. **Validation gates.** Show the detected commands and the proposed split into `quick` and `full`. Sources in order of trust: CI, repo scripts, composer/package.json, Makefile. Ask whether it is right.
   - Take `expect` and `notRunExitCodes` from `commands.scripts_meta` in the scan. `exit_codes_doc` is the exit code description from the script header; e.g. "2 when the environment is unavailable" gives `notRunExitCodes: [2]`. `status_tokens` are the status strings the script prints; e.g. `UNIT_OK` gives `expect`.
   - A token `X_FAILED` without `X_OK` usually means a status built in code (e.g. `label + '_OK'` in a helper). Confirm it by reading the code or running it before you write `expect`.
   - A "zero tests" or "tests skipped" code is not a missing environment for unit tests. Leave it out of `notRunExitCodes`, unless the script describes it as a missing account or device.
   - Propose a `docs` command in `quick` (`references/config-schema.md`, section validation).
   - Read each candidate command before proposing it. Mark and explain in the proposal:
     - a command that writes tracked files (a build into a committed directory, a test that rewrites a fixture): it makes the evidence STALE; keep it out of `quick` and `full`, or run it last and say so in `needs`;
     - a command that may print secrets into logs (secret scanners, commands that dump the environment, especially when the repo tracks an env file): never a gate, because gate logs are kept as evidence;
     - a command that starts, stops or restarts containers or services by a fixed name: it can hit another checkout; not a gate;
     - one exit code for both "environment missing" and "tests failed": `notRunExitCodes` cannot separate them; guard the command with a `precheck`.
2. **Git.** Show the detected base branch, the commit pattern (from history) and the ticket prefixes. Defaults: commit only on request, no push, no AI signature.
3. **High-risk areas.** Propose a list from the scan, the code and the docs (e.g. auth, payments, migrations, when the repo has them). The user adds domain areas.
4. **Docs language.** By default, detected from the existing docs.

## Round 2: only when relevant

- **Docs root**, when the repo has both `docs/` and `.ai/`, or neither. By default the existing one, and `.ai` for a new repo.
- **Reference module** for code templates, when there are several candidates.
- **Codex**, when the repo has `AGENTS.md`, `.codex/` or `.agents/`. Default: yes. Without these files the default is also yes, because the cost is one symlink.
- **AI signature in commits**, when the sources differ. Order of precedence: a team rule in docs (e.g. a commit standard, `CLAUDE.md`) > the `includeCoAuthoredBy` setting in `.claude/settings.json` > default `false`. The share of commits with a signature (`ai_signature_commits`) is only information, not a rule. With `--defaults`, choose by this order and record it in "Default decisions".
- **Security settings**, when the scan found secret files without `permissions.deny` rules. Propose adding the rules to `.claude/settings.json`. Editing settings needs approval.

## Default values without asking

- `agents.models`: `plan` and `implement` = `inherit`, `review` = `opus`, `verify` = `haiku`. When the user has Codex CLI (`command -v codex`), ask about the alternating mode: `crossVendor: true`, `review` and `plan` on Codex, `implement` and `planReview` on Claude (example in `config-schema.md`). Default: no, because it needs a login in both CLIs. On "yes", also write `agents.timeoutSec: 3600` (the CLI slot limit). In the same question, ask about slot effort; hint: `plan` and `planReview` = `high`, `implement` = `high`, `review` = `xhigh`.
  - Codex model: the `model` value from `~/.codex/config.toml`, and the list of models and efforts from `~/.codex/models_cache.json` (`.models[].slug`, `.models[].supported_reasoning_levels[].effort`). Do not copy the model from the example. Reject an effort outside the model's list in the interview. Both files missing: `"model": "inherit"`.
  - The team config sets the mode for the team. A person without Codex CLI does not change it for everyone: they switch slots in `.ai/av.config.json.local` (`config-schema.md`, section "Local override"). Setup gives a ready example in the report, but does not create the `.local` file.
  - Slot agent definitions (`av-slot-<effort>`) are needed when any `claude` slot has an effort other than `inherit`, also without the alternating mode. `SKILL.md`, step 9 handles installation.
  - Alternating mode: tell the user about the allow rule for `agent.sh` and about permission prompts (skill `av-implement`, section "Permissions"). The user adds the rule, not setup. In ADOPTION, take the stronger of two: the model from the converted agent's frontmatter or this default. Order: `haiku` < `sonnet` < `opus`; `inherit` stays when the old agent had no explicit model. Slots: architect and planner -> `plan`; implementers -> `implement`; reviewers and security -> `review`; verifiers -> `verify`.
  - Several agents in one slot: take the model of the agent that did the hardest work in that slot (code assessment > failure diagnosis > running commands).
  - `verify` never gets `opus`: `haiku` for just running commands, `sonnet` when the verifier diagnosed failures (e.g. E2E test analysis).
  - `inherit` means "session model" and sits outside the scale. Keep `inherit` in the `plan` and `implement` slots, unless the old agent had an explicit model there; then take the explicit one.
  - Adoption does not lower the review model.
  - `fable` is an allowed value, but it sits outside the scale. Write it only on the user's decision.
- `agents.independentReview`: `true`.
- `integrations`: from `.mcp.json`, `enabledMcpjsonServers` and MCP server names (e.g. atlassian/jira -> tracker `jira`, figma, bitbucket). Tool names from docs (e.g. Lokalise) as extra fields.
- Tool integrations (a board, a design tool): record them in `integrations`. How to access a tool (MCP, browser, CLI) is the team's decision: take it from the repo (existing agents, skills, docs) or ask. The plugin has no default.
- `git.baseBranch`: the branch that pull requests go to in the history (`merged_branch_names`, docs about the flow). When docs list several main branches without choosing one, take `develop` if it exists. `base_branch_guess` from the scan is only a hint; in a local clone it may be wrong.
- `git.ticketPrefixes`: the keys of `git.ticket_prefixes` from the scan with a count of at least 3, plus prefixes from docs. Single hits are usually noise.
- `git.commit`: the team rule from docs; when docs conflict or say nothing, `on-request`, and the conflict goes to the report.

## What not to ask

- About things visible in the code (framework, versions, directory layout).
- About code style preferences that can be read from linters and existing code.
- About secrets. Never ask for tokens or passwords. Describe a test account as a requirement in `needs`.

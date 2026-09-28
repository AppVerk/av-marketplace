# Oh My Pi (OMP)

The OMP edition is generated from the same sources as the Claude Code plugins. It contains Code Review, Commit, QA and the Frontend, PHP and Python Developer plugins, plus two plugins that exist only in OMP:

- [Delivery](plugins/delivery.md) delivers an approved plan-mode plan task by task: each task goes to the developer agent that owns its files, is reviewed, and gets its own commit.
- [Plan Review](plugins/plan-review.md) has a second model review every plan-mode plan before it reaches the approval dialog.

## Installation

```bash
omp plugin marketplace add AppVerk/av-marketplace
omp plugin install \
  code-review@av-marketplace commit@av-marketplace qa@av-marketplace \
  delivery@av-marketplace plan-review@av-marketplace \
  python-developer@av-marketplace frontend-developer@av-marketplace php-developer@av-marketplace
```

`omp plugin install` accepts several plugin IDs; list only the plugins you need. Delivery hands tasks to the developer plugins, and `/qa:loop` needs Code Review. Start a new OMP session after installing: a running session does not load the extensions that Commit, Delivery and Plan Review ship.

Delivery needs Python 3.9 or newer as `python3`, and Commit needs `jq`; see [Prerequisites](installation.md#prerequisites).

## Updating

```bash
omp plugin marketplace update av-marketplace
omp plugin upgrade
```

`omp plugin upgrade` compares installed versions with the cached catalog and does not fetch it, so update the marketplace first. To upgrade one plugin, pass its ID, e.g. `omp plugin upgrade delivery@av-marketplace`.

## Model roles

Agents pick their model through model roles instead of a fixed model:

| Role | Agents |
|------|--------|
| `code_review` | Code Review's auditors, Delivery's task reviewer |
| `executor` | `code-review:fix-auto`, the developer agents, Delivery's implementer |
| `tester` | QA's FE and BE testers |
| `challenger` | Code Review's challenger and cross-verifier |
| `analyst` | Code Review's composition analyst, decision analyst and feedback analyzer |
| `plan` | OMP plan mode, QA's test planner |
| `advisor` | Plan Review's reviewer, QA's test-plan reviewer |

Map them in `~/.omp/agent/config.yml`, for example:

```yaml
modelRoles:
  code_review: anthropic/claude-opus-5-5
  analyst: anthropic/claude-opus-5-5
  executor: openai-codex/gpt-5.5
  tester: openai-codex/gpt-5.5
  challenger: openai-codex/gpt-5.5
  advisor: openai-codex/gpt-5.5
```

An unmapped role falls back:

- Agents generated from the Claude Code plugins use `opus`, the model their Claude Code edition names, then the session model. `code-review:decision-analyst` uses the session model, as in Claude Code.
- Delivery's implementer and task reviewer use the session model.
- `advisor` is an OMP role: unmapped, it first resolves through your `slow` role, or OMP's built-in list of slow models.

Delivery routes a task that lists no files through OMP's `judge` role; see the [Delivery guide](plugins/delivery.md#plan-format).

## Differences from Claude Code

Commands carry their plugin's name: `/commit:commit`, `/code-review:review`, `/code-review:fix QA-001`. The OMP sections of the [Commit](plugins/commit.md#oh-my-pi) and [QA](plugins/qa.md#oh-my-pi) guides cover the rest, such as QA's browser settings and how the git guards behave without a UI.

# Oh My Pi (OMP)

Most OMP plugins are generated from the same sources as their Claude Code editions. The OMP column of [Available Plugins](../README.md#available-plugins) shows which plugins it contains. Plan Review exists only in OMP; Delivery's OMP edition is written for OMP instead of generated from its Claude Code edition:

- [Delivery](plugins/delivery.md) delivers an approved plan-mode plan task by task: each task goes to the developer agent that owns its files, is reviewed, and gets its own commit; then QA runs when the change is testable, and a code review closes the delivery.
- [Plan Review](plugins/plan-review.md) has a second model review every plan-mode plan before it reaches the approval dialog.

## Installation

```bash
omp plugin marketplace add AppVerk/av-marketplace
omp plugin install <plugin>@av-marketplace
```

`omp plugin install` accepts several plugin IDs at once. Delivery hands tasks to the developer plugins and, with QA installed, runs `/qa:run` on testable deliveries; `/qa:run` needs Code Review for fixes. Start a new OMP session after installing: a running session does not load the extensions that Commit, Delivery and Plan Review ship.

QA and Code Review's auto-accept and `after_review` need Python 3.11 or newer as `python3`, Delivery needs Python 3.9 or newer, and Commit needs `jq`; see [Prerequisites](installation.md#prerequisites).

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
| `tester` | QA's FE, BE and desktop testers |
| `challenger` | Code Review's challenger and cross-verifier |
| `analyst` | Code Review's composition analyst, decision analyst and feedback analyzer |
| `plan` | OMP plan mode, QA's test planner and config author |
| `advisor` | Plan Review's reviewer, QA's test-plan reviewer, the Advisor of QA's test planner |

### Recommended models

This is the mapping we run the plugins with and test them on. Put it in `~/.omp/agent/config.yml`:

```yaml
modelRoles:
  plan: anthropic/claude-fable-5-1:max
  advisor: openai-codex/gpt-6-astra
  executor: openai-codex/gpt-6-sol:xhigh
  code_review: anthropic/claude-opus-5-5:xhigh
  challenger: openai-codex/gpt-6-sol:xhigh
  analyst: anthropic/claude-opus-5-5:xhigh
  tester: openai-codex/gpt-6-sol:low
```

The suffix after a model sets its thinking level. The mapping pairs each check with a different model family than the work it checks:

| Work | Checked by |
|------|------------|
| Plans (`plan`, Anthropic) | Plan Review, QA's test-plan reviewer and the test planner's Advisor (`advisor`, OpenAI) |
| Code (`executor`, OpenAI) | Delivery's task reviewer and Code Review's auditors (`code_review`, Anthropic) |
| Review findings (`code_review`, Anthropic) | Code Review's challenger and cross-verifier (`challenger`, OpenAI) |

The models need the `anthropic` and `openai-codex` providers logged in (`/login anthropic`, `/login openai-codex`); `omp models anthropic` and `omp models openai-codex` list what your account offers. If you use other providers, keep the pairing: map each checking role to a different model family than the role it checks.

### Decision model

The `judge` role supplies the decision model for [Delivery routing](plugins/delivery.md#routing) and Code Review's second opinion when `[code-review]` sets `auto_accept_gate = "decision-model"` (see [Code Review configuration](plugins/code-review.md#configuration)). Code Review re-runs the cited evidence for that opinion and cascades to a second `decision-analyst` when the decision model does not agree. Unmapped, the role uses TypeSafe Jev when you have TypeSafe or OpenRouter credentials.

Only catalog decision models count: `omp models --kind judge` lists them. The answering model must match a catalog selector, or that selector followed by `-` and eight digits. A failed listing accepts no model. A chat model from OMP's fallback chain is ignored: Delivery falls back to text routing, and Code Review asks a second analyst.

A local alternative is `nimble-v3:9b`, which needs Ollama 0.40.4 or newer. Download it:

```bash
ollama pull nimble-v3:9b
```

Declare it in `~/.omp/agent/models.yml`, using the Ollama base URL:

```yaml
providers:
  nimble-local:
    baseUrl: http://127.0.0.1:11434
    api: typesafe
    auth: none
    models:
      - id: nimble-v3:9b
        kind: judge
```

Then map the role in `~/.omp/agent/config.yml`:

```yaml
modelRoles:
  judge: nimble-local/nimble-v3:9b
```

The role also drives OMP's own judged features (`find`, TTSR question rules and auto-thinking), so remapping it changes those too.

### Fallbacks

An unmapped role falls back:

- Agents generated from the Claude Code plugins use `opus`, the model their Claude Code edition names, then the session model. `code-review:decision-analyst` uses the session model, as in Claude Code.
- Delivery's implementer and task reviewer use the session model.
- `advisor` is an OMP role: unmapped, it first resolves through your `slow` role, or OMP's built-in list of slow models.

## Advisor

QA's test planner runs with OMP's Advisor: a second model on the `advisor` role watches the planner's turns while it writes the plan and can steer it. The main session and every other agent run without an Advisor unless you enable one (`advisor.enabled` or `/advisor on` for the session). Switch it off for the planner, or on for another agent, with `task.agentAdvisor` in `~/.omp/agent/config.yml`:

```yaml
task:
  agentAdvisor:
    "qa:test-planner": "off"
    "delivery:implementer": "on"
```

A value other than `"on"` or `"off"` is a model pattern for that agent's Advisor.

## Differences from Claude Code

Commands carry their plugin's name: `/commit:commit`, `/code-review:review`, `/code-review:fix QA-001`. The OMP sections of the [Commit](plugins/commit.md#oh-my-pi) and [QA](plugins/qa.md#oh-my-pi) guides cover the rest, such as QA's browser settings and how the git guards behave without a UI.

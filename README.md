<div align="center">

# av-marketplace

**One AI development harness for Claude Code and Oh My Pi.**<br>
Plan, deliver, test, review and commit, with each stage handing its output to the next.

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Plugins](https://img.shields.io/badge/plugins-14-green.svg)](#available-plugins)
[![Claude Code](https://img.shields.io/badge/Claude_Code-supported-D97757.svg)](#claude-code)
[![Oh My Pi](https://img.shields.io/badge/Oh_My_Pi-supported-A98BFA.svg)](#oh-my-pi-omp)

</div>

![From plan to pull request. Claude Code: brainstorm a spec with superpowers, review it with /superutils:spec-review, write the plan, then start delivery. Oh My Pi: write the plan in plan mode, Plan Review has a second model review it, then you approve it. Delivery, for every task: route it to the agent that owns its files, implement, review with up to 3 fix rounds, commit. After the last task: verification, QA and code review, then you choose which findings to fix and open the PR.](docs/assets/harness-flow.png)

## Why use it

- **Plans run task by task.** Delivery sends each task to the developer agent that owns its files, has it reviewed and gives it its own commit.
- **Every result gets a second look.** A task reviewer checks each task's code before it is committed. In every code review a challenger tests the serious findings for false positives and a cross-verifier correlates findings across domains. In Oh My Pi a second model also reviews each plan, and with the recommended role mapping each check runs on a different model family than the work it checks.
- **QA exercises the running app.** `/qa:run` tests in the browser, through APIs and data stores, and in desktop apps, then can fix the issues you approve and retest within fixed limits.
- **Findings have IDs.** Code review and QA findings carry IDs like `SEC-001` and `QA-001`; `/fix`, `/fix-report` and `/fix-all` work on both.
- **You keep the decisions.** You approve the plan, choose which findings get fixed after each review and push the branch yourself. The Commit plugin blocks direct `git commit` and force-pushes.
- **Experts for your stack.** Python, TypeScript + React and PHP developer agents bring coding standards and TDD.

## How it works

Claude Code and Oh My Pi hand the plan to the same Delivery pipeline. They differ in how the plan is made and checked, and in which models do the work:

| | Claude Code | Oh My Pi |
|---|---|---|
| Before the plan | Brainstorm a spec with [superpowers](docs/workflow.md#prerequisites), then check it with `/superutils:spec-review` | Write the plan in plan mode |
| Plan check | Delivery sends back a plan whose tasks break its format | Plan Review: a second model reviews every plan before the approval dialog; Delivery checks the task format |
| Delivery starts when you | pick subagent-driven execution for a superpowers plan, approve a plan-mode plan, or run `/delivery:execute <plan>` on a plan in [Delivery's format](docs/plugins/delivery.md#plan-format) | approve a plan-mode plan, or run `/delivery:execute <plan>` on a plan in Delivery's format |
| Models | Plugin agents run on `opus`; `decision-analyst` uses the session model | Agents ask for model roles; with the [recommended role mapping](docs/oh-my-pi.md#recommended-models), each check runs on a different model family than the work |
| Task without a file list (`/delivery:execute`) | Routed by its text | In a Python, PHP or React repository, a decision model (`judge` role) routes it when it names one stack with enough confidence; otherwise its text decides |
| Commands | `/review`, `/fix SEC-001`, `/fix-all`, `/commit` | `/code-review:review`, `/code-review:fix SEC-001`, `/code-review:fix-all`, `/commit:commit` |
| Only in this tool | Superutils, Security Pipeline, Web Auditor, Simple Language, Sequential Thinking | Plan Review |

![Who checks whom in Oh My Pi with the recommended role mapping: plans written on the plan role (Anthropic) are checked on the advisor role (OpenAI); code written on the executor role (OpenAI) is checked on the code_review role (Anthropic); review findings from the code_review role are checked on the challenger role (OpenAI).](docs/assets/cross-model-checks.png)

This README uses the Claude Code command names. In Oh My Pi every command carries its plugin's name, so `/fix-report` is `/code-review:fix-report` and `/commit` is `/commit:commit`; `/qa:run` and `/delivery:execute` are the same in both.

The [Recommended Workflow](docs/workflow.md) walks through every stage and the artifact it leaves; the [Oh My Pi guide](docs/oh-my-pi.md#model-roles) lists the model roles and the models we run them with.

## Installation

Add the marketplace, then install the plugins you need. [Available Plugins](#available-plugins) lists their IDs and which tool supports each one. For the whole harness, install Delivery, Code Review, QA, Commit and the developer plugin for your stack; in Claude Code, add Superutils for spec review (it builds on [superpowers](docs/workflow.md#prerequisites)); in Oh My Pi, add Plan Review.

### Claude Code

```bash
/plugin marketplace add AppVerk/av-marketplace
/plugin install <plugin>@av-marketplace
```

You can also pick plugins in the Discover tab of `/plugin`. Verify with `/help`: the installed plugins' commands are listed.

### Oh My Pi (OMP)

```bash
omp plugin marketplace add AppVerk/av-marketplace
omp plugin install <plugin>@av-marketplace
```

`omp plugin install` accepts several plugin IDs at once. The [Oh My Pi guide](docs/oh-my-pi.md) covers updating, prerequisites and the models we recommend per role.

## Available Plugins

| Plugin | Version | ID | Claude Code | OMP | Description |
|--------|---------|----|:-----------:|:---:|-------------|
| [Code Review](docs/plugins/code-review.md) | 2.5.0 | `code-review` | ✓ | ✓ | Security, architecture and code-quality review with an adversarial challenger and cross-domain correlation; fix findings by ID (`/fix SEC-001`) or in bulk (`/fix-report`, `/fix-all`) |
| [Commit](docs/plugins/commit.md) | 1.4.1 | `commit` | ✓ | ✓ | Conventional Commits messages; blocks direct `git commit`, force-push and protected-branch deletion, and asks before pushes to `main`/`master`, tags and other remotes |
| [Security Pipeline](docs/plugins/security-pipeline.md) | 1.0.1 | `security-pipeline` | ✓ | — | `/setup` adds Semgrep SAST and TruffleHog secret-scanning steps to your CI; detects GitHub Actions, GitLab CI, Bitbucket and Azure DevOps |
| [Web Auditor](docs/plugins/web-auditor.md) | 2.1.5 | `web-auditor` | ✓ | — | Audits a running website for security, SEO, performance and compliance; `--verify` adds cross-domain correlation and adversarial review |
| [Frontend Developer](docs/plugins/frontend-developer.md) | 1.2.2 | `frontend-developer` | ✓ | ✓ | `developer` agent and `/develop` command for TypeScript + React: coding standards, TDD, Tailwind, Zustand, TanStack Query and Router, React Hook Form |
| [PHP Developer](docs/plugins/php-developer.md) | 1.0.4 | `php-developer` | ✓ | ✓ | `developer` agent and `/develop` command for PHP: coding standards, TDD, Symfony, Doctrine ORM, DDD |
| [Python Developer](docs/plugins/python-developer.md) | 3.0.5 | `python-developer` | ✓ | ✓ | `developer` agent and `/develop` command for Python: coding standards, TDD, FastAPI, SQLAlchemy, Pydantic, Django, DRF, Celery |
| [QA](docs/plugins/qa.md) | 3.1.0 | `qa` | ✓ | ✓ | `/qa:run` tests your change in the browser, through APIs and stores, and in desktop apps, can fix the issues you approve and retests within fixed limits; reports use `QA-001` IDs |
| [QA Ebitengine](https://github.com/mszenfeld/qa-ebitengine) | 0.1.0 | `qa-ebitengine` | ✓ | ✓ | Desktop driver for QA: lets `/qa:run` test Ebitengine games headless in the background. Requires `qa` |
| [Delivery](docs/plugins/delivery.md) | 0.8.1 | `delivery` | ✓ | ✓ | Runs an approved plan task by task: each task goes to the developer agent that owns its files and is reviewed and committed; then Verification, QA on testable changes and a full code review |
| [Plan Review](docs/plugins/plan-review.md) | 0.2.0 | `plan-review` | — | ✓ | A second model, on the `advisor` role, reviews every plan-mode plan before the approval dialog; the plan cannot be proposed until a review approves it, 3 review rounds are used, or you skip a running review with Esc |
| [Superutils](docs/plugins/superutils.md) | 2.0.0 | `superutils` | ✓ | — | `/superutils:spec-review` runs a bounded triage pipeline on design specs: a lens panel, challengers for criticals and approve-gated fix batches |
| [Simple Language](docs/plugins/simple-language.md) | 1.0.0 | `simple-language` | ✓ | — | Plain-language, scannable replies and documents, active from session start |
| [Sequential Thinking](https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking) | MCP | `sequentialthinking` | ✓ | — | MCP server for structured, step-by-step problem solving |

## Documentation

- [Recommended Workflow](docs/workflow.md)
- [Installation & Optional Tools](docs/installation.md)
- [Oh My Pi (OMP)](docs/oh-my-pi.md)
- [Plugin Guides](docs/plugins/)
- [Contributing](docs/contributing.md)

## Support

- **Bug Reports**: [GitHub Issues](https://github.com/AppVerk/av-marketplace/issues)
- **Feature Requests**: Submit with the `enhancement` label

## License

This project is licensed under the [MIT License](LICENSE).

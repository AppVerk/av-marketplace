# Plan Review Plugin (Oh My Pi only)

Plan Review makes a second model review every plan written in OMP plan mode before it reaches the approval dialog. The agent gets the findings, fixes the plan, and only then proposes it.

## Setup

Install the plugin and map the `advisor` model role in `~/.omp/agent/config.yml`. Pick a model from another family than your `plan` role, so the reviewer does not share the planner's blind spots:

```yaml
modelRoles:
  plan: anthropic/claude-fable-5-1:max
  advisor: openai-codex/gpt-6-astra
```

Without `modelRoles.advisor`, OMP resolves the role through `slow`. The role only picks the reviewer's model; OMP's Advisor runtime stays off unless you enable it (`advisor.enabled`).

## How a plan is reviewed

1. In plan mode the agent writes the plan file, then writes `{"title": "<slug>"}` to `xd://plan_review`.
2. The plugin runs `omp -p` on the `advisor` role with the `read`, `grep` and `glob` tools, without extensions or skills. The reviewer checks the plan against the repository and returns findings marked `blocker`, `concern` or `nit`.
3. Blockers and concerns request changes. The agent resolves each one in the plan file, or states in the plan why it does not apply, and runs the review again. Nits alone approve the plan.
4. Writing the slug to `xd://propose` is blocked until a review approves the current plan text. Any edit after an approving review needs another review.

After 3 review rounds of one plan file, `xd://propose` lets the plan through with a warning, and you decide on the open findings in the approval dialog. If the review cannot run (no `omp` on `PATH`, a reviewer error, an answer that is not the expected JSON, or 15 minutes without an answer), the plugin warns and lets that plan text through unreviewed.

Review state lives in the OMP process: after a restart or `/resume`, the next proposal needs a fresh review.

With Delivery installed, a plan that Delivery's task check rejects still needs a passing review after you fix it, because fixing it changes the plan text.

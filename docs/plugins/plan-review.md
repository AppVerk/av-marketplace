# Plan Review Plugin (Oh My Pi only)

Plan Review makes a second model review every plan written in OMP plan mode before it reaches the approval dialog. The agent gets the findings and fixes the plan until a review finds no blockers; the concerns that review leaves open go to approval in the plan file.

Plan Review is optional. Without it, plan mode proposes a plan directly: no other plugin in this marketplace calls `xd://plan_review` or waits for a review.

## Setup

Install the plugin and map the `advisor` model role in `~/.omp/agent/config.yml`. Pick a model from another family than your `plan` role, so the reviewer does not share the planner's blind spots:

```yaml
modelRoles:
  plan: anthropic/claude-fable-5-1:max
  advisor: openai-codex/gpt-6-astra
```

Without `modelRoles.advisor`, OMP resolves the role through `slow`. The role only picks the reviewer's model; OMP's Advisor runtime stays off unless you enable it (`advisor.enabled`).

OMP loads the plugin's extension when the `omp` process starts. After installing, disabling or uninstalling Plan Review, quit OMP and run `omp` again: `/new`, `/reload-plugins` and the in-session `/plugins` and `/marketplace` commands do not reload extensions, so the running process keeps reviewing plans until it exits.

## How a plan is reviewed

1. In plan mode the agent writes the plan file, then writes `{"title": "<slug>"}` to `xd://plan_review`.
2. The plugin runs `omp -p` on the `advisor` role with the `read`, `grep` and `glob` tools, without extensions or skills. The reviewer checks the plan against the repository and returns findings marked `blocker`, `concern` or `nit`. While it runs, the review shows its round and the elapsed time, updated every 15 seconds.
3. A blocker requests changes: the agent resolves every blocker and concern of that review in the plan file, or states in the plan why one does not apply, and runs the review again. A review without blockers approves the plan; its result reads `approved with open concerns` when it reported concerns, and `approved` when it reported only nits or nothing.
4. The plugin lists the concerns of a review without blockers in a `## Open review findings` section at the end of the plan file, so the approval dialog shows them and you decide on them when you approve. When Delivery runs the approved plan, the implementer and the reviewer of every task receive them as well, and Delivery applies those about the plan's `## Verification` that hold to its checks, or prints them as `manual` checks when they need a project file or a step outside the delivery ([Delivery](delivery.md#plan-review-findings)). The agent proposes the plan without revising it for them. Writing the section needs no new review, and every review removes the previous section before the reviewer reads the plan, so the section always belongs to the latest review. The plugin writes only plan files stored in the session's `local://` directory, where plan mode keeps its plans, and leaves a plan alone if it changed while the reviewer ran; then the agent reviews the current text again, unless that was the last of the 3 rounds. For a plan file stored elsewhere, when writing the section fails, or when the plan changed while the last round's reviewer ran, the agent reports the findings to you instead.
5. Writing the slug to `xd://propose` is blocked until a review finds no blockers in the current plan text. Until the 3 rounds are used, any edit after that review, including an edit of the `## Open review findings` section, needs another review; after them, `xd://propose` lets any text through with a warning.

A review round takes minutes: about 7 minutes (median) in our sessions with `openai-codex/gpt-6-astra`. The reviewer stops after 15 minutes.

Every reviewer run of a plan file is a round, including a run that cannot finish. After 3 rounds of one plan file, `xd://propose` lets the plan through with a warning. When the last round still found blockers, the plugin lists its blockers and concerns in the `## Open review findings` section, and you decide on them in the approval dialog. One plan waits at most 3 × 15 minutes for reviews. If a review cannot run (no `omp` on `PATH`, a reviewer error, an answer that is not the expected JSON, or 15 minutes without an answer), the plugin warns and lets that plan text through unreviewed.

To skip a running review, press Esc. These other interrupts of the running turn skip it the same way: Enter on an empty prompt while messages are queued, leaving plan mode with `/plan`, a collab guest's interrupt, an RPC `abort` or ACP cancel, and another extension's abort. The plugin warns that the plan goes to approval unreviewed; ask the agent to propose it. A skipped review does not use a round, and any edit to the plan after it needs a review again.

Review state lives in the OMP process: after a restart or `/resume`, the next proposal needs a fresh review.

With Delivery installed, a plan that Delivery's task check rejects still needs a review without blockers after you fix it, because fixing it changes the plan text. The `## Open review findings` section does not change that check: it comes after the last task, and a task ends at the next `##` heading.

## Review records

Review records are for contributors who work on Plan Review: they feed its eval and the measurement of its cost. They are off by default. Turn them on in your user file `${XDG_CONFIG_HOME:-~/.config}/av/config.toml`, which applies to every repository:

```toml
version = 1

[plan-review]
records = true
```

`records` is the only key of the `[plan-review]` table: `true` or `false`, `false` by default. A repository's `.av/config.toml` can set it too, and `.av/local.toml` overrides it when one of those files has the table ([override resolution](../configuration.md#files)). The plugin reads the setting at every `xd://plan_review` call through the shared configuration loader, which needs `python3` 3.11 or newer; without it, records stay off. An invalid `[plan-review]` table turns records off with a warning. In every case the review result and the `xd://propose` gate stay as they are.

With records on, every `xd://plan_review` call saves one JSON record in the session's artifacts directory, which is the session file's path without `.jsonl`: `<artifacts directory>/plan-review/<start time>-<8 hex characters>.json`, for example `2026-11-13T09-41-07.123Z-1a2b3c4d.json`. The names sort in start order. The plugin saves the record when the call ends, whatever its result, so a session has one record per call: reviews, reviews that could not run, skipped or cancelled runs, calls after the 3 rounds are used, and calls that failed. Records never go to the repository.

| Field | Content |
|-------|---------|
| `version` | The plugin version; `null` when its `package.json` cannot be read |
| `title` | The title the agent wrote to `xd://plan_review` |
| `url` | The plan file; `null` when no plan file was found |
| `round` | The round of the reviewer run; `null` when no reviewer ran. A skipped run uses no round, so the next run has the same number |
| `startedAt`, `endedAt` | Start and end of the call, ISO 8601 in UTC |
| `outcome` | `approve`, `approve-with-concerns` or `revise` when the reviewer answered; `unavailable` when the review could not run; `skipped` when you interrupted it; `cancelled` for any other abort; `exhausted` when the 3 rounds were used and no reviewer ran; `error` when the call failed, for example without a plan file |
| `reason` | Why the review was `unavailable` or the call ended with `error`; otherwise `null` |
| `reviewer` | The `<provider>/<model>` that answered; `null` without an answer |
| `plan` | `{"text", "sha256"}`: the plan text quoted to the reviewer and its SHA-256. For a plan file in the session's `local://` directory, the text has no `## Open review findings` section. `null` when no reviewer ran. The reviewer received that plugin version's reviewer prompt, then `Plan (<url>):` and the text between `<plan>` tags |
| `answer` | The reviewer's final answer as written, before parsing; `null` without one |
| `findings` | The findings parsed from the answer; `null` when the answer was not the expected JSON |
| `usage` | The `usage` object of every assistant message the reviewer finished, from the `message_end` events of its JSON output, in order and as OMP reports it: one per model turn, turns before a recovery or continuation included. Add them up for the round's tokens and cost. `null` when the output has no finished assistant message |
| `proposeSha256` | The SHA-256 the call stored for the `xd://propose` gate: the hash of the plan text this call reviewed, plus the `## Open review findings` section the plugin wrote after the review. `null` when the call stored no hash: the outcome is `cancelled`, `exhausted` or `error`, or the plugin found the plan changed while the reviewer ran, which it checks only before writing open findings. A non-null hash belongs to the text this call reviewed, not necessarily to the plan file's current text. The gate lets a plan through when its current text has this hash and the outcome is not `revise`; after the 3 rounds it lets any text through |

A record holds the whole plan text and the reviewer's answer, and both can quote the repository's code: share a session's artifacts only where you would share that code. A fork of the session copies its artifacts, records included.

If a record cannot be saved, for example in a session without a session file, the plugin warns; the review result and the `xd://propose` gate stay as they are. The plugin never reads records back: review state still lives in the OMP process.

# Hermes Tweet Plugin

Hermes Agent X/Twitter workflow skill for research, reading, and approval-gated posting through [Hermes Tweet](https://github.com/Xquik-dev/hermes-tweet).

**Version:** 0.1.6

## Skills

### Hermes Tweet

Use this skill when Claude Code needs Hermes Agent support for X/Twitter research, public post or account reading, or a carefully approved public action.

The skill covers three Hermes Tweet tools:

1. `tweet_explore` checks whether Hermes Tweet fits the request and works without credentials.
2. `tweet_read` reads public X/Twitter data when `XQUIK_API_KEY` is configured.
3. `tweet_action` performs approval-gated write actions when `XQUIK_API_KEY` and `HERMES_TWEET_ENABLE_ACTIONS=true` are configured.

## Configuration

Set these variables in the Hermes Tweet runtime environment:

```bash
XQUIK_API_KEY=...
HERMES_TWEET_ENABLE_ACTIONS=true
```

Only set `HERMES_TWEET_ENABLE_ACTIONS=true` when write actions should be available. The skill requires an explicit user approval step before calling `tweet_action`.

## Usage

```text
Use Hermes Tweet to find recent X posts about our release.
Use Hermes Tweet to summarize this account before I draft a reply.
Use Hermes Tweet to prepare a post, show me the exact payload, and wait for approval.
```

## Safety

- Do not reveal API keys or environment values.
- Do not post, reply, like, follow, or delete without explicit approval for the exact payload.
- Do not retry writes after an authorization or policy error unless the user asks after reviewing the error.
- Do not use the skill for bulk engagement, spam, evasion, hidden scraping, or private data access.

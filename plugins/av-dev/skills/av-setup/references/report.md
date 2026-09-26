# av-setup final report

Up to 20 lines in the reply. The full list of changes goes to `<paths.reports>/YYYY-MM-DD-av-setup.md`.

```markdown
<Verdict in 1 line: e.g. "Setup ready: 14 files created, 6 updated, 9 to delete after your approval (git rm command below).">

| Area | State |
|---|---|
| Config | `.ai/av.config.json`, quick/full gates |
| Docs | N created, M updated, K TODO markers |
| Overlays | list of 5 files |
| Role skills | e.g. shop-backend, shop-web, shop-tests or "1 role, rules in the overlay" |
| Codex | AGENTS.md -> CLAUDE.md; .agents/skills -> .claude/skills or "no project skills" |
| Setup validation | `check_setup.sh`: ERRORS e WARNINGS w, e.g. "0 / 2 (missing section X)" |
| Docs drift | count from the step 3 audit and how many were fixed (`audit --fix`) or "kept in the report" |
| Knowledge loss (ADOPTION) | `adoption_diff.sh`: LOST m, of which k in "Knowledge that gets lost" |
| Quick gate | PASS / FAIL / NOT_RUN with reason |
| Eval review | only with `--eval`: "N/5 defects, F false confirmations" (`references/eval.md`) |

Gaps:
- <e.g. no e2e test command; 12 TODOs in domain/business-rules.md>

Next step:
- <1-3 concrete actions, e.g. "review the av-review overlay", "fill in the TODOs in business-rules.md">
```

Rules:
- Verdict in the first line.
- Numbers and paths in the table, not in prose.
- Do not repeat the content of generated files. Give paths.
- Do not commit. Propose a commit message that follows `git.commitPattern` when the user asks for it.

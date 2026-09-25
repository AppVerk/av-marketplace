# Integration template: miro

Miro is handled through the browser (Claude in Chrome and the board page's Web SDK), also in a background tab. The global av-* skills know nothing about Miro. The knowledge reaches the repo from this directory.

Manifest: `template.json`. General template rules: `references/doc-set.md`, section "Integrations".

## When

- The repo, docs or user point to Miro: `miro.com/app/board/` URLs in docs, a Miro MCP server, an answer in the interview.
- Config: `integrations.miro = {"via": "browser", "boards": {"<name>": "https://miro.com/app/board/<id>/"}}`. `via` is always `browser`, also when the repo has a Miro MCP server. `mcp` only by team decision; then do not copy the template.
- Miro does not go into `integrations.mcp` with `via: "browser"`.
- A person without the Chrome extension sets `via` in `.ai/av.config.json.local`.

## Files

| From the template | To the repo |
|---|---|
| `miro.md` | `<docs.root>/miro.md` |
| `miro-frames.js` | `<paths.scripts>/miro-frames.js` |

Add `fakeNames` from the manifest to the `av-docs-sync.md` overlay, section "Known false names". Overlays link to `<docs.root>/miro.md` and do not list Miro MCP tools.

## Board maintained by the repo

This applies to a repo that maintains a Miro board as documentation (technical debt, screen flows, a description of working with the agent): an entry in `integrations.miro.boards`. The board is not in git, so without these rules it drifts from the repo after a few tasks.

| Where | What to generate |
|---|---|
| docs, debt file (e.g. `known-issues.md`) | section "Miro board": board name from `boards`, badge legend, change log (round, date, what was added, balance) |
| `CLAUDE.md`, critical rules | a change on the board gets a change log entry; a change in the debt file gets a board update |
| `av-docs-sync.md`, code -> docs map | row: change in the debt file -> update of the board frame |
| `av-verify.md`, tool checks | row "Board up to date" and the section "Miro board check" below |
| `av-implement.md`, required steps | board update together with docs, before review and the `full` gate |

Section "Miro board check" in `av-verify.md`:
- a table "board element -> source of truth in the repo"; only elements the repo really feeds (test count from the gate log, balance from the debt file, debt cards, screen badges),
- run: first the update from docs, then a read in the final gates without editing the repo,
- evidence `<paths.runs>/<RUN_ID>/miro-check.md`: element, id on the board, value on the board, value in the repo, `OK` or `DRIFT`,
- PASS only without `DRIFT`; no browser, no Miro session or a read error is NOT_RUN with a reason and NEEDS_HUMAN.

Take board elements, frame ids and the badge legend from the board during setup (read through the browser); do not guess. Empty or unavailable board: sections with `_[TODO: fill in]_` and a gap in the report.

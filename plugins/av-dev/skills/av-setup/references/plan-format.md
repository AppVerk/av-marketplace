# av-setup plan format

One format for NEW, COMPLETION, ADOPTION and REFRESH modes. Add sections marked "(ADOPTION)" only in that mode.

```markdown
# av-setup: <project> (<mode>)

## Verdict
<1-2 sentences: how many files we create, update, keep, convert, delete.>

## Decisions
| File | Action | Target | Source of facts / reason |
|---|---|---|---|

## Config
<key values: quick/full gates, risk, git, models; the full JSON in the "Appendix: config" section at the end of the plan>

## Knowledge moved to overlays (ADOPTION)
| Source (file:line range) | Rules (summary) | Target |

## Knowledge that gets lost (ADOPTION)
<output of `adoption_diff.sh`: TOKENS n LOST m FILTERED f>
<orchestration, handoff formats, statuses; each item with its source and what replaces it. Each LOST token group has a target in "Knowledge moved to overlays" or a row here.>

## Mode mapping (ADOPTION, when the repo had its own modes)
| Old mode | Conditions | New mode | Stricter rules in the overlay |

## Deliberately not moved (ADOPTION)
<rules from the old setup that we do not move because they are outdated or contradict the code; each with evidence>

## Docs drift from code
<audit from step 3 of SKILL.md: total and counts per file; the full list in a working file>
| Docs file | MISSING | NAME after triage | LINEREF | Removed names | Total |
|---|---|---|---|---|---|

<drift that changes plan decisions:>
| file:line | docs say | code says |

<with any certain drift item (definition: `SKILL.md` step 3): an "av-docs-sync audit --fix" step before the overlays, for approval; a separate row in Decisions (rule: `SKILL.md` step 3)>


## Default decisions
<values taken without asking, e.g. with --defaults; each with a reason>

## TODO
<things that cannot be determined from the repo>

## Appendix: config
<the full proposed `.ai/av.config.json` in a json block>
```

## Actions

| Action | Meaning |
|---|---|
| CREATE | new file |
| UPDATE | edit of an existing file; the change scope goes in the "Target" column |
| KEEP | no change |
| CONVERT | content moves to an overlay, the config or docs; the file is deleted afterwards |
| MERGE | merges with another file |
| DROP | deletion without moving content (outdated, duplicated) |
| MOVE | file move (`git mv`) with fixed references; the target path goes in the "Target" column |
| MAP | an existing team file covers a topic from the docs set; we create no new file, the docs `README.md` links to the existing one |

UPDATE also covers "KEEP with a reference fix": the file stays, only the names of removed agents and commands change. Write the change scope in the "Target" column, e.g. "only the Pipeline section" or "only references".

## Level of detail

- Give rule sources as `file:range` per rule group, e.g. `code-reviewer.md:20-58 -> axes 1-4`. No row per rule is needed.
- Group items: "scripts `scripts/*_test.sh` (4 files) KEEP" instead of 4 rows.
- The plan must be readable in 5 minutes. The "Decisions" section usually fits in 40 rows.

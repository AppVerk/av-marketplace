# Localized names

The plugin is written in English. Files generated in a repo (docs, overlays, role skills, plans, reports, learnings) use `project.language` from the config.

Skills and scripts refer to sections, modes and verdict words by their canonical English name. In a repo, the same item may carry its localized name. Both are valid. When a skill says "overlay section X", accept X or its localized name from this table.

Rules:
- `av-setup` writes headers in `project.language`, using this table for the names below.
- Verdict tokens (`READY_FOR_COMMIT`, `NEEDS_HUMAN`, `PLAN_READY`, `APPROVED`, `NEEDS_FIXES`, `PASS`, `FAIL`, `NOT_RUN`, `FRESH`, `STALE`, `DOCS_OK`, `DOCS_DRIFT`) and script codes (`SETUP_*`, `CHECK`, `GATE`) are never translated.
- A language not in the table: use the English name.
- Adding a language: add a column here and the header aliases in `check_setup.sh` and `check_names.sh`.

## Overlay sections

| Overlay | English (canonical) | Polish (pl) |
|---|---|---|
| av-plan | Task source | Źródło zadania |
| av-plan | Files to read before planning | Pliki do przeczytania przed planem |
| av-plan | Required plan sections | Obowiązkowe sekcje planu |
| av-plan | Helper scripts | Pomocnicze skrypty |
| av-implement | Roles | Role |
| av-implement | Required steps | Obowiązkowe kroki |
| av-implement | Mode selection | Wybór trybu |
| av-implement | SMALL mode conditions | Warunki trybu MAŁY |
| av-implement | Review in SMALL mode | Review w trybie MAŁY |
| av-implement | Learnings | Wnioski |
| av-implement | Gates per stage | Bramki per etap |
| av-review | How to check the axes | Jak sprawdzać osie |
| av-review | Additional review checks | Dodatkowe kontrole review |
| av-verify | Gate selection | Dobór bramki |
| av-verify | Environment setup | Przygotowanie środowiska |
| av-verify | Interpreting results | Interpretacja wyników |
| av-verify | Known flaky tests | Znane niestabilne testy |
| av-verify | Tool checks | Kontrole narzędziowe |
| av-docs-sync | Code -> docs map | Mapa kod -> docs |
| av-docs-sync | Numbers to maintain | Liczby do utrzymania |
| av-docs-sync | Out of sync scope | Poza zakresem sync |
| av-docs-sync | Known false names | Znane fałszywe nazwy |

## Role skill sections

| English (canonical) | Polish (pl) |
|---|---|
| File scope | Zakres plików |
| Read first | Czytaj najpierw |
| Patterns | Wzorce |
| Required steps | Obowiązkowe kroki |
| Layer check | Sprawdzenie warstwy |
| Handoff | Przekazanie |
| Pitfalls | Pułapki |

## Plan sections (av-plan)

| English (canonical) | Polish (pl) |
|---|---|
| Verdict | Werdykt |
| Goal and scope | Cel i zakres |
| Acceptance criteria | Kryteria akceptacji |
| Reference pattern | Wzorzec referencyjny |
| Contract | Kontrakt |
| Files | Pliki |
| Order | Kolejność |
| Tests | Testy |
| Validation | Walidacja |
| Docs | Docs |
| Risks | Ryzyka |
| Open questions | Pytania otwarte |

## Setup plan sections (av-setup)

| English (canonical) | Polish (pl) |
|---|---|
| Verdict | Werdykt |
| Decisions | Decyzje |
| Config | Config |
| Knowledge moved to overlays | Wiedza przenoszona do nakładek |
| Knowledge that gets lost | Wiedza, która ginie |
| Mode mapping | Mapowanie trybów |
| Deliberately not moved | Nieprzeniesione celowo |
| Docs drift from code | Rozjazdy docs z kodem |
| Default decisions | Decyzje domyślne |
| Appendix: config | Załącznik: config |
| Actions | Akcje |

## Modes

| English (canonical) | Polish (pl) |
|---|---|
| SMALL, STANDARD, LARGE (av-implement, av-plan) | MAŁY, STANDARD, DUŻY |
| NEW, COMPLETION, ADOPTION, REFRESH (av-setup) | NOWY, UZUPEŁNIENIE, ADOPCJA, ODŚWIEŻENIE |

## Docs sections

| English (canonical) | Polish (pl) |
|---|---|
| Task routing (`CLAUDE.md`) | Routing zadań |
| Working with the agent (`CLAUDE.md`) | Praca z agentem |
| Models (`agents.md`) | Modele |
| Session learnings (`CLAUDE.md`) | Wnioski z sesji |

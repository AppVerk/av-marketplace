# Localized names

The plugin is written in English. Files generated in a repo (docs, overlays, role skills, plans, reports, learnings) use `project.language` from the config.

Skills and scripts refer to sections, modes and verdict words by their canonical English name. In a repo, the same item may carry its localized name. Both are valid. When a skill says "overlay section X", accept X or its localized name from this table.

Rules:
- `av-setup` writes headers in `project.language`, using this table for the names below.
- Verdict tokens (`READY_FOR_COMMIT`, `NEEDS_HUMAN`, `PLAN_READY`, `APPROVED`, `NEEDS_FIXES`, `PASS`, `FAIL`, `NOT_RUN`, `FRESH`, `STALE`, `DOCS_OK`, `DOCS_DRIFT`) and script codes (`SETUP_*`, `CHECK`, `GATE`) are never translated.
- A language not in the table: use the English name.
- Adding a language: add a column here and the header aliases in `check_setup.sh` and `av-docs-sync/scripts/docs_lib.sh`.

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
| av-implement | Docs update | Aktualizacja docs |
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
| av-docs-sync | Excluded docs paths | Wykluczone ścieżki docs |
| av-docs-sync | Known false paths | Znane fałszywe ścieżki |

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

Headers of the files `av-setup` generates from `references/doc-set.md`.

| File | English (canonical) | Polish (pl) |
|---|---|---|
| `CLAUDE.md` | Quick start | Szybki start |
| `CLAUDE.md` | Code map | Mapa kodu |
| `CLAUDE.md` | Task routing | Routing zadań |
| `CLAUDE.md` | Critical rules | Krytyczne zasady |
| `CLAUDE.md` | Working with the agent | Praca z agentem |
| `CLAUDE.md` | Documentation | Dokumentacja |
| `CLAUDE.md` | Git | Git |
| `CLAUDE.md`, learnings file | Session learnings | Wnioski z sesji |
| `code-review.md` | Review rules | Reguły review |
| `code-review.md` | Priorities | Priorytety |
| `code-review.md` | Axes | Osie |
| `code-review.md` | Known false alarms | Znane fałszywe alarmy |
| `code-review.md` | Severity | Ważność |
| `agents.md` | Skills | Skille |
| `agents.md` | Role skills | Skille ról |
| `agents.md` | Models | Modele |
| `agents.md` | Machine requirements | Wymagania na maszynie |
| `agents.md` | Local override | Nadpisanie lokalne |
| module file | Module: {Name} | Moduł: {Nazwa} |
| module file | Files | Pliki |
| module file | Contracts | Kontrakty |
| module file | Dependencies | Zależności |
| module file | Pitfalls | Pułapki |

## Titles and markers

Titles of generated files and fixed text in file headers.

| Where | English (canonical) | Polish (pl) |
|---|---|---|
| overlay title | av-{skill} overlay: {project} | Nakładka av-{skill}: {project} |
| overlay header note | generated by av-setup YYYY-MM-DD; feel free to edit | wygenerowane przez av-setup YYYY-MM-DD; edytuj śmiało |
| `agents.md` title | Working with the agent | Praca z agentem |
| `contracts.md` title | Contracts | Kontrakty |
| `code-review.md` title | Review rules | Reguły review |
| `code-review.md` axis from adoption | Plan compliance | Zgodność z planem |
| integration topic file | Access | Dostęp |
| integration topic file | Usage | Użycie |

## Markers

| English (canonical) | Polish (pl) |
|---|---|
| `_[TODO: fill in]_` | `_[TODO: uzupełnij]_` |
| `_[description to create: av-docs-sync]_` | `_[opis do utworzenia: av-docs-sync]_` |

## Names outside the tables

A header that is not in these tables: translate it once and use the same translation in every file of the repo. Before you write it, check the existing docs of the repo for a header with the same meaning and reuse it.

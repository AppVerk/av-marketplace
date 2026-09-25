# Szablon integracji: miro

Miro obsługiwane przez przeglądarkę (Claude in Chrome i Web SDK strony tablicy), także na karcie w tle. Globalne skille av-* nic o Miro nie wiedzą. Wiedza trafia do repo z tego katalogu.

Manifest: `template.json`. Ogólne zasady szablonów: `references/doc-set.md`, sekcja "Integracje".

## Kiedy

- Repo, docs albo użytkownik wskazują Miro: adresy `miro.com/app/board/` w docs, serwer MCP Miro, odpowiedź w wywiadzie.
- Config: `integrations.miro = {"via": "browser", "boards": {"<nazwa>": "https://miro.com/app/board/<id>/"}}`. `via` zawsze `browser`, także gdy repo ma serwer MCP Miro. `mcp` tylko z decyzji zespołu; wtedy szablonu nie kopiuj.
- Miro nie trafia do `integrations.mcp` przy `via: "browser"`.
- Osoba bez rozszerzenia Chrome ustawia `via` w `.ai/av.config.json.local`.

## Pliki

| Z szablonu | Do repo |
|---|---|
| `miro.md` | `<docs.root>/miro.md` |
| `miro-frames.js` | `<paths.scripts>/miro-frames.js` |

`fakeNames` z manifestu dopisz do nakładki `av-docs-sync.md`, sekcja "Znane fałszywe nazwy". Nakładki linkują do `<docs.root>/miro.md` i nie wymieniają narzędzi MCP Miro.

## Tablica utrzymywana przez repo

Dotyczy repo, które utrzymuje tablicę Miro jako dokumentację (dług techniczny, procesy ekranów, opis pracy z agentem): wpis w `integrations.miro.boards`. Tablica nie jest w gicie, więc bez tych reguł rozjeżdża się z repo po kilku zadaniach.

| Gdzie | Co wygenerować |
|---|---|
| docs, plik długu (np. `known-issues.md`) | sekcja "Tablica Miro": nazwa tablicy z `boards`, słownik plakietek, dziennik zmian (tura, data, co doszło, bilans) |
| `CLAUDE.md`, krytyczne zasady | zmiana na tablicy dostaje wpis w dzienniku; zmiana w pliku długu dostaje aktualizację tablicy |
| `av-docs-sync.md`, mapa kod -> docs | wiersz: zmiana w pliku długu -> aktualizacja ramki tablicy |
| `av-verify.md`, kontrole narzędziowe | wiersz "Tablica aktualna" i sekcja "Kontrola tablicy Miro" niżej |
| `av-implement.md`, obowiązkowe kroki | aktualizacja tablicy razem z docs, przed review i bramką `full` |

Sekcja "Kontrola tablicy Miro" w `av-verify.md`:
- tabela "element tablicy -> źródło prawdy w repo"; tylko elementy, które repo naprawdę zasila (liczba testów z logu bramki, bilans z pliku długu, karty długu, plakietki ekranów),
- przebieg: najpierw aktualizacja z docs, potem odczyt w bramkach końcowych bez edycji repo,
- dowód `<paths.runs>/<RUN_ID>/miro-check.md`: element, id na tablicy, wartość na tablicy, wartość w repo, `OK` albo `ROZJAZD`,
- PASS tylko bez `ROZJAZD`; brak przeglądarki, brak sesji Miro albo błąd odczytu to NOT_RUN z powodem i NEEDS_HUMAN.

Elementy tablicy, id ramek i słownik plakietek bierz z tablicy przy setupie (odczyt przez przeglądarkę), nie zgaduj. Tablica pusta albo niedostępna: sekcje z `_[TODO: uzupełnij]_` i luka w raporcie.

# Zestaw dokumentacji

Ten plik opisuje, jakie dokumenty tworzy `av-setup` i skąd bierze do nich fakty. Profil stacku z `references/stacks/` dodaje pliki specyficzne.

## Zasady nadrzędne

1. **Fakty tylko z kodu.** Każda ścieżka, klasa, metoda, komenda i liczba musi istnieć w repo. Gdy czegoś nie da się ustalić, wpisz `_[TODO: uzupełnij]_`. Zmyślona reguła szkodzi bardziej niż brak reguły, bo agent ją wykona.
2. **Jeden właściciel tematu.** Każdy temat ma jeden plik. Gdzie indziej wolno dać tylko link i jedno zdanie. Kopie zawsze się rozjeżdżają.
3. **Nie numeruj reguł, do których ktoś będzie się odwoływał.** Numeracja przesuwa się przy każdym dopisaniu. Linkuj do sekcji.
4. **Nie nadpisuj istniejących plików.** Brakujące tworzysz. Zmiany w istniejących idą tylko przez zatwierdzony plan (tryb adopcji albo odświeżenia).
5. **Nie kopiuj reguł z innego projektu.** Szablony dają kształt, treść pochodzi z tego repo.
6. **Krótko.** Plik wejściowy do około 150 linii; powyżej 170 przenieś szczegóły do plików tematycznych. Szczegóły w plikach tematycznych, czytanych na żądanie.
7. **Styl.** Język z `project.language`. Krótkie zdania, listy i tabele zamiast gęstej prozy. Bez pauz "—" i półpauz "–". Tylko zwykły myślnik "-".

## Plik wejściowy `CLAUDE.md`

`AGENTS.md` to symlink do `CLAUDE.md`, gdy `codex.enabled`. Kolejność sekcji:

```markdown
# CLAUDE.md

<Jedno zdanie: co to za projekt, stack, dla kogo.> Ten plik to skrót i zasady. Szczegóły są w `<docs.root>/`.

## Szybki start
<3-6 komend z validation.commands i environment: instalacja, uruchomienie, bramka quick.>

## Mapa kodu
<Drzewo katalogów z jednolinijkowym opisem. Tylko katalogi, które istnieją.>

Przepływ: `<warstwa A> -> <warstwa B> -> ...` (gdy architektura ma wyraźny przepływ).

## Routing zadań

| Gdy zadanie dotyczy | Czytaj najpierw | Kluczowe reguły |
|---|---|---|
| <obszar repo> | <prawdziwe ścieżki docs i kodu> | <konwencje wykryte w kodzie albo TODO> |

## Krytyczne zasady
<Tylko nieoczywiste reguły, których złamanie psuje build, dane albo proces. Każda z uzasadnieniem w pół zdania.>

## Praca z agentem
<Które skille av-* do czego. Tabela 5 wierszy. Link do nakładek i do `<docs.root>/agents.md`, sekcja "Modele". Jedno zdanie: sloty ustala `agents.models` w configu, ustawienia jednej osoby idą do `.ai/av.config.json.local`.>

## Dokumentacja
<Tabela: plik | opis. Wszystkie pliki z docs.root.>

## Git
<Gałęzie, wzorzec nazwy gałęzi i commita, commit tylko na prośbę, bez push, bez podpisu AI.>

## Wnioski z sesji
Na początku sesji przeczytaj `<paths.learnings>`, jeśli istnieje.
```

**Routing zadań** to najważniejsza sekcja. Jeden wiersz na istotny obszar: moduł domenowy, warstwa, UI, testy, CI, tłumaczenia. `Czytaj najpierw` zawiera prawdziwe ścieżki. `Kluczowe reguły` zawierają konwencje zaobserwowane w kodzie, np. "nowy endpoint = metoda w `NovolApi*.swift` + model w `Response/`".

## Rdzeń `<docs.root>/`

| Plik | Właściciel tematu | Źródło faktów |
|---|---|---|
| `README.md` | indeks docs, tabela właścicieli tematów | lista wygenerowanych plików |
| `architecture.md` | warstwy, przepływ, DI, granice modułów | struktura katalogów, importy, rejestracje DI |
| `coding-standards.md` | nazewnictwo, sekcje, lokalizacja, komentarze | 3-5 reprezentatywnych plików, linter config |
| `commands.md` | build, testy, lint, uruchomienie, logi | `validation.commands`, skrypty, CI |
| `environment.md` | wymagane narzędzia, wersje, docker, symulator | lockfile, `.tool-versions`, compose, README |
| `configuration.md` | pliki konfiguracyjne i co wolno w nich zmieniać | pliki config, env bez wartości |
| `tech-stack.md` | zależności z wersjami | lockfile |
| `testing.md` | jak pisać i uruchamiać testy, atrapy, fixtures | katalogi testów, przykładowe testy |
| `agents.md` | praca z agentem: skille av-*, nakładki, skille ról, sloty i modele (bez kopii wartości z configu), wymagania maszyny (Codex CLI, definicje agentów slotów, reguła allow dla `agent.sh`, rozszerzenie przeglądarki przy integracjach), nadpisanie lokalne `.ai/av.config.json.local` | config, `SKILL.md` av-implement "Sloty i dostawcy" |
| `code-review.md` | reguły review repo (czyta `av-review`) | profil stacku + konwencje z kodu |
| `contracts.md` | chronione powierzchnie i co jest zmianą łamiącą | publiczne API, routy, schemat DB, deep linki, eventy |
| `modules/README.md` | indeks modułów | kandydaci ze skanu |
| `modules/_template.md` | szablon opisu modułu | profil stacku |
| `modules/<Moduł>.md` | jeden moduł | kod modułu |
| `domain/glossary.md` | słownik pojęć biznesowych | nazwy klas, enumów, tłumaczeń |
| `domain/business-rules.md` | reguły biznesowe | walidatory, enumy statusów, testy |
| `code-templates/` | szablony per warstwa | najlepiej zbudowany moduł referencyjny |
| `<paths.learnings>` | wnioski z sesji (gitignored) | plik z nagłówkiem, wzór poniżej |
| `<paths.workspace>/README.md` | układ katalogu roboczego (reszta gitignored) | stały tekst |

Pliki z profilu stacku (np. `networking.md`, `php-rules.md`, `frontend.md`) dochodzą do tej tabeli.

Gdy repo używa `docs/` z własnym układem (np. `docs/standards/`), nie duplikuj. Zmapuj istniejące pliki na tematy z tabeli. Twórz tylko brakujące tematy, w konwencji nazw zespołu.

## `code-review.md`

Jedyny właściciel osi review i checklist. Nakładka `av-review.md` tylko do niego linkuje i dodaje narzędzia.

```markdown
# Reguły review

## Priorytety
1. Poprawność i regresje.
2. Bezpieczeństwo (link do sekcji profilu).
3. Kontrakty z `contracts.md`.
4. Konwencje repo.

## Osie
| Oś | Co sprawdzić | Typowy błąd w tym repo |
|---|---|---|

## Znane fałszywe alarmy
<Rzeczy, które wyglądają na błąd, ale są celowe. Np. polski tekst w en.json to placeholder.>

## Ważność
BLOCKER / HIGH / MEDIUM / LOW / INFO z definicjami.
```

## `contracts.md`

Inwentarz faktycznych powierzchni. Dla każdej: gdzie żyje, kto konsumuje, co jest zmianą łamiącą, co trzeba zrobić przy zmianie (wersjonowanie, okres przejściowy, notka migracyjna). Przykłady: endpointy REST konsumowane przez aplikacje mobilne, schemat DB i migracje, deep linki, klucze push, eventy i kolejki, publiczne komendy CLI, formaty plików importu.

## Integracje

Instrukcje narzędzi zewnętrznych i narzędzia stacku żyją w repo, nie w globalnych skillach av-*. Globalnie leżą tylko szablony: `templates/<nazwa>/` z manifestem `template.json` i opisem `README.md`.

Manifest:
- `configKey`: klucz configu, który włącza szablon, np. `integrations.<nazwa>`,
- `applies`: wyrażenie jq na configu; `true` znaczy, że pliki mają być w repo,
- `validate`: wyrażenie jq zwracające opisy błędów pola (walidacja w `check_setup.sh`),
- `files`: plik szablonu -> cel w repo z `{docs.root}` i `{paths.scripts}`,
- `placeholders`: napisy w treści do podmiany na wartości z configu,
- `fakeNames`: nazwy do sekcji "Znane fałszywe nazwy" w nakładce `av-docs-sync.md`.

Zasady:
- Przeczytaj `README.md` szablonu: kiedy go użyć, jak wypełnić config, co dopisać w nakładkach.
- Pliki kopiuj z podmianą `placeholders`. Resztę treści zostaw: to sprawdzone rozwiązanie, nie treść do wymyślania.
- Istniejącego pliku nie nadpisuj. Pokaż diff i zapytaj; z `--defaults` zapisz obok jako `.proposed`.
- Plik docs dostaje wiersz w tabeli "Dokumentacja" w `CLAUDE.md` i w indeksie docs.
- `check_setup.sh` zgłasza `SETUP_INTEGRATION_INVALID` (ERROR) i `SETUP_TEMPLATE_MISSING` (WARNING), gdy `applies` jest prawdą, a pliku brak.
- Problem jednego repo (skrypt dla jego projektu, obejście jego narzędzia) rozwiązuj w tym repo: w `<paths.scripts>`, docs i nakładkach. Nie dopisuj go do szablonu ani profilu stacku.

## Moduły

Szablon modułu weź z profilu stacku. Wspólny szkielet:

```markdown
# Moduł: {Nazwa}

<Jedno zdanie: co robi, w jakim stylu jest napisany (nowy/stary).>

## Pliki
| Warstwa | Plik |

## Kontrakty
<endpointy, routy, eventy>

## Zależności
<inne moduły, serwisy>

## Pułapki
<rzeczy nieoczywiste; tylko potwierdzone w kodzie>
```

Budżet i równoległość opisów modułów opisuje `SKILL.md`, krok 7. Moduły bez pełnego opisu dostają wiersz w `modules/README.md` z adnotacją `_[opis do utworzenia: av-docs-sync]_`.

## Szablony kodu

Wybierz moduł referencyjny: najnowszy styl, komplet warstw, testy. Dla każdej warstwy utwórz `code-templates/<warstwa>.md` z minimalnym, kompletnym przykładem skopiowanym z tego modułu i uproszczonym do nazw zastępczych. Dodaj tabelę w `code-templates.md`: szablon, warstwa, kiedy użyć.

## Plik wniosków

```markdown
# Wnioski z sesji

Czytaj na początku sesji. Dopisuj 1-2 konkretne wnioski po zadaniu, gdy są nowe.

## [YYYY-MM-DD] <temat>
- <wniosek w 1-2 zdaniach, ze ścieżką lub komendą>
```

W ADOPCJI istniejący plik zostaje z własnym formatem.

## `.gitignore`

Docelowo:

```
<paths.workspace>/*
!<paths.workspace>/README.md
.ai/sessions/
.ai/av.config.json.local
```

Wzorzec `<paths.workspace>/` (cały katalog) blokuje wyjątek dla README, bo git nie wchodzi do zignorowanego katalogu. Taki wzorzec zamień na dwie linie powyżej. Skan pokazuje obecne wzorce w `ai_setup.gitignore_ai`.

# Nakładki projektu

Nakładka to plik `<paths.overlays>/<skill>.md`, np. `.ai/overlays/av-review.md`. Rozszerza ogólny skill o reguły tego repo. Ogólny skill czyta ją zaraz po configu.

Nakładki nie są skillami Claude Code. Nie mają frontmatter `name`/`description` i nie pojawiają się na liście skilli. Dzięki temu nie konkurują ze skillami `av-*` o wywołanie.

## Co nakładka może, a czego nie

Może:
- dodać role, obowiązkowe kroki, narzędzia do sprawdzania osi review i pliki do przeczytania (same osie należą do `code-review.md`),
- zawęzić wybór trybu, np. wymusić tryb DUŻY dla zmian w nawigacji,
- wskazać skrypty i project skille do użycia w danym kroku.

Nie może:
- wyłączyć niezależnego review dla zmian wysokiego ryzyka,
- pozwolić na commit, push albo podpis AI wbrew `git` z configu,
- przekierować zapisu poza repo i poza `paths.workspace`,
- dodawać bramek ani dowodów spoza `validation.commands` (dowód PASS/FAIL pochodzi tylko z `gate.sh`),
- osłabić zasad bezpieczeństwa skilla.

Skill pomija regułę nakładki, która łamie te granice, i zgłasza to w raporcie.

## Komenda walidacji a narzędzie pracy

- **Komenda walidacji** sprawdza wynik i daje dowód PASS/FAIL. Żyje w `validation.commands`. Uruchamia ją `gate.sh`.
- **Narzędzie pracy** to skrypt repo używany w trakcie implementacji, np. dodanie pliku do projektu Xcode (`xcodeproj_add.rb`), indeks endpointów (`api_index.sh`), generator kodu. Nakładka może wskazać je jako obowiązkowy krok. Nie daje ono dowodu bramki.

## Wspólny nagłówek

```markdown
<!-- av-overlay: av-review | stack: ios-uikit | wygenerowane przez av-setup YYYY-MM-DD; edytuj śmiało -->
# Nakładka av-review: <projekt>
```

Zespół edytuje nakładki ręcznie. Przy odświeżeniu `av-setup` nie nadpisuje nakładki. Proponuje diff sekcji i pyta.

## `av-plan.md`

```markdown
## Pliki do przeczytania przed planem
<ścieżki; np. indeks endpointów generowany skryptem>

## Obowiązkowe sekcje planu
<np. DATA_CONTRACT: pola odpowiedzi API z typami i opcjonalnością; UI_SCOPE: ekrany, stany, klucze tłumaczeń>

## Pomocnicze skrypty
<np. `scripts/api_index.sh` - indeks sygnatur zamiast ręcznego szukania>

```

Role mają jednego właściciela: `roles` w `.ai/av.config.json` (`references/config-schema.md`). `av-plan` czyta je stamtąd.

## `av-implement.md`

```markdown
## Role
Role, skille ról, kolejność i zakres plików są w `roles` w `.ai/av.config.json`. Pliki generowane są w `generatedPaths`, narzędzia repo w `unownedPaths`. Właściciela pliku podaje `check_setup.sh --owner <plik>` ze skilla `av-setup`.
<opcjonalnie: uwagi do kolejności, np. "ui równolegle z data przy gotowym kontrakcie". Bez kopii globów.>

Co rola oddaje innym, opisuje sekcja "Przekazanie" w jej skillu. Nakładka tego nie powtarza.

## Obowiązkowe kroki
<tylko reguły wspólne dla wszystkich warstw, np. nowy klucz tłumaczenia do 4 plików. Reguły jednej warstwy należą do skilla roli (`references/role-skills.md`).>

## Wybór trybu
<zaostrzenia ponad definicje z av-plan; np. zmiana w Presenter.swift = DUŻY; przy wysokim ryzyku plan obowiązkowy>

## Warunki trybu MAŁY
<dodatkowe warunki wejścia do MAŁY; np. "tylko deterministyczna poprawka jednej funkcji z testem, który wcześniej padał">

## Review w trybie MAŁY
<"tak" albo "nie"; domyślnie "nie">

## Wnioski
<opcjonalnie: format i zasady wpisów do learnings, np. przeniesione ze starego promptu podsumowania sesji>

## Bramki per etap
<kiedy uruchamiać bramki, np. po każdej roli: quick; przed raportem: bramki końcowe. Które bramki, mówi tylko `av-verify.md`, sekcja "Dobór bramki".>
```

## `av-review.md`

Osie i checklisty mają jednego właściciela: `docs.reviewRules` (zwykle `code-review.md`). Nakładka ich nie powtarza. Zawiera tylko to, jak sprawdzać i kto poprawia.

```markdown
## Jak sprawdzać osie
| Oś z code-review.md | Narzędzie (grep, skrypt) |
|---|---|

## Dodatkowe kontrole review
<komendy z validation.commands albo narzędzia, których wynik reviewer czyta; np. `lint_delta` - nowe znaleziska to kandydaci, nie blokery. To nie są nowe bramki.>
```

Właściciela poprawki reviewer ustala skryptem `check_setup.sh --owner <plik>` (role z configu).

## `av-verify.md`

```markdown
## Dobór bramki
| Zmiana | Bramka |
|---|---|
| tylko docs | brak |
| kod bez UI | quick |
| ekran lub nawigacja | full + ui |

## Przygotowanie środowiska
<np. `docker compose up -d`; symulator; konto testowe z ~/.claude/credentials/<projekt>.env>

## Interpretacja wyników
<np. `UNIT_FAILED` z "0 tests" = błąd konfiguracji, nie test czerwony>

## Znane niestabilne testy
<testy z rozpoznaną niestabilnością; każdy z objawem, dowodem i ticketem, jeśli istnieje. Wpis nie zwalnia z kontroli: nierozwiązany FLAKY oznacza NEEDS_HUMAN, także po zielonej powtórce>

## Kontrole narzędziowe
| Kontrola | Kiedy obowiązkowa | Jak (narzędzie, kroki; integracje według docs repo) | Dowód |
|---|---|---|---|
```

## `av-docs-sync.md`

```markdown
## Mapa kod -> docs
| Zmiana w | Aktualizuj |
|---|---|
| `N-Family/ArchitectureBase/Modules/Network/NovolApi/*.swift` | `.ai/networking.md`, moduł |

## Liczby do utrzymania
<np. "8 agentów" w agents.md, liczba modułów w modules/README.md>

## Poza zakresem sync
<pliki pisane ręcznie, których sync nie rusza>

## Znane fałszywe nazwy
<nazwy w backtickach, które `check_names.sh` zgłasza, choć nie są rozjazdem; np. nazwy z innego repo, słowa z przykładów>
- `Nazwa`
- `Prefiks*`
```

## Sekcja "Znane fałszywe nazwy"

`check_names.sh` ze skilla `av-docs-sync` czyta tę sekcję sam. Ścieżka pochodzi z `paths.overlays`. Format: jedna linia na nazwę w backtickach, np. ``- `Nazwa` ``. Gwiazdka na końcu oznacza prefiks, np. ``- `Legacy*` ``. Wpisuj tylko nazwy sprawdzone w kodzie jako fałszywy alarm. Prawdziwy rozjazd poprawiaj w docs, nie dopisuj go tutaj.

## Wymagane sekcje

`check_setup.sh` zgłasza `SETUP_OVERLAY_SECTION`, gdy nakładce brakuje sekcji z tej listy. Nagłówek może mieć dopisek, np. "Pliki generowane i wspólne".

| Nakładka | Sekcje |
|---|---|
| `av-plan.md` | Pliki do przeczytania przed planem; Obowiązkowe sekcje planu |
| `av-implement.md` | Role; Obowiązkowe kroki; Wybór trybu; Bramki per etap |
| `av-review.md` | Jak sprawdzać osie |
| `av-verify.md` | Dobór bramki; Interpretacja wyników |
| `av-docs-sync.md` | Mapa kod -> docs; Znane fałszywe nazwy |

Pusta sekcja jest poprawna. Napisz w niej "brak".

Ten sam skrypt sprawdza treść nakładek i skilli ról:
- ścieżki w backtickach istnieją (`SETUP_REF_MISSING`),
- nazwy w `--gate X` i `--only X` istnieją w `validation` (`SETUP_GATE_UNKNOWN`),
- tabela ról nie kopiuje globów z configu (`SETUP_GLOB_COPY`).

## Skąd brać treść nakładek

1. Profil stacku daje domyślne osie, role i bramki.
2. Skan i lektura kodu dają prawdziwe ścieżki i skrypty.
3. W trybie adopcji najcenniejsze źródło to istniejące pliki agentów, komend i pipeline'u. Przenieś z nich reguły merytoryczne. Pomiń orkiestrację, bo tę robi ogólny skill. Szczegóły w `references/adoption.md`.

Każdą komendę, którą wpisujesz do nakładki (grep, `ls`, skrypt), uruchom raz na repo przed zapisem i sprawdź wynik. Wzorce grep dla osi review sprawdzaj na całym kodzie źródeł, nie na małym diffie: wzorzec musi trafić choć raz w repo albo w celowo przygotowanym przykładzie. Wzorzec bez trafień nigdzie usuń albo oznacz jako niesprawdzony. Komenda, która daje fałszywe trafienia, uczy agenta złych wniosków. Przykład: `ls src/` zwraca też pliki, a `ls -d src/*/` tylko katalogi modułów.

Nakładka ma być krótka: zwykle 30-150 linii. Wiedza, która jest normą dla ludzi (osie review, konwencje, reguły domenowe), należy do docs, a nakładka tylko do niej linkuje. W nakładce zostają rzeczy operacyjne dla skilla: role, kroki obowiązkowe, dobór bramek, narzędzia. Znane fałszywe alarmy review należą do `code-review.md`.

## Werdykt i kontrole wymagane

Generowane nakładki muszą wymagać PASS z aktualnym dowodem dla każdej wymaganej kontroli. NOT_RUN wymaganej kontroli oznacza NEEDS_HUMAN, FAIL blokuje gotowość. Kontrola nieadekwatna do zmiany nie jest wymagana; podaj powód. Opcjonalne komendy mogą mieć SKIPPED według configu. Nie generuj wyjątków zwalniających znane testy FLAKY ani zmiany opcjonalności po porażce. Sam PASS po powtórce bez poprawki przyczyny nie zamyka FLAKY. Reguły te nie wymagają dodatkowych powtórek ani nowych bramek.

## Parametry i ponowne użycie dowodów

Generując nakładkę av-verify i komendy walidacji, wypisz parametry zmieniające zakres lub środowisko (np. suite, runtime, destination). W przykładach przekazuj je jawnie przez `gate.sh --env KLUCZ=WARTOSC`. Nie opieraj selektorów na niewidocznym, odziedziczonym środowisku przy `--reuse-fresh`.

Reuse wymaga zgodności kodu i tożsamości wywołania: definicji komendy, checkoutu, gate.sh i końcowych wartości jawnych parametrów. Zmiana parametrów wymusza wykonanie; identyczne parametry mogą korzystać z dowodu. Zmiana zewnętrznych usług lub toolchainu wymaga wykonania bez reuse. Nie zapisuj sekretów w configu ani przykładach. Nie generuj własnego cache opartego wyłącznie na nazwie komendy i odcisku kodu. Przy starszym gate.sh bez invocationFingerprint nie zalecaj reuse między różnymi parametrami.

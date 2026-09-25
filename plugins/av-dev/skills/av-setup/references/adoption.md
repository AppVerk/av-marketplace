# Tryb adopcji

Adopcja przenosi istniejący ręczny setup (pipeline, agenci, komendy) na skille `av-*` z nakładkami. Wiedza zostaje, znika tylko własna orkiestracja.

Adopcja uruchamia się, gdy skan zwraca `ai_setup.orchestration: true`, a repo nie ma `.ai/av.config.json`. Repo z samymi docs, bez agentów, komend i pipeline'u, idzie trybem UZUPEŁNIENIE, a nie adopcją.

## Zasada

Zachowaj wiedzę, zamień orkiestrację.
- Wiedza to reguły, konwencje, osie review, pułapki, skrypty i progi.
- Orkiestracja to fazy, statusy, przekazywanie między agentami i formaty handoffów. Ogólne skille robią ją same.

**Ostrzejsza reguła wygrywa.** Gdy stary setup był ostrzejszy od domyślnych zachowań `av-*`, zachowaj to jako zaostrzenie w nakładce. Przykład: "przy wysokim ryzyku plan jest obowiązkowy", choć domyślnie plan wymaga dopiero tryb DUŻY. Adopcja nie może po cichu osłabić procesu zespołu.

## Krok 1: Inwentarz

Z wyniku skanu weź `ai_setup`: agenci, komendy, skille, prompty, `pipeline_docs`, `.codex`, `.agents/skills`, `githooks`, `claude_other`, hooki i `enabled_plugins`. Przeczytaj każdy plik. Czytaj sam, dopóki pliki mają razem poniżej około 5000 linii: nakładki potrzebują reguł niemal dosłownie, a przekazanie ich przez subagenta nie oszczędza kontekstu. Powyżej rozdziel lekturę na subagentów. Każdy zapisuje wyciąg reguł z zakresami linii (`plik:od-do`) do pliku w `<tmp>/` i zwraca tylko ścieżkę i spis treści. Czytaj wyciągi wybiórczo.

Znajdź też pliki, które **odwołują się** do orkiestracji:

```bash
grep -rlwE "<nazwy agentów>|<nazwy komend>|<nazwy project skilli>|implementation-pipeline|pipeline_state|orkiestrator|orchestrator|BOUNDED|FULL|SELF_CHECK" \
  --include='*.md' --include='*.html' --include='*.json' --include='*.toml' . | grep -v -e workspace/ -e sessions/
grep -rlnE "[Ff]az[aeiy] [0-9]|[Pp]hase [0-9]" --include='*.md' . | grep -v -e workspace/ -e sessions/
```

Wzorce w cudzysłowach, bo bez nich zsh rozwija `*.md`. `-w` chroni przed trafieniami typu `architect` w słowie "architecture". Nazwy, które są zwykłymi słowami (np. skill `translate`), dają trafienia w kodzie i przykładach. Każde trafienie przejrzyj; to tylko kandydat na UPDATE.

**Sprawdź aktualność reguł**, które przenosisz. Reguła o znanym długu albo znanym fałszywym alarmie mogła się zdezaktualizować (np. dług naprawiony w ostatnich commitach). Sprawdź ją w kodzie. Nieaktualną wpisz do "Nieprzeniesione celowo".

## Krok 2: Klasyfikacja

Akcje z `references/plan-format.md`. Klasyfikuj po treści, nie po nazwie. Agent o nazwie "reviewer" może zawierać reguły implementacji, a skill o nazwie "lint-gate" może być wrapperem pipeline'u.

Typowe mapowanie:

| Artefakt | Akcja | Cel |
|---|---|---|
| dokument pipeline'u (np. `.ai/implementation-pipeline.md`, `docs/pipeline.md`) | CONVERT | tryby i progi -> `av-implement.md`; format findings -> `av-review.md`; bramki -> `validation`; reszta do "Wiedza, która ginie" |
| komenda planu (`feature_plan`, `/architect`) | CONVERT | wymagane sekcje planu -> `av-plan.md` |
| komendy implementacji i wznowienia (`feature_implement`, `feature_continue`) | CONVERT | reguły -> `av-implement.md` |
| komendy docs (`docs_update`, `docs_audit`) | CONVERT | mapa kod->docs, perspektywy audytu -> `av-docs-sync.md` |
| komenda builda (`build`) | CONVERT | komenda -> `validation.commands.build` |
| agent implementujący (`backend-php`, `frontend-designer`, `js-specialist`, `ios-data-layer`, `ios-presentation`, `angular-developer`) | CONVERT | zakres plików -> rola w `roles` w configu; reguły warstwy -> skill roli `.claude/skills/<prefiks>-<rola>/` (`references/role-skills.md`) |
| agent review (`swift-reviewer`, `code-reviewer`, `view-reviewer`, `angular-reviewer`) | CONVERT | osie i checklisty -> `code-review.md`; narzędzia sprawdzania i właściciele -> `av-review.md` |
| agent bezpieczeństwa (`security-reviewer`, `security-auditor`) | CONVERT | reguły -> oś bezpieczeństwa w `code-review.md` |
| agent weryfikujący komendami (`build-verifier`, `test-runner`, `simulator-verifier`, `e2e-test-runner`) | CONVERT | komendy -> `validation`; interpretacja wyników -> `av-verify.md` |
| agent weryfikujący narzędziami MCP (`visual-verifier` z Playwright, porównanie z Figmą) | CONVERT | procedura -> `av-verify.md`, sekcja "Kontrole narzędziowe", z warunkiem, kiedy jest obowiązkowa. Nie da dowodu `gate.sh`, ale `av-implement` musi ją wykonać i zaraportować |
| reguły sprzątania środowiska po nazwie kontenera albo procesu | przenieś z filtrem | tylko z filtrem po katalogu tego checkoutu; inaczej trafiają w cudze środowiska |
| agent akceptacji względem planu (`acceptance-verifier`) | CONVERT | kryteria -> oś "Zgodność z planem" w `code-review.md`; `av-review` sprawdza ją przy `--run` |
| `docs-keeper`, `docs-auditor` | CONVERT | -> `av-docs-sync.md` |
| agent tłumaczeń (`i18n-guardian`) | KEEP albo CONVERT | KEEP, gdy wykonuje pracę (dopisuje klucze w wielu plikach języków, synchronizuje z narzędziem typu Lokalise); CONVERT, gdy tylko sprawdza reguły; wtedy reguły -> `code-review.md` i obowiązkowe kroki |
| agenci narzędziowi (`miro-reader`, `figma-reader`) | KEEP albo UPDATE | nie są częścią pipeline'u; UPDATE, gdy odwołują się do usuniętych agentów, faz albo komend |
| project skille narzędziowe (`translate`, `read-miro`, `writing-tests`, `angular-templates`) | KEEP albo UPDATE | nakładki mogą je wskazywać; UPDATE odwołań jak wyżej |
| project skille-wrappery pipeline'u (odwołują się do RUN_ID, faz, manifestu) | CONVERT | reguły -> nakładka; wrapper DROP albo UPDATE, gdy zawiera też narzędzie |
| prompt podsumowania sesji (`.claude/prompts/post-session-review.md`) | KEEP, gdy używa go hook; w przeciwnym razie CONVERT | -> nakładka `av-implement.md`, sekcja "Wnioski" (czyta ją krok 10 `av-implement`) |
| skrypty pipeline'u (`pipeline_state.py`, `pipeline_check.py`) i ich testy | DROP albo TODO | zastępuje je `gate.sh`; usunięcie wymaga zgody; bez zgody wpisz do TODO |
| skrypty narzędziowe powstałe dla pracy z agentem, poza `paths.scripts` (sprawdź: `git log --diff-filter=A` i brak pliku na `git.baseBranch`) | MOVE | przenieś `git mv` do `paths.scripts`; popraw ustalanie root w skrypcie (`dirname "$0"`, `__file__`, `__dir__`) i wszystkie odwołania w docs, configu, testach, także formy `./scripts/` i `. ./scripts/` (source); po przeniesieniu uruchom bramkę `quick`; skrypty w Pythonie zaproponuj do przepisania na bash (`references/config-schema.md`, pole `paths.scripts`) |
| skrypty narzędziowe (`project_lint.sh`, `verify.sh`, `ui_test.sh`) | KEEP | trafiają do `validation` |
| `.ai/agents.md` albo `docs/agents.md` | UPDATE | opis skilli av-* i nakładek zamiast rosteru agentów |
| docs z odwołaniami do agentów i komend (`README.md`, `feature-checklist.md`, `code-templates.md`, `commands.md`) | UPDATE | podmień nazwy na skille av-*; lista plików z grepa w kroku 1 |
| sekcja pipeline'u w `CLAUDE.md` | UPDATE | -> sekcja "Praca z agentem" |
| reguły krytyczne i styl odpowiedzi w `CLAUDE.md` | KEEP | to decyzje zespołu |
| `.codex/agents/*.toml` | DROP | Codex dostaje skille przez `.agents/skills` |
| `.codex/config.toml`, `.mcp.json`, `settings.json` | KEEP | środowisko i MCP |
| `.agents/skills/*` | MERGE | unikalne skille -> `.claude/skills/`, potem symlink |
| `sessions/learnings.md`, pliki w `workspace/` | KEEP | historia zespołu |
| `workspace/README.md` | UPDATE | opis katalogów `runs/`, `plans/`, `reports/` zamiast faz starego pipeline'u |
| pusty katalog `.claude/skills/` po konwersji | DROP | bez skilli projektu nie ma symlinku `.agents/skills` |
| sekcje docs z linkami przychodzącymi (np. `agents.md#sekcja`) | przenieś, nie usuwaj | przenieś sekcję do pliku-właściciela tematu i popraw linki |
| `docs/onboarding.html` i inne materiały HTML | UPDATE albo TODO | odwołania do starego procesu; duże pliki generowane zostaw jako TODO z komendą regeneracji |

## Mapowanie trybów

Gdy stary pipeline miał własne tryby, rozpisz je w planie (sekcja "Mapowanie trybów"). Typowo:

| Stary | Nowy | Uwagi |
|---|---|---|
| tryb bez reviewera z deterministycznym testem (np. SELF_CHECK) | MAŁY | warunki wejścia starego trybu -> "Warunki trybu MAŁY"; gdy stary tryb pomijał review, w "Review w trybie MAŁY" wpisz "nie" |
| jeden implementer + reviewer (np. BOUNDED) | STANDARD | |
| "pełen pipeline" z jednym implementerem, testami, review bezpieczeństwa i obowiązkowym planem | STANDARD z zaostrzeniami | w "Wybór trybu": plan obowiązkowy, bramka `full` przed raportem, oś bezpieczeństwa zawsze. Nie mapuj na DUŻY, bo DUŻY oznacza kilka ról, a wtedy STANDARD nigdy nie byłby używany |
| "pełen pipeline" z kilkoma rolami (backend, frontend, js, e2e) | DUŻY | STANDARD może wtedy zostać prawie pusty; to poprawne, gdy stary proces nie miał trybu pośredniego. Zapisz to w planie wprost |
| specjaliści równolegle, podział review (np. FULL) | DUŻY | przenieś kryteria wejścia do "Wybór trybu" |
| "wysokie ryzyko wymusza pełny tryb" | zaostrzenie | w `av-implement.md`, sekcja "Wybór trybu": przy wysokim ryzyku plan obowiązkowy (poza domyślnym review, `full` i osią bezpieczeństwa). Nie mapuj na DUŻY, bo DUŻY oznacza kontrakt albo kilka ról |

Gdy docs zespołu podają sprzeczne progi trybów (np. "od 2 warstw" i "od 3 warstw"), weź ostrzejszy i zapisz sprzeczność w "Rozjazdy docs z kodem".

## Krok 3: Plan

Według `references/plan-format.md`. Sekcja "Wiedza, która ginie" jest obowiązkowa. Pozwala zespołowi zaprotestować, zanim coś zniknie.

**Detektor utraty wiedzy.** Porównaj pliki CONVERT i DROP z docs, które zostają:

```bash
bash <katalog-skilla>/scripts/adoption_diff.sh --root <root-repo> \
  --old <pliki CONVERT i DROP> --new CLAUDE.md <katalog-docs> \
  --noise '<nazwy starych agentów i komend, np. swift-reviewer|feature_plan>'
```

- Wynik: `LOST <stary-plik> <token>` dla tokenu w backtickach bez śladu w nowym korpusie. Na końcu `TOKENS n LOST m FILTERED f`.
- Filtr pomija orkiestrację: RUN_ID, CHECK_ID, EVIDENCE, `$ARGUMENTS`, `pipeline_state`, `pipeline_check`, ścieżki `.claude/agents` i `.claude/commands`. `--noise` (ERE) dodaje nazwy starych agentów i komend.
- Każdy `LOST` dostaje w planie miejsce. Reguła merytoryczna (kategoria findings, próg, skrypt, pułapka) idzie do "Wiedza przenoszona do nakładek" z celem. Orkiestracja idzie do "Wiedza, która ginie" z tym, co ją zastępuje.
- Grupuj: jeden wiersz na grupę tokenów, nie na token. Liczby `TOKENS`, `LOST` i `FILTERED` wpisz do planu.

Bez zatwierdzenia (poza `--defaults`) nic nie usuwaj ani nie edytuj. Wolno tylko zapisać plan.

## Krok 4: Wykonanie

Nowe pliki powstają przed usunięciem starych. W każdej chwili repo ma działający setup.

1. `.ai/av.config.json`. Potem `av-docs-sync audit --fix`, gdy plan go zawiera (SKILL.md, krok 3).
2. Nakładki i `code-review.md`.
3. Pozostałe docs: `contracts.md` i inne brakujące tematy.
4. `CLAUDE.md` i pliki z listy UPDATE.
5. Codex według `references/codex.md`.
6. Usunięcia: `git rm` tylko plików, których usunięcie użytkownik wprost zatwierdził. `--defaults` nie jest taką zgodą: bez niej zostaw pliki CONVERT i DROP na miejscu, a w raporcie podaj gotową komendę `git rm` z listą. Historia zostaje w git, więc powrót jest możliwy.

## Krok 5: Kontrola po migracji

- Powtórz grep z kroku 1. Każde trafienie poza `workspace/` i `sessions/` popraw albo zgłoś.
- `check_refs.sh` dla zmienionych docs i nakładek.
- `adoption_diff.sh` ponownie, na nowym setupie. Po usunięciach: `--old-rev HEAD --deleted --new CLAUDE.md <katalog-docs> .claude/skills` z tym samym `--noise`. Przed usunięciami: `--old <pliki CONVERT i DROP>`. `LOST` spoza "Wiedza, która ginie" to luka: dopisz regułę do nakładki albo skilla roli, a gdy się nie da, zgłoś w raporcie.
- `check_setup.sh`: nakładki, role, odwołania i nazwy bramek. `ERROR` popraw przed raportem.
- Bramka `quick` na samym końcu, według SKILL.md, krok 10, punkt 5. Sprawdza, że komendy z configu naprawdę działają.
- Każda grupa reguł z sekcji "Wiedza przenoszona do nakładek" ma miejsce docelowe. Brak miejsca to luka w raporcie.

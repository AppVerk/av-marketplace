# Wywiad

Pytaj tylko o to, czego nie da się wyprowadzić z repo. Każde pytanie ma podpowiedź z wyniku skanu. Użytkownik ją potwierdza albo poprawia. Z `--defaults` pomiń wywiad i użyj wykrytych wartości.

Zadaj pytania jednym narzędziem pytań (np. AskUserQuestion), maksymalnie 4 naraz. Rekomendowaną opcję daj jako pierwszą.

## Runda 1: zawsze

1. **Bramki walidacji.** Pokaż wykryte komendy i proponowany podział na `quick` i `full`. Źródła w kolejności zaufania: CI, skrypty repo, composer/package.json, Makefile. Zapytaj, czy się zgadza.
   - `expect` i `notRunExitCodes` bierz z `commands.scripts_meta` w skanie. `exit_codes_doc` to opis kodów wyjścia z nagłówka skryptu, np. "2 przy niedostępnym środowisku" daje `notRunExitCodes: [2]`. `status_tokens` to napisy statusu drukowane przez skrypt, np. `UNIT_OK` daje `expect`.
   - Token `X_FAILED` bez `X_OK` oznacza zwykle status składany w kodzie (np. `label + '_OK'` w helperze). Potwierdź go lekturą kodu albo uruchomieniem, zanim wpiszesz `expect`.
   - Kod "zero testów" albo "testy pominięte" nie jest brakiem środowiska dla testów jednostkowych. Zostaw go poza `notRunExitCodes`, chyba że skrypt opisuje go jako brak konta lub urządzenia.
   - Zaproponuj komendę `docs` w `quick` (`references/config-schema.md`, sekcja validation).
2. **Git.** Pokaż wykrytą gałąź bazową, wzorzec commita (z historii) i prefiksy ticketów. Domyślnie: commit tylko na prośbę, bez push, bez podpisu AI.
3. **Obszary wysokiego ryzyka.** Zaproponuj listę z profilu stacku i ze skanu (auth, płatności, migracje). Użytkownik dopisuje domenowe.
4. **Język docs.** Domyślnie wykryty z istniejących docs.

## Runda 2: tylko gdy dotyczy

- **Root docs**, gdy repo ma zarówno `docs/`, jak i `.ai/`, albo żadnego. Domyślnie istniejący, a dla nowego repo `.ai`.
- **Moduł referencyjny** do szablonów kodu, gdy kandydatów jest kilku.
- **Codex**, gdy repo ma `AGENTS.md`, `.codex/` albo `.agents/`. Domyślnie tak. Bez tych plików domyślnie też tak, bo koszt to jeden symlink.
- **Podpis AI w commitach**, gdy źródła się różnią. Kolejność pierwszeństwa: reguła zespołu w docs (np. standard commitów, `CLAUDE.md`) > ustawienie `includeCoAuthoredBy` w `.claude/settings.json` > domyślnie `false`. Udział commitów z podpisem (`ai_signature_commits`) to tylko informacja, nie reguła. Z `--defaults` wybierz według tej kolejności i zapisz w "Decyzje domyślne".
- **Ustawienia bezpieczeństwa**, gdy skan znalazł pliki sekretów bez reguł `permissions.deny`. Zaproponuj dopisanie reguł do `.claude/settings.json`. Edycja ustawień wymaga zgody.

## Wartości domyślne bez pytania

- `agents.models`: `plan` i `implement` = `inherit`, `review` = `opus`, `verify` = `haiku`. Gdy użytkownik ma Codex CLI (`command -v codex`), zapytaj o tryb naprzemienny: `crossVendor: true`, `review` i `plan` na Codex, `implement` i `planReview` na Claude (przykład w `config-schema.md`). Domyślnie nie, bo wymaga logowania w obu CLI. Przy "tak" wpisz też `agents.timeoutSec: 3600` (limit slotu CLI). W tym samym pytaniu zapytaj o effort slotów; podpowiedź: `plan` i `planReview` = `high`, `implement` = `high`, `review` = `xhigh`.
  - Model Codex: wartość `model` z `~/.codex/config.toml`, a lista modeli i effortów z `~/.codex/models_cache.json` (`.models[].slug`, `.models[].supported_reasoning_levels[].effort`). Nie przepisuj modelu z przykładu. Effort spoza listy modelu odrzuć w wywiadzie. Brak obu plików: `"model": "inherit"`.
  - Config zespołu ustala tryb dla zespołu. Osoba bez Codex CLI nie zmienia go dla wszystkich: przełącza sloty w `.ai/av.config.json.local` (`config-schema.md`, sekcja "Nadpisanie lokalne"). Setup podaje gotowy przykład w raporcie, ale pliku `.local` nie tworzy.
  - Definicje agentów slotów (`av-slot-<effort>`) są potrzebne, gdy któryś slot `claude` ma effort inny niż `inherit`, także bez trybu naprzemiennego. Instalację obsługuje `SKILL.md`, krok 9.
  - Tryb naprzemienny: powiedz użytkownikowi o regule allow dla `agent.sh` i o prośbach o zgodę (skill `av-implement`, sekcja "Uprawnienia"). Regułę dodaje użytkownik, nie setup. W ADOPCJI weź mocniejszy z dwóch: model z frontmattera konwertowanego agenta albo ten domyślny. Kolejność: `haiku` < `sonnet` < `opus`; `inherit` zostaje, gdy stary agent nie miał jawnego modelu. Sloty: architekt i planista -> `plan`; implementerzy -> `implement`; reviewerzy i bezpieczeństwo -> `review`; weryfikatory -> `verify`.
  - Kilku agentów w jednym slocie: weź model agenta, który wykonywał najtrudniejszą pracę w tym slocie (ocena kodu > diagnoza porażek > uruchamianie komend).
  - `verify` nigdy nie dostaje `opus`: `haiku` dla samego uruchamiania komend, `sonnet`, gdy weryfikator diagnozował porażki (np. analiza testów E2E).
  - `inherit` znaczy "model sesji" i stoi poza skalą. Zostaw `inherit` w slotach `plan` i `implement`, chyba że stary agent miał tam jawny model; wtedy weź jawny.
  - Adopcja nie obniża modelu review.
  - `fable` to dozwolona wartość, ale stoi poza skalą. Wpisuj ją tylko z decyzji użytkownika.
- `agents.independentReview`: `true`.
- `integrations`: z `.mcp.json`, `enabledMcpjsonServers` i nazw serwerów MCP (np. atlassian/jira -> tracker `jira`, figma, bitbucket). Nazwy narzędzi z docs (np. Lokalise) jako dodatkowe pola.
- Integracje z szablonem (`templates/*/README.md`, sekcja "Kiedy"): gdy warunek pasuje do repo albo odpowiedzi użytkownika, wypełnij pole configu według README szablonu.
- `git.baseBranch`: gałąź, do której trafiają pull requesty w historii (`merged_branch_names`, docs o flow). Gdy docs wymieniają kilka gałęzi głównych bez wskazania, weź `develop`, jeśli istnieje. `base_branch_guess` ze skanu to tylko podpowiedź; w klonie lokalnym może być błędna.
- `git.ticketPrefixes`: klucze `git.ticket_prefixes` ze skanu z licznikiem co najmniej 3, uzupełnione o prefiksy z docs. Pojedyncze trafienia to zwykle szum.
- `git.commit`: reguła zespołu z docs; gdy docs są sprzeczne albo milczą, `on-request`, a sprzeczność trafia do raportu.

## Czego nie pytać

- O rzeczy widoczne w kodzie (framework, wersje, układ katalogów).
- O preferencje stylu kodu, które da się odczytać z linterów i istniejącego kodu.
- O sekrety. Nigdy nie proś o tokeny ani hasła. Konto testowe opisz jako wymaganie w `needs`.

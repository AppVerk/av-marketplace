# Profil: PHP / Symfony

## Wykrywanie
- `composer.json` z `symfony/framework-bundle`. Wersję PHP i Symfony weź ze skanu.
- `ddd_layout` ze skanu (`Domain`, `Application`, `Infrastructure`) oznacza DDD/CQRS. Pusty oznacza klasyczny układ `Controller/Service/Entity`.
- `twig: true` i katalog `templates/` oznaczają aplikację z widokami (panel admina). Wtedy dołącz też profil `frontend-node.md`, gdy w repo jest `package.json`.
- `docker-compose*.yml` oznacza, że komendy idą przez kontener.

## Komendy i bramki
- Źródło prawdy to skrypty composera (`analyse`, `test`, `phpstan`, `cs-fix`, `architecture`) i kroki CI.
- Gdy PHP działa w dockerze, poprzedź komendy `docker compose exec -T <serwis_php>`. Nazwę serwisu weź z compose. Na ARM64 sprawdź osobny plik compose.
- **Precheck musi sprawdzać kontenery tego checkoutu.** Nazwa projektu compose pochodzi z nazwy katalogu. Klon albo worktree o tej samej nazwie trafi więc w kontenery innego checkoutu, np. żywego repo. `docker compose ps` tego nie odróżni. Sprawdzaj etykietę katalogu roboczego:
  `docker ps -q --filter "label=com.docker.compose.project.working_dir=$(git rev-parse --show-toplevel)" --filter "label=com.docker.compose.service=<serwis_php>" | grep -q .`
  Użyj `git rev-parse --show-toplevel`, a nie `$PWD`, bo komenda z polem `cwd` działa w podkatalogu. Gdy compose leży w podkatalogu (np. `tests/E2E/`), podaj ten katalog.
  Wtedy komenda w kontenerze działa tylko na kodzie z tego katalogu.
- Stałe `container_name` w compose (np. `projekt-e2e`) sprawiają, że drugi checkout nie postawi własnego stacka. Zapisz to w `needs` i w raporcie.
- Reguły sprzątania kontenerów po nazwie (`docker rm $(docker ps --filter name=...)`) trafiają w kontenery innych checkoutów. Przy adopcji nie przenoś ich do nakładek bez filtra po `working_dir`.
- Gdy compose wymaga pliku env (np. `docker/.env`), dodaj go do precheck: `test -f docker/.env && ...`.
- `needs`: "docker compose up -d" oraz przygotowana baza testowa (`composer setup-test` albo odpowiednik).
- Testy funkcjonalne często czyszczą bazę testową. Nie uruchamiaj ich przeciw bazie dev.
- Typowo: `quick` = analiza statyczna (cs dry-run + phpstan + reguły architektury) + docs, `full` = quick + testy.
- `docs`: komenda z `references/config-schema.md` (`check_refs.sh` i `check_linerefs.sh` z `--strict`). Trwa sekundy i łapie rozjazdy docs z kodem przy każdej zmianie.
- Tylko `docker compose` ze spacją, nie `docker-compose`, gdy repo tak robi.

## Dodatkowe docs
- `php-rules.md`: reguły języka i frameworka (typy, readonly, enumy, atrybuty, serializacja).
- `testing.md`: rodzaje testów, fixtures, baza testowa.
- `api-contracts.md` albo sekcja w `contracts.md`: endpointy konsumowane przez aplikacje mobilne i panele.
- Dla aplikacji z widokami: `frontend.md` (Twig, formularze, assety).

## Moduły
- DDD: `src/<Moduł>/` z warstwami. Szablon: Przeznaczenie, Encje i VO, Endpointy, Command/Query, Eventy i Process Managery, Repozytoria, Zależności międzymodułowe, Świadome odstępstwa, Reguły biznesowe.
- Panel z widokami: moduł = obszar funkcjonalny (kontroler + formularze + widoki). Szablon: Cel, Endpointy API, Routy, Formularze, Widoki, Skrypty TS, Klucze tłumaczeń, Uprawnienia, Pułapki.

## Osie review
| Oś | Co sprawdzić |
|---|---|
| Warstwy i granice | domena bez zależności od infrastruktury; komunikacja między modułami przez kontrakt, nie przez encje innego modułu |
| Doctrine i dane | N+1, `flush` w pętli, migracja zgodna z encją, brak zmian niezwiązanych z zadaniem w migracji |
| Kontrakt API | zmiana pola odpowiedzi = zmiana łamiąca dla aplikacji mobilnych; grupy serializacji nie wystawiają pól wewnętrznych |
| Bezpieczeństwo | autoryzacja po stronie serwera (voter, access control), walidacja wejścia, zapytania z parametrami, brak sekretów w kodzie, OWASP API Top 10 |
| Asynchroniczność | handlery idempotentne, obsługa ponowień, transporty Messengera |
| Testy | test funkcjonalny dla nowego endpointu; regresja dla poprawki |
| Widoki (gdy Twig) | escapowanie, CSRF w formularzach, tłumaczenia, spójność z istniejącymi widokami |

## Role dla av-implement
- API/DDD: `backend` (cały kod PHP) i opcjonalnie `tests` (testy funkcjonalne i unit). Skille `<prefiks>-backend`, `<prefiks>-tests`; `backend` może wskazać też skill z pluginu, np. `phpstorm-plugin:php-project-guide`.
- Panel z widokami: `backend` (kontrolery, formularze, modele, klient API), `twig` (widoki, style, tłumaczenia), `ts` (skrypty TS i build), `e2e` (testy przeglądarkowe). Skille `<prefiks>-backend`, `<prefiks>-twig`, `<prefiks>-ts`, `<prefiks>-e2e`.

## Wysokie ryzyko (domyślne)
Uwierzytelnianie (JWT, klucze), autoryzacja, migracje DB, publiczne odpowiedzi API, płatności i salda punktów, handlery asynchroniczne, integracje zewnętrzne (SAP, push), usuwanie danych.

## Mapa docs-sync
| Zmiana w | Docs |
|---|---|
| kontroler, route | moduł, `contracts.md` |
| encja, migracja | moduł, `architecture.md` przy nowym agregacie |
| `composer.json` | `tech-stack.md` |
| `config/packages/*` | `configuration.md` |
| nowy katalog w `src/` | nowy moduł, `modules/README.md` |

## Defekty do evalu
Zestaw dla `references/eval.md`.
| # | Defekt | Oś |
|---|---|---|
| 1 | nowy endpoint bez kontroli dostępu (brak `IsGranted`, votera albo reguły `access_control`) | Bezpieczeństwo |
| 2 | zapytanie DQL albo SQL sklejane z parametrem żądania zamiast parametru | Bezpieczeństwo |
| 3 | `flush()` w pętli albo zapytanie w pętli (N+1) przy liście encji | Doctrine i dane |
| 4 | pole wewnętrzne encji dodane do grupy serializacji odpowiedzi API | Kontrakt API |
| 5 | handler Messengera, który przy ponowieniu nalicza punkty drugi raz | Asynchroniczność |

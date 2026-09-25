# Profil: Angular

## Wykrywanie
- `angular.json` i `@angular/core` w `package.json`. Wersję weź ze skanu.
- Standalone vs NgModule: `bootstrapApplication` w `main.ts` albo `standalone: true` w komponentach. Od Angular 19 standalone jest domyślny, więc sprawdź też brak `@NgModule`.
- Sygnały: `signal(`, `computed(`, `input(` w kodzie. Stan: `@ngrx/*` albo własne fasady i serwisy.
- Testy: `unit_test` ze skanu (karma/jasmine, jest, vitest). E2E: playwright albo cypress.
- i18n: `@ngx-translate/core`, transloco albo `@angular/localize`. Pliki tłumaczeń zwykle w `src/assets/i18n/*.json`.

## Komendy i bramki
- Źródło prawdy: skrypty `package.json` i kroki CI. Runner z lockfile (`npm run`, `yarn`, `pnpm`).
- Testy tylko w trybie bez watch: szukaj skryptu z `--no-watch` albo `--watch=false` i przeglądarką headless. Skrypt z watch zawiesi bramkę.
- `precheck` dla każdej komendy npm: `test -d node_modules`. Bez niego brak zależności daje FAIL zamiast NOT_RUN.
- `precheck` dla karma: dostępny Chrome lub Chromium (`CHROME_BIN`).
- Typowo: `quick` = lint + prettier check + stylelint (jeśli jest) + docs + testy headless; `full` = quick + build developerski.
- `docs`: komenda z `references/config-schema.md` (`check_refs.sh` i `check_linerefs.sh` z `--strict`). Trwa sekundy i łapie rozjazdy docs z kodem przy każdej zmianie.
- Build produkcyjny zostaw poza bramkami, chyba że CI go wymaga.
- `expect` dla skryptów npm zwykle pomiń. Kod wyjścia `ng lint`, `ng test --no-watch` i `ng build` jest wiarygodny. Napis dodaj tylko, gdy widzisz go w logu CI.
- Hooki husky (`tooling.husky_hooks` w skanie) pokazują, co zespół uważa za bramkę przed commitem. Zwykle to dobry kandydat na `quick`.
- Gdy zespół budował aplikację w trakcie pracy (np. żeby łapać błędy szablonów typu NG8002, których nie widzi lint), zachowaj build w `quick`. To zasada "ostrzejsza reguła wygrywa" z adopcji.

## Docs
Aplikacje Angular często trzymają docs w `docs/` (np. `docs/standards/*.md`, `docs/project-context.md`). Uszanuj ten układ. Ustaw `docs.root: "docs"`. Brakujące tematy dodaj w konwencji zespołu.

Tematy specyficzne:
- `angular-patterns.md`: komponenty, szablony, DTO vs model, serwisy, RxJS, style.
- `architecture.md`: podział na feature'y, lazy loading, fasady, routing.
- `testing.md`: wzorzec testów (np. bez TestBed), mockowanie, fakeAsync.
- `translations.md`: przepływ kluczy, liczba języków, zasady placeholderów, narzędzie typu Lokalise.

## Moduły
Kandydaci: `src/app/*` (feature'y). Pomiń katalogi techniczne (`core`, `shared`, `layout`, `i18n`), ale opisz je w `architecture.md`. Szablon: Cel, Routing, Komponenty, Serwisy i fasady, Modele i DTO, API, Klucze tłumaczeń, Testy, Pułapki.

## Osie review
| Oś | Co sprawdzić |
|---|---|
| Subskrypcje i pamięć | `async` pipe, `takeUntilDestroyed` albo wzorzec projektu; brak ręcznych `subscribe` bez sprzątania |
| Change detection | `OnPush`, sygnały, brak ciężkich funkcji w szablonie, `track` w pętlach |
| Typy | bez `any`, DTO vs model zgodnie z konwencją, strict templates |
| Architektura | podział na feature'y, lazy loading, brak importów w poprzek feature'ów |
| i18n | nowy klucz we wszystkich plikach języków, zgodnie z regułą zespołu |
| Bezpieczeństwo | `innerHTML` i `bypassSecurityTrust*`, tokeny w storage, interceptory i guardy |
| Testy | spec dla nowej logiki; asercje także w `subscribe` |
| Style | tokeny i zmienne SCSS zamiast wartości wpisanych na sztywno |

## Role dla av-implement
Zwykle jedna rola `angular`. Przy dużych zmianach: `feature` (komponenty, serwisy, routing), `i18n` (klucze we wszystkich językach), `tests` (spec). Tłumaczenia jako osobna rola, gdy języków jest dużo. Istniejące skille projektu (np. `angular-templates`, `writing-tests`, `writing-i18n-keys`) wskazuj jako skille ról zamiast tworzyć nowe.

## Wysokie ryzyko (domyślne)
Uwierzytelnianie (interceptory, guardy, przechowywanie tokenów), konfiguracje środowisk, płatności, masowe zmiany plików tłumaczeń, zmiany w `core`/`shared` używanych przez wiele feature'ów.

## Mapa docs-sync
| Zmiana w | Docs |
|---|---|
| nowy katalog w `src/app/` | nowy moduł, indeks modułów |
| routing | `architecture.md`, moduł |
| `package.json` zależności | `tech-stack.md` |
| pliki tłumaczeń (struktura) | `translations.md` |

## Defekty do evalu
Zestaw dla `references/eval.md`.
| # | Defekt | Oś |
|---|---|---|
| 1 | `subscribe` w komponencie bez `takeUntilDestroyed` ani `async` pipe | Subskrypcje i pamięć |
| 2 | `[innerHTML]` z danymi z API albo `bypassSecurityTrustHtml` bez sanitizacji | Bezpieczeństwo |
| 3 | nowy klucz tłumaczenia tylko w jednym pliku języka | i18n |
| 4 | typ `any` w nowym DTO albo serwisie | Typy |
| 5 | import z wnętrza innego feature'a zamiast z jego publicznego API | Architektura |

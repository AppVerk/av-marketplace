# Profile: Angular

## Detection
- `angular.json` and `@angular/core` in `package.json`. Take the version from the scan.
- Standalone vs NgModule: `bootstrapApplication` in `main.ts` or `standalone: true` in components. Since Angular 19 standalone is the default, so also check for the absence of `@NgModule`.
- Signals: `signal(`, `computed(`, `input(` in the code. State: `@ngrx/*` or custom facades and services.
- Tests: `unit_test` from the scan (karma/jasmine, jest, vitest). E2E: playwright or cypress.
- i18n: `@ngx-translate/core`, transloco or `@angular/localize`. Translation files are usually in `src/assets/i18n/*.json`.

## Commands and gates
- Source of truth: `package.json` scripts and CI steps. Runner from the lockfile (`npm run`, `yarn`, `pnpm`).
- Tests only in no-watch mode: look for a script with `--no-watch` or `--watch=false` and a headless browser. A script with watch will hang the gate.
- `precheck` for every npm command: `test -d node_modules`. Without it, missing dependencies give FAIL instead of NOT_RUN.
- `precheck` for karma: Chrome or Chromium available (`CHROME_BIN`).
- Typically: `quick` = lint + prettier check + stylelint (if present) + docs + headless tests; `full` = quick + development build.
- `docs`: the command from `references/config-schema.md` (`check_refs.sh` and `check_linerefs.sh` with `--strict`). It takes seconds and catches docs drift from code on every change.
- Keep the production build out of the gates, unless CI requires it.
- Usually skip `expect` for npm scripts. The exit code of `ng lint`, `ng test --no-watch` and `ng build` is reliable. Add a string only when you see it in the CI log.
- Husky hooks (`tooling.husky_hooks` in the scan) show what the team treats as a pre-commit gate. That is usually a good candidate for `quick`.
- When the team built the app during work (e.g. to catch template errors like NG8002 that lint does not see), keep the build in `quick`. This is the "stricter rule wins" principle from adoption.

## Docs
Angular apps often keep docs in `docs/` (e.g. `docs/standards/*.md`, `docs/project-context.md`). Respect this layout. Set `docs.root: "docs"`. Add missing topics in the team's convention.

Specific topics:
- `angular-patterns.md`: components, templates, DTO vs model, services, RxJS, styles.
- `architecture.md`: split into features, lazy loading, facades, routing.
- `testing.md`: test pattern (e.g. without TestBed), mocking, fakeAsync.
- `translations.md`: key flow, number of languages, placeholder rules, a tool like Lokalise.

## Modules
Candidates: `src/app/*` (features). Skip technical directories (`core`, `shared`, `layout`, `i18n`), but describe them in `architecture.md`. Template: Purpose, Routing, Components, Services and facades, Models and DTOs, API, Translation keys, Tests, Pitfalls.

## Review axes
| Axis | What to check |
|---|---|
| Subscriptions and memory | `async` pipe, `takeUntilDestroyed` or the project pattern; no manual `subscribe` without cleanup |
| Change detection | `OnPush`, signals, no heavy functions in the template, `track` in loops |
| Types | no `any`, DTO vs model per the convention, strict templates |
| Architecture | split into features, lazy loading, no imports across features |
| i18n | new key in all language files, per the team rule |
| Security | `innerHTML` and `bypassSecurityTrust*`, tokens in storage, interceptors and guards |
| Tests | spec for new logic; assertions also inside `subscribe` |
| Styles | tokens and SCSS variables instead of hard-coded values |

## Roles for av-implement
Usually one role `angular`. For large changes: `feature` (components, services, routing), `i18n` (keys in all languages), `tests` (spec). Translations as a separate role when there are many languages. Point to existing project skills (e.g. `angular-templates`, `writing-tests`, `writing-i18n-keys`) as role skills instead of creating new ones.

## High risk (default)
Authentication (interceptors, guards, token storage), environment configs, payments, bulk changes to translation files, changes in `core`/`shared` used by many features.

## Docs-sync map
| Change in | Docs |
|---|---|
| new directory in `src/app/` | new module, module index |
| routing | `architecture.md`, module |
| `package.json` dependencies | `tech-stack.md` |
| translation files (structure) | `translations.md` |

## Eval defects
The set for `references/eval.md`.
| # | Defect | Axis |
|---|---|---|
| 1 | `subscribe` in a component without `takeUntilDestroyed` or `async` pipe | Subscriptions and memory |
| 2 | `[innerHTML]` with API data or `bypassSecurityTrustHtml` without sanitization | Security |
| 3 | new translation key in only one language file | i18n |
| 4 | `any` type in a new DTO or service | Types |
| 5 | import from inside another feature instead of its public API | Architecture |

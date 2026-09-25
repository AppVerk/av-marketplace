# Profile: PHP / Symfony

## Detection
- `composer.json` with `symfony/framework-bundle`. Take the PHP and Symfony versions from the scan.
- `ddd_layout` from the scan (`Domain`, `Application`, `Infrastructure`) means DDD/CQRS. Empty means the classic `Controller/Service/Entity` layout.
- `twig: true` and a `templates/` directory mean an app with views (admin panel). Then also include the `frontend-node.md` profile when the repo has a `package.json`.
- `docker-compose*.yml` means commands run through a container.

## Commands and gates
- The source of truth is composer scripts (`analyse`, `test`, `phpstan`, `cs-fix`, `architecture`) and CI steps.
- When PHP runs in docker, prefix commands with `docker compose exec -T <php_service>`. Take the service name from compose. On ARM64, check for a separate compose file.
- **Precheck must check the containers of this checkout.** The compose project name comes from the directory name. So a clone or worktree with the same name hits the containers of another checkout, e.g. the live repo. `docker compose ps` cannot tell them apart. Check the working directory label:
  `docker ps -q --filter "label=com.docker.compose.project.working_dir=$(git rev-parse --show-toplevel)" --filter "label=com.docker.compose.service=<php_service>" | grep -q .`
  Use `git rev-parse --show-toplevel`, not `$PWD`, because a command with the `cwd` field runs in a subdirectory. When compose lives in a subdirectory (e.g. `tests/E2E/`), give that directory.
  Then the command in the container works only on the code from this directory.
- A fixed `container_name` in compose (e.g. `project-e2e`) keeps a second checkout from starting its own stack. Record it in `needs` and in the report.
- Container cleanup rules by name (`docker rm $(docker ps --filter name=...)`) hit the containers of other checkouts. In adoption, do not move them to overlays without a `working_dir` filter.
- When compose needs an env file (e.g. `docker/.env`), add it to precheck: `test -f docker/.env && ...`.
- `needs`: "docker compose up -d" and a prepared test database (`composer setup-test` or equivalent).
- Functional tests often wipe the test database. Do not run them against the dev database.
- Typically: `quick` = static analysis (cs dry-run + phpstan + architecture rules) + docs, `full` = quick + tests.
- `docs`: the command from `references/config-schema.md` (`check_refs.sh` and `check_linerefs.sh` with `--strict`). It takes seconds and catches docs drift from code on every change.
- Only `docker compose` with a space, not `docker-compose`, when the repo does so.

## Additional docs
- `php-rules.md`: language and framework rules (types, readonly, enums, attributes, serialization).
- `testing.md`: test types, fixtures, test database.
- `api-contracts.md` or a section in `contracts.md`: endpoints consumed by mobile apps and panels.
- For apps with views: `frontend.md` (Twig, forms, assets).

## Modules
- DDD: `src/<Module>/` with layers. Template: Purpose, Entities and VOs, Endpoints, Command/Query, Events and Process Managers, Repositories, Cross-module dependencies, Deliberate deviations, Business rules.
- Panel with views: module = functional area (controller + forms + views). Template: Purpose, API endpoints, Routes, Forms, Views, TS scripts, Translation keys, Permissions, Pitfalls.

## Review axes
| Axis | What to check |
|---|---|
| Layers and boundaries | domain without infrastructure dependencies; communication between modules through a contract, not through another module's entities |
| Doctrine and data | N+1, `flush` in a loop, migration consistent with the entity, no changes unrelated to the task in the migration |
| API contract | a response field change = a breaking change for mobile apps; serialization groups do not expose internal fields |
| Security | server-side authorization (voter, access control), input validation, parameterized queries, no secrets in code, OWASP API Top 10 |
| Asynchrony | idempotent handlers, retry handling, Messenger transports |
| Tests | functional test for a new endpoint; regression test for a fix |
| Views (with Twig) | escaping, CSRF in forms, translations, consistency with existing views |

## Roles for av-implement
- API/DDD: `backend` (all PHP code) and optionally `tests` (functional and unit tests). Skills `<prefix>-backend`, `<prefix>-tests`; `backend` can also point to a plugin skill, e.g. `phpstorm-plugin:php-project-guide`.
- Panel with views: `backend` (controllers, forms, models, API client), `twig` (views, styles, translations), `ts` (TS scripts and build), `e2e` (browser tests). Skills `<prefix>-backend`, `<prefix>-twig`, `<prefix>-ts`, `<prefix>-e2e`.

## High risk (default)
Authentication (JWT, keys), authorization, DB migrations, public API responses, payments and point balances, async handlers, external integrations (SAP, push), data deletion.

## Docs-sync map
| Change in | Docs |
|---|---|
| controller, route | module, `contracts.md` |
| entity, migration | module, `architecture.md` for a new aggregate |
| `composer.json` | `tech-stack.md` |
| `config/packages/*` | `configuration.md` |
| new directory in `src/` | new module, `modules/README.md` |

## Eval defects
The set for `references/eval.md`.
| # | Defect | Axis |
|---|---|---|
| 1 | new endpoint without access control (no `IsGranted`, voter or `access_control` rule) | Security |
| 2 | DQL or SQL query concatenated with a request parameter instead of a bound parameter | Security |
| 3 | `flush()` in a loop or a query in a loop (N+1) over a list of entities | Doctrine and data |
| 4 | internal entity field added to an API response serialization group | API contract |
| 5 | Messenger handler that awards points a second time on retry | Asynchrony |

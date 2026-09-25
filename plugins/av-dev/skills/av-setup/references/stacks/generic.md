# Profile: generic

Use it when no profile fits (Python, Go, Node backend, Android) or as a supplement.

## Commands and gates
Order of source trust:
1. CI steps (`bitbucket-pipelines.yml`, `.github/workflows/*`, `.gitlab-ci.yml`).
2. Scripts in `scripts/`.
3. `package.json` (runner from the lockfile), `composer.json`, `Makefile`.
4. Language conventions: `pyproject.toml` -> `pytest` and the configured linter; `go.mod` -> `go test ./...`, `go vet ./...`; `Cargo.toml` -> `cargo test`, `cargo clippy`; Gradle -> `./gradlew test lint`.

`quick` = fast and without an environment (lint, types, docs, unit). `full` = quick + build + integration tests.
- `docs`: the command from `references/config-schema.md` (`check_refs.sh` and `check_linerefs.sh` with `--strict`). It takes seconds and catches docs drift from code on every change.

## Modules
First- or second-level directories under `src/` (or its equivalent) with at least a few files. Template from the common skeleton in `doc-set.md`.

## Review axes
Correctness, security at trust boundaries, contracts from `contracts.md`, tests for new logic and regressions, repo conventions.

## Roles
One role `developer`, unless the repo layout clearly splits layers.

## High risk
Authentication, authorization, data migrations, public API, payments, concurrency, data deletion.

## Eval defects
The set for `references/eval.md` when the stack profile has none of its own. Add 2 defects from the repo history.
| # | Defect | Axis |
|---|---|---|
| 1 | fake secret hard-coded in the code | Security |
| 2 | user input without validation at a trust boundary | Security |
| 3 | new logic without a test, or a test without assertions | Tests |

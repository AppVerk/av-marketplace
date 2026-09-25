# Profil: ogólny

Użyj, gdy żaden profil nie pasuje (Python, Go, Node backend, Android) albo jako uzupełnienie.

## Komendy i bramki
Kolejność zaufania źródeł:
1. Kroki CI (`bitbucket-pipelines.yml`, `.github/workflows/*`, `.gitlab-ci.yml`).
2. Skrypty w `scripts/`.
3. `package.json` (runner z lockfile), `composer.json`, `Makefile`.
4. Konwencje języka: `pyproject.toml` -> `pytest` i skonfigurowany linter; `go.mod` -> `go test ./...`, `go vet ./...`; `Cargo.toml` -> `cargo test`, `cargo clippy`; Gradle -> `./gradlew test lint`.

`quick` = szybkie i bez środowiska (lint, typy, docs, unit). `full` = quick + build + testy integracyjne.
- `docs`: komenda z `references/config-schema.md` (`check_refs.sh` i `check_linerefs.sh` z `--strict`). Trwa sekundy i łapie rozjazdy docs z kodem przy każdej zmianie.

## Moduły
Katalogi pierwszego lub drugiego poziomu pod `src/` (albo odpowiednikiem) z co najmniej kilkoma plikami. Szablon ze wspólnego szkieletu w `doc-set.md`.

## Osie review
Poprawność, bezpieczeństwo na granicach zaufania, kontrakty z `contracts.md`, testy dla nowej logiki i regresji, konwencje repo.

## Role
Jedna rola `developer`, chyba że układ repo wyraźnie dzieli warstwy.

## Wysokie ryzyko
Uwierzytelnianie, autoryzacja, migracje danych, publiczne API, płatności, współbieżność, usuwanie danych.

## Defekty do evalu
Zestaw dla `references/eval.md`, gdy profil stacku nie ma własnego. Uzupełnij 2 defektami z historii repo.
| # | Defekt | Oś |
|---|---|---|
| 1 | fikcyjny sekret wpisany w kodzie | Bezpieczeństwo |
| 2 | dane wejściowe użytkownika bez walidacji na granicy zaufania | Bezpieczeństwo |
| 3 | nowa logika bez testu albo test bez asercji | Testy |

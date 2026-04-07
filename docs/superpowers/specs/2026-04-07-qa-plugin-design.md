# QA Plugin Design Spec

## Overview

Plugin QA do Claude Code — analizuje zmiany w kodzie, generuje plan testów, wykonuje testy automatycznie (FE via Playwright, BE via API/DB) i tworzy raport z wynikami.

Plugin działa w modelu dwufazowym analogicznym do superpowers (plan → execute): najpierw generuje plan testów jako artefakt Markdown do review, a następnie wykonuje go w tej samej lub osobnej sesji.

## Plugin Structure

```
plugins/qa/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── create-plan.md
│   └── run.md
├── agents/
│   ├── fe-tester.md
│   └── be-tester.md
└── skills/
    ├── test-plan-format/
    │   └── SKILL.md
    ├── fe-testing/
    │   └── SKILL.md
    ├── be-testing/
    │   └── SKILL.md
    └── report-format/
        └── SKILL.md
```

### plugin.json

```json
{
  "name": "qa",
  "description": "Automated QA testing plugin — analyzes code changes, generates test plans, executes FE and BE tests, and produces reports compatible with code-review.",
  "version": "1.0.0"
}
```

## Commands

### `/qa:create-plan`

Analiza zmian i generowanie planu testów.

**Argument:** Opcjonalny, w naturalnym języku. Przykłady:
- `/qa:create-plan` — domyślnie bierze PR z aktualnego brancha
- `/qa:create-plan #123` — diff z PR #123
- `/qa:create-plan feature/xyz` — diff brancha względem main
- `/qa:create-plan ostatnie 10 commitów` — diff z ostatnich 10 commitów
- `/qa:create-plan ten branch` — diff aktualnego brancha względem main
- `/qa:create-plan staged changes` — staged zmiany

**Priorytet rozwiązywania źródła diffa (bez argumentu):**
1. PR — jeśli aktualny branch ma otwarty PR, używa jego diffa
2. Branch — fallback, diff aktualnego brancha względem main/master

**Flow:**
1. Parsowanie argumentu i pobranie diffa
2. Klasyfikacja zmienionych plików na FE/BE na podstawie ścieżek i zawartości (np. `.tsx`/`.vue` → FE, `views.py`/`controllers/` → BE)
3. Identyfikacja zmienionych komponentów: endpointy, modele, migracje, komponenty UI, routy
4. Zbieranie kontekstu — czytanie powiązanych plików (routery, modele, schematy), szukanie dokumentacji w `docs/`, OpenAPI/Swagger, README
5. Wykrycie dostępnych narzędzi testowych — Playwright MCP, narzędzia CLI (curl, httpie), dostęp do DB (psql, sqlite3)
6. Generowanie planu testów (skill: `test-plan-format`) — scenariusze FE/BE, edge cases, oczekiwane wyniki, przypisane narzędzia
7. Zapis planu do `docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md`
8. Propozycja przejścia do `/qa:run` — po zapisaniu planu komenda informuje użytkownika i proponuje uruchomienie testów

### `/qa:run`

Wykonanie planu testów.

**Argument:** Opcjonalny.
- `/qa:run` — szuka najnowszego planu w `docs/testing/plans/`
- `/qa:run docs/testing/plans/2026-04-07-user-auth-test-plan.md` — wykonuje wskazany plan

**Flow:**
1. Wczytanie i parsowanie planu testów
2. Walidacja środowiska — sprawdzenie czy narzędzia wykryte na etapie planu są nadal dostępne
3. Uruchomienie agentów równolegle:
   - `fe-tester` — jeśli plan zawiera scenariusze FE
   - `be-tester` — jeśli plan zawiera scenariusze BE
   - Jeśli zmiany dotyczą tylko jednego typu — uruchamiany jest tylko odpowiedni agent
4. Zbieranie wyników od agentów
5. Generowanie raportu (skill: `report-format`) — w formacie kompatybilnym z code-review
6. Zapis raportu do `docs/testing/reports/YYYY-MM-DD-<topic>-report.md`

## Agents

### `fe-tester`

Agent odpowiedzialny za wykonanie scenariuszy testowych FE.

**Narzędzia:** Playwright MCP (browser_navigate, browser_click, browser_fill_form, browser_snapshot, browser_take_screenshot, itp.)

**Skill:** `fe-testing`

**Odpowiedzialności:**
- Czyta przypisane scenariusze FE z planu testów
- Wykonuje testy UI za pomocą Playwright MCP
- Dla każdego scenariusza: nawigacja, interakcja z elementami, weryfikacja stanu UI
- Robi screenshot przy błędach (zapis do `docs/testing/reports/screenshots/`)
- Zwraca wyniki per scenariusz: pass/fail, logi, screenshoty

### `be-tester`

Agent odpowiedzialny za wykonanie scenariuszy testowych BE.

**Narzędzia:** Bash (curl, httpie, psql, sqlite3 — adaptacyjnie, w zależności od dostępności)

**Skill:** `be-testing`

**Odpowiedzialności:**
- Czyta przypisane scenariusze BE z planu testów
- Testuje API — wysyła requesty, weryfikuje response (status code, body, headers)
- Sprawdza stany w DB — wykonuje query, weryfikuje dane po operacjach
- Testuje error handling — nieprawidłowe dane, brakujące pola, autoryzacja
- Zwraca wyniki per scenariusz: pass/fail, logi, response body przy błędach

## Skills

### `test-plan-format`

Struktura i konwencje planu testów.

**Zawiera:**
- Format pliku Markdown (sekcje: Source, Changes Summary, Detected Tools, FE/BE Test Scenarios)
- Konwencje nazewnictwa scenariuszy: `FE-XX` dla frontend, `BE-XX` dla backend
- Zasady generowania edge cases (granice, puste dane, brak autoryzacji, duplikaty, race conditions)
- Reguły zapisu pliku — ścieżka `docs/testing/plans/`, format nazwy `YYYY-MM-DD-<topic>-test-plan.md`

### `fe-testing`

Wzorce testowania frontendowego z Playwright.

**Zawiera:**
- Jak używać Playwright MCP do nawigacji, interakcji, asercji
- Wzorce weryfikacji stanów UI: widoczność elementów, tekst, formularze, disabled/enabled states
- Strategia screenshotów: robienie przy błędach, zapis do `docs/testing/reports/screenshots/`
- Typowe scenariusze: auth flows, formularze (walidacja, submit, error states), nawigacja, responsywność

### `be-testing`

Wzorce testowania backendowego.

**Zawiera:**
- Testowanie API: budowanie requestów (metoda, headers, body), weryfikacja response (status, body, headers)
- Weryfikacja stanu DB: wzorce query (sprawdzenie rekordu po INSERT, brak rekordu po DELETE, zmiana po UPDATE)
- Testowanie error handling: nieprawidłowy payload → 422, brak autoryzacji → 401/403, duplikat → 409, nieistniejący zasób → 404
- Wykrywanie i adaptacyjne użycie dostępnych narzędzi (curl, httpie, psql, sqlite3, mysql itp.)

### `report-format`

Format raportu z testów kompatybilny z code-review.

**Zawiera:**
- Struktura raportu: Summary (total/pass/fail/skip), Issues Found, Detailed Results
- Format issue ID: `QA-XXX` (np. QA-001, QA-002) — kompatybilny z code-review na potrzeby przyszłej integracji z `/fix`
- Severity levels: HIGH, MEDIUM, LOW
- Format issue: scenariusz źródłowy, expected vs actual, response/screenshot, powiązany plik:linia
- Format detailed results: lista scenariuszy ze statusem pass/fail/skip

## Test Plan Format

```markdown
# Test Plan: <tytuł>

## Source
- Type: PR #123 / branch feature/xyz / last 5 commits
- Base: main
- Date: YYYY-MM-DD

## Changes Summary
Krótki opis co się zmieniło i co wymaga testowania.

## Detected Tools
- Playwright MCP: ✅/❌
- Database access: ✅ (psql) / ❌
- HTTP client: curl / httpie / ❌

## FE Test Scenarios

### FE-01: <nazwa scenariusza>
- **Area:** <komponent/strona>
- **Steps:**
  1. Nawiguj do /page
  2. Kliknij przycisk X
  3. Zweryfikuj że Y jest widoczne
- **Expected:** <oczekiwany rezultat>
- **Edge cases:**
  - Co jeśli użytkownik nie jest zalogowany?
  - Co przy pustych danych?

## BE Test Scenarios

### BE-01: <nazwa scenariusza>
- **Area:** <endpoint/serwis>
- **Method:** POST /api/resource
- **Payload:** `{ "field": "value" }`
- **Expected:** 201, response zawiera ID
- **DB Check:** `SELECT * FROM resources WHERE ...` — nowy rekord istnieje
- **Edge cases:**
  - Brakujące wymagane pole → 422
  - Duplikat → 409
```

## Test Report Format

```markdown
# Test Report: <tytuł>

## Summary
- Total: 12 | ✅ Pass: 9 | ❌ Fail: 2 | ⏭ Skip: 1
- Plan: docs/testing/plans/YYYY-MM-DD-<topic>-test-plan.md
- Date: YYYY-MM-DD

## Issues Found

### QA-001 [HIGH] POST /api/users returns 500 on duplicate email
- **Scenario:** BE-03
- **Expected:** 409 Conflict
- **Actual:** 500 Internal Server Error
- **Response:** `{"error": "Internal server error"}`
- **File:** src/api/users.py:45

### QA-002 [MEDIUM] Login button unresponsive after failed attempt
- **Scenario:** FE-02
- **Expected:** Button re-enables after error toast
- **Actual:** Button stays disabled
- **Screenshot:** docs/testing/reports/screenshots/qa-002.png

## Detailed Results

### ✅ FE-01: Homepage renders correctly
### ✅ BE-01: GET /api/users returns list
### ❌ BE-03: POST /api/users duplicate handling
### ⏭ FE-03: Mobile responsive layout (skipped — Playwright MCP unavailable)
```

## Assumptions

- **Środowisko uruchomione przez użytkownika** — serwer, DB muszą być dostępne przed `/qa:run`
- **Adaptacyjne narzędzia** — plugin wykrywa co jest dostępne (Playwright MCP, curl, psql itp.) i dostosowuje plan/wykonanie
- **Plan jako artefakt** — plan testów jest plikiem Markdown do review, wykonanie w tej samej lub osobnej sesji
- **Kompatybilność z code-review** — format raportu (QA-XXX) przygotowany pod przyszłą integrację z `/fix`
- **Przyszłe iteracje** — integracja z `/fix` do automatycznego naprawiania znalezionych bugów (poza zakresem v1.0.0)

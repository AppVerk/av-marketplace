# Schemat `.ai/av.config.json`

Jeden plik konfiguracji na repozytorium. Czytają go wszystkie skille `av-*`. Plik jest commitowany, bo to ustawienia zespołu, a nie preferencje jednej osoby.

Plik zawsze leży w `.ai/av.config.json`, nawet gdy dokumentacja dla ludzi siedzi w `docs/`. Dzięki temu każdy skill znajduje go bez szukania.

## Nadpisanie lokalne `.ai/av.config.json.local`

Ustawienia jednej osoby albo jednej maszyny idą do `.ai/av.config.json.local`. Plik jest w `.gitignore`. Typowe powody: brak Codex CLI (slot Codex przełączony na Claude), inny symulator w `needs` i `precheck`, dłuższy `timeoutSec` na wolnej maszynie, własna integracja.

Skille i skrypty czytają config efektywny ze skryptu `av-verify/scripts/config.sh`:

```bash
bash <skille>/av-verify/scripts/config.sh --root .            # efektywny JSON
bash <skille>/av-verify/scripts/config.sh --root . --sources  # skąd, które klucze
```

Łączenie:

| W pliku `.local` | Efekt |
|---|---|
| obiekt | łączy się rekurencyjnie z obiektem zespołu |
| tablica | zastępuje całą tablicę zespołu |
| napis, liczba, bool | zastępuje wartość |
| `null` | usuwa klucz z configu efektywnego |

Przykład: osoba bez Codex CLI.

```json
{
  "agents": {
    "crossVendor": false,
    "models": {
      "plan":   {"provider": "claude", "model": "opus", "effort": "high"},
      "review": {"provider": "claude", "model": "opus", "effort": "xhigh"}
    }
  }
}
```

Zasady:
- Walidacja (`gate.sh --list`) sprawdza config efektywny. Błędne nadpisanie daje błąd configu (kod 2), np. `haiku` w `review` albo `crossVendor` bez dwóch dostawców.
- `gate.sh --list` wypisuje `CONFIG_LOCAL` i nadpisane klucze (`OVERRIDE`, `REMOVE`). Bramka wypisuje `CONFIG_LOCAL`. Raport `av-verify` i `av-implement` wymienia nadpisane klucze, bo wynik zależy od maszyny.
- `--no-local` w `config.sh`, `gate.sh` i `check_setup.sh` pomija nadpisanie.
- `av-setup` nigdy nie tworzy ani nie edytuje pliku `.local`. Dopisuje go do `.gitignore`. Przy ODŚWIEŻENIU porównuje skan z configiem zespołu (`--no-local`).
- Komendy z `.local` uruchamiają się bez pytania, tak jak komendy zespołu. Plik pisze właściciel maszyny, nie repo.
- `check_setup.sh` zgłasza `SETUP_LOCAL_TRACKED` (ERROR), gdy plik jest w gicie, i `SETUP_LOCAL_IGNORE` (WARNING), gdy `.gitignore` go nie ignoruje.
- Bez sekretów także w `.local`. Sekrety leżą poza repo.

## Pełny przykład

```json
{
  "version": 1,
  "requires": { "av-dev": ">=0.1.0" },
  "project": {
    "name": "acme-ios",
    "summary": "Natywna aplikacja iOS sklepu Acme (przykład, nie kopiuj wartości).",
    "language": "pl",
    "stacks": ["acme-uikit"],
    "skillPrefix": "acme"
  },
  "docs": {
    "entry": "CLAUDE.md",
    "root": ".ai",
    "index": ".ai/README.md",
    "modules": ".ai/modules",
    "domain": ".ai/domain",
    "reviewRules": ".ai/code-review.md",
    "contracts": ".ai/contracts.md"
  },
  "paths": {
    "overlays": ".ai/overlays",
    "workspace": ".ai/workspace",
    "plans": ".ai/workspace/plans",
    "reports": ".ai/workspace/reports",
    "runs": ".ai/workspace/runs",
    "learnings": ".ai/sessions/learnings.md",
    "scripts": ".ai/scripts"
  },
  "git": {
    "baseBranch": "develop",
    "branchPattern": "{type}/{TICKET}-{slug}",
    "branchTypes": ["feature", "bugfix", "task", "hotfix"],
    "commitPattern": "{TICKET} {imperative sentence in English}",
    "ticketPrefixes": ["ACM"],
    "commit": "on-request",
    "push": "never",
    "aiSignature": false
  },
  "validation": {
    "commands": {
      "lint": { "run": ".ai/scripts/lint.sh", "timeoutSec": 300 },
      "unit": { "run": ".ai/scripts/unit_test.sh", "expect": "UNIT_OK", "timeoutSec": 900 },
      "build": {
        "run": "xcodebuild -workspace Acme.xcworkspace -scheme \"Acme Dev\" -destination \"generic/platform=iOS Simulator\" -configuration Debug build",
        "expect": "BUILD SUCCEEDED",
        "timeoutSec": 1200
      },
      "ui": {
        "run": ".ai/scripts/ui_test.sh \"$UI_SUITE\"",
        "expect": "DEVICE_OK",
        "precheck": "test -n \"$UI_SUITE\" && xcrun simctl list devices available | grep -q iPhone",
        "needs": "symulator, konto testowe, parametr UI_SUITE",
        "notRunExitCodes": [2],
        "covers": ["build"],
        "timeoutSec": 3600
      },
      "docs": {
        "run": "bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_refs.sh\" CLAUDE.md .ai .claude/skills --root . --strict && bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_linerefs.sh\" CLAUDE.md .ai --root . --strict",
        "timeoutSec": 120
      },
      "fixtures": {
        "run": ".ai/scripts/fixtures_check.sh",
        "precheck": "test -d ../acme-api",
        "optional": true
      }
    },
    "gates": {
      "quick": ["lint", "docs", "unit"],
      "full": ["lint", "docs", "unit", "build"]
    }
  },
  "roles": [
    { "name": "data", "skill": "acme-data", "order": 1, "globs": ["Acme/API_/**", "Acme/ArchitectureBase/Modules/Network/**", "Acme/DataProviders/**"] },
    { "name": "ui", "skill": "acme-ui", "order": 1, "globs": ["Acme/Domains/**", "Acme/Presenters/**", "Acme/*.lproj/**"] },
    { "name": "tests", "skill": "acme-tests", "order": 2, "globs": ["AcmeTests/**", "AcmeUITests/**"] }
  ],
  "generatedPaths": ["Pods/**", "Acme.xcodeproj/project.pbxproj"],
  "unownedPaths": [".ai/scripts/**"],
  "risk": {
    "highRiskAreas": ["uwierzytelnianie", "sieć i sesja", "płatności i punkty", "deep linki", "dane osobowe"],
    "highRiskPaths": ["Acme/API_/**", "Acme/ArchitectureBase/Modules/Persistence/**"]
  },
  "agents": {
    "independentReview": true,
    "models": { "plan": "inherit", "implement": "inherit", "review": "opus", "verify": "haiku" }
  },
  "integrations": {
    "tracker": "jira",
    "design": ["miro"],
    "mcp": ["atlassian", "bitbucket"],
    "miro": {"via": "browser", "boards": {"docs": "https://miro.com/app/board/aBcDeFgHiJk=/"}},
    "translations": "lokalise"
  },
  "codex": { "enabled": true }
}
```

## Pola

**requires** (opcjonalne)
- `{"av-dev": ">=X.Y.Z"}`: minimalna wersja skilli av-*. Wersję skilla podaje plik `VERSION` w jego katalogu. Brak pliku oznacza wersję `dev`.
- `gate.sh --list` porównuje wersje. Wersja `dev` daje `WARNING`. Za niska wersja to błąd configu (kod 2).
- `av-setup` wpisuje tu wersję zainstalowanych skilli, gdy ją zna (plik `VERSION` obok skilli). Przy `dev` pole pomija.

**project**
- `language`: język generowanych docs, planów i raportów. Kod i komendy zawsze po angielsku.
- `stacks`: identyfikatory profili z `references/stacks/`. Repo mieszane ma kilka, np. `["php-symfony", "frontend-node"]`.
- `skillPrefix`: prefiks nazw skilli ról, np. `admin` daje `admin-backend`. Domyślnie z nazwy projektu (`composer.json`, `package.json`, adres `origin`), nie z nazwy katalogu: ostatni człon bez prefiksu firmy.

**docs**
- `entry`: plik instrukcji agenta. Zwykle `CLAUDE.md`, a `AGENTS.md` to symlink do niego.
- `root`: katalog dokumentacji dla ludzi i agentów. `.ai` dla nowych repo. `docs` tam, gdzie zespół już go używa.
- `reviewRules`: reguły review repo. Czyta je `av-review`.
- `contracts`: chronione powierzchnie kontraktu (API, schemat DB, deep linki, eventy). Czytają go `av-review` i `av-plan`.

**paths**
- `overlays`: nakładki per skill. Zawsze pod `.ai/`.
- `workspace`: katalog gitignorowany na pliki robocze. `plans`, `reports` i `runs` leżą pod nim.
- `learnings`: wnioski z sesji, gitignorowane.
- `scripts`: narzędzia repo powstałe dla pracy z agentem (bramki, lint, fixtures, indeksy, atrapy). Domyślnie `.ai/scripts`, commitowane. Katalog `scripts/` w root zostaje dla narzędzi zespołu sprzed AI. Język: bash z `jq`, `git`, `awk`, `curl`. Inny język tylko z powodem zapisanym w nagłówku skryptu, np. serwer HTTP (Python) albo edycja `project.pbxproj` gemem `xcodeproj` (Ruby). Testy skryptów w `<scripts>/tests/`.

**git**
- `baseBranch`: gałąź, względem której liczy się diff. `"auto"` oznacza `origin/HEAD`.
- `branchPattern`: wzorzec nazwy gałęzi. `{type}` to jedna z `branchTypes`, `{TICKET}` to ticket z prefiksem z `ticketPrefixes`, `{slug}` to krótki opis kebab-case.
- `commit`: `"on-request"` (domyślnie), `"after-green-gate"` albo `"free"` (swobodnie na gałęzi zadania, nigdy na gałęziach chronionych). Skille nie commitują poza tym, na co pozwala ta wartość. Gdy źródła w repo są sprzeczne, wybierz `"on-request"` i zgłoś sprzeczność w raporcie.
- `push`: `"never"` (domyślnie) albo `"on-request"`. `gate.sh --list` odrzuca inne wartości `commit` i `push`.
- `aiSignature`: `false` oznacza brak `Co-Authored-By` i podpisów AI w commitach.

**validation**
- `commands`: nazwane komendy. Każda ma `run`. Opcjonalne pola:
  - `expect`: napis, który musi paść w wyjściu, np. `BUILD SUCCEEDED`. Chroni przed fałszywym zielonym. Źródła: prawdziwe wyjście komendy (log CI, uruchomienie), kod skryptu repo, który ten napis drukuje, albo stały komunikat narzędzia opisany w profilu stacku (np. `** BUILD SUCCEEDED **` z xcodebuild). Zgadnięty `expect` daje fałszywe FAIL. Gdy żadne źródło go nie potwierdza, pomiń pole; wystarczy kod wyjścia.
  - `precheck`: komenda sprawdzająca środowisko. Gdy padnie, wynik to `NOT_RUN`, a nie `FAIL`. Precheck musi sprawdzać środowisko **tego checkoutu**: zależności w tym katalogu, kontenery z tego katalogu (etykieta `com.docker.compose.project.working_dir`), nie dowolne działające usługi o tej samej nazwie.
  - `needs`: opis wymagań dla człowieka, np. "docker compose up".
  - `timeoutSec`: limit czasu, domyślnie 900.
  - `cwd`: katalog względem root repo.
  - `notRunExitCodes`: kody wyjścia, które skrypt repo zwraca przy braku środowiska (np. 2 = usługa nie działa). Dają `NOT_RUN` zamiast `FAIL`. Ustalaj je per komenda z kodu skryptu. Ten sam kod może znaczyć co innego w różnych komendach: "0 testów" to brak konta (NOT_RUN) dla testów UI, ale błąd konfiguracji (FAIL) dla testów jednostkowych.
  - `optional`: `true` oznacza, że `NOT_RUN` tej komendy nie czyni bramki niekompletną. Wynik to `SKIPPED`.
  - `covers`: lista komend, które ta komenda pokrywa. Przykład: testy UI budują aplikację, więc `ui` pokrywa `build`. W jednej bramce komenda pokryta nie uruchamia się drugi raz.
  - `parallel`: `true` oznacza, że komenda nie dzieli stanu z innymi komendami bramki (nie pisze tam, skąd inne czytają, nie używa tego samego symulatora, bazy ani katalogu builda). Startuje w tle na początku bramki, obok reszty. Wyniki, logi i dowody są te same i idą w kolejności bramki. Typowo: `docs`, `lint`, sprawdzenie fixtures obok testów. Nie ustawiaj dla buildów ani testów na wspólnym urządzeniu. Komenda z `covers` albo pokryta przez inną komendę bramki idzie po kolei mimo flagi. Wartość inna niż `true`/`false` to błąd configu.
- Parametry komend przekazuj zmiennymi środowiska: `"run": "scripts/ui_test.sh \"$UI_SUITE\""`, a wywołanie to `gate.sh --only ui --env UI_SUITE=LoginTests`. Brak parametru wykryj w `precheck`.
- `gates`: nazwane zestawy komend. `quick` po każdej zmianie kodu. `full` przed raportem w trybach STANDARD i DUŻY oraz przy wysokim ryzyku; tryb MAŁY kończy się na `quick`. Można dodać własne, np. `e2e`. Kiedy uruchamiać bramki specjalne, mówi nakładka `av-verify.md`, sekcja "Dobór bramki".
- Komenda nie musi należeć do bramki. Komendy pomocnicze z parametrem, np. `lint_snapshot` i `lint_delta` z `LINT_BASE`, wywołuje się przez `gate.sh --only lint_delta --env LINT_BASE=...`.
- **Katalog skilli w komendach.** `gate.sh` eksportuje do każdej komendy i precheck zmienną `AV_SKILLS_DIR`: katalog, w którym leżą skille av-*. Dzięki temu config nie zawiera ścieżki z `~/.claude`.
- **Komenda `docs`** (zalecana): wykrywa pewne rozjazdy docs z kodem w kilka sekund, także przy zmianach poza `av-implement`. Daj ją do `quick`:
  ```json
  "docs": {"run": "bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_refs.sh\" CLAUDE.md .ai .claude/skills --root . --strict && bash \"$AV_SKILLS_DIR/av-docs-sync/scripts/check_linerefs.sh\" CLAUDE.md .ai --root . --strict", "timeoutSec": 120}
  ```
  `--strict` daje kod 1 tylko przy pewnych rozjazdach: `MISSING` w `check_refs.sh` oraz `LINEREF_RANGE`, `LINEREF_NOFILE`, `LINEREF_GONE` w `check_linerefs.sh`. Ścieżki `CLAUDE.md .ai` zastąp wartościami `docs.entry` i `docs.root`. `.claude/skills` dopisz do `check_refs.sh`, gdy repo ma skille ról: ich ścieżki rozjeżdżają się tak samo jak docs. Bez skilli ról pomiń ten katalog.

Komendy z configu to jedyne komendy, które `av-verify` uruchamia bez pytania. Są zaakceptowane przez zespół, bo leżą w commitowanym pliku.

**roles** (opcjonalne; jedyne źródło zakresu plików ról)
- Lista ról: `name`, `skill`, `order`, `globs`.
  - `name`: nazwa roli, ta sama w planie, nakładce i nazwie skilla.
  - `skill`: skill roli w `.claude/skills/<skill>/SKILL.md`. Skill z pluginu zapisz z dwukropkiem, np. `phpstorm-plugin:php-project-guide`; walidator go nie szuka.
  - `order`: role z tą samą liczbą mogą pracować równolegle. Niższa liczba idzie pierwsza.
  - `globs`: składnia git pathspec `:(glob)`: `*`, `**`, `?`. Bez nawiasów `{a,b}`: każdy wariant to osobny glob. Ścieżka bez gwiazdki obejmuje też zawartość katalogu.
- Globy ról nie mogą się nakładać. Plik bez roli należy do `implementer`, czyli sesji głównej.
- Nakładka `av-implement.md` i skill roli nie kopiują globów. Linkują do `roles` jednym zdaniem.
- Właściciela pliku ustala `check_setup.sh --owner <plik>...` ze skilla `av-setup`. Kolejność: `generatedPaths`, potem `roles` (pierwsza według `order`), potem `unownedPaths`, na końcu `implementer`.
- Repo z jedną rolą może pominąć `roles`. Wtedy każdy plik należy do `implementer`.

**generatedPaths**: globy plików, których żadna rola nie edytuje ręcznie: lockfile, `Pods/**`, wynik builda, `project.pbxproj` zmieniany skryptem.

**unownedPaths**: globy narzędzi repo poza rolami, np. `scripts/**`. Zmiana tylko wtedy, gdy plan ją wymienia.

**risk**
- `highRiskAreas`: obszary opisane słowami. `av-implement` i `av-plan` porównują z nimi zadanie.
- `highRiskPaths`: globy. Zmiana w nich zawsze wymusza niezależny review i oś bezpieczeństwa. Nie wpisuj tu katalogów zmienianych przy prawie każdym zadaniu (np. plików tłumaczeń albo głównego routera). Ryzyko typu "masowa zmiana tłumaczeń" opisz słowami w `highRiskAreas`, np. "zmiana ponad 20 kluczy tłumaczeń naraz".

**agents**
- `independentReview`: `true` oznacza, że review robi świeży subagent bez kontekstu implementacji.
- `models`: sloty `plan`, `planReview`, `implement`, `review`, `verify`. Wartość to napis albo obiekt.
  - Napis: model Claude, `inherit`, `opus`, `sonnet`, `haiku`, `fable` albo pełne id `claude-<id>`. Skrót dla `{"provider": "claude", "model": "<napis>"}`.
  - Obiekt: `{"provider": "claude"|"codex", "model": "...", "effort": "..."}`. Wszystkie pola opcjonalne: `provider` domyślnie `claude`, `model` i `effort` domyślnie `inherit`. Model `codex` to nazwa z Codex CLI, np. `<model-codex>`; `inherit` bierze model z `~/.codex/config.toml`.
  - Effort: `claude` przyjmuje `low`, `medium`, `high`, `xhigh`, `max`; `codex` także `minimal` i `ultra`. Czy dany model Codex obsługuje effort, sprawdza `agent.sh` w `~/.codex/models_cache.json` (ostrzeżenie).
  - `planReview` bez wpisu dziedziczy `review`. Brak slotu to `inherit`.
  - `gate.sh --list` odrzuca inne wartości oraz `haiku` w `review` (kod 2). Nie dawaj `haiku` do review. Tani model potrafi fałszywie potwierdzić poprawność. Do uruchamiania komend z obiektywnym kodem wyjścia wystarcza. Przy adopcji wybierz mocniejszy z dwóch: model z frontmattera starego agenta albo domyślny z tego schematu.
  - Slot Claude wykonuje narzędzie Agent z definicją `av-slot-<effort>` (uprawnienia sesji). Slot Codex wykonuje `av-implement/scripts/agent.sh` przez `codex exec` w sandboksie użytkownika, z prośbą o zgodę przy braku uprawnień. Zasady: skill `av-implement`, sekcje "Sloty i dostawcy" i "Uprawnienia".
- `crossVendor` (opcjonalne, bool): `true` wymaga, żeby `review` miał innego dostawcę niż `implement`, a `planReview` (albo `review`) innego niż `plan`. Modele różnych firm mylą się w różnych miejscach, więc wzajemna kontrola łapie więcej. Przykład naprzemienny:

  ```json
  "agents": {
    "independentReview": true,
    "crossVendor": true,
    "timeoutSec": 3600,
    "models": {
      "plan":       {"provider": "codex",  "model": "<model-codex>", "effort": "high"},
      "planReview": {"provider": "claude", "model": "opus",        "effort": "high"},
      "implement":  {"provider": "claude", "model": "opus",        "effort": "xhigh"},
      "review":     {"provider": "codex",  "model": "<model-codex>", "effort": "xhigh"},
      "verify":     "inherit"
    }
  }
  ```
- `timeoutSec` (opcjonalne): limit jednego slotu w `agent.sh`, domyślnie 3600.

**integrations**: informacja dla skilli, z jakich narzędzi mogą korzystać (tracker, Miro, Figma, system tłumaczeń). Pola są otwarte, zespół może dodać własne. Sekrety nigdy tu nie trafiają.
- Integracja z szablonem w `templates/<nazwa>/` ma kształt pola opisany w `README.md` szablonu. Walidację robi `check_setup.sh` z manifestu szablonu. Przykład wyżej: `miro` (`templates/miro/`).
- `mcp` wymienia serwery MCP, z których skille korzystają.

**codex.enabled**: `true` oznacza, że setup utrzymuje `AGENTS.md` i `.agents/skills` jako symlinki.

## Zasady

- Bez sekretów, tokenów i danych osobowych w configu, także w `.local`.
- Przy odświeżeniu zachowaj wartości ustawione ręcznie. Zmieniaj tylko to, o co prosi użytkownik albo co wykrył skan i użytkownik zatwierdził.
- Nieznane pola zostaw bez zmian. Zespół mógł je dodać dla własnych nakładek.

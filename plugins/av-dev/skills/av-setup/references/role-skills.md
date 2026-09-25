# Skille ról

Skill roli to project skill z wiedzą jednej warstwy repo: backend, widoki, TS, testy E2E, warstwa danych iOS i tak dalej. Leży w `.claude/skills/<prefiks>-<rola>/SKILL.md` i jest commitowany.

## Po co

`av-implement` nie zna warstw. Gdyby reguły wszystkich warstw siedziały w jednej nakładce, każdy agent czytałby całość, choć potrzebuje jednej części. Skill roli rozwiązuje to na 3 sposoby:
- subagent roli w trybie DUŻY ładuje tylko swój skill,
- w trybach MAŁY i STANDARD sesja ładuje tylko skille warstw, których dotyka zmiana,
- skill działa też poza `av-implement`: Claude użyje go sam przy zwykłej pracy nad plikami warstwy, a Codex widzi go przez `.agents/skills`.

## Kiedy tworzyć

- Repo ma co najmniej 2 role w `roles` w configu (np. backend i widoki, warstwa danych i prezentacja): jeden skill na rolę.
- Repo ma 1 rolę: skill roli jest opcjonalny. Tworzysz go, gdy reguły warstwy mają ponad 40 linii. Mniejsze zostają w nakładce.
- Istnieje już dobry skill projektu dla tej warstwy (np. `angular-templates`): nie duplikuj. Rola wskazuje istniejący skill.
- Warstwę pokrywa plugin z marketplace (np. `phpstorm-plugin:php-project-guide`): rola może wskazać jego skill albo agenta. Reguły tego repo, których plugin nie zna, i tak dostają skill roli, tylko krótszy.

## Nazwa

`<prefiks>-<rola>`, np. `admin-backend`, `admin-twig`, `admin-ts`, `admin-e2e`, `ios-data`, `ios-ui`. Prefiks pochodzi z `project.skillPrefix` w configu. Domyślnie bierzesz go z nazwy projektu, a nie z nazwy katalogu (klon albo worktree może mieć inną): najpierw `name` z `composer.json` albo `package.json`, potem nazwa repo z adresu `origin`, potem nazwa głównego pliku projektu, który wykrył profil stacku. Gdy żadne źródło nie istnieje (klon bez `origin`, repo bez manifestu), zapytaj w wywiadzie; z `--defaults` weź nazwę katalogu i zapisz to w "Decyzje domyślne". Z nazwy weź ostatni człon bez prefiksu firmy, np. `nfamily-admin` daje `admin`.

Nazwa roli jest taka sama w configu (`roles[].name`), w planie (`av-plan`, kolumna "Rola") i w nazwie skilla.

## Format

```markdown
---
name: admin-twig
description: Reguły warstwy widoków nfamily-admin (Twig, CSS, menu, tłumaczenia widoczne w Twig). Użyj przy każdej zmianie w katalogu templates, w metronic/src/css/custom/nfamily.css, sekcji menu w config/services.yaml albo kluczy tłumaczeń używanych w Twig, także gdy zadanie tylko wspomina widok, listę, formularz albo modal.
---

# admin-twig: widoki

## Zakres plików
Zakres plików tej roli to rola `twig` w `roles` w `.ai/av.config.json`.
<opcjonalnie: pliki poza zakresem, które rola czyta albo zgłasza innej roli; bez globów z configu>

## Czytaj najpierw
<ścieżki docs, bez przepisywania ich treści>

## Wzorce
| Przypadek | Plik wzorcowy |

## Obowiązkowe kroki
<reguły, których złamanie psuje build, bezpieczeństwo albo spójność; krótko, z powodem w pół zdania>

## Sprawdzenie warstwy
<szybkie komendy na plikach tej warstwy w trakcie pracy, np. phpstan tylko na zmienionych plikach. To pomoc dla roli, nie dowód. Dowodem są wyłącznie bramki z validation.commands, które uruchamia av-verify. Gdy komenda istnieje w configu, podaj jej nazwę (`gate.sh --only <nazwa>`) zamiast ją przepisywać.>

## Przekazanie
- Dostajesz: <od której roli i co, np. tabela route od admin-backend>
- Oddajesz: <komu i co, np. lista data-testid dla admin-ts>

To jedyne miejsce opisu przekazania. Kolejność ról jest w configu (`order`).

## Pułapki
<rzeczy nieoczywiste, potwierdzone w kodzie>
```

Zasady:
- Opis (`description`) wymienia katalogi (nazwy, bez `/**`) i słowa, po których Claude rozpozna warstwę. Globy w opisie liczy `SETUP_GLOB_COPY`. Pisz go szeroko, bo zbyt wąski opis sprawia, że skill się nie uruchamia. Długość do około 300 znaków.
- Treść: 40-150 linii. Wiedza, która jest normą dla ludzi (architektura, konwencje), zostaje w docs; skill tylko do niej linkuje.
- Fakty z kodu, jak w całym setupie. Każdą ścieżkę i komendę sprawdź przed zapisem.
- Skill roli nie orkiestruje. Nie mówi o bramkach całego repo, review ani commitach. To robi `av-implement`.
- Skill nie kopiuje globów roli. Globy żyją tylko w configu. `check_setup.sh` zgłasza kopię 3 lub więcej globów jako `SETUP_GLOB_COPY`.

## Pliki wspólne dla kilku warstw

Jeden plik ma jednego właściciela, czyli jedną rolę. Plik dzielony po treści (np. tłumaczenia z kluczami dla Twig i dla TS, `services.yaml` z menu i serwisami) dostaje rola, która zmienia go najczęściej. Pozostałe role przekazują jej potrzebne wpisy przez kontrakt w planie i sekcję "Przekazanie". Globy ról nie mogą się nakładać. `check_setup.sh` zgłasza nakładanie jako `SETUP_ROLE_OVERLAP`.

Pliki generowane przez build (np. `public/build/**`) nie należą do żadnej roli. Wpisz je do `generatedPaths` w configu. Narzędzia repo (np. `scripts/**`) wpisz do `unownedPaths`.

## Skąd brać treść

1. W ADOPCJI: prompty starych agentów implementujących (`backend-php`, `frontend-designer`, `js-specialist`, `ios-data-layer`, `ios-presentation`, `angular-developer`) oraz fazy pipeline'u, w których pracę robił sam orkiestrator (np. "2.4 E2E"). Reguły merytoryczne przechodzą do skilla roli prawie dosłownie. Orkiestracja (fazy, statusy, formaty handoff) nie przechodzi.
2. Profil stacku, sekcja "Role dla av-implement".
3. Kod: moduł referencyjny i 3-5 plików warstwy.

## Nakładka a skill roli

Mapa ról (nazwa, skill, kolejność, globy) żyje w `roles` w configu. Nakładka `av-implement.md`, sekcja "Role", tylko do niej linkuje.

Reguły wspólne dla wszystkich warstw (np. "nowy klucz tłumaczenia w obu plikach") zostają w nakładce, w "Obowiązkowe kroki". Reguły jednej warstwy idą do skilla roli.

## ODŚWIEŻENIE

Nakładka z regułami warstw wpisanymi bezpośrednio w tabelę ról albo w "Obowiązkowe kroki" to stary format. Zaproponuj wydzielenie ich do skilli ról. Treść przenieś bez zmian merytorycznych.

Tabela ról z globami w nakładce albo sekcja "Zakres plików" z globami w skillu roli to też stary format. Zaproponuj przeniesienie globów do `roles` w configu. Nawiasy `{a,b}` rozpisz na osobne globy. Potem uruchom `check_setup.sh` i popraw `SETUP_ROLE_OVERLAP` oraz `SETUP_ROLE_EMPTY`.

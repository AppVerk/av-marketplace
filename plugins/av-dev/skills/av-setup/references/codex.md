# Claude Code i Codex z jednego źródła

Cel: jedna kopia instrukcji i skilli. Porty ręczne (np. `.codex/agents/*.toml`) rozjeżdżają się z oryginałem po kilku tygodniach.

## Instrukcje

- Źródło: `CLAUDE.md`.
- `AGENTS.md` to symlink: `ln -s CLAUDE.md AGENTS.md`.
- Gdy `AGENTS.md` istnieje jako zwykły plik z inną treścią, nie nadpisuj. Pokaż diff i zapytaj, która wersja jest źródłem. Treść drugiej scal w źródło, potem utwórz symlink.
- Importy w stylu `@docs/plik.md` działają w Claude Code. Codex ich nie rozwija. Gdy `CLAUDE.md` opiera się na importach, dodaj obok zwykły link markdown albo tabelę routingu ze ścieżkami. Wtedy oba narzędzia trafią do pliku.

## Project skille

- Źródło: `.claude/skills/`.
- Codex czyta project skille z `.agents/skills/`. Utwórz symlink katalogu z root repo: `mkdir -p .agents && ln -s ../.claude/skills .agents/skills`. Cel symlinku jest liczony względem `.agents/`, więc `../.claude/skills` jest poprawny.
- Symlink powstaje dopiero wtedy, gdy w `.claude/skills/` są skille do zachowania: skille ról z `av-setup` albo skille KEEP i UPDATE. Gdy wszystkie są CONVERT i czekają na zgodę na usunięcie, nie twórz symlinku, bo Codex dostałby wrappery starego pipeline'u. Utwórz go po usunięciu, jeśli coś zostanie.
- Repo bez `.claude/skills/` nie dostaje symlinku. Wisiałby w próżni. Raport mówi wtedy "Codex: AGENTS.md; skille projektu brak".
- Sprawdź `git check-ignore -q .agents/skills` (skan: `ai_setup.agents_ignored`). Gdy zespół celowo ignoruje `.agents/`, nie twórz symlinku i nie zmieniaj `.gitignore`. Zapisz to w raporcie jako decyzję zespołu.
- Gdy `.agents/skills/` istnieje jako katalog z plikami:
  1. Skille obecne w obu miejscach porównaj. Identyczne usuń z `.agents/skills/`.
  2. Unikalne przenieś do `.claude/skills/`.
  3. Skille-porty komend (np. `source-command-*`) oznacz jako DROP w planie. Ich rolę przejmują skille `av-*`.
  4. Dopiero pusty katalog zamień na symlink.

## Globalne skille av-*

Skille `av-*` żyją poza repo: w `~/.claude/skills/` albo w pluginie `av-dev`. Codex potrzebuje ich osobnej instalacji. Lokalizację skilli użytkownika Codex sprawdź w jego aktualnej dokumentacji. Nie zgaduj ścieżki. W raporcie podaj komendę symlinku, gdy lokalizacja jest znana.

Wykonawca slotu na Codex (`agent.sh`, `provider: codex`) nie potrzebuje tej instalacji. Działa w sandboksie z `~/.codex/config.toml` (domyślnie `workspace-write`); brakujące uprawnienia przyznaje człowiek przez orkiestratora. `agent.sh` podaje mu ścieżkę katalogu skilli w nagłówku promptu, a Codex czyta `SKILL.md` wprost z dysku. Instalacja jest potrzebna tylko wtedy, gdy człowiek uruchamia skille av-* bezpośrednio w Codex.

## Czego nie ruszać

- `.codex/config.toml`: środowisko i serwery MCP dla Codex. Zostaje.
- `.codex/hooks.json`: zostaje. Zgłoś, gdy zawiera ścieżki absolutne z nazwą użytkownika, bo nie zadziała u innych osób.
- `.codex/agents/*.toml`: w adopcji DROP po zatwierdzeniu.

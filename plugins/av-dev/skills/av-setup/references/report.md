# Raport końcowy av-setup

Do 20 linii w odpowiedzi. Pełna lista zmian w `<paths.reports>/YYYY-MM-DD-av-setup.md`.

```markdown
<Werdykt w 1 linii: np. "Setup gotowy: 14 plików utworzonych, 6 zaktualizowanych, 9 do usunięcia po Twojej zgodzie (komenda git rm poniżej).">

| Obszar | Stan |
|---|---|
| Config | `.ai/av.config.json`, bramki quick/full |
| Docs | N utworzonych, M zaktualizowanych, K znaczników TODO |
| Nakładki | lista 5 plików |
| Skille ról | np. admin-backend, admin-twig, admin-ts, admin-e2e albo "1 rola, reguły w nakładce" |
| Codex | AGENTS.md -> CLAUDE.md; .agents/skills -> .claude/skills albo "brak skilli projektu" |
| Walidacja setupu | `check_setup.sh`: ERRORS e WARNINGS w, np. "0 / 2 (brak sekcji X)" |
| Rozjazdy docs | liczba z audytu kroku 3 i ile naprawiono (`audit --fix`) albo "zostają w raporcie" |
| Utrata wiedzy (ADOPCJA) | `adoption_diff.sh`: LOST m, z tego k w "Wiedza, która ginie" |
| Bramka quick | PASS / FAIL / NOT_RUN z powodem |
| Eval review | tylko z `--eval`: "N/5 defektów, F fałszywych potwierdzeń" (`references/eval.md`) |

Luki:
- <np. brak komendy testów e2e; 12 TODO w domain/business-rules.md>

Następny krok:
- <1-3 konkretne akcje, np. "przejrzyj nakładkę av-review", "uzupełnij TODO w business-rules.md">
```

Zasady:
- Werdykt w pierwszej linii.
- Liczby i ścieżki w tabeli, nie w prozie.
- Nie powtarzaj treści wygenerowanych plików. Podaj ścieżki.
- Nie commituj. Zaproponuj komunikat commita zgodny z `git.commitPattern`, gdy użytkownik o to poprosi.

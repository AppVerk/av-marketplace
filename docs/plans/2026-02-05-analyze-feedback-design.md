# Design: `/analyze-feedback` Command

**Data:** 2026-02-05
**Status:** Zatwierdzony

## Przegląd

Command do pobierania komentarzy z Pull Requesta, oceny ich merytoryczności i generowania raportu z gotowymi odpowiedziami.

### Cel

Automatyczna klasyfikacja feedbacku z code review:
- **Zaadresować** - sugestia sensowna, warto wdrożyć
- **Odrzucić** - sugestia bez sensu technicznego/biznesowego, z wygenerowanym draftem odpowiedzi

### Flow użytkownika

```
/analyze-feedback [numer-PR] [--include-conversation]
         ↓
    Pobranie komentarzy z GitHub (gh api)
         ↓
    Zebranie kontekstu (diff, pliki, docs, historia)
         ↓
    Analiza każdego komentarza przez AI
         ↓
    Raport z klasyfikacją i drafami odpowiedzi
         ↓
    "Opublikować odpowiedzi? (wszystkie / wybrane / nie)"
```

## Specyfikacja

### Argumenty

| Argument | Typ | Opis |
|----------|-----|------|
| `pr-number` | opcjonalny | Numer PR. Bez argumentu: detekcja z aktualnego brancha |
| `--include-conversation` | flaga | Włącz analizę ogólnych komentarzy (nie tylko review comments) |

### Źródła danych

| Źródło | Metoda pobrania | Cel |
|--------|-----------------|-----|
| PR diff | `gh pr diff <nr>` | Zrozumienie zmian |
| Review comments | `gh api /repos/{owner}/{repo}/pulls/{nr}/comments` | Lista komentarzy do analizy |
| Conversation comments | `gh api /repos/{owner}/{repo}/issues/{nr}/comments` | Opcjonalnie z flagą |
| Pliki z diff | Read tool na zmienionych plikach | Pełny kontekst kodu |
| Importy/zależności | Glob + Read na importowanych modułach | Zrozumienie architektury |
| Dokumentacja (root) | `README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `CODING_STANDARDS.md` | Standardy projektu |
| Dokumentacja (/docs) | `docs/**/*.md` (jeśli katalog istnieje) | Standardy projektu |
| Historia commitów | `git log --oneline -20 -- <plik>` | Kontekst historyczny zmian |
| Poprzednie PR-y | `gh pr list --state merged --search "<plik>"` | Wcześniejsze decyzje |

### Format raportu

```markdown
## Analiza feedbacku: PR #123 - "Tytuł PR"

**Repozytorium:** owner/repo
**Autor PR:** @username
**Komentarzy przeanalizowanych:** 8 (6 review, 2 conversation)

---

### ✅ Do zaadresowania (5)

#### 1. @reviewer w `src/auth.py:42`
> "Brak walidacji tokena przed użyciem"

**Uzasadnienie:** Słuszna uwaga - token powinien być walidowany przed dekodowaniem. Brak walidacji może prowadzić do błędów runtime.

---

### ❌ Do odrzucenia (3)

#### 1. @reviewer w `src/utils.py:28`
> "Powinieneś użyć klasy zamiast funkcji"

**Uzasadnienie:** Funkcja jest odpowiednia dla tej operacji bezstanowej. Klasa dodałaby niepotrzebną złożoność.

**Draft odpowiedzi:**
> Funkcja jest tu właściwym wyborem - operacja jest bezstanowa i nie wymaga przechowywania kontekstu między wywołaniami. Klasa dodałaby złożoność bez korzyści.

---

### Podsumowanie

| Kategoria | Liczba |
|-----------|--------|
| ✅ Do zaadresowania | 5 |
| ❌ Do odrzucenia | 3 |

**Opublikować odpowiedzi? (wszystkie / wybrane / nie)**
```

### Styl odpowiedzi

Drafty odpowiedzi do odrzuconych komentarzy:
- Zwięzłe: 2-3 zdania
- Bezpośrednie, bez zbędnej kurtuazji
- Techniczne uzasadnienie

### Publikacja na GitHub

**Opcje:**
- `wszystkie` - publikuj wszystkie drafty
- `wybrane` - interaktywny wybór (np. "1,3" lub "1-3")
- `nie` - tylko raport, bez publikacji

**Metoda:** `gh api --method POST /repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`

### Obsługa błędów

| Sytuacja | Zachowanie |
|----------|------------|
| Brak argumentu, branch nie ma PR | Komunikat z prośbą o podanie numeru PR |
| PR nie istnieje | Komunikat o błędzie |
| PR bez komentarzy | Komunikat informacyjny |
| Komentarze tylko od autora PR | Pomiń |
| Komentarz to emoji/reakcja | Pomiń |
| Komentarz resolved | Oznacz jako "(resolved)" |
| Brak autoryzacji `gh` | Instrukcja logowania |
| Rate limit API | Retry z backoff |

## Architektura

### Struktura plików

```
plugins/code-review/
├── commands/
│   └── analyze-feedback.md    # Główny command
└── agents/
    └── feedback-analyzer.md   # Subagent do analizy komentarzy
```

### Podział odpowiedzialności

| Komponent | Rola |
|-----------|------|
| `analyze-feedback.md` | Orkiestracja: pobranie PR, zebranie kontekstu, wywołanie agenta, prezentacja raportu, publikacja |
| `feedback-analyzer.md` | Analiza pojedynczego komentarza: ocena merytoryczności, klasyfikacja, generowanie draftu odpowiedzi |

### Konfiguracja techniczna

**Command (`analyze-feedback.md`):**
```yaml
allowed-tools: Read, Glob, Grep, Bash(gh:*), Bash(git:*), Task
description: Analyze PR feedback comments, classify them, and generate response drafts.
model: claude-opus-4-5
argument-hint: [pr-number] [--include-conversation]
```

**Agent (`feedback-analyzer.md`):**
```yaml
allowed-tools: Read, Glob, Grep, Bash(git:*)
description: Analyze single PR comment for validity and generate response if needed.
model: claude-opus-4-5
```

## Decyzje projektowe

1. **GitHub tylko** - pierwsza wersja wspiera tylko GitHub via `gh` CLI
2. **Review comments domyślnie** - conversation comments opcjonalnie (flaga)
3. **Pełny kontekst** - diff + pliki + docs + historia dla najlepszej jakości analizy
4. **Opus dla obu komponentów** - wysoka jakość analizy merytorycznej
5. **Publikacja opcjonalna** - użytkownik kontroluje co trafia na GitHub

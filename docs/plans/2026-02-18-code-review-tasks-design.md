# Design: Tasks w pluginie code-review

**Data:** 2026-02-18
**Scope:** `/review` + `/fix`
**Podejście:** A — Tasks tylko w commandach (koordynator zarządza)

---

## Kontekst

Plugin `code-review` ma złożone wielokrokowe workflow, ale użytkownik nie widzi postępu wykonania. Dodanie Claude Code Tasks (TaskCreate/TaskUpdate/TaskList) da widoczność na poziomie faz — użytkownik widzi spinner z aktualnym krokiem.

### Co się NIE zmienia

- Agenty (`security-auditor.md`, `code-quality-auditor.md`, `feedback-analyzer.md`) — bez zmian
- Skille — bez zmian
- `analyze-feedback.md` — bez zmian
- Format raportów — bez zmian
- Logika workflow — bez zmian
- Enforcement mechanizmy (MANDATORY, checklisty, Red Flags) — zostają

### Dlaczego Tasks tylko w commandach

Subagenty uruchamiane przez `Task()` z `run_in_background: true` nie mają domyślnie dostępu do TaskCreate/TaskUpdate. Pattern z web-auditor i superpowers potwierdza: koordynator zarządza taskami, subagenty raportują wyniki.

---

## `/review` — struktura tasków

Taski tworzone **wszystkie na starcie** w pierwszej wiadomości (razem z launch subagentów):

| # | Subject | activeForm | Mapowanie na workflow |
|---|---------|------------|---------------------|
| 1 | Launch security & quality auditors | Launching security & quality auditors... | Step 1-2 (launch both Task agents) |
| 2 | Perform performance analysis | Analyzing performance... | Step 3 |
| 3 | Perform architecture & maintainability review | Reviewing architecture & maintainability... | Step 4-5 |
| 4 | Collect subagent results | Collecting subagent results... | Step 6 (TaskOutput × 2) |
| 5 | Generate final report | Generating final report... | Step 7 |

### Zmiany w `review.md`

- Dodać `TaskCreate`, `TaskUpdate`, `TaskList` do `allowed-tools` w frontmatter
- Dodać instrukcje TaskCreate po sekcji "MANDATORY FIRST STEP" — tworzenie wszystkich 5 tasków
- Dodać instrukcje TaskUpdate (status: in_progress/completed) przy przejściu między krokami workflow

---

## `/fix` — struktura tasków

Taski tworzone **wszystkie na starcie** po sparsowaniu issue:

| # | Subject | activeForm | Mapowanie na workflow |
|---|---------|------------|---------------------|
| 1 | Parse issue | Parsing issue... | Phase 1 |
| 2 | Analyze context | Analyzing code context... | Phase 2 |
| 3 | Propose fix | Proposing fix... | Phase 3 (wait for user approval) |
| 4 | Implement fix | Implementing fix... | Phase 4 (after approval) |
| 5 | Verify fix | Verifying fix... | Phase 5-6 (+ auto-iterations) |
| 6 | Generate report | Generating report... | Phase 7 |

### Zmiany w `fix.md`

- Dodać `TaskCreate`, `TaskUpdate`, `TaskList` do `allowed-tools` w frontmatter
- Dodać instrukcje TaskCreate na początku Phase 1 — tworzenie wszystkich 6 tasków
- Dodać instrukcje TaskUpdate (status: in_progress/completed) przy przejściu między fazami
- Task 3 pozostaje in_progress do momentu approval od usera
- Task 5 obejmuje weryfikację + auto-iteracje (bez tworzenia nowych tasków per iteracja)

# Agent Teams w pluginach av-marketplace

**Data:** 2026-02-18
**Status:** Zatwierdzony design
**Dotyczy:** web-auditor, code-review

---

## Kontekst

Claude Code wprowadził eksperymentalny koncept [Agent Teams](https://code.claude.com/docs/en/agent-teams) — koordynację wielu instancji Claude Code pracujących jako zespół ze wspólną listą zadań, bezpośrednią komunikacją między agentami i scentralizowanym zarządzaniem.

Obecna architektura pluginów web-auditor i code-review opiera się na subagentach (fire-and-forget), które raportują wyniki do koordynatora bez komunikacji między sobą. Agent Teams umożliwia komunikację między agentami, co otwiera scenariusze:

- **Cross-pollination** — agent A informuje agenta B o odkryciu do głębszego zbadania
- **Adversarial review** — agenci kwestionują nawzajem swoje wyniki, eliminując false positives
- **Shared context building** — kolektywne budowanie wspólnego obrazu systemu

## Decyzje projektowe

| Decyzja | Wybór | Uzasadnienie |
|---------|-------|-------------|
| Podejście | Selective + Adversarial (A+C) | Subagenty do skanowania (tanio), Agent Teams do weryfikacji (wartość) |
| Dual-mode | Tak | Subagenty domyślnie, Agent Teams z flagą `--agent-team` |
| Minimalizacja kosztów | Agent Teams tylko w fazie weryfikacji | 2 teammate'ów zamiast 7, operują na wynikach nie na surowych danych |
| Agenty per-plugin | Tak | Różna wiedza domenowa, inne wzorce korelacji |

## Architektura

### Workflow z `--agent-team`

```
Phase 1: Recon (bez zmian)
    |
Phase 2: Parallel Scanning (subagenty, bez zmian)
    |
    v zebrane wyniki wszystkich subagentow
    |
    +-- [bez flagi] --> Phase 3: Consolidation (obecny flow)
    |
    +-- [--agent-team] --> Phase 2.5: Verification Team
                               |
                               +- Cross-Verifier  <--> Challenger
                               |       ^                    ^
                               |       v                    v
                               +- Synthesizer (lead)
                                       |
                                   Phase 3: Enhanced Consolidation
```

### Verification Team — role

| Rola | Odpowiedzialnosc |
|------|-----------------|
| **Synthesizer** (lead) | Laczy wyniki skanow, identyfikuje powiazania miedzy domenami, buduje wspolny obraz ryzyka. Koordynuje debate. |
| **Cross-Verifier** | Analizuje wyniki pod katem powiazan miedzydomenowych. Identyfikuje luki w coverage. Proponuje nowe composite findings. |
| **Challenger** | Kwestionuje severity, szuka false positives, weryfikuje czy remediation jest realistyczna. Kazdy finding CRITICAL/HIGH musi "przezyc" challenge. |

## Interfejs komend

### web-auditor

```
/audit <url> [--scope all|security|seo|performance|compliance] [--depth N] [--output-dir path] [--agent-team]
```

### code-review

```
/review [description] [--agent-team]
```

### Walidacja

Jesli `--agent-team` podane, ale `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` nie wlaczone:

```
! Agent Teams require the experimental flag.
  Add to settings.json:
  { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }

  Continuing without Agent Teams...
```

## Zmiany w plikach

### web-auditor

| Plik | Zmiana |
|------|--------|
| `commands/audit.md` | Parsowanie `--agent-team`, walidacja flagi env, przekazanie do agenta |
| `agents/web-auditor.md` | Nowa Phase 2.5 warunkowa |
| `agents/cross-verifier.md` | **Nowy agent** |
| `agents/challenger.md` | **Nowy agent** |

### code-review

| Plik | Zmiana |
|------|--------|
| `commands/review.md` | Parsowanie `--agent-team`, walidacja flagi env |
| `commands/review.md` | Nowa sekcja warunkowa po Step 5 |
| `agents/cross-verifier.md` | **Nowy agent** |
| `agents/challenger.md` | **Nowy agent** |

### Struktura katalogow

```
plugins/web-auditor/agents/
  +-- web-auditor.md          (istniejacy - lead/koordynator)
  +-- web-security-agent.md   (istniejacy)
  +-- ...                     (pozostale istniejace)
  +-- cross-verifier.md       (NOWY)
  +-- challenger.md           (NOWY)

plugins/code-review/agents/
  +-- security-auditor.md     (istniejacy)
  +-- code-quality-auditor.md (istniejacy)
  +-- feedback-analyzer.md    (istniejacy)
  +-- cross-verifier.md       (NOWY)
  +-- challenger.md           (NOWY)
```

## Phase 2.5 — szczegolowy flow

### web-auditor

1. Zbierz wyniki Phase 2 w findings bundle (web_security, api_security, infrastructure, supply_chain, seo, performance, compliance)
2. `TeamCreate("verification-team")`
3. Spawn Cross-Verifier z findings bundle
4. Spawn Challenger z findings bundle
5. Czekaj na wyniki + komunikacje miedzy nimi
6. Zbierz enhanced findings
7. Shutdown team
8. Przejdz do Phase 3 z enhanced findings

### code-review

Analogiczny flow po zebraniu wynikow z security-auditor i code-quality-auditor.

## Prompt design — Cross-Verifier

### Input

Findings bundle + URL inventory + detected technologies (web-auditor) lub pelne wyniki obu audytorow (code-review).

### Zadania

1. **Korelacje miedzydomenowe** — dla kazdej pary domen sprawdz czy findings sie wzmacniaja
2. **Coverage gaps** — co powinno byc sprawdzone ale nie zostalo
3. **Severity adjustment** — gdy dwa findings razem tworza wieksze ryzyko
4. **Nowe composite findings** — findings wynikajace z kombinacji

### Output format

```markdown
## Cross-Domain Correlations
- [CORRELATION-1] {domena A finding} + {domena B finding} -> {implikacja}
  Suggested action: {new finding | severity upgrade | coverage note}

## Coverage Gaps
- [GAP-1] {co pominieto} - recommended: {ktory agent powinien to sprawdzic}

## New Composite Findings
- [COMPOSITE-1] [SEVERITY] {tytul} - based on: {finding IDs}
```

### Przykladowe korelacje (web-auditor)

- Infra: otwarty port 3000 + WebSec: brak CSP -> podwyzszenie severity
- Supply chain: outdated jQuery + WebSec: brak X-Content-Type-Options -> XSS risk
- Performance: brak cache headers + Compliance: brak consent -> tracking bez zgody cached

### Przykladowe korelacje (code-review)

- God Object + injection vulnerability w tym obiekcie -> wyzsze ryzyko
- Brak typowania + user input handling -> injection surface
- Circular dependency + security-critical module -> blast radius
- Missing tests + security-critical code -> unverified security

## Prompt design — Challenger

### Input

Ten sam findings bundle co Cross-Verifier.

### Zadania

1. **Weryfikacja CRITICAL/HIGH** — kazdy finding musi przejsc challenge: czy evidence wystarczajacy? czy remediation realistyczna? czy severity uzasadniony?
2. **False positive detection** — header "missing" ale kompensowany, vulnerability w nieuzywany kodzie, outdated library ale vulnerable function nie wywolywana
3. **Severity calibration** — standaryzacja severity across domen

### Output format

```markdown
## Challenge Results
- [FINDING-ID] Status: confirmed | downgraded:{old}->{new} | false-positive
  Reasoning: {dlaczego}

## False Positives
- [FINDING-ID] {dlaczego to false positive}

## Severity Corrections
- [FINDING-ID] {old severity} -> {new severity}: {uzasadnienie}
```

## Komunikacja miedzy teammate'ami

Oba agenty dostaja w prompcie instrukcje:

```
You are part of a Verification Team. You can message your teammate directly:
- Send your findings to your teammate for cross-review
- Respond to challenges or correlations they send you
- Work toward consensus on disputed findings
- If you disagree, explain why with evidence

Your teammate:
- Cross-Verifier: focuses on cross-domain correlations and coverage gaps
- Challenger: focuses on false positives and severity calibration
```

## Tools dla nowych agentow

| Agent | Tools | Uzasadnienie |
|-------|-------|-------------|
| Cross-Verifier | Read, Grep, Glob, WebSearch | Weryfikacja korelacji, CVE lookup |
| Challenger | Read, Grep, Glob, WebSearch | Weryfikacja false positives, kontekst |

Oba agenty nie potrzebuja Bash, Write ani Playwright — operuja wylacznie na findings.

## Enhanced Phase 3 — konsolidacja

### Algorytm merge

1. Wez oryginalne findings z Phase 2
2. Zastosuj Challenger decisions: usun false-positive, zmien severity downgraded, oznacz confirmed tagiem `[verified]`
3. Dodaj composite findings od Cross-Verifier
4. Dolacz coverage gaps jako sekcje w raporcie
5. Deduplikuj
6. Sortuj po severity

### Nowe sekcje w raporcie (web-auditor)

```markdown
## Verification Summary

| Metric | Count |
|--------|-------|
| Findings verified | {n} |
| False positives removed | {n} |
| Severity adjustments | {n} |
| New cross-domain findings | {n} |
| Coverage gaps identified | {n} |

### Cross-Domain Correlations
{Tabela korelacji z Cross-Verifier}

### Challenged Findings
{Lista findings ktore zostaly downgraded lub usuniete, z uzasadnieniem}

### Coverage Gaps
{Co nie zostalo zbadane - rekomendacje na nastepny audit}
```

### Nowe sekcje w raporcie (code-review)

```markdown
## Verification Summary

### Cross-Analysis (Security <-> Quality)
{Korelacje miedzy findings security i quality audytorow}

### Challenged Findings
{Findings odrzucone lub skorygowane przez Challenger}
```

## Czego NIE zmieniamy

- Format raportu bez `--agent-team` — zero zmian, pelna backward compatibility
- Phase 1 i Phase 2 — bez zmian
- Istniejace agenty (security-auditor, web-security-agent, itd.) — bez zmian
- plugin.json — bez zmian (nowe agenty automatycznie wykrywane z katalogu agents/)

# Format planu av-setup

Jeden format dla trybów NOWY, UZUPEŁNIENIE, ADOPCJA i ODŚWIEŻENIE. Sekcje oznaczone "(ADOPCJA)" dodaj tylko w tym trybie.

```markdown
# av-setup: <projekt> (<tryb>)

## Werdykt
<1-2 zdania: ile plików tworzymy, aktualizujemy, zostawiamy, konwertujemy, usuwamy.>

## Decyzje
| Plik | Akcja | Cel | Źródło faktów / uzasadnienie |
|---|---|---|---|

## Config
<kluczowe wartości: bramki quick/full, ryzyko, git, modele; pełny JSON w sekcji "Załącznik: config" na końcu planu>

## Wiedza przenoszona do nakładek (ADOPCJA)
| Źródło (plik:zakres linii) | Reguły (skrót) | Cel |

## Wiedza, która ginie (ADOPCJA)
<wynik `adoption_diff.sh`: TOKENS n LOST m FILTERED f>
<orkiestracja, formaty handoff, statusy; każdy punkt ze źródłem i tym, co go zastępuje. Każda grupa tokenów LOST ma cel w "Wiedza przenoszona do nakładek" albo wiersz tutaj.>

## Mapowanie trybów (ADOPCJA, gdy repo miało własne tryby)
| Stary tryb | Warunki | Nowy tryb | Zaostrzenia w nakładce |

## Nieprzeniesione celowo (ADOPCJA)
<reguły ze starego setupu, których nie przenosimy, bo są nieaktualne albo sprzeczne z kodem; każda z dowodem>

## Rozjazdy docs z kodem
<audyt z kroku 3 SKILL.md: suma i liczby per plik; pełna lista w pliku roboczym>
| Plik docs | MISSING | NAME po triage | LINEREF | Usunięte nazwy | Razem |
|---|---|---|---|---|---|

<rozjazdy, które zmieniają decyzje planu:>
| plik:linia | docs mówi | kod mówi |

<przy ponad 10 rozjazdach: krok "av-docs-sync audit --fix" przed nakładkami, do zatwierdzenia; w Decyzjach jako osobny wiersz>


## Decyzje domyślne
<wartości przyjęte bez pytania, np. przy --defaults; każda z powodem>

## TODO
<rzeczy, których nie da się ustalić z repo>

## Załącznik: config
<pełny proponowany `.ai/av.config.json` w bloku json>
```

## Akcje

| Akcja | Znaczenie |
|---|---|
| UTWÓRZ | nowy plik |
| UPDATE | edycja istniejącego pliku, zakres zmian w kolumnie "Cel" |
| KEEP | bez zmian |
| CONVERT | treść przechodzi do nakładki, configu albo docs; plik potem do usunięcia |
| MERGE | łączy się z innym plikiem |
| DROP | usunięcie bez przenoszenia treści (nieaktualne, zdublowane) |
| MOVE | przeniesienie pliku (`git mv`) z poprawą odwołań; ścieżka docelowa w kolumnie "Cel" |
| MAP | istniejący plik zespołu pokrywa temat z zestawu docs; nowego pliku nie tworzymy, `README.md` docs linkuje do istniejącego |

UPDATE obejmuje też "KEEP z poprawką odwołań": plik zostaje, zmieniają się tylko nazwy usuniętych agentów i komend. Zakres zmiany wpisz w kolumnie "Cel", np. "tylko sekcja Pipeline" albo "tylko odwołania".

## Szczegółowość

- Źródła reguł podawaj jako `plik:zakres` na grupę reguł, np. `swift-reviewer.md:20-58 -> osie 1-4`. Nie potrzeba wiersza na każdą regułę.
- Pozycje grupuj: "skrypty `scripts/*_test.sh` (4 pliki) KEEP" zamiast 4 wierszy.
- Plan ma być czytelny w 5 minut. Sekcja "Decyzje" zwykle mieści się w 40 wierszach.

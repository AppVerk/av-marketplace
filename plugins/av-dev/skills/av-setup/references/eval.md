# Eval review po wdrożeniu

Eval sprawdza, czy `av-review` z nowym `code-review.md` i nakładką łapie typowe defekty tego repo. Uruchamiasz go krokiem 10b, tylko z flagą `--eval`.

Wynik trafia do raportu jako "Eval review: N/5".

## Zasady bezpieczeństwa

- Eval działa tylko na klonie w katalogu roboczym sesji (`<tmp>/eval-<projekt>`). Nigdy na żywym repo.
- Defekty i fikcyjne sekrety istnieją tylko w klonie. Klon usuń po ocenie.
- Bez commitów w żywym repo, bez push, bez komend na środowiskach współdzielonych.
- Fikcyjny sekret wygląda realnie, ale nie jest prawdziwy, np. `sk_test_EVAL0000000000000000`.

## Przebieg

1. **Klon.** `git clone --no-hardlinks <root-repo> <tmp>/eval-<projekt>`. Skopiuj do klonu nowe, jeszcze niezacommitowane pliki setupu: config, nakładki, `code-review.md`, `contracts.md`, skille ról.
2. **Gałąź.** W klonie `git checkout -b eval/av-review`. Zacommituj setup jako bazę: `git commit -m "eval base"`.
3. **Defekty.** Wstrzyknij N defektów (domyślnie 5) z sekcji "Defekty do evalu" profilu stacku. Każdy w innym pliku, w kodzie, który wygląda na zwykłą zmianę funkcji. Dodaj też 1-2 poprawne zmiany jako tło, żeby diff nie składał się z samych błędów.
4. **Klucz odpowiedzi.** Zapisz listę defektów (plik:linia, opis) do `<tmp>/eval-key.md`. Klucz zostaje poza klonem i poza promptem reviewera.
5. **Commit defektów.** `git commit -am "eval changes"` w klonie. Diff względem bazy to materiał review.
6. **Review.** Świeży subagent bez kontekstu tej sesji uruchamia skill `av-review` na klonie, dla zakresu `eval base..HEAD`. Model: `agents.models.review` z configu. Prompt podaje tylko katalog klonu i zakres. Nie wspominaj o evalu ani o liczbie defektów.
7. **Ocena.** Porównaj findings z kluczem:
   - trafienie: finding wskazuje plik defektu i opisuje jego istotę (linia może się różnić o kilka),
   - fałszywe potwierdzenie: reviewer ocenił zmienione miejsce z defektem jako poprawne, albo werdykt to APPROVED mimo defektu o wadze blokującej,
   - fałszywe zgłoszenie: finding w kodzie tła, który nie jest błędem.
8. **Sprzątanie.** Usuń klon i klucz. Zachowaj tylko wynik.

## Wynik

Do raportu setupu, wiersz "Eval review":

```
N/5 defektów, F fałszywych potwierdzeń, Z fałszywych zgłoszeń
```

- Poniżej 4/5: sprawdź, której osi `code-review.md` brakuje albo której narzędzia brakuje w nakładce `av-review.md`. Zaproponuj poprawkę. Nie powtarzaj evalu w tej samej sesji, żeby nie dopasować reguł do znanych defektów.
- Każde fałszywe potwierdzenie opisz w "Luki" raportu z nazwą osi.
- Wynik z modelem innym niż w configu nie jest porównywalny. Zapisz model obok wyniku.

## Defekty spoza profilu

Profil daje domyślny zestaw. Lepszy zestaw pochodzi z historii repo:
- defekty z pomiarów zespołu (np. stary benchmark pipeline'u),
- błędy z ostatnich poprawek (`git log --grep` z prefiksem ticketu i słowem "fix"),
- reguły z `code-review.md` oznaczone jako blokujące.

Wybierz 5 z różnych osi review. Jedna oś nie powinna mieć więcej niż 2 defekty.

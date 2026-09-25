# Profil: frontend w repo backendu (Node, TypeScript, Tailwind, E2E)

Stosuj jako dodatek, gdy skan wykrył `package.json` w podkatalogu repo innego stacku. Przykład: `metronic/` w panelu Symfony albo `tests/E2E/` z Playwright.

## Wykrywanie
- `id: node` ze skanu z `dir` różnym od `.`.
- `frontend_hints`: `tailwindcss`, `typescript`, `vite`, `webpack`, `@playwright/test`.

## Komendy i bramki
- Build assetów: skrypt `build` z `package.json` w danym katalogu, z polem `cwd` w configu.
- Gdy build nadpisuje pliki śledzone przez git (np. `public/build/`), nie wkładaj go do `quick`. Zmienia drzewo, więc wcześniejsze dowody robią się STALE. Daj go do `full` jako ostatnią komendę.
- E2E: osobna bramka `e2e` z `precheck` na działające środowisko (docker, serwer aplikacji, atrapa API typu WireMock). `needs` opisuje, jak je uruchomić.
- Nie wrzucaj E2E do `quick`. Trwa długo i wymaga środowiska.

## Docs
- `frontend.md`: układ widoków, komponenty, style, build assetów.
- `js-reference.md` albo sekcja we `frontend.md`: strony TS, wzorce, helpery.
- `e2e-testing.md`: uruchomienie, fixtures, atrapy API, selektory (`data-testid`).

## Osie review
| Oś | Co sprawdzić |
|---|---|
| Spójność widoków | te same komponenty i klasy co w podobnych widokach |
| TS | typy, brak globali, obsługa błędów fetch |
| Dostępność | etykiety, focus, kontrast |
| E2E | selektory stabilne (`data-testid`), brak sleepów |

## Weryfikacja wizualna
Gdy zespół porównuje ekrany z referencją (Figma, istniejące widoki), opisz to w nakładce `av-verify.md`: jak zrobić zrzuty, gdzie je zapisać (`<paths.workspace>/screenshots/`), z czym porównać.

# Profil: iOS (Swift, UIKit lub SwiftUI)

## Wykrywanie
- `*.xcworkspace` albo `*.xcodeproj` w root. `Podfile` oznacza CocoaPods, `Package.swift` albo `Package.resolved` oznacza SPM.
- `xcode_synchronized_groups` ze skanu: `false` oznacza klasyczne grupy. Wtedy nowy plik trzeba dodać do targetu. Bez tego build nie przejdzie.
- UIKit vs SwiftUI: policz `import SwiftUI` i `UIViewController` w kodzie.

## Komendy i bramki
- Schematy i konfiguracje: `xcodebuild -list -json -workspace <ws>` (albo `-project`).
- Build: `xcodebuild -workspace <ws> -scheme <scheme> -destination "generic/platform=iOS Simulator" -configuration <Debug-*> build`, `expect: "BUILD SUCCEEDED"`.
- Nie dodawaj `CODE_SIGNING_ALLOWED=NO`, gdy aplikacja używa Keychain. Bez podpisu Keychain nie działa i testy dają fałszywe wyniki.
- Testy jednostkowe: `xcodebuild test -scheme <scheme> -destination "platform=iOS Simulator,name=<model>" -only-testing:<Target>`. Gdy repo ma skrypt z czytelnym statusem, użyj skryptu.
- `precheck` dla testów: dostępny symulator (`xcrun simctl list devices available`).
- `DEVELOPER_DIR` ustaw, gdy w systemie jest kilka Xcode. Najlepiej w `env` w `.claude/settings.json`, wtedy komendy w configu zostają krótkie. Alternatywa: prefiks w `run`, np. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...`.
- Nie proponuj `pod update` w bramkach. Tylko `pod install`, gdy `Podfile.lock` różni się od `Pods/Manifest.lock`.
- Typowo: `quick` = lint + docs + unit, `full` = quick + build; testy UI jako osobna bramka `ui` z `covers: ["build"]`.
- `docs`: komenda z `references/config-schema.md` (`check_refs.sh` i `check_linerefs.sh` z `--strict`). Trwa sekundy i łapie rozjazdy docs z kodem przy każdej zmianie.
- Testy jednostkowe przez `xcodebuild test` kompilują aplikację, więc trwają minuty. Gdy `unit` trwa ponad 2 minuty, zapytaj, czy trzymać go w `quick`, czy przenieść do `full`. `quick` jest uruchamiany po każdej rundzie poprawek. Z `--defaults`: zachowaj wybór zespołu (np. skrypt opisany w docs jako bramka przy każdej zmianie), a bez takiego opisu przenieś `unit` do `full`.
- `precheck` dla testów i builda: `test -d Pods` (przy CocoaPods) i dostępny symulator.
- Pewny `expect` dla xcodebuild: `** BUILD SUCCEEDED **` (build) i `** TEST SUCCEEDED **` (test).
- Cykl czerwony-zielony potrzebuje szybkiego testu jednej suity. Dodaj komendę poza bramkami, np. `unit_one` z `run: "scripts/unit_test.sh \"$UNIT_SUITE\""` i `precheck: "test -n \"$UNIT_SUITE\""`. Wywołanie: `gate.sh --only unit_one --env UNIT_SUITE=StringValidationTests`.

## Dodatkowe docs
- `networking.md`: warstwa sieci, środowiska API, nagłówki, obsługa błędów i 401.
- `navigation.md`: nawigacja, deep linki, push.
- `ui-reference.md`: kolory, fonty, komponenty, helpery.
- `known-issues.md`: dług techniczny, gdy zespół go śledzi.

## Moduły
Kandydaci: katalogi ekranów lub feature'ów (np. `*/Domains/*`, `*/Features/*`, `*/Scenes/*`). Szablon modułu: Pliki (Warstwa | Plik), Stan (enum), Endpointy, Nawigacja, Lokalizacja, Pułapki.

## Osie review
| Oś | Co sprawdzić |
|---|---|
| Warstwy i DI | przepływ VC -> VM -> manager -> API; rejestracje w kontenerze; brak skrótów przez singletony |
| Pamięć i wątki | `[weak self]` w closure'ach i `sink`; UI tylko na main; `store(in:)` dla subskrypcji |
| Lokalizacja | teksty UI przez klucze; klucz we wszystkich plikach języków |
| Konwencje UI | kolory i fonty z rozszerzeń projektu, bez hexów i `systemFont` |
| Regresja stylu | nowy kod w aktualnym wzorcu, nie w starym |
| Bezpieczeństwo | Keychain zamiast UserDefaults dla sekretów; ATS; walidacja deep linków; brak logowania danych osobowych; uprawnienia w Info.plist |
| Projekt Xcode | nowe pliki w targecie; brak przypadkowych zmian w `project.pbxproj`, entitlements, plistach |

## Role dla av-implement
- `data` (skill `<prefiks>-data`): modele odpowiedzi, endpointy, managery domenowe, rejestracje DI.
- `ui` (skill `<prefiks>-ui`): ViewModel, ViewController, komórki, nawigacja, tłumaczenia, testy UI.
Tryb DUŻY dzieli pracę na te role z rozłącznymi plikami. Kontrakt między nimi to lista typów i metod warstwy danych.

## Wysokie ryzyko (domyślne)
Uwierzytelnianie i token, Keychain, sesja i wylogowanie, konfiguracja API (`clientId`, wersja API), płatności, deep linki i push, migracje danych lokalnych, entitlements i Info.plist.

## Mapa docs-sync
| Zmiana w | Docs |
|---|---|
| endpointy API | `networking.md`, moduł |
| managery domenowe, DI | `architecture.md`, moduł |
| nawigacja, deep linki | `navigation.md` |
| nowy katalog ekranu | nowy `modules/<Moduł>.md`, `modules/README.md` |
| Podfile, Package.resolved | `tech-stack.md` |

## Defekty do evalu
Zestaw dla `references/eval.md`. Wzór: pomiar pipeline'u nfamily-ios z 18-19.09.2026.
| # | Defekt | Oś |
|---|---|---|
| 1 | fikcyjny klucz API albo `clientSecret` wpisany w kodzie klienta sieci | Bezpieczeństwo |
| 2 | `sink { self.… }` bez `[weak self]` w nowym ViewModelu | Pamięć i wątki |
| 3 | nowy klucz tłumaczenia tylko w części plików `Localizable.strings` | Lokalizacja |
| 4 | `UIColor(hex:)` albo `UIFont.systemFont` zamiast rozszerzeń projektu | Konwencje UI |
| 5 | pełny model użytkownika (e-mail, telefon) w `print` albo w `UserDefaults` | Bezpieczeństwo |

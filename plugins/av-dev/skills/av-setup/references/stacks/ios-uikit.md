# Profile: iOS (Swift, UIKit or SwiftUI)

## Detection
- `*.xcworkspace` or `*.xcodeproj` in the root. `Podfile` means CocoaPods, `Package.swift` or `Package.resolved` means SPM.
- `xcode_synchronized_groups` from the scan: `false` means classic groups. Then a new file must be added to the target. Without that the build fails.
- UIKit vs SwiftUI: count `import SwiftUI` and `UIViewController` in the code.

## Commands and gates
- Schemes and configurations: `xcodebuild -list -json -workspace <ws>` (or `-project`).
- Build: `xcodebuild -workspace <ws> -scheme <scheme> -destination "generic/platform=iOS Simulator" -configuration <Debug-*> build`, `expect: "BUILD SUCCEEDED"`.
- Do not add `CODE_SIGNING_ALLOWED=NO` when the app uses Keychain. Without signing, Keychain does not work and tests give false results.
- Unit tests: `xcodebuild test -scheme <scheme> -destination "platform=iOS Simulator,name=<model>" -only-testing:<Target>`. When the repo has a script with a readable status, use the script.
- `precheck` for tests: an available simulator (`xcrun simctl list devices available`).
- Set `DEVELOPER_DIR` when the system has several Xcode versions. Best in `env` in `.claude/settings.json`; then the config commands stay short. Alternative: a prefix in `run`, e.g. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...`.
- Do not propose `pod update` in gates. Only `pod install`, when `Podfile.lock` differs from `Pods/Manifest.lock`.
- Typically: `quick` = lint + docs + unit, `full` = quick + build; UI tests as a separate `ui` gate with `covers: ["build"]`.
- `docs`: the command from `references/config-schema.md` (`check_refs.sh` and `check_linerefs.sh` with `--strict`). It takes seconds and catches docs drift from code on every change.
- Unit tests through `xcodebuild test` compile the app, so they take minutes. When `unit` takes over 2 minutes, ask whether to keep it in `quick` or move it to `full`. `quick` runs after each fix round. With `--defaults`: keep the team's choice (e.g. a script described in the docs as the gate for every change); without such a description, move `unit` to `full`.
- `precheck` for tests and build: `test -d Pods` (with CocoaPods) and an available simulator.
- Reliable `expect` for xcodebuild: `** BUILD SUCCEEDED **` (build) and `** TEST SUCCEEDED **` (test).
- The red-green cycle needs a fast test of one suite. Add a command outside the gates, e.g. `unit_one` with `run: "scripts/unit_test.sh \"$UNIT_SUITE\""` and `precheck: "test -n \"$UNIT_SUITE\""`. Call: `gate.sh --only unit_one --env UNIT_SUITE=StringValidationTests`.

## Additional docs
- `networking.md`: network layer, API environments, headers, error handling and 401.
- `navigation.md`: navigation, deep links, push.
- `ui-reference.md`: colors, fonts, components, helpers.
- `known-issues.md`: technical debt, when the team tracks it.

## Modules
Candidates: screen or feature directories (e.g. `*/Domains/*`, `*/Features/*`, `*/Scenes/*`). Module template: Files (Layer | File), State (enum), Endpoints, Navigation, Localization, Pitfalls.

## Review axes
| Axis | What to check |
|---|---|
| Layers and DI | VC -> VM -> manager -> API flow; registrations in the container; no shortcuts through singletons |
| Memory and threads | `[weak self]` in closures and `sink`; UI only on main; `store(in:)` for subscriptions |
| Localization | UI texts through keys; key in all language files |
| UI conventions | colors and fonts from project extensions, no hex values and no `systemFont` |
| Style regression | new code in the current pattern, not the old one |
| Security | Keychain instead of UserDefaults for secrets; ATS; deep link validation; no logging of personal data; permissions in Info.plist |
| Xcode project | new files in the target; no accidental changes in `project.pbxproj`, entitlements, plists |

## Roles for av-implement
- `data` (skill `<prefix>-data`): response models, endpoints, domain managers, DI registrations.
- `ui` (skill `<prefix>-ui`): ViewModel, ViewController, cells, navigation, translations, UI tests.
LARGE mode splits the work into these roles with disjoint files. The contract between them is the list of data layer types and methods.

## High risk (default)
Authentication and token, Keychain, session and logout, API configuration (`clientId`, API version), payments, deep links and push, local data migrations, entitlements and Info.plist.

## Docs-sync map
| Change in | Docs |
|---|---|
| API endpoints | `networking.md`, module |
| domain managers, DI | `architecture.md`, module |
| navigation, deep links | `navigation.md` |
| new screen directory | new `modules/<Module>.md`, `modules/README.md` |
| Podfile, Package.resolved | `tech-stack.md` |

## Eval defects
The set for `references/eval.md`. Based on: the nfamily-ios pipeline measurement from 18-19.09.2026.
| # | Defect | Axis |
|---|---|---|
| 1 | fake API key or `clientSecret` hard-coded in the network client | Security |
| 2 | `sink { self.… }` without `[weak self]` in a new ViewModel | Memory and threads |
| 3 | new translation key in only some `Localizable.strings` files | Localization |
| 4 | `UIColor(hex:)` or `UIFont.systemFont` instead of project extensions | UI conventions |
| 5 | full user model (e-mail, phone) in `print` or in `UserDefaults` | Security |

---
paths:
  - "**/*.swift"
  - "PullwatchKit/**"
  - "Pullwatch/**"
---

# Writing Swift here

Pullwatch is a menu-bar app (`LSUIElement`) for **macOS 26.6 and later**,
universal (Apple Silicon and Intel), built with Xcode 27 and Swift 6.4
(`swift-tools-version: 6.4`, Swift 6 language mode). Write for the current SDK; anything up to macOS 26.6 needs no
availability check, anything newer does, with a fallback that works on 26.6. When unsure whether an API exists or how it is spelled, read
the SDK's `.swiftinterface` or Apple's documentation first; never guess an
API from memory.

Apple's own guidance ships with Xcode as agent skills: run
`bash scripts/dev/xcode-skills.sh` once per Mac (and after an Xcode update)
to export them into `.claude/skills/` (git-ignored). `swiftui-specialist`
supersedes anything here that disagrees, apart from the macOS 26.6 floor.

Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when
`xcode-select` points at the Command Line Tools.

## Follow the code that is there

This is Alessandro's codebase; our work goes back to him as one combined
pull request at the end. Rewriting and restructuring it is allowed (CLAUDE.md,
Hard rules); keep these conventions while doing so.

- **Comments and design documents are Dutch**, like the rest of the code and
  `docs/superpowers/`. Commit subjects, PR titles and issues are English.
- Formatting is Xcode's (Ctrl-I indentation, 4 spaces). Reformat only what a
  pull request is about, so its diff stays readable.
- No "·" separators or em dashes in user-facing text: a translated phrase,
  a second line in `.secondary`, or separate views.
- `PullwatchKit` holds everything without a window, in modules:
  `PullwatchCore` (`Sources/PullwatchCore/`, by area: models, the
  `PRProvider` and `TokenSource` protocols, polling, history, version checks,
  the update check; no provider API code), one module per provider
  (`PullwatchGitHub`, `PullwatchAzureDevOps`) that depends only on
  `PullwatchCore`, and `PullwatchProviders` (`ProviderFactory`). A new
  provider is a new module plus one case in `ProviderFactory`. Module names
  start with `Pullwatch` so none shares its name with a type in it. Only
  what another module or the app uses is `public`; what only the package's
  modules share is `package`. The app (`Pullwatch/Pullwatch/`) only wires
  (`App/`) and draws (`Views/`): `AppModel` is the one `@Observable` model,
  views read it. A new file goes in the folder of its module and area; the
  Xcode project picks it up. A new library product also needs an
  `XCSwiftPackageProductDependency` in `project.pbxproj`.
- Network access goes through the `HTTPClient` protocol (`HTTP.swift`) and
  processes through `ProcessRunner`, so tests can stub both. Errors a person
  sees go through `ProviderError.userMessage`.
- Tokens live in the Keychain (`Keychain.swift`). Settings are `AppConfig`,
  stored as `~/Library/Application Support/Pullwatch/config.json` through
  `JSONFileStore` (history and seen state likewise); only small UI state
  (last section, seen versions) is in `UserDefaults`. Never a token in
  `UserDefaults` or a file.
- Logging with `Logger(subsystem: "nl.torrisi.pullwatch", category: …)`.

## Language and concurrency

- Swift 6 strict concurrency with approachable concurrency
  (`SWIFT_APPROACHABLE_CONCURRENCY`) and the upcoming features
  `ExistentialAny`, `MemberImportVisibility`, `NonisolatedNonsendingByDefault`
  and `InferIsolatedConformances`, in the app (project build settings) and in
  every PullwatchKit target (`Package.swift`). CI treats warnings as errors.
- **Where code runs.** The app target is `@MainActor` by default
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in `App.xcconfig`): views,
  `AppModel` and app glue need no annotation. Mark what is not UI
  `nonisolated`: a network client, a file-level `Log`, pure value extensions
  used by `KeyPathComparator` or tests. PullwatchKit is nonisolated by
  default; an `async` function there runs on its caller's actor
  (`nonisolated(nonsending)`); use `@concurrent` only for work that must leave
  the caller's actor. App tests that touch app types are `@MainActor` suites.
- No `@preconcurrency`, `nonisolated(unsafe)` or `@unchecked Sendable` to
  silence the compiler (tests excepted).
- `async`/`await`, `Task`, task groups and actors for new code; shared
  mutable state in an `actor`. Do not add `DispatchQueue`, completion
  handlers or Combine; the few existing `DispatchQueue.main.async` calls in
  AppKit glue stay until that code is touched for another reason.
- Observation (`@Observable`, `@State`, `@Bindable`), never
  `ObservableObject` / `@Published`.
- `any P` for existentials, `some P` for opaque types.

## SwiftUI and macOS

- System controls, fonts, semantic colours and SF Symbols by their real
  names. `Form` with `.formStyle(.grouped)` for settings,
  `ContentUnavailableView` for empty states.
- Liquid Glass comes from the system; never put `.glassEffect` behind
  content, only on a custom floating control.
- Every menu command has a keyboard shortcut (`Shortcuts.swift`), every
  icon-only button a `.help` and an accessibility label.
- Views send intents; `AppModel` changes state. No network calls from a
  view's body.

## Text and languages

The app speaks Dutch (development language of the package), English, German
and French, through `Pullwatch/Pullwatch/Localizable.xcstrings` and one
`Localizable.xcstrings` per PullwatchKit module with text (now
`PullwatchCore` and `PullwatchGitHub`).

- In a package module, text goes through that module's own bundle helper
  (`bundle: .localizedCore`, `bundle: .localizedGitHub`), which is
  `#bundle` in the language the app chose; a new module with text gets its
  own catalog, helper (`Bundle.localized(#bundle, for:)`) and an entry in
  `LocalizationTests.catalogs`. Give each key an `nl` entry too, so the
  module's bundle has an `nl.lproj`; without it Dutch falls back to
  another language.

- SwiftUI literals (`Text("…")`, `Button("…")`) localise by themselves;
  the keys are the Dutch text, as in the existing code.
- `String(localized:)` only where a `String` is required (notifications,
  messages kept in the model).
- A sentence is one string, never assembled from pieces; counts get plural
  variations in the catalog.
- **Every new string gets all four languages** in the catalog before the
  commit; `LocalizationTests` fails otherwise. Check the screens in at least
  Dutch and English.

## Tests

- Swift Testing only (`@Suite`, `@Test`, `#expect`, `#require`). Logic goes
  in a PullwatchKit module and is tested in that module's test target
  (`PullwatchKit/Tests/<Module>Tests`); `Pullwatch/PullwatchTests` checks
  the built app (hosted, no polling).
- Network tests go through `MockHTTPClient`, process tests through
  `MockProcessRunner` (both in `PullwatchKit/Tests/PullwatchTestSupport`,
  `package` so every test target can use them); never the real GitHub,
  Azure DevOps, `gh` or `az`.
- Never weaken, skip or delete a test to make a build pass.

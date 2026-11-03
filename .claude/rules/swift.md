---
paths:
  - "**/*.swift"
  - "PullwatchKit/**"
  - "Pullwatch/**"
---

# Writing Swift here

Pullwatch is a menu-bar app (`LSUIElement`) for **macOS 26.6 and later**,
universal (Apple Silicon and Intel), built with the current Xcode and Swift 6
language mode. Write for the current SDK; anything up to macOS 26.6 needs no
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
- `PullwatchCore` (`PullwatchKit/Sources/PullwatchCore/`, by area) holds
  everything without a window: providers, polling, history, version checks,
  the update check. The app (`Pullwatch/Pullwatch/`) only wires (`App/`) and
  draws (`Views/`): `AppModel` is the one `@Observable` model, views read it.
  A new file goes in the folder of its area; the Xcode project picks it up.
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

- Swift 6 strict concurrency. No `@preconcurrency`, `nonisolated(unsafe)` or
  `@unchecked Sendable` to silence the compiler (tests excepted).
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
and French, through `Pullwatch/Pullwatch/Localizable.xcstrings` and
`PullwatchKit/Sources/PullwatchCore/Localizable.xcstrings`.

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
  in `PullwatchCore` and is tested in `PullwatchKit/Tests/PullwatchCoreTests`;
  `Pullwatch/PullwatchTests` checks the built app (hosted, no polling).
- Network tests go through `MockHTTPClient`, process tests through
  `MockProcessRunner` (both in `PullwatchKit/Tests/PullwatchCoreTests/Support`); never
  the real GitHub, Azure DevOps, `gh` or `az`.
- Never weaken, skip or delete a test to make a build pass.

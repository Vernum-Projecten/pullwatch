---
paths:
  - "**/*.swift"
  - "PullwatchKit/**"
  - "Pullwatch/**"
---

# Writing Swift here

The one style guide for Pullwatch's Swift. It follows Apple's Xcode 27.1
agent skills and Swift 6.4; where it says less, the skills decide. Every rule
gives its reason, so a case it does not cover can be argued from that.

## Toolchain and sources of truth

- **macOS 26.6 and later, universal**, built with Xcode 27.1 and Swift 6.4.0
  (`swift-tools-version: 6.4`, Swift 6 language mode). Anything up to macOS
  26.6 needs no availability check; anything newer gets `if #available(macOS
  27, *)` with a fallback that works on 26.6, because users on 26.6 run the
  same binary.
- Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when
  `xcode-select` points at the Command Line Tools: their Swift is a
  different version.
- Apple's guidance ships with Xcode as agent skills. Run
  `bash scripts/dev/xcode-skills.sh` once per Mac and after every Xcode
  update; it exports them into `.claude/skills/` (git-ignored, they are
  Apple's). Read `swiftui-specialist` (and its `references/`) before writing
  or reviewing a view, `swiftui-whats-new-27` before using an SDK 27 API or
  when `@State` stops compiling, `modernize-tests` before touching tests.
- Never guess an API. Check the SDK's `.swiftinterface` (under
  `xcrun --sdk macosx --show-sdk-path`) or Apple's documentation first; the
  skills say the same.

## Follow the code that is there

The code goes back to Alessandro as one pull request, so it must read as his
codebase made better, not as a second style next to his.

- **Comments and design documents are Dutch**; commit subjects, PR titles
  and issues are English.
- Xcode's formatting (Ctrl-I, 4 spaces). Reformat only what the pull
  request is about, so the diff stays readable.
- No "·" separators or em dashes, in text a person sees and in comments: a
  translated phrase, a second line in `.secondary`, or separate views.

## File layout

A file is found by its name, a type by its module and area.

- `PullwatchKit` holds everything without a window. `PullwatchCore`
  (`Sources/PullwatchCore/<Area>/`: `Model`, `Providers`, `Polling`,
  `History`, `Versions`, `Updates`, `Support`) has no provider API code; each
  provider is a module (`PullwatchGitHub`, `PullwatchAzureDevOps`,
  `PullwatchGitLab`) that depends only on `PullwatchCore`;
  `PullwatchProviders` (`ProviderFactory`) is the only module that knows them
  all. A new provider is a new module plus one case in `ProviderFactory`.
  Module names start with `Pullwatch` so none shares its name with a type.
- The app only wires (`Pullwatch/Pullwatch/App/`: the `@Observable` models,
  AppKit glue) and draws (`Views/`, shared pieces in `Views/Components/`).
  Views read the models and send intents; they never call the network.
- One main type per file, named after it. An extension that adds a whole
  area to a large type goes in `Type+Area.swift`
  (`GitHubProvider+ExtraRepos.swift`). The synchronized Xcode folders pick
  a new file up; a new library product also needs an
  `XCSwiftPackageProductDependency` in `project.pbxproj`.
- In a file: the Dutch `///` comment on what the type is for, then the type,
  then `// MARK: -` sections for groups of members (`// MARK: - Afleveren`).
- Access: only what another module or the app uses is `public`; what only
  the package's modules share is `package`; the rest is `private` or
  internal. A wider surface is harder to change later.

## What runs where

Both targets build with strict concurrency, approachable concurrency
(`SWIFT_APPROACHABLE_CONCURRENCY`) and the upcoming features
`ExistentialAny`, `MemberImportVisibility`, `NonisolatedNonsendingByDefault`
and `InferIsolatedConformances` (project build settings and `Package.swift`).
CI treats warnings as errors.

- **The app target is `@MainActor` by default**
  (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in `App.xcconfig`). Views,
  models and AppKit glue need no annotation; writing `@MainActor` on them
  again only adds noise, so leave it off. Mark what is not UI `nonisolated`:
  an `HTTPClient`, a file-level `Log`, value types and extensions that tests
  or `KeyPathComparator` use off the main actor.
- **The test targets are not.** `App.xcconfig` only applies to the app, so
  a suite in `PullwatchTests` that touches app types is `@MainActor @Suite`,
  and the UI tests keep their `@MainActor`.
- **PullwatchKit is nonisolated by default.** An `async` function there is
  `nonisolated(nonsending)`: it runs on its caller's actor, so calling it
  from the main actor does not hop and its arguments need not be `Sendable`.
  Mark a function `@concurrent` only when its work must leave the caller's
  actor (`RepoCheckTables.build` makes large tables off the main actor).
- Shared mutable state lives in an `actor` (`PollEngine`, the providers,
  the token sources). Small state that synchronous code must reach goes in
  a `Mutex` from `Synchronization` (`SecretStores`), never `NSLock` plus
  `@unchecked Sendable`: the compiler then checks the type.
- No `@preconcurrency`, `nonisolated(unsafe)` or `@unchecked Sendable` to
  silence the compiler, in tests either; they hide the races strict
  concurrency exists to find.
- To get back to the main actor from a nonisolated closure, make the
  closure `@MainActor` (`{ @MainActor in … }`) instead of wrapping its body
  in `MainActor.run`; the isolation is then part of the closure's type.

## Async code

- `async`/`await`, `Task`, task groups and actors. No `DispatchQueue`,
  `DispatchGroup`, completion handlers or Combine: Apple ships an `async`
  form of the APIs we use (`UNUserNotificationCenter.add`,
  `notificationSettings()`, `URLSession.data(for:)`), and callbacks lose
  cancellation and error propagation. When a callback API has no `async`
  form, wrap it once: `withCheckedThrowingContinuation` for one result
  (resumed exactly once), `AsyncStream.makeStream` for a series
  (`ProcessRunner` turns `terminationHandler` and `readabilityHandler` into
  streams). Not `FileHandle.bytes` on a pipe: with several processes at once
  it can miss the end of the output and hang until the timeout.
- **Every long-running job has one owning task**, stored on the model that
  runs it (`VersionsModel.checkTask`, `PollingModel.refreshTask`,
  `UpdatesModel.checkTask`, the loop and wake tasks of `AppModel`), started
  by a `start…()` method that refuses a second one and cleared in a `defer`
  inside the task. A view calls `versions.startCheck()`, never
  `Task { await versions.check() }`: an unowned task cannot be cancelled or
  told apart from the next one. A task a view needs for its own lifetime
  goes in `.task` or `.task(id:)`. A stream of events (notification clicks)
  is an `AsyncStream` with one consumer, not a callback property.
- Cancellation is cooperative. A long call takes
  `withTaskCancellationHandler` to stop its work (terminate the process,
  cancel the request); a loop checks `Task.isCancelled` or calls
  `try Task.checkCancellation()`.
- **Cleanup goes in `defer`, and since Swift 6.4 it may `await`**
  (SE-0493): `defer { await store.unlock() }` runs on every way out of the
  scope, including a throw and cancellation, so the cleanup is written once
  instead of in each `catch`.
- **`withTaskCancellationShield`** (SE-0504) runs a closure as if its task
  were not cancelled, for work that must finish once started (saving a
  rotated refresh token, writing a file half way). It needs the macOS 27
  runtime, so until the floor moves, use it only inside
  `if #available(macOS 27, *)` with a fallback that keeps today's
  behaviour; where the fallback would be the whole function again, wait for
  the floor.
- Never block a thread of the cooperative pool (`readDataToEndOfFile`,
  `waitUntilExit`, `sleep`): the pool has as many threads as cores, and one
  blocked thread stalls unrelated tasks. Use the `async` API or
  `Task.sleep(for:)`.

## Types and syntax

- `any P` for an existential, `some P` for an opaque type
  (`ExistentialAny` requires it). An optional one needs no parentheses
  since Swift 6.4 (SE-0521): `any HTTPClient?`, `some View?`.
- A warning we accept on purpose gets `@diagnose` (SE-0522) on the smallest
  declaration, with a Dutch comment why:
  `@diagnose(DeprecatedDeclaration, as: ignored)`. The group name is the one
  in brackets after the warning (`[#DeprecatedDeclaration]`). Never use it
  to hide a warning we could fix, and never for a whole file.
- Errors a person sees go through `ProviderError.userMessage`. Network
  access goes through the `HTTPClient` protocol (`HTTP.swift`) and processes
  through `ProcessRunner`, so tests can stub both.
- Tokens live in the Keychain (`Keychain.swift`, `SecretStores`). Settings
  are `AppConfig` in `~/Library/Application Support/Pullwatch/config.json`
  through `JSONFileStore` (history and seen state likewise); only small UI
  state is in `UserDefaults`. Never a token in `UserDefaults` or a file.
- Logging with `Log(category:)`, which wraps
  `Logger(subsystem: "nl.torrisi.pullwatch", category:)`.

## Observation

- `@Observable` classes for state that views read; never
  `ObservableObject`, `@Published`, `@StateObject` or `@EnvironmentObject`.
  Observation tracks each property a view reads, so a change only redraws
  the views that read it.
- One model per job (`AccountsModel`, `HistoryModel`, `PollingModel`, …),
  put in each scene's environment by `appModels(_:)`. A view reads the model
  it needs with `@Environment(PollingModel.self) private var polling`, never
  the whole `AppModel`, which is for intents that span models (removing an
  account, Cmd-R, the settings with side effects). Bindings to an environment
  model go through `Bindable(router).path`.
- **A view inside a `Table` cell or a `List` row never reads a model from
  the environment**; the screen that owns the table reads it and passes the
  value in (`ChecksBadge(checks:isEnabled:)`). AppKit draws such a cell in
  its own hosting view and sometimes without the window's environment, and
  then SwiftUI stops the app ("No Observable object of type AccountsModel
  found"). `CellEnvironmentTests` draws these views without any model.
- In the app the default isolation already makes a model `@MainActor`; do
  not repeat it. A model in PullwatchKit has none, so it would need
  `@MainActor` itself.
- Make the types of stored properties `Equatable`: the generated setter then
  skips setting an equal value, and a poll that brings no news redraws
  nothing.
- A computed property still depends on what it reads. When many views read
  a derived value of a large collection, store the derived value and keep it
  up to date (`RepoPage.visiblePackageGroups`).
- `@ObservationIgnored` for state no view reads (tasks, caches, flags), so
  writing it redraws nothing.
- To follow a model outside a view, iterate `Observations { model.value }`
  (macOS 26): an `AsyncSequence` that yields after each transaction, without
  callbacks. SE-0506's `withObservationTracking(options:)` and
  `withContinuousObservation`, with `willSet`, `didSet` and `deinit` events,
  need macOS 27, so only behind `#available`.

## SwiftUI

From `swiftui-specialist` and `swiftui-whats-new-27`; read them for the
examples.

- **No soft-deprecated API in new or changed code.** They compile without a
  warning but are marked `deprecated: 100000.0`;
  `swiftui-specialist/references/soft-deprecated-apis.md` lists them with
  their replacements. The ones that turn up here: `.overlay(view)` and
  `.background(view)` become `.overlay { … }` and `.background { … }`,
  `foregroundColor` becomes `foregroundStyle`, `cornerRadius` becomes
  `clipShape(.rect(cornerRadius:))`, `onChange(of:) { new in }` becomes the
  two-parameter or no-parameter form, `NavigationView` becomes
  `NavigationStack` or `NavigationSplitView`. A pull request about something
  else leaves the views it does not touch alone.
- **`@State` is a macro in SDK 27.** Always `private`. Do not give it an
  initial value and also assign it in `init`: the body sees the initial
  value. Assign it only in `init`, or only at the declaration.
- **Data flow.** Give a view only the data it reads (a field, not the whole
  model value), so it redraws only when that changes. Pass a collection
  element to its row view as the element, not as an index. Bindings go
  through key paths (`$model.items[id]`, a subscript on the model), not
  `Binding(get:set:)`: a closure binding cannot be compared and redraws on
  every update.
- **Side effects.** `.onChange(of:)` and `.task(id:)` make the view depend
  on the value they watch. When the body is large, move the modifier with
  its dependency into a small view of its own.
- **Structure.** A section of a screen is its own `View` struct, not a
  computed property or a `func` returning `some View`: a struct is compared
  and skipped when its inputs did not change. Keep `init` cheap (no
  sorting, formatting or I/O); it runs on every parent redraw. No `Group`
  around a single child.
- **ForEach and List.** Identity comes from the data (`Identifiable`, or a
  stable `id:` key path), never from an index, an offset of
  `.enumerated()` or `UUID()` made in `body`; a wrong identity loses state
  and animations. Sort and filter before the `ForEach`, in the model, not
  inline. A `List` row is one view (no top-level `if` without `else`, no
  `AnyView`) so `List` stays on its fast path.
- **Modifiers.** Vary a modifier's argument with a ternary
  (`.foregroundStyle(isOn ? .red : .primary)`), never an `if`/`else` view
  or an `.if` modifier, which swaps the view's identity. `AnyShapeStyle` is
  fine when the two styles have different types.
- **Environment and focused values.** Declare them with `@Entry` and a
  stable default (a literal, `nil`, an enum case, a `static let`), never a
  fresh object or `Date()`. Never store a closure in a custom key: it
  cannot be compared, so every reader redraws; store the data and let the
  model act on it (`BrowserTarget` in `Shortcuts.swift`). Remove an
  `@Environment` a view no longer reads.
- **macOS look.** System controls, fonts, semantic colours and SF Symbols
  by their real names. `Form` with `.formStyle(.grouped)` for settings,
  `ContentUnavailableView` for empty states. Liquid Glass comes from the
  system: `.glassEffect` only on a custom floating control, never behind
  content. Every menu command has a keyboard shortcut (`Shortcuts.swift`),
  every icon-only button a `.help` and an accessibility label.

## Text and languages

The app speaks Dutch (the development language), English, German and
French, through `Pullwatch/Pullwatch/Localizable.xcstrings` and one catalog
per PullwatchKit module with text (`PullwatchCore`, `PullwatchGitHub`).

- SwiftUI literals (`Text("…")`, `Button("…")`) localise by themselves; the
  keys are the Dutch text. A `String` variable passed to `Text` does not, so
  types that carry text for a view hold a `LocalizedStringResource`.
- `String(localized:)` only where a `String` is required (notifications,
  messages kept in a model).
- In a package module, text names its module's bundle
  (`bundle: .localizedCore`, `bundle: .localizedGitHub`), which is
  `#bundle` in the language the app chose; without it the lookup goes to the
  app's catalog and finds nothing. A new module with text gets its own
  catalog, helper (`Bundle.localized(#bundle, for:)`) and an entry in
  `LocalizationTests.catalogs`, and every key an `nl` entry so the bundle
  has an `nl.lproj`.
- A sentence is one string, never assembled from pieces; counts get plural
  variations; dates, numbers and lists use format styles
  (`.formatted(.list(type: .and))`), so each language gets its own grammar.
- `.leading` and `.trailing`, never `.left` and `.right`.
- **Every new string gets all four languages** before the commit
  (`bash scripts/dev/sync-strings.sh`, then fill in en, de and fr);
  `LocalizationTests` fails otherwise.

## Tests

- **Swift Testing** (`@Suite`, `@Test`, `#expect`, `#require`); XCTest only
  for the UI tests, which need XCUIAutomation. Logic goes in a PullwatchKit
  module and is tested in that module's target
  (`PullwatchKit/Tests/<Module>Tests`); `Pullwatch/PullwatchTests` checks the
  built app (hosted, no polling).
- A suite is a `struct`; its `init` builds the fixtures, and Swift Testing
  makes a fresh instance per test, so tests cannot leak state into each
  other. Use a `final class` or `actor` only when the suite needs `deinit`,
  and `@Suite(.serialized)` only for shared outside state (the Keychain).
- One input per case: a loop over inputs inside a test becomes
  `@Test(arguments:)`, so a failure names the input and the others still run.
- `try #require` for what the rest of the test needs, instead of `guard`
  plus `Issue.record` and `return`. Never turn a `#require` into an
  `#expect`: the test would go on with a bad value.
- `#expect(throws: SomeError.case)` for the exact error,
  `await confirmation { … }` for a callback that must happen, never a
  `Task.sleep` that hopes it did.
- A new test whose name reads as a sentence uses a raw identifier:
  ``@Test func `Retries after a rate limit`()``. Existing names stay, so a
  rename never hides a change.
- When a failing `#expect` on a large model value prints too much, conform
  the type in the test target to `CustomTestReflectable` (ST-0022) and
  return a `Mirror` of the fields that matter, or to
  `CustomTestStringConvertible` for a one-line description.
- Hunt a flaky test by repeating it, not by rerunning CI:
  `swift test --filter <Test> --maximum-repetitions 100 --repeat-until fail`
  or `xcodebuild test … -only-testing:<id> -test-iterations 100
  -run-tests-until-failure`.
- Network tests go through `MockHTTPClient`, process tests through
  `MockProcessRunner`, secrets through `InMemorySecretStore`, time through
  `TestClock` (all `package` in `PullwatchKit/Tests/PullwatchTestSupport`);
  never the real GitHub, Azure DevOps, GitLab, `gh`, `az` or `glab`.
- Never weaken, skip or delete a test to make a build pass.

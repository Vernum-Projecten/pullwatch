# CLAUDE.md

Pullwatch is a macOS menu-bar app by Alessandro Torrisi that notifies about
new pull requests (Azure DevOps and GitHub) and tags, keeps a searchable
history, and checks repositories for outdated runtimes, packages and known
vulnerabilities. Apache-2.0. `README.md` describes every feature; the design
of each part is in `docs/superpowers/specs/` and its plan in
`docs/superpowers/plans/` (both Dutch). Swift is written as
`.claude/rules/swift.md` says.

## Where the work happens

- `upstream` = `alessandro823/pullwatch`, Alessandro's repository and the
  source of truth. We have read access only.
- `origin` = `Vernum-Projecten/pullwatch`, our fork. Branches, issues,
  their relations and pull requests all live here: each change merges into
  the fork's `main` through a pull request in the fork
  (`gh pr create --repo Vernum-Projecten/pullwatch --base main`).
- **No pull request goes to upstream until all our work is done.** Then the
  fork's `main` goes to Alessandro as one combined pull request. Never open
  a pull request against `alessandro823/pullwatch` before the owner says so.
- `gh repo set-default Vernum-Projecten/pullwatch` once per clone, so `gh`
  and `scripts/gh/*` act on the fork, not on upstream.
- When Alessandro pushes new work: `git fetch upstream`, then merge
  `upstream/main` into the fork's `main` through a pull request in the fork,
  so the final pull request stays mergeable.

## Repository map

- `Pullwatch/`: the app. `Pullwatch.xcodeproj` (committed; synchronized
  folders, so adding a file needs no project edit; shared scheme
  `Pullwatch`). Settings: `App.xcconfig` (version, build number, bundle id),
  included by `Debug.xcconfig` (the test GitHub App "TEST Pullwatch" of
  Vernum-Projecten; then the optional, git-ignored `Local.xcconfig`) and
  `Release.xcconfig` (the maintainer's GitHub App). Never put the test app in
  `Release.xcconfig`.
  `Pullwatch/Pullwatch/App/`: state and wiring. `PullwatchApp.swift` (four
  scenes: the `MenuBarExtra`, the main `Window`, the welcome `Window` that
  opens by itself on a first launch via `defaultLaunchBehavior`, and the
  `Settings` scene; `appModels(_:)` puts every model in each scene's
  environment), `AppDelegate` (starts the model, except as a test host),
  `WindowPresence` (shows the Dock icon while one of those windows is open),
  `AppModel.swift` (the composition root: creates the models
  once, starts the loop, and keeps the intents that span models), and one
  `@Observable` model per job, each read by views from the environment:
  `AccountsModel` (config, accounts, Keychain, GitHub sign-in),
  `HistoryModel` (history, read state, menu lists, Dock badge),
  `PollingModel` (one poll, statuses, refetch), `VersionsModel` (the version
  check, the stored report and the one the screens show without the data of
  sources that are off), `OverviewModel` (repo summaries and sidebar),
  `NotificationsModel`, `UpdatesModel` and `AppRouter` (windows, sidebar,
  paths, filters; `show(_:)` opens a window or section); `AppServices` holds
  the stores, the engine and the notifier,
  `GitHubSignIn` (the GitHub sign-in flow), `Updater` (Sparkle 2: updates in
  the app when the build has `SPARKLE_PUBLIC_ED_KEY`), `FakeGitHub` and
  `FakeWorld` (debug only: a GitHub without network and its repositories, for
  the UI tests and the camera tours), `Notifier` and `NotificationGlyph`,
  `Shortcuts` (commands; ⌘O reads the `browserTarget` focused value),
  `AppLanguage` (the language choice in General: follow macOS or a fixed
  language through `AppleLanguages`, applied by relaunching), and the models
  of single screens (`RepoPage`, `PackageRows`, `RepoBriefs`, `TagFilter`,
  `RepoVersions+Clipboard`).
  `Pullwatch/Pullwatch/Views/`: only draws. `MenuBarLabel` (the menu-bar
  icon; it opens the windows the model asks for through
  `AppRouter.windowRequest`), `AboutView` (the About window), `MenuView`
  (the menu-bar popover), `MainView` (sidebar: PRs, Tags, Repos, Versions,
  Statistics), `SettingsView` (the Settings window: Accounts, Notifications,
  General with the language choice, and Sources), `SourcesSettingsView` (the Sources tab:
  every outgoing connection, switches for the data sources, **Copy
  overview**), `AccountEditor`, `OnboardingView` with `OnboardingSteps`, the
  section views, and `Components/` (shared pieces: `SourceStatusParts` with
  the "Niet gecontroleerd: bron … staat uit" texts, `Pasteboard`,
  `CopyButton`, `AgentBriefButton` and `AgentBriefMenu`, the vulnerability
  table and its cells). The repository page is `RepoDetailView` with a file
  per tab (`RepoOverviewTab`, `RepoCheckTab`, `RepoPackagesTab`,
  `RepoSecurityTab`), `RepoInspector` and `RepoDetailToolbar`; it puts the
  agent briefs behind the Overview headings and in the toolbar's More menu
  (`RepoBriefs`, one per section). `Localizable.xcstrings`
  holds the app's text in nl, en, de and fr; `Info.plist` holds only what the
  generated one cannot (`CFBundleLocalizations`). `AppIcon.icon` is the
  app icon, an Icon Composer bundle (`icon.json` plus one SVG per layer in
  `Assets/`); edit it in Icon Composer or by hand, and check it with
  `ictool` (inside Icon Composer) in light, dark, tinted and clear.
  `Pullwatch/PullwatchTests/`: hosted Swift Testing suites for the built app
  (bundle id, menu-bar app, languages, translations complete, SF Symbols).
  While XCTest hosts the app, `AppDelegate` does not start polling.
  `Pullwatch/PullwatchUITests/`: XCUITests that launch the app with an empty
  data folder (`-PullwatchDataDirectory <dir>`, read by `AppPaths`) and
  tokens in memory only (`-PullwatchEphemeralSecrets`, also implied by
  `-PullwatchFakeGitHub`; `SecretStores`), and walk
  the first-run onboarding in Dutch and English. In debug builds
  `-PullwatchSnapshotDirectory <dir>` makes the app draw its own windows to
  PNG (`App/SnapshotCamera.swift`), no Screen Recording permission needed;
  with `-PullwatchFakeGitHub YES -PullwatchFakeData YES
  -PullwatchSnapshotTour YES` and a `config.json` with a GitHub account in
  the data folder it walks every screen of the main window
  (`App/SnapshotTour.swift`), and `-PullwatchOnboardingTour YES` every step of
  the welcome window. Comparing the PNGs of two builds pixel by pixel shows a
  refactor changed nothing; only clocks and time stamps differ.
- `PullwatchKit/`: the local Swift package (`Package.swift`), everything
  without a window, in six modules under `Sources/`. The names start with
  `Pullwatch` so a module never shares its name with a type in it.
  `PullwatchCore/`, by area, with no provider API code: `Model/` (models,
  `AppConfig`), `Providers/` (the `PRProvider` and `TokenSource` protocols,
  `ProviderError`, `StaticTokenSource`), `Polling/` (`PollEngine`, backoff,
  notification planning, filters, seen state), `History/` (history,
  statistics, repo overview), `Versions/` (the version and vulnerability
  checks: stack and dependency detection, package registries, end-of-life,
  OSV; `DataSource` is the catalogue of data sources that can be switched
  off, vulnerability and version sources and the CI checks of pull
  requests, `SourcesOverview` lists every connection for the Sources tab
  and its copied overview, `AgentBrief` turns a section of the repository
  page into a Markdown brief for an AI agent), `Updates/` (`UpdateChecker`, `Appcast`, `UpdateFeed`), `Support/` (HTTP, processes, JSON
  store, Keychain and `SecretStores`, logging, localisation). `PullwatchGitHub/`:
  `GitHubProvider` (github.com, GitHub Enterprise Server and GHE.com through
  `GitHubEndpoints`), the GitHub App device flow and token store
  (`GitHubAppAuth`), the `gh` token source and `GhCLIAccounts`.
  `PullwatchAzureDevOps/`: `AzureDevOpsProvider` and the `az` token source.
  `PullwatchGitLab/`: `GitLabProvider` (gitlab.com and self-managed, REST v4)
  and the `glab` token source. Each provider has the same layout: the
  provider itself (accounts, repositories, pull requests), `+Tags`, `+HTTP`,
  one file of DTOs, and a `+Area` file per further area (co-authors, files,
  checks, security, extra repositories, merge queues and trains).
  `PullwatchProviders/`: `ProviderFactory`, the only module that knows every
  provider. `PullwatchMCP/`: the MCP server for coding agents, on the
  official MCP Swift SDK (`modelcontextprotocol/swift-sdk`, pinned to an
  exact release in `Package.swift`): `MCPToolRegistry` holds the `MCPTool`s
  (an `MCPSchema` for input and output, a handler returning an
  `MCPToolResult`), `PullwatchMCPServer.start` serves them as an SDK `Server`
  named Pullwatch on any SDK `Transport`, wrapped in `MCPBoundedTransport`
  (`MCPLimits`: message size and nesting). The app does not link it yet.
  `PullwatchKit/Package.resolved` and the project's `Package.resolved` pin
  the same versions; a dependency change updates both. Every provider also reads the repositories a person adds by
  hand (`Account.extraRepos`, `PRProvider.checkRepository`), with an
  anonymous fallback for public repositories on github.com and gitlab.com
  only. The app links `PullwatchCore`, `PullwatchGitHub` (the sign-in
  screens) and `PullwatchProviders`. Only what another module or the app
  uses is `public`; what only the package's own modules share is `package`.
  A module with text has its own `Localizable.xcstrings` and its own
  `Bundle.localized…` helper (`Support/Localization.swift`).
  `Tests/`: one Swift Testing target per module (`PullwatchCoreTests`,
  `PullwatchGitHubTests`, `PullwatchAzureDevOpsTests`,
  `PullwatchGitLabTests`, `PullwatchProvidersTests`, `PullwatchMCPTests`),
  and `PullwatchTestSupport` with the shared
  `MockHTTPClient`, `MockProcessRunner`, `InMemorySecretStore`, `TestClock`
  (starting at `Date.testStart`), `CLILocator.homebrew` and `.nothing`,
  `expectCalledHostsAreListed` and fixtures; a helper only one target needs
  goes in that target's `Support/`.
- `docs/setup.md`: everything the maintainer configures outside the code
  (signing, the GitHub App, the release secrets), each with its steps;
  `docs/github-app.md`: the GitHub App for **Sign in with GitHub**. Keep both
  in step with the code. `docs/superpowers/`: Alessandro's design specs and
  plans (Dutch).
- `.github/workflows/`: `ci.yml` (every pull request and push to `main`:
  shellcheck and actionlint, the changelog fragment guard, `swift test`, `xcodebuild test` with the unit
  and UI tests, `release.sh --unsigned` with a universal check; no secrets)
  and `release.yml` (a `v*` tag: check, sign, notarise, package, draft
  release). `.github/actionlint.yaml` names the `xcode-27` runner label.
  `CHANGELOG.md` (Keep a Changelog) gives each release its notes, assembled
  from the fragments in `changelog.d/`.
  `docs/releasing.md`: the release procedure and its Actions secrets.
- `scripts/release/release.sh [--unsigned]`: Release build (universal), and
  with a Developer ID also signing, notarisation and stapling of the app
  and the DMG; local (notarytool profile) and in `release.yml` (API key in
  `NOTARY_KEY_FILE`). `package.sh <app> <version> <out-dir>` makes
  `Pullwatch-<version>.dmg` (the install window: background from
  `dmg-background.swift`, icons placed by Finder through AppleScript) and
  `Pullwatch-<version>.zip`. The icon positions in both files must match.
  `check-version.sh vX.Y.Z` (tag, `MARKETING_VERSION`, build number and
  changelog agree, no fragment left), `notes.sh vX.Y.Z` (the changelog
  section), `changelog.sh` (`--check`, `--preview`, `--assemble` of the
  fragments), `protect-tags.sh` (the `v*` tag ruleset), `verify-update.swift`
  (checks the signed appcast and zip against the app's public key).
- `scripts/checks/changelog-guard.sh`: the changelog fragment guard CI runs
  on every pull request (`--self-test` proves it). `changelog.d/`: the
  fragments of the next release and their format (`README.md`).
- `scripts/gh/`: tracker helpers (copied from FerroLICENCE): `fields.sh`
  (issue type, Priority, Effort), `rel.sh` (sub-issues and blocked-by),
  `labels.sh` (the label set). `scripts/dev/xcode-skills.sh` exports
  Apple's Xcode agent skills into `.claude/skills/`; `sync-strings.sh` (with
  `catalog-tidy.py`) writes the extracted text into the String Catalogs.
- `.githooks/`: `pre-commit` (refuses private keys, tokens, certificates)
  and `commit-msg` (strips AI attribution). Install once per clone:
  `git config core.hooksPath .githooks`.

## Hard rules

- **Never push to upstream.** Push to `origin` and open a pull request in
  the fork; the Claude Bash hook refuses a push to upstream.
- **No secrets in the tree.** Tokens live in the Keychain; the Developer ID
  certificate, the notarisation credentials and Sparkle's private
  key are Alessandro's and live in Actions secrets and his Keychain. The
  pre-commit hook and the Claude `protect_secrets.sh` hook refuse them.
- **The bundle id stays `nl.torrisi.pullwatch`.** Changing it loses every
  user's settings, notifications permission and Keychain tokens.
- **The app supports macOS 26.6 and later, universal (Apple Silicon and
  Intel).** One deployment target, set at the project level and in
  `PullwatchKit/Package.swift`; never per target.
- **Every user-facing string in all four languages** (nl, en, de, fr).
- **Never weaken, skip or delete a test** to make a build pass.
- **No AI attribution in commits, PRs or issues.** No `Co-authored-by`, no
  "Generated with", no robot emoji. The `commit-msg` hook strips it and the
  Claude Bash hook refuses the command.
- **A full makeover is allowed.** Refactor, rewrite, restructure and restyle
  any part of the app, Alessandro's code included, when it makes Pullwatch
  better; do not ask first. Keep each pull request about one thing, and keep
  Dutch comments and Xcode's formatting.
- **Prose has no AI tells**, in UI text, docs, commits and PRs: no em dashes,
  no middle dot "·" as a separator, no "not X but Y", no buzzwords. Write a
  phrase ("octo op GitHub"), use two lines, or separate labels instead.

## Gates (run before every commit)

The same as CI (`.github/workflows/ci.yml`), warnings as errors:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path PullwatchKit -Xswiftc -warnings-as-errors
xcodebuild test -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch \
  -destination 'platform=macOS' SWIFT_TREAT_WARNINGS_AS_ERRORS=YES     # unit and UI tests
shellcheck scripts/*/*.sh .claude/hooks/*.sh .githooks/*
actionlint
bash scripts/release/changelog.sh --check
bash scripts/dev/sync-strings.sh && git diff --exit-code -- '*.xcstrings'
```

The UI tests take over the screen. On a Mac someone is working on, run
`-only-testing:PullwatchTests` and `xcodebuild build-for-testing` instead,
and let CI run the UI tests.

A UI change is looked at before it is called done: run the app (⌘R in Xcode),
open every screen it touches in light and dark mode, in Dutch and English,
at the smallest window size, and check for truncation and overflow. For the
onboarding, `TEST_RUNNER_PULLWATCH_SHOTS=<dir> xcodebuild test … -only-testing:PullwatchUITests`
saves every step as PNG per language. UI tests quit a running Pullwatch
(same bundle id) first.

After changing user-facing text, `bash scripts/dev/sync-strings.sh` writes the
new keys into every String Catalog (xcodebuild alone does not); add the
English, German and French for each before committing. `LocalizationTests`
fails while an entry misses a language, and CI's "String Catalogs in step
with the code" job fails when the script would still change a catalog.

## Formatting

Xcode's indentation (Ctrl-I), 4 spaces, as the code is now. There is no
`swift format` gate: FerroLICENCE's configuration would rewrite 779 lines in
43 files. Adopting a formatter is Alessandro's call.

## Workflow

The tracker is the fork's GitHub Issues (`Vernum-Projecten/pullwatch`). The
type (Bug, Feature, Task), the priority (Urgent, High, Medium, Low) and the
effort (High, Medium, Low) are GitHub's native issue type and the
Vernum-Projecten organisation's `Priority` and `Effort` issue fields, never
labels. File an issue with `scripts/gh/fields.sh new <type> <priority>
<effort> <gh issue create args>`, never a bare `gh issue create`. `Low` is
one sitting, `Medium` one pull request, `High` more than one. A Task carries
exactly one work-kind label (`documentation`, `chore`, `refactor`, `perf`,
`test`, `ci`); a Bug and a Feature carry none. Epics are parents
(`scripts/gh/rel.sh parent <child> <epic>`); order is `rel.sh blocked-by`.
Read an issue with `gh issue view <n> --json title,body,comments`.

A change lands in the fork's `main` through a PR in the fork, on a
conventional-type branch (a Bug is `fix/`,
a Feature `feat/`, a Task its work kind), with conventional commit subjects
in English (`feat: …`, `fix: …`), as upstream's history does. The PR body
says what changed and why, and links the fork issue. Prefer what
FerroLICENCE (`~/RustroverProjects/FerroLICENCE`) already does and has
proven (icon, DMG window, Sparkle updater, CI, release lane) over designing
it again; each issue lists the files to copy.

## Releases

A tag `vX.Y.Z` on `main` runs `.github/workflows/release.yml`: it checks
that the tag, `MARKETING_VERSION` and a dated `CHANGELOG.md` section agree,
imports the Developer ID of Code24 BV from Actions secrets into a keychain
of its own, runs `scripts/release/release.sh` (sign, notarise, staple,
package), signs `appcast.xml` for the zip with Sparkle's key and checks
it against the app's public key, and attaches the DMG, zip and appcast to
a draft release with the changelog section as notes (a tag
`vX.Y.Z-beta.N` makes a pre-release on Sparkle's `beta` channel).
Alessandro checks the draft and publishes it; the app reads the latest
release's appcast once a day and Sparkle installs the update (without a
public key in the build, `UpdateChecker` shows a download button). The secrets are his and
exist only in his repository: in the fork the lane stops at once and names
the missing ones. `docs/releasing.md` has the procedure and the secret
names. `release.sh` on his Mac (notarytool profile `pullwatch`) still makes
the same files. Every change worth noting adds a fragment under
`changelog.d/` (`changelog.d/README.md`), never a line under `[Unreleased]`
in `CHANGELOG.md`: the `changelog` CI job (`scripts/checks/changelog-guard.sh`)
fails a pull request that writes there, and one that changes `Pullwatch/` or
`PullwatchKit/Sources/` without a fragment unless it has the `no-changelog`
label. The release branch runs `scripts/release/changelog.sh --assemble
X.Y.Z YYYY-MM-DD` before the tag.

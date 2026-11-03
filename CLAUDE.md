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
  `Pullwatch`), `App.xcconfig` (version, build number, bundle id).
  `Pullwatch/Pullwatch/App/`: state and wiring. `PullwatchApp.swift` (the
  `MenuBarExtra`, the main `Window`, the Dock-icon switch), `AppModel.swift`
  (the one `@Observable` model: polling loop, config, history, update check),
  `Notifier`, `Shortcuts`, `AppLanguage`. `Pullwatch/Pullwatch/Views/`: only
  draws. `MenuView` (the menu-bar popover), `MainView` (sidebar: PRs, Tags,
  Repos, Versions, Statistics, Settings), `SettingsView`, `AccountEditor`,
  the section views, and `Components/` (pills, rows). `Localizable.xcstrings`
  holds the app's text in nl, en, de and fr; `Info.plist` holds only what the
  generated one cannot (`CFBundleLocalizations`). `Assets.xcassets` has the
  icon (drawn by `scripts/make-icon.swift`; being replaced, #4).
  `Pullwatch/PullwatchTests/`: hosted Swift Testing suites for the built app
  (bundle id, menu-bar app, languages, translations complete, SF Symbols).
  While XCTest hosts the app, `AppDelegate` does not start polling.
- `PullwatchKit/`: the local Swift package (`Package.swift`) with the
  `PullwatchCore` module, everything without a window, by area under
  `Sources/PullwatchCore/`: `Model/` (models, `AppConfig`), `Providers/`
  (`PRProvider`, GitHub, Azure DevOps, `ProviderFactory`, token sources),
  `Polling/` (`PollEngine`, backoff, notification planning, filters, seen
  state), `History/` (history, statistics, repo overview), `Versions/` (the
  version and vulnerability checks: stack and dependency detection, package
  registries, end-of-life, OSV), `Updates/` (`UpdateChecker`), `Support/`
  (HTTP, processes, JSON store, Keychain, localisation).
  `Tests/PullwatchCoreTests/`: its Swift Testing suites; `Support/` has
  `MockHTTPClient` and `MockProcessRunner`.
- `scripts/release/release.sh [--unsigned]`: Release build (universal), DMG,
  and with a Developer ID also signing, notarisation and stapling.
- `scripts/gh/`: tracker helpers (copied from FerroLICENCE): `fields.sh`
  (issue type, Priority, Effort), `rel.sh` (sub-issues and blocked-by),
  `labels.sh` (the label set). `scripts/dev/xcode-skills.sh` exports
  Apple's Xcode agent skills into `.claude/skills/`.
- `.githooks/`: `pre-commit` (refuses private keys, tokens, certificates)
  and `commit-msg` (strips AI attribution). Install once per clone:
  `git config core.hooksPath .githooks`.

## Hard rules

- **Never push to upstream.** Push to `origin` and open a pull request in
  the fork; the Claude Bash hook refuses a push to upstream.
- **No secrets in the tree.** Tokens live in the Keychain; the Developer ID
  certificate, the notarisation credentials and (later) Sparkle's private
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
- **Stay in Alessandro's style.** Dutch comments, Xcode's formatting, no
  drive-by reformatting or renames in a pull request about something else.
  Bigger changes to how he works (build system, formatter, CI) are proposed
  in an issue and agreed before the pull request.
- **Prose has no AI tells**: no em dashes, no "not X but Y", no buzzwords.

## Gates (run before every commit)

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path PullwatchKit                      # PullwatchCore
xcodebuild test -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch -destination 'platform=macOS'
shellcheck scripts/*/*.sh .claude/hooks/*.sh .githooks/*
```

A UI change is looked at before it is called done: run the app (⌘R in Xcode),
open every screen it touches in light and dark mode, in Dutch and English,
at the smallest window size, and check for truncation and overflow.

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

Today: `scripts/release/release.sh` on Alessandro's Mac (Developer ID of Code24 BV,
notarytool profile `pullwatch`) builds a signed, notarised DMG that he
uploads to a GitHub release `vX.Y.Z`. The app's `UpdateChecker` reads
`releases/latest` once a day. The release lane moves to CI with Sparkle
updates in #8 and #9.

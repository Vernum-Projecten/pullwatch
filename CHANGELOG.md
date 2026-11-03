# Changelog

All notable changes to Pullwatch are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the app
follows [Semantic Versioning](https://semver.org/). Each released section
becomes the notes of its GitHub release (`scripts/release/notes.sh`);
`docs/releasing.md` describes how a release is cut.

## [Unreleased]

### Added

- **More lockfiles for the package and vulnerability check**: `yarn.lock`
  (classic and Berry), `pnpm-lock.yaml` (v6 to v9), NuGet
  `packages.lock.json` and `Gemfile.lock`, each install with its workspace,
  direct or transitive, runtime, dev or optional, and the chain it comes
  through. Ruby gems get their latest version from rubygems.org.
- **Where each package and vulnerability comes from.** The repository page
  lists packages per workspace in Direct, Transitive and Dev groups, with
  every version on its own row and the chain it comes through ("via
  express → body-parser"). A vulnerability shows once per advisory with
  Direct or Via express, Dev only and what to update, and the count counts
  advisories. Versions shows each repository's versions per workspace and
  marks repositories that only have a package transitively. New CVE
  notifications and the copied repository text say direct or via which
  package.
- **Mark as read or unread in the main window.** Right-click a PR or tag
  (or press ⇧⌘U, as in Mail), mark everything in the list as read with the
  toolbar button or ⌘K, and see unread items by their blue dot. The menu's
  rows have Mark as Read and Mark as Unread too.
- **Welcome window on first launch.** It walks through adding an account
  and asks for permission to send notifications by itself.
- **Sign in with GitHub** through the Pullwatch GitHub App (device flow):
  the code goes on the clipboard, the app waits for the approval and the
  installation, and lists the accounts and organisations where it is
  installed. Debug builds use the test app "TEST Pullwatch".
- **Profile pictures** for GitHub accounts.
- **An install window in the disk image**: the app and a link to
  Applications on a background with an arrow.
- **Log level** in Settings, General, and a button that opens Console.
- **CI and a release workflow.** Every pull request runs the package tests,
  the app's unit and UI tests and an unsigned release build with the disk
  image. A tag `vX.Y.Z` builds, signs, notarises and packages the release
  and attaches it to a draft GitHub release.

### Changed

- Built with Swift 6.4 (tools version 6.4) with approachable concurrency,
  the app on the main actor by default, and the ExistentialAny,
  MemberImportVisibility, NonisolatedNonsendingByDefault and
  InferIsolatedConformances features; CI treats warnings as errors.
- **Choose per repository what to follow.** The account's repository list
  has three columns again, PRs, Tags and Merged, with an "all" checkbox
  per owner and column. Notifications per kind are in a repository's
  context menu. New repositories can follow nothing, PRs, or PRs and tags.
- A new app icon in Icon Composer format.
- Account names follow the organisation.
- The project is a committed Xcode project with settings in `.xcconfig`
  files and a folder per area.
- `scripts/release/release.sh` notarises and staples the app before
  packaging it, so the app in the zip carries its own ticket too.
- Following a repository follows its PRs and tags; a new account follows
  both for repositories it finds later. Existing settings stay as they are.
- Progress has one place: a bar at the bottom of the main window for the
  first sync, fetching the history again and the version check, with Stop
  where that is safe. Toolbar buttons stay put while their job runs, and the
  menu shows a small spinner next to Refresh during a poll.
- The version check keeps every install of a package: its version, its
  workspace, direct or transitive, runtime, dev or optional, and the
  shortest chain from a direct package. A package used in two versions is
  no longer folded into the oldest one, and each vulnerability is listed
  for every install it hits. Older saved checks still load.

### Fixed

- The main window fills in after adding an account: existing tags within
  the history retention appear under Tags (read, without notifications),
  newly followed repositories get their version check right after the poll
  that first sees them, and empty lists say they are fetching.
- Opening Pullwatch while it runs shows the main window.
- Adding an account no longer leaves an empty row behind: nothing is saved
  until the account has an organisation, and empty accounts from older
  versions are removed at launch.
- A GitHub organisation where Pullwatch was just installed, and a PR that
  was just opened, show up at once instead of up to a minute later.
- Reloading the repositories of an account keeps the list in place, and
  Reload works again after a failed load.
- Notifications say "1 new PR" instead of "1 new PRs", in every language,
  and show the severity of a vulnerability in your language.
- Tokens of accounts that no longer exist are removed from the Keychain at
  launch, and test runs no longer leave tokens behind.

## [0.5.0] - 2026-11-01

Released by Alessandro Torrisi from the upstream repository
([alessandro823/pullwatch](https://github.com/alessandro823/pullwatch/releases/tag/v0.5.0)),
before this changelog existed. The fork starts from this version.

### Added

- **Repositories**: a list per project, worst first, with a page per
  repository for its pull requests, the version check, packages with a new
  version and its activity.
- **Statistics**: pull request activity per week, month or year, filtered
  by project, author or repository.
- **Keyboard shortcuts** for the sections, search, refresh, back and open
  in the browser.
- The menu header shows the version number.

### Changed

- The repository overview is calculated once instead of on every screen
  update.

[Unreleased]: https://github.com/Vernum-Projecten/pullwatch/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/alessandro823/pullwatch/releases/tag/v0.5.0

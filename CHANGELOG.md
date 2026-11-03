# Changelog

All notable changes to Pullwatch are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the app
follows [Semantic Versioning](https://semver.org/). Each released section
becomes the notes of its GitHub release (`scripts/release/notes.sh`);
`docs/releasing.md` describes how a release is cut.

## [Unreleased]

### Added

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

- A new app icon in Icon Composer format.
- Account names follow the organisation.
- The project is a committed Xcode project with settings in `.xcconfig`
  files and a folder per area.
- `scripts/release/release.sh` notarises and staples the app before
  packaging it, so the app in the zip carries its own ticket too.

### Fixed

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

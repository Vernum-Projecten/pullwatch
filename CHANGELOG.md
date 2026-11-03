# Changelog

All notable changes to Pullwatch are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the app
follows [Semantic Versioning](https://semver.org/). Each released section
becomes the notes of its GitHub release (`scripts/release/notes.sh`);
`docs/releasing.md` describes how a release is cut. Changes since the last
release wait as fragments in `changelog.d/` until the cut writes them here.

## [Unreleased]

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

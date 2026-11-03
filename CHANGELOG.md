# Changelog

All notable changes to Pullwatch are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the app
follows [Semantic Versioning](https://semver.org/). Each released section
becomes the notes of its GitHub release (`scripts/release/notes.sh`);
`docs/releasing.md` describes how a release is cut. Changes since the last
release wait as fragments in `changelog.d/` until the cut writes them here.

## [Unreleased]

## [0.6.0] - 2026-11-03

### Thank you, Ruben

This release would not exist in this form without **Ruben Talstra** (@rubentalstra). He created the fork [Vernum-Projecten/pullwatch](https://github.com/Vernum-Projecten/pullwatch), where nearly everything in 0.6.0 was built, and his input and ideas shaped where Pullwatch is going:

- **More places to follow:** GitLab (gitlab.com and your own server), GitHub Enterprise Server and GHE.com, and single repositories you add yourself.
- **Sign in with GitHub** through the Pullwatch GitHub App, a welcome window that walks you through your first account, and profile pictures and co-authors in the pull request list.
- **A much deeper version check:** every install of every package with where it comes from, more lockfiles (yarn, pnpm, NuGet, Gemfile), version ranges per ecosystem, what blocks an update, and GitHub's advisories, code scanning and secret scanning.
- **A new main window** with navigation, search, tables, mark as read or unread, and GitHub's icons for pull requests.
- **Updates inside the app** with Sparkle, a signed and notarised release lane, CI on every pull request, and a proper install window in the disk image.

Thank you, Ruben, for the time, the care and the many good ideas. 🙏

### Added

- **Sources** in Settings: every source Pullwatch takes vulnerability and
  version information from (OSV.dev, the GitHub Advisory Database, GitHub
  security, Azure DevOps Advanced Security, the package registries,
  endoflife.date and swift.org), with what it provides, the address it
  calls and a switch to turn it off, plus every other connection Pullwatch
  makes (your accounts' servers, Sign in with GitHub, profile pictures and
  the update check). **Copy overview** puts the list on the clipboard, to
  share with whoever asks where the data comes from. A source that is off
  is never called, and wherever that leaves something unchecked Pullwatch
  says so ("Not checked: source OSV.dev is off") instead of "no
  vulnerabilities" or "up to date".
- **Copy a section for an AI agent.** Every heading on a repository's page
  has a copy button that puts that section on the clipboard as an English
  Markdown brief: packages with their versions, files, ranges and what
  blocks an update; vulnerabilities with their ids and fixed versions;
  security alerts; pull requests; each with a task line an agent can act on.
- **Language** in Settings, General: follow macOS (the default) or choose
  Nederlands, English, Deutsch or Français, with a button to restart
  Pullwatch in that language.
- **Welcome window on first launch.** It walks through adding an account
  and asks for permission to send notifications by itself. Its headings are
  announced by VoiceOver and its text wraps or scrolls at larger sizes (Vernum-Projecten/pullwatch#5).
- **An install window in the disk image**: the app and a link to
  Applications on a background with an arrow (Vernum-Projecten/pullwatch#7).
- **CI and a release workflow.** Every pull request runs the package tests,
  the app's unit and UI tests and an unsigned release build with the disk
  image. A tag `vX.Y.Z` builds, signs, notarises and packages the release
  and attaches it to a draft GitHub release (Vernum-Projecten/pullwatch#8).
- **Updates inside the app** with Sparkle. When a new version is out, the
  menu and the notification offer **Install**: Pullwatch shows the release
  notes, downloads the update, checks its signatures, installs it and
  restarts. Settings, General, Updates adds **Install updates
  automatically** (download in the background, install when you quit) and
  **Include test versions** (pre-releases). An update is only offered on a
  macOS version it runs on (Vernum-Projecten/pullwatch#9).
- GitLab accounts, on gitlab.com or your own server (https only): Pullwatch follows the
  merge requests, tags and releases of the groups (with their subgroups) and users you
  choose, shows who worked on a merge request, and runs the version and vulnerability check
  on GitLab repositories. Sign in with a personal access token with the `read_api` scope or
  with the GitLab CLI (`glab auth login`). Add one in the welcome window or under
  Settings, Accounts (Vernum-Projecten/pullwatch#10).
- GitHub Enterprise accounts, on GitHub Enterprise Server or your enterprise's subdomain on
  GHE.com (https only): choose GitHub Enterprise on the GitHub card in the welcome window or
  in the add menu under Settings, Accounts, and enter your server. Pullwatch follows pull
  requests, tags and releases there, links to that server and shows its host on the account
  card. Sign in with a personal access token made on the server or with the GitHub CLI
  (`gh auth login --hostname`). What a server lacks, such as a repository's own advisories
  on GitHub Enterprise Server, shows as not available instead of an error (Vernum-Projecten/pullwatch#11).
- **Sign in with GitHub** through the Pullwatch GitHub App (device flow):
  the code goes on the clipboard, the app waits for the approval and the
  installation, and lists the accounts and organisations where it is
  installed. Debug builds use the test app "TEST Pullwatch" (Vernum-Projecten/pullwatch#18).
- **Profile pictures** for GitHub accounts (Vernum-Projecten/pullwatch#22).
- **Log level** in Settings, General, and a button that opens Console (Vernum-Projecten/pullwatch#35).
- **Co-authors of a pull request.** The PR list shows the author with the
  people who worked on it (commit authors and `Co-authored-by:` trailers),
  as small avatars and "mona and 2 others"; hover for every name. GitHub
  asks once per new or changed PR in one batched GraphQL request, Azure
  DevOps reads the PR's commits. Statistics can count co-authors too (Vernum-Projecten/pullwatch#49).
- **Where each package and vulnerability comes from.** The repository page
  lists packages per workspace in Direct, Transitive and Dev groups, with
  every version on its own row and the chain it comes through ("via
  express → body-parser"). A vulnerability shows once per advisory with
  Direct or Via express, Dev only and what to update, and the count counts
  advisories. Dependencies shows each repository's versions per workspace and
  marks repositories that only have a package transitively. New CVE
  notifications and the copied repository text say direct or via which
  package (Vernum-Projecten/pullwatch#58).
- **More lockfiles for the package and vulnerability check**: `yarn.lock`
  (classic and Berry), `pnpm-lock.yaml` (v6 to v9), NuGet
  `packages.lock.json` and `Gemfile.lock`, each install with its workspace,
  direct or transitive, runtime, dev or optional, and the chain it comes
  through. Ruby gems get their latest version from rubygems.org (Vernum-Projecten/pullwatch#59).
- **Mark as read or unread in the main window.** Right-click a PR or tag
  (or press ⇧⌘U, as in Mail), mark everything in the list as read with the
  toolbar button or ⌘K, and see unread items by their blue dot. The menu's
  rows have Mark as Read and Mark as Unread too (Vernum-Projecten/pullwatch#63).
- **GitHub's advisories and security alerts.** Each vulnerability shows its
  GHSA id next to the CVE, GitHub's severity with the CVSS score and vector,
  the CWE names and a link to github.com/advisories, on the repository page,
  in the copied text and in notifications; each advisory is fetched once.
  The repository page gets a security section with the repository's own
  published advisories, open code scanning alerts and the number of open
  secrets on GitHub, or the Advanced Security alerts on Azure DevOps. Open
  critical and high alerts count in the Repos findings and health, with an
  optional notification (Settings, General). A kind the app may not read
  yet shows **Needs permission** with a link (Vernum-Projecten/pullwatch#73).
- The version check keeps the range each manifest asks for next to the installed version (npm, yarn
  and pnpm, Composer, PyPI and Poetry, Cargo, NuGet, RubyGems, Go modules and Swift packages), and
  works out per install whether the newest version fits that range, so only the lockfile changes,
  or needs a manifest change, and whether the step is a patch, minor or major update (Vernum-Projecten/pullwatch#83).
- The version check now reads what each package version asks for from its registry (npm,
  Packagist, crates.io, NuGet, RubyGems, PyPI and the Go proxy) and works out what holds an
  update back: a parent package whose range pins it, a peer dependency, or a runtime (Node, PHP,
  Python, Rust, .NET, Ruby, Go) that is older than the new version needs. It also finds the
  newest version you can use right now, and the lowest parent version that lets a fix through.
  Vulnerability fixes use the same rules. Details per version are kept between checks, so a
  check asks the registries for little more than before (Vernum-Projecten/pullwatch#84).
- **Watch single repositories you add yourself.** Under "Other
  Repositories" in an account's repository list, or with "Watch a
  Repository…" in the main window (Go menu and the Repos toolbar), type
  `owner/repo` or paste a github.com or dev.azure.com link. Pullwatch checks
  it first and says in plain words when it can't find or read it. On GitHub
  this works for public repositories of other organisations too, without
  the Pullwatch app installed there; when your account can't read one,
  Pullwatch reads it without signing in and says so (Vernum-Projecten/pullwatch#89).

### Changed

- A new app icon in Icon Composer format (Vernum-Projecten/pullwatch#4).
- `scripts/release/release.sh` notarises and staples the app before
  packaging it, so the app in the zip carries its own ticket too (Vernum-Projecten/pullwatch#8).
- The project is a committed Xcode project with settings in `.xcconfig`
  files and a folder per area (Vernum-Projecten/pullwatch#12).
- Account names follow the organisation (Vernum-Projecten/pullwatch#21).
- Progress has one place: a bar at the bottom of the main window for the
  first sync, fetching the history again and the version check, with Stop
  where that is safe. Toolbar buttons stay put while their job runs, and the
  menu shows a small spinner next to Refresh during a poll (Vernum-Projecten/pullwatch#52).
- **What to follow per repository is simpler.** The account's repository
  list keeps its PRs, Tags and Merged columns with an "all" checkbox per
  owner and column, without a bell in every cell: notifications per kind
  are in a repository's context menu. Merged needs PRs, and New
  Repositories chooses between nothing, PRs, or PRs and tags (Vernum-Projecten/pullwatch#54).
- The version check keeps every install of a package: its version, its
  workspace, direct or transitive, runtime, dev or optional, and the
  shortest chain from a direct package. A package used in two versions is
  no longer folded into the oldest one, and each vulnerability is listed
  for every install it hits. Older saved checks still load (Vernum-Projecten/pullwatch#57).
- Built with Swift 6.4 (tools version 6.4) with approachable concurrency,
  the app on the main actor by default, and the ExistentialAny,
  MemberImportVisibility, NonisolatedNonsendingByDefault and
  InferIsolatedConformances features; CI treats warnings as errors (Vernum-Projecten/pullwatch#66).
- **Pullwatch fetches only what you choose.** A new account follows no
  repositories until you check them, so it never fetches a whole account by
  itself, and a saved account can be turned off with "Fetch This Account"
  without losing its choices (Vernum-Projecten/pullwatch#71).
- The **Versions** section is now called **Dependencies** (Afhankelijkheden),
  since it shows the runtimes, frameworks and packages a repository depends on (Vernum-Projecten/pullwatch#75).
- **Pull request icons like GitHub's.** Open, draft, merged and closed pull
  requests each get GitHub's Octicon in GitHub's colour (green, gray,
  purple, red) in the menu, the PR list, the sidebar and the empty lists,
  and the Closed pill is red now. The PR and tag list shows one narrow icon
  column in place of Kind and Status (hover for "Pull request, merged" or
  "Tag"), with the Release pill next to the tag name. The app icon and the
  menu bar icon use the same `git-pull-request` glyph. The Octicons are MIT
  licensed (see NOTICE) (Vernum-Projecten/pullwatch#77).

### Fixed

- Windows opened from the menu (Settings, About, Open…) come to the front
  instead of opening behind the app you were using.
- Opening Pullwatch while it runs shows the main window (Vernum-Projecten/pullwatch#6).
- Adding an account no longer leaves an empty row behind: nothing is saved
  until the account has an organisation, and empty accounts from older
  versions are removed at launch (Vernum-Projecten/pullwatch#22).
- Tokens of accounts that no longer exist are removed from the Keychain at
  launch (Vernum-Projecten/pullwatch#50).
- A PR that was just opened shows up at once instead of up to a minute
  later: Pullwatch no longer answers from GitHub's one-minute cache (Vernum-Projecten/pullwatch#51).
- The main window fills in after adding an account: existing tags within
  the history retention appear under Tags (read, without notifications),
  newly followed repositories get their version check right after the poll
  that first sees them, and empty lists say they are fetching (Vernum-Projecten/pullwatch#52).
- Notifications say "1 new PR" instead of "1 new PRs", in every language,
  and show the severity of a vulnerability in your language (Vernum-Projecten/pullwatch#53).
- **Tags have an author on GitHub, and releases are shown.** Tags and
  Releases lists each tag with who made it (the person behind a release,
  else the tagger, else the commit author) and its photo, a Release or
  Pre-release label with the release title, and a filter for releases or
  tags without one. A release published after its tag was seen gets one
  notification and updates the same row. A tag without a release opens the
  tag's files instead of a release page that does not exist. GitHub tags
  come from one GraphQL request per ten repositories, and a repository
  where nothing changed costs one small request per fifty. Azure DevOps
  tags without a creator get their tagger or commit author (Vernum-Projecten/pullwatch#74).

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

[Unreleased]: https://github.com/alessandro823/pullwatch/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/alessandro823/pullwatch/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/alessandro823/pullwatch/releases/tag/v0.5.0

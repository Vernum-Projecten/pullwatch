# Pullwatch

A macOS menu bar app that notifies you about new pull requests in Azure DevOps and GitHub, plus new tags and GitHub releases (optional, per repository). It keeps a searchable history and can check your repositories for outdated languages, frameworks and known vulnerabilities.

Available in English, Dutch, German and French: Pullwatch follows the macOS language, or pick one under Settings → General → Language.

## Install

Download the latest `Pullwatch-x.y.z.dmg` from [Releases](https://github.com/alessandro823/pullwatch/releases), open it and drag Pullwatch to Applications.

The app is signed with a Developer ID and notarized by Apple. Universal (Apple silicon and Intel), requires macOS 26.6 or later.

## Build from source

- Xcode 27 (Swift 6.4), macOS 26.6 or later
- Optional: `az` (`az login`) and/or `gh` (`gh auth login`) for CLI authentication

Open `Pullwatch/Pullwatch.xcodeproj` in Xcode and run the **Pullwatch** scheme (⌘R). From the command line:

```bash
swift test --package-path PullwatchKit              # PullwatchKit unit tests
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch build
scripts/release/release.sh --unsigned               # dist/Pullwatch-<version>.dmg and .zip, ad-hoc signed
scripts/release/release.sh                          # signed with Developer ID, notarized and stapled DMG
```

`release.sh` builds the app and hands it to `scripts/release/package.sh`, which makes the disk image and `Pullwatch-<version>.zip` (for the updater). The disk image opens as an install window: the app on the left, Applications on the right, and a background drawn by `scripts/release/dmg-background.swift` that says "Install Pullwatch" with an arrow between them. Finder lays out that window through AppleScript, so the first run asks whether your terminal may control Finder; allow it (System Settings, Privacy & Security, Automation).

The version is `MARKETING_VERSION` (and the build number `CURRENT_PROJECT_VERSION`) in `Pullwatch/App.xcconfig`. A signed release needs a Developer ID Application certificate in the Keychain and a notarytool profile (`xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>`); override with `SIGN_ID=…` and `NOTARY_PROFILE=…`.

The repository holds the app (`Pullwatch/`: the Xcode project, `App/` for state and wiring, `Views/` for the screens) and the `PullwatchKit` Swift package, which the app links and which has the unit tests. Its modules: `PullwatchCore` (models, polling, history, version checks, updates), `PullwatchGitHub` and `PullwatchAzureDevOps` (one per provider), and `PullwatchProviders` (picks the provider for an account).

## Usage

1. Click the menu bar icon → **Instellingen…** (Settings), which opens the settings in the main window.
2. Add an account (Azure DevOps or GitHub), choose PAT or CLI, and test the connection. With the GitHub CLI and several `gh` accounts, pick which one provides the token under **GitHub-account**.
3. Per account, choose which repositories you follow: PR's, Tags and/or Completed (merged PRs).

Tags are off by default. Next to each checkbox is a bell: turn it off to keep following the repository (menu and history) without getting notifications. The bell in the header toggles all visible repositories. Tags are polled every 15 minutes (separate from the PR interval; "Nu verversen" polls tags too). The first tag poll per repository is silent. On GitHub the Tags checkbox follows releases too: a release published for a tag Pullwatch already saw gives one notification ("new release" with its title) and updates the same history row.

Pullwatch checks GitHub once a day for a newer release (Settings → General, also **Check now**); when there is one, you get a notification and a download button in the menu.

While a window (settings, history, versions) is open, Pullwatch shows in the Dock; close the last window and it runs from the menu bar only.

### Main window

**Openen…** in the menu opens the main window. Its sidebar has **PR's**, **Tags en releases**, **Repo's** (repositories), **Afhankelijkheden** (dependencies) and **Statistieken** (statistics), with **Instellingen** (settings) pinned at the bottom; the badges count unread PRs and tags and unseen new versions. Under PR's, Tags and Repo's you can expand a list of projects (Azure DevOps) or owners (GitHub), each with its own unread count; selecting one filters the list and the search to that project. Pullwatch remembers the last section. **Instellingen…** in the menu and ⌘, open the settings there.

### Keyboard shortcuts and jumps

In the main window, the **Ga** (Go) menu has ⌘1–⌘5 for PR's, Tags, Repo's, Afhankelijkheden and Statistieken, ⌘F to search the current section, ⌘R to refresh (the open repository, otherwise poll or check everything), ⌘[ or Esc to go back from a repository page, and ⌘O to open the selection (or the open repository) in the browser.

Jumps between sections: a repository page links to all its PRs and tags, to its statistics, and from a CVE to that package in Afhankelijkheden; in Statistieken a selected author links to their PRs and a repository to its page; in the menu, right-click a PR or tag for **Open repo**.

### History

**PR's** and **Tags en releases** are searchable lists of every detected PR and tag (double-click opens the page). A tag shows who made it (on GitHub the person behind its release, else the tagger, else the commit author) with their photo, and a Release or Pre-release label with the release title; the toolbar filters on all tags, releases only or tags without a release. A tag with a release opens the release, one without opens the files at that tag. Retention (2 months, 6 months, 1 year or forever) is set under Settings → General.

Pullwatch also fetches existing PRs (open, merged and closed) for the history. The first time it goes back to the retention period, with at most 1000 PRs per account; after that the history is updated every 15 minutes (state, title and close date). Fetched PRs don't notify and are marked as read. Changing the repository filter or retention restarts the initial fetch for that account. The GitHub search API has its own limit of 30 requests per minute; when hit, Pullwatch waits it out while PR polling carries on.

Calls to `az` and `gh` time out after 20 seconds.

### Repositories

**Repo's** lists the followed repositories, worst first: red for known CVEs or an end-of-life runtime, orange for a runtime that is behind or packages with a new version, green when current, grey when not checked yet. Clicking one opens its page: open and recent PRs, the check (runtimes and CVEs, see below) and the packages with a new version, plus buttons to open it in the browser, check it again and follow it (PR's, Tags, Completed, each with its own notification bell) without going to Settings.

Every full check also stores a compact snapshot (versions, statuses, CVE counts, package updates per repository; at most 730) in `version-history.json`, for statistics in a later version.

### Statistics

**Statistieken** shows PR activity from the history: opened and merged PRs per week, month or year (12 weeks, 12 months or 5 years), the PRs opened and merged in the current period, the median time from opening to merge and the number of active authors, plus rankings of authors and of the busiest repositories. Filter on a project or an author (click a name in the ranking); bots (`[bot]` in the name) are hidden by default. **Co-auteurs meetellen** in the author menu counts a PR for each of its co-authors too. A repository page shows the same chart per month for that repository. Activity only counts PRs, not commits, and goes back as far as the history does.

### Dependencies

The check behind **Repo's** shows which followed repositories are behind. Per repository Pullwatch reads, on the default branch:

| File | Detects |
|---|---|
| `go.mod` | Go |
| `*.csproj`, `*.fsproj`, `Directory.Build.props` | .NET |
| `package.json` | Node (`engines`), Angular, React, Vue, Next.js, Nuxt |
| `composer.json` | PHP, Symfony, Laravel |
| `rust-toolchain(.toml)`, root `Cargo.toml` | Rust |
| `Package.swift` | Swift (`swift-tools-version`, compared with the releases on swift.org; Swift has no EOL policy, so never EOL) |
| `.nvmrc`, `.node-version`, `pyproject.toml`, `.python-version` | Node, Python |
| `Dockerfile*` | base images (node, golang, python, dotnet, alpine, debian, ubuntu, nginx, postgres, redis, eclipse-temurin, rust, php, ruby) |
| `.github/workflows/*.yml` | `python-version`, `node-version`, `go-version`, `dotnet-version` |

Versions are compared with [endoflife.date](https://endoflife.date): **Actueel** (current), **Achter** (a newer major/minor exists; patches don't count), **EOL** or **Onbekend** (unknown).

- A version requirement that is only a minimum (`engines.node`, `php` in `composer.json`, `requires-python`, `rust-version`, CI versions) is dropped when the same language is pinned elsewhere (Docker image, `.nvmrc`, `rust-toolchain`).
- A `go.mod` used as a local copy of a dependency (`replace … => ./path`) is ignored.
- For frameworks, the installed version from `package-lock.json`/`composer.lock` wins over the manifest's minimum.
- Custom Docker images are recognised by a known name before the first dash (`php-fpm-alpine:8.4` → PHP 8.4); `ARG` defaults in `FROM` are filled in.

The same check looks up known vulnerabilities via [OSV.dev](https://osv.dev) for packages with an exact version: `go.mod`, `package-lock.json`, `PackageReference`/`PackageVersion` in .NET projects, `requirements*.txt` (`==` only), `poetry.lock`, `uv.lock`, `composer.lock`, `Cargo.lock` (crates.io only), `Package.resolved`, `yarn.lock` (classic and Berry), `pnpm-lock.yaml` (v6 to v9), NuGet `packages.lock.json` and `Gemfile.lock` (gems from rubygems.org; `GIT` and `PATH` gems are skipped). Every install keeps its workspace (the folder of its manifest, or the npm, yarn or pnpm workspace), whether it is direct or comes in through another package (with the shortest chain), and whether it is for runtime, development only or optional. Maven and Gradle are not read: their versions come from resolving a build. Each scan reads at most 50 files per repository; when there are more, lockfiles go first. Package names and versions are sent to api.osv.dev, also for private repositories.

If a repository has tags, the newest version tag is checked too (pre-releases like `-rc1` only if there is nothing else). Each vulnerability on the default branch is marked as also in that release or new since it. Anything already fixed on the default branch is not reported.

The check runs once a day (can be turned off under Settings → General) and on **Alles checken**; on a repository page, **Check** re-checks just that repository and the copy button puts its versions and vulnerabilities on the clipboard. New CVEs found by the daily check trigger a notification. From **PR's** or **Tags**, **Repo** (or right-click a row) opens the page of that repository.

### Dependencies per package

**Afhankelijkheden** (dependencies) turns the same check around: per runtime and package, which version is the latest and which repositories are still on an older one. It updates with the version check (daily, **Alles checken**, **Nu checken**).

- **Runtimes** (Go, Node, PHP, Python, .NET, Rust, Swift, Docker images) are compared within their release cycle, patches included: a repository on Go 1.27.3 sees "Go 1.27.4 beschikbaar", one on Go 1.26.9 sees 1.26.10 once that is out. A newer cycle (Node 22 → 25) is not listed here; the repository check already shows that as behind. A version without a patch (`go 1.27`, `node:22`) is never behind on patches.
- **Packages** are the direct dependencies only: `go.mod` without `// indirect`, the root and the workspaces in `package-lock.json` (v2/v3) and `pnpm-lock.yaml`, `Direct` in `packages.lock.json`, `DEPENDENCIES` in `Gemfile.lock`, and for `composer.lock`, `Cargo.lock`, `poetry.lock`, `uv.lock` and `yarn.lock` the names in `composer.json`, `Cargo.toml`, `pyproject.toml` or the `package.json` of the root and each workspace. Development-only packages come from `devDependencies`, `require-dev`, dev groups and the `group :development, :test` blocks of a `Gemfile`. .NET `PackageReference`s and `requirements*.txt` are direct already. A package without an exact version (a range without a lockfile) is not counted. Frameworks (React, Angular, Vue, Next.js, Nuxt, Laravel, Symfony) appear once, as a package.
- The latest version comes from the package's registry: proxy.golang.org, registry.npmjs.org, repo.packagist.org, api.nuget.org, pypi.org, crates.io and rubygems.org. Pre-releases don't count. Package names are sent to these registries, also for private repositories. Private modules and Swift packages end up under **Niet te checken** (can't be checked).
- After the daily check, one notification lists the new versions of anything a repository is behind on (turn off under Settings → General → **Melding bij nieuwe versies**). The first time a package is seen stays silent.

### PAT scopes

- Azure DevOps: **Code (Read)** (also covers tags) and **Project and Team (Read)** (the project list comes from `/_apis/projects`).
- GitHub (fine-grained): **Pull requests: Read** and **Metadata: Read** on the repositories you want, plus **Contents: Read** for the dependency check. Classic: `repo`.

## Known quirks

- With an ad-hoc signed local build (from Xcode or `release.sh --unsigned`), macOS may ask for Keychain access again after each install for PAT accounts; choose "Always Allow".
- On first launch Pullwatch opens a welcome window: where the menu bar icon is, your first account, then notifications and launch at login. Opening Pullwatch again while it runs opens the main window (or the welcome window while no account is set up).
- Running from Xcode while an installed Pullwatch is open gives you two menu bar icons; quit the installed one first via **Stop** in the menu.

## Data

`~/Library/Application Support/Pullwatch/`: `config.json`, `seen.json`, `history.json`, `versions.json`. Tokens are stored in the Keychain (`nl.torrisi.pullwatch`).

Logs: `log stream --predicate 'subsystem == "nl.torrisi.pullwatch"'`

## License

[Apache 2.0](LICENSE)

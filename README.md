# Pullwatch

A macOS menu bar app that notifies you about new pull requests in Azure DevOps and GitHub (github.com, GitHub Enterprise Server and GHE.com) and new merge requests in GitLab™ (gitlab.com or your own server), plus new tags and GitHub and GitLab releases (optional, per repository). It keeps a searchable history and can check your repositories for outdated languages, frameworks and known vulnerabilities.

Available in English, Dutch, German and French: Pullwatch follows the macOS language, or pick one under Settings → General → Language.

## Install

Download the latest `Pullwatch-x.y.z.dmg` from [Releases](https://github.com/alessandro823/pullwatch/releases), open it and drag Pullwatch to Applications.

The app is signed with a Developer ID and notarized by Apple. Universal (Apple silicon and Intel), requires macOS 26.6 or later.

## Build from source

- Xcode 27 (Swift 6.4), macOS 26.6 or later
- Optional: `az` (`az login`), `gh` (`gh auth login`) and/or `glab` (`glab auth login`) for CLI authentication

Open `Pullwatch/Pullwatch.xcodeproj` in Xcode and run the **Pullwatch** scheme (⌘R). From the command line:

```bash
swift test --package-path PullwatchKit              # PullwatchKit unit tests
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch build
scripts/release/release.sh --unsigned               # dist/Pullwatch-<version>.dmg and .zip, ad-hoc signed
scripts/release/release.sh                          # signed with Developer ID, notarized and stapled DMG
```

`release.sh` builds the app, removes Sparkle's XPC services (only a sandboxed app needs them) and signs Sparkle's parts one by one, then hands the app to `scripts/release/package.sh`, which makes the disk image and `Pullwatch-<version>.zip` (the update Sparkle installs; the release workflow writes the signed `appcast.xml` for it). The disk image opens as an install window: the app on the left, Applications on the right, and a background drawn by `scripts/release/dmg-background.swift` that says "Install Pullwatch" with an arrow between them. Finder lays out that window through AppleScript, so the first run asks whether your terminal may control Finder; allow it (System Settings, Privacy & Security, Automation).

The version is `MARKETING_VERSION` (and the build number `CURRENT_PROJECT_VERSION`) in `Pullwatch/App.xcconfig`. A signed release needs a Developer ID Application certificate in the Keychain and a notarytool profile (`xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>`); override with `SIGN_ID=…` and `NOTARY_PROFILE=…`.

The repository holds the app (`Pullwatch/`: the Xcode project, `App/` for state and wiring, `Views/` for the screens) and the `PullwatchKit` Swift package, which the app links and which has the unit tests. Its modules: `PullwatchCore` (models, polling, history, version checks, updates), `PullwatchGitHub`, `PullwatchAzureDevOps` and `PullwatchGitLab` (one per provider), and `PullwatchProviders` (picks the provider for an account).

## Usage

1. Click the menu bar icon → **Instellingen…** (Settings), which opens the settings in the main window.
2. Add an account (Azure DevOps, GitHub or GitLab), choose PAT or CLI, and test the connection. With the GitHub CLI and several `gh` accounts, pick which one provides the token under **GitHub-account**. For GitHub Enterprise, choose **GitHub Enterprise** on the GitHub card (or in the **+** menu under Settings) and enter your server under **Server**: a GitHub Enterprise Server (`https://github.example.com`) or your enterprise's subdomain on GHE.com (`https://acme.ghe.com`), https only. Pullwatch finds the API itself (`/api/v3` on a server, `api.acme.ghe.com` on GHE.com), links to pull requests, tags and repositories on that server, and the account card shows the host. For GitLab, leave **Server** empty for gitlab.com or enter your own server (https only, for example `https://gitlab.example.com`), and list the groups or users to follow, separated by commas (`acme, acme/platform`); a group includes its subgroups, and repositories appear as `group/subgroup/project`.
3. Per account, choose which repositories you follow: PR's, Tags and/or Completed (merged PRs).

Under **Andere repositories** (other repositories) in the same list you add single repositories outside the account's owners: type `owner/repo` (GitHub) or `project/repo` (Azure DevOps, inside the account's organisation), or paste a github.com or dev.azure.com link. Pullwatch checks it with one request and says in plain words when it can't find or read it; remove one with a right click or the Delete key. **Volg een repository…** (⇧⌘N, in the Go menu and the toolbar of **Repo's**) opens the same field with a choice of account. On GitHub this also works for a public repository of another organisation where the Pullwatch GitHub App is not installed, such as `openEHR/specifications-AM`; if your token may not read it, Pullwatch reads it without signing in (see `docs/github-app.md`). Their PRs come in one search per account with `repo:` qualifiers (30 repositories per search), and they show up everywhere like the other followed repositories, grouped under their own owner. On GitLab, type `group/subgroup/project` or paste a link from gitlab.com or the account's own server (also `/-/` links such as `/-/merge_requests/12`); a link to another server is refused. A public project your token may not read is read without signing in, if the server answers without a token (gitlab.com does; a server that requires signing in does not, and then the project is not found). Each such project costs one request for its merge requests per poll (one page, the 100 most recently updated), and its tags, releases, co-authors and files go through the usual GitLab requests.

Tags are off by default. Next to each checkbox is a bell: turn it off to keep following the repository (menu and history) without getting notifications. The bell in the header toggles all visible repositories. Tags are polled every 15 minutes (separate from the PR interval; "Nu verversen" polls tags too). The first tag poll per repository is silent. On GitHub the Tags checkbox follows releases too: a release published for a tag Pullwatch already saw gives one notification ("new release" with its title) and updates the same history row.

Pullwatch checks GitHub once a day for a newer release (Settings → General, also **Check now**); when there is one, you get a notification and a banner in the menu. A release build installs the update itself with [Sparkle](https://sparkle-project.org): **Install** shows the release notes, then Sparkle downloads the update, checks its EdDSA signature and the Developer ID signature, installs it and restarts Pullwatch. Under Settings → General, **Install updates automatically** downloads an update in the background and installs it when you quit Pullwatch, and **Include test versions** also offers pre-releases (Sparkle's beta channel). A build without Sparkle's public key (one you build from source, or a fork without its own key) keeps the download button for the disk image instead.

While a window (settings, history, versions) is open, Pullwatch shows in the Dock; close the last window and it runs from the menu bar only.

### Notifications

Each notification says what happened in the title ("New Pull Request", "Pull Request Merged", "New Release v1.2.0", "Critical Vulnerability"), the repository in the subtitle, and the pull request or release title with its author and co-authors ("by mona and 2 others") in the body. macOS stacks them per account and repository. Up to 20 items per poll each get their own notification; above that, one notification per repository says how many there are and lists the first three. A GitHub author's avatar is attached (fetched once, cached for a week); otherwise the notification shows the icon of its kind.

Each pull request shows its checks (CI) the way GitHub's list does: in the PR list next to the state icon, after the title in the menu and in a repository's pull requests, an icon in the colour of the state (GitHub's Octicons `check` in green, `x` in red, `dot-fill` in amber while something still runs) and the count of passed checks out of all of them, `4/8`; skipped and neutral checks count as passed. The tooltip and VoiceOver say it in words ("4 of 8 checks passed, 1 failed and 3 running"); a pull request without checks has no cell. GitHub's count comes from the last commit's `statusCheckRollup`, in the same GraphQL request as the co-authors; Azure DevOps reads the pull request's statuses and its build policies, GitLab the jobs of the merge request's head pipeline. Only open pull requests and those merged in the last three days are asked, and one whose checks are finished and that did not change costs no request. Without the permission (the GitHub App's **Checks** and **Commit statuses**, see `docs/github-app.md`) there is no cell and the repository page says **Checks: Needs permission**. **Mislukte checks van je eigen pull requests** under Settings → Notifications (off by default) notifies you when the checks of one of your own open pull requests fail.

The buttons depend on the kind: **Mark as Read**, **Open Repository Page** (in Pullwatch) and **Mute Repository** on pull requests, releases and tags; **Show in Pullwatch**, **Copy Advisory ID** and **Open Repository Page** on a vulnerability. **Mute Repository** turns off that kind's notifications for that repository (the same bell as in Settings), and the menu shows **Undo** until you dismiss it. Clicking the notification itself opens the pull request, release or advisory and marks it read; reading an item in Pullwatch removes its notification from Notification Center.

New pull requests, releases, vulnerabilities and security alerts arrive with a banner and sound; tags without a release, merged pull requests and new versions arrive quietly in Notification Center only. The most serious vulnerability leads the stack. Pullwatch does not use Time Sensitive notifications: that needs an entitlement only a provisioning profile can carry (see `docs/setup.md`).

**Settings → Notifications** has a switch per kind (new pull requests, merged pull requests, releases, tags, vulnerabilities, security alerts, new versions) with a preview of each, **Quiet hours** (no sound and Notification Center only between two times; Focus and Do Not Disturb still come from macOS), the unread count on the Dock icon and the unread dot in the menu bar.

### Main window

**Openen…** in the menu opens the main window. Its sidebar has **PR's**, **Tags en releases**, **Repo's** (repositories), **Afhankelijkheden** (dependencies) and **Statistieken** (statistics), with **Instellingen** (settings) pinned at the bottom; the badges count unread PRs and tags and unseen new versions. Under PR's, Tags and Repo's you can expand a list of projects (Azure DevOps) or owners (GitHub and GitLab), each with its own unread count; selecting one filters the list and the search to that project. Pullwatch remembers the last section. **Instellingen…** in the menu and ⌘, open the settings there.

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

Each vulnerability also shows its GitHub Advisory Database entry: the GHSA id next to the CVE, GitHub's severity with the CVSS score and vector, the CWE names and a link to `github.com/advisories`, on the repository page, in the copied text and in notifications. Pullwatch fetches each advisory once from the public advisories API (`api.github.com/advisories`, with a GitHub account's token when there is one) and keeps it with the check.

The repository page also shows what the service itself knows, read with the same daily check and **Check**, never on every poll. On GitHub: the advisories the repository publishes about itself, open code scanning alerts (CodeQL and other tools, with file and line) and the number of open secret scanning alerts (never the secret). On Azure DevOps: open Advanced Security alerts (code and dependencies, and the number of secrets). GitLab has no equivalent open to every plan (its vulnerability report is GitLab Ultimate), so a GitLab repository shows only the version and OSV check. Open critical and high alerts count in the repository's findings and health; a notification for a new one is off by default (Settings → Notifications). When a kind is turned off for a repository, or the GitHub App or token may not read it, the page says **Off** or **Needs permission** with a link, and nothing fails; what a GitHub Enterprise Server does not have (the repository's own advisories) says **Not available on this server**.

The check runs once a day (can be turned off under Settings → General) and on **Alles checken**; on a repository page, **Check** re-checks just that repository and the copy button puts its versions and vulnerabilities on the clipboard. New CVEs found by the daily check trigger a notification. From **PR's** or **Tags**, **Repo** (or right-click a row) opens the page of that repository.

### Dependencies per package

**Afhankelijkheden** (dependencies) turns the same check around: per runtime and package, which version is the latest and which repositories are still on an older one. It updates with the version check (daily, **Alles checken**, **Nu checken**).

- **Runtimes** (Go, Node, PHP, Python, .NET, Rust, Swift, Docker images) are compared within their release cycle, patches included: a repository on Go 1.27.3 sees "Go 1.27.4 beschikbaar", one on Go 1.26.9 sees 1.26.10 once that is out. A newer cycle (Node 22 → 25) is not listed here; the repository check already shows that as behind. A version without a patch (`go 1.27`, `node:22`) is never behind on patches.
- **Packages** are the direct dependencies only: `go.mod` without `// indirect`, the root and the workspaces in `package-lock.json` (v2/v3) and `pnpm-lock.yaml`, `Direct` in `packages.lock.json`, `DEPENDENCIES` in `Gemfile.lock`, and for `composer.lock`, `Cargo.lock`, `poetry.lock`, `uv.lock` and `yarn.lock` the names in `composer.json`, `Cargo.toml`, `pyproject.toml` or the `package.json` of the root and each workspace. Development-only packages come from `devDependencies`, `require-dev`, dev groups and the `group :development, :test` blocks of a `Gemfile`. .NET `PackageReference`s and `requirements*.txt` are direct already. A package without an exact version (a range without a lockfile) is not counted. Frameworks (React, Angular, Vue, Next.js, Nuxt, Laravel, Symfony) appear once, as a package.
- The latest version comes from the package's registry: proxy.golang.org, registry.npmjs.org, repo.packagist.org, api.nuget.org, pypi.org, crates.io and rubygems.org. Pre-releases don't count. Package names are sent to these registries, also for private repositories. Private modules and Swift packages end up under **Niet te checken** (can't be checked).
- After the daily check, one notification lists the new versions of anything a repository is behind on (turn off under Settings → Notifications → **Nieuwe versies**). The first time a package is seen stays silent.

### Sources

Settings → **Bronnen** (sources) lists every outside service Pullwatch talks to, in plain language: under **Kwetsbaarheden** OSV.dev, the GitHub Advisory Database, GitHub's own security data and Azure DevOps Advanced Security; under **Versies** the package registries, endoflife.date and swift.org; under **Pull requests** the CI checks of pull requests (off: no checks are fetched, shown or notified). Each row says what the source provides, the address Pullwatch calls (selectable) and a link to its site, with a switch. A source that is off is called nowhere: not in the daily check, not when one repository is checked again, not when advisories are completed. Wherever that leaves something unchecked, Pullwatch says so ("Niet gecontroleerd: bron OSV.dev staat uit", "Versie niet gecontroleerd: bron npm staat uit") and never shows it as current or free of vulnerabilities; what an earlier check got from that source is hidden at once. OSV.dev is the only source for package vulnerabilities in GitHub and GitLab repositories, and the tab says so. A switch does not start a check; **Nu checken** runs one. **Overige verbindingen** (other connections) lists the rest without a switch: the server of each account, signing in with GitHub, profile pictures and the update check (on or off under Settings → General). **Kopieer overzicht** puts the whole list, with the version, the date and the state of each source, on the clipboard as plain text, to paste into an email or chat. Everything is on by default; the choice is stored in `config.json` as `disabledSources`.

### PAT scopes

- Azure DevOps: **Code (Read)** (also covers tags) and **Project and Team (Read)** (the project list comes from `/_apis/projects`); optionally **Advanced Security (Read)** for its alerts.
- GitHub (fine-grained): **Pull requests: Read** and **Metadata: Read** on the repositories you want, plus **Contents: Read** for the dependency check and **Repository security advisories: Read** for the repository's own advisories; optionally **Code scanning alerts: Read** and **Secret scanning alerts: Read**. Classic: `repo` (with `security_events` for the alerts).
- GitHub Enterprise (Server, or `<name>.ghe.com`): a token made on that server. Classic: `repo` and `read:org` (with `security_events` for the alerts); the **Token maken** link in the account editor opens the server's token page with these filled in. Fine-grained tokens need the same permissions as on github.com. With the GitHub CLI, Pullwatch runs `gh auth token --hostname <server>` (log in first with `gh auth login --hostname <server>`). **Sign in with GitHub** works on github.com only; see [docs/setup.md](docs/setup.md).
- GitLab: a personal access token with the **read_api** scope (merge requests, projects, tags, releases, commits and files). The **Token maken** link in the account editor opens your server's token page with the name and scope filled in. With the GitLab CLI, Pullwatch reads `glab config get token --host <server>`.

## Known quirks

- With an ad-hoc signed local build (from Xcode or `release.sh --unsigned`), macOS may ask for Keychain access again after each install for PAT accounts; choose "Always Allow".
- On first launch Pullwatch opens a welcome window: where the menu bar icon is, your first account, then notifications and launch at login. Opening Pullwatch again while it runs opens the main window (or the welcome window while no account is set up).
- Running from Xcode while an installed Pullwatch is open gives you two menu bar icons; quit the installed one first via **Stop** in the menu.

## Data

`~/Library/Application Support/Pullwatch/`: `config.json`, `seen.json`, `history.json`, `versions.json`. Tokens are stored in the Keychain (`nl.torrisi.pullwatch`).

Logs: `log stream --predicate 'subsystem == "nl.torrisi.pullwatch"'`

## License

[Apache 2.0](LICENSE)

## Third-party

- The pull request icons (open, draft, merged and closed), the checks icons, the menu bar icon and the glyph of the app icon are [GitHub Octicons](https://github.com/primer/octicons) (`git-pull-request`, `git-pull-request-draft`, `git-merge`, `git-pull-request-closed`, `check`, `x`, `dot-fill`), MIT License, Copyright (c) GitHub Inc. See [NOTICE](NOTICE).
- GitHub and the Invertocat are trademarks of GitHub, Inc. The unmodified Invertocat from GitHub's [logo downloads](https://brand.github.com/foundations/logo) marks GitHub on the account choice, in the add-account menu and as the placeholder of a GitHub account; GitHub's guidelines allow a logo that shows an integration.
- GITLAB is a trademark of GitLab Inc. in the United States and other countries and regions. GitLab's [Trademark Guidelines](https://handbook.gitlab.com/handbook/marketing/brand-and-product-marketing/brand/brand-activation/trademark-guidelines/) do not allow its logos in a product's interface, so Pullwatch shows the name GitLab™ with an SF Symbol.
- Azure DevOps is a trademark of the Microsoft group of companies. Microsoft's [Azure icon terms](https://learn.microsoft.com/azure/architecture/icons/) cover diagrams and documentation only, so Pullwatch shows the name with an SF Symbol.
- Pullwatch is not affiliated with, endorsed or sponsored by GitHub, GitLab or Microsoft.

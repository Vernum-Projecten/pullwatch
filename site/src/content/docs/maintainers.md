---
title: For maintainers
description: Where the maintainer documentation lives, and how to build Pullwatch from source.
---

The maintainer documentation lives in the repository, next to the code it describes, so it changes in the same pull request.

| Document | What it covers |
|---|---|
| [docs/setup.md](https://github.com/alessandro823/pullwatch/blob/main/docs/setup.md) | Everything the maintainer configures outside the code: signing, the GitHub App, the release secrets |
| [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) | The release procedure and its Actions secrets |
| [docs/github-app.md](https://github.com/alessandro823/pullwatch/blob/main/docs/github-app.md) | The GitHub App behind **Sign In with GitHub** |
| [docs/website.md](https://github.com/alessandro823/pullwatch/blob/main/docs/website.md) | This website: GitHub Pages, the custom domain and its DNS records |
| [site/README.md](https://github.com/alessandro823/pullwatch/blob/main/site/README.md) | Running and building this website, and adding a page |
| [CONTRIBUTING.md](https://github.com/alessandro823/pullwatch/blob/main/CONTRIBUTING.md) | How to build, test and send a change, and what a pull request needs |
| [SECURITY.md](https://github.com/alessandro823/pullwatch/blob/main/SECURITY.md) | How to report a vulnerability privately, and what is in scope |
| [CHANGELOG.md](https://github.com/alessandro823/pullwatch/blob/main/CHANGELOG.md) | The release notes of every version |

## Build from source

You need Xcode 27 (Swift 6.4) on macOS 26.6 or later. Optionally, `az` (`az login`), `gh` (`gh auth login`) or `glab` (`glab auth login`) for signing in through a command-line tool.

Open `Pullwatch/Pullwatch.xcodeproj` and run the **Pullwatch** scheme (⌘R), or from the command line:

```sh
swift test --package-path PullwatchKit              # the PullwatchKit unit tests
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch build
scripts/release/release.sh --unsigned               # dist/Pullwatch-<version>.dmg and .zip, ad hoc signed
scripts/release/release.sh                          # signed with Developer ID, notarized and stapled
```

Running from Xcode while an installed Pullwatch is open gives you two menu bar icons; quit the installed one first with **Quit Pullwatch** in its menu panel. An ad hoc signed build may ask for Keychain access again after each install for token accounts; choose **Always Allow**.

## The repository

- `Pullwatch/`: the app, with the Xcode project. `Pullwatch/Pullwatch/` has one folder per feature with its model and its views, such as `Accounts/`, `PullRequests/`, `Repositories/` and `Settings/`.
- `PullwatchKit/`: the Swift package the app links, with the unit tests. Its modules are `PullwatchCore` (models, polling, history, version checks, updates), `PullwatchGitHub`, `PullwatchAzureDevOps` and `PullwatchGitLab` (one per service), `PullwatchProviders` (picks the service for an account) and `PullwatchMCP` (the server for coding agents).
- `site/`: this website. `scripts/`: the release, check and development scripts. `docs/`: the maintainer documents above.

## Making a release build

`release.sh` builds the app, removes Sparkle's XPC services (only a sandboxed app needs them) and signs Sparkle's parts one by one, then hands the app to `scripts/release/package.sh`. That makes the disk image and `Pullwatch-<version>.zip`, the update Sparkle installs; the release workflow writes the signed `appcast.xml` for it.

The disk image opens as an install window: the app on the left, Applications on the right, and a background drawn by `scripts/release/dmg-background.swift` that says "Install Pullwatch" with an arrow between them. Finder lays out that window through AppleScript, so the first run asks whether your terminal may control Finder; allow it under System Settings, Privacy & Security, Automation.

The version is `MARKETING_VERSION`, and the build number `CURRENT_PROJECT_VERSION`, in `Pullwatch/App.xcconfig`. A signed release needs a Developer ID Application certificate in the Keychain and a notarytool profile (`xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>`); choose others with `SIGN_ID=...` and `NOTARY_PROFILE=...`. [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) has the full procedure.

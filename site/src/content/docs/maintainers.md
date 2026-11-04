---
title: For maintainers
description: Where the maintainer documentation lives in the repository.
---

The maintainer documentation lives in the repository, next to the code it describes, so it changes in the same pull request.

| Document | What it covers |
|---|---|
| [docs/setup.md](https://github.com/alessandro823/pullwatch/blob/main/docs/setup.md) | Everything the maintainer configures outside the code: signing, the GitHub App, the release secrets |
| [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) | The release procedure and its Actions secrets |
| [docs/github-app.md](https://github.com/alessandro823/pullwatch/blob/main/docs/github-app.md) | The GitHub App behind **Sign In with GitHub** |
| [docs/website.md](https://github.com/alessandro823/pullwatch/blob/main/docs/website.md) | This website: GitHub Pages, the custom domain and its DNS records |
| [site/README.md](https://github.com/alessandro823/pullwatch/blob/main/site/README.md) | Running and building this website, and adding a page |
| [CHANGELOG.md](https://github.com/alessandro823/pullwatch/blob/main/CHANGELOG.md) | The release notes of every version |

## Build from source

You need Xcode 27 (Swift 6.4) on macOS 26.6 or later. Open `Pullwatch/Pullwatch.xcodeproj` and run the **Pullwatch** scheme, or from the command line:

```sh
swift test --package-path PullwatchKit              # the PullwatchKit unit tests
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch build
scripts/release/release.sh --unsigned               # dist/Pullwatch-<version>.dmg and .zip, ad hoc signed
```

The [README](https://github.com/alessandro823/pullwatch#readme) has the details.

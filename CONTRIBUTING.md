# Contributing to Pullwatch

Thanks for helping. Pullwatch is a small project with one maintainer, so a
contribution that follows this page is the one that lands quickest.

- **A bug or an idea:** open an [issue](https://github.com/alessandro823/pullwatch/issues/new/choose)
  with the bug report or feature template.
- **A question:** read the [FAQ](https://pullwatch.net/faq/) and
  [Troubleshooting](https://pullwatch.net/troubleshooting/) first; [SUPPORT.md](SUPPORT.md)
  says where to go next.
- **A vulnerability:** never in a public issue. Follow [SECURITY.md](SECURITY.md).
- **A larger change** (a new feature, a new service, a refactor across
  folders): open an issue first and agree on the approach, so nobody writes
  a pull request that cannot be merged.

Everyone here follows the [Code of Conduct](CODE_OF_CONDUCT.md). Using AI
tools is fine; [AI_POLICY.md](AI_POLICY.md) says what that asks of you.

## Set up

You need Xcode 27 (Swift 6.4) on macOS 26.6 or later.

```bash
git clone https://github.com/alessandro823/pullwatch.git
cd pullwatch
git config core.hooksPath .githooks   # refuses secrets, cleans commit messages
open Pullwatch/Pullwatch.xcodeproj    # run the Pullwatch scheme with ⌘R
```

[CLAUDE.md](CLAUDE.md) maps the repository and holds the project's rules;
[.claude/rules/swift.md](.claude/rules/swift.md) is the Swift style guide.
Both apply to every contributor, human or agent.

## Run the gates

Run what CI runs before you push. Warnings are errors.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path PullwatchKit -Xswiftc -warnings-as-errors
xcodebuild test -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch \
  -destination 'platform=macOS' -only-testing:PullwatchTests
shellcheck scripts/*/*.sh .claude/hooks/*.sh .githooks/*
actionlint
bash scripts/release/changelog.sh --check
bash scripts/dev/sync-strings.sh && git diff --exit-code -- '*.xcstrings'
```

The UI tests (`PullwatchUITests`) take over the screen and quit a running
Pullwatch. Run them only on a Mac nobody is using, and never on someone
else's Mac; CI runs them on every pull request. Do not pass
`SWIFT_TREAT_WARNINGS_AS_ERRORS` to `xcodebuild`: the project already sets
it, and on the command line it also reaches the packages and stops the build.

A change to `site/` also builds the website (Node from `site/.nvmrc`):

```bash
cd site && npm ci && npm run build && npm run check-links
```

## What a change needs

- **Text in four languages.** Every user-facing string is in Dutch, English,
  German and French. After changing text, run
  `bash scripts/dev/sync-strings.sh` and fill in the English, German and
  French of each new entry in the String Catalog. The website's pages exist
  in the same four languages (`site/src/content/docs/<lang>/`).
- **A look at the UI.** Open every screen the change touches in light and
  dark mode, in Dutch and English, at the smallest window size, and check
  for truncated or overflowing text. Put before and after screenshots in the
  pull request, made with fake data only.
- **A changelog fragment.** A change a person using the app would notice
  adds one file under `changelog.d/`, as [changelog.d/README.md](changelog.d/README.md)
  describes; never a line under `[Unreleased]` in `CHANGELOG.md`. A change
  nobody notices (a refactor, tests, CI, docs) gets the `no-changelog`
  label instead; say so in the pull request and a maintainer adds it.
- **Tests.** New behaviour gets a test in the target that mirrors its
  folder. Never weaken, skip or delete a test to make a build pass.
- **Dependencies.** A package change updates both `Package.resolved` files
  and the app's acknowledgements; `scripts/checks/acknowledgements.sh` fails
  otherwise.
- **No secrets.** Tokens, keys and certificates never go into the
  repository; the pre-commit hook refuses them.

## Branches, commits and pull requests

- Branch from `main` with a conventional type: `fix/…`, `feat/…`, `docs/…`,
  `refactor/…`, `test/…`, `perf/…`, `ci/…` or `chore/…`.
- Commit subjects are English conventional commits (`fix: …`, `feat: …`).
  Code comments follow the code around them, which is Dutch.
- One pull request does one thing. Its description says what changed and
  why, and links the issue (`Closes #123`).
- No AI or assistant attribution in commits or pull requests: no
  `Co-authored-by` for a tool, no "Generated with" line.
- Prose in the app, the docs and the website has no em dashes and no
  middle dot as a separator.

## Licence of your contribution

Pullwatch is licensed under the [Apache License 2.0](LICENSE). Under its
section 5, anything you submit for inclusion is licensed under the same
terms, with no further agreement. There is no CLA and no DCO sign-off:
opening a pull request is enough. Submit only work you have the right to
license this way.

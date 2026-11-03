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
- `origin` = `Vernum-Projecten/pullwatch`, our fork. Branches, issues and
  their relations live here; every change goes back to upstream as a pull
  request from a fork branch.
- `gh repo set-default Vernum-Projecten/pullwatch` once per clone, so `gh`
  and `scripts/gh/*` act on the fork, not on upstream.
- Before starting a branch: `git fetch upstream && git switch main && git
  merge --ff-only upstream/main && git push origin main`.

## Repository map

- `App/`: the SwiftUI app target. `PullwatchApp.swift` (the `MenuBarExtra`,
  the main `Window`, the Dock-icon switch), `AppModel.swift` (the one
  `@Observable` model: polling loop, config, history, update check),
  `MenuView` (the menu-bar popover), `MainView` (sidebar: PRs, Tags, Repos,
  Versions, Statistics, Settings), `SettingsView`, `AccountEditor`,
  `Notifier` (user notifications), `Shortcuts`, `AppLanguage`.
  `Localizable.xcstrings` holds the app's text in nl, en, de and fr.
  `Assets.xcassets/AppIcon.appiconset` is the icon (drawn by
  `scripts/make-icon.swift`; being replaced, #4).
- `Sources/PullwatchCore/`: a local Swift package with everything without a
  window. Providers behind `PRProvider` (`GitHubProvider`,
  `AzureDevOpsProvider`, `ProviderFactory`), token sources (PAT in the
  Keychain, `gh` / `az` CLI), `PollEngine`, `History`, `SeenState`,
  `NotificationPlanner`, the version and vulnerability checks
  (`StackDetector`, `DependencyDetector`, `PackageRegistry`, `EndOfLife`,
  `OSV`), `UpdateChecker` (GitHub releases), `HTTP` and `ProcessRunner`.
- `Tests/PullwatchCoreTests/`: Swift Testing suites for the package;
  `Support/` has `MockHTTPClient` and `MockProcessRunner`.
- `project.yml` (XcodeGen) generates the git-ignored `Pullwatch.xcodeproj`;
  `Makefile` wraps the build, DMG and release. Both are being replaced by a
  committed Xcode project and xcconfig (#12).
- `scripts/gh/`: tracker helpers (copied from FerroLICENCE): `fields.sh`
  (issue type, Priority, Effort), `rel.sh` (sub-issues and blocked-by),
  `labels.sh` (the label set). `scripts/dev/xcode-skills.sh` exports
  Apple's Xcode agent skills into `.claude/skills/`.
- `.githooks/`: `pre-commit` (refuses private keys, tokens, certificates)
  and `commit-msg` (strips AI attribution). Install once per clone:
  `git config core.hooksPath .githooks`.

## Hard rules

- **Never push to upstream.** Push to `origin` and open a pull request; the
  Claude Bash hook refuses a push to upstream.
- **No secrets in the tree.** Tokens live in the Keychain; the Developer ID
  certificate, the notarisation credentials and (later) Sparkle's private
  key are Alessandro's and live in Actions secrets and his Keychain. The
  pre-commit hook and the Claude `protect_secrets.sh` hook refuse them.
- **The bundle id stays `nl.torrisi.pullwatch`.** Changing it loses every
  user's settings, notifications permission and Keychain tokens.
- **The app supports macOS 14 and later, universal.** No API above 14
  without an availability check and a working fallback.
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
swift test                                   # PullwatchCore
make build                                   # needs `brew install xcodegen`; until #12
shellcheck scripts/gh/*.sh scripts/dev/*.sh .claude/hooks/*.sh .githooks/*
```

A UI change is looked at before it is called done: run the app (`make run`),
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

A change lands through a PR on a conventional-type branch (a Bug is `fix/`,
a Feature `feat/`, a Task its work kind), with conventional commit subjects
in English (`feat: …`, `fix: …`), as upstream's history does. The PR body
says what changed and why, and links the fork issue. Prefer what
FerroLICENCE (`~/RustroverProjects/FerroLICENCE`) already does and has
proven (icon, DMG window, Sparkle updater, CI, release lane) over designing
it again; each issue lists the files to copy.

## Releases

Today: `make release` on Alessandro's Mac (Developer ID of Code24 BV,
notarytool profile `pullwatch`) builds a signed, notarised DMG that he
uploads to a GitHub release `vX.Y.Z`. The app's `UpdateChecker` reads
`releases/latest` once a day. The release lane moves to CI with Sparkle
updates in #8 and #9.

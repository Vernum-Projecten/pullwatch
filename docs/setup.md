# What the maintainer sets up

Everything Pullwatch needs that is not code: accounts, keys and settings that
only the maintainer (Alessandro, `alessandro823`) can create, because they
belong to him. Each item links to the document with the exact steps. Nothing
here is secret unless it says so, and nothing secret ever goes into this
repository.

| What | Where it lives | Steps | Needed for |
|---|---|---|---|
| Developer ID Application certificate (team Code24 BV) | the maintainer's login Keychain | Apple Developer, Certificates; already in place for `scripts/release/release.sh` | signed, notarised releases |
| notarytool profile `pullwatch` | the maintainer's Keychain | `xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>`; already in place | notarising releases |
| **GitHub App "Pullwatch"** | the maintainer's GitHub account | [github-app.md](github-app.md) | **Sign in with GitHub** (device flow) |
| `PW_GITHUB_CLIENT_ID`, `PW_GITHUB_APP_SLUG` | `Pullwatch/Release.xcconfig` (public values) | [github-app.md](github-app.md), step 2 | release builds find the GitHub App |
| Test GitHub App for development | Vernum-Projecten ("TEST Pullwatch"), values in `Pullwatch/Debug.xcconfig` | [github-app.md](github-app.md), "Development builds use a test app" | Xcode's Run and the tests; replace with your own if you prefer |

Coming with later work, documented when it lands:

- Actions secrets for the release workflow (certificate, notarisation key):
  the CI and release issue.
- Sparkle's EdDSA key pair for in-app updates: the private half as an Actions
  secret and in the maintainer's Keychain, the public half in
  `Pullwatch/App.xcconfig`: the Sparkle issue.

Azure DevOps needs nothing here: people sign in with the Azure CLI
(`az login`) or a personal access token of their own.

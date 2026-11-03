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
| Automation permission: the terminal may control Finder | the Mac that runs `scripts/release/release.sh` | System Settings, Privacy & Security, Automation; macOS asks on the first run of `scripts/release/package.sh` | laying out the install window of the disk image |
| **GitHub App "Pullwatch"** | the maintainer's GitHub account | [github-app.md](github-app.md); read-only permissions Pull requests, Contents, Metadata and Repository security advisories, optional Code scanning alerts and Secret scanning alerts; each installation's owner accepts a new permission ([github-app.md](github-app.md), section 6) | **Sign in with GitHub** (device flow), the repository's own advisories, code scanning and the secret count |
| `PW_GITHUB_CLIENT_ID`, `PW_GITHUB_APP_SLUG` | `Pullwatch/Release.xcconfig` (public values) | [github-app.md](github-app.md), step 2 | release builds find the GitHub App |
| Actions secrets `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD` (secret) | the repository's Actions secrets | [releasing.md](releasing.md), "Secrets, once", step 1 | the release workflow signs with the Developer ID |
| Actions secrets `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` (secret) | the repository's Actions secrets; the key is an App Store Connect API key of Code24 BV | [releasing.md](releasing.md), "Secrets, once", step 2 | the release workflow notarises |
| Test GitHub App for development | Vernum-Projecten ("TEST Pullwatch"), values in `Pullwatch/Debug.xcconfig` | [github-app.md](github-app.md), "Development builds use a test app"; give it the same permissions as the release app (it has Repository security advisories; code and secret scanning are not granted, so those show **Needs permission**) | Xcode's Run and the tests; replace with your own if you prefer |

Coming with later work, documented when it lands:

- Sparkle's EdDSA key pair for in-app updates: the private half as an Actions
  secret and in the maintainer's Keychain, the public half in
  `Pullwatch/App.xcconfig`: the Sparkle issue.

Azure DevOps needs nothing here: people sign in with the Azure CLI
(`az login`) or a personal access token of their own.

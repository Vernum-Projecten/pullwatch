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
| **GitHub App "Pullwatch"** | the maintainer's GitHub account | [github-app.md](github-app.md); read-only permissions Pull requests, Contents, Metadata and Repository security advisories, optional Code scanning alerts, Secret scanning alerts, Checks and Commit statuses; each installation's owner accepts a new permission ([github-app.md](github-app.md), section 6) | **Sign in with GitHub** (device flow), the repository's own advisories, code scanning and the secret count, each pull request's checks |
| `PW_GITHUB_CLIENT_ID`, `PW_GITHUB_APP_SLUG` | `Pullwatch/Release.xcconfig` (public values) | [github-app.md](github-app.md), step 2 | release builds find the GitHub App |
| Actions secrets `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD` (secret) | the repository's Actions secrets | [releasing.md](releasing.md), "Secrets, once", step 1 | the release workflow signs with the Developer ID |
| Actions secrets `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` (secret) | the repository's Actions secrets; the key is an App Store Connect API key of Code24 BV | [releasing.md](releasing.md), "Secrets, once", step 2 | the release workflow notarises |
| Sparkle's EdDSA key pair: Actions secret `SPARKLE_PRIVATE_KEY` (secret) | the private half in the maintainer's login Keychain (made by `generate_keys`) and in the repository's Actions secrets; never in a file | [releasing.md](releasing.md), "Secrets, once", step 3 | the release workflow signs the update and its `appcast.xml`; without it the lane stops in its first job |
| `SPARKLE_PUBLIC_ED_KEY` | `Pullwatch/Release.xcconfig` (public value) | [releasing.md](releasing.md), "Secrets, once", step 3 | release builds install updates in the app; empty, they only show a download button, and `check-version.sh` refuses a release |
| `PW_RELEASES_OWNER` | `Pullwatch/App.xcconfig` (public value, `alessandro823`) | change it only in a fork that makes its own releases | where the update check and Sparkle find the releases |
| Test GitHub App for development | Vernum-Projecten ("TEST Pullwatch"), values in `Pullwatch/Debug.xcconfig` | [github-app.md](github-app.md), "Development builds use a test app"; give it the same permissions as the release app (it has Repository security advisories; code and secret scanning, Checks and Commit statuses are not granted, so those show **Needs permission**) | Xcode's Run and the tests; replace with your own if you prefer |
| GitHub Pages, the repository variable `PAGES_DOMAIN` and the DNS of `pullwatch.net` | the repository's Pages settings and Actions variables; the zone at the registrar | [website.md](website.md) | the website at `https://pullwatch.net` (until then `https://alessandro823.github.io/pullwatch/`) |

The MCP server for coding agents needs nothing here either. Its helper,
`Contents/Helpers/pullwatch-mcp`, is signed by `scripts/release/release.sh`
with the same Developer ID and its own identifier, and notarised with the
app; the app accepts only that helper of its own team on its socket
([mcp.md](mcp.md)).

Azure DevOps needs nothing here: people sign in with the Azure CLI
(`az login`) or a personal access token of their own.

GitLab needs nothing here either. Each person makes a personal access token
with the `read_api` scope on gitlab.com or their own server (User settings,
Access tokens; the account editor's **Token maken** link opens that page with
the name and scope filled in), or signs in with the GitLab CLI
(`glab auth login --hostname <server>`). Pullwatch only reads, so `read_api`
is enough; `api` works too but gives more than it needs. A self-managed server
must be reachable over https; Pullwatch refuses plain http so the token never
travels unencrypted.

GitHub Enterprise needs nothing here either. Pullwatch talks to GitHub
Enterprise Server at `https://<server>/api/v3` (GraphQL at
`https://<server>/api/graphql`) and to GitHub Enterprise Cloud with data
residency (`https://<name>.ghe.com`) at `https://api.<name>.ghe.com` (GraphQL at
`https://api.<name>.ghe.com/graphql`). Each person signs in on that server,
which must be reachable over https:

- **Personal access token**, made on the server (Settings, Developer
  settings, Personal access tokens; the account editor's **Token maken** link
  opens the classic token page with the name and the scopes filled in).
  Classic: `repo` and `read:org`, plus `security_events` for code scanning
  and secret scanning alerts. Fine-grained (where the server has them):
  **Pull requests**, **Contents** and **Metadata** read-only on the
  repositories to follow, optionally **Code scanning alerts**, **Secret
  scanning alerts**, **Checks** and **Commit statuses** read-only (the last
  two for each pull request's checks cell; classic `repo` covers them).
- **GitHub CLI**: `gh auth login --hostname <server>`; Pullwatch then runs
  `gh auth token --hostname <server>` and lists the `gh` accounts of that host.

**Sign in with GitHub** is for github.com only. The Pullwatch GitHub App lives
on github.com; on a GitHub Enterprise Server a GitHub App has to be registered
on that server, with its own client ID, and a ghe.com enterprise likewise.
Letting a person enter such a client ID is left for later.

What a GitHub Enterprise server lacks shows as not available instead of an
error: GitHub Enterprise Server has no repository security advisories (the
repository page says **Niet beschikbaar op deze server**), code scanning and
secret scanning need GitHub Advanced Security on the server (without it they
show **Staat uit**), and a server whose GraphQL API misses a field Pullwatch
asks for tags and releases falls back to the REST API (tags then have no date
unless they have a release) and shows no co-authors. The GitHub Advisory
Database lookups keep going to `api.github.com`, without the server's token:
an enterprise token never leaves its own server. Other repositories you add to
an enterprise account are read with its token on that server only; the
fallback without a token that github.com accounts have is off there, because
GitHub Enterprise Server and GHE.com rarely allow reading without signing in.

## Repository settings

Settings of `alessandro823/pullwatch` that no file in the repository can
make. Each needs admin rights on the repository; the command under each
checks it. Set `repo=alessandro823/pullwatch` first.

- [ ] **Private vulnerability reporting** on (Settings, Advanced Security),
  so [SECURITY.md](../SECURITY.md) works. Turning it on also adds "Report a
  vulnerability" to the issue chooser; `.github/ISSUE_TEMPLATE/config.yml`
  therefore has no link of its own for it. Turn on with
  `gh api -X PUT repos/$repo/private-vulnerability-reporting`.

  ```bash
  gh api repos/$repo/private-vulnerability-reporting --jq .enabled   # true
  ```

- [ ] **Dependabot alerts** and **Dependabot security updates** on
  (Settings, Advanced Security). Version updates come from
  `.github/dependabot.yml` and need nothing here.

  ```bash
  gh api repos/$repo/vulnerability-alerts --silent && echo alerts on    # 404 when off
  gh api repos/$repo/automated-security-fixes --jq .enabled             # true
  ```

- [ ] **Secret scanning** and **push protection** on (Settings, Advanced
  Security).

  ```bash
  gh api repos/$repo --jq '.security_and_analysis | {secret_scanning, secret_scanning_push_protection}'
  # both "status": "enabled"
  ```

- [ ] **A ruleset for `main`** (Settings, Rules, Rulesets): a pull request
  before merging, and the required checks of CI (`shell scripts and
  workflows`, `PullwatchKit tests`, `app build, unit and UI tests`, `String
  Catalogs in step with the code`, `unsigned release build and disk image`)
  and Changelog (`changelog fragment`) and Website (`build and check
  links`), all from GitHub Actions. The Website workflow runs on every pull
  request and skips its build when nothing under `site/` changed; a skipped
  job counts as passed, so requiring it never blocks a pull request.
  `.github/CODEOWNERS` asks Alessandro and the fork's owner
  (`rubentalstra`) to review every change.

  ```bash
  gh api repos/$repo/rules/branches/main --jq '.[].type'
  # includes pull_request and required_status_checks
  gh api repos/$repo/rules/branches/main \
    --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context'
  ```

  To create it from the command line:

  ```bash
  gh api --method POST repos/$repo/rulesets --input - <<'JSON'
  {
    "name": "main",
    "target": "branch",
    "enforcement": "active",
    "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
    "rules": [
      { "type": "deletion" },
      { "type": "non_fast_forward" },
      { "type": "pull_request", "parameters": {
          "required_approving_review_count": 0,
          "dismiss_stale_reviews_on_push": false,
          "require_code_owner_review": false,
          "require_last_push_approval": false,
          "required_review_thread_resolution": false } },
      { "type": "required_status_checks", "parameters": {
          "strict_required_status_checks_policy": false,
          "required_status_checks": [
            { "context": "shell scripts and workflows", "integration_id": 15368 },
            { "context": "PullwatchKit tests", "integration_id": 15368 },
            { "context": "app build, unit and UI tests", "integration_id": 15368 },
            { "context": "String Catalogs in step with the code", "integration_id": 15368 },
            { "context": "unsigned release build and disk image", "integration_id": 15368 },
            { "context": "changelog fragment", "integration_id": 15368 },
            { "context": "build and check links", "integration_id": 15368 }
          ] } }
    ]
  }
  JSON
  ```

  (`15368` is the app id of GitHub Actions.)

- [ ] **Discussions** off: questions go to the
  [FAQ](https://pullwatch.net/faq/) and to Issues, as
  `.github/ISSUE_TEMPLATE/config.yml` and [SUPPORT.md](../SUPPORT.md) say.

  ```bash
  gh api repos/$repo --jq .has_discussions   # false
  ```

- [ ] **Reported content** from all users (Settings, Moderation options,
  Reported content), so the reports [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md)
  points to reach the maintainer. There is no REST API for this setting;
  check it on that page.

- [ ] **Description, website and topics** (the About box on the
  repository's front page).

  ```bash
  gh api repos/$repo --jq '{description, homepage, topics}'
  gh repo edit $repo \
    --description "Pull requests, tags and outdated dependencies, watched from your Mac's menu bar." \
    --homepage https://pullwatch.net \
    --add-topic macos,swiftui,menu-bar-app,github,gitlab,azure-devops,pull-requests,mcp
  ```

## Time Sensitive notifications (not used)

Pullwatch could let a new critical or high vulnerability break through Focus
with `UNNotificationInterruptionLevel.timeSensitive`, but it does not, and
there is no setting for it. On macOS that level needs the entitlement
`com.apple.developer.usernotifications.time-sensitive`. Apple lists Time
Sensitive Notifications as supported for Developer ID apps (Supported
capabilities, macOS), but like every `com.apple.developer.*` entitlement it
only works when an embedded provisioning profile allows it; an app signed
with the entitlement and without such a profile does not launch.

Pullwatch has no provisioning profile today: debug builds are signed ad hoc
(`CODE_SIGN_IDENTITY = -`), and `scripts/release/release.sh` signs with the
Developer ID certificate only. To add it later, the maintainer would:

1. Register the App ID `nl.torrisi.pullwatch` in the Apple Developer account
   of Code24 BV and turn on **Time Sensitive Notifications**.
2. Create a **Developer ID** provisioning profile for that App ID, keep it with
   the release secrets, and embed it as
   `Pullwatch.app/Contents/embedded.provisionprofile` before signing in
   `release.sh` and `release.yml`.
3. Add an entitlements file with the key set to `true` for the Release
   configuration only, and check the signed app with
   `codesign -d --entitlements - Pullwatch.app`.
4. Then add the setting (off by default) and use `.timeSensitive` for a new
   critical or high vulnerability in a direct runtime dependency
   (`NotificationImportance` in `PullwatchCore`).

Until then those notifications are `.active` with the highest
`relevanceScore`, so they lead the stack but respect Focus.

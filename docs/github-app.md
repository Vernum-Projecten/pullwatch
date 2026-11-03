# The Pullwatch GitHub App

Pullwatch signs people in to GitHub through a GitHub App with the device
flow: the app shows a short code, the person enters it on
`github.com/login/device`, and Pullwatch receives a token. No `gh` CLI and no
personal access token are needed. The device flow uses no client secret, so
nothing secret goes into the app or this repository.

The app belongs to the Pullwatch maintainer (Alessandro, `alessandro823`).
Create it once with the settings below. Azure DevOps does not use it:
Azure DevOps accounts keep signing in with the Azure CLI (`az login`) or a
personal access token.

## 1. Create the app

GitHub, your profile picture, **Settings**, **Developer settings**, **GitHub
Apps**, **New GitHub App**:

| Field | Value |
|---|---|
| GitHub App name | `Pullwatch` (the name people see when they approve the sign-in and install it) |
| Homepage URL | `https://github.com/alessandro823/pullwatch` |
| Callback URL | leave empty |
| Expire user authorization tokens | **on** (a token lasts 8 hours and renews itself for 6 months) |
| Request user authorization (OAuth) during installation | off |
| Enable Device Flow | **on** |
| Setup URL | leave empty |
| Webhook | off (untick **Active**) |
| Where can this GitHub App be installed? | **Any account** (people install it on their own account and organisations) |

**Repository permissions**, all read-only, and nothing else:

| Permission | Access | Why Pullwatch needs it |
|---|---|---|
| Pull requests | Read-only | find new, merged and closed pull requests (`search/issues`) |
| Contents | Read-only | list tags; read files for the version and vulnerability checks (`git/trees`, `contents`) |
| Metadata | Read-only | required by GitHub; lists the repositories (`user/repos`, `orgs/{org}/repos`) |
| Repository security advisories | Read-only | the advisories a repository publishes about itself, on its page in Pullwatch (`repos/{owner}/{repo}/security-advisories?state=published`) |
| Code scanning alerts | Read-only, optional | open CodeQL and other code scanning alerts on the repository page, in its findings and health, and (when turned on) a notification for a new critical or high one (`repos/{owner}/{repo}/code-scanning/alerts?state=open`) |
| Secret scanning alerts | Read-only, optional | only the number of open secrets, with a link to GitHub; Pullwatch asks with `hide_secret=true` and never reads a secret (`repos/{owner}/{repo}/secret-scanning/alerts?state=open`) |

Without the two optional permissions Pullwatch works as before: the
repository page shows **Needs permission** next to Code scanning or Secret
scanning, quietly, and nothing else changes. Add them only if the people who
use Pullwatch want those alerts in it.

The details of GitHub's own advisories (severity, CVSS score and vector,
CWE, the page on `github.com/advisories`) for the vulnerabilities Pullwatch
finds come from the public GitHub Advisory Database (`GET /advisories/{ghsa_id}`,
and `GET /advisories?cve_id=` when OSV only knows the CVE). That needs no
permission; Pullwatch sends the app's token for the higher rate limit, and
fetches each advisory once, not per repository or per check.

No organisation permissions, no account permissions, no events.

Click **Create GitHub App**.

## 2. Copy two values into the app

On the new app's **General** page:

- **Client ID** (starts with `Iv`).
- The app's **public link** `https://github.com/apps/<slug>`: the `<slug>`
  is the name in lower case (`pullwatch` if that name was free).

Put both in `Pullwatch/Release.xcconfig` (release builds):

```text
PW_GITHUB_CLIENT_ID = Iv23li...
PW_GITHUB_APP_SLUG = pullwatch
```

and land the change through a pull request. While these are empty, a
release offers a token instead of **Sign in with GitHub**. Both values are public: the
client id only identifies the app and grants nothing by itself. Leave
**Generate a new client secret** and **Generate a private key** alone;
Pullwatch uses neither, and neither may ever enter this repository.

### Development builds use a test app

`Pullwatch/Debug.xcconfig` (Xcode's Run, the tests) points at a separate test
app with the same settings: **TEST Pullwatch** of Vernum-Projecten
(`github.com/apps/test-pullwatch`), so trying things out never touches the
real app's users. To use your own test app on your Mac, create one with the
settings above and put its values in `Pullwatch/Local.xcconfig`, which git
ignores:

```text
PW_GITHUB_CLIENT_ID = Iv23li...
PW_GITHUB_APP_SLUG = my-pullwatch-test
```

## 3. What a person does

1. In Pullwatch: add a GitHub account, **Sign in with GitHub**. Pullwatch
   shows a code and opens `github.com/login/device`; the person enters the
   code and approves Pullwatch.
2. **Install the app** where their repositories are: Pullwatch links to
   `https://github.com/apps/<slug>/installations/new`. On their own account
   they can install it right away. On an organisation, an organisation owner
   installs it, or approves the request a member sends from that page.
   They choose **All repositories** or **Only select repositories**.
3. Pullwatch lists where the app is installed (their account first, then
   the organisations); they pick one, and Pullwatch lists its repositories
   to follow. Coming back from the installation page refreshes the list.

A GitHub App token only reaches repositories the app is installed on. A
repository that is missing in Pullwatch usually means the app is not
installed on it (or the person has no access); adding it on the
installation page fixes that without signing in again.

## 4. What the token can do

The token is a user-to-server token: it acts as the person who signed in,
limited to the read-only permissions above, and to repositories where
both that person and the installation have access. Pullwatch cannot write
anything, comment, merge or change settings.

The token and its refresh token live in the login Keychain of the Mac that
signed in, never in a file. Removing the account in Pullwatch deletes them.
To cut a Mac off: the person revokes Pullwatch under GitHub, **Settings**,
**Applications**, **Authorized GitHub Apps**; an organisation can suspend or
uninstall the installation.

## 5. Later changes

- **More permissions**: changing a permission makes every installation ask
  its owner to accept the change before it applies. Ask only for read-only
  access, and only when a feature needs it. The next section says what the
  owner sees.
- **A new client id** (a second app, or a recreated one) signs everyone out
  at their next refresh; avoid it.

## 6. When the app asks for a new permission

Saving a permission change on the app's **Permissions & events** page (with
a short note on why) does not give it to anyone yet. GitHub emails the owner
of every installation, and each installation keeps the old permissions until
its owner accepts:

- **On a personal account**: GitHub, **Settings**, **Applications**,
  **Installed GitHub Apps**, **Configure** next to Pullwatch, then
  **Review request** and **Accept new permissions**.
- **On an organisation**: an owner opens the organisation's **Settings**,
  **GitHub Apps**, **Configure** next to Pullwatch, then **Review request**
  and **Accept new permissions**.

The installation page is also reachable from the app's public link,
`https://github.com/apps/<slug>/installations/new`, which lists the accounts
where it is installed.

Until an owner accepts, GitHub answers 403 for the new data. Pullwatch does
not treat that as an error: the account keeps working, and the repository
page shows **Needs permission** next to that kind with an **Approve** link to
the installations page (`github.com/settings/installations`, or
`github.com/organizations/<org>/settings/installations` for an
organisation). A feature GitHub has turned off for a repository (no code
scanning set up, secret scanning disabled) shows as **Off**. The next daily
check, or **Check** on the repository page, reads the data once the owner
has accepted.

The test app **TEST Pullwatch** and the release app **Pullwatch** each have
their own permissions: a change to one has to be made on the other as well,
and its installations accept it separately.

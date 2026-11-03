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

No organisation permissions, no account permissions, no events.

Click **Create GitHub App**.

## 2. Copy two values into the app

On the new app's **General** page:

- **Client ID** (starts with `Iv`).
- The app's **public link** `https://github.com/apps/<slug>`: the `<slug>`
  is the name in lower case (`pullwatch` if that name was free).

Put both in `Pullwatch/App.xcconfig`:

```text
PW_GITHUB_CLIENT_ID = Iv23li...
PW_GITHUB_APP_SLUG = pullwatch
```

and land the change through a pull request. Both values are public: the
client id only identifies the app and grants nothing by itself. Leave
**Generate a new client secret** and **Generate a private key** alone;
Pullwatch uses neither, and neither may ever enter this repository.

## 3. What a person does

1. In Pullwatch: add a GitHub account, **Sign in with GitHub**. Pullwatch
   shows a code and opens `github.com/login/device`; the person enters the
   code and approves Pullwatch.
2. **Install the app** where their repositories are: Pullwatch links to
   `https://github.com/apps/<slug>/installations/new`. On their own account
   they can install it right away. On an organisation, an organisation owner
   installs it, or approves the request a member sends from that page.
   They choose **All repositories** or **Only select repositories**.
3. Pullwatch lists the repositories that both the person and the app can
   see, and they pick which to follow.

A GitHub App token only reaches repositories the app is installed on. A
repository that is missing in Pullwatch usually means the app is not
installed on it (or the person has no access); adding it on the
installation page fixes that without signing in again.

## 4. What the token can do

The token is a user-to-server token: it acts as the person who signed in,
limited to the three read-only permissions above, and to repositories where
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
  access, and only when a feature needs it.
- **A new client id** (a second app, or a recreated one) signs everyone out
  at their next refresh; avoid it.

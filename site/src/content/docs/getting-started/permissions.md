---
title: Token permissions
description: The scopes and permissions Pullwatch needs on GitHub, GitHub Enterprise, Azure DevOps, GitLab, Bitbucket, Codeberg, Forgejo and Gitea.
---

Pullwatch only reads. Give a token the read permissions below and nothing more. When a permission for an optional part is missing, that part says **Needs permission** with a link, and the rest keeps working.

## GitHub

**Fine-grained token**, on the repositories you want to follow:

| Permission | Needed for |
|---|---|
| Pull requests: Read | pull requests |
| Metadata: Read | repositories (always required) |
| Contents: Read | the dependency check (manifests and lockfiles) |
| Repository security advisories: Read | the repository's own advisories |
| Code scanning alerts: Read | optional, code scanning alerts |
| Secret scanning alerts: Read | optional, the number of open secret scanning alerts |
| Checks: Read and Commit statuses: Read | optional, the checks of each pull request |

**Classic token**: `repo`, plus `security_events` for the code scanning and secret scanning alerts, and optionally `read:packages` for the packages your repositories publish to GitHub Packages. With the GitHub CLI, add that scope with `gh auth refresh -s read:packages`.

**Sign In with GitHub** uses the Pullwatch GitHub App. It asks for these repository permissions, all read-only, and nothing else:

| Permission | Access | What it is for | Without it |
|---|---|---|---|
| Metadata | Read-only, mandatory | the repositories of the owners you follow | GitHub does not allow an app without it |
| Pull requests | Read-only | pull requests, their co-authors and merge queue | no pull requests |
| Contents | Read-only | tags, releases and the files of the dependency check | no tags or releases, no dependency check |
| Repository security advisories | Read-only | the repository's own advisories | **Needs permission** on the repository page |
| Checks | Read-only | the check runs in each pull request's checks | no checks for pull requests |
| Commit statuses | Read-only | the commit statuses in the same checks | no checks for pull requests |
| Code scanning alerts | Read-only, optional | code scanning alerts | **Needs permission** next to them |
| Secret scanning alerts | Read-only, optional | the number of open secret scanning alerts | **Needs permission** next to them |

The owner of each installation accepts them; when the app gains a new permission, GitHub asks the owner to accept it once more.

The app has no Packages permission: GitHub refuses packages to every GitHub App. An account that signs in with GitHub reads the packages its repositories publish with the GitHub CLI instead. **Read packages with the GitHub CLI** in the account editor is on when `gh` is logged in, and shows which `gh` account it uses. That account needs the `read:packages` scope: `gh auth refresh -h github.com -s read:packages`. Without `gh`, without the scope, or with the switch off, **Packages** shows **Needs permission** with the exact command.

## GitHub Enterprise

Make the token on your own server. Classic: `repo` and `read:org`, plus `security_events` for the alerts. **Create token** in the account editor opens the server's token page with these filled in. Fine-grained tokens need the same permissions as on github.com.

With the GitHub CLI, Pullwatch runs `gh auth token --hostname <server>`. Log in first with `gh auth login --hostname <server>`.

## Azure DevOps

| Scope | Needed for |
|---|---|
| Code (Read) | pull requests, tags and the dependency check |
| Project and Team (Read) | the list of projects |
| Advanced Security (Read) | optional, Advanced Security alerts |
| Packaging (Read) | optional, the packages in your Azure Artifacts feeds |

With the Azure CLI, sign in with `az login`; Pullwatch asks `az` for a token.

## GitLab

A personal access token with the **read_api** scope covers merge requests, projects, tags, releases, commits and files, and the packages and container images your projects publish to GitLab's registries. `api` works too, but gives more than Pullwatch needs. With the GitLab CLI, Pullwatch reads `glab config get token --host <server>`.

## Bitbucket

An Atlassian **API token with scopes** for the app Bitbucket, together with the email address of your Atlassian account:

| Scope | Needed for |
|---|---|
| `read:user:bitbucket` | your own account, to hide your own pull requests |
| `read:repository:bitbucket` | repositories, tags, build statuses (the checks) and the dependency check |
| `read:pullrequest:bitbucket` | pull requests and their commits (the co-authors) |

These three are all Pullwatch asks for. `read:workspace:bitbucket` is not needed: Pullwatch checks a workspace through its repositories. Bitbucket's app passwords stopped working in July 2026.

## Codeberg, Forgejo and Gitea

Make a token under Settings, Applications on the server, with these scopes, all on Read:

| Scope | Used for |
|---|---|
| `read:user` | who you are, and the repositories of users you follow |
| `read:organization` | the organizations you follow and their repositories |
| `read:repository` | pull requests, tags, releases, commit statuses (checks), commits and files |
| `read:issue` | the list of pull requests, which comes from the issue search (`/repos/issues/search`) |

Without one of them, **Test connection** names the scope that is missing. A token limited to public repositories works for public repositories only. There is no command-line sign-in: the `tea` tool has no command that hands out its token.

## Signing in with a command-line tool

With `gh`, `az` or `glab`, Pullwatch gets the token from the command-line tool, so you sign in there and not in Pullwatch. Calls to these tools time out after 20 seconds.

---
title: Token permissions
description: The scopes and permissions Pullwatch needs on GitHub, GitHub Enterprise, Azure DevOps, GitLab and Bitbucket.
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

**Classic token**: `repo`, plus `security_events` for the code scanning and secret scanning alerts.

**Sign In with GitHub** uses the Pullwatch GitHub App, which asks for the same read permissions. The owner of each installation accepts them; when the app gains a new permission, GitHub asks the owner to accept it once more.

## GitHub Enterprise

Make the token on your own server. Classic: `repo` and `read:org`, plus `security_events` for the alerts. **Create token** in the account editor opens the server's token page with these filled in. Fine-grained tokens need the same permissions as on github.com.

With the GitHub CLI, Pullwatch runs `gh auth token --hostname <server>`. Log in first with `gh auth login --hostname <server>`.

## Azure DevOps

| Scope | Needed for |
|---|---|
| Code (Read) | pull requests, tags and the dependency check |
| Project and Team (Read) | the list of projects |
| Advanced Security (Read) | optional, Advanced Security alerts |

With the Azure CLI, sign in with `az login`; Pullwatch asks `az` for a token.

## GitLab

A personal access token with the **read_api** scope covers merge requests, projects, tags, releases, commits and files. `api` works too, but gives more than Pullwatch needs. With the GitLab CLI, Pullwatch reads `glab config get token --host <server>`.

## Bitbucket

An Atlassian **API token with scopes** for the app Bitbucket, together with the email address of your Atlassian account:

| Scope | Needed for |
|---|---|
| `read:user:bitbucket` | your own account, to hide your own pull requests |
| `read:repository:bitbucket` | repositories, tags, build statuses (the checks) and the dependency check |
| `read:pullrequest:bitbucket` | pull requests and their commits (the co-authors) |

These three are all Pullwatch asks for. `read:workspace:bitbucket` is not needed: Pullwatch checks a workspace through its repositories. Bitbucket's app passwords stopped working in July 2026.

## Signing in with a command-line tool

With `gh`, `az` or `glab`, Pullwatch gets the token from the command-line tool, so you sign in there and not in Pullwatch. Calls to these tools time out after 20 seconds.

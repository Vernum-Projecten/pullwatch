---
title: Add your accounts
description: Connect GitHub, GitHub Enterprise, Azure DevOps and GitLab, and choose which repositories Pullwatch follows.
---

Open **Settings** (the gear button in the menu panel) and go to **Accounts**. Add an account with **+**, choose how Pullwatch signs in, and use **Test connection** to check it. You can add as many accounts as you like, of any kind.

Pullwatch only reads. It never comments, merges or changes anything on your servers.

## GitHub

There are three ways to sign in on github.com:

- **Sign In with GitHub.** Pullwatch shows a code, you confirm it on github.com, and the Pullwatch GitHub App gets read access to the repositories you choose when you install it. The app asks only for read permissions.
- **Personal access token.** Paste a token you made yourself. See [Token permissions](/getting-started/permissions/) for the scopes.
- **GitHub CLI.** If you use `gh` (`gh auth login`), Pullwatch asks it for a token. With several `gh` accounts, pick the one to use under **GitHub account**.

## GitHub Enterprise

Choose **GitHub Enterprise** on the GitHub card (or in the **+** menu) and enter your server under **Server**:

- a GitHub Enterprise Server, such as `https://github.example.com`, or
- your enterprise's subdomain on GHE.com, such as `https://acme.ghe.com`.

Only https works, so a token never travels unencrypted. Pullwatch finds the API by itself and links to pull requests, tags and repositories on that server. Sign in with a personal access token made on that server, or with the GitHub CLI after `gh auth login --hostname <server>`. **Sign In with GitHub** is for github.com only.

Some things a server does not have show as **Not available on this server** instead of an error, such as a repository's own security advisories on GitHub Enterprise Server.

## Azure DevOps

Enter your organization, then sign in with a personal access token or with the Azure CLI (`az login`). Pullwatch reads the projects of the organization and their repositories.

## GitLab

Leave **Server** empty for gitlab.com, or enter your own server (https only, for example `https://gitlab.example.com`). List the groups or users to follow, separated by commas, such as `acme, acme/platform`. A group includes its subgroups, and repositories appear as `group/subgroup/project`.

Sign in with a personal access token with the `read_api` scope, or with the GitLab CLI (`glab auth login`). **Create token** in the account editor opens your server's token page with the name and scope filled in.

## Choose what to follow

Each account lists its repositories. Per repository, tick what you want:

- **PRs**: new pull requests (or merge requests).
- **Tags**: new tags, and on GitHub and GitLab the releases made for them. Tags are off by default.
- **Merged**: pull requests that get merged.

Next to each tick is a bell. Turn it off to keep a repository in the menu and the history without notifications. The bell in the header switches all visible repositories at once. Per account you can also include draft pull requests, hide your own, and turn the whole account off for a while.

## Repositories outside your account

Under **Other repositories** at the bottom of the list, add a single repository that is not part of the account's owners or groups:

- GitHub: `owner/repo`, or paste a github.com link.
- Azure DevOps: `project/repo` inside the account's organization, or a dev.azure.com link.
- GitLab: `group/subgroup/project`, or a link from gitlab.com or the account's own server.

Pullwatch checks it with one request and tells you in plain words when it cannot find or read it. A public repository on github.com or gitlab.com that your token may not read is read without signing in. **Watch a Repository…** (⇧⌘N, in the File menu and in the toolbar of Repositories) opens the same field with a choice of account. Remove one with a right click or the Delete key.

Such a repository shows up everywhere like the others you follow, grouped under its own owner.

- **GitHub**: this also works for a public repository of another organization where the Pullwatch GitHub App is not installed, such as `openEHR/specifications-AM`. The pull requests of these repositories come in one search per account, with up to 30 repositories per search.
- **GitLab**: links from gitlab.com or the account's own server work, also `/-/` links such as `/-/merge_requests/12`; a link to another server is refused. A public project is read without signing in only when the server answers without a token: gitlab.com does, a server that requires signing in does not, and then the project is not found. Each such project costs one request per poll for its merge requests (one page, the 100 most recently updated).

## How often Pullwatch looks

Under Settings, General you set how often Pullwatch checks for new pull requests, and how long the history is kept (2 months, 6 months, 1 year or forever). Tags are checked every 15 minutes. **Refresh now** in the menu panel checks right away.

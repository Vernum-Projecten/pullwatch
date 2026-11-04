---
title: Privacy and sources
description: Where Pullwatch keeps your data, every connection it makes, and how to switch data sources off.
---

Pullwatch runs on your Mac and nowhere else. It has no account, no server of its own and no analytics. It talks to the servers of your accounts and to a few public services, and Settings, **Sources** lists every one of them.

## What stays on your Mac

- **Tokens** live in the macOS Keychain, under `nl.torrisi.pullwatch`. When you sign in with `gh`, `az` or `glab`, the token stays with that tool.
- **Settings, history and check results** are JSON files in `~/Library/Application Support/Pullwatch/`: `config.json`, `seen.json`, `history.json`, `versions.json` and `version-history.json`. Every full check adds a compact snapshot to `version-history.json` (versions, states, vulnerability counts and package updates per repository, at most 730 snapshots), kept for statistics over time.

Removing an account removes its history too.

## Settings, Sources

The Sources tab lists every outside service in plain language. Each row says what the source provides, the address Pullwatch calls, and links to its site.

**Vulnerabilities**

- **OSV.dev** (`api.osv.dev`): known vulnerabilities in your packages. Package names and versions are sent, also for private repositories. It is the only source for package vulnerabilities in GitHub and GitLab repositories.
- **GitHub Advisory Database** (`api.github.com/advisories`): severity, CVSS, CWE and links for each advisory, fetched once per advisory.
- **GitHub security**: the repository's own advisories, code scanning and secret scanning, from your GitHub account.
- **Azure DevOps Advanced Security**: its alerts, from your Azure DevOps account.

**Versions**

- The package registries: proxy.golang.org, registry.npmjs.org, repo.packagist.org, api.nuget.org, pypi.org, crates.io and rubygems.org. Package names are sent, also for private repositories.
- **Package registries of your accounts**: the packages and container images your followed repositories publish to GitHub Packages, the GitLab registries and Azure Artifacts, read once a day with the token of each account and sent nowhere else. In-house package names are never sent to the public registries or OSV.dev. Off: no registry of yours is read, the Packages section is empty, and in-house dependencies say "Not checked: source Package registries of your accounts is off".
- **endoflife.date**: release cycles and end-of-life dates of runtimes and frameworks.
- **swift.org**: the Swift releases.

**Pull requests**

- **CI checks** of pull requests. Off: no checks are fetched, shown or notified.

Each of these has a switch. A source that is off is called nowhere: not in the daily check, not when you check one repository again, not when advisories are completed. Wherever that leaves something unchecked, Pullwatch says so ("Not checked: source OSV.dev is off", "Version not checked: source npm is off") and never shows it as current or free of vulnerabilities. What an earlier check got from that source is hidden at once. Flipping a switch does not start a check; **Check now** runs one.

**Other connections** lists the rest, which have no switch of their own:

- the server of each account, for pull requests, tags, repositories, manifests and lockfiles;
- signing in to GitHub, for the GitHub App;
- profile pictures of your accounts and of the authors of pull requests and tags;
- the Pullwatch update check, which you turn off under Settings, General.

**Copy overview** puts the whole list, with the version, the date and the state of each source, on the clipboard as plain text, to paste into an email or chat, for example for your security team.

Everything is on by default. Your choice is stored in `config.json`, as `disabledSources`.

## Public repositories without a token

A public repository on github.com, gitlab.com or bitbucket.org that your token may not read is read without signing in. Pullwatch never sends one account's token to another server: a GitHub Enterprise token stays on its own server.

## Open-source software

The open-source software inside Pullwatch, with its version and license, is listed under [Acknowledgements](/acknowledgements/).

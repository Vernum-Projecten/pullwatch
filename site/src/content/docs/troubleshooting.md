---
title: Troubleshooting
description: What to do when notifications, accounts, checks or updates do not work as expected.
---

## I get no notifications

- When the menu panel says **Notifications are off in System Settings**, open System Settings, Notifications, Pullwatch and allow them.
- Check Settings, Notifications: each kind has its own switch, and **Quiet hours** keeps notifications silent and in Notification Center only.
- Check the bell next to the repository in Settings, Accounts. **Mute Repository** on a notification turns that bell off.
- Focus and Do Not Disturb hold back notifications from every app, Pullwatch included.
- The first tag poll of a repository is silent, and so are pull requests fetched for the history.

## An account shows an error

The menu panel shows each account with the state of its last poll. Open Settings, Accounts, select the account and use **Test connection**.

- **Token invalid or expired**: make a new token with the [permissions](/getting-started/permissions/) Pullwatch needs and save it.
- **Signed in with `gh`, `az` or `glab`**: sign in again in that tool (`gh auth login`, `az login`, `glab auth login`). Calls to these tools time out after 20 seconds.
- **A self-managed server**: it must be reachable over https; Pullwatch refuses plain http.

## A repository is missing

- With **Sign In with GitHub**, Pullwatch only sees repositories where the Pullwatch GitHub App is installed. Install it on another account or organization from the account editor.
- For GitLab, check the groups or users listed on the account. A group includes its subgroups.
- For a single repository outside your accounts, add it under **Other repositories**.

## Tags or branches of a repository stopped coming in

The token of the account can't read that repository: it was not found, or the token has no access to it. Settings, Accounts shows the number on the account, and the account lists the repositories under **Can’t Be Read with This Token**. The repository page and the Latest tag column in Repos mark them too.

- **Signed in with `gh`**: without a choice under **GitHub account**, the token comes from the active account in `gh`. After `gh auth switch` to a login without access, an organization's private repositories become unreadable. Pick the login that can read them.
- **A personal access token**: give it access to these repositories, or stop following them.

When access is back, the tags and branches that were missed come in on the next poll.

## A part of the repository page says Needs permission

The token or the GitHub App may not read that part, such as checks, code scanning or secret scanning. The link next to it leads to the permission. Everything else keeps working. See [Token permissions](/getting-started/permissions/).

## Something says Not checked

A data source is switched off under Settings, Sources, so Pullwatch did not check that part. Switch it on and click **Check now**.

## A runtime or package says Unknown or Can't be checked

Pullwatch could not read a version from the files, or the package is private or a Swift package, which no public registry knows. Maven and Gradle projects are not read.

## Keychain asks for access after every update

This only happens with a build you made yourself (from Xcode or ad hoc signed). Choose **Always Allow**. Releases from GitHub are signed with a Developer ID and do not ask.

## Two Pullwatch icons in the menu bar

You run a build from Xcode next to the installed app. Quit one with **Quit Pullwatch** in its menu panel.

## Logs

Pullwatch writes to the system log. Set the level under Settings, General, **Log Level**, then stream it in Terminal:

```sh
log stream --predicate 'subsystem == "nl.torrisi.pullwatch"'
```

Or open Console and search for `nl.torrisi.pullwatch`. If you found a bug, open an [issue on GitHub](https://github.com/alessandro823/pullwatch/issues) with what you did and what the log said, without tokens.

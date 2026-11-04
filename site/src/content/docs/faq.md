---
title: FAQ
description: Short answers to common questions about Pullwatch.
---

## Is Pullwatch free?

Yes. Pullwatch is open source under the [Apache 2.0 license](https://github.com/alessandro823/pullwatch/blob/main/LICENSE), and every release is on [GitHub](https://github.com/alessandro823/pullwatch/releases).

## Which Macs does it run on?

macOS 26.6 or later, on Apple silicon and on Intel. It is one universal app.

## Which services does it support?

GitHub (github.com, GitHub Enterprise Server and GHE.com), Azure DevOps, and GitLab (gitlab.com and your own server). See [Add your accounts](/getting-started/accounts/).

## Can Pullwatch change anything in my repositories?

No. It only reads: pull requests, tags, releases, repository files for the dependency check, and security alerts. It never comments, approves, merges or pushes.

## Does it send my code anywhere?

No source code leaves your Mac except to your own servers, where it came from. For the dependency check, package names and versions go to OSV.dev and the package registries. You can switch each of those off. See [Privacy and sources](/privacy/).

## How often does it check?

Pull requests at the interval you set under Settings, General. Tags every 15 minutes. The history of existing pull requests every 15 minutes. Dependencies and vulnerabilities once a day, which you can turn off, plus whenever you click **Check all** or **Check**.

## Why does a notification not have a sound?

Tags without a release, merged pull requests and new versions arrive quietly on purpose, in Notification Center only. During **Quiet hours**, nothing makes a sound. Focus and Do Not Disturb from macOS apply too.

## Can I follow a repository that is not mine?

Yes. Add it under **Other repositories** in its account, or with **Watch a Repository…** (⇧⌘N). A public repository on github.com or gitlab.com works even when your token cannot read it.

## Which languages does Pullwatch speak?

English, Dutch, German and French. It follows macOS, or you choose under Settings, General, **Language**.

## How do I update?

Pullwatch looks for updates once a day and installs them for you. See [Updates](/getting-started/install/#updates).

## Is Pullwatch affiliated with GitHub, GitLab or Microsoft?

No. GitHub is a trademark of GitHub, Inc., GITLAB is a trademark of GitLab Inc., and Azure DevOps is a trademark of the Microsoft group of companies.

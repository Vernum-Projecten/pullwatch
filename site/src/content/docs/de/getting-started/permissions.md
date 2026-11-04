---
title: Token-Berechtigungen
description: Die Scopes und Berechtigungen, die Pullwatch auf GitHub, GitHub Enterprise, Azure DevOps, GitLab, Bitbucket, Codeberg, Forgejo und Gitea braucht.
---

Pullwatch liest nur. Gib einem Token die unten genannten Leseberechtigungen und nichts weiter. Fehlt eine Berechtigung für einen optionalen Teil, zeigt dieser Teil **Berechtigung nötig** mit einem Link, und der Rest funktioniert weiter.

## GitHub

**Fine-grained token**, für die Repositories, denen du folgen willst:

| Berechtigung | Gebraucht für |
|---|---|
| Pull requests: Read | Pull Requests |
| Metadata: Read | Repositories (immer erforderlich) |
| Contents: Read | die Prüfung der Abhängigkeiten (Manifeste und Lockfiles) |
| Repository security advisories: Read | die eigenen Advisories des Repositorys |
| Code scanning alerts: Read | optional, Warnungen aus dem Code-Scanning |
| Secret scanning alerts: Read | optional, die Anzahl offener Warnungen aus dem Secret-Scanning |
| Checks: Read und Commit statuses: Read | optional, die Checks jedes Pull Requests |

**Classic token**: `repo`, dazu `security_events` für die Warnungen aus Code-Scanning und Secret-Scanning, und optional `read:packages` für die Pakete, die deine Repositories in GitHub Packages veröffentlichen. Mit der GitHub CLI fügst du diesen Scope mit `gh auth refresh -s read:packages` hinzu.

**Mit GitHub anmelden** nutzt die GitHub App von Pullwatch. Sie fragt nach diesen Berechtigungen für Repositories, alle nur lesend, und nach nichts sonst:

| Berechtigung | Zugriff | Wofür | Ohne sie |
|---|---|---|---|
| Metadata | Read-only, Pflicht | die Repositories der Eigentümer, denen du folgst | GitHub erlaubt keine App ohne sie |
| Pull requests | Read-only | Pull Requests, ihre Co-Autoren und die Merge Queue | keine Pull Requests |
| Contents | Read-only | Tags, Releases und die Dateien für die Prüfung der Abhängigkeiten | keine Tags oder Releases, keine Prüfung der Abhängigkeiten |
| Repository security advisories | Read-only | die eigenen Advisories des Repositorys | **Berechtigung nötig** auf der Seite des Repositorys |
| Checks | Read-only | die Check Runs in den Checks jedes Pull Requests | keine Checks bei Pull Requests |
| Commit statuses | Read-only | die Commit-Status in denselben Checks | keine Checks bei Pull Requests |
| Code scanning alerts | Read-only, optional | Warnungen aus dem Code-Scanning | **Berechtigung nötig** daneben |
| Secret scanning alerts | Read-only, optional | die Anzahl offener Warnungen aus dem Secret-Scanning | **Berechtigung nötig** daneben |

Der Owner jeder Installation akzeptiert sie. Bekommt die App eine neue Berechtigung, bittet GitHub den Owner, sie noch einmal zu akzeptieren.

Die App hat keine Berechtigung Packages: GitHub gibt Pakete an keine GitHub App heraus. Ein Konto, das sich mit GitHub anmeldet, liest die Pakete seiner Repositories deshalb mit der GitHub CLI. **Pakete mit der GitHub CLI lesen** im Konto-Editor ist an, wenn `gh` angemeldet ist, und zeigt, welches `gh`-Konto es nutzt. Dieses Konto braucht den Scope `read:packages`: `gh auth refresh -h github.com -s read:packages`. Ohne `gh`, ohne den Scope oder mit ausgeschaltetem Schalter zeigt **Pakete** **Berechtigung nötig** mit dem genauen Befehl.

## GitHub Enterprise

Erstelle das Token auf deinem eigenen Server. Classic: `repo` und `read:org`, dazu `security_events` für die Warnungen. **Token erstellen** im Kontoeditor öffnet die Token-Seite des Servers mit diesen Angaben bereits ausgefüllt. Fine-grained tokens brauchen dieselben Berechtigungen wie auf github.com.

Mit der GitHub CLI führt Pullwatch `gh auth token --hostname <server>` aus. Melde dich vorher mit `gh auth login --hostname <server>` an.

## Azure DevOps

| Scope | Gebraucht für |
|---|---|
| Code (Read) | Pull Requests, Tags und die Prüfung der Abhängigkeiten |
| Project and Team (Read) | die Liste der Projekte |
| Advanced Security (Read) | optional, Warnungen aus Advanced Security |
| Packaging (Read) | optional, die Pakete in deinen Feeds von Azure Artifacts |

Mit der Azure CLI meldest du dich mit `az login` an; Pullwatch fragt `az` nach einem Token.

## GitLab

Ein Personal Access Token mit dem Scope **read_api** deckt Merge Requests, Projekte, Tags, Releases, Commits und Dateien ab, dazu die Pakete und Container-Images, die deine Projekte in den Registries von GitLab veröffentlichen. `api` funktioniert auch, gibt aber mehr frei, als Pullwatch braucht. Mit der GitLab CLI liest Pullwatch `glab config get token --host <server>`.

## Bitbucket

Ein **API-Token mit Scopes** von Atlassian für die App Bitbucket, zusammen mit der E-Mail-Adresse deines Atlassian-Kontos:

| Scope | Benötigt für |
|---|---|
| `read:user:bitbucket` | dein eigenes Konto, um deine eigenen Pull Requests auszublenden |
| `read:repository:bitbucket` | Repositories, Tags, Build-Status (die Checks) und die Prüfung der Abhängigkeiten |
| `read:pullrequest:bitbucket` | Pull Requests und ihre Commits (die Co-Autoren) |

Mehr verlangt Pullwatch nicht. `read:workspace:bitbucket` ist nicht nötig: Pullwatch prüft einen Workspace über seine Repositories. Die App-Passwörter von Bitbucket funktionieren seit Juli 2026 nicht mehr.

## Codeberg, Forgejo und Gitea

Erstelle ein Token unter Einstellungen, Anwendungen auf dem Server, mit diesen Scopes, alle auf Lesen:

| Scope | Wofür |
|---|---|
| `read:user` | wer du bist, und die Repositories von Benutzern, denen du folgst |
| `read:organization` | die Organisationen, denen du folgst, und ihre Repositories |
| `read:repository` | Pull Requests, Tags, Releases, Commit-Statuses (Checks), Commits und Dateien |
| `read:issue` | die Liste der Pull Requests, die aus der Issue-Suche kommt (`/repos/issues/search`) |

Fehlt einer, nennt **Verbindung testen** den fehlenden Scope. Ein Token, das nur öffentliche Repositories darf, funktioniert nur für öffentliche Repositories. Eine Anmeldung über die Kommandozeile gibt es nicht: `tea` hat keinen Befehl, der sein Token herausgibt.

## Anmelden mit einem Kommandozeilenwerkzeug

Mit `gh`, `az` oder `glab` holt Pullwatch das Token vom Kommandozeilenwerkzeug. Du meldest dich also dort an und nicht in Pullwatch. Aufrufe dieser Werkzeuge brechen nach 20 Sekunden ab.

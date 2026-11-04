---
title: Token-Berechtigungen
description: Die Scopes und Berechtigungen, die Pullwatch auf GitHub, GitHub Enterprise, Azure DevOps und GitLab braucht.
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

**Classic token**: `repo`, dazu `security_events` für die Warnungen aus Code-Scanning und Secret-Scanning.

**Mit GitHub anmelden** nutzt die GitHub App von Pullwatch, die nach denselben Leseberechtigungen fragt. Der Owner jeder Installation akzeptiert sie. Bekommt die App eine neue Berechtigung, bittet GitHub den Owner, sie noch einmal zu akzeptieren.

## GitHub Enterprise

Erstelle das Token auf deinem eigenen Server. Classic: `repo` und `read:org`, dazu `security_events` für die Warnungen. **Token erstellen** im Kontoeditor öffnet die Token-Seite des Servers mit diesen Angaben bereits ausgefüllt. Fine-grained tokens brauchen dieselben Berechtigungen wie auf github.com.

Mit der GitHub CLI führt Pullwatch `gh auth token --hostname <server>` aus. Melde dich vorher mit `gh auth login --hostname <server>` an.

## Azure DevOps

| Scope | Gebraucht für |
|---|---|
| Code (Read) | Pull Requests, Tags und die Prüfung der Abhängigkeiten |
| Project and Team (Read) | die Liste der Projekte |
| Advanced Security (Read) | optional, Warnungen aus Advanced Security |

Mit der Azure CLI meldest du dich mit `az login` an; Pullwatch fragt `az` nach einem Token.

## GitLab

Ein Personal Access Token mit dem Scope **read_api** deckt Merge Requests, Projekte, Tags, Releases, Commits und Dateien ab. `api` funktioniert auch, gibt aber mehr frei, als Pullwatch braucht. Mit der GitLab CLI liest Pullwatch `glab config get token --host <server>`.

## Anmelden mit einem Kommandozeilenwerkzeug

Mit `gh`, `az` oder `glab` holt Pullwatch das Token vom Kommandozeilenwerkzeug. Du meldest dich also dort an und nicht in Pullwatch. Aufrufe dieser Werkzeuge brechen nach 20 Sekunden ab.

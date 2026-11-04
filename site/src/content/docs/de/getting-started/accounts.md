---
title: Konten hinzufügen
description: GitHub, GitHub Enterprise, Azure DevOps und GitLab verbinden und wählen, welchen Repositories Pullwatch folgt.
---

Öffne **Einstellungen** (die Zahnrad-Schaltfläche im Menü) und geh zu **Konten**. Füge mit **+** ein Konto hinzu, wähle, wie Pullwatch sich anmeldet, und prüfe es mit **Verbindung testen**. Du kannst beliebig viele Konten jeder Art hinzufügen.

Pullwatch liest nur. Es kommentiert, merged und ändert nie etwas auf deinen Servern.

## GitHub

Auf github.com kannst du dich auf drei Arten anmelden:

- **Mit GitHub anmelden.** Pullwatch zeigt einen Code, du bestätigst ihn auf github.com, und die GitHub App von Pullwatch bekommt Lesezugriff auf die Repositories, die du bei ihrer Installation auswählst. Die App fragt nur nach Leseberechtigungen.
- **Personal Access Token.** Füge ein Token ein, das du selbst erstellt hast. Die Scopes stehen unter [Token-Berechtigungen](/de/getting-started/permissions/).
- **GitHub CLI.** Nutzt du `gh` (`gh auth login`), fragt Pullwatch dort nach einem Token. Hast du mehrere Konten in `gh`, wähle unter **GitHub-Konto** das gewünschte.

## GitHub Enterprise

Wähle **GitHub Enterprise** auf der GitHub-Karte (oder im Menü **+**) und gib deinen Server unter **Server** ein:

- einen GitHub Enterprise Server, etwa `https://github.example.com`, oder
- die Subdomain deines Unternehmens auf GHE.com, etwa `https://acme.ghe.com`.

Nur https funktioniert, damit ein Token nie unverschlüsselt übertragen wird. Pullwatch findet die API selbst und verlinkt auf Pull Requests, Tags und Repositories auf diesem Server. Melde dich mit einem Personal Access Token an, das auf diesem Server erstellt wurde, oder mit der GitHub CLI nach `gh auth login --hostname <server>`. **Mit GitHub anmelden** gilt nur für github.com.

Was ein Server nicht hat, erscheint als **Auf diesem Server nicht verfügbar** statt als Fehler, etwa die eigenen Sicherheits-Advisories eines Repositorys auf GitHub Enterprise Server.

## Azure DevOps

Gib deine Organisation ein und melde dich mit einem Personal Access Token oder mit der Azure CLI (`az login`) an. Pullwatch liest die Projekte der Organisation und ihre Repositories.

## GitLab

Lass **Server** für gitlab.com leer, oder gib deinen eigenen Server ein (nur https, zum Beispiel `https://gitlab.example.com`). Trage die Gruppen oder Benutzer ein, denen du folgen willst, durch Kommas getrennt, etwa `acme, acme/platform`. Eine Gruppe umfasst ihre Untergruppen, und Repositories erscheinen als `group/subgroup/project`.

Melde dich mit einem Personal Access Token mit dem Scope `read_api` an, oder mit der GitLab CLI (`glab auth login`). **Token erstellen** im Kontoeditor öffnet die Token-Seite deines Servers mit ausgefülltem Namen und Scope.

## Wählen, was du verfolgst

Jedes Konto listet seine Repositories. Hake pro Repository an, was du möchtest:

- **PRs**: neue Pull Requests (oder Merge Requests).
- **Tags**: neue Tags und bei GitHub und GitLab die Releases dazu. Tags sind standardmäßig aus.
- **Gemergt**: Pull Requests, die gemergt werden.

Neben jedem Haken ist eine Glocke. Schalte sie aus, um ein Repository ohne Mitteilungen im Menü und im Verlauf zu behalten. Die Glocke in der Kopfzeile schaltet alle sichtbaren Repositories auf einmal. Pro Konto kannst du außerdem Entwurfs-PRs einbeziehen, deine eigenen ausblenden und das ganze Konto eine Weile ausschalten.

## Repositories außerhalb deines Kontos

Unter **Andere Repositorys** unten in der Liste fügst du ein einzelnes Repository hinzu, das nicht zu den Ownern oder Gruppen des Kontos gehört:

- GitHub: `owner/repo`, oder füge einen Link von github.com ein.
- Azure DevOps: `project/repo` innerhalb der Organisation des Kontos, oder ein Link von dev.azure.com.
- GitLab: `group/subgroup/project`, oder ein Link von gitlab.com oder vom eigenen Server des Kontos.

Pullwatch prüft es mit einer Anfrage und sagt dir in klaren Worten, wenn es das Repository nicht finden oder lesen kann. Ein öffentliches Repository auf github.com oder gitlab.com, das dein Token nicht lesen darf, wird ohne Anmeldung gelesen. **Einem Repository folgen…** (⇧⌘N, im Menü Ablage und in der Symbolleiste von Repositories) öffnet dasselbe Feld mit einer Auswahl des Kontos. Entferne eines per Rechtsklick oder mit der Entfernen-Taste.

Ein solches Repository erscheint überall wie die anderen, denen du folgst, gruppiert unter seinem eigenen Owner.

- **GitHub**: Das funktioniert auch für ein öffentliches Repository einer anderen Organisation, in der die GitHub App von Pullwatch nicht installiert ist, etwa `openEHR/specifications-AM`. Die Pull Requests dieser Repositories kommen mit einer Suche pro Konto, mit bis zu 30 Repositories pro Suche.
- **GitLab**: Links von gitlab.com oder vom eigenen Server des Kontos funktionieren, auch Links mit `/-/` wie `/-/merge_requests/12`. Ein Link zu einem anderen Server wird abgelehnt. Ein öffentliches Projekt wird nur dann ohne Anmeldung gelesen, wenn der Server ohne Token antwortet: gitlab.com tut das, ein Server, der eine Anmeldung verlangt, nicht, und dann wird das Projekt nicht gefunden. Jedes solche Projekt kostet pro Abfrage eine Anfrage für seine Merge Requests (eine Seite, die 100 zuletzt aktualisierten).

## Wie oft Pullwatch nachsieht

Unter Einstellungen, Allgemein legst du fest, wie oft Pullwatch nach neuen Pull Requests sucht und wie lange der Verlauf aufbewahrt wird (2 Monate, 6 Monate, 1 Jahr oder Immer). Tags werden alle 15 Minuten geprüft. **Jetzt aktualisieren** im Menü prüft sofort.

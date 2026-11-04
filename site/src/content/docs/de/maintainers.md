---
title: Für Maintainer
description: Wo die Dokumentation für Maintainer liegt und wie du Pullwatch aus dem Quellcode baust.
---

Die Dokumentation für Maintainer liegt im Repository, neben dem Code, den sie beschreibt. So ändert sie sich im selben Pull Request.

| Dokument | Inhalt |
|---|---|
| [docs/setup.md](https://github.com/alessandro823/pullwatch/blob/main/docs/setup.md) | Alles, was der Maintainer außerhalb des Codes einrichtet: Signierung, die GitHub App, die Secrets für Releases |
| [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) | Der Ablauf eines Releases und seine Actions-Secrets |
| [docs/github-app.md](https://github.com/alessandro823/pullwatch/blob/main/docs/github-app.md) | Die GitHub App hinter **Mit GitHub anmelden** |
| [docs/website.md](https://github.com/alessandro823/pullwatch/blob/main/docs/website.md) | Diese Website: GitHub Pages, die eigene Domain und ihre DNS-Einträge |
| [site/README.md](https://github.com/alessandro823/pullwatch/blob/main/site/README.md) | Diese Website starten und bauen, und eine Seite hinzufügen |
| [CHANGELOG.md](https://github.com/alessandro823/pullwatch/blob/main/CHANGELOG.md) | Die Versionshinweise jeder Version |

## Aus dem Quellcode bauen

Du brauchst Xcode 27 (Swift 6.4) auf macOS 26.6 oder neuer. Optional `az` (`az login`), `gh` (`gh auth login`) oder `glab` (`glab auth login`), um dich über ein Kommandozeilenwerkzeug anzumelden.

Öffne `Pullwatch/Pullwatch.xcodeproj` und starte das Scheme **Pullwatch** (⌘R), oder auf der Kommandozeile:

```sh
swift test --package-path PullwatchKit              # the PullwatchKit unit tests
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch build
scripts/release/release.sh --unsigned               # dist/Pullwatch-<version>.dmg and .zip, ad hoc signed
scripts/release/release.sh                          # signed with Developer ID, notarized and stapled
```

Startest du aus Xcode, während ein installiertes Pullwatch offen ist, hast du zwei Symbole in der Menüleiste. Beende das installierte vorher mit **Pullwatch beenden** in seinem Menü. Ein ad hoc signierter Build kann bei Konten mit Token nach jeder Installation erneut nach Zugriff auf den Schlüsselbund fragen. Wähle dann **Immer erlauben**.

## Das Repository

- `Pullwatch/`: die App mit dem Xcode-Projekt. `Pullwatch/Pullwatch/` hat einen Ordner pro Funktion mit Modell und Views, etwa `Accounts/`, `PullRequests/`, `Repositories/` und `Settings/`.
- `PullwatchKit/`: das Swift-Paket, das die App einbindet, mit den Unit-Tests. Seine Module sind `PullwatchCore` (Modelle, Abfragen, Verlauf, Versionsprüfungen, Updates), `PullwatchGitHub`, `PullwatchAzureDevOps` und `PullwatchGitLab` (eines pro Dienst), `PullwatchProviders` (wählt den Dienst für ein Konto) und `PullwatchMCP` (der Server für Coding-Agenten).
- `site/`: diese Website. `scripts/`: die Skripte für Releases, Prüfungen und Entwicklung. `docs/`: die oben genannten Dokumente für Maintainer.

## Einen Release-Build erstellen

`release.sh` baut die App, entfernt die XPC-Dienste von Sparkle (nur eine App in der Sandbox braucht sie) und signiert die Teile von Sparkle einzeln. Dann übergibt es die App an `scripts/release/package.sh`. Das erstellt das Disk-Image und `Pullwatch-<version>.zip`, das Update, das Sparkle installiert. Der Release-Workflow schreibt dafür die signierte `appcast.xml`.

Das Disk-Image öffnet sich als Installationsfenster: links die App, rechts Programme, und ein Hintergrund, den `scripts/release/dmg-background.swift` zeichnet, mit „Install Pullwatch“ und einem Pfeil dazwischen. Der Finder ordnet dieses Fenster über AppleScript an. Beim ersten Lauf wirst du deshalb gefragt, ob dein Terminal den Finder steuern darf. Erlaube es unter Systemeinstellungen, Datenschutz & Sicherheit, Automation.

Die Version ist `MARKETING_VERSION` und die Build-Nummer `CURRENT_PROJECT_VERSION`, beide in `Pullwatch/App.xcconfig`. Ein signiertes Release braucht ein Zertifikat „Developer ID Application“ im Schlüsselbund und ein notarytool-Profil (`xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>`). Andere wählst du mit `SIGN_ID=...` und `NOTARY_PROFILE=...`. [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) beschreibt den vollständigen Ablauf.

---
title: Datenschutz und Quellen
description: Wo Pullwatch deine Daten speichert, welche Verbindungen es aufbaut und wie du Datenquellen ausschaltest.
---

Pullwatch läuft auf deinem Mac und nirgendwo sonst. Es hat kein eigenes Konto, keinen eigenen Server und keine Analysedienste. Es spricht mit den Servern deiner Konten und mit ein paar öffentlichen Diensten, und unter Einstellungen, **Quellen** steht jeder davon.

## Was auf deinem Mac bleibt

- **Tokens** liegen im Schlüsselbund von macOS, unter `nl.torrisi.pullwatch`. Meldest du dich mit `gh`, `az` oder `glab` an, bleibt das Token bei diesem Werkzeug.
- **Einstellungen, Verlauf und Prüfergebnisse** sind JSON-Dateien in `~/Library/Application Support/Pullwatch/`: `config.json`, `seen.json`, `history.json`, `versions.json` und `version-history.json`. Jede vollständige Prüfung fügt `version-history.json` eine kompakte Momentaufnahme hinzu (Versionen, Status, Anzahl der Schwachstellen und Paket-Updates pro Repository, höchstens 730 Momentaufnahmen). Sie dienen den Statistiken über die Zeit.

Entfernst du ein Konto, wird auch sein Verlauf entfernt.

## Einstellungen, Quellen

Der Tab Quellen listet jeden externen Dienst in einfacher Sprache auf. Jede Zeile sagt, was die Quelle liefert, welche Adresse Pullwatch aufruft, und verlinkt auf ihre Website.

**Sicherheitslücken**

- **OSV.dev** (`api.osv.dev`): bekannte Schwachstellen in deinen Paketen. Paketnamen und Versionen werden gesendet, auch bei privaten Repositories. Es ist die einzige Quelle für Schwachstellen in Paketen bei Repositories auf GitHub und GitLab.
- **GitHub Advisory Database** (`api.github.com/advisories`): Schweregrad, CVSS, CWE und Links zu jedem Advisory, einmal pro Advisory abgerufen.
- **GitHub-Sicherheit**: die eigenen Advisories des Repositorys, Code-Scanning und Secret-Scanning, über dein GitHub-Konto.
- **Azure DevOps Advanced Security**: deren Warnungen, über dein Azure-DevOps-Konto.

**Versionen**

- Die Paket-Registries: proxy.golang.org, registry.npmjs.org, repo.packagist.org, api.nuget.org, pypi.org, crates.io und rubygems.org. Paketnamen werden gesendet, auch bei privaten Repositories.
- **endoflife.date**: Releasezyklen und Support-Ende von Runtimes und Frameworks.
- **swift.org**: die Swift-Releases.

**Pull Requests**

- **CI-Checks** von Pull Requests. Aus: Es werden keine Checks abgerufen, angezeigt oder gemeldet.

Jede davon hat einen Schalter. Eine ausgeschaltete Quelle wird nirgends aufgerufen: nicht bei der täglichen Prüfung, nicht beim erneuten Prüfen eines Repositorys, nicht beim Ergänzen von Advisories. Bleibt dadurch etwas ungeprüft, sagt Pullwatch das („Nicht geprüft: Quelle OSV.dev ist aus“, „Version nicht geprüft: Quelle npm ist aus“) und zeigt es nie als aktuell oder frei von Schwachstellen an. Was eine frühere Prüfung von dieser Quelle bekommen hat, wird sofort ausgeblendet. Ein Schalter startet keine Prüfung. Dafür gibt es **Jetzt prüfen**.

**Weitere Verbindungen** listet den Rest, ohne eigenen Schalter:

- der Server jedes Kontos, für Pull Requests, Tags, Repositories, Manifeste und Lockfiles;
- die Anmeldung bei GitHub, für die GitHub App;
- Profilbilder deiner Konten und der Autoren von Pull Requests und Tags;
- die Updateprüfung von Pullwatch, die du unter Einstellungen, Allgemein ausschaltest.

**Übersicht kopieren** legt die ganze Liste mit der Version, dem Datum und dem Stand jeder Quelle als einfachen Text in die Zwischenablage, zum Einfügen in eine E-Mail oder einen Chat, etwa für dein Sicherheitsteam.

Standardmäßig ist alles eingeschaltet. Deine Wahl wird in `config.json` gespeichert, als `disabledSources`.

## Öffentliche Repositories ohne Token

Ein öffentliches Repository auf github.com, gitlab.com oder bitbucket.org, das dein Token nicht lesen darf, wird ohne Anmeldung gelesen. Pullwatch schickt das Token eines Kontos nie an einen anderen Server: Ein Token für GitHub Enterprise bleibt auf seinem eigenen Server.

## Open-Source-Software

Die Open-Source-Software in Pullwatch, mit Version und Lizenz, findest du unter [Danksagungen](/de/acknowledgements/).

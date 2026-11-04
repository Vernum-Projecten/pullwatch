---
title: FAQ
description: Kurze Antworten auf häufige Fragen zu Pullwatch.
---

## Ist Pullwatch kostenlos?

Ja. Pullwatch ist Open Source unter der [Apache-Lizenz 2.0](https://github.com/alessandro823/pullwatch/blob/main/LICENSE), und jedes Release steht auf [GitHub](https://github.com/alessandro823/pullwatch/releases).

## Auf welchen Macs läuft es?

macOS 26.6 oder neuer, auf Apple Silicon und auf Intel. Es ist eine einzige universelle App.

## Welche Dienste werden unterstützt?

GitHub (github.com, GitHub Enterprise Server und GHE.com), Azure DevOps, GitLab (gitlab.com und dein eigener Server) und Bitbucket Cloud (bitbucket.org). Siehe [Konten hinzufügen](/de/getting-started/accounts/).

## Kann Pullwatch etwas in meinen Repositories ändern?

Nein. Es liest nur: Pull Requests, Tags, Releases, Dateien des Repositorys für die Prüfung der Abhängigkeiten und Sicherheitswarnungen. Es kommentiert, genehmigt, merged und pusht nie.

## Schickt es meinen Code irgendwohin?

Nein. Quellcode verlässt deinen Mac nur in Richtung deiner eigenen Server, von denen er stammt. Für die Prüfung der Abhängigkeiten gehen Paketnamen und Versionen an OSV.dev und die Paket-Registries. Jede dieser Quellen kannst du ausschalten. Siehe [Datenschutz und Quellen](/de/privacy/).

## Wie oft prüft es?

Pull Requests im Intervall, das du unter Einstellungen, Allgemein festlegst. Tags alle 15 Minuten. Den Verlauf bestehender Pull Requests alle 15 Minuten. Abhängigkeiten und Schwachstellen einmal am Tag, was du ausschalten kannst, und zusätzlich immer, wenn du auf **Alle prüfen** oder **Prüfen** klickst.

## Warum hat eine Mitteilung keinen Ton?

Tags ohne Release, gemergte Pull Requests und neue Versionen kommen absichtlich leise an, nur in der Mitteilungszentrale. Während der **Ruhezeiten** macht nichts einen Ton. Fokus und Nicht stören von macOS gelten ebenfalls.

## Kann ich einem Repository folgen, das nicht mir gehört?

Ja. Füge es unter **Andere Repositorys** in seinem Konto hinzu, oder mit **Einem Repository folgen…** (⇧⌘N). Ein öffentliches Repository auf github.com, gitlab.com oder bitbucket.org funktioniert auch dann, wenn dein Token es nicht lesen darf.

## Welche Sprachen spricht Pullwatch?

Englisch, Niederländisch, Deutsch und Französisch. Es folgt macOS, oder du wählst unter Einstellungen, Allgemein, **Sprache**.

## Wie aktualisiere ich?

Pullwatch sucht einmal am Tag nach Updates und installiert sie für dich. Siehe [Updates](/de/getting-started/install/#updates).

## Gehört Pullwatch zu GitHub, GitLab, Atlassian oder Microsoft?

Nein. GitHub ist eine Marke von GitHub, Inc., GITLAB ist eine Marke von GitLab Inc., Bitbucket ist eine Marke von Atlassian, und Azure DevOps ist eine Marke der Microsoft-Unternehmensgruppe.

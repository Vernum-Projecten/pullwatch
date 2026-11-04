---
title: Installation und erster Start
description: Pullwatch laden, in den Ordner Programme bewegen und das Willkommensfenster durchgehen.
sidebar:
  label: Installation und erster Start
---

## Was du brauchst

- Einen Mac mit macOS 26.6 oder neuer. Pullwatch ist eine universelle App und läuft nativ auf Apple Silicon und auf Intel.
- Ein Konto bei mindestens einem dieser Dienste: github.com, ein GitHub-Enterprise-Server (Server oder GHE.com), Azure DevOps oder GitLab (gitlab.com oder dein eigener Server).

## Installieren

1. Lade die neueste `Pullwatch-x.y.z.dmg` von der [Release-Seite](https://github.com/alessandro823/pullwatch/releases/latest).
2. Öffne das Disk-Image und zieh **Pullwatch** auf **Programme**.
3. Öffne Pullwatch über Programme, Spotlight oder das Launchpad.

Jedes Release ist mit einer Developer ID signiert und von Apple notarisiert, deshalb öffnet macOS es ohne Warnung.

## Das Willkommensfenster

Beim ersten Start öffnet Pullwatch ein Willkommensfenster, das dich durch die Einrichtung führt:

1. **Wo Pullwatch zu finden ist.** Es läuft in der Menüleiste; das Willkommensfenster zeigt dir das Symbol.
2. **Dein erstes Konto.** Wähle GitHub, GitHub Enterprise, Azure DevOps oder GitLab. Siehe [Konten hinzufügen](/de/getting-started/accounts/) für jeden Dienst.
3. **Mitteilungen.** macOS fragt einmal, ob Pullwatch Mitteilungen senden darf. Erlaube es, um von neuen Pull Requests und Tags zu erfahren, sobald sie erscheinen.
4. **Beim Anmelden starten**, damit Pullwatch nach einem Neustart da ist.

Danach fragt Pullwatch deine Konten im Hintergrund ab. Beim ersten Mal ruft es auch deine bestehenden Pull Requests ab, damit der Verlauf nicht leer ist. Diese lösen keine Mitteilung aus und kommen als gelesen markiert an.

## Wo du es findest

- **Das Symbol in der Menüleiste** öffnet das [Menü](/de/using/menu/) mit den neuesten Pull Requests und Tags.
- **Öffnen…** im Menü öffnet das Hauptfenster mit PRs, Tags und Releases, Statistiken, Repositories und Abhängigkeiten. Es merkt sich den Bereich, den du zuletzt offen hattest.
- **Einstellungen** ist die Zahnrad-Schaltfläche im Menü, oder ⌘, während Pullwatch im Vordergrund ist.

Solange eines seiner Fenster offen ist, erscheint Pullwatch im Dock. Schließt du das letzte Fenster, läuft es nur noch in der Menüleiste. Öffnest du Pullwatch erneut, während es läuft, erscheint das Hauptfenster (oder das Willkommensfenster, solange kein Konto eingerichtet ist).

## Updates

Pullwatch sucht einmal am Tag nach einem neuen Release (Einstellungen, Allgemein, wo **Jetzt prüfen** sofort sucht). Gibt es eines, bekommst du eine Mitteilung und ein Banner im Menü. **Installieren** zeigt die Versionshinweise. Dann lädt [Sparkle](https://sparkle-project.org) das Update, prüft seine EdDSA-Signatur und seine Developer-ID-Signatur, installiert es und startet Pullwatch neu.

Unter Einstellungen, Allgemein lädt **Updates automatisch installieren** ein Update im Hintergrund und installiert es, wenn du Pullwatch beendest, und **Testversionen anbieten** bietet auch Vorab-Releases an.

Ein Build ohne den öffentlichen Schlüssel von Sparkle, etwa einer, den du aus dem Quellcode baust, zeigt stattdessen eine Schaltfläche, die das Disk-Image lädt.

## Sprache

Pullwatch spricht Englisch, Niederländisch, Deutsch und Französisch. Es folgt der Sprache von macOS, oder du wählst eine unter Einstellungen, Allgemein, **Sprache**.

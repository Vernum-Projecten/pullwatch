---
title: Fehlerbehebung
description: Was du tun kannst, wenn Mitteilungen, Konten, Prüfungen oder Updates nicht wie erwartet funktionieren.
---

## Ich bekomme keine Mitteilungen

- Steht im Menü **Mitteilungen sind in den Systemeinstellungen deaktiviert**, öffne Systemeinstellungen, Mitteilungen, Pullwatch und erlaube sie.
- Sieh unter Einstellungen, Mitteilungen nach: Jede Art hat ihren eigenen Schalter, und **Ruhezeiten** hält Mitteilungen still und nur in der Mitteilungszentrale.
- Sieh dir die Glocke neben dem Repository unter Einstellungen, Konten an. **Repository stummschalten** in einer Mitteilung schaltet diese Glocke aus.
- Fokus und Nicht stören halten Mitteilungen aller Apps zurück, auch die von Pullwatch.
- Die erste Tag-Abfrage eines Repositorys ist still, ebenso Pull Requests, die für den Verlauf abgerufen werden.

## Ein Konto zeigt einen Fehler

Das Menü zeigt jedes Konto mit dem Stand seiner letzten Abfrage. Öffne Einstellungen, Konten, wähle das Konto und nutze **Verbindung testen**.

- **Token ungültig oder abgelaufen**: Erstelle ein neues Token mit den [Berechtigungen](/de/getting-started/permissions/), die Pullwatch braucht, und sichere es.
- **Angemeldet mit `gh`, `az` oder `glab`**: Melde dich in diesem Werkzeug erneut an (`gh auth login`, `az login`, `glab auth login`). Aufrufe dieser Werkzeuge brechen nach 20 Sekunden ab.
- **Ein selbst verwalteter Server**: Er muss über https erreichbar sein. Einfaches http lehnt Pullwatch ab.

## Ein Repository fehlt

- Mit **Mit GitHub anmelden** sieht Pullwatch nur Repositories, in denen die GitHub App von Pullwatch installiert ist. Installiere sie im Kontoeditor für ein anderes Konto oder eine andere Organisation.
- Bei GitLab prüfe die Gruppen oder Benutzer, die beim Konto eingetragen sind. Eine Gruppe umfasst ihre Untergruppen.
- Für ein einzelnes Repository außerhalb deiner Konten füge es unter **Andere Repositorys** hinzu.

## Ein Teil der Repository-Seite zeigt Berechtigung nötig

Das Token oder die GitHub App darf diesen Teil nicht lesen, etwa Checks, Code-Scanning oder Secret-Scanning. Der Link daneben führt zur Berechtigung. Alles andere funktioniert weiter. Siehe [Token-Berechtigungen](/de/getting-started/permissions/).

## Etwas zeigt Nicht geprüft

Eine Datenquelle ist unter Einstellungen, Quellen ausgeschaltet, deshalb hat Pullwatch diesen Teil nicht geprüft. Schalte sie ein und klicke auf **Jetzt prüfen**.

## Eine Runtime oder ein Paket zeigt Unbekannt oder Nicht prüfbar

Pullwatch konnte keine Version aus den Dateien lesen, oder das Paket ist privat oder ein Swift-Paket, das keine öffentliche Registry kennt. Projekte mit Maven und Gradle werden nicht gelesen.

## Der Schlüsselbund fragt nach jedem Update nach Zugriff

Das passiert nur mit einem Build, den du selbst erstellt hast (aus Xcode oder ad hoc signiert). Wähle **Immer erlauben**. Releases von GitHub sind mit einer Developer ID signiert und fragen nicht.

## Zwei Pullwatch-Symbole in der Menüleiste

Du startest einen Build aus Xcode neben der installierten App. Beende einen davon mit **Pullwatch beenden** in seinem Menü.

## Protokolle

Pullwatch schreibt in das Systemprotokoll. Lege die Stufe unter Einstellungen, Allgemein, **Protokollstufe** fest und verfolge das Protokoll dann im Terminal:

```sh
log stream --predicate 'subsystem == "nl.torrisi.pullwatch"'
```

Oder öffne die Konsole und suche nach `nl.torrisi.pullwatch`. Hast du einen Fehler gefunden, eröffne ein [Issue auf GitHub](https://github.com/alessandro823/pullwatch/issues) mit dem, was du getan hast, und dem, was im Protokoll stand, ohne Tokens.

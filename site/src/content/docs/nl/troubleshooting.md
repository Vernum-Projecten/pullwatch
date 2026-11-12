---
title: Problemen oplossen
description: Wat je doet als meldingen, accounts, checks of updates niet werken zoals je verwacht.
---

## Ik krijg geen meldingen

- Zegt het menupaneel **Meldingen staan uit in Systeeminstellingen**, open dan Systeeminstellingen, Berichtgeving, Pullwatch en sta ze toe.
- Kijk bij Instellingen, Meldingen: elke soort heeft een eigen schakelaar, en **Stille uren** houdt meldingen stil en alleen in het Berichtencentrum.
- Kijk naar de bel naast de repository in Instellingen, Accounts. **Repo dempen** op een melding zet die bel uit.
- Focus en Niet storen houden meldingen van elke app tegen, ook die van Pullwatch.
- De eerste keer dat Pullwatch de tags van een repository ophaalt, blijft het stil, en dat geldt ook voor pull requests die voor de geschiedenis worden opgehaald.

## Een account geeft een fout

Het menupaneel toont elk account met de stand van de laatste poll. Open Instellingen, Accounts, kies het account en gebruik **Test verbinding**.

- **Token ongeldig of verlopen**: maak een nieuw token met de [rechten](/nl/getting-started/permissions/) die Pullwatch nodig heeft en bewaar het.
- **Ingelogd met `gh`, `az` of `glab`**: log opnieuw in met die tool (`gh auth login`, `az login`, `glab auth login`). Een aanroep van deze tools stopt na 20 seconden.
- **Een eigen server**: die moet bereikbaar zijn via https; Pullwatch weigert gewoon http.

## Een repository ontbreekt

- Met **Inloggen met GitHub** ziet Pullwatch alleen repositories waar de GitHub-app van Pullwatch geïnstalleerd is. Installeer hem op een ander account of een andere organisatie vanuit het accountscherm, met **Op een ander account of organisatie installeren…**.
- Kijk bij GitLab naar de groepen of gebruikers die bij het account staan. Een groep volgt ook zijn subgroepen.
- Voeg een losse repository buiten je accounts toe onder **Andere repositories**.

## Tags of branches van een repository komen niet meer binnen

Het token van het account kan die repository niet lezen: hij is niet gevonden, of het token heeft er geen toegang toe. Instellingen, Accounts toont het aantal bij het account, en het account noemt de repositories onder **Niet te lezen met dit token**. De repopagina en de kolom Laatste tag in Repo's markeren ze ook.

- **Ingelogd met `gh`**: zonder keuze bij **GitHub-account** komt het token van het actieve account in `gh`. Na `gh auth switch` naar een login zonder toegang worden de private repositories van een organisatie onleesbaar. Kies de login die ze kan lezen.
- **Een personal access token**: geef het toegang tot deze repositories, of volg ze niet meer.

Is de toegang terug, dan komen de gemiste tags en branches bij de volgende poll binnen.

## Een deel van de repopagina zegt Toestemming nodig

Het token of de GitHub-app mag dat deel niet lezen, zoals checks, code scanning of secret scanning. De link ernaast leidt naar het recht. Al het andere blijft werken. Zie [Rechten van tokens](/nl/getting-started/permissions/).

## Er staat Niet gecontroleerd

Een gegevensbron staat uit onder Instellingen, Bronnen, dus Pullwatch heeft dat deel niet gecontroleerd. Zet hem aan en klik op **Nu checken**.

## Een runtime of package zegt Onbekend of Niet te checken

Pullwatch kon geen versie uit de bestanden lezen, of het package is privé of een Swift-package, dat geen openbaar register kent. Projecten met Maven en Gradle worden niet gelezen.

## De sleutelhanger vraagt na elke update om toegang

Dat gebeurt alleen met een build die je zelf hebt gemaakt (vanuit Xcode of ad hoc ondertekend). Kies **Sta altijd toe**. Releases van GitHub zijn ondertekend met een Developer ID en vragen er niet om.

## Twee Pullwatch-iconen in de menubalk

Je draait een build vanuit Xcode naast de geïnstalleerde app. Stop er een met **Stop Pullwatch** in het menupaneel ervan.

## Logs

Pullwatch schrijft naar het systeemlog. Stel het niveau in onder Instellingen, Algemeen, **Logniveau**, en volg het dan in Terminal:

```sh
log stream --predicate 'subsystem == "nl.torrisi.pullwatch"'
```

Of open Console en zoek op `nl.torrisi.pullwatch`. Heb je een bug gevonden, open dan een [issue op GitHub](https://github.com/alessandro823/pullwatch/issues) met wat je deed en wat er in het log stond, zonder tokens.

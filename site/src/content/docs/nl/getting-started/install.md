---
title: Installeren en eerste start
description: Download Pullwatch, zet het in Apps en loop het welkomstvenster door.
sidebar:
  label: Installeren en eerste start
---

## Wat je nodig hebt

- Een Mac met macOS 26.6 of nieuwer. Pullwatch is een universele app en draait dus native op Apple silicon en op Intel.
- Een account op minstens een van deze: github.com, een GitHub Enterprise-server (Server of GHE.com), Azure DevOps of GitLab (gitlab.com of je eigen server).

## Installeren

1. Download de nieuwste `Pullwatch-x.y.z.dmg` van de [releasepagina](https://github.com/alessandro823/pullwatch/releases/latest).
2. Open de schijfkopie en sleep **Pullwatch** naar **Apps**.
3. Open Pullwatch vanuit Apps, Spotlight of Launchpad.

Elke release is ondertekend met een Developer ID en door Apple gecontroleerd (notarized), dus macOS opent hem zonder waarschuwing.

## Het welkomstvenster

Bij de eerste start opent Pullwatch een welkomstvenster dat je door de installatie leidt:

1. **Waar Pullwatch staat.** Het draait in de menubalk; het welkomstvenster wijst het icoon aan.
2. **Je eerste account.** Kies GitHub, GitHub Enterprise, Azure DevOps of GitLab. Zie [Je accounts toevoegen](/nl/getting-started/accounts/) voor elk ervan.
3. **Meldingen.** macOS vraagt één keer of Pullwatch meldingen mag sturen. Sta het toe om nieuwe pull requests en tags te zien zodra ze er zijn.
4. **Starten bij inloggen**, zodat Pullwatch er na een herstart weer is.

Daarna kijkt Pullwatch op de achtergrond bij je accounts. De eerste keer haalt het ook je bestaande pull requests op, zodat de geschiedenis niet leeg is. Die geven geen melding en komen binnen als gelezen.

## Waar je het vindt

- **Het icoon in de menubalk** opent het [menupaneel](/nl/using/menu/) met de nieuwste pull requests en tags.
- **Openen…** in het menupaneel opent het hoofdvenster met PR's, Tags en releases, Statistieken, Repo's en Afhankelijkheden. Het onthoudt welk onderdeel je het laatst open had.
- **Instellingen** is de knop met het tandwiel in het menupaneel, of ⌘, als Pullwatch vooraan staat.

Zolang een van de vensters open is, staat Pullwatch in het Dock. Sluit je het laatste venster, dan draait het alleen nog in de menubalk. Open je Pullwatch opnieuw terwijl het draait, dan komt het hoofdvenster tevoorschijn (of het welkomstvenster zolang er geen account is ingesteld).

## Updates

Pullwatch zoekt eens per dag naar een nieuwe release (Instellingen, Algemeen, waar **Nu controleren** meteen kijkt). Is er een, dan krijg je een melding en een balk in het menupaneel. **Installeren** toont de release notes; daarna downloadt [Sparkle](https://sparkle-project.org) de update, controleert de EdDSA-handtekening en de Developer ID-handtekening, installeert hem en start Pullwatch opnieuw.

Onder Instellingen, Algemeen downloadt **Updates automatisch installeren** een update op de achtergrond en installeert hem als je Pullwatch afsluit, en **Testversies aanbieden** biedt ook pre-releases aan.

Een build zonder de openbare sleutel van Sparkle, zoals een die je zelf uit de broncode bouwt, toont in plaats daarvan een knop die de schijfkopie downloadt.

## Taal

Pullwatch spreekt Engels, Nederlands, Duits en Frans. Het volgt de taal van macOS, of je kiest er een onder Instellingen, Algemeen, **Taal**.

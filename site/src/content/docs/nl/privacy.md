---
title: Privacy en bronnen
description: Waar Pullwatch je gegevens bewaart, elke verbinding die het maakt, en hoe je gegevensbronnen uitzet.
---

Pullwatch draait op je Mac en nergens anders. Het heeft geen account, geen eigen server en geen analytics. Het praat met de servers van je accounts en met een paar openbare diensten, en Instellingen, **Bronnen** toont ze allemaal.

## Wat op je Mac blijft

- **Tokens** staan in de sleutelhanger van macOS, onder `nl.torrisi.pullwatch`. Log je in met `gh`, `az` of `glab`, dan blijft het token bij die tool.
- **Instellingen, geschiedenis en uitkomsten van checks** zijn JSON-bestanden in `~/Library/Application Support/Pullwatch/`: `config.json`, `seen.json`, `history.json`, `versions.json` en `version-history.json`. Elke volledige check voegt een compacte momentopname toe aan `version-history.json` (versies, standen, aantallen kwetsbaarheden en package-updates per repository, hooguit 730 momentopnamen), bewaard voor statistieken door de tijd.

Verwijder je een account, dan verdwijnt ook de geschiedenis ervan.

## Instellingen, Bronnen

Het tabblad Bronnen toont elke externe dienst in gewone taal. Elke rij zegt wat de bron levert en welk adres Pullwatch aanroept, en linkt naar de website ervan.

**Kwetsbaarheden**

- **OSV.dev** (`api.osv.dev`): bekende kwetsbaarheden in je packages. Namen en versies van packages worden verstuurd, ook voor privé-repositories. Het is de enige bron voor kwetsbaarheden in packages bij repositories op GitHub en GitLab.
- **GitHub Advisory Database** (`api.github.com/advisories`): ernst, CVSS, CWE en links voor elk advies, één keer per advies opgehaald.
- **GitHub-beveiliging**: de eigen adviezen van de repository, code scanning en secret scanning, via je GitHub-account.
- **Azure DevOps Advanced Security**: de meldingen ervan, via je Azure DevOps-account.

**Versies**

- De package-registers: proxy.golang.org, registry.npmjs.org, repo.packagist.org, api.nuget.org, pypi.org, crates.io en rubygems.org. Namen van packages worden verstuurd, ook voor privé-repositories.
- **endoflife.date**: releasecycli en einddata van ondersteuning van runtimes en frameworks.
- **swift.org**: de releases van Swift.

**Pull requests**

- **CI-checks** van pull requests. Uit: er worden geen checks opgehaald, getoond of gemeld.

Elk hiervan heeft een schakelaar. Een bron die uit staat, wordt nergens aangeroepen: niet in de dagelijkse check, niet als je één repository opnieuw checkt, niet als adviezen worden aangevuld. Overal waar daardoor iets niet gecontroleerd is, zegt Pullwatch dat ("Niet gecontroleerd: bron OSV.dev staat uit", "Versie niet gecontroleerd: bron npm staat uit") en toont het nooit als actueel of vrij van kwetsbaarheden. Wat een eerdere check van die bron kreeg, verdwijnt meteen uit beeld. Een schakelaar omzetten start geen check; daarvoor klik je op **Nu checken**.

**Overige verbindingen** toont de rest, die geen eigen schakelaar hebben:

- de server van elk account, voor pull requests, tags, repositories, manifesten en lockfiles;
- inloggen bij GitHub, voor de GitHub-app;
- profielfoto's van je accounts en van de auteurs van pull requests en tags;
- de updatecheck van Pullwatch, die je uitzet onder Instellingen, Algemeen.

**Kopieer overzicht** zet de hele lijst, met de versie, de datum en de stand van elke bron, als platte tekst op het klembord, om in een mail of chat te plakken, bijvoorbeeld voor je securityteam.

Alles staat standaard aan. Je keuze wordt bewaard in `config.json`, als `disabledSources`.

## Openbare repositories zonder token

Een openbare repository op github.com of gitlab.com die je token niet mag lezen, wordt gelezen zonder in te loggen. Pullwatch stuurt het token van een account nooit naar een andere server: een token van GitHub Enterprise blijft op zijn eigen server.

## Opensourcesoftware

De opensourcesoftware in Pullwatch, met de versie en de licentie van elk onderdeel, staat onder [Erkenningen](/nl/acknowledgements/).

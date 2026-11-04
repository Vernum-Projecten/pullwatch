# Hoofdvenster met zijbalk en package-versies: ontwerp

> Noot (4 november 2026): Dit ontwerp noemt bestanden zoals ze toen heetten. Sinds de opruiming van #112 staan de bronnen per module en gebied (`PullwatchKit/Sources/<Module>/<Gebied>/`, `Pullwatch/Pullwatch/App/` en `Views/`) en zijn de grote bestanden per onderdeel gesplitst; `CLAUDE.md` geeft de huidige indeling. De leestekens volgen de huisstijl (geen em dashes en geen middelpunt als scheidingsteken); de inhoud is niet veranderd.

Datum: 2026-11-01

## Waarom

Alessandro ontdekte bij toeval dat er een nieuwe Go-versie uit was. Pullwatch kijkt al naar de
versies in alle gevolgde repo's, maar:

- het Versies-scherm is per repo ("repo X loopt achter"), niet per package ("Go 1.27.4 is uit, deze
  repo's zitten nog op de oude versie");
- patches tellen niet mee (`EndOfLife.evaluate`), dus Go 1.27.3 → 1.27.4 blijft "Actueel";
- libraries worden al ingelezen, maar alleen voor de CVE-check; hun nieuwste versie wordt nooit opgehaald;
- er komt alleen een melding bij nieuwe CVE's, niet bij nieuwe versies.

Daarnaast wil Alessandro PR's, tags, de repo-controle en de versies in één venster in plaats van in
losse vensters.

## Doelen

1. **Eén hoofdvenster met zijbalk** (`NavigationSplitView`, de macOS-standaard zoals Mail en Xcode)
   met vier onderdelen: **PR's**, **Tags**, **Repo-controle**, **Versies**.
2. **Nieuw onderdeel Versies**, per package: welke runtimes en directe libraries de gevolgde repo's
   gebruiken, wat de nieuwste versie is, en welke repo's nog op een oudere versie zitten.
3. **Melding** als er een nieuwe versie uitkomt van iets dat de repo's gebruiken.

## Niet-doelen

- Geen indirecte (transitieve) dependencies: die geven honderden regels en meldingen.
- Geen automatische PR's of bumps; Pullwatch blijft alleen-lezen.
- Repo-controle (het huidige Versies-scherm) verandert inhoudelijk niet: daar blijven patches
  niet meetellen en blijven EOL en CVE's de focus.
- Instellingen blijft een apart venster (Alessandro heeft dat niet gevraagd; macOS-gewoonte, mijn keuze).

## Anti-doelen

- Meldingenspam: één melding per check per package-update is al te veel bij tientallen npm-packages.
- Een lijst vol "onbekend" doordat private modules of private registries niet op te zoeken zijn.

## Deel 1: Hoofdvenster

- De `Window`s `history` en `versions` in `PullwatchApp.swift` worden één `Window` (id bv. `main`,
  titel "Pullwatch") met een `NavigationSplitView`. Settings blijft een eigen `Window`.
- Zijbalk, in deze volgorde:
  - **PR's**: de huidige `HistoryView` met vast filter op pull requests (incl. completed/merged).
  - **Tags**: `HistoryView` met vast filter op tags. Het segmented filter "Alles / PR's / Tags" verdwijnt.
  - **Repo-controle**: de huidige `VersionsView`, ongewijzigd van inhoud; hernoemd.
  - **Versies**: nieuw (deel 2).
- Tellers in de zijbalk (badge): PR's = ongelezen PR's, Tags = ongelezen tags, Versies = aantal
  packages met een nieuwe versie die je nog niet gezien hebt. Repo-controle zonder teller (mijn keuze;
  de builder mag daar het aantal repo's met CVE's tonen als dat vanzelf meekomt).
- Menu: "Geschiedenis…" en "Versies…" worden vervangen door één knop "Openen…" plus, als het past , 
  directe sprongen. Minimaal: de knop opent het hoofdvenster op het laatst gekozen onderdeel. Bestaande
  sprongen (dubbelklik/rechtsklik "Versies" vanuit de geschiedenis, `model.versionsSearch`) gaan naar
  het onderdeel Repo-controle met het zoekfilter, zoals nu.
- Gekozen onderdeel onthouden via `@AppStorage`.
- Het Dock-gedrag ("zichtbaar zolang een venster open is") blijft.
- Localisatie: nieuwe strings in NL/EN/DE/FR, net als de rest.

## Deel 2: Onderdeel Versies

### Wat er op het scherm staat

Zie mockup `.superpowers/brainstorm/…/content/versions-tab.html`. Lijst per package:

- Groep **Nieuwe versie beschikbaar**: packages waar minstens één repo een oudere versie heeft dan de
  nieuwste. Regel: `Go`, soort-label (`runtime`, `go`, `npm`, `composer`, `nuget`, `pypi`, `cargo`),
  "**1.27.4 beschikbaar**", "5 repo's achter", sinds wanneer bekend.
- Uitklappen: per achterlopende repo de repo-naam, de gebruikte versie en het bestand/de bestanden
  (`go.mod`, `Dockerfile`), plus "✓ N repo's al op 1.27.4".
- Groep **Actueel**: packages waar alle repo's bij zijn, ingeklapt.
- Groep **Niet te checken** (ingeklapt, onderaan): packages waarvan de nieuwste versie niet op te
  halen was (private module, onbekend register). Niet in de teller, geen melding.
- Zoekveld (package of repo) en knop "Nu checken".
- Een package staat in "Nieuwe versie beschikbaar" zolang er een repo achterloopt, het is een
  toestand, geen bericht. Een stip/"nieuw" markeert packages waarvan de nieuwste versie veranderd is
  sinds je dit onderdeel voor het laatst opende (mijn keuze).
- Klik op een repo-naam: spring naar Repo-controle gefilterd op die repo (zelfde mechanisme als nu).

### Wat telt mee

- **Runtimes/talen**: de onderdelen die `StackDetector` al vindt (Go, PHP, Node, Swift, .NET, Python,
  Rust, Docker-images), **per cyclus** (mijn keuze na builder-check): een repo op Go 1.27.3 ziet
  "Go 1.27.4 beschikbaar", een repo op Go 1.26.9 ziet "Go 1.26.10 beschikbaar" zodra die uit is. Een
  rij is dus (product, cyclus), bv. "Go 1.27". Een nieuwere cyclus (Node 22 → 25, Go 1.26 → 1.27) is
  hier géén update: dat toont Repo-controle al als "Achter", en anders staat een LTS-repo eeuwig in de
  lijst. Bron: endoflife.date (`latest` van díe cyclus) en swift.org, zoals nu.
- **Frameworks** (React, Angular, Vue, Next.js, Nuxt, Laravel, Symfony; de sleutels van
  `StackDetector.lockedPackages`) verschijnen **één keer**, als library-regel (`react`, npm) met de
  nieuwste versie uit het register, niet ook nog als runtime-regel (mijn keuze).
- **Directe libraries** per ecosysteem. Dit vraagt aanpassing van `DependencyDetector`, die nu ook
  indirecte packages oplevert:
  - Go: `go.mod` `require`-regels **zonder** `// indirect`.
  - npm: `package-lock.json` v2/v3 → `packages[""].dependencies` + `devDependencies` bepalen de
    directe namen; versie uit de lock. Lockfile v1 of geen lock: namen uit `package.json`, versie
    alleen als die exact is.
  - Composer: namen uit `composer.json` `require`/`require-dev` (zonder `php` en `ext-*`), versie uit
    `composer.lock`.
  - NuGet: `PackageReference`/`PackageVersion` zijn al direct.
  - PyPI: `requirements*.txt` `==` is direct; `pyproject.toml`-dependencies + `poetry.lock`/`uv.lock`
    voor de versie.
  - Cargo: `Cargo.toml` `[dependencies]` + `Cargo.lock` voor de versie.
  - Swift: `Package.resolved` heeft geen direct-markering; neem alle pins (meestal weinig). Nieuwste
    versie voor SwiftURL valt buiten de eerste versie → "Niet te checken" (mijn keuze, mag later).
  - De CVE-check blijft **alle** packages gebruiken; het onderscheid direct/indirect is een extra
    veld, geen vervanging.
- **Patches tellen wél mee**, anders dan in Repo-controle.
- Een versie zonder patch (`go 1.27` in `go.mod`, `node:22` als image) telt als "op de nieuwste patch
  van die cyclus" (mijn keuze): je kunt daar niet achterlopen op een patch.
- Pre-releases (`-rc`, `-beta`, `-alpha`, `-next`) tellen nooit als nieuwste versie.
- Libraries vergelijken met de nieuwste versie in het register; een nieuwe major telt ook als
  "beschikbaar" (react 19 → 20). Builder mag dat visueel onderscheiden (bv. "major"), geen eis.
- Een repo zonder exacte versie voor een package (`^19.0.0` zonder lockfile) telt voor dat package
  niet mee (mijn keuze): niet achter, niet actueel.

### Bron van de nieuwste library-versie

Eén request per uniek package over alle repo's heen (dedupe), met dezelfde `HTTPClient`-abstractie,
timeouts en `HTTPStatus.check` als OSV/endoflife.date:

| Ecosysteem | Endpoint |
|---|---|
| Go | `https://proxy.golang.org/<module, hoofdletters escaped>/@latest` |
| npm | `https://registry.npmjs.org/<name>/latest` (scoped: `@scope%2fname`) |
| Packagist | `https://repo.packagist.org/p2/<vendor>/<name>.json` |
| NuGet | `https://api.nuget.org/v3-flatcontainer/<id lowercase>/index.json` (laatste niet-prerelease) |
| PyPI | `https://pypi.org/pypi/<name>/json` → `info.version` |
| crates.io | `https://crates.io/api/v1/crates/<name>` → `max_stable_version` (vereist `User-Agent`) |

Exacte endpoints mag de builder verfijnen. 404/403 → "Niet te checken", geen fout voor de hele check.
Package-namen gaan naar deze registers, ook van private repo's, net als nu bij OSV.dev. README
vermeldt dat.

### Wanneer

- Draait mee met de bestaande versiecheck (dagelijks, `autoVersionCheck`, en "Opnieuw checken" /
  "Nu checken"). Geen eigen schema.
- ↻ op één repo in Repo-controle werkt het onderdeel Versies ook bij voor die repo.
- Opslag: uitbreiden van `versions.json` (of een eigen bestand ernaast, keuze builder), met per
  package de nieuwste versie en wanneer die voor het eerst gezien is. Oude `versions.json` moet
  blijven laden (decodeIfPresent, zoals nu).

### Melding

- Na een **automatische** check (zoals bij CVE's; bij een handmatige check kijk je al): packages waarvan de nieuwste versie **veranderd** is t.o.v. de vorige check en waar
  minstens één repo achterloopt → één **gebundelde** melding: "3 nieuwe versies: Go 1.27.4, react
  19.3.0, laravel/framework 12.4.1" (meer dan ~3 → "+ N meer"). Klik opent het hoofdvenster op Versies.
- De eerste check (geen vorige gegevens voor dat package) is stil, zoals bij tags.
- Schakelaar in Instellingen → Algemeen: "Melding bij nieuwe versies" (standaard aan).
- Via `Notifier`, naast `deliverVulnerabilities`.

## Volgorde

1. Deel 1 (hoofdvenster) los opleveren; geen nieuwe functionaliteit, wel een merkbare verandering.
2. Deel 2: detectie direct/indirect → ophalen nieuwste versies → model + opslag → scherm → melding.

## Overgelaten aan de builder

- Precieze vorm van modellen en opslag; testopzet volgt `Tests/PullwatchCoreTests` (mock HTTP).
- Visuele details binnen de mockup-richting (pills, kleuren, iconen).
- Of het hoofdvenster een toolbar-zoekveld (`.searchable`) gebruikt of het huidige `TextField`.
- Versienummer en releasenotes zoals bij eerdere releases.

# Bronnen: waar de CVE- en versie-informatie vandaan komt

## Waarom

De CISO vroeg waar de beveiligings- en versie-informatie in Pullwatch vandaan
komt, en Alessandro kon dat niet beantwoorden. Pullwatch moet dat zelf laten
zien, in gewone taal, zodat ook iemand die meekijkt het snapt. Daarnaast moet je
kunnen bepalen welke bronnen Pullwatch aanroept, zodat alleen goedgekeurde
bronnen gebruikt worden.

## Doelen

- Een tabblad **Bronnen** in Instellingen dat elke externe bron toont: naam,
  wat hij levert, het adres dat Pullwatch aanroept en een link naar de site.
- Per bron een **aan/uit-schakelaar**. Een bron die uit staat, roept Pullwatch
  nergens meer aan: niet in de dagelijkse check, niet bij een herhaalde check
  van één repo, niet bij het aanvullen van adviezen.
- Overal waar daardoor iets niet gecontroleerd wordt: **"Niet gecontroleerd:
  bron xxx staat uit"**.
- Een knop **Kopieer overzicht** die het overzicht als tekst op het klembord
  zet, om in een mail of Teams-bericht te plakken.
- Standaard staat alles aan: voor wie niets aanpast verandert er niets.

## Niet-doelen

- Zelf bronnen toevoegen (een eigen spiegel, NVD, een interne registry). Komt
  misschien later; het ontwerp moet dat niet in de weg zitten (zie Model).
- Een exportbestand (PDF, CSV). Alleen het klembord.
- Bronnen per account of per repo instellen. De keuze geldt voor de hele app.

## Anti-doelen

- **Een bron die uit staat mag nooit lijken op "alles veilig" of "actueel".**
  Wie OSV.dev uitzet, mag nergens "Geen kwetsbaarheden" zien. Dat is erger dan
  geen scherm.
- Geen technische taal als hoofdtekst. Het adres staat erbij, maar de
  beschrijving is voor een niet-ontwikkelaar.

## De bronnen

Wat de code nu aanroept (`PullwatchKit/Sources`):

**Kwetsbaarheden**

| Bron | Wat hij levert | Aanroep | Waar in de code |
|---|---|---|---|
| OSV.dev | Bekende kwetsbaarheden (CVE's, GHSA's) in packages. **De enige bron voor kwetsbaarheden in packages bij GitHub- en GitLab-repo's**; Azure DevOps Advanced Security meldt ook kwetsbare packages (`alertType` "dependency", "malware"). | `api.osv.dev/v1/querybatch`, `api.osv.dev/v1/vulns/{id}` | `Versions/OSV.swift`, stap 4 in `VersionChecker.check` |
| GitHub Advisory Database | Aanvullende details bij een gevonden melding: ernst, CVSS, CWE, publicatie, intrekking | `api.github.com` (advisories) | `Versions/GitHubAdvisory.swift`, `Versions/AdvisoryLookup.swift` |
| GitHub-beveiliging (en "GitHub security", de "GitHub-Sicherheit", fr "Sécurité GitHub") | Code scanning, secret scanning en de eigen adviezen van een repo | GitHub-API van het account | `PullwatchGitHub/GitHubProvider+Security.swift` |
| Azure DevOps Advanced Security | Meldingen van Advanced Security per repo | `_apis/alert/repositories/{repo}/alerts` | `PullwatchAzureDevOps/AzureDevOpsProvider+Security.swift` |

**Versies**

| Bron | Wat hij levert | Aanroep |
|---|---|---|
| npm | Nieuwste versie en metadata van npm-packages | `registry.npmjs.org` |
| PyPI | idem, Python | `pypi.org/pypi` |
| crates.io | idem, Rust | `crates.io/api/v1/crates` |
| NuGet | idem, .NET | `api.nuget.org` |
| RubyGems | idem, Ruby | `rubygems.org/api` |
| Packagist | idem, PHP | `repo.packagist.org` |
| Go-moduleproxy (en "Go module proxy", de "Go-Modul-Proxy", fr "Proxy des modules Go") | idem, Go | `proxy.golang.org` |
| endoflife.date | Releasecycli en end-of-life van runtimes (Go, .NET, Node en meer) | `endoflife.date/api/v1/products/{product}` |
| swift.org | Swift-releases (Swift heeft geen EOL-beleid) | `swift.org/api/v1/install/releases.json` |

De registries staan in `Versions/Registries/PackageRegistry.swift` en
`Versions/Registries/RegistryMetadata.swift`, endoflife.date en swift.org in
`Versions/Registries/EndOfLife.swift`.

**Overige verbindingen** (beslist door Alessandro: het overzicht toont élke
verbinding naar buiten, zodat het het volledige antwoord is op "met wie praat
Pullwatch")

De namen GitHub-beveiliging en Go-moduleproxy zijn omschrijvingen en worden
vertaald (in het tabblad, in "Niet gecontroleerd: bron … staat uit" en in het
gekopieerde overzicht, in de taal daarvan); de andere namen zijn eigennamen en
staan in elke taal hetzelfde.

| Verbinding | Wat | Schakelaar |
|---|---|---|
| Servers van je accounts | Per account de server (github.com, een GitHub Enterprise-server of GHE.com, dev.azure.com, gitlab.com of een eigen GitLab): PR's, tags, repo's, manifesten en lockfiles. Eén rij per account, met het adres waar de provider echt mee praat: `api.github.com`, `api.<naam>.ghe.com`, `<server>/api/v3`, `dev.azure.com/<organisatie>` of `<server>/api/v4` (`SourcesOverview.server(of:)`). Bij een account via de Azure CLI of de GitHub CLI zegt de rij dat Pullwatch het token van `az` of `gh` haalt, en dat dat programma zelf `login.microsoftonline.com` of `api.github.com` kan aanroepen. | Geen; uitzetten gaat via het account zelf. |
| Inloggen bij GitHub | De device flow en het vernieuwen van het token (`github.com/login/device/code`, `github.com/login/oauth/access_token`) voor accounts die via de GitHub App inloggen. De GitHub App staat op github.com, ook bij een Enterprise-account. Alleen als zo'n account er is. | Geen; staat aan zolang een van die accounts aan staat. |
| Profielfoto's | Per account de hosts van de foto's die de app laadt (`SourcesOverview.pictureHosts(of:)`), los van de geschiedenis: github.com en `avatars.githubusercontent.com` (waar `github.com/<login>.png` naar doorstuurt en waar de foto's van auteurs staan); bij een GitHub Enterprise-server of GHE.com `<server>` en `avatars.<server>` (subdomain isolation); bij GitLab de server zelf (geüploade foto's, `<server>/uploads/…`) en `secure.gravatar.com` (Gravatar, standaard op gitlab.com en op een eigen GitLab). Alleen als er een GitHub- of GitLab-account is. | Geen; staat aan zolang een GitHub- of GitLab-account aan staat. |
| Updatecheck van Pullwatch | `api.github.com` (releases van Pullwatch, voor testversies), de appcast en de zip op `github.com` (Sparkle), en `release-assets.githubusercontent.com` en `objects.githubusercontent.com`, waar github.com de downloads van een release naar doorstuurt; in één rij met alle adressen | Geen eigen schakelaar hier; de rij toont de stand van "Automatisch op updates controleren" in Algemeen en linkt daarheen. |

De bouwer controleert deze lijst tegen de code: als er een externe aanroep is
die hier ontbreekt, hoort die er ook bij. De lijst in de app moet compleet zijn,
anders klopt het antwoord aan de CISO niet.

## Gedrag als een bron uit staat

- **OSV.dev uit:** geen CVE-check voor packages. Op de plekken waar nu
  kwetsbaarheden of "geen kwetsbaarheden" staan (repo-pagina, Packages,
  menu-samenvatting, meldingen): "Niet gecontroleerd: bron OSV.dev staat uit".
  Geen meldingen over nieuwe kwetsbaarheden. Eerder gevonden kwetsbaarheden in
  `versions.json` blijven niet als actueel staan: na de volgende check zijn ze
  weg en staat er de melding hierboven.
- **GitHub Advisory Database uit:** meldingen van OSV blijven, zonder de extra
  details. Bij de details staat "Details niet opgehaald: bron GitHub Advisory
  Database staat uit". Ernst valt terug op wat OSV geeft.
- **GitHub-beveiliging of Azure DevOps Advanced Security uit:** de
  beveiligingssectie van de repo toont "Niet gecontroleerd: bron … staat uit",
  niet "geen meldingen".
- **Een registry uit:** voor packages van dat ecosysteem geen nieuwste versie
  en geen updatestatus. Bij die packages: "Versie niet gecontroleerd: bron npm
  staat uit". Ze tellen niet mee als "actueel".
- **endoflife.date of swift.org uit:** runtimes van dat product krijgen geen
  EOL- of achter-status maar "Niet gecontroleerd: bron … staat uit". Ze tellen
  niet mee als "actueel".
- Bij OSV.dev uit blijven de meldingen van Azure DevOps Advanced Security
  (ook kwetsbare packages) gewoon zichtbaar in de beveiligingssectie van de
  repo; de package-schermen tonen "Niet gecontroleerd: bron OSV.dev staat uit".
- Het tabblad Bronnen toont bij OSV.dev vast de waarschuwing dat dit de enige
  bron voor kwetsbaarheden in packages bij GitHub- en GitLab-repo's is. Uitzetten vraagt geen bevestiging;
  de waarschuwing staat er al.
- Een schakelaar omzetten start geen check. Het effect is zichtbaar na de
  volgende check; het tabblad zegt dat ("Geldt vanaf de volgende check") en
  heeft een knop om nu te checken als de check niet al loopt.

## Het tabblad Bronnen

- Derde tabblad in `SettingsView`, na Accounts en Algemeen, met een passend
  SF Symbol.
- Drie groepen: **Kwetsbaarheden**, **Versies** en **Overige verbindingen**,
  in een `Form` zoals de andere tabbladen.
- Per bron één rij: naam, beschrijving in `.secondary`, het adres (selecteerbaar),
  een link naar de site, en de schakelaar. Zonder "·"-scheidingstekens of em
  dashes (`.claude/rules/swift.md`).
- Onderaan **Kopieer overzicht**.
- Teksten in de String Catalogs, in alle talen die de app heeft (Nederlands,
  Engels, Duits, Frans), zoals CLAUDE.md beschrijft.

## Kopieer overzicht

Platte tekst (leesbaar als Markdown) op het klembord, bijvoorbeeld:

```
Pullwatch 0.5.0: bronnen (3 november 2026)

Kwetsbaarheden
- OSV.dev: aan. Bekende kwetsbaarheden in packages. https://api.osv.dev
- GitHub Advisory Database: aan. Details bij gevonden meldingen. https://api.github.com
...

Versies
- npm: uit. Nieuwste versies van npm-packages. https://registry.npmjs.org
...
```

Met versie en datum, zodat de CISO weet waar het over gaat. In de taal van de
app.

## Model

- Eén lijst van bronnen in `PullwatchCore` (bv. een `DataSource`-type met een
  vaste id, groep, naam, beschrijving, basisadres en sitelink). Het tabblad, het
  overzicht en de checks lezen allemaal uit die ene lijst, zodat ze niet uit
  elkaar lopen.
- De keuze komt in `AppConfig` en dus in `config.json`, als de set van
  **uitgezette** bron-id's. Een nieuwe bron staat daardoor vanzelf aan, en een
  oude config zonder het veld betekent "alles aan".
- Later zelf bronnen toevoegen moet passen zonder de keuzeset om te bouwen; dat
  is de reden voor vaste id's en één lijst. Verder hoeft er nu niets voor
  gebouwd te worden.
- `VersionChecker` (en `AdvisoryDatabase`, de `securityAlerts`-aanroepen)
  krijgen de uitgezette bronnen mee en slaan die aanroepen over. Het resultaat
  legt per repo vast welke controle niet gedaan is en door welke bron, zodat de
  views de juiste tekst kunnen tonen. Dit moet onderscheidbaar blijven van
  "mislukt" (`vulnerabilityError`) en van "niets gevonden".

## Tests

- Per bron: uit betekent nul aanroepen naar zijn adres (`MockHTTPClient`), ook
  bij `run(account:repo:)` en `runMissing`.
- OSV uit: het rapport zegt "niet gecontroleerd", niet een lege lijst
  kwetsbaarheden; geen nieuwe-kwetsbaarheidmeldingen.
- Een registry uit: die packages zijn niet "actueel".
- `config.json` zonder het nieuwe veld decodeert als "alles aan".
- Het overzicht bevat elke bron uit de lijst, met de juiste aan/uit-stand.
- Een controle dat de lijst compleet is: elke host die Pullwatch aanroept
  (checks, adviezen, beveiliging, updatecheck; voor accounts: de server van het
  account) staat in het overzicht.
- OSV weer aan na een periode uit geeft geen stortvloed aan meldingen over
  "nieuwe" kwetsbaarheden: "niet gecontroleerd" telt in `newVulnerabilities`
  zoals `vulnerabilityError`.

## Aan de bouwer

- De precieze teksten (buiten de vaste formule "Niet gecontroleerd: bron xxx
  staat uit"), het SF Symbol en de indeling van de rijen.
- Hoe het "niet gecontroleerd"-resultaat in `RepoVersions` en `VersionReport`
  wordt opgeslagen, zolang oude `versions.json`-bestanden blijven decoderen.
- Of de schakelaars van GitHub-beveiliging en Azure DevOps Advanced Security
  alleen getoond worden als er een account van die dienst is.
- Opgeslagen adviesdetails en registry-resultaten van een bron die uit staat
  niet meer tonen.
- Eén schakelaar voor GitHub-beveiliging op github.com en op GitHub
  Enterprise. GitLab heeft nu geen beveiligings-API (`securityAlerts` geeft
  nil) en krijgt geen rij in Kwetsbaarheden.

## Mijn keuzes (Claude), ter controle

- GitHub-beveiliging en Azure DevOps Advanced Security krijgen ook een schakelaar.
- De keuze staat in `config.json`, als set van uitgezette bronnen.
- Geen bevestiging bij uitzetten; een vaste waarschuwing bij OSV.dev.
- Omzetten start geen check, wel een knop om nu te checken.
- Platte tekst op het klembord, met versie en datum.
- De waarschuwing bij OSV.dev is beperkt tot GitHub- en GitLab-repo's, omdat
  Azure DevOps Advanced Security ook kwetsbare packages meldt.

## In de fork (merge van 0.6.0)

- **CI-checks** is een extra bron, in een eigen groep **Pull requests** op het
  tabblad en in het gekopieerde overzicht (`DataSourceID.ciChecks`). Uit: de
  poll vraagt geen checks (`PollEngine.poll(fetchChecks:)`), de checks die
  eerder opgehaald zijn staan nergens meer (PR-lijst, menu, repo-pagina) en er
  komt geen melding over mislukte checks. De checks komen van de server van
  het account; de adressen in de catalogus zijn de publieke standaard.
- Het getoonde rapport (`visible(disabled:accountKinds:)`) staat in
  `VersionsModel.versionReport`; het bewaarde rapport (`storedReport`) gaat
  naar de volgende check. De schakelaar is `AccountsModel[sourceEnabled:]`.
- De opdrachten voor een AI-agent staan op de vernieuwde repo-pagina achter
  de kopjes van Overzicht en, voor elk kopje van elk tabblad, in
  **Meer > Kopieer voor een AI-agent** (`RepoBriefs`).

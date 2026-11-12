# Branches: pushes naar branches zien

Datum: 2026-11-11

## Waarom

Iemand werkte een paar dagen aan een project en Pullwatch liet geen enkele PR
of tag zien. Dan rijst de vraag of die persoon wel iets doet. Werk dat nog
geen PR of tag heeft, is nu onzichtbaar. Deze functie maakt het zichtbaar:
welke branches bewegen, wie er commit en wanneer.

Het is een overzicht om zelf in te kijken, geen meldingenstroom.

## Doelen

- Een nieuwe sectie **Branches** in de zijbalk van het hoofdvenster, naast
  PRs en Tags.
- Daarin een tijdlijn van pushes naar branches van gevolgde repositories,
  nieuwste eerst. Per rij: branch, repo, wie, aantal nieuwe commits, wanneer.
- Zoeken, en filteren op repo en op persoon. Een klik op een naam in de
  tabel filtert op die persoon.
- Een filter voor eigen pushes: alleen die van anderen, of ook de eigen. De
  eigen pushes horen erbij, het filter bepaalt of je ze ziet.
- Een klik op een rij (of dubbelklik, zoals bij PRs) opent de vergelijking
  van die push in de browser bij de dienst. Daar staan de details; Pullwatch
  toont zelf geen commits of bestanden.
- Alle providers: GitHub, Azure DevOps, GitLab, Bitbucket, Gitea.
- Bij de eerste keer is de lijst meteen gevuld: per branch die de laatste
  14 dagen bewoog één rij met de laatste commit (keuze van Claude; Alessandro
  beantwoordde de vraag niet direct).

## Geen doelen

- Geen meldingen voor pushes, ook geen schakelaar daarvoor.
- Geen inspector met commits of gewijzigde bestanden; de browser doet dat.
- Geen MCP-tool `list_pushes` in deze versie.
- Niet elke losse push apart: Pullwatch ziet wat er tussen twee polls
  veranderde (zie Werking).
- Geen statistieken of grafieken over pushes in Statistieken.

## Anti-doelen

- Ruis in de menubalk of de Dock-badge: pushes tellen niet mee voor
  ongelezen en komen niet in het menu.
- Rate limits raken die PRs of tags laten falen. Branches mogen nooit een
  poll van PRs of tags tegenhouden. Elke fout bij branches, ook
  `.rateLimited`, geldt alleen voor branches: de PRs en tags van die poll
  komen gewoon binnen. Bij `.rateLimited` slaat het account branches over
  tot de limiet voorbij is (keuze van Claude; dit gaat verder dan tags, waar
  `.rateLimited` het account laat falen).
- Een surveillancegevoel: de sectie toont wat in de dienst al openbaar is
  voor wie de repo kan lezen, niet meer.

## Werking

**Wat een push is.** Pullwatch onthoudt per gevolgde repo per branch de
laatste commit (sha). Verandert die tussen twee polls, dan komt er een rij:
branch, repo, wie, oude sha, nieuwe sha, aantal nieuwe commits, tijd. Een
branch die nieuw is, krijgt een rij met het label "nieuwe branch". Pusht
iemand drie keer tussen twee polls, dan is dat één rij met alle nieuwe
commits. Dit geldt voor alle providers gelijk, ook voor Azure DevOps dat
losse pushes wel kent (keuze van Claude: één gedrag overal).

**Wie.** De auteur van de nieuwste commit (de GitHub-login met foto als die
bekend is, anders de naam uit git). Wie er werkelijk pushte, geven de meeste
diensten niet goedkoop terug; de auteur is voor de vraag "doet die persoon
iets" goed genoeg (keuze van Claude).

**Force-push.** Is de oude commit geen voorouder van de nieuwe, dan krijgt de
rij het label "force-push" in plaats van een aantal commits. Hoe dat per
provider goedkoop te bepalen is, is aan de bouwer; lukt het bij een provider
niet zonder veel verzoeken, dan toont die provider de rij als gewone push.

**Pushes naar een branch met een open PR** tellen mee: het gaat om activiteit.

**Verwijderde branches** geven geen rij.

**Eerste keer (seed).** Een repo die nog niet geseed is, levert geen
honderden rijen op. Elke branch met een laatste commit in de afgelopen 14
dagen krijgt één rij met die commit en de datum ervan; oudere branches
worden alleen onthouden. Daarna komen er alleen echte veranderingen bij.
Dit volgt het patroon van de tags (`seeded`, `backfill`,
`tagBackfillLimit`).

**Eigen pushes.** Of een rij van jezelf is, gaat zo goed als de provider
het toelaat (keuze van Claude): is de commit aan een account gekoppeld
(GitHub-login, en bij GitLab en Bitbucket waar de dienst dat geeft), dan op
dat account tegen `userId`; anders op het e-mailadres of de naam van de
commit tegen die van het account (bij Azure DevOps is `userId` een GUID, dus
daar altijd zo). Een rij die niet als eigen te herkennen is, blijft
zichtbaar. De website zegt dat het filter buiten GitHub op naam en
e-mailadres werkt. Het filter "Alleen anderen" staat standaard uit, zodat je alles ziet
(keuze van Claude).

**Welke repos.** Een repo volgt branches via een nieuwe vlag in `WatchSet`
(`branches`), net als `tags`, zodat het per repo aan en uit kan in Repos en
in de accounteditor. Branches lopen mee met PRs (besloten door Alessandro):
elke repo die PRs volgt, volgt ook branches, ook in bestaande configuraties
en ook een repo die PRs alleen via `newRepoDefault` volgt. `NewRepoDefault`
krijgt geen nieuwe keuze: `.prs` en `.prsAndTags` geven allebei branches
mee, dus Settings en de onboarding veranderen niet. Wie het voor een repo
niet wil, zet `branches` daar uit. De kosten blijven beperkt doordat een
repo zonder verandering via de vingerafdruk bijna niets kost.

**Geschiedenis.** Rijen bewaren net zo lang als de PR-geschiedenis
(`HistoryRetention`). Of ze in `history.json` komen als nieuw
`HistoryEntry`-geval of in een eigen bestand, is aan de bouwer; ze tellen in
geen geval mee voor gelezen, ongelezen, de Dock-badge en het menu.

**Kosten.** Alleen een branch die veranderde kost meer dan het ophalen van
de lijst. Bij GitHub gaan branches zoals tags via GraphQL met aliassen en
een vingerafdruk per repo, zodat een repo zonder verandering bijna niets
kost. Branches worden niet vaker opgehaald dan tags.

## Per provider (wat de bouwer kan gebruiken)

| Provider | Branches met laatste commit | Vergelijking in de browser |
|---|---|---|
| GitHub | GraphQL `refs(refPrefix: "refs/heads/")` met `target { ... on Commit }` | `/<owner>/<repo>/compare/<oud>...<nieuw>` |
| Azure DevOps | `_apis/git/repositories/{id}/refs?filter=heads/` | `.../branchCompare?baseVersion=GC<oud>&targetVersion=GC<nieuw>` |
| GitLab | `/projects/:id/repository/branches` | `/-/compare/<oud>...<nieuw>` |
| Bitbucket | `/repositories/{ws}/{repo}/refs/branches` | `/branches/compare/<nieuw>%0D<oud>` |
| Gitea | `/repos/{owner}/{repo}/branches` | `/compare/<oud>...<nieuw>` |

Bij een nieuwe branch of een seed-rij zonder oude commit opent de klik de
branch zelf (of de nieuwste commit) in plaats van een vergelijking. Elke
provider krijgt de methode in een eigen `+Branches`-bestand, met een
standaard in `PRProvider` die niets teruggeeft, zoals bij de andere
uitbreidingen. Paginering volgt `PageLink`.

## Scherm

Sectie **Branches** in de zijbalk (`MainView`) na Tags. Een tabel zoals die
van PRs en Tags, met de kolommen Branch, Repo, Wie (met foto), Commits
("+4", "force-push" of "nieuwe branch") en Laatste push (relatieve tijd).
Toolbar met zoeken, filter op repo, filter op persoon en de schakelaar voor
eigen pushes. Een lege staat zoals `FilteredEmptyView` als filters alles
verbergen, en een eigen lege staat als er nog geen branches gevolgd worden.
Contextmenu op een rij: openen in browser, branchnaam kopiëren.

De mockup uit het gesprek staat in
`.superpowers/brainstorm/` (optie A en de doorklik), niet in git.

## Beperkingen

- Alle tekst in nl, en, de en fr (`sync-strings.sh`, `LocalizationTests`).
- Geen em dashes, geen "·" als scheidingsteken in UI of docs.
- Een bron die uit staat (Settings, Sources) of een provider zonder steun
  toont dat met de bestaande "Niet gecontroleerd"-teksten waar dat past.
- `FakeGitHub` en `FakeWorld` krijgen branches en pushes, zodat de UI-tests
  en de camera-tour de sectie in licht en donker vastleggen; de website
  (`site/`, vier talen) krijgt een pagina of paragraaf met screenshots.
- Changelog-fragment in `changelog.d/`.
- Testen per provider met `MockHTTPClient` en voor de engine (seed,
  verandering, force-push, verwijderde branch, nieuwe branch, eigen filter).

## Werkwijze

Eerst lokaal: bouwen op een branch `feat/branches`, Alessandro draait de app
en bekijkt de sectie. Pas na zijn akkoord gaat de branch naar `origin` en
komt er een PR in de fork. Een issue in de fork volgt bij de PR.

## Aan de bouwer

- Of rijen in `history.json` staan of apart.
- Hoe het aantal nieuwe commits en een force-push per provider het
  goedkoopst te bepalen zijn.
- De precieze GraphQL-vorm en batchgrootte bij GitHub.
- Of de oude sha's in `SeenState` of een eigen bestand staan.

---
title: Rechten van tokens
description: De scopes en rechten die Pullwatch nodig heeft op GitHub, GitHub Enterprise, Azure DevOps, GitLab, Bitbucket, Codeberg, Forgejo en Gitea.
---

Pullwatch leest alleen. Geef een token de leesrechten hieronder en niets meer. Ontbreekt een recht voor een optioneel deel, dan staat bij dat deel **Toestemming nodig** met een link, en de rest blijft werken.

## GitHub

**Fine-grained token**, op de repositories die je wilt volgen:

| Recht | Nodig voor |
|---|---|
| Pull requests: Read | pull requests |
| Metadata: Read | repositories (altijd verplicht) |
| Contents: Read | de check van afhankelijkheden (manifesten en lockfiles) |
| Repository security advisories: Read | de eigen adviezen van de repository |
| Code scanning alerts: Read | optioneel, meldingen van code scanning |
| Secret scanning alerts: Read | optioneel, het aantal open meldingen van secret scanning |
| Checks: Read en Commit statuses: Read | optioneel, de checks van elke pull request |

**Classic token**: `repo`, plus `security_events` voor de meldingen van code scanning en secret scanning, en optioneel `read:packages` voor de packages die je repositories in GitHub Packages publiceren. Met de GitHub CLI voeg je die scope toe met `gh auth refresh -s read:packages`.

**Inloggen met GitHub** gebruikt de GitHub-app van Pullwatch. Die vraagt om deze rechten op repositories, allemaal alleen lezen, en verder niets:

| Recht | Toegang | Waarvoor | Zonder dit recht |
|---|---|---|---|
| Metadata | Read-only, verplicht | de repositories van de eigenaren die je volgt | GitHub staat geen app zonder toe |
| Pull requests | Read-only | pull requests, hun co-auteurs en de merge queue | geen pull requests |
| Contents | Read-only | tags, releases en de bestanden voor de check van afhankelijkheden | geen tags of releases, geen check van afhankelijkheden |
| Repository security advisories | Read-only | de eigen adviezen van de repository | **Toestemming nodig** op de pagina van de repository |
| Checks | Read-only | de check runs in de checks van elke pull request | geen checks bij pull requests |
| Commit statuses | Read-only | de commit statuses in dezelfde checks | geen checks bij pull requests |
| Code scanning alerts | Read-only, optioneel | meldingen van code scanning | **Toestemming nodig** ernaast |
| Secret scanning alerts | Read-only, optioneel | het aantal open meldingen van secret scanning | **Toestemming nodig** ernaast |

De eigenaar van elke installatie keurt ze goed; krijgt de app een nieuw recht, dan vraagt GitHub de eigenaar om dat nog een keer goed te keuren.

De app heeft geen recht Packages: GitHub geeft packages aan geen enkele GitHub App. Een account dat inlogt met GitHub leest de packages die zijn repositories publiceren daarom met de GitHub CLI. **Packages lezen met de GitHub CLI** in de account-editor staat aan als `gh` is ingelogd, en toont welk `gh`-account het gebruikt. Dat account heeft de scope `read:packages` nodig: `gh auth refresh -h github.com -s read:packages`. Zonder `gh`, zonder de scope of met de schakelaar uit toont **Packages** **Toestemming nodig** met de precieze opdracht.

## GitHub Enterprise

Maak het token op je eigen server. Classic: `repo` en `read:org`, plus `security_events` voor de meldingen. **Token maken** in het accountscherm opent de tokenpagina van de server met deze al ingevuld. Fine-grained tokens hebben dezelfde rechten nodig als op github.com.

Met de GitHub CLI voert Pullwatch `gh auth token --hostname <server>` uit. Log eerst in met `gh auth login --hostname <server>`.

## Azure DevOps

| Scope | Nodig voor |
|---|---|
| Code (Read) | pull requests, tags en de check van afhankelijkheden |
| Project and Team (Read) | de lijst met projecten |
| Advanced Security (Read) | optioneel, meldingen van Advanced Security |
| Packaging (Read) | optioneel, de packages in je feeds van Azure Artifacts |

Met de Azure CLI log je in met `az login`; Pullwatch vraagt `az` om een token.

## GitLab

Een personal access token met de scope **read_api** dekt merge requests, projecten, tags, releases, commits en bestanden, en de packages en container-images die je projecten in de registers van GitLab publiceren. `api` werkt ook, maar geeft meer dan Pullwatch nodig heeft. Met de GitLab CLI leest Pullwatch `glab config get token --host <server>`.

## Bitbucket

Een **API-token met scopes** van Atlassian voor de app Bitbucket, samen met het e-mailadres van je Atlassian-account:

| Scope | Nodig voor |
|---|---|
| `read:user:bitbucket` | je eigen account, om je eigen pull requests te verbergen |
| `read:repository:bitbucket` | repositories, tags, build-statussen (de checks) en de check van afhankelijkheden |
| `read:pullrequest:bitbucket` | pull requests en hun commits (de co-auteurs) |

Meer vraagt Pullwatch niet. `read:workspace:bitbucket` is niet nodig: Pullwatch controleert een workspace via zijn repositories. De app passwords van Bitbucket werken sinds juli 2026 niet meer.

## Codeberg, Forgejo en Gitea

Maak een token onder Instellingen, Applicaties op de server, met deze scopes, alle op Lezen:

| Scope | Gebruikt voor |
|---|---|
| `read:user` | wie je bent, en de repositories van gebruikers die je volgt |
| `read:organization` | de organisaties die je volgt en hun repositories |
| `read:repository` | pull requests, tags, releases, commit statuses (checks), commits en bestanden |
| `read:issue` | de lijst van pull requests, die uit de zoekfunctie voor issues komt (`/repos/issues/search`) |

Mist er een, dan noemt **Test verbinding** de scope die ontbreekt. Een token dat alleen bij openbare repositories mag, werkt alleen voor openbare repositories. Inloggen via de opdrachtregel kan niet: `tea` heeft geen opdracht die zijn token afgeeft.

## Inloggen met een opdrachtregeltool

Met `gh`, `az` of `glab` haalt Pullwatch het token uit de opdrachtregeltool, dus je logt daar in en niet in Pullwatch. Een aanroep van deze tools stopt na 20 seconden.

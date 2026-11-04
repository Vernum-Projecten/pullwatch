---
title: Rechten van tokens
description: De scopes en rechten die Pullwatch nodig heeft op GitHub, GitHub Enterprise, Azure DevOps en GitLab.
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

**Inloggen met GitHub** gebruikt de GitHub-app van Pullwatch, die om dezelfde leesrechten vraagt, plus het optionele Packages: Read voor de packages die je repositories publiceren; zonder dat recht staat bij die packages dat er een recht ontbreekt. De eigenaar van elke installatie keurt ze goed; krijgt de app een nieuw recht, dan vraagt GitHub de eigenaar om dat nog een keer goed te keuren.

## GitHub Enterprise

Maak het token op je eigen server. Classic: `repo` en `read:org`, plus `security_events` voor de meldingen. **Token maken** in het accountscherm opent de tokenpagina van de server met deze al ingevuld. Fine-grained tokens hebben dezelfde rechten nodig als op github.com.

Met de GitHub CLI voert Pullwatch `gh auth token --hostname <server>` uit. Log eerst in met `gh auth login --hostname <server>`.

## Azure DevOps

| Scope | Nodig voor |
|---|---|
| Code (Read) | pull requests, tags en de check van afhankelijkheden |
| Project and Team (Read) | de lijst met projecten |
| Advanced Security (Read) | optioneel, meldingen van Advanced Security |

Met de Azure CLI log je in met `az login`; Pullwatch vraagt `az` om een token.

## GitLab

Een personal access token met de scope **read_api** dekt merge requests, projecten, tags, releases, commits en bestanden. `api` werkt ook, maar geeft meer dan Pullwatch nodig heeft. Met de GitLab CLI leest Pullwatch `glab config get token --host <server>`.

## Inloggen met een opdrachtregeltool

Met `gh`, `az` of `glab` haalt Pullwatch het token uit de opdrachtregeltool, dus je logt daar in en niet in Pullwatch. Een aanroep van deze tools stopt na 20 seconden.

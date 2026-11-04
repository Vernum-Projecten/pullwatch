---
title: Je accounts toevoegen
description: Koppel GitHub, GitHub Enterprise, Azure DevOps en GitLab, en kies welke repositories Pullwatch volgt.
---

Open **Instellingen** (de knop met het tandwiel in het menupaneel) en ga naar **Accounts**. Voeg een account toe met **+**, kies hoe Pullwatch inlogt, en controleer het met **Test verbinding**. Je kunt zoveel accounts toevoegen als je wilt, van elke soort.

Pullwatch leest alleen. Het plaatst nooit een reactie, merget niets en verandert niets op je servers.

## GitHub

Op github.com kun je op drie manieren inloggen:

- **Inloggen met GitHub.** Pullwatch toont een code, die bevestig je op github.com, en de GitHub-app van Pullwatch krijgt leestoegang tot de repositories die je kiest als je hem installeert. De app vraagt alleen om leesrechten.
- **Personal Access Token.** Plak een token dat je zelf hebt gemaakt. Zie [Rechten van tokens](/nl/getting-started/permissions/) voor de scopes.
- **GitHub CLI.** Gebruik je `gh` (`gh auth login`), dan vraagt Pullwatch daar een token aan. Met meerdere `gh`-accounts kies je onder **GitHub-account** welk account Pullwatch gebruikt.

## GitHub Enterprise

Kies **GitHub Enterprise** op de kaart van GitHub (of in het menu **+**) en vul je server in bij **Server**:

- een GitHub Enterprise Server, zoals `https://github.example.com`, of
- het subdomein van je enterprise op GHE.com, zoals `https://acme.ghe.com`.

Alleen https werkt, zodat een token nooit onversleuteld over het netwerk gaat. Pullwatch vindt de API zelf en linkt naar pull requests, tags en repositories op die server. Log in met een personal access token dat je op die server hebt gemaakt, of met de GitHub CLI na `gh auth login --hostname <server>`. **Inloggen met GitHub** werkt alleen voor github.com.

Wat een server niet heeft, staat er als **Niet beschikbaar op deze server** in plaats van als fout, zoals de eigen beveiligingsadviezen van een repository op GitHub Enterprise Server.

## Azure DevOps

Vul je organisatie in en log in met een personal access token of met de Azure CLI (`az login`). Pullwatch leest de projecten van de organisatie en hun repositories.

## GitLab

Laat **Server** leeg voor gitlab.com, of vul je eigen server in (alleen https, bijvoorbeeld `https://gitlab.example.com`). Zet de groepen of gebruikers die je wilt volgen erin, gescheiden door komma's, zoals `acme, acme/platform`. Een groep volgt ook zijn subgroepen, en repositories verschijnen als `groep/subgroep/project`.

Log in met een personal access token met de scope `read_api`, of met de GitLab CLI (`glab auth login`). **Token maken** in het accountscherm opent de tokenpagina van je server met de naam en de scope al ingevuld.

## Kiezen wat je volgt

Elk account toont zijn repositories. Vink per repository aan wat je wilt:

- **PR's**: nieuwe pull requests (of merge requests).
- **Tags**: nieuwe tags, en op GitHub en GitLab de releases die erbij gemaakt zijn. Tags staan standaard uit.
- **Gemerged**: pull requests die gemerged worden.

Naast elk vinkje staat een bel. Zet die uit om een repository in het menu en de geschiedenis te houden zonder meldingen. De bel in de kop zet alle zichtbare repositories in één keer om. Per account kun je ook draft-pull requests meenemen, je eigen pull requests verbergen, en het hele account een tijdje uitzetten.

## Repositories buiten je account

Onder **Andere repositories**, onderaan de lijst, voeg je een losse repository toe die niet bij de eigenaren of groepen van het account hoort:

- GitHub: `eigenaar/repo`, of plak een link van github.com.
- Azure DevOps: `project/repo` binnen de organisatie van het account, of een link van dev.azure.com.
- GitLab: `groep/subgroep/project`, of een link van gitlab.com of van de eigen server van het account.

Pullwatch controleert hem met één verzoek en zegt in gewone woorden wanneer het hem niet kan vinden of lezen. Een openbare repository op github.com of gitlab.com die je token niet mag lezen, wordt gelezen zonder in te loggen. **Volg een repository…** (⇧⌘N, in het menu Ga en in de knoppenbalk van Repo's) opent hetzelfde veld, met een keuze voor het account. Haal er een weg met een rechtermuisklik of de Delete-toets.

Zo'n repository verschijnt overal zoals de andere die je volgt, gegroepeerd onder zijn eigen eigenaar.

- **GitHub**: dit werkt ook voor een openbare repository van een andere organisatie waar de GitHub-app van Pullwatch niet geïnstalleerd is, zoals `openEHR/specifications-AM`. De pull requests van deze repositories komen binnen met één zoekopdracht per account, met maximaal 30 repositories per zoekopdracht.
- **GitLab**: links van gitlab.com of van de eigen server van het account werken, ook `/-/`-links zoals `/-/merge_requests/12`; een link naar een andere server wordt geweigerd. Een openbaar project wordt alleen zonder inloggen gelezen als de server zonder token antwoordt: gitlab.com doet dat, een server die inloggen vereist niet, en dan wordt het project niet gevonden. Elk zo'n project kost per poll één verzoek voor zijn merge requests (één pagina, de 100 die het laatst zijn bijgewerkt).

## Hoe vaak Pullwatch kijkt

Onder Instellingen, Algemeen stel je in hoe vaak Pullwatch naar nieuwe pull requests kijkt, en hoe lang de geschiedenis bewaard blijft (2 maanden, 6 maanden, 1 jaar of altijd). Tags worden elke 15 minuten gecontroleerd. **Nu verversen** in het menupaneel kijkt meteen.

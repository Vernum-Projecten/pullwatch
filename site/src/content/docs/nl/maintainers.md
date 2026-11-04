---
title: Voor maintainers
description: Waar de documentatie voor maintainers staat, en hoe je Pullwatch uit de broncode bouwt.
---

De documentatie voor maintainers staat in de repository, naast de code die ze beschrijft, zodat ze in dezelfde pull request meeverandert.

| Document | Waar het over gaat |
|---|---|
| [docs/setup.md](https://github.com/alessandro823/pullwatch/blob/main/docs/setup.md) | Alles wat de maintainer buiten de code instelt: ondertekening, de GitHub-app, de secrets voor releases |
| [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) | De procedure voor een release en de secrets in Actions |
| [docs/github-app.md](https://github.com/alessandro823/pullwatch/blob/main/docs/github-app.md) | De GitHub-app achter **Inloggen met GitHub** |
| [docs/website.md](https://github.com/alessandro823/pullwatch/blob/main/docs/website.md) | Deze website: GitHub Pages, het eigen domein en de DNS-records ervan |
| [site/README.md](https://github.com/alessandro823/pullwatch/blob/main/site/README.md) | Deze website draaien en bouwen, en een pagina toevoegen |
| [CONTRIBUTING.md](https://github.com/alessandro823/pullwatch/blob/main/CONTRIBUTING.md) | Hoe je een wijziging bouwt, test en instuurt, en wat een pull request nodig heeft |
| [SECURITY.md](https://github.com/alessandro823/pullwatch/blob/main/SECURITY.md) | Hoe je een kwetsbaarheid vertrouwelijk meldt, en wat eronder valt |
| [CHANGELOG.md](https://github.com/alessandro823/pullwatch/blob/main/CHANGELOG.md) | De release notes van elke versie |

## Bouwen uit de broncode

Je hebt Xcode 27 (Swift 6.4) nodig op macOS 26.6 of nieuwer. Optioneel `az` (`az login`), `gh` (`gh auth login`) of `glab` (`glab auth login`) om via een opdrachtregeltool in te loggen.

Open `Pullwatch/Pullwatch.xcodeproj` en voer het scheme **Pullwatch** uit (⌘R), of vanaf de opdrachtregel:

```sh
swift test --package-path PullwatchKit              # the PullwatchKit unit tests
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch build
scripts/release/release.sh --unsigned               # dist/Pullwatch-<version>.dmg and .zip, ad hoc signed
scripts/release/release.sh                          # signed with Developer ID, notarized and stapled
```

Draai je vanuit Xcode terwijl een geïnstalleerde Pullwatch open is, dan krijg je twee iconen in de menubalk; stop eerst de geïnstalleerde met **Stop Pullwatch** in het menupaneel ervan. Een ad hoc ondertekende build kan voor accounts met een token na elke installatie opnieuw om toegang tot de sleutelhanger vragen; kies **Sta altijd toe**.

## De repository

- `Pullwatch/`: de app, met het Xcode-project. `Pullwatch/Pullwatch/` heeft per onderdeel een map met het model en de views, zoals `Accounts/`, `PullRequests/`, `Repositories/` en `Settings/`.
- `PullwatchKit/`: het Swift-package dat de app linkt, met de unittests. De modules zijn `PullwatchCore` (modellen, polling, geschiedenis, versiechecks, updates), `PullwatchGitHub`, `PullwatchAzureDevOps` en `PullwatchGitLab` (één per dienst), `PullwatchProviders` (kiest de dienst voor een account) en `PullwatchMCP` (de server voor coding agents).
- `site/`: deze website. `scripts/`: de scripts voor releases, checks en ontwikkeling. `docs/`: de documenten voor maintainers hierboven.

## Een releasebuild maken

`release.sh` bouwt de app, haalt de XPC-services van Sparkle weg (alleen een app in een sandbox heeft die nodig) en ondertekent de onderdelen van Sparkle een voor een, en geeft de app dan door aan `scripts/release/package.sh`. Dat maakt de schijfkopie en `Pullwatch-<version>.zip`, de update die Sparkle installeert; de release-workflow schrijft daarvoor de ondertekende `appcast.xml`.

De schijfkopie opent als installatievenster: de app links, Apps rechts, en een achtergrond getekend door `scripts/release/dmg-background.swift` met "Install Pullwatch" en een pijl ertussen. Finder legt dat venster aan via AppleScript, dus de eerste keer wordt gevraagd of je terminal Finder mag besturen; sta dat toe onder Systeeminstellingen, Privacy en beveiliging, Automatisering.

De versie is `MARKETING_VERSION`, en het buildnummer `CURRENT_PROJECT_VERSION`, in `Pullwatch/App.xcconfig`. Een ondertekende release heeft een Developer ID Application-certificaat in de sleutelhanger nodig en een notarytool-profiel (`xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>`); kies andere met `SIGN_ID=...` en `NOTARY_PROFILE=...`. [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) heeft de volledige procedure.

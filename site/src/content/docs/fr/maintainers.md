---
title: Pour les mainteneurs
description: "Où se trouve la documentation des mainteneurs, et comment compiler Pullwatch à partir des sources."
---

La documentation des mainteneurs se trouve dans le dépôt, à côté du code qu’elle décrit, pour qu’elle change dans la même pull request.

| Document | Contenu |
|---|---|
| [docs/setup.md](https://github.com/alessandro823/pullwatch/blob/main/docs/setup.md) | Tout ce que le mainteneur configure en dehors du code : la signature, la GitHub App, les secrets de publication |
| [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) | La procédure de publication et ses secrets Actions |
| [docs/github-app.md](https://github.com/alessandro823/pullwatch/blob/main/docs/github-app.md) | La GitHub App derrière **Se connecter avec GitHub** |
| [docs/website.md](https://github.com/alessandro823/pullwatch/blob/main/docs/website.md) | Ce site : GitHub Pages, le domaine personnalisé et ses enregistrements DNS |
| [site/README.md](https://github.com/alessandro823/pullwatch/blob/main/site/README.md) | Lancer et compiler ce site, et ajouter une page |
| [CHANGELOG.md](https://github.com/alessandro823/pullwatch/blob/main/CHANGELOG.md) | Les notes de version de chaque version |

## Compiler à partir des sources

Il vous faut Xcode 27 (Swift 6.4) sur macOS 26.6 ou ultérieur. En option, `az` (`az login`), `gh` (`gh auth login`) ou `glab` (`glab auth login`) pour vous connecter via un outil en ligne de commande.

Ouvrez `Pullwatch/Pullwatch.xcodeproj` et lancez le schéma **Pullwatch** (⌘R), ou en ligne de commande :

```sh
swift test --package-path PullwatchKit              # les tests unitaires de PullwatchKit
xcodebuild -project Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch build
scripts/release/release.sh --unsigned               # dist/Pullwatch-<version>.dmg et .zip, signés ad hoc
scripts/release/release.sh                          # signé avec Developer ID, notarisé et agrafé
```

Si vous lancez l’app depuis Xcode alors qu’un Pullwatch installé est ouvert, vous obtenez deux icônes dans la barre des menus ; quittez d’abord celui qui est installé avec **Quitter Pullwatch** dans son panneau du menu. Une build signée ad hoc peut redemander l’accès au trousseau après chaque installation pour les comptes à jeton ; choisissez **Toujours autoriser**.

## Le dépôt

- `Pullwatch/` : l’app, avec le projet Xcode. `Pullwatch/Pullwatch/` contient un dossier par fonction avec son modèle et ses vues, comme `Accounts/`, `PullRequests/`, `Repositories/` et `Settings/`.
- `PullwatchKit/` : le paquet Swift que l’app intègre, avec les tests unitaires. Ses modules sont `PullwatchCore` (modèles, interrogation, historique, vérification des versions, mises à jour), `PullwatchGitHub`, `PullwatchAzureDevOps` et `PullwatchGitLab` (un par service), `PullwatchProviders` (choisit le service d’un compte) et `PullwatchMCP` (le serveur pour les agents de code).
- `site/` : ce site. `scripts/` : les scripts de publication, de vérification et de développement. `docs/` : les documents des mainteneurs ci-dessus.

## Créer une build de publication

`release.sh` compile l’app, retire les services XPC de Sparkle (seule une app en sandbox en a besoin) et signe les éléments de Sparkle un par un, puis passe l’app à `scripts/release/package.sh`. Celui-ci crée l’image disque et `Pullwatch-<version>.zip`, la mise à jour que Sparkle installe ; le workflow de publication écrit l’`appcast.xml` signé correspondant.

L’image disque s’ouvre sur une fenêtre d’installation : l’app à gauche, Applications à droite, et un arrière-plan dessiné par `scripts/release/dmg-background.swift` qui affiche « Install Pullwatch » avec une flèche entre les deux. Le Finder dispose cette fenêtre via AppleScript, donc la première exécution demande si votre terminal peut contrôler le Finder ; autorisez-le dans Réglages Système, Confidentialité et sécurité, Automatisation.

La version est `MARKETING_VERSION`, et le numéro de build `CURRENT_PROJECT_VERSION`, dans `Pullwatch/App.xcconfig`. Une version signée demande un certificat Developer ID Application dans le trousseau et un profil notarytool (`xcrun notarytool store-credentials pullwatch --apple-id <id> --team-id <team>`) ; choisissez-en d’autres avec `SIGN_ID=...` et `NOTARY_PROFILE=...`. [docs/releasing.md](https://github.com/alessandro823/pullwatch/blob/main/docs/releasing.md) décrit la procédure complète.

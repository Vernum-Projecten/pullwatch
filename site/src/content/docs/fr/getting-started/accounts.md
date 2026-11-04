---
title: Ajouter vos comptes
description: "Connectez GitHub, GitHub Enterprise, Azure DevOps et GitLab, et choisissez les dépôts que Pullwatch suit."
---

Ouvrez **Réglages** (le bouton en forme d’engrenage du panneau du menu) et allez dans **Comptes**. Ajoutez un compte avec **+**, choisissez comment Pullwatch se connecte, et utilisez **Tester la connexion** pour le vérifier. Vous pouvez ajouter autant de comptes que vous voulez, de tout type.

Pullwatch ne fait que lire. Il ne commente, ne fusionne et ne modifie jamais rien sur vos serveurs.

## GitHub

Il y a trois façons de se connecter sur github.com :

- **Se connecter avec GitHub.** Pullwatch affiche un code, vous le confirmez sur github.com, et la GitHub App Pullwatch obtient un accès en lecture aux dépôts que vous choisissez en l’installant. L’app ne demande que des autorisations en lecture.
- **Personal Access Token.** Collez un jeton que vous avez créé vous-même. Voir [Autorisations des jetons](/fr/getting-started/permissions/) pour les portées.
- **GitHub CLI.** Si vous utilisez `gh` (`gh auth login`), Pullwatch lui demande un jeton. Avec plusieurs comptes `gh`, choisissez celui à utiliser sous **Compte GitHub**.

## GitHub Enterprise

Choisissez **GitHub Enterprise** sur la carte GitHub (ou dans le menu **+**) et saisissez votre serveur sous **Serveur** :

- un GitHub Enterprise Server, comme `https://github.example.com`, ou
- le sous-domaine de votre entreprise sur GHE.com, comme `https://acme.ghe.com`.

Seul https fonctionne, pour qu’un jeton ne circule jamais sans chiffrement. Pullwatch trouve l’API tout seul et crée des liens vers les pull requests, les tags et les dépôts sur ce serveur. Connectez-vous avec un jeton d’accès personnel créé sur ce serveur, ou avec la GitHub CLI après `gh auth login --hostname <server>`. **Se connecter avec GitHub** ne vaut que pour github.com.

Ce qu’un serveur ne propose pas s’affiche comme **Non disponible sur ce serveur** au lieu d’une erreur, par exemple les avis de sécurité propres d’un dépôt sur GitHub Enterprise Server.

## Azure DevOps

Saisissez votre organisation, puis connectez-vous avec un jeton d’accès personnel ou avec Azure CLI (`az login`). Pullwatch lit les projets de l’organisation et leurs dépôts.

## GitLab

Laissez **Serveur** vide pour gitlab.com, ou saisissez votre propre serveur (https uniquement, par exemple `https://gitlab.example.com`). Indiquez les groupes ou les utilisateurs à suivre, séparés par des virgules, comme `acme, acme/platform`. Un groupe inclut ses sous-groupes, et les dépôts apparaissent sous la forme `group/subgroup/project`.

Connectez-vous avec un jeton d’accès personnel avec la portée `read_api`, ou avec la GitLab CLI (`glab auth login`). **Créer un jeton** dans l’éditeur de compte ouvre la page des jetons de votre serveur avec le nom et la portée déjà remplis.

## Choisir ce que vous suivez

Chaque compte liste ses dépôts. Pour chaque dépôt, cochez ce que vous voulez :

- **PR** : les nouvelles pull requests (ou merge requests).
- **Tags** : les nouveaux tags et, sur GitHub et GitLab, les versions publiées qui leur sont associées. Les tags sont désactivés par défaut.
- **Fusionnée** : les pull requests qui sont fusionnées.

À côté de chaque case se trouve une cloche. Désactivez-la pour garder un dépôt dans le menu et l’historique sans notifications. La cloche de l’en-tête bascule d’un coup tous les dépôts visibles. Pour chaque compte, vous pouvez aussi inclure les pull requests en brouillon, masquer les vôtres, et désactiver tout le compte pour un temps.

## Dépôts hors de votre compte

Sous **Autres dépôts**, en bas de la liste, ajoutez un dépôt isolé qui ne fait pas partie des propriétaires ou des groupes du compte :

- GitHub : `owner/repo`, ou collez un lien github.com.
- Azure DevOps : `project/repo` dans l’organisation du compte, ou un lien dev.azure.com.
- GitLab : `group/subgroup/project`, ou un lien de gitlab.com ou du propre serveur du compte.

Pullwatch le vérifie avec une seule requête et vous dit en termes simples quand il ne peut pas le trouver ou le lire. Un dépôt public sur github.com ou gitlab.com que votre jeton ne peut pas lire est lu sans connexion. **Suivre un dépôt…** (⇧⌘N, dans le menu Aller et dans la barre d’outils de Dépôts) ouvre le même champ avec un choix de compte. Retirez-en un avec un clic droit ou la touche Supprimer.

Un tel dépôt apparaît partout comme les autres dépôts que vous suivez, regroupé sous son propre propriétaire.

- **GitHub** : cela fonctionne aussi pour un dépôt public d’une autre organisation où la GitHub App Pullwatch n’est pas installée, comme `openEHR/specifications-AM`. Les pull requests de ces dépôts arrivent par une recherche par compte, avec jusqu’à 30 dépôts par recherche.
- **GitLab** : les liens de gitlab.com ou du propre serveur du compte fonctionnent, y compris les liens `/-/` comme `/-/merge_requests/12` ; un lien vers un autre serveur est refusé. Un projet public n’est lu sans connexion que si le serveur répond sans jeton : gitlab.com le fait, un serveur qui exige une connexion non, et le projet est alors introuvable. Chaque projet de ce type coûte une requête par interrogation pour ses merge requests (une page, les 100 plus récemment mises à jour).

## À quelle fréquence Pullwatch regarde

Dans Réglages, Général, vous choisissez à quelle fréquence Pullwatch cherche de nouvelles pull requests, et combien de temps l’historique est conservé (2 mois, 6 mois, 1 an ou Toujours). Les tags sont vérifiés toutes les 15 minutes. **Actualiser maintenant** dans le panneau du menu vérifie tout de suite.

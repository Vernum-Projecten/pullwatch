---
title: FAQ
description: Des réponses courtes aux questions fréquentes sur Pullwatch.
---

## Pullwatch est-il gratuit ?

Oui. Pullwatch est open source sous [licence Apache 2.0](https://github.com/alessandro823/pullwatch/blob/main/LICENSE), et chaque version est sur [GitHub](https://github.com/alessandro823/pullwatch/releases).

## Sur quels Mac fonctionne-t-il ?

macOS 26.6 ou ultérieur, sur Apple silicon et sur Intel. C’est une seule app universelle.

## Quels services prend-il en charge ?

GitHub (github.com, GitHub Enterprise Server et GHE.com), Azure DevOps et GitLab (gitlab.com et votre propre serveur). Voir [Ajouter vos comptes](/fr/getting-started/accounts/).

## Pullwatch peut-il modifier quelque chose dans mes dépôts ?

Non. Il ne fait que lire : les pull requests, les tags, les versions publiées, les fichiers des dépôts pour la vérification des dépendances, et les alertes de sécurité. Il ne commente, n’approuve, ne fusionne et ne pousse jamais rien.

## Envoie-t-il mon code quelque part ?

Non. Aucun code source ne quitte votre Mac, sauf vers vos propres serveurs, d’où il vient. Pour la vérification des dépendances, les noms et les versions des paquets sont envoyés à OSV.dev et aux registres de paquets. Vous pouvez désactiver chacun d’eux. Voir [Confidentialité et sources](/fr/privacy/).

## À quelle fréquence vérifie-t-il ?

Les pull requests, à l’intervalle que vous choisissez dans Réglages, Général. Les tags, toutes les 15 minutes. L’historique des pull requests existantes, toutes les 15 minutes. Les dépendances et les vulnérabilités, une fois par jour (vous pouvez le désactiver), et chaque fois que vous cliquez sur **Tout vérifier** ou **Vérifier**.

## Pourquoi une notification n’a-t-elle pas de son ?

Les tags sans version publiée, les pull requests fusionnées et les nouvelles versions arrivent en silence, exprès, uniquement dans le Centre de notifications. Pendant les **Heures calmes**, rien ne fait de bruit. Les modes Concentration et Ne pas déranger de macOS s’appliquent aussi.

## Puis-je suivre un dépôt qui n’est pas le mien ?

Oui. Ajoutez-le sous **Autres dépôts** dans son compte, ou avec **Suivre un dépôt…** (⇧⌘N). Un dépôt public sur github.com ou gitlab.com fonctionne même quand votre jeton ne peut pas le lire.

## Quelles langues Pullwatch parle-t-il ?

L’anglais, le néerlandais, l’allemand et le français. Il suit la langue de macOS, ou vous la choisissez dans Réglages, Général, **Langue**.

## Comment faire une mise à jour ?

Pullwatch recherche les mises à jour une fois par jour et les installe pour vous. Voir [Mises à jour](/fr/getting-started/install/#mises-à-jour).

## Pullwatch est-il affilié à GitHub, GitLab ou Microsoft ?

Non. GitHub est une marque de GitHub, Inc., GITLAB est une marque de GitLab Inc., et Azure DevOps est une marque du groupe de sociétés Microsoft.

---
title: Installation et premier lancement
description: "Téléchargez Pullwatch, placez-le dans Applications et suivez la fenêtre de bienvenue."
sidebar:
  label: Installation et premier lancement
---

## Ce qu’il vous faut

- Un Mac avec macOS 26.6 ou ultérieur. Pullwatch est une app universelle, il fonctionne donc en natif sur Apple silicon et sur Intel.
- Un compte sur au moins un de ces services : github.com, un serveur GitHub Enterprise (Server ou GHE.com), Azure DevOps ou GitLab (gitlab.com ou votre propre serveur).

## Installation

1. Téléchargez le dernier `Pullwatch-x.y.z.dmg` depuis la [page des versions](https://github.com/alessandro823/pullwatch/releases/latest).
2. Ouvrez l’image disque et faites glisser **Pullwatch** sur **Applications**.
3. Ouvrez Pullwatch depuis Applications, Spotlight ou Launchpad.

Chaque version est signée avec un Developer ID et notarisée par Apple, donc macOS l’ouvre sans avertissement.

## La fenêtre de bienvenue

Au premier lancement, Pullwatch ouvre une fenêtre de bienvenue qui vous guide dans la configuration :

1. Où se trouve Pullwatch. Il fonctionne dans la barre des menus ; la fenêtre de bienvenue vous montre l’icône.
2. **Votre premier compte.** Choisissez GitHub, GitHub Enterprise, Azure DevOps ou GitLab. Voir [Ajouter vos comptes](/fr/getting-started/accounts/) pour chacun.
3. **Notifications.** macOS demande une fois si Pullwatch peut envoyer des notifications. Autorisez-le pour être prévenu des nouvelles pull requests et des nouveaux tags dès leur apparition.
4. **Ouvrir à la connexion**, pour que Pullwatch soit là après un redémarrage.

Ensuite, Pullwatch interroge vos comptes en arrière-plan. La première fois, il récupère aussi vos pull requests existantes, pour que l’historique ne soit pas vide. Elles ne déclenchent pas de notification et arrivent marquées comme lues.

## Où le trouver

- **L’icône de la barre des menus** ouvre le [panneau du menu](/fr/using/menu/) avec les pull requests et les tags les plus récents.
- **Ouvrir…** dans le panneau du menu ouvre la fenêtre principale avec PR, Tags et versions publiées, Statistiques, Dépôts et Dépendances. Elle retient la dernière section ouverte.
- **Réglages** est le bouton en forme d’engrenage du panneau du menu, ou ⌘, quand Pullwatch est au premier plan.

Tant qu’une de ses fenêtres est ouverte, Pullwatch apparaît dans le Dock. Fermez la dernière fenêtre et il ne fonctionne plus que depuis la barre des menus. Rouvrir Pullwatch pendant qu’il tourne affiche la fenêtre principale (ou la fenêtre de bienvenue tant qu’aucun compte n’est configuré).

## Mises à jour

Pullwatch recherche une nouvelle version une fois par jour (Réglages, Général, où **Vérifier maintenant** lance la recherche tout de suite). Quand il y en a une, vous recevez une notification et une bannière apparaît dans le panneau du menu. **Installer** affiche les notes de version ; ensuite [Sparkle](https://sparkle-project.org) télécharge la mise à jour, vérifie sa signature EdDSA et sa signature Developer ID, l’installe et redémarre Pullwatch.

Dans Réglages, Général, **Installer les mises à jour automatiquement** télécharge une mise à jour en arrière-plan et l’installe quand vous quittez Pullwatch, et **Inclure les versions de test** propose aussi les préversions.

Une build sans la clé publique de Sparkle, comme une build compilée à partir des sources, affiche à la place un bouton qui télécharge l’image disque.

## Langue

Pullwatch parle anglais, néerlandais, allemand et français. Il suit la langue de macOS, ou vous en choisissez une dans Réglages, Général, **Langue**.

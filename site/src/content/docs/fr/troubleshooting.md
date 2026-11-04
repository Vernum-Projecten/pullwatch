---
title: Dépannage
description: "Que faire quand les notifications, les comptes, les vérifications ou les mises à jour ne fonctionnent pas comme prévu."
---

## Je ne reçois aucune notification

- Quand le panneau du menu indique **Les notifications sont désactivées dans Réglages Système**, ouvrez Réglages Système, Notifications, Pullwatch et autorisez-les.
- Vérifiez Réglages, Notifications : chaque type a son propre interrupteur, et les **Heures calmes** rendent les notifications silencieuses et les envoient uniquement dans le Centre de notifications.
- Vérifiez la cloche à côté du dépôt dans Réglages, Comptes. **Mettre le dépôt en sourdine** sur une notification désactive cette cloche.
- Les modes Concentration et Ne pas déranger retiennent les notifications de toutes les apps, Pullwatch compris.
- La première interrogation des tags d’un dépôt est silencieuse, tout comme les pull requests récupérées pour l’historique.

## Un compte affiche une erreur

Le panneau du menu affiche chaque compte avec l’état de sa dernière interrogation. Ouvrez Réglages, Comptes, sélectionnez le compte et utilisez **Tester la connexion**.

- **Jeton invalide ou expiré** : créez un nouveau jeton avec les [autorisations](/fr/getting-started/permissions/) dont Pullwatch a besoin et enregistrez-le.
- **Connecté avec `gh`, `az` ou `glab`** : reconnectez-vous dans cet outil (`gh auth login`, `az login`, `glab auth login`). Les appels à ces outils expirent après 20 secondes.
- **Un serveur autogéré** : il doit être joignable en https ; Pullwatch refuse le http simple.

## Un dépôt manque

- Avec **Se connecter avec GitHub**, Pullwatch ne voit que les dépôts où la GitHub App Pullwatch est installée. Installez-la sur un autre compte ou une autre organisation depuis l’éditeur de compte.
- Pour GitLab, vérifiez les groupes ou les utilisateurs indiqués dans le compte. Un groupe inclut ses sous-groupes.
- Pour un dépôt isolé hors de vos comptes, ajoutez-le sous **Autres dépôts**.

## Une partie de la page du dépôt indique Autorisation requise

Le jeton ou la GitHub App n’a peut-être pas le droit de lire cette partie, comme les checks, l’analyse du code ou l’analyse des secrets. Le lien à côté mène à l’autorisation. Tout le reste continue de fonctionner. Voir [Autorisations des jetons](/fr/getting-started/permissions/).

## Quelque chose indique Non vérifié

Une source de données est désactivée dans Réglages, Sources, donc Pullwatch n’a pas vérifié cette partie. Activez-la et cliquez sur **Vérifier maintenant**.

## Un runtime ou un paquet indique Inconnu ou Impossible à vérifier

Pullwatch n’a pas pu lire de version dans les fichiers, ou le paquet est privé ou est un paquet Swift, qu’aucun registre public ne connaît. Les projets Maven et Gradle ne sont pas lus.

## Le trousseau demande l’accès après chaque mise à jour

Cela n’arrive qu’avec une build que vous avez compilée vous-même (depuis Xcode ou signée ad hoc). Choisissez **Toujours autoriser**. Les versions publiées sur GitHub sont signées avec un Developer ID et ne demandent rien.

## Deux icônes Pullwatch dans la barre des menus

Vous lancez une build depuis Xcode à côté de l’app installée. Quittez-en une avec **Quitter Pullwatch** dans son panneau du menu.

## Journaux

Pullwatch écrit dans le journal système. Choisissez le niveau dans Réglages, Général, **Niveau de journalisation**, puis suivez le journal dans Terminal :

```sh
log stream --predicate 'subsystem == "nl.torrisi.pullwatch"'
```

Ou ouvrez Console et recherchez `nl.torrisi.pullwatch`. Si vous avez trouvé un bug, ouvrez une [issue sur GitHub](https://github.com/alessandro823/pullwatch/issues) avec ce que vous avez fait et ce que disait le journal, sans jetons.

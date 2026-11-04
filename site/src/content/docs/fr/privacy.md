---
title: Confidentialité et sources
description: "Où Pullwatch conserve vos données, chaque connexion qu’il établit, et comment désactiver des sources de données."
---

Pullwatch fonctionne sur votre Mac et nulle part ailleurs. Il n’a ni compte, ni serveur à lui, ni outil d’analyse d’audience. Il communique avec les serveurs de vos comptes et avec quelques services publics, et Réglages, **Sources** les liste tous.

## Ce qui reste sur votre Mac

- **Les jetons** sont dans le trousseau de macOS, sous `nl.torrisi.pullwatch`. Quand vous vous connectez avec `gh`, `az` ou `glab`, le jeton reste dans cet outil.
- **Les réglages, l’historique et les résultats des vérifications** sont des fichiers JSON dans `~/Library/Application Support/Pullwatch/` : `config.json`, `seen.json`, `history.json`, `versions.json` et `version-history.json`. Chaque vérification complète ajoute un instantané compact à `version-history.json` (versions, états, nombres de vulnérabilités et mises à jour de paquets par dépôt, 730 instantanés au maximum), conservé pour les statistiques dans le temps.

Supprimer un compte supprime aussi son historique.

## Réglages, Sources

L’onglet Sources liste chaque service externe en termes simples. Chaque ligne indique ce que fournit la source, l’adresse que Pullwatch appelle, et un lien vers son site.

**Vulnérabilités**

- **OSV.dev** (`api.osv.dev`) : les vulnérabilités connues de vos paquets. Les noms et les versions des paquets sont envoyés, aussi pour les dépôts privés. C’est la seule source de vulnérabilités de paquets pour les dépôts GitHub et GitLab.
- **GitHub Advisory Database** (`api.github.com/advisories`) : la gravité, le CVSS, le CWE et les liens de chaque avis, récupérés une fois par avis.
- **Sécurité GitHub** : les avis propres du dépôt, l’analyse du code et l’analyse des secrets, depuis votre compte GitHub.
- **Azure DevOps Advanced Security** : ses alertes, depuis votre compte Azure DevOps.

**Versions**

- Les registres de paquets : proxy.golang.org, registry.npmjs.org, repo.packagist.org, api.nuget.org, pypi.org, crates.io et rubygems.org. Les noms des paquets sont envoyés, aussi pour les dépôts privés.
- **endoflife.date** : les cycles de publication et les dates de fin de vie des runtimes et des frameworks.
- **swift.org** : les versions de Swift.

**Pull requests**

- **Checks CI** des pull requests. Désactivé : aucun check n’est récupéré, affiché ni notifié.

Chacune de ces sources a un interrupteur. Une source désactivée n’est appelée nulle part : ni dans la vérification quotidienne, ni quand vous vérifiez à nouveau un dépôt, ni quand les avis sont complétés. Partout où cela laisse quelque chose sans vérification, Pullwatch le dit (« Non vérifié : la source OSV.dev est désactivée », « Version non vérifiée : la source npm est désactivée ») et ne le présente jamais comme à jour ou sans vulnérabilité. Ce qu’une vérification antérieure a obtenu de cette source est masqué aussitôt. Basculer un interrupteur ne lance pas de vérification ; **Vérifier maintenant** en lance une.

**Autres connexions** liste le reste, qui n’a pas d’interrupteur propre :

- le serveur de chaque compte, pour les pull requests, les tags, les dépôts, les manifestes et les fichiers de verrouillage ;
- la connexion à GitHub, pour la GitHub App ;
- les photos de profil de vos comptes et des auteurs des pull requests et des tags ;
- la recherche de mises à jour de Pullwatch, que vous désactivez dans Réglages, Général.

**Copier l’aperçu** copie toute la liste, avec la version, la date et l’état de chaque source, dans le presse-papiers en texte brut, à coller dans un e-mail ou une messagerie, par exemple pour votre équipe de sécurité.

Tout est activé par défaut. Votre choix est enregistré dans `config.json`, sous `disabledSources`.

## Dépôts publics sans jeton

Un dépôt public sur github.com ou gitlab.com que votre jeton ne peut pas lire est lu sans connexion. Pullwatch n’envoie jamais le jeton d’un compte à un autre serveur : un jeton GitHub Enterprise reste sur son propre serveur.

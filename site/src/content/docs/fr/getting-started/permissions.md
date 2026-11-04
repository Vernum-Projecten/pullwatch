---
title: Autorisations des jetons
description: "Les portées et les autorisations dont Pullwatch a besoin sur GitHub, GitHub Enterprise, Azure DevOps, GitLab, Bitbucket, Codeberg, Forgejo et Gitea."
---

Pullwatch ne fait que lire. Donnez à un jeton les autorisations en lecture ci-dessous, et rien de plus. Quand il manque une autorisation pour une partie facultative, cette partie indique **Autorisation requise** avec un lien, et le reste continue de fonctionner.

## GitHub

**Fine-grained token**, sur les dépôts que vous voulez suivre :

| Autorisation | Nécessaire pour |
|---|---|
| Pull requests: Read | les pull requests |
| Metadata: Read | les dépôts (toujours obligatoire) |
| Contents: Read | la vérification des dépendances (manifestes et fichiers de verrouillage) |
| Repository security advisories: Read | les avis propres du dépôt |
| Code scanning alerts: Read | facultatif, les alertes d’analyse du code |
| Secret scanning alerts: Read | facultatif, le nombre d’alertes d’analyse des secrets ouvertes |
| Checks: Read et Commit statuses: Read | facultatif, les checks de chaque pull request |

**Classic token** : `repo`, plus `security_events` pour les alertes d’analyse du code et d’analyse des secrets, et en option `read:packages` pour les paquets que vos dépôts publient dans GitHub Packages. Avec la GitHub CLI, ajoutez ce scope avec `gh auth refresh -s read:packages`.

**Se connecter avec GitHub** utilise la GitHub App Pullwatch, qui demande les mêmes autorisations en lecture, plus l’autorisation facultative Packages: Read pour les paquets que vos dépôts publient ; sans elle, ces paquets indiquent qu’une autorisation manque. Le propriétaire de chaque installation les accepte ; quand l’app obtient une nouvelle autorisation, GitHub demande au propriétaire de l’accepter une nouvelle fois.

## GitHub Enterprise

Créez le jeton sur votre propre serveur. Classic : `repo` et `read:org`, plus `security_events` pour les alertes. **Créer un jeton** dans l’éditeur de compte ouvre la page des jetons du serveur avec ces portées déjà remplies. Les fine-grained tokens demandent les mêmes autorisations que sur github.com.

Avec la GitHub CLI, Pullwatch exécute `gh auth token --hostname <server>`. Connectez-vous d’abord avec `gh auth login --hostname <server>`.

## Azure DevOps

| Portée | Nécessaire pour |
|---|---|
| Code (Read) | les pull requests, les tags et la vérification des dépendances |
| Project and Team (Read) | la liste des projets |
| Advanced Security (Read) | facultatif, les alertes Advanced Security |
| Packaging (Read) | facultatif, les paquets de vos flux Azure Artifacts |

Avec Azure CLI, connectez-vous avec `az login` ; Pullwatch demande un jeton à `az`.

## GitLab

Un jeton d’accès personnel avec la portée **read_api** couvre les merge requests, les projets, les tags, les versions publiées, les commits et les fichiers, ainsi que les paquets et les images de conteneur que vos projets publient dans les registres de GitLab. `api` fonctionne aussi, mais donne plus que ce dont Pullwatch a besoin. Avec la GitLab CLI, Pullwatch lit `glab config get token --host <server>`.

## Bitbucket

Un **jeton d’API avec scopes** d’Atlassian pour l’app Bitbucket, avec l’adresse e-mail de votre compte Atlassian :

| Portée | Nécessaire pour |
|---|---|
| `read:user:bitbucket` | votre propre compte, pour masquer vos propres pull requests |
| `read:repository:bitbucket` | les dépôts, les tags, les statuts de build (les checks) et la vérification des dépendances |
| `read:pullrequest:bitbucket` | les pull requests et leurs commits (les co-auteurs) |

Pullwatch ne demande rien de plus. `read:workspace:bitbucket` n’est pas nécessaire : Pullwatch vérifie un workspace par ses dépôts. Les mots de passe d’application de Bitbucket ne fonctionnent plus depuis juillet 2026.

## Codeberg, Forgejo et Gitea

Créez un jeton sous Paramètres, Applications sur le serveur, avec ces portées, toutes en Lecture :

| Portée | Utilisée pour |
|---|---|
| `read:user` | qui vous êtes, et les dépôts des utilisateurs que vous suivez |
| `read:organization` | les organisations que vous suivez et leurs dépôts |
| `read:repository` | pull requests, tags, versions publiées, statuts de commit (checks), commits et fichiers |
| `read:issue` | la liste des pull requests, qui vient de la recherche d’issues (`/repos/issues/search`) |

S’il en manque une, **Tester la connexion** nomme la portée manquante. Un jeton limité aux dépôts publics ne fonctionne que pour les dépôts publics. Il n’y a pas de connexion en ligne de commande : `tea` n’a aucune commande qui fournit son jeton.

## Connexion avec un outil en ligne de commande

Avec `gh`, `az` ou `glab`, Pullwatch obtient le jeton de l’outil en ligne de commande : vous vous connectez donc dans cet outil et non dans Pullwatch. Les appels à ces outils expirent après 20 secondes.

---
title: Agents (MCP)
description: "Bientôt disponible. Les agents de code pourront interroger Pullwatch sur vos pull requests, vos dépôts et vos vulnérabilités via MCP."
---

:::note[Bientôt disponible]
Cette partie de Pullwatch est encore en développement. Cette page l’expliquera en détail dès sa sortie.
:::

Pullwatch reçoit un serveur [Model Context Protocol](https://modelcontextprotocol.io) local, pour qu’un agent de code sur votre Mac puisse lui demander ce qu’il sait : vos pull requests suivies et leurs checks, les tags, l’état de chaque dépôt, ses paquets obsolètes et ses vulnérabilités connues. L’agent ne fait que lire, il ne voit que les dépôts que vous suivez et il ne reçoit jamais de jeton.

Vous pouvez déjà confier une tâche à un agent : **Copier pour un agent IA** sur une page de dépôt copie une section de cette page dans le presse-papiers sous forme de consigne en Markdown (voir [Dépôts](/fr/using/repositories/#copier-pour-un-agent-ia)).

Suivez l’avancement dans l’[issue #139](https://github.com/Vernum-Projecten/pullwatch/issues/139).

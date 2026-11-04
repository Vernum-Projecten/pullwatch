---
title: Erkenningen
description: De opensourcesoftware in Pullwatch, met de versie en de licentie van elk onderdeel.
---

Pullwatch is gratis en open source onder de [Apache License 2.0](https://github.com/alessandro823/pullwatch/blob/main/LICENSE). Het bevat de opensourcesoftware hieronder. De app heeft de volledige licentietekst van elk onderdeel aan boord: open **Over Pullwatch** en kies **Erkenningen**, of kies **Help**, **Erkenningen** terwijl er een venster van Pullwatch open is. De bestanden staan ook in de app zelf, in `Pullwatch.app/Contents/Resources/Acknowledgements/`, naast de eigen `LICENSE` en `NOTICE` van Pullwatch.

| Onderdeel | Versie | Licentie | Gebruikt voor |
|---|---|---|---|
| [Sparkle](https://sparkle-project.org) | 2.10.1 | MIT, met BSD (bsdiff, bspatch, SUSignatureVerifier), MIT (sais-lite) en zlib (Ed25519) voor de code die het meebrengt | Updates installeren |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | 0.12.1 | Apache 2.0 en MIT (het project stapt over van MIT naar Apache 2.0) | De verbinding voor coding agents, in de app en in `pullwatch-mcp` |
| [SwiftLog](https://github.com/apple/swift-log) | 1.16.2 | Apache 2.0 | Logging in de MCP Swift SDK |
| [Swift System](https://github.com/apple/swift-system) | 1.8.1 | Apache 2.0 with the Runtime Library Exception | Systeemaanroepen in de MCP Swift SDK |
| [EventSource](https://github.com/mattt/eventsource) | 1.6.0 | MIT | Server-sent events in de MCP Swift SDK |
| [GitHub Octicons](https://github.com/primer/octicons) | 19.41.0 | MIT | De symbolen voor pull requests en checks, het icoon in de menubalk en het teken in het app-icoon |

De MCP Swift SDK haalt voor zijn eigen testtools ook SwiftNIO, Swift Atomics en Swift Collections binnen. Pullwatch linkt ze niet, dus ze zitten niet in de app.

GitHub, GitLab en Azure DevOps zijn merken van hun eigenaars. Pullwatch gebruikt hun namen alleen om te zeggen dat het ermee werkt, en is niet aan een van hen verbonden of door hen goedgekeurd. Het [NOTICE-bestand](https://github.com/alessandro823/pullwatch/blob/main/NOTICE) heeft de details.

---
title: Danksagungen
description: Die Open-Source-Software in Pullwatch, mit Version und Lizenz.
---

Pullwatch ist kostenlos und Open Source unter der [Apache License 2.0](https://github.com/alessandro823/pullwatch/blob/main/LICENSE). Es enthält die Open-Source-Software unten. Die App bringt den vollständigen Lizenztext jeder Komponente mit: Öffne **Über Pullwatch** und wähle **Danksagungen**, oder wähle **Hilfe**, **Danksagungen**, während ein Fenster von Pullwatch offen ist. Die Dateien liegen auch in der App selbst, in `Pullwatch.app/Contents/Resources/Acknowledgements/`, neben der eigenen `LICENSE` und `NOTICE` von Pullwatch.

| Komponente | Version | Lizenz | Wofür |
|---|---|---|---|
| [Sparkle](https://sparkle-project.org) | 2.10.1 | MIT, mit BSD (bsdiff, bspatch, SUSignatureVerifier), MIT (sais-lite) und zlib (Ed25519) für den Code, den es mitbringt | Updates installieren |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | 0.12.1 | Apache 2.0 und MIT (das Projekt wechselt von MIT zu Apache 2.0) | Die Verbindung für Coding-Agenten, in der App und in `pullwatch-mcp` |
| [SwiftLog](https://github.com/apple/swift-log) | 1.16.2 | Apache 2.0 | Protokollierung im MCP Swift SDK |
| [Swift System](https://github.com/apple/swift-system) | 1.8.1 | Apache 2.0 with the Runtime Library Exception | Systemaufrufe im MCP Swift SDK |
| [EventSource](https://github.com/mattt/eventsource) | 1.6.0 | MIT | Server-Sent Events im MCP Swift SDK |
| [GitHub Octicons](https://github.com/primer/octicons) | 19.41.0 | MIT | Die Symbole für Pull Requests und Checks, das Symbol in der Menüleiste und das Zeichen im App-Symbol |

Das MCP Swift SDK bringt für seine eigenen Testwerkzeuge auch SwiftNIO, Swift Atomics und Swift Collections mit. Pullwatch linkt sie nicht, sie sind also nicht Teil der App.

GitHub, GitLab und Azure DevOps sind Marken ihrer Inhaber. Pullwatch nennt ihre Namen nur, um zu sagen, dass es mit ihnen funktioniert, und ist mit keinem von ihnen verbunden oder von ihnen empfohlen. Die Einzelheiten stehen in der [NOTICE-Datei](https://github.com/alessandro823/pullwatch/blob/main/NOTICE).

---
title: Acknowledgements
description: The open-source software inside Pullwatch, with its version and license.
---

Pullwatch is free and open source under the [Apache License 2.0](https://github.com/alessandro823/pullwatch/blob/main/LICENSE). It includes the open-source software below. The app carries the full license text of each one: open **About Pullwatch** and choose **Acknowledgements**, or choose **Help**, **Acknowledgements** while a Pullwatch window is open. The files are also in the app itself, in `Pullwatch.app/Contents/Resources/Acknowledgements/`, next to Pullwatch's own `LICENSE` and `NOTICE`.

| Component | Version | License | Used for |
|---|---|---|---|
| [Sparkle](https://sparkle-project.org) | 2.10.1 | MIT, with BSD (bsdiff, bspatch, SUSignatureVerifier), MIT (sais-lite) and zlib (Ed25519) for the code it embeds | Installing updates |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | 0.12.1 | Apache 2.0 and MIT (the project is moving from MIT to Apache 2.0) | The connection for coding agents, in the app and in `pullwatch-mcp` |
| [SwiftLog](https://github.com/apple/swift-log) | 1.16.2 | Apache 2.0 | Logging inside the MCP Swift SDK |
| [Swift System](https://github.com/apple/swift-system) | 1.8.1 | Apache 2.0 with the Runtime Library Exception | System calls inside the MCP Swift SDK |
| [EventSource](https://github.com/mattt/eventsource) | 1.6.0 | MIT | Server-sent events inside the MCP Swift SDK |
| [GitHub Octicons](https://github.com/primer/octicons) | 19.41.0 | MIT | The pull request and check symbols, the menu bar icon and the glyph of the app icon |

The MCP Swift SDK also pulls in SwiftNIO, Swift Atomics and Swift Collections for its own test tools. Pullwatch does not link them, so they are not part of the app.

GitHub, GitLab and Azure DevOps are trademarks of their owners. Pullwatch uses their names only to say it works with them, and is not affiliated with or endorsed by any of them. The [NOTICE file](https://github.com/alessandro823/pullwatch/blob/main/NOTICE) has the details.

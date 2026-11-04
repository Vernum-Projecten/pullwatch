public import Foundation
public import Logging
public import MCP

/// Een `Transport` van de SDK over één verbonden Unix-socket: JSON-RPC-berichten als regels,
/// afgesloten met `\n`, zoals de stdio-transport van MCP (de helper geeft stdin en stdout
/// ongewijzigd door). Een regel langer dan `MCPLimits.maxMessageBytes` wordt niet gebufferd maar
/// meteen met `-32600` beantwoord; `MCPBoundedTransport` ziet alleen hele berichten.
public actor MCPSocketTransport: Transport {
    public nonisolated let logger: Logger
    private let descriptor: NonBlockingDescriptor
    private let limits: MCPLimits
    private let messages: AsyncThrowingStream<Data, any Error>
    private let deliver: AsyncThrowingStream<Data, any Error>.Continuation
    private var reading: Task<Void, Never>?
    /// De laatste schrijfopdracht: elke volgende wacht erop, zodat twee antwoorden nooit door
    /// elkaar op de socket komen.
    private var lastWrite: Task<Void, any Error>?

    package init(descriptor: NonBlockingDescriptor, limits: MCPLimits = .standard) {
        self.descriptor = descriptor
        self.limits = limits
        self.logger = Logger(label: "nl.torrisi.pullwatch.mcp.socket", factory: { _ in SwiftLogNoOpLogHandler() })
        (messages, deliver) = AsyncThrowingStream.makeStream(of: Data.self)
    }

    public func connect() async throws {
        guard reading == nil else { return }
        let chunks = descriptor.chunks()
        reading = Task { [deliver, limits] in
            var framer = LineFramer(maxLineBytes: limits.maxMessageBytes)
            for await chunk in chunks {
                for line in framer.append(chunk) {
                    await self.handle(line)
                }
            }
            for line in framer.finish() {
                await self.handle(line)
            }
            deliver.finish()
        }
    }

    private func handle(_ line: LineFramer.Line) async {
        switch line {
        case .message(let message):
            deliver.yield(message)
        case .oversized:
            // Het bericht is niet gelezen, dus zonder id; de sessie gaat door.
            if let response = try? MCPBoundedTransport.invalidRequest("Message is larger than \(limits.maxMessageBytes) bytes") {
                try? await send(response)
            }
        }
    }

    public func disconnect() async {
        reading?.cancel()
        reading = nil
        descriptor.close()
        deliver.finish()
    }

    public func send(_ data: Data) async throws {
        var line = data
        line.append(UInt8(ascii: "\n"))
        let previous = lastWrite
        let write = Task { [descriptor] in
            _ = await previous?.result
            try await descriptor.write(line)
        }
        lastWrite = write
        try await write.value
    }

    public func receive() -> AsyncThrowingStream<Data, any Error> {
        messages
    }
}

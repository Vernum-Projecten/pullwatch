public import Foundation
public import Logging
public import MCP

/// Een `Transport` om een ander heen dat elk binnenkomend bericht eerst langs `MCPLimits` haalt.
/// Een te groot of te diep genest bericht komt nooit bij de server: de agent krijgt meteen een
/// JSON-RPC-fout (`-32600`, zonder id, want het bericht is niet gelezen) en de sessie gaat door.
/// `PullwatchMCPServer.start` zet elk transport hierin, de socket ook.
public actor MCPBoundedTransport: Transport {
    public nonisolated let logger: Logger
    private let inner: any Transport
    private let limits: MCPLimits

    public init(wrapping inner: any Transport, limits: MCPLimits = .standard) {
        self.inner = inner
        self.limits = limits
        self.logger = Logger(label: "nl.torrisi.pullwatch.mcp.bounded", factory: { _ in SwiftLogNoOpLogHandler() })
    }

    public func connect() async throws {
        try await inner.connect()
    }

    public func disconnect() async {
        await inner.disconnect()
    }

    public func send(_ data: Data) async throws {
        try await inner.send(data)
    }

    public func receive() -> AsyncThrowingStream<Data, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        let task = Task { [inner, limits] in
            do {
                for try await message in await inner.receive() {
                    if let violation = limits.violation(in: message) {
                        try await inner.send(Self.invalidRequest(violation))
                    } else {
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Het JSON-RPC-antwoord op een bericht dat niet door mag.
    static func invalidRequest(_ message: String) throws -> Data {
        let response: Value = [
            "jsonrpc": "2.0",
            "id": nil,
            "error": ["code": .int(MCPError.invalidRequest(nil).code), "message": .string(message)],
        ]
        return try JSONEncoder().encode(response)
    }
}

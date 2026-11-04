import Darwin
import Foundation
import MCP
import Testing
@testable import PullwatchMCP

/// Een eigen, korte map per test voor `mcp.sock` (een socketpad mag niet langer dan 104 bytes
/// zijn), weggegooid aan het eind. Nooit de echte datamap.
final class SocketDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "pw-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var socket: URL { url.appending(path: "mcp.sock") }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Berichten die ergens binnenkomen, één voor één te lezen.
final class MessageQueue: Sendable {
    let stream: AsyncStream<Data>
    let continuation: AsyncStream<Data>.Continuation
    private let reader: Reader

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        reader = Reader(stream)
    }

    func push(_ message: Data) {
        continuation.yield(message)
    }

    /// Het volgende bericht, of nil als de stroom eindigde.
    func next() async -> Data? {
        await reader.next()
    }

    /// Het volgende bericht als JSON-object.
    func nextObject() async throws -> [String: Value] {
        let data = try #require(await next())
        return try #require(JSONDecoder().decode(Value.self, from: data).objectValue)
    }

    private actor Reader {
        private var iterator: AsyncStream<Data>.AsyncIterator

        init(_ stream: AsyncStream<Data>) {
            iterator = stream.makeAsyncIterator()
        }

        func next() async -> Data? {
            var current = iterator
            defer { iterator = current }
            return await current.next(isolation: self)
        }
    }
}

/// Een client op een socket: stuurt regels en leest de antwoorden als regels.
struct LineClient {
    let descriptor: NonBlockingDescriptor
    let lines = MessageQueue()
    private let reading: Task<Void, Never>

    init(_ descriptor: NonBlockingDescriptor) {
        self.descriptor = descriptor
        let chunks = descriptor.chunks()
        reading = Task { [lines] in
            var framer = LineFramer(maxLineBytes: 1 << 24)
            for await chunk in chunks {
                for case .message(let message) in framer.append(chunk) { lines.push(message) }
            }
            lines.continuation.finish()
        }
    }

    static func connect(to url: URL) throws -> LineClient {
        LineClient(try UnixSocket.connect(to: url))
    }

    func send(_ json: String) async throws {
        try await descriptor.write(Data((json + "\n").utf8))
    }

    func request(_ json: String) async throws -> [String: Value] {
        try await send(json)
        return try await lines.nextObject()
    }

    func close() {
        descriptor.close()
        reading.cancel()
    }
}

/// Twee verbonden sockets, voor de transport zonder listener.
func socketPair() throws -> (NonBlockingDescriptor, NonBlockingDescriptor) {
    var pair: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { throw MCPSocketError.system("socketpair", errno) }
    try UnixSocket.ignoreBrokenPipe(pair[0])
    try UnixSocket.ignoreBrokenPipe(pair[1])
    return (try NonBlockingDescriptor(adopting: pair[0]), try NonBlockingDescriptor(adopting: pair[1]))
}

/// Laat elke verbinding toe, zoals de echte controle de helper toelaat.
struct AcceptingInspector: MCPPeerInspecting {
    func evidence(forSocket socket: Int32, requirement: String?) -> MCPPeerEvidence {
        MCPPeerEvidence(
            userID: getuid(),
            signature: .valid(.init(identifier: MCPPeerPolicy.helperIdentifier, teamIdentifier: nil, isAdHoc: true, meetsRequirement: false))
        )
    }
}

/// Weigert elke verbinding: een ongetekend proces.
struct UnsignedInspector: MCPPeerInspecting {
    func evidence(forSocket socket: Int32, requirement: String?) -> MCPPeerEvidence {
        MCPPeerEvidence(userID: getuid(), signature: .invalid)
    }
}

extension MCPPeerCheck {
    static let acceptAll = MCPPeerCheck(policy: MCPPeerPolicy(userID: getuid(), teamIdentifier: nil), inspector: AcceptingInspector())
    static let refuseAll = MCPPeerCheck(policy: MCPPeerPolicy(userID: getuid(), teamIdentifier: nil), inspector: UnsignedInspector())
}

/// De JSON van een `initialize` van een agent.
func initializeRequest(id: Int = 1, client: String = "claude-code") -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"\#(client)","version":"2.1.0"}}}"#
}

let initializedNotification = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#

func toolsListRequest(id: Int) -> String {
    #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/list"}"#
}

import Foundation
import MCP
import PullwatchMCP
import Testing

/// Een gestarte Pullwatch-server en de ruwe kant van een client: stuurt JSON zoals een agent het
/// over de draad stuurt en leest de antwoorden als `Value`. Voor wat de `Client` van de SDK niet
/// laat sturen (een oudere protocolversie, kapotte parameters, een te groot bericht).
struct RawSession {
    let server: Server
    private let transport: InMemoryTransport
    private let inbox: Inbox

    init(tools: MCPToolRegistry, limits: MCPLimits = .standard) async throws {
        let (client, server) = await InMemoryTransport.createConnectedPair()
        self.server = try await PullwatchMCPServer.start(tools: tools, version: "1.2.3", limits: limits, on: server)
        try await client.connect()
        self.transport = client
        self.inbox = Inbox(await client.receive())
    }

    func send(_ json: String) async throws {
        try await transport.send(Data(json.utf8))
    }

    /// Het volgende bericht van de server, als JSON-object.
    func next() async throws -> [String: Value] {
        let data = try #require(await inbox.next())
        return try #require(JSONDecoder().decode(Value.self, from: data).objectValue)
    }

    /// Stuurt `json` en geeft het antwoord.
    func request(_ json: String) async throws -> [String: Value] {
        try await send(json)
        return try await next()
    }

    /// `initialize` met `version`, gevolgd door `notifications/initialized`, zoals een agent doet.
    @discardableResult
    func initialize(version: String = "2025-11-25") async throws -> [String: Value] {
        let response = try await request(
            #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"\#(version)","capabilities":{},"clientInfo":{"name":"raw","version":"1"}}}"#
        )
        try await send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        return response
    }

    func stop() async {
        await server.stop()
    }
}

/// Leest de berichten van de server één voor één.
private actor Inbox {
    private var iterator: AsyncThrowingStream<Data, any Error>.AsyncIterator

    init(_ stream: AsyncThrowingStream<Data, any Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Data? {
        // Een actor mag een mutating async functie niet op zijn eigen property aanroepen; dus via
        // een kopie. Er leest maar één test tegelijk, dus de kopie loopt nooit uit de pas.
        var current = iterator
        defer { iterator = current }
        return try await current.next(isolation: self)
    }
}

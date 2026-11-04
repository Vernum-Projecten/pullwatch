import Foundation
import MCP
import PullwatchMCP
import Testing

/// De server zoals een agent hem ziet, over het in-memory transport van de SDK: de handshake,
/// `tools/list`, `tools/call` en elke manier waarop een verzoek fout kan zijn.
@Suite(.timeLimit(.minutes(1)))
struct PullwatchMCPServerTests {
    let tools: MCPToolRegistry

    init() throws {
        tools = try TestTools.registry()
    }

    /// Een `Client` van de SDK, verbonden en met de handshake gedaan.
    func connect() async throws -> (client: Client, server: Server, handshake: Initialize.Result) {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = try await PullwatchMCPServer.start(tools: tools, version: "1.2.3", on: serverTransport)
        let client = Client(name: "test-agent", version: "1.0")
        let handshake = try await client.connect(transport: clientTransport)
        return (client, server, handshake)
    }

    func call(_ client: Client, _ name: String, _ arguments: [String: Value]? = nil) async throws -> CallTool.Result {
        try await client.send(CallTool.request(.init(name: name, arguments: arguments))).value
    }

    /// De foutcode van een `tools/call` die als protocolfout terugkomt.
    func errorCode(_ client: Client, _ name: String, _ arguments: [String: Value]? = nil) async throws -> Int? {
        let error = await #expect(throws: MCPError.self) {
            _ = try await call(client, name, arguments)
        }
        return error?.code
    }

    // MARK: - Handshake

    @Test func `The SDK client shakes hands and sees Pullwatch with tools`() async throws {
        let (client, server, handshake) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        #expect(handshake.serverInfo.name == "Pullwatch")
        #expect(handshake.serverInfo.version == "1.2.3")
        #expect(handshake.protocolVersion == Version.latest)
        #expect(handshake.capabilities.tools != nil)
        #expect(handshake.capabilities.resources == nil)
        #expect(handshake.capabilities.prompts == nil)
    }

    @Test(arguments: [
        ("2025-11-25", "2025-11-25"),
        ("2025-06-18", "2025-06-18"),
        ("2025-03-26", "2025-03-26"),
        // Een versie die de SDK niet kent, krijgt de nieuwste die hij wel kent.
        ("2026-07-28", "2025-11-25"),
    ])
    func `The handshake agrees on a protocol version`(requested: String, agreed: String) async throws {
        let session = try await RawSession(tools: tools)
        defer { await session.stop() }

        let response = try await session.initialize(version: requested)

        let result = try #require(response["result"]?.objectValue)
        #expect(result["protocolVersion"] == .string(agreed))
        #expect(result["serverInfo"]?.objectValue?["name"] == "Pullwatch")
    }

    @Test func `The server speaks the versions of the pinned SDK`() {
        #expect(PullwatchMCPServer.protocolVersions == ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"])
    }

    @Test func `A request before the handshake is refused`() async throws {
        let session = try await RawSession(tools: tools)
        defer { await session.stop() }

        let response = try await session.request(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)

        #expect(response["error"]?.objectValue?["code"] == .int(-32600))
    }

    @Test func `The client name reaches the initialize hook`() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        try await confirmation { reported in
            let server = try await PullwatchMCPServer.start(tools: tools, version: "1.2.3", on: serverTransport) { info in
                #expect(info.name == "test-agent")
                reported()
            }
            let client = Client(name: "test-agent", version: "1.0")
            try await client.connect(transport: clientTransport)
            await client.disconnect()
            await server.stop()
        }
    }

    // MARK: - tools/list

    @Test func `tools/list returns every tool with its schemas`() async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        let (listed, nextCursor) = try await client.listTools()

        #expect(listed.map(\.name) == ["describe_repo", "not_followed", "crashing", "wrong_output"])
        #expect(nextCursor == nil)
        let describe = try #require(listed.first)
        #expect(describe.description == "Returns the repository, state and limit it was asked for.")
        #expect(describe.inputSchema == TestTools.describeRepo.inputSchema.jsonSchema)
        #expect(describe.outputSchema == TestTools.describeRepo.outputSchema.jsonSchema)
        #expect(describe.annotations.readOnlyHint == true)
        #expect(describe.annotations.openWorldHint == false)
        let input = try #require(describe.inputSchema.objectValue)
        #expect(input["type"] == "object")
        #expect(input["required"] == ["repo"])
        #expect(input["additionalProperties"] == false)
    }

    // MARK: - tools/call

    @Test func `A tool call returns structured content and a summary`() async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        let result = try await call(client, "describe_repo", ["repo": "acme/web", "state": "closed", "limit": 5])

        #expect(result.isError == false)
        #expect(result.structuredContent == ["repo": "acme/web", "state": "closed", "limit": 5])
        let texts = result.content.compactMap { content -> String? in
            if case let .text(text, _, _) = content { text } else { nil }
        }
        #expect(texts == ["Repository acme/web.", #"{"limit":5,"repo":"acme/web","state":"closed"}"#])
    }

    @Test func `Missing optional arguments are fine`() async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        let result = try await call(client, "describe_repo", ["repo": "acme/web"])

        #expect(result.structuredContent == ["repo": "acme/web", "state": "open", "limit": 20])
    }

    /// MCP 2025-11-25: ongeldige argumenten zijn een fout van de tool (`isError`), geen
    /// protocolfout, zodat het model de melding leest en de aanroep verbetert.
    @Test(arguments: [
        ([String: Value](), "`repo` is required"),
        (["repo": 42], "`repo` must be a string"),
        (["repo": "acme/web", "state": "merged"], "`state` must be one of open, closed"),
        (["repo": "acme/web", "limit": 0], "`limit` must be at least 1"),
        (["repo": "acme/web", "limit": 51], "`limit` must be at most 50"),
        (["repo": "acme/web", "limit": 2.5], "`limit` must be an integer"),
        (["repo": "acme/web", "labels": ["a", "b", "c", "d"]], "`labels` must have at most 3 items"),
        (["repo": "acme/web", "labels": [1]], "`labels[0]` must be a string"),
        (["repo": .string(String(repeating: "a", count: 101))], "`repo` must be at most 100 characters"),
        (["repo": "acme/web", "unknown": true], "`unknown` is not a known field (known: labels, limit, repo, state)"),
    ] as [([String: Value], String)])
    func `Invalid arguments come back as a tool error the model can act on`(arguments: [String: Value], problem: String) async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        let result = try await call(client, "describe_repo", arguments)

        #expect(result.isError == true)
        #expect(result.content == [.text(text: "Invalid arguments for describe_repo: \(problem).", annotations: nil, _meta: nil)])
        #expect(result.structuredContent == nil)
        // De sessie gaat door: een verbeterde aanroep slaagt.
        #expect(try await call(client, "describe_repo", ["repo": "acme/web"]).isError == false)
    }

    @Test func `An unknown tool is refused with invalid params`() async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        #expect(try await errorCode(client, "drop_database") == -32602)
    }

    @Test(arguments: [
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call"}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":3}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"describe_repo","arguments":"repo=acme/web"}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":["describe_repo"]}"#,
    ])
    func `A malformed tools/call is refused with invalid params`(message: String) async throws {
        let session = try await RawSession(tools: tools)
        defer { await session.stop() }
        try await session.initialize()

        let response = try await session.request(message)

        #expect(response["id"] == 7)
        #expect(response["error"]?.objectValue?["code"] == .int(-32602))
    }

    @Test func `A tool error reaches the model as an error result`() async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        let result = try await call(client, "not_followed")

        #expect(result.isError == true)
        #expect(result.content == [.text(text: "Repository acme/secret is not followed in Pullwatch.", annotations: nil, _meta: nil)])
        #expect(result.structuredContent == nil)
    }

    @Test func `A tool that fails inside gives an error result without its details`() async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        let result = try await call(client, "crashing")

        #expect(result.isError == true)
        #expect(result.content == [.text(text: "The tool crashing failed inside Pullwatch.", annotations: nil, _meta: nil)])
        // De server leeft nog.
        #expect(try await call(client, "describe_repo", ["repo": "acme/web"]).isError == false)
    }

    @Test func `Output outside its schema is an internal error`() async throws {
        let (client, server, _) = try await connect()
        defer { await client.disconnect(); await server.stop() }

        #expect(try await errorCode(client, "wrong_output") == -32603)
    }

    // MARK: - Andere verzoeken

    @Test func `An unknown method is refused with method not found`() async throws {
        let session = try await RawSession(tools: tools)
        defer { await session.stop() }
        try await session.initialize()

        let response = try await session.request(#"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#)

        #expect(response["id"] == 9)
        #expect(response["error"]?.objectValue?["code"] == .int(-32601))
    }

    @Test func `Ping works after the handshake`() async throws {
        let session = try await RawSession(tools: tools)
        defer { await session.stop() }
        try await session.initialize()

        let response = try await session.request(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)

        #expect(response["id"] == 2)
        #expect(response["result"] == [:])
    }

    // MARK: - Grenzen

    @Test(arguments: [
        // Groter dan het maximum van 4 KiB.
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"describe_repo","arguments":{"repo":"\#(String(repeating: "a", count: 5000))"}}}"#,
        // Dieper genest dan 8 niveaus.
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"describe_repo","arguments":{"repo":"x","labels":[[[[[[["deep"]]]]]]]}}}"#,
    ])
    func `A message over the limits is refused and the session goes on`(message: String) async throws {
        let session = try await RawSession(tools: tools, limits: MCPLimits(maxMessageBytes: 4096, maxDepth: 8))
        defer { await session.stop() }
        try await session.initialize()

        let refused = try await session.request(message)

        #expect(refused["id"] == .null)
        #expect(refused["error"]?.objectValue?["code"] == .int(-32600))
        let ping = try await session.request(#"{"jsonrpc":"2.0","id":4,"method":"ping"}"#)
        #expect(ping["id"] == 4)
        #expect(ping["result"] == [:])
    }

    @Test func `Brackets inside a string do not count as nesting`() async throws {
        let session = try await RawSession(tools: tools, limits: MCPLimits(maxMessageBytes: 4096, maxDepth: 8))
        defer { await session.stop() }
        try await session.initialize()

        let response = try await session.request(
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"describe_repo","arguments":{"repo":"[[[[[[[[[[{{{{\"]]"}}}"#
        )

        #expect(response["id"] == 5)
        #expect(response["result"]?.objectValue?["isError"] == false)
    }
}

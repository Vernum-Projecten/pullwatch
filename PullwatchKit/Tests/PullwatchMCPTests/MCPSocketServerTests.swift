import Foundation
import MCP
import Testing
@testable import PullwatchMCP

/// De server van de app op de socket: een sessie per verbinding, de controle vooraf, en alles
/// dicht bij het stoppen.
@Suite(.timeLimit(.minutes(1))) struct MCPSocketServerTests {
    let directory: SocketDirectory

    init() throws {
        directory = try SocketDirectory()
    }

    /// Start een server en wacht tot hij luistert.
    private func start(_ peerCheck: MCPPeerCheck = .acceptAll) async throws -> (MCPSocketServer, Task<Void, any Error>) {
        let server = MCPSocketServer(url: directory.socket, tools: try TestTools.registry(), version: "9.9.9", peerCheck: peerCheck)
        let task = Task { try await server.run() }
        try await waitUntil { FileManager.default.fileExists(atPath: directory.socket.path(percentEncoded: false)) }
        return (server, task)
    }

    @Test func `An agent shakes hands and lists the tools over the socket`() async throws {
        let (_, task) = try await start()
        defer { task.cancel() }
        let client = try LineClient.connect(to: directory.socket)
        defer { client.close() }

        let hello = try await client.request(initializeRequest())
        #expect(hello["result"]?.objectValue?["serverInfo"]?.objectValue?["name"] == "Pullwatch")
        try await client.send(initializedNotification)
        let list = try await client.request(toolsListRequest(id: 2))
        let names = list["result"]?.objectValue?["tools"]?.arrayValue?.compactMap { $0.objectValue?["name"]?.stringValue }
        #expect(names == (try TestTools.registry().tools.map(\.name)))
    }

    @Test func `Each connection is its own session`() async throws {
        let (_, task) = try await start()
        defer { task.cancel() }
        let first = try LineClient.connect(to: directory.socket)
        let second = try LineClient.connect(to: directory.socket)
        defer {
            first.close()
            second.close()
        }
        _ = try await first.request(initializeRequest())
        // De tweede heeft nog geen handshake gedaan, dus de server weigert hem.
        let refused = try await second.request(toolsListRequest(id: 5))
        #expect(refused["error"]?.objectValue?["code"] == .int(-32600))
        try await first.send(initializedNotification)
        #expect(try await first.request(toolsListRequest(id: 6))["result"] != nil)
    }

    @Test func `The sessions are reported with the client name`() async throws {
        let (server, task) = try await start()
        var events = server.events.makeAsyncIterator()
        let client = try LineClient.connect(to: directory.socket)
        _ = try await client.request(initializeRequest(client: "claude-code"))

        guard case .connected(let session) = try #require(await events.next()) else { throw SessionEventError() }
        #expect(session.clientName == nil)
        #expect(try #require(await events.next()) == .identified(id: session.id, name: "claude-code", version: "2.1.0"))
        client.close()
        #expect(try #require(await events.next()) == .disconnected(id: session.id))
        task.cancel()
        #expect(await events.next() == nil, "de stroom eindigt als de server stopt")
    }

    @Test func `A refused peer is closed before anything is read`() async throws {
        let (server, task) = try await start(.refuseAll)
        defer { task.cancel() }
        let client = try LineClient.connect(to: directory.socket)
        defer { client.close() }
        try? await client.send(initializeRequest())
        #expect(await client.lines.next() == nil, "geen antwoord, alleen het einde")
        task.cancel()
        var events = server.events.makeAsyncIterator()
        #expect(await events.next() == nil, "een geweigerde verbinding is geen sessie")
    }

    @Test func `Stopping closes every session and removes the socket`() async throws {
        let (_, task) = try await start()
        let client = try LineClient.connect(to: directory.socket)
        _ = try await client.request(initializeRequest())

        task.cancel()
        _ = await task.result
        #expect(await client.lines.next() == nil, "de sessie is dicht")
        #expect(!FileManager.default.fileExists(atPath: directory.socket.path(percentEncoded: false)))
        client.close()
    }

    @Test func `A second server on the same socket fails and leaves the first alone`() async throws {
        let (_, task) = try await start()
        defer { task.cancel() }
        let second = MCPSocketServer(url: directory.socket, tools: try TestTools.registry(), version: "1", peerCheck: .acceptAll)
        await #expect(throws: MCPSocketError.inUse(directory.socket.path(percentEncoded: false))) { try await second.run() }
        let client = try LineClient.connect(to: directory.socket)
        defer { client.close() }
        #expect(try await client.request(initializeRequest())["result"] != nil)
    }
}

struct SessionEventError: Error {}

/// Wacht tot `condition` waar is, hoogstens vijf seconden.
func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        try #require(ContinuousClock.now < deadline, "wachtte te lang")
        try await Task.sleep(for: .milliseconds(10))
    }
}

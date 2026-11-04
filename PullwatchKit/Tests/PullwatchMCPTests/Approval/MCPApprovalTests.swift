import Foundation
import MCP
import PullwatchCore
import Synchronization
import Testing
@testable import PullwatchMCP

/// Toestaan per agent, over de echte socket: tot de persoon een client toestaat krijgt elke
/// `tools/call` de wachtmelding, de verbinding blijft open, en toestaan telt meteen. Daarnaast
/// de laatst gebruikte tool en loskoppelen, waarna de helper niet opnieuw verbindt.
@Suite(.timeLimit(.minutes(1))) struct MCPApprovalTests {
    let directory: SocketDirectory
    let approved = ApprovedNames()

    init() throws {
        directory = try SocketDirectory()
    }

    private func start() async throws -> (MCPSocketServer, Task<Void, any Error>) {
        let approval = MCPApproval { [approved] name in approved.contains(name) }
        let server = MCPSocketServer(
            url: directory.socket, tools: try TestTools.registry(), version: "9.9.9", peerCheck: .acceptAll, approval: approval
        )
        let task = Task { try await server.run() }
        try await waitUntil { FileManager.default.fileExists(atPath: directory.socket.path(percentEncoded: false)) }
        return (server, task)
    }

    private func callRequest(id: Int) -> String {
        #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"describe_repo","arguments":{"repo":"acme/web"}}}"#
    }

    private func text(_ reply: [String: Value]) -> String? {
        reply["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
    }

    @Test func `An agent that is not allowed yet hears where to allow it, and stays connected`() async throws {
        let (_, task) = try await start()
        defer { task.cancel() }
        let client = try LineClient.connect(to: directory.socket)
        defer { client.close() }
        _ = try await client.request(initializeRequest(client: "claude-code"))
        try await client.send(initializedNotification)

        let call = try await client.request(callRequest(id: 2))
        #expect(call["result"]?.objectValue?["isError"] == true)
        #expect(text(call) == "Waiting for approval in Pullwatch: allow Claude Code in the notification or under Settings, Agents.")
        #expect(call["result"]?.objectValue?["structuredContent"] == nil, "geen gegevens zolang hij wacht")

        // De lijst van tools bevat geen gegevens; de agent krijgt hem, zodat hij na toestaan
        // meteen verder kan.
        let list = try await client.request(toolsListRequest(id: 3))
        #expect(list["result"]?.objectValue?["tools"]?.arrayValue?.isEmpty == false)

        approved.insert("claude-code")
        let allowed = try await client.request(callRequest(id: 4))
        #expect(allowed["result"]?.objectValue?["isError"] == false)
        #expect(allowed["result"]?.objectValue?["structuredContent"]?.objectValue?["repo"] == "acme/web")
    }

    @Test func `Approval goes by client name, so another agent still waits`() async throws {
        approved.insert("claude-code")
        let (_, task) = try await start()
        defer { task.cancel() }
        let client = try LineClient.connect(to: directory.socket)
        defer { client.close() }
        _ = try await client.request(initializeRequest(client: "codex-mcp-client"))
        try await client.send(initializedNotification)

        let call = try await client.request(callRequest(id: 2))
        #expect(text(call) == MCPApproval.waitingMessage(for: "Codex"))
    }

    @Test func `Allowed tool calls are reported with the tool name`() async throws {
        approved.insert("claude-code")
        let (server, task) = try await start()
        defer { task.cancel() }
        var events = server.events.makeAsyncIterator()
        let client = try LineClient.connect(to: directory.socket)
        defer { client.close() }
        _ = try await client.request(initializeRequest(client: "claude-code"))
        try await client.send(initializedNotification)
        _ = try await client.request(callRequest(id: 2))

        guard case .connected(let session) = try #require(await events.next()) else { throw SessionEventError() }
        #expect(try #require(await events.next()) == .identified(id: session.id, name: "claude-code", version: "2.1.0"))
        #expect(try #require(await events.next()) == .calledTool(id: session.id, name: "describe_repo"))
    }

    @Test func `Disconnect closes one session and tells the helper first`() async throws {
        let (server, task) = try await start()
        defer { task.cancel() }
        var events = server.events.makeAsyncIterator()
        let client = try LineClient.connect(to: directory.socket)
        defer { client.close() }
        _ = try await client.request(initializeRequest())
        guard case .connected(let session) = try #require(await events.next()) else { throw SessionEventError() }

        await server.disconnect(id: session.id)

        #expect(try await client.lines.nextObject()["method"] == .string(PullwatchDisconnectNotification.name))
        #expect(await client.lines.next() == nil, "de sessie is dicht")
        #expect(try #require(await events.next()) == .identified(id: session.id, name: "claude-code", version: "2.1.0"))
        #expect(try #require(await events.next()) == .disconnected(id: session.id))
        await server.disconnect(id: UUID())
    }

    @Test func `After a disconnect the helper does not reconnect and says why`() async throws {
        let app = try FakeApp(at: directory.socket)
        defer { app.close() }
        let bridge = MCPBridge(socketURL: directory.socket, readAccess: { .whileOpen }, launcher: StubLauncher(), timing: MCPBridgeTests.fast)
        let (input, agent) = AsyncStream.makeStream(of: Data.self)
        let replies = MessageQueue()
        let helper = Task { await bridge.run(input: input) { replies.push($0) } }

        let connection = try await app.nextConnection()
        agent.yield(Data((toolsListRequest(id: 1) + "\n").utf8))
        #expect(try await connection.lines.nextObject()["id"] == 1)
        try await connection.send(#"{"jsonrpc":"2.0","method":"notifications/pullwatch/disconnected"}"#)
        connection.close()

        let lost = try await replies.nextObject()
        #expect(lost["id"] == 1)
        #expect(lost["error"]?.objectValue?["message"]?.stringValue == MCPBridge.Message.disconnected)
        agent.yield(Data((toolsListRequest(id: 2) + "\n").utf8))
        let after = try await replies.nextObject()
        #expect(after["error"]?.objectValue?["message"]?.stringValue == MCPBridge.Message.disconnected)
        agent.finish()
        await helper.value
    }

    @Test(arguments: [
        ("claude-code", nil, "Claude Code"),
        ("codex-mcp-client", nil, "Codex"),
        ("cursor-vscode", nil, "Cursor"),
        ("Visual Studio Code", nil, "VS Code"),
        ("my-agent", nil, "my-agent"),
        ("my-agent", "My Agent", "My Agent"),
        ("claude-code", " ", "Claude Code"),
    ] as [(String, String?, String)])
    func `Agents are shown by the name people know`(name: String, title: String?, shown: String) {
        #expect(MCPClientName.displayName(name: name, title: title) == shown)
    }

    @Test func `A session shows its name once it said who it is`() {
        var session = MCPSession(id: UUID(), connectedSince: .now)
        #expect(session.displayName == nil)
        session.clientName = "claude-code"
        #expect(session.displayName == "Claude Code")
    }
}

/// De toegestane namen, die een test halverwege kan aanvullen.
final class ApprovedNames: Sendable {
    private let names = Mutex<Set<String>>([])

    func insert(_ name: String) {
        _ = names.withLock { $0.insert(name) }
    }

    func contains(_ name: String) -> Bool {
        names.withLock { $0.contains(name) }
    }
}

import Foundation
import MCP
import PullwatchCore
import Synchronization
import Testing
@testable import PullwatchMCP

/// De helper `pullwatch-mcp` per stand van `AgentAccess`, met een nep-starter en een socket in
/// een eigen map: weigeren, doorgeven, Pullwatch starten en opnieuw verbinden.
@Suite(.timeLimit(.minutes(1))) struct MCPBridgeTests {
    let directory: SocketDirectory

    init() throws {
        directory = try SocketDirectory()
    }

    static let fast = MCPBridge.Timing(launchWait: .seconds(5), reconnectWait: .seconds(2), pollInterval: .milliseconds(20))

    /// Een gestarte helper: wat de agent stuurt gaat in `agent`, wat de helper teruggeeft komt
    /// uit `replies`.
    struct Running {
        let agent: AsyncStream<Data>.Continuation
        let replies: MessageQueue
        let task: Task<Void, Never>

        func send(_ json: String) {
            agent.yield(Data((json + "\n").utf8))
        }

        func request(_ json: String) async throws -> [String: Value] {
            send(json)
            return try await replies.nextObject()
        }

        /// Sluit stdin en wacht tot de helper stopt.
        func finish() async {
            agent.finish()
            await task.value
        }
    }

    private func run(
        _ access: AgentAccess, launcher: StubLauncher = StubLauncher(), timing: MCPBridge.Timing = fast
    ) -> Running {
        let bridge = MCPBridge(socketURL: directory.socket, readAccess: { access }, launcher: launcher, timing: timing)
        let (input, agent) = AsyncStream.makeStream(of: Data.self)
        let replies = MessageQueue()
        let task = Task {
            await bridge.run(input: input) { replies.push($0) }
            replies.continuation.finish()
        }
        return Running(agent: agent, replies: replies, task: task)
    }

    private func startServer() async throws -> Task<Void, any Error> {
        let server = MCPSocketServer(url: directory.socket, tools: try TestTools.registry(), version: "9.9.9", peerCheck: .acceptAll)
        let task = Task { try await server.run() }
        try await waitUntil { FileManager.default.fileExists(atPath: directory.socket.path(percentEncoded: false)) }
        return task
    }

    private func errorMessage(_ reply: [String: Value]) -> String? {
        reply["error"]?.objectValue?["message"]?.stringValue
    }

    // MARK: - Nooit

    @Test func `Never answers every request with where to turn agents on`() async throws {
        let server = try await startServer()
        defer { server.cancel() }
        let launcher = StubLauncher()
        let helper = run(.never, launcher: launcher)

        let first = try await helper.request(initializeRequest(id: 7))
        #expect(first["id"] == 7)
        #expect(errorMessage(first) == "Agents are turned off in Pullwatch: Settings, Agents")
        helper.send(initializedNotification)
        let second = try await helper.request(#"{"jsonrpc":"2.0","id":"abc","method":"tools/list"}"#)
        #expect(second["id"] == "abc", "een notificatie krijgt geen antwoord; het volgende antwoord is voor het verzoek")
        #expect(errorMessage(second) == MCPBridge.Message.turnedOff)

        await helper.finish()
        #expect(await helper.replies.next() == nil, "stopt als stdin sluit")
        #expect(launcher.launches == 0)
    }

    // MARK: - Zolang Pullwatch open is

    @Test func `While open without Pullwatch every request hears to open it`() async throws {
        let launcher = StubLauncher()
        let helper = run(.whileOpen, launcher: launcher)
        let reply = try await helper.request(initializeRequest())
        #expect(reply["id"] == 1)
        #expect(errorMessage(reply) == "Open Pullwatch to use it from an agent.")
        await helper.finish()
        #expect(launcher.launches == 0, "zolang open start nooit iets")
    }

    @Test func `While open with Pullwatch the messages go both ways`() async throws {
        let server = try await startServer()
        defer { server.cancel() }
        let helper = run(.whileOpen)

        let hello = try await helper.request(initializeRequest())
        #expect(hello["id"] == 1)
        #expect(hello["result"]?.objectValue?["serverInfo"]?.objectValue?["name"] == "Pullwatch")
        helper.send(initializedNotification)
        let list = try await helper.request(toolsListRequest(id: 2))
        #expect(list["id"] == 2)
        #expect(list["result"]?.objectValue?["tools"]?.arrayValue?.isEmpty == false)
        await helper.finish()
    }

    @Test func `A line over the limit gets an error from the helper itself`() async throws {
        let helper = run(.whileOpen)
        helper.send(#"{"padding":"\#(String(repeating: "x", count: MCPLimits.standard.maxMessageBytes))"}"#)
        let reply = try await helper.replies.nextObject()
        #expect(reply["error"]?.objectValue?["code"] == .int(-32600))
        await helper.finish()
    }

    // MARK: - Altijd

    @Test func `Always starts Pullwatch and waits for the socket`() async throws {
        let started = Mutex<Task<Void, any Error>?>(nil)
        let launcher = StubLauncher {
            let server = MCPSocketServer(url: directory.socket, tools: try TestTools.registry(), version: "9.9.9", peerCheck: .acceptAll)
            // Zoals een echte start: de socket komt even later.
            started.withLock { $0 = Task { try await Task.sleep(for: .milliseconds(200)); try await server.run() } }
        }
        let helper = run(.always, launcher: launcher)
        defer { started.withLock { $0?.cancel() } }

        let hello = try await helper.request(initializeRequest())
        #expect(hello["result"] != nil)
        #expect(launcher.launches == 1)
        await helper.finish()
    }

    @Test func `Always with Pullwatch running starts nothing`() async throws {
        let server = try await startServer()
        defer { server.cancel() }
        let launcher = StubLauncher()
        let helper = run(.always, launcher: launcher)
        #expect(try await helper.request(initializeRequest())["result"] != nil)
        #expect(launcher.launches == 0)
        await helper.finish()
    }

    @Test func `Always says so when Pullwatch does not come up in time`() async throws {
        let launcher = StubLauncher()
        let timing = MCPBridge.Timing(launchWait: .milliseconds(200), reconnectWait: .milliseconds(200), pollInterval: .milliseconds(20))
        let helper = run(.always, launcher: launcher, timing: timing)
        let reply = try await helper.request(initializeRequest())
        #expect(errorMessage(reply) == MCPBridge.Message.didNotStart)
        #expect(launcher.launches == 1)
        await helper.finish()
    }

    @Test func `Always says so when Pullwatch cannot be started`() async throws {
        let launcher = StubLauncher { throw CocoaError(.fileNoSuchFile) }
        let helper = run(.always, launcher: launcher)
        let reply = try await helper.request(initializeRequest())
        #expect(errorMessage(reply) == MCPBridge.Message.didNotStart)
        await helper.finish()
    }

    // MARK: - Opnieuw verbinden

    @Test func `After a restart of Pullwatch the agent goes on without a new handshake`() async throws {
        let first = try await startServer()
        let helper = run(.whileOpen)
        #expect(try await helper.request(initializeRequest())["result"] != nil)
        helper.send(initializedNotification)
        #expect(try await helper.request(toolsListRequest(id: 2))["result"] != nil)

        // Sparkle: de app stopt en start opnieuw.
        first.cancel()
        _ = await first.result
        let second = try await startServer()
        defer { second.cancel() }

        let list = try await helper.request(toolsListRequest(id: 3))
        #expect(list["id"] == 3)
        #expect(list["result"] != nil, "de helper deed de handshake opnieuw: \(list)")
        await helper.finish()
    }

    @Test func `The helper replays the handshake and holds requests until it is done`() async throws {
        let app = try FakeApp(at: directory.socket)
        defer { app.close() }
        let helper = run(.whileOpen)

        let firstConnection = try await app.nextConnection()
        helper.send(initializeRequest(id: 1))
        #expect(try await firstConnection.lines.nextObject()["id"] == 1)
        try await firstConnection.send(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)
        #expect(try await helper.replies.nextObject()["id"] == 1)
        helper.send(initializedNotification)
        #expect(try await firstConnection.lines.nextObject()["method"] == "notifications/initialized")

        // Een verzoek dat de app niet meer beantwoordt.
        helper.send(toolsListRequest(id: 2))
        #expect(try await firstConnection.lines.nextObject()["id"] == 2)
        firstConnection.close()
        let lost = try await helper.replies.nextObject()
        #expect(lost["id"] == 2)
        #expect(errorMessage(lost) == MCPBridge.Message.restarted)

        let secondConnection = try await app.nextConnection()
        let replay = try await secondConnection.lines.nextObject()
        #expect(replay["method"] == "initialize")
        #expect(replay["id"] == "pullwatch-mcp-reconnect")
        #expect(replay["params"]?.objectValue?["clientInfo"]?.objectValue?["name"] == "claude-code")

        helper.send(toolsListRequest(id: 3))
        try await secondConnection.send(#"{"jsonrpc":"2.0","id":"pullwatch-mcp-reconnect","result":{}}"#)
        #expect(try await secondConnection.lines.nextObject()["method"] == "notifications/initialized")
        #expect(try await secondConnection.lines.nextObject()["id"] == 3, "pas na de handshake")
        try await secondConnection.send(#"{"jsonrpc":"2.0","id":3,"result":{"tools":[]}}"#)
        let answer = try await helper.replies.nextObject()
        #expect(answer["id"] == 3, "het antwoord op de herhaalde handshake ging niet naar de agent")

        // Maar één keer opnieuw: daarna zegt de helper dat Pullwatch open moet.
        secondConnection.close()
        // Komt het verzoek binnen voordat de helper het sluiten zag, dan krijgt het de fout van
        // een verloren verzoek; het volgende ziet de helper zeker na het sluiten.
        let racing = try await helper.request(toolsListRequest(id: 4))
        #expect(racing["id"] == 4)
        #expect([MCPBridge.Message.openPullwatch, MCPBridge.Message.restarted].contains(errorMessage(racing)))
        let after = try await helper.request(toolsListRequest(id: 5))
        #expect(errorMessage(after) == MCPBridge.Message.openPullwatch)
        await helper.finish()
    }

    @Test func `Turning agents off while connected stops the helper from reconnecting`() async throws {
        let app = try FakeApp(at: directory.socket)
        defer { app.close() }
        let access = Mutex(AgentAccess.whileOpen)
        let bridge = MCPBridge(socketURL: directory.socket, readAccess: { access.withLock { $0 } }, launcher: StubLauncher(), timing: Self.fast)
        let (input, agent) = AsyncStream.makeStream(of: Data.self)
        let replies = MessageQueue()
        let task = Task { await bridge.run(input: input) { replies.push($0) } }

        let connection = try await app.nextConnection()
        access.withLock { $0 = .never }
        connection.close()
        agent.yield(Data((toolsListRequest(id: 9) + "\n").utf8))
        let racing = try await replies.nextObject()
        #expect([MCPBridge.Message.turnedOff, MCPBridge.Message.restarted].contains(errorMessage(racing)))
        agent.yield(Data((toolsListRequest(id: 10) + "\n").utf8))
        let reply = try await replies.nextObject()
        #expect(errorMessage(reply) == MCPBridge.Message.turnedOff)
        agent.finish()
        await task.value
    }

    // MARK: - De app vinden

    @Test func `The app is found from the helper inside it`() {
        let helper = URL(filePath: "/Applications/Pullwatch.app/Contents/Helpers/pullwatch-mcp")
        #expect(PullwatchAppLocation.appBundle(forHelperAt: helper) == URL(filePath: "/Applications/Pullwatch.app/", directoryHint: .isDirectory))
    }

    @Test func `A helper outside an app has no app to start`() {
        #expect(PullwatchAppLocation.appBundle(forHelperAt: URL(filePath: "/usr/local/bin/pullwatch-mcp")) == nil)
        #expect(PullwatchAppLocation.appBundle(forHelperAt: URL(filePath: "/tmp/Helpers/pullwatch-mcp")) == nil)
    }

    @Test func `The app gets the test arguments of the helper`() {
        let arguments = PullwatchAppLocation.launchArguments(from: ["PullwatchDataDirectory": "/tmp/x", "NSDebug": "YES"])
        #expect(arguments == ["-PullwatchDataDirectory", "/tmp/x"])
    }

    @Test func `The mode comes from config.json, never without one`() throws {
        let config = directory.url.appending(path: "config.json")
        #expect(MCPBridge.configuredAccess(at: config) == .never)
        try JSONFileStore<AppConfig>(url: config).save(AppConfig(agentAccess: .always))
        #expect(MCPBridge.configuredAccess(at: config) == .always)
        try Data("not json".utf8).write(to: config)
        #expect(MCPBridge.configuredAccess(at: config) == .never)
    }
}

/// Telt de starts en doet wat de test wil, zonder iets echt te starten.
final class StubLauncher: PullwatchLaunching {
    private let count = Mutex(0)
    private let action: @Sendable () throws -> Void

    init(_ action: @escaping @Sendable () throws -> Void = {}) {
        self.action = action
    }

    var launches: Int { count.withLock { $0 } }

    func launchPullwatch() async throws {
        count.withLock { $0 += 1 }
        try action()
    }
}

/// Een app die alleen de socket heeft: de test leest en schrijft zelf per verbinding.
final class FakeApp: Sendable {
    private let listener: MCPSocketListener
    private let connections: MessageQueueOf<Int32>

    init(at url: URL) throws {
        listener = try MCPSocketListener.open(at: url)
        connections = MessageQueueOf(listener.connections())
    }

    func nextConnection() async throws -> LineClient {
        let socket = try #require(await connections.next())
        return LineClient(try NonBlockingDescriptor(adopting: socket))
    }

    func close() {
        listener.close()
    }
}

/// Leest een stroom één element per keer.
actor MessageQueueOf<Element: Sendable> {
    private var iterator: AsyncStream<Element>.AsyncIterator

    init(_ stream: AsyncStream<Element>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async -> Element? {
        var current = iterator
        defer { iterator = current }
        return await current.next(isolation: self)
    }
}

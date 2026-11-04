import Foundation
import PullwatchCore
import PullwatchMCP
import Synchronization
import Testing

@testable import Pullwatch

/// De MCP-verbinding van de gebouwde app: de socket blijft dicht als host van de tests, agents
/// staan standaard uit, en de echte helper in de bundle praat via een socket in een eigen map
/// met de server, met de echte controle van zijn handtekening. Nooit de echte datamap.
@MainActor @Suite(.timeLimit(.minutes(1))) struct AgentServerTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pw-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var socket: URL { directory.appending(path: "mcp.sock") }

    private var helper: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/pullwatch-mcp")
    }

    @Test func `Agents are off by default`() {
        #expect(AppConfig().agentAccess == .never)
    }

    @Test func `The socket stays closed while XCTest hosts the app`() {
        #expect(!AppModel.shared.agents.isListening)
        let server = AgentServer(socketURL: socket, makeTools: { [] })
        server.apply(.always)
        #expect(!server.isListening)
        #expect(!FileManager.default.fileExists(atPath: socket.path(percentEncoded: false)))
    }

    @Test func `The helper is inside the app`() {
        #expect(FileManager.default.isExecutableFile(atPath: helper.path(percentEncoded: false)))
        #expect(PullwatchAppLocation.appBundle(forHelperAt: helper)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL)
    }

    @Test func `The real helper reaches the server through the socket`() async throws {
        try JSONFileStore<AppConfig>(url: directory.appending(path: "config.json")).save(AppConfig(agentAccess: .whileOpen))
        let server = MCPSocketServer(url: socket, tools: try MCPToolRegistry([]), version: "1.0.0")
        let serving = Task { try await server.run() }
        defer {
            serving.cancel()
            try? FileManager.default.removeItem(at: directory)
        }
        try await waitForSocket()

        let run = try HelperRun(helper: helper, dataDirectory: directory)
        run.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"e2e","version":"1"}}}"#)
        let hello = try await run.nextObject()
        let serverInfo = (hello["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "Pullwatch", "\(hello)")
        run.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        run.send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let list = try await run.nextObject()
        #expect(list["id"] as? Int == 2)
        #expect(((list["result"] as? [String: Any])?["tools"] as? [Any])?.isEmpty == true, "\(list)")

        var events = server.events.makeAsyncIterator()
        guard case .connected(let session) = await events.next() else { throw HelperRun.Failure("geen sessie") }
        #expect(await events.next() == .identified(id: session.id, name: "e2e", version: "1"))
        #expect(await run.finish() == 0)
    }

    @Test func `The real helper refuses when agents are off`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let run = try HelperRun(helper: helper, dataDirectory: directory)
        run.send(#"{"jsonrpc":"2.0","id":"x","method":"initialize","params":{}}"#)
        let reply = try await run.nextObject()
        #expect(reply["id"] as? String == "x")
        #expect((reply["error"] as? [String: Any])?["message"] as? String == MCPBridge.Message.turnedOff)
        #expect(await run.finish() == 0)
        #expect(!FileManager.default.fileExists(atPath: socket.path(percentEncoded: false)))
    }

    private func waitForSocket() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: socket.path(percentEncoded: false)) {
            try #require(ContinuousClock.now < deadline, "de server luisterde niet")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// De helper als proces, zoals een agent hem start: berichten op stdin, antwoorden van stdout.
private final class HelperRun: Sendable {
    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private let process = Process()
    private let input = Pipe()
    private let lines: AsyncStream<Data>
    private let reader: Reader
    private let exits: AsyncStream<Int32>

    init(helper: URL, dataDirectory: URL) throws {
        process.executableURL = helper
        process.arguments = ["-PullwatchDataDirectory", dataDirectory.path(percentEncoded: false)]
        process.standardInput = input
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let (lines, line) = AsyncStream.makeStream(of: Data.self)
        self.lines = lines
        reader = Reader(lines)
        let buffer = Buffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                line.finish()
            } else {
                for message in buffer.append(data) { line.yield(message) }
            }
        }
        let (exits, exit) = AsyncStream.makeStream(of: Int32.self, bufferingPolicy: .bufferingNewest(1))
        self.exits = exits
        process.terminationHandler = { process in
            exit.yield(process.terminationStatus)
            exit.finish()
        }
        try process.run()
    }

    func send(_ json: String) {
        input.fileHandleForWriting.write(Data((json + "\n").utf8))
    }

    func nextObject() async throws -> [String: Any] {
        guard let data = await reader.next() else { throw Failure("de helper stopte zonder antwoord") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure("geen JSON-object") }
        return object
    }

    /// Sluit stdin, zoals een agent die stopt, en geeft de exitcode.
    func finish() async -> Int32? {
        try? input.fileHandleForWriting.close()
        for await status in exits { return status }
        return nil
    }

    /// Knipt stdout in regels.
    private final class Buffer: Sendable {
        private let pending = Mutex(Data())

        func append(_ data: Data) -> [Data] {
            pending.withLock { pending in
                pending.append(data)
                var lines: [Data] = []
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    lines.append(Data(pending[..<newline]))
                    pending = Data(pending[pending.index(after: newline)...])
                }
                return lines
            }
        }
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

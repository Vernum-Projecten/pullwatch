import Darwin
import Foundation
import MCP
import PullwatchCore

/// Eén verbonden agent, zoals de app hem toont: welke client het is (uit `initialize`, alleen om
/// te tonen, geen beveiliging) en sinds wanneer.
public struct MCPSession: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// `clientInfo.name` (`claude-code`), nil tot de client `initialize` stuurde.
    public var clientName: String?
    /// `clientInfo.version`, nil tot `initialize`.
    public var clientVersion: String?
    public let connectedSince: Date

    public init(id: UUID, clientName: String? = nil, clientVersion: String? = nil, connectedSince: Date) {
        self.id = id
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.connectedSince = connectedSince
    }
}

/// Wat er met de sessies gebeurt, in volgorde.
public enum MCPSessionEvent: Sendable, Equatable {
    /// Een verbinding is door de controle en heeft een sessie.
    case connected(MCPSession)
    /// De client van de sessie meldde zich met `initialize`.
    case identified(id: UUID, name: String, version: String)
    case disconnected(id: UUID)
}

/// De MCP-server van de app op de Unix-socket: luistert op `mcp.sock`, controleert elke nieuwe
/// verbinding (`MCPPeerCheck`) voordat er iets gelezen wordt, en start per toegelaten verbinding
/// één `PullwatchMCPServer` met de tools. `run()` loopt tot zijn taak geannuleerd wordt; dan
/// sluiten alle sessies en verdwijnt het socketbestand.
public final class MCPSocketServer: Sendable {
    /// Elke sessie die begint, zich meldt of eindigt. Eén lezer; eindigt als `run()` stopt.
    public let events: AsyncStream<MCPSessionEvent>
    private let emit: AsyncStream<MCPSessionEvent>.Continuation
    private let url: URL
    private let tools: MCPToolRegistry
    private let version: String
    private let instructions: String?
    private let limits: MCPLimits
    private let peerCheck: MCPPeerCheck
    private static let log = Log(category: "MCP")

    public init(
        url: URL = UnixSocket.url(),
        tools: MCPToolRegistry,
        version: String,
        instructions: String? = nil,
        limits: MCPLimits = .standard,
        peerCheck: MCPPeerCheck = .forCurrentProcess()
    ) {
        self.url = url
        self.tools = tools
        self.version = version
        self.instructions = instructions
        self.limits = limits
        self.peerCheck = peerCheck
        (events, emit) = AsyncStream.makeStream(of: MCPSessionEvent.self)
    }

    /// Luistert tot de taak geannuleerd wordt. Gooit als de socket niet open kan (een tweede
    /// Pullwatch luistert al, de map is niet te schrijven).
    public func run() async throws {
        defer { emit.finish() }
        let listener = try MCPSocketListener.open(at: url)
        defer { listener.close() }
        Self.log.notice("MCP: luistert op \(url.path(percentEncoded: false))")
        let connections = listener.connections()
        await withDiscardingTaskGroup { group in
            for await connection in connections {
                group.addTask { await self.serve(connection, listener: listener) }
            }
            // Geannuleerd (of de socket faalde): eerst niemand meer toelaten, dan de sessies
            // stoppen.
            listener.close()
            group.cancelAll()
        }
        Self.log.notice("MCP: gestopt met luisteren")
    }

    /// Eén verbinding: eerst de controle, dan een sessie tot de agent of de app sluit.
    private func serve(_ socket: Int32, listener: MCPSocketListener) async {
        let decision = peerCheck.evaluate(socket: socket)
        guard decision == .accept else {
            if case .refuse(let reason) = decision { Self.log.warning("MCP: verbinding geweigerd: \(reason)") }
            _ = Darwin.close(socket)
            return
        }
        let descriptor: NonBlockingDescriptor
        do {
            try UnixSocket.ignoreBrokenPipe(socket)
            descriptor = try NonBlockingDescriptor(adopting: socket)
        } catch {
            Self.log.error("MCP: verbinding niet in te stellen: \(error)")
            _ = Darwin.close(socket)
            return
        }

        let session = MCPSession(id: UUID(), connectedSince: Date())
        emit.yield(.connected(session))
        defer { emit.yield(.disconnected(id: session.id)) }
        let transport = MCPSocketTransport(descriptor: descriptor, limits: limits)
        do {
            let server = try await PullwatchMCPServer.start(
                tools: tools, version: version, instructions: instructions, limits: limits, on: transport
            ) { [emit] client in
                emit.yield(.identified(id: session.id, name: client.name, version: client.version))
            }
            await withTaskCancellationHandler {
                await server.waitUntilCompleted()
            } onCancel: {
                // Eerst niemand meer toelaten: een helper die na het sluiten meteen opnieuw
                // verbindt, mag niet nog bij deze server binnenkomen.
                listener.close()
                descriptor.shutdown()
            }
            await server.stop()
        } catch {
            Self.log.error("MCP: sessie niet te starten: \(error)")
            descriptor.close()
        }
    }
}

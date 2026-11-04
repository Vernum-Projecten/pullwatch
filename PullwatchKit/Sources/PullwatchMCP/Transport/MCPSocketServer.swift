import Darwin
import Foundation
import MCP
import PullwatchCore
import Synchronization

/// Eén verbonden agent, zoals de app hem toont: welke client het is (uit `initialize`, alleen om
/// te tonen, geen beveiliging), sinds wanneer, en welke tool hij het laatst gebruikte.
public struct MCPSession: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// `clientInfo.name` (`claude-code`), nil tot de client `initialize` stuurde.
    public var clientName: String?
    /// `clientInfo.title` (`Claude Code`), als de client er een stuurt.
    public var clientTitle: String?
    /// `clientInfo.version`, nil tot `initialize`.
    public var clientVersion: String?
    public let connectedSince: Date
    /// De naam van de laatst aangeroepen tool (`list_pull_requests`), nil tot de eerste.
    public var lastTool: String?
    /// Wanneer die tool werd aangeroepen.
    public var lastActivity: Date?

    public init(
        id: UUID, clientName: String? = nil, clientTitle: String? = nil, clientVersion: String? = nil, connectedSince: Date,
        lastTool: String? = nil, lastActivity: Date? = nil
    ) {
        self.id = id
        self.clientName = clientName
        self.clientTitle = clientTitle
        self.clientVersion = clientVersion
        self.connectedSince = connectedSince
        self.lastTool = lastTool
        self.lastActivity = lastActivity
    }

    /// De naam om te tonen (`MCPClientName`), nil tot `initialize`.
    public var displayName: String? {
        clientName.map { MCPClientName.displayName(name: $0, title: clientTitle) }
    }
}

/// Wat er met de sessies gebeurt, in volgorde.
public enum MCPSessionEvent: Sendable, Equatable {
    /// Een verbinding is door de controle en heeft een sessie.
    case connected(MCPSession)
    /// De client van de sessie meldde zich met `initialize`.
    case identified(id: UUID, name: String, version: String, title: String? = nil)
    /// De client riep een tool aan (alleen toegestane aanroepen).
    case calledTool(id: UUID, name: String)
    case disconnected(id: UUID)
}

/// De notificatie die de app stuurt voordat hij een agent loskoppelt (Loskoppelen, Niet
/// toestaan). De helper geeft hem niet door: hij weet dan dat hij niet opnieuw moet verbinden.
public struct PullwatchDisconnectNotification: MCP.Notification {
    public static let name = "notifications/pullwatch/disconnected"
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
    private let approval: MCPApproval?
    /// De lopende sessies, om er een los te kunnen koppelen.
    private let live = Mutex<[UUID: LiveSession]>([:])
    private static let log = Log(category: "MCP")

    public init(
        url: URL = UnixSocket.url(),
        tools: MCPToolRegistry,
        version: String,
        instructions: String? = nil,
        limits: MCPLimits = .standard,
        peerCheck: MCPPeerCheck = .forCurrentProcess(),
        approval: MCPApproval? = nil
    ) {
        self.url = url
        self.tools = tools
        self.version = version
        self.instructions = instructions
        self.limits = limits
        self.peerCheck = peerCheck
        self.approval = approval
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
                tools: tools, version: version, instructions: instructions, limits: limits, approval: approval, on: transport
            ) { [emit] client in
                emit.yield(.identified(id: session.id, name: client.name, version: client.version, title: client.title))
            } onToolCall: { [emit] tool in
                emit.yield(.calledTool(id: session.id, name: tool))
            }
            live.withLock { $0[session.id] = LiveSession(server: server, descriptor: descriptor) }
            defer { _ = live.withLock { $0.removeValue(forKey: session.id) } }
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

    // MARK: - Loskoppelen

    /// Koppelt sessie `id` los: eerst `PullwatchDisconnectNotification`, zodat de helper niet
    /// opnieuw verbindt, dan gaat de socket dicht. Een sessie die al weg is: niets.
    public func disconnect(id: UUID) async {
        guard let session = live.withLock({ $0[id] }) else { return }
        try? await session.server.notify(PullwatchDisconnectNotification.message())
        session.descriptor.shutdown()
    }

    /// Wat `disconnect(id:)` van een lopende sessie nodig heeft.
    private struct LiveSession: Sendable {
        let server: Server
        let descriptor: NonBlockingDescriptor
    }
}

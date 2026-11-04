import Foundation
import Observation
import PullwatchCore
import PullwatchMCP

nonisolated private let logger = Log(category: "MCP")

/// De MCP-server voor coding agents in de app: luistert op `mcp.sock` zolang Instellingen, Agents
/// niet op **Nooit** staat, en houdt bij welke agents verbonden zijn. `AppModel` zet hem aan en
/// uit; de lijst van sessies is voor het scherm Agents (#143) en de knop in het menu (#144).
@Observable
final class AgentServer {
    /// De verbonden agents, in volgorde van verbinden.
    private(set) var sessions: [MCPSession] = []
    /// Of de socket open is.
    private(set) var isListening = false

    /// Of de app gestart is; daarvoor (en als host van de unit-tests) opent `AppModel` niets.
    @ObservationIgnored var isEnabled = false
    /// De luistertaak; er is er hoogstens één.
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    /// Welke luistertaak de huidige is, zodat een gestopte taak bij het afronden de nieuwe niet
    /// opruimt.
    @ObservationIgnored private var listenID: UUID?
    /// De vorige luistertaak, die nog aan het sluiten kan zijn; een nieuwe wacht erop, anders
    /// zou de socket nog bezet zijn.
    @ObservationIgnored private var stoppingTask: Task<Void, Never>?
    @ObservationIgnored private let makeTools: () -> [MCPTool]
    @ObservationIgnored private let socketURL: URL

    init(socketURL: URL = UnixSocket.url(), makeTools: @escaping () -> [MCPTool]) {
        self.socketURL = socketURL
        self.makeTools = makeTools
    }

    /// Opent of sluit de socket voor `access`. Nooit als host van de unit-tests.
    func apply(_ access: AgentAccess) {
        if access.opensSocket, !AppModel.isTestHost {
            startListening()
        } else {
            stopListening()
        }
    }

    /// Opent de socket, tenzij hij al open is.
    func startListening() {
        guard listenTask == nil else { return }
        let registry: MCPToolRegistry
        do {
            registry = try MCPToolRegistry(makeTools())
        } catch {
            logger.error("MCP: ongeldige tool \(error.name): \(error.reason)")
            return
        }
        let server = MCPSocketServer(url: socketURL, tools: registry, version: AppModel.currentVersion)
        let id = UUID()
        let previous = stoppingTask
        listenID = id
        isListening = true
        listenTask = Task { [weak self] in
            defer {
                if let self, self.listenID == id {
                    self.listenID = nil
                    self.listenTask = nil
                    self.isListening = false
                    self.sessions = []
                }
            }
            await previous?.value
            guard !Task.isCancelled else { return }
            await withDiscardingTaskGroup { group in
                group.addTask {
                    do {
                        try await server.run()
                    } catch {
                        logger.error("MCP: socket niet te openen: \(error)")
                    }
                }
                for await event in server.events {
                    self?.handle(event)
                }
            }
        }
    }

    /// Sluit de socket en elke sessie.
    func stopListening() {
        guard let listenTask else { return }
        listenTask.cancel()
        stoppingTask = listenTask
        self.listenTask = nil
        listenID = nil
        isListening = false
        sessions = []
    }

    private func handle(_ event: MCPSessionEvent) {
        switch event {
        case .connected(let session):
            sessions.append(session)
            logger.notice("MCP: agent verbonden")
        case .identified(let id, let name, let version):
            guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
            sessions[index].clientName = name
            sessions[index].clientVersion = version
            logger.notice("MCP: agent is \(name) \(version)")
        case .disconnected(let id):
            sessions.removeAll { $0.id == id }
            logger.notice("MCP: agent weg")
        }
    }
}

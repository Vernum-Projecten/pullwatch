import Foundation
import Observation
import PullwatchCore
import PullwatchMCP

nonisolated private let logger = Log(category: "MCP")

/// De MCP-server voor coding agents in de app: luistert op `mcp.sock` zolang Instellingen, Agents
/// niet op **Nooit** staat, houdt bij welke agents verbonden zijn en welke de persoon heeft
/// toegestaan. Een agent die zich voor het eerst meldt, wacht op toestemming (`MCPApproval`):
/// `onApprovalNeeded` vraagt het met een melding, en tot dan geeft elke tool-aanroep een
/// wachtmelding. `AppModel` zet hem aan en uit en bewaart de toegestane agents in `AppConfig`;
/// Instellingen, Agents en de knop in het menu (#144) lezen `sessions` en `pendingAgents`.
@Observable
final class AgentServer {
    /// De verbonden agents, in volgorde van verbinden.
    private(set) var sessions: [MCPSession] = []
    /// Of de socket open is.
    private(set) var isListening = false
    /// De toegestane agents op `clientInfo.name` (`AppConfig.approvedAgents`).
    private(set) var approvedAgents: [String] = []

    /// Een agent die nog niet is toegestaan en verbonden is.
    struct PendingAgent: Identifiable, Equatable {
        /// `clientInfo.name`, waar toestaan op gaat.
        let id: String
        let displayName: String
    }

    /// Of de app gestart is; daarvoor (en als host van de unit-tests) opent `AppModel` niets.
    @ObservationIgnored var isEnabled = false
    /// De toegestane agents zijn veranderd; `AppModel` bewaart ze in de config.
    @ObservationIgnored var onApprovalsChanged: (([String]) -> Void)?
    /// Een agent die niet is toegestaan meldde zich (`clientName`, `displayName`); `AppModel`
    /// vraagt het met een melding.
    @ObservationIgnored var onApprovalNeeded: ((_ clientName: String, _ displayName: String) -> Void)?
    /// De vraag over `clientName` is beantwoord (hier of in de melding); de melding mag weg.
    @ObservationIgnored var onApprovalAnswered: ((_ clientName: String) -> Void)?
    /// De luistertaak; er is er hoogstens één.
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    /// Welke luistertaak de huidige is, zodat een gestopte taak bij het afronden de nieuwe niet
    /// opruimt.
    @ObservationIgnored private var listenID: UUID?
    /// De vorige luistertaak, die nog aan het sluiten kan zijn; een nieuwe wacht erop, anders
    /// zou de socket nog bezet zijn.
    @ObservationIgnored private var stoppingTask: Task<Void, Never>?
    /// De server van de huidige luistertaak, om een sessie los te koppelen.
    @ObservationIgnored private var server: MCPSocketServer?
    @ObservationIgnored private let makeTools: () -> [MCPTool]
    @ObservationIgnored private let socketURL: URL

    init(socketURL: URL = UnixSocket.url(), makeTools: @escaping () -> [MCPTool]) {
        self.socketURL = socketURL
        self.makeTools = makeTools
    }

    // MARK: - Luisteren

    /// Opent of sluit de socket voor `access`. Nooit als host van de unit-tests.
    func apply(_ access: AgentAccess) {
        if access.opensSocket, !AppModel.isTestHost {
            startListening()
        } else {
            stopListening()
        }
    }

    /// Opent de socket, tenzij hij al open is. De tools worden hier gemaakt, dus pas als de
    /// modellen van de app er zijn.
    func startListening() {
        guard listenTask == nil else { return }
        let registry: MCPToolRegistry
        do {
            registry = try MCPToolRegistry(makeTools())
        } catch {
            logger.error("MCP: ongeldige tool \(error.name): \(error.reason)")
            return
        }
        let approval = MCPApproval { @MainActor [weak self] clientName in
            self?.isApproved(clientName) ?? false
        }
        let server = MCPSocketServer(url: socketURL, tools: registry, version: AppModel.currentVersion, approval: approval)
        let id = UUID()
        let previous = stoppingTask
        listenID = id
        isListening = true
        self.server = server
        listenTask = Task { [weak self] in
            defer {
                if let self, self.listenID == id {
                    self.listenID = nil
                    self.listenTask = nil
                    self.server = nil
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
        server = nil
        isListening = false
        sessions = []
    }

    /// Verwerkt wat de server over de sessies meldt.
    func handle(_ event: MCPSessionEvent) {
        switch event {
        case .connected(let session):
            sessions.append(session)
            logger.notice("MCP: agent verbonden")
        case .identified(let id, let name, let version, let title):
            guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
            // Al een sessie van deze client die wacht: die heeft de vraag al gesteld.
            let alreadyAsked = sessions.contains { $0.id != id && $0.clientName == name }
            sessions[index].clientName = name
            sessions[index].clientTitle = title
            sessions[index].clientVersion = version
            logger.notice("MCP: agent is \(name) \(version)")
            if !isApproved(name), !alreadyAsked {
                onApprovalNeeded?(name, MCPClientName.displayName(name: name, title: title))
            }
        case .calledTool(let id, let tool):
            guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
            sessions[index].lastTool = tool
            sessions[index].lastActivity = Date()
        case .disconnected(let id):
            sessions.removeAll { $0.id == id }
            logger.notice("MCP: agent weg")
        }
    }

    // MARK: - Toestaan

    func isApproved(_ clientName: String) -> Bool {
        approvedAgents.contains(clientName)
    }

    /// De verbonden agents die nog op toestemming wachten, één per client, in volgorde van
    /// verbinden.
    var pendingAgents: [PendingAgent] {
        var seen: Set<String> = []
        return sessions.compactMap { session in
            guard let name = session.clientName, let displayName = session.displayName,
                  !isApproved(name), seen.insert(name).inserted else { return nil }
            return PendingAgent(id: name, displayName: displayName)
        }
    }

    /// Neemt de toegestane agents uit de config over (bij het starten en na elke wijziging).
    func load(approved: [String]) {
        approvedAgents = approved
    }

    /// Sta `clientName` toe: zijn volgende tool-aanroep krijgt een antwoord.
    func allow(_ clientName: String) {
        if !isApproved(clientName) {
            approvedAgents.append(clientName)
            onApprovalsChanged?(approvedAgents)
        }
        onApprovalAnswered?(clientName)
    }

    /// Sta `clientName` niet toe: elke sessie van die client gaat dicht; er wordt niets
    /// onthouden, dus een volgende keer vraagt Pullwatch het opnieuw.
    func deny(_ clientName: String) {
        for session in sessions where session.clientName == clientName {
            disconnect(id: session.id)
        }
        onApprovalAnswered?(clientName)
    }

    /// Haalt `clientName` van de lijst; een verbonden sessie wacht daarna weer op toestemming.
    func removeApproval(_ clientName: String) {
        guard isApproved(clientName) else { return }
        approvedAgents.removeAll { $0 == clientName }
        onApprovalsChanged?(approvedAgents)
    }

    // MARK: - Loskoppelen

    /// Koppelt sessie `id` los. De helper hoort het eerst en verbindt dan niet opnieuw; de sessie
    /// verdwijnt uit `sessions` als de server hem gesloten meldt.
    func disconnect(id: UUID) {
        guard let server else {
            // Zonder server (de nep-sessies van de camera, de tests): meteen weg.
            sessions.removeAll { $0.id == id }
            return
        }
        Task { await server.disconnect(id: id) }
    }

    #if DEBUG
    /// Alleen voor `FakeAgents` en de tests: sessies zonder echte verbinding.
    func showFakeSessions(_ sessions: [MCPSession]) {
        self.sessions = sessions
    }
    #endif
}

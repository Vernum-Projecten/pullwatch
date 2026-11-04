import Foundation
import PullwatchMCP

/// Wat de agentknop in de kop van het menupaneel toont: de verbonden agents, wie op toestemming
/// wacht, of de knop er is en wat hij zegt. Een waarde, uit `AgentServer.sessions` gemaakt, zodat
/// de tests hem zonder model of venster kunnen nagaan.
struct MenuAgentsSummary: Equatable {
    /// Eén verbonden agent en of hij op toestemming wacht.
    struct Agent: Identifiable, Equatable {
        let session: MCPSession
        let isWaiting: Bool
        var id: UUID { session.id }
    }

    let agents: [Agent]

    /// `isApproved` zegt of een `clientInfo.name` mag; een agent die nog niet zei wie hij is,
    /// wacht nog niet.
    init(sessions: [MCPSession], isApproved: (String) -> Bool) {
        agents = sessions.map { session in
            Agent(session: session, isWaiting: session.clientName.map { !isApproved($0) } ?? false)
        }
    }

    var count: Int { agents.count }
    var waitingCount: Int { agents.count(where: \.isWaiting) }
    /// De knop staat er alleen zolang er een agent verbonden is.
    var isVisible: Bool { !agents.isEmpty }
    /// Een agent wacht op toestemming: de knop krijgt een oranje stip.
    var isWaiting: Bool { waitingCount > 0 }

    /// De tooltip en het VoiceOver-label: wie wacht gaat voor, anders hoeveel er verbonden zijn.
    func label(bundle: Bundle = .main) -> String {
        if isWaiting {
            String(localized: "\(waitingCount) agents wachten op toestemming", bundle: bundle, comment: "Menupaneel, knop Agents; aantal agents dat op toestemming wacht")
        } else {
            String(localized: "\(count) agents verbonden", bundle: bundle, comment: "Menupaneel, knop Agents; aantal verbonden agents")
        }
    }
}

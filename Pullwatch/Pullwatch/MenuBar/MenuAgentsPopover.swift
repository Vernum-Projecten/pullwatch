import PullwatchMCP
import SwiftUI

/// De lijst achter de agentknop in het menupaneel: per verbonden agent naam, versie, sinds wanneer
/// en de laatste tool, met Loskoppelen; wie wacht ook Sta niet toe en Sta toe. Onderaan
/// Agentinstellingen…, naar Instellingen, Agents. Leest geen model; de agents en de acties komen
/// binnen.
struct MenuAgentsPopover: View {
    let agents: [MenuAgentsSummary.Agent]
    /// Op `clientInfo.name`.
    let allow: (String) -> Void
    let deny: (String) -> Void
    let disconnect: (UUID) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verbonden agents")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(agents) { agent in
                MenuAgentRow(agent: agent, allow: allow, deny: deny) { disconnect(agent.id) }
                Divider()
            }
            Button("Agentinstellingen…", action: openSettings)
                .accessibilityIdentifier("menu.agents.settings")
        }
        .padding(14)
        .frame(width: 380)
    }
}

/// Eén agent in de lijst: de rij van Instellingen, en als hij wacht de vraag eronder.
private struct MenuAgentRow: View {
    let agent: MenuAgentsSummary.Agent
    let allow: (String) -> Void
    let deny: (String) -> Void
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ConnectedAgentRow(session: agent.session, isWaiting: agent.isWaiting, disconnect: disconnect)
            if agent.isWaiting, let name = agent.session.clientName {
                let displayName = agent.session.displayName ?? name
                HStack {
                    Button("Sta niet toe") { deny(name) }
                        .help("Koppel \(displayName) los, zonder iets te onthouden")
                    Button("Sta toe") { allow(name) }
                        .buttonStyle(.borderedProminent)
                        .help("\(displayName) mag Pullwatch gebruiken")
                }
            }
        }
    }
}

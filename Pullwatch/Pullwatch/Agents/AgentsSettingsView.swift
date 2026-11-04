import PullwatchCore
import PullwatchMCP
import SwiftUI

/// Instellingen, Agents: of coding agents Pullwatch mogen gebruiken (zoals Xcode's "Allow
/// External Agents to Use Xcode Tools"), hoe je een agent instelt, welke agents nu verbonden
/// zijn en welke je hebt toegestaan.
struct AgentsSettingsView: View {
    /// Het SF Symbol van agents, in het tabblad en bij een verbonden agent.
    nonisolated static let symbol = "point.3.connected.trianglepath.dotted"

    var body: some View {
        Form {
            AgentAccessSection()
            AgentSetupSection()
            ConnectedAgentsSection()
            ApprovedAgentsSection()
        }
        .formStyle(.grouped)
    }
}

/// De keuze Nooit, Zolang Pullwatch open is, Altijd, met wat delen betekent.
private struct AgentAccessSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            Picker("Agents toestaan Pullwatch te gebruiken", selection: Bindable(app).agentAccess) {
                ForEach(AgentAccess.allCases, id: \.self) { access in
                    Text(access.label).tag(access)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.agents.access")
            Text("Wat een agent in Pullwatch leest, gaat naar de aanbieder van zijn model.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } footer: {
            Text("Agents lezen alleen wat Pullwatch al heeft opgehaald en kunnen niets veranderen op GitHub, Azure DevOps of GitLab.")
        }
    }
}

/// Per client de opdracht of JSON, met het pad van de helper in deze app.
private struct AgentSetupSection: View {
    var body: some View {
        let helper = AgentClient.helperPath
        Section("Een agent instellen") {
            ForEach(AgentClient.allCases) { client in
                AgentSetupRow(name: client.name, setup: client.setup(helper: helper), placement: client.placement)
            }
        }
    }
}

/// De agents die nu verbonden zijn, live uit `AgentServer`.
private struct ConnectedAgentsSection: View {
    @Environment(AgentServer.self) private var agents

    var body: some View {
        Section("Verbonden agents") {
            if agents.sessions.isEmpty {
                ContentUnavailableView {
                    Label("Geen agent verbonden", systemImage: AgentsSettingsView.symbol)
                } description: {
                    Text("Een agent die je hierboven hebt ingesteld, verschijnt hier zodra hij Pullwatch gebruikt.")
                }
            } else {
                ForEach(agents.sessions) { session in
                    ConnectedAgentRow(
                        session: session,
                        isWaiting: session.clientName.map { !agents.isApproved($0) } ?? false
                    ) {
                        agents.disconnect(id: session.id)
                    }
                }
            }
        }
    }
}

/// Wie op toestemming wacht (Sta toe, Sta niet toe) en wie al mag (met verwijderen).
private struct ApprovedAgentsSection: View {
    @Environment(AgentServer.self) private var agents

    var body: some View {
        Section {
            ForEach(agents.pendingAgents) { pending in
                ApprovedAgentRow(
                    displayName: pending.displayName,
                    status: .waiting(allow: { agents.allow(pending.id) }, deny: { agents.deny(pending.id) })
                )
            }
            ForEach(agents.approvedAgents, id: \.self) { name in
                ApprovedAgentRow(
                    displayName: MCPClientName.displayName(name: name),
                    status: .approved(remove: { agents.removeApproval(name) })
                )
            }
            if agents.pendingAgents.isEmpty && agents.approvedAgents.isEmpty {
                Text("Nog geen agent toegestaan.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Toegestane agents")
        } footer: {
            Text("De eerste keer dat een agent Pullwatch gebruikt, vraagt Pullwatch het met een melding. Tot je toestaat, krijgt de agent geen gegevens.")
        }
    }
}

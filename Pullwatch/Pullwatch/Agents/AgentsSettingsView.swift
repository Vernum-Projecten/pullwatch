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

/// De keuze Nooit, Zolang Pullwatch open is, Altijd; daaronder wat delen betekent.
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
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wat een agent in Pullwatch leest, gaat naar de aanbieder van zijn model.")
                Text("Agents lezen alleen wat Pullwatch al heeft opgehaald en kunnen niets veranderen op GitHub, Azure DevOps of GitLab.")
            }
        }
    }
}

/// Eén client tegelijk, gekozen met een gesegmenteerde knop: de opdracht of JSON met het pad van
/// de helper in deze app.
private struct AgentSetupSection: View {
    @State private var client: AgentClient = .claudeCode

    var body: some View {
        Section {
            Picker("Agent", selection: $client) {
                ForEach(AgentClient.allCases) { client in
                    Text(verbatim: client.name).tag(client)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("settings.agents.client")
            AgentSetupRow(name: client.name, setup: client.setup(helper: AgentClient.helperPath), placement: client.placement)
        } header: {
            Text("Een agent instellen")
        } footer: {
            Text("Gebruikt het pad van deze Pullwatch. Verplaats je de app, stel de agent dan opnieuw in.")
        }
    }
}

/// De agents die nu verbonden zijn, live uit `AgentServer`.
private struct ConnectedAgentsSection: View {
    @Environment(AgentServer.self) private var agents

    var body: some View {
        Section("Verbonden agents") {
            if agents.sessions.isEmpty {
                EmptyListRow(
                    symbol: AgentsSettingsView.symbol,
                    title: "Geen agent verbonden",
                    message: "Een agent die je hierboven hebt ingesteld, verschijnt hier zodra hij Pullwatch gebruikt."
                )
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
            if agents.pendingAgents.isEmpty && agents.approvedAgents.isEmpty {
                EmptyListRow(symbol: "checkmark.circle", title: "Nog geen agent toegestaan", message: nil)
            }
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
        } header: {
            Text("Toegestane agents")
        } footer: {
            Text("De eerste keer dat een agent Pullwatch gebruikt, vraagt Pullwatch het met een melding. Tot je toestaat, krijgt de agent geen gegevens.")
        }
    }
}

/// Een lege lijst in een groep, gecentreerd zoals Systeeminstellingen het doet: een klein symbool,
/// de titel en eventueel een regel uitleg, in `.secondary`.
private struct EmptyListRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

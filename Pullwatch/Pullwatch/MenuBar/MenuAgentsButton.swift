import SwiftUI

/// In de kop van het menupaneel, alleen zolang er een agent verbonden is (zoals Xcode het doet):
/// het symbool van Agents met het aantal, en een oranje stip als er een op toestemming wacht. Een
/// klik toont de verbonden agents (`MenuAgentsPopover`). Leest `AgentServer` zelf, zodat een agent
/// die komt of gaat alleen deze knop opnieuw laat tekenen; zonder agent tekent hij niets en blijft
/// de kop zoals hij was.
struct MenuAgentsButton: View {
    @Environment(AgentServer.self) private var agents
    @Environment(AppRouter.self) private var router
    @State private var showsAgents = false

    var body: some View {
        let summary = MenuAgentsSummary(sessions: agents.sessions, isApproved: agents.isApproved)
        if summary.isVisible {
            Button {
                showsAgents.toggle()
            } label: {
                MenuAgentsButtonLabel(count: summary.count, isWaiting: summary.isWaiting)
            }
            .buttonStyle(MenuIconButtonStyle(id: "agents"))
            .help(Text(verbatim: summary.label()))
            .accessibilityLabel(Text(verbatim: summary.label()))
            .accessibilityIdentifier("menu.agents")
            .popover(isPresented: $showsAgents, arrowEdge: .bottom) {
                MenuAgentsPopover(
                    agents: summary.agents,
                    allow: agents.allow,
                    deny: agents.deny,
                    disconnect: agents.disconnect(id:),
                    openSettings: openAgentSettings
                )
            }
            #if DEBUG
            // Voor schermafbeeldingen (`-PullwatchMenuAgentsPopover YES`): de lijst meteen open.
            .task {
                guard UserDefaults.standard.bool(forKey: "PullwatchMenuAgentsPopover") else { return }
                try? await Task.sleep(for: .seconds(1))
                showsAgents = true
                SnapshotCamera.shootPopover("menu-agents")
                // `-PullwatchMenuAgentsOpenSettings YES`: daarna Agentinstellingen…, zoals een klik.
                guard UserDefaults.standard.bool(forKey: "PullwatchMenuAgentsOpenSettings") else { return }
                try? await Task.sleep(for: .seconds(2))
                openAgentSettings()
            }
            #endif
        }
    }

    /// Agentinstellingen…: de lijst dicht en Instellingen open op Agents.
    private func openAgentSettings() {
        showsAgents = false
        router.showSettings(.agents)
    }
}

/// Het symbool met het aantal, en de oranje stip rechtsboven als er een agent wacht.
private struct MenuAgentsButtonLabel: View {
    let count: Int
    let isWaiting: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: AgentsSettingsView.symbol)
            Text(count, format: .number)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.orange)
                .frame(width: 7, height: 7)
                .opacity(isWaiting ? 1 : 0)
                .offset(x: -1, y: -3)
        }
    }
}

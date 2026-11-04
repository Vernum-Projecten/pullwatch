import PullwatchMCP
import SwiftUI

/// Eén verbonden agent: naam en versie (of "Verbinden…" tot `initialize`), sinds wanneer, de
/// laatst gebruikte tool, of hij op toestemming wacht, en Loskoppelen. Leest geen model; de
/// sessie en de knop komen binnen.
struct ConnectedAgentRow: View {
    let session: MCPSession
    let isWaiting: Bool
    let disconnect: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: AgentsSettingsView.symbol)
                .font(.title3)
                // Oranje als hij wacht, grijs tot hij zegt wie hij is.
                .foregroundStyle(isWaiting ? AnyShapeStyle(.orange) : session.clientName == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let name = session.displayName {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: name).fontWeight(.medium)
                        if let version = session.clientVersion, !version.isEmpty {
                            Text(verbatim: version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Verbinden…", comment: "Instellingen, Agents: een agent is verbonden maar heeft nog niet gezegd wie hij is")
                        .fontWeight(.medium)
                }
                // Elke minuut opnieuw, zodat "2 minuten geleden" klopt.
                TimelineView(.everyMinute) { _ in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Verbonden \(session.connectedSince.formatted(.relative(presentation: .named)))", comment: "Instellingen, Agents; hoe lang geleden, bv. 5 minuten geleden")
                        if isWaiting {
                            Text("Wacht op toestemming")
                                .foregroundStyle(.orange)
                        } else if let tool = session.lastTool, let at = session.lastActivity {
                            Text("Laatste tool: \(tool), \(at.formatted(.relative(presentation: .named)))", comment: "Instellingen, Agents; naam van een MCP-tool en hoe lang geleden")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Loskoppelen", action: disconnect)
                .help("Sluit de verbinding van deze agent met Pullwatch")
        }
        .padding(.vertical, 2)
    }
}

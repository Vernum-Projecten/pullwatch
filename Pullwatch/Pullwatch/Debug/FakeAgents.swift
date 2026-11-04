#if DEBUG
import Foundation
import PullwatchMCP

/// Alleen in debug-builds: met `-PullwatchFakeAgents <n>` toont Instellingen, Agents `n` nep-
/// agents (1 tot 3) zonder echte verbinding, voor de camera: Claude Code met een laatst gebruikte
/// tool, Codex, en een agent die nog niet zei wie hij is. Of Codex op toestemming wacht, hangt
/// af van `approvedAgents` in config.json.
enum FakeAgents {
    static var count: Int { UserDefaults.standard.integer(forKey: "PullwatchFakeAgents") }

    static func installIfRequested(in server: AgentServer) {
        guard count > 0 else { return }
        let now = Date()
        let sessions = [
            MCPSession(
                id: UUID(), clientName: "claude-code", clientVersion: "2.1.31", connectedSince: now.addingTimeInterval(-12 * 60),
                lastTool: "list_pull_requests", lastActivity: now.addingTimeInterval(-90)
            ),
            MCPSession(id: UUID(), clientName: "codex-mcp-client", clientVersion: "0.64.0", connectedSince: now.addingTimeInterval(-3 * 60)),
            MCPSession(id: UUID(), connectedSince: now.addingTimeInterval(-5)),
        ]
        server.showFakeSessions(Array(sessions.prefix(count)))
    }
}
#endif

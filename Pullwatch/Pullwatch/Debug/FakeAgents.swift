#if DEBUG
import AppKit
import PullwatchMCP

/// Alleen in debug-builds: met `-PullwatchFakeAgents <n>` toont Instellingen, Agents `n` nep-
/// agents (0 tot 3) zonder echte verbinding, voor de camera: Claude Code met een laatst gebruikte
/// tool, Codex, en een agent die nog niet zei wie hij is. Of Codex op toestemming wacht, hangt
/// af van `approvedAgents` in config.json. Met `-PullwatchSnapshotDark YES` of
/// `-PullwatchSnapshotLight YES` erbij in donkere of lichte modus, zoals de tour.
/// Bijvoorbeeld: `-PullwatchOpenSettings YES -PullwatchSettingsPane agents -PullwatchFakeAgents 2
/// -PullwatchSnapshotDirectory <map>`.
enum FakeAgents {
    static func installIfRequested(in server: AgentServer) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "PullwatchFakeAgents") != nil else { return }
        if defaults.bool(forKey: "PullwatchSnapshotDark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if defaults.bool(forKey: "PullwatchSnapshotLight") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        let now = Date()
        let sessions = [
            MCPSession(
                id: UUID(), clientName: "claude-code", clientVersion: "2.1.31", connectedSince: now.addingTimeInterval(-12 * 60),
                lastTool: "list_pull_requests", lastActivity: now.addingTimeInterval(-90)
            ),
            MCPSession(id: UUID(), clientName: "codex-mcp-client", clientVersion: "0.64.0", connectedSince: now.addingTimeInterval(-3 * 60)),
            MCPSession(id: UUID(), connectedSince: now.addingTimeInterval(-5)),
        ]
        server.showFakeSessions(Array(sessions.prefix(max(0, defaults.integer(forKey: "PullwatchFakeAgents")))))
    }
}
#endif

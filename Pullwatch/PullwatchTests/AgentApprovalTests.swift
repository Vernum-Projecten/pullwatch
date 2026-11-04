import Foundation
import PullwatchCore
import PullwatchMCP
import Testing

@testable import Pullwatch

/// Toestaan per agent in de app: wie zich meldt zonder toestemming krijgt één vraag, wacht tot
/// Sta toe, Sta niet toe koppelt los zonder iets te onthouden, en de lijst gaat naar de config.
/// Met een eigen `AgentServer` zonder socket; nooit de echte config.
@MainActor @Suite struct AgentApprovalTests {
    let server = AgentServer(socketURL: FileManager.default.temporaryDirectory.appending(path: "pw-unused.sock"), makeTools: { [] })
    let asked = Recorder<String>()
    let answered = Recorder<String>()
    let saved = Recorder<[String]>()

    init() {
        let asked = asked, answered = answered, saved = saved
        server.onApprovalNeeded = { name, displayName in asked.append("\(name)=\(displayName)") }
        server.onApprovalAnswered = { answered.append($0) }
        server.onApprovalsChanged = { saved.append($0) }
    }

    /// Een sessie die verbindt en zich meldt.
    @discardableResult
    private func connect(_ name: String, title: String? = nil) -> UUID {
        let id = UUID()
        server.handle(.connected(MCPSession(id: id, connectedSince: .now)))
        server.handle(.identified(id: id, name: name, version: "1.0", title: title))
        return id
    }

    @Test func `A new agent is asked about once and waits`() {
        connect("claude-code")
        connect("claude-code")

        #expect(asked.values == ["claude-code=Claude Code"])
        #expect(server.pendingAgents == [AgentServer.PendingAgent(id: "claude-code", displayName: "Claude Code")])
        #expect(!server.isApproved("claude-code"))
    }

    @Test func `A connecting agent without a name is not asked about yet`() {
        server.handle(.connected(MCPSession(id: UUID(), connectedSince: .now)))

        #expect(asked.values.isEmpty)
        #expect(server.pendingAgents.isEmpty)
        #expect(server.sessions.first?.displayName == nil)
    }

    @Test func `An approved agent is not asked about`() {
        server.load(approved: ["claude-code"])
        connect("claude-code")

        #expect(asked.values.isEmpty)
        #expect(server.pendingAgents.isEmpty)
    }

    @Test func `Allow approves, saves and answers the notification`() {
        connect("codex-mcp-client")

        server.allow("codex-mcp-client")

        #expect(server.isApproved("codex-mcp-client"))
        #expect(server.pendingAgents.isEmpty)
        #expect(saved.values == [["codex-mcp-client"]])
        #expect(answered.values == ["codex-mcp-client"])
        #expect(server.sessions.count == 1, "de agent blijft verbonden")
    }

    @Test func `Don't Allow disconnects that agent and remembers nothing`() {
        connect("codex-mcp-client")
        let other = connect("claude-code")

        server.deny("codex-mcp-client")

        #expect(server.sessions.map(\.id) == [other])
        #expect(!server.isApproved("codex-mcp-client"))
        #expect(saved.values.isEmpty)
        #expect(answered.values == ["codex-mcp-client"])
    }

    @Test func `Removing an approval makes a connected agent wait again`() {
        server.load(approved: ["claude-code", "cursor-vscode"])
        connect("claude-code")

        server.removeApproval("claude-code")

        #expect(server.approvedAgents == ["cursor-vscode"])
        #expect(saved.values == [["cursor-vscode"]])
        #expect(server.pendingAgents.map(\.id) == ["claude-code"])
    }

    @Test func `The last tool and when it was used are kept per agent`() throws {
        let id = connect("claude-code")

        server.handle(.calledTool(id: id, name: "list_pull_requests"))

        let session = try #require(server.sessions.first)
        #expect(session.lastTool == "list_pull_requests")
        #expect(session.lastActivity != nil)
    }

    @Test func `Disconnect without a socket removes the agent at once`() {
        let id = connect("claude-code")
        server.disconnect(id: id)
        #expect(server.sessions.isEmpty)
    }

    @Test func `The title from initialize is the name that is shown`() {
        connect("my-agent", title: "My Agent")
        #expect(server.pendingAgents.first?.displayName == "My Agent")
    }

    @Test func `A config from before the approvals has no approved agents`() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"accounts":[],"pollInterval":120}"#.utf8))
        #expect(config.approvedAgents.isEmpty)
    }

    // MARK: - Melding

    @Test func `The question is a notification with Allow and Don't Allow`() {
        let content = NotificationContentBuilder().agentApproval(clientName: "claude-code", displayName: "Claude Code")

        #expect(content.kind == .agent)
        #expect(content.category == .agent)
        #expect(NotificationCategory.agent.actions == [.allowAgent, .denyAgent])
        #expect(content.title.contains("Claude Code"))
        #expect(content.identifier == NotificationContentBuilder.agentApprovalIdentifier("claude-code"))
        #expect(NotificationPayload(userInfo: content.payload.userInfo).agentName == "claude-code")
        #expect(content.importance.level == .active)
    }

    // MARK: - Instellingen

    @Test func `The access picker offers the three modes with their own words`() {
        let labels = AgentAccess.allCases.map { String(localized: $0.label) }
        #expect(AgentAccess.allCases == [.never, .whileOpen, .always])
        #expect(Set(labels).count == 3)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    @Test func `The access setting reads the config`() {
        #expect(AppModel.shared.agentAccess == AppModel.shared.accounts.config.agentAccess)
    }

    @Test(arguments: AgentClient.allCases)
    func `Each client gets the helper path in its own format`(_ client: AgentClient) {
        let setup = client.setup(helper: "/Applications/Pullwatch.app/Contents/Helpers/pullwatch-mcp")
        #expect(setup.contains("/Applications/Pullwatch.app/Contents/Helpers/pullwatch-mcp"))
        #expect(setup.contains("pullwatch"))
    }

    @Test func `The commands match each client's documentation`() throws {
        let helper = "/Applications/Pullwatch.app/Contents/Helpers/pullwatch-mcp"
        #expect(AgentClient.claudeCode.setup(helper: helper) == "claude mcp add --scope user --transport stdio pullwatch -- \(helper)")
        #expect(AgentClient.codex.setup(helper: helper) == "codex mcp add pullwatch -- \(helper)")
        let cursor = try #require(JSONSerialization.jsonObject(with: Data(AgentClient.cursor.setup(helper: helper).utf8)) as? [String: Any])
        let cursorServer = (cursor["mcpServers"] as? [String: Any])?["pullwatch"] as? [String: Any]
        #expect(cursorServer?["command"] as? String == helper)
        #expect(cursorServer?["type"] as? String == "stdio")
        let vsCode = try #require(JSONSerialization.jsonObject(with: Data(AgentClient.vsCode.setup(helper: helper).utf8)) as? [String: Any])
        let vsCodeServer = (vsCode["servers"] as? [String: Any])?["pullwatch"] as? [String: Any]
        #expect(vsCodeServer?["command"] as? String == helper)
        #expect(vsCodeServer?["type"] as? String == "stdio")
    }

    @Test func `A helper path with spaces or quotes stays one word`() throws {
        let helper = #"/Users/ada/My Apps/Ada's "Pullwatch".app/Contents/Helpers/pullwatch-mcp"#
        #expect(AgentClient.shellQuoted(helper) == #"'/Users/ada/My Apps/Ada'\''s "Pullwatch".app/Contents/Helpers/pullwatch-mcp'"#)
        #expect(AgentClient.claudeCode.setup(helper: helper).hasSuffix("-- " + AgentClient.shellQuoted(helper)))
        let json = try #require(JSONSerialization.jsonObject(with: Data(AgentClient.cursor.setup(helper: helper).utf8)) as? [String: Any])
        #expect(((json["mcpServers"] as? [String: Any])?["pullwatch"] as? [String: Any])?["command"] as? String == helper)
    }

    @Test func `The helper path is the one inside the running app`() {
        #expect(AgentClient.helperPath.hasSuffix(".app/Contents/Helpers/pullwatch-mcp"))
        #expect(FileManager.default.isExecutableFile(atPath: AgentClient.helperPath))
    }
}

/// Houdt bij wat een callback kreeg.
@MainActor final class Recorder<Value> {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}

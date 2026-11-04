import Foundation
import Testing
import PullwatchCore

/// De agents die de persoon heeft toegestaan: een oude config heeft er geen, de lijst houdt zijn
/// volgorde, en iets onleesbaars geeft geen toegestane agent.
@Suite struct ApprovedAgentsTests {
    @Test func `A new config has no approved agents`() {
        #expect(AppConfig().approvedAgents.isEmpty)
    }

    @Test func `A config from before the approvals has no approved agents`() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"accounts":[],"pollInterval":120,"agentAccess":"always"}"#.utf8))
        #expect(config.approvedAgents.isEmpty)
        #expect(config.agentAccess == .always, "de rest leest gewoon")
    }

    @Test func `The approved agents survive a round trip in order`() throws {
        let config = AppConfig(approvedAgents: ["codex-mcp-client", "claude-code"])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data).approvedAgents == ["codex-mcp-client", "claude-code"])
        let written = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(written?["approvedAgents"] as? [String] == ["codex-mcp-client", "claude-code"])
    }

    @Test func `An unreadable list gives no approved agents`() throws {
        let json = #"{"accounts":[],"pollInterval":120,"approvedAgents":"claude-code"}"#
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).approvedAgents.isEmpty)
    }
}

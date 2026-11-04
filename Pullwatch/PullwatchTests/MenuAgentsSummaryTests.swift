import Foundation
import PullwatchMCP
import Testing

@testable import Pullwatch

/// De agentknop in de kop van het menupaneel: alleen met een verbonden agent, het aantal, wie op
/// toestemming wacht (de oranje stip) en wat tooltip en VoiceOver zeggen, in het Engels en Nederlands.
@MainActor @Suite struct MenuAgentsSummaryTests {
    private let approved: Set<String> = ["claude-code"]

    private func summary(_ names: [String?]) -> MenuAgentsSummary {
        let sessions = names.map { MCPSession(id: UUID(), clientName: $0, connectedSince: .now) }
        return MenuAgentsSummary(sessions: sessions, isApproved: approved.contains)
    }

    private func language(_ code: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func `Without agents the button is not there`() {
        let none = summary([])

        #expect(!none.isVisible)
        #expect(none.count == 0)
        #expect(!none.isWaiting)
    }

    @Test func `One approved agent shows the count without the waiting dot`() throws {
        let one = summary(["claude-code"])

        #expect(one.isVisible)
        #expect(one.count == 1)
        #expect(!one.isWaiting)
        #expect(one.label(bundle: try language("en")) == "1 agent connected")
        #expect(one.label(bundle: try language("nl")) == "1 agent verbonden")
    }

    @Test func `Two approved agents are counted`() throws {
        let two = summary(["claude-code", "claude-code"])

        #expect(two.label(bundle: try language("en")) == "2 agents connected")
        #expect(two.label(bundle: try language("nl")) == "2 agents verbonden")
    }

    @Test func `An agent that waits for approval shows the dot and says so`() throws {
        let three = summary(["claude-code", "codex-mcp-client", nil])

        #expect(three.count == 3)
        #expect(three.waitingCount == 1)
        #expect(three.isWaiting)
        #expect(three.agents.map(\.isWaiting) == [false, true, false])
        #expect(three.label(bundle: try language("en")) == "1 agent waiting for approval")
        #expect(three.label(bundle: try language("nl")) == "1 agent wacht op toestemming")
    }

    @Test func `An agent that is still connecting does not wait yet`() {
        let connecting = summary([nil])

        #expect(connecting.isVisible)
        #expect(!connecting.isWaiting)
    }
}

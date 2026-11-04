import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// `get_status` en `get_agent_brief` over de fixtures.
@Suite struct StatusAndBriefToolsTests {
    let harness = ToolHarness()

    // MARK: - get_status

    @Test func `Status lists accounts as name and host with their poll state`() async throws {
        let output = try await harness.output("get_status")

        #expect(output["accounts"] == [
            [
                "id": .string(FakeDataSource.gitHubId.uuidString), "service": "GitHub", "name": "@octo", "host": "github.com",
                "state": "ok", "last_poll": "2026-11-04T09:00:00Z",
            ],
            [
                "id": .string(FakeDataSource.gitLabId.uuidString), "service": "GitLab", "name": "group", "host": "gitlab.example.com",
                "state": "failed", "failing_since": "2026-11-03T10:00:00Z", "error": "Token invalid or expired",
            ],
        ])
        #expect(output["last_successful_poll"] == "2026-11-04T09:00:00Z")
        #expect(output["sync"] == ["state": "idle"])
        #expect(output["version_check_at"] == "2026-11-03T10:00:00Z")
        #expect(output["sources_off"] == [["source": "pyPI", "name": "PyPI", "message": "Not checked: source PyPI is off."]])
        #expect(output["followed_repositories"] == 3)
        #expect(output["unread_pull_requests"] == 6)
        #expect(output["unread_tags"] == 2)
    }

    @Test func `Status shows a paused account and what is syncing`() async throws {
        var harness = harness
        harness.source.accountList[1].isPaused = true
        harness.source.sync = .syncing(done: 2, total: 5, what: .versions)

        let output = try await harness.output("get_status")

        #expect(output["accounts"]?.objects.last?["state"] == "paused")
        #expect(output["sync"] == ["state": "syncing", "work": "versions", "done": 2, "total": 5])
    }

    // MARK: - get_agent_brief

    @Test(arguments: GetAgentBriefSection.allCases)
    func `Every section gives the same brief as Copy for agent`(section: GetAgentBriefSection) async throws {
        let output = try await harness.output("get_agent_brief", ["repo": "acme/web", "section": .string(section.rawValue)])

        let markdown = try #require(output["markdown"]?.stringValue)
        #expect(markdown.hasPrefix("## Pullwatch: \(section.title)\n\nRepository: acme/web (https://github.com/acme/web)"))
        #expect(markdown.contains("\nTask: "))
        #expect(output["section"] == .string(section.rawValue))
    }

    @Test func `The check brief is AgentBrief's own text`() async throws {
        let source = harness.source
        let summary = try #require(await source.repoSummaries().first { $0.repo == "acme/web" })
        let versions = try #require(summary.versions)
        let expected = AgentBrief.vulnerabilities(
            AgentBrief.Repository(name: "acme/web", url: URL(string: "https://github.com/acme/web"), checkedAt: FakeDataSource.checkedAt),
            versions: versions, advisories: summary.advisories, advisoryDetailsOff: false,
            context: await source.updateContext(for: versions)
        )

        let output = try await harness.output("get_agent_brief", ["repo": "acme/web", "section": "check"])

        #expect(output["markdown"] == .string(expected))
    }

    @Test func `A brief notes a source that is off`() async throws {
        let output = try await harness.output("get_agent_brief", ["repo": "group/app", "section": "packages"])

        #expect(output["markdown"]?.stringValue?.contains("Not checked: source PyPI was switched off.") == true)
    }

    @Test func `A brief for a repository that is not followed is a tool error`() async throws {
        let message = try await harness.error("get_agent_brief", ["repo": "acme/old", "section": "check"])

        #expect(message == "Repository acme/old is not followed in Pullwatch. list_repositories lists the repositories you can ask about.")
    }

    @Test func `A packages brief for a workspace that does not exist names the ones that do`() async throws {
        let message = try await harness.error("get_agent_brief", ["repo": "acme/web", "section": "packages", "workspace": "apps/site"])

        #expect(message == "acme/web has no workspace \"apps/site\" with packages. Workspaces: \"\" (root).")
    }
}

/// De kopjes van `get_agent_brief` met de titel van hun opdracht.
enum GetAgentBriefSection: String, CaseIterable, Sendable {
    case pullRequests = "pull_requests"
    case pullRequestsPerMonth = "pull_requests_per_month"
    case check
    case packageUpdates = "package_updates"
    case packages
    case security

    var title: String {
        switch self {
        case .pullRequests: "pull requests"
        case .pullRequestsPerMonth: "pull requests per month"
        case .check: "check (runtimes and vulnerabilities)"
        case .packageUpdates: "packages with a new version"
        case .packages: "packages"
        case .security: "security on GitHub"
        }
    }
}

import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

@testable import Pullwatch

/// De adapter van de app voor de MCP-tools: met vaste waarden in plaats van de modellen geeft
/// `get_status` en `list_pull_requests` wat de app weet, elke aanroep opnieuw gelezen, en nergens
/// een token. Geen echte modellen, dus geen bestanden of Keychain.
@MainActor @Suite struct AppMCPDataSourceTests {
    static let secret = "fake-token-never-shared-4c1d"
    static let gitHubId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let gitLabId = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let now = Date(timeIntervalSince1970: 1_793_000_000)

    /// Wat de "modellen" nu bevatten; de adapter leest het bij elke aanroep.
    @MainActor final class Models {
        var config = AppConfig(
            accounts: [
                Account(
                    id: AppMCPDataSourceTests.gitHubId, kind: .gitHub, organization: "acme", authMethod: .gitHubApp, login: "octo",
                    repoWatch: ["acme/web": WatchSet(prs: true, tags: true)], cliUser: AppMCPDataSourceTests.secret
                ),
                Account(
                    id: AppMCPDataSourceTests.gitLabId, kind: .gitLab, organization: "group", authMethod: .pat,
                    repoWatch: ["group/app": .prs],
                    instanceURL: URL(string: "https://oauth2:\(AppMCPDataSourceTests.secret)@gitlab.example.com")
                ),
            ],
            disabledSources: [.pyPI]
        )
        var history = History()
        var states: [UUID: AccountState] = [AppMCPDataSourceTests.gitHubId: .ok(lastPoll: AppMCPDataSourceTests.now)]
        var reads = 0
    }

    let models = Models()
    let registry: MCPToolRegistry

    init() throws {
        let models = models
        models.history.add(pullRequests: [Self.pr(1, title: "Add login"), Self.pr(2, title: "Fix crash")], tags: [], at: Self.now)
        let source = AppMCPDataSource(AppMCPDataSource.Reads(
            config: {
                models.reads += 1
                return models.config
            },
            historyItems: { models.history.items },
            currentUserIds: { [Self.gitHubId: "1001"] },
            repoSummaries: { RepoOverview.summaries(accounts: models.config.accounts, report: nil, history: models.history) },
            versionReport: { nil },
            updateContext: { UpdateContext(repo: $0, metadata: [:]) },
            activityStats: { period, filter in
                var cache = ActivityStatsCache()
                return cache.stats(history: models.history, period: period, filter: filter, now: Self.now)
            },
            accountStates: { models.states },
            lastSuccessfulPoll: { Self.now },
            syncStatus: { .idle }
        ))
        registry = try PullwatchMCPTools.registry(dataSource: source)
    }

    static func pr(_ number: Int, title: String) -> PullRequest {
        PullRequest(
            accountId: gitHubId, repo: "acme/web", number: number, title: title, authorId: "1001", authorName: "octo",
            isDraft: false, createdAt: now.addingTimeInterval(TimeInterval(-number) * 3600),
            webURL: URL(string: "https://github.com/acme/web/pull/\(number)")!,
            checks: .counts(CheckCounts(passed: 3, failed: number == 1 ? 1 : 0))
        )
    }

    /// Het hele antwoord zoals het over de draad gaat.
    private func wire(_ result: CallTool.Result) throws -> String {
        String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    }

    @Test func `get_status reports the accounts, the sources that are off and no token`() async throws {
        let result = try await registry.call("get_status", arguments: [:])

        #expect(result.isError == false)
        let status = try #require(result.structuredContent?.objectValue)
        let accounts = try #require(status["accounts"]?.arrayValue)
        #expect(accounts.compactMap { $0.objectValue?["name"]?.stringValue } == ["@octo", "group"])
        #expect(accounts.compactMap { $0.objectValue?["host"]?.stringValue } == ["github.com", "gitlab.example.com"])
        #expect(status["sources_off"]?.arrayValue?.first?.objectValue?["source"] == "pyPI")
        #expect(status["unread_pull_requests"] == 2)
        let json = try wire(result)
        #expect(!json.contains(Self.secret))
        #expect(!json.contains("oauth2"))
    }

    @Test func `list_pull_requests lists the history with checks`() async throws {
        let result = try await registry.call("list_pull_requests", arguments: [:])

        #expect(result.isError == false)
        let list = try #require(result.structuredContent?.objectValue)
        #expect(list["total"] == 2)
        let prs = try #require(list["pull_requests"]?.arrayValue).compactMap(\.objectValue)
        #expect(prs.map { $0["title"] } == ["Add login", "Fix crash"])
        #expect(prs.first?["checks"]?.objectValue?["status"] == "failed")
        #expect(prs.first?["is_mine"] == true)
        #expect(!(try wire(result)).contains(Self.secret))
    }

    @Test func `Each call reads the models again, so nothing goes stale`() async throws {
        _ = try await registry.call("list_pull_requests", arguments: [:])
        models.history.add(pullRequests: [Self.pr(3, title: "New one")], tags: [], at: Self.now.addingTimeInterval(60))
        let before = models.reads

        let result = try await registry.call("list_pull_requests", arguments: [:])

        #expect(result.structuredContent?.objectValue?["total"] == 3)
        #expect(models.reads > before)
    }

    @Test func `The app gives agents the nine tools over its models`() throws {
        let names = AppModel.shared.mcpTools().map(\.name)
        #expect(names == PullwatchMCPTools.all(dataSource: AppModel.shared.mcpDataSource).map(\.name))
        #expect(names.count == 9)
        #expect(names.contains("get_status"))
    }
}

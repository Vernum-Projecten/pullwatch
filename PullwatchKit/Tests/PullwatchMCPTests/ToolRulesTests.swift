import Foundation
import MCP
import PullwatchCore
import PullwatchMCP
import Testing

/// De regels die voor elke tool gelden: alleen lezen, geen geheim in de uitvoer, alleen gevolgde
/// repo's, Engelse beschrijvingen en velden in snake_case.
@Suite struct ToolRulesTests {
    let harness = ToolHarness()

    static let names = [
        "get_status", "list_pull_requests", "get_pull_request", "list_tags", "list_repositories", "get_repository_report",
        "list_vulnerabilities", "explain_update", "get_agent_brief",
    ]

    /// Elke tool met argumenten die zoveel mogelijk uitvoer geven.
    static let calls: [(String, [String: Value])] = [
        ("get_status", [:]),
        ("list_pull_requests", ["state": "all", "limit": 100]),
        ("get_pull_request", ["repo": "acme/web", "number": 1]),
        ("list_tags", ["limit": 100]),
        ("list_repositories", ["limit": 100]),
        ("get_repository_report", ["repo": "acme/web", "limit": 100]),
        ("get_repository_report", ["repo": "group/app"]),
        ("list_vulnerabilities", ["limit": 100]),
        ("explain_update", ["repo": "acme/web", "package": "body-parser"]),
        ("get_agent_brief", ["repo": "acme/web", "section": "security"]),
        ("get_agent_brief", ["repo": "acme/web", "section": "check"]),
        ("get_agent_brief", ["repo": "group/app", "section": "packages"]),
    ]

    @Test func `The registry holds every tool, read only`() throws {
        let registry = try PullwatchMCPTools.registry(dataSource: FakeDataSource())

        #expect(registry.definitions.map(\.name) == Self.names)
        for tool in registry.definitions {
            #expect(tool.annotations.readOnlyHint == true, "\(tool.name)")
            #expect(tool.annotations.openWorldHint == false, "\(tool.name)")
            #expect((tool.description?.count ?? 0) > 150, "\(tool.name) needs a description written for a model")
        }
    }

    @Test(arguments: calls.map { "\($0.0) \($0.1)" })
    func `No output contains a token or anything from the Keychain`(call: String) async throws {
        let (name, arguments) = try #require(Self.calls.first { "\($0.0) \($0.1)" == call })

        let wire = try await harness.wire(name, arguments)

        #expect(!wire.contains(FakeDataSource.secret))
        #expect(!wire.contains("oauth2"))
        #expect(!wire.contains("gitHubApp"))
        #expect(!wire.contains("\"pat\""))
        #expect(!wire.contains("acme/old"))
    }

    @Test(arguments: names.filter { ["get_pull_request", "get_repository_report", "explain_update", "get_agent_brief", "list_pull_requests", "list_tags", "list_vulnerabilities"].contains($0) })
    func `Every tool that takes a repository refuses one that is not followed`(name: String) async throws {
        let arguments: [String: Value] = ["repo": "evil/other", "number": 1, "package": "x", "section": "check"]
        let schema = try #require(PullwatchMCPTools.all(dataSource: FakeDataSource()).first { $0.name == name }?.inputSchema.jsonSchema)
        let known = Set(schema["properties"]?.objectValue?.keys.map { $0 } ?? [])

        let message = try await harness.error(name, arguments.filter { known.contains($0.key) })

        #expect(message == "Repository evil/other is not followed in Pullwatch. list_repositories lists the repositories you can ask about.")
    }

    @Test(arguments: names)
    func `Output fields are snake_case`(name: String) throws {
        let tool = try #require(PullwatchMCPTools.all(dataSource: FakeDataSource()).first { $0.name == name })

        for key in Self.keys(of: tool.outputSchema.jsonSchema) + Self.keys(of: tool.inputSchema.jsonSchema) {
            #expect(key.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }, "\(name): \(key)")
        }
    }

    @Test func `An unknown account id is a tool error`() async throws {
        let message = try await harness.error("list_pull_requests", ["account_id": "nobody"])

        #expect(message == "No account has the id nobody. get_status lists the accounts with their ids.")
    }

    @Test func `The data source can be a main actor type, as the app's adapter will be`() async throws {
        let registry = try PullwatchMCPTools.registry(dataSource: await MainActorSource(FakeDataSource()))

        let result = try await registry.call("get_status", arguments: [:])

        #expect(result.isError == false)
    }

    /// Alle veldnamen in een JSON Schema, ook genest.
    static func keys(of schema: Value) -> [String] {
        let properties = schema["properties"]?.objectValue ?? [:]
        var keys = Array(properties.keys)
        for value in properties.values { keys += self.keys(of: value) }
        if let items = schema["items"] { keys += self.keys(of: items) }
        return keys
    }
}

/// Zoals de adapter van de app: een klasse op de main actor die de modellen leest.
@MainActor
final class MainActorSource: MCPDataSource {
    private let fake: FakeDataSource

    init(_ fake: FakeDataSource) {
        self.fake = fake
    }

    func accounts() async -> [Account] { await fake.accounts() }
    func disabledSources() async -> Set<DataSourceID> { await fake.disabledSources() }
    func historyItems() async -> [HistoryItem] { await fake.historyItems() }
    func currentUserIds() async -> [UUID: String] { await fake.currentUserIds() }
    func repoSummaries() async -> [RepoSummary] { await fake.repoSummaries() }
    func versionReport() async -> VersionReport? { await fake.versionReport() }
    func updateContext(for repo: RepoVersions) async -> UpdateContext { await fake.updateContext(for: repo) }
    func activityStats(period: StatsPeriod, filter: ActivityFilter) async -> ActivityStats { await fake.activityStats(period: period, filter: filter) }
    func accountStates() async -> [UUID: AccountState] { await fake.accountStates() }
    func lastSuccessfulPoll() async -> Date? { await fake.lastSuccessfulPoll() }
    func syncStatus() async -> SyncStatus { await fake.syncStatus() }
}

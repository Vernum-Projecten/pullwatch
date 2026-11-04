import Foundation
import MCP
import PullwatchCore

/// `list_repositories`: de gevolgde repo's met hun gezondheid en de aantallen bevindingen,
/// slechtste eerst, zoals het onderdeel Repo's.
enum ListRepositoriesTool {
    static let name = "list_repositories"

    struct SeverityCounts: Encodable {
        var critical = 0
        var high = 0
        var moderate = 0
        var low = 0
        var unknown = 0
    }

    struct Repository: Encodable {
        let repository: String
        let accountId: UUID
        let url: URL?
        let health: String
        let checked: Bool
        let checkError: String?
        let openPullRequests: Int
        let latestTag: String?
        let vulnerabilities: Int?
        let vulnerabilitiesBySeverity: SeverityCounts?
        let seriousSecurityAlerts: Int?
        let openSecrets: Int?
        let outdatedRuntimes: Int?
        let packageUpdates: Int
        let notChecked: [MCPSourceOff]
    }

    struct Output: Encodable {
        let repositories: [Repository]
        let checkedAt: Date?
        let total: Int
        let nextCursor: String?
    }

    static let healthValues = ["problem", "behind", "ok", "unknown"]

    static func make(_ source: any MCPDataSource) -> MCPTool {
        MCPTool(
            name: name,
            title: "List followed repositories",
            description: """
                Lists the repositories Pullwatch follows, worst first, with their health and counts: open pull requests, \
                known vulnerabilities by severity, serious code scanning or Advanced Security alerts, open secrets (a count, \
                never the secret), outdated runtimes and packages with a newer version. health is problem (vulnerabilities, \
                end of life or serious alerts), behind (outdated runtimes or packages), ok, or unknown (not checked yet, the \
                check failed, or a source was off; never read unknown as clean). Use it first to see what needs attention \
                and which repositories you can ask about. Filters: account_id, health. Paged with limit and cursor.
                """,
            input: .object(
                [
                    "account_id": .string("Only this account (an id from get_status).", maxLength: 64),
                    "health": .string("Only repositories with this health.", oneOf: healthValues),
                ].merging(MCPPaging.inputFields) { first, _ in first }
            ),
            output: .object(
                [
                    "repositories": .array(of: .object(
                        [
                            "repository": .string(),
                            "account_id": .string(),
                            "url": .string("The web page of the repository."),
                            "health": .string(oneOf: healthValues),
                            "checked": .boolean("Whether the version and vulnerability check has run for it; false means nothing is known yet."),
                            "check_error": .string("Why the last check failed."),
                            "open_pull_requests": .integer(),
                            "latest_tag": .string(),
                            "vulnerabilities": .integer("Known vulnerabilities (advisories) on the default branch."),
                            "vulnerabilities_by_severity": .object(
                                ["critical": .integer(), "high": .integer(), "moderate": .integer(), "low": .integer(), "unknown": .integer()],
                                required: ["critical", "high", "moderate", "low", "unknown"]
                            ),
                            "serious_security_alerts": .integer("Open critical and high alerts from code scanning or Advanced Security."),
                            "open_secrets": .integer("How many open secrets secret scanning found; the secrets themselves are never shared."),
                            "outdated_runtimes": .integer("Runtimes and frameworks that are behind or end of life."),
                            "package_updates": .integer("Packages with a newer version."),
                            "not_checked": .array(of: MCPSourceOff.schema),
                        ],
                        required: ["repository", "account_id", "health", "checked", "open_pull_requests", "package_updates", "not_checked"]
                    )),
                    "checked_at": .dateTime("When the last full version and vulnerability check ran."),
                ].merging(MCPPaging.outputFields) { first, _ in first },
                required: ["repositories", "total"]
            )
        ) { arguments in
            try await run(arguments, source: source)
        }
    }

    static func run(_ arguments: MCPArguments, source: any MCPDataSource) async throws -> MCPToolResult {
        let paging = try MCPPaging(arguments)
        let accounts = await source.accounts()
        let followed = MCPFollowedRepos(accounts: accounts, summaries: await source.repoSummaries(), history: await source.historyItems())
        let accountIds = Set(try MCPFollowedRepos.accounts(accounts, matching: arguments.string("account_id")).map(\.id))
        let health = arguments.string("health")
        let report = await source.versionReport()

        let repositories = followed.followedSummaries
            .filter { accountIds.contains($0.accountId) && (health == nil || healthText($0.health) == health) }
            .map { summary in repository(summary, account: accounts.first { $0.id == summary.accountId }) }
        let page = paging.page(repositories)
        let problems = repositories.filter { $0.health == "problem" }.count
        let unknown = repositories.filter { $0.health == "unknown" }.count
        let summary = "\(MCPToolOutput.count(repositories.count, "repository", "repositories")): \(problems) with problems, \(unknown) unknown."
        let output = Output(repositories: page.items, checkedAt: report?.checkedAt, total: repositories.count, nextCursor: page.nextCursor)
        return try MCPToolOutput.result(output, summary: summary)
    }

    static func healthText(_ health: RepoHealth) -> String {
        switch health {
        case .problem: "problem"
        case .behind: "behind"
        case .ok: "ok"
        case .unknown: "unknown"
        }
    }

    private static func repository(_ summary: RepoSummary, account: Account?) -> Repository {
        let versions = summary.versions
        var counts: SeverityCounts?
        if let versions, versions.error == nil, !versions.isUnchecked(.osv), versions.vulnerabilityError == nil {
            var tally = SeverityCounts()
            for row in versions.vulnerabilityRows(gitHub: summary.advisories) {
                switch row.severity {
                case .critical: tally.critical += 1
                case .high: tally.high += 1
                case .moderate: tally.moderate += 1
                case .low: tally.low += 1
                case .unknown: tally.unknown += 1
                }
            }
            counts = tally
        }
        let checked = versions != nil && versions?.error == nil
        return Repository(
            repository: summary.repo, accountId: summary.accountId, url: account?.safeRepoWebURL(summary.repo),
            health: healthText(summary.health), checked: versions != nil, checkError: versions?.error,
            openPullRequests: summary.openPullRequests, latestTag: summary.latestTag,
            vulnerabilities: counts == nil ? nil : versions?.advisoryCount,
            vulnerabilitiesBySeverity: counts,
            seriousSecurityAlerts: checked && versions?.security != nil ? summary.seriousSecurityAlerts.count : nil,
            openSecrets: checked ? versions?.security?.secretCount : nil,
            outdatedRuntimes: checked ? versions?.outdatedComponents.count : nil,
            packageUpdates: summary.packageUpdates.count,
            notChecked: versions.map { MCPSourceOff.skipped($0) } ?? []
        )
    }
}

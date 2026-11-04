import Foundation
import MCP
import PullwatchCore

/// `get_status`: de accounts (naam en host, nooit een token), hoe hun laatste poll ging, wat er
/// nu loopt, wanneer de versiecheck was en welke bronnen uit staan.
enum GetStatusTool {
    static let name = "get_status"

    struct AccountStatus: Encodable {
        let id: UUID
        let service: String
        let name: String
        let host: String
        let state: String
        let lastPoll: Date?
        let failingSince: Date?
        let error: String?
    }

    struct Sync: Encodable {
        let state: String
        let work: String?
        let done: Int?
        let total: Int?
    }

    struct SourceOff: Encodable {
        let source: String
        let name: String
        let message: String
    }

    struct Output: Encodable {
        let accounts: [AccountStatus]
        let lastSuccessfulPoll: Date?
        let sync: Sync
        let versionCheckAt: Date?
        let sourcesOff: [SourceOff]
        let followedRepositories: Int
        let unreadPullRequests: Int
        let unreadTags: Int
    }

    static func make(_ source: any MCPDataSource) -> MCPTool {
        MCPTool(
            name: name,
            title: "Get Pullwatch status",
            description: """
                Returns Pullwatch's state: the accounts it follows (id, service, name and host; never a token), whether \
                their last poll worked, the last successful poll, what is syncing now, when the last version and \
                vulnerability check ran, which data sources are switched off in Settings (anything from those is not \
                checked, never clean), and how many repositories are followed and items unread. Use it first to see how \
                fresh the data is, and to find the account_id other tools take.
                """,
            output: .object(
                [
                    "accounts": .array(of: .object(
                        AccountStatus.fields, required: ["id", "service", "name", "host", "state"]
                    )),
                    "last_successful_poll": .dateTime("The last poll in which at least one account worked."),
                    "sync": .object(
                        [
                            "state": .string(oneOf: ["idle", "syncing", "failed"]),
                            "work": .string("What is syncing.", oneOf: ["accounts", "first_sync", "refetch", "versions", "repo_check"]),
                            "done": .integer(), "total": .integer("0 while the total is not known yet."),
                        ],
                        required: ["state"]
                    ),
                    "version_check_at": .dateTime("When the last full version and vulnerability check ran."),
                    "sources_off": .array(of: .object(
                        [
                            "source": .string(oneOf: DataSourceID.allCases.map(\.rawValue)), "name": .string(),
                            "message": .string(),
                        ],
                        required: ["source", "name", "message"]
                    ), "Data sources switched off in Settings, Sources."),
                    "followed_repositories": .integer(),
                    "unread_pull_requests": .integer(),
                    "unread_tags": .integer(),
                ],
                required: ["accounts", "sync", "sources_off", "followed_repositories", "unread_pull_requests", "unread_tags"]
            )
        ) { arguments in
            try await run(arguments, source: source)
        }
    }

    static func run(_ arguments: MCPArguments, source: any MCPDataSource) async throws -> MCPToolResult {
        let accounts = await source.accounts()
        let states = await source.accountStates()
        let history = await source.historyItems()
        let followed = MCPFollowedRepos(accounts: accounts, summaries: await source.repoSummaries(), history: history)
        let disabled = await source.disabledSources()
        let english = SourcesOverview.bundle(for: Locale(identifier: "en"))

        let statuses = accounts.map { account in
            let info = MCPAccountInfo(account)
            var state = "not_polled_yet"
            var lastPoll: Date?
            var since: Date?
            var error: String?
            switch states[account.id] {
            case .ok(let date):
                state = "ok"
                lastPoll = date
            case .failed(let failure, let date):
                state = "failed"
                since = date
                error = failure.userMessage(bundle: english)
            case .idle, nil:
                break
            }
            if account.isPaused { state = "paused" }
            return AccountStatus(
                id: info.id, service: info.service, name: info.name, host: info.host, state: state, lastPoll: lastPoll,
                failingSince: since, error: error
            )
        }
        let sourcesOff = DataSource.all.map(\.id).filter(disabled.contains).map {
            SourceOff(source: $0.rawValue, name: MCPSourceOff.name($0), message: MCPSourceOff($0).message)
        }
        let isFollowed = { (item: HistoryItem) in followed.contains(accountId: item.entry.accountId, repo: item.entry.repo) }
        let output = Output(
            accounts: statuses, lastSuccessfulPoll: await source.lastSuccessfulPoll(), sync: sync(await source.syncStatus()),
            versionCheckAt: await source.versionReport()?.checkedAt, sourcesOff: sourcesOff,
            followedRepositories: followed.followedSummaries.count,
            unreadPullRequests: history.filter { $0.entry.kind == .pullRequest && !$0.isRead && isFollowed($0) }.count,
            unreadTags: history.filter { $0.entry.kind == .tag && !$0.isRead && isFollowed($0) }.count
        )
        let failing = statuses.filter { $0.state == "failed" }.count
        var summary = "\(MCPToolOutput.count(accounts.count, "account")) (\(failing) failing), \(output.followedRepositories) followed repositories"
        summary += sourcesOff.isEmpty ? "." : "; sources off: \(sourcesOff.map(\.name).joined(separator: ", "))."
        return try MCPToolOutput.result(output, summary: summary)
    }

    private static func sync(_ status: SyncStatus) -> Sync {
        switch status {
        case .idle:
            return Sync(state: "idle", work: nil, done: nil, total: nil)
        case .failed:
            return Sync(state: "failed", work: nil, done: nil, total: nil)
        case .syncing(let done, let total, let what):
            let work = switch what {
            case .accounts: "accounts"
            case .firstSync: "first_sync"
            case .refetch: "refetch"
            case .versions: "versions"
            case .repoCheck: "repo_check"
            }
            return Sync(state: "syncing", work: work, done: done, total: total)
        }
    }
}

extension GetStatusTool.AccountStatus {
    static let fields: [String: MCPSchema] = MCPAccountInfo.fields.merging([
        "state": .string("How the last poll went; paused means the account is switched off.", oneOf: ["ok", "failed", "not_polled_yet", "paused"]),
        "last_poll": .dateTime("The last successful poll."),
        "failing_since": .dateTime("Since when polling fails."),
        "error": .string("Why polling fails."),
    ]) { first, _ in first }
}

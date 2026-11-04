import Foundation
import PullwatchCore
import PullwatchMCP

/// Wat de MCP-tools lezen, uit de modellen van de app: elke vraag leest het model op dat moment,
/// zodat een agent precies ziet wat de vensters tonen, zonder kopie die veroudert. Niets hier
/// raakt een token of de Keychain. De tests geven vaste waarden mee (`Reads`), zodat ze geen
/// echte modellen of bestanden nodig hebben.
final class AppMCPDataSource: MCPDataSource {
    /// Waar elke vraag gelezen wordt.
    struct Reads: Sendable {
        /// `AccountsModel.config`: accounts en bronnen die uit staan.
        var config: @MainActor () -> AppConfig
        /// `HistoryModel.history.items`.
        var historyItems: @MainActor () -> [HistoryItem]
        /// `PollEngine.currentUserIds()`.
        var currentUserIds: @MainActor () async -> [UUID: String]
        /// `OverviewModel.repoSummaries`.
        var repoSummaries: @MainActor () -> [RepoSummary]
        /// `VersionsModel.versionReport`: het getoonde rapport, zonder bronnen die uit staan.
        var versionReport: @MainActor () -> VersionReport?
        /// `VersionsModel.updateContext(for:)`.
        var updateContext: @MainActor (RepoVersions) -> UpdateContext
        /// `HistoryModel.activityStats(period:filter:)`.
        var activityStats: @MainActor (StatsPeriod, ActivityFilter) -> ActivityStats
        /// `PollingModel.statuses`.
        var accountStates: @MainActor () -> [UUID: AccountState]
        /// `PollingModel.lastSuccessfulPoll`.
        var lastSuccessfulPoll: @MainActor () -> Date?
        /// `AppModel.syncStatus`.
        var syncStatus: @MainActor () -> SyncStatus
    }

    private let reads: Reads

    init(_ reads: Reads) {
        self.reads = reads
    }

    /// Over de modellen van de app. `syncStatus` komt van `AppModel`, dat de modellen samen leest.
    convenience init(
        accounts: AccountsModel, history: HistoryModel, overview: OverviewModel, versions: VersionsModel,
        polling: PollingModel, engine: PollEngine, syncStatus: @escaping @MainActor () -> SyncStatus
    ) {
        self.init(Reads(
            config: { accounts.config },
            historyItems: { history.history.items },
            currentUserIds: { await engine.currentUserIds() },
            repoSummaries: { overview.repoSummaries },
            versionReport: { versions.versionReport },
            updateContext: { versions.updateContext(for: $0) },
            activityStats: { history.activityStats(period: $0, filter: $1) },
            accountStates: { polling.statuses },
            lastSuccessfulPoll: { polling.lastSuccessfulPoll },
            syncStatus: syncStatus
        ))
    }

    // MARK: - MCPDataSource

    func accounts() async -> [Account] { await reads.config().accounts }
    func disabledSources() async -> Set<DataSourceID> { await reads.config().disabledSources }
    func historyItems() async -> [HistoryItem] { await reads.historyItems() }
    func currentUserIds() async -> [UUID: String] { await reads.currentUserIds() }
    func repoSummaries() async -> [RepoSummary] { await reads.repoSummaries() }
    func versionReport() async -> VersionReport? { await reads.versionReport() }
    func updateContext(for repo: RepoVersions) async -> UpdateContext { await reads.updateContext(repo) }
    func activityStats(period: StatsPeriod, filter: ActivityFilter) async -> ActivityStats { await reads.activityStats(period, filter) }
    func accountStates() async -> [UUID: AccountState] { await reads.accountStates() }
    func lastSuccessfulPoll() async -> Date? { await reads.lastSuccessfulPoll() }
    func syncStatus() async -> SyncStatus { await reads.syncStatus() }
}

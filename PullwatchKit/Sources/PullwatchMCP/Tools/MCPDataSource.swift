public import Foundation
public import PullwatchCore

/// Wat de MCP-tools van Pullwatch lezen: alleen wat de app al heeft opgehaald, als waarden uit
/// PullwatchCore. De app levert dit uit zijn modellen (op de main actor, dus `async`); de tests
/// uit fixtures. Er is bewust geen token, Keychain-item of geheim te vragen: wat hier niet in
/// staat, kan geen tool laten uitlekken.
public protocol MCPDataSource: Sendable {
    /// De accounts uit de instellingen (`AppConfig.accounts`). Een `Account` heeft geen token
    /// (die staan in de Keychain); de tools tonen er alleen naam, dienst en host van.
    func accounts() async -> [Account]

    /// De bronnen die in Instellingen, Bronnen uit staan (`AppConfig.disabledSources`).
    func disabledSources() async -> Set<DataSourceID>

    /// De geschiedenis van PR's en tags met gelezen of niet (`HistoryModel.history.items`).
    func historyItems() async -> [HistoryItem]

    /// Wie elk account bij zijn dienst is (`PollEngine.currentUserIds()`), om eigen PR's te
    /// herkennen; een account zonder poll ontbreekt.
    func currentUserIds() async -> [UUID: String]

    /// Per repo alles wat Pullwatch weet (`OverviewModel.repoSummaries`), slechtste eerst.
    func repoSummaries() async -> [RepoSummary]

    /// Het versierapport zoals de schermen het tonen, zonder wat van bronnen kwam die nu uit
    /// staan (`VersionsModel.versionReport`); nil zolang er nooit een check was.
    func versionReport() async -> VersionReport?

    /// Wat de update van een package of de oplossing van een kwetsbaarheid in `repo` tegenhoudt
    /// (`VersionsModel.updateContext(for:)`).
    func updateContext(for repo: RepoVersions) async -> UpdateContext

    /// PR-statistieken voor de opdracht "pull requests per month" (`HistoryModel.activityStats`).
    func activityStats(period: StatsPeriod, filter: ActivityFilter) async -> ActivityStats

    /// Hoe de laatste poll per account ging (`PollingModel.statuses`).
    func accountStates() async -> [UUID: AccountState]

    /// Per account de gevolgde repo's die het token niet kan lezen (`PollingModel.unreachableRepos`);
    /// hun tags en branches worden niet bijgewerkt.
    func unreachableRepos() async -> [UUID: UnreachableRepos]

    /// De laatste poll waarin minstens één account slaagde (`PollingModel.lastSuccessfulPoll`).
    func lastSuccessfulPoll() async -> Date?

    /// Wat Pullwatch nu ophaalt (`AppModel.syncStatus`).
    func syncStatus() async -> SyncStatus
}

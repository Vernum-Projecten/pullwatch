import Foundation
import Observation
import PullwatchCore

/// Het overzicht dat de zijbalk, de lijsten en de repo-pagina's lezen: per repo een samenvatting,
/// en de projecten en tellers van de zijbalk. Bewaard en alleen opnieuw berekend als de
/// instellingen, de geschiedenis of het versierapport verandert, want de views lezen het bij
/// elke schermupdate.
@Observable
final class OverviewModel {
    private(set) var repoSummaries: [RepoSummary] = []
    /// Zelfde als `repoSummaries`, op `RepoSummary.id`, voor pagina's die één repo tonen.
    private(set) var repoSummariesById: [String: RepoSummary] = [:]
    /// Projecten en tellers van de zijbalk.
    private(set) var sidebar = SidebarContent()
    /// Accountnamen op id, voor projectnamen die bij twee accounts voorkomen.
    private(set) var accountNames: [UUID: String] = [:]

    @ObservationIgnored private let accounts: AccountsModel
    @ObservationIgnored private let history: HistoryModel
    @ObservationIgnored private let versions: VersionsModel

    init(accounts: AccountsModel, history: HistoryModel, versions: VersionsModel) {
        self.accounts = accounts
        self.history = history
        self.versions = versions
        recomputeRepoSummaries()
    }

    /// `RepoSummary.id` van een repo uit de geschiedenis (de naam kan in hoofdletters verschillen).
    func repoId(accountId: UUID, repo: String) -> String {
        RepoOverview.repoId(in: repoSummaries, accountId: accountId, repo: repo)
    }

    /// Na een wijziging van instellingen, geschiedenis of rapport.
    func recomputeRepoSummaries() {
        repoSummaries = RepoOverview.summaries(
            accounts: accounts.config.accounts, report: versions.versionReport, history: history.history,
            packageSummaries: versions.packageSummaries
        )
        repoSummariesById = Dictionary(repoSummaries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        recomputeSidebar()
    }

    /// Na een wijziging van wat je in Afhankelijkheden gezien hebt: alleen de tellers.
    func recomputeSidebar() {
        let config = accounts.config
        let history = history.history
        let names = Dictionary(config.accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        if names != accountNames { accountNames = names }
        let content = SidebarContent(
            pullRequestGroups: history.groups(.pullRequest, accountNames: names),
            tagGroups: history.groups(.tag, accountNames: names),
            repoGroups: RepoOverview.groups(repoSummaries, accountNames: names),
            badges: [
                .pullRequests: history.unreadCount(.pullRequest),
                .tags: history.unreadCount(.tag),
                .repos: repoSummaries.filter { $0.health == .problem }.count,
                // Alleen wat je nu kunt nemen, en wat een kwetsbaarheid oplost.
                .dependencies: PackageVersions.badgeCount(
                    versions.packageSummaries, seen: versions.seenPackageVersions,
                    securityFixes: versions.versionReport?.packagesWithSecurityFixes ?? []
                ),
            ]
        )
        // Alleen bij een echte wijziging, zodat de zijbalk niet bij elke poll opnieuw tekent.
        if content != sidebar { sidebar = content }
    }
}

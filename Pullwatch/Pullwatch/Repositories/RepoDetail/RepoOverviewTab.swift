import AppKit
import PullwatchCore
import SwiftUI

/// Het tabblad Overzicht van de repo-pagina: status, pull requests, activiteit en wat er gevolgd wordt.
struct RepoOverviewTab: View {
    @Environment(AppModel.self) private var app
    @Environment(AccountsModel.self) private var accounts
    @Environment(HistoryModel.self) private var historyModel
    @Environment(VersionsModel.self) private var versions
    @Environment(AppRouter.self) private var router
    let summary: RepoSummary
    let account: Account?

    private var historyRepo: HistoryRepo { HistoryRepo(accountId: summary.accountId, repo: summary.repo) }

    private var pullRequests: [HistoryItem] { RepoBriefs.pullRequests(of: summary, in: historyModel.history) }

    private var briefs: RepoBriefs {
        RepoBriefs(summary: summary, account: account, accounts: accounts, versions: versions, history: historyModel)
    }

    var body: some View {
        Form {
            RepoOverviewSection(
                health: summary.health,
                accountName: account?.displayName,
                latestTag: summary.latestTag,
                checkedAt: summary.versions == nil ? nil : versions.versionReport?.checkedAt
            )
            RepoPullRequestsSection(
                items: pullRequests,
                providerKind: account?.kind,
                openCount: summary.openPullRequests,
                showsChecks: accounts.config.isEnabled(.ciChecks),
                open: { historyModel.open($0) },
                showAll: { router.showHistory($0, repo: historyRepo) },
                brief: { briefs.pullRequests() }
            )
            Section {
                ActivityChart(
                    stats: historyModel.activityStats(period: .month, filter: ActivityFilter(repoId: summary.id)),
                    period: .month
                )
                .frame(height: 140)
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("PR's per maand")
                    Spacer()
                    AgentBriefButton { briefs.pullRequestsPerMonth() }
                }
            }
            if let account {
                RepoWatchSection(watch: Bindable(app)[watch: summary.repo, account: account.id])
            }
        }
        .formStyle(.grouped)
    }
}

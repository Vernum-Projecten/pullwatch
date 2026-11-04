import Charts
import PullwatchCore
import SwiftUI

extension StatsPeriod {
    var title: LocalizedStringResource {
        switch self {
        case .week: "Week"
        case .month: "Maand"
        case .year: "Jaar"
        }
    }

    var unit: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// Om de hoeveel periodes een label op de as komt: twaalf weken passen niet naast elkaar.
    var axisStride: Int {
        switch self {
        case .week: 2
        case .month, .year: 1
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .week: .dateTime.day().month(.abbreviated)
        case .month: .dateTime.month(.abbreviated)
        case .year: .dateTime.year()
        }
    }
}

/// PR-activiteit over alle gevolgde repo's (of één repo): per periode, per auteur en per repo.
struct StatsView: View {
    @Environment(AccountsModel.self) private var accounts
    @Environment(HistoryModel.self) private var historyModel
    @Environment(OverviewModel.self) private var overview
    @Environment(AppRouter.self) private var router
    /// Alleen deze repo (`RepoSummary.id`), vanaf de repo-pagina; nil voor alles.
    var repoId: String? = nil

    @AppStorage("statsPeriod") private var period: StatsPeriod = .month
    @AppStorage("statsHideBots") private var hideBots = true
    @AppStorage("statsCountCoAuthors") private var countCoAuthors = false
    @State private var group: HistoryGroup.ID?
    @State private var author: String?

    private var repoSummary: RepoSummary? { repoId.flatMap { overview.repoSummariesById[$0] } }

    /// Azure DevOps noemt mergen "completed": zijn alle accounts in beeld van Azure DevOps, dan
    /// heet gemerged hier afgerond, zoals in de meldingen.
    private var saysCompleted: Bool {
        let ids: Set<UUID> =
            if let repoSummary { [repoSummary.accountId] }
            else if let group { [group.accountId] }
            else { Set(accounts.config.pollableAccounts.map(\.id)) }
        let kinds = accounts.config.accounts.filter { ids.contains($0.id) }.map(\.kind)
        return !kinds.isEmpty && kinds.allSatisfy { $0 == .azureDevOps }
    }

    var body: some View {
        let filter = ActivityFilter(group: group, author: author, repoId: repoId, hideBots: hideBots, countCoAuthors: countCoAuthors)
        let stats = historyModel.activityStats(period: period, filter: filter)
        // Auteurskeuze zonder auteursfilter, anders blijft alleen de gekozen auteur over.
        let withoutAuthor = ActivityFilter(group: group, repoId: repoId, hideBots: hideBots, countCoAuthors: countCoAuthors)
        let authors = author == nil ? stats.authors : historyModel.activityStats(period: period, filter: withoutAuthor).authors

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatTiles(stats: stats, saysCompleted: saysCompleted)
                if let author {
                    Button {
                        router.showHistory(.pullRequest, author: author, repo: repoSummary.map { HistoryRepo(accountId: $0.accountId, repo: $0.repo) })
                    } label: {
                        Label {
                            Text("Toon de PR's van \(author)")
                        } icon: {
                            ItemKind.pullRequest.glyph.image
                        }
                    }
                    .buttonStyle(.link)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("PR-activiteit").font(.headline)
                    ActivityChart(stats: stats, period: period, saysCompleted: saysCompleted)
                        .frame(height: 220)
                }
                HStack(alignment: .top, spacing: 24) {
                    RankingChart(
                        title: countCoAuthors ? "Auteurs en co-auteurs" : "Auteurs", items: Array(stats.authors.prefix(10)),
                        states: stats.authorStates, saysCompleted: saysCompleted, selected: author
                    ) { name in
                        author = author == name ? nil : name
                    }
                    if repoId == nil {
                        RankingChart(
                            title: "Drukste repo's", items: Array(stats.repos.prefix(10)),
                            states: stats.repoStates, saysCompleted: saysCompleted, selected: nil
                        ) { name in
                            if let summary = overview.repoSummaries.first(where: { $0.repo == name }) {
                                router.showRepo(id: summary.id)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text("Statistieken"))
        .navigationSubtitle(repoSummary.map { Text(verbatim: $0.repo) } ?? Text("Alle gevolgde repo's"))
        .toolbar {
            StatsToolbar(
                period: $period,
                group: $group,
                author: $author,
                hideBots: $hideBots,
                countCoAuthors: $countCoAuthors,
                groups: repoId == nil ? overview.sidebar.pullRequestGroups : [],
                authors: authors
            )
        }
    }
}

extension PRStatus {
    /// De status in één woord, voor de uitsplitsing per auteur of repo. Azure DevOps noemt
    /// gemerged afgerond.
    func stateName(saysCompleted: Bool) -> LocalizedStringResource {
        switch self {
        case .open: "Open"
        case .draft: "Draft"
        case .queued: "In wachtrij"
        case .merged: saysCompleted ? "Afgerond" : "Gemerged"
        case .closed: "Gesloten"
        }
    }
}

extension PRStateCounts {
    func count(_ status: PRStatus) -> Int {
        switch status {
        case .open: open
        case .draft: draft
        // Een PR in de rij is nog open en telt daar mee, zoals in de grafiek: geen eigen regel.
        case .queued: 0
        case .merged: merged
        case .closed: closed
        }
    }
}

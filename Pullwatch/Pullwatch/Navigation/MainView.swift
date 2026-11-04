import PullwatchCore
import SwiftUI

/// Hoofdvenster: een zijbalk met de onderdelen en hun projecten, en per keuze een
/// `NavigationStack` waar repo-pagina's en statistieken van een repo op komen.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(AccountsModel.self) private var accounts
    @Environment(OverviewModel.self) private var overview
    @Environment(AppRouter.self) private var router
    /// Laatst gekozen onderdeel van dit venster; een project kan bij de volgende start weg zijn.
    @SceneStorage("mainSection") private var storedSection: MainSection = .pullRequests

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: Bindable(router).sidebarSelection, content: overview.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            let selection = router.sidebarSelection ?? .section(storedSection)
            NavigationStack(path: Bindable(router).path) {
                SectionRoot(selection: selection)
                    .navigationDestination(for: Route.self) { route in
                        RouteView(route: route)
                    }
            }
            // Een andere keuze in de zijbalk is een nieuwe stack, met eigen zoekveld en selectie.
            .id(selection)
            // Lang werk (eerste sync, opnieuw ophalen, versiecheck) op één vaste plek, in elk onderdeel.
            .activityBar(app.syncStatus, cancel: app.cancelSync)
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            if router.sidebarSelection == nil { router.sidebarSelection = .section(storedSection) }
        }
        .onChange(of: router.mainSection) { _, section in
            storedSection = section
        }
        // "Volg een repository…" uit het menu Ga of de knoppenbalk van Repo's.
        .sheet(isPresented: Bindable(router).isWatchingRepository) {
            WatchRepositorySheet(accounts: accounts.accountsForExtraRepos) { accountId, check in
                app.addExtraRepository(check, to: accountId)
            }
        }
    }
}

/// De zijbalk: PR's, Tags en Statistieken onder Geschiedenis, Repo's en Versies onder Controle,
/// met per onderdeel de projecten om op te filteren.
struct SidebarView: View {
    @Binding var selection: SidebarItem?
    let content: SidebarContent

    @AppStorage("sidebarPullRequestsExpanded") private var pullRequestsExpanded = true
    @AppStorage("sidebarTagsExpanded") private var tagsExpanded = false
    @AppStorage("sidebarReposExpanded") private var reposExpanded = false

    var body: some View {
        List(selection: $selection) {
            Section("Geschiedenis") {
                SidebarSectionRow(section: .pullRequests, content: content, isExpanded: $pullRequestsExpanded)
                SidebarSectionRow(section: .tags, content: content, isExpanded: $tagsExpanded)
                SidebarSectionRow(section: .stats, content: content, isExpanded: .constant(false))
            }
            Section("Controle") {
                SidebarSectionRow(section: .repos, content: content, isExpanded: $reposExpanded)
                SidebarSectionRow(section: .dependencies, content: content, isExpanded: .constant(false))
            }
        }
    }
}

/// Eén onderdeel in de zijbalk, met zijn projecten eronder als die er zijn.
private struct SidebarSectionRow: View {
    let section: MainSection
    let content: SidebarContent
    @Binding var isExpanded: Bool

    private func item(for group: HistoryGroup) -> SidebarItem {
        switch section {
        case .pullRequests: .group(.pullRequest, group.id)
        case .tags: .group(.tag, group.id)
        default: .repoGroup(group.id)
        }
    }

    var body: some View {
        let groups = content.groups(section)
        if groups.isEmpty {
            SectionLabel(section: section, badge: content.badges[section] ?? 0)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(groups) { group in
                    Text(verbatim: group.name)
                        .badge(group.unreadCount)
                        .tag(item(for: group))
                }
            } label: {
                SectionLabel(section: section, badge: content.badges[section] ?? 0)
            }
        }
    }
}

private struct SectionLabel: View {
    let section: MainSection
    let badge: Int

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            section.glyph.image
        }
        .badge(badge)
        .tag(SidebarItem.section(section))
    }
}

/// De lijst van een keuze in de zijbalk, onderaan de stack.
private struct SectionRoot: View {
    @Environment(OverviewModel.self) private var overview
    let selection: SidebarItem

    var body: some View {
        let groupName = overview.sidebar.name(of: selection)
        switch selection {
        case .group(let kind, let id):
            HistoryView(kind: kind, group: id, groupName: groupName)
        case .repoGroup(let id):
            ReposView(group: id, groupName: groupName)
        case .section(let section):
            switch section {
            case .pullRequests: HistoryView(kind: .pullRequest)
            case .tags: HistoryView(kind: .tag)
            case .stats: StatsView()
            case .repos: ReposView()
            case .dependencies: PackagesView()
            }
        }
    }
}

/// Een pagina op de stack.
private struct RouteView: View {
    @Environment(OverviewModel.self) private var overview
    let route: Route

    var body: some View {
        switch route {
        case .repo(let id):
            if let summary = overview.repoSummariesById[id] {
                RepoDetailView(summary: summary)
            } else {
                ContentUnavailableView(
                    "Repo niet gevonden",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Deze repo wordt niet meer gevolgd of is nog niet gecheckt.")
                )
            }
        case .stats(let repoId):
            StatsView(repoId: repoId)
        }
    }
}

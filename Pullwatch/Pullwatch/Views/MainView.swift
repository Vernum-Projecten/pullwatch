import PullwatchCore
import SwiftUI

/// Hoofdvenster: een zijbalk met de onderdelen en hun projecten, en per keuze een
/// `NavigationStack` waar repo-pagina's en statistieken van een repo op komen.
struct MainView: View {
    @Bindable var model: AppModel
    /// Laatst gekozen onderdeel van dit venster; een project kan bij de volgende start weg zijn.
    @SceneStorage("mainSection") private var storedSection: MainSection = .pullRequests

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $model.sidebarSelection, content: model.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            let selection = model.sidebarSelection ?? .section(storedSection)
            NavigationStack(path: $model.path) {
                SectionRoot(model: model, selection: selection)
                    .navigationDestination(for: Route.self) { route in
                        RouteView(model: model, route: route)
                    }
            }
            // Een andere keuze in de zijbalk is een nieuwe stack, met eigen zoekveld en selectie.
            .id(selection)
        }
        .frame(minWidth: 900, minHeight: 520)
        .onAppear {
            if model.sidebarSelection == nil { model.sidebarSelection = .section(storedSection) }
        }
        .onChange(of: model.mainSection) { _, section in
            storedSection = section
        }    }
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
                SidebarSectionRow(section: .versions, content: content, isExpanded: .constant(false))
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
            Image(systemName: section.symbol)
        }
        .badge(badge)
        .tag(SidebarItem.section(section))
    }
}

/// De lijst van een keuze in de zijbalk, onderaan de stack.
private struct SectionRoot: View {
    let model: AppModel
    let selection: SidebarItem

    var body: some View {
        let groupName = model.sidebar.name(of: selection)
        switch selection {
        case .group(let kind, let id):
            HistoryView(model: model, kind: kind, group: id, groupName: groupName)
        case .repoGroup(let id):
            ReposView(model: model, group: id, groupName: groupName)
        case .section(let section):
            switch section {
            case .pullRequests: HistoryView(model: model, kind: .pullRequest)
            case .tags: HistoryView(model: model, kind: .tag)
            case .stats: StatsView(model: model)
            case .repos: ReposView(model: model)
            case .versions: PackagesView(model: model)
            }
        }
    }
}

/// Een pagina op de stack.
private struct RouteView: View {
    let model: AppModel
    let route: Route

    var body: some View {
        switch route {
        case .repo(let id):
            if let summary = model.repoSummariesById[id] {
                RepoDetailView(model: model, summary: summary)
            } else {
                ContentUnavailableView(
                    "Repo niet gevonden",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Deze repo wordt niet meer gevolgd of is nog niet gecheckt.")
                )
            }
        case .stats(let repoId):
            StatsView(model: model, repoId: repoId)
        }
    }
}

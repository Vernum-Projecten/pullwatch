import PullwatchCore
import SwiftUI

/// Onderdelen van het hoofdvenster, in de volgorde van de zijbalk; Instellingen staat los onderaan.
enum MainSection: String, CaseIterable, Identifiable {
    case pullRequests, tags, repos, versions, stats, settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .pullRequests: "PR's"
        case .tags: "Tags"
        case .repos: "Repo's"
        case .versions: "Versies"
        case .stats: "Statistieken"
        case .settings: "Instellingen"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .tags: "tag"
        case .repos: "folder"
        case .versions: "shippingbox"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

/// Selectie in de zijbalk: een onderdeel, of één project onder PR's, Tags of Repo's.
enum SidebarItem: Hashable {
    case section(MainSection)
    case group(ItemKind, HistoryGroup.ID)
    case repoGroup(HistoryGroup.ID)
}

/// Hoofdvenster: PR's en tags per project, repo-controle, versies en instellingen achter één zijbalk.
struct MainView: View {
    @Bindable var model: AppModel
    @AppStorage("sidebarPullRequestsExpanded") private var pullRequestsExpanded = true
    @AppStorage("sidebarTagsExpanded") private var tagsExpanded = false
    @AppStorage("sidebarReposExpanded") private var reposExpanded = false

    private var accountNames: [UUID: String] {
        Dictionary(model.config.accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    private func badge(_ section: MainSection) -> Int {
        switch section {
        case .pullRequests: model.history.unreadCount(.pullRequest)
        case .tags: model.history.unreadCount(.tag)
        case .versions: model.unseenPackageUpdates
        case .repos: model.repoSummaries.filter { $0.health == .problem }.count
        case .stats, .settings: 0
        }
    }

    private func row(_ section: MainSection) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(badge(section))
            .tag(SidebarItem.section(section))
    }

    @ViewBuilder
    private func historySection(_ section: MainSection, kind: ItemKind, isExpanded: Binding<Bool>) -> some View {
        let groups = model.history.groups(kind, accountNames: accountNames)
        if groups.isEmpty {
            row(section)
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(groups) { group in
                    Text(group.name)
                        .badge(group.unreadCount)
                        .tag(SidebarItem.group(kind, group.id))
                }
            } label: {
                row(section)
            }
        }
    }

    @ViewBuilder
    private var reposSection: some View {
        let groups = RepoOverview.groups(model.repoSummaries, accountNames: accountNames)
        if groups.isEmpty {
            row(.repos)
        } else {
            DisclosureGroup(isExpanded: $reposExpanded) {
                ForEach(groups) { group in
                    Text(group.name)
                        .badge(group.unreadCount)
                        .tag(SidebarItem.repoGroup(group.id))
                }
            } label: {
                row(.repos)
            }
        }
    }

    private var groupName: String? {
        switch model.sidebarSelection {
        case .group(let kind, let id):
            model.history.groups(kind, accountNames: accountNames).first { $0.id == id }?.name
        case .repoGroup(let id):
            RepoOverview.groups(model.repoSummaries, accountNames: accountNames).first { $0.id == id }?.name
        default:
            nil
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                historySection(.pullRequests, kind: .pullRequest, isExpanded: $pullRequestsExpanded)
                historySection(.tags, kind: .tag, isExpanded: $tagsExpanded)
                reposSection
                row(.versions)
                row(.stats)
            }
            .safeAreaInset(edge: .bottom) {
                // Vast onderaan, los van de inhoud; een eigen List zodat de selectie er hetzelfde uitziet.
                List(selection: $model.sidebarSelection) {
                    row(.settings)
                }
                .scrollDisabled(true)
                .frame(height: 36)
                .overlay(alignment: .top) { Divider() }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            switch model.sidebarSelection {
            case .group(let kind, let id):
                HistoryView(model: model, kind: kind, group: id, groupName: groupName)
            case .repoGroup(let id):
                ReposView(model: model, group: id, groupName: groupName)
            default:
                switch model.mainSection {
                case .pullRequests: HistoryView(model: model, kind: .pullRequest)
                case .tags: HistoryView(model: model, kind: .tag)
                case .repos: ReposView(model: model)
                case .versions: PackagesView(model: model)
                case .stats: StatsView(model: model)
                case .settings: SettingsView(model: model)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 520)
    }
}

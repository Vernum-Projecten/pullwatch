import PullwatchCore
import SwiftUI

/// Onderdelen van het hoofdvenster, in de volgorde van de zijbalk; Instellingen staat los onderaan.
enum MainSection: String, CaseIterable, Identifiable {
    case pullRequests, tags, repoCheck, versions, settings

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .pullRequests: "PR's"
        case .tags: "Tags"
        case .repoCheck: "Repo-controle"
        case .versions: "Versies"
        case .settings: "Instellingen"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .tags: "tag"
        case .repoCheck: "checklist"
        case .versions: "shippingbox"
        case .settings: "gearshape"
        }
    }
}

/// Selectie in de zijbalk: een onderdeel, of één project onder PR's of Tags.
enum SidebarItem: Hashable {
    case section(MainSection)
    case group(ItemKind, HistoryGroup.ID)
}

/// Hoofdvenster: PR's en tags per project, repo-controle, versies en instellingen achter één zijbalk.
struct MainView: View {
    @Bindable var model: AppModel
    @AppStorage("sidebarPullRequestsExpanded") private var pullRequestsExpanded = true
    @AppStorage("sidebarTagsExpanded") private var tagsExpanded = false

    private var accountNames: [UUID: String] {
        Dictionary(model.config.accounts.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    private func badge(_ section: MainSection) -> Int {
        switch section {
        case .pullRequests: model.history.unreadCount(.pullRequest)
        case .tags: model.history.unreadCount(.tag)
        case .versions: model.unseenPackageUpdates
        case .repoCheck, .settings: 0
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

    private var groupName: String? {
        guard case .group(let kind, let id) = model.sidebarSelection else { return nil }
        return model.history.groups(kind, accountNames: accountNames).first { $0.id == id }?.name
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                historySection(.pullRequests, kind: .pullRequest, isExpanded: $pullRequestsExpanded)
                historySection(.tags, kind: .tag, isExpanded: $tagsExpanded)
                row(.repoCheck)
                row(.versions)
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
            default:
                switch model.mainSection {
                case .pullRequests: HistoryView(model: model, kind: .pullRequest)
                case .tags: HistoryView(model: model, kind: .tag)
                case .repoCheck: VersionsView(model: model)
                case .versions: PackagesView(model: model)
                case .settings: SettingsView(model: model)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 520)
    }
}

import PullwatchCore
import SwiftUI

/// Onderdelen van het hoofdvenster, in de volgorde van de zijbalk.
enum MainSection: String, CaseIterable, Identifiable {
    case pullRequests, tags, repoCheck, versions

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .pullRequests: "PR's"
        case .tags: "Tags"
        case .repoCheck: "Repo-controle"
        case .versions: "Versies"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .tags: "tag"
        case .repoCheck: "checklist"
        case .versions: "shippingbox"
        }
    }
}

/// Hoofdvenster: PR's, tags, repo-controle en versies achter één zijbalk.
struct MainView: View {
    @Bindable var model: AppModel

    private func badge(_ section: MainSection) -> Int {
        switch section {
        case .pullRequests: model.history.unreadCount(.pullRequest)
        case .tags: model.history.unreadCount(.tag)
        case .repoCheck: 0
        case .versions: model.unseenPackageUpdates
        }
    }

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $model.mainSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(badge(section))
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch model.mainSection ?? .pullRequests {
            case .pullRequests: HistoryView(model: model, kind: .pullRequest)
            case .tags: HistoryView(model: model, kind: .tag)
            case .repoCheck: VersionsView(model: model)
            case .versions: PackagesView(model: model)
            }
        }
        .frame(minWidth: 860, minHeight: 460)
    }
}

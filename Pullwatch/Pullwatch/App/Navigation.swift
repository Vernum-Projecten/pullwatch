import PullwatchCore
import SwiftUI

/// Onderdelen van het hoofdvenster, in de volgorde van de zijbalk en van ⌘1 tot ⌘5.
enum MainSection: String, CaseIterable, Identifiable {
    case pullRequests, tags, stats, repos, versions

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .pullRequests: "PR's"
        case .tags: "Tags"
        case .stats: "Statistieken"
        case .repos: "Repo's"
        case .versions: "Versies"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .tags: "tag"
        case .stats: "chart.bar"
        case .repos: "folder"
        case .versions: "shippingbox"
        }
    }
}

/// Selectie in de zijbalk: een onderdeel, of één project onder PR's, Tags of Repo's.
enum SidebarItem: Hashable {
    case section(MainSection)
    case group(ItemKind, HistoryGroup.ID)
    case repoGroup(HistoryGroup.ID)

    /// Het onderdeel waar deze selectie bij hoort.
    var section: MainSection {
        switch self {
        case .section(let section): section
        case .group(.pullRequest, _): .pullRequests
        case .group(.tag, _): .tags
        case .repoGroup: .repos
        }
    }
}

/// Een pagina die op de `NavigationStack` van het zichtbare onderdeel komt; de terugknop van het
/// systeem (en ⌘[) haalt hem er weer af.
enum Route: Hashable {
    /// De pagina van één repo (`RepoSummary.id`).
    case repo(String)
    /// Statistieken van één repo (`RepoSummary.id`).
    case stats(repoId: String)
}

/// Filter op PR's of Tags dat vanaf een andere plek komt (een auteur uit Statistieken, een repo-pagina);
/// staat als token in het zoekveld en gaat weg zoals elke token.
enum HistoryToken: Hashable, Identifiable {
    case author(String)
    case repo(HistoryRepo)

    var id: Self { self }
}

/// Wat de zijbalk toont: de projecten per onderdeel en de tellers. Het model houdt het bij als
/// geschiedenis, config of repo-overzicht verandert, zodat de zijbalk niets hoeft te rekenen.
struct SidebarContent: Equatable {
    var pullRequestGroups: [HistoryGroup] = []
    var tagGroups: [HistoryGroup] = []
    var repoGroups: [HistoryGroup] = []
    var badges: [MainSection: Int] = [:]

    func groups(_ section: MainSection) -> [HistoryGroup] {
        switch section {
        case .pullRequests: pullRequestGroups
        case .tags: tagGroups
        case .repos: repoGroups
        case .stats, .versions: []
        }
    }

    /// Naam van een project uit de zijbalk, voor de titel van de lijst.
    func name(of item: SidebarItem) -> String? {
        switch item {
        case .section: nil
        case .group(let kind, let id): groups(kind == .pullRequest ? .pullRequests : .tags).first { $0.id == id }?.name
        case .repoGroup(let id): repoGroups.first { $0.id == id }?.name
        }
    }
}

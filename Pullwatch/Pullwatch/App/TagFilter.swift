import PullwatchCore
import SwiftUI

// Waarden voor sorteren en tonen, geen UI-state: buiten de main actor bruikbaar (KeyPathComparator).
nonisolated extension HistoryItem {
    /// Sorteersleutel voor de kolom Auteur; zonder auteur achteraan.
    var authorSortKey: String { entry.author ?? "\u{10FFFF}" }

    /// Sorteersleutel voor de kolom met checks: mislukt eerst, dan bezig, geslaagd en zonder checks.
    var checksSortKey: Int {
        switch entry.checks?.state {
        case .failed: 0
        case .pending: 1
        case .passed: 2
        case nil: 3
        }
    }

    /// Sorteersleutel voor de icoonkolom: eerst de soort (PR's voor tags), dan de status.
    var glyphSortKey: Int {
        switch entry.prStatus {
        case .open: 0
        case .queued: 1
        case .draft: 2
        case .merged: 3
        case .closed: 4
        case nil: 5
        }
    }
}

/// Welke tags de lijst toont: alles, alleen die met een release (ook pre-releases) of alleen
/// die zonder.
enum TagFilter: String, CaseIterable, Identifiable {
    case all, releases, withoutRelease

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: "Alles"
        case .releases: "Alleen releases"
        case .withoutRelease: "Tags zonder release"
        }
    }
}

nonisolated extension TagFilter {
    func includes(_ entry: HistoryEntry) -> Bool {
        switch self {
        case .all: true
        case .releases: entry.release != nil
        case .withoutRelease: entry.kind == .tag && entry.release == nil
        }
    }
}

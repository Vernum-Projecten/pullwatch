import Foundation

/// Sorteert de kolom Repo: op de naam die de kolom toont (bij een PR de korte naam, bij een tag de
/// repo voluit), dan op de repo voluit zodat twee repo's met dezelfde korte naam niet door elkaar
/// lopen, en binnen een repo op nummer. Zo staan de PR's van één repo bij elkaar, `#9` voor `#10`.
public struct RepoSortKey: Comparable, Sendable {
    public let name: String
    public let repo: String
    /// Het PR-nummer; 0 voor een tag.
    public let number: Int

    public init(_ entry: HistoryEntry) {
        repo = entry.repo
        switch entry {
        case .pullRequest(let pr):
            name = PullRequest.shortName(of: pr.repo)
            number = pr.number
        case .tag:
            name = entry.repo
            number = 0
        }
    }

    /// Gelijk zoals de volgorde het ziet, zodat `==` en `<` het eens zijn.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let byName = lhs.name.localizedStandardCompare(rhs.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        let byRepo = lhs.repo.localizedStandardCompare(rhs.repo)
        if byRepo != .orderedSame { return byRepo == .orderedAscending }
        return lhs.number < rhs.number
    }
}

extension HistoryEntry {
    /// Voor de kolom Repo (`RepoSortKey`).
    public var repoSortKey: RepoSortKey { RepoSortKey(self) }
}

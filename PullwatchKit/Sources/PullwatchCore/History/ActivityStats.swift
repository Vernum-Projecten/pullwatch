import Foundation

public enum StatsPeriod: String, CaseIterable, Sendable {
    case week, month, year

    /// Aantal periodes in de grafiek, de huidige als laatste.
    var bucketCount: Int {
        switch self {
        case .week: 12
        case .month: 12
        case .year: 5
        }
    }

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

/// Welke PR's meetellen. Leeg filter = alles behalve bots.
public struct ActivityFilter: Hashable, Sendable {
    public var group: HistoryGroup.ID?
    public var author: String?
    /// `RepoSummary.id` ("<accountId>/<repo>") voor de grafiek op een repo-pagina.
    public var repoId: String?
    public var hideBots: Bool
    /// Co-auteurs tellen mee als auteur: in de ranglijst, de actieve auteurs en het auteursfilter
    /// telt een PR dan voor iedereen die eraan meewerkte.
    public var countCoAuthors: Bool

    public init(
        group: HistoryGroup.ID? = nil, author: String? = nil, repoId: String? = nil, hideBots: Bool = true,
        countCoAuthors: Bool = false
    ) {
        self.group = group
        self.author = author
        self.repoId = repoId
        self.hideBots = hideBots
        self.countCoAuthors = countCoAuthors
    }

    /// Wie er voor deze PR meetelt: de auteur, en met `countCoAuthors` ook de co-auteurs.
    func people(of pr: PullRequest) -> [String] {
        countCoAuthors ? pr.contributorNames : [pr.authorName]
    }

    /// GitHub-bots heten "naam[bot]".
    public static func isBot(_ author: String) -> Bool {
        author.localizedCaseInsensitiveContains("[bot]")
    }
}

public struct ActivityBucket: Hashable, Sendable, Identifiable {
    public let start: Date
    public let opened: Int
    public let merged: Int

    public var id: Date { start }
}

public struct RankedName: Hashable, Sendable, Identifiable {
    public let name: String
    public let count: Int

    public var id: String { name }
}

/// PR-activiteit per week, maand of jaar uit de geschiedenis.
public struct ActivityStats: Sendable {
    /// Oudste eerst; de laatste is de huidige periode.
    public let buckets: [ActivityBucket]
    public let openedThisPeriod: Int
    public let mergedThisPeriod: Int
    /// Mediaan van aanmaak tot merge, over de PR's die binnen de grafiek gemerged zijn.
    public let medianLeadTime: TimeInterval?
    /// Auteurs met een geopende PR in de huidige periode.
    public let activeAuthors: Int
    /// Geopende PR's binnen de grafiek, meeste eerst.
    public let authors: [RankedName]
    public let repos: [RankedName]

    public static func compute(
        history: History, period: StatsPeriod, filter: ActivityFilter, now: Date = Date(), calendar: Calendar = .current
    ) -> ActivityStats {
        let currentStart = calendar.dateInterval(of: period.component, for: now)?.start ?? now
        let starts = (0..<period.bucketCount).reversed().compactMap {
            calendar.date(byAdding: period.component, value: -$0, to: currentStart)
        }
        guard let rangeStart = starts.first,
              let rangeEnd = calendar.date(byAdding: period.component, value: 1, to: currentStart) else {
            return ActivityStats(buckets: [], openedThisPeriod: 0, mergedThisPeriod: 0, medianLeadTime: nil,
                                 activeAuthors: 0, authors: [], repos: [])
        }
        let range = rangeStart..<rangeEnd

        let pullRequests: [PullRequest] = history.items.compactMap { item in
            guard case .pullRequest(let pr) = item.entry else { return nil }
            if filter.hideBots && ActivityFilter.isBot(pr.authorName) { return nil }
            if let author = filter.author, !filter.people(of: pr).contains(author) { return nil }
            if let group = filter.group, HistoryGroup.ID(accountId: pr.accountId, repo: pr.repo) != group { return nil }
            if let repoId = filter.repoId, "\(pr.accountId.uuidString)/\(pr.repo)" != repoId { return nil }
            return pr
        }

        func bucketIndex(_ date: Date) -> Int? {
            guard range.contains(date) else { return nil }
            return starts.lastIndex { $0 <= date }
        }
        var opened = Array(repeating: 0, count: starts.count)
        var merged = Array(repeating: 0, count: starts.count)
        var leadTimes: [TimeInterval] = []
        var authors: [String: Int] = [:]
        var repos: [String: Int] = [:]
        var activeAuthors: Set<String> = []
        for pr in pullRequests {
            if let index = bucketIndex(pr.createdAt) {
                opened[index] += 1
                for name in filter.people(of: pr) where !(filter.hideBots && ActivityFilter.isBot(name)) {
                    authors[name, default: 0] += 1
                    if index == starts.count - 1 { activeAuthors.insert(name) }
                }
                repos[pr.repo, default: 0] += 1
            }
            if pr.state == .merged, let closedAt = pr.closedAt, let index = bucketIndex(closedAt) {
                merged[index] += 1
                leadTimes.append(closedAt.timeIntervalSince(pr.createdAt))
            }
        }

        func ranked(_ counts: [String: Int]) -> [RankedName] {
            counts.map { RankedName(name: $0.key, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return ActivityStats(
            buckets: starts.indices.map { ActivityBucket(start: starts[$0], opened: opened[$0], merged: merged[$0]) },
            openedThisPeriod: opened.last ?? 0,
            mergedThisPeriod: merged.last ?? 0,
            medianLeadTime: median(leadTimes),
            activeAuthors: activeAuthors.count,
            authors: ranked(authors),
            repos: ranked(repos)
        )
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

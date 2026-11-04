public import Foundation

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

/// Eén periode in de grafiek. Geopend en draft tellen op de aanmaakdatum, gemerged en gesloten op
/// de sluitdatum, zodat een PR in twee periodes kan meetellen.
public struct ActivityBucket: Hashable, Sendable, Identifiable {
    public let start: Date
    /// Alle PR's die in deze periode geopend zijn, drafts inbegrepen.
    public let opened: Int
    /// Het deel van `opened` dat nu nog een open draft is. De geschiedenis bewaart alleen de
    /// huidige status, niet of een PR als draft begon: een draft die later klaar of gemerged is,
    /// telt hier niet meer mee.
    public let drafts: Int
    public let merged: Int
    /// Gesloten zonder te mergen.
    public let closed: Int

    public init(start: Date, opened: Int, drafts: Int = 0, merged: Int, closed: Int = 0) {
        self.start = start
        self.opened = opened
        self.drafts = drafts
        self.merged = merged
        self.closed = closed
    }

    /// Geopend en geen draft (meer): het groene deel van de staaf.
    public var openedReady: Int { opened - drafts }

    public var id: Date { start }
}

/// Hoeveel PR's er nu in elke status staan, zoals GitHub ze toont: open, draft, gemerged en
/// gesloten zonder merge. Voor de uitsplitsing per auteur of repo.
public struct PRStateCounts: Hashable, Sendable {
    public var open = 0
    public var draft = 0
    public var merged = 0
    public var closed = 0

    public init(open: Int = 0, draft: Int = 0, merged: Int = 0, closed: Int = 0) {
        self.open = open
        self.draft = draft
        self.merged = merged
        self.closed = closed
    }

    mutating func add(_ pr: PullRequest) {
        switch pr.state {
        case .open where pr.isDraft: draft += 1
        case .open: open += 1
        case .merged: merged += 1
        case .closed: closed += 1
        }
    }
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
    /// Gesloten zonder merge in de huidige periode.
    public let closedThisPeriod: Int
    /// Open drafts op dit moment, ongeacht wanneer ze geopend zijn.
    public let openDrafts: Int
    /// Mediaan van aanmaak tot merge, over de PR's die binnen de grafiek gemerged zijn.
    public let medianLeadTime: TimeInterval?
    /// Auteurs met een geopende PR in de huidige periode.
    public let activeAuthors: Int
    /// Geopende PR's binnen de grafiek, meeste eerst.
    public let authors: [RankedName]
    public let repos: [RankedName]
    /// De huidige status van de PR's achter `authors` en `repos`, op naam: de tooltip splitst
    /// het aantal zo uit.
    public let authorStates: [String: PRStateCounts]
    public let repoStates: [String: PRStateCounts]

    static func compute(
        history: History, period: StatsPeriod, filter: ActivityFilter, now: Date = Date(), calendar: Calendar = .current
    ) -> ActivityStats {
        let currentStart = calendar.dateInterval(of: period.component, for: now)?.start ?? now
        let starts = (0..<period.bucketCount).reversed().compactMap {
            calendar.date(byAdding: period.component, value: -$0, to: currentStart)
        }
        guard let rangeStart = starts.first,
              let rangeEnd = calendar.date(byAdding: period.component, value: 1, to: currentStart) else {
            return ActivityStats(buckets: [], openedThisPeriod: 0, mergedThisPeriod: 0, closedThisPeriod: 0, openDrafts: 0,
                                 medianLeadTime: nil, activeAuthors: 0, authors: [], repos: [], authorStates: [:], repoStates: [:])
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
        var drafts = Array(repeating: 0, count: starts.count)
        var merged = Array(repeating: 0, count: starts.count)
        var closed = Array(repeating: 0, count: starts.count)
        var openDrafts = 0
        var authorStates: [String: PRStateCounts] = [:]
        var repoStates: [String: PRStateCounts] = [:]
        var leadTimes: [TimeInterval] = []
        var authors: [String: Int] = [:]
        var repos: [String: Int] = [:]
        var activeAuthors: Set<String> = []
        for pr in pullRequests {
            let isOpenDraft = pr.state == .open && pr.isDraft
            if isOpenDraft { openDrafts += 1 }
            if let index = bucketIndex(pr.createdAt) {
                opened[index] += 1
                if isOpenDraft { drafts[index] += 1 }
                for name in filter.people(of: pr) where !(filter.hideBots && ActivityFilter.isBot(name)) {
                    authors[name, default: 0] += 1
                    authorStates[name, default: PRStateCounts()].add(pr)
                    if index == starts.count - 1 { activeAuthors.insert(name) }
                }
                repos[pr.repo, default: 0] += 1
                repoStates[pr.repo, default: PRStateCounts()].add(pr)
            }
            if let closedAt = pr.closedAt, let index = bucketIndex(closedAt) {
                switch pr.state {
                case .merged:
                    merged[index] += 1
                    leadTimes.append(closedAt.timeIntervalSince(pr.createdAt))
                case .closed:
                    closed[index] += 1
                case .open:
                    break
                }
            }
        }

        func ranked(_ counts: [String: Int]) -> [RankedName] {
            counts.map { RankedName(name: $0.key, count: $0.value) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return ActivityStats(
            buckets: starts.indices.map {
                ActivityBucket(start: starts[$0], opened: opened[$0], drafts: drafts[$0], merged: merged[$0], closed: closed[$0])
            },
            openedThisPeriod: opened.last ?? 0,
            mergedThisPeriod: merged.last ?? 0,
            closedThisPeriod: closed.last ?? 0,
            openDrafts: openDrafts,
            medianLeadTime: median(leadTimes),
            activeAuthors: activeAuthors.count,
            authors: ranked(authors),
            repos: ranked(repos),
            authorStates: authorStates,
            repoStates: repoStates
        )
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

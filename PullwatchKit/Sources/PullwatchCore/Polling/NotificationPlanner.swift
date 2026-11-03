import Foundation

/// Eén repo van één account: de groep waarin macOS de meldingen stapelt (`threadIdentifier`).
public struct RepositoryKey: Hashable, Sendable {
    public let accountId: UUID?
    public let repo: String

    public init(accountId: UUID?, repo: String) {
        self.accountId = accountId
        self.repo = repo
    }

    /// Vast per account en repo, hoofdletterongevoelig: "<account-id>/<repo>".
    public var threadIdentifier: String {
        "\(accountId?.uuidString ?? "-")/\(repo.lowercased())"
    }
}

/// Iets uit een poll dat een melding kan geven: een nieuwe PR, een gemergde PR, een eigen PR
/// waarvan de checks mislukten, of een tag (met of zonder release).
public enum RepositoryItem: Equatable, Sendable {
    case pullRequest(PullRequest)
    case merged(PullRequest)
    case checksFailed(PullRequest)
    case tag(Tag)

    public var kind: NotificationKind {
        switch self {
        case .pullRequest: .pullRequest
        case .merged: .merged
        case .checksFailed: .checksFailed
        case .tag(let tag): tag.release == nil ? .tag : .release
        }
    }

    public var repository: RepositoryKey {
        switch self {
        case .pullRequest(let pr), .merged(let pr), .checksFailed(let pr): RepositoryKey(accountId: pr.accountId, repo: pr.repo)
        case .tag(let tag): RepositoryKey(accountId: tag.accountId, repo: tag.repo)
        }
    }

    /// Het id van het item in de geschiedenis (`HistoryItem.id`): wat "Markeer als gelezen" leest.
    public var historyKey: String {
        switch self {
        case .pullRequest(let pr), .merged(let pr), .checksFailed(let pr): pr.dedupKey
        case .tag(let tag): tag.dedupKey
        }
    }

    /// Het id van de melding: vast, zodat dezelfde melding nog eens de oude vervangt. Gemerged
    /// en mislukte checks hebben een eigen id, naast de melding van de nieuwe PR; een volgende
    /// keer mislukte checks van dezelfde PR vervangt de vorige.
    public var notificationIdentifier: String {
        switch self {
        case .pullRequest(let pr): pr.dedupKey
        case .merged(let pr): pr.dedupKey + ":completed"
        case .checksFailed(let pr): pr.dedupKey + ":checks"
        case .tag(let tag): tag.dedupKey
        }
    }

    /// Wat er per repo gevolgd wordt en meldt (`WatchSet`); releases horen bij de tags, mislukte
    /// checks bij de PR's.
    public var watchKind: WatchKind {
        switch self {
        case .pullRequest, .checksFailed: .pullRequests
        case .merged: .merged
        case .tag: .tags
        }
    }
}

/// Een melding zoals de planner hem bedoelt: één item, of boven de grens één samenvatting per repo.
public enum PlannedNotification<Item: Equatable & Sendable>: Equatable, Sendable {
    case single(Item)
    case summary(RepositoryKey, [Item])
}

public enum NotificationPlanner {
    /// Zoveel losse meldingen per poll (of per check) hooguit; daarboven één per repo. macOS
    /// stapelt de losse per repo zelf, dus een gewone poll geeft elk item een eigen melding.
    public static let cap = 20

    /// Wat er van een poll gemeld wordt: per soort alleen als die aan staat (`settings`), per repo
    /// alleen als die repo voor die soort meldt (#54), in de volgorde PR's, mislukte checks,
    /// releases, tags en gemergde PR's. Mislukte checks gaan over je eigen PR's en melden ook in
    /// een repo die nieuwe PR's stil volgt. Boven `cap` één samenvatting per repo.
    public static func plan(
        pullRequests: [PullRequest], tags: [Tag], completed: [PullRequest] = [], failedChecks: [PullRequest] = [],
        settings: NotificationSettings = NotificationSettings(), accounts: [Account] = []
    ) -> [PlannedNotification<RepositoryItem>] {
        let audible = audible(pullRequests: pullRequests, tags: tags, completed: completed, accounts: accounts)
        let items: [RepositoryItem] = audible.pullRequests.map(RepositoryItem.pullRequest)
            + failedChecks.map(RepositoryItem.checksFailed)
            + audible.tags.filter { $0.release != nil }.map(RepositoryItem.tag)
            + audible.tags.filter { $0.release == nil }.map(RepositoryItem.tag)
            + audible.completed.map(RepositoryItem.merged)
        return capped(items.filter { settings[$0.kind] }, repository: \.repository)
    }

    /// Laat weg waarvoor de repo op "geen melding" staat; het item zelf blijft gevolgd. Een
    /// account dat er niet (meer) is meldt alles.
    public static func audible(
        pullRequests: [PullRequest], tags: [Tag], completed: [PullRequest], accounts: [Account]
    ) -> (pullRequests: [PullRequest], tags: [Tag], completed: [PullRequest]) {
        let byId = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func notifies(_ accountId: UUID, _ repo: String, _ field: KeyPath<WatchSet, Bool>) -> Bool {
            byId[accountId]?.watch(for: repo)[keyPath: field] ?? true
        }
        return (
            pullRequests.filter { notifies($0.accountId, $0.repo, \.notifyPRs) },
            tags.filter { notifies($0.accountId, $0.repo, \.notifyTags) },
            completed.filter { notifies($0.accountId, $0.repo, \.notifyCompleted) }
        )
    }

    /// Tot en met `cap` items: elk een eigen melding. Daarboven per repo (in de volgorde waarin
    /// de repo's voor het eerst voorkomen) één samenvatting; een repo met maar één item houdt
    /// zijn eigen melding.
    public static func capped<Item: Equatable & Sendable>(
        _ items: [Item], repository: (Item) -> RepositoryKey, cap: Int = cap
    ) -> [PlannedNotification<Item>] {
        guard items.count > cap else { return items.map { .single($0) } }
        var order: [RepositoryKey] = []
        var groups: [RepositoryKey: [Item]] = [:]
        for item in items {
            let key = repository(item)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { key in
            let group = groups[key] ?? []
            return group.count == 1 ? .single(group[0]) : .summary(key, group)
        }
    }
}

/// Hoe belangrijk een melding is: hoe hij binnenkomt en hoe hoog hij in de stapel staat
/// (`relevanceScore`, 0 tot 1; de hoogste staat in de samenvatting van macOS vooraan).
public struct NotificationImportance: Equatable, Sendable {
    public var level: NotificationLevel
    public var relevance: Double
    /// Met geluid; in de stille uren nooit.
    public var playsSound: Bool

    public init(level: NotificationLevel, relevance: Double, playsSound: Bool) {
        self.level = level
        self.relevance = relevance
        self.playsSound = playsSound
    }

    /// Nieuwe PR's, mislukte checks van je eigen PR's en releases die je volgt komen met een
    /// banner; tags zonder release, gemergde
    /// PR's en nieuwe versies alleen in het Berichtencentrum. Een kwetsbaarheid of
    /// beveiligingsmelding gaat voor, de ernstigste het hoogst. `severityRank` zoals
    /// `Vulnerability.severityRank` (critical 4 … low 1, onbekend 0).
    public static func of(_ kind: NotificationKind, severityRank: Int = 0, quiet: Bool = false) -> Self {
        let base: Self = switch kind {
        case .pullRequest: Self(level: .active, relevance: 0.6, playsSound: true)
        case .checksFailed: Self(level: .active, relevance: 0.62, playsSound: true)
        case .release: Self(level: .active, relevance: 0.5, playsSound: true)
        case .merged: Self(level: .passive, relevance: 0.3, playsSound: false)
        case .tag: Self(level: .passive, relevance: 0.2, playsSound: false)
        case .vulnerability, .securityAlert:
            Self(level: .active, relevance: 0.7 + 0.075 * Double(min(max(severityRank, 0), 4)), playsSound: true)
        case .packageUpdate: Self(level: .passive, relevance: 0.1, playsSound: false)
        case .appUpdate: Self(level: .passive, relevance: 0.4, playsSound: false)
        case .account: Self(level: .active, relevance: 0.65, playsSound: true)
        }
        return quiet ? Self(level: .passive, relevance: base.relevance, playsSound: false) : base
    }

    /// Voor een samenvatting: zo belangrijk als het belangrijkste item erin.
    public static func strongest(_ all: [Self]) -> Self? {
        all.max { ($0.level, $0.relevance) < ($1.level, $1.relevance) }
    }
}

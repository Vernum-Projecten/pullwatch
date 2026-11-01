import Foundation

public enum HistoryEntry: Codable, Hashable, Sendable {
    case pullRequest(PullRequest)
    case tag(Tag)

    public var kind: ItemKind {
        switch self {
        case .pullRequest: return .pullRequest
        case .tag: return .tag
        }
    }

    public var dedupKey: String {
        switch self {
        case .pullRequest(let pr): return pr.dedupKey
        case .tag(let tag): return tag.dedupKey
        }
    }

    public var accountId: UUID {
        switch self {
        case .pullRequest(let pr): return pr.accountId
        case .tag(let tag): return tag.accountId
        }
    }

    public var repo: String {
        switch self {
        case .pullRequest(let pr): return pr.repo
        case .tag(let tag): return tag.repo
        }
    }

    /// PR-titel of tagnaam.
    public var title: String {
        switch self {
        case .pullRequest(let pr): return pr.title
        case .tag(let tag): return tag.name
        }
    }

    public var author: String? {
        switch self {
        case .pullRequest(let pr): return pr.authorName
        case .tag(let tag): return tag.authorName
        }
    }

    public var webURL: URL {
        switch self {
        case .pullRequest(let pr): return pr.webURL
        case .tag(let tag): return tag.webURL
        }
    }

    /// Status van de PR; `nil` voor tags.
    public var prState: PRState? {
        switch self {
        case .pullRequest(let pr): return pr.state
        case .tag: return nil
        }
    }
}

public struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    public var entry: HistoryEntry
    public var detectedAt: Date
    public var isRead: Bool

    public var id: String { entry.dedupKey }

    public init(entry: HistoryEntry, detectedAt: Date, isRead: Bool) {
        self.entry = entry
        self.detectedAt = detectedAt
        self.isRead = isRead
    }
}

public enum HistoryRetention: String, Codable, CaseIterable, Sendable {
    case twoMonths, sixMonths, oneYear, forever

    /// Maximale leeftijd; `nil` betekent dat er nooit iets wordt verwijderd.
    public var maxAge: TimeInterval? {
        let day: TimeInterval = 86_400
        switch self {
        case .twoMonths: return 61 * day
        case .sixMonths: return 183 * day
        case .oneYear: return 365 * day
        case .forever: return nil
        }
    }

    public var label: String {
        switch self {
        case .twoMonths: return String(localized: "2 maanden", bundle: .localizedCore)
        case .sixMonths: return String(localized: "6 maanden", bundle: .localizedCore)
        case .oneYear: return String(localized: "1 jaar", bundle: .localizedCore)
        case .forever: return String(localized: "Altijd", bundle: .localizedCore)
        }
    }
}

public struct History: Codable, Equatable, Sendable {
    /// Nieuwste eerst.
    public private(set) var items: [HistoryItem] = []

    public init() {}

    /// Neemt een oude `RecentList` over, met behoud van `detectedAt` en `isRead`.
    public init(migrating list: RecentList) {
        items = list.items.map {
            HistoryItem(entry: .pullRequest($0.pullRequest), detectedAt: $0.detectedAt, isRead: $0.isRead)
        }
    }

    public var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    public func unreadCount(_ kind: ItemKind) -> Int {
        items.filter { !$0.isRead && $0.entry.kind == kind }.count
    }

    /// Bestaande items worden vervangen en komen bovenaan; tags komen boven de PR's uit dezelfde aanroep.
    public mutating func add(pullRequests: [PullRequest], tags: [Tag], at date: Date) {
        let entries = pullRequests.sorted { $0.createdAt < $1.createdAt }.map(HistoryEntry.pullRequest)
            + tags.map(HistoryEntry.tag)
        for entry in entries {
            items.removeAll { $0.id == entry.dedupKey }
            items.insert(HistoryItem(entry: entry, detectedAt: date, isRead: false), at: 0)
        }
    }

    /// Voegt gesyncte PR's toe (gelezen, `detectedAt` = `createdAt`, op volgorde van `detectedAt`
    /// ingevoegd) of werkt bij bestaande items alleen status, sluitdatum en titel bij.
    /// Nieuwe PR's aangemaakt vóór `notBefore` (de bewaartermijn) worden niet toegevoegd, anders
    /// zouden ze direct weer weggeprunet worden. Geeft `true` als er iets veranderd is.
    @discardableResult
    public mutating func merge(synced: [PullRequest], notBefore: Date? = nil) -> Bool {
        var indexById: [String: Int] = [:]
        indexById.reserveCapacity(items.count + synced.count)
        for (index, item) in items.enumerated() {
            indexById[item.id] = index
        }
        let existingCount = items.count
        var changed = false
        for pr in synced {
            let key = pr.dedupKey
            if let index = indexById[key] {
                if Self.update(&items[index], with: pr) { changed = true }
            } else {
                if let notBefore, pr.createdAt < notBefore { continue }
                indexById[key] = items.count
                items.append(HistoryItem(entry: .pullRequest(pr), detectedAt: pr.createdAt, isRead: true))
                changed = true
            }
        }
        if items.count > existingCount {
            // Stabiel sorteren (index als tiebreak): bij gelijke datum blijven bestaande items vóór
            // nieuwe en nieuwe items in aanvoervolgorde.
            items = items.enumerated()
                .sorted { $0.element.detectedAt != $1.element.detectedAt
                    ? $0.element.detectedAt > $1.element.detectedAt
                    : $0.offset < $1.offset }
                .map(\.element)
        }
        return changed
    }

    /// Werkt status, sluitdatum en titel van een PR-item bij. Geeft `true` als er iets veranderde.
    private static func update(_ item: inout HistoryItem, with pr: PullRequest) -> Bool {
        guard case .pullRequest(var existing) = item.entry else { return false }
        guard existing.state != pr.state || existing.closedAt != pr.closedAt || existing.title != pr.title else { return false }
        existing.state = pr.state
        existing.closedAt = pr.closedAt
        existing.title = pr.title
        item.entry = .pullRequest(existing)
        return true
    }

    public mutating func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
    }

    public mutating func markAllRead() {
        for index in items.indices {
            items[index].isRead = true
        }
    }

    public mutating func removeAccount(_ id: UUID) {
        items.removeAll { $0.entry.accountId == id }
    }

    /// Verwijdert items ouder dan de bewaartermijn. Geeft `true` als er iets is verwijderd.
    @discardableResult
    public mutating func prune(now: Date, retention: HistoryRetention) -> Bool {
        guard let maxAge = retention.maxAge else { return false }
        let before = items.count
        items.removeAll { now.timeIntervalSince($0.detectedAt) > maxAge }
        return items.count != before
    }

    public func latest(_ kind: ItemKind, limit: Int) -> [HistoryItem] {
        Array(items.filter { $0.entry.kind == kind }.prefix(max(limit, 0)))
    }

    /// Projecten (Azure DevOps) of eigenaren (GitHub) met items van `kind`, op naam. Dezelfde naam bij
    /// twee accounts krijgt de accountnaam erachter.
    public func groups(_ kind: ItemKind, accountNames: [UUID: String]) -> [HistoryGroup] {
        var unread: [HistoryGroup.ID: Int] = [:]
        for item in items where item.entry.kind == kind {
            let id = HistoryGroup.ID(item.entry)
            unread[id, default: 0] += item.isRead ? 0 : 1
        }
        return HistoryGroup.named(unread, accountNames: accountNames)
    }

    /// Lege tekst (na trimmen) geeft alles; anders hoofdletterongevoelig zoeken in titel, auteur en repo.
    /// Met `group` alleen items van dat project, met `author` alleen PR's van die auteur, met `repo`
    /// alleen items van die repo (hoofdletterongevoelig).
    public func search(
        _ text: String, kind: ItemKind?, group: HistoryGroup.ID? = nil, author: String? = nil, repo: HistoryRepo? = nil
    ) -> [HistoryItem] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            if let kind, item.entry.kind != kind { return false }
            if let group, HistoryGroup.ID(item.entry) != group { return false }
            if let author, item.entry.author != author { return false }
            if let repo, item.entry.accountId != repo.accountId
                || item.entry.repo.caseInsensitiveCompare(repo.repo) != .orderedSame { return false }
            if query.isEmpty { return true }
            return item.entry.title.localizedCaseInsensitiveContains(query)
                || (item.entry.author?.localizedCaseInsensitiveContains(query) ?? false)
                || item.entry.repo.localizedCaseInsensitiveContains(query)
        }
    }
}

extension History {
    /// Kiest de beginstand bij het opstarten: `history.json` wint; anders wordt `recent.json` gemigreerd.
    /// `storedUnreadable` betekent dat `history.json` bestond maar niet te laden was: dan wordt er
    /// niet gemigreerd (een oude `recent.json` is geen vervanging) en start de geschiedenis leeg.
    /// `needsSave` is `true` als de uitkomst nog naar `history.json` moet worden weggeschreven.
    public static func initial(
        stored: History?,
        storedUnreadable: Bool = false,
        legacy: RecentList?
    ) -> (history: History, needsSave: Bool) {
        if let stored { return (stored, false) }
        if storedUnreadable { return (History(), false) }
        if let legacy { return (History(migrating: legacy), true) }
        return (History(), false)
    }
}

/// Project (Azure DevOps) of eigenaar (GitHub) binnen één account: het deel van de repo-naam vóór de "/".
public struct HistoryGroup: Hashable, Sendable, Identifiable {
    public struct ID: Hashable, Sendable, Codable {
        public let accountId: UUID
        public let project: String

        public init(accountId: UUID, project: String) {
            self.accountId = accountId
            self.project = project
        }

        init(_ entry: HistoryEntry) {
            self.init(accountId: entry.accountId, repo: entry.repo)
        }

        public init(accountId: UUID, repo: String) {
            let project = repo.split(separator: "/", maxSplits: 1).first.map(String.init) ?? repo
            self.init(accountId: accountId, project: project)
        }
    }

    /// Groepen met hun teller, op naam; dezelfde projectnaam bij twee accounts krijgt de accountnaam erachter.
    static func named(_ counts: [ID: Int], accountNames: [UUID: String]) -> [HistoryGroup] {
        let projectCounts = Dictionary(grouping: counts.keys, by: \.project).mapValues(\.count)
        return counts.map { id, count in
            let account = accountNames[id.accountId]
            let name = (projectCounts[id.project] ?? 0) > 1 && account != nil ? "\(id.project) (\(account!))" : id.project
            return HistoryGroup(id: id, name: name, unreadCount: count)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public let id: ID
    public let name: String
    public let unreadCount: Int
}

/// Eén repo binnen een account, als filter op de geschiedenis.
public struct HistoryRepo: Hashable, Sendable {
    public let accountId: UUID
    public let repo: String

    public init(accountId: UUID, repo: String) {
        self.accountId = accountId
        self.repo = repo
    }
}

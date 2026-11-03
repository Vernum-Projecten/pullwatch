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

    /// Co-auteurs van een PR; leeg voor tags.
    public var coAuthors: [Person] {
        switch self {
        case .pullRequest(let pr): return pr.coAuthors
        case .tag: return []
        }
    }

    /// Foto van de auteur van een tag (GitHub); `nil` voor PR's.
    public var authorAvatarURL: URL? {
        switch self {
        case .pullRequest: return nil
        case .tag(let tag): return tag.authorAvatarURL
        }
    }

    /// De release bij een tag; `nil` voor PR's en tags zonder release.
    public var release: ReleaseInfo? {
        switch self {
        case .pullRequest: return nil
        case .tag(let tag): return tag.release
        }
    }

    /// De titel van de release bij een tag, als die iets anders zegt dan de tagnaam.
    public var releaseTitle: String? {
        switch self {
        case .pullRequest: return nil
        case .tag(let tag): return tag.releaseTitle
        }
    }

    public var webURL: URL {
        switch self {
        case .pullRequest(let pr): return pr.webURL
        case .tag(let tag): return tag.webURL
        }
    }

    /// De checks van een PR; `nil` voor tags en voor een PR zonder opgehaalde checks.
    public var checks: PRChecks? {
        switch self {
        case .pullRequest(let pr): return pr.checks
        case .tag: return nil
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

    /// Voegt bestaande tags uit de eerste tag-poll toe: gelezen, `detectedAt` = `createdAt`, op
    /// volgorde van datum. Een tag die al in de geschiedenis staat blijft zoals hij is, net als
    /// tags zonder datum of van vóór `notBefore`. Geeft `true` als er iets is toegevoegd.
    @discardableResult
    public mutating func merge(syncedTags tags: [Tag], notBefore: Date? = nil) -> Bool {
        var known = Set(items.map(\.id))
        var added: [HistoryItem] = []
        for tag in tags {
            guard let date = tag.createdAt, notBefore.map({ date >= $0 }) ?? true,
                  known.insert(tag.dedupKey).inserted else { continue }
            added.append(HistoryItem(entry: .tag(tag), detectedAt: date, isRead: true))
        }
        guard !added.isEmpty else { return false }
        // Stabiel: bij gelijke datum blijven bestaande items vóór de nieuwe.
        items = (items + added).enumerated()
            .sorted { $0.element.detectedAt != $1.element.detectedAt
                ? $0.element.detectedAt > $1.element.detectedAt
                : $0.offset < $1.offset }
            .map(\.element)
        return true
    }

    /// Werkt bestaande tag-items bij met wat de provider nu van die tags weet (auteur, foto,
    /// release, link), zonder volgorde of gelezen-status te veranderen; voegt niets toe. Een
    /// bekende datum blijft staan als de nieuwe tag er geen heeft. Geeft `true` als er iets veranderde.
    @discardableResult
    public mutating func update(tags: [Tag]) -> Bool {
        guard !tags.isEmpty else { return false }
        let byKey = Dictionary(tags.map { ($0.dedupKey, $0) }, uniquingKeysWith: { _, last in last })
        var changed = false
        for index in items.indices {
            guard case .tag(let existing) = items[index].entry, let tag = byKey[existing.dedupKey] else { continue }
            let merged = Tag(
                accountId: tag.accountId,
                repo: existing.repo,
                name: tag.name,
                authorName: tag.authorName ?? existing.authorName,
                authorAvatarURL: tag.authorAvatarURL ?? existing.authorAvatarURL,
                webURL: tag.webURL,
                createdAt: tag.createdAt ?? existing.createdAt,
                release: tag.release
            )
            guard merged != existing else { continue }
            items[index].entry = .tag(merged)
            changed = true
        }
        return changed
    }

    /// Werkt status, sluitdatum, titel, co-auteurs en checks van een PR-item bij. Een lege lijst
    /// co-auteurs en ontbrekende checks laten de bewaarde staan: die betekenen meestal "deze poll
    /// niet opgehaald". Geeft `true` als er iets veranderde.
    private static func update(_ item: inout HistoryItem, with pr: PullRequest) -> Bool {
        guard case .pullRequest(var existing) = item.entry else { return false }
        let coAuthors = pr.coAuthors.isEmpty ? existing.coAuthors : pr.coAuthors
        let checks = pr.checks ?? existing.checks
        // De wachtrij komt per poll (`update(mergeQueues:)`); na een merge of sluiten is hij voorbij.
        let mergeQueue = pr.state == .open ? existing.mergeQueue : nil
        guard existing.state != pr.state || existing.closedAt != pr.closedAt || existing.title != pr.title
                || existing.coAuthors != coAuthors || existing.checks != checks
                || existing.mergeQueue != mergeQueue else { return false }
        existing.mergeQueue = mergeQueue
        existing.state = pr.state
        existing.closedAt = pr.closedAt
        existing.title = pr.title
        existing.coAuthors = coAuthors
        existing.checks = checks
        item.entry = .pullRequest(existing)
        return true
    }

    /// Zet de net opgehaalde checks (per dedupKey) bij de PR's in de geschiedenis, zonder volgorde
    /// of gelezen-status te veranderen; voegt niets toe. Geeft `true` als er iets veranderde.
    @discardableResult
    public mutating func update(checks: [String: PRChecks]) -> Bool {
        guard !checks.isEmpty else { return false }
        var changed = false
        for index in items.indices {
            guard case .pullRequest(var pr) = items[index].entry, let found = checks[pr.dedupKey],
                  pr.checks != found else { continue }
            pr.checks = found
            items[index].entry = .pullRequest(pr)
            changed = true
        }
        return changed
    }

    /// Zet bij de open PR's in de geschiedenis of ze in de rij staan om vanzelf te mergen (per
    /// dedupKey; `nil` als waarde: niet in de rij), zonder volgorde of gelezen-status te
    /// veranderen. Een PR die niet meer open is houdt wat hij had: zijn status zegt dan genoeg.
    /// Geeft `true` als er iets veranderde.
    @discardableResult
    public mutating func update(mergeQueues: [String: MergeQueueEntry?]) -> Bool {
        guard !mergeQueues.isEmpty else { return false }
        var changed = false
        for index in items.indices {
            guard case .pullRequest(var pr) = items[index].entry, pr.state == .open,
                  let found = mergeQueues[pr.dedupKey], pr.mergeQueue != found else { continue }
            pr.mergeQueue = found
            items[index].entry = .pullRequest(pr)
            changed = true
        }
        return changed
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

    /// Zet deze items op gelezen of ongelezen. `true` als er iets veranderde.
    @discardableResult
    public mutating func setRead(_ ids: Set<String>, _ isRead: Bool) -> Bool {
        var changed = false
        for index in items.indices where ids.contains(items[index].id) && items[index].isRead != isRead {
            items[index].isRead = isRead
            changed = true
        }
        return changed
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

    /// Lege tekst (na trimmen) geeft alles; anders hoofdletterongevoelig zoeken in titel (ook die
    /// van een release), auteur, co-auteurs en repo.
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
                || (item.entry.releaseTitle?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.entry.author?.localizedCaseInsensitiveContains(query) ?? false)
                || item.entry.coAuthors.contains { $0.handle.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query) }
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

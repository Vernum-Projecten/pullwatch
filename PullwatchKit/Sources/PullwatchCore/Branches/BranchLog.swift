public import Foundation

/// Alle gemelde pushes naar branches, nieuwste eerst; staat in branches.json.
public struct BranchLog: Codable, Equatable, Sendable {
    /// Nieuwste eerst (`pushedAt`).
    public private(set) var pushes: [BranchPush]

    public init(pushes: [BranchPush] = []) {
        self.pushes = pushes
    }

    /// Dubbele id's worden genegeerd; daarna staat alles op `pushedAt`, nieuwste eerst.
    public mutating func add(_ new: [BranchPush]) {
        var known = Set(pushes.map(\.id))
        let added = new.filter { known.insert($0.id).inserted }
        guard !added.isEmpty else { return }
        // Stabiel sorteren (index als tiebreak), zodat bestaande rijen bij gelijke tijd vooraan blijven.
        pushes = (pushes + added).enumerated()
            .sorted { $0.element.pushedAt != $1.element.pushedAt
                ? $0.element.pushedAt > $1.element.pushedAt
                : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Verwijdert pushes ouder dan de bewaartermijn. Geeft `true` als er iets is verwijderd.
    @discardableResult
    public mutating func prune(now: Date, retention: HistoryRetention) -> Bool {
        guard let maxAge = retention.maxAge else { return false }
        let before = pushes.count
        pushes.removeAll { now.timeIntervalSince($0.pushedAt) > maxAge }
        return pushes.count != before
    }

    public mutating func removeAccount(_ id: UUID) {
        pushes.removeAll { $0.accountId == id }
    }
}

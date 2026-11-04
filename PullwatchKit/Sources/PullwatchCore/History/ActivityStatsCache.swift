public import Foundation

/// Statistieken per periode en filter, bewaard tot de geschiedenis verandert (`removeAll()`) of
/// tot ze `lifetime` oud zijn: de periode schuift op, dus na een tijd klopt de grafiek niet meer.
public struct ActivityStatsCache {
    /// Hoe lang een berekening geldt.
    static let lifetime: TimeInterval = 600

    private struct Key: Hashable {
        let period: StatsPeriod
        let filter: ActivityFilter
    }

    private var entries: [Key: (at: Date, stats: ActivityStats)] = [:]

    public init() {}

    /// De bewaarde statistieken, of nieuwe uit `history` als er geen (verse) zijn.
    public mutating func stats(
        history: History, period: StatsPeriod, filter: ActivityFilter, now: Date = Date(), calendar: Calendar = .current
    ) -> ActivityStats {
        let key = Key(period: period, filter: filter)
        if let cached = entries[key], now.timeIntervalSince(cached.at) < Self.lifetime { return cached.stats }
        let stats = ActivityStats.compute(history: history, period: period, filter: filter, now: now, calendar: calendar)
        entries[key] = (now, stats)
        return stats
    }

    /// Alles vergeten, bijvoorbeeld omdat de geschiedenis veranderde.
    public mutating func removeAll() {
        entries = [:]
    }
}

import Foundation


/// Namen en e-mailadressen van de ingelogde gebruiker zoals de dienst ze kent, om een commit
/// zonder gekoppeld account toch als eigen te herkennen (`PollEngine.isOwn`). Leeg is geldig.
public struct UserIdentity: Sendable, Equatable {
    public var names: [String]
    public var emails: [String]

    /// Lege en dubbele waarden (hoofdletterongevoelig) vallen weg.
    public init(names: [String], emails: [String]) {
        self.names = Self.distinct(names)
        self.emails = Self.distinct(emails)
    }

    private static func distinct(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

import Foundation

/// De gevolgde repo's van één account die het token niet kan lezen: de provider gaf een 404 of
/// geen toegang, dus hun tags of branches worden overgeslagen. Tags en branches lopen elk op hun
/// eigen ritme, dus elk houdt zijn eigen lijst bij; de laatste geslaagde fetch van die soort
/// beslist. Na een mislukte fetch blijft de lijst staan tot de volgende die lukt.
public struct UnreachableRepos: Equatable, Sendable {
    /// Repo's waarvan de tags overgeslagen werden, in de schrijfwijze van de account-instellingen
    /// of de dienst.
    var tags: [String] = []
    /// Repo's waarvan de branches overgeslagen werden.
    var branches: [String] = []

    public init(tags: [String] = [], branches: [String] = []) {
        self.tags = tags
        self.branches = branches
    }

    /// Alle onbereikbare repo's, hoofdletterongevoelig ontdubbeld en gesorteerd.
    public var repos: [String] {
        var seen: Set<String> = []
        return (tags + branches)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public var isEmpty: Bool { tags.isEmpty && branches.isEmpty }

    /// Is `repo` (hoofdletterongevoelig) onbereikbaar?
    public func contains(_ repo: String) -> Bool {
        let key = repo.lowercased()
        return (tags + branches).contains { $0.lowercased() == key }
    }

    /// De repo's uit `requested` die in `unavailable` (lowercased) staan, in de schrijfwijze van
    /// `requested`.
    static func names(of requested: [String], in unavailable: Set<String>) -> [String] {
        var seen: Set<String> = []
        return requested.filter { unavailable.contains($0.lowercased()) && seen.insert($0.lowercased()).inserted }
    }
}

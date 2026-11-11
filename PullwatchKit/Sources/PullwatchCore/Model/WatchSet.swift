import Foundation

/// Alleen nog gebruikt om oude configuratie te migreren.
enum FilterMode: String, Codable, Hashable, Sendable, CaseIterable {
    case allow, deny
}

/// Wat er voor één repo gevolgd wordt.
public struct WatchSet: Codable, Hashable, Sendable {
    public var prs: Bool
    public var tags: Bool
    /// Pushes naar branches van deze repo (sectie Branches). Heeft geen eigen melding.
    public var branches: Bool
    /// Melding als een PR in deze repo gemerged (completed) wordt.
    public var completed: Bool
    /// Melding bij een nieuwe PR; uit = wel volgen (menu, geschiedenis), geen melding.
    var notifyPRs: Bool
    var notifyTags: Bool
    var notifyCompleted: Bool

    public init(
        prs: Bool, tags: Bool, branches: Bool = false, completed: Bool = false,
        notifyPRs: Bool = true, notifyTags: Bool = true, notifyCompleted: Bool = true
    ) {
        self.prs = prs
        self.tags = tags
        self.branches = branches
        self.completed = completed
        self.notifyPRs = notifyPRs
        self.notifyTags = notifyTags
        self.notifyCompleted = notifyCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case prs, tags, branches, completed, notifyPRs, notifyTags, notifyCompleted
    }

    /// Oude JSON heeft geen `completed` (dan uit), geen meldingskeuzes (dan aan) en geen
    /// `branches` (dan zoals `prs`: wie PR's volgde, volgt nu ook de branches).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prs = try c.decode(Bool.self, forKey: .prs)
        tags = try c.decode(Bool.self, forKey: .tags)
        branches = try c.decodeIfPresent(Bool.self, forKey: .branches) ?? prs
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        notifyPRs = try c.decodeIfPresent(Bool.self, forKey: .notifyPRs) ?? true
        notifyTags = try c.decodeIfPresent(Bool.self, forKey: .notifyTags) ?? true
        notifyCompleted = try c.decodeIfPresent(Bool.self, forKey: .notifyCompleted) ?? true
    }

    public static let none = WatchSet(prs: false, tags: false)
    public static let prs = WatchSet(prs: true, tags: false, branches: true)
    public static let tags = WatchSet(prs: false, tags: true)
    static let both = WatchSet(prs: true, tags: true, branches: true)

    /// Volgt deze set dit soort? Aanzetten zet ook de melding ervan aan. Gemerged hoort bij de
    /// PR's: PR's uit zet gemerged uit, gemerged aan zet PR's aan. Branches lopen mee met de PR's:
    /// PR's aan of uit zet de branches mee; het vinkje Branches zelf staat daarna los.
    public subscript(follows kind: WatchKind) -> Bool {
        get {
            switch kind {
            case .pullRequests: prs
            case .tags: tags
            case .branches: branches
            case .merged: completed
            }
        }
        set {
            switch kind {
            case .pullRequests:
                prs = newValue
                branches = newValue
                if newValue { notifyPRs = true } else { completed = false }
            case .tags:
                tags = newValue
                if newValue { notifyTags = true }
            case .branches:
                branches = newValue
            case .merged:
                completed = newValue
                if newValue {
                    notifyCompleted = true
                    if !prs { prs = true; branches = true; notifyPRs = true }
                }
            }
        }
    }

    /// Een melding bij dit soort (alleen zinvol als het gevolgd wordt). Branches melden niet:
    /// lezen geeft altijd `false`, zetten doet niets.
    public subscript(notifies kind: WatchKind) -> Bool {
        get {
            switch kind {
            case .pullRequests: notifyPRs
            case .tags: notifyTags
            case .branches: false
            case .merged: notifyCompleted
            }
        }
        set {
            switch kind {
            case .pullRequests: notifyPRs = newValue
            case .tags: notifyTags = newValue
            case .branches: break
            case .merged: notifyCompleted = newValue
            }
        }
    }
}

/// Wat per repo te volgen is: nieuwe PR's, nieuwe tags, pushes naar branches en gemergde (completed) PR's.
public enum WatchKind: String, CaseIterable, Identifiable, Sendable {
    case pullRequests, tags, branches, merged
    public var id: Self { self }
}

/// Wat er gevolgd wordt voor repo's zonder eigen instelling. Een nieuw account volgt niets
/// (`none`): je kiest zelf welke repo's, zodat Pullwatch niet een heel account ophaalt. Een
/// config zonder het veld (van vóór die keuze) houdt `prs`.
public enum NewRepoDefault: String, Codable, CaseIterable, Sendable {
    case none, prs, prsAndTags

    var watchSet: WatchSet {
        switch self {
        case .none: return .none
        case .prs: return .prs
        case .prsAndTags: return .both
        }
    }
}

/// Gedeelde (de)codering van de repo-instellingen voor `Account` en `FilterSettings`,
/// inclusief migratie van het oude `filterMode`/`repos`-formaat.
enum RepoWatchCoding {
    enum Keys: String, CodingKey {
        case repoWatch, newRepoDefault
    }

    enum LegacyKeys: String, CodingKey {
        case filterMode, repos
    }

    static func decode(from decoder: any Decoder) throws -> (repoWatch: [String: WatchSet], newRepoDefault: NewRepoDefault) {
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if let mode = try legacy.decodeIfPresent(FilterMode.self, forKey: .filterMode) {
            let repos = try legacy.decodeIfPresent([String].self, forKey: .repos) ?? []
            switch mode {
            case .deny: return (Dictionary(repos.map { ($0, WatchSet.none) }, uniquingKeysWith: { a, _ in a }), .prs)
            case .allow: return (Dictionary(repos.map { ($0, WatchSet.prs) }, uniquingKeysWith: { a, _ in a }), .none)
            }
        }
        let c = try decoder.container(keyedBy: Keys.self)
        return (
            try c.decodeIfPresent([String: WatchSet].self, forKey: .repoWatch) ?? [:],
            try c.decodeIfPresent(NewRepoDefault.self, forKey: .newRepoDefault) ?? .prs
        )
    }

    static func lookup(_ repo: String, in repoWatch: [String: WatchSet], default fallback: NewRepoDefault) -> WatchSet {
        if let exact = repoWatch[repo] { return exact }
        for (key, value) in repoWatch where key.caseInsensitiveCompare(repo) == .orderedSame {
            return value
        }
        return fallback.watchSet
    }
}

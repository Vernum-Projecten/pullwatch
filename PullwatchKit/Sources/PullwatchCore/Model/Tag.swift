public import Foundation

/// Een tag zoals een provider hem geeft, met de release erbij als die er is.
public struct Tag: Codable, Hashable, Sendable {
    public let accountId: UUID
    public let repo: String
    public let name: String
    /// Wie de tag of release maakte: de GitHub-login als die bekend is, anders de naam uit git.
    public let authorName: String?
    /// Foto van `authorName`; alleen bij GitHub.
    public let authorAvatarURL: URL?
    /// De release-pagina als de tag een gepubliceerde release heeft, anders de tag zelf.
    public let webURL: URL
    /// Datum van de tag (of de commit erachter). Ontbreekt in oude JSON en bij een provider die
    /// alleen in `PRProvider.datedTags` datums geeft.
    public let createdAt: Date?
    /// De GitHub-release bij deze tag; `nil` zonder release, bij Azure DevOps en in oude JSON.
    /// Concepten komen hier nooit.
    public let release: ReleaseInfo?

    public init(
        accountId: UUID,
        repo: String,
        name: String,
        authorName: String?,
        authorAvatarURL: URL? = nil,
        webURL: URL,
        createdAt: Date? = nil,
        release: ReleaseInfo? = nil
    ) {
        self.accountId = accountId
        self.repo = repo
        self.name = name
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.webURL = webURL
        self.createdAt = createdAt
        self.release = release
    }

    public var dedupKey: String { "\(accountId.uuidString):\(repo.lowercased()):tag:\(name)" }

    /// De titel van de release als die iets anders zegt dan de tagnaam, anders `nil`.
    public var releaseTitle: String? {
        guard let title = release?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, title != name else { return nil }
        return title
    }
}

/// Een gepubliceerde GitHub-release bij een tag.
public struct ReleaseInfo: Codable, Hashable, Sendable {
    /// De naam van de release; leeg of `nil` als die niet is ingevuld.
    public var title: String?
    /// Wie de release publiceerde (kan een bot zijn, bv. `github-actions[bot]`).
    public var authorLogin: String?
    public var authorAvatarURL: URL?
    public var isPrerelease: Bool
    public var publishedAt: Date?
    public var url: URL

    public init(
        title: String?,
        authorLogin: String? = nil,
        authorAvatarURL: URL? = nil,
        isPrerelease: Bool = false,
        publishedAt: Date? = nil,
        url: URL
    ) {
        self.title = title
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.isPrerelease = isPrerelease
        self.publishedAt = publishedAt
        self.url = url
    }
}

/// Resultaat van `PRProvider.tags(in:)`.
public struct TagFetch: Equatable, Sendable {
    public var tags: [Tag]
    /// Repo's die overgeslagen zijn (404 of geen toegang); exact de doorgegeven repo-strings.
    public var unavailableRepos: [String]
    /// Per repo (exact de doorgegeven repo-string) een vingerafdruk van de nieuwste tag en
    /// release, voor `PRProvider.tags(in:unchanged:)`. Leeg bij een provider zonder.
    public var fingerprints: [String: String]
    /// Repo's waarvan de vingerafdruk niet veranderde: van die repo's staan er geen tags in `tags`.
    public var unchangedRepos: [String]

    public init(
        tags: [Tag],
        unavailableRepos: [String] = [],
        fingerprints: [String: String] = [:],
        unchangedRepos: [String] = []
    ) {
        self.tags = tags
        self.unavailableRepos = unavailableRepos
        self.fingerprints = fingerprints
        self.unchangedRepos = unchangedRepos
    }
}

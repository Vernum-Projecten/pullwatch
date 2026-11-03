import Foundation

public enum ProviderKind: String, Codable, Hashable, Sendable, CaseIterable {
    // Een nieuwe dienst komt erbij als nieuwe case; de rawValue staat in config.json en
    // verandert nooit, zodat een bestaande config gewoon blijft decoderen.
    case azureDevOps, gitHub, gitLab

    /// Productnaam, in elke taal hetzelfde.
    public var name: String {
        switch self {
        case .azureDevOps: "Azure DevOps"
        case .gitHub: "GitHub"
        case .gitLab: "GitLab"
        }
    }

    /// Kan een account van deze dienst op een eigen server staan (`Account.instanceURL`)?
    public var supportsInstanceURL: Bool { self == .gitLab }

    /// Het adres van de dienst zonder eigen server; Azure DevOps heeft er een per organisatie.
    public var defaultInstanceURL: URL? {
        switch self {
        case .azureDevOps: nil
        case .gitHub: URL(string: "https://github.com")
        case .gitLab: URL(string: "https://gitlab.com")
        }
    }
}

public enum ItemKind: String, Codable, Sendable {
    case pullRequest, tag
}

public enum AuthMethod: String, Codable, Hashable, Sendable, CaseIterable {
    /// Personal access token in de Keychain.
    case pat
    /// Het token van `az` of `gh`.
    case cli
    /// Inloggen met GitHub via de Pullwatch GitHub App (alleen GitHub); tokens in de Keychain.
    case gitHubApp
}

/// Alleen nog gebruikt om oude configuratie te migreren.
public enum FilterMode: String, Codable, Hashable, Sendable, CaseIterable {
    case allow, deny
}

/// Wat er voor één repo gevolgd wordt.
public struct WatchSet: Codable, Hashable, Sendable {
    public var prs: Bool
    public var tags: Bool
    /// Melding als een PR in deze repo gemerged (completed) wordt.
    public var completed: Bool
    /// Melding bij een nieuwe PR; uit = wel volgen (menu, geschiedenis), geen melding.
    public var notifyPRs: Bool
    public var notifyTags: Bool
    public var notifyCompleted: Bool

    public init(
        prs: Bool, tags: Bool, completed: Bool = false,
        notifyPRs: Bool = true, notifyTags: Bool = true, notifyCompleted: Bool = true
    ) {
        self.prs = prs
        self.tags = tags
        self.completed = completed
        self.notifyPRs = notifyPRs
        self.notifyTags = notifyTags
        self.notifyCompleted = notifyCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case prs, tags, completed, notifyPRs, notifyTags, notifyCompleted
    }

    /// Oude JSON heeft geen `completed` (dan uit) en geen meldingskeuzes (dan aan).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prs = try c.decode(Bool.self, forKey: .prs)
        tags = try c.decode(Bool.self, forKey: .tags)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        notifyPRs = try c.decodeIfPresent(Bool.self, forKey: .notifyPRs) ?? true
        notifyTags = try c.decodeIfPresent(Bool.self, forKey: .notifyTags) ?? true
        notifyCompleted = try c.decodeIfPresent(Bool.self, forKey: .notifyCompleted) ?? true
    }

    public static let none = WatchSet(prs: false, tags: false)
    public static let prs = WatchSet(prs: true, tags: false)
    public static let tags = WatchSet(prs: false, tags: true)
    public static let both = WatchSet(prs: true, tags: true)

    /// Volgt deze set dit soort? Aanzetten zet ook de melding ervan aan. Gemerged hoort bij de
    /// PR's: PR's uit zet gemerged uit, gemerged aan zet PR's aan.
    public subscript(follows kind: WatchKind) -> Bool {
        get {
            switch kind {
            case .pullRequests: prs
            case .tags: tags
            case .merged: completed
            }
        }
        set {
            switch kind {
            case .pullRequests:
                prs = newValue
                if newValue { notifyPRs = true } else { completed = false }
            case .tags:
                tags = newValue
                if newValue { notifyTags = true }
            case .merged:
                completed = newValue
                if newValue {
                    notifyCompleted = true
                    if !prs { prs = true; notifyPRs = true }
                }
            }
        }
    }

    /// Een melding bij dit soort (alleen zinvol als het gevolgd wordt).
    public subscript(notifies kind: WatchKind) -> Bool {
        get {
            switch kind {
            case .pullRequests: notifyPRs
            case .tags: notifyTags
            case .merged: notifyCompleted
            }
        }
        set {
            switch kind {
            case .pullRequests: notifyPRs = newValue
            case .tags: notifyTags = newValue
            case .merged: notifyCompleted = newValue
            }
        }
    }
}

/// Wat per repo te volgen is: nieuwe PR's, nieuwe tags en gemergde (completed) PR's.
public enum WatchKind: String, CaseIterable, Identifiable, Sendable {
    case pullRequests, tags, merged
    public var id: Self { self }
}

/// Wat er gevolgd wordt voor repo's zonder eigen instelling. Een nieuw account volgt niets
/// (`none`): je kiest zelf welke repo's, zodat Pullwatch niet een heel account ophaalt. Een
/// config zonder het veld (van vóór die keuze) houdt `prs`.
public enum NewRepoDefault: String, Codable, CaseIterable, Sendable {
    case none, prs, prsAndTags

    public var watchSet: WatchSet {
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

public struct Account: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kind: ProviderKind
    /// Wat dit account volgt: Azure DevOps-organisatie, of bij GitHub het eigen account en/of
    /// organisaties. Eén inlog kan meerdere eigenaren volgen.
    public var owners: [String]
    /// Wie er via de GitHub App is ingelogd (de login, zonder @); nil bij een token of CLI.
    public var login: String?
    public var authMethod: AuthMethod
    /// Per repo wat gevolgd wordt. Azure DevOps: "project/repo", GitHub: "owner/repo".
    public var repoWatch: [String: WatchSet]
    /// Geldt voor repo's die niet in `repoWatch` staan.
    public var newRepoDefault: NewRepoDefault
    public var includeDrafts: Bool
    public var hideOwn: Bool
    /// GitHub CLI: welk `gh`-account (login) het token levert; nil = het actieve account.
    public var cliUser: String?
    /// Uitgezet: Pullwatch haalt niets op en meldt niets voor dit account; de keuzes blijven bewaard.
    public var isPaused: Bool
    /// Eigen server (GitLab self-managed): alleen https, zonder "/" aan het eind
    /// (`InstanceURL.parse`). nil = de standaard van de dienst (`ProviderKind.defaultInstanceURL`).
    public var instanceURL: URL?

    /// Waar de repo's van dit account staan: de eigen server, anders de standaard van de dienst.
    public var effectiveInstanceURL: URL? {
        kind.supportsInstanceURL ? (instanceURL ?? kind.defaultInstanceURL) : kind.defaultInstanceURL
    }

    /// De dienst in namen: de host van een eigen server ("gitlab.example.com"), anders de productnaam.
    public var serviceName: String {
        guard kind.supportsInstanceURL, let host = instanceURL?.host(),
              host != kind.defaultInstanceURL?.host() else { return kind.name }
        return host
    }
    /// Losse repo's die je zelf toevoegde, ook buiten de eigenaren (bv. een openbare repo van een
    /// andere organisatie), in dezelfde vorm als `repoWatch`. Wat er gevolgd wordt staat gewoon in
    /// `repoWatch`. Azure DevOps: "project/repo" binnen de organisatie van het account.
    public var extraRepos: [String]

    /// Volgt dit account iets: een repo met PR's, tags of gemerged, of nieuwe repo's.
    public var followsAnything: Bool {
        newRepoDefault != .none || repoWatch.values.contains { $0.prs || $0.tags || $0.completed }
    }

    /// Is dit een zelf toegevoegde repo (hoofdletterongevoelig)?
    public func isExtra(_ repo: String) -> Bool {
        extraRepos.contains { $0.caseInsensitiveCompare(repo) == .orderedSame }
    }

    /// Voegt een losse repo toe (niet dubbel) en volgt er `watch` van.
    public mutating func addExtraRepo(_ repo: String, watch: WatchSet = .prs) {
        if !isExtra(repo) {
            extraRepos.append(repo)
            extraRepos.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        let key = repoWatch.keys.first { $0.caseInsensitiveCompare(repo) == .orderedSame } ?? repo
        repoWatch[key] = watch
    }

    /// Haalt een losse repo weg, met wat er van gevolgd werd.
    public mutating func removeExtraRepo(_ repo: String) {
        extraRepos.removeAll { $0.caseInsensitiveCompare(repo) == .orderedSame }
        for key in repoWatch.keys where key.caseInsensitiveCompare(repo) == .orderedSame {
            repoWatch[key] = nil
        }
    }

    /// Losse repo's waarvan de eigenaar niet al gevolgd wordt: alleen die hebben bij GitHub een
    /// eigen zoekopdracht nodig. Hoofdletterongevoelig ontdubbeld.
    public var extraReposOutsideOwners: [String] {
        Self.reposOutside(owners: owners, extraRepos)
    }

    /// Zie `extraReposOutsideOwners`; ook voor een provider die alleen de lijsten kent.
    public static func reposOutside(owners: [String], _ repos: [String]) -> [String] {
        var seen: Set<String> = []
        return repos.filter { repo in
            let owner = repo.split(separator: "/", maxSplits: 1).first.map(String.init) ?? repo
            guard !owners.contains(where: { $0.caseInsensitiveCompare(owner) == .orderedSame }) else { return false }
            return seen.insert(repo.lowercased()).inserted
        }
    }

    /// De eerste (of enige) eigenaar; voor Azure DevOps de organisatie. Zetten maakt er de enige van.
    public var organization: String {
        get { owners.first ?? "" }
        set {
            let value = newValue.trimmingCharacters(in: .whitespaces)
            owners = value.isEmpty ? [] : [value]
        }
    }

    /// Naam in lijsten en meldingen: "@login op GitHub" na inloggen met GitHub, anders de
    /// eigenaar(s) op de dienst ("octo op GitHub"); zonder eigenaar alleen de dienst.
    public var displayName: String {
        if let login, !login.isEmpty {
            return String(localized: "@\(login) op \(serviceName)", bundle: .localizedCore, comment: "GitHub-login, dienst")
        }
        let named = owners.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !named.isEmpty else { return kind.name }
        let list = named.formatted(.list(type: .and))
        return String(localized: "\(list) op \(serviceName)", bundle: .localizedCore, comment: "Organisatie(s), groep(en) of gebruiker(s), dienst (GitHub, Azure DevOps, GitLab of de host van een eigen server)")
    }

    /// Een account dat minstens één eigenaar volgt: alleen zo'n account wordt bewaard en gepold.
    public var isComplete: Bool { owners.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

    /// Profielfoto van wie er inlogde, anders van de eerste eigenaar (openbaar, zonder token);
    /// Azure DevOps geeft foto's alleen met inloggen, dus daar nil.
    public var avatarURL: URL? { Self.gitHubAvatarURL(login ?? organization, kind: kind) }

    public static func gitHubAvatarURL(_ login: String, kind: ProviderKind = .gitHub, size: Int = 128) -> URL? {
        let login = login.trimmingCharacters(in: .whitespaces)
        guard kind == .gitHub, !login.isEmpty,
              let encoded = login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://github.com/\(encoded).png?size=\(size)")
    }

    public init(
        id: UUID = UUID(),
        kind: ProviderKind,
        organization: String,
        authMethod: AuthMethod,
        login: String? = nil,
        repoWatch: [String: WatchSet] = [:],
        newRepoDefault: NewRepoDefault = .none,
        includeDrafts: Bool = false,
        hideOwn: Bool = true,
        cliUser: String? = nil,
        isPaused: Bool = false,
        instanceURL: URL? = nil,
        extraRepos: [String] = []
    ) {
        self.id = id
        self.kind = kind
        let organization = organization.trimmingCharacters(in: .whitespaces)
        self.owners = organization.isEmpty ? [] : [organization]
        self.login = login
        self.authMethod = authMethod
        self.repoWatch = repoWatch
        self.newRepoDefault = newRepoDefault
        self.includeDrafts = includeDrafts
        self.hideOwn = hideOwn
        self.cliUser = cliUser
        self.isPaused = isPaused
        self.instanceURL = instanceURL
        self.extraRepos = extraRepos
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, organization, owners, login, authMethod, repoWatch, newRepoDefault, includeDrafts, hideOwn, cliUser, isPaused, instanceURL, extraRepos
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(ProviderKind.self, forKey: .kind)
        // Een vroeger zelf gekozen `displayName` wordt niet meer gelezen: de naam volgt de eigenaren.
        // Van voor meerdere eigenaren: alleen `organization`, die dan de enige eigenaar wordt.
        if let owners = try c.decodeIfPresent([String].self, forKey: .owners) {
            self.owners = owners
        } else {
            let organization = try c.decode(String.self, forKey: .organization)
            owners = organization.isEmpty ? [] : [organization]
        }
        login = try c.decodeIfPresent(String.self, forKey: .login)
        authMethod = try c.decode(AuthMethod.self, forKey: .authMethod)
        (repoWatch, newRepoDefault) = try RepoWatchCoding.decode(from: decoder)
        includeDrafts = try c.decode(Bool.self, forKey: .includeDrafts)
        hideOwn = try c.decode(Bool.self, forKey: .hideOwn)
        cliUser = try c.decodeIfPresent(String.self, forKey: .cliUser)
        isPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        // Van vóór eigen servers: geen veld, dus de standaard van de dienst.
        instanceURL = try c.decodeIfPresent(URL.self, forKey: .instanceURL)
        // Van vóór de losse repo's: geen.
        extraRepos = try c.decodeIfPresent([String].self, forKey: .extraRepos) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        // Nog wel geschreven: oudere Pullwatch-versies hebben het veld nodig om de config te lezen.
        try c.encode(displayName, forKey: .displayName)
        // Ook `organization` (de eerste eigenaar): oudere versies lezen alleen dat veld.
        try c.encode(organization, forKey: .organization)
        try c.encode(owners, forKey: .owners)
        try c.encodeIfPresent(login, forKey: .login)
        try c.encode(authMethod, forKey: .authMethod)
        try c.encode(repoWatch, forKey: .repoWatch)
        try c.encode(newRepoDefault, forKey: .newRepoDefault)
        try c.encode(includeDrafts, forKey: .includeDrafts)
        try c.encode(hideOwn, forKey: .hideOwn)
        try c.encodeIfPresent(cliUser, forKey: .cliUser)
        if isPaused { try c.encode(isPaused, forKey: .isPaused) }
        try c.encodeIfPresent(instanceURL, forKey: .instanceURL)
        if !extraRepos.isEmpty { try c.encode(extraRepos, forKey: .extraRepos) }
    }

    /// Wat er voor deze repo gevolgd wordt (hoofdletterongevoelig).
    /// Webpagina van de repo: Azure DevOps `…/<project>/_git/<repo>`, GitHub `github.com/<eigenaar>/<repo>`.
    public func repoWebURL(_ repo: String) -> URL? {
        switch kind {
        case .azureDevOps:
            let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return URL(string: "https://dev.azure.com")?
                .appending(path: organization).appending(path: parts[0]).appending(path: "_git").appending(path: parts[1])
        case .gitHub:
            return URL(string: "https://github.com")?.appending(path: repo)
        case .gitLab:
            // "groep/subgroep/project" onder de eigen server of gitlab.com.
            return effectiveInstanceURL?.appending(path: repo)
        }
    }

    public func watch(for repo: String) -> WatchSet {
        RepoWatchCoding.lookup(repo, in: repoWatch, default: newRepoDefault)
    }

    /// Schrijft wat er voor deze repo gevolgd wordt. Hergebruikt een bestaande key
    /// (hoofdletterongevoelig); een entry gelijk aan de standaard zonder tags verdwijnt.
    public mutating func setWatch(_ set: WatchSet, for repo: String) {
        let key = repoWatch.keys.first { $0.caseInsensitiveCompare(repo) == .orderedSame } ?? repo
        if set == newRepoDefault.watchSet && !set.tags {
            repoWatch[key] = nil
        } else {
            repoWatch[key] = set
        }
    }

    /// Voegt repo's van de provider en uit de config samen, hoofdletterongevoelig ontdubbeld
    /// (de schrijfwijze van de provider wint) en hoofdletterongevoelig gesorteerd.
    public static func mergedRepoNames(available: [String], configured: [String]) -> [String] {
        var byLowercase: [String: String] = [:]
        for name in configured { byLowercase[name.lowercased()] = name }
        for name in available { byLowercase[name.lowercased()] = name }
        return byLowercase.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Repo's waarvan de tags gevolgd worden, gesorteerd en hoofdletterongevoelig ontdubbeld
    /// (de eerste schrijfwijze in sorteervolgorde wint), zodat een repo niet dubbel opgehaald wordt.
    public var tagRepos: [String] {
        var seen: Set<String> = []
        return repoWatch.filter { $0.value.tags }.keys.sorted().filter { seen.insert($0.lowercased()).inserted }
    }

    /// Volgen repo's zonder eigen instelling ook hun tags? Dan zijn de tag-repo's pas bekend
    /// met de lijst van de dienst (`tagRepos(available:)`).
    public var followsTagsByDefault: Bool { newRepoDefault.watchSet.tags }

    /// Repo's waarvan de tags gevolgd worden, uit de lijst van de dienst plus de eigen
    /// instellingen; hoofdletterongevoelig ontdubbeld (de schrijfwijze van de dienst wint).
    public func tagRepos(available: [String]) -> [String] {
        Account.mergedRepoNames(available: available, configured: Array(repoWatch.keys))
            .filter { watch(for: $0).tags }
    }
}

public enum PRState: String, Codable, Sendable, CaseIterable {
    case open, merged, closed
}

public struct PullRequest: Codable, Hashable, Sendable {
    public let accountId: UUID
    public let repo: String
    public let number: Int
    public var title: String
    public let authorId: String
    public let authorName: String
    public let isDraft: Bool
    public let createdAt: Date
    public let webURL: URL
    public var state: PRState
    public var closedAt: Date?
    /// Wie er naast de auteur aan meewerkte (commit-auteurs en `Co-authored-by:`-trailers),
    /// zonder de auteur zelf en zonder bots. Leeg zolang het niet opgehaald is.
    public var coAuthors: [Person]
    /// Verandert als de PR verandert (GitHub: `updated_at`, Azure DevOps: de laatste commit van de
    /// bronbranch); `PollEngine` haalt de co-auteurs alleen opnieuw op als dit anders is.
    public var revision: String?

    public init(
        accountId: UUID,
        repo: String,
        number: Int,
        title: String,
        authorId: String,
        authorName: String,
        isDraft: Bool,
        createdAt: Date,
        webURL: URL,
        state: PRState = .open,
        closedAt: Date? = nil,
        coAuthors: [Person] = [],
        revision: String? = nil
    ) {
        self.accountId = accountId
        self.repo = repo
        self.number = number
        self.title = title
        self.authorId = authorId
        self.authorName = authorName
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.webURL = webURL
        self.state = state
        self.closedAt = closedAt
        self.coAuthors = coAuthors
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, repo, number, title, authorId, authorName, isDraft, createdAt, webURL, state, closedAt, coAuthors, revision
    }

    /// Oude JSON heeft geen `state`/`closedAt`: dan is de PR open. Zonder `coAuthors` (van vóór de
    /// co-auteurs) is die lijst leeg.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(UUID.self, forKey: .accountId)
        repo = try c.decode(String.self, forKey: .repo)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        authorId = try c.decode(String.self, forKey: .authorId)
        authorName = try c.decode(String.self, forKey: .authorName)
        isDraft = try c.decode(Bool.self, forKey: .isDraft)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        webURL = try c.decode(URL.self, forKey: .webURL)
        state = try c.decodeIfPresent(PRState.self, forKey: .state) ?? .open
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        coAuthors = try c.decodeIfPresent([Person].self, forKey: .coAuthors) ?? []
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
    }

    /// De auteur en daarna de co-auteurs, zoals ze in lijsten en statistieken heten.
    public var contributorNames: [String] { [authorName] + coAuthors.map(\.handle) }

    public var dedupKey: String { "\(accountId.uuidString):\(repo):\(number)" }
}

/// Iemand die aan een PR meewerkte: een GitHub-gebruiker (login, foto) of alleen een naam en
/// e-mailadres uit een commit.
public struct Person: Codable, Hashable, Sendable {
    /// Naam uit de commit of trailer; bij een GitHub-gebruiker zonder naam de login.
    public var name: String
    /// GitHub-login (zonder @), als bekend.
    public var login: String?
    public var email: String?
    public var avatarURL: URL?

    public init(name: String, login: String? = nil, email: String? = nil, avatarURL: URL? = nil) {
        self.name = name
        self.login = login
        self.email = email
        self.avatarURL = avatarURL
    }

    /// Zoals de persoon in lijsten heet: de login (net als `PullRequest.authorName` bij GitHub),
    /// anders de naam.
    public var handle: String { login ?? name }
}

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

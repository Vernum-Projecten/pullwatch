import Foundation

/// Een gevolgd account bij een dienst, met wat er per repo gevolgd wordt; staat in `AppConfig`.
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
    /// Eigen server (GitLab self-managed, GitHub Enterprise Server of `<naam>.ghe.com`): alleen https, zonder "/" aan het eind
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

    /// Een GitHub-account op GitHub Enterprise Server of GHE.com in plaats van github.com.
    public var isGitHubEnterprise: Bool {
        kind == .gitHub && instanceURL != nil && instanceURL != kind.defaultInstanceURL
    }

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
    var extraReposOutsideOwners: [String] {
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
    public var avatarURL: URL? { Self.gitHubAvatarURL(login ?? organization, kind: kind, web: effectiveInstanceURL) }

    /// `<web>/<login>.png`: github.com, of de eigen GitHub Enterprise-server (`web`), die dezelfde
    /// route kent. Een server die alles achter inloggen zet geeft geen foto; dan het symbool.
    public static func gitHubAvatarURL(_ login: String, kind: ProviderKind = .gitHub, size: Int = 128, web: URL? = nil) -> URL? {
        let login = login.trimmingCharacters(in: .whitespaces)
        guard kind == .gitHub, !login.isEmpty,
              let encoded = login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        let base = (web ?? kind.defaultInstanceURL)?.absoluteString ?? "https://github.com"
        return URL(string: "\(base)/\(encoded).png?size=\(size)")
    }

    /// De foto van een auteur: `provided` (wat de API gaf) als die er is, anders de gok
    /// `gitHubAvatarURL(login)`. Een bot (`github-actions[bot]`, `renovate[bot]`) is een GitHub
    /// App: zijn foto staat niet onder `/<naam>.png` (404, met of zonder `[bot]`), dus zonder
    /// foto van de API geen gok maar het persoonssymbool. Een naam met spaties is geen login.
    public static func authorAvatarURL(
        _ provided: URL?, login: String, kind: ProviderKind, size: Int, web: URL? = nil
    ) -> URL? {
        if let provided { return provided }
        guard !login.contains(" "), !login.hasSuffix("[bot]") else { return nil }
        return gitHubAvatarURL(login, kind: kind, size: size, web: web)
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

    /// Webpagina van de repo: Azure DevOps `…/<project>/_git/<repo>`, GitHub `<server>/<eigenaar>/<repo>`.
    public func repoWebURL(_ repo: String) -> URL? {
        switch kind {
        case .azureDevOps:
            let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return URL(string: "https://dev.azure.com")?
                .appending(path: organization).appending(path: parts[0]).appending(path: "_git").appending(path: parts[1])
        case .gitHub, .gitLab:
            // "eigenaar/repo" (GitHub) of "groep/subgroep/project" (GitLab) onder de eigen
            // server, anders github.com of gitlab.com.
            return effectiveInstanceURL?.appending(path: repo)
        }
    }

    /// Wat er voor deze repo gevolgd wordt (hoofdletterongevoelig).
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
    var tagRepos: [String] {
        var seen: Set<String> = []
        return repoWatch.filter { $0.value.tags }.keys.sorted().filter { seen.insert($0.lowercased()).inserted }
    }

    /// Volgen repo's zonder eigen instelling ook hun tags? Dan zijn de tag-repo's pas bekend
    /// met de lijst van de dienst (`tagRepos(available:)`).
    var followsTagsByDefault: Bool { newRepoDefault.watchSet.tags }

    /// Repo's waarvan de tags gevolgd worden, uit de lijst van de dienst plus de eigen
    /// instellingen; hoofdletterongevoelig ontdubbeld (de schrijfwijze van de dienst wint).
    func tagRepos(available: [String]) -> [String] {
        Account.mergedRepoNames(available: available, configured: Array(repoWatch.keys))
            .filter { watch(for: $0).tags }
    }
}

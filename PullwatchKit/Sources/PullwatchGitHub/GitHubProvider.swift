public import Foundation
public import PullwatchCore

/// GitHub (github.com, GitHub Enterprise Server of GHE.com) via REST en GraphQL: de pull requests
/// van de gevolgde eigenaren en losse repo's, tags met releases, bestanden, checks en beveiliging.
public actor GitHubProvider: PRProvider {
    enum OwnerKind { case organization, user }

    let accountId: UUID
    /// De gevolgde eigenaren: het eigen account en/of organisaties.
    let owners: [String]
    let tokenSource: any TokenSource
    let http: any HTTPClient
    let now: @Sendable () -> Date
    /// Waar de API en de webpagina's staan: github.com, GHE.com of een eigen server.
    let endpoints: GitHubEndpoints
    var apiBase: URL { endpoints.api }
    let pageSize = 100
    let maxPages = 10
    private var ownerKinds: [String: OwnerKind] = [:]
    /// Losse repo's (`Account.extraRepos`) waarvan de eigenaar niet gevolgd wordt: die krijgen
    /// een eigen zoekopdracht en mogen zonder token gelezen worden (`GitHubProvider+ExtraRepos`).
    let extraRepos: [String]
    /// Hoe elke losse repo te lezen is, per repo lowercased; zie `access(for:)`.
    var repoAccess: [String: (access: RepoAccess, at: Date)] = [:]
    /// Tot wanneer de limiet voor verzoeken zonder token op is (60 per uur, zoeken 10 per minuut).
    var anonymousPausedUntil: Date?
    /// De server kent een veld uit de GraphQL-vraag voor tags niet (een oudere GitHub Enterprise
    /// Server): tags en releases komen dan via REST.
    var tagsViaREST = false
    /// De server kent de velden voor de telling van de checks niet (een oudere GitHub Enterprise
    /// Server): dan vraagt Pullwatch ze niet meer en heeft een PR geen checks.
    var checksUnsupported = false
    /// De server kent de merge queue niet (een oudere GitHub Enterprise Server): dan vraagt
    /// Pullwatch er niet meer naar en staat geen PR in de rij.
    var mergeQueueUnsupported = false
    /// De PR's (dedupKey) die bij de vorige vraag in de merge queue stonden, voor als een
    /// volgende vraag mislukt: dan blijven ze staan in plaats van even uit de rij te vallen.
    var knownMergeQueues: [String: MergeQueueEntry] = [:]
    /// Hoe het account inlogt: bepaalt welk recht er ontbreekt als GitHub iets weigert (een recht
    /// van de GitHub App, of een scope van het token).
    let authMethod: AuthMethod
    /// Alleen bij de GitHub App: het token waarmee de packages gelezen worden, dat van de GitHub
    /// CLI (`GhCLISource` voor de host van het account). GitHubs Packages-API weigert elk token van
    /// een GitHub App, dus het eigen token gaat nooit naar het register; nil = uitgezet
    /// (`Account.packagesViaCLI`), dan geen packages en geen verzoek.
    let packagesTokenSource: (any TokenSource)?

    public init(
        accountId: UUID,
        owners: [String],
        extraRepos: [String] = [],
        instanceURL: URL? = nil,
        authMethod: AuthMethod = .pat,
        tokenSource: any TokenSource,
        packagesTokenSource: (any TokenSource)? = nil,
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountId = accountId
        self.authMethod = authMethod
        self.packagesTokenSource = packagesTokenSource
        self.endpoints = GitHubEndpoints(instanceURL: instanceURL)
        self.owners = owners.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.extraRepos = Account.reposOutside(owners: self.owners, extraRepos)
        self.tokenSource = tokenSource
        self.http = http
        self.now = now
    }

    public init(
        accountId: UUID,
        owner: String,
        instanceURL: URL? = nil,
        tokenSource: any TokenSource,
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(accountId: accountId, owners: [owner], instanceURL: instanceURL, tokenSource: tokenSource, http: http, now: now)
    }

    public func currentUserId() async throws -> String {
        let user: UserDTO = try await get(apiBase.appending(path: "user"))
        return user.login
    }

    public func testConnection() async throws -> String {
        let login = try await currentUserId()
        for owner in owners {
            do {
                _ = try await resolveOwnerKind(owner)
            } catch ProviderError.server(status: 404) {
                throw ProviderError.noAccess(owner)
            }
        }
        return login
    }

    /// Waar de Pullwatch GitHub App is geïnstalleerd en de ingelogde persoon bij kan: de accounts
    /// en organisaties die als eigenaar te kiezen zijn, het eigen account eerst, dan de
    /// organisaties op naam. Alleen met een token van de GitHub App.
    public func installationOwners() async throws -> [GitHubOwner] {
        struct Page: Decodable {
            struct Installation: Decodable {
                struct Owner: Decodable {
                    let login: String
                    let type: String?
                }
                let account: Owner
            }
            let totalCount: Int
            let installations: [Installation]
        }
        var owners: [GitHubOwner] = []
        var page = 1
        while true {
            let response: Page = try await get(
                apiBase.appending(path: "user/installations"),
                query: [URLQueryItem(name: "per_page", value: String(pageSize)), URLQueryItem(name: "page", value: "\(page)")]
            )
            owners += response.installations.map {
                GitHubOwner(login: $0.account.login, isOrganization: $0.account.type == "Organization")
            }
            if response.installations.isEmpty || owners.count >= response.totalCount { break }
            page += 1
        }
        let me = try? await currentUserId()
        return owners.sorted { lhs, rhs in
            if lhs.login == me { return true }
            if rhs.login == me { return false }
            if lhs.isOrganization != rhs.isOrganization { return !lhs.isOrganization }
            return lhs.login.localizedCaseInsensitiveCompare(rhs.login) == .orderedAscending
        }.map { owner in
            var owner = owner
            owner.isSignedInUser = owner.login == me
            return owner
        }
    }

    /// De repositories van alle gevolgde eigenaren en de losse repo's, op naam.
    public func listRepos() async throws -> [String] {
        var names: [String] = []
        for owner in owners { names += try await listRepos(of: owner) }
        names += await extraRepoNames()
        return Account.mergedRepoNames(available: names, configured: [])
    }

    private func listRepos(of owner: String) async throws -> [String] {
        let url: URL
        var query: [URLQueryItem] = []
        switch try await resolveOwnerKind(owner) {
        case .organization:
            url = apiBase.appending(path: "orgs").appending(path: owner).appending(path: "repos")
        case .user:
            let login = try await currentUserId()
            if login.caseInsensitiveCompare(owner) == .orderedSame {
                // /users/{owner}/repos toont geen private repos; voor jezelf /user/repos gebruiken.
                url = apiBase.appending(path: "user/repos")
                query = [URLQueryItem(name: "affiliation", value: "owner")]
            } else {
                url = apiBase.appending(path: "users").appending(path: owner).appending(path: "repos")
            }
        }

        var names: [String] = []
        for page in 1...maxPages {
            let repos: [RepoDTO] = try await get(url, query: query + [
                URLQueryItem(name: "per_page", value: String(pageSize)),
                URLQueryItem(name: "page", value: String(page)),
            ])
            names += repos.map(\.fullName)
            if repos.count < pageSize { break }
        }
        return names
    }

    /// Open PR's bij alle gevolgde eigenaren: één zoekopdracht per eigenaar (`user:` of `org:`),
    /// plus de losse repo's in gebundelde zoekopdrachten (`repo:`), met hun plek in de merge queue
    /// (`GitHubProvider+MergeQueue`).
    public func openPullRequests() async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for owner in owners {
            let qualifier = try await resolveOwnerKind(owner) == .organization ? "org" : "user"
            result += try await searchPullRequests("is:pr is:open \(qualifier):\(owner)", byUpdate: false, limit: .max)
        }
        result += try await extraPullRequests("is:pr is:open", byUpdate: false, limit: .max)
        return await withMergeQueues(result)
    }

    /// Bijgewerkte PR's bij alle gevolgde eigenaren en losse repo's, nieuwste eerst, samen hooguit `limit`.
    public func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] {
        let updated = since.map { " updated:>=" + $0.formatted(Date.ISO8601FormatStyle(timeZone: .gmt)) } ?? ""
        var result: [PullRequest] = []
        for owner in owners {
            let qualifier = try await resolveOwnerKind(owner) == .organization ? "org" : "user"
            result += try await searchPullRequests("is:pr \(qualifier):\(owner)\(updated)", byUpdate: true, limit: limit)
        }
        result += try await extraPullRequests("is:pr\(updated)", byUpdate: true, limit: limit)
        guard owners.count + (extraRepos.isEmpty ? 0 : 1) > 1 else { return result }
        // Over eigenaren heen de recentste eerst (gesloten, anders geopend), zodat de grens eerlijk is.
        return Array(result.sorted { ($0.closedAt ?? $0.createdAt) > ($1.closedAt ?? $1.createdAt) }.prefix(limit))
    }

    /// Eén zoekopdracht, alle pagina's tot `limit`; `byUpdate` sorteert op laatst bijgewerkt.
    /// `anonymous` zonder token (openbare losse repo's).
    func searchPullRequests(_ q: String, byUpdate: Bool, limit: Int, anonymous: Bool = false) async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for page in 1...maxPages {
            var query = [URLQueryItem(name: "q", value: q)]
            if byUpdate {
                query += [URLQueryItem(name: "sort", value: "updated"), URLQueryItem(name: "order", value: "desc")]
            }
            query += [
                URLQueryItem(name: "per_page", value: String(pageSize)),
                URLQueryItem(name: "page", value: String(page)),
            ]
            let response = try JSONDecoding.decode(
                SearchDTO.self,
                from: try await send(apiBase.appending(path: "search/issues"), query: query, anonymous: anonymous).data,
                snakeCase: true
            )
            for item in response.items {
                result.append(try makePullRequest(item))
            }
            if result.count >= limit || response.items.count < pageSize || result.count >= response.totalCount { break }
        }
        return Array(result.prefix(limit))
    }

    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        let tree: TreeDTO
        do {
            tree = try JSONDecoding.decode(TreeDTO.self, from: try await repoData(
                repo,
                apiBase.appending(path: "repos").appending(path: repo).appending(path: "git/trees").appending(path: ref ?? "HEAD"),
                query: [URLQueryItem(name: "recursive", value: "1")]
            ), snakeCase: true)
        } catch ProviderError.server(status: 409) {
            return [] // lege repo
        }
        return tree.tree.filter { $0.type == "blob" }.map(\.path)
    }

    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        let data = try await repoData(
            repo,
            apiBase.appending(path: "repos").appending(path: repo).appending(path: "contents").appending(path: path),
            query: ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? [],
            accept: "application/vnd.github.raw+json"
        )
        return String(decoding: data, as: UTF8.self)
    }

    public func invalidateCredentials() async {
        await tokenSource.invalidate()
    }

    func resolveOwnerKind(_ owner: String) async throws -> OwnerKind {
        if let kind = ownerKinds[owner] { return kind }
        let info: OwnerDTO = try await get(apiBase.appending(path: "users").appending(path: owner))
        let kind: OwnerKind = info.type == "Organization" ? .organization : .user
        ownerKinds[owner] = kind
        return kind
    }

    private func makePullRequest(_ item: SearchDTO.Item) throws -> PullRequest {
        guard let createdAt = DateParsing.parse(item.createdAt) else {
            throw ProviderError.decoding("created_at \(item.createdAt)")
        }
        guard let webURL = URL(string: item.htmlUrl),
              let repoURL = URL(string: item.repositoryUrl) else {
            throw ProviderError.decoding("url in PR \(item.number)")
        }
        let repo = repoURL.pathComponents.suffix(2).joined(separator: "/")
        let state: PRState = (item.state ?? "open") == "open" ? .open : (item.pullRequest?.mergedAt != nil ? .merged : .closed)
        return PullRequest(
            accountId: accountId,
            repo: repo,
            number: item.number,
            title: item.title,
            authorId: item.user.login,
            authorName: item.user.login,
            authorAvatarURL: item.user.avatarUrl.flatMap(URL.init(string:)),
            isDraft: item.draft ?? false,
            createdAt: createdAt,
            webURL: webURL,
            state: state,
            closedAt: item.closedAt.flatMap(DateParsing.parse),
            revision: item.updatedAt
        )
    }
}

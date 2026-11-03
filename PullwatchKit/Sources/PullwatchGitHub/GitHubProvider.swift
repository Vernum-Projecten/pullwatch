import Foundation
import PullwatchCore

public actor GitHubProvider: PRProvider {
    enum OwnerKind { case organization, user }

    let accountId: UUID
    /// De gevolgde eigenaren: het eigen account en/of organisaties.
    private let owners: [String]
    let tokenSource: any TokenSource
    let http: any HTTPClient
    let now: @Sendable () -> Date
    let apiBase = URL(string: "https://api.github.com")!
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

    public init(
        accountId: UUID,
        owners: [String],
        extraRepos: [String] = [],
        tokenSource: any TokenSource,
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountId = accountId
        self.owners = owners.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.extraRepos = Account.reposOutside(owners: self.owners, extraRepos)
        self.tokenSource = tokenSource
        self.http = http
        self.now = now
    }

    public init(
        accountId: UUID,
        owner: String,
        tokenSource: any TokenSource,
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(accountId: accountId, owners: [owner], tokenSource: tokenSource, http: http, now: now)
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
                query: [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: "\(page)")]
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
    /// plus de losse repo's in gebundelde zoekopdrachten (`repo:`).
    public func openPullRequests() async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for owner in owners {
            let qualifier = try await resolveOwnerKind(owner) == .organization ? "org" : "user"
            result += try await searchPullRequests("is:pr is:open \(qualifier):\(owner)", byUpdate: false, limit: .max)
        }
        result += try await extraPullRequests("is:pr is:open", byUpdate: false, limit: .max)
        return result
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

    public func tags(in repos: [String]) async throws -> TagFetch {
        try await tags(in: repos, unchanged: [:])
    }

    /// Via GraphQL, met aliassen voor meerdere repo's per verzoek: per repo de nieuwste tags (met
    /// tagger, commit-auteur en datum) en releases. Repo's met een bekende vingerafdruk krijgen
    /// eerst een kleine vraag (één tag en één release per repo); alleen wat veranderde wordt
    /// daarna helemaal opgehaald. Een repo die niet (meer) bestaat of geen toegang geeft
    /// (GraphQL geeft dan `null`, de hele batch 401/403) komt in `unavailableRepos`.
    public func tags(in repos: [String], unchanged known: [String: String]) async throws -> TagFetch {
        var fetch = TagFetch(tags: [])
        // Losse repo's die alleen zonder token te lezen zijn gaan via REST (GraphQL vraagt altijd
        // een token); de rest gaat samen via GraphQL.
        let (signed, unsigned, unavailable) = try await splitByAccess(repos)
        fetch.unavailableRepos += unavailable
        for repo in unsigned { await restTags(repo, into: &fetch) }
        let repos = signed
        var changed = repos.filter { known[$0] == nil }
        let checked = repos.filter { known[$0] != nil }
        for batch in checked.chunked(Self.fingerprintBatchSize) {
            let nodes = try await repositoryTags(batch, tags: 1, releases: 1, fetch: &fetch)
            for repo in batch {
                guard let node = nodes[repo] else { continue }
                if node.fingerprint == known[repo] {
                    fetch.unchangedRepos.append(repo)
                    fetch.fingerprints[repo] = node.fingerprint
                } else {
                    changed.append(repo)
                }
            }
        }
        for batch in changed.chunked(Self.tagBatchSize) {
            let nodes = try await repositoryTags(batch, tags: Self.tagLimit, releases: Self.releaseLimit, fetch: &fetch)
            for repo in batch {
                guard let node = nodes[repo] else { continue }
                fetch.fingerprints[repo] = node.fingerprint
                fetch.tags += makeTags(repo: repo, node)
            }
        }
        // Een losse repo die GraphQL niet gaf: nog één keer via REST, met token en anders zonder.
        for repo in fetch.unavailableRepos where isExtra(repo) && repos.contains(repo) {
            fetch.unavailableRepos.removeAll { $0 == repo }
            await restTags(repo, into: &fetch)
        }
        return fetch
    }

    /// Repo's per GraphQL-verzoek voor de volledige vraag (tot honderd tags elk) en voor de
    /// vingerafdrukken (één tag en één release elk).
    static let tagBatchSize = 10
    static let fingerprintBatchSize = 50
    /// Zoveel nieuwste tags en releases per repo.
    static let tagLimit = 100
    static let releaseLimit = 20

    /// Eén GraphQL-verzoek voor `repos`; geeft per gevonden repo zijn tags en releases. Wat
    /// niet gevonden wordt of geen toegang geeft komt in `fetch.unavailableRepos`.
    private func repositoryTags(
        _ repos: [String],
        tags: Int,
        releases: Int,
        fetch: inout TagFetch
    ) async throws -> [String: TagQuery.Repository] {
        var variables: [String: String] = [:]
        var valid: [(alias: String, repo: String)] = []
        for repo in repos {
            let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                fetch.unavailableRepos.append(repo)
                continue
            }
            let index = valid.count
            variables["o\(index)"] = parts[0]
            variables["n\(index)"] = parts[1]
            valid.append(("r\(index)", repo))
        }
        guard !valid.isEmpty else { return [:] }
        let request = TagQuery(query: TagQuery.text(count: valid.count, tags: tags, releases: releases), variables: variables)
        let response: TagQuery.Response
        let headers: HTTPURLResponse
        do {
            let (body, http) = try await send(apiBase.appending(path: "graphql"), body: try JSONEncoder().encode(request))
            response = try JSONDecoding.decode(TagQuery.Response.self, from: body)
            headers = http
        } catch ProviderError.unauthorized {
            fetch.unavailableRepos += valid.map(\.repo) // geen toegang (403: SSO, rechten, IP-allowlist)
            return [:]
        }
        // GraphQL meldt een opgebruikte limiet met status 200 en een fout van het type RATE_LIMITED.
        if response.errors?.contains(where: { $0.type == "RATE_LIMITED" }) == true {
            let reset = headers.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init)
            throw ProviderError.rateLimited(until: reset.map(Date.init(timeIntervalSince1970:)) ?? now() + 60)
        }
        guard let payload = response.data else {
            throw ProviderError.decoding("GraphQL: \(response.errors?.first?.message ?? "geen data")")
        }
        var result: [String: TagQuery.Repository] = [:]
        for (alias, repo) in valid {
            if let node = payload[alias] ?? nil {
                result[repo] = node
            } else {
                fetch.unavailableRepos.append(repo) // bestaat niet (meer) of geen toegang
            }
        }
        return result
    }

    /// De tags van één repo, met hun release (geen concepten). De auteur is wie de release
    /// publiceerde, maar een bot (zoals `github-actions[bot]`) maakt plaats voor de tagger of
    /// de auteur van de commit: die persoon zette de release echt in gang.
    private func makeTags(repo: String, _ node: TagQuery.Repository) -> [Tag] {
        var releases: [String: TagQuery.Release] = [:]
        for release in node.releases.nodes where !release.isDraft && releases[release.tagName] == nil {
            releases[release.tagName] = release
        }
        return node.refs.nodes.compactMap { ref in
            guard let treeURL = tagTreeURL(repo: repo, tag: ref.name) else { return nil }
            let target = ref.target
            let tagger = target?.tagger
            let commit = target?.target ?? target.map { TagQuery.Commit(committedDate: $0.committedDate, author: $0.author) }
            let release = releases[ref.name]
            let releaseInfo = release.flatMap { release in
                URL(string: release.url).map { url in
                    ReleaseInfo(
                        title: release.name,
                        authorLogin: release.author?.login,
                        authorAvatarURL: release.author.flatMap { URL(string: $0.avatarUrl) },
                        isPrerelease: release.isPrerelease,
                        publishedAt: release.publishedAt.flatMap(DateParsing.parse),
                        url: url
                    )
                }
            }
            let releaseAuthor = release?.author.map { (name: $0.login, avatar: URL(string: $0.avatarUrl)) }
            let people = [
                releaseAuthor.flatMap { $0.name.hasSuffix("[bot]") ? nil : $0 },
                tagger?.person,
                commit?.author?.person,
                releaseAuthor,
            ]
            let author = people.compactMap { $0 }.first
            return Tag(
                accountId: accountId,
                repo: repo,
                name: ref.name,
                authorName: author?.name,
                authorAvatarURL: author?.avatar,
                webURL: releaseInfo?.url ?? treeURL,
                createdAt: (tagger?.date ?? commit?.committedDate).flatMap(DateParsing.parse),
                release: releaseInfo
            )
        }
    }

    /// De nieuwste tags van één repo met datum, uit dezelfde GraphQL-vraag als `tags(in:)`. Een
    /// repo die niet (meer) bestaat geeft een lege lijst.
    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        guard limit > 0 else { return [] }
        let tags = try await tags(in: [repo]).tags.filter { $0.createdAt != nil }
        return Array(tags.sorted { $0.createdAt! > $1.createdAt! }.prefix(limit))
    }

    /// Een tag zonder release opent de bestanden op die tag; een release-pagina bestaat dan
    /// niet. De tagnaam wordt als één padsegment gecodeerd, dus "/" wordt %2F en "+" wordt %2B.
    func tagTreeURL(repo: String, tag: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = tag.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://github.com/\(repo)/tree/\(encoded)")
    }

    /// PR's per GraphQL-verzoek bij `coAuthors(of:)`.
    static let coAuthorBatch = 20

    /// Via GraphQL, twintig PR's per verzoek (aliassen `pr0`, `pr1`, …): de auteurs van de laatste
    /// vijftig commits. GitHub zet de `Co-authored-by:`-trailers daar zelf bij en koppelt ze aan
    /// gebruikers met hun foto. Een PR die niet (meer) bestaat geeft een lege lijst.
    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        var result: [String: [Person]] = [:]
        // Repo's die alleen zonder token te lezen zijn slaan we over: GraphQL vraagt een token.
        let known = pullRequests.filter { $0.repo.split(separator: "/").count == 2 && !readsWithoutToken($0.repo) }
        for start in stride(from: 0, to: known.count, by: Self.coAuthorBatch) {
            let batch = Array(known[start..<min(start + Self.coAuthorBatch, known.count)])
            let request = CoAuthorQueryDTO(batch)
            let data = try await data(apiBase.appending(path: "graphql"), body: try JSONEncoder().encode(request))
            let response = try JSONDecoding.decode(CoAuthorQueryDTO.Response.self, from: data)
            // Zonder `data` mislukte het hele verzoek (bv. de GraphQL-limiet): later opnieuw.
            guard let found = response.data else { throw ProviderError.decoding("graphql co-auteurs") }
            for (index, pr) in batch.enumerated() {
                let commits = found["pr\(index)"]??.pullRequest?.commits.nodes ?? []
                let candidates = commits.flatMap { $0.commit.authors.nodes }.map { author in
                    Person(
                        name: author.name ?? author.user?.login ?? author.email ?? "",
                        login: author.user?.login,
                        email: author.email,
                        avatarURL: author.user?.avatarUrl.flatMap(URL.init(string:))
                    )
                }.filter { !$0.name.isEmpty }
                result[pr.dedupKey] = CoAuthorTrailer.coAuthors(from: candidates, author: [pr.authorId, pr.authorName])
            }
        }
        return result
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
            isDraft: item.draft ?? false,
            createdAt: createdAt,
            webURL: webURL,
            state: state,
            closedAt: item.closedAt.flatMap(DateParsing.parse),
            revision: item.updatedAt
        )
    }

    private func get<T: Decodable>(_ url: URL, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoding.decode(T.self, from: try await data(url, query: query), snakeCase: true)
    }

    private func data(
        _ url: URL,
        query: [URLQueryItem] = [],
        accept: String = "application/vnd.github+json",
        body: Data? = nil
    ) async throws -> Data {
        try await send(url, query: query, accept: accept, body: body).data
    }

    /// Met `checked: false` zonder de status te controleren (de beveiligingsgegevens lezen 403
    /// en 404 zelf). Met `anonymous` zonder token: alleen voor openbare losse repo's.
    func send(
        _ url: URL,
        query: [URLQueryItem] = [],
        accept: String = "application/vnd.github+json",
        body: Data? = nil,
        checked: Bool = true,
        anonymous: Bool = false
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !anonymous {
            let token = try await tokenSource.token()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await http.send(request)
        if checked { try HTTPStatus.check(response, now: now()) }
        return (data, response)
    }
}

extension Array {
    /// Opeenvolgende stukken van hooguit `size` elementen.
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

private struct UserDTO: Decodable {
    let login: String
}

private struct OwnerDTO: Decodable {
    let type: String
}

private struct RepoDTO: Decodable {
    let fullName: String
}

private struct SearchDTO: Decodable {
    struct PullRequestInfo: Decodable {
        let mergedAt: String?
    }

    struct Item: Decodable {
        let number: Int
        let title: String
        let createdAt: String
        let updatedAt: String?
        let draft: Bool?
        let state: String?
        let closedAt: String?
        let pullRequest: PullRequestInfo?
        let user: UserDTO
        let htmlUrl: String
        let repositoryUrl: String
    }

    let totalCount: Int
    let items: [Item]
}

private struct TreeDTO: Decodable {
    struct Entry: Decodable {
        let path: String
        let type: String
    }

    let tree: [Entry]
}

/// GraphQL: per repo (alias `r0`, `r1`, …; variabelen `o0`/`n0` voor eigenaar en naam) de
/// nieuwste tags op datum, met tagger en commit-auteur, en de nieuwste releases.
private struct TagQuery: Encodable {
    let query: String
    let variables: [String: String]

    static func text(count: Int, tags: Int, releases: Int) -> String {
        let declarations = (0..<count).map { "$o\($0): String!, $n\($0): String!" }.joined(separator: ", ")
        let fields = (0..<count).map { "  r\($0): repository(owner: $o\($0), name: $n\($0)) { ...TagsAndReleases }" }
            .joined(separator: "\n")
        return """
            query(\(declarations)) {
            \(fields)
            }
            fragment TagsAndReleases on Repository {
              refs(refPrefix: "refs/tags/", first: \(tags), orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
                totalCount
                nodes {
                  name
                  target {
                    ...CommitInfo
                    ... on Tag { tagger { ...Actor date } target { ...CommitInfo } }
                  }
                }
              }
              releases(first: \(releases), orderBy: {field: CREATED_AT, direction: DESC}) {
                totalCount
                nodes { id tagName name isDraft isPrerelease publishedAt updatedAt url author { login avatarUrl } }
              }
            }
            fragment CommitInfo on Commit { committedDate author { ...Actor } }
            fragment Actor on GitActor { name avatarUrl user { login avatarUrl } }
            """
    }

    struct Response: Decodable {
        struct GraphQLError: Decodable {
            let type: String?
            let message: String?
        }

        let data: [String: Repository?]?
        let errors: [GraphQLError]?
    }

    struct Repository: Decodable {
        struct Refs: Decodable {
            let totalCount: Int
            let nodes: [Ref]
        }

        struct Releases: Decodable {
            let totalCount: Int
            let nodes: [Release]
        }

        let refs: Refs
        let releases: Releases

        /// Verandert zodra er een tag of release bij komt, verdwijnt of een release verandert
        /// (bv. van concept naar gepubliceerd, of van pre-release naar release).
        var fingerprint: String {
            let release = releases.nodes.first
            return [
                "\(refs.totalCount)", refs.nodes.first?.name ?? "",
                "\(releases.totalCount)", release?.id ?? "", release?.updatedAt ?? "",
                release.map { "\($0.isDraft)/\($0.isPrerelease)" } ?? "",
            ].joined(separator: "|")
        }
    }

    struct Ref: Decodable {
        let name: String
        let target: Target?
    }

    /// Een `Commit` (lichte tag) of een `Tag` (geannoteerde tag) met de commit erachter.
    struct Target: Decodable {
        let committedDate: String?
        let author: Actor?
        let tagger: Actor?
        let target: Commit?
    }

    struct Commit: Decodable {
        let committedDate: String?
        let author: Actor?
    }

    struct Actor: Decodable {
        struct User: Decodable {
            let login: String
            let avatarUrl: String?
        }

        let name: String?
        let avatarUrl: String?
        let date: String?
        let user: User?

        /// De GitHub-login als die bekend is, anders de naam uit git; met foto.
        var person: (name: String, avatar: URL?)? {
            if let user { return (user.login, (user.avatarUrl ?? avatarUrl).flatMap(URL.init(string:))) }
            guard let name, !name.isEmpty else { return nil }
            return (name, avatarUrl.flatMap(URL.init(string:)))
        }
    }

    struct Release: Decodable {
        struct Author: Decodable {
            let login: String
            let avatarUrl: String
        }

        let id: String
        let tagName: String
        let name: String?
        let isDraft: Bool
        let isPrerelease: Bool
        let publishedAt: String?
        let updatedAt: String?
        let url: String
        let author: Author?
    }
}

/// GraphQL: de commit-auteurs (met co-auteurs) van een reeks PR's, elk onder een eigen alias.
private struct CoAuthorQueryDTO: Encodable {
    let query: String
    let variables: [String: Variable]

    enum Variable: Encodable {
        case text(String)
        case number(Int)

        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text(let value): try c.encode(value)
            case .number(let value): try c.encode(value)
            }
        }
    }

    init(_ pullRequests: [PullRequest]) {
        var declarations: [String] = []
        var fields: [String] = []
        var variables: [String: Variable] = [:]
        for (index, pr) in pullRequests.enumerated() {
            let parts = pr.repo.split(separator: "/", maxSplits: 1).map(String.init)
            declarations.append("$o\(index): String!, $n\(index): String!, $p\(index): Int!")
            fields.append("""
                  pr\(index): repository(owner: $o\(index), name: $n\(index)) {
                    pullRequest(number: $p\(index)) {
                      commits(last: 50) { nodes { commit { authors(first: 5) { nodes { name email user { login avatarUrl } } } } } }
                    }
                  }
                """)
            variables["o\(index)"] = .text(parts[0])
            variables["n\(index)"] = .text(parts[1])
            variables["p\(index)"] = .number(pr.number)
        }
        query = "query(" + declarations.joined(separator: ", ") + ") {\n" + fields.joined(separator: "\n") + "\n}"
        self.variables = variables
    }

    struct Response: Decodable {
        struct Repository: Decodable { let pullRequest: PullRequestNode? }
        struct PullRequestNode: Decodable { let commits: Commits }
        struct Commits: Decodable { let nodes: [CommitNode] }
        struct CommitNode: Decodable { let commit: Commit }
        struct Commit: Decodable { let authors: Authors }
        struct Authors: Decodable { let nodes: [Author] }
        struct Author: Decodable {
            struct User: Decodable {
                let login: String
                let avatarUrl: String?
            }
            let name: String?
            let email: String?
            let user: User?
        }

        let data: [String: Repository?]?
    }
}

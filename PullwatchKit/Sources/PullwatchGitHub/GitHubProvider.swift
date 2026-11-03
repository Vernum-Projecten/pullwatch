import Foundation
import PullwatchCore

public actor GitHubProvider: PRProvider {
    private enum OwnerKind { case organization, user }

    private let accountId: UUID
    /// De gevolgde eigenaren: het eigen account en/of organisaties.
    private let owners: [String]
    private let tokenSource: any TokenSource
    private let http: any HTTPClient
    private let now: @Sendable () -> Date
    private let apiBase = URL(string: "https://api.github.com")!
    private let pageSize = 100
    private let maxPages = 10
    private var ownerKinds: [String: OwnerKind] = [:]

    public init(
        accountId: UUID,
        owners: [String],
        tokenSource: any TokenSource,
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountId = accountId
        self.owners = owners.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
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

    /// De repositories van alle gevolgde eigenaren, op naam.
    public func listRepos() async throws -> [String] {
        var names: [String] = []
        for owner in owners { names += try await listRepos(of: owner) }
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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

    /// Open PR's bij alle gevolgde eigenaren: één zoekopdracht per eigenaar (`user:` of `org:`).
    public func openPullRequests() async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for owner in owners { result += try await openPullRequests(of: owner) }
        return result
    }

    private func openPullRequests(of owner: String) async throws -> [PullRequest] {
        let qualifier = try await resolveOwnerKind(owner) == .organization ? "org" : "user"
        var result: [PullRequest] = []
        for page in 1...maxPages {
            let response: SearchDTO = try await get(apiBase.appending(path: "search/issues"), query: [
                URLQueryItem(name: "q", value: "is:pr is:open \(qualifier):\(owner)"),
                URLQueryItem(name: "per_page", value: String(pageSize)),
                URLQueryItem(name: "page", value: String(page)),
            ])
            for item in response.items {
                result.append(try makePullRequest(item))
            }
            if response.items.count < pageSize || result.count >= response.totalCount { break }
        }
        return result
    }

    /// Bijgewerkte PR's bij alle gevolgde eigenaren, nieuwste eerst, samen hooguit `limit`.
    public func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for owner in owners { result += try await pullRequests(of: owner, updatedSince: since, limit: limit) }
        guard owners.count > 1 else { return result }
        // Over eigenaren heen de recentste eerst (gesloten, anders geopend), zodat de grens eerlijk is.
        return Array(result.sorted { ($0.closedAt ?? $0.createdAt) > ($1.closedAt ?? $1.createdAt) }.prefix(limit))
    }

    private func pullRequests(of owner: String, updatedSince since: Date?, limit: Int) async throws -> [PullRequest] {
        let qualifier = try await resolveOwnerKind(owner) == .organization ? "org" : "user"
        var q = "is:pr \(qualifier):\(owner)"
        if let since {
            q += " updated:>=" + since.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))
        }
        var result: [PullRequest] = []
        for page in 1...maxPages {
            let response: SearchDTO = try await get(apiBase.appending(path: "search/issues"), query: [
                URLQueryItem(name: "q", value: q),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: String(pageSize)),
                URLQueryItem(name: "page", value: String(page)),
            ])
            for item in response.items {
                result.append(try makePullRequest(item))
            }
            if result.count >= limit || response.items.count < pageSize || result.count >= response.totalCount { break }
        }
        return Array(result.prefix(limit))
    }

    public func tags(in repos: [String]) async throws -> TagFetch {
        var result: [Tag] = []
        var unavailable: [String] = []
        for repo in repos {
            do {
                for page in 1...maxPages {
                    let dtos: [TagDTO] = try await get(
                        apiBase.appending(path: "repos").appending(path: repo).appending(path: "tags"),
                        query: [
                            URLQueryItem(name: "per_page", value: String(pageSize)),
                            URLQueryItem(name: "page", value: String(page)),
                        ]
                    )
                    for dto in dtos {
                        guard let url = tagURL(repo: repo, tag: dto.name) else { continue }
                        result.append(Tag(accountId: accountId, repo: repo, name: dto.name, authorName: nil, webURL: url))
                    }
                    if dtos.count < pageSize { break }
                }
            } catch ProviderError.server(status: 404) {
                unavailable.append(repo) // repo bestaat niet (meer)
                continue
            } catch ProviderError.unauthorized {
                unavailable.append(repo) // geen toegang (403: SSO, rechten, IP-allowlist); andere repo's gaan door
                continue
            }
        }
        return TagFetch(tags: result, unavailableRepos: unavailable)
    }

    /// Via GraphQL, in één verzoek: de REST-lijst van tags heeft geen datums. Een geannoteerde
    /// tag krijgt de datum van de tagger, een lichte tag die van de commit. Een repo die niet
    /// (meer) bestaat geeft een lege lijst.
    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, limit > 0 else { return [] }
        let request = TagQueryDTO(
            query: TagQueryDTO.text,
            variables: .init(owner: parts[0], name: parts[1], first: min(limit, pageSize))
        )
        let response = try JSONDecoding.decode(
            TagQueryDTO.Response.self,
            from: try await data(apiBase.appending(path: "graphql"), body: try JSONEncoder().encode(request))
        )
        return (response.data?.repository?.refs.nodes ?? []).compactMap { node in
            guard let url = tagURL(repo: repo, tag: node.name),
                  let date = (node.target.tagger?.date ?? node.target.committedDate ?? node.target.target?.committedDate)
                .flatMap(DateParsing.parse) else { return nil }
            return Tag(accountId: accountId, repo: repo, name: node.name, authorName: nil, webURL: url, createdAt: date)
        }
    }

    /// De tagnaam wordt als één padsegment gecodeerd, dus "/" wordt %2F en "+" wordt %2B.
    private func tagURL(repo: String, tag: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = tag.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://github.com/\(repo)/releases/tag/\(encoded)")
    }

    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        let tree: TreeDTO
        do {
            tree = try await get(
                apiBase.appending(path: "repos").appending(path: repo).appending(path: "git/trees").appending(path: ref ?? "HEAD"),
                query: [URLQueryItem(name: "recursive", value: "1")]
            )
        } catch ProviderError.server(status: 409) {
            return [] // lege repo
        }
        return tree.tree.filter { $0.type == "blob" }.map(\.path)
    }

    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        let data = try await data(
            apiBase.appending(path: "repos").appending(path: repo).appending(path: "contents").appending(path: path),
            query: ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? [],
            accept: "application/vnd.github.raw+json"
        )
        return String(decoding: data, as: UTF8.self)
    }

    public func invalidateCredentials() async {
        await tokenSource.invalidate()
    }

    private func resolveOwnerKind(_ owner: String) async throws -> OwnerKind {
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
            closedAt: item.closedAt.flatMap(DateParsing.parse)
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
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let token = try await tokenSource.token()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await http.send(request)
        try HTTPStatus.check(response, now: now())
        return data
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

private struct TagDTO: Decodable {
    let name: String
}

/// GraphQL: de nieuwste tags van één repo, op datum, met de datum van tagger of commit.
private struct TagQueryDTO: Encodable {
    static let text = """
        query($owner: String!, $name: String!, $first: Int!) {
          repository(owner: $owner, name: $name) {
            refs(refPrefix: "refs/tags/", first: $first, orderBy: {field: TAG_COMMIT_DATE, direction: DESC}) {
              nodes {
                name
                target {
                  ... on Commit { committedDate }
                  ... on Tag { tagger { date } target { ... on Commit { committedDate } } }
                }
              }
            }
          }
        }
        """

    struct Variables: Encodable {
        let owner: String
        let name: String
        let first: Int
    }

    let query: String
    let variables: Variables

    struct Response: Decodable {
        struct Payload: Decodable { let repository: Repository? }
        struct Repository: Decodable { let refs: Refs }
        struct Refs: Decodable { let nodes: [Node] }
        struct Node: Decodable {
            let name: String
            let target: Target
        }
        struct Target: Decodable {
            struct Tagger: Decodable { let date: String? }
            struct Inner: Decodable { let committedDate: String? }
            let committedDate: String?
            let tagger: Tagger?
            let target: Inner?
        }

        let data: Payload?
    }
}

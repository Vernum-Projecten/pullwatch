import Foundation
import PullwatchCore

public actor AzureDevOpsProvider: PRProvider {
    private let accountId: UUID
    let organization: String
    private let tokenSource: any TokenSource
    private let authMethod: AuthMethod
    private let http: any HTTPClient
    let now: @Sendable () -> Date
    let pageSize = 100
    private var projectCache: (names: [String], fetchedAt: Date)?
    /// Het e-mailadres (`uniqueName`) van de auteur per PR (dedupKey), uit de laatste lijst, zodat
    /// `coAuthors(of:)` de eigen commits van de auteur herkent.
    private var authorEmails: [String: String] = [:]
    /// Het id van het project per PR (dedupKey), uit de laatste lijst: de policy-evaluaties van
    /// een PR vragen het (`checks(of:)`).
    var projectIds: [String: String] = [:]
    /// Hooguit zoveel commits per PR waarvan het bericht afgekapt is en apart opgehaald wordt.
    private let fullMessageLimit = 10

    public init(
        accountId: UUID,
        organization: String,
        tokenSource: any TokenSource,
        authMethod: AuthMethod,
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountId = accountId
        self.organization = organization
        self.tokenSource = tokenSource
        self.authMethod = authMethod
        self.http = http
        self.now = now
    }

    var baseURL: URL {
        URL(string: "https://dev.azure.com")!.appending(path: organization)
    }

    public func currentUserId() async throws -> String {
        try await authenticatedUser().id
    }

    public func testConnection() async throws -> String {
        let user = try await authenticatedUser()
        // connectionData is niet organisatie-gebonden; een org-endpoint bewijst pas toegang.
        do {
            let _: ValueList<ProjectDTO> = try await get(
                baseURL.appending(path: "_apis/projects"),
                query: [URLQueryItem(name: "$top", value: "1")]
            )
        } catch ProviderError.unauthorized {
            throw ProviderError.noAccess(organization)
        }
        return user.providerDisplayName ?? user.id
    }

    /// Azure DevOps beantwoordt connectionData met een anonieme gebruiker als het token niet geaccepteerd wordt.
    private func authenticatedUser() async throws -> ConnectionData.User {
        let data: ConnectionData = try await get(baseURL.appending(path: "_apis/connectionData"), apiVersion: "7.1-preview")
        guard data.authenticatedUser.id != ConnectionData.anonymousUserId else { throw ProviderError.unauthorized }
        return data.authenticatedUser
    }

    public func listRepos() async throws -> [String] {
        var result: [String] = []
        for project in try await projects() {
            let list: ValueList<RepositoryDTO> = try await get(
                baseURL.appending(path: project).appending(path: "_apis/git/repositories")
            )
            result += list.value.map { "\(project)/\($0.name)" }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func openPullRequests() async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for project in try await projects() {
            var skip = 0
            while true {
                let page: ValueList<PullRequestDTO> = try await get(
                    baseURL.appending(path: project).appending(path: "_apis/git/pullrequests"),
                    query: [
                        URLQueryItem(name: "searchCriteria.status", value: "active"),
                        URLQueryItem(name: "$top", value: String(pageSize)),
                        URLQueryItem(name: "$skip", value: String(skip)),
                    ]
                )
                for dto in page.value {
                    result.append(try makePullRequest(dto))
                }
                if page.value.count < pageSize { break }
                skip += pageSize
            }
        }
        return result
    }

    public func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] {
        var byId: [Int: PullRequest] = [:]
        // Met `since` twee reeksen: recent aangemaakt en recent gesloten; zonder `since` één reeks.
        let ranges: [String?] = since == nil ? [nil] : ["created", "closed"]
        // Per reeks het aantal opgehaalde PR's over alle projecten; een reeks stopt bij `limit`.
        var fetched = Array(repeating: 0, count: ranges.count)
        for project in try await projects() {
            for (series, range) in ranges.enumerated() where fetched[series] < limit {
                var skip = 0
                while true {
                    var query = [
                        URLQueryItem(name: "searchCriteria.status", value: "all"),
                        URLQueryItem(name: "$top", value: String(pageSize)),
                        URLQueryItem(name: "$skip", value: String(skip)),
                    ]
                    if let range, let since {
                        query += [
                            URLQueryItem(name: "searchCriteria.queryTimeRangeType", value: range),
                            URLQueryItem(name: "searchCriteria.minTime", value: since.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))),
                        ]
                    }
                    let page: ValueList<PullRequestDTO>
                    do {
                        page = try await get(
                            baseURL.appending(path: project).appending(path: "_apis/git/pullrequests"),
                            query: query
                        )
                    } catch ProviderError.server(status: 404) {
                        break // project bestaat niet (meer)
                    }
                    for dto in page.value {
                        byId[dto.pullRequestId] = try makePullRequest(dto)
                    }
                    fetched[series] += page.value.count
                    if page.value.count < pageSize || fetched[series] >= limit { break }
                    skip += pageSize
                }
            }
            if fetched.allSatisfy({ $0 >= limit }) { break }
        }
        return Array(byId.values.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    public func tags(in repos: [String]) async throws -> TagFetch {
        var result: [Tag] = []
        var unavailable: [String] = []
        for repo in repos {
            guard let slash = repo.firstIndex(of: "/") else { continue }
            let project = String(repo[..<slash])
            let name = String(repo[repo.index(after: slash)...])
            let repoURL = baseURL.appending(path: project).appending(path: "_apis/git/repositories").appending(path: name)
            let list: ValueList<RefDTO>
            do {
                list = try await get(
                    repoURL.appending(path: "refs"),
                    query: [URLQueryItem(name: "filter", value: "tags/"), URLQueryItem(name: "peelTags", value: "true")]
                )
            } catch ProviderError.server(status: 404) {
                unavailable.append(repo) // repo bestaat niet (meer)
                continue
            } catch ProviderError.unauthorized {
                unavailable.append(repo) // geen toegang (403: SSO, rechten, IP-allowlist); andere repo's gaan door
                continue
            }
            let fallback = await missingAuthors(list.value, repoURL: repoURL)
            for ref in list.value {
                let tagName = ref.name.hasPrefix("refs/tags/") ? String(ref.name.dropFirst("refs/tags/".count)) : ref.name
                result.append(Tag(
                    accountId: accountId,
                    repo: repo,
                    name: tagName,
                    authorName: ref.creator?.displayName ?? fallback[ref.name],
                    webURL: tagURL(project: project, repo: name, tag: tagName)
                ))
            }
        }
        return TagFetch(tags: result, unavailableRepos: unavailable)
    }

    /// Tags met de datum van hun commit: de refs (met `peelTags`, zodat een geannoteerde tag zijn
    /// commit noemt) en daarna de commits in één `commitsbatch` per honderd.
    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        guard let slash = repo.firstIndex(of: "/"), limit > 0 else { return [] }
        let project = String(repo[..<slash])
        let name = String(repo[repo.index(after: slash)...])
        let repoURL = baseURL.appending(path: project).appending(path: "_apis/git/repositories").appending(path: name)
        let list: ValueList<RefDTO> = try await get(
            repoURL.appending(path: "refs"),
            query: [URLQueryItem(name: "filter", value: "tags/"), URLQueryItem(name: "peelTags", value: "true")]
        )
        var commitByTag: [String: String] = [:]
        for ref in list.value {
            guard let commit = ref.peeledObjectId ?? ref.objectId else { continue }
            commitByTag[ref.name] = commit
        }
        var dates: [String: Date] = [:]
        var commitAuthors: [String: String] = [:]
        let ids = Array(Set(commitByTag.values)).sorted()
        // Hooguit tien batches: een repo met duizenden tags hoeft niet helemaal terug.
        for start in stride(from: 0, to: min(ids.count, 1000), by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let body = try JSONEncoder().encode(CommitsBatchDTO(ids: batch, top: batch.count))
            let commits: ValueList<CommitDTO> = try await get(repoURL.appending(path: "commitsbatch"), body: body)
            for commit in commits.value {
                if let date = (commit.committer?.date ?? commit.author?.date).flatMap(DateParsing.parse) {
                    dates[commit.commitId] = date
                }
                if let author = commit.author?.name, !author.isEmpty { commitAuthors[commit.commitId] = author }
            }
        }
        let creators = Dictionary(list.value.map { ($0.name, $0.creator?.displayName) }, uniquingKeysWith: { first, _ in first })
        let tags: [Tag] = commitByTag.compactMap { refName, commit in
            guard let date = dates[commit] else { return nil }
            let tagName = refName.hasPrefix("refs/tags/") ? String(refName.dropFirst("refs/tags/".count)) : refName
            return Tag(
                accountId: accountId,
                repo: repo,
                name: tagName,
                authorName: (creators[refName] ?? nil) ?? commitAuthors[commit],
                webURL: tagURL(project: project, repo: name, tag: tagName),
                createdAt: date
            )
        }
        return Array(tags.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.prefix(limit))
    }

    /// Per PR de commits (`pullRequests/{id}/commits`): hun auteurs en de `Co-authored-by:`-trailers
    /// in de berichten. Azure DevOps kent geen co-auteurs en geen foto's. Een afgekapt bericht
    /// wordt los opgehaald (hooguit tien per PR). Een PR die niet (meer) bestaat geeft een lege lijst.
    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        var result: [String: [Person]] = [:]
        for pr in pullRequests {
            let parts = pr.repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let repoURL = baseURL.appending(path: parts[0]).appending(path: "_apis/git/repositories").appending(path: parts[1])
            let commits: ValueList<PRCommitDTO>
            do {
                commits = try await get(
                    repoURL.appending(path: "pullRequests").appending(path: String(pr.number)).appending(path: "commits"),
                    query: [URLQueryItem(name: "$top", value: String(pageSize))]
                )
            } catch ProviderError.server(status: 404) {
                result[pr.dedupKey] = []
                continue
            }
            var candidates: [Person] = []
            var fullMessages = 0
            for commit in commits.value {
                if let name = commit.author?.name, !name.isEmpty {
                    candidates.append(Person(name: name, email: commit.author?.email))
                }
                var message = commit.comment ?? ""
                if commit.commentTruncated == true, fullMessages < fullMessageLimit {
                    fullMessages += 1
                    let full: PRCommitDTO = try await get(repoURL.appending(path: "commits").appending(path: commit.commitId))
                    message = full.comment ?? message
                }
                candidates += CoAuthorTrailer.people(in: message)
            }
            let author = [pr.authorId, pr.authorName] + (authorEmails[pr.dedupKey].map { [$0] } ?? [])
            result[pr.dedupKey] = CoAuthorTrailer.coAuthors(from: candidates, author: author)
        }
        return result
    }

    /// Auteurs voor tags waarbij Azure DevOps geen `creator` noemt: bij een geannoteerde tag
    /// (met `peeledObjectId`) de tagger uit `annotatedtags`, bij een lichte tag de auteur van
    /// de commit uit één `commitsbatch`. Hooguit twintig tags en honderd commits, zodat een
    /// oude repo zonder creators de poll niet ophoudt; wat mislukt blijft zonder auteur.
    private func missingAuthors(_ refs: [RefDTO], repoURL: URL) async -> [String: String] {
        let missing = refs.filter { $0.creator == nil && $0.objectId != nil }
        guard !missing.isEmpty else { return [:] }
        var authors: [String: String] = [:]
        for ref in missing.filter({ $0.peeledObjectId != nil }).prefix(20) {
            guard let objectId = ref.objectId,
                  let tag: AnnotatedTagDTO = try? await get(repoURL.appending(path: "annotatedtags").appending(path: objectId)),
                  let name = tag.taggedBy?.name, !name.isEmpty else { continue }
            authors[ref.name] = name
        }
        let lightweight = Array(missing.filter { $0.peeledObjectId == nil }.prefix(100))
        let ids = Array(Set(lightweight.compactMap(\.objectId))).sorted()
        if !ids.isEmpty, let body = try? JSONEncoder().encode(CommitsBatchDTO(ids: ids, top: ids.count)),
           let commits: ValueList<CommitDTO> = try? await get(repoURL.appending(path: "commitsbatch"), body: body) {
            let byId = Dictionary(commits.value.compactMap { commit in commit.author?.name.map { (commit.commitId, $0) } },
                                  uniquingKeysWith: { first, _ in first })
            for ref in lightweight {
                if let id = ref.objectId, let name = byId[id], !name.isEmpty { authors[ref.name] = name }
            }
        }
        return authors
    }

    private func tagURL(project: String, repo: String, tag: String) -> URL {
        let base = baseURL.appending(path: project).appending(path: "_git").appending(path: repo)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        // "+" en andere tekens expliciet coderen; "/" blijft leesbaar.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        components.percentEncodedQuery = "version=GT" + (tag.addingPercentEncoding(withAllowedCharacters: allowed) ?? tag)
        return components.url!
    }

    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        let list: ValueList<ItemDTO>
        do {
            list = try await get(itemsURL(repo), query: [
                URLQueryItem(name: "scopePath", value: "/"),
                URLQueryItem(name: "recursionLevel", value: "Full"),
            ] + versionQuery(ref))
        } catch ProviderError.server(status: 404) {
            return [] // lege repo
        }
        return list.value.filter { $0.isFolder != true }.map { String($0.path.drop { $0 == "/" }) }
    }

    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        let item: ItemDTO = try await get(itemsURL(repo), query: [
            URLQueryItem(name: "path", value: "/" + path),
            URLQueryItem(name: "includeContent", value: "true"),
        ] + versionQuery(ref))
        return item.content ?? ""
    }

    /// Zonder tag leest Azure DevOps de default branch.
    private func versionQuery(_ tag: String?) -> [URLQueryItem] {
        guard let tag else { return [] }
        return [
            URLQueryItem(name: "versionDescriptor.version", value: tag),
            URLQueryItem(name: "versionDescriptor.versionType", value: "tag"),
        ]
    }

    /// `repo` is "project/naam", zoals `listRepos()` levert.
    private func itemsURL(_ repo: String) -> URL {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        return baseURL.appending(path: parts.first ?? repo).appending(path: "_apis/git/repositories")
            .appending(path: parts.last ?? repo).appending(path: "items")
    }

    public func invalidateCredentials() async {
        projectCache = nil
        await tokenSource.invalidate()
    }

    /// Een losse repo (`project/repo`) binnen de organisatie van het account: één verzoek naar de
    /// repository. Azure DevOps kent geen openbaar lezen zonder inloggen voor deze API's.
    public func checkRepository(_ repo: String) async throws -> RepositoryCheck {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw ProviderError.noAccess(repo) }
        let (data, response) = try await send(
            baseURL.appending(path: parts[0]).appending(path: "_apis/git/repositories").appending(path: parts[1]),
            apiVersion: "7.1"
        )
        if response.statusCode == 404 || response.statusCode == 403 { throw ProviderError.noAccess(repo) }
        try HTTPStatus.check(response, now: now())
        let found = try JSONDecoding.decode(SingleRepositoryDTO.self, from: data)
        return RepositoryCheck(name: "\(found.project.name)/\(found.name)")
    }

    private func projects() async throws -> [String] {
        if let projectCache, now().timeIntervalSince(projectCache.fetchedAt) < 3600 {
            return projectCache.names
        }
        let list: ValueList<ProjectDTO> = try await get(
            baseURL.appending(path: "_apis/projects"),
            query: [URLQueryItem(name: "$top", value: "500")]
        )
        let names = list.value.map(\.name)
        projectCache = (names, now())
        return names
    }

    private func makePullRequest(_ dto: PullRequestDTO) throws -> PullRequest {
        guard let createdAt = DateParsing.parse(dto.creationDate) else {
            throw ProviderError.decoding("creationDate \(dto.creationDate)")
        }
        let project = dto.repository.project.name
        let state: PRState
        switch dto.status {
        case "completed": state = .merged
        case "abandoned": state = .closed
        default: state = .open
        }
        let webURL = baseURL
            .appending(path: project)
            .appending(path: "_git")
            .appending(path: dto.repository.name)
            .appending(path: "pullrequest")
            .appending(path: String(dto.pullRequestId))
        let pullRequest = PullRequest(
            accountId: accountId,
            repo: "\(project)/\(dto.repository.name)",
            number: dto.pullRequestId,
            title: dto.title,
            authorId: dto.createdBy.id,
            authorName: dto.createdBy.displayName,
            isDraft: dto.isDraft ?? false,
            createdAt: createdAt,
            webURL: webURL,
            state: state,
            closedAt: dto.closedDate.flatMap(DateParsing.parse),
            revision: dto.lastMergeSourceCommit?.commitId
        )
        if let email = dto.createdBy.uniqueName { authorEmails[pullRequest.dedupKey] = email }
        if let id = dto.repository.project.id { projectIds[pullRequest.dedupKey] = id }
        return pullRequest
    }

    private func authorizationHeader() async throws -> String {
        let token = try await tokenSource.token()
        switch authMethod {
        case .pat: return "Basic " + Data(":\(token)".utf8).base64EncodedString()
        case .cli, .gitHubApp: return "Bearer \(token)"
        }
    }

    func get<T: Decodable>(
        _ url: URL,
        apiVersion: String = "7.1",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        let (data, response) = try await send(url, apiVersion: apiVersion, query: query, body: body)
        try HTTPStatus.check(response, now: now())
        return try JSONDecoding.decode(T.self, from: data)
    }

    /// Het verzoek met autorisatie en api-version, zonder de status te controleren.
    func send(
        _ url: URL,
        apiVersion: String,
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query + [URLQueryItem(name: "api-version", value: apiVersion)]
        var request = URLRequest(url: components.url!)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let authorization = try await authorizationHeader()
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await http.send(request)
    }
}

private struct ValueList<T: Decodable>: Decodable {
    let value: [T]
}

private struct ItemDTO: Decodable {
    let path: String
    let isFolder: Bool?
    let content: String?
}

private struct ConnectionData: Decodable {
    static let anonymousUserId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    struct User: Decodable {
        let id: String
        let providerDisplayName: String?
    }
    let authenticatedUser: User
}

private struct ProjectDTO: Decodable {
    let name: String
}

private struct RepositoryDTO: Decodable {
    let name: String
}

private struct SingleRepositoryDTO: Decodable {
    struct Project: Decodable { let name: String }
    let name: String
    let project: Project
}

private struct PullRequestDTO: Decodable {
    struct Identity: Decodable {
        let id: String
        let displayName: String
        /// Meestal het e-mailadres.
        let uniqueName: String?
    }

    struct CommitRef: Decodable { let commitId: String }

    struct Repository: Decodable {
        struct Project: Decodable {
            let name: String
            let id: String?
        }
        let name: String
        let project: Project
    }

    let pullRequestId: Int
    let title: String
    let isDraft: Bool?
    let status: String?
    let closedDate: String?
    let creationDate: String
    let createdBy: Identity
    let repository: Repository
    /// De laatste commit van de bronbranch; verandert bij elke push.
    let lastMergeSourceCommit: CommitRef?
}

/// Een commit van een PR, of los opgehaald voor het volledige bericht.
private struct PRCommitDTO: Decodable {
    struct Person: Decodable {
        let name: String?
        let email: String?
    }
    let commitId: String
    let author: Person?
    let comment: String?
    let commentTruncated: Bool?
}

private struct RefDTO: Decodable {
    struct Creator: Decodable { let displayName: String }
    let name: String
    let creator: Creator?
    let objectId: String?
    /// Bij `peelTags=true` de commit achter een geannoteerde tag.
    let peeledObjectId: String?
}

private struct CommitsBatchDTO: Encodable {
    let ids: [String]
    let top: Int

    private enum CodingKeys: String, CodingKey {
        case ids
        case top = "$top"
    }
}

private struct AnnotatedTagDTO: Decodable {
    struct UserDate: Decodable { let name: String? }
    let taggedBy: UserDate?
}

private struct CommitDTO: Decodable {
    struct Person: Decodable {
        let name: String?
        let date: String?
    }
    let commitId: String
    let author: Person?
    let committer: Person?
}

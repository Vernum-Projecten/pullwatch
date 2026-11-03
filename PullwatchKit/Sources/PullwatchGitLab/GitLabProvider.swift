import Foundation
import PullwatchCore

/// GitLab (gitlab.com of een eigen server) via de REST API v4. Eigenaren zijn groepen (met hun
/// subgroepen) of gebruikers; een repo heet zoals GitLab hem noemt, `groep/subgroep/project`
/// (`path_with_namespace`). Merge requests worden `PullRequest`s met hun `iid` als nummer.
public actor GitLabProvider: PRProvider {
    enum Owner: Equatable {
        /// Een groep met zijn volledige pad ("groep/subgroep").
        case group(String)
        /// Een gebruiker met zijn id (de API van gebruikers wil het id, niet de naam).
        case user(id: Int)
    }

    private let accountId: UUID
    private let owners: [String]
    let tokenSource: any TokenSource
    let http: any HTTPClient
    let now: @Sendable () -> Date
    /// De server zonder "/" aan het eind, bv. `https://gitlab.com` of `https://example.com/gitlab`.
    let instanceURL: URL
    let pageSize = 100
    let maxPages = 10
    /// Een bestandsboom kan groot zijn; zoveel pagina's van honderd paden hooguit.
    let maxTreePages = 100
    private var ownerCache: [String: Owner] = [:]
    /// De projecten van een gebruiker-eigenaar (merge requests gaan daar per project), een uur bewaard.
    private var userProjects: [Int: (paths: [String], fetchedAt: Date)] = [:]
    /// De weergavenaam van de auteur per PR (dedupKey), uit de laatste lijst, zodat
    /// `coAuthors(of:)` de eigen commits van de auteur herkent (commits hebben geen gebruikersnaam).
    private var authorNames: [String: String] = [:]
    /// Losse projecten (`Account.extraRepos`) buiten de gevolgde groepen en gebruikers: die krijgen
    /// per poll elk één vraag naar hun merge requests (`GitLabProvider+ExtraProjects`).
    let extraRepos: [String]
    /// Hoe elk los project te lezen is, per pad lowercased; zie `access(for:)`.
    var projectAccess: [String: (access: ProjectAccess, at: Date)] = [:]
    /// Tot wanneer de limiet voor verzoeken zonder token op is.
    var anonymousPausedUntil: Date?

    public static let defaultInstanceURL = URL(string: "https://gitlab.com")!

    public init(
        accountId: UUID,
        owners: [String],
        extraRepos: [String] = [],
        instanceURL: URL? = nil,
        tokenSource: any TokenSource,
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountId = accountId
        self.owners = owners
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/@"))) }
            .filter { !$0.isEmpty }
        self.extraRepos = Self.projectsOutside(owners: self.owners, extraRepos)
        self.instanceURL = instanceURL ?? Self.defaultInstanceURL
        self.tokenSource = tokenSource
        self.http = http
        self.now = now
    }

    // MARK: Gebruiker en verbinding

    public func currentUserId() async throws -> String {
        try await currentUser().username
    }

    /// Controleert het token (`/user`) en of elke eigenaar te vinden is; geeft de gebruikersnaam.
    public func testConnection() async throws -> String {
        let user = try await currentUser()
        for owner in owners {
            _ = try await resolve(owner)
        }
        return user.username
    }

    private func currentUser() async throws -> UserDTO {
        try await get(endpoint("user"))
    }

    // MARK: Repo's

    /// De projecten van alle gevolgde eigenaren (groepen met subgroepen, gebruikers), op naam;
    /// gearchiveerde projecten niet.
    public func listRepos() async throws -> [String] {
        var names: [String] = []
        for owner in owners {
            names += try await projects(of: try await resolve(owner))
        }
        names += try await extraProjectNames()
        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func projects(of owner: Owner) async throws -> [String] {
        let url: URL
        var query = [
            URLQueryItem(name: "simple", value: "true"),
            URLQueryItem(name: "archived", value: "false"),
            URLQueryItem(name: "order_by", value: "id"),
            URLQueryItem(name: "sort", value: "asc"),
        ]
        switch owner {
        case .group(let path):
            url = endpoint("groups", path, "projects")
            // Ook de subgroepen, maar geen projecten die een andere groep met deze deelt.
            query += [URLQueryItem(name: "include_subgroups", value: "true"), URLQueryItem(name: "with_shared", value: "false")]
        case .user(let id):
            url = endpoint("users", String(id), "projects")
        }
        let projects: [ProjectDTO] = try await pages(url, query: query, maxPages: maxPages)
        return projects.map(\.pathWithNamespace)
    }

    /// De projecten van een gebruiker, een uur bewaard: per poll gaat er per project een vraag
    /// naar de merge requests, de lijst zelf hoeft niet elke keer.
    private func cachedProjects(ofUser id: Int) async throws -> [String] {
        if let cached = userProjects[id], now().timeIntervalSince(cached.fetchedAt) < 3600 {
            return cached.paths
        }
        let paths = try await projects(of: .user(id: id))
        userProjects[id] = (paths, now())
        return paths
    }

    // MARK: Merge requests

    /// Open merge requests (ook drafts) bij alle gevolgde eigenaren: één lijst per groep (met
    /// subgroepen), bij een gebruiker één per project.
    public func openPullRequests() async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for owner in owners {
            result += try await mergeRequests(of: try await resolve(owner), query: [
                URLQueryItem(name: "state", value: "opened"),
            ], limit: .max)
        }
        // Van een los project de honderd recentst bijgewerkte open merge requests, in één vraag.
        result += try await extraMergeRequests(query: [
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "sort", value: "desc"),
        ], limit: .max)
        return result
    }

    /// Merge requests in elke status, recentst bijgewerkt eerst, samen hooguit `limit`; met
    /// `since` alleen wat sindsdien is bijgewerkt (`updated_after`).
    public func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] {
        var query = [
            URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "sort", value: "desc"),
        ]
        if let since {
            query.append(URLQueryItem(name: "updated_after", value: since.formatted(Date.ISO8601FormatStyle(timeZone: .gmt))))
        }
        var result: [PullRequest] = []
        for owner in owners {
            result += try await mergeRequests(of: try await resolve(owner), query: query, limit: limit)
        }
        result += try await extraMergeRequests(query: query, limit: limit)
        // Over eigenaren en projecten heen de recentste eerst, zodat de grens eerlijk is.
        return Array(result.sorted { ($0.closedAt ?? $0.createdAt) > ($1.closedAt ?? $1.createdAt) }.prefix(limit))
    }

    private func mergeRequests(of owner: Owner, query: [URLQueryItem], limit: Int) async throws -> [PullRequest] {
        let query = query + [URLQueryItem(name: "scope", value: "all")]
        switch owner {
        case .group(let path):
            let found: [MergeRequestDTO] = try await pages(
                endpoint("groups", path, "merge_requests"), query: query, maxPages: maxPages, stop: { $0.count >= limit }
            )
            return try found.prefix(limit).map(makePullRequest)
        case .user(let id):
            var result: [PullRequest] = []
            for project in try await cachedProjects(ofUser: id) {
                let found: [MergeRequestDTO]
                do {
                    found = try await pages(
                        endpoint("projects", project, "merge_requests"), query: query, maxPages: maxPages, stop: { $0.count >= limit }
                    )
                } catch ProviderError.server(status: 404) {
                    continue // project bestaat niet (meer); de lijst is hooguit een uur oud
                }
                result += try found.prefix(limit).map(makePullRequest)
            }
            return result
        }
    }

    func makePullRequest(_ dto: MergeRequestDTO) throws -> PullRequest {
        guard let createdAt = DateParsing.parse(dto.createdAt) else {
            throw ProviderError.decoding("created_at \(dto.createdAt)")
        }
        guard let webURL = URL(string: dto.webUrl), let repo = Self.repoPath(of: dto, instanceURL: instanceURL) else {
            throw ProviderError.decoding("web_url in merge request \(dto.iid)")
        }
        let state: PRState = switch dto.state {
        case "merged": .merged
        case "closed": .closed
        default: .open // "opened", en "locked" (tijdelijk vergrendeld, nog open)
        }
        let closedAt = state == .merged ? (dto.mergedAt ?? dto.closedAt) : (state == .closed ? dto.closedAt : nil)
        let pullRequest = PullRequest(
            accountId: accountId,
            repo: repo,
            number: dto.iid,
            title: dto.title,
            authorId: dto.author.username,
            authorName: dto.author.username,
            isDraft: dto.draft ?? dto.workInProgress ?? false,
            createdAt: createdAt,
            webURL: webURL,
            state: state,
            closedAt: closedAt.flatMap(DateParsing.parse),
            // De laatste commit van de bronbranch: verandert bij elke push, niet bij een reactie.
            revision: dto.sha ?? dto.updatedAt
        )
        if let name = dto.author.name, !name.isEmpty { authorNames[pullRequest.dedupKey] = name }
        return pullRequest
    }

    /// "groep/subgroep/project" uit `references.full` ("groep/project!12"), anders uit de
    /// webpagina (`<server>/groep/project/-/merge_requests/12`).
    static func repoPath(of dto: MergeRequestDTO, instanceURL: URL) -> String? {
        if let full = dto.references?.full, let bang = full.lastIndex(of: "!") {
            let path = String(full[..<bang])
            if path.contains("/") { return path }
        }
        let prefix = instanceURL.absoluteString + "/"
        guard dto.webUrl.hasPrefix(prefix), let marker = dto.webUrl.range(of: "/-/merge_requests/") else { return nil }
        let path = dto.webUrl[dto.webUrl.index(dto.webUrl.startIndex, offsetBy: prefix.count)..<marker.lowerBound]
        return path.isEmpty ? nil : String(path).removingPercentEncoding ?? String(path)
    }

    // MARK: Tags

    /// Per repo één vraag naar de tags (nieuwste eerst, met de commit erachter) en alleen als een
    /// tag een release heeft een tweede naar de releases (titel, auteur, datum). Een repo die 404
    /// of 403 geeft komt in `unavailableRepos`.
    public func tags(in repos: [String]) async throws -> TagFetch {
        var fetch = TagFetch(tags: [])
        for repo in repos {
            do {
                fetch.tags += try await tags(of: repo)
            } catch ProviderError.server(status: 404) {
                fetch.unavailableRepos.append(repo) // bestaat niet (meer)
            } catch ProviderError.unauthorized {
                fetch.unavailableRepos.append(repo) // 403: geen toegang tot de repository
            } catch ProviderError.rateLimited where readsWithoutTokenCached(repo) {
                fetch.unavailableRepos.append(repo) // limiet zonder token op; de volgende keer weer
            }
        }
        return fetch
    }

    static let tagLimit = 100
    static let releaseLimit = 20

    private func tags(of repo: String) async throws -> [Tag] {
        let anonymous = try await readsAnonymously(repo)
        let tags: [TagDTO] = try await get(endpoint("projects", repo, "repository", "tags"), anonymous: anonymous, query: [
            URLQueryItem(name: "order_by", value: "updated"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: String(Self.tagLimit)),
        ])
        var releases: [String: ReleaseDTO] = [:]
        if tags.contains(where: { $0.release != nil }) {
            let list: [ReleaseDTO] = try await get(endpoint("projects", repo, "releases"), anonymous: anonymous, query: [
                URLQueryItem(name: "order_by", value: "released_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: String(Self.releaseLimit)),
            ])
            for release in list where releases[release.tagName] == nil { releases[release.tagName] = release }
        }
        return tags.compactMap { makeTag(repo: repo, $0, release: releases[$0.name]) }
    }

    /// De auteur is wie de release maakte, maar een bot maakt plaats voor de auteur van de commit:
    /// die persoon zette de release echt in gang.
    private func makeTag(repo: String, _ dto: TagDTO, release: ReleaseDTO?) -> Tag? {
        guard let tagURL = webURL(repo, "-", "tags", dto.name) else { return nil }
        let releaseInfo = release.map { release in
            ReleaseInfo(
                title: release.name,
                authorLogin: release.author?.username,
                authorAvatarURL: release.author?.avatarUrl.flatMap(URL.init(string:)),
                isPrerelease: false, // GitLab kent geen pre-releases
                publishedAt: (release.releasedAt ?? release.createdAt).flatMap(DateParsing.parse),
                url: release.links?.selfURL.flatMap(URL.init(string:)) ?? webURL(repo, "-", "releases", dto.name) ?? tagURL
            )
        }
        let releaseAuthor = release?.author.map { (name: $0.username, avatar: $0.avatarUrl.flatMap(URL.init(string:))) }
        let commitAuthor = dto.commit?.authorName.flatMap { $0.isEmpty ? nil : (name: $0, avatar: URL?.none) }
        let people = [releaseAuthor.flatMap { Self.isBot($0.name) ? nil : $0 }, commitAuthor, releaseAuthor]
        let author = people.compactMap { $0 }.first
        return Tag(
            accountId: accountId,
            repo: repo,
            name: dto.name,
            authorName: author?.name,
            authorAvatarURL: author?.avatar,
            webURL: releaseInfo?.url ?? tagURL,
            // Een geannoteerde tag heeft een eigen datum, een lichte die van zijn commit.
            createdAt: (dto.createdAt ?? dto.commit?.committedDate ?? dto.commit?.createdAt).flatMap(DateParsing.parse),
            release: releaseInfo
        )
    }

    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        guard limit > 0 else { return [] }
        let tags = try await tags(in: [repo]).tags.compactMap { tag in tag.createdAt.map { (tag, $0) } }
        return tags.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// GitLab-bots: projecttokens en groepstokens (`project_12_bot_…`, `group_3_bot_…`), de
    /// beveiligingsbots, en GitHub-achtige namen met "[bot]".
    static func isBot(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("[bot]") || lower.contains("_bot_") || lower.hasSuffix("_bot") || lower.hasSuffix("-bot")
    }

    // MARK: Co-auteurs

    /// Per merge request de commits (`merge_requests/:iid/commits`): hun auteurs en de
    /// `Co-authored-by:`-trailers in de berichten. GitLab koppelt commits niet aan gebruikers, dus
    /// zonder login of foto. Een merge request die niet (meer) bestaat geeft een lege lijst.
    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        var result: [String: [Person]] = [:]
        for pr in pullRequests {
            let commits: [CommitDTO]
            do {
                let anonymous = try await readsAnonymously(pr.repo)
                commits = try await get(
                    endpoint("projects", pr.repo, "merge_requests", String(pr.number), "commits"), anonymous: anonymous, query: [
                        URLQueryItem(name: "per_page", value: String(pageSize)),
                    ]
                )
            } catch ProviderError.server(status: 404) {
                result[pr.dedupKey] = []
                continue
            } catch ProviderError.rateLimited where readsWithoutTokenCached(pr.repo) {
                continue // limiet zonder token op: deze keer zonder co-auteurs
            }
            var candidates: [Person] = []
            for commit in commits {
                if let name = commit.authorName, !name.isEmpty, !Self.isBot(name) {
                    candidates.append(Person(name: name, email: commit.authorEmail))
                }
                candidates += CoAuthorTrailer.people(in: commit.message ?? "")
            }
            let author = [pr.authorId, pr.authorName] + (authorNames[pr.dedupKey].map { [$0] } ?? [])
            result[pr.dedupKey] = CoAuthorTrailer.coAuthors(from: candidates, author: author)
        }
        return result
    }

    // MARK: Bestanden

    /// Alle bestanden op `ref` (zonder: de default branch), via de boom (`recursive=true`). Een
    /// lege repo heeft geen boom: GitLab geeft dan 404, dat wordt een lege lijst.
    public func filePaths(in repo: String, ref: String?) async throws -> [String] {
        var query = [URLQueryItem(name: "recursive", value: "true")]
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        let entries: [TreeEntryDTO]
        do {
            entries = try await pages(
                endpoint("projects", repo, "repository", "tree"), query: query, maxPages: maxTreePages,
                anonymous: try await readsAnonymously(repo)
            )
        } catch ProviderError.server(status: 404) {
            return []
        }
        return entries.filter { $0.type == "blob" }.map(\.path)
    }

    /// Eén bestand als tekst (`repository/files/:pad/raw`); het hele pad is één gecodeerd segment.
    public func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        let data = try await send(
            endpoint("projects", repo, "repository", "files", path, "raw"),
            query: ref.map { [URLQueryItem(name: "ref", value: $0)] } ?? [],
            anonymous: try await readsAnonymously(repo)
        ).data
        return String(decoding: data, as: UTF8.self)
    }

    public func invalidateCredentials() async {
        userProjects = [:]
        projectAccess = [:]
        await tokenSource.invalidate()
    }

    // GitLab heeft geen schone tegenhanger van code scanning en adviezen voor iedereen (de
    // vulnerability-API is GitLab Ultimate en GraphQL): `securityAlerts` blijft de standaard nil.

    // MARK: Eigenaren

    /// Een groep (ook "groep/subgroep") of anders een gebruiker; een naam die geen van beide is
    /// geeft `noAccess`. Bewaard zolang de provider bestaat.
    func resolve(_ owner: String) async throws -> Owner {
        if let known = ownerCache[owner] { return known }
        let resolved: Owner
        do {
            let group: GroupDTO = try await get(endpoint("groups", owner), query: [
                URLQueryItem(name: "with_projects", value: "false"),
            ])
            resolved = .group(group.fullPath)
        } catch ProviderError.server(status: 404) {
            let users: [UserDTO] = try await get(endpoint("users"), query: [URLQueryItem(name: "username", value: owner)])
            guard let user = users.first(where: { $0.username.caseInsensitiveCompare(owner) == .orderedSame }) ?? users.first,
                  let id = user.id else {
                throw ProviderError.noAccess(owner)
            }
            resolved = .user(id: id)
        }
        ownerCache[owner] = resolved
        return resolved
    }

    // MARK: HTTP

    /// Tekens die in een padsegment ongecodeerd mogen; de rest (ook "/", "." blijft) wordt %XX.
    /// GitLab wil een project of bestand als één segment: `groep%2Fproject`, `src%2Fmain.swift`.
    private static let segmentAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func encode(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? segment
    }

    /// `<server>/api/v4/<segment>/<segment>…`, elk segment apart gecodeerd.
    func endpoint(_ segments: String...) -> URL {
        URL(string: instanceURL.absoluteString + "/api/v4/" + segments.map(Self.encode).joined(separator: "/"))!
    }

    /// Een pagina op de server: de repo houdt zijn "/" (`groep/project`), de rest wordt gecodeerd.
    private func webURL(_ repo: String, _ segments: String...) -> URL? {
        let repoPath = repo.split(separator: "/").map { Self.encode(String($0)) }.joined(separator: "/")
        return URL(string: instanceURL.absoluteString + "/" + repoPath + "/" + segments.map(Self.encode).joined(separator: "/"))
    }

    /// Bladert met `page` tot de server geen `x-next-page` meer noemt (of `stop` genoeg vindt).
    /// Antwoordt de server met keyset-paginering (alleen een `Link` met `rel="next"`), dan volgt
    /// dit die link, maar alleen op dezelfde server: het token gaat nooit naar een andere host.
    /// Met `anonymous` zonder token: alleen voor openbare losse projecten.
    func pages<T: Decodable>(
        _ url: URL,
        query: [URLQueryItem],
        maxPages: Int,
        anonymous: Bool = false,
        stop: ([T]) -> Bool = { _ in false }
    ) async throws -> [T] {
        var result: [T] = []
        var next: URL? = Self.withQuery(url, query + [
            URLQueryItem(name: "per_page", value: String(pageSize)),
            URLQueryItem(name: "page", value: "1"),
        ])
        var fetched = 0
        while let current = next, fetched < maxPages {
            let (data, response) = try await send(current, anonymous: anonymous)
            result += try JSONDecoding.decode([T].self, from: data, snakeCase: true)
            fetched += 1
            if stop(result) { break }
            next = nextPage(after: current, response: response, base: url, query: query)
        }
        return result
    }

    private func nextPage(after current: URL, response: HTTPURLResponse, base: URL, query: [URLQueryItem]) -> URL? {
        if let page = response.value(forHTTPHeaderField: "x-next-page")?.trimmingCharacters(in: .whitespaces), !page.isEmpty {
            guard Int(page) != nil else { return nil }
            return Self.withQuery(base, query + [
                URLQueryItem(name: "per_page", value: String(pageSize)),
                URLQueryItem(name: "page", value: page),
            ])
        }
        guard let link = response.value(forHTTPHeaderField: "Link"), let url = Self.nextLink(in: link),
              url.scheme == instanceURL.scheme, url.host() == instanceURL.host(), url.port == instanceURL.port,
              url != current else { return nil }
        return url
    }

    /// De URL met `rel="next"` uit een `Link`-header (RFC 8288).
    static func nextLink(in header: String) -> URL? {
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let target = pieces.first, target.hasPrefix("<"), target.hasSuffix(">"),
                  pieces.dropFirst().contains(where: { $0.replacingOccurrences(of: " ", with: "") == #"rel="next""# }) else { continue }
            return URL(string: String(target.dropFirst().dropLast()))
        }
        return nil
    }

    /// Zet de query achter `url`; "+" wordt %2B, anders leest GitLab het als spatie (tagnamen als
    /// `1.0+build`, tijden met een tijdzone).
    static func withQuery(_ url: URL, _ query: [URLQueryItem]) -> URL {
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = query
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? url
    }

    func get<T: Decodable>(_ url: URL, anonymous: Bool = false, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoding.decode(T.self, from: try await send(url, query: query, anonymous: anonymous).data, snakeCase: true)
    }

    /// Een GET met het token als Bearer (een personal access token en het OAuth-token van `glab`
    /// werken allebei zo). 429 met `Retry-After` of `RateLimit-Reset` wordt `rateLimited`.
    /// Met `anonymous` zonder token, voor een openbaar los project; is die limiet op, dan gaan er
    /// tot de reset geen verzoeken zonder token meer uit. Met `checked: false` zonder de status te
    /// controleren (de controle van een los project leest 401, 403 en 404 zelf).
    func send(
        _ url: URL,
        query: [URLQueryItem] = [],
        anonymous: Bool = false,
        checked: Bool = true
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        if anonymous, let until = anonymousPausedUntil, until > now() { throw ProviderError.rateLimited(until: until) }
        var request = URLRequest(url: Self.withQuery(url, query))
        if !anonymous {
            let token = try await tokenSource.token()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.send(request)
        if checked {
            do {
                try HTTPStatus.check(response, now: now())
            } catch ProviderError.rateLimited(let until) where anonymous {
                anonymousPausedUntil = until
                throw ProviderError.rateLimited(until: until)
            }
        }
        return (data, response)
    }
}

// MARK: DTO's (snake_case, `JSONDecoding` met `snakeCase: true`)

struct UserDTO: Decodable {
    let id: Int?
    let username: String
    let name: String?
}

private struct GroupDTO: Decodable {
    let fullPath: String
}

private struct ProjectDTO: Decodable {
    let pathWithNamespace: String
}

struct MergeRequestDTO: Decodable {
    struct Author: Decodable {
        let username: String
        let name: String?
    }

    struct References: Decodable {
        let full: String?
    }

    let iid: Int
    let title: String
    let state: String
    let createdAt: String
    let updatedAt: String?
    let mergedAt: String?
    let closedAt: String?
    let draft: Bool?
    let workInProgress: Bool?
    let author: Author
    let webUrl: String
    let references: References?
    let sha: String?
}

private struct TagDTO: Decodable {
    struct Commit: Decodable {
        let authorName: String?
        let committedDate: String?
        let createdAt: String?
    }

    struct Release: Decodable {
        let tagName: String
    }

    let name: String
    let createdAt: String?
    let commit: Commit?
    let release: Release?
}

private struct ReleaseDTO: Decodable {
    struct Author: Decodable {
        let username: String
        let avatarUrl: String?
    }

    struct Links: Decodable {
        let selfURL: String?

        private enum CodingKeys: String, CodingKey {
            case selfURL = "self"
        }
    }

    let name: String?
    let tagName: String
    let createdAt: String?
    let releasedAt: String?
    let author: Author?
    let links: Links?

    private enum CodingKeys: String, CodingKey {
        case name, tagName, createdAt, releasedAt, author
        case links = "_links"
    }
}

private struct CommitDTO: Decodable {
    let authorName: String?
    let authorEmail: String?
    let message: String?
}

private struct TreeEntryDTO: Decodable {
    let path: String
    let type: String
}

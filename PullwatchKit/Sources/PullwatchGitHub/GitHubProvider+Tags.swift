import Foundation
public import PullwatchCore

// MARK: - Tags

extension GitHubProvider {
    public func tags(in repos: [String]) async throws -> TagFetch {
        try await tags(in: repos, unchanged: [:])
    }

    /// Via GraphQL, met aliassen voor meerdere repo's per verzoek: per repo de nieuwste tags (met
    /// tagger, commit-auteur en datum) en releases. Repo's met een bekende vingerafdruk krijgen
    /// eerst een kleine vraag (één tag en één release per repo); alleen wat veranderde wordt
    /// daarna helemaal opgehaald. Een repo die niet (meer) bestaat of geen toegang geeft
    /// (GraphQL geeft dan `null`, de hele batch 401/403) komt in `unavailableRepos`.
    public func tags(in repos: [String], unchanged known: [String: String]) async throws -> TagFetch {
        if tagsViaREST { return try await restTags(in: repos) }
        do {
            return try await graphQLTags(in: repos, unchanged: known)
        } catch is GraphQLSchemaMismatch {
            tagsViaREST = true
            return try await restTags(in: repos)
        }
    }

    private func graphQLTags(in repos: [String], unchanged known: [String: String]) async throws -> TagFetch {
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
            let (body, http) = try await send(endpoints.graphQL, body: try JSONEncoder().encode(request))
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
            if GraphQLSchemaMismatch.matches(response.errors) { throw GraphQLSchemaMismatch() }
            throw ProviderError.decoding(response.errors?.first?.message.map { "GraphQL: \($0)" }
                ?? String(localized: "GraphQL-antwoord zonder gegevens", bundle: .localizedGitHub))
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
                releaseAuthor.flatMap { Self.isBot($0.name) ? nil : $0 },
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
        return URL(string: "\(endpoints.web.absoluteString)/\(repo)/tree/\(encoded)")
    }

    /// Een GitHub-app als `github-actions[bot]`: die geeft een release geen herkenbare auteur.
    static func isBot(_ login: String) -> Bool { login.hasSuffix("[bot]") }

    /// Tags en releases via REST voor alle repo's, voor een GitHub Enterprise Server waarvan de
    /// GraphQL-API een veld uit `TagQuery` niet kent. Per repo dezelfde twee verzoeken als bij een
    /// losse repo (`restTags(_:into:)`); een tag zonder release heeft hier geen datum en geen auteur.
    func restTags(in repos: [String]) async throws -> TagFetch {
        var fetch = TagFetch(tags: [])
        for repo in repos {
            guard repo.split(separator: "/").count == 2 else {
                fetch.unavailableRepos.append(repo)
                continue
            }
            await restTags(repo, into: &fetch)
        }
        return fetch
    }
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

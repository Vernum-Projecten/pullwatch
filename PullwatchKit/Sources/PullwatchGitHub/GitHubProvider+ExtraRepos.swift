import Foundation
import PullwatchCore

private let logger = Log(category: "github")

/// Hoe een losse repo te lezen is.
enum RepoAccess: Equatable, Sendable {
    /// Met het token van het account; de naam zoals GitHub hem schrijft.
    case token(String)
    /// Alleen zonder token: een openbare repo waar het token niet bij mag (bv. omdat de GitHub
    /// App daar niet geïnstalleerd is). Telt tegen de limiet zonder inloggen.
    case anonymous(String)
    /// Bestaat niet, of is privé en niet te lezen.
    case missing
    /// De limiet zonder token is op; later opnieuw kijken.
    case paused(until: Date)
}

/// Losse repo's (`Account.extraRepos`) buiten de gevolgde eigenaren.
///
/// Eerst altijd met het token van het account: GitHub geeft een GitHub App met een gebruikerstoken
/// leesrecht op openbare gegevens, ook waar de app niet geïnstalleerd is. Geeft GitHub voor zo'n
/// repo toch 403 of 404, dan nog één keer zonder token; lukt dat, dan wordt die repo voortaan
/// zonder token gelezen (`RepoAccess.anonymous`). De limiet zonder token is klein (60 verzoeken per
/// uur, zoeken 10 per minuut): is die op, dan slaat Pullwatch die repo's over tot de limiet terug
/// is, zonder dat het account faalt.
extension GitHubProvider {
    /// Zoveel losse repo's per zoekopdracht (`repo:a/b repo:c/d …`), en de zoektekst hooguit zo
    /// lang. GitHub telt qualifiers niet mee in zijn grens van 256 tekens, maar de hele URL heeft
    /// wel een grens; 55 repo's (1737 tekens) werkte, dit blijft daar ruim onder.
    static let searchBatchRepos = 30
    static let searchQueryLength = 1000
    /// Na zoveel seconden kijkt Pullwatch opnieuw of een niet gevonden losse repo er weer is.
    static let missingRecheck: TimeInterval = 3600

    func isExtra(_ repo: String) -> Bool {
        extraRepos.contains { $0.caseInsensitiveCompare(repo) == .orderedSame }
    }

    /// Wordt deze repo (al) zonder token gelezen?
    func readsWithoutToken(_ repo: String) -> Bool {
        if case .anonymous = repoAccess[repo.lowercased()]?.access { return true }
        return false
    }

    public func checkRepository(_ repo: String) async throws -> RepositoryCheck {
        repoAccess[repo.lowercased()] = nil
        switch try await probe(repo) {
        case .token(let name): return RepositoryCheck(name: name)
        case .anonymous(let name): return RepositoryCheck(name: name, readWithoutSignIn: true)
        case .missing: throw ProviderError.noAccess(repo)
        case .paused(let until): throw ProviderError.rateLimited(until: until)
        }
    }

    /// Hoe deze losse repo te lezen is; onthouden zolang de provider leeft (een niet gevonden
    /// repo een uur, een gepauzeerde tot de limiet terug is).
    func access(for repo: String) async throws -> RepoAccess {
        let key = repo.lowercased()
        if let known = repoAccess[key] {
            switch known.access {
            case .token, .anonymous: return known.access
            case .missing where now().timeIntervalSince(known.at) < Self.missingRecheck: return known.access
            case .paused(let until) where until > now(): return known.access
            case .missing, .paused: break
            }
        }
        return try await probe(repo)
    }

    /// Eén `GET /repos/{repo}` met token, en bij 403 of 404 nog één zonder.
    private func probe(_ repo: String) async throws -> RepoAccess {
        let url = apiBase.appending(path: "repos").appending(path: repo)
        let result: RepoAccess
        if let name = try await readableName(url, anonymous: false) {
            result = .token(name)
        } else if let until = anonymousPausedUntil, until > now() {
            result = .paused(until: until)
        } else {
            do {
                result = try await readableName(url, anonymous: true).map(RepoAccess.anonymous) ?? .missing
            } catch ProviderError.rateLimited(let until) {
                anonymousPausedUntil = until
                result = .paused(until: until)
            }
        }
        repoAccess[repo.lowercased()] = (result, now())
        return result
    }

    /// De naam van de repo, of nil bij 404 of een 403 die geen limiet is (niet te lezen).
    private func readableName(_ url: URL, anonymous: Bool) async throws -> String? {
        let (data, response) = try await send(url, checked: false, anonymous: anonymous)
        do {
            try HTTPStatus.check(response, now: now())
        } catch ProviderError.unauthorized where response.statusCode == 403 {
            return nil
        } catch ProviderError.server(status: 404) {
            return nil
        }
        return try JSONDecoding.decode(RepositoryDTO.self, from: data, snakeCase: true).fullName
    }

    /// De losse repo's met hun naam zoals GitHub hem schrijft, zonder de niet gevonden. Lukt het
    /// kijken niet (netwerk, limiet), dan de naam uit de instellingen.
    func extraRepoNames() async -> [String] {
        var names: [String] = []
        for repo in extraRepos {
            switch try? await access(for: repo) {
            case .token(let name)?, .anonymous(let name)?: names.append(name)
            case .missing?: continue
            case .paused?, nil: names.append(repo)
            }
        }
        return names
    }

    /// Verdeelt `repos` in wat met het token gaat en losse repo's die alleen zonder token te lezen
    /// zijn. Een niet gevonden of gepauzeerde losse repo komt in `unavailable`.
    func splitByAccess(_ repos: [String]) async throws -> (signed: [String], unsigned: [String], unavailable: [String]) {
        var signed: [String] = []
        var unsigned: [String] = []
        var unavailable: [String] = []
        for repo in repos {
            guard isExtra(repo) else {
                signed.append(repo)
                continue
            }
            switch try await access(for: repo) {
            case .token: signed.append(repo)
            case .anonymous: unsigned.append(repo)
            case .missing, .paused: unavailable.append(repo)
            }
        }
        return (signed, unsigned, unavailable)
    }

    /// Zoekteksten met de losse repo's als `repo:`-qualifiers, gebundeld binnen GitHubs grenzen.
    static func searchQueries(_ base: String, repos: [String]) -> [String] {
        var queries: [String] = []
        var current = base
        var count = 0
        for repo in repos {
            let qualifier = " repo:\(repo)"
            if count > 0, count >= searchBatchRepos || current.count + qualifier.count > searchQueryLength {
                queries.append(current)
                current = base
                count = 0
            }
            current += qualifier
            count += 1
        }
        if count > 0 { queries.append(current) }
        return queries
    }

    /// De PR's van de losse repo's: eerst gebundeld met token, dan de openbare zonder token. Is de
    /// limiet zonder token op, dan komen die repo's deze keer niet mee (geen fout).
    func extraPullRequests(_ base: String, byUpdate: Bool, limit: Int) async throws -> [PullRequest] {
        guard !extraRepos.isEmpty else { return [] }
        var signed: [String] = []
        var unsigned: [String] = []
        for repo in extraRepos {
            switch try await access(for: repo) {
            case .token(let name): signed.append(name)
            case .anonymous(let name): unsigned.append(name)
            case .missing, .paused: continue
            }
        }
        var result: [PullRequest] = []
        for q in Self.searchQueries(base, repos: signed) {
            do {
                result += try await searchPullRequests(q, byUpdate: byUpdate, limit: limit)
            } catch ProviderError.server(status: 422) {
                // Geen van deze repo's is (nog) te doorzoeken; bij de volgende poll opnieuw kijken.
                logger.notice("zoeken in losse repo's geweigerd: \(q)")
                for repo in signed where q.contains("repo:\(repo)") { repoAccess[repo.lowercased()] = nil }
            }
        }
        for q in Self.searchQueries(base, repos: unsigned) {
            if let until = anonymousPausedUntil, until > now() { break }
            do {
                result += try await searchPullRequests(q, byUpdate: byUpdate, limit: limit, anonymous: true)
            } catch ProviderError.rateLimited(let until) {
                anonymousPausedUntil = until
                logger.notice("limiet zonder inloggen op tot \(until.formatted(date: .omitted, time: .shortened))")
                break
            } catch ProviderError.server(status: 422) {
                for repo in unsigned where q.contains("repo:\(repo)") { repoAccess[repo.lowercased()] = nil }
            }
        }
        return result
    }

    /// Tags en releases van één losse repo via REST (twee verzoeken), met het token als dat mag
    /// en anders zonder. Wat niet lukt komt in `unavailableRepos`; de limiet zonder token is dan
    /// geen fout.
    func restTags(_ repo: String, into fetch: inout TagFetch) async {
        do {
            let tagsURL = apiBase.appending(path: "repos").appending(path: repo).appending(path: "tags")
            let releasesURL = apiBase.appending(path: "repos").appending(path: repo).appending(path: "releases")
            let page = [URLQueryItem(name: "per_page", value: "100")]
            let refs = try JSONDecoding.decode([RestTagDTO].self, from: try await repoData(repo, tagsURL, query: page), snakeCase: true)
            let releases = try JSONDecoding.decode(
                [RestReleaseDTO].self,
                from: try await repoData(repo, releasesURL, query: [URLQueryItem(name: "per_page", value: "20")]),
                snakeCase: true
            ).filter { !$0.draft }
            var byTag: [String: RestReleaseDTO] = [:]
            for release in releases where byTag[release.tagName] == nil { byTag[release.tagName] = release }
            for ref in refs {
                guard let treeURL = tagTreeURL(repo: repo, tag: ref.name) else { continue }
                let release = byTag[ref.name]
                let info = release.flatMap { release in
                    URL(string: release.htmlUrl).map { url in
                        ReleaseInfo(
                            title: release.name,
                            authorLogin: release.author?.login,
                            authorAvatarURL: release.author?.avatarUrl.flatMap(URL.init(string:)),
                            isPrerelease: release.prerelease,
                            publishedAt: release.publishedAt.flatMap(DateParsing.parse),
                            url: url
                        )
                    }
                }
                // REST geeft bij een tag geen maker; die van de release, tenzij dat een bot is.
                let author = release?.author.flatMap { $0.login.hasSuffix("[bot]") ? nil : $0 }
                fetch.tags.append(Tag(
                    accountId: accountId,
                    repo: repo,
                    name: ref.name,
                    authorName: author?.login,
                    authorAvatarURL: author?.avatarUrl.flatMap(URL.init(string:)),
                    webURL: info?.url ?? treeURL,
                    createdAt: info?.publishedAt,
                    release: info
                ))
            }
            let latest = releases.first
            fetch.fingerprints[repo] = [
                "rest", "\(refs.count)", refs.first?.name ?? "",
                "\(releases.count)", latest.map { "\($0.id)" } ?? "", latest?.publishedAt ?? "",
                latest.map { "\($0.prerelease)" } ?? "",
            ].joined(separator: "|")
        } catch {
            if case ProviderError.rateLimited(let until) = error, readsWithoutToken(repo) { anonymousPausedUntil = until }
            logger.notice("tags van \(repo) overgeslagen: \(error.localizedDescription)")
            fetch.unavailableRepos.append(repo)
        }
    }

    /// Een verzoek over één repo. Een losse repo die alleen zonder token te lezen is gaat meteen
    /// zonder; anders eerst met token, en bij 403 of 404 voor een losse repo nog één keer zonder
    /// als die repo openbaar blijkt.
    func repoData(
        _ repo: String,
        _ url: URL,
        query: [URLQueryItem] = [],
        accept: String = "application/vnd.github+json"
    ) async throws -> Data {
        if readsWithoutToken(repo) {
            return try await anonymousData(url, query: query, accept: accept)
        }
        do {
            return try await send(url, query: query, accept: accept).data
        } catch let error as ProviderError where isExtra(repo) && (error == .unauthorized || error == .server(status: 404)) {
            guard case .anonymous = try await access(for: repo) else { throw error }
            return try await anonymousData(url, query: query, accept: accept)
        }
    }

    private func anonymousData(_ url: URL, query: [URLQueryItem], accept: String) async throws -> Data {
        if let until = anonymousPausedUntil, until > now() { throw ProviderError.rateLimited(until: until) }
        do {
            return try await send(url, query: query, accept: accept, anonymous: true).data
        } catch ProviderError.rateLimited(let until) {
            anonymousPausedUntil = until
            throw ProviderError.rateLimited(until: until)
        }
    }
}

private struct RepositoryDTO: Decodable {
    let fullName: String
}

private struct RestTagDTO: Decodable {
    let name: String
}

private struct RestReleaseDTO: Decodable {
    struct Author: Decodable {
        let login: String
        let avatarUrl: String?
    }

    let id: Int
    let tagName: String
    let name: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: String?
    let htmlUrl: String
    let author: Author?
}

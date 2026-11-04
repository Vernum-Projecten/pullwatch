import Foundation
public import PullwatchCore

private let logger = Log(category: "gitea")

/// Hoe een losse repo te lezen is.
enum RepoAccess: Equatable, Sendable {
    /// Met het token van het account; de naam zoals de server hem schrijft.
    case token(name: String)
    /// Alleen zonder token: een openbare repo waar het token niet bij mag.
    case anonymous(name: String)
    /// Bestaat niet, of is niet te lezen (ook niet zonder token: privé, of een server die zonder
    /// inloggen niets laat zien, `REQUIRE_SIGNIN_VIEW`).
    case missing
    /// De limiet zonder token is op; later opnieuw kijken.
    case paused(until: Date)
}

/// Losse repo's (`Account.extraRepos`) buiten de gevolgde eigenaren.
///
/// Eerst met het token (`GET /repos/:eigenaar/:repo`). Geeft de server 403 of 404, dan nog één
/// keer zonder token; lukt dat, dan wordt die repo voortaan zonder token gelezen. Of een server
/// dat toestaat blijkt zo vanzelf: een server die alles achter inloggen zet antwoordt 401, 403 of
/// 404, en dan is de repo niet te lezen. Per poll kost een losse repo één vraag naar zijn pull
/// requests (`/pulls`, één pagina, recentst bijgewerkt eerst).
extension GiteaProvider {
    /// Na zoveel seconden kijkt Pullwatch opnieuw of een niet gevonden losse repo er weer is.
    static let missingRecheck: TimeInterval = 3600

    func isExtra(_ repo: String) -> Bool {
        extraRepos.contains { $0.caseInsensitiveCompare(repo) == .orderedSame }
    }

    /// Wordt deze repo (al) zonder token gelezen, of wacht hij op de limiet zonder token?
    func readsWithoutTokenCached(_ repo: String) -> Bool {
        switch repoAccess[repo.lowercased()]?.access {
        case .anonymous?, .paused?: true
        default: false
        }
    }

    /// Of een verzoek over deze repo zonder token moet. Een niet gevonden losse repo wordt meteen
    /// 404 (geen verzoek), een gepauzeerde `rateLimited`.
    func readsAnonymously(_ repo: String) async throws -> Bool {
        guard isExtra(repo) else { return false }
        switch try await access(for: repo) {
        case .token: return false
        case .anonymous: return true
        case .missing: throw ProviderError.server(status: 404)
        case .paused(let until): throw ProviderError.rateLimited(until: until)
        }
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

    /// Hoe deze losse repo te lezen is; onthouden zolang de provider leeft (een niet gevonden repo
    /// een uur, een gepauzeerde tot de limiet terug is).
    func access(for repo: String) async throws -> RepoAccess {
        if let known = repoAccess[repo.lowercased()] {
            switch known.access {
            case .token, .anonymous: return known.access
            case .missing where now().timeIntervalSince(known.at) < Self.missingRecheck: return known.access
            case .paused(let until) where until > now(): return known.access
            case .missing, .paused: break
            }
        }
        return try await probe(repo)
    }

    /// Eén `GET /repos/:eigenaar/:repo` met token, en bij 403 of 404 nog één zonder.
    private func probe(_ repo: String) async throws -> RepoAccess {
        let url = repoEndpoint(repo)
        let result: RepoAccess
        if let found = try await readableRepo(url, anonymous: false) {
            result = .token(name: found.fullName)
        } else if let until = anonymousPausedUntil, until > now() {
            result = .paused(until: until)
        } else {
            do {
                result = try await readableRepo(url, anonymous: true).map { .anonymous(name: $0.fullName) } ?? .missing
            } catch ProviderError.rateLimited(let until) {
                result = .paused(until: until)
            }
        }
        repoAccess[repo.lowercased()] = (result, now())
        return result
    }

    /// De repo, of nil als hij niet te lezen is: 404, of 403 die geen limiet is. Zonder token ook
    /// 401 (een server die inloggen eist); met token is 401 een ongeldig token en dus een fout.
    private func readableRepo(_ url: URL, anonymous: Bool) async throws -> RepositoryDTO? {
        let (data, response) = try await send(url, anonymous: anonymous, checked: false)
        if !anonymous, response.statusCode == 403, let scope = Self.missingScope(in: data) {
            throw ProviderError.missingScope(scope)
        }
        do {
            try HTTPStatus.check(response, now: now())
        } catch ProviderError.unauthorized where anonymous || response.statusCode == 403 {
            return nil
        } catch ProviderError.server(status: 404) {
            return nil
        } catch ProviderError.rateLimited(let until) where anonymous {
            anonymousPausedUntil = until
            throw ProviderError.rateLimited(until: until)
        }
        return try JSONDecoding.decode(RepositoryDTO.self, from: data, snakeCase: true)
    }

    /// De losse repo's met hun naam zoals de server hem schrijft, zonder de niet gevonden. Is de
    /// limiet zonder token op, dan de naam uit de instellingen. Een ongeldig token is een fout.
    func extraRepoNames() async throws -> [String] {
        var names: [String] = []
        for repo in extraRepos {
            do {
                switch try await access(for: repo) {
                case .token(let name), .anonymous(let name): names.append(name)
                case .missing: continue
                case .paused: names.append(repo)
                }
            } catch ProviderError.unauthorized {
                throw ProviderError.unauthorized
            } catch let error as ProviderError where error.isMissingScope {
                throw error
            } catch {
                names.append(repo) // netwerk: de naam uit de instellingen
            }
        }
        return names
    }

    /// Per losse repo één pagina pull requests (`/repos/:eigenaar/:repo/pulls`, recentst bijgewerkt
    /// eerst), met het token of zonder. Met `since` alleen wat sindsdien is bijgewerkt. Wat niet
    /// (meer) te lezen is komt deze keer niet mee (geen fout).
    func extraPullRequests(state: String, since: Date?, limit: Int) async throws -> [PullRequest] {
        var result: [PullRequest] = []
        for repo in extraRepos {
            let name: String
            let anonymous: Bool
            switch try await access(for: repo) {
            case .token(let found): (name, anonymous) = (found, false)
            case .anonymous(let found): (name, anonymous) = (found, true)
            case .missing, .paused: continue
            }
            do {
                let found: [PullRequestDTO] = try await pages(
                    repoEndpoint(name, "pulls"),
                    query: [URLQueryItem(name: "state", value: state), URLQueryItem(name: "sort", value: "recentupdate")],
                    maxPages: 1, anonymous: anonymous
                )
                let recent = found.filter { dto in
                    guard let since else { return true }
                    return (dto.updatedAt.flatMap(DateParsing.parse) ?? .distantFuture) >= since
                }
                result += try recent.prefix(limit).map { try makePullRequest($0, repo: name) }
            } catch ProviderError.rateLimited where anonymous {
                logger.notice("limiet zonder inloggen op; pull requests van \(repo) overgeslagen")
            } catch ProviderError.server(status: 404) {
                repoAccess[repo.lowercased()] = nil
            } catch ProviderError.unauthorized where anonymous {
                repoAccess[repo.lowercased()] = nil
            }
        }
        return result
    }
}

extension ProviderError {
    var isMissingScope: Bool {
        if case .missingScope = self { true } else { false }
    }
}

import Foundation
public import PullwatchCore

/// Hoe een losse repo te lezen is.
enum RepoAccess: Equatable, Sendable {
    /// Met het token van het account; de naam zoals Bitbucket hem schrijft.
    case token(name: String)
    /// Alleen zonder inloggen: een openbare repo waar het token niet bij mag. Telt tegen de
    /// lagere limiet zonder inloggen.
    case anonymous(name: String)
    /// Bestaat niet, of is niet te lezen (ook niet zonder inloggen: privé).
    case missing
    /// De limiet zonder inloggen is op; later opnieuw kijken.
    case paused(until: Date)
}

/// Losse repo's (`Account.extraRepos`) buiten de gevolgde workspaces.
///
/// Eerst met het token van het account (`GET /repositories/{workspace}/{repo}`). Geeft Bitbucket
/// 403 of 404, dan nog één keer zonder inloggen; lukt dat, dan wordt die repo voortaan zonder
/// inloggen gelezen. Is de limiet zonder inloggen op, dan slaat Pullwatch die repo's over tot de
/// limiet terug is, zonder dat het account faalt.
extension BitbucketProvider {
    /// Na zoveel seconden kijkt Pullwatch opnieuw of een niet gevonden losse repo er weer is.
    static let missingRecheck: TimeInterval = 3600

    func isExtra(_ repo: String) -> Bool {
        extraRepos.contains { $0.caseInsensitiveCompare(repo) == .orderedSame }
    }

    /// Wordt deze repo (al) zonder inloggen gelezen, of wacht hij op die limiet?
    func readsWithoutTokenCached(_ repo: String) -> Bool {
        switch repoAccess[repo.lowercased()]?.access {
        case .anonymous?, .paused?: true
        default: false
        }
    }

    /// Of een verzoek over deze repo zonder inloggen moet. Een niet gevonden losse repo wordt
    /// meteen 404 (geen verzoek), een gepauzeerde `rateLimited`.
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

    /// Hoe deze losse repo te lezen is; onthouden zolang de provider leeft (een niet gevonden
    /// repo een uur, een gepauzeerde tot de limiet terug is).
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

    /// Eén `GET /repositories/{workspace}/{repo}` met inloggen, en bij 403 of 404 nog één zonder.
    private func probe(_ repo: String) async throws -> RepoAccess {
        let url = repository(repo)
        let result: RepoAccess
        if let found = try await readableRepository(url, anonymous: false) {
            result = .token(name: found.fullName)
        } else if let until = anonymousPausedUntil, until > now() {
            result = .paused(until: until)
        } else {
            do {
                result = try await readableRepository(url, anonymous: true).map { .anonymous(name: $0.fullName) } ?? .missing
            } catch ProviderError.rateLimited(let until) {
                result = .paused(until: until)
            }
        }
        repoAccess[repo.lowercased()] = (result, now())
        return result
    }

    /// De repo, of nil als hij niet te lezen is: 404, of 403 die geen limiet is. Zonder inloggen
    /// ook 401; met inloggen is 401 een ongeldig token en dus een fout.
    private func readableRepository(_ url: URL, anonymous: Bool) async throws -> RepositoryDTO? {
        let (data, response) = try await send(url, anonymous: anonymous, checked: false)
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

    /// De losse repo's met de naam zoals Bitbucket hem schrijft, zonder de niet gevonden. Is de
    /// limiet zonder inloggen op, dan de naam uit de instellingen. Een ongeldig token is een fout.
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
            } catch ProviderError.missingToken {
                throw ProviderError.missingToken
            } catch {
                names.append(repo) // netwerk: de naam uit de instellingen
            }
        }
        return names
    }
}

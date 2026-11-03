import Foundation
import PullwatchCore

private let logger = Log(category: "gitlab")

/// Hoe een los project te lezen is.
enum ProjectAccess: Equatable, Sendable {
    /// Met het token van het account; het pad zoals GitLab het schrijft en het project-id.
    case token(name: String, id: Int)
    /// Alleen zonder token: een openbaar project waar het token niet bij mag (bv. een token dat
    /// alleen bij één groep hoort). Telt tegen de limiet zonder inloggen.
    case anonymous(name: String, id: Int)
    /// Bestaat niet, of is niet te lezen (ook niet zonder token: privé, of een server die
    /// zonder inloggen niets laat zien).
    case missing
    /// De limiet zonder token is op; later opnieuw kijken.
    case paused(until: Date)
}

/// Losse projecten (`Account.extraRepos`) buiten de gevolgde groepen en gebruikers.
///
/// Eerst altijd met het token van het account (`GET /projects/:pad`). Geeft GitLab 403 of 404,
/// dan nog één keer zonder token; lukt dat, dan wordt dat project voortaan zonder token gelezen.
/// Of een eigen server dat toestaat blijkt zo vanzelf: een server die zonder inloggen niets laat
/// zien antwoordt 401 of 404, en dan is het project niet te lezen. Is de limiet zonder token op
/// (gitlab.com: 500 verzoeken per minuut per IP-adres), dan slaat Pullwatch die projecten over tot
/// de limiet terug is, zonder dat het account faalt.
///
/// Per poll kost een los project één vraag naar zijn merge requests (`/projects/:id/merge_requests`,
/// één pagina van honderd, recentst bijgewerkt eerst), ook in de geschiedenis-sync.
extension GitLabProvider {
    /// Na zoveel seconden kijkt Pullwatch opnieuw of een niet gevonden los project er weer is.
    static let missingRecheck: TimeInterval = 3600

    /// De losse projecten die niet al onder een gevolgde groep of gebruiker vallen (die komen al
    /// mee in de lijst van die eigenaar), hoofdletterongevoelig ontdubbeld. Een groep volgt ook zijn
    /// subgroepen, dus `acme/platform/api` valt onder `acme`.
    static func projectsOutside(owners: [String], _ repos: [String]) -> [String] {
        let prefixes = owners.map { $0.lowercased() + "/" }
        var seen: Set<String> = []
        return repos.filter { repo in
            let lower = repo.lowercased()
            guard !prefixes.contains(where: lower.hasPrefix) else { return false }
            return seen.insert(lower).inserted
        }
    }

    func isExtra(_ repo: String) -> Bool {
        extraRepos.contains { $0.caseInsensitiveCompare(repo) == .orderedSame }
    }

    /// Wordt dit project (al) zonder token gelezen, of wacht het op de limiet zonder token?
    func readsWithoutTokenCached(_ repo: String) -> Bool {
        switch projectAccess[repo.lowercased()]?.access {
        case .anonymous?, .paused?: true
        default: false
        }
    }

    /// Of een verzoek over dit project zonder token moet. Een niet gevonden los project wordt
    /// meteen 404 (geen verzoek), een gepauzeerd `rateLimited`.
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
        projectAccess[repo.lowercased()] = nil
        switch try await probe(repo) {
        case .token(let name, _): return RepositoryCheck(name: name)
        case .anonymous(let name, _): return RepositoryCheck(name: name, readWithoutSignIn: true)
        case .missing: throw ProviderError.noAccess(repo)
        case .paused(let until): throw ProviderError.rateLimited(until: until)
        }
    }

    /// Hoe dit losse project te lezen is; onthouden zolang de provider leeft (een niet gevonden
    /// project een uur, een gepauzeerd tot de limiet terug is).
    func access(for repo: String) async throws -> ProjectAccess {
        if let known = projectAccess[repo.lowercased()] {
            switch known.access {
            case .token, .anonymous: return known.access
            case .missing where now().timeIntervalSince(known.at) < Self.missingRecheck: return known.access
            case .paused(let until) where until > now(): return known.access
            case .missing, .paused: break
            }
        }
        return try await probe(repo)
    }

    /// Eén `GET /projects/:pad` met token, en bij 403 of 404 nog één zonder.
    private func probe(_ repo: String) async throws -> ProjectAccess {
        let url = endpoint("projects", repo)
        let result: ProjectAccess
        if let project = try await readableProject(url, anonymous: false) {
            result = .token(name: project.pathWithNamespace, id: project.id)
        } else if let until = anonymousPausedUntil, until > now() {
            result = .paused(until: until)
        } else {
            do {
                result = try await readableProject(url, anonymous: true)
                    .map { .anonymous(name: $0.pathWithNamespace, id: $0.id) } ?? .missing
            } catch ProviderError.rateLimited(let until) {
                result = .paused(until: until)
            }
        }
        projectAccess[repo.lowercased()] = (result, now())
        return result
    }

    /// Het project, of nil als het niet te lezen is: 404, of 403 die geen limiet is. Zonder token
    /// ook 401 (een server die inloggen eist); met token is 401 een ongeldig token en dus een fout.
    private func readableProject(_ url: URL, anonymous: Bool) async throws -> ExtraProjectDTO? {
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
        return try JSONDecoding.decode(ExtraProjectDTO.self, from: data, snakeCase: true)
    }

    /// De losse projecten met hun pad zoals GitLab het schrijft, zonder de niet gevonden. Is de
    /// limiet zonder token op, dan het pad uit de instellingen. Een ongeldig token is een fout.
    func extraProjectNames() async throws -> [String] {
        var names: [String] = []
        for repo in extraRepos {
            do {
                switch try await access(for: repo) {
                case .token(let name, _), .anonymous(let name, _): names.append(name)
                case .missing: continue
                case .paused: names.append(repo)
                }
            } catch ProviderError.unauthorized {
                throw ProviderError.unauthorized
            } catch {
                names.append(repo) // netwerk: de naam uit de instellingen
            }
        }
        return names
    }

    /// Per los project één pagina merge requests (`/projects/:id/merge_requests`), met het token
    /// of zonder als het project alleen zo te lezen is. Wat niet (meer) te lezen is, of waar de
    /// limiet zonder token voor op is, komt deze keer niet mee (geen fout); een verdwenen project
    /// wordt bij de volgende poll opnieuw bekeken.
    func extraMergeRequests(query: [URLQueryItem], limit: Int) async throws -> [PullRequest] {
        let query = query + [URLQueryItem(name: "scope", value: "all")]
        var result: [PullRequest] = []
        for repo in extraRepos {
            let target: (id: Int, anonymous: Bool)
            switch try await access(for: repo) {
            case .token(_, let id): target = (id, false)
            case .anonymous(_, let id): target = (id, true)
            case .missing, .paused: continue
            }
            let anonymous = target.anonymous
            do {
                let found: [MergeRequestDTO] = try await pages(
                    endpoint("projects", String(target.id), "merge_requests"), query: query, maxPages: 1, anonymous: anonymous
                )
                result += try found.prefix(limit).map(makePullRequest)
            } catch ProviderError.rateLimited where anonymous {
                logger.notice("limiet zonder inloggen op; merge requests van \(repo) overgeslagen")
            } catch ProviderError.server(status: 404) {
                projectAccess[repo.lowercased()] = nil
            } catch ProviderError.unauthorized where anonymous || isMergeRequestsOff(repo) {
                // 403: merge requests staan uit of zijn niet zichtbaar; bij de volgende poll opnieuw.
                projectAccess[repo.lowercased()] = nil
            }
        }
        return result
    }

    /// Een 403 op de merge requests van een project dat met het token te lezen is: GitLab doet dat
    /// als merge requests in dat project uit staan of alleen voor leden zijn. Het token zelf is dan
    /// in orde (het project werd er net mee gelezen, en een ongeldig token valt al eerder op bij de
    /// eigenaren), dus geen fout voor het hele account.
    private func isMergeRequestsOff(_ repo: String) -> Bool {
        if case .token? = projectAccess[repo.lowercased()]?.access { return true }
        return false
    }
}

/// Wat Pullwatch van een los project wil weten; zonder token geeft GitLab minder velden.
struct ExtraProjectDTO: Decodable {
    let id: Int
    let pathWithNamespace: String
}

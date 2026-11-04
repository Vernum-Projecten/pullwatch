public import Foundation

public protocol PRProvider: Sendable {
    /// Identiteit van de ingelogde gebruiker, vergeleken met `PullRequest.authorId`.
    func currentUserId() async throws -> String
    /// Verbindingstest: controleert token én toegang tot de organisatie/owner,
    /// en geeft de weergavenaam van de ingelogde gebruiker.
    func testConnection() async throws -> String
    /// Alle repos die het account kan zien, in hetzelfde formaat als `Account.repoWatch`.
    func listRepos() async throws -> [String]
    /// Alle open PR's inclusief drafts, ongefilterd.
    func openPullRequests() async throws -> [PullRequest]
    /// PR's in alle statussen (open, gemerged, gesloten), nieuwste eerst, afgekapt op `limit`.
    /// Met `since` alleen PR's die sindsdien zijn bijgewerkt (GitHub) of aangemaakt/gesloten (Azure DevOps).
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest]
    /// Tags van de opgegeven repos; `Tag.repo` is exact de doorgegeven repo-string.
    /// Een repo die 404 of geen toegang geeft wordt overgeslagen en in `unavailableRepos` gemeld.
    func tags(in repos: [String]) async throws -> TagFetch
    /// Als `tags(in:)`, maar een repo waarvan de vingerafdruk (`TagFetch.fingerprints`) nog gelijk
    /// is aan die in `unchanged` komt zonder tags terug, in `TagFetch.unchangedRepos`. Zo kost een
    /// poll waarin niets veranderde weinig. Een provider zonder vingerafdrukken haalt alles op.
    func tags(in repos: [String], unchanged: [String: String]) async throws -> TagFetch
    /// De nieuwste tags van één repo mét datum (`Tag.createdAt`), nieuwste eerst, hooguit
    /// `limit`. Alleen voor de eerste tag-poll van een repo, die ze stil in de geschiedenis zet.
    /// Een provider zonder datums geeft een lege lijst.
    func datedTags(in repo: String, limit: Int) async throws -> [Tag]
    /// Wie er naast de auteur aan deze PR's meewerkte, per `PullRequest.dedupKey`, zonder de
    /// auteur en bots (`CoAuthorTrailer.coAuthors`). Alleen voor nieuwe of veranderde PR's
    /// (`PollEngine`); een PR die de provider niet (meer) vindt ontbreekt of is leeg.
    func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]]
    /// De checks (CI) op de laatste commit van deze PR's, per `PullRequest.dedupKey`. Alleen
    /// de telling per stand, geen namen of links. Een PR zonder checks geeft een lege telling,
    /// een PR die de provider niet (meer) vindt ontbreekt; weigert de dienst de checks
    /// (rechten), dan `.needsPermission`.
    func checks(of pullRequests: [PullRequest]) async throws -> [String: PRChecks]
    /// Co-auteurs en checks in één keer: `coAuthorsOf` en `checksOf` zijn de dedupKeys van de
    /// PR's die elk nodig hebben. GitHub vraagt ze samen in dezelfde GraphQL-verzoeken; de
    /// standaard roept `coAuthors(of:)` en `checks(of:)` los aan, en een fout van de een laat de
    /// ander staan.
    func details(of pullRequests: [PullRequest], coAuthorsOf: Set<String>, checksOf: Set<String>) async throws -> PRDetails
    /// Alle bestandspaden (zonder leidende "/") op `ref` (tagnaam) of zonder ref op de default branch;
    /// een lege repo geeft een lege lijst.
    func filePaths(in repo: String, ref: String?) async throws -> [String]
    /// Inhoud van één bestand op `ref` (tagnaam) of zonder ref op de default branch, als tekst.
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String
    /// Gooi gecachte tokens weg (na een 401).
    func invalidateCredentials() async
    /// De beveiligingsgegevens van de dienst zelf voor één repo: code scanning, het aantal open
    /// geheimen en eigen adviezen (GitHub), of Advanced Security (Azure DevOps). Wat niet aan staat
    /// of niet mag, staat als `SecurityFeed` in het resultaat, niet als fout. nil: deze dienst kent
    /// zoiets niet.
    func securityAlerts(in repo: String) async throws -> SecurityScan?
    /// Token voor de openbare GitHub Advisory Database (hogere rate limit); nil zonder GitHub.
    func advisoryDatabaseToken() async -> String?
    /// Controleert een zelf toegevoegde repo (`Account.extraRepos`, al gelezen met
    /// `RepositoryReference`) met één verzoek: bestaat hij en mag dit account, of iedereen, hem
    /// lezen. Gooit `ProviderError.noAccess` als hij er niet is of niet te lezen is, en
    /// `RepositoryProblem.unsupported` bij een dienst die geen losse repo's kent.
    func checkRepository(_ repo: String) async throws -> RepositoryCheck
}

extension PRProvider {
    public func tags(in repos: [String], unchanged: [String: String]) async throws -> TagFetch {
        try await tags(in: repos)
    }

    public func securityAlerts(in repo: String) async throws -> SecurityScan? { nil }

    public func advisoryDatabaseToken() async -> String? { nil }

    /// Een provider zonder losse repo's (de standaard voor een nieuwe dienst tot hij ze kent).
    public func checkRepository(_ repo: String) async throws -> RepositoryCheck {
        throw RepositoryProblem.unsupported
    }

    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] { [] }

    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] { [:] }

    public func checks(of pullRequests: [PullRequest]) async throws -> [String: PRChecks] { [:] }

    public func details(of pullRequests: [PullRequest], coAuthorsOf: Set<String>, checksOf: Set<String>) async throws -> PRDetails {
        let forCoAuthors = pullRequests.filter { coAuthorsOf.contains($0.dedupKey) }
        let forChecks = pullRequests.filter { checksOf.contains($0.dedupKey) }
        var details = PRDetails()
        var failure: (any Error)?
        if !forCoAuthors.isEmpty {
            do { details.coAuthors = try await coAuthors(of: forCoAuthors) } catch { failure = error }
        }
        if !forChecks.isEmpty {
            do { details.checks = try await checks(of: forChecks) } catch { failure = failure ?? error }
        }
        // Alleen als niets lukte een fout; anders telt wat er wel is.
        if let failure, details.coAuthors.isEmpty, details.checks.isEmpty { throw failure }
        return details
    }

    public func filePaths(in repo: String) async throws -> [String] {
        try await filePaths(in: repo, ref: nil)
    }

    public func fileContent(in repo: String, path: String) async throws -> String {
        try await fileContent(in: repo, path: path, ref: nil)
    }
}

/// Wat `PRProvider.details` per PR (dedupKey) teruggeeft.
public struct PRDetails: Equatable, Sendable {
    public var coAuthors: [String: [Person]]
    public var checks: [String: PRChecks]

    public init(coAuthors: [String: [Person]] = [:], checks: [String: PRChecks] = [:]) {
        self.coAuthors = coAuthors
        self.checks = checks
    }
}

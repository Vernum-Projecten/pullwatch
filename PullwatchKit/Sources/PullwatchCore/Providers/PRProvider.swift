import Foundation

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
    /// De nieuwste tags van één repo mét datum (`Tag.createdAt`), nieuwste eerst, hooguit
    /// `limit`. Alleen voor de eerste tag-poll van een repo, die ze stil in de geschiedenis zet.
    /// Een provider zonder datums geeft een lege lijst.
    func datedTags(in repo: String, limit: Int) async throws -> [Tag]
    /// Wie er naast de auteur aan deze PR's meewerkte, per `PullRequest.dedupKey`, zonder de
    /// auteur en bots (`CoAuthorTrailer.coAuthors`). Alleen voor nieuwe of veranderde PR's
    /// (`PollEngine`); een PR die de provider niet (meer) vindt ontbreekt of is leeg.
    func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]]
    /// Alle bestandspaden (zonder leidende "/") op `ref` (tagnaam) of zonder ref op de default branch;
    /// een lege repo geeft een lege lijst.
    func filePaths(in repo: String, ref: String?) async throws -> [String]
    /// Inhoud van één bestand op `ref` (tagnaam) of zonder ref op de default branch, als tekst.
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String
    /// Gooi gecachte tokens weg (na een 401).
    func invalidateCredentials() async
}

extension PRProvider {
    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] { [] }

    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] { [:] }

    public func filePaths(in repo: String) async throws -> [String] {
        try await filePaths(in: repo, ref: nil)
    }

    public func fileContent(in repo: String, path: String) async throws -> String {
        try await fileContent(in: repo, path: path, ref: nil)
    }
}

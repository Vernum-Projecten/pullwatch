import Foundation
import PullwatchCore

/// De provider van een account dat niet kan inloggen: zonder bruikbaar adres voor zijn eigen server
/// (`Account.serverProblem`, `ProviderError.unusableServer`) of, bij Bitbucket, zonder e-mailadres
/// (`Account.lacksEmail`, `ProviderError.missingEmail`). Elk verzoek faalt meteen met die fout,
/// zonder netwerk en zonder token. Zo gaat een token nooit naar de standaard van de dienst of naar
/// een http-adres, ook niet als iemand het account toch probeert op te halen of te testen.
struct UnusableAccountProvider: PRProvider {
    let error: ProviderError

    func currentUserId() async throws -> String { throw error }
    func testConnection() async throws -> String { throw error }
    func listRepos() async throws -> [String] { throw error }
    func openPullRequests() async throws -> [PullRequest] { throw error }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { throw error }
    func tags(in repos: [String]) async throws -> TagFetch { throw error }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { throw error }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String { throw error }
    func invalidateCredentials() async {}
    func checkRepository(_ repo: String) async throws -> RepositoryCheck { throw error }
    func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages { throw error }
}

import Foundation
public import PullwatchCore

/// De checks van een pull request in Gitea en Forgejo: de commit statuses op de laatste commit
/// van de bronbranch (Gitea Actions, Forgejo Actions, Woodpecker en andere CI zetten ze daar).
/// Twee verzoeken per pull request: de pull request zelf (voor `head.sha`) en de gecombineerde
/// stand van die commit, met per context de laatste status.
extension GiteaProvider {
    /// Zonder statuses een lege telling. Mag het token de statuses niet lezen (401 of 403), dan
    /// `.needsPermission`. Een pull request die niet (meer) bestaat ontbreekt.
    public func checks(of pullRequests: [PullRequest]) async throws -> [String: PRChecks] {
        var result: [String: PRChecks] = [:]
        for pr in pullRequests {
            do {
                let anonymous = try await readsAnonymously(pr.repo)
                let pull: PullRequestDTO = try await get(repoEndpoint(pr.repo, "pulls", String(pr.number)), anonymous: anonymous)
                guard let sha = pull.head?.sha, !sha.isEmpty else {
                    result[pr.dedupKey] = .counts(CheckCounts())
                    continue
                }
                let combined: CombinedStatusDTO = try await get(
                    repoEndpoint(pr.repo, "commits", sha, "status"), anonymous: anonymous,
                    query: [URLQueryItem(name: "limit", value: String(pageSize))]
                )
                result[pr.dedupKey] = .counts(CheckCounts((combined.statuses ?? []).compactMap { Self.outcome(of: $0.status) }))
            } catch ProviderError.unauthorized, ProviderError.missingScope {
                result[pr.dedupKey] = .needsPermission
            } catch ProviderError.server(status: 404) {
                continue
            } catch ProviderError.rateLimited where readsWithoutTokenCached(pr.repo) {
                continue // limiet zonder token op: deze keer zonder checks
            }
        }
        return result
    }

    /// De stand van een commit status. `warning` is een geslaagde check met een waarschuwing
    /// (Gitea toont hem niet rood); `error` is een check die vastliep, dus mislukt. Forgejo kent
    /// ook `skipped`.
    static func outcome(of status: String?) -> CheckOutcome? {
        switch status {
        case "success", "warning": .passed
        case "skipped": .skipped
        case "failure", "error": .failed
        case "pending": .pending
        default: nil
        }
    }
}

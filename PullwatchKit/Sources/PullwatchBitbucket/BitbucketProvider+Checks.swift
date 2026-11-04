import Foundation
public import PullwatchCore

/// De checks van een pull request in Bitbucket: de build-statussen op de laatste commit van de
/// bronbranch (`/commit/{hash}/statuses`), van Bitbucket Pipelines en van andere CI (Jenkins,
/// Bamboo, …) die een status meldt. Eén verzoek per pull request.
extension BitbucketProvider {
    /// Zonder statussen een lege telling. Mag het token ze niet lezen (401 of 403), dan
    /// `.needsPermission`. Een pull request zonder bekende commit of een repo die niet (meer)
    /// bestaat ontbreekt.
    public func checks(of pullRequests: [PullRequest]) async throws -> [String: PRChecks] {
        var result: [String: PRChecks] = [:]
        for pr in pullRequests {
            guard let hash = pr.revision, Self.isCommitHash(hash) else { continue }
            do {
                let anonymous = try await readsAnonymously(pr.repo)
                let statuses: [CommitStatusDTO] = try await pages(
                    repository(pr.repo, "commit", hash, "statuses"),
                    query: [URLQueryItem(name: "pagelen", value: String(pageSize))],
                    maxPages: 1, anonymous: anonymous
                )
                result[pr.dedupKey] = .counts(CheckCounts(statuses.compactMap { Self.outcome(of: $0.state) }))
            } catch ProviderError.unauthorized {
                result[pr.dedupKey] = .needsPermission
            } catch ProviderError.server(status: 404) {
                continue
            } catch ProviderError.rateLimited where readsWithoutTokenCached(pr.repo) {
                continue // limiet zonder inloggen op: deze keer zonder checks
            }
        }
        return result
    }

    /// De stand van een build-status. Een gestopte build (STOPPED) telt als mislukt, zoals een
    /// geannuleerde job bij GitLab: hij is niet geslaagd en houdt een merge tegen.
    static func outcome(of state: String?) -> CheckOutcome? {
        switch state {
        case "SUCCESSFUL": .passed
        case "FAILED", "STOPPED": .failed
        case "INPROGRESS": .pending
        default: nil
        }
    }

    /// Een (verkorte) commit-hash, zoals `source.commit.hash` hem geeft ("6315b3bac849").
    static func isCommitHash(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy(\.isHexDigit)
    }
}

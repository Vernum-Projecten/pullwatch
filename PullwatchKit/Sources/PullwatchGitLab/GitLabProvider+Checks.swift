import Foundation
import PullwatchCore

/// De checks van een merge request in GitLab: de jobs van zijn `head_pipeline`, de pipeline op
/// de laatste commit van de bronbranch. Twee verzoeken per merge request (de merge request zelf,
/// want alleen die noemt `head_pipeline`, en de jobs van die pipeline).
extension GitLabProvider {
    /// Zonder pipeline een lege telling. Mag het token de pipeline niet lezen (401 of 403), dan
    /// `.needsPermission`. Een merge request die niet (meer) bestaat ontbreekt.
    public func checks(of pullRequests: [PullRequest]) async throws -> [String: PRChecks] {
        var result: [String: PRChecks] = [:]
        for pr in pullRequests {
            do {
                let anonymous = try await readsAnonymously(pr.repo)
                let request: MergeRequestPipelineDTO = try await get(
                    endpoint("projects", pr.repo, "merge_requests", String(pr.number)), anonymous: anonymous
                )
                guard let pipeline = request.headPipeline else {
                    result[pr.dedupKey] = .counts(CheckCounts())
                    continue
                }
                let jobs: [JobDTO] = try await get(
                    endpoint("projects", pr.repo, "pipelines", String(pipeline.id), "jobs"), anonymous: anonymous,
                    query: [URLQueryItem(name: "per_page", value: String(pageSize))]
                )
                // Een pipeline zonder zichtbare jobs (bv. alleen bridges): dan telt de pipeline zelf.
                let outcomes = jobs.isEmpty
                    ? [Self.outcome(of: pipeline.status, allowFailure: false)].compactMap { $0 }
                    : jobs.compactMap { Self.outcome(of: $0.status, allowFailure: $0.allowFailure ?? false) }
                result[pr.dedupKey] = .counts(CheckCounts(outcomes))
            } catch ProviderError.unauthorized {
                result[pr.dedupKey] = .needsPermission
            } catch ProviderError.server(status: 404) {
                continue
            } catch ProviderError.rateLimited where readsWithoutTokenCached(pr.repo) {
                continue // limiet zonder token op: deze keer zonder checks
            }
        }
        return result
    }

    /// De stand van een job of pipeline. Een handmatige job telt als overgeslagen; een mislukte
    /// job die mag mislukken (`allow_failure`) als geslaagd, zoals GitLab hem met een
    /// waarschuwing groen laat.
    static func outcome(of status: String?, allowFailure: Bool) -> CheckOutcome? {
        switch status {
        case "success": .passed
        case "skipped", "manual": .skipped
        case "failed": allowFailure ? .passed : .failed
        case "canceled", "canceling": .failed
        case "created", "pending", "running", "preparing", "scheduled", "waiting_for_resource",
             "waiting_for_callback": .pending
        default: nil
        }
    }

    struct MergeRequestPipelineDTO: Decodable {
        struct Pipeline: Decodable {
            let id: Int
            let status: String?
        }
        let headPipeline: Pipeline?
    }

    struct JobDTO: Decodable {
        let status: String?
        let allowFailure: Bool?
    }
}

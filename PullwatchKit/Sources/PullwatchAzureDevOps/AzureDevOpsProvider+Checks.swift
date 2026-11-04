import Foundation
public import PullwatchCore

/// De checks van een PR in Azure DevOps: de statussen die pipelines en andere diensten op de PR
/// zetten (`pullRequests/{id}/statuses`, per context alleen de nieuwste) en de build-policy's
/// (build validation) uit de policy-evaluaties van de PR. Twee verzoeken per PR.
extension AzureDevOpsProvider {
    /// Het type van de policy "Build" (build validation); andere policy's (reviewers, gekoppelde
    /// werkitems) zijn geen checks.
    static let buildPolicyType = "0609b952-1397-4640-95ec-e00a01b2c241"

    /// Mag het token de statussen niet lezen (401 of 403), dan `.needsPermission`; mag het alleen
    /// de policy's niet lezen, dan tellen alleen de statussen. Een PR die niet (meer) bestaat
    /// ontbreekt.
    public func checks(of pullRequests: [PullRequest]) async throws -> [String: PRChecks] {
        var result: [String: PRChecks] = [:]
        for pr in pullRequests {
            let parts = pr.repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let statuses: ValueList<StatusDTO>
            do {
                statuses = try await get(
                    baseURL.appending(path: parts[0]).appending(path: "_apis/git/repositories").appending(path: parts[1])
                        .appending(path: "pullRequests").appending(path: String(pr.number)).appending(path: "statuses")
                )
            } catch ProviderError.unauthorized {
                result[pr.dedupKey] = .needsPermission
                continue
            } catch ProviderError.server(status: 404) {
                continue
            }
            var counts = CheckCounts(Self.latest(statuses.value).compactMap { Self.outcome(of: $0.state) })
            if let projectId = projectIds[pr.dedupKey] {
                do {
                    let evaluations: EvaluationList = try await get(
                        baseURL.appending(path: parts[0]).appending(path: "_apis/policy/evaluations"),
                        apiVersion: "7.1-preview.1",
                        query: [URLQueryItem(name: "artifactId", value: "vstfs:///CodeReview/CodeReviewId/\(projectId)/\(pr.number)")]
                    )
                    for evaluation in evaluations.value
                    where evaluation.configuration.type.id == Self.buildPolicyType && evaluation.configuration.isEnabled != false {
                        if let outcome = Self.outcome(ofPolicy: evaluation.status) { counts.add(outcome) }
                    }
                } catch ProviderError.unauthorized, ProviderError.server(status: 404) {
                    // Zonder recht op de policy's: alleen de statussen.
                }
            }
            result[pr.dedupKey] = .counts(counts)
        }
        return result
    }

    /// Per context (genre en naam) de nieuwste status: een pipeline zet er bij elke iteratie een
    /// nieuwe bij.
    static func latest(_ statuses: [StatusDTO]) -> [StatusDTO] {
        var byContext: [String: StatusDTO] = [:]
        for status in statuses {
            let key = "\(status.context?.genre ?? "")/\(status.context?.name ?? "\(status.id ?? 0)")"
            if let known = byContext[key],
               (known.iterationId ?? 0, known.id ?? 0) >= (status.iterationId ?? 0, status.id ?? 0) { continue }
            byContext[key] = status
        }
        return Array(byContext.values)
    }

    /// `GitStatusState`; `notSet` telt niet mee.
    static func outcome(of state: String?) -> CheckOutcome? {
        switch state {
        case "succeeded": .passed
        case "notApplicable": .skipped
        case "failed", "error": .failed
        case "pending": .pending
        default: nil
        }
    }

    /// `PolicyEvaluationStatus` van een build-policy.
    static func outcome(ofPolicy status: String?) -> CheckOutcome? {
        switch status {
        case "approved": .passed
        case "notApplicable": .skipped
        case "rejected", "broken": .failed
        case "queued", "running": .pending
        default: nil
        }
    }

    struct StatusDTO: Decodable {
        struct Context: Decodable {
            let name: String?
            let genre: String?
        }
        let id: Int?
        let state: String?
        let iterationId: Int?
        let context: Context?
    }

    struct EvaluationList: Decodable {
        struct Evaluation: Decodable {
            struct Configuration: Decodable {
                struct PolicyType: Decodable { let id: String }
                let isEnabled: Bool?
                let type: PolicyType
            }
            let status: String?
            let configuration: Configuration
        }
        let value: [Evaluation]
    }
}

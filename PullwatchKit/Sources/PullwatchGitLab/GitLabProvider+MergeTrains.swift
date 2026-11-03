import Foundation
import PullwatchCore

/// De plek van een merge request in de merge train van zijn doelbranch (GitLab Premium,
/// `GET /projects/:id/merge_trains?scope=active&sort=asc`). Alleen voor projecten met een open
/// merge request dat auto-merge aan heeft: zo komt een merge request in de train, en een
/// project zonder zoiets kost geen verzoek. Een project zonder trains (Free, uit, of geen rechten)
/// krijgt een dag geen vraag meer.
extension GitLabProvider {
    /// Zo lang na "geen merge trains" vraagt Pullwatch het een project niet opnieuw.
    static let mergeTrainRetry: TimeInterval = 86_400

    /// De merge requests met hun plek in de train erbij. Een fout laat ze staan zoals ze zijn:
    /// met auto-merge, zonder plek.
    func withMergeTrains(_ pullRequests: [PullRequest]) async -> [PullRequest] {
        let projects = Set(pullRequests.filter { $0.mergeQueue != nil }.map(\.repo))
        guard !projects.isEmpty else { return pullRequests }
        var cars: [String: MergeQueueEntry] = [:]
        for project in projects.sorted() {
            let key = project.lowercased()
            if let since = withoutMergeTrains[key], now().timeIntervalSince(since) < Self.mergeTrainRetry { continue }
            // Een train lezen vraagt de rol Developer: zonder token kan het niet.
            if readsWithoutTokenCached(project) { continue }
            do {
                let found: [MergeTrainCarDTO] = try await pages(
                    endpoint("projects", project, "merge_trains"),
                    query: [URLQueryItem(name: "scope", value: "active"), URLQueryItem(name: "sort", value: "asc")],
                    maxPages: 1
                )
                for (iid, car) in Self.positions(found) { cars["\(project)!\(iid)"] = car }
                withoutMergeTrains[key] = nil
            } catch ProviderError.server(status: 404), ProviderError.unauthorized {
                // 403 (Free, geen rechten) wordt `unauthorized`, 404 een project zonder trains.
                withoutMergeTrains[key] = now()
            } catch {
                // Een tijdelijke fout: volgende poll opnieuw, de merge requests houden auto-merge.
                continue
            }
        }
        guard !cars.isEmpty else { return pullRequests }
        return pullRequests.map { pr in
            guard let car = cars["\(pr.repo)!\(pr.number)"] else { return pr }
            var pr = pr
            pr.mergeQueue = car
            return pr
        }
    }

    /// Per iid de plek in de train van zijn doelbranch, vanaf 1. GitLab geeft geen plek, maar
    /// een lager `id` kwam eerder in de train (de API-documentatie van merge trains).
    static func positions(_ cars: [MergeTrainCarDTO]) -> [Int: MergeQueueEntry] {
        var result: [Int: MergeQueueEntry] = [:]
        for (_, train) in Dictionary(grouping: cars, by: { $0.targetBranch ?? "" }) {
            for (index, car) in train.sorted(by: { $0.id < $1.id }).enumerated() {
                result[car.mergeRequest.iid] = MergeQueueEntry(
                    kind: .mergeTrain, position: index + 1, enqueuedAt: car.createdAt.flatMap(DateParsing.parse)
                )
            }
        }
        return result
    }
}

/// Eén merge request in een merge train (`/projects/:id/merge_trains`).
struct MergeTrainCarDTO: Decodable {
    struct MergeRequest: Decodable { let iid: Int }

    let id: Int
    let targetBranch: String?
    let createdAt: String?
    let mergeRequest: MergeRequest
}

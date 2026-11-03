import Foundation
import PullwatchCore

/// Of een open PR in de merge queue staat (`PullRequest.isInMergeQueue` en
/// `mergeQueueEntry { state position enqueuedAt }`), via dezelfde gebundelde GraphQL-vraag als de
/// co-auteurs en checks (`PRDetailQuery`), vijftig PR's per verzoek. De zoek-API van REST kent
/// de merge queue niet. Een server zonder deze velden (een oudere GitHub Enterprise Server)
/// krijgt de vraag daarna niet meer: geen PR staat dan in de rij.
extension GitHubProvider {
    /// PR's per GraphQL-verzoek: de vraag per PR is klein.
    static let mergeQueueBatch = 50

    /// De PR's met hun plek in de merge queue erbij. Drafts kunnen niet in de rij. Mislukt een
    /// verzoek, dan houden de PR's daarin wat de vorige vraag zei, en faalt de poll niet.
    func withMergeQueues(_ pullRequests: [PullRequest]) async -> [PullRequest] {
        guard !mergeQueueUnsupported else { return pullRequests }
        let candidates = pullRequests.filter {
            $0.state == .open && !$0.isDraft && $0.repo.split(separator: "/").count == 2 && !readsWithoutToken($0.repo)
        }
        guard !candidates.isEmpty else {
            knownMergeQueues = [:]
            return pullRequests
        }
        var found: [String: MergeQueueEntry] = [:]
        for batch in candidates.chunked(Self.mergeQueueBatch) {
            do {
                found.merge(try await mergeQueues(of: batch)) { _, new in new }
            } catch is GraphQLSchemaMismatch {
                mergeQueueUnsupported = true
                knownMergeQueues = [:]
                return pullRequests
            } catch {
                for pr in batch { if let known = knownMergeQueues[pr.dedupKey] { found[pr.dedupKey] = known } }
            }
        }
        knownMergeQueues = found
        return pullRequests.map { pr in
            var pr = pr
            pr.mergeQueue = found[pr.dedupKey]
            return pr
        }
    }

    /// Eén verzoek: per PR in de rij zijn plek. Gooit `GraphQLSchemaMismatch` als de server de
    /// velden niet kent.
    private func mergeQueues(of batch: [PullRequest]) async throws -> [String: MergeQueueEntry] {
        let wanted = batch.map { PRDetailQuery.Wanted(pr: $0, coAuthors: false, checks: false, mergeQueue: true) }
        let (data, _) = try await send(endpoints.graphQL, body: try JSONEncoder().encode(PRDetailQuery(wanted)))
        let response = try JSONDecoding.decode(PRDetailQuery.Response.self, from: data)
        guard let nodes = response.data else {
            if GraphQLSchemaMismatch.matches(response.errors) { throw GraphQLSchemaMismatch() }
            // Zonder `data` mislukte het hele verzoek (bv. de GraphQL-limiet); de aanroeper houdt
            // dan wat hij wist.
            throw ProviderError.decoding(response.errors?.first?.message.map { "GraphQL: \($0)" }
                ?? String(localized: "GraphQL-antwoord zonder gegevens", bundle: .localizedGitHub))
        }
        var result: [String: MergeQueueEntry] = [:]
        for (index, pr) in batch.enumerated() {
            guard let node = (nodes["pr\(index)"] ?? nil)?.pullRequest,
                  node.isInMergeQueue == true || node.mergeQueueEntry != nil else { continue }
            result[pr.dedupKey] = MergeQueueEntry(
                kind: .mergeQueue,
                position: node.mergeQueueEntry?.position,
                enqueuedAt: node.mergeQueueEntry?.enqueuedAt.flatMap(DateParsing.parse)
            )
        }
        return result
    }
}

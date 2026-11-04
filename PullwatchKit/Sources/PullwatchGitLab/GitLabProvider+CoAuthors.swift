import Foundation
import PullwatchCore

// MARK: - Co-auteurs

extension GitLabProvider {
    /// Per merge request de commits (`merge_requests/:iid/commits`): hun auteurs en de
    /// `Co-authored-by:`-trailers in de berichten. GitLab koppelt commits niet aan gebruikers, dus
    /// zonder login of foto. Een merge request die niet (meer) bestaat geeft een lege lijst.
    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        var result: [String: [Person]] = [:]
        for pr in pullRequests {
            let commits: [CommitDTO]
            do {
                let anonymous = try await readsAnonymously(pr.repo)
                commits = try await get(
                    endpoint("projects", pr.repo, "merge_requests", String(pr.number), "commits"), anonymous: anonymous, query: [
                        URLQueryItem(name: "per_page", value: String(pageSize)),
                    ]
                )
            } catch ProviderError.server(status: 404) {
                result[pr.dedupKey] = []
                continue
            } catch ProviderError.rateLimited where readsWithoutTokenCached(pr.repo) {
                continue // limiet zonder token op: deze keer zonder co-auteurs
            }
            var candidates: [Person] = []
            for commit in commits {
                if let name = commit.authorName, !name.isEmpty, !Self.isBot(name) {
                    candidates.append(Person(name: name, email: commit.authorEmail))
                }
                candidates += CoAuthorTrailer.people(in: commit.message ?? "")
            }
            let author = [pr.authorId, pr.authorName] + (authorNames[pr.dedupKey].map { [$0] } ?? [])
            result[pr.dedupKey] = CoAuthorTrailer.coAuthors(from: candidates, author: author)
        }
        return result
    }
}

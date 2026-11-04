import Foundation
public import PullwatchCore

// MARK: - Co-auteurs

extension BitbucketProvider {
    /// Per pull request de commits (`pullrequests/{id}/commits`, één pagina van honderd): hun
    /// auteurs en de `Co-authored-by:`-trailers in de berichten. Een pull request die niet (meer)
    /// bestaat geeft een lege lijst.
    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        var result: [String: [Person]] = [:]
        for pr in pullRequests {
            let commits: [CommitDTO]
            do {
                commits = try await pages(
                    repository(pr.repo, "pullrequests", String(pr.number), "commits"),
                    query: [URLQueryItem(name: "pagelen", value: String(pageSize))],
                    maxPages: 1, anonymous: try await readsAnonymously(pr.repo)
                )
            } catch ProviderError.server(status: 404) {
                result[pr.dedupKey] = []
                continue
            } catch ProviderError.rateLimited where readsWithoutTokenCached(pr.repo) {
                continue // limiet zonder inloggen op: deze keer zonder co-auteurs
            }
            var candidates: [Person] = []
            for commit in commits {
                let raw = commit.author?.raw ?? ""
                if let name = commit.author?.user?.displayName ?? Self.name(fromRaw: raw) {
                    candidates.append(Person(
                        name: name, email: Self.email(fromRaw: raw),
                        avatarURL: commit.author?.user?.links?.avatar?.href.flatMap(URL.init(string:))
                    ))
                }
                candidates += CoAuthorTrailer.people(in: commit.message ?? "")
            }
            let author = [pr.authorId, pr.authorName] + (authorNames[pr.dedupKey].map { [$0] } ?? [])
            result[pr.dedupKey] = CoAuthorTrailer.coAuthors(from: candidates, author: author)
        }
        return result
    }
}

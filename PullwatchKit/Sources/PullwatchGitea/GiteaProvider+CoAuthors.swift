import Foundation
public import PullwatchCore

// MARK: - Co-auteurs

extension GiteaProvider {
    /// Per pull request de commits (`pulls/:nummer/commits`, zonder handtekeningen en bestanden):
    /// hun auteurs, met login en foto als de server de commit aan een gebruiker koppelt, en de
    /// `Co-authored-by:`-trailers in de berichten. Een pull request die niet (meer) bestaat geeft
    /// een lege lijst.
    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        var result: [String: [Person]] = [:]
        for pr in pullRequests {
            let commits: [CommitDTO]
            do {
                commits = try await get(
                    repoEndpoint(pr.repo, "pulls", String(pr.number), "commits"),
                    anonymous: try await readsAnonymously(pr.repo),
                    query: [
                        URLQueryItem(name: "limit", value: String(pageSize)),
                        URLQueryItem(name: "verification", value: "false"),
                        URLQueryItem(name: "files", value: "false"),
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
                let login = commit.author?.login
                if let name = commit.commit?.author?.name, !name.isEmpty, !Self.isBot(name), !Self.isBot(login ?? "") {
                    candidates.append(Person(
                        name: name, login: login, email: commit.commit?.author?.email,
                        avatarURL: commit.author?.avatarUrl.flatMap(URL.init(string:))
                    ))
                }
                candidates += CoAuthorTrailer.people(in: commit.commit?.message ?? "")
            }
            let author = [pr.authorId, pr.authorName] + (authorNames[pr.dedupKey].map { [$0] } ?? [])
            result[pr.dedupKey] = CoAuthorTrailer.coAuthors(from: candidates, author: author)
        }
        return result
    }
}

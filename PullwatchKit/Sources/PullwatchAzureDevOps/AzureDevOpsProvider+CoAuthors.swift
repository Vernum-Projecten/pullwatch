import Foundation
public import PullwatchCore

// MARK: - Co-auteurs

extension AzureDevOpsProvider {
    /// Per PR de commits (`pullRequests/{id}/commits`): hun auteurs en de `Co-authored-by:`-trailers
    /// in de berichten. Azure DevOps kent geen co-auteurs en geen foto's. Een afgekapt bericht
    /// wordt los opgehaald (hooguit tien per PR). Een PR die niet (meer) bestaat geeft een lege lijst.
    public func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        var result: [String: [Person]] = [:]
        for pr in pullRequests {
            let parts = pr.repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let repoURL = baseURL.appending(path: parts[0]).appending(path: "_apis/git/repositories").appending(path: parts[1])
            let commits: ValueList<PRCommitDTO>
            do {
                commits = try await get(
                    repoURL.appending(path: "pullRequests").appending(path: String(pr.number)).appending(path: "commits"),
                    query: [URLQueryItem(name: "$top", value: String(pageSize))]
                )
            } catch ProviderError.server(status: 404) {
                result[pr.dedupKey] = []
                continue
            }
            var candidates: [Person] = []
            var fullMessages = 0
            for commit in commits.value {
                if let name = commit.author?.name, !name.isEmpty {
                    candidates.append(Person(name: name, email: commit.author?.email))
                }
                var message = commit.comment ?? ""
                if commit.commentTruncated == true, fullMessages < fullMessageLimit {
                    fullMessages += 1
                    let full: PRCommitDTO = try await get(repoURL.appending(path: "commits").appending(path: commit.commitId))
                    message = full.comment ?? message
                }
                candidates += CoAuthorTrailer.people(in: message)
            }
            let author = [pr.authorId, pr.authorName] + (authorEmails[pr.dedupKey].map { [$0] } ?? [])
            result[pr.dedupKey] = CoAuthorTrailer.coAuthors(from: candidates, author: author)
        }
        return result
    }
}

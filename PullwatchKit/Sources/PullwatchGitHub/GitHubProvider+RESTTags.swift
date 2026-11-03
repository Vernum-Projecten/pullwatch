import Foundation
import PullwatchCore

/// Tags en releases via REST voor alle repo's, voor een GitHub Enterprise Server waarvan de
/// GraphQL-API een veld uit `TagQuery` niet kent. Per repo dezelfde twee verzoeken als bij een
/// losse repo (`restTags(_:into:)`); een tag zonder release heeft hier geen datum en geen auteur.
extension GitHubProvider {
    func restTags(in repos: [String]) async throws -> TagFetch {
        var fetch = TagFetch(tags: [])
        for repo in repos {
            guard repo.split(separator: "/").count == 2 else {
                fetch.unavailableRepos.append(repo)
                continue
            }
            await restTags(repo, into: &fetch)
        }
        return fetch
    }
}

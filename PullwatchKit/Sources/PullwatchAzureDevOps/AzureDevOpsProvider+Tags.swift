import Foundation
import PullwatchCore

// MARK: - Tags

extension AzureDevOpsProvider {
    public func tags(in repos: [String]) async throws -> TagFetch {
        var result: [Tag] = []
        var unavailable: [String] = []
        for repo in repos {
            guard let slash = repo.firstIndex(of: "/") else { continue }
            let project = String(repo[..<slash])
            let name = String(repo[repo.index(after: slash)...])
            let repoURL = baseURL.appending(path: project).appending(path: "_apis/git/repositories").appending(path: name)
            let list: ValueList<RefDTO>
            do {
                list = try await get(
                    repoURL.appending(path: "refs"),
                    query: [URLQueryItem(name: "filter", value: "tags/"), URLQueryItem(name: "peelTags", value: "true")]
                )
            } catch ProviderError.server(status: 404) {
                unavailable.append(repo) // repo bestaat niet (meer)
                continue
            } catch ProviderError.unauthorized {
                unavailable.append(repo) // geen toegang (403: SSO, rechten, IP-allowlist); andere repo's gaan door
                continue
            }
            let fallback = await missingAuthors(list.value, repoURL: repoURL)
            for ref in list.value {
                let tagName = Self.tagName(fromRef: ref.name)
                result.append(Tag(
                    accountId: accountId,
                    repo: repo,
                    name: tagName,
                    authorName: ref.creator?.displayName ?? fallback[ref.name],
                    webURL: tagURL(project: project, repo: name, tag: tagName)
                ))
            }
        }
        return TagFetch(tags: result, unavailableRepos: unavailable)
    }

    /// Tags met de datum van hun commit: de refs (met `peelTags`, zodat een geannoteerde tag zijn
    /// commit noemt) en daarna de commits in één `commitsbatch` per honderd.
    public func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        guard let slash = repo.firstIndex(of: "/"), limit > 0 else { return [] }
        let project = String(repo[..<slash])
        let name = String(repo[repo.index(after: slash)...])
        let repoURL = baseURL.appending(path: project).appending(path: "_apis/git/repositories").appending(path: name)
        let list: ValueList<RefDTO> = try await get(
            repoURL.appending(path: "refs"),
            query: [URLQueryItem(name: "filter", value: "tags/"), URLQueryItem(name: "peelTags", value: "true")]
        )
        var commitByTag: [String: String] = [:]
        for ref in list.value {
            guard let commit = ref.peeledObjectId ?? ref.objectId else { continue }
            commitByTag[ref.name] = commit
        }
        var dates: [String: Date] = [:]
        var commitAuthors: [String: String] = [:]
        let ids = Array(Set(commitByTag.values)).sorted()
        // Hooguit tien batches: een repo met duizenden tags hoeft niet helemaal terug.
        for start in stride(from: 0, to: min(ids.count, 1000), by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let body = try JSONEncoder().encode(CommitsBatchDTO(ids: batch, top: batch.count))
            let commits: ValueList<CommitDTO> = try await get(repoURL.appending(path: "commitsbatch"), body: body)
            for commit in commits.value {
                if let date = (commit.committer?.date ?? commit.author?.date).flatMap(DateParsing.parse) {
                    dates[commit.commitId] = date
                }
                if let author = commit.author?.name, !author.isEmpty { commitAuthors[commit.commitId] = author }
            }
        }
        let creators = Dictionary(list.value.map { ($0.name, $0.creator?.displayName) }, uniquingKeysWith: { first, _ in first })
        let tags: [Tag] = commitByTag.compactMap { refName, commit in
            guard let date = dates[commit] else { return nil }
            let tagName = Self.tagName(fromRef: refName)
            return Tag(
                accountId: accountId,
                repo: repo,
                name: tagName,
                authorName: (creators[refName] ?? nil) ?? commitAuthors[commit],
                webURL: tagURL(project: project, repo: name, tag: tagName),
                createdAt: date
            )
        }
        return Array(tags.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }.prefix(limit))
    }

    /// Auteurs voor tags waarbij Azure DevOps geen `creator` noemt: bij een geannoteerde tag
    /// (met `peeledObjectId`) de tagger uit `annotatedtags`, bij een lichte tag de auteur van
    /// de commit uit één `commitsbatch`. Hooguit twintig tags en honderd commits, zodat een
    /// oude repo zonder creators de poll niet ophoudt; wat mislukt blijft zonder auteur.
    private func missingAuthors(_ refs: [RefDTO], repoURL: URL) async -> [String: String] {
        let missing = refs.filter { $0.creator == nil && $0.objectId != nil }
        guard !missing.isEmpty else { return [:] }
        var authors: [String: String] = [:]
        for ref in missing.filter({ $0.peeledObjectId != nil }).prefix(20) {
            guard let objectId = ref.objectId,
                  let tag: AnnotatedTagDTO = try? await get(repoURL.appending(path: "annotatedtags").appending(path: objectId)),
                  let name = tag.taggedBy?.name, !name.isEmpty else { continue }
            authors[ref.name] = name
        }
        let lightweight = Array(missing.filter { $0.peeledObjectId == nil }.prefix(100))
        let ids = Array(Set(lightweight.compactMap(\.objectId))).sorted()
        if !ids.isEmpty, let body = try? JSONEncoder().encode(CommitsBatchDTO(ids: ids, top: ids.count)),
           let commits: ValueList<CommitDTO> = try? await get(repoURL.appending(path: "commitsbatch"), body: body) {
            let byId = Dictionary(commits.value.compactMap { commit in commit.author?.name.map { (commit.commitId, $0) } },
                                  uniquingKeysWith: { first, _ in first })
            for ref in lightweight {
                if let id = ref.objectId, let name = byId[id], !name.isEmpty { authors[ref.name] = name }
            }
        }
        return authors
    }

    private func tagURL(project: String, repo: String, tag: String) -> URL {
        let base = baseURL.appending(path: project).appending(path: "_git").appending(path: repo)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        // "+" en andere tekens expliciet coderen; "/" blijft leesbaar.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        components.percentEncodedQuery = "version=GT" + (tag.addingPercentEncoding(withAllowedCharacters: allowed) ?? tag)
        return components.url!
    }

    /// "refs/tags/v1.0" wordt "v1.0"; een naam zonder dat voorvoegsel blijft zoals hij is.
    static func tagName(fromRef ref: String) -> String {
        ref.hasPrefix("refs/tags/") ? String(ref.dropFirst("refs/tags/".count)) : ref
    }
}

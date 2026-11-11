public import Foundation
public import PullwatchCore

// MARK: - Branches

extension AzureDevOpsProvider {
    public func branches(in repos: [String], unchanged: [String: String]) async throws -> BranchFetch {
        var fetch = BranchFetch()
        for repo in repos {
            guard let (project, name) = Self.split(repo) else {
                fetch.unavailableRepos.append(repo)
                continue
            }
            let repoURL = baseURL.appending(path: project).appending(path: "_apis/git/repositories").appending(path: name)
            do {
                let refs = try await headRefs(repoURL: repoURL)
                // Gesorteerde `name:sha`: verandert zodra een branch komt, gaat of een nieuwe commit krijgt.
                let fingerprint = refs.map { "\($0.name):\($0.sha)" }.sorted().joined(separator: "\n")
                if unchanged[repo] == fingerprint {
                    fetch.unchangedRepos.append(repo)
                    continue
                }
                let commits = try await commits(of: refs.map(\.sha), repoURL: repoURL)
                fetch.fingerprints[repo] = fingerprint
                fetch.heads += refs.map { ref in
                    let commit = commits[ref.sha]
                    return BranchHead(
                        repo: repo,
                        name: ref.name,
                        sha: ref.sha,
                        committedAt: (commit?.committer?.date ?? commit?.author?.date).flatMap(DateParsing.parse),
                        authorName: commit?.author?.name,
                        authorId: nil, // de GUID van een gebruiker staat niet op de commit
                        authorEmail: commit?.author?.email,
                        webURL: branchURL(project: project, repo: name, branch: ref.name)
                    )
                }
            } catch ProviderError.server(status: 404) {
                fetch.unavailableRepos.append(repo) // repo bestaat niet (meer)
            } catch ProviderError.unauthorized {
                fetch.unavailableRepos.append(repo) // geen toegang; andere repo's gaan door
            }
        }
        return fetch
    }

    public func compare(in repo: String, from: String, to: String) async throws -> BranchComparison? {
        guard let (project, name) = Self.split(repo) else { return nil }
        let url = baseURL.appending(path: project).appending(path: "_apis/git/repositories").appending(path: name)
            .appending(path: "diffs/commits")
        do {
            let diffs: CommitDiffsDTO = try await get(url, query: [
                URLQueryItem(name: "baseVersion", value: from),
                URLQueryItem(name: "baseVersionType", value: "commit"),
                URLQueryItem(name: "targetVersion", value: to),
                URLQueryItem(name: "targetVersionType", value: "commit"),
                URLQueryItem(name: "$top", value: "1"),
            ])
            return BranchComparison(ahead: diffs.aheadCount, behind: diffs.behindCount)
        } catch ProviderError.server(status: 404) {
            return nil
        }
    }

    public nonisolated func compareURL(in repo: String, from: String, to: String) -> URL? {
        guard let (project, name) = Self.split(repo) else { return nil }
        let base = URL(string: "https://dev.azure.com")!.appending(path: organization).appending(path: project)
            .appending(path: "_git").appending(path: name).appending(path: "branchCompare")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = "baseVersion=GC\(Self.encode(from))&targetVersion=GC\(Self.encode(to))"
        return components?.url
    }

    // MARK: Hulp

    private struct HeadRef { let name: String; let sha: String }

    /// Alle heads van een repo; de lijst komt in stukken met een vervolgtoken in de antwoordheader.
    private func headRefs(repoURL: URL) async throws -> [HeadRef] {
        var result: [HeadRef] = []
        var token: String?
        var pages = 0
        repeat {
            var query = [URLQueryItem(name: "filter", value: "heads/"), URLQueryItem(name: "peelTags", value: "false")]
            if let token { query.append(URLQueryItem(name: "continuationToken", value: token)) }
            let (data, response) = try await send(repoURL.appending(path: "refs"), apiVersion: "7.1", query: query)
            try HTTPStatus.check(response, now: now())
            let list = try JSONDecoding.decode(ValueList<RefDTO>.self, from: data)
            for ref in list.value {
                guard let sha = ref.objectId, ref.name.hasPrefix("refs/heads/") else { continue }
                result.append(HeadRef(name: String(ref.name.dropFirst("refs/heads/".count)), sha: sha))
            }
            token = response.value(forHTTPHeaderField: "x-ms-continuationtoken").flatMap { $0.isEmpty ? nil : $0 }
            pages += 1
        } while token != nil && pages < 100 // een kapotte server mag de poll niet eindeloos bezighouden
        return result
    }

    /// De commits per sha, in één `commitsbatch` per honderd.
    private func commits(of shas: [String], repoURL: URL) async throws -> [String: CommitDTO] {
        let ids = Array(Set(shas)).sorted()
        var result: [String: CommitDTO] = [:]
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let body = try JSONEncoder().encode(CommitsBatchDTO(ids: batch, top: batch.count))
            let list: ValueList<CommitDTO> = try await get(repoURL.appending(path: "commitsbatch"), body: body)
            for commit in list.value { result[commit.commitId] = commit }
        }
        return result
    }

    private func branchURL(project: String, repo: String, branch: String) -> URL {
        let base = baseURL.appending(path: project).appending(path: "_git").appending(path: repo)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = "version=GB" + Self.encode(branch)
        return components.url!
    }

    /// "project/repo" in twee delen; nil zonder streepje.
    private nonisolated static func split(_ repo: String) -> (project: String, name: String)? {
        guard let slash = repo.firstIndex(of: "/") else { return nil }
        return (String(repo[..<slash]), String(repo[repo.index(after: slash)...]))
    }

    /// "/" blijft leesbaar; spatie, "#", "+" en andere tekens worden gecodeerd.
    private nonisolated static func encode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

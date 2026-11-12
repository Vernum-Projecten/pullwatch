import CryptoKit
public import Foundation
public import PullwatchCore

// MARK: - Branches

extension GiteaProvider {
    /// Hooguit zoveel pagina's per repo (vijfduizend branches); daarna telt wat er is.
    static let branchMaxPages = 100

    /// Per repo alle branches met hun laatste commit, zoals `tags(in:)` repo na repo. Gitea kent
    /// geen goedkopere controle, dus de vingerafdruk (de hash van de gesorteerde `naam:sha`-paren)
    /// volgt pas na het ophalen; een gelijke geeft `unchangedRepos`. Elke gevraagde repo komt in
    /// precies één uitkomst: gelezen (een vingerafdruk, ook zonder branches), `unavailableRepos`
    /// of `unchangedRepos`.
    public func branches(in repos: [String], unchanged known: [String: String]) async throws -> BranchFetch {
        var fetch = BranchFetch()
        for repo in repos {
            do {
                let branches = try await branches(of: repo)
                let fingerprint = Self.branchFingerprint(branches.map { ($0.name, $0.commit?.id ?? "") })
                if known[repo] == fingerprint {
                    fetch.unchangedRepos.append(repo)
                    continue
                }
                fetch.fingerprints[repo] = fingerprint
                fetch.heads += branches.compactMap { makeHead(repo: repo, $0) }
            } catch ProviderError.server(status: 404) {
                fetch.unavailableRepos.append(repo) // bestaat niet (meer)
            } catch ProviderError.unauthorized {
                fetch.unavailableRepos.append(repo) // 403: geen toegang tot de repository
            } catch ProviderError.rateLimited where readsWithoutTokenCached(repo) {
                fetch.unavailableRepos.append(repo) // limiet zonder token op; de volgende keer weer
            }
        }
        return fetch
    }

    private func branches(of repo: String) async throws -> [BranchDTO] {
        try await pages(
            repoEndpoint(repo, "branches"), query: [], maxPages: Self.branchMaxPages,
            anonymous: try await readsAnonymously(repo)
        )
    }

    /// De auteur is de naam uit git; `authorId` is de gebruikersnaam van het account achter de
    /// commit (dezelfde als `currentUserId()`), en ontbreekt als Gitea de commit aan niemand
    /// koppelt. Gitea geeft hier geen foto mee.
    private func makeHead(repo: String, _ dto: BranchDTO) -> BranchHead? {
        guard let commit = dto.commit, let webURL = branchURL(repo: repo, branch: dto.name) else { return nil }
        return BranchHead(
            repo: repo,
            name: dto.name,
            sha: commit.id,
            committedAt: commit.timestamp.flatMap(DateParsing.parse),
            authorName: commit.author?.name.flatMap { $0.isEmpty ? nil : $0 },
            authorId: commit.author?.username.flatMap { $0.isEmpty ? nil : $0 },
            authorEmail: commit.author?.email.flatMap { $0.isEmpty ? nil : $0 },
            authorAvatarURL: nil,
            webURL: webURL
        )
    }

    /// Hash van de op naam gesorteerde `naam:sha`-paren; verandert bij een push, een nieuwe en
    /// een verwijderde branch.
    static func branchFingerprint(_ pairs: [(name: String, sha: String)]) -> String {
        let text = pairs.sorted { $0.name < $1.name }.map { "\($0.name):\($0.sha)" }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Hoeveel commits `to` voor en achter ligt op `from`: twee vergelijkingen
    /// (`compare/<van>...<naar>`, `total_commits`). Oudere Gitea-versies kennen `compare` niet
    /// (404), en dan weten we het niet: nil.
    public func compare(in repo: String, from: String, to: String) async throws -> BranchComparison? {
        do {
            let anonymous = try await readsAnonymously(repo)
            let ahead = try await commitCount(repo, from: from, to: to, anonymous: anonymous)
            let behind = try await commitCount(repo, from: to, to: from, anonymous: anonymous)
            return BranchComparison(ahead: ahead, behind: behind)
        } catch ProviderError.server(status: 404) {
            return nil
        }
    }

    private func commitCount(_ repo: String, from: String, to: String, anonymous: Bool) async throws -> Int {
        let dto: CompareDTO = try await get(repoEndpoint(repo, "compare", "\(from)...\(to)"), anonymous: anonymous)
        return dto.totalCommits
    }

    nonisolated public func compareURL(in repo: String, from: String, to: String) -> URL? {
        webURL(repo, "compare", "\(from)...\(to)")
    }

    /// De bestanden op deze branch. Elk segment van de naam apart gecodeerd: de "/" blijft een
    /// "/" (Gitea leest `src/branch/feature/x` als branch `feature/x`), de rest wordt %-gecodeerd.
    nonisolated func branchURL(repo: String, branch: String) -> URL? {
        let name = branch.split(separator: "/", omittingEmptySubsequences: false).map { Self.encode(String($0)) }
        let repoPath = repo.split(separator: "/").map { Self.encode(String($0)) }
        return URL(string: instanceURL.absoluteString + "/" + (repoPath + ["src", "branch"] + name).joined(separator: "/"))
    }
}

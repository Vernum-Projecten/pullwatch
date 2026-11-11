import CryptoKit
public import Foundation
public import PullwatchCore

// MARK: - Branches

extension BitbucketProvider {
    /// Hooguit zoveel pagina's per repo (vijfduizend branches); daarna telt wat er is.
    static let branchMaxPages = 50
    /// Zoveel commits telt een vergelijking hooguit per kant.
    static let compareLimit = 100

    /// Per repo alle branches met hun laatste commit, zoals `tags(in:)` repo na repo. Bitbucket
    /// kent geen goedkopere controle, dus de vingerafdruk (de hash van de gesorteerde
    /// `naam:sha`-paren) volgt pas na het ophalen; een gelijke geeft `unchangedRepos`. Elke
    /// gevraagde repo komt in precies één uitkomst: gelezen (een vingerafdruk, ook zonder
    /// branches), `unavailableRepos` of `unchangedRepos`.
    public func branches(in repos: [String], unchanged known: [String: String]) async throws -> BranchFetch {
        var fetch = BranchFetch()
        for repo in repos {
            do {
                let branches = try await branches(of: repo)
                let fingerprint = Self.branchFingerprint(branches.map { ($0.name, $0.target?.hash ?? "") })
                if known[repo] == fingerprint {
                    fetch.unchangedRepos.append(repo)
                    continue
                }
                fetch.fingerprints[repo] = fingerprint
                fetch.heads += branches.compactMap { makeHead(repo: repo, $0) }
            } catch ProviderError.server(status: 404) {
                fetch.unavailableRepos.append(repo) // bestaat niet (meer)
            } catch ProviderError.unauthorized where isExtra(repo) {
                fetch.unavailableRepos.append(repo) // 403: geen toegang tot deze losse repo
            } catch ProviderError.rateLimited where readsWithoutTokenCached(repo) {
                fetch.unavailableRepos.append(repo) // limiet zonder inloggen op; de volgende keer weer
            }
        }
        return fetch
    }

    private func branches(of repo: String) async throws -> [BranchDTO] {
        try await pages(
            repository(repo, "refs", "branches"),
            query: [URLQueryItem(name: "pagelen", value: String(pageSize))],
            maxPages: Self.branchMaxPages, anonymous: try await readsAnonymously(repo)
        )
    }

    /// De auteur is de naam uit git, of het Bitbucket-account als Bitbucket het e-mailadres kent.
    /// `authorId` is de uuid van dat account, hetzelfde als `currentUserId()`.
    private func makeHead(repo: String, _ dto: BranchDTO) -> BranchHead? {
        guard let hash = dto.target?.hash, let webURL = Self.webURL(repo, "branch", dto.name) else { return nil }
        let author = dto.target?.author
        return BranchHead(
            repo: repo,
            name: dto.name,
            sha: hash,
            committedAt: dto.target?.date.flatMap(DateParsing.parse),
            authorName: author?.user?.displayName ?? author?.raw.flatMap(Self.name(fromRaw:)),
            authorId: author?.user?.uuid,
            authorEmail: author?.raw.flatMap(Self.email(fromRaw:)),
            authorAvatarURL: author?.user?.links?.avatar?.href.flatMap(URL.init(string:)),
            webURL: webURL
        )
    }

    /// Hash van de op naam gesorteerde `naam:sha`-paren; verandert bij een push, een nieuwe en
    /// een verwijderde branch.
    static func branchFingerprint(_ pairs: [(name: String, sha: String)]) -> String {
        let text = pairs.sorted { $0.name < $1.name }.map { "\($0.name):\($0.sha)" }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Hoeveel commits `to` voor en achter ligt op `from`: twee vragen (`include` en `exclude`),
    /// elk tot honderd commits. Een onbekende commit (404) geeft nil.
    public func compare(in repo: String, from: String, to: String) async throws -> BranchComparison? {
        do {
            let anonymous = try await readsAnonymously(repo)
            let ahead = try await commitCount(repo, include: to, exclude: from, anonymous: anonymous)
            let behind = try await commitCount(repo, include: from, exclude: to, anonymous: anonymous)
            return BranchComparison(ahead: ahead, behind: behind)
        } catch ProviderError.server(status: 404) {
            return nil
        }
    }

    private func commitCount(_ repo: String, include: String, exclude: String, anonymous: Bool) async throws -> Int {
        let commits: [CommitDTO] = try await pages(
            repository(repo, "commits"),
            query: [
                URLQueryItem(name: "include", value: include),
                URLQueryItem(name: "exclude", value: exclude),
                URLQueryItem(name: "pagelen", value: String(Self.compareLimit)),
            ],
            maxPages: 1, anonymous: anonymous
        )
        return min(commits.count, Self.compareLimit)
    }

    /// De vergelijkingspagina: `to` en `from` gescheiden door een gecodeerde regelterugloop
    /// (`%0D`), elk deel apart gecodeerd.
    nonisolated public func compareURL(in repo: String, from: String, to: String) -> URL? {
        Self.pageURL(repo, ["branches", "compare", Self.encode(to) + "%0D" + Self.encode(from)])
    }
}

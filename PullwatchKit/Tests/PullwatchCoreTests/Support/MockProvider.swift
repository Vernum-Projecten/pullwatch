import Foundation
@testable import PullwatchCore

actor MockProvider: PRProvider {
    private var userId = "me"
    private var pullRequests: [PullRequest] = []
    private var error: ProviderError?
    private var tagError: ProviderError?
    private var unavailableTagRepos: Set<String> = []
    private var tagList: [Tag] = []
    private var datedTagList: [Tag] = []
    private var datedTagError: ProviderError?
    private var repos: [String] = []
    private(set) var datedTagRepos: [String] = []
    private var syncedPullRequests: [PullRequest] = []
    private var syncError: ProviderError?
    private(set) var fetchCount = 0
    private(set) var syncCount = 0
    /// Laatste aan `pullRequests(updatedSince:limit:)` doorgegeven `since` (nil = nog nooit aangeroepen).
    private(set) var lastSyncSince: Date??
    private(set) var tagFetchCount = 0
    /// Vingerafdruk per repo (lowercased) die `tags(in:unchanged:)` geeft; leeg = geen vingerafdrukken.
    private var fingerprints: [String: String] = [:]
    /// Laatste aan `tags(in:unchanged:)` doorgegeven vingerafdrukken.
    private(set) var lastUnchanged: [String: String] = [:]
    private(set) var invalidateCount = 0
    private var coAuthorList: [String: [Person]] = [:]
    private var coAuthorError: ProviderError?
    /// Per aanroep van `coAuthors(of:)` de dedupKeys die gevraagd werden.
    private(set) var coAuthorRequests: [[String]] = []
    private var checkList: [String: PRChecks] = [:]
    /// Per aanroep van `checks(of:)` de dedupKeys die gevraagd werden.
    private(set) var checkRequests: [[String]] = []

    private var unreadQueues: Set<String> = []
    private var exits = MergeQueueExits()
    /// Per aanroep van `mergeQueueExits(of:)` de dedupKeys die gevraagd werden.
    private(set) var exitRequests: [[String]] = []

    func set(pullRequests: [PullRequest]) { self.pullRequests = pullRequests }
    func set(unreadMergeQueues: Set<String>) { unreadQueues = unreadMergeQueues }
    func set(exits: MergeQueueExits) { self.exits = exits }

    func unreadMergeQueues() async -> Set<String> { unreadQueues }

    func mergeQueueExits(of pullRequests: [PullRequest]) async -> MergeQueueExits {
        exitRequests.append(pullRequests.map(\.dedupKey))
        return exits
    }
    func set(syncedPullRequests: [PullRequest]) { self.syncedPullRequests = syncedPullRequests }
    /// Fout die alleen `pullRequests(updatedSince:limit:)` gooit.
    func set(syncError: ProviderError?) { self.syncError = syncError }
    func set(tags: [Tag]) { tagList = tags }
    /// Wat `datedTags(in:limit:)` geeft (per repo gefilterd).
    func set(datedTags: [Tag]) { datedTagList = datedTags }
    func set(datedTagError: ProviderError?) { self.datedTagError = datedTagError }
    /// Wat `listRepos()` geeft.
    func set(repos: [String]) { self.repos = repos }
    func set(error: ProviderError?) { self.error = error }
    /// Wat `coAuthors(of:)` geeft, per dedupKey.
    func set(coAuthors: [String: [Person]]) { coAuthorList = coAuthors }
    func set(coAuthorError: ProviderError?) { self.coAuthorError = coAuthorError }
    /// Wat `checks(of:)` geeft, per dedupKey.
    func set(checks: [String: PRChecks]) { checkList = checks }
    func set(userId: String) { self.userId = userId }
    /// Fout die alleen `tags(in:)` gooit.
    func set(tagError: ProviderError?) { self.tagError = tagError }
    func set(fingerprints: [String: String]) { self.fingerprints = fingerprints }
    /// Repo's die `tags(in:)` als onbereikbaar meldt (404/403).
    func set(unavailableTagRepos: [String]) { self.unavailableTagRepos = Set(unavailableTagRepos.map { $0.lowercased() }) }

    func currentUserId() async throws -> String {
        if let error { throw error }
        return userId
    }

    func testConnection() async throws -> String {
        if let error { throw error }
        return userId
    }

    func listRepos() async throws -> [String] {
        if let error { throw error }
        return repos
    }

    func openPullRequests() async throws -> [PullRequest] {
        fetchCount += 1
        if let error { throw error }
        return pullRequests
    }

    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] {
        syncCount += 1
        lastSyncSince = .some(since)
        if let syncError { throw syncError }
        return Array(syncedPullRequests.prefix(limit))
    }

    func tags(in repos: [String]) async throws -> TagFetch {
        tagFetchCount += 1
        if let error { throw error }
        if let tagError { throw tagError }
        let wanted = Set(repos.map { $0.lowercased() }).subtracting(unavailableTagRepos)
        return TagFetch(
            tags: tagList.filter { wanted.contains($0.repo.lowercased()) },
            unavailableRepos: repos.filter { unavailableTagRepos.contains($0.lowercased()) }
        )
    }

    /// Met vingerafdrukken: een repo waarvan de bekende vingerafdruk gelijk is komt zonder tags terug.
    func tags(in repos: [String], unchanged: [String: String]) async throws -> TagFetch {
        lastUnchanged = unchanged
        var fetch = try await tags(in: repos)
        guard !fingerprints.isEmpty else { return fetch }
        let available = repos.filter { !unavailableTagRepos.contains($0.lowercased()) }
        let same = Set(available.filter { unchanged[$0] != nil && unchanged[$0] == fingerprints[$0.lowercased()] }.map { $0.lowercased() })
        fetch.tags.removeAll { same.contains($0.repo.lowercased()) }
        fetch.unchangedRepos = available.filter { same.contains($0.lowercased()) }
        fetch.fingerprints = Dictionary(available.compactMap { repo in fingerprints[repo.lowercased()].map { (repo, $0) } },
                                        uniquingKeysWith: { first, _ in first })
        return fetch
    }

    func datedTags(in repo: String, limit: Int) async throws -> [Tag] {
        datedTagRepos.append(repo)
        if let datedTagError { throw datedTagError }
        return Array(datedTagList.filter { $0.repo.lowercased() == repo.lowercased() }.prefix(limit))
    }

    func coAuthors(of pullRequests: [PullRequest]) async throws -> [String: [Person]] {
        coAuthorRequests.append(pullRequests.map(\.dedupKey))
        if let coAuthorError { throw coAuthorError }
        return coAuthorList.filter { key, _ in pullRequests.contains { $0.dedupKey == key } }
    }

    func checks(of pullRequests: [PullRequest]) async throws -> [String: PRChecks] {
        checkRequests.append(pullRequests.map(\.dedupKey))
        return checkList.filter { key, _ in pullRequests.contains { $0.dedupKey == key } }
    }

    func filePaths(in repo: String, ref: String?) async throws -> [String] { [] }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String { "" }
    func invalidateCredentials() async { invalidateCount += 1 }
}

/// Provider waarvan `openPullRequests` pas terugkeert na `release()`; `started` meldt dat een fetch loopt.
actor GatedProvider: PRProvider {
    private let gate: AsyncStream<Void>
    private let gateContinuation: AsyncStream<Void>.Continuation
    let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private(set) var fetchCount = 0

    init() {
        (gate, gateContinuation) = AsyncStream.makeStream()
        (started, startedContinuation) = AsyncStream.makeStream()
    }

    func release() { gateContinuation.yield() }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] { [] }

    func openPullRequests() async throws -> [PullRequest] {
        fetchCount += 1
        startedContinuation.yield()
        for await _ in gate { break }
        return []
    }

    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch { TagFetch(tags: []) }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { [] }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String { "" }
    func invalidateCredentials() async {}
}

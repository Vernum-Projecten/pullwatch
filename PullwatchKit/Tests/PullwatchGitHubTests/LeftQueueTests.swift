import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

/// Uit de merge queue of auto-merge van GitHub zonder te mergen: twee polls van `PollEngine` met
/// de echte `GitHubProvider`, de reden uit de tijdlijn, en geen melding bij een merge, een draft,
/// een mislukte vraag of een eerste poll.
@Suite struct LeftQueueTests {
    let account = Account.fixture(id: fixedAccountId, kind: .gitHub, organization: "acme")
    let http = MockHTTPClient()
    let clock = TestClock()
    let engine: PollEngine

    init() {
        let provider = GitHubProvider(accountId: fixedAccountId, owner: "acme", tokenSource: StaticTokenSource(token: "t"), http: http)
        let clock = clock
        engine = PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now })
    }

    static func item(number: Int = 1, draft: Bool = false) -> String {
        #"""
        {"number":\#(number),"title":"PR \#(number)","created_at":"2025-10-15T10:00:00Z","updated_at":"2025-10-15T10:00:00Z","draft":\#(draft),
         "user":{"login":"octocat"},"html_url":"https://github.com/acme/web/pull/\#(number)",
         "repository_url":"https://api.github.com/repos/acme/web"}
        """#
    }

    static let inQueue = #"""
        {"data":{"pr0":{"pullRequest":{"state":"OPEN","isDraft":false,"isInMergeQueue":true,"mergeQueueEntry":{"state":"AWAITING_CHECKS","position":1,"enqueuedAt":"2025-10-15T11:00:00Z"},"autoMergeRequest":null}}}}
        """#
    static let autoMerge = #"""
        {"data":{"pr0":{"pullRequest":{"state":"OPEN","isDraft":false,"isInMergeQueue":false,"mergeQueueEntry":null,"autoMergeRequest":{"enabledAt":"2025-10-15T11:00:00Z"}}}}}
        """#
    static let notQueued = #"""
        {"data":{"pr0":{"pullRequest":{"state":"OPEN","isDraft":false,"isInMergeQueue":false,"mergeQueueEntry":null,"autoMergeRequest":null}}}}
        """#
    static let mergedMeanwhile = #"""
        {"data":{"pr0":{"pullRequest":{"state":"MERGED","isDraft":false,"isInMergeQueue":false,"mergeQueueEntry":null,"autoMergeRequest":null}}}}
        """#
    static let rateLimited = #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#

    static func exit(_ reason: String?) -> String {
        let node = reason.map { #"{"reason":"\#($0)"}"# } ?? "null"
        return #"{"data":{"pr0":{"pullRequest":{"state":"OPEN","isInMergeQueue":false,"autoMergeRequest":null,"queueExit":{"nodes":[\#(node)]}}}}}"#
    }

    /// De antwoorden van één poll: de open PR's, de vraag naar de rij en de tijdlijn.
    func serve(open: [String], queue: String, exit: String = Self.exit(nil)) {
        http.removeAllRoutes()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("github.com/user", body: #"{"login":"me"}"#)
        http.on("search/issues", body: #"{"total_count":\#(open.count),"items":[\#(open.joined(separator: ","))]}"#)
        http.on("graphql", bodyContains: "queueExit: timelineItems", body: exit)
        http.on("graphql", bodyContains: "isInMergeQueue mergeQueueEntry", body: queue)
        // Co-auteurs en checks: geen antwoord per PR.
        http.on("graphql", body: #"{"data":{}}"#)
    }

    func poll() async -> PollResult {
        clock.advance(120)
        return await engine.poll(accounts: [account], interval: 120, retention: .oneYear, fetchChecks: false)
    }

    func exitQueries() -> [String] {
        http.requests.compactMap { $0.httpBody.map { String(decoding: $0, as: UTF8.self) } }.filter { $0.contains("queueExit:") }
    }

    @Test func `Leaving the merge queue gives one notification with the reason`() async throws {
        serve(open: [Self.item()], queue: Self.inQueue)
        let first = await poll()
        serve(open: [Self.item()], queue: Self.notQueued, exit: Self.exit("The merge commit failed its checks"))

        let result = await poll()

        #expect(first.leftQueue.isEmpty)
        let left = try #require(result.leftQueue.first)
        #expect(result.leftQueue.count == 1)
        #expect(left.number == 1)
        #expect(left.leftQueue?.kind == .mergeQueue)
        #expect(left.leftQueue?.reason == "The merge commit failed its checks")
        #expect(exitQueries().count == 1)
        #expect(exitQueries().first?.contains("REMOVED_FROM_MERGE_QUEUE_EVENT") == true)
    }

    @Test func `Auto-merge shows as queued, and turning off gives the reason of GitHub`() async throws {
        serve(open: [Self.item()], queue: Self.autoMerge)
        let first = await poll()
        serve(open: [Self.item()], queue: Self.notQueued, exit: Self.exit("Base branch was changed"))

        let result = await poll()

        #expect(first.mergeQueues.values.compactMap { $0?.kind } == [.autoMerge])
        let left = try #require(result.leftQueue.first)
        #expect(left.leftQueue?.kind == .autoMerge)
        #expect(left.leftQueue?.reason == "Base branch was changed")
        #expect(exitQueries().first?.contains("AUTO_MERGE_DISABLED_EVENT") == true)
    }

    @Test func `Without a reason in the timeline the notification still comes`() async {
        serve(open: [Self.item()], queue: Self.inQueue)
        _ = await poll()
        serve(open: [Self.item()], queue: Self.notQueued, exit: Self.exit(nil))

        let result = await poll()

        #expect(result.leftQueue.count == 1)
        #expect(result.leftQueue.first?.leftQueue?.reason == nil)
    }

    @Test func `Queued, then merged, gives none`() async {
        serve(open: [Self.item()], queue: Self.inQueue)
        _ = await poll()
        serve(open: [], queue: Self.notQueued)

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
        #expect(exitQueries().isEmpty)
    }

    @Test func `Merged while search still lists it open gives none`() async {
        serve(open: [Self.item()], queue: Self.inQueue)
        _ = await poll()
        serve(open: [Self.item()], queue: Self.mergedMeanwhile)

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `Queued, then draft, gives none`() async {
        serve(open: [Self.item()], queue: Self.inQueue)
        _ = await poll()
        serve(open: [Self.item(draft: true)], queue: Self.notQueued)

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `A failed read of the queue gives none and keeps the old state`() async {
        serve(open: [Self.item()], queue: Self.inQueue)
        _ = await poll()
        serve(open: [Self.item()], queue: Self.rateLimited)
        let failed = await poll()
        serve(open: [Self.item()], queue: Self.notQueued)

        let read = await poll()

        #expect(failed.leftQueue.isEmpty)
        #expect(read.leftQueue.count == 1)
    }

    @Test func `The first poll gives none`() async {
        serve(open: [Self.item()], queue: Self.notQueued)

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }
}

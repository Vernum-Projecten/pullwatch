import Foundation
import Testing
@testable import PullwatchBitbucket
@testable import PullwatchCore
import PullwatchTestSupport

/// Uit de merge queue van Bitbucket Cloud (`queued`) zonder te mergen: twee polls van `PollEngine`
/// met de echte `BitbucketProvider`. Bitbucket geeft geen reden; de melding komt zonder.
@Suite struct LeftQueueTests {
    let api = "https://api.bitbucket.org/2.0/"
    let account = Account.fixture(id: fixedAccountId, kind: .bitbucket, organization: "atlassian")
    let http = MockHTTPClient()
    let clock = TestClock()
    let engine: PollEngine

    init() {
        let clock = clock
        let provider = BitbucketProvider(
            accountId: fixedAccountId, workspaces: ["atlassian"], email: "jane@example.com", extraRepos: [],
            tokenSource: StaticTokenSource(token: "ATATT3xFfGF0-secret"), http: http, now: { clock.now }
        )
        engine = PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now })
    }

    /// De antwoorden van één poll; `updated` van de repo verandert per poll, zodat de provider de
    /// open pull requests opnieuw vraagt.
    func serve(_ pullRequests: [String], updated: String) {
        http.removeAllRoutes()
        http.on("\(api)repositories/atlassian?", body: BitbucketFixtures.repositories([("atlassian/atlassian-event", updated)]))
        http.on("pullrequests?state=OPEN", body: BitbucketFixtures.page(pullRequests))
        http.on("pullrequests", body: BitbucketFixtures.page([]))
        http.on("\(api)user", body: BitbucketFixtures.user)
    }

    func poll() async -> PollResult {
        clock.advance(120)
        return await engine.poll(accounts: [account], interval: 120, retention: .oneYear, fetchChecks: false)
    }

    @Test func `Leaving the merge queue gives one notification without a reason`() async throws {
        serve([BitbucketFixtures.pullRequest(1, queued: true)], updated: "2026-11-04T11:00:00+00:00")
        let first = await poll()
        serve([BitbucketFixtures.pullRequest(1, queued: false)], updated: "2026-11-04T12:00:00+00:00")

        let result = await poll()

        #expect(first.leftQueue.isEmpty)
        let left = try #require(result.leftQueue.first)
        #expect(result.leftQueue.count == 1)
        #expect(left.number == 1)
        #expect(left.leftQueue?.kind == .mergeQueue)
        #expect(left.leftQueue?.reason == nil)
    }

    @Test func `Queued, then merged, gives none`() async {
        serve([BitbucketFixtures.pullRequest(1, queued: true)], updated: "2026-11-04T11:00:00+00:00")
        _ = await poll()
        serve([], updated: "2026-11-04T12:00:00+00:00")

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `Queued, then draft, gives none`() async {
        serve([BitbucketFixtures.pullRequest(1, queued: true)], updated: "2026-11-04T11:00:00+00:00")
        _ = await poll()
        serve([BitbucketFixtures.pullRequest(1, draft: true)], updated: "2026-11-04T12:00:00+00:00")

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `A failed poll gives none and keeps the old state`() async {
        serve([BitbucketFixtures.pullRequest(1, queued: true)], updated: "2026-11-04T11:00:00+00:00")
        _ = await poll()
        http.removeAllRoutes()
        let failed = await poll()
        serve([BitbucketFixtures.pullRequest(1, queued: false)], updated: "2026-11-04T12:00:00+00:00")
        clock.advance(3600)

        let read = await poll()

        #expect(failed.leftQueue.isEmpty)
        #expect(read.leftQueue.count == 1)
    }

    @Test func `The first poll gives none`() async {
        serve([BitbucketFixtures.pullRequest(1)], updated: "2026-11-04T11:00:00+00:00")

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }
}

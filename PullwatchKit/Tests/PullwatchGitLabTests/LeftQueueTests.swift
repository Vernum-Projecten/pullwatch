import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitLab
import PullwatchTestSupport

/// Uit de merge train of auto-merge van GitLab zonder te mergen: twee polls van `PollEngine` met
/// de echte `GitLabProvider`. GitLab geeft de reden alleen als vrije tekst in een systeemnotitie;
/// die leest Pullwatch niet, dus de melding komt zonder reden.
@Suite struct LeftQueueTests {
    let api = "https://gitlab.com/api/v4/"
    let account = Account.fixture(id: fixedAccountId, kind: .gitLab, organization: "acme")
    let http = MockHTTPClient()
    let clock = TestClock()
    let engine: PollEngine

    init() {
        let clock = clock
        let provider = GitLabProvider(
            accountId: fixedAccountId, owners: ["acme"], tokenSource: StaticTokenSource(token: "glpat-secret"), http: http,
            now: { clock.now }
        )
        engine = PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now })
    }

    /// De antwoorden van één poll: de open merge requests en de merge trains.
    func serve(_ mergeRequests: [String], trains: String = "[]", trainStatus: Int = 200) {
        http.removeAllRoutes()
        http.on("\(api)groups/acme?", body: GitLabFixtures.group)
        http.on("groups/acme/merge_requests", body: "[" + mergeRequests.joined(separator: ",") + "]")
        http.on("merge_trains", status: trainStatus, body: trains)
        http.on("\(api)user", body: GitLabFixtures.user)
    }

    func poll() async -> PollResult {
        clock.advance(120)
        return await engine.poll(accounts: [account], interval: 120, retention: .oneYear, fetchChecks: false)
    }

    static let car = #"[{"id":5,"target_branch":"main","status":"fresh","created_at":"2025-10-15T11:00:00.000Z","merge_request":{"iid":12}}]"#

    @Test func `Leaving auto-merge gives one notification without a reason`() async throws {
        serve([GitLabFixtures.mergeRequest(iid: 12, autoMerge: true)], trains: #"{"message":"404 Not found"}"#, trainStatus: 404)
        let first = await poll()
        serve([GitLabFixtures.mergeRequest(iid: 12)])

        let result = await poll()

        #expect(first.leftQueue.isEmpty)
        let left = try #require(result.leftQueue.first)
        #expect(result.leftQueue.count == 1)
        #expect(left.number == 12)
        #expect(left.leftQueue?.kind == .autoMerge)
        #expect(left.leftQueue?.reason == nil)
    }

    @Test func `Leaving the merge train gives one notification`() async throws {
        serve([GitLabFixtures.mergeRequest(iid: 12, autoMerge: true)], trains: Self.car)
        _ = await poll()
        serve([GitLabFixtures.mergeRequest(iid: 12)])

        let result = await poll()

        #expect(result.leftQueue.map(\.leftQueue?.kind) == [.mergeTrain])
    }

    @Test func `Queued, then merged, gives none`() async {
        serve([GitLabFixtures.mergeRequest(iid: 12, autoMerge: true)], trains: Self.car)
        _ = await poll()
        serve([])

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `Queued, then draft, gives none`() async {
        serve([GitLabFixtures.mergeRequest(iid: 12, autoMerge: true)], trains: Self.car)
        _ = await poll()
        serve([GitLabFixtures.mergeRequest(iid: 12, draft: true)])

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `A failed read of the merge train gives none`() async {
        serve([GitLabFixtures.mergeRequest(iid: 12, autoMerge: true)], trains: Self.car)
        _ = await poll()
        // De train is even niet te lezen: de merge request houdt auto-merge en blijft in de rij.
        serve([GitLabFixtures.mergeRequest(iid: 12, autoMerge: true)], trains: #"{"message":"500"}"#, trainStatus: 500)

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `The first poll gives none`() async {
        serve([GitLabFixtures.mergeRequest(iid: 12)])

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }
}

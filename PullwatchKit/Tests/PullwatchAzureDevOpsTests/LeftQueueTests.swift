import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

/// Auto-complete van Azure DevOps uitgezet zonder te voltooien: twee polls van `PollEngine` met de
/// echte `AzureDevOpsProvider`. Azure DevOps geeft geen reden; de melding komt zonder.
@Suite struct LeftQueueTests {
    let account = Account.fixture(id: fixedAccountId, kind: .azureDevOps, organization: "acme")
    let http = MockHTTPClient()
    let clock = TestClock()
    let engine: PollEngine

    init() {
        let clock = clock
        let provider = AzureDevOpsProvider(
            accountId: fixedAccountId, organization: "acme",
            tokenSource: StaticTokenSource(token: "secret"), authMethod: .pat, http: http, now: { clock.now }
        )
        engine = PollEngine(makeProvider: { _ in provider }, store: nil, now: { clock.now })
    }

    static func pr(autoComplete: Bool = false, draft: Bool = false) -> String {
        let setBy = autoComplete ? #","autoCompleteSetBy":{"id":"other-guid","displayName":"Piet Pieters"}"# : ""
        return #"""
            {"pullRequestId":18,"title":"PR 18","creationDate":"2025-10-15T10:00:00Z","status":"active","isDraft":\#(draft)\#(setBy),
             "createdBy":{"id":"user-guid","displayName":"Jan Jansen"},
             "repository":{"name":"api","project":{"name":"My Project"}}}
            """#
    }

    /// De antwoorden van één poll: de actieve pull requests.
    func serve(_ pullRequests: [String]) {
        http.removeAllRoutes()
        http.on("connectionData", body: #"{"authenticatedUser":{"id":"me-guid"}}"#)
        http.on("_apis/projects", body: #"{"count":1,"value":[{"name":"My Project"}]}"#)
        http.on("_apis/git/pullrequests", body: #"{"value":[\#(pullRequests.joined(separator: ","))]}"#)
    }

    func poll() async -> PollResult {
        clock.advance(120)
        return await engine.poll(accounts: [account], interval: 120, retention: .oneYear, fetchChecks: false)
    }

    @Test func `Turning auto-complete off gives one notification without a reason`() async throws {
        serve([Self.pr(autoComplete: true)])
        let first = await poll()
        serve([Self.pr()])

        let result = await poll()

        #expect(first.leftQueue.isEmpty)
        let left = try #require(result.leftQueue.first)
        #expect(result.leftQueue.count == 1)
        #expect(left.number == 18)
        #expect(left.leftQueue?.kind == .autoComplete)
        #expect(left.leftQueue?.reason == nil)
    }

    @Test func `Auto-complete, then completed, gives none`() async {
        serve([Self.pr(autoComplete: true)])
        _ = await poll()
        serve([])

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `Auto-complete, then draft, gives none`() async {
        serve([Self.pr(autoComplete: true)])
        _ = await poll()
        serve([Self.pr(draft: true)])

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }

    @Test func `A failed poll gives none and keeps the old state`() async {
        serve([Self.pr(autoComplete: true)])
        _ = await poll()
        http.removeAllRoutes()
        let failed = await poll()
        serve([Self.pr()])
        clock.advance(3600)

        let read = await poll()

        #expect(failed.leftQueue.isEmpty)
        #expect(read.leftQueue.count == 1)
    }

    @Test func `The first poll gives none`() async {
        serve([Self.pr()])

        let result = await poll()

        #expect(result.leftQueue.isEmpty)
    }
}

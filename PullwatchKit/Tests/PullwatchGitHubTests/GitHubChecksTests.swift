import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport
import Synchronization

@Suite struct GitHubChecksTests {
    let http = MockHTTPClient()

    var provider: GitHubProvider { makeProvider(http) }

    func pr(_ number: Int, repo: String = "acme/web") -> PullRequest {
        .fixture(repo: repo, number: number, authorId: "octocat", authorName: "octocat")
    }

    func rollup(runs: [(String, Int)], statuses: [(String, Int)] = []) -> String {
        let runs = runs.map { #"{"state":"\#($0.0)","count":\#($0.1)}"# }.joined(separator: ",")
        let statuses = statuses.map { #"{"state":"\#($0.0)","count":\#($0.1)}"# }.joined(separator: ",")
        return #"{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"checkRunCountsByState":[\#(runs)],"statusContextCountsByState":[\#(statuses)]}}}}]}"#
    }

    func body(_ request: URLRequest?) throws -> String {
        try #require(request?.httpBody.flatMap { String(data: $0, encoding: .utf8) })
    }

    @Test func `Counts per state come from the rollup of the last commit`() async throws {
        http.on("api.github.com/graphql", body: #"""
        {"data":{
          "pr0":{"pullRequest":{"headCommit":\#(rollup(runs: [("SUCCESS", 5), ("SKIPPED", 1), ("NEUTRAL", 1), ("FAILURE", 1)], statuses: [("SUCCESS", 1), ("PENDING", 1)]))}},
          "pr1":{"pullRequest":{"headCommit":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}},
          "pr2":{"pullRequest":null}
        }}
        """#)
        let red = pr(1), none = pr(2), gone = pr(3, repo: "acme/gone")

        let checks = try await provider.checks(of: [red, none, gone])

        #expect(checks[red.dedupKey] == .counts(CheckCounts(passed: 6, skipped: 2, failed: 1, pending: 1)))
        #expect(checks[none.dedupKey] == .counts(CheckCounts()))
        #expect(checks[gone.dedupKey] == nil)
        let query = try body(http.requests.first)
        // Alleen de telling: geen namen, links of tijden van de checks.
        #expect(query.contains("checkRunCountsByState") && query.contains("statusContextCountsByState"))
        #expect(!query.contains("detailsUrl") && !query.contains("startedAt"))
        #expect(!query.contains("authors(first"))
    }

    @Test(arguments: [
        ("SUCCESS", CheckOutcome.passed), ("COMPLETED", .passed), ("NEUTRAL", .skipped), ("SKIPPED", .skipped),
        ("FAILURE", .failed), ("TIMED_OUT", .failed), ("ACTION_REQUIRED", .failed), ("CANCELLED", .failed),
        ("STARTUP_FAILURE", .failed), ("QUEUED", .pending), ("IN_PROGRESS", .pending), ("WAITING", .pending),
    ])
    func `Check run states map like GitHub's list`(_ state: String, _ outcome: CheckOutcome) {
        #expect(GitHubCheckState.checkRun(state) == outcome)
    }

    @Test(arguments: [("SUCCESS", CheckOutcome.passed), ("ERROR", .failed), ("FAILURE", .failed), ("PENDING", .pending), ("EXPECTED", .pending)])
    func `Commit status states map too`(_ state: String, _ outcome: CheckOutcome) {
        #expect(GitHubCheckState.statusContext(state) == outcome)
    }

    @Test func `Co-authors and checks share one request`() async throws {
        http.on("api.github.com/graphql", body: #"""
        {"data":{"pr0":{"pullRequest":{
          "commits":{"nodes":[{"commit":{"authors":{"nodes":[{"name":"Mona","email":"mona@example.com","user":{"login":"mona","avatarUrl":null}}]}}}]},
          "headCommit":\#(rollup(runs: [("SUCCESS", 8)]))}}}}
        """#)
        let both = pr(1)

        let details = try await provider.details(of: [both], coAuthorsOf: [both.dedupKey], checksOf: [both.dedupKey])

        #expect(http.requests.count == 1)
        #expect(details.coAuthors[both.dedupKey]?.map(\.handle) == ["mona"])
        #expect(details.checks[both.dedupKey] == .counts(CheckCounts(passed: 8)))
        let query = try body(http.requests.first)
        #expect(query.contains("commits(last: 50)") && query.contains("headCommit: commits(last: 1)"))
    }

    @Test func `Only what each pull request needs is asked`() async throws {
        http.on("api.github.com/graphql", body: #"{"data":{}}"#)
        let onlyAuthors = pr(1), onlyChecks = pr(2)

        _ = try await provider.details(of: [onlyAuthors, onlyChecks], coAuthorsOf: [onlyAuthors.dedupKey], checksOf: [onlyChecks.dedupKey])

        let query = try body(http.requests.first)
        let first = try #require(query.range(of: "pr1:"))
        #expect(query[..<first.lowerBound].contains("commits(last: 50)"))
        #expect(!query[..<first.lowerBound].contains("headCommit"))
        #expect(query[first.lowerBound...].contains("headCommit"))
        #expect(!query[first.lowerBound...].contains("commits(last: 50)"))
    }

    @Test func `A refused rollup needs permission and keeps the co-authors`() async throws {
        http.on("api.github.com/graphql", body: #"""
        {"data":{"pr0":{"pullRequest":{
          "commits":{"nodes":[{"commit":{"authors":{"nodes":[{"name":"Mona","email":"mona@example.com","user":{"login":"mona","avatarUrl":null}}]}}}]},
          "headCommit":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}}},
         "errors":[{"type":"FORBIDDEN","path":["pr0","pullRequest","headCommit","nodes",0,"commit","statusCheckRollup"],
                    "message":"Resource not accessible by integration"}]}
        """#)
        let pull = pr(1)

        let details = try await provider.details(of: [pull], coAuthorsOf: [pull.dedupKey], checksOf: [pull.dedupKey])

        #expect(details.checks[pull.dedupKey] == .needsPermission)
        #expect(details.coAuthors[pull.dedupKey]?.map(\.handle) == ["mona"])
    }

    @Test func `A request refused as a whole is asked again without the checks`() async throws {
        http.onSequence("api.github.com/graphql", bodies: [
            #"{"data":{"pr0":{"pullRequest":{"commits":{"nodes":[]}}}}}"#,
        ])
        let refusing = MockHTTPClient()
        refusing.on("api.github.com/graphql", status: 403, body: #"{"message":"Resource not accessible by integration"}"#)
        let provider = GitHubProvider(accountId: fixedAccountId, owner: "acme", tokenSource: StaticTokenSource(token: "t"), http: SwitchingClient(first: refusing, then: http))
        let pull = pr(1)

        let details = try await provider.details(of: [pull], coAuthorsOf: [pull.dedupKey], checksOf: [pull.dedupKey])

        #expect(details.checks[pull.dedupKey] == .needsPermission)
        #expect(details.coAuthors[pull.dedupKey] == [])
        #expect(!(try body(http.requests.first)).contains("headCommit"))
    }

    @Test func `A server without the count fields stops asking for checks`() async throws {
        http.onSequence("api.github.com/graphql", bodies: [
            #"{"errors":[{"message":"Field 'checkRunCountsByState' doesn't exist on type 'StatusCheckRollupContextConnection'","extensions":{"code":"undefinedField"}}]}"#,
            #"{"data":{"pr0":{"pullRequest":{"commits":{"nodes":[]}}}}}"#,
        ])
        let provider = provider
        let pull = pr(1)

        let first = try await provider.details(of: [pull], coAuthorsOf: [pull.dedupKey], checksOf: [pull.dedupKey])
        _ = try await provider.checks(of: [pull])

        #expect(first.checks[pull.dedupKey] == .counts(CheckCounts()))
        #expect(http.requests.count == 2)
        #expect(!(try body(http.requests.last)).contains("headCommit"))
    }
}

/// Het eerste verzoek naar `first`, de rest naar `then`.
private final class SwitchingClient: HTTPClient, Sendable {
    private let first: MockHTTPClient
    private let then: MockHTTPClient
    private let used = Mutex(false)

    init(first: MockHTTPClient, then: MockHTTPClient) {
        self.first = first
        self.then = then
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let isFirst = used.withLock { used in
            defer { used = true }
            return !used
        }
        return try await (isFirst ? first : then).send(request)
    }
}

import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitLab
import PullwatchTestSupport

@Suite struct GitLabChecksTests {
    let http = MockHTTPClient()
    let api = "https://gitlab.com/api/v4/"

    var provider: GitLabProvider {
        GitLabProvider(
            accountId: fixedAccountId, owners: ["acme"],
            tokenSource: StaticTokenSource(token: "glpat-secret"), http: http
        )
    }

    let pr = PullRequest.fixture(repo: "acme/platform/api", number: 12)

    @Test func `The jobs of the head pipeline are counted`() async throws {
        http.on("\(api)projects/acme%2Fplatform%2Fapi/merge_requests/12", body: #"{"iid":12,"head_pipeline":{"id":900,"status":"running"}}"#)
        http.on("\(api)projects/acme%2Fplatform%2Fapi/pipelines/900/jobs", body: #"""
        [{"status":"success"},{"status":"success"},{"status":"skipped"},{"status":"manual"},
         {"status":"failed","allow_failure":true},{"status":"failed","allow_failure":false},
         {"status":"running"},{"status":"pending"}]
        """#)

        let checks = try await provider.checks(of: [pr])

        #expect(checks[pr.dedupKey] == .counts(CheckCounts(passed: 3, skipped: 2, failed: 1, pending: 2)))
        #expect(http.requests.count == 2)
    }

    @Test func `Without a pipeline there are no checks and no second request`() async throws {
        http.on("\(api)projects/acme%2Fplatform%2Fapi/merge_requests/12", body: #"{"iid":12,"head_pipeline":null}"#)

        let checks = try await provider.checks(of: [pr])

        #expect(checks[pr.dedupKey] == .counts(CheckCounts()))
        #expect(http.requests.count == 1)
    }

    @Test func `A refused pipeline needs permission, a missing request is left out`() async throws {
        let gone = PullRequest.fixture(repo: "acme/gone", number: 1)
        http.on("\(api)projects/acme%2Fplatform%2Fapi/merge_requests/12", status: 403, body: #"{"message":"403 Forbidden"}"#)
        http.on("\(api)projects/acme%2Fgone/merge_requests/1", status: 404, body: #"{"message":"404 Not found"}"#)

        let checks = try await provider.checks(of: [pr, gone])

        #expect(checks == [pr.dedupKey: .needsPermission])
    }

    @Test(arguments: [
        ("success", false, CheckOutcome?.some(.passed)), ("failed", false, .failed), ("failed", true, .passed),
        ("canceled", false, .failed), ("manual", false, .skipped), ("created", false, .pending),
        ("waiting_for_resource", false, .pending), ("unknown", false, nil),
    ])
    func `Job states map to the count`(_ status: String, _ allowFailure: Bool, _ outcome: CheckOutcome?) {
        #expect(GitLabProvider.outcome(of: status, allowFailure: allowFailure) == outcome)
    }
}

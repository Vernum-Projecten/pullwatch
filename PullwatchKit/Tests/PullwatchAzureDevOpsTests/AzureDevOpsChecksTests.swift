import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct AzureDevOpsChecksTests {
    let http = MockHTTPClient()
    let projects = #"{"count":1,"value":[{"name":"My Project"}]}"#
    let pullRequest = #"""
    {"value":[{"pullRequestId":17,"title":"PR 17","creationDate":"2025-10-15T10:00:00Z",
     "createdBy":{"id":"user-guid","displayName":"Jan Jansen"},
     "lastMergeSourceCommit":{"commitId":"abc123"},
     "repository":{"name":"api","project":{"name":"My Project","id":"project-guid"}}}]}
    """#

    var provider: AzureDevOpsProvider {
        AzureDevOpsProvider(
            accountId: fixedAccountId, organization: "acme",
            tokenSource: StaticTokenSource(token: "secret"), authMethod: .pat, http: http
        )
    }

    let build = "0609b952-1397-4640-95ec-e00a01b2c241"

    @Test func `Newest status per context and the build policies count`() async throws {
        http.on("_apis/projects", body: projects)
        http.on("_apis/git/pullrequests?", body: pullRequest)
        http.on("pullRequests/17/statuses", body: #"""
        {"value":[
          {"id":1,"iterationId":1,"state":"failed","context":{"genre":"ci","name":"lint"}},
          {"id":2,"iterationId":2,"state":"succeeded","context":{"genre":"ci","name":"lint"}},
          {"id":3,"iterationId":2,"state":"pending","context":{"genre":"ci","name":"deploy"}},
          {"id":4,"iterationId":2,"state":"notSet","context":{"genre":"ci","name":"other"}}
        ]}
        """#)
        http.on("_apis/policy/evaluations", body: #"""
        {"value":[
          {"status":"rejected","configuration":{"isEnabled":true,"type":{"id":"\#(build)"}}},
          {"status":"approved","configuration":{"isEnabled":true,"type":{"id":"\#(build)"}}},
          {"status":"approved","configuration":{"isEnabled":true,"type":{"id":"fa4e907d-c16b-4a4c-9dfa-4906e5d171dd"}}}
        ]}
        """#)
        let provider = provider
        let pr = try #require(try await provider.openPullRequests().first)

        let checks = try await provider.checks(of: [pr])

        #expect(checks[pr.dedupKey] == .counts(CheckCounts(passed: 2, failed: 1, pending: 1)))
        let evaluation = try #require(http.requests.last?.url?.absoluteString)
        #expect(evaluation.contains("artifactId=vstfs:///CodeReview/CodeReviewId/project-guid/17"))
    }

    @Test func `A token without access to the statuses needs permission`() async throws {
        http.on("_apis/projects", body: projects)
        http.on("_apis/git/pullrequests?", body: pullRequest)
        http.on("pullRequests/17/statuses", status: 401, body: "")
        let provider = provider
        let pr = try #require(try await provider.openPullRequests().first)

        #expect(try await provider.checks(of: [pr]) == [pr.dedupKey: .needsPermission])
    }

    @Test func `Without access to the policies only the statuses count`() async throws {
        http.on("_apis/projects", body: projects)
        http.on("_apis/git/pullrequests?", body: pullRequest)
        http.on("pullRequests/17/statuses", body: #"{"value":[{"id":1,"state":"succeeded","context":{"genre":"ci","name":"build"}}]}"#)
        http.on("_apis/policy/evaluations", status: 403, body: "")
        let provider = provider
        let pr = try #require(try await provider.openPullRequests().first)

        #expect(try await provider.checks(of: [pr]) == [pr.dedupKey: .counts(CheckCounts(passed: 1))])
    }
}

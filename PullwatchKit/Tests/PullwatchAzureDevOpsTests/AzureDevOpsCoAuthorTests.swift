import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct AzureDevOpsCoAuthorTests {
    let projects = #"{"count":1,"value":[{"name":"My Project"}]}"#
    let pullRequest = #"""
    {"value":[{"pullRequestId":17,"title":"PR 17","creationDate":"2025-10-15T10:00:00Z",
     "createdBy":{"id":"user-guid","displayName":"Jan Jansen","uniqueName":"jan@acme.example"},
     "lastMergeSourceCommit":{"commitId":"abc123"},
     "repository":{"name":"api","project":{"name":"My Project"}}}]}
    """#

    @Test func lastSourceCommitIsTheRevision() async throws {
        let http = MockHTTPClient()
        http.on("_apis/projects", body: projects)
        http.on("_apis/git/pullrequests", body: pullRequest)

        #expect(try await makeProvider(http).openPullRequests().first?.revision == "abc123")
    }

    @Test func commitAuthorsAndTrailersWithoutTheAuthor() async throws {
        let http = MockHTTPClient()
        http.on("_apis/projects", body: projects)
        http.on("_apis/git/pullrequests?", body: pullRequest)
        http.on("pullRequests/17/commits", body: #"""
        {"value":[
          {"commitId":"c1","author":{"name":"jjansen","email":"jan@acme.example"},
           "comment":"Add login\n\nCo-authored-by: Piet Pieters <piet@acme.example>\nco-authored-by: Build Bot[bot] <bot@acme.example>"},
          {"commitId":"c2","author":{"name":"Piet","email":"PIET@acme.example"},"comment":"Fix tests"},
          {"commitId":"c3","author":{"name":"Jan Jansen","email":"jan@home.example"},"comment":"Long message","commentTruncated":true}
        ]}
        """#)
        http.on("commits/c3", body: #"""
        {"commitId":"c3","author":{"name":"Jan Jansen","email":"jan@home.example"},
         "comment":"Long message that goes on\n\nCo-Authored-By: Kees <kees@acme.example>"}
        """#)
        let provider = makeProvider(http)
        let pr = try #require(try await provider.openPullRequests().first)

        let result = try await provider.coAuthors(of: [pr])

        #expect(result[pr.dedupKey] == [
            Person(name: "Piet Pieters", email: "piet@acme.example"),
            Person(name: "Kees", email: "kees@acme.example"),
        ])
        let urls = http.requests.compactMap(\.url?.absoluteString)
        #expect(urls.contains { $0.contains("My%20Project/_apis/git/repositories/api/pullRequests/17/commits") })
        #expect(urls.filter { $0.contains("/commits/") }.count == 1, "alleen het afgekapte bericht los")
    }

    @Test func missingPullRequestHasNoCoAuthors() async throws {
        let http = MockHTTPClient()
        http.on("pullRequests/9/commits", status: 404, body: "{}")
        let pr = PullRequest.fixture(repo: "My Project/api", number: 9)

        #expect(try await makeProvider(http).coAuthors(of: [pr])[pr.dedupKey] == [])
    }
}

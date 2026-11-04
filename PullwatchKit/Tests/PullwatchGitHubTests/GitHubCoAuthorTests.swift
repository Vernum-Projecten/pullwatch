import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

@Suite struct GitHubCoAuthorTests {
    func pr(_ number: Int, repo: String = "acme/web", author: String = "octocat") -> PullRequest {
        .fixture(repo: repo, number: number, authorId: author, authorName: author)
    }

    func author(_ name: String, email: String, login: String? = nil) -> String {
        let user = login.map { #"{"login":"\#($0)","avatarUrl":"https://avatars.githubusercontent.com/u/\#($0)"}"# } ?? "null"
        return #"{"name":"\#(name)","email":"\#(email)","user":\#(user)}"#
    }

    @Test func searchUpdateDateIsTheRevision() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("search/issues", body: #"""
        {"total_count":1,"items":[{"number":1,"title":"PR","created_at":"2025-10-15T10:00:00Z","updated_at":"2025-10-16T08:00:00Z",
         "user":{"login":"octocat"},"html_url":"https://github.com/acme/web/pull/1","repository_url":"https://api.github.com/repos/acme/web"}]}
        """#)

        let prs = try await makeProvider(http).openPullRequests()

        #expect(prs.first?.revision == "2025-10-16T08:00:00Z")
    }

    @Test func commitAuthorsBecomeCoAuthorsWithoutTheAuthorOrBots() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: #"""
        {"data":{
          "pr0":{"pullRequest":{"commits":{"nodes":[
            {"commit":{"authors":{"nodes":[\#(author("The Octocat", email: "octo@example.com", login: "octocat")), \#(author("Mona Lisa", email: "mona@example.com", login: "mona"))]}}},
            {"commit":{"authors":{"nodes":[\#(author("Mona", email: "MONA@example.com")), \#(author("Jan", email: "jan@example.com")), \#(author("dependabot[bot]", email: "1+dependabot[bot]@users.noreply.github.com"))]}}}
          ]}}},
          "pr1":{"pullRequest":null}
        },"errors":[{"type":"NOT_FOUND"}]}
        """#)
        let first = pr(1)
        let gone = pr(2, repo: "acme/gone")

        let result = try await makeProvider(http).coAuthors(of: [first, gone])

        #expect(result[first.dedupKey] == [
            Person(name: "Mona Lisa", login: "mona", email: "mona@example.com",
                   avatarURL: URL(string: "https://avatars.githubusercontent.com/u/mona")),
            Person(name: "Jan", email: "jan@example.com"),
        ])
        #expect(result[gone.dedupKey] == [])
        #expect(http.requests.count == 1)
        let body = try #require(http.requests.first?.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("pr1: repository(owner: $o1, name: $n1)"))
        #expect(body.contains(#""n1":"gone""#) && body.contains(#""p0":1"#))
    }

    @Test func severalPullRequestsShareOneRequestPerBatch() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: #"{"data":{}}"#)
        let prs = (1...(GitHubProvider.coAuthorBatch + 1)).map { pr($0) }

        let result = try await makeProvider(http).coAuthors(of: prs)

        #expect(http.requests.count == 2)
        #expect(result.count == prs.count)
        #expect(result.values.allSatisfy { $0.isEmpty })
    }

    @Test func failedQueryThrowsSoItIsTriedAgain() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#)

        await #expect(throws: ProviderError.self) {
            try await makeProvider(http).coAuthors(of: [pr(1)])
        }
    }

    @Test func `An answer without data says so in the chosen language`() async {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: "{}")
        let expected = String(localized: "GraphQL-antwoord zonder co-auteurs en checks", bundle: .localizedGitHub)

        await #expect(throws: ProviderError.decoding(expected)) {
            try await makeProvider(http).coAuthors(of: [pr(1)])
        }
    }

    @Test func noPullRequestsNoRequest() async throws {
        let http = MockHTTPClient()
        #expect(try await makeProvider(http).coAuthors(of: []).isEmpty)
        #expect(http.requests.isEmpty)
    }
}

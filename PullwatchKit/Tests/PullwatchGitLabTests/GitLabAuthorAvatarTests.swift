import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitLab
import PullwatchTestSupport

/// De foto van de auteur van een merge request komt uit `author.avatar_url`; op een eigen server
/// kan dat een pad zijn.
@Suite struct GitLabAuthorAvatarTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let instance: String
        let raw: String?
        let expected: String?
        var testDescription: String { "\(instance) \(raw ?? "nil")" }
    }

    static let cases = [
        Case(instance: "https://gitlab.com", raw: "https://gitlab.com/uploads/-/system/user/avatar/5/avatar.png",
             expected: "https://gitlab.com/uploads/-/system/user/avatar/5/avatar.png"),
        Case(instance: "https://gitlab.com", raw: "https://secure.gravatar.com/avatar/abc?s=80&d=identicon",
             expected: "https://secure.gravatar.com/avatar/abc?s=80&d=identicon"),
        Case(instance: "https://git.example.com", raw: "/uploads/-/system/user/avatar/1/avatar.png",
             expected: "https://git.example.com/uploads/-/system/user/avatar/1/avatar.png"),
        Case(instance: "https://git.example.com/gitlab", raw: "/uploads/-/system/user/avatar/1/avatar.png",
             expected: "https://git.example.com/gitlab/uploads/-/system/user/avatar/1/avatar.png"),
        Case(instance: "https://git.example.com/gitlab", raw: "/gitlab/uploads/-/system/user/avatar/1/avatar.png",
             expected: "https://git.example.com/gitlab/uploads/-/system/user/avatar/1/avatar.png"),
        Case(instance: "https://git.example.com", raw: nil, expected: nil),
        Case(instance: "https://git.example.com", raw: "", expected: nil),
    ]

    @Test(arguments: cases)
    func `An absolute avatar URL stays and a relative one resolves against the server`(_ c: Case) throws {
        let instance = try #require(URL(string: c.instance))
        #expect(GitLabProvider.avatarURL(c.raw, instanceURL: instance) == c.expected.flatMap(URL.init(string:)))
    }

    @Test func `A merge request carries the avatar URL of its author`() async throws {
        let http = MockHTTPClient()
        http.on("https://gitlab.com/api/v4/groups/acme?", body: GitLabFixtures.group)
        http.on("groups/acme/merge_requests", body: "[" + GitLabFixtures.mergeRequest(iid: 1) + "]")
        let provider = GitLabProvider(
            accountId: fixedAccountId, owners: ["acme"], tokenSource: StaticTokenSource(token: "glpat-secret"), http: http
        )

        let pr = try #require(try await provider.pullRequests(updatedSince: nil, limit: 10).first)

        #expect(pr.authorAvatarURL == URL(string: "https://gitlab.com/uploads/-/system/user/avatar/5/avatar.png"))
    }

    @Test func `A relative avatar path on a self-managed server becomes a full URL`() async throws {
        let http = MockHTTPClient()
        http.on("https://git.example.com/gitlab/api/v4/groups/team?", body: #"{"id":1,"full_path":"team"}"#)
        http.on("https://git.example.com/gitlab/api/v4/groups/team/merge_requests", body: #"""
        [{"iid":8,"title":"MR","state":"opened","created_at":"2025-10-15T10:00:00Z",
          "author":{"username":"jan","avatar_url":"/uploads/-/system/user/avatar/1/avatar.png"},
          "references":{"full":"team/app!8"},
          "web_url":"https://git.example.com/gitlab/team/app/-/merge_requests/8"}]
        """#)
        let provider = GitLabProvider(
            accountId: fixedAccountId, owners: ["team"], instanceURL: URL(string: "https://git.example.com/gitlab"),
            tokenSource: StaticTokenSource(token: "glpat-secret"), http: http
        )

        let pr = try #require(try await provider.pullRequests(updatedSince: nil, limit: 10).first)

        #expect(pr.authorAvatarURL == URL(string: "https://git.example.com/gitlab/uploads/-/system/user/avatar/1/avatar.png"))
    }
}

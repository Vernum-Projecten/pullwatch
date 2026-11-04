import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

/// De foto van de auteur van een PR komt uit `user.avatar_url` van de zoek-API, ook voor een bot:
/// `github.com/<bot>.png` bestaat niet.
@Suite struct GitHubAuthorAvatarTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let login: String
        let avatar: String?
        var testDescription: String { login }
    }

    static let cases = [
        Case(login: "octocat", avatar: "https://avatars.githubusercontent.com/u/583231?v=4"),
        Case(login: "github-actions[bot]", avatar: "https://avatars.githubusercontent.com/in/15368?v=4"),
        Case(login: "renovate[bot]", avatar: "https://avatars.githubusercontent.com/in/2740?v=4"),
        Case(login: "oldfixture", avatar: nil),
    ]

    func search(_ c: Case) -> String {
        let user = c.avatar.map { #"{"login":"\#(c.login)","avatar_url":"\#($0)"}"# } ?? #"{"login":"\#(c.login)"}"#
        return #"""
        {"total_count":1,"items":[{"number":7,"title":"Bump","created_at":"2026-10-15T10:00:00Z","draft":false,
         "user":\#(user),
         "html_url":"https://github.com/acme/web/pull/7",
         "repository_url":"https://api.github.com/repos/acme/web"}]}
        """#
    }

    @Test(arguments: cases)
    func `The author avatar of a pull request is the one the search API returns`(_ c: Case) async throws {
        let http = MockHTTPClient()
        http.on("search/issues", body: search(c))
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        let provider = GitHubProvider(accountId: fixedAccountId, owners: ["acme"], tokenSource: StaticTokenSource(token: "t"), http: http)

        let pr = try #require(try await provider.openPullRequests().first)

        #expect(pr.authorName == c.login)
        #expect(pr.authorAvatarURL == c.avatar.flatMap(URL.init(string:)))
    }

    @Test func `A GitHub Enterprise author keeps the avatar on the own server`() async throws {
        let http = MockHTTPClient()
        http.on("search/issues", body: #"""
        {"total_count":1,"items":[{"number":3,"title":"Fix","created_at":"2026-10-15T10:00:00Z",
         "user":{"login":"me","avatar_url":"https://github.example.com/avatars/u/2?"},
         "html_url":"https://github.example.com/me/dotfiles/pull/3",
         "repository_url":"https://github.example.com/api/v3/repos/me/dotfiles"}]}
        """#)
        http.on("users/me", body: #"{"type":"User"}"#)
        let provider = GitHubProvider(
            accountId: fixedAccountId, owners: ["me"], instanceURL: URL(string: "https://github.example.com"),
            tokenSource: StaticTokenSource(token: "t"), http: http
        )

        let pr = try #require(try await provider.openPullRequests().first)

        #expect(pr.authorAvatarURL == URL(string: "https://github.example.com/avatars/u/2?"))
    }
}

import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitea
import PullwatchTestSupport

/// Branches van Gitea, Forgejo en Codeberg: de heads per repo (met bladeren en een vingerafdruk),
/// de vergelijking van twee commits en de adressen van de webpagina's.
@Suite struct GiteaProviderBranchTests {
    let api = "https://codeberg.org/api/v1/"

    func branch(
        _ name: String, id: String, date: String = "2026-11-10T09:00:00Z",
        author: String = "Jan Jansen", email: String = "jan@example.com", username: String? = "jan"
    ) -> String {
        let user = username.map { #","username":"\#($0)""# } ?? ""
        return #"{"name":"\#(name)","commit":{"id":"\#(id)","message":"m","timestamp":"\#(date)","#
            + #""author":{"name":"\#(author)","email":"\#(email)"\#(user)},"#
            + #""committer":{"name":"Web","email":"noreply@example.com"}},"protected":false}"#
    }

    func list(_ branches: [String]) -> String { "[" + branches.joined(separator: ",") + "]" }

    func compareBody(_ total: Int) -> String { #"{"total_commits":\#(total),"commits":[]}"# }

    // MARK: Heads

    @Test func headsCarryTheCommitAndItsAuthor() async throws {
        let http = MockHTTPClient()
        http.on("\(api)repos/acme/api/branches", body: list([
            branch("main", id: "aaa111"),
            branch("feature/x", id: "bbb222", author: "Piet", email: "piet@example.com", username: nil),
        ]))
        let fetch = try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])

        #expect(fetch.unavailableRepos.isEmpty)
        #expect(fetch.unchangedRepos.isEmpty)
        #expect(fetch.heads.map(\.name) == ["main", "feature/x"])
        let main = try #require(fetch.heads.first)
        #expect(main.repo == "acme/api")
        #expect(main.sha == "aaa111")
        #expect(main.committedAt == DateParsing.parse("2026-11-10T09:00:00Z"))
        #expect(main.authorName == "Jan Jansen")
        #expect(main.authorEmail == "jan@example.com")
        #expect(main.authorId == "jan")
        #expect(main.webURL.absoluteString == "https://codeberg.org/acme/api/src/branch/main")
        #expect(fetch.heads[1].authorId == nil)
        #expect(fetch.heads[1].webURL.absoluteString == "https://codeberg.org/acme/api/src/branch/feature/x")
        #expect(fetch.fingerprints["acme/api"] != nil)
        #expect(try #require(urls(http).first).contains("limit=50"))
    }

    /// `authorId` moet gelijk zijn aan `currentUserId()`: de login van de gebruiker.
    @Test func authorIdMatchesTheCurrentUserLogin() async throws {
        let http = MockHTTPClient()
        http.on("\(api)user", body: GiteaFixtures.user())
        http.on("\(api)repos/acme/api/branches", body: list([branch("main", id: "aaa", username: "jdoe")]))
        let provider = makeProvider(http)
        let fetch = try await provider.branches(in: ["acme/api"], unchanged: [:])
        #expect(fetch.heads.first?.authorId == (try await provider.currentUserId()))
    }

    @Test func laterPagesAreRead() async throws {
        let http = MockHTTPClient()
        http.on("page=2", body: list([branch("b2", id: "222")]))
        http.on("repos/acme/api/branches", headers: [
            "Link": #"<https://codeberg.org/api/v1/repos/acme/api/branches?limit=50&page=2>; rel="next""#,
        ], body: list([branch("b1", id: "111")]))
        let fetch = try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])
        #expect(fetch.heads.map(\.name) == ["b1", "b2"])
    }

    @Test func anOtherHostNextLinkIsNotFollowed() async throws {
        let http = MockHTTPClient()
        http.on("evil.example.com", body: list([branch("stolen", id: "999")]))
        http.on("repos/acme/api/branches", headers: ["Link": #"<https://evil.example.com/api/v1/x?page=2>; rel="next""#],
                body: list([branch("b1", id: "111")]))
        let fetch = try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])
        #expect(fetch.heads.map(\.name) == ["b1"])
        #expect(!urls(http).contains { $0.contains("evil.example.com") })
    }

    // MARK: Vingerafdruk en uitkomsten

    @Test func anUnchangedFingerprintSkipsTheHeads() async throws {
        let http = MockHTTPClient()
        http.on("repos/acme/api/branches", body: list([branch("main", id: "aaa"), branch("dev", id: "bbb")]))
        let provider = makeProvider(http)
        let first = try await provider.branches(in: ["acme/api"], unchanged: [:])
        let fingerprint = try #require(first.fingerprints["acme/api"])

        let second = try await provider.branches(in: ["acme/api"], unchanged: ["acme/api": fingerprint])
        #expect(second.unchangedRepos == ["acme/api"])
        #expect(second.heads.isEmpty)
        #expect(second.fingerprints.isEmpty)

        // Een push (andere sha) verandert de vingerafdruk.
        let pushed = MockHTTPClient()
        pushed.on("repos/acme/api/branches", body: list([branch("main", id: "ccc"), branch("dev", id: "bbb")]))
        let third = try await makeProvider(pushed).branches(in: ["acme/api"], unchanged: ["acme/api": fingerprint])
        #expect(third.unchangedRepos.isEmpty)
        #expect(third.heads.count == 2)
        #expect(third.fingerprints["acme/api"] != fingerprint)
    }

    @Test func missingOrForbiddenReposAreUnavailable() async throws {
        let http = MockHTTPClient()
        http.on("repos/acme/gone/", status: 404, body: GiteaFixtures.notFound)
        http.on("repos/acme/secret/", status: 403, body: #"{"message":"Forbidden"}"#)
        http.on("repos/acme/ok/", body: list([branch("main", id: "aaa")]))
        let fetch = try await makeProvider(http).branches(in: ["acme/gone", "acme/secret", "acme/ok"], unchanged: [:])
        #expect(fetch.unavailableRepos == ["acme/gone", "acme/secret"])
        #expect(fetch.heads.map(\.repo) == ["acme/ok"])
    }

    /// Elke gevraagde repo komt in precies één uitkomst, ook een repo zonder branches.
    @Test func everyRequestedRepoEndsUpInExactlyOneBucket() async throws {
        let http = MockHTTPClient()
        http.on("repos/acme/read/", body: list([branch("main", id: "aaa")]))
        http.on("repos/acme/empty/", body: "[]")
        http.on("repos/acme/same/", body: list([branch("main", id: "bbb")]))
        http.on("repos/acme/gone/", status: 404, body: GiteaFixtures.notFound)
        let provider = makeProvider(http)
        let same = try #require(try await provider.branches(in: ["acme/same"], unchanged: [:]).fingerprints["acme/same"])

        let repos = ["acme/read", "acme/empty", "acme/same", "acme/gone"]
        let fetch = try await provider.branches(in: repos, unchanged: ["acme/same": same])
        let read = Set(fetch.fingerprints.keys)
        #expect(read == ["acme/read", "acme/empty"])
        #expect(Set(fetch.unchangedRepos) == ["acme/same"])
        #expect(Set(fetch.unavailableRepos) == ["acme/gone"])
        #expect(read.union(fetch.unchangedRepos).union(fetch.unavailableRepos) == Set(repos))
        #expect(fetch.heads.filter { $0.repo == "acme/empty" }.isEmpty)
    }

    @Test func aRateLimitOfTheAccountIsThrown() async throws {
        let http = MockHTTPClient()
        http.on("repos/acme/api/branches", status: 429, headers: ["Retry-After": "30"], body: "Retry later")
        await #expect(throws: ProviderError.rateLimited(until: Date.testStart + 30)) {
            try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])
        }
    }

    // MARK: Vergelijken

    @Test func compareCountsAheadAndBehind() async throws {
        let http = MockHTTPClient()
        http.on("compare/main...feature%2Fx", body: compareBody(3))
        http.on("compare/feature%2Fx...main", body: compareBody(5))
        let result = try await makeProvider(http).compare(in: "acme/api", from: "main", to: "feature/x")
        #expect(result == BranchComparison(ahead: 3, behind: 5))
    }

    @Test func compareOnAnOldServerIsNil() async throws {
        let http = MockHTTPClient()
        http.on("/compare/", status: 404, body: GiteaFixtures.notFound)
        #expect(try await makeProvider(http).compare(in: "acme/api", from: "main", to: "dev") == nil)
    }

    @Test func compareThrowsOtherErrors() async throws {
        let http = MockHTTPClient()
        http.on("/compare/", status: 429, headers: ["Retry-After": "30"], body: "Retry later")
        await #expect(throws: ProviderError.rateLimited(until: Date.testStart + 30)) {
            try await makeProvider(http).compare(in: "acme/api", from: "main", to: "dev")
        }
    }

    // MARK: Adressen

    @Test func urlsEncodeAwkwardBranchNames() async throws {
        let http = MockHTTPClient()
        http.on("\(api)repos/acme/api/branches", body: list([branch("feature/ä b#1", id: "aaa")]))
        let provider = makeProvider(http)
        let fetch = try await provider.branches(in: ["acme/api"], unchanged: [:])
        #expect(fetch.heads.first?.webURL.absoluteString == "https://codeberg.org/acme/api/src/branch/feature/%C3%A4%20b%231")
        #expect(
            provider.compareURL(in: "acme/api", from: "main", to: "feature/ä b#1")?.absoluteString
                == "https://codeberg.org/acme/api/compare/main...feature%2F%C3%A4%20b%231"
        )
    }
}

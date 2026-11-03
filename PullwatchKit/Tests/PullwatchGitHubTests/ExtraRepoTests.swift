import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

/// Losse repo's buiten de gevolgde eigenaren: gebundeld zoeken, en lezen zonder token als het
/// token een openbare repo niet mag lezen.
@Suite struct ExtraRepoTests {
    let extra = "openEHR/specifications-AM"

    func item(number: Int, repo: String) -> String {
        #"""
        {"number":\#(number),"title":"PR \#(number)","created_at":"2025-10-15T10:00:00Z","draft":false,
         "user":{"login":"someone"},
         "html_url":"https://github.com/\#(repo)/pull/\#(number)",
         "repository_url":"https://api.github.com/repos/\#(repo)"}
        """#
    }

    func makeProvider(_ http: MockHTTPClient, owners: [String] = ["acme"], extras: [String]) -> GitHubProvider {
        GitHubProvider(
            accountId: fixedAccountId, owners: owners, extraRepos: extras,
            tokenSource: StaticTokenSource(token: "ghtok"), http: http, now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    func searches(_ http: MockHTTPClient) -> [URLRequest] {
        http.requests.filter { $0.url?.absoluteString.contains("search/issues") == true }
    }

    // MARK: Bundelen

    @Test func bundlesRepoQualifiersWithinTheLimits() {
        let repos = (0..<75).map { "owner\($0)/repository-\($0)" }
        let queries = GitHubProvider.searchQueries("is:pr is:open", repos: repos)

        #expect(queries.count == 3, "30 per zoekopdracht")
        #expect(queries.allSatisfy { $0.hasPrefix("is:pr is:open repo:") })
        #expect(queries.allSatisfy { $0.count <= GitHubProvider.searchQueryLength })
        let found = queries.flatMap { $0.split(separator: " ").filter { $0.hasPrefix("repo:") }.map { String($0.dropFirst(5)) } }
        #expect(found == repos, "elke repo precies één keer, in volgorde")
    }

    @Test func longNamesMakeSmallerBatches() {
        let repos = (0..<20).map { "an-owner-with-a-long-name-\($0)/" + String(repeating: "r", count: 80) }
        let queries = GitHubProvider.searchQueries("is:pr", repos: repos)
        #expect(queries.count > 1)
        #expect(queries.allSatisfy { $0.count <= GitHubProvider.searchQueryLength })
    }

    @Test func noExtraReposMeansNoExtraSearch() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("search/issues", body: #"{"total_count":0,"items":[]}"#)
        _ = try await makeProvider(http, extras: []).openPullRequests()
        #expect(searches(http).count == 1)
    }

    @Test func extraRepoOfAFollowedOwnerNeedsNoOwnSearch() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("search/issues", body: #"{"total_count":0,"items":[]}"#)
        _ = try await makeProvider(http, extras: ["ACME/web"]).openPullRequests()
        #expect(searches(http).count == 1, "acme/web komt al mee met org:acme")
    }

    // MARK: Met token

    @Test func readableExtraRepoIsSearchedWithTheToken() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("api.github.com/repos/\(extra)", authorized: true, body: #"{"full_name":"\#(extra)"}"#)
        http.on("repo:\(extra)", body: #"{"total_count":1,"items":[\#(item(number: 50, repo: extra))]}"#)
        http.on("search/issues", body: #"{"total_count":0,"items":[]}"#)

        let prs = try await makeProvider(http, extras: [extra]).openPullRequests()

        #expect(prs.map(\.repo) == [extra])
        let search = try #require(searches(http).first { $0.url!.absoluteString.contains("repo:") })
        #expect(search.value(forHTTPHeaderField: "Authorization") == "Bearer ghtok")
        #expect(search.url!.absoluteString.contains("is:open"))
    }

    // MARK: Zonder token

    @Test func publicRepoTheTokenCannotReadIsReadWithoutToken() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        // Met token: niet te zien (de app is daar niet geïnstalleerd); zonder token wel.
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 404, body: #"{"message":"Not Found"}"#)
        http.on("api.github.com/repos/\(extra)", authorized: false, body: #"{"full_name":"\#(extra)"}"#)
        http.on("repo:\(extra)", authorized: false, body: #"{"total_count":1,"items":[\#(item(number: 50, repo: extra))]}"#)
        http.on("search/issues", body: #"{"total_count":0,"items":[]}"#)
        let provider = makeProvider(http, extras: [extra])

        let prs = try await provider.openPullRequests()

        #expect(prs.map(\.number) == [50])
        let probes = http.requests.filter { $0.url!.path() == "/repos/\(extra)" }
        #expect(probes.map { $0.value(forHTTPHeaderField: "Authorization") != nil } == [true, false], "eerst met token, dan zonder")
        let search = try #require(searches(http).first { $0.url!.absoluteString.contains("repo:") })
        #expect(search.value(forHTTPHeaderField: "Authorization") == nil)

        // Een tweede poll kijkt niet opnieuw: de repo wordt meteen zonder token doorzocht.
        _ = try await provider.openPullRequests()
        #expect(http.requests.filter { $0.url!.path() == "/repos/\(extra)" }.count == 2)
    }

    @Test func forbiddenWithTheTokenAlsoFallsBack() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 403, body: #"{"message":"Resource not accessible by integration"}"#)
        http.on("api.github.com/repos/\(extra)", authorized: false, body: #"{"full_name":"\#(extra)"}"#)

        let check = try await makeProvider(http, extras: [extra]).checkRepository(extra)

        #expect(check == RepositoryCheck(name: extra, readWithoutSignIn: true))
    }

    @Test func checkGivesTheNameAsGitHubWritesIt() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/repos/openehr/specifications-am", authorized: true, body: #"{"full_name":"\#(extra)"}"#)

        let check = try await makeProvider(http, extras: []).checkRepository("openehr/specifications-am")

        #expect(check == RepositoryCheck(name: extra))
        #expect(http.requests.count == 1, "één verzoek")
    }

    @Test func missingRepoIsNoAccess() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/repos/openEHR/nope", status: 404, body: #"{"message":"Not Found"}"#)

        await #expect(throws: ProviderError.noAccess("openEHR/nope")) {
            try await makeProvider(http, extras: []).checkRepository("openEHR/nope")
        }
    }

    @Test func revokedTokenIsNotHiddenByTheFallback() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 401, body: #"{"message":"Bad credentials"}"#)
        http.on("api.github.com/repos/\(extra)", authorized: false, body: #"{"full_name":"\#(extra)"}"#)

        await #expect(throws: ProviderError.unauthorized) {
            try await makeProvider(http, extras: [extra]).checkRepository(extra)
        }
    }

    @Test func spentAnonymousLimitSkipsTheRepoWithoutFailing() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("org:acme", body: #"{"total_count":1,"items":[\#(item(number: 1, repo: "acme/web"))]}"#)
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 404, body: #"{"message":"Not Found"}"#)
        http.on(
            "api.github.com/repos/\(extra)", authorized: false, status: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800003600"],
            body: #"{"message":"API rate limit exceeded"}"#
        )
        let provider = makeProvider(http, extras: [extra])

        let prs = try await provider.openPullRequests()

        #expect(prs.map(\.repo) == ["acme/web"], "het account zelf gaat gewoon door")
        // Tot de limiet terug is geen nieuwe poging zonder token.
        _ = try await provider.openPullRequests()
        #expect(http.requests.filter { $0.url!.path() == "/repos/\(extra)" && $0.value(forHTTPHeaderField: "Authorization") == nil }.count == 1)
        await #expect(throws: ProviderError.rateLimited(until: Date(timeIntervalSince1970: 1_800_003_600))) {
            try await provider.checkRepository(extra)
        }
    }

    @Test func spentAnonymousSearchLimitKeepsTheOtherResults() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("org:acme", body: #"{"total_count":1,"items":[\#(item(number: 1, repo: "acme/web"))]}"#)
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 404, body: #"{"message":"Not Found"}"#)
        http.on("api.github.com/repos/\(extra)", authorized: false, body: #"{"full_name":"\#(extra)"}"#)
        http.on(
            "repo:\(extra)", authorized: false, status: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000060"],
            body: #"{"message":"API rate limit exceeded"}"#
        )

        let prs = try await makeProvider(http, extras: [extra]).openPullRequests()

        #expect(prs.map(\.repo) == ["acme/web"])
    }

    @Test func listsExtraReposWithTheirOwnSpelling() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("orgs/acme/repos", body: #"[{"full_name":"acme/web"}]"#)
        http.on("api.github.com/repos/openehr/specifications-am", authorized: true, status: 404, body: "{}")
        http.on("api.github.com/repos/openehr/specifications-am", authorized: false, body: #"{"full_name":"\#(extra)"}"#)
        http.on("api.github.com/repos/gone/away", status: 404, body: "{}")

        let repos = try await makeProvider(http, extras: ["openehr/specifications-am", "gone/away"]).listRepos()

        #expect(repos == ["acme/web", extra], "een verdwenen losse repo staat er niet bij")
    }

    @Test func filesOfAPublicRepoAreReadWithoutToken() async throws {
        let http = MockHTTPClient()
        http.on("git/trees/HEAD", authorized: true, status: 404, body: "{}")
        http.on("git/trees/HEAD", authorized: false, body: #"{"tree":[{"path":"package.json","type":"blob"}]}"#)
        http.on("contents/package.json", authorized: false, body: "{}")
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 404, body: "{}")
        http.on("api.github.com/repos/\(extra)", authorized: false, body: #"{"full_name":"\#(extra)"}"#)
        let provider = makeProvider(http, extras: [extra])

        #expect(try await provider.filePaths(in: extra) == ["package.json"])
        #expect(try await provider.fileContent(in: extra, path: "package.json") == "{}")
        let contents = try #require(http.requests.first { $0.url!.path().contains("contents") })
        #expect(contents.value(forHTTPHeaderField: "Authorization") == nil, "na de eerste keer meteen zonder token")
    }

    @Test func aMissingFileInAReadableRepoStaysAnError() async throws {
        let http = MockHTTPClient()
        http.on("contents/nope", status: 404, body: "{}")
        http.on("api.github.com/repos/\(extra)", authorized: true, body: #"{"full_name":"\#(extra)"}"#)

        await #expect(throws: ProviderError.server(status: 404)) {
            try await makeProvider(http, extras: [extra]).fileContent(in: extra, path: "nope")
        }
        #expect(!http.requests.contains { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test func tagsOfAPublicRepoComeFromRestWithoutToken() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/repos/\(extra)/tags", authorized: false, body: #"[{"name":"Release-2.3.0"},{"name":"Release-2.2.0"}]"#)
        http.on("api.github.com/repos/\(extra)/releases", authorized: false, body: #"""
            [{"id":1,"tag_name":"Release-2.3.0","name":"AM 2.3.0","draft":false,"prerelease":false,
              "published_at":"2025-01-02T10:00:00Z","html_url":"https://github.com/\#(extra)/releases/tag/Release-2.3.0",
              "author":{"login":"wolandscat","avatar_url":"https://github.com/wolandscat.png"}}]
            """#)
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 404, body: "{}")
        http.on("api.github.com/repos/\(extra)", authorized: false, body: #"{"full_name":"\#(extra)"}"#)

        let fetch = try await makeProvider(http, extras: [extra]).tags(in: [extra])

        #expect(fetch.tags.map(\.name) == ["Release-2.3.0", "Release-2.2.0"])
        #expect(fetch.tags.first?.release?.title == "AM 2.3.0")
        #expect(fetch.tags.first?.authorName == "wolandscat")
        #expect(fetch.unavailableRepos.isEmpty)
        #expect(fetch.fingerprints[extra] != nil)
        #expect(!http.requests.contains { $0.url!.path() == "/graphql" }, "GraphQL vraagt altijd een token")
    }

    @Test func coAuthorsSkipReposReadWithoutToken() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/repos/\(extra)", authorized: true, status: 404, body: "{}")
        http.on("api.github.com/repos/\(extra)", authorized: false, body: #"{"full_name":"\#(extra)"}"#)
        let provider = makeProvider(http, extras: [extra])
        _ = try await provider.checkRepository(extra)
        let pr = PullRequest(
            accountId: fixedAccountId, repo: extra, number: 50, title: "t", authorId: "a", authorName: "a",
            isDraft: false, createdAt: Date(), webURL: URL(string: "https://github.com")!
        )

        #expect(try await provider.coAuthors(of: [pr]).isEmpty)
        #expect(!http.requests.contains { $0.url!.path() == "/graphql" })
    }
}

import Foundation
import Testing
@testable import PullwatchBitbucket
@testable import PullwatchCore
import PullwatchTestSupport

/// Branches van Bitbucket: de heads per repo (met bladeren en een vingerafdruk), de vergelijking
/// van twee commits en de adressen van de webpagina's.
@Suite struct BitbucketProviderBranchTests {
    let api = "https://api.bitbucket.org/2.0/"

    func makeProvider(_ http: MockHTTPClient, extras: [String] = []) -> BitbucketProvider {
        BitbucketProvider(
            accountId: fixedAccountId, workspaces: ["acme"], email: "jane@example.com", extraRepos: extras,
            tokenSource: StaticTokenSource(token: "ATATT3xFfGF0-secret"), http: http, now: { Date.testStart }
        )
    }

    func branch(
        _ name: String, hash: String, date: String = "2026-11-10T09:00:00+00:00",
        raw: String = "Jan Jansen <jan@example.com>", user: String? = nil
    ) -> String {
        #"{"name":"\#(name)","type":"branch","target":{"type":"commit","hash":"\#(hash)","date":"\#(date)","#
            + #""author":{"type":"author","raw":"\#(raw)"\#(user.map { ",\"user\":" + $0 } ?? "")}}}"#
    }

    func page(_ values: [String], next: String? = nil) -> String {
        BitbucketFixtures.page(values, next: next)
    }

    func commits(_ count: Int) -> String {
        page((0..<count).map { #"{"hash":"c\#($0)"}"# })
    }

    func urls(_ http: MockHTTPClient) -> [String] { http.requests.compactMap { $0.url?.absoluteString } }

    // MARK: Heads

    @Test func headsCarryTheCommitAndItsAuthor() async throws {
        let http = MockHTTPClient()
        let user = #"{"display_name":"Piet","uuid":"{aaaa-bbbb}","account_id":"557057:abc","links":{"avatar":{"href":"https://secure.gravatar.com/avatar/2"}}}"#
        http.on("repositories/acme/api/refs/branches", body: page([
            branch("main", hash: "aaa111"),
            branch("feature/x", hash: "bbb222", raw: "Piet <piet@example.com>", user: user),
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
        #expect(main.authorId == nil)
        #expect(main.authorAvatarURL == nil)
        #expect(main.webURL.absoluteString == "https://bitbucket.org/acme/api/branch/main")
        let linked = fetch.heads[1]
        // Het id is dat van `currentUserId()` (de uuid), zodat de eigen-push-controle klopt.
        #expect(linked.authorId == "{aaaa-bbbb}")
        #expect(linked.authorName == "Piet")
        #expect(linked.authorEmail == "piet@example.com")
        #expect(linked.authorAvatarURL?.absoluteString == "https://secure.gravatar.com/avatar/2")
        #expect(fetch.fingerprints["acme/api"] != nil)
        #expect(try #require(urls(http).first).contains("pagelen=100"))
    }

    @Test func laterPagesAreRead() async throws {
        let http = MockHTTPClient()
        let second = "\(api)repositories/acme/api/refs/branches?pagelen=100&page=2"
        http.on("page=2", body: page([branch("b2", hash: "222")]))
        http.on("refs/branches", body: page([branch("b1", hash: "111")], next: second))
        let fetch = try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])
        #expect(fetch.heads.map(\.name) == ["b1", "b2"])
    }

    @Test func anOtherHostNextLinkIsNotFollowed() async throws {
        let http = MockHTTPClient()
        http.on("evil.example.com", body: page([branch("stolen", hash: "999")]))
        http.on("refs/branches", body: page([branch("b1", hash: "111")], next: "https://evil.example.com/2.0/x?page=2"))
        let fetch = try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])
        #expect(fetch.heads.map(\.name) == ["b1"])
        #expect(!urls(http).contains { $0.contains("evil.example.com") })
    }

    // MARK: Vingerafdruk en uitkomsten

    @Test func anUnchangedFingerprintSkipsTheHeads() async throws {
        let http = MockHTTPClient()
        http.on("refs/branches", body: page([branch("main", hash: "aaa"), branch("dev", hash: "bbb")]))
        let provider = makeProvider(http)
        let first = try await provider.branches(in: ["acme/api"], unchanged: [:])
        let fingerprint = try #require(first.fingerprints["acme/api"])

        let second = try await provider.branches(in: ["acme/api"], unchanged: ["acme/api": fingerprint])
        #expect(second.unchangedRepos == ["acme/api"])
        #expect(second.heads.isEmpty)
        #expect(second.fingerprints.isEmpty)

        let pushed = MockHTTPClient()
        pushed.on("refs/branches", body: page([branch("main", hash: "ccc"), branch("dev", hash: "bbb")]))
        let third = try await makeProvider(pushed).branches(in: ["acme/api"], unchanged: ["acme/api": fingerprint])
        #expect(third.unchangedRepos.isEmpty)
        #expect(third.heads.count == 2)
        #expect(third.fingerprints["acme/api"] != fingerprint)
    }

    @Test func missingOrForbiddenExtraReposAreUnavailable() async throws {
        let http = MockHTTPClient()
        http.on("repositories/acme/gone/", status: 404, body: BitbucketFixtures.noAccess)
        http.on("repositories/other/secret/refs/branches", status: 403, body: BitbucketFixtures.noAccess)
        http.on("repositories/other/secret", body: BitbucketFixtures.repository("other/secret"))
        http.on("repositories/acme/ok/", body: page([branch("main", hash: "aaa")]))
        let fetch = try await makeProvider(http, extras: ["other/secret"])
            .branches(in: ["acme/gone", "other/secret", "acme/ok"], unchanged: [:])
        #expect(fetch.unavailableRepos == ["acme/gone", "other/secret"])
        #expect(fetch.heads.map(\.repo) == ["acme/ok"])
    }

    /// Elke gevraagde repo komt in precies één uitkomst, ook een repo zonder branches.
    @Test func everyRequestedRepoEndsUpInExactlyOneBucket() async throws {
        let http = MockHTTPClient()
        http.on("repositories/acme/read/", body: page([branch("main", hash: "aaa")]))
        http.on("repositories/acme/empty/", body: page([]))
        http.on("repositories/acme/same/", body: page([branch("main", hash: "bbb")]))
        http.on("repositories/acme/gone/", status: 404, body: BitbucketFixtures.noAccess)
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
        http.on("refs/branches", status: 429, headers: ["Retry-After": "30"], body: "Retry later")
        await #expect(throws: ProviderError.rateLimited(until: Date.testStart + 30)) {
            try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])
        }
    }

    @Test func aPublicExtraRepoIsReadWithoutTokenAndItsLimitMakesItUnavailable() async throws {
        let http = MockHTTPClient()
        http.on("refs/branches", authorized: false, body: page([branch("main", hash: "aaa")]))
        http.on("\(api)repositories/atlassian/aui", authorized: true, status: 403, body: BitbucketFixtures.noAccess)
        http.on("\(api)repositories/atlassian/aui", authorized: false, body: BitbucketFixtures.repository("atlassian/aui"))
        let fetch = try await makeProvider(http, extras: ["atlassian/aui"]).branches(in: ["atlassian/aui"], unchanged: [:])
        #expect(fetch.heads.map(\.name) == ["main"])
        #expect(http.requests.filter { $0.url?.path.hasSuffix("/refs/branches") == true }
            .allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })

        let limited = MockHTTPClient()
        limited.on("refs/branches", authorized: false, status: 429, headers: ["Retry-After": "30"], body: "")
        limited.on("\(api)repositories/atlassian/aui", authorized: true, status: 403, body: BitbucketFixtures.noAccess)
        limited.on("\(api)repositories/atlassian/aui", authorized: false, body: BitbucketFixtures.repository("atlassian/aui"))
        let second = try await makeProvider(limited, extras: ["atlassian/aui"]).branches(in: ["atlassian/aui"], unchanged: [:])
        #expect(second.unavailableRepos == ["atlassian/aui"])
        #expect(second.heads.isEmpty)
    }

    // MARK: Vergelijken

    @Test func compareCountsAheadAndBehindWithTwoRequests() async throws {
        let http = MockHTTPClient()
        http.on("include=new&exclude=old", body: commits(3))
        http.on("include=old&exclude=new", body: commits(1))
        let comparison = try await makeProvider(http).compare(in: "acme/api", from: "old", to: "new")
        #expect(comparison == BranchComparison(ahead: 3, behind: 1))
        let calls = urls(http)
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.contains("repositories/acme/api/commits?") && $0.contains("pagelen=100") })
    }

    @Test func compareCapsTheCountAtOneHundred() async throws {
        let http = MockHTTPClient()
        http.on("include=new&exclude=old", body: page((0..<100).map { #"{"hash":"c\#($0)"}"# }, next: "\(api)repositories/acme/api/commits?page=2"))
        http.on("include=old&exclude=new", body: commits(0))
        let comparison = try await makeProvider(http).compare(in: "acme/api", from: "old", to: "new")
        #expect(comparison == BranchComparison(ahead: 100, behind: 0))
        #expect(urls(http).count == 2)
    }

    @Test func compareOfAnUnknownCommitIsNil() async throws {
        let http = MockHTTPClient()
        http.on("commits", status: 404, body: BitbucketFixtures.noAccess)
        #expect(try await makeProvider(http).compare(in: "acme/api", from: "gone", to: "new") == nil)
    }

    @Test func compareLetsOtherErrorsThrough() async throws {
        let http = MockHTTPClient()
        http.on("commits", status: 500, body: "boom")
        await #expect(throws: ProviderError.self) {
            try await makeProvider(http).compare(in: "acme/api", from: "a", to: "b")
        }
    }

    // MARK: Adressen

    /// Bitbucket scheidt de twee kanten met een gecodeerde regelterugloop (`%0D`); die mag niet
    /// nog eens gecodeerd worden.
    @Test func compareURLSeparatesBothSidesWithAnEncodedCarriageReturn() {
        let provider = makeProvider(MockHTTPClient())
        #expect(provider.compareURL(in: "acme/api", from: "abc", to: "def")?.absoluteString
            == "https://bitbucket.org/acme/api/branches/compare/def%0Dabc")
        #expect(provider.compareURL(in: "acme/api", from: "main", to: "feature/ä b#1")?.absoluteString
            == "https://bitbucket.org/acme/api/branches/compare/feature%2F%C3%A4%20b%231%0Dmain")
    }

    @Test func headURLEncodesAnAwkwardName() async throws {
        let http = MockHTTPClient()
        http.on("refs/branches", body: page([branch("feature/ä b#1", hash: "aaa")]))
        let fetch = try await makeProvider(http).branches(in: ["acme/api"], unchanged: [:])
        #expect(fetch.heads[0].webURL.absoluteString == "https://bitbucket.org/acme/api/branch/feature%2F%C3%A4%20b%231")
    }
}

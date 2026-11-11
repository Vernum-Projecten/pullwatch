import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

/// Branches van Azure DevOps: de heads uit de refs, de commits in één `commitsbatch`, de
/// vingerafdruk (gesorteerde `name:sha`), de vergelijking en de adressen van de webpagina's.
@Suite struct AzureDevOpsProviderBranchTests {
    func commitsJSON(_ commits: [(id: String, name: String, email: String, date: String)]) -> String {
        let items = commits.map {
            #"{"commitId":"\#($0.id)","author":{"name":"\#($0.name)","email":"\#($0.email)","date":"2026-01-01T00:00:00Z"},"#
                + #""committer":{"name":"Cm","date":"\#($0.date)"}}"#
        }
        return #"{"value":[\#(items.joined(separator: ","))]}"#
    }

    func refsJSON(_ refs: [(name: String, sha: String)]) -> String {
        #"{"value":[\#(refs.map { #"{"name":"refs/heads/\#($0.name)","objectId":"\#($0.sha)"}"# }.joined(separator: ","))]}"#
    }

    @Test func `Heads carry commit date author and email`() async throws {
        let http = MockHTTPClient()
        http.on("repositories/api/refs", body: refsJSON([("main", "c1"), ("feature/x", "c2")]))
        http.on("repositories/api/commitsbatch", body: commitsJSON([
            ("c1", "Jan Jansen", "jan@example.com", "2026-11-10T09:00:00Z"),
            ("c2", "Piet", "piet@example.com", "2026-11-10T10:00:00Z"),
        ]))

        let fetch = try await makeProvider(http).branches(in: ["My Project/api"], unchanged: [:])

        #expect(fetch.unavailableRepos.isEmpty)
        #expect(fetch.unchangedRepos.isEmpty)
        #expect(fetch.fingerprints["My Project/api"] == "feature/x:c2\nmain:c1")
        let main = try #require(fetch.heads.first { $0.name == "main" })
        #expect(main.repo == "My Project/api")
        #expect(main.sha == "c1")
        #expect(main.authorName == "Jan Jansen")
        #expect(main.authorEmail == "jan@example.com")
        #expect(main.authorId == nil)
        #expect(main.committedAt == DateParsing.parse("2026-11-10T09:00:00Z"))
        #expect(fetch.heads.count == 2)
        let refs = try #require(http.requests.first { $0.url!.absoluteString.contains("/refs") }?.url?.absoluteString)
        #expect(refs.contains("filter=heads/"))
        #expect(refs.contains("peelTags=false"))
        #expect(refs.hasPrefix("https://dev.azure.com/acme/My%20Project/_apis/git/repositories/api/refs"))
        let batches = http.requests.filter { $0.url!.absoluteString.contains("commitsbatch") }
        #expect(batches.count == 1)
        expectCalledHostsAreListed(
            called: Set(http.requests.compactMap { $0.url?.host() }), expected: ["dev.azure.com"], listed: ["dev.azure.com"]
        )
    }

    @Test func `Follows the continuation token to the next page`() async throws {
        let http = MockHTTPClient()
        http.on("continuationToken=tok%2B1", body: refsJSON([("b", "c2")]))
        http.on("repositories/api/refs", headers: ["x-ms-continuationtoken": "tok+1"], body: refsJSON([("a", "c1")]))
        http.on("commitsbatch", body: commitsJSON([
            ("c1", "A", "a@x.nl", "2026-11-10T09:00:00Z"), ("c2", "B", "b@x.nl", "2026-11-10T09:00:00Z"),
        ]))

        let fetch = try await makeProvider(http).branches(in: ["proj/api"], unchanged: [:])

        #expect(Set(fetch.heads.map(\.name)) == ["a", "b"])
        #expect(fetch.fingerprints["proj/api"] == "a:c1\nb:c2")
    }

    @Test func `An equal fingerprint skips the commits`() async throws {
        let http = MockHTTPClient()
        http.on("repositories/api/refs", body: refsJSON([("main", "c1")]))

        let fetch = try await makeProvider(http).branches(in: ["proj/api"], unchanged: ["proj/api": "main:c1"])

        #expect(fetch.unchangedRepos == ["proj/api"])
        #expect(fetch.heads.isEmpty)
        #expect(fetch.fingerprints.isEmpty)
        #expect(!http.requests.contains { $0.url!.absoluteString.contains("commitsbatch") })
    }

    @Test func `A missing or forbidden repo is unavailable`() async throws {
        let http = MockHTTPClient()
        http.on("repositories/gone/refs", status: 404, body: "{}")
        http.on("repositories/secret/refs", status: 403, body: "{}")

        let fetch = try await makeProvider(http).branches(in: ["proj/gone", "proj/secret"], unchanged: [:])

        #expect(fetch.unavailableRepos == ["proj/gone", "proj/secret"])
        #expect(fetch.heads.isEmpty)
        #expect(fetch.fingerprints.isEmpty)
    }

    @Test func `Every repo ends up in exactly one outcome`() async throws {
        let http = MockHTTPClient()
        http.on("repositories/full/refs", body: refsJSON([("main", "c1")]))
        http.on("repositories/empty/refs", body: #"{"value":[]}"#)
        http.on("repositories/same/refs", body: refsJSON([("main", "c9")]))
        http.on("repositories/gone/refs", status: 404, body: "{}")
        http.on("commitsbatch", body: commitsJSON([("c1", "A", "a@x.nl", "2026-11-10T09:00:00Z")]))
        let repos = ["p/full", "p/empty", "p/same", "p/gone", "noslash"]

        let fetch = try await makeProvider(http).branches(in: repos, unchanged: ["p/same": "main:c9"])

        #expect(fetch.fingerprints.keys.sorted() == ["p/empty", "p/full"])
        #expect(fetch.fingerprints["p/empty"] == "")
        #expect(Set(fetch.heads.map(\.repo)) == ["p/full"])
        #expect(fetch.unchangedRepos == ["p/same"])
        #expect(fetch.unavailableRepos.sorted() == ["noslash", "p/gone"])
        let outcomes = Set(fetch.fingerprints.keys).union(fetch.unavailableRepos).union(fetch.unchangedRepos)
        #expect(outcomes == Set(repos))
    }

    @Test func `A rate limit is thrown`() async {
        let http = MockHTTPClient()
        http.on("refs", status: 429, headers: ["Retry-After": "30"], body: "{}")

        await #expect(throws: ProviderError.self) {
            _ = try await makeProvider(http).branches(in: ["proj/api"], unchanged: [:])
        }
    }

    @Test func `Compare gives ahead and behind`() async throws {
        let http = MockHTTPClient()
        http.on("diffs/commits", body: #"{"aheadCount":3,"behindCount":1,"changes":[]}"#)

        let result = try await makeProvider(http).compare(in: "proj/api", from: "aaa", to: "bbb")

        #expect(result == BranchComparison(ahead: 3, behind: 1))
        let url = try #require(http.requests.first?.url?.absoluteString)
        #expect(url.contains("baseVersion=aaa"))
        #expect(url.contains("baseVersionType=commit"))
        #expect(url.contains("targetVersion=bbb"))
        #expect(url.contains("targetVersionType=commit"))
        #expect(url.contains("$top=1"))
    }

    @Test func `Compare is nil on a 404`() async throws {
        let http = MockHTTPClient()
        http.on("diffs/commits", status: 404, body: "{}")

        #expect(try await makeProvider(http).compare(in: "proj/api", from: "a", to: "b") == nil)
    }

    @Test func `Compare throws other errors`() async {
        let http = MockHTTPClient()
        http.on("diffs/commits", status: 500, body: "{}")

        await #expect(throws: ProviderError.self) {
            _ = try await makeProvider(http).compare(in: "proj/api", from: "a", to: "b")
        }
    }

    @Test func `Compare URL and head URL encode awkward branch names`() async throws {
        let http = MockHTTPClient()
        http.on("repositories/api/refs", body: refsJSON([("feature/ä b#1", "c1")]))
        http.on("commitsbatch", body: commitsJSON([("c1", "A", "a@x.nl", "2026-11-10T09:00:00Z")]))
        let provider = makeProvider(http)

        let fetch = try await provider.branches(in: ["My Project/api"], unchanged: [:])

        let head = try #require(fetch.heads.first)
        #expect(head.name == "feature/ä b#1")
        #expect(head.webURL.absoluteString
            == "https://dev.azure.com/acme/My%20Project/_git/api?version=GBfeature/%C3%A4%20b%231")
        #expect(provider.compareURL(in: "My Project/api", from: "aaa", to: "bbb")?.absoluteString
            == "https://dev.azure.com/acme/My%20Project/_git/api/branchCompare?baseVersion=GCaaa&targetVersion=GCbbb")
        #expect(provider.compareURL(in: "noslash", from: "a", to: "b") == nil)
    }
}

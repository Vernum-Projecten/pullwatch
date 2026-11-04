import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

@Suite struct GitHubProviderTests {
    func item(number: Int, repo: String = "acme/web", draft: Bool? = false, login: String = "octocat") -> String {
        let draftField = draft.map { #","draft":\#($0)"# } ?? ""
        return #"""
        {"number":\#(number),"title":"PR \#(number)","created_at":"2025-10-15T10:00:00Z"\#(draftField),
         "user":{"login":"\#(login)"},
         "html_url":"https://github.com/\#(repo)/pull/\#(number)",
         "repository_url":"https://api.github.com/repos/\#(repo)"}
        """#
    }

    @Test func followsSeveralOwnersWithOneSearchEach() async throws {
        let http = MockHTTPClient()
        http.on("org:acme", body: #"{"total_count":1,"items":[\#(item(number: 1, repo: "acme/web"))]}"#)
        http.on("user:jane", body: #"{"total_count":1,"items":[\#(item(number: 2, repo: "jane/dotfiles"))]}"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("users/jane", body: #"{"type":"User"}"#)
        let provider = GitHubProvider(accountId: fixedAccountId, owners: ["jane", "acme"], tokenSource: StaticTokenSource(token: "t"), http: http)

        let prs = try await provider.openPullRequests()

        #expect(Set(prs.map(\.repo)) == ["acme/web", "jane/dotfiles"], "PR's van het eigen account en de organisatie samen")
        let searches = http.requests.compactMap(\.url?.absoluteString).filter { $0.contains("search/issues") }
        #expect(searches.count == 2)
    }

    @Test func listsTheRepositoriesOfEveryOwner() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/user?", body: #"{"login":"jane"}"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("users/jane", body: #"{"type":"User"}"#)
        http.on("orgs/acme/repos", body: #"[{"full_name":"acme/web"}]"#)
        http.on("user/repos", body: #"[{"full_name":"jane/dotfiles"},{"full_name":"jane/zed"}]"#)
        http.on("api.github.com/user", body: #"{"login":"jane"}"#)
        let provider = GitHubProvider(accountId: fixedAccountId, owners: ["jane", "acme"], tokenSource: StaticTokenSource(token: "t"), http: http)

        #expect(try await provider.listRepos() == ["acme/web", "jane/dotfiles", "jane/zed"])
    }

    @Test func searchesOpenPullRequestsForOrganization() async throws {
        let http = MockHTTPClient()
        http.on("search/issues", body: #"{"total_count":1,"items":[\#(item(number: 5, draft: true))]}"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)

        let prs = try await makeProvider(http).openPullRequests()

        let pr = try #require(prs.first)
        #expect(pr.repo == "acme/web")
        #expect(pr.number == 5)
        #expect(pr.title == "PR 5")
        #expect(pr.authorId == "octocat")
        #expect(pr.authorName == "octocat")
        #expect(pr.isDraft == true)
        #expect(pr.createdAt == Date(timeIntervalSince1970: 1_760_522_400))
        #expect(pr.webURL.absoluteString == "https://github.com/acme/web/pull/5")

        let searchURL = try #require(http.requests.last?.url)
        let q = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        #expect(q == "is:pr is:open org:acme")
    }

    @Test func usesUserQualifierForUserOwner() async throws {
        let http = MockHTTPClient()
        http.on("search/issues", body: #"{"total_count":0,"items":[]}"#)
        http.on("users/alessandro", body: #"{"type":"User"}"#)

        _ = try await makeProvider(http, owner: "alessandro").openPullRequests()

        let searchURL = try #require(http.requests.last?.url)
        let q = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        #expect(q == "is:pr is:open user:alessandro")
    }

    @Test func missingDraftFieldMeansNotDraft() async throws {
        let http = MockHTTPClient()
        http.on("search/issues", body: #"{"total_count":1,"items":[\#(item(number: 1, draft: nil))]}"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        #expect(try await makeProvider(http).openPullRequests().first?.isDraft == false)
    }

    @Test func testConnectionReturnsLoginAfterResolvingOwner() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("github.com/user", body: #"{"login":"alessandro"}"#)
        #expect(try await makeProvider(http).testConnection() == "alessandro")
        #expect(http.requests.contains { $0.url!.absoluteString.hasSuffix("users/acme") })
    }

    @Test func testConnectionReportsNoAccessForUnknownOwner() async {
        let http = MockHTTPClient()
        http.on("users/acme", status: 404, body: #"{"message":"Not Found"}"#)
        http.on("github.com/user", body: #"{"login":"alessandro"}"#)
        let provider = makeProvider(http)
        await #expect(throws: ProviderError.noAccess("acme")) { try await provider.testConnection() }
    }

    @Test func sendsBearerAndGitHubHeaders() async throws {
        let http = MockHTTPClient()
        http.on("github.com/user", body: #"{"login":"alessandro"}"#)
        #expect(try await makeProvider(http).currentUserId() == "alessandro")
        let request = try #require(http.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ghtok")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }

    @Test func listsOrgRepos() async throws {
        let http = MockHTTPClient()
        http.on("orgs/acme/repos", body: #"[{"full_name":"acme/web"},{"full_name":"acme/api"}]"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        #expect(try await makeProvider(http).listRepos() == ["acme/api", "acme/web"])
    }

    @Test func listsOwnReposIncludingPrivateViaUserEndpoint() async throws {
        let http = MockHTTPClient()
        http.on("user/repos", body: #"[{"full_name":"alessandro/secret"}]"#)
        http.on("users/alessandro", body: #"{"type":"User"}"#)
        http.on("github.com/user", body: #"{"login":"Alessandro"}"#)

        #expect(try await makeProvider(http, owner: "alessandro").listRepos() == ["alessandro/secret"])
        let reposURL = try #require(http.requests.last?.url?.absoluteString)
        #expect(reposURL.contains("affiliation=owner"))
    }

    @Test func rateLimitIsReported() async {
        let http = MockHTTPClient()
        http.on("users/acme", status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1760000600"], body: "{}")
        let provider = makeProvider(http)
        await #expect(throws: ProviderError.rateLimited(until: Date(timeIntervalSince1970: 1_760_000_600))) {
            try await provider.openPullRequests()
        }
    }

    @Test func paginatesSearchResults() async throws {
        let http = MockHTTPClient()
        let page1 = (1...100).map { item(number: $0) }.joined(separator: ",")
        http.on("page=2", body: #"{"total_count":101,"items":[\#(item(number: 101))]}"#)
        http.on("page=1", body: #"{"total_count":101,"items":[\#(page1)]}"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        #expect(try await makeProvider(http).openPullRequests().count == 101)
    }

    // MARK: - Tags en releases

    /// Eén repo in een GraphQL-antwoord: `refs` en `releases` als JSON-lijsten van nodes.
    func repoJSON(refs: [String], releases: [String] = [], refCount: Int? = nil, releaseCount: Int? = nil) -> String {
        #"{"refs":{"totalCount":\#(refCount ?? refs.count),"nodes":[\#(refs.joined(separator: ","))]},"#
            + #""releases":{"totalCount":\#(releaseCount ?? releases.count),"nodes":[\#(releases.joined(separator: ","))]}}"#
    }

    func graphQL(_ repos: [String?]) -> String {
        let fields = repos.enumerated().map { #""r\#($0.offset)":\#($0.element ?? "null")"# }
        return #"{"data":{\#(fields.joined(separator: ","))}}"#
    }

    func lightweightTag(_ name: String, date: String = "2026-08-01T10:00:00Z", author: String = #"{"name":"Jan Jansen","avatarUrl":"https://avatars.githubusercontent.com/u/e?email=jan","user":null}"#) -> String {
        #"{"name":"\#(name)","target":{"committedDate":"\#(date)","author":\#(author)}}"#
    }

    func release(_ tag: String, name: String?, login: String, prerelease: Bool = false, draft: Bool = false, id: String? = nil) -> String {
        let title = name.map { #""\#($0)""# } ?? "null"
        let releaseId = id ?? "RE_" + tag
        return #"{"id":"\#(releaseId)","tagName":"\#(tag)","name":\#(title),"isDraft":\#(draft),"isPrerelease":\#(prerelease),"#
            + #""publishedAt":"2026-11-02T13:31:28Z","updatedAt":"2026-11-02T13:31:28Z","#
            + #""url":"https://github.com/acme/api/releases/tag/\#(tag)","author":{"login":"\#(login)","avatarUrl":"https://avatars.githubusercontent.com/in/15368?v=4"}}"#
    }

    /// Zoals `v5.6.0-rc10` van FerroHEALTH/FerroEHR: een geannoteerde tag van een persoon, met een
    /// pre-release die `github-actions[bot]` publiceerde.
    let annotatedByPerson = #"""
    {"name":"v5.6.0-rc10","target":{
      "tagger":{"name":"Ruben Talstra","avatarUrl":"https://avatars.githubusercontent.com/u/14235001?v=4","date":"2026-11-02T13:54:42+01:00",
                "user":{"login":"rubentalstra","avatarUrl":"https://avatars.githubusercontent.com/u/14235001?u=x&v=4"}},
      "target":{"committedDate":"2026-11-02T12:50:57Z","author":{"name":"Ruben Talstra","avatarUrl":null,"user":{"login":"rubentalstra","avatarUrl":null}}}}}
    """#

    @Test func tagOfAPersonWithABotReleaseShowsThePersonAndThePrerelease() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: graphQL([repoJSON(
            refs: [annotatedByPerson],
            releases: [release("v5.6.0-rc10", name: "5.6.0-rc10", login: "github-actions[bot]", prerelease: true)]
        )]))

        let tag = try #require(try await makeProvider(http).tags(in: ["acme/api"]).tags.first)

        #expect(tag.authorName == "rubentalstra")
        #expect(tag.authorAvatarURL?.absoluteString == "https://avatars.githubusercontent.com/u/14235001?u=x&v=4")
        #expect(tag.release?.isPrerelease == true)
        #expect(tag.release?.title == "5.6.0-rc10")
        #expect(tag.release?.authorLogin == "github-actions[bot]")
        #expect(tag.releaseTitle == "5.6.0-rc10")
        #expect(tag.webURL.absoluteString == "https://github.com/acme/api/releases/tag/v5.6.0-rc10")
        #expect(tag.createdAt == DateParsing.parse("2026-11-02T12:54:42Z"))
        #expect(tag.accountId == fixedAccountId && tag.repo == "acme/api")
    }

    @Test func authorIsTheReleaseAuthorThenTheTaggerThenTheCommitAuthor() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: graphQL([repoJSON(
            refs: [lightweightTag("v3"), lightweightTag("v2"), lightweightTag("v1"), annotatedByPerson],
            releases: [
                release("v3", name: "Drie", login: "hubot", draft: true),
                release("v2", name: "Twee", login: "mona"),
            ]
        )]))

        let tags = try await makeProvider(http).tags(in: ["acme/api"]).tags
        let byName = Dictionary(uniqueKeysWithValues: tags.map { ($0.name, $0) })

        #expect(byName["v2"]?.authorName == "mona") // een mens publiceerde de release
        #expect(byName["v2"]?.release?.isPrerelease == false)
        #expect(byName["v2"]?.releaseTitle == "Twee")
        #expect(byName["v1"]?.authorName == "Jan Jansen") // lichte tag: de commit-auteur, zonder GitHub-account
        #expect(byName["v1"]?.release == nil)
        #expect(byName["v3"]?.release == nil) // concepten tellen niet
        #expect(byName["v3"]?.webURL.absoluteString == "https://github.com/acme/api/tree/v3")
        #expect(byName["v5.6.0-rc10"]?.authorName == "rubentalstra") // geannoteerd, zonder release: de tagger
    }

    @Test func requestAsksForTagsReleasesAndAuthorsOfEveryRepoWithAliases() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: graphQL([repoJSON(refs: [lightweightTag("v1")]), repoJSON(refs: [lightweightTag("v9")])]))

        let tags = try await makeProvider(http).tags(in: ["acme/api", "jane/web"]).tags

        #expect(tags.map(\.repo) == ["acme/api", "jane/web"])
        #expect(http.requests.count == 1)
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let variables = try #require(body["variables"] as? [String: String])
        #expect(variables == ["o0": "acme", "n0": "api", "o1": "jane", "n1": "web"])
        let query = try #require(body["query"] as? String)
        for field in ["r0: repository(owner: $o0, name: $n0)", "r1: repository(owner: $o1, name: $n1)",
                      "first: 100", "TAG_COMMIT_DATE", "releases(first: 20", "isPrerelease", "isDraft", "tagger", "author"] {
            #expect(query.contains(field), "\(field)")
        }
    }

    @Test func manyReposAreSplitIntoBatches() async throws {
        let http = MockHTTPClient()
        let repos = (0..<12).map { "acme/r\($0)" }
        http.on("api.github.com/graphql", body: graphQL(Array(repeating: repoJSON(refs: [lightweightTag("v1")]), count: 10)))

        let fetch = try await makeProvider(http).tags(in: repos)

        #expect(http.requests.count == 2)
        #expect(fetch.tags.count == 12)
        #expect(Set(fetch.fingerprints.keys) == Set(repos))
    }

    @Test func unchangedRepoCostsOneSmallRequestAndNoTags() async throws {
        let http = MockHTTPClient()
        let body = graphQL([repoJSON(refs: [lightweightTag("v2")], releases: [release("v2", name: nil, login: "mona")], refCount: 40, releaseCount: 3)])
        http.on("api.github.com/graphql", body: body)
        let provider = makeProvider(http)
        let first = try await provider.tags(in: ["acme/api"])
        let fingerprint = try #require(first.fingerprints["acme/api"])

        let second = try await provider.tags(in: ["acme/api"], unchanged: ["acme/api": fingerprint])

        #expect(second.tags.isEmpty)
        #expect(second.unchangedRepos == ["acme/api"])
        #expect(second.fingerprints["acme/api"] == fingerprint)
        #expect(http.requests.count == 2)
        let query = try #require(http.requests.last?.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["query"] as? String)
        #expect(query.contains("first: 1,") && query.contains("releases(first: 1,"))
    }

    @Test func changedRepoIsFetchedInFull() async throws {
        let http = MockHTTPClient()
        http.onSequence("api.github.com/graphql", bodies: [
            // De kleine vraag: een nieuwe release.
            graphQL([repoJSON(refs: [lightweightTag("v2")], releases: [release("v2", name: "Twee", login: "mona", id: "RE_new")])]),
            graphQL([repoJSON(refs: [lightweightTag("v2"), lightweightTag("v1")], releases: [release("v2", name: "Twee", login: "mona", id: "RE_new")])]),
        ])

        let fetch = try await makeProvider(http).tags(in: ["acme/api"], unchanged: ["acme/api": "oud"])

        #expect(http.requests.count == 2)
        #expect(fetch.unchangedRepos.isEmpty)
        #expect(fetch.tags.map(\.name) == ["v2", "v1"])
        #expect(fetch.tags.first?.release != nil)
        #expect(fetch.fingerprints["acme/api"] != "oud")
    }

    @Test func fingerprintChangesWithANewTagOrRelease() async throws {
        func fingerprint(_ body: String) async throws -> String? {
            let http = MockHTTPClient()
            http.on("api.github.com/graphql", body: body)
            return try await makeProvider(http).tags(in: ["acme/api"]).fingerprints["acme/api"]
        }
        let base = try await fingerprint(graphQL([repoJSON(refs: [lightweightTag("v1")])]))
        let newTag = try await fingerprint(graphQL([repoJSON(refs: [lightweightTag("v2"), lightweightTag("v1")])]))
        let newRelease = try await fingerprint(graphQL([repoJSON(refs: [lightweightTag("v1")], releases: [release("v1", name: nil, login: "mona")])]))
        let promoted = try await fingerprint(graphQL([repoJSON(refs: [lightweightTag("v1")], releases: [release("v1", name: nil, login: "mona", prerelease: true)])]))

        #expect(Set([base, newTag, newRelease, promoted]).count == 4)
    }

    @Test func datedTagsAreTheNewestTagsWithADate() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: graphQL([repoJSON(refs: [
            lightweightTag("v1", date: "2026-08-01T10:00:00Z"),
            annotatedByPerson,
            #"{"name":"tree","target":{}}"#,
            #"{"name":"gone","target":null}"#,
        ])]))

        let tags = try await makeProvider(http).datedTags(in: "acme/api", limit: 50)

        #expect(tags.map(\.name) == ["v5.6.0-rc10", "v1"])
        #expect(tags.allSatisfy { $0.repo == "acme/api" && $0.accountId == fixedAccountId })
        #expect(try await makeProvider(http).datedTags(in: "acme/api", limit: 1).map(\.name) == ["v5.6.0-rc10"])
    }

    @Test func `Tags without data and without a message say so in the chosen language`() async {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: "{}")
        let expected = String(localized: "GraphQL-antwoord zonder gegevens", bundle: .localizedGitHub)

        await #expect(throws: ProviderError.decoding(expected)) {
            try await makeProvider(http).datedTags(in: "acme/api", limit: 50)
        }
    }

    @Test func `Tags without data keep the message from GitHub`() async {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: #"{"errors":[{"type":"INTERNAL","message":"Something went wrong"}]}"#)

        await #expect(throws: ProviderError.decoding("GraphQL: Something went wrong")) {
            try await makeProvider(http).datedTags(in: "acme/api", limit: 50)
        }
    }

    @Test func datedTagsOfMissingRepoAreEmpty() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: #"{"data":{"r0":null},"errors":[{"type":"NOT_FOUND"}]}"#)

        #expect(try await makeProvider(http).datedTags(in: "acme/gone", limit: 50).isEmpty)
    }

    @Test func tagURLWithoutReleaseEncodesName() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: graphQL([repoJSON(refs: [lightweightTag("release/1.0"), lightweightTag("v1+b")])]))

        let tags = try await makeProvider(http).tags(in: ["acme/api"]).tags

        #expect(tags.map(\.webURL.absoluteString) == [
            "https://github.com/acme/api/tree/release%2F1.0",
            "https://github.com/acme/api/tree/v1%2Bb",
        ])
    }

    @Test func missingRepoYieldsNoTags() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", body: #"{"data":{"r0":null},"errors":[{"type":"NOT_FOUND","path":["r0"]}]}"#)

        let fetch = try await makeProvider(http).tags(in: ["acme/gone"])

        #expect(fetch.tags.isEmpty)
        #expect(fetch.unavailableRepos == ["acme/gone"])
    }

    @Test func forbiddenRepoIsSkippedOthersStillYieldTags() async throws {
        let http = MockHTTPClient()
        // SAML of geen rechten op één repo: GraphQL geeft daar null met een FORBIDDEN-fout.
        http.on("api.github.com/graphql", body: #"{"data":{"r0":null,"r1":\#(repoJSON(refs: [lightweightTag("v1")]))},"errors":[{"type":"FORBIDDEN","path":["r0"]}]}"#)

        let fetch = try await makeProvider(http).tags(in: ["acme/secret", "acme/api"])

        #expect(fetch.unavailableRepos == ["acme/secret"])
        #expect(fetch.tags.map(\.name) == ["v1"])
        #expect(fetch.tags.allSatisfy { $0.repo == "acme/api" })
    }

    @Test func forbiddenBatchMarksItsReposUnavailable() async throws {
        let http = MockHTTPClient()
        // 403 zonder rate-limit-headers (SSO, rechten, IP-allowlist) → .unauthorized.
        http.on("api.github.com/graphql", status: 403, body: #"{"message":"Resource protected by organization SAML enforcement"}"#)

        let fetch = try await makeProvider(http).tags(in: ["acme/secret", "acme/api"])

        #expect(fetch.tags.isEmpty)
        #expect(fetch.unavailableRepos == ["acme/secret", "acme/api"])
    }

    @Test func graphQLRateLimitThrowsRateLimitedUntilReset() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", headers: ["X-RateLimit-Reset": "1900000000"], body: #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#)

        await #expect(throws: ProviderError.rateLimited(until: Date(timeIntervalSince1970: 1_900_000_000))) {
            _ = try await makeProvider(http).tags(in: ["acme/api"])
        }
    }

    @Test func tagRequestFailureOtherThanNotFoundPropagates() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/graphql", status: 500, body: "{}")

        await #expect(throws: ProviderError.self) {
            _ = try await makeProvider(http).tags(in: ["acme/api"])
        }
    }

    func syncItem(number: Int, state: String, mergedAt: String?, closedAt: String? = nil) -> String {
        let closed = closedAt.map { #""\#($0)""# } ?? "null"
        let pr = mergedAt.map { #"{"merged_at":"\#($0)"}"# } ?? #"{"merged_at":null}"#
        return #"""
        {"number":\#(number),"title":"PR \#(number)","created_at":"2025-10-15T10:00:00Z","state":"\#(state)",
         "closed_at":\#(closed),"pull_request":\#(pr),
         "user":{"login":"octocat"},
         "html_url":"https://github.com/acme/web/pull/\#(number)",
         "repository_url":"https://api.github.com/repos/acme/web"}
        """#
    }

    func searchQuery(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    @Test func syncMapsStates() async throws {
        let http = MockHTTPClient()
        http.on("search/issues", body: #"""
        {"total_count":3,"items":[\#(syncItem(number: 1, state: "open", mergedAt: nil)),
        \#(syncItem(number: 2, state: "closed", mergedAt: "2025-10-16T09:00:00Z", closedAt: "2025-10-16T09:00:00Z")),
        \#(syncItem(number: 3, state: "closed", mergedAt: nil, closedAt: "2025-10-16T08:00:00Z"))]}
        """#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)

        let prs = try await makeProvider(http).pullRequests(updatedSince: nil, limit: 1000)

        #expect(prs.map(\.state) == [.open, .merged, .closed])
        #expect(prs[0].closedAt == nil)
        #expect(prs[1].closedAt == Date(timeIntervalSince1970: 1_760_605_200))
        #expect(prs[2].closedAt == Date(timeIntervalSince1970: 1_760_601_600))
    }

    @Test func syncQueryIncludesUpdatedSinceAndSort() async throws {
        let http = MockHTTPClient()
        http.on("search/issues", body: #"{"total_count":0,"items":[]}"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        let provider = makeProvider(http)

        _ = try await provider.pullRequests(updatedSince: Date.testStart, limit: 1000)
        let withSince = try #require(http.requests.last)
        #expect(searchQuery(withSince, "q") == "is:pr org:acme updated:>=2025-10-09T08:53:20Z")
        #expect(searchQuery(withSince, "sort") == "updated")
        #expect(searchQuery(withSince, "order") == "desc")

        _ = try await provider.pullRequests(updatedSince: nil, limit: 1000)
        let without = try #require(http.requests.last)
        #expect(searchQuery(without, "q") == "is:pr org:acme")
    }

    @Test func syncStopsAtLimit() async throws {
        let http = MockHTTPClient()
        let page = (1...100).map { syncItem(number: $0, state: "open", mergedAt: nil) }.joined(separator: ",")
        http.on("search/issues", body: #"{"total_count":300,"items":[\#(page)]}"#)
        http.on("users/acme", body: #"{"type":"Organization"}"#)

        let prs = try await makeProvider(http).pullRequests(updatedSince: nil, limit: 150)

        #expect(prs.count == 150)
        #expect(http.requests.filter { $0.url!.absoluteString.contains("search/issues") }.count == 2)
    }
}

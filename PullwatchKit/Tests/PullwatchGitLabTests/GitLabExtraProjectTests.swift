import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitLab
import PullwatchTestSupport

/// Losse projecten (`Account.extraRepos`) bij GitLab: de controle met één verzoek, lezen zonder
/// token als het token er niet bij mag, en per poll één vraag naar de merge requests per project.
@Suite struct GitLabExtraProjectTests {
    let api = "https://gitlab.com/api/v4/"
    let now = Date.testStart
    /// Een openbaar project in de vorm die gitlab.com zonder token geeft (minder velden).
    let cli = #"""
    {"id":34675721,"description":"GitLab CLI","name":"cli","name_with_namespace":"GitLab.org / cli",
     "path":"cli","path_with_namespace":"gitlab-org/cli","created_at":"2022-03-24T13:23:02.000Z",
     "default_branch":"main","web_url":"https://gitlab.com/gitlab-org/cli","visibility":"public",
     "namespace":{"id":9970,"name":"GitLab.org","path":"gitlab-org","kind":"group","full_path":"gitlab-org"}}
    """#
    let notFound = #"{"message":"404 Project Not Found"}"#

    func makeProvider(
        _ http: MockHTTPClient,
        owners: [String] = ["acme"],
        extras: [String] = ["gitlab-org/cli"],
        instance: URL? = nil,
        clock: TestClock? = nil
    ) -> GitLabProvider {
        let fixed = now
        let time: @Sendable () -> Date
        if let clock { time = { clock.now } } else { time = { fixed } }
        return GitLabProvider(
            accountId: fixedAccountId, owners: owners, extraRepos: extras, instanceURL: instance,
            tokenSource: StaticTokenSource(token: "glpat-secret"), http: http, now: time
        )
    }

    func urls(_ http: MockHTTPClient, authorized: Bool? = nil) -> [String] {
        http.requests
            .filter { authorized == nil || ($0.value(forHTTPHeaderField: "Authorization") != nil) == authorized }
            .compactMap { $0.url?.absoluteString }
    }

    /// De groep "acme" met één open merge request, en het project gitlab-org/cli dat alleen
    /// zonder token te lezen is.
    func publicCLI(_ http: MockHTTPClient, mergeRequests: String? = nil) {
        http.on("\(api)groups/acme?", body: GitLabFixtures.group)
        http.on("\(api)groups/acme/merge_requests", body: "[\(GitLabFixtures.mergeRequest(iid: 1))]")
        http.on("\(api)projects/34675721/merge_requests", authorized: false, headers: ["x-next-page": "2"], body: mergeRequests
            ?? "[\(GitLabFixtures.mergeRequest(iid: 4310, project: "gitlab-org/cli"))]")
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: true, status: 404, body: notFound)
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: false, body: cli)
    }

    // MARK: Controleren

    @Test func checkGivesThePathAsGitLabWritesIt() async throws {
        let http = MockHTTPClient()
        http.on("\(api)projects/Gitlab-Org%2FCLI", authorized: true, body: cli)
        let check = try await makeProvider(http, extras: []).checkRepository("Gitlab-Org/CLI")
        #expect(check == RepositoryCheck(name: "gitlab-org/cli"))
        #expect(urls(http) == ["\(api)projects/Gitlab-Org%2FCLI"])
    }

    @Test func aPublicProjectTheTokenCannotSeeIsReadWithoutSignIn() async throws {
        let http = MockHTTPClient()
        publicCLI(http)
        let check = try await makeProvider(http, extras: []).checkRepository("gitlab-org/cli")
        #expect(check == RepositoryCheck(name: "gitlab-org/cli", readWithoutSignIn: true))
        #expect(urls(http, authorized: true) == ["\(api)projects/gitlab-org%2Fcli"])
        #expect(urls(http, authorized: false) == ["\(api)projects/gitlab-org%2Fcli"])
    }

    @Test func aForbiddenTokenAlsoTriesWithoutSignIn() async throws {
        let http = MockHTTPClient()
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: true, status: 403, body: #"{"message":"403 Forbidden"}"#)
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: false, body: cli)
        #expect(try await makeProvider(http, extras: []).checkRepository("gitlab-org/cli").readWithoutSignIn)
    }

    @Test func aPrivateOrMissingProjectIsNoAccess() async throws {
        let http = MockHTTPClient()
        http.on("\(api)projects/acme%2Fsecret", status: 404, body: notFound)
        await #expect(throws: ProviderError.noAccess("acme/secret")) {
            try await makeProvider(http, extras: []).checkRepository("acme/secret")
        }
        #expect(urls(http).count == 2)
    }

    /// Een eigen server die zonder inloggen niets laat zien antwoordt 401: dat is niet te lezen,
    /// geen ongeldig token.
    @Test func aServerThatNeedsSignInIsDetectedNotAssumed() async throws {
        let http = MockHTTPClient()
        let server = URL(string: "https://code.example.com")!
        http.on("https://code.example.com/api/v4/projects/team%2Fapp", authorized: true, status: 404, body: notFound)
        http.on("https://code.example.com/api/v4/projects/team%2Fapp", authorized: false, status: 401, body: #"{"message":"401 Unauthorized"}"#)
        await #expect(throws: ProviderError.noAccess("team/app")) {
            try await makeProvider(http, extras: [], instance: server).checkRepository("team/app")
        }
        // Staat de server het wel toe, dan leest Pullwatch het project zonder token.
        let open = MockHTTPClient()
        open.on("https://code.example.com/api/v4/projects/team%2Fapp", authorized: true, status: 404, body: notFound)
        open.on("https://code.example.com/api/v4/projects/team%2Fapp", authorized: false, body: GitLabFixtures.project("team/app", id: 5))
        let check = try await makeProvider(open, extras: [], instance: server).checkRepository("team/app")
        #expect(check == RepositoryCheck(name: "team/app", readWithoutSignIn: true))
    }

    @Test func anInvalidTokenIsNeverMasked() async throws {
        let http = MockHTTPClient()
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: true, status: 401, body: #"{"message":"401 Unauthorized"}"#)
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: false, body: cli)
        await #expect(throws: ProviderError.unauthorized) {
            try await makeProvider(http, extras: []).checkRepository("gitlab-org/cli")
        }
        #expect(urls(http, authorized: false).isEmpty)
    }

    @Test func theLimitWithoutSignInSaysWhenToTryAgain() async throws {
        let http = MockHTTPClient()
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: true, status: 404, body: notFound)
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: false, status: 429, headers: [
            "RateLimit-Remaining": "0", "RateLimit-Reset": "1760000060",
        ], body: "Retry later")
        await #expect(throws: ProviderError.rateLimited(until: Date(timeIntervalSince1970: 1_760_000_060))) {
            try await makeProvider(http, extras: []).checkRepository("gitlab-org/cli")
        }
    }

    // MARK: Pollen

    @Test func oneMergeRequestRequestPerExtraProjectPerPoll() async throws {
        let http = MockHTTPClient()
        publicCLI(http)
        let provider = makeProvider(http)
        let first = try await provider.openPullRequests()
        #expect(first.map(\.repo).sorted() == ["acme/platform/api", "gitlab-org/cli"])
        let pr = try #require(first.first { $0.repo == "gitlab-org/cli" })
        #expect(pr.number == 4310)
        #expect(pr.webURL.absoluteString == "https://gitlab.com/gitlab-org/cli/-/merge_requests/4310")

        // Eén pagina, ook als GitLab er meer heeft (`x-next-page`), zonder token, op project-id.
        let extra = urls(http).filter { $0.contains("projects/34675721/merge_requests") }
        #expect(extra == ["\(api)projects/34675721/merge_requests?state=opened&order_by=updated_at&sort=desc&scope=all&per_page=100&page=1"])
        #expect(urls(http, authorized: false).allSatisfy { $0.contains("projects/") })

        // De volgende poll: niet opnieuw controleren, weer één vraag.
        let before = http.requests.count
        _ = try await provider.openPullRequests()
        let second = urls(http).dropFirst(before)
        #expect(second.filter { $0.contains("projects/") } == ["\(api)projects/34675721/merge_requests?state=opened&order_by=updated_at&sort=desc&scope=all&per_page=100&page=1"])
    }

    @Test func historyAsksTheExtraProjectWhatChangedSince() async throws {
        let http = MockHTTPClient()
        publicCLI(http, mergeRequests: "[\(GitLabFixtures.mergeRequest(iid: 4300, project: "gitlab-org/cli", state: "merged", mergedAt: "2025-10-17T09:00:00.000Z"))]")
        let since = Date(timeIntervalSince1970: 1_759_000_000)
        let prs = try await makeProvider(http).pullRequests(updatedSince: since, limit: 50)
        let merged = try #require(prs.first { $0.repo == "gitlab-org/cli" })
        #expect(merged.state == .merged)
        let extra = urls(http).filter { $0.contains("projects/34675721/merge_requests") }
        #expect(extra.count == 1)
        #expect(extra.first?.contains("updated_after=2025-09-27T19:06:40Z") == true)
        #expect(extra.first?.contains("order_by=updated_at&sort=desc") == true)
    }

    @Test func aProjectUnderAFollowedGroupCostsNothingExtra() async throws {
        let http = MockHTTPClient()
        http.on("\(api)groups/acme?", body: GitLabFixtures.group)
        http.on("\(api)groups/acme/merge_requests", body: "[\(GitLabFixtures.mergeRequest(iid: 1))]")
        let provider = makeProvider(http, extras: ["ACME/platform/api"])
        let prs = try await provider.openPullRequests()
        #expect(prs.count == 1)
        #expect(!urls(http).contains { $0.contains("projects/") })
        #expect(GitLabProvider.projectsOutside(owners: ["acme"], ["acme/x", "acmeco/y", "Other/z", "other/Z"]) == ["acmeco/y", "Other/z"])
    }

    @Test func extraProjectsAreListedAsGitLabWritesThem() async throws {
        let http = MockHTTPClient()
        http.on("\(api)groups/acme/projects", body: "[\(GitLabFixtures.project("acme/web", id: 3))]")
        http.on("\(api)groups/acme?", body: GitLabFixtures.group)
        http.on("\(api)projects/gone%2Fproject", status: 404, body: notFound)
        http.on("\(api)projects/Gitlab-org%2Fcli", authorized: true, body: cli)
        let repos = try await makeProvider(http, extras: ["Gitlab-org/cli", "gone/project"]).listRepos()
        #expect(repos == ["acme/web", "gitlab-org/cli"])
    }

    @Test func theLimitWithoutSignInSkipsTheProjectNotTheAccount() async throws {
        let http = MockHTTPClient()
        let clock = TestClock()
        http.on("\(api)groups/acme?", body: GitLabFixtures.group)
        http.on("\(api)groups/acme/merge_requests", body: "[\(GitLabFixtures.mergeRequest(iid: 1))]")
        http.on("\(api)projects/34675721/merge_requests", authorized: false, status: 429, headers: [
            "RateLimit-Remaining": "0", "RateLimit-Reset": "1760000060",
        ], body: "Retry later")
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: true, status: 404, body: notFound)
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: false, body: cli)
        let provider = makeProvider(http, clock: clock)
        #expect(try await provider.openPullRequests().map(\.repo) == ["acme/platform/api"])

        // Tot de reset gaat er niets zonder token meer uit.
        let before = urls(http, authorized: false).count
        #expect(try await provider.openPullRequests().count == 1)
        #expect(urls(http, authorized: false).count == before)
        clock.advance(61)
        _ = try await provider.openPullRequests()
        #expect(urls(http, authorized: false).count == before + 1)
    }

    @Test func aVanishedProjectIsSkippedAndCheckedAgain() async throws {
        let http = MockHTTPClient()
        http.on("\(api)groups/acme?", body: GitLabFixtures.group)
        http.on("\(api)groups/acme/merge_requests", body: "[]")
        http.on("\(api)projects/34675721/merge_requests", authorized: true, status: 404, body: notFound)
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: true, body: cli)
        let provider = makeProvider(http)
        #expect(try await provider.openPullRequests().isEmpty)
        _ = try await provider.openPullRequests()
        // Elke poll opnieuw gecontroleerd, omdat de lijst van merge requests 404 gaf.
        #expect(urls(http).filter { $0 == "\(api)projects/gitlab-org%2Fcli" }.count == 2)
    }

    @Test func mergeRequestsTurnedOffDoNotFailTheAccount() async throws {
        let http = MockHTTPClient()
        http.on("\(api)groups/acme?", body: GitLabFixtures.group)
        http.on("\(api)groups/acme/merge_requests", body: "[\(GitLabFixtures.mergeRequest(iid: 1))]")
        http.on("\(api)projects/34675721/merge_requests", authorized: true, status: 403, body: #"{"message":"403 Forbidden"}"#)
        http.on("\(api)projects/gitlab-org%2Fcli", authorized: true, body: cli)
        #expect(try await makeProvider(http).openPullRequests().count == 1)
    }

    // MARK: Tags, co-auteurs en bestanden

    @Test func tagsAndFilesOfAPublicProjectGoWithoutAToken() async throws {
        let http = MockHTTPClient()
        http.on("\(api)projects/gitlab-org%2Fcli/repository/tags", authorized: false, body: "[\(GitLabFixtures.tag("v1.0.0", created: nil, committed: "2025-10-01T10:00:00.000Z", author: "Jane", release: false))]")
        http.on("\(api)projects/gitlab-org%2Fcli/repository/tree", authorized: false, body: GitLabFixtures.tree([("go.mod", "blob")]))
        http.on("\(api)projects/gitlab-org%2Fcli/repository/files/go.mod/raw", authorized: false, body: "module gitlab.com/gitlab-org/cli")
        http.on("\(api)projects/gitlab-org%2Fcli/merge_requests/4310/commits", authorized: false, body: "[\(GitLabFixtures.commit(author: "Bob", email: "bob@example.com", message: "Fix"))]")
        publicCLI(http)
        let provider = makeProvider(http)
        let fetch = try await provider.tags(in: ["gitlab-org/cli"])
        #expect(fetch.tags.map(\.name) == ["v1.0.0"])
        #expect(fetch.tags.first?.repo == "gitlab-org/cli")
        #expect(try await provider.filePaths(in: "gitlab-org/cli", ref: nil) == ["go.mod"])
        #expect(try await provider.fileContent(in: "gitlab-org/cli", path: "go.mod", ref: nil).hasPrefix("module"))
        let pr = PullRequest.fixture(repo: "gitlab-org/cli", number: 4310, authorId: "alice", authorName: "alice")
        let coAuthors = try await provider.coAuthors(of: [pr])
        #expect(coAuthors[pr.dedupKey]?.map(\.name) == ["Bob"])
        // Alleen de controle ging met token.
        #expect(urls(http, authorized: true) == ["\(api)projects/gitlab-org%2Fcli"])
    }

    @Test func aMissingExtraProjectHasNoTagsAndCostsNoRequest() async throws {
        let http = MockHTTPClient()
        http.on("\(api)projects/gone%2Fproject", status: 404, body: notFound)
        let provider = makeProvider(http, extras: ["gone/project"])
        let fetch = try await provider.tags(in: ["gone/project"])
        #expect(fetch.unavailableRepos == ["gone/project"])
        #expect(!urls(http).contains { $0.contains("repository/tags") })
    }
}

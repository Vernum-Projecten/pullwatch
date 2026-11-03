import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

/// GitHub Enterprise Server (`<server>/api/v3`, `<server>/api/graphql`) en GHE.com
/// (`api.<naam>.ghe.com`): waar elk verzoek heen gaat, en wat zo'n server niet kent.
@Suite struct GitHubEnterpriseTests {
    static let server = URL(string: "https://github.example.com")!

    func makeProvider(_ http: MockHTTPClient, instance: URL? = server, owner: String = "acme") -> GitHubProvider {
        GitHubProvider(
            accountId: fixedAccountId, owner: owner, instanceURL: instance,
            tokenSource: StaticTokenSource(token: "ghes-token"), http: http
        )
    }

    var urls: (MockHTTPClient) -> [String] { { $0.requests.compactMap(\.url?.absoluteString) } }

    // MARK: - Adressen

    @Test func gitHubDotComKeepsItsAddresses() {
        for instance in [nil, URL(string: "https://github.com")] {
            let endpoints = GitHubEndpoints(instanceURL: instance)
            #expect(endpoints.flavor == .dotCom)
            #expect(endpoints.web.absoluteString == "https://github.com")
            #expect(endpoints.api.absoluteString == "https://api.github.com")
            #expect(endpoints.graphQL.absoluteString == "https://api.github.com/graphql")
            #expect(endpoints.cliHost == "github.com")
        }
    }

    @Test func enterpriseServerUsesApiV3AndApiGraphQL() {
        let endpoints = GitHubEndpoints(instanceURL: Self.server)
        #expect(endpoints.flavor == .server)
        #expect(endpoints.web.absoluteString == "https://github.example.com")
        #expect(endpoints.api.absoluteString == "https://github.example.com/api/v3")
        #expect(endpoints.graphQL.absoluteString == "https://github.example.com/api/graphql")
        #expect(endpoints.cliHost == "github.example.com")

        let withPort = GitHubEndpoints(instanceURL: URL(string: "https://git.example.com:8443"))
        #expect(withPort.api.absoluteString == "https://git.example.com:8443/api/v3")
        #expect(withPort.cliHost == "git.example.com:8443")
    }

    @Test func dataResidencyUsesTheApiSubdomain() {
        let endpoints = GitHubEndpoints(instanceURL: URL(string: "https://acme.ghe.com"))
        #expect(endpoints.flavor == .dataResidency)
        #expect(endpoints.web.absoluteString == "https://acme.ghe.com")
        #expect(endpoints.api.absoluteString == "https://api.acme.ghe.com")
        #expect(endpoints.graphQL.absoluteString == "https://api.acme.ghe.com/graphql")
        #expect(endpoints.cliHost == "acme.ghe.com")
        // ghe.com zelf of een dieper subdomein is geen eigen subdomein: dan een gewone server.
        #expect(GitHubEndpoints(instanceURL: URL(string: "https://git.acme.ghe.com")).flavor == .server)
    }

    @Test func gitHubDotComRequestsAreUnchanged() async throws {
        let http = MockHTTPClient()
        http.on("graphql", body: #"{"data":{"r0":null}}"#)
        http.on("/user", body: #"{"login":"me"}"#)
        let provider = GitHubProvider(accountId: fixedAccountId, owner: "acme", tokenSource: StaticTokenSource(token: "t"), http: http)
        _ = try await provider.currentUserId()
        _ = try await provider.tags(in: ["acme/web"])
        #expect(urls(http) == ["https://api.github.com/user", "https://api.github.com/graphql"])
    }

    // MARK: - Elk verzoek naar de server

    @Test func everyRESTCallGoesToTheServer() async throws {
        let http = MockHTTPClient()
        http.on("api/v3/user/repos", body: #"[{"full_name":"me/dotfiles"}]"#)
        http.on("api/v3/user/installations", body: #"{"total_count":0,"installations":[]}"#)
        http.on("api/v3/users/me", body: #"{"type":"User"}"#)
        http.on("api/v3/user", body: #"{"login":"me"}"#)
        http.on("api/v3/search/issues", body: #"""
        {"total_count":1,"items":[{"number":3,"title":"PR","created_at":"2025-10-15T10:00:00Z","state":"open",
         "user":{"login":"me"},"html_url":"https://github.example.com/me/dotfiles/pull/3",
         "repository_url":"https://github.example.com/api/v3/repos/me/dotfiles"}]}
        """#)
        http.on("api/v3/repos/me/dotfiles/git/trees/HEAD", body: #"{"tree":[{"path":"Package.swift","type":"blob"}]}"#)
        http.on("api/v3/repos/me/dotfiles/contents/Package.swift", body: "// swift-tools-version: 6.0")
        let provider = makeProvider(http, owner: "me")

        #expect(try await provider.testConnection() == "me")
        #expect(try await provider.listRepos() == ["me/dotfiles"])
        let open = try await provider.openPullRequests()
        #expect(open.first?.repo == "me/dotfiles")
        #expect(open.first?.webURL.absoluteString == "https://github.example.com/me/dotfiles/pull/3")
        #expect(try await provider.pullRequests(updatedSince: nil, limit: 10).count == 1)
        #expect(try await provider.filePaths(in: "me/dotfiles", ref: nil) == ["Package.swift"])
        #expect(try await provider.fileContent(in: "me/dotfiles", path: "Package.swift", ref: nil).hasPrefix("// swift-tools"))
        #expect(try await provider.installationOwners().isEmpty)

        #expect(urls(http).allSatisfy { $0.hasPrefix("https://github.example.com/api/v3/") }, "\(urls(http))")
        #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer ghes-token" })
    }

    @Test func tagsAndCoAuthorsUseTheServersGraphQL() async throws {
        let http = MockHTTPClient()
        http.onSequence("api/graphql", bodies: [
            #"""
            {"data":{"r0":{"refs":{"totalCount":1,"nodes":[{"name":"v1","target":{"committedDate":"2026-08-01T10:00:00Z","author":{"name":"Jan","avatarUrl":"https://github.example.com/avatars/u/2","user":null}}}]},
                           "releases":{"totalCount":0,"nodes":[]}}}}
            """#,
            #"{"data":{"pr0":{"pullRequest":{"commits":{"nodes":[]}}}}}"#,
        ])
        let provider = makeProvider(http)

        let tag = try #require(try await provider.tags(in: ["acme/web"]).tags.first)
        #expect(tag.webURL.absoluteString == "https://github.example.com/acme/web/tree/v1", "een link naar de server, niet naar github.com")
        #expect(tag.authorAvatarURL?.absoluteString == "https://github.example.com/avatars/u/2", "de foto van de server")
        _ = try await provider.coAuthors(of: [.fixture(repo: "acme/web", number: 1)])

        #expect(urls(http) == ["https://github.example.com/api/graphql", "https://github.example.com/api/graphql"])
    }

    @Test func dataResidencyCallsTheApiSubdomain() async throws {
        let http = MockHTTPClient()
        http.on("api.acme.ghe.com/graphql", body: #"{"data":{"r0":null}}"#)
        http.on("api.acme.ghe.com/user", body: #"{"login":"me"}"#)
        let provider = makeProvider(http, instance: URL(string: "https://acme.ghe.com"))
        _ = try await provider.currentUserId()
        _ = try await provider.tags(in: ["acme/web"])
        #expect(urls(http) == ["https://api.acme.ghe.com/user", "https://api.acme.ghe.com/graphql"])
    }

    // MARK: - Wat een server niet kent

    @Test func olderServerWithoutTheTagFieldsFallsBackToREST() async throws {
        let http = MockHTTPClient()
        http.on("api/graphql", body: #"""
        {"errors":[{"message":"Field 'isPrerelease' doesn't exist on type 'Release'","extensions":{"code":"undefinedField","typeName":"Release","fieldName":"isPrerelease"}}]}
        """#)
        http.on("api/v3/repos/acme/web/tags", body: #"[{"name":"v2","commit":{"sha":"b"}},{"name":"v1","commit":{"sha":"a"}}]"#)
        http.on("api/v3/repos/acme/web/releases", body: #"""
        [{"id":2,"tag_name":"v2","name":"Twee","draft":false,"prerelease":true,"published_at":"2026-10-01T10:00:00Z",
          "html_url":"https://github.example.com/acme/web/releases/tag/v2","author":{"login":"jan","avatar_url":"https://github.example.com/avatars/u/2"}}]
        """#)
        http.on("api/v3/repos/acme/gone/tags", status: 404, body: #"{"message":"Not Found"}"#)
        let provider = makeProvider(http)

        let fetch = try await provider.tags(in: ["acme/web", "acme/gone"])

        #expect(fetch.tags.map(\.name) == ["v2", "v1"])
        let release = try #require(fetch.tags.first?.release)
        #expect(release.isPrerelease)
        #expect(release.authorLogin == "jan")
        #expect(fetch.tags.first?.webURL.absoluteString == "https://github.example.com/acme/web/releases/tag/v2")
        #expect(fetch.tags.last?.webURL.absoluteString == "https://github.example.com/acme/web/tree/v1")
        #expect(fetch.unavailableRepos == ["acme/gone"])

        // De volgende keer meteen via REST, zonder eerst GraphQL te proberen.
        let before = urls(http).filter { $0.hasSuffix("api/graphql") }.count
        _ = try await provider.tags(in: ["acme/web"])
        #expect(urls(http).filter { $0.hasSuffix("api/graphql") }.count == before)
    }

    @Test func otherGraphQLErrorsStillFail() async {
        let http = MockHTTPClient()
        http.on("api/graphql", body: #"{"errors":[{"message":"Something went wrong"}]}"#)
        await #expect(throws: ProviderError.self) { try await makeProvider(http).tags(in: ["acme/web"]) }
    }

    @Test func serverWithoutCoAuthorFieldsGivesNoCoAuthors() async throws {
        let http = MockHTTPClient()
        http.on("api/graphql", body: #"{"errors":[{"message":"Field 'authors' doesn't exist on type 'Commit'","extensions":{"code":"undefinedField"}}]}"#)
        let pr = PullRequest.fixture(repo: "acme/web", number: 1)
        let found = try await makeProvider(http).coAuthors(of: [pr])
        #expect(found == [pr.dedupKey: []])
    }

    @Test func repositoryAdvisoriesAreNotAvailableOnAServer() async throws {
        let http = MockHTTPClient()
        http.on("code-scanning/alerts", status: 404, body: #"{"message":"Advanced Security must be enabled"}"#)
        http.on("secret-scanning/alerts", body: "[]")
        let scan = try #require(try await makeProvider(http).securityAlerts(in: "acme/web"))

        let advisories = try #require(scan.feeds.first { $0.kind == .repositoryAdvisories })
        #expect(advisories.availability == .notAvailable)
        #expect(scan.feeds.first { $0.kind == .codeScanning }?.availability == .notEnabled)
        #expect(scan.feeds.first { $0.kind == .codeScanning }?.link?.absoluteString
                == "https://github.example.com/acme/web/security/code-scanning")
        #expect(!urls(http).contains { $0.contains("security-advisories") }, "de server kent dit verzoek niet")
        #expect(urls(http).allSatisfy { $0.hasPrefix("https://github.example.com/api/v3/") })
    }

    @Test func enterpriseTokenNeverGoesToTheAdvisoryDatabase() async {
        #expect(await makeProvider(MockHTTPClient()).advisoryDatabaseToken() == nil)
        #expect(await makeProvider(MockHTTPClient(), instance: URL(string: "https://acme.ghe.com")).advisoryDatabaseToken() == nil)
        #expect(await makeProvider(MockHTTPClient(), instance: nil).advisoryDatabaseToken() == "ghes-token")
    }

    // MARK: - Losse repo's op de server

    func makeExtraProvider(_ http: MockHTTPClient, instance: URL?) -> GitHubProvider {
        GitHubProvider(
            accountId: fixedAccountId, owners: ["acme"], extraRepos: ["other/tool"], instanceURL: instance,
            tokenSource: StaticTokenSource(token: "ghes-token"), http: http
        )
    }

    @Test func extraReposAreCheckedOnTheServerWithTheToken() async throws {
        let http = MockHTTPClient()
        http.on("api/v3/repos/other/tool", body: #"{"full_name":"Other/Tool"}"#)
        let check = try await makeExtraProvider(http, instance: Self.server).checkRepository("other/tool")
        #expect(check.name == "Other/Tool")
        #expect(urls(http) == ["https://github.example.com/api/v3/repos/other/tool"])
    }

    @Test func noAnonymousFallbackOnAServerOrGHECom() async {
        for instance in [Self.server, URL(string: "https://acme.ghe.com")!] {
            let http = MockHTTPClient()
            http.on("repos/other/tool", status: 404, body: #"{"message":"Not Found"}"#)
            await #expect(throws: ProviderError.noAccess("other/tool")) {
                try await makeExtraProvider(http, instance: instance).checkRepository("other/tool")
            }
            #expect(http.requests.count == 1, "geen tweede verzoek zonder token")
            #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer ghes-token" })
        }
    }

    @Test func gitHubDotComKeepsTheAnonymousFallback() async throws {
        let http = MockHTTPClient()
        http.on("api.github.com/repos/other/tool", authorized: true, status: 404, body: #"{"message":"Not Found"}"#)
        http.on("api.github.com/repos/other/tool", authorized: false, body: #"{"full_name":"other/tool"}"#)
        let check = try await makeExtraProvider(http, instance: nil).checkRepository("other/tool")
        #expect(check.readWithoutSignIn)
    }

    @Test func permissionLinksPointToTheServer() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        http.on("code-scanning/alerts", status: 403, body: #"{"message":"Resource not accessible by personal access token"}"#)
        http.on("secret-scanning/alerts", body: "[]")
        let scan = try #require(try await makeProvider(http).securityAlerts(in: "acme/web"))
        let code = try #require(scan.feeds.first { $0.kind == .codeScanning })
        #expect(code.availability == .needsPermission)
        #expect(code.link?.absoluteString == "https://github.example.com/organizations/acme/settings/installations")
    }
}

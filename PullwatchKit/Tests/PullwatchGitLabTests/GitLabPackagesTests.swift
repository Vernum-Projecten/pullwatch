import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitLab
import PullwatchTestSupport

/// De eigen packages in GitLab: het pakketregister en de container registry van de gevolgde
/// projecten, per groep één lijst, per project waar dat moet, en een 401 of 403 als
/// `.needsPermission`. De antwoorden zijn ingekorte echte antwoorden van gitlab.com
/// (`/groups/9970/packages`, `/projects/278964/registry/repositories`, de tags van een image).
@Suite struct GitLabPackagesTests {
    let api = "https://gitlab.com/api/v4/"

    /// Eén regel uit `/groups/:id/packages` (bij een project zonder `project_path`).
    func row(
        _ name: String, version: String, type: String = "npm", project: String? = "acme/web", status: String = "default",
        id: Int = 75303154, created: String = "2026-11-04T14:07:42.890Z", ref: String? = nil, tag: Bool = false
    ) -> String {
        let projectFields = project.map { #""project_id":278964,"project_path":"\#($0)","# } ?? ""
        let pipeline = ref.map { ref in
            #"""
            {"id":3027356417,"iid":6748160,"project_id":278964,"sha":"add44d83","ref":"\#(ref)","tag":\#(tag),"status":"success",
             "source":"push","created_at":"2026-11-04T13:48:06.081Z","web_url":"https://gitlab.com/\#(project ?? "acme/web")/-/pipelines/3027356417",
             "user":{"id":32707,"username":"ross","name":"Ross","state":"active"}}
            """#
        } ?? "null"
        return #"""
        {"id":\#(id),"name":"\#(name)","version":"\#(version)","package_type":"\#(type)","status":"\#(status)",
         "_links":{"web_path":"/\#(project ?? "acme/web")/-/packages/\#(id)"},"created_at":"\#(created)",
         "last_downloaded_at":null,"creator_id":32707,\#(projectFields)"tags":[],"pipeline":\#(pipeline),"pipelines":[]}
        """#
    }

    /// Eén image uit `/…/registry/repositories`.
    func image(id: Int, path: String) -> String {
        let name = path.split(separator: "/").count > 2 ? String(path.split(separator: "/").last!) : ""
        return #"""
        {"id":\#(id),"name":"\#(name)","path":"\#(path)","project_id":278964,"location":"registry.gitlab.com/\#(path)",
         "created_at":"2022-12-15T20:48:11.037Z","cleanup_policy_started_at":null,"status":null}
        """#
    }

    func tag(_ name: String, image path: String = "acme/web") -> String {
        #"{"name":"\#(name)","path":"\#(path):\#(name)","location":"registry.gitlab.com/\#(path):\#(name)"}"#
    }

    func tagDetail(_ name: String, created: String, digest: String? = nil) -> String {
        let digest = digest ?? "sha256:\(name)"
        return #"""
        {"name":"\#(name)","path":"acme/web:\#(name)","location":"registry.gitlab.com/acme/web:\#(name)",
         "revision":"c3490dcf","short_revision":"c3490dcf","digest":"\#(digest)","created_at":"\#(created)","total_size":2818413}
        """#
    }

    func list(_ items: String...) -> String {
        "[" + items.joined(separator: ",") + "]"
    }

    func makeProvider(_ http: MockHTTPClient, owners: [String] = ["acme"], extras: [String] = [], instance: URL? = nil) -> GitLabProvider {
        GitLabProvider(
            accountId: fixedAccountId, owners: owners, extraRepos: extras, instanceURL: instance,
            tokenSource: StaticTokenSource(token: "glpat-secret"), http: http, now: { Date.testStart }
        )
    }

    func group(_ http: MockHTTPClient, base: String? = nil) {
        http.on("\(base ?? api)groups/acme?", body: GitLabFixtures.group)
    }

    func urls(_ http: MockHTTPClient) -> [String] {
        http.requests.compactMap(\.url?.absoluteString)
    }

    // MARK: - Pakketregister

    @Test func `Lists the packages of a followed group once, grouped by name with their pipeline`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/registry/repositories", body: "[]")
        http.on("groups/acme/packages", body: list(
            row("@acme/ui", version: "2.3.0", id: 3, created: "2026-11-04T10:00:00.000Z", ref: "v2.3.0", tag: true),
            row("com/acme/core", version: "1.0.0", type: "maven", project: "acme/platform/api", id: 2, created: "2026-11-03T10:00:00.000Z"),
            row("@acme/ui", version: "2.2.0", id: 1, created: "2026-10-01T10:00:00.000Z", ref: "main"),
            row("@acme/other", version: "1.0.0", project: "acme/not-followed", id: 4),
            row("@acme/ui", version: "2.4.0-rc", status: "processing", id: 5)
        ))

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web", "acme/platform/api"])

        #expect(result.packages.map(\.name) == ["@acme/ui", "com/acme/core"])
        let ui = try #require(result.packages.first)
        #expect(ui.type == .npm)
        #expect(ui.owner == "acme")
        #expect(ui.repository == "acme/web")
        #expect(ui.accountId == fixedAccountId)
        #expect(ui.latestVersion == "2.3.0")
        #expect(ui.publishedAt == DateParsing.parse("2026-11-04T10:00:00.000Z"))
        #expect(ui.versions.map(\.version) == ["2.3.0", "2.2.0"], "een versie in verwerking telt niet")
        #expect(ui.versions.first?.tag == "v2.3.0")
        #expect(ui.versions.first?.runURL?.absoluteString == "https://gitlab.com/acme/web/-/pipelines/3027356417")
        #expect(ui.versions.last?.tag == nil, "main is een branch, geen tag")
        #expect(ui.versions.last?.runURL != nil)
        #expect(ui.webURL?.absoluteString == "https://gitlab.com/acme/web/-/packages/3")
        let core = try #require(result.packages.last)
        #expect(core.type == .maven)
        #expect(core.owner == "acme/platform")
        #expect(core.repository == "acme/platform/api")
        #expect(core.id == "acme/platform/maven/com/acme/core")
        #expect(!urls(http).contains { $0.contains("/projects/") }, "alles kwam uit de lijst van de groep")
        #expect(urls(http).contains("\(api)groups/acme/packages?order_by=created_at&sort=desc&per_page=100&page=1"))
    }

    @Test func `The stable release stays behind many newer pre-releases`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/registry/repositories", body: "[]")
        let betas = (1...12).reversed().map { row("@acme/ui", version: "3.0.0-beta.\($0)", id: 100 + $0, created: "2026-10-\(10 + $0)T10:00:00.000Z") }
        let rows = betas + [row("@acme/ui", version: "2.9.0", id: 1, created: "2026-09-01T10:00:00.000Z")]
        http.on("groups/acme/packages", body: "[\(rows.joined(separator: ","))]")

        let ui = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(ui.versions.count == PublishedPackage.recentVersionLimit)
        #expect(ui.versions.first?.version == "3.0.0-beta.12")
        #expect(ui.versions.last?.version == "2.9.0")
        #expect(ui.releasedVersion == "2.9.0")
        #expect(ui.newestPrerelease == "3.0.0-beta.12")
    }

    @Test func `Follows X-Next-Page through the packages of a group`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/registry/repositories", body: "[]")
        http.on("groups/acme/packages?order_by=created_at&sort=desc&per_page=100&page=2", body: "[\(row("@acme/old", version: "0.1.0", id: 1))]")
        http.on("groups/acme/packages?", headers: ["x-next-page": "2", "x-page": "1"], body: "[\(row("@acme/ui", version: "2.3.0", id: 2))]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.map(\.name) == ["@acme/ui", "@acme/old"])
    }

    @Test func `Follows a Link header on the same server only`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/registry/repositories", body: "[]")
        http.on("id_after=9", headers: ["Link": #"<https://evil.example.com/api/v4/groups/acme/packages?id_after=1>; rel="next""#],
                body: "[\(row("@acme/old", version: "0.1.0", id: 1))]")
        http.on("groups/acme/packages?", headers: ["Link": #"<https://gitlab.com/api/v4/groups/acme/packages?id_after=9>; rel="next""#],
                body: "[\(row("@acme/ui", version: "2.3.0", id: 2))]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.map(\.name) == ["@acme/ui", "@acme/old"])
        #expect(!urls(http).contains { $0.contains("evil.example.com") })
    }

    @Test func `Asks a project itself when the list of its group was too long`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/registry/repositories", body: "[]")
        http.on("projects/acme%2Fplatform%2Fapi/packages", body: "[\(row("com/acme/core", version: "1.0.0", type: "maven", project: nil))]")
        http.on("projects/acme%2Fplatform%2Fapi/registry/repositories", body: "[]")
        http.on("groups/acme/packages?", headers: ["x-next-page": "2"], body: "[\(row("@acme/ui", version: "2.3.0"))]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web", "acme/platform/api"])

        let groupPages = urls(http).filter { $0.contains("groups/acme/packages") }
        #expect(groupPages.count == GitLabProvider.groupPackagePages)
        #expect(urls(http).contains { $0.contains("projects/acme%2Fplatform%2Fapi/packages") })
        #expect(!urls(http).contains { $0.contains("projects/acme%2Fweb/packages") }, "acme/web had al regels")
        #expect(Set(result.packages.map(\.name)) == ["@acme/ui", "com/acme/core"])
        let core = try #require(result.packages.first { $0.name == "com/acme/core" })
        #expect(core.repository == "acme/platform/api")
    }

    @Test func `Asks each project of a user`() async throws {
        let http = MockHTTPClient()
        http.on("groups/jdoe?", status: 404, body: #"{"message":"404 Group Not Found"}"#)
        http.on("users?username=jdoe", body: GitLabFixtures.users("jdoe", id: 42))
        http.on("projects/jdoe%2Ftool/packages", body: "[\(row("tool", version: "1.0.0", type: "pypi", project: nil))]")
        http.on("projects/jdoe%2Ftool/registry/repositories", body: "[]")

        let result = try await makeProvider(http, owners: ["jdoe"]).publishedPackages(followedRepos: ["jdoe/tool"])

        let tool = try #require(result.packages.first)
        #expect(tool.type == .pyPI)
        #expect(tool.owner == "jdoe")
        #expect(tool.repository == "jdoe/tool")
        #expect(urls(http).contains("\(api)projects/jdoe%2Ftool/packages?order_by=created_at&sort=desc&per_page=100&page=1"))
    }

    @Test func `Reads a public extra project without a token when the token cannot`() async throws {
        let http = MockHTTPClient()
        http.on("projects/gitlab-org%2Fcli/packages", authorized: false, body: "[\(row("glab", version: "1.50.0", type: "generic", project: nil))]")
        http.on("projects/gitlab-org%2Fcli/registry/repositories", authorized: false, body: "[]")
        http.on("projects/gitlab-org%2Fcli", authorized: true, status: 404, body: #"{"message":"404 Project Not Found"}"#)
        http.on("projects/gitlab-org%2Fcli", authorized: false, body: #"{"id":34675721,"path_with_namespace":"gitlab-org/cli"}"#)

        let result = try await makeProvider(http, owners: [], extras: ["gitlab-org/cli"]).publishedPackages(followedRepos: ["gitlab-org/cli"])

        #expect(result.packages.map(\.name) == ["glab"])
        let listing = try #require(http.requests.first { $0.url?.absoluteString.contains("/packages?") == true })
        #expect(listing.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func `Self-managed servers use their own address`() async throws {
        let base = "https://git.example.com/gitlab/api/v4/"
        let http = MockHTTPClient()
        group(http, base: base)
        http.on("\(base)groups/acme/registry/repositories", body: "[]")
        http.on("\(base)groups/acme/packages", body: "[\(row("@acme/ui", version: "2.3.0", id: 7))]")

        let provider = makeProvider(http, instance: URL(string: "https://git.example.com/gitlab"))
        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.first?.webURL?.absoluteString == "https://git.example.com/gitlab/acme/web/-/packages/7")
        #expect(urls(http).allSatisfy { $0.hasPrefix(base) })
    }

    // MARK: - Container registry

    @Test func `Lists the images of followed projects with their newest tags`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/packages", body: "[]")
        http.on("repositories/5/tags/1.4.0", body: tagDetail("1.4.0", created: "2026-11-01T16:49:51.272+00:00", digest: "sha256:c3490dcf10ffb653"))
        http.on("repositories/5/tags/latest", body: tagDetail("latest", created: "2026-11-01T16:49:51.272+00:00", digest: "sha256:c3490dcf10ffb653"))
        http.on("repositories/5/tags?", body: list(tag("latest"), tag("1.4.0"), tag("1.3.0")))
        http.on("repositories/6/tags?", body: "[]")
        http.on("groups/acme/registry/repositories", body: list(image(id: 5, path: "acme/web"), image(id: 6, path: "acme/web/worker"), image(id: 7, path: "acme/other")))

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.map(\.name) == ["acme/web", "acme/web/worker"], "acme/other wordt niet gevolgd")
        let web = try #require(result.packages.first)
        #expect(web.type == .container)
        #expect(web.repository == "acme/web")
        #expect(web.owner == "acme")
        #expect(web.versions.map(\.version) == ["1.4.0", "1.3.0"], "latest zegt niets over de versie")
        #expect(web.latestVersion == "1.4.0")
        #expect(web.latestTag == .onLatestVersion, "dezelfde digest")
        #expect(web.versions.map(\.isLatestTag) == [true, false])
        #expect(web.publishedAt == DateParsing.parse("2026-11-01T16:49:51.272+00:00"))
        #expect(web.versions.last?.publishedAt == nil)
        #expect(web.webURL?.absoluteString == "https://gitlab.com/acme/web/container_registry/5")
        #expect(result.packages.last?.repository == "acme/web")
        #expect(result.packages.last?.versions.isEmpty == true)
        #expect(urls(http).contains("\(api)projects/acme%2Fweb/registry/repositories/5/tags?pagination=keyset&order_by=published_at&sort=desc&per_page=100"))
        #expect(urls(http).filter { $0.contains("/tags/") }.count == 2, "alleen de nieuwste versie en latest in detail")
    }

    @Test func `Sorts tags by their details when the server cannot sort them`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/packages", body: "[]")
        http.on("tags/1.10.0", body: tagDetail("1.10.0", created: "2026-10-01T10:00:00.000+00:00"))
        http.on("tags/1.9.0", body: tagDetail("1.9.0", created: "2026-10-15T10:00:00.000+00:00"))
        http.on("tags?pagination=keyset", status: 400, body: #"{"message":"400 Bad request - keyset pagination is not supported"}"#)
        http.on("repositories/5/tags?per_page=100", body: list(tag("1.9.0"), tag("1.10.0"), tag("latest")))
        http.on("groups/acme/registry/repositories", body: "[\(image(id: 5, path: "acme/web"))]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        let web = try #require(result.packages.first)
        #expect(web.versions.map(\.version) == ["1.9.0", "1.10.0"], "nieuwste eerst, op datum")
        #expect(web.latestVersion == "1.10.0", "de hoogste versie, niet de nieuwste datum")
        #expect(web.publishedAt == DateParsing.parse("2026-10-01T10:00:00.000+00:00"), "de datum van die versie")
    }

    /// Hoe het lezen van de tags van een image mislukt (#215).
    enum TagsFailure: String, CaseIterable, Sendable {
        case serverError, timeout, undecodable
    }

    @Test(arguments: TagsFailure.allCases)
    func `Tags that cannot be read mark the image as failed, not as untagged`(_ failure: TagsFailure) async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/packages", body: "[]")
        switch failure {
        case .serverError: http.on("repositories/5/tags?", status: 502, body: #"{"message":"502 Bad Gateway"}"#)
        case .timeout: http.fail("repositories/5/tags?", with: ProviderError.timeout(command: "gitlab.com"))
        case .undecodable: http.on("repositories/5/tags?", body: #"{"unexpected":"object"}"#)
        }
        http.on("groups/acme/registry/repositories", body: "[\(image(id: 5, path: "acme/web"))]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        let web = try #require(result.packages.first)
        #expect(web.versionsReadFailed)
        #expect(web.latestVersion == nil)
    }

    @Test func `Keeps latest when it is the only tag`() {
        let only = ContainerVersions(images: GitLabProvider.images([("latest", nil, nil)], link: nil))
        #expect(only.latestVersion == "latest")
        #expect(only.latestKind == .floatingTag)
        #expect(ContainerVersions(images: GitLabProvider.images([("latest", nil, nil), ("1.0", nil, nil)], link: nil)).latestVersion == "1.0")
    }

    @Test func `Reads the version among commit, signature and branch tags`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/packages", body: "[]")
        http.on("repositories/5/tags/0.0.17", body: tagDetail("0.0.17", created: "2026-11-04T11:43:07.000+00:00", digest: "sha256:f889"))
        http.on("repositories/5/tags/latest", body: tagDetail("latest", created: "2026-11-04T15:32:46.000+00:00", digest: "sha256:aa01"))
        http.on("repositories/5/tags?", body: list(
            tag("sha256-6ae52104050e88a57d380b6d61a14db91ba985bb08854faac4daa6d1f17d8c0a.sig"), tag("latest"), tag("main"),
            tag("466930c1"), tag("sha-466930c"), tag("artifacthub.io"), tag("0.0.17"), tag("0.0"), tag("0.0.15")
        ))
        http.on("groups/acme/registry/repositories", body: "[\(image(id: 5, path: "acme/web"))]")

        let web = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(web.latestVersion == "0.0.17")
        #expect(web.latestKind == .version)
        #expect(web.publishedAt == DateParsing.parse("2026-11-04T11:43:07.000+00:00"))
        #expect(web.versions.map(\.version) == ["0.0.17", "0.0", "0.0.15"])
        #expect(web.latestTag == .unversionedBuild, "latest staat op een nieuwere build van main")
    }

    @Test func `An image with only branch and commit tags shows its newest branch`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/packages", body: "[]")
        http.on("repositories/5/tags/main", body: tagDetail("main", created: "2026-11-04T15:32:46.000+00:00"))
        http.on("repositories/5/tags?", body: list(tag("sha-466930c"), tag("main"), tag("f83df34cc968f5e0f916834508336c8eeb4c9e41")))
        http.on("groups/acme/registry/repositories", body: "[\(image(id: 5, path: "acme/web"))]")

        let web = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(web.latestVersion == "main")
        #expect(web.latestKind == .floatingTag)
        #expect(web.versions.isEmpty)
        #expect(web.publishedAt == DateParsing.parse("2026-11-04T15:32:46.000+00:00"))
    }

    // MARK: - Rechten en lege registers

    enum Denial: String, CaseIterable {
        case unauthorizedGroup, forbiddenGroup, insufficientScopeProject
    }

    @Test(arguments: Denial.allCases)
    func `A missing read_api becomes needsPermission`(denial: Denial) async throws {
        let http = MockHTTPClient()
        let scope = #"{"error":"insufficient_scope","error_description":"The request requires higher privileges than provided by the access token.","scope":"api read_api"}"#
        switch denial {
        case .unauthorizedGroup:
            group(http)
            http.on("groups/acme/packages", status: 401, body: #"{"message":"401 Unauthorized"}"#)
        case .forbiddenGroup:
            group(http)
            http.on("groups/acme/packages", status: 403, body: #"{"message":"403 Forbidden"}"#)
        case .insufficientScopeProject:
            http.on("groups/jdoe?", status: 404, body: "{}")
            http.on("users?username=jdoe", body: GitLabFixtures.users("jdoe", id: 42))
            http.on("projects/jdoe%2Ftool/packages", status: 403, body: scope)
        }
        let owner = denial == .insufficientScopeProject ? "jdoe" : "acme"

        let result = try await makeProvider(http, owners: [owner]).publishedPackages(followedRepos: ["\(owner)/tool"])

        #expect(result == .needsPermission(reason: PackagesPermission.gitLabReadAPI))
        #expect(PackagesPermission.gitLabReadAPI.contains("read_api"))
    }

    @Test(arguments: [403, 404])
    func `A project without a readable registry is empty`(status: Int) async throws {
        let http = MockHTTPClient()
        http.on("groups/jdoe?", status: 404, body: "{}")
        http.on("users?username=jdoe", body: GitLabFixtures.users("jdoe", id: 42))
        http.on("projects/jdoe%2Ftool/", status: status, body: #"{"message":"\#(status)"}"#)

        let result = try await makeProvider(http, owners: ["jdoe"]).publishedPackages(followedRepos: ["jdoe/tool"])

        #expect(result == .packages([]))
    }

    @Test func `A group with no followed project is not asked`() async throws {
        let http = MockHTTPClient()
        group(http)

        let result = try await makeProvider(http).publishedPackages(followedRepos: [])

        #expect(result == .packages([]))
        #expect(!urls(http).contains { $0.contains("packages") || $0.contains("registry") })
    }

    @Test func `A rate limit stays an error`() async throws {
        let http = MockHTTPClient()
        group(http)
        http.on("groups/acme/packages", status: 429, headers: ["Retry-After": "30"], body: "Retry later")

        await #expect(throws: ProviderError.rateLimited(until: Date.testStart + 30)) {
            try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])
        }
    }
}

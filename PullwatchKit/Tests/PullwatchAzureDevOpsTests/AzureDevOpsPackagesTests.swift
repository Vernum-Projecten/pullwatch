import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

/// De eigen packages in Azure Artifacts: de feeds van de organisatie en van de gevolgde projecten,
/// per feed de packages met hun nieuwste versie, zonder wat uit een upstream komt, en een 401 of
/// 403 als `.needsPermission`. De antwoorden volgen de vorm van Feed Management - Get Feeds en
/// Artifact Details - Get Packages (REST 7.1), ingekort.
@Suite struct AzureDevOpsPackagesTests {
    let feeds = "https://feeds.dev.azure.com/acme/"

    func feed(_ name: String, id: String, project: String? = nil, deleted: Bool = false) -> String {
        let projectField = project.map { #"{"id":"7f3b1c2e-0000-4000-8000-000000000001","name":"\#($0)","visibility":"private"}"# } ?? "null"
        return #"""
        {"id":"\#(id)","name":"\#(name)","fullyQualifiedName":"\#(name)","fullyQualifiedId":"\#(id)","project":\#(projectField),
         "url":"https://feeds.dev.azure.com/acme/_apis/Packaging/Feeds/\#(id)","upstreamEnabled":true,"hideDeletedPackageVersions":true,
         "deletedDate":\#(deleted ? #""2026-01-01T00:00:00Z""# : "null"),"capabilities":"defaultCapabilities","badgesEnabled":false}
        """#
    }

    func package(
        _ name: String, protocolType: String = "Npm", version: String = "2.3.0", upstream: Bool = false,
        published: String = "2026-10-30T21:59:01.1234567Z"
    ) -> String {
        let upstreamField = upstream ? #""directUpstreamSourceId":"b3a6c0de-0000-4000-8000-000000000009","# : ""
        return #"""
        {"id":"0b4d1e5f-0000-4000-8000-000000000002","normalizedName":"\#(name.lowercased())","name":"\#(name)",
         "protocolType":"\#(protocolType)","url":"https://feeds.dev.azure.com/acme/_apis/Packaging/Feeds/f1/Packages/0b4d",
         "versions":[{"id":"9c1e0000-0000-4000-8000-000000000003","normalizedVersion":"\#(version)","version":"\#(version)",
           "isLatest":true,"isListed":true,"storageId":"ABC","views":[{"id":"v1","name":"Local","url":null,"type":"implicit"}],
           \#(upstreamField)"publishDate":"\#(published)"}],"_links":{}}
        """#
    }

    func list(_ items: String...) -> String {
        list(items)
    }

    func list(_ items: [String]) -> String {
        #"{"count":\#(items.count),"value":["# + items.joined(separator: ",") + "]}"
    }

    func urls(_ http: MockHTTPClient) -> [String] {
        http.requests.compactMap(\.url?.absoluteString)
    }

    // MARK: - Feeds en packages

    @Test func `Lists the packages of the organization's feeds and of followed projects`() async throws {
        let http = MockHTTPClient()
        http.on("Feeds/f-org/packages", body: list(package("@acme/ui"), package("left-pad", version: "1.3.0", upstream: true)))
        http.on("Feeds/f-web/packages", body: list(package("Acme.Core", protocolType: "NuGet", version: "4.1.0")))
        http.on("\(feeds)Web/_apis/packaging/feeds", body: list(feed("web-feed", id: "f-web", project: "Web")))
        http.on("\(feeds)_apis/packaging/feeds", body: list(
            feed("shared", id: "f-org"), feed("web-feed", id: "f-web", project: "Web"),
            feed("other", id: "f-other", project: "Other"), feed("old", id: "f-old", deleted: true)
        ))

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["Web/site", "Web/api"])

        #expect(result.packages.map(\.name) == ["@acme/ui", "Acme.Core"], "left-pad komt uit een upstream")
        let ui = try #require(result.packages.first)
        #expect(ui.type == .npm)
        #expect(ui.owner == "acme", "een feed van de organisatie")
        #expect(ui.repository == nil)
        #expect(ui.accountId == fixedAccountId)
        #expect(ui.latestVersion == "2.3.0")
        #expect(ui.publishedAt == DateParsing.parse("2026-10-30T21:59:01.1234567Z"))
        #expect(ui.webURL?.absoluteString == "https://dev.azure.com/acme/_artifacts/feed/shared/Npm/@acme%2Fui/overview/2.3.0")
        let core = try #require(result.packages.last)
        #expect(core.type == .nuGet)
        #expect(core.owner == "Web", "een feed van een project staat onder dat project")
        #expect(core.webURL?.absoluteString == "https://dev.azure.com/acme/Web/_artifacts/feed/web-feed/NuGet/Acme.Core/overview/4.1.0")

        #expect(urls(http).contains("\(feeds)_apis/packaging/feeds?api-version=7.1"))
        #expect(urls(http).filter { $0.contains("/_apis/packaging/feeds") }.count == 2, "de organisatie en het project Web, één keer")
        #expect(urls(http).contains("\(feeds)Web/_apis/packaging/Feeds/f-web/packages?includeUrls=false&$top=100&$skip=0&api-version=7.1"))
        #expect(!urls(http).contains { $0.contains("f-other") || $0.contains("f-old") })
    }

    @Test func `Pages through a feed with skip`() async throws {
        let http = MockHTTPClient()
        let full = (0..<100).map { package("pkg-\($0)") }
        http.on("$skip=100", body: list(package("last")))
        http.on("$skip=0", body: #"{"count":100,"value":["# + full.joined(separator: ",") + "]}")
        http.on("_apis/packaging/feeds", body: list(feed("shared", id: "f-org")))

        let result = try await makeProvider(http).publishedPackages(followedRepos: [])

        #expect(result.packages.count == 101)
        #expect(result.packages.last?.name == "last")
        #expect(!urls(http).contains { $0.contains("$skip=200") })
    }

    @Test(arguments: [
        ("Npm", PublishedPackageType.npm), ("NuGet", .nuGet), ("Maven", .maven), ("PyPi", .pyPI), ("Python", .pyPI),
        ("Cargo", .cargo), ("UPack", .universal), ("Universal", .universal), ("Swift", PublishedPackageType(rawValue: "swift")),
    ])
    func `Maps the protocol type`(protocolType: String, expected: PublishedPackageType) {
        #expect(AzureDevOpsProvider.packageType(protocolType: protocolType) == expected)
    }

    @Test(arguments: [
        (PublishedPackageType.npm, "npm" as String?), (.nuGet, "NuGet"), (.maven, "Maven"), (.pyPI, "PyPI"), (.cargo, "crates.io"),
        (.universal, nil),
    ])
    func `Azure types name the ecosystem of the dependency check`(type: PublishedPackageType, ecosystem: String?) {
        #expect(type.dependencyEcosystem == ecosystem)
    }

    // MARK: - Pre-releases (#219)

    let versionsPath = "Feeds/f-org/Packages/0b4d1e5f-0000-4000-8000-000000000002/versions"

    func version(_ version: String, latest: Bool = false, deleted: Bool = false, upstream: Bool = false, published: String) -> String {
        let upstreamField = upstream ? #""directUpstreamSourceId":"b3a6c0de-0000-4000-8000-000000000009","# : ""
        return #"""
        {"id":"9c1e0000-0000-4000-8000-0000000000\#(version.count)","normalizedVersion":"\#(version)","version":"\#(version)",
         "isLatest":\#(latest),"isListed":true,"isDeleted":\#(deleted),\#(upstreamField)"publishDate":"\#(published)"}
        """#
    }

    @Test func `A pre-release marked isLatest leaves the highest stable release as the latest version`() async throws {
        let http = MockHTTPClient()
        http.on(versionsPath, body: list(
            version("2.4.0-beta1", latest: true, published: "2026-10-30T10:00:00Z"),
            version("2.3.5", deleted: true, published: "2026-10-20T10:00:00Z"),
            version("3.0.0", upstream: true, published: "2026-10-25T10:00:00Z"),
            version("2.3.0", published: "2026-10-01T10:00:00Z"),
            version("2.2.0", published: "2026-09-01T10:00:00Z")
        ))
        http.on("Feeds/f-org/packages", body: list(package("@acme/ui", version: "2.4.0-beta1", published: "2026-10-30T10:00:00Z")))
        http.on("_apis/packaging/feeds", body: list(feed("shared", id: "f-org")))

        let ui = try #require(try await makeProvider(http).publishedPackages(followedRepos: []).packages.first)

        #expect(ui.releasedVersion == "2.3.0", "de hoogste stabiele release, niet de pre-release van isLatest")
        #expect(ui.newestPrerelease == "2.4.0-beta1", "de nieuwere pre-release wordt alleen genoemd")
        #expect(ui.versions.map(\.version) == ["2.4.0-beta1", "2.3.0", "2.2.0"], "zonder verwijderde versie en zonder upstream")
        #expect(ui.releasedAt == DateParsing.parse("2026-10-01T10:00:00Z"))
        #expect(ui.webURL?.absoluteString == "https://dev.azure.com/acme/_artifacts/feed/shared/Npm/@acme%2Fui/overview/2.3.0")
        #expect(!ui.versionsReadFailed)
        #expect(urls(http).contains("\(feeds)_apis/packaging/\(versionsPath)?includeUrls=false&isDeleted=false&api-version=7.1"))
    }

    /// Alleen pre-releases: dan is de hoogste pre-release de nieuwste versie, zoals bij een image
    /// zonder stabiele versietag, en er is geen nieuwere pre-release om te noemen.
    @Test func `With only pre-releases the highest pre-release is the latest version`() async throws {
        let http = MockHTTPClient()
        http.on(versionsPath, body: list(
            version("1.0.0-rc.2", latest: true, published: "2026-10-30T10:00:00Z"),
            version("1.0.0-rc.1", published: "2026-10-01T10:00:00Z")
        ))
        http.on("Feeds/f-org/packages", body: list(package("@acme/ui", version: "1.0.0-rc.2", published: "2026-10-30T10:00:00Z")))
        http.on("_apis/packaging/feeds", body: list(feed("shared", id: "f-org")))

        let ui = try #require(try await makeProvider(http).publishedPackages(followedRepos: []).packages.first)

        #expect(ui.releasedVersion == "1.0.0-rc.2")
        #expect(ui.newestPrerelease == nil)
        #expect(ui.versions.map(\.version) == ["1.0.0-rc.2", "1.0.0-rc.1"])
        #expect(ui.webURL?.absoluteString == "https://dev.azure.com/acme/_artifacts/feed/shared/Npm/@acme%2Fui/overview/1.0.0-rc.2")
    }

    @Test func `A stable isLatest needs no further request`() async throws {
        let http = MockHTTPClient()
        http.on("Feeds/f-org/packages", body: list(package("@acme/ui", version: "2.3.0")))
        http.on("_apis/packaging/feeds", body: list(feed("shared", id: "f-org")))

        let ui = try #require(try await makeProvider(http).publishedPackages(followedRepos: []).packages.first)

        #expect(ui.releasedVersion == "2.3.0")
        #expect(ui.newestPrerelease == nil)
        #expect(ui.versions.map(\.version) == ["2.3.0"])
        #expect(!urls(http).contains { $0.contains("/versions") })
    }

    @Test func `The stable release stays behind many newer pre-releases`() async throws {
        let http = MockHTTPClient()
        let betas = (1...12).reversed().map { version("3.0.0-beta.\($0)", latest: $0 == 12, published: "2026-10-\(10 + $0)T10:00:00Z") }
        http.on(versionsPath, body: list(betas + [version("2.9.0", published: "2026-09-01T10:00:00Z")]))
        http.on("Feeds/f-org/packages", body: list(package("@acme/ui", version: "3.0.0-beta.12")))
        http.on("_apis/packaging/feeds", body: list(feed("shared", id: "f-org")))

        let ui = try #require(try await makeProvider(http).publishedPackages(followedRepos: []).packages.first)

        #expect(ui.versions.count == PublishedPackage.recentVersionLimit)
        #expect(ui.versions.last?.version == "2.9.0")
        #expect(ui.releasedVersion == "2.9.0")
        #expect(ui.newestPrerelease == "3.0.0-beta.12")
    }

    @Test func `Versions that cannot be read mark the package as read failed`() async throws {
        let http = MockHTTPClient()
        http.on(versionsPath, status: 500, body: #"{"message":"Internal error"}"#)
        http.on("Feeds/f-org/packages", body: list(package("@acme/ui", version: "2.4.0-beta1")))
        http.on("_apis/packaging/feeds", body: list(feed("shared", id: "f-org")))

        let ui = try #require(try await makeProvider(http).publishedPackages(followedRepos: []).packages.first)

        #expect(ui.versionsReadFailed, "geen stabiele versie bekend, dus geen bron van een nieuwste versie (#215)")
        #expect(ui.versions.map(\.version) == ["2.4.0-beta1"])
    }

    // MARK: - Rechten en lege registers

    @Test(arguments: [(401, AuthMethod.pat), (403, .pat), (401, .cli), (403, .cli)])
    func `A missing Packaging permission becomes needsPermission`(status: Int, auth: AuthMethod) async throws {
        let http = MockHTTPClient()
        http.on("_apis/packaging/feeds", status: status, body: #"{"message":"TF400813: The user is not authorized to access this resource."}"#)

        let result = try await makeProvider(http, auth: auth).publishedPackages(followedRepos: ["Web/site"])

        #expect(result == .needsPermission(reason: PackagesPermission.azurePackagingRead(for: auth)))
    }

    @Test func `A forbidden feed makes the account need permission`() async throws {
        let http = MockHTTPClient()
        http.on("Feeds/f-org/packages", status: 403, body: "{}")
        http.on("_apis/packaging/feeds", body: list(feed("shared", id: "f-org")))

        let result = try await makeProvider(http).publishedPackages(followedRepos: [])

        #expect(result == .needsPermission(reason: PackagesPermission.azurePackagingRead(for: .pat)))
        #expect(PackagesPermission.azurePackagingRead(for: .pat).contains("Packaging (Read)"))
    }

    @Test func `An organization without Azure Artifacts has no packages`() async throws {
        let http = MockHTTPClient()
        http.on("_apis/packaging/feeds", status: 404, body: #"{"message":"Not found"}"#)

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["Web/site"])

        #expect(result == .packages([]))
    }

    @Test func `A rate limit stays an error`() async throws {
        let http = MockHTTPClient()
        http.on("_apis/packaging/feeds", status: 429, headers: ["Retry-After": "30"], body: "")

        await #expect(throws: ProviderError.self) {
            try await makeProvider(http).publishedPackages(followedRepos: [])
        }
    }
}

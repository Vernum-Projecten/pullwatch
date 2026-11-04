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

import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Provider met de bestanden van één repo en een eigen register.
private actor RegistryProvider: PRProvider {
    let files: [String: String]
    let published: PublishedPackages

    init(files: [String: String], published: PublishedPackages) {
        self.files = files
        self.published = published
    }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] { ["acme/web"] }
    func openPullRequests() async throws -> [PullRequest] { [] }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch { TagFetch(tags: []) }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { files.keys.sorted() }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        guard let content = files[path] else { throw ProviderError.server(status: 404) }
        return content
    }
    func invalidateCredentials() async {}
    func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages { published }
}

/// Een eigen package zonder bekende nieuwste versie is nooit `.checked` (#215): de vorige versie
/// blijft, of de sleutel is deze check publiek, en een naam die alleen het eigen register kent gaat
/// nergens heen en staat als "niet gecontroleerd".
@Suite struct VersionCheckerInHouseVersionTests {
    static let account = Account(kind: .gitLab, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs, "acme/lib": .prs])
    static let key = "npm:acme-billing"
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    /// Een repo die `name` 1.4.0 uit `registry` installeert (het eigen register van GitLab, of npmjs.com).
    static func files(name: String = "acme-billing", registry: String? = nil) -> [String: String] {
        let resolved = registry ?? "https://gitlab.com/api/v4/projects/42/packages/npm/\(name)/-/\(name)-1.4.0.tgz"
        return [
            "package.json": #"{"name":"web","dependencies":{"\#(name)":"^1.4.0"}}"#,
            "package-lock.json": #"""
            {"name":"web","lockfileVersion":3,"requires":true,"packages":{
              "":{"name":"web","dependencies":{"\#(name)":"^1.4.0"}},
              "node_modules/\#(name)":{"version":"1.4.0","resolved":"\#(resolved)","integrity":"sha512-abc=="}
            }}
            """#,
        ]
    }

    /// Wat het register noemt: het package zonder versies (geen repository) of met een mislukte read.
    enum Unversioned: String, CaseIterable, Sendable {
        case noRepository, readFailed
    }

    static func published(_ kind: Unversioned, name: String = "acme-billing") -> PublishedPackage {
        switch kind {
        case .noRepository:
            PublishedPackage(accountId: account.id, name: name, type: .npm, owner: "acme", repository: nil)
        case .readFailed:
            PublishedPackage(accountId: account.id, name: name, type: .npm, owner: "acme", repository: "acme/lib", versionsReadFailed: true)
        }
    }

    /// OSV kent een kwetsbaarheid in `name` 1.4.0; npmjs.com kent `name` op 1.3.0.
    static func http(name: String = "acme-billing") -> MockHTTPClient {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GHSA-pub"}]}]}"#)
        http.on("vulns/GHSA-pub", body: #"""
        {"id":"GHSA-pub","summary":"Public CVE","database_specific":{"severity":"HIGH"},
         "affected":[{"package":{"name":"\#(name)","ecosystem":"npm"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"1.4.1"}]}]}]}
        """#)
        http.on("registry.npmjs.org/\(name)", body: #"{"dist-tags":{"latest":"1.3.0"},"versions":{"1.3.0":{},"1.4.0":{}}}"#)
        return http
    }

    func run(files: [String: String], published: [PublishedPackage], http: MockHTTPClient, cache: [String: PackageMetadata] = [:]) async -> VersionReport {
        let provider = RegistryProvider(files: files, published: .packages(published))
        return await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, metadataCache: cache, accounts: [Self.account]
        ).run(accounts: [Self.account])
    }

    func vulnerabilities(_ report: VersionReport) throws -> [String] {
        try #require(report.repos.first { $0.repo == "acme/web" }).vulnerabilities.map(\.id)
    }

    /// Geen verzoek, ook niet in de body (OSV), noemt de eigen naam.
    func expectNoRequest(for name: String, in http: MockHTTPClient) {
        for request in http.requests {
            let text = (request.url?.absoluteString ?? "") + String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(!text.contains(name), "verzoek met \(name): \(request.url?.absoluteString ?? "")")
        }
    }

    // MARK: - Alleen het eigen register kent de naam

    @Test(arguments: Unversioned.allCases)
    func `A private-only name without a version is not checked and reaches no request`(_ kind: Unversioned) async throws {
        let http = Self.http()
        let report = await run(files: Self.files(), published: [Self.published(kind)], http: http)

        let metadata = try #require(report.packageMetadata[Self.key])
        let inHouse = try #require(metadata.inHouse)
        #expect(inHouse.status == .readFailed)
        #expect(!inHouse.isChecked)
        #expect(metadata.latest == nil)
        #expect(report.latestPackages[Self.key]?.version == nil)
        #expect(try vulnerabilities(report).isEmpty)
        expectNoRequest(for: "acme-billing", in: http)
    }

    @Test func `A failed read keeps the version of the previous check`() async throws {
        let http = Self.http()
        let before = PublishedPackage(
            accountId: Self.account.id, name: "acme-billing", type: .npm, owner: "acme", repository: "acme/lib",
            versions: [PublishedVersion(version: "1.5.0")]
        )
        let cache = [Self.key: try #require(VersionChecker.metadata(of: before, repositoryURL: nil))]

        let report = await run(files: Self.files(), published: [Self.published(.readFailed)], http: http, cache: cache)

        #expect(report.packageMetadata[Self.key]?.inHouse?.status == .checked)
        #expect(report.latestPackages[Self.key]?.version == "1.5.0")
        expectNoRequest(for: "acme-billing", in: http)
    }

    @Test func `A previous check without a version is not kept`() async throws {
        let http = Self.http()
        let earlier = InHousePackage(accountId: Self.account.id, name: "acme-billing", type: .npm, owner: "acme", repository: "acme/lib")
        let cache = [Self.key: PackageMetadata(latest: nil, versions: [:], inHouse: earlier)]

        let report = await run(files: Self.files(), published: [Self.published(.readFailed)], http: http, cache: cache)

        #expect(report.packageMetadata[Self.key]?.inHouse?.status == .readFailed)
        expectNoRequest(for: "acme-billing", in: http)
    }

    // MARK: - Het publieke register kent de naam

    @Test(arguments: Unversioned.allCases)
    func `A name the public registry knows is public for this check`(_ kind: Unversioned) async throws {
        let name = "left-pad"
        let http = Self.http(name: name)
        let cache = ["npm:\(name)": PackageMetadata(latest: "1.3.0", versions: ["1.3.0": VersionMetadata()])]

        let report = await run(
            files: Self.files(name: name), published: [Self.published(kind, name: name)], http: http, cache: cache
        )

        #expect(report.packageMetadata["npm:\(name)"]?.inHouse == nil)
        #expect(report.latestPackages["npm:\(name)"]?.version == "1.3.0")
        #expect(try vulnerabilities(report) == ["GHSA-pub"])
    }

    @Test func `A namesake without a version still gives the hint`() async throws {
        let name = "left-pad"
        let http = Self.http(name: name)

        let report = await run(
            files: Self.files(name: name, registry: "https://registry.npmjs.org/\(name)/-/\(name)-1.4.0.tgz"),
            published: [Self.published(.readFailed, name: name)], http: http
        )

        #expect(report.packageMetadata["npm:\(name)"]?.inHouse == nil)
        #expect(report.packageMetadata["npm:\(name)"]?.alsoPublishedBy?.source == "acme/lib")
        #expect(try vulnerabilities(report) == ["GHSA-pub"])
    }

    // MARK: - Opslaan

    @Test func `The read failure survives the stored report`() throws {
        let inHouse = InHousePackage(accountId: Self.account.id, name: "acme-billing", type: .npm, owner: "acme", repository: nil, status: .readFailed)
        let package = Self.published(.readFailed)

        let decodedInHouse = try JSONDecoder().decode(InHousePackage.self, from: JSONEncoder().encode(inHouse))
        let decodedPackage = try JSONDecoder().decode(PublishedPackage.self, from: JSONEncoder().encode(package))

        #expect(decodedInHouse.status == .readFailed)
        #expect(decodedPackage.versionsReadFailed)
        #expect(try JSONDecoder().decode(PublishedPackage.self, from: JSONEncoder().encode(Self.published(.noRepository))).versionsReadFailed == false)
    }
}

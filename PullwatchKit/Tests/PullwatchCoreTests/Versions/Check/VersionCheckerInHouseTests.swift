import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Provider met bestanden en een eigen register.
private actor InHouseProvider: PRProvider {
    let repos: [String]
    let files: [String: [String: String]]
    let published: PublishedPackages

    init(repos: [String], files: [String: [String: String]], published: PublishedPackages) {
        self.repos = repos
        self.files = files
        self.published = published
    }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] { repos }
    func openPullRequests() async throws -> [PullRequest] { [] }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch { TagFetch(tags: []) }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { Array((files[repo] ?? [:]).keys).sorted() }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String {
        guard let content = files[repo]?[path] else { throw ProviderError.server(status: 404) }
        return content
    }
    func invalidateCredentials() async {}
    func publishedPackages(followedRepos: [String]) async throws -> PublishedPackages { published }
}

/// Een dependency die een gevolgde repo zelf publiceert, krijgt zijn nieuwste versie uit het eigen
/// register; het publieke register en OSV horen de naam nooit.
@Suite struct VersionCheckerInHouseTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    let account = Account(kind: .gitHub, organization: "acme", authMethod: .pat, repoWatch: ["acme/web": .prs, "acme/ui": .prs])

    /// acme/web vraagt het eigen @acme/ui en het publieke lodash.
    func files(ui requested: String = "^2.1.0", other: String = "@acme/ui") -> [String: [String: String]] {
        let manifest = #"{"name":"web","dependencies":{"\#(other)":"\#(requested)","lodash":"^4.17.20"}}"#
        let lock = #"{"lockfileVersion":3,"packages":{"":{"name":"web","dependencies":{"\#(other)":"\#(requested)","lodash":"^4.17.20"}},"#
            + #""node_modules/\#(other)":{"version":"2.1.0"},"node_modules/lodash":{"version":"4.17.20"}}}"#
        return ["acme/web": ["package.json": manifest, "package-lock.json": lock]]
    }

    /// Wat acme/ui in GitHub Packages publiceert: GitHub noemt een npm-package zonder scope.
    func published(_ versions: [String] = ["2.3.0", "2.2.0", "2.1.0"]) -> PublishedPackages {
        .packages([PublishedPackage(
            accountId: account.id, name: "ui", type: .npm, owner: "acme", repository: "acme/ui",
            webURL: URL(string: "https://github.com/orgs/acme/packages/npm/package/ui"),
            versions: versions.map { PublishedVersion(version: $0) }
        )])
    }

    func http() -> MockHTTPClient {
        let http = MockHTTPClient()
        http.on("registry.npmjs.org/lodash", body: #"{"dist-tags":{"latest":"4.17.21"},"versions":{"4.17.20":{},"4.17.21":{}}}"#)
        http.on("registry.npmjs.org", status: 404, body: "{}")
        http.on("querybatch", body: #"{"results":[{}]}"#)
        return http
    }

    /// Geen verzoek, ook niet in de body (OSV), noemt de eigen naam.
    func expectNoRequest(for name: String, in http: MockHTTPClient) {
        for request in http.requests {
            let text = (request.url?.absoluteString ?? "") + String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(!text.contains(name), "verzoek met \(name): \(request.url?.absoluteString ?? "")")
            #expect(!text.contains(name.replacingOccurrences(of: "/", with: "%2F")))
        }
    }

    func run(
        files: [String: [String: String]], published: PublishedPackages, http: MockHTTPClient,
        cache: [String: PackageMetadata] = [:], disabled: Set<DataSourceID> = []
    ) async -> VersionReport {
        let provider = InHouseProvider(repos: ["acme/web", "acme/ui"], files: files, published: published)
        return await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, metadataCache: cache, disabledSources: disabled,
            accounts: [account]
        ).run(accounts: [account])
    }

    func update(_ report: VersionReport, _ key: String = "npm:@acme/ui") throws -> PackageUpdate {
        let repo = try #require(report.repos.first { $0.repo == "acme/web" })
        let use = try #require(repo.packages.first { $0.key == key })
        return try #require(use.update(latest: report.latestPackages[key]?.version, context: report.updateContext(for: repo)))
    }

    // MARK: - Uit het eigen register

    @Test func `An in-house package takes its latest version from the published package`() async throws {
        let http = http()
        let report = await run(files: files(), published: published(), http: http)

        #expect(report.latestPackages["npm:@acme/ui"]?.version == "2.3.0")
        let inHouse = try #require(report.packageMetadata["npm:@acme/ui"]?.inHouse)
        #expect(inHouse.repository == "acme/ui")
        #expect(inHouse.repositoryURL == URL(string: "https://github.com/acme/ui"))
        #expect(inHouse.registryURL == URL(string: "https://github.com/orgs/acme/packages/npm/package/ui"))
        #expect(inHouse.status == .checked)
        #expect(try update(report).status == .withinRange)
        // lodash gaat nog gewoon naar npmjs.com.
        #expect(report.latestPackages["npm:lodash"]?.version == "4.17.21")
        #expect(report.packageMetadata["npm:lodash"]?.inHouse == nil)
    }

    @Test func `The public registry and OSV never see an in-house name`() async {
        let http = http()
        _ = await run(files: files(), published: published(), http: http)

        expectNoRequest(for: "@acme/ui", in: http)
        #expect(http.requests.contains { $0.url?.absoluteString.contains("registry.npmjs.org/lodash") == true })
    }

    @Test(arguments: [
        ("^2.1.0", ["2.3.0", "2.1.0"], PackageUpdate.Status.withinRange),
        ("~2.1.0", ["2.3.0", "2.1.0"], .needsManifestChange),
        ("^2.1.0", ["2.1.0"], .upToDate),
        ("^2.1.0", ["3.0.0-beta.1", "2.1.0"], .upToDate),
    ])
    func `Update status comes from the published versions`(requested: String, versions: [String], expected: PackageUpdate.Status) async throws {
        let report = await run(files: files(ui: requested), published: published(versions), http: http())

        #expect(try update(report).status == expected)
    }

    @Test func `A parent's range blocks an in-house package like any other`() throws {
        let package = PublishedPackage(
            accountId: account.id, name: "@acme/ui", type: .npm, owner: "acme", repository: "acme/ui",
            versions: [PublishedVersion(version: "2.0.0"), PublishedVersion(version: "1.4.0")]
        )
        let metadata = VersionChecker.metadata(of: package, repositoryURL: nil)
        let install = PackageInstall(version: "1.4.0", workspace: "", scope: .transitive, via: ["@acme/app"], source: "package-lock.json", requested: "^1.0.0")
        let repo = RepoVersions(
            accountId: account.id, repo: "acme/web", components: [],
            otherPackages: [PackageUse(ecosystem: "npm", name: "@acme/ui", installs: [install])]
        )

        let update = install.update(
            ecosystem: "npm", name: "@acme/ui", latest: metadata.latest,
            context: UpdateContext(repo: repo, metadata: ["npm:@acme/ui": metadata])
        )

        #expect(metadata.latest == "2.0.0")
        #expect(update.status == .blockedByPackage(parent: "@acme/app", parentRange: "^1.0.0", minimumParentVersion: nil))
    }

    // MARK: - Bron uit, geen recht

    var cachedInHouse: [String: PackageMetadata] {
        let package = PublishedPackage(
            accountId: account.id, name: "ui", type: .npm, owner: "acme", repository: "acme/ui", versions: [PublishedVersion(version: "2.3.0")]
        )
        return ["npm:@acme/ui": VersionChecker.metadata(of: package, repositoryURL: URL(string: "https://github.com/acme/ui"))]
    }

    @Test func `With the source off an in-house package is not checked and never up to date`() async throws {
        let http = http()
        let report = await run(files: files(), published: published(), http: http, cache: cachedInHouse, disabled: [.packageRegistries])

        #expect(report.latestPackages["npm:@acme/ui"]?.version == nil)
        #expect(report.packageMetadata["npm:@acme/ui"]?.inHouse?.status == .sourceOff)
        #expect(try update(report).status == .unknown)
        let repo = try #require(report.repos.first { $0.repo == "acme/web" })
        #expect(repo.isUnchecked(.packageRegistries))
        let summary = try #require(report.packageSummaries().first { $0.id == "npm:@acme/ui" })
        #expect(summary.state == .unchecked)
        #expect(summary.inHouse?.status == .sourceOff)
        expectNoRequest(for: "@acme/ui", in: http)
    }

    @Test func `Without permission an in-house package says so and stays private`() async throws {
        let http = http()
        let report = await run(
            files: files(), published: .needsPermission(reason: "read:packages ontbreekt"), http: http, cache: cachedInHouse
        )

        #expect(report.latestPackages["npm:@acme/ui"]?.version == nil)
        #expect(report.packageMetadata["npm:@acme/ui"]?.inHouse?.status == .needsPermission(reason: "read:packages ontbreekt"))
        #expect(try update(report).status == .unknown)
        expectNoRequest(for: "@acme/ui", in: http)
    }

    @Test func `A failing registry keeps the in-house versions of the last check`() async throws {
        let http = http()
        let report = await run(files: files(), published: .failed(message: "offline"), http: http, cache: cachedInHouse)

        #expect(report.latestPackages["npm:@acme/ui"]?.version == "2.3.0")
        #expect(report.packageMetadata["npm:@acme/ui"]?.inHouse?.status == .checked)
        expectNoRequest(for: "@acme/ui", in: http)
    }

    @Test func `A private name that no followed repository publishes is checked as before`() async throws {
        let http = http()
        let report = await run(files: files(other: "@other/thing"), published: published(), http: http)

        #expect(report.packageMetadata["npm:@other/thing"]?.inHouse == nil)
        #expect(report.latestPackages["npm:@other/thing"]?.version == nil)
        #expect(http.requests.contains { $0.url?.absoluteString.contains("registry.npmjs.org/@other%2Fthing") == true })
        #expect(try update(report, "npm:@other/thing").unknownReason == .noLatestVersion)
    }

    @Test func `Checking one repository again uses the packages of the last check`() async throws {
        let http = http()
        let provider = InHouseProvider(repos: ["acme/web"], files: files(), published: .notSupported)
        let previous = [AccountPackages(accountId: account.id, result: published(), checkedAt: now)]

        let checked = await VersionChecker(
            makeProvider: { _ in provider }, http: http, now: { now }, publishedPackages: previous, accounts: [account]
        ).run(account: account, repo: "acme/web")

        #expect(checked.latest["npm:@acme/ui"]?.version == "2.3.0")
        #expect(checked.metadata["npm:@acme/ui"]?.inHouse?.repository == "acme/ui")
        expectNoRequest(for: "@acme/ui", in: http)
    }

    // MARK: - Tonen met een bron uit

    @Test func `Turning the source off after a check hides the in-house versions`() async throws {
        let report = await run(files: files(), published: published(), http: http())

        let shown = report.visible(disabled: [.packageRegistries], accountKinds: [account.id: .gitHub])

        #expect(shown.latestPackages["npm:@acme/ui"] == nil)
        #expect(shown.packageMetadata["npm:@acme/ui"]?.inHouse?.status == .sourceOff)
        #expect(shown.repos.first { $0.repo == "acme/web" }?.isUnchecked(.packageRegistries) == true)
        #expect(shown.packageSummaries().first { $0.id == "npm:@acme/ui" }?.state == .unchecked)
    }

    @Test func `Turning npm off leaves the in-house versions alone`() async throws {
        let report = await run(files: files(), published: published(), http: http())

        let shown = report.visible(disabled: [.npm], accountKinds: [account.id: .gitHub])

        #expect(shown.latestPackages["npm:@acme/ui"]?.version == "2.3.0")
        #expect(shown.latestPackages["npm:lodash"] == nil)
        #expect(shown.packageMetadata["npm:@acme/ui"]?.inHouse?.status == .checked)
    }
}

import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Provider met vaste bestanden en beveiligingsgegevens, die telt hoe vaak `securityAlerts` gevraagd wordt.
private actor CountingSecurityProvider: PRProvider {
    let files: [String: [String: String]]
    let scan: SecurityScan?
    private(set) var securityCalls = 0

    init(files: [String: [String: String]], scan: SecurityScan? = SecurityScan(feeds: [], alerts: [], advisories: [])) {
        self.files = files
        self.scan = scan
    }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] { files.keys.sorted() }
    func openPullRequests() async throws -> [PullRequest] { [] }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch { TagFetch(tags: []) }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { (files[repo] ?? [:]).keys.sorted() }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String { files[repo]?[path] ?? "" }
    func invalidateCredentials() async {}
    func securityAlerts(in repo: String) async throws -> SecurityScan? {
        securityCalls += 1
        return scan
    }
}

@Suite struct DataSourceCheckTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    static let gomod = "go 1.26\nrequire x.com/y v1.0.0\n"

    func account(_ kind: ProviderKind = .gitHub, repos: [String] = ["acme/a"], instanceURL: URL? = nil) -> Account {
        Account(
            kind: kind, organization: "acme", authMethod: .pat,
            repoWatch: Dictionary(uniqueKeysWithValues: repos.map { ($0, .prs) }), instanceURL: instanceURL
        )
    }

    func checker(_ provider: any PRProvider, http: MockHTTPClient, disabled: Set<DataSourceID>) -> VersionChecker {
        VersionChecker(makeProvider: { _ in provider }, http: http, now: { now }, disabledSources: disabled)
    }

    func osvCalls(_ http: MockHTTPClient) -> Int {
        http.requests.filter { $0.url?.host == "api.osv.dev" }.count
    }

    @Test func osvOffMakesNoOSVRequests() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GHSA-1"}]}]}"#)
        let provider = CountingSecurityProvider(files: ["acme/a": ["go.mod": Self.gomod]])

        let report = await checker(provider, http: http, disabled: [.osv]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(!http.requests.contains { $0.url?.host == "api.osv.dev" })
        #expect(repo.isUnchecked(.osv))
        #expect(repo.vulnerabilities.isEmpty)
        #expect(repo.vulnerabilityError == nil)
    }

    @Test func osvOffWithoutDependenciesSkipsNothing() async throws {
        let http = MockHTTPClient()
        let provider = CountingSecurityProvider(files: ["acme/a": ["README.md": "hallo"]])

        let report = await checker(provider, http: http, disabled: [.osv]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(repo.skippedSources.isEmpty)
        #expect(!repo.isUnchecked(.osv))
    }

    @Test func osvOnSkipsNothing() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{}]}"#)
        let provider = CountingSecurityProvider(files: ["acme/a": ["go.mod": Self.gomod]])

        let report = await checker(provider, http: http, disabled: []).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(repo.skippedSources.isEmpty)
        #expect(osvCalls(http) == 1, "met OSV aan gaat de batch wel de deur uit")
    }

    @Test func osvOffMarksTheReleaseToo() async throws {
        let http = MockHTTPClient()
        let provider = FileProvider(
            repos: ["acme/a"], files: ["acme/a": ["go.mod": Self.gomod], "acme/a@v1.0.0": ["go.mod": Self.gomod]],
            tags: ["acme/a": ["v1.0.0"]]
        )

        let report = await checker(provider, http: http, disabled: [.osv]).run(accounts: [account()])

        let release = try #require(report.repos.first?.release)
        #expect(release.skippedSources == [.osv])
        #expect(release.vulnerabilities.isEmpty)
        #expect(osvCalls(http) == 0)
    }

    @Test func singleRepoRunSkipsDisabled() async {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{"vulns":[{"id":"GHSA-1"}]}]}"#)
        let provider = CountingSecurityProvider(files: ["acme/a": ["go.mod": Self.gomod], "acme/b": ["go.mod": Self.gomod]])
        let checker = checker(provider, http: http, disabled: [.osv])
        let both = account(repos: ["acme/a", "acme/b"])

        let single = await checker.run(account: both, repo: "acme/a")
        let missing = await checker.runMissing(accounts: [both], in: VersionReport(checkedAt: now, repos: [single.repo]))

        #expect(osvCalls(http) == 0)
        #expect(single.repo.isUnchecked(.osv))
        #expect(missing.repos.map(\.repo) == ["acme/b"])
        #expect(missing.repos.first?.isUnchecked(.osv) == true)
    }

    @Test func gitHubSecurityOffSkipsAlerts() async throws {
        let provider = CountingSecurityProvider(files: ["acme/a": [:]])

        let report = await checker(provider, http: MockHTTPClient(), disabled: [.gitHubSecurity]).run(accounts: [account(.gitHub)])

        let repo = try #require(report.repos.first)
        #expect(await provider.securityCalls == 0)
        #expect(repo.security == nil)
        #expect(repo.isUnchecked(.gitHubSecurity))
    }

    @Test func gitHubSecurityOffCoversEnterprise() async throws {
        let provider = CountingSecurityProvider(files: ["acme/a": [:]])
        let enterprise = account(.gitHub, instanceURL: URL(string: "https://github.example.com"))
        #expect(enterprise.isGitHubEnterprise)

        let report = await checker(provider, http: MockHTTPClient(), disabled: [.gitHubSecurity]).run(accounts: [enterprise])

        let repo = try #require(report.repos.first)
        #expect(await provider.securityCalls == 0)
        #expect(repo.isUnchecked(.gitHubSecurity))
    }

    @Test func azureAdvancedSecurityOffSkipsAlerts() async throws {
        let provider = CountingSecurityProvider(files: ["acme/a": [:]])

        let report = await checker(provider, http: MockHTTPClient(), disabled: [.azureDevOpsAdvancedSecurity])
            .run(accounts: [account(.azureDevOps)])

        let repo = try #require(report.repos.first)
        #expect(await provider.securityCalls == 0)
        #expect(repo.security == nil)
        #expect(repo.isUnchecked(.azureDevOpsAdvancedSecurity))
        #expect(!repo.isUnchecked(.gitHubSecurity))
    }

    @Test func securityOfTheOtherServiceStillRuns() async throws {
        let provider = CountingSecurityProvider(files: ["acme/a": [:]])

        let report = await checker(provider, http: MockHTTPClient(), disabled: [.gitHubSecurity])
            .run(accounts: [account(.azureDevOps)])

        let repo = try #require(report.repos.first)
        #expect(await provider.securityCalls == 1)
        #expect(repo.security != nil)
        #expect(repo.skippedSources.isEmpty)
    }

    @Test func advisoryDatabaseOffMakesNoLookups() async {
        let http = MockHTTPClient()
        http.on("advisories/GHSA-jf85-cpcp-j695", body: AdvisoryDatabaseTests.advisoryJSON)
        let provider = CountingSecurityProvider(files: [:])
        let vulnerability = Vulnerability(
            id: "GHSA-jf85-cpcp-j695", cve: "CVE-2019-10744", summary: nil, severity: nil, ecosystem: "npm", package: "lodash",
            version: "4.17.11", fixedIn: nil, source: "package-lock.json"
        )
        let start = VersionReport(
            checkedAt: now, repos: [RepoVersions(accountId: UUID(), repo: "acme/web", components: [], vulnerabilities: [vulnerability])]
        )

        let done = await checker(provider, http: http, disabled: [.gitHubAdvisoryDatabase])
            .completingAdvisories(of: start, accounts: [account(.gitHub)])

        #expect(!http.requests.contains { $0.url?.absoluteString.contains("api.github.com/advisories") == true })
        #expect(http.requests.isEmpty)
        #expect(done == start)
    }

    @Test func osvBackOnDoesNotNotify() {
        let id = UUID()
        let vulnerability = Vulnerability(
            id: "GHSA-1", cve: nil, summary: nil, severity: nil, ecosystem: "Go", package: "x.com/y",
            version: "1.0.0", fixedIn: nil, source: "go.mod"
        )
        let previous = VersionReport(
            checkedAt: now, repos: [RepoVersions(accountId: id, repo: "acme/a", components: [], skippedSources: [.osv])]
        )
        let new = VersionReport(
            checkedAt: now, repos: [RepoVersions(accountId: id, repo: "acme/a", components: [], vulnerabilities: [vulnerability])]
        )
        let stillOff = VersionReport(
            checkedAt: now, repos: [RepoVersions(accountId: id, repo: "acme/a", components: [], skippedSources: [.osv])]
        )

        #expect(new.newVulnerabilities(since: previous).isEmpty)
        #expect(stillOff.newVulnerabilities(since: new).isEmpty)
        // Zonder overgeslagen bron meldt dezelfde vondst zich wel.
        let before = VersionReport(checkedAt: now, repos: [RepoVersions(accountId: id, repo: "acme/a", components: [])])
        #expect(new.newVulnerabilities(since: before).count == 1)
    }

    @Test func oldVersionsJSONDecodes() throws {
        let json = #"""
            {"accountId":"00000000-0000-0000-0000-000000000001","repo":"acme/a","components":[],
             "release":{"tag":"v1","components":[],"vulnerabilities":[]}}
            """#
        let repo = try JSONDecoder().decode(RepoVersions.self, from: Data(json.utf8))
        #expect(repo.skippedSources.isEmpty)
        #expect(repo.release?.skippedSources.isEmpty == true)
    }

    @Test func skippedSourcesRoundTrip() throws {
        let repo = RepoVersions(
            accountId: UUID(), repo: "acme/a", components: [],
            release: ReleaseVersions(tag: "v1", components: [], skippedSources: [.osv]),
            skippedSources: [.osv, .gitHubSecurity]
        )
        let decoded = try JSONDecoder().decode(RepoVersions.self, from: JSONEncoder().encode(repo))
        #expect(decoded == repo)
        #expect(decoded.isUnchecked(.gitHubSecurity))
    }

    // MARK: Versiebronnen

    /// left-pad direct uit npm, requests direct uit PyPI.
    static let npmLock = #"{"lockfileVersion":3,"packages":{"":{"dependencies":{"left-pad":"^1"}},"node_modules/left-pad":{"version":"1.3.0"}}}"#
    static let npmAndPyPI: [String: String] = [
        "package.json": #"{"dependencies":{"left-pad":"^1"}}"#,
        "package-lock.json": npmLock,
        "requirements.txt": "requests==2.31.0\n",
    ]
    static let goReleases = #"{"result":{"releases":[{"name":"1.26","releaseDate":"2026-02-01","isEol":false,"latest":{"name":"1.26.2"}}]}}"#
    static let swiftReleases = #"[{"name":"6.4","date":"2026-09-15","tag":"swift-6.4-RELEASE"}]"#

    func registryHTTP() -> MockHTTPClient {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{},{}]}"#)
        http.on("registry.npmjs.org/left-pad", body: #"{"name":"left-pad","dist-tags":{"latest":"1.3.0"},"versions":{"1.3.0":{"name":"left-pad","version":"1.3.0"}}}"#)
        http.on("pypi.org/pypi/requests", body: #"{"info":{"name":"requests","version":"2.32.0"},"releases":{"2.31.0":[],"2.32.0":[]}}"#)
        return http
    }

    @Test func npmOffMakesNoRegistryRequests() async throws {
        let http = registryHTTP()
        let provider = CountingSecurityProvider(files: ["acme/a": Self.npmAndPyPI])

        let report = await checker(provider, http: http, disabled: [.npm]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(repo.packages.contains { $0.key == "npm:left-pad" }, "het package zelf staat er nog wel")
        #expect(!http.requests.contains { $0.url?.host == "registry.npmjs.org" })
        #expect(repo.isUnchecked(.npm))
        #expect(report.latestPackages["npm:left-pad"] == nil)
        #expect(report.packageMetadata["npm:left-pad"] == nil)
    }

    @Test func npmOffLeavesPyPIAlone() async throws {
        let http = registryHTTP()
        let provider = CountingSecurityProvider(files: ["acme/a": Self.npmAndPyPI])

        let report = await checker(provider, http: http, disabled: [.npm]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(http.requests.contains { $0.url?.host == "pypi.org" })
        #expect(report.latestPackages["PyPI:requests"] != nil)
        #expect(!repo.isUnchecked(.pyPI))
    }

    @Test func registryOffOnlyMarksReposThatUseIt() async throws {
        let http = registryHTTP()
        let provider = CountingSecurityProvider(files: ["acme/a": ["requirements.txt": "requests==2.31.0\n"]])

        let report = await checker(provider, http: http, disabled: [.npm]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(!repo.isUnchecked(.npm), "zonder npm-packages heeft npm niets te controleren")
    }

    @Test func goProxyOffMakesNoProxyRequests() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{}]}"#)
        http.on("products/go", body: Self.goReleases)
        let provider = CountingSecurityProvider(files: ["acme/a": ["go.mod": Self.gomod]])

        let report = await checker(provider, http: http, disabled: [.goProxy]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(!http.requests.contains { $0.url?.host == "proxy.golang.org" })
        #expect(repo.isUnchecked(.goProxy))
        #expect(report.latestPackages["Go:x.com/y"] == nil)
    }

    @Test func endOfLifeOffMakesNoRequests() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{}]}"#)
        http.on("products/go", body: Self.goReleases)
        http.on("proxy.golang.org", status: 404, body: "")
        let provider = CountingSecurityProvider(files: ["acme/a": ["go.mod": Self.gomod]])

        let report = await checker(provider, http: http, disabled: [.endOfLife]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        let component = try #require(repo.components.first { $0.product == "go" })
        #expect(!http.requests.contains { $0.url?.host == "endoflife.date" })
        #expect(component.status == .unknown)
        #expect(component.latest == nil)
        #expect(repo.isUnchecked(.endOfLife))
        #expect(!repo.isUnchecked(.swiftOrg))
    }

    @Test func endOfLifeOffMarksTheReleaseToo() async throws {
        let http = MockHTTPClient()
        http.on("products/go", body: Self.goReleases)
        let provider = FileProvider(
            repos: ["acme/a"], files: ["acme/a": ["go.mod": "go 1.26\n"], "acme/a@v1.0.0": ["go.mod": "go 1.26\n"]],
            tags: ["acme/a": ["v1.0.0"]]
        )

        let report = await checker(provider, http: http, disabled: [.endOfLife]).run(accounts: [account()])

        let release = try #require(report.repos.first?.release)
        #expect(release.isUnchecked(.endOfLife))
        #expect(release.components.allSatisfy { $0.status == .unknown })
    }

    @Test func swiftOrgOffOnlySkipsSwift() async throws {
        let http = MockHTTPClient()
        http.on("querybatch", body: #"{"results":[{}]}"#)
        http.on("products/go", body: Self.goReleases)
        http.on("swift.org", body: Self.swiftReleases)
        http.on("proxy.golang.org", status: 404, body: "")
        let provider = CountingSecurityProvider(files: ["acme/a": [
            "go.mod": Self.gomod,
            "Package.swift": "// swift-tools-version: 6.4\nimport PackageDescription\n",
        ]])

        let report = await checker(provider, http: http, disabled: [.swiftOrg]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        let swift = try #require(repo.components.first { $0.product == "swift" })
        let go = try #require(repo.components.first { $0.product == "go" })
        #expect(!http.requests.contains { $0.url?.host?.hasSuffix("swift.org") == true })
        #expect(swift.status == .unknown)
        #expect(go.status == .current, "Go komt nog gewoon van endoflife.date")
        #expect(repo.isUnchecked(.swiftOrg))
        #expect(!repo.isUnchecked(.endOfLife))
    }

    @Test func releaseSourceOffWithoutThatProductSkipsNothing() async throws {
        let http = MockHTTPClient()
        http.on("products/go", body: Self.goReleases)
        let provider = CountingSecurityProvider(files: ["acme/a": ["go.mod": "go 1.26\n"]])

        let report = await checker(provider, http: http, disabled: [.swiftOrg]).run(accounts: [account()])

        let repo = try #require(report.repos.first)
        #expect(repo.skippedSources.isEmpty)
    }

    @Test func unknownSkippedSourceDecodesAndKeepsTheKnownOnes() throws {
        let json = #"""
            {"accountId":"00000000-0000-0000-0000-000000000001","repo":"acme/a","components":[],
             "skippedSources":["osv","someFutureSource","npm"],
             "release":{"tag":"v1","components":[],"vulnerabilities":[],"skippedSources":["nope","endOfLife"]}}
            """#
        let repo = try JSONDecoder().decode(RepoVersions.self, from: Data(json.utf8))
        #expect(repo.skippedSources == [.osv, .npm])
        #expect(repo.release?.skippedSources == [.endOfLife])
    }

    // MARK: Eerder opgehaalde gegevens verbergen

    static let webId = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let azureId = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    static let kinds: [UUID: ProviderKind] = [webId: .gitHub, azureId: .azureDevOps]

    static let lodashVulnerability = Vulnerability(
        id: "GHSA-jf85-cpcp-j695", cve: "CVE-2019-10744", summary: nil, severity: nil, ecosystem: "npm", package: "lodash",
        version: "4.17.11", fixedIn: nil, source: "package-lock.json"
    )

    /// Een rapport van een check waarin alles aan stond: kwetsbaarheden, nieuwste versies, adviezen,
    /// beveiliging en releasegegevens, ook voor de laatste release.
    func fullReport() -> VersionReport {
        let go = ComponentVersion(
            product: "go", label: "Go", version: "1.26", latest: "1.26.2", status: .current, sources: ["go.mod"],
            cycle: "1.26", cycleLatest: "1.26.2"
        )
        let swift = ComponentVersion(
            product: "swift", label: "Swift", version: "6.4", latest: "6.4", status: .current, sources: ["Package.swift"]
        )
        let security = SecurityScan(feeds: [], alerts: [], secretCount: 0)
        let web = RepoVersions(
            accountId: Self.webId, repo: "acme/web", components: [go, swift],
            vulnerabilities: [Self.lodashVulnerability], vulnerabilityError: "CVE-check onvolledig",
            release: ReleaseVersions(tag: "v1.0.0", components: [go], vulnerabilities: [Self.lodashVulnerability]),
            packages: [
                PackageUse(ecosystem: "npm", name: "left-pad", version: "1.3.0", sources: ["package-lock.json"]),
                PackageUse(ecosystem: "PyPI", name: "requests", version: "2.32.0", sources: ["requirements.txt"]),
            ],
            otherPackages: [PackageUse(ecosystem: "npm", name: "lodash", version: "4.17.11", sources: ["package-lock.json"])],
            security: security
        )
        let azure = RepoVersions(accountId: Self.azureId, repo: "acme/api", components: [], security: security)
        let advisory = GitHubAdvisory(
            ghsaId: "GHSA-jf85-cpcp-j695", cveId: "CVE-2019-10744", summary: nil, severity: "HIGH", cvss: nil, cwes: [],
            url: GitHubAdvisory.pageURL(ghsaId: "GHSA-jf85-cpcp-j695"), fetchedAt: now
        )
        return VersionReport(
            checkedAt: now, repos: [web, azure],
            latestPackages: [
                "npm:left-pad": PackageLatest(version: "1.3.0", seenAt: now),
                "npm:lodash": PackageLatest(version: "4.17.21", seenAt: now),
                "PyPI:requests": PackageLatest(version: "2.32.0", seenAt: now),
            ],
            advisories: ["GHSA-jf85-cpcp-j695": advisory],
            packageMetadata: [
                "npm:left-pad": PackageMetadata(latest: "1.3.0", versions: ["1.3.0": VersionMetadata(dependencies: [:])]),
                "PyPI:requests": PackageMetadata(latest: "2.32.0", versions: ["2.32.0": VersionMetadata()]),
            ]
        )
    }

    func repo(_ report: VersionReport, _ name: String) throws -> RepoVersions {
        try #require(report.repos.first { $0.repo == name })
    }

    @Test func visibleWithNothingDisabledIsIdentity() {
        let report = fullReport()
        #expect(report.visible(disabled: [], accountKinds: Self.kinds) == report)
    }

    @Test func visibleHidesVulnerabilitiesWhenOSVOff() throws {
        let report = fullReport()
        #expect(try repo(report, "acme/web").vulnerabilities.isEmpty == false, "het rapport had kwetsbaarheden")

        let visible = report.visible(disabled: [.osv], accountKinds: Self.kinds)

        let web = try repo(visible, "acme/web")
        #expect(web.vulnerabilities.isEmpty)
        #expect(web.vulnerabilityError == nil, "een oude CVE-fout is net zo min actueel")
        #expect(web.isUnchecked(.osv))
        let release = try #require(web.release)
        #expect(release.vulnerabilities.isEmpty)
        #expect(release.isUnchecked(.osv))
        #expect(!(try repo(visible, "acme/api")).isUnchecked(.osv), "zonder packages had OSV niets te controleren")
    }

    @Test func visibleHidesLatestOfDisabledRegistry() throws {
        let report = fullReport()
        // left-pad 1.3.0 is de nieuwste: in het rapport staat het package als actueel.
        #expect(report.latestPackages["npm:left-pad"]?.version == "1.3.0")

        let visible = report.visible(disabled: [.npm], accountKinds: Self.kinds)

        let web = try repo(visible, "acme/web")
        #expect(visible.latestPackages["npm:left-pad"] == nil)
        #expect(visible.latestPackages["npm:lodash"] == nil, "ook een transitief package")
        #expect(visible.packageMetadata["npm:left-pad"] == nil)
        #expect(web.isUnchecked(.npm))
        #expect(web.packages.contains { $0.key == "npm:left-pad" }, "het package zelf blijft staan")
        #expect(visible.latestPackages["PyPI:requests"] != nil)
        #expect(visible.packageMetadata["PyPI:requests"] != nil)
        #expect(!web.isUnchecked(.pyPI))
        #expect(!(try repo(visible, "acme/api")).isUnchecked(.npm), "zonder npm-packages niets te controleren")
    }

    @Test func visibleHidesAdvisoryDetails() throws {
        let report = fullReport()
        #expect(!report.advisories.isEmpty)

        let visible = report.visible(disabled: [.gitHubAdvisoryDatabase], accountKinds: Self.kinds)

        #expect(visible.advisories.isEmpty)
        #expect(try repo(visible, "acme/web").vulnerabilities == [Self.lodashVulnerability], "de melding van OSV blijft")
    }

    @Test func visibleHidesSecurityOfThatServiceOnly() throws {
        let visible = fullReport().visible(disabled: [.gitHubSecurity], accountKinds: Self.kinds)

        let web = try repo(visible, "acme/web")
        let azure = try repo(visible, "acme/api")
        #expect(web.security == nil)
        #expect(web.isUnchecked(.gitHubSecurity))
        #expect(azure.security != nil)
        #expect(azure.skippedSources.isEmpty)

        let azureOff = fullReport().visible(disabled: [.azureDevOpsAdvancedSecurity], accountKinds: Self.kinds)
        #expect(try repo(azureOff, "acme/api").security == nil)
        #expect(try repo(azureOff, "acme/api").isUnchecked(.azureDevOpsAdvancedSecurity))
        #expect(try repo(azureOff, "acme/web").security != nil)
    }

    @Test func visibleHidesStatusOfDisabledReleaseSource() throws {
        let visible = fullReport().visible(disabled: [.endOfLife], accountKinds: Self.kinds)

        let web = try repo(visible, "acme/web")
        let go = try #require(web.components.first { $0.product == "go" })
        let swift = try #require(web.components.first { $0.product == "swift" })
        #expect(go.status == .unknown)
        #expect(go.latest == nil)
        #expect(go.cycleLatest == nil)
        #expect(go.version == "1.26", "de gevonden versie zelf blijft")
        #expect(swift.status == .current, "Swift komt van swift.org")
        #expect(web.isUnchecked(.endOfLife))
        #expect(!web.isUnchecked(.swiftOrg))
        let release = try #require(web.release)
        #expect(release.components.allSatisfy { $0.status == .unknown && $0.latest == nil })
        #expect(release.isUnchecked(.endOfLife))
    }

    @Test func visibleHidesRegistryDataThatReplacingKept() async throws {
        // Eerst een volledige check met npm aan, dan npm uit en één repo opnieuw.
        let http = registryHTTP()
        let provider = CountingSecurityProvider(files: ["acme/a": Self.npmAndPyPI])
        let full = await checker(provider, http: http, disabled: []).run(accounts: [account()])
        #expect(full.latestPackages["npm:left-pad"] != nil)
        let single = await checker(provider, http: http, disabled: [.npm]).run(account: account(), repo: "acme/a")
        let replaced = full.replacing(single.repo, latest: single.latest, metadata: single.metadata)
        // `replacing` voegt samen: de oude npm-gegevens staan er nog.
        #expect(replaced.latestPackages["npm:left-pad"] != nil)

        let accountId = try #require(replaced.repos.first).accountId
        let visible = replaced.visible(disabled: [.npm], accountKinds: [accountId: .gitHub])

        #expect(visible.latestPackages["npm:left-pad"] == nil)
        #expect(visible.packageMetadata["npm:left-pad"] == nil)
        #expect(visible.latestPackages["PyPI:requests"] != nil)
        #expect(try #require(visible.repos.first).isUnchecked(.npm))
    }

    /// `visible` en een nieuwe check met dezelfde bronnen uit zeggen hetzelfde.
    @Test(arguments: [
        Set<DataSourceID>([.osv]), [.npm], [.pyPI], [.endOfLife], [.swiftOrg], [.gitHubSecurity], [.osv, .npm, .endOfLife],
    ])
    func visibleAgreesWithAFreshCheck(disabled: Set<DataSourceID>) async throws {
        let http = registryHTTP()
        http.on("products/go", body: Self.goReleases)
        http.on("swift.org", body: Self.swiftReleases)
        http.on("proxy.golang.org", status: 404, body: "")
        var files = Self.npmAndPyPI
        files["go.mod"] = "go 1.26\n"
        files["Package.swift"] = "// swift-tools-version: 6.4\nimport PackageDescription\n"
        let provider = CountingSecurityProvider(files: ["acme/a": files])
        let account = account()

        let fresh = await checker(provider, http: http, disabled: disabled).run(accounts: [account])

        #expect(fresh.visible(disabled: disabled, accountKinds: [account.id: account.kind]) == fresh)
    }

    // MARK: Stap 6 met een register uit

    /// Een Go-module waarvan de metadata er al is (bv. uit een eerdere check), met nieuwste versie 1.1.0.
    func goNeeds(_ versions: [String: VersionMetadata], isComplete: Bool) -> (repos: [RepoVersions], latest: [String: PackageLatest], metadata: [String: PackageMetadata]) {
        let repo = RepoVersions(
            accountId: UUID(), repo: "acme/a",
            components: [ComponentVersion(product: "go", label: "Go", version: "1.26", latest: nil, status: .unknown, sources: ["go.mod"])],
            packages: [PackageUse(ecosystem: "Go", name: "x.com/y", version: "1.0.0", sources: ["go.mod"])]
        )
        return (
            [repo], ["Go:x.com/y": PackageLatest(version: "1.1.0", seenAt: now)],
            ["Go:x.com/y": PackageMetadata(latest: "1.1.0", versions: versions, isComplete: isComplete)]
        )
    }

    func proxyCalls(_ http: MockHTTPClient) -> [String] {
        http.requests.filter { $0.url?.host == "proxy.golang.org" }.compactMap { $0.url?.path }
    }

    @Test func completingMetadataAsksNoDetailOfADisabledRegistry() async {
        // Van 1.1.0 ontbreekt de go.mod: stap 6 zou die ophalen.
        let needs = goNeeds(["1.0.0": VersionMetadata(), "1.1.0": VersionMetadata()], isComplete: true)
        let provider = CountingSecurityProvider(files: [:])

        let on = MockHTTPClient()
        _ = await checker(provider, http: on, disabled: []).completingMetadata(
            needs.metadata, repos: needs.repos, latest: needs.latest, floors: [:], attempted: ["Go:x.com/y"], date: now
        )
        #expect(proxyCalls(on).contains { $0.hasSuffix("/@v/v1.1.0.mod") }, "met de proxy aan vraagt stap 6 de go.mod")

        let off = MockHTTPClient()
        _ = await checker(provider, http: off, disabled: [.goProxy]).completingMetadata(
            needs.metadata, repos: needs.repos, latest: needs.latest, floors: [:], attempted: ["Go:x.com/y"], date: now
        )
        #expect(proxyCalls(off).isEmpty)
    }

    @Test func completingMetadataAsksNoVersionListOfADisabledRegistry() async {
        // 1.1.0 vraagt Go 1.30 en alleen @latest is bekend: stap 6 zou de versielijst ophalen.
        let needs = goNeeds(["1.1.0": VersionMetadata(dependencies: [:], runtimes: ["go": ">= 1.30"])], isComplete: false)
        let provider = CountingSecurityProvider(files: [:])

        let on = MockHTTPClient()
        _ = await checker(provider, http: on, disabled: []).completingMetadata(
            needs.metadata, repos: needs.repos, latest: needs.latest, floors: [:], attempted: ["Go:x.com/y"], date: now
        )
        #expect(proxyCalls(on).contains { $0.hasSuffix("/@v/list") }, "met de proxy aan vraagt stap 6 de versielijst")

        let off = MockHTTPClient()
        _ = await checker(provider, http: off, disabled: [.goProxy]).completingMetadata(
            needs.metadata, repos: needs.repos, latest: needs.latest, floors: [:], attempted: ["Go:x.com/y"], date: now
        )
        #expect(proxyCalls(off).isEmpty)
    }
}

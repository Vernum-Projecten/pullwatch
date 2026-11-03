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
}

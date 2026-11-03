import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Eén repo zonder bestanden, met vaste beveiligingsgegevens en een token voor de Advisory Database.
private actor SecurityProvider: PRProvider {
    let scan: SecurityScan?
    let token: String?

    init(scan: SecurityScan?, token: String? = nil) {
        self.scan = scan
        self.token = token
    }

    func currentUserId() async throws -> String { "me" }
    func testConnection() async throws -> String { "me" }
    func listRepos() async throws -> [String] { ["acme/web"] }
    func openPullRequests() async throws -> [PullRequest] { [] }
    func pullRequests(updatedSince since: Date?, limit: Int) async throws -> [PullRequest] { [] }
    func tags(in repos: [String]) async throws -> TagFetch { TagFetch(tags: []) }
    func filePaths(in repo: String, ref: String?) async throws -> [String] { [] }
    func fileContent(in repo: String, path: String, ref: String?) async throws -> String { "" }
    func invalidateCredentials() async {}
    func securityAlerts(in repo: String) async throws -> SecurityScan? { scan }
    func advisoryDatabaseToken() async -> String? { token }
}

@Suite struct AdvisoryDatabaseTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    static let advisoryJSON = #"""
        {"ghsa_id":"GHSA-jf85-cpcp-j695","cve_id":"CVE-2019-10744","url":"https://api.github.com/advisories/GHSA-jf85-cpcp-j695",
         "html_url":"https://github.com/advisories/GHSA-jf85-cpcp-j695","summary":"Prototype Pollution in lodash","type":"reviewed",
         "severity":"critical","identifiers":[{"type":"GHSA","value":"GHSA-jf85-cpcp-j695"},{"type":"CVE","value":"CVE-2019-10744"}],
         "published_at":"2019-07-10T19:45:23Z","withdrawn_at":null,
         "vulnerabilities":[{"package":{"ecosystem":"npm","name":"lodash"},"vulnerable_version_range":"< 4.17.12","first_patched_version":"4.17.12"}],
         "cvss_severities":{"cvss_v3":{"vector_string":"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:H","score":9.1},
                            "cvss_v4":{"vector_string":null,"score":0.0}},
         "cwes":[{"cwe_id":"CWE-1321","name":"Improperly Controlled Modification of Object Prototype Attributes ('Prototype Pollution')"}]}
        """#

    @Test func decodesSeverityCVSSAndCWEs() async throws {
        let http = MockHTTPClient()
        http.on("advisories/GHSA-jf85-cpcp-j695", body: Self.advisoryJSON)

        let advisory = try #require(try await AdvisoryDatabase.advisory(ghsaId: "GHSA-jf85-cpcp-j695", http: http, token: "t", now: now))

        #expect(advisory.severity == "CRITICAL")
        #expect(advisory.cveId == "CVE-2019-10744")
        #expect(advisory.cvss?.score == 9.1, "v4 zonder score valt terug op v3")
        #expect(advisory.cvss?.vector == "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:H")
        #expect(advisory.cwes == [GitHubAdvisory.CWE(id: "CWE-1321", name: "Improperly Controlled Modification of Object Prototype Attributes ('Prototype Pollution')")])
        #expect(advisory.url.absoluteString == "https://github.com/advisories/GHSA-jf85-cpcp-j695")
        #expect(advisory.packages.isEmpty, "de globale adviezen bewaren geen packages")
        #expect(advisory.fetchedAt == now)
        let request = try #require(http.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }

    @Test func looksUpGHSAIdsAndCVEsOnceEach() async {
        let http = MockHTTPClient()
        http.on("advisories/GHSA-jf85-cpcp-j695", body: Self.advisoryJSON)
        http.on("advisories/GHSA-none", status: 404, body: #"{"message":"Not Found"}"#)
        http.on("advisories/GHSA-down", status: 500, body: "")
        http.on("cve_id=CVE-2019-10744", body: "[\(Self.advisoryJSON)]")
        http.on("cve_id=CVE-0000-0000", body: "[]")

        let lookup = await AdvisoryDatabase.lookUp(
            ghsaIds: ["GHSA-jf85-cpcp-j695", "GHSA-none", "GHSA-down"], cves: ["CVE-2019-10744", "CVE-0000-0000"],
            http: http, token: nil, now: now
        )

        #expect(lookup.advisories.map(\.ghsaId) == ["GHSA-jf85-cpcp-j695", "GHSA-jf85-cpcp-j695"])
        #expect(lookup.misses == ["CVE-0000-0000", "GHSA-none"])
        #expect(lookup.failed == 1)
        #expect(http.requests.count == 5)
        #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil }, "zonder token anoniem")
    }
}

@Suite struct AdvisoryCacheTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    let account = UUID()

    func vuln(_ id: String, cve: String? = nil, ghsa: String? = nil) -> Vulnerability {
        Vulnerability(id: id, cve: cve, ghsa: ghsa, summary: nil, severity: nil, ecosystem: "npm", package: "lodash",
                      version: "4.17.11", fixedIn: nil, source: "package-lock.json")
    }

    func advisory(_ ghsa: String, cve: String? = nil, fetchedAt: Date? = nil) -> GitHubAdvisory {
        GitHubAdvisory(ghsaId: ghsa, cveId: cve, summary: nil, severity: "HIGH", cvss: nil, cwes: [],
                       url: GitHubAdvisory.pageURL(ghsaId: ghsa), fetchedAt: fetchedAt ?? now)
    }

    func report(_ vulns: [Vulnerability], advisories: [GitHubAdvisory] = [], misses: [String: Date] = [:]) -> VersionReport {
        VersionReport(
            checkedAt: now, repos: [RepoVersions(accountId: account, repo: "acme/web", components: [], vulnerabilities: vulns)],
            advisories: Dictionary(uniqueKeysWithValues: advisories.map { ($0.ghsaId, $0) }), advisoryMisses: misses
        )
    }

    @Test func ghsaComesFromTheIdOrAnAlias() {
        #expect(vuln("GHSA-1").ghsa == "GHSA-1")
        #expect(vuln("GO-2024-1").ghsa == nil)
        let records = ["PYSEC-1": OSVRecord(id: "PYSEC-1", aliases: ["CVE-9", "GHSA-9"], summary: nil, severity: nil, fixed: [:])]
        let dependency = Dependency(ecosystem: "PyPI", name: "django", version: "1.0", source: "requirements.txt")
        let found = OSV.vulnerabilities(dependencies: [dependency], ids: [["PYSEC-1"]], records: records)
        #expect(found.first?.ghsa == "GHSA-9")
        #expect(found.first?.cve == "CVE-9")
    }

    @Test func matchesAnAdvisoryByGHSAThenByCVE() {
        let report = report([], advisories: [advisory("GHSA-1", cve: "CVE-1"), advisory("GHSA-2", cve: "CVE-2")])
        #expect(report.advisory(for: vuln("GHSA-1"))?.ghsaId == "GHSA-1")
        #expect(report.advisory(for: vuln("GO-1", cve: "CVE-2"))?.ghsaId == "GHSA-2")
        #expect(report.advisory(for: vuln("GO-2", cve: "CVE-3")) == nil)
    }

    @Test func asksOnlyForWhatIsMissingOrStale() {
        let old = now - GitHubAdvisory.refreshInterval - 1
        let report = report(
            [vuln("GHSA-fresh"), vuln("GHSA-stale"), vuln("GHSA-new"), vuln("GHSA-missed"), vuln("GO-1", cve: "CVE-1"),
             vuln("GO-2", cve: "CVE-known"), vuln("GO-3", cve: "CVE-missed")],
            advisories: [advisory("GHSA-fresh"), advisory("GHSA-stale", fetchedAt: old), advisory("GHSA-k", cve: "CVE-known")],
            misses: ["GHSA-missed": now - 60, "CVE-missed": now - GitHubAdvisory.missRetryInterval - 1]
        )
        let missing = report.missingAdvisoryLookups(now: now)
        #expect(missing.ghsaIds == ["GHSA-stale", "GHSA-new"])
        #expect(missing.cves == ["CVE-1", "CVE-missed"])
    }

    @Test func addingKeepsOnlyWhatTheReportStillUses() {
        let start = report([vuln("GHSA-1"), vuln("GO-1", cve: "CVE-2")], advisories: [advisory("GHSA-gone")], misses: ["CVE-old": now])
        var lookup = AdvisoryDatabase.Lookup()
        lookup.advisories = [advisory("GHSA-1"), advisory("GHSA-2", cve: "CVE-2")]
        let added = start.adding(lookup, at: now)
        #expect(Set(added.advisories.keys) == ["GHSA-1", "GHSA-2"])
        #expect(added.advisoryMisses.isEmpty)
        // Een volgende check vraagt niets meer.
        let missing = added.missingAdvisoryLookups(now: now + 3600)
        #expect(missing.ghsaIds.isEmpty && missing.cves.isEmpty)
        // Vervangen van een repo en overnemen in een nieuwe check houden de cache.
        #expect(added.replacing(added.repos[0]).advisories == added.advisories)
        let fresh = VersionReport(checkedAt: now, repos: added.repos).carryingAdvisories(from: added)
        #expect(fresh.advisories == added.advisories)
        #expect(fresh.carryingSeenDates(from: added).advisories == added.advisories)
    }

    @Test func theCheckerFetchesEachAdvisoryOnceWithTheGitHubToken() async {
        let http = MockHTTPClient()
        http.on("advisories/GHSA-jf85-cpcp-j695", body: AdvisoryDatabaseTests.advisoryJSON)
        let provider = SecurityProvider(scan: nil, token: "app-token")
        let checker = VersionChecker(makeProvider: { _ in provider }, http: http, now: { now })
        let accounts = [Account(kind: .gitHub, organization: "acme", authMethod: .gitHubApp)]
        let start = report([vuln("GHSA-jf85-cpcp-j695"), vuln("GHSA-jf85-cpcp-j695")])

        let done = await checker.completingAdvisories(of: start, accounts: accounts)
        let again = await checker.completingAdvisories(of: done, accounts: accounts)

        #expect(done.advisory(for: vuln("GHSA-jf85-cpcp-j695"))?.cvss?.score == 9.1)
        #expect(again == done)
        #expect(http.requests.count == 1, "één verzoek voor het advies, ook bij een tweede check")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer app-token")
    }

    @Test func oldVersionsJSONDecodesWithoutTheNewFields() throws {
        let json = #"""
            {"checkedAt":0,"repos":[{"accountId":"00000000-0000-0000-0000-000000000001","repo":"a/b","components":[],
              "vulnerabilities":[{"id":"GHSA-x","cve":null,"summary":null,"severity":"HIGH","ecosystem":"npm","package":"p",
                                  "version":"1","fixedIn":null,"source":"package-lock.json"}]}]}
            """#
        let report = try JSONDecoder().decode(VersionReport.self, from: Data(json.utf8))
        #expect(report.advisories.isEmpty)
        #expect(report.advisoryMisses.isEmpty)
        #expect(report.repos[0].security == nil)
        #expect(report.repos[0].vulnerabilities[0].ghsa == "GHSA-x", "zonder opgeslagen GHSA-id telt een GHSA-id als id")
    }

    @Test func aReportRoundTripsItsSecurityData() throws {
        let scan = SecurityScan(
            feeds: [SecurityFeed(kind: .codeScanning, availability: .available), SecurityFeed(kind: .secretScanning, availability: .needsPermission)],
            alerts: [SecurityAlert(source: .codeScanning, kind: .code, number: 1, title: "x", severity: "HIGH", url: URL(string: "https://x")!)],
            advisories: [advisory("GHSA-own")]
        )
        let report = VersionReport(
            checkedAt: now, repos: [RepoVersions(accountId: account, repo: "a/b", components: [], security: scan)],
            advisories: ["GHSA-1": advisory("GHSA-1")], advisoryMisses: ["CVE-1": now]
        )
        let decoded = try JSONDecoder().decode(VersionReport.self, from: JSONEncoder().encode(report))
        #expect(decoded == report)
    }
}

@Suite struct SecurityScanTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    let account = UUID()

    func alert(_ number: Int, _ severity: String?, source: SecurityAlert.Source = .codeScanning) -> SecurityAlert {
        SecurityAlert(source: source, kind: .code, number: number, title: "alert \(number)", severity: severity, url: URL(string: "https://x/\(number)")!)
    }

    func report(_ scan: SecurityScan?) -> VersionReport {
        VersionReport(checkedAt: now, repos: [RepoVersions(accountId: account, repo: "acme/web", components: [], security: scan)])
    }

    func scan(_ alerts: [SecurityAlert], code: SecurityFeed.Availability = .available) -> SecurityScan {
        SecurityScan(feeds: [SecurityFeed(kind: .codeScanning, availability: code)], alerts: alerts)
    }

    @Test func sortsWorstFirstAndCountsOnlyCriticalAndHighAsSerious() {
        let scan = scan([alert(1, "LOW"), alert(2, "CRITICAL"), alert(3, nil), alert(4, "HIGH")])
        #expect(scan.alerts.map(\.number) == [2, 4, 1, 3])
        #expect(scan.seriousAlerts.map(\.number) == [2, 4])
        #expect(scan.hasFindings)
        #expect(!SecurityScan(feeds: []).hasFindings)
    }

    @Test func notifiesOnlyNewSeriousAlertsOfAFeedThatWasReadableBefore() {
        let before = report(scan([alert(1, "HIGH")]))
        let after = report(scan([alert(1, "HIGH"), alert(2, "CRITICAL"), alert(3, "MODERATE")]))
        #expect(after.newSecurityAlerts(since: before).map(\.alert.number) == [2])
        #expect(after.newSecurityAlerts(since: nil).isEmpty, "de eerste check meldt niets")
        // Pas goedgekeurd recht of eerste keer gelezen: alles is bekend.
        #expect(after.newSecurityAlerts(since: report(scan([], code: .needsPermission))).isEmpty)
        #expect(after.newSecurityAlerts(since: report(nil)).isEmpty)
    }

    @Test func theCheckerStoresTheScanWithTheRepo() async {
        let scan = scan([alert(7, "HIGH")])
        let provider = SecurityProvider(scan: scan)
        let account = Account(kind: .gitHub, organization: "acme", authMethod: .gitHubApp, repoWatch: ["acme/web": .prs])
        let report = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(accounts: [account])
        #expect(report.repos.first?.security == scan)
        let single = await VersionChecker(makeProvider: { _ in provider }, http: MockHTTPClient(), now: { now }).run(account: account, repo: "acme/web")
        #expect(single.repo.security == scan)
    }
}

import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

@Suite struct GitHubSecurityTests {
    func makeProvider(_ http: MockHTTPClient) -> GitHubProvider {
        GitHubProvider(accountId: fixedAccountId, owner: "acme", tokenSource: StaticTokenSource(token: "ghtok"), http: http)
    }

    func codeAlert(_ number: Int, level: String? = "high", severity: String = "error") -> String {
        let levelField = level.map { #""\#($0)""# } ?? "null"
        return #"""
        {"number":\#(number),"created_at":"2026-10-01T10:00:00Z","state":"open",
         "html_url":"https://github.com/acme/web/security/code-scanning/\#(number)",
         "rule":{"id":"js/sql-injection","name":"SqlInjection","severity":"\#(severity)",
                 "security_severity_level":\#(levelField),"description":"Database query built from user-controlled sources"},
         "tool":{"name":"CodeQL","version":"2.19.0"},
         "most_recent_instance":{"ref":"refs/heads/main","state":"open",
           "location":{"path":"src/db.js","start_line":42,"end_line":42},"message":{"text":"This query depends on a user-provided value."}}}
        """#
    }

    let repoAdvisory = #"""
        [{"ghsa_id":"GHSA-aaaa-bbbb-cccc","cve_id":"CVE-2026-1111","html_url":"https://github.com/acme/web/security/advisories/GHSA-aaaa-bbbb-cccc",
          "summary":"Path traversal in upload","severity":"medium","state":"published","published_at":"2026-09-01T00:00:00Z",
          "vulnerabilities":[{"package":{"ecosystem":"npm","name":"acme-web"},"vulnerable_version_range":"< 2.1.0","patched_versions":"2.1.0"}],
          "cvss_severities":{"cvss_v3":{"vector_string":"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N","score":7.5},"cvss_v4":null},
          "cwes":[{"cwe_id":"CWE-22","name":"Improper Limitation of a Pathname to a Restricted Directory"}],"cwe_ids":["CWE-22"]}]
        """#

    @Test func readsCodeScanningSecretsAndOwnAdvisories() async throws {
        let http = MockHTTPClient()
        http.on("code-scanning/alerts", body: "[\(codeAlert(3)), \(codeAlert(4, level: nil, severity: "warning"))]")
        http.on("secret-scanning/alerts", body: #"[{"number":1},{"number":2}]"#)
        http.on("security-advisories", body: repoAdvisory)

        let scan = try #require(try await makeProvider(http).securityAlerts(in: "acme/web"))

        #expect(scan.feeds.map(\.availability) == [.available, .available, .available])
        #expect(scan.alerts.map(\.number) == [3, 4], "ernstigste eerst")
        let alert = try #require(scan.alerts.first)
        #expect(alert.severity == "HIGH")
        #expect(alert.toolSeverity == "error")
        #expect(alert.rule == "js/sql-injection")
        #expect(alert.tool == "CodeQL")
        #expect(alert.path == "src/db.js")
        #expect(alert.line == 42)
        #expect(alert.title == "Database query built from user-controlled sources")
        #expect(alert.url.absoluteString == "https://github.com/acme/web/security/code-scanning/3")
        #expect(alert.isSerious)
        #expect(scan.alerts[1].severity == nil)
        #expect(!scan.alerts[1].isSerious, "zonder beveiligingsernst telt een warning niet als ernstig")
        #expect(scan.secretCount == 2)
        let advisory = try #require(scan.advisories.first)
        #expect(advisory.ghsaId == "GHSA-aaaa-bbbb-cccc")
        #expect(advisory.severity == "MODERATE")
        #expect(advisory.cvss == GitHubAdvisory.CVSS(score: 7.5, vector: "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N"))
        #expect(advisory.cvss?.version == "3.1")
        #expect(advisory.cwes.map(\.id) == ["CWE-22"])
        #expect(advisory.packages == [.init(ecosystem: "npm", name: "acme-web", vulnerableRange: "< 2.1.0", patched: "2.1.0")])

        let urls = http.requests.compactMap(\.url?.absoluteString)
        #expect(urls.count == 3, "één verzoek per soort")
        #expect(urls.contains { $0.contains("code-scanning/alerts?state=open&per_page=100") })
        #expect(urls.contains { $0.contains("secret-scanning/alerts?state=open&hide_secret=true&per_page=100") })
        #expect(urls.contains { $0.contains("security-advisories?state=published&per_page=100") })
    }

    @Test func forbiddenByTheAppNeedsPermissionWithTheInstallationPage() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"type":"Organization"}"#)
        let noAccess = #"{"message":"Resource not accessible by integration","status":"403"}"#
        http.on("code-scanning/alerts", status: 403, body: noAccess)
        http.on("secret-scanning/alerts", status: 403, body: noAccess)
        http.on("security-advisories", status: 403, body: noAccess)

        let scan = try #require(try await makeProvider(http).securityAlerts(in: "acme/web"))

        #expect(scan.feeds.allSatisfy { $0.availability == .needsPermission })
        #expect(scan.feeds.first?.link?.absoluteString == "https://github.com/organizations/acme/settings/installations")
        #expect(scan.secretCount == nil)
        #expect(scan.alerts.isEmpty)
    }

    @Test func turnedOffOrMissingIsNotEnabled() async throws {
        let http = MockHTTPClient()
        http.on("code-scanning/alerts", status: 403, body: #"{"message":"Advanced Security must be enabled for this repository to use code scanning."}"#)
        http.on("secret-scanning/alerts", status: 404, body: #"{"message":"Secret scanning is disabled on this repository."}"#)
        http.on("security-advisories", status: 404, body: #"{"message":"Not Found"}"#)

        let scan = try #require(try await makeProvider(http).securityAlerts(in: "acme/web"))

        #expect(scan.feeds.map(\.availability) == [.notEnabled, .notEnabled, .notEnabled])
        #expect(scan.feed(.codeScanning)?.link?.absoluteString == "https://github.com/acme/web/security/code-scanning")
    }

    @Test func aRateLimitIsAFailureNotAPermission() async throws {
        let http = MockHTTPClient()
        let limited = ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1792000000"]
        http.on("code-scanning/alerts", status: 403, headers: limited, body: #"{"message":"API rate limit exceeded"}"#)
        http.on("secret-scanning/alerts", body: "[]")
        http.on("security-advisories", body: "[]")

        let scan = try #require(try await makeProvider(http).securityAlerts(in: "acme/web"))

        #expect(scan.feed(.codeScanning)?.availability == .failed)
        #expect(scan.feed(.codeScanning)?.message != nil)
        #expect(scan.secretCount == 0)
    }

    @Test func followsTheNextLinkForMorePages() async throws {
        let http = MockHTTPClient()
        let next = "https://api.github.com/repositories/1/code-scanning/alerts?state=open&per_page=100&after=Y3Vyc29y"
        http.on("after=Y3Vyc29y", body: "[\(codeAlert(2))]")
        http.on("code-scanning/alerts", headers: ["Link": #"<\#(next)>; rel="next", <https://x/last>; rel="last""#], body: "[\(codeAlert(1))]")
        http.on("secret-scanning/alerts", body: "[]")
        http.on("security-advisories", body: "[]")

        let scan = try #require(try await makeProvider(http).securityAlerts(in: "acme/web"))

        #expect(Set(scan.alerts.map(\.number)) == [1, 2])
        #expect(http.requests.filter { $0.url?.absoluteString.contains("code-scanning") == true }.count == 2)
    }

    @Test func readsTheNextLink() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!, statusCode: 200, httpVersion: nil,
            headerFields: ["Link": #"<https://api.github.com/a?before=x>; rel="prev", <https://api.github.com/a?after=y>; rel="next""#]
        )!
        #expect(GitHubProvider.nextLink(response)?.absoluteString == "https://api.github.com/a?after=y")
    }

    @Test func givesItsTokenForTheAdvisoryDatabase() async {
        #expect(await makeProvider(MockHTTPClient()).advisoryDatabaseToken() == "ghtok")
    }
}

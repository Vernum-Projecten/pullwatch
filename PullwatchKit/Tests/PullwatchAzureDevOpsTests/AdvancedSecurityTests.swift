import Foundation
import Testing
@testable import PullwatchAzureDevOps
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct AdvancedSecurityTests {
    let alerts = #"""
        {"count":3,"value":[
          {"alertId":11,"alertType":"code","severity":"high","state":"active","title":"SQL injection",
           "firstSeenDate":"2026-10-01T10:00:00.1234567Z",
           "tools":[{"name":"CodeQL","rules":[{"opaqueId":"cs/sql-injection","friendlyName":"SQL injection"}]}],
           "physicalLocations":[{"filePath":"/src/Db.cs","region":{"lineStart":17,"lineEnd":17}}]},
          {"alertId":12,"alertType":"dependency","severity":"critical","state":"active","title":"CVE-2026-2222 in Newtonsoft.Json",
           "logicalLocations":[{"fullyQualifiedName":"nuget/Newtonsoft.Json/12.0.1","kind":"component"}],
           "tools":[{"name":"DependencyScanning"}]},
          {"alertId":13,"alertType":"secret","severity":"critical","state":"active","title":"Azure Storage key","truncatedSecret":"abc***"}
        ]}
        """#

    @Test func readsActiveAlertsAndCountsSecrets() async throws {
        let http = MockHTTPClient()
        http.on("advsec.dev.azure.com", body: alerts)

        let scan = try #require(try await makeProvider(http).securityAlerts(in: "My Project/api"))

        #expect(scan.feeds == [SecurityFeed(
            kind: .advancedSecurity, availability: .available,
            link: URL(string: "https://dev.azure.com/acme/My%20Project/_git/api/alerts")!
        )])
        #expect(scan.alerts.map(\.number) == [12, 11], "ernstigste eerst")
        let dependency = scan.alerts[0]
        #expect(dependency.kind == .dependency)
        #expect(dependency.severity == "CRITICAL")
        #expect(dependency.package == "nuget/Newtonsoft.Json/12.0.1")
        let code = scan.alerts[1]
        #expect(code.kind == .code)
        #expect(code.rule == "cs/sql-injection")
        #expect(code.path == "src/Db.cs")
        #expect(code.line == 17)
        #expect(code.url.absoluteString == "https://dev.azure.com/acme/My%20Project/_git/api/alerts/11")
        #expect(scan.secretCount == 1, "een geheim wordt alleen geteld")
        #expect(!scan.alerts.contains { $0.title == "Azure Storage key" })

        let url = try #require(http.requests.first?.url?.absoluteString)
        #expect(url.hasPrefix("https://advsec.dev.azure.com/acme/My%20Project/_apis/alert/repositories/api/alerts?"))
        #expect(url.contains("criteria.states=active"))
        #expect(url.contains("top=100"))
        #expect(url.contains("api-version=7.2-preview.1"))
    }

    @Test func followsTheContinuationToken() async throws {
        let http = MockHTTPClient()
        http.on("continuationToken=next", body: #"{"value":[{"alertId":2,"alertType":"code","severity":"low","title":"b"}]}"#)
        http.on("advsec.dev.azure.com", headers: ["x-ms-continuationtoken": "next"],
                body: #"{"value":[{"alertId":1,"alertType":"code","severity":"low","title":"a"}]}"#)

        let scan = try #require(try await makeProvider(http).securityAlerts(in: "proj/api"))

        #expect(Set(scan.alerts.map(\.number)) == [1, 2])
        #expect(http.requests.count == 2)
    }

    @Test func withoutAdvancedSecurityOrPermissionNothingFails() async throws {
        let off = MockHTTPClient()
        off.on("advsec.dev.azure.com", status: 404, body: "")
        let notEnabled = try #require(try await makeProvider(off).securityAlerts(in: "proj/api"))
        #expect(notEnabled.feeds.map(\.availability) == [.notEnabled])
        #expect(notEnabled.secretCount == nil)

        let forbidden = MockHTTPClient()
        forbidden.on("advsec.dev.azure.com", status: 403, body: "")
        let needsPermission = try #require(try await makeProvider(forbidden).securityAlerts(in: "proj/api"))
        #expect(needsPermission.feeds.map(\.availability) == [.needsPermission])

        let broken = MockHTTPClient()
        broken.on("advsec.dev.azure.com", status: 500, body: "")
        let failed = try #require(try await makeProvider(broken).securityAlerts(in: "proj/api"))
        #expect(failed.feeds.map(\.availability) == [.failed])
    }
}
